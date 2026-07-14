import Combine
import Foundation

@MainActor
final class EventBus: ObservableObject {
    static let shared = EventBus()

    @Published private(set) var sessionState: CodexSessionState = .notLoaded
    @Published private(set) var activityKind: CodexActivityKind = .none
    @Published private(set) var turnState: CodexTurnState?
    @Published private(set) var awaitReason: AwaitReason?
    @Published private(set) var latestToken: TokenSnapshot?
    @Published private(set) var activeSessionId: String?

    private let minimumActiveDisplayDuration: TimeInterval
    private let now: () -> Date
    private let maxTrackedSessions = 32
    private var sessionStates: [String: CodexSessionState] = [:]
    private var sessionActivities: [String: CodexActivityKind] = [:]
    private var sessionTurnStates: [String: CodexTurnState] = [:]
    private var sessionAwaitReasons: [String: AwaitReason] = [:]
    private var sessionTokens: [String: TokenSnapshot] = [:]
    private var sessionLastActivity: [String: Date] = [:]
    private var activeStateEnteredAt: Date?
    private var pendingRestTasks: [String: Task<Void, Never>] = [:]

    init(
        minimumActiveDisplayDuration: TimeInterval = 1.4,
        now: @escaping () -> Date = Date.init
    ) {
        self.minimumActiveDisplayDuration = minimumActiveDisplayDuration
        self.now = now
    }

    var isActive: Bool {
        switch sessionState {
        case .running, .waitingForInput, .readyForReview:
            return true
        case .notLoaded, .idle, .error:
            return false
        }
    }

    var isAwaitingInput: Bool {
        sessionState == .waitingForInput
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
        let previousActiveSessionId = activeSessionId
        let previousActiveWasResting = activeSessionIsResting

        sessionStates[event.sessionId] = event.state
        sessionActivities[event.sessionId] = event.activityKind
        sessionLastActivity[event.sessionId] = event.timestamp

        if let turnState = event.turnState {
            sessionTurnStates[event.sessionId] = turnState
        } else {
            sessionTurnStates.removeValue(forKey: event.sessionId)
        }

        if let awaitReason = event.awaitReason {
            sessionAwaitReasons[event.sessionId] = awaitReason
        } else if event.state != .waitingForInput {
            sessionAwaitReasons.removeValue(forKey: event.sessionId)
        }

        activeSessionId = bestSessionId()
        if let activeSessionId,
           (sessionStates[activeSessionId] ?? .notLoaded).shouldPromoteToFront {
            if activeSessionId != previousActiveSessionId || previousActiveWasResting {
                activeStateEnteredAt = now()
            }
        } else {
            activeStateEnteredAt = nil
        }

        applyActiveSession()
        pruneTrackedSessions()
    }

    private func shouldDelayRestingState(_ event: SessionStateEvent) -> Bool {
        guard event.state.isRestingState,
              activeSessionId == event.sessionId,
              let activeStateEnteredAt else {
            return false
        }

        return now().timeIntervalSince(activeStateEnteredAt) < minimumActiveDisplayDuration
    }

    private func scheduleRestingState(_ event: SessionStateEvent) {
        let elapsed = activeStateEnteredAt.map { now().timeIntervalSince($0) } ?? 0
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

        activeSessionId = bestSessionId()
        applyActiveSession()

        let isActiveSnapshot = activeSessionId == snapshot.sessionId
        TokenStore.shared.update(with: snapshot, isActive: isActiveSnapshot)
        pruneTrackedSessions()
    }

    func handleRuntimeDisconnected() {
        for task in pendingRestTasks.values {
            task.cancel()
        }
        pendingRestTasks.removeAll()
        sessionStates.removeAll()
        sessionActivities.removeAll()
        sessionTurnStates.removeAll()
        sessionAwaitReasons.removeAll()
        sessionLastActivity = sessionTokens.mapValues(\.timestamp)
        activeStateEnteredAt = nil
        activeSessionId = bestSessionId()
        applyActiveSession()
    }

    private func applyActiveSession() {
        guard let activeSessionId else {
            sessionState = .notLoaded
            activityKind = .none
            turnState = nil
            awaitReason = nil
            latestToken = nil
            return
        }

        sessionState = sessionStates[activeSessionId] ?? .notLoaded
        activityKind = sessionActivities[activeSessionId] ?? .none
        turnState = sessionTurnStates[activeSessionId]
        awaitReason = sessionAwaitReasons[activeSessionId]
        latestToken = sessionTokens[activeSessionId]
        TokenStore.shared.showSession(activeSessionId, latest: sessionTokens[activeSessionId])
    }

    private func bestSessionId() -> String? {
        let sessionIds = Set(sessionStates.keys)
            .union(sessionTokens.keys)
            .union(sessionLastActivity.keys)

        return sessionIds.max { lhs, rhs in
            let lhsState = sessionStates[lhs] ?? .notLoaded
            let rhsState = sessionStates[rhs] ?? .notLoaded

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

        return !(sessionStates[activeSessionId] ?? .notLoaded).shouldPromoteToFront
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
            sessionActivities.removeValue(forKey: item.key)
            sessionTurnStates.removeValue(forKey: item.key)
            sessionAwaitReasons.removeValue(forKey: item.key)
            sessionTokens.removeValue(forKey: item.key)
            sessionLastActivity.removeValue(forKey: item.key)
            pendingRestTasks[item.key]?.cancel()
            pendingRestTasks.removeValue(forKey: item.key)
        }
    }
}

private extension CodexSessionState {
    var isRestingState: Bool {
        switch self {
        case .notLoaded, .idle:
            return true
        case .running, .waitingForInput, .readyForReview, .error:
            return false
        }
    }

    var shouldPromoteToFront: Bool {
        switch self {
        case .running, .waitingForInput, .readyForReview:
            return true
        case .notLoaded, .idle, .error:
            return false
        }
    }

    var displayPriority: Int {
        switch self {
        case .waitingForInput:
            return 5
        case .readyForReview:
            return 4
        case .running:
            return 3
        case .error:
            return 2
        case .idle:
            return 1
        case .notLoaded:
            return 0
        }
    }
}
