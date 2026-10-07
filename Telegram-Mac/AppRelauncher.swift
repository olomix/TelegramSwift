import Cocoa
import TelegramCore

enum AppRelauncher {
    /// Kept open until this process exits; the helper sees end-of-file then.
    private static var exitPipe: Pipe?

    /// Quits and reopens the app. The new copy starts only after this
    /// process has exited, so two copies never share the database.
    /// Returns false, leaving the app running, when the helper cannot start.
    static func relaunch() -> Bool {
        // Waiting on a pipe needs no right to signal this process, which the
        // App Sandbox may deny to the helper. -n because LaunchServices may
        // still list the exited app as running and only send it a reopen.
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "cat >/dev/null; open -n \"$1\"", "sh", Bundle.main.bundlePath]
        process.standardInput = pipe
        do {
            try process.run()
        } catch {
            Logger.shared.log("AppRelauncher", "Could not schedule relaunch: \(error)")
            return false
        }
        exitPipe = pipe
        NSApp.terminate(nil)
        return true
    }
}
