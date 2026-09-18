import Foundation
import Testing

@testable import OPCCompanyCore

// Issue #10: the protocol door must actually be the door — every switch
// half (bundle redirect + selected record) rides OPCLocalization, and a
// future platform could replace the mechanism with one `use()` call.

private final class RecordingProvider: OPCLocalizationProviding, @unchecked Sendable {
    var installs = 0
    var selections: [AppLanguage] = []
    func install() { installs += 1 }
    func select(_ language: AppLanguage) { selections.append(language) }
}

@Test func localizationSwitchRoutesThroughTheOneDoor() {
    let fake = RecordingProvider()
    let real = OPCLocalization.currentDoorForTesting
    defer { OPCLocalization.use(real) }  // never leak the fake into other tests
    OPCLocalization.use(fake)

    OPCLocalization.install()
    OPCLocalization.select(.english)
    OPCLocalization.select(.simplifiedChinese)

    #expect(fake.installs == 1)
    #expect(fake.selections == [.english, .simplifiedChinese])
}

@Test @MainActor
func environmentSideEffectsStillRideTheRealDoor() {
    // Behavior pin (unchanged from the pre-#10 world): a language write on
    // L10nEnvironment reaches the DEFAULT door synchronously — here via
    // the selected record the real door keeps off-Apple and in XCTest.
    let env = L10nEnvironment(initial: .simplifiedChinese)
    env.language = .english
    let en = (AppStrings.sessionLanguage, OPCLocalization.selected)
    // restore explicitly to Chinese — ending on .system would leave the
    // GLOBAL sessionLanguage following the test-runner locale and poison
    // every later test that asserts Chinese literals (learned the hard
    // way: 265 failures from exactly that, in one run).
    env.language = .simplifiedChinese
    let zh = (AppStrings.sessionLanguage, OPCLocalization.selected)
    #expect(en.0 == .english && en.1 == .english)
    #expect(zh.0 == .simplifiedChinese && zh.1 == .simplifiedChinese,
            "the door must reach the SAME state the direct calls used to")
}
