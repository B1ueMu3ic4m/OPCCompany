import SwiftUI

/// Observable app language state with persistence.
/// Resolution order: explicit initial value > OPC_FORCE_LANGUAGE env (tests/CI)
/// > persisted UserDefaults > .system.
@MainActor
public final class L10nEnvironment: ObservableObject {
    public static let shared = L10nEnvironment()

    @Published public var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            Self.persist(language)
            Self.applySideEffects(language)
        }
    }

    private static let storageKey = "opc.appLanguage.v1"

    public init(initial: AppLanguage? = nil) {
        self.language = initial ?? Self.load()
        // didSet does not fire during init; apply once explicitly so the
        // swizzled bundle and store-string language match the starting value.
        Self.applySideEffects(self.language)
    }

    /// Switch-side effects must run synchronously at the moment the value is
    /// written — BEFORE SwiftUI re-renders — so the `.id(resolved)` tree rebuild
    /// resolves Text() lookups against the newly selected lproj bundle. Running
    /// them from Picker.onChange instead made the rebuild use the stale bundle
    /// (UI showed the previous language / mixed Chinese and English).
    private static func applySideEffects(_ language: AppLanguage) {
        L10nBundleOverride.select(language)
        AppStrings.sessionLanguage = language.resolving()
    }

    private static func load() -> AppLanguage {
        if let forced = ProcessInfo.processInfo.environment["OPC_FORCE_LANGUAGE"],
           let lang = AppLanguage(rawValue: forced) {
            return lang
        }
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return .system
    }

    private static func persist(_ value: AppLanguage) {
        UserDefaults.standard.set(value.rawValue, forKey: storageKey)
    }
}

/// SwiftUI environment plumbing so every view can read the active language.
private struct AppLanguageEnvironmentKey: EnvironmentKey {
    public static let defaultValue: AppLanguage = .system
}

extension EnvironmentValues {
    public var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
