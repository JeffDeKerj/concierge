import Foundation

/// Runs the job runner script when launchd starts the app with `--tick`.
///
/// launchd starts the app's own binary rather than python, so macOS treats the
/// jobs as Concierge's: the one Full Disk Access grant to Concierge then covers
/// the WhatsApp database for scheduled jobs and for the question box alike.
enum TickLauncher {
    static let flag = "--tick"

    /// Runs one tick and returns its exit status.
    static func run() -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", Paths.project.appendingPathComponent("Scripts/tick.py").path]
        var env = ProcessInfo.processInfo.environment
        // launchd's PATH has no Homebrew, where `uv` (the WhatsApp server) lives.
        let extra = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = env["PATH"].map { "\(extra):\($0)" } ?? "\(extra):/usr/bin:/bin:/usr/sbin:/sbin"
        env["CONCIERGE_DIR"] = Paths.project.path
        // tick.py speaks through `<this binary> --say`.
        env["CONCIERGE_APP"] = Bundle.main.executablePath ?? CommandLine.arguments[0]
        process.environment = env
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("tick: \(error.localizedDescription)\n".utf8))
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
