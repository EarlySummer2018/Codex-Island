import AppKit
import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var updateManager = AppUpdateManager.shared
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            divider

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    settingToggle(
                        title: capsuleTitle,
                        systemImage: "capsule",
                        isOn: Binding(
                            get: { settings.isCapsuleVisible },
                            set: setCapsuleVisible
                        ),
                        color: PanelPalette.magenta
                    )

                    settingToggle(
                        title: desktopPetTitle,
                        systemImage: "sparkles",
                        isOn: $settings.isDesktopPetEnabled,
                        color: PanelPalette.cyan
                    )
                }

                HStack(spacing: 8) {
                    capsuleStyleControl
                    expansionTriggerControl
                    languageControl
                }

                actionGrid
            }
            .padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PanelPalette.control.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PanelPalette.cyan.opacity(0.36), lineWidth: 1)
                    )

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PanelPalette.cyan)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(settingsTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PanelPalette.text)
                    .lineLimit(1)

                Text(settingsSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            Button {
                AppDirectories.open(CustomPetCatalog.shared.rootDirectory)
            } label: {
                Label(settings.text(.customPets), systemImage: "pawprint.fill")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PanelPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelPalette.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PanelPalette.magenta.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(settings.text(.customPets))

            Button {
                AppRelauncher.restart()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PanelPalette.text)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelPalette.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PanelPalette.magenta.opacity(0.20), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.text(.restartApp))
            .help(settings.text(.restartApp))

            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PanelPalette.text)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelPalette.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PanelPalette.cyan.opacity(0.20), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backTitle)
            .help(backTitle)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .frame(height: 56)
    }

    private func settingToggle(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        color: Color
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color.opacity(isOn.wrappedValue ? 0.18 : 0.08))
                    )

                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PanelPalette.text)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(color)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PanelPalette.control.opacity(isOn.wrappedValue ? 0.86 : 0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(isOn.wrappedValue ? 0.28 : 0.10), lineWidth: 1)
        )
    }

    private var capsuleStyleControl: some View {
        settingControl(settings.text(.capsuleStyle)) {
            HStack(spacing: 4) {
                segmentButton(
                    settings.text(.largeCapsule),
                    isSelected: settings.capsuleStyle == .large
                ) {
                    settings.capsuleStyle = .large
                }

                segmentButton(
                    settings.text(.smallCapsule),
                    isSelected: settings.capsuleStyle == .small
                ) {
                    settings.capsuleStyle = .small
                }
            }
        }
    }

    private var expansionTriggerControl: some View {
        settingControl(expansionTitle) {
            HStack(spacing: 4) {
                segmentButton(
                    hoverTitle,
                    isSelected: settings.capsuleExpansionTrigger == .hover
                ) {
                    settings.capsuleExpansionTrigger = .hover
                }

                segmentButton(
                    clickTitle,
                    isSelected: settings.capsuleExpansionTrigger == .click
                ) {
                    settings.capsuleExpansionTrigger = .click
                }
            }
        }
    }

    private var languageControl: some View {
        settingControl(settings.text(.language)) {
            HStack(spacing: 4) {
                segmentButton(
                    settings.text(.chinese),
                    isSelected: settings.language == .chinese
                ) {
                    settings.language = .chinese
                }

                segmentButton(
                    settings.text(.english),
                    isSelected: settings.language == .english
                ) {
                    settings.language = .english
                }
            }
        }
    }

    private func settingControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            settingsLabel(title)

            content()
                .padding(3)
                .frame(height: 30)
                .background(segmentBackground)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelPalette.control.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PanelPalette.edge, lineWidth: 1)
        )
    }

    private var segmentBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(PanelPalette.surface.opacity(0.76))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(PanelPalette.edge, lineWidth: 1)
            )
    }

    private func segmentButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? PanelPalette.surface : PanelPalette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? PanelPalette.cyan.opacity(0.92) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isSelected ? Color.clear : PanelPalette.edge.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(PanelPalette.textDim)
            .lineLimit(1)
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2),
            spacing: 6
        ) {
            actionButton(settings.text(.openCodex), systemImage: "arrow.up.right.square", color: PanelPalette.cyan) {
                CodexActivation.activate()
            }
            actionButton(settings.text(.openCodexSessions), systemImage: "folder") {
                AppDirectories.open(AppDirectories.codexSessionsDirectory())
            }
            actionButton(settings.text(.openCacheDirectory), systemImage: "tray") {
                AppDirectories.open(AppDirectories.appCacheDirectory())
            }
            actionButton(updateButtonTitle, systemImage: "arrow.triangle.2.circlepath") {
                updateManager.performPrimaryUpdateAction()
            }
            .disabled(updateManager.isChecking || updateManager.isDownloading)
            .opacity(updateManager.isChecking || updateManager.isDownloading ? 0.45 : 1)
            actionButton(settings.text(.resetCapsulePosition), systemImage: "location", color: PanelPalette.magenta) {
                NotchIslandPanel.shared.resetPosition()
            }
            actionButton(settings.text(.quit), systemImage: "power", color: PanelPalette.magenta) {
                NSApp.terminate(nil)
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color = PanelPalette.textDim,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color.opacity(0.12))
                    )

                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Spacer(minLength: 0)
            }
            .foregroundStyle(PanelPalette.text)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PanelPalette.control.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func setCapsuleVisible(_ visible: Bool) {
        settings.isCapsuleVisible = visible
    }

    private var updateButtonTitle: String {
        if updateManager.downloadedUpdateURL != nil {
            return settings.text(.restartToUpdate)
        }

        if updateManager.isDownloading {
            return settings.text(.downloadingUpdate)
        }

        if updateManager.isChecking {
            return settings.text(.checkingForUpdates)
        }

        return settings.text(.checkForUpdates)
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        PanelPalette.cyan.opacity(0.26),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private var capsuleTitle: String {
        switch settings.language {
        case .chinese:
            return "胶囊"
        case .english:
            return "Capsule"
        }
    }

    private var desktopPetTitle: String {
        switch settings.language {
        case .chinese:
            return "桌宠"
        case .english:
            return "Desktop Pet"
        }
    }

    private var expansionTitle: String {
        switch settings.language {
        case .chinese:
            return "展开"
        case .english:
            return "Expand"
        }
    }

    private var hoverTitle: String {
        switch settings.language {
        case .chinese:
            return "悬浮"
        case .english:
            return "Hover"
        }
    }

    private var clickTitle: String {
        switch settings.language {
        case .chinese:
            return "点击"
        case .english:
            return "Click"
        }
    }

    private var settingsTitle: String {
        switch settings.language {
        case .chinese:
            return "设置"
        case .english:
            return "Settings"
        }
    }

    private var settingsSubtitle: String {
        switch settings.language {
        case .chinese:
            return "胶囊、语言和本地操作"
        case .english:
            return "Capsule, language, and local actions"
        }
    }

    private var backTitle: String {
        switch settings.language {
        case .chinese:
            return "返回"
        case .english:
            return "Back"
        }
    }
}
