import AppKit
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let settings = AppSettingsStore.shared
    private let updateManager = AppUpdateManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        updateManager.configure()
        AwaitNotificationCoordinator.shared.configure()

        // Phase 09 connects the Swift app to the Rust sidecar.
        SidecarBridge.shared.start()

        setupDebugObservers()

        // Phase 05 creates and positions the notch window.
        NotchIslandPanel.shared.show()
        DesktopPetController.shared.configure()

        print("CodexIsland launched")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        guard let button = statusItem?.button else {
            return
        }

        button.image = StatusBarIcon.makeTemplateImage()
        button.imagePosition = .imageOnly
        button.toolTip = "Codex Island"
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

        settings.$isDesktopPetEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)

        updateManager.$isChecking
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)

        updateManager.$isDownloading
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleStatusMenuRebuild()
            }
            .store(in: &cancellables)

        updateManager.$downloadedUpdateURL
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

        menu.addItem(
            withTitle: settings.text(settings.isDesktopPetEnabled ? .disableDesktopPet : .enableDesktopPet),
            action: #selector(toggleDesktopPet),
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

        menu.addItem(checkForUpdatesMenuItem())

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

    private func checkForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: settings.text(updateMenuTitleKey),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = !updateManager.isChecking && !updateManager.isDownloading
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

    private var updateMenuTitleKey: AppTextKey {
        if updateManager.downloadedUpdateURL != nil {
            return .restartToUpdate
        }

        if updateManager.isDownloading {
            return .downloadingUpdate
        }

        if updateManager.isChecking {
            return .checkingForUpdates
        }

        return .checkForUpdates
    }

    @objc private func toggleCapsuleVisibility() {
        settings.isCapsuleVisible.toggle()

        if settings.isCapsuleVisible {
            NotchIslandPanel.shared.show()
        } else {
            settings.isDesktopPetEnabled = false
            NotchIslandPanel.shared.hide()
        }

        scheduleStatusMenuRebuild()
    }

    @objc private func toggleDesktopPet() {
        guard settings.isCapsuleVisible || settings.isDesktopPetEnabled else {
            return
        }

        settings.isDesktopPetEnabled.toggle()
        scheduleStatusMenuRebuild()
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

    @objc private func checkForUpdates() {
        updateManager.performPrimaryUpdateAction()
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
        DesktopPetController.shared.stopImmediately()
        SidecarBridge.shared.stop()
    }

    private func setupDebugObservers() {
        #if DEBUG
        Publishers.CombineLatest(EventBus.shared.$sessionState, EventBus.shared.$activityKind)
            .sink { state, activity in
                print("[EventBus] runtime=\(state.rawValue) activity=\(activity.rawValue)")
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

private enum StatusBarIcon {
    static func makeTemplateImage() -> NSImage {
        if let image = NSImage(named: "StatusBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Codex Island"
            return image
        }

        let imageSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor.black.setFill()

        func fill(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
            NSRect(
                x: CGFloat(x),
                y: imageSize.height - CGFloat(y + height),
                width: CGFloat(width),
                height: CGFloat(height)
            ).fill()
        }

        func clear(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
            NSGraphicsContext.current?.cgContext.clear(
                CGRect(
                    x: CGFloat(x),
                    y: imageSize.height - CGFloat(y + height),
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
            )
        }

        fill(9, 2, 1, 3)
        fill(12, 1, 1, 3)
        fill(14, 2, 1, 3)
        fill(9, 4, 6, 1)
        fill(8, 5, 7, 4)
        fill(14, 6, 3, 2)
        fill(4, 8, 4, 5)
        fill(6, 9, 7, 5)
        fill(2, 10, 4, 2)
        fill(1, 9, 2, 2)
        fill(5, 14, 2, 2)
        fill(10, 14, 2, 2)
        fill(4, 7, 1, 2)
        fill(2, 8, 1, 1)

        clear(10, 6, 1, 1)
        clear(13, 6, 1, 1)
        clear(15, 8, 1, 1)

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Codex Island"
        return image
    }
}
