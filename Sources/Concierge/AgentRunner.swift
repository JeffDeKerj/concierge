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
    /// `onLine` gets each line of the output as soon as it is written, for
    /// a tool that sends its answer in pieces.
    func run(_ backend: AgentBackend, arguments: [String],
             onLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcessOutput {
        guard let executable = backend.executable else {
            throw AgentError.missingExecutable(backend.displayName)
        }

        let process = Process()
        let (launched, launchArguments) = FinanceFence.wrap(backend.id, executable: executable, arguments: arguments)
        process.executableURL = launched
        process.arguments = launchArguments
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
        // Nestor's own run: the desk hook (answering sessions by voice) leaves it alone.
        env["NESTOR_RUN"] = "1"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        self.process = process

        // Drain both pipes off the main thread so a long answer never blocks the child.
        let outTask = Task.detached(priority: .userInitiated) { () -> Data in
            guard let onLine else { return outPipe.fileHandleForReading.readDataToEndOfFile() }
            var all = Data()
            var pending = Data()
            while true {
                let chunk = outPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                all.append(chunk)
                pending.append(chunk)
                while let end = pending.firstIndex(of: 0x0A) {
                    onLine(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                    pending.removeSubrange(pending.startIndex...end)
                }
            }
            if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
            return all
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

/// The owner's finance notes are for Claude only (owner, 2026-11-28). Claude
/// Code is fenced by its own permission list; Antigravity and Codex have no
/// per-folder deny that holds (tried: Antigravity's deny rules and trusted
/// folders did not stop a read), so they run inside the Mac's sandbox with
/// the finance folder walled off.
enum FinanceFence {
    static let folder = NSHomeDirectory() + "/Documents/Personal/Finance"

    /// The sandbox rules: everything as usual but reading the finance folder.
    static var profile: String {
        let path = (folder as NSString).resolvingSymlinksInPath
        return "(version 1)(allow default)(deny file-read* (subpath \"\(path)\"))"
    }

    /// What to launch for a backend. Pure, for tests.
    static func wrap(_ backendID: String, executable: URL, arguments: [String]) -> (URL, [String]) {
        guard backendID != "claude" else { return (executable, arguments) }
        return (URL(fileURLWithPath: "/usr/bin/sandbox-exec"), ["-p", profile, executable.path] + arguments)
    }
}
