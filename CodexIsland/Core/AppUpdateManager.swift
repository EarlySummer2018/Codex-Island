import AppKit
import Combine
import Foundation

@MainActor
final class AppUpdateManager: ObservableObject {
    static let shared = AppUpdateManager()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadedUpdateURL: URL?

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/EarlySummer2018/Codex-Island/releases/latest"
    )!
    private let latestReleaseWebURL = URL(
        string: "https://github.com/EarlySummer2018/Codex-Island/releases/latest"
    )!
    private let githubBaseURL = URL(string: "https://github.com")!

    private init() {}

    func configure() {
        // Updates are intentionally user-initiated from the single menu action.
    }

    func performPrimaryUpdateAction() {
        if let downloadedUpdateURL {
            openDownloadedUpdateAndQuit(downloadedUpdateURL)
            return
        }

        Task {
            await checkAndDownloadLatestUpdate()
        }
    }

    private func checkAndDownloadLatestUpdate() async {
        guard !isChecking, !isDownloading else {
            return
        }

        isChecking = true

        let release: GitHubRelease
        do {
            release = try await fetchLatestRelease()
        } catch {
            isChecking = false
            showCheckFailedAlert(error: error)
            return
        }

        isChecking = false

        guard release.isNewer(than: currentVersionString) else {
            downloadedUpdateURL = nil
            showNoUpdateAlert()
            return
        }

        guard let asset = release.preferredInstallAsset else {
            showNoInstallAssetAlert(release: release)
            return
        }

        await downloadUpdate(asset: asset)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        do {
            return try await fetchLatestReleaseFromAPI()
        } catch UpdateError.httpStatus(let statusCode) where [403, 429].contains(statusCode) {
            return try await fetchLatestReleaseFromWeb()
        } catch {
            throw error
        }
    }

    private func fetchLatestReleaseFromAPI() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func fetchLatestReleaseFromWeb() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseWebURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)

        guard let finalURL = response.url,
              let tagName = tagName(from: finalURL) else {
            throw UpdateError.cannotResolveLatestRelease
        }

        let assets = try await fetchReleaseAssetsFromWeb(tagName: tagName)
        return GitHubRelease(tagName: tagName, name: tagName, assets: assets)
    }

    private func fetchReleaseAssetsFromWeb(tagName: String) async throws -> [GitHubRelease.Asset] {
        let assetsURL = githubBaseURL
            .appendingPathComponent("EarlySummer2018")
            .appendingPathComponent("Codex-Island")
            .appendingPathComponent("releases")
            .appendingPathComponent("expanded_assets")
            .appendingPathComponent(tagName)

        var request = URLRequest(url: assetsURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(webUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)

        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }

        return releaseAssets(in: html, tagName: tagName)
    }

    private func tagName(from url: URL) -> String? {
        let components = url.pathComponents

        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            return nil
        }

        return components[tagIndex + 1]
    }

    private func releaseAssets(in html: String, tagName: String) -> [GitHubRelease.Asset] {
        let escapedTag = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = "/EarlySummer2018/Codex-Island/releases/download/"
            + escapedTag
            + "/([^\\\"?<>]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seenPaths = Set<String>()

        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let fileRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            let encodedFileName = String(html[fileRange])
                .replacingOccurrences(of: "&amp;", with: "&")
            let path = "/EarlySummer2018/Codex-Island/releases/download/"
                + tagName
                + "/"
                + encodedFileName

            guard seenPaths.insert(path).inserted,
                  let downloadURL = URL(string: path, relativeTo: githubBaseURL)?.absoluteURL else {
                return nil
            }

            let fileName = encodedFileName.removingPercentEncoding ?? encodedFileName
            return GitHubRelease.Asset(name: fileName, browserDownloadURL: downloadURL)
        }
    }

    private var webUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X) CodexIsland/\(currentVersionString)"
    }

    private func downloadUpdate(asset: GitHubRelease.Asset) async {
        guard !isDownloading else {
            return
        }

        isDownloading = true
        defer {
            isDownloading = false
        }

        do {
            let downloadedURL = try await downloadAsset(asset)
            downloadedUpdateURL = downloadedURL
        } catch {
            downloadedUpdateURL = nil
            showDownloadFailedAlert(error: error)
        }
    }

    private func downloadAsset(_ asset: GitHubRelease.Asset) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("CodexIsland", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validateHTTPResponse(response)

        let updatesDirectory = try updatesDirectory()
        let destinationURL = updatesDirectory.appendingPathComponent(asset.safeFileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }
    }

    private func updatesDirectory() throws -> URL {
        let directory = AppDirectories.appCacheDirectory()
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func openDownloadedUpdateAndQuit(_ fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            downloadedUpdateURL = nil
            showDownloadedFileMissingAlert()
            return
        }

        if canApplyAutomatically(fileURL),
           launchAutomaticUpdate(from: fileURL) {
            NSApp.terminate(nil)
            return
        }

        NSWorkspace.shared.open(fileURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.terminate(nil)
        }
    }

    private func canApplyAutomatically(_ fileURL: URL) -> Bool {
        ["zip", "dmg"].contains(fileURL.pathExtension.lowercased())
    }

    private func launchAutomaticUpdate(from fileURL: URL) -> Bool {
        do {
            let directory = try updatesDirectory()
            let scriptURL = directory.appendingPathComponent(
                "apply-codex-island-update.sh",
                isDirectory: false
            )
            let logURL = directory.appendingPathComponent(
                "apply-codex-island-update.log",
                isDirectory: false
            )

            try automaticUpdateScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                scriptURL.path,
                Bundle.main.bundleURL.path,
                fileURL.path,
                "\(ProcessInfo.processInfo.processIdentifier)",
                logURL.path
            ]
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private var automaticUpdateScript: String {
        """
        #!/bin/bash
        set -u

        SCRIPT_PATH="$1"
        CURRENT_APP="$2"
        UPDATE_FILE="$3"
        APP_PID="$4"
        LOG_FILE="$5"

        exec >> "$LOG_FILE" 2>&1

        echo "=== Codex Island update $(/bin/date) ==="
        echo "Current app: $CURRENT_APP"
        echo "Update file: $UPDATE_FILE"

        APP_NAME="$(/usr/bin/basename "$CURRENT_APP")"
        PARENT_DIR="$(/usr/bin/dirname "$CURRENT_APP")"
        BACKUP_APP="$PARENT_DIR/.${APP_NAME}.previous-update"
        TMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/codex-island-update.XXXXXX")"
        MOUNT_DIR=""

        cleanup() {
            if [ -n "$MOUNT_DIR" ] && /sbin/mount | /usr/bin/grep -q "on $MOUNT_DIR "; then
                /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet || true
            fi
            /bin/rm -rf "$TMP_DIR"
            /bin/rm -f "$SCRIPT_PATH"
        }

        restore_backup() {
            if [ -d "$BACKUP_APP" ] && [ ! -d "$CURRENT_APP" ]; then
                /bin/mv "$BACKUP_APP" "$CURRENT_APP" || true
            fi
        }

        fail() {
            echo "Update failed: $1"
            restore_backup
            /usr/bin/open "$UPDATE_FILE" >/dev/null 2>&1 || /usr/bin/open -R "$UPDATE_FILE" >/dev/null 2>&1 || true
            exit 1
        }

        trap cleanup EXIT

        for _ in $(/usr/bin/seq 1 120); do
            if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
                break
            fi
            /bin/sleep 0.25
        done

        if /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
            fail "timed out waiting for app to quit"
        fi

        SOURCE_ROOT=""
        UPDATE_EXT="$(/bin/echo "${UPDATE_FILE##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')"

        case "$UPDATE_EXT" in
            zip)
                SOURCE_ROOT="$TMP_DIR/extracted"
                /bin/mkdir -p "$SOURCE_ROOT" || fail "could not create extraction directory"
                /usr/bin/ditto -x -k "$UPDATE_FILE" "$SOURCE_ROOT" || fail "could not extract zip"
                ;;
            dmg)
                MOUNT_DIR="$TMP_DIR/mount"
                /bin/mkdir -p "$MOUNT_DIR" || fail "could not create mount directory"
                /usr/bin/hdiutil attach "$UPDATE_FILE" -nobrowse -quiet -mountpoint "$MOUNT_DIR" || fail "could not mount dmg"
                SOURCE_ROOT="$MOUNT_DIR"
                ;;
            *)
                fail "unsupported update type: $UPDATE_EXT"
                ;;
        esac

        SOURCE_APP="$(/usr/bin/find "$SOURCE_ROOT" -maxdepth 4 -name "$APP_NAME" -type d -print -quit)"
        if [ -z "$SOURCE_APP" ]; then
            SOURCE_APP="$(/usr/bin/find "$SOURCE_ROOT" -maxdepth 4 -name "CodexIsland.app" -type d -print -quit)"
        fi
        if [ -z "$SOURCE_APP" ]; then
            fail "updated app bundle not found"
        fi

        /bin/rm -rf "$BACKUP_APP" || fail "could not remove previous backup"
        if [ -d "$CURRENT_APP" ]; then
            /bin/mv "$CURRENT_APP" "$BACKUP_APP" || fail "could not move current app"
        fi

        if ! /usr/bin/ditto "$SOURCE_APP" "$CURRENT_APP"; then
            /bin/rm -rf "$CURRENT_APP"
            restore_backup
            fail "could not copy updated app"
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$CURRENT_APP" >/dev/null 2>&1 || true
        /usr/bin/open "$CURRENT_APP" >/dev/null 2>&1 || fail "could not relaunch app"
        /bin/rm -rf "$BACKUP_APP"

        echo "Update applied successfully"
        """
    }

    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text(.noUpdateTitle)
        alert.informativeText = text(.noUpdateBody, currentVersionString)
        alert.addButton(withTitle: text(.okButton))
        alert.runModal()
    }

    private func showNoInstallAssetAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text(.noInstallAssetTitle)
        alert.informativeText = text(.noInstallAssetBody, release.displayVersion)
        alert.addButton(withTitle: text(.okButton))
        alert.runModal()
    }

    private func showCheckFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text(.checkFailedTitle)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: text(.okButton))
        alert.runModal()
    }

    private func showDownloadFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text(.downloadFailedTitle)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: text(.okButton))
        alert.runModal()
    }

    private func showDownloadedFileMissingAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text(.downloadMissingTitle)
        alert.informativeText = text(.downloadMissingBody)
        alert.addButton(withTitle: text(.okButton))
        alert.runModal()
    }

    private var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func text(_ key: UpdateTextKey, _ value: String? = nil) -> String {
        let language = AppSettingsStore.shared.language

        switch (language, key) {
        case (.chinese, .noUpdateTitle):
            return "当前已是最新版本"
        case (.english, .noUpdateTitle):
            return "Codex Island Is Up to Date"
        case (.chinese, .noUpdateBody):
            return "当前版本：\(value ?? currentVersionString)"
        case (.english, .noUpdateBody):
            return "Current version: \(value ?? currentVersionString)"
        case (.chinese, .noInstallAssetTitle):
            return "无法直接安装更新"
        case (.english, .noInstallAssetTitle):
            return "Automatic Update Unavailable"
        case (.chinese, .noInstallAssetBody):
            return "版本 \(value ?? "") 没有可直接安装的 macOS 安装包。"
        case (.english, .noInstallAssetBody):
            return "Version \(value ?? "") does not include a directly installable macOS package."
        case (.chinese, .checkFailedTitle):
            return "检查更新失败"
        case (.english, .checkFailedTitle):
            return "Update Check Failed"
        case (.chinese, .downloadFailedTitle):
            return "下载更新失败"
        case (.english, .downloadFailedTitle):
            return "Update Download Failed"
        case (.chinese, .downloadMissingTitle):
            return "更新文件不存在"
        case (.english, .downloadMissingTitle):
            return "Downloaded Update Missing"
        case (.chinese, .downloadMissingBody):
            return "请重新检查更新并下载。"
        case (.english, .downloadMissingBody):
            return "Check for updates again to download a fresh installer."
        case (.chinese, .okButton):
            return "好"
        case (.english, .okButton):
            return "OK"
        }
    }
}

