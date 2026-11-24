import Foundation

enum ClaudeError: LocalizedError {
    case missingExecutable
    case failed(status: Int32, output: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The claude command was not found. Install Claude Code or set CLAUDE_ASSISTANT_CLAUDE_BIN."
        case .failed(let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "claude exited with status \(status)." + (detail.isEmpty ? "" : "\n\(detail)")
        case .cancelled:
            return "Cancelled."
        }
    }
}

struct ClaudeOutput {
    let status: Int32
    let stdout: String
    let stderr: String
    var text: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    var combined: String { (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One headless `claude -p …` run in the project folder. Keeps the process so
/// the caller can stop it.
final class ClaudeRunner {
    private var process: Process?

    /// Run `claude` with `arguments`, the project as working directory. Throws
    /// when the binary is missing; a non-zero exit is returned, not thrown, so
    /// callers can read the message.
    func run(arguments: [String]) async throws -> ClaudeOutput {
        guard let claude = ToolLookup.claude else { throw ClaudeError.missingExecutable }

        let process = Process()
        process.executableURL = claude
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
        return ClaudeOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    func stop() {
        process?.terminate()
    }

    var isRunning: Bool { process?.isRunning ?? false }
}
