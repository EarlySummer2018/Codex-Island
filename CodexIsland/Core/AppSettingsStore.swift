import AppKit
import Combine
import CoreGraphics
import Foundation

enum CapsuleDisplayStyle: String, CaseIterable, Codable, Hashable {
    case large
    case small

    private static let desktopPetCapsuleWidthReduction: CGFloat = 36

    var pillSize: CGSize {
        switch self {
        case .large:
            return CGSize(width: 360, height: 34)
        case .small:
            return CGSize(width: 148, height: 34)
        }
    }

    func pillSize(desktopPetEnabled: Bool) -> CGSize {
        guard desktopPetEnabled else {
            return pillSize
        }

        return CGSize(
            width: max(pillSize.width - Self.desktopPetCapsuleWidthReduction, pillSize.height),
            height: pillSize.height
        )
    }
}

enum CapsuleExpansionTrigger: String, CaseIterable, Codable, Hashable {
    case hover
    case click
}

enum AppLanguage: String, CaseIterable, Codable, Hashable {
    case chinese = "zh-Hans"
    case english = "en"
}

enum AppTextKey {
    case appName
    case showCapsule
    case hideCapsule
    case enableDesktopPet
    case disableDesktopPet
    case capsuleStyle
    case largeCapsule
    case smallCapsule
    case language
    case chinese
    case english
    case customPets
    case openCacheDirectory
    case openCodexSessions
    case openCodex
    case checkForUpdates
    case checkingForUpdates
    case downloadingUpdate
    case restartToUpdate
    case restartApp
    case resetCapsulePosition
    case quit
    case notLoaded
    case idle
    case running
    case waitingForInput
    case readyForReview
    case error
    case reasoning
    case commandExecution
    case fileChange
    case webSearch
    case agentMessage
    case input
    case cached
    case cacheRate
    case uncached
    case output
    case total
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

    @Published var isDesktopPetEnabled: Bool {
        didSet {
            defaults.set(isDesktopPetEnabled, forKey: desktopPetEnabledKey)
        }
    }

    @Published var capsuleExpansionTrigger: CapsuleExpansionTrigger {
        didSet {
            defaults.set(capsuleExpansionTrigger.rawValue, forKey: capsuleExpansionTriggerKey)
        }
    }

    private let defaults = UserDefaults.standard
    private let capsuleStyleKey = "CodexIsland.Settings.capsuleStyle"
    private let languageKey = "CodexIsland.Settings.language"
    private let capsuleVisibleKey = "CodexIsland.Settings.capsuleVisible"
    private let desktopPetEnabledKey = "CodexIsland.Settings.desktopPetEnabled"
    private let capsuleExpansionTriggerKey = "CodexIsland.Settings.capsuleExpansionTrigger"

    private init() {
        let savedStyle = defaults.string(forKey: capsuleStyleKey)
            .flatMap(CapsuleDisplayStyle.init(rawValue:)) ?? .large
        let savedLanguage = defaults.string(forKey: languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .chinese
        let savedVisibility = defaults.object(forKey: capsuleVisibleKey) as? Bool ?? true
        let savedDesktopPetEnabled = defaults.object(forKey: desktopPetEnabledKey) as? Bool ?? false
        let savedExpansionTrigger = defaults.string(forKey: capsuleExpansionTriggerKey)
            .flatMap(CapsuleExpansionTrigger.init(rawValue:)) ?? .hover

        capsuleStyle = savedStyle
        language = savedLanguage
        isCapsuleVisible = savedVisibility
        isDesktopPetEnabled = savedDesktopPetEnabled
        capsuleExpansionTrigger = savedExpansionTrigger
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
        case .enableDesktopPet: return "开启桌宠模式"
        case .disableDesktopPet: return "关闭桌宠模式"
        case .capsuleStyle: return "胶囊样式"
        case .largeCapsule: return "大胶囊"
        case .smallCapsule: return "小胶囊"
        case .language: return "语言"
        case .chinese: return "中文"
        case .english: return "English"
        case .customPets: return "自定义宠物"
        case .openCacheDirectory: return "打开缓存目录"
        case .openCodexSessions: return "打开 Codex 会话目录"
        case .openCodex: return "打开 Codex"
        case .checkForUpdates: return "检查更新..."
        case .checkingForUpdates: return "正在检查更新..."
        case .downloadingUpdate: return "下载中..."
        case .restartToUpdate: return "重启以更新"
        case .restartApp: return "重启应用"
        case .resetCapsulePosition: return "重置胶囊位置"
        case .quit: return "退出"
        case .notLoaded: return "空闲"
        case .idle: return "空闲"
        case .running: return "运行中"
        case .waitingForInput: return "等待输入"
        case .readyForReview: return "可供审阅"
        case .error: return "错误"
        case .reasoning: return "思考"
        case .commandExecution: return "运行命令"
        case .fileChange: return "编辑文件"
        case .webSearch: return "网页检索"
        case .agentMessage: return "生成回复"
        case .input: return "输入"
        case .cached: return "缓存"
        case .cacheRate: return "缓存率"
        case .uncached: return "未缓存"
        case .output: return "输出"
        case .total: return "总计"
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
        case .enableDesktopPet: return "Enable Desktop Pet"
        case .disableDesktopPet: return "Disable Desktop Pet"
        case .capsuleStyle: return "Capsule Style"
        case .largeCapsule: return "Large Capsule"
        case .smallCapsule: return "Small Capsule"
        case .language: return "Language"
        case .chinese: return "中文"
        case .english: return "English"
        case .customPets: return "Custom Pets"
        case .openCacheDirectory: return "Open Cache Directory"
        case .openCodexSessions: return "Open Codex Sessions"
        case .openCodex: return "Open Codex"
        case .checkForUpdates: return "Check for Updates..."
        case .checkingForUpdates: return "Checking for Updates..."
        case .downloadingUpdate: return "Downloading..."
        case .restartToUpdate: return "Restart to Update"
        case .restartApp: return "Restart App"
        case .resetCapsulePosition: return "Reset Capsule Position"
        case .quit: return "Quit"
        case .notLoaded: return "Idle"
        case .idle: return "Idle"
        case .running: return "Running"
        case .waitingForInput: return "Waiting for Input"
        case .readyForReview: return "Ready for Review"
        case .error: return "Error"
        case .reasoning: return "Reasoning"
        case .commandExecution: return "Running Command"
        case .fileChange: return "Editing Files"
        case .webSearch: return "Web Search"
        case .agentMessage: return "Generating Reply"
        case .input: return "Input"
        case .cached: return "Cached"
        case .cacheRate: return "Cache Rate"
        case .uncached: return "Uncached"
        case .output: return "Output"
        case .total: return "Total"
        case .noTokenDataYet: return "No token data yet"
        case .sessionTotalPrefix: return "Session total "
        case .sessionTotalSuffix: return " tokens"
        }
    }
}

enum AppDirectories {
    static func codexHomeDirectory() -> URL {
        let path = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? "\(NSHomeDirectory())/.codex"
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func appCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("CodexIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func codexSessionsDirectory() -> URL {
        let directory = codexHomeDirectory()
            .appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func customPetStagesDirectory() -> URL {
        codexHomeDirectory()
            .appendingPathComponent("pets", isDirectory: true)
            .appendingPathComponent("codex-island-stages", isDirectory: true)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
