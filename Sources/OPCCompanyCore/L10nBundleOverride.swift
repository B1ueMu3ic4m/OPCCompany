import Foundation

#if canImport(ObjectiveC)
import ObjectiveC

/// Makes Bundle.main .strings lookups follow the in-app language selection.
///
/// SwiftUI `Text("literal")` resolves LocalizedStringKey through
/// Bundle.main.localizedString — which normally follows the SYSTEM language,
/// not SwiftUI's .locale environment. We swizzle the main bundle's class so
/// lookups consult the lproj sub-bundle chosen by the user.
public enum L10nBundleOverride {
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var active: Bundle?
    /// Resolved selection of the last `select(_:)` call; nil under `.system`.
    /// Internal: the test harness's Bundle.main carries no lproj resources, so
    /// `active` is not observable there — tests assert this instead.
    nonisolated(unsafe) static var selected: AppLanguage?

    private final class OverrideBundle: Bundle, @unchecked Sendable {
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            if let b = L10nBundleOverride.active {
                return b.localizedString(forKey: key, value: value ?? key, table: tableName)
            }
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }

    /// Swizzle once at app start.
    public static func install() {
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, OverrideBundle.self)
    }

    /// Point lookups at the sub-bundle for the selected language.
    /// zh mode uses the identity table; nil (system) keeps stock behavior.
    public static func select(_ language: AppLanguage) {
        switch language.resolving() {
        case .english:
            selected = .english
            active = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap { Bundle(path: $0) }
        case .simplifiedChinese:
            selected = .simplifiedChinese
            active = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap { Bundle(path: $0) }
        case .system:
            selected = nil
            active = nil
        }
    }
}

#else
// ═══ Windows / platforms without the ObjC runtime ═══
//
// The swizzle exists ONLY to redirect SwiftUI `Text("literal")` lookups
// through Bundle.main — there is no SwiftUI on Windows, so the mechanism is
// moot. Dynamic strings keep working through the platform-neutral path
// (`"中文".L()` → AppStrings.sessionLanguage, set by L10nEnvironment right
// after this call). Same public API so L10nEnvironment compiles unchanged;
// `selected` is recorded for behavioral parity and testability.
// Tracked as issue #10 (replace the swizzle with a neutral lookup).
public enum L10nBundleOverride {
    nonisolated(unsafe) static var selected: AppLanguage?

    public static func install() { /* no-op: no Bundle consumers on this platform */ }

    public static func select(_ language: AppLanguage) {
        switch language.resolving() {
        case .english: selected = .english
        case .simplifiedChinese: selected = .simplifiedChinese
        case .system: selected = nil
        }
    }
}
#endif
