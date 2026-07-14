import AppKit
import Foundation

enum AppRelauncher {
    static let helperExecutableURL = URL(fileURLWithPath: "/bin/sh")

    static func helperArguments(for bundleURL: URL) -> [String] {
        [
            "-c",
            "/bin/sleep 0.6; exec /usr/bin/open -n \"$1\"",
            "codex-island-restart",
            bundleURL.standardizedFileURL.path
        ]
    }

    @MainActor
    static func restart(bundleURL: URL = Bundle.main.bundleURL) {
        let helper = Process()
        helper.executableURL = helperExecutableURL
        helper.arguments = helperArguments(for: bundleURL)

        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
            print("Could not restart CodexIsland: \(error)")
        }
    }
}
