import Combine
import Foundation

@MainActor
final class EventBus: ObservableObject {
    static let shared = EventBus()

    @Published private(set) var sessionState: CodexSessionState = .idle
    @Published private(set) var awaitReason: AwaitReason?
    @Published private(set) var latestToken: TokenSnapshot?
    @Published private(set) var activeSessionId: String?

    private let minimumActiveDisplayDuration: TimeInterval = 1.4
    private let maxTrackedSessions = 32
    private var sessionStates: [String: CodexSessionState] = [:]
    private var sessionAwaitReasons: [String: AwaitReason] = [:]
    private var sessionTokens: [String: TokenSnapshot] = [:]
    private var sessionLastActivity: [String: Date] = [:]
    private var activeStateEnteredAt: Date?
    private var pendingRestTasks: [String: Task<Void, Never>] = [:]

    var isActive: Bool {
        sessionState != .idle && sessionState != .error
    }

    var isStreaming: Bool {
        sessionState == .streaming
    }

    var isAwaitingInput: Bool {
        sessionState == .awaitingInput
    }

    func handleStateEvent(_ event: SessionStateEvent) {
        pendingRestTasks[event.sessionId]?.cancel()
        pendingRestTasks[event.sessionId] = nil

        if shouldDelayRestingState(event) {
            scheduleRestingState(event)
            return
        }

        applyStateEvent(event)
    }

    private func applyStateEvent(_ event: SessionStateEvent) {
        sessionStates[event.sessionId] = event.state
        sessionLastActivity[event.sessionId] = event.timestamp

        if let awaitReason = event.awaitReason {
            sessionAwaitReasons[event.sessionId] = awaitReason
        } else if event.state != .awaitingInput {
            sessionAwaitReasons.removeValue(forKey: event.sessionId)
        }

        if event.state.shouldPromoteToFront {
            activeSessionId = event.sessionId
            activeStateEnteredAt = Date()
        } else if activeSessionId == nil || activeSessionId == event.sessionId {
            activeSessionId = bestSessionId()
            if activeSessionId == nil || activeSessionIsResting {
                activeStateEnteredAt = nil
            }
        }

        applyActiveSession()
        pruneTrackedSessions()
    }

    private func shouldDelayRestingState(_ event: SessionStateEvent) -> Bool {
        guard event.state == .idle,
              activeSessionId == event.sessionId,
              let activeStateEnteredAt else {
            return false
        }

        return Date().timeIntervalSince(activeStateEnteredAt) < minimumActiveDisplayDuration
    }

    private func scheduleRestingState(_ event: SessionStateEvent) {
        let elapsed = activeStateEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
        let delay = max(0, minimumActiveDisplayDuration - elapsed)

        pendingRestTasks[event.sessionId] = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }

                self.pendingRestTasks[event.sessionId] = nil
                self.applyStateEvent(event)
            }
        }
    }

    func handleTokenSnapshot(_ snapshot: TokenSnapshot) {
        sessionTokens[snapshot.sessionId] = snapshot
        sessionLastActivity[snapshot.sessionId] = snapshot.timestamp

        if activeSessionId == nil || activeSessionIsResting {
            activeSessionId = snapshot.sessionId
        }

        let isActiveSnapshot = activeSessionId == snapshot.sessionId
        TokenStore.shared.update(with: snapshot, isActive: isActiveSnapshot)

        if isActiveSnapshot {
            latestToken = snapshot
        }
        pruneTrackedSessions()
    }

    private func applyActiveSession() {
        guard let activeSessionId else {
            sessionState = .idle
            awaitReason = nil
            latestToken = nil
            return
        }

        sessionState = sessionStates[activeSessionId] ?? .idle
        awaitReason = sessionAwaitReasons[activeSessionId]
        latestToken = sessionTokens[activeSessionId]
        TokenStore.shared.showSession(activeSessionId, latest: sessionTokens[activeSessionId])
    }

    private func bestSessionId() -> String? {
        let sessionIds = Set(sessionStates.keys)
            .union(sessionTokens.keys)
            .union(sessionLastActivity.keys)

        return sessionIds.max { lhs, rhs in
            let lhsState = sessionStates[lhs] ?? .idle
            let rhsState = sessionStates[rhs] ?? .idle

            if lhsState.displayPriority != rhsState.displayPriority {
                return lhsState.displayPriority < rhsState.displayPriority
            }

            let lhsDate = sessionLastActivity[lhs] ?? .distantPast
            let rhsDate = sessionLastActivity[rhs] ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private var activeSessionIsResting: Bool {
        guard let activeSessionId else {
            return true
        }

        return !(sessionStates[activeSessionId] ?? .idle).shouldPromoteToFront
    }

    private func pruneTrackedSessions() {
        guard sessionLastActivity.count > maxTrackedSessions else {
            return
        }

        let protectedSessionId = activeSessionId
        let removable = sessionLastActivity
            .filter { item in
                item.key != protectedSessionId
            }
            .sorted { lhs, rhs in
                lhs.value < rhs.value
            }
            .prefix(max(sessionLastActivity.count - maxTrackedSessions, 0))

        for item in removable {
            sessionStates.removeValue(forKey: item.key)
            sessionAwaitReasons.removeValue(forKey: item.key)
            sessionTokens.removeValue(forKey: item.key)
            sessionLastActivity.removeValue(forKey: item.key)
            pendingRestTasks[item.key]?.cancel()
            pendingRestTasks.removeValue(forKey: item.key)
        }
    }

}

private extension CodexSessionState {
    var shouldPromoteToFront: Bool {
        switch self {
        case .thinking, .working, .streaming, .awaitingInput:
            return true
        case .idle, .error:
            return false
        }
    }

    var displayPriority: Int {
        switch self {
        case .awaitingInput:
            return 4
        case .working:
            return 3
        case .streaming:
            return 3
        case .thinking:
            return 2
        case .error:
            return 1
        case .idle:
            return 0
        }
    }
}
