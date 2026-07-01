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

    func testFurinaFormsUnlockEveryTenLevelsThroughFullPink() {
        XCTAssertEqual(PetForm.form(for: 0), .original)
        XCTAssertEqual(PetForm.form(for: 9), .original)
        XCTAssertEqual(PetForm.form(for: 10), .shoesPink)
        XCTAssertEqual(PetForm.form(for: 20), .legsPink)
        XCTAssertEqual(PetForm.form(for: 30), .capePink)
        XCTAssertEqual(PetForm.form(for: 40), .skirtPink)
        XCTAssertEqual(PetForm.form(for: 50), .sleevesPink)
        XCTAssertEqual(PetForm.form(for: 60), .topPink)
        XCTAssertEqual(PetForm.form(for: 70), .ornamentRose)
        XCTAssertEqual(PetForm.form(for: 80), .hatPink)
        XCTAssertEqual(PetForm.form(for: 90), .hairPink)
        XCTAssertEqual(PetForm.form(for: 100), .fullPink)
        XCTAssertEqual(PetForm.form(for: 120), .fullPink)
    }

    func testFurinaRecolorPartsAdvanceOnePartAtATime() {
        XCTAssertEqual(PetForm.shoesPink.furinaRecolorParts, [.shoes])
        XCTAssertEqual(PetForm.legsPink.furinaRecolorParts, [.shoes, .legs])
        XCTAssertTrue(PetForm.hatPink.furinaRecolorParts.contains(.hat))
        XCTAssertFalse(PetForm.hatPink.furinaRecolorParts.contains(.hairTips))
        XCTAssertTrue(PetForm.hairPink.furinaRecolorParts.contains(.hairTips))
        XCTAssertEqual(PetForm.fullPink.furinaRecolorParts, PetForm.hairPink.furinaRecolorParts)
    }
}

@MainActor
final class PetEvolutionStoreTests: XCTestCase {
    func testFirstHistoricalSnapshotImportsExistingTokensWithoutReplayTriggers() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 20_000_000_000))

        XCTAssertEqual(store.level, 42)
        XCTAssertEqual(store.earnedTokens, 20_000_000_000)
        XCTAssertEqual(store.currentForm, .skirtPink)
        XCTAssertNil(store.feedTrigger)
        XCTAssertNil(store.levelUpTrigger)
    }

    func testSubsequentTokensAdvanceFromHistoricalTotal() {
        let store = PetEvolutionStore(defaults: makeDefaults())

        store.update(with: snapshot(totalTokens: 1_000_000_000))
        store.update(with: snapshot(totalTokens: 1_300_000_000))

        XCTAssertEqual(store.earnedTokens, 1_300_000_000)
        XCTAssertEqual(store.level, 10)
        XCTAssertEqual(store.currentForm, .shoesPink)
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
