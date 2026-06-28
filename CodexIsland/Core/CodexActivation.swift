import AppKit
import Foundation

enum CodexActivation {
    static func activate() {
        if let runningCodex = NSWorkspace.shared.runningApplications.first(where: isCodexApp) {
            runningCodex.activate(options: .activateIgnoringOtherApps)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Codex"]

        do {
            try process.run()
        } catch {
            print("Failed to open Codex: \(error.localizedDescription)")
        }
    }

    private static func isCodexApp(_ app: NSRunningApplication) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
           bundleIdentifier.contains("codex") {
            return true
        }

        if let localizedName = app.localizedName?.lowercased(),
           localizedName.contains("codex") {
            return true
        }

        return false
    }
}
