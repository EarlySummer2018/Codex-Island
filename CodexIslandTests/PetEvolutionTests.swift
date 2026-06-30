import XCTest
@testable import CodexIsland

final class PetLevelCurveTests: XCTestCase {
    func testTokensRequired() {
        XCTAssertEqual(PetLevelCurve.tokensRequired(for: 0), 0)
        XCTAssertEqual(PetLevelCurve.tokensRequired(for: 100), 109_500_000_000)
    }

    func testLevelForHeavyOneDayUsage() {
        XCTAssertEqual(PetLevelCurve.level(for: 300_000_000), 5)
    }

    func testLevelClampsToSupportedRange() {
        XCTAssertEqual(PetLevelCurve.level(for: -1), 0)
        XCTAssertEqual(PetLevelCurve.level(for: Int64.max), 100)
        XCTAssertEqual(PetLevelCurve.tokensRequired(for: -12), 0)
        XCTAssertEqual(PetLevelCurve.tokensRequired(for: 120), 109_500_000_000)
    }

    func testMaxLevelProgressIsComplete() {
        let maxTokens = PetLevelCurve.tokensRequired(for: 100)
        XCTAssertEqual(PetLevelCurve.progress(for: maxTokens), 1)
        XCTAssertNil(PetLevelCurve.tokensToNextLevel(for: maxTokens))
    }
}

@MainActor
final class PetEvolutionStoreTests: XCTestCase {
    func testFirstHistoricalSnapshotImportsExistingTokensWithoutReplayTriggers() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 20_000_000_000))

        XCTAssertEqual(store.level, 42)
        XCTAssertEqual(store.earnedTokens, 20_000_000_000)
        XCTAssertEqual(store.currentForm, .spark)
        XCTAssertNil(store.feedTrigger)
        XCTAssertNil(store.levelUpTrigger)
    }

    func testSubsequentTokensAdvanceFromHistoricalTotal() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 1_000_000_000))
        store.update(with: snapshot(totalTokens: 1_300_000_000))

        XCTAssertEqual(store.earnedTokens, 1_300_000_000)
        XCTAssertEqual(store.level, 10)
        XCTAssertEqual(store.currentForm, .antenna)
        XCTAssertNotNil(store.levelUpTrigger)
    }

    func testSnapshotDecreaseDoesNotDeductOrDoubleCount() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 1_000_000_000))
        store.update(with: snapshot(totalTokens: 1_300_000_000))
        store.update(with: snapshot(totalTokens: 1_200_000_000))
        store.update(with: snapshot(totalTokens: 1_350_000_000))

        XCTAssertEqual(store.earnedTokens, 1_350_000_000)
        XCTAssertEqual(store.level, 11)
    }

    func testExistingBaselineOnlyInstallImportsHistoricalTotal() {
        let defaults = makeDefaults()
        defaults.set(Int64(1_000_000_000), forKey: "CodexIsland.PetEvolutionV2.lastObservedTotalTokens")
        let store = PetEvolutionStore(defaults: defaults)

        store.update(with: snapshot(totalTokens: 1_000_000_000))

        XCTAssertEqual(store.earnedTokens, 1_000_000_000)
        XCTAssertEqual(store.level, 9)
        XCTAssertNil(store.levelUpTrigger)
    }

    func testFeedTriggerFiresOnTwentyFiveMillionMilestones() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 0))
        XCTAssertNil(store.feedTrigger)

        store.update(with: snapshot(totalTokens: 25_000_000))
        let firstTrigger = store.feedTrigger
        XCTAssertNotNil(firstTrigger)

        store.update(with: snapshot(totalTokens: 49_999_999))
        XCTAssertEqual(store.feedTrigger, firstTrigger)

        store.update(with: snapshot(totalTokens: 50_000_000))
        XCTAssertNotEqual(store.feedTrigger, firstTrigger)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CodexIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func snapshot(totalTokens: Int) -> GlobalTokenUsageSnapshot {
        GlobalTokenUsageSnapshot(
            type: "global_token_usage",
            totalInput: totalTokens,
            totalCachedInput: 0,
            totalOutput: 0,
            totalReasoning: 0,
            totalTokens: totalTokens,
            sessionCount: 1,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
