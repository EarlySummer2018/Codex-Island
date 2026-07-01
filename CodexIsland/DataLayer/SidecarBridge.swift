import Foundation
import Darwin

final class SidecarBridge {
    static let shared = SidecarBridge()

    private let queue = DispatchQueue(label: "com.huang.codexisland.sidecar", qos: .utility)
    private let connectionQueue = DispatchQueue(
        label: "com.huang.codexisland.sidecar.connection",
        qos: .utility
    )
    private let decoder = IpcEventDecoder()
    private let socketPath = "\(NSTemporaryDirectory())codex-island-\(getuid()).sock"

    private var process: Process?
    private var shouldRun = false
    private var isConnecting = false

    private init() {}

    func start() {
        queue.async { [weak self] in
            guard let self, !self.shouldRun else {
                return
            }

            self.shouldRun = true
            self.launchSidecar()
            self.startConnectionLoop()
        }
    }

    func stop() {
        queue.sync {
            self.shouldRun = false
            self.process?.terminationHandler = nil
            self.process?.terminate()
            self.process = nil
            try? FileManager.default.removeItem(atPath: self.socketPath)
        }
    }

    private func launchSidecar() {
        guard let executableURL = resolveSidecarExecutable() else {
            print("Sidecar executable not found")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_ISLAND_SOCKET"] = socketPath
        environment["RUST_LOG"] = environment["RUST_LOG"] ?? "info"
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }

            for line in text.split(whereSeparator: \.isNewline) {
                print("[codex-watcher] \(line)")
            }
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            print("codex-watcher exited with status \(process.terminationStatus)")

            self?.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.shouldRun else {
                    return
                }

                self.process = nil
                self.launchSidecar()
                self.startConnectionLoop()
            }
        }

        do {
            try FileManager.default.removeItem(atPath: socketPath)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        } catch {
            print("Failed to remove stale socket: \(error.localizedDescription)")
        }

        do {
            try process.run()
            self.process = process
            print("codex-watcher started: \(executableURL.path)")
        } catch {
            print("Failed to start codex-watcher: \(error.localizedDescription)")
        }
    }

    private func startConnectionLoop() {
        guard !isConnecting else {
            return
        }

        isConnecting = true

        connectionQueue.async { [weak self] in
            guard let self else {
                return
            }

            while self.shouldRun {
                do {
                    let handle = try UnixSocket.connect(path: self.socketPath)
                    print("Connected to codex-watcher IPC: \(self.socketPath)")
                    self.readLines(from: handle)
                } catch {
                    Thread.sleep(forTimeInterval: 0.35)
                }
            }

            self.queue.async { [weak self] in
                self?.isConnecting = false
            }
        }
    }

    private func readLines(from handle: FileHandle) {
        var buffer = Data()

        while shouldRun {
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                break
            }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)

                guard !lineData.isEmpty,
                      let line = String(data: lineData, encoding: .utf8) else {
                    continue
                }

                handleIpcLine(line)
            }
        }

        try? handle.close()
    }

    private func handleIpcLine(_ line: String) {
        switch decoder.decode(line: line) {
        case .state(let event):
            Task { @MainActor in
                EventBus.shared.handleStateEvent(event)
            }
        case .token(let snapshot):
            Task { @MainActor in
                EventBus.shared.handleTokenSnapshot(snapshot)
            }
        case .globalToken(let snapshot):
            Task { @MainActor in
                PetEvolutionStore.shared.update(with: snapshot)
            }
        case .dailyToken(let snapshot):
            Task { @MainActor in
                TokenStore.shared.update(with: snapshot)
            }
        case .ignored:
            break
        case .invalid(let error):
            print("Invalid IPC line: \(error.localizedDescription)")
        }
    }

    private func resolveSidecarExecutable() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "codex-watcher", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debugURL = projectRoot
            .appendingPathComponent("codex-watcher")
            .appendingPathComponent("target")
            .appendingPathComponent("debug")
            .appendingPathComponent("codex-watcher")

        if FileManager.default.isExecutableFile(atPath: debugURL.path) {
            return debugURL
        }

        return nil
    }
}

enum IpcMessage {
    case state(SessionStateEvent)
    case token(TokenSnapshot)
    case globalToken(GlobalTokenUsageSnapshot)
    case dailyToken(DailyTokenUsageSnapshot)
    case ignored
    case invalid(Error)
}

final class IpcEventDecoder {
    private let jsonDecoder: JSONDecoder

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = IpcEventDecoder.fractionalDateFormatter.date(from: dateString) {
                return date
            }

            if let date = IpcEventDecoder.dateFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(dateString)"
            )
        }
        self.jsonDecoder = decoder
    }

    func decode(line: String) -> IpcMessage {
        guard let data = line.data(using: .utf8) else {
            return .ignored
        }

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .ignored
            }

            if object["type"] as? String == "global_token_usage" {
                return .globalToken(try jsonDecoder.decode(GlobalTokenUsageSnapshot.self, from: data))
            }

            if object["type"] as? String == "daily_token_usage" {
                return .dailyToken(try jsonDecoder.decode(DailyTokenUsageSnapshot.self, from: data))
            }

            if object["state"] != nil, object["session_id"] != nil {
                return .state(try jsonDecoder.decode(SessionStateEvent.self, from: data))
            }

            if object["total_input"] != nil, object["delta_output"] != nil {
                return .token(try jsonDecoder.decode(TokenSnapshot.self, from: data))
            }

            return .ignored
        } catch {
            return .invalid(error)
        }
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum UnixSocket {
    static func connect(path: String) throws -> FileHandle {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let encodedPath = path.utf8CString
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard encodedPath.count <= maxPathLength else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: CChar.self, repeating: 0)
            encodedPath.withUnsafeBufferPointer { sourceBuffer in
                rawBuffer.copyMemory(from: UnsafeRawBufferPointer(sourceBuffer))
            }
        }

        let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + encodedPath.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addressLength)
            }
        }

        guard result == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(fd)
            throw POSIXError(code)
        }

        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
