import Foundation

enum AgentError: LocalizedError {
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "The \(name) command was not found. Install it, or point the app at it with its environment variable."
        }
    }
}

struct ProcessOutput {
    let status: Int32
    let stdout: String
    let stderr: String
    var combined: String { (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One headless run of the chosen agent in the project folder. Keeps the
/// process so the caller can stop it.
final class AgentRunner {
    private var process: Process?

    /// Run the backend's binary with `arguments`, the project as working
    /// directory. Throws only when the binary is missing; a non-zero exit is
    /// returned so the backend can read the message.
    func run(_ backend: AgentBackend, arguments: [String]) async throws -> ProcessOutput {
        guard let executable = backend.executable else {
            throw AgentError.missingExecutable(backend.displayName)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = Paths.project

        var env = ProcessInfo.processInfo.environment
        let extraPath = [
            NSHomeDirectory() + "/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
        env["PATH"] = env["PATH"].map { "\(extraPath):\($0)" } ?? extraPath
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        self.process = process

        // Drain both pipes off the main thread so a long answer never blocks the child.
        let outTask = Task.detached(priority: .userInitiated) {
            outPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let errTask = Task.detached(priority: .userInitiated) {
            errPipe.fileHandleForReading.readDataToEndOfFile()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        self.process = nil

        let stdout = String(data: await outTask.value, encoding: .utf8) ?? ""
        let stderr = String(data: await errTask.value, encoding: .utf8) ?? ""
        return ProcessOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    func stop() {
        process?.terminate()
    }

    var isRunning: Bool { process?.isRunning ?? false }
}
