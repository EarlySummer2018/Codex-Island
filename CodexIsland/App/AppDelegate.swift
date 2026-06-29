import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        AwaitNotificationCoordinator.shared.configure()

        // Phase 09 connects the Swift app to the Rust sidecar.
        SidecarBridge.shared.start()

        setupDebugObservers()

        // Phase 05 creates and positions the notch window.
        NotchIslandPanel.shared.show()

        print("CodexIsland launched")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        guard let button = statusItem?.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "cpu",
            accessibilityDescription: "Codex Island"
        )
        button.image?.isTemplate = true
        rebuildStatusMenu()

        settings.$capsuleStyle
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)

        settings.$language
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)

        settings.$isCapsuleVisible
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)
    }

    private func scheduleStatusMenuRebuild() {
        DispatchQueue.main.async { [weak self] in
            self?.rebuildStatusMenu()
        }
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        menu.addItem(
            withTitle: settings.text(settings.isCapsuleVisible ? .hideCapsule : .showCapsule),
            action: #selector(toggleCapsuleVisibility),
            keyEquivalent: ""
        ).target = self

        menu.addItem(styleMenuItem())
        menu.addItem(languageMenuItem())

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: settings.text(.openCacheDirectory),
            action: #selector(openCacheDirectory),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: settings.text(.openCodexSessions),
            action: #selector(openCodexSessions),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: settings.text(.openCodex),
            action: #selector(openCodex),
            keyEquivalent: ""
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: settings.text(.resetCapsulePosition),
            action: #selector(resetCapsulePosition),
            keyEquivalent: ""
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: settings.text(.quit),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        statusItem?.menu = menu
    }

    private func styleMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: settings.text(.capsuleStyle), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for style in CapsuleDisplayStyle.allCases {
            let menuItem = NSMenuItem(
                title: style == .large ? settings.text(.largeCapsule) : settings.text(.smallCapsule),
                action: #selector(selectCapsuleStyle(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = style.rawValue
            menuItem.state = settings.capsuleStyle == style ? .on : .off
            submenu.addItem(menuItem)
        }
        item.submenu = submenu
        return item
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: settings.text(.language), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            let menuItem = NSMenuItem(
                title: language == .chinese ? settings.text(.chinese) : settings.text(.english),
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = language.rawValue
            menuItem.state = settings.language == language ? .on : .off
            submenu.addItem(menuItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func toggleCapsuleVisibility() {
        settings.isCapsuleVisible.toggle()
    }

    @objc private func selectCapsuleStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = CapsuleDisplayStyle(rawValue: rawValue) else {
            return
        }

        guard settings.capsuleStyle != style else {
            return
        }

        settings.capsuleStyle = style
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            return
        }

        guard settings.language != language else {
            return
        }

        settings.language = language
    }

    @objc private func openCacheDirectory() {
        AppDirectories.open(AppDirectories.appCacheDirectory())
    }

    @objc private func openCodexSessions() {
        AppDirectories.open(AppDirectories.codexSessionsDirectory())
    }

    @objc private func openCodex() {
        CodexActivation.activate()
    }

    @objc private func resetCapsulePosition() {
        NotchIslandPanel.shared.resetPosition()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SidecarBridge.shared.stop()
    }

    private func setupDebugObservers() {
        #if DEBUG
        EventBus.shared.$sessionState
            .sink { state in
                print("[EventBus] state -> \(state.rawValue)")
            }
            .store(in: &cancellables)

        EventBus.shared.$latestToken
            .compactMap { $0 }
            .sink { snapshot in
                print(
                    "[Token] IN:\(snapshot.totalInput) CACHE:\(snapshot.totalCachedInput) OUT:\(snapshot.totalOutput)"
                )
            }
            .store(in: &cancellables)
        #endif
    }
}
