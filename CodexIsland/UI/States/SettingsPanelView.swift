import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var updateManager = AppUpdateManager.shared
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            divider

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    settingToggle(
                        title: capsuleTitle,
                        isOn: Binding(
                            get: { settings.isCapsuleVisible },
                            set: setCapsuleVisible
                        ),
                        color: PanelPalette.magenta
                    )

                    settingToggle(
                        title: desktopPetTitle,
                        isOn: $settings.isDesktopPetEnabled,
                        color: PanelPalette.cyan
                    )
                    .disabled(!settings.isCapsuleVisible)
                    .opacity(settings.isCapsuleVisible ? 1 : 0.45)
                }

                HStack(spacing: 8) {
                    capsuleStyleControl
                    languageControl
                }

                actionGrid
            }
            .padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)
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
        .frame(height: 64)
    }

    private func settingToggle(
        title: String,
        isOn: Binding<Bool>,
        color: Color
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PanelPalette.text)
                .lineLimit(1)
        }
        .toggleStyle(.switch)
        .tint(color)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PanelPalette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 1)
        )
    }

    private var capsuleStyleControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsLabel(settings.text(.capsuleStyle))

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
            .padding(3)
            .frame(height: 30)
            .background(segmentBackground)
        }
        .frame(maxWidth: .infinity)
    }

    private var languageControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsLabel(settings.text(.language))

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
            .padding(3)
            .frame(height: 30)
            .background(segmentBackground)
        }
        .frame(maxWidth: .infinity)
    }

    private var segmentBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(PanelPalette.surface.opacity(0.86))
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
                        .fill(isSelected ? PanelPalette.cyan : Color.clear)
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
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
            spacing: 7
        ) {
            actionButton(settings.text(.openCodex), systemImage: "arrow.up.right.square") {
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
            actionButton(settings.text(.resetCapsulePosition), systemImage: "location") {
                NotchIslandPanel.shared.resetPosition()
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .foregroundStyle(PanelPalette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PanelPalette.control.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PanelPalette.edge, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func setCapsuleVisible(_ visible: Bool) {
        settings.isCapsuleVisible = visible

        if !visible {
            settings.isDesktopPetEnabled = false
        }
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
