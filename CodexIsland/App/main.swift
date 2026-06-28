import AppKit

MainActor.assumeIsolated {
    let appDelegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = appDelegate
    app.run()
}
