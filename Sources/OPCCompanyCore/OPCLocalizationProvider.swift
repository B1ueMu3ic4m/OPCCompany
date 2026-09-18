import Foundation

// ═══ Issue #10 (M0): portable i18n lookup, one call-site door ═══
//
// Two surfaces used to switch the in-app language by NAME: the ObjC
// bundle swizzle (redirects SwiftUI `Text("literal")` through the
// selected lproj) and `AppStrings.sessionLanguage` (the reverse table
// behind `"中文".L()`). The swizzle's platform coupling was already lawful
// — confined behind the ObjC-import guard since PR #7, pinned by the
// confinement test. THIS protocol is the seam #10 asked for:
// every switch on every platform now speaks through one door, and the
// door picks the mechanism. A new surface can no longer forget one side.
//
// Text("literal") migration verdict (#10's second half): we deliberately
// do NOT rewrite the ~100 SwiftUI call sites to `Text("中文".L())`. The
// swizzle is confined, behavior-tested and cost-free where it exists;
// off-Apple there is no SwiftUI, so the mechanism is moot — the Flutter
// shell and CLI never resolve these strings. What the protocol guarantees
// instead: a future platform with SwiftUI but WITHOUT ObjC plugs a
// dictionary-backed provider into `install()` here — zero call-site
// churn, one place to decide.
//
// Adding a surface: GUI/Apple keeps `Text("中文")` (swizzle path, or this
// protocol's no-op on non-ObjC); dynamic strings anywhere: `.L()`.

/// One door for both halves of an in-app language switch.
public protocol OPCLocalizationProviding: AnyObject {
    /// Redirect localized-string lookups at app start (idempotent).
    func install()
    /// Point every future lookup at `language` (resolved on the other side).
    func select(_ language: AppLanguage)
}

/// Default door: the ObjC bundle swizzle on Apple platforms (the only
/// place the ObjC runtime import may live — guard test enforces), and a
/// select-only observer elsewhere (recorded for behavioral parity and
/// testability, exactly like the old `#else` twin).
public enum OPCLocalization {
    private final class Door: OPCLocalizationProviding, @unchecked Sendable {
        func install() { L10nBundleOverride.install() }
        func select(_ language: AppLanguage) { L10nBundleOverride.select(language) }
    }

    nonisolated(unsafe) private static var door: OPCLocalizationProviding = Door()

    /// Last explicit selection (nil under `.system`) — same observable
    /// contract the old direct calls had.
    public static var selected: AppLanguage? { L10nBundleOverride.selected }

    /// Test/future-platform seam: swap the whole mechanism in one write.
    static func use(_ provider: OPCLocalizationProviding) { door = provider }
    static var currentDoorForTesting: OPCLocalizationProviding { door }

    public static func install() { door.install() }
    public static func select(_ language: AppLanguage) { door.select(language) }
}
