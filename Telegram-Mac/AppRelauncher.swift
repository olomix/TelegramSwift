import Cocoa

enum AppRelauncher {
    /// Quits and reopens the app. The new copy starts only after this
    /// process has exited, so two copies never share the database.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; open \"$2\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", "\(pid)", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            NSLog("Could not schedule relaunch: \(error)")
        }
        NSApp.terminate(nil)
    }
}