private enum UpdateTextKey {
    case noUpdateTitle
    case noUpdateBody
    case noInstallAssetTitle
    case noInstallAssetBody
    case checkFailedTitle
    case downloadFailedTitle
    case downloadMissingTitle
    case downloadMissingBody
    case okButton
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let assets: [Asset]

    var displayVersion: String {
        name?.isEmpty == false ? name! : tagName
    }

    var preferredInstallAsset: Asset? {
        let supportedExtensions = ["zip", "dmg", "pkg"]

        return supportedExtensions.lazy
            .compactMap { fileExtension in
                assets.first { asset in
                    asset.name.lowercased().hasSuffix(".\(fileExtension)")
                        && asset.name.lowercased().contains("mac")
                }
            }
            .first
            ?? assets.first { asset in
                supportedExtensions.contains(asset.fileExtension)
            }
    }

    func isNewer(than currentVersion: String) -> Bool {
        AppVersion(tagName) > AppVersion(currentVersion)
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        var fileExtension: String {
            URL(fileURLWithPath: name).pathExtension.lowercased()
        }

        var safeFileName: String {
            name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
        }

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private struct AppVersion: Comparable {
    let components: [Int]

    init(_ string: String) {
        let trimmed = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = trimmed.split(separator: "-", maxSplits: 1).first ?? ""

        components = core
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { character in
                    character.isNumber
                }
                return Int(digits) ?? 0
            }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)

        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}

private enum UpdateError: LocalizedError {
    case httpStatus(Int)
    case cannotResolveLatestRelease

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "HTTP \(code)"
        case .cannotResolveLatestRelease:
            return "Cannot resolve latest GitHub release"
        }
    }
}
