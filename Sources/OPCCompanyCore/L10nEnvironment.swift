import SwiftUI

/// Observable app language state with persistence.
/// Resolution order: explicit initial value > OPC_FORCE_LANGUAGE env (tests/CI)
/// > persisted UserDefaults > .system.
@MainActor
public final class L10nEnvironment: ObservableObject {
    public static let shared = L10nEnvironment()

    @Published public var language: AppLanguage {
        didSet { Self.persist(language) }
    }

    private static let storageKey = "opc.appLanguage.v1"

    public init(initial: AppLanguage? = nil) {
        self.language = initial ?? Self.load()
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
