import AppKit
import Combine
import CoreGraphics
import Foundation

enum CapsuleDisplayStyle: String, CaseIterable, Codable {
    case large
    case small

    var pillSize: CGSize {
        switch self {
        case .large:
            return CGSize(width: 440, height: 34)
        case .small:
            return CGSize(width: 260, height: 34)
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable {
    case chinese = "zh-Hans"
    case english = "en"
}

enum AppTextKey {
    case appName
    case showCapsule
    case hideCapsule
    case capsuleStyle
    case largeCapsule
    case smallCapsule
    case language
    case chinese
    case english
    case openCacheDirectory
    case openCodexSessions
    case openCodex
    case resetCapsulePosition
    case quit
    case idle
    case thinking
    case streaming
    case awaitingInput
    case error
    case input
    case cached
    case uncached
    case output
    case noTokenDataYet
    case sessionTotalPrefix
    case sessionTotalSuffix
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var capsuleStyle: CapsuleDisplayStyle {
        didSet {
            defaults.set(capsuleStyle.rawValue, forKey: capsuleStyleKey)
        }
    }

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: languageKey)
        }
    }

    @Published var isCapsuleVisible: Bool {
        didSet {
            defaults.set(isCapsuleVisible, forKey: capsuleVisibleKey)
        }
    }

    private let defaults = UserDefaults.standard
    private let capsuleStyleKey = "CodexIsland.Settings.capsuleStyle"
    private let languageKey = "CodexIsland.Settings.language"
    private let capsuleVisibleKey = "CodexIsland.Settings.capsuleVisible"

    private init() {
        let savedStyle = defaults.string(forKey: capsuleStyleKey)
            .flatMap(CapsuleDisplayStyle.init(rawValue:)) ?? .large
        let savedLanguage = defaults.string(forKey: languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        let savedVisibility = defaults.object(forKey: capsuleVisibleKey) as? Bool ?? true

        capsuleStyle = savedStyle
        language = savedLanguage
        isCapsuleVisible = savedVisibility
    }

    func text(_ key: AppTextKey) -> String {
        switch language {
        case .chinese:
            return chineseText(key)
        case .english:
            return englishText(key)
        }
    }

    private func chineseText(_ key: AppTextKey) -> String {
        switch key {
        case .appName: return "Codex Island"
        case .showCapsule: return "显示胶囊"
        case .hideCapsule: return "隐藏胶囊"
        case .capsuleStyle: return "胶囊样式"
        case .largeCapsule: return "大胶囊"
        case .smallCapsule: return "小胶囊"
        case .language: return "语言"
        case .chinese: return "中文"
        case .english: return "English"
        case .openCacheDirectory: return "打开缓存目录"
        case .openCodexSessions: return "打开 Codex 会话目录"
        case .openCodex: return "打开 Codex"
        case .resetCapsulePosition: return "重置胶囊位置"
        case .quit: return "退出"
        case .idle: return "空闲"
        case .thinking: return "思考中"
        case .streaming: return "输出中"
        case .awaitingInput: return "等待回复"
        case .error: return "错误"
        case .input: return "输入"
        case .cached: return "缓存"
        case .uncached: return "未缓存"
        case .output: return "输出"
        case .noTokenDataYet: return "暂无 token 数据"
        case .sessionTotalPrefix: return "当前会话共 "
        case .sessionTotalSuffix: return " tokens"
        }
    }

    private func englishText(_ key: AppTextKey) -> String {
        switch key {
        case .appName: return "Codex Island"
        case .showCapsule: return "Show Capsule"
        case .hideCapsule: return "Hide Capsule"
        case .capsuleStyle: return "Capsule Style"
        case .largeCapsule: return "Large Capsule"
        case .smallCapsule: return "Small Capsule"
        case .language: return "Language"
        case .chinese: return "中文"
        case .english: return "English"
        case .openCacheDirectory: return "Open Cache Directory"
        case .openCodexSessions: return "Open Codex Sessions"
        case .openCodex: return "Open Codex"
        case .resetCapsulePosition: return "Reset Capsule Position"
        case .quit: return "Quit"
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .streaming: return "Streaming"
        case .awaitingInput: return "Awaiting Input"
        case .error: return "Error"
        case .input: return "Input"
        case .cached: return "Cached"
        case .uncached: return "Uncached"
        case .output: return "Output"
        case .noTokenDataYet: return "No token data yet"
        case .sessionTotalPrefix: return "Session total "
        case .sessionTotalSuffix: return " tokens"
        }
    }
}

enum AppDirectories {
    static func appCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("CodexIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func codexSessionsDirectory() -> URL {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? "\(NSHomeDirectory())/.codex"
        let directory = URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
