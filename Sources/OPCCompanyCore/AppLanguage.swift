import Foundation

/// Application UI language, selectable in-app (System / 简体中文 / English).
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    /// Label shown in the language picker. The System row shows the language
    /// it currently resolves to, so "Auto" never surprises the user
    /// (system preferred languages may not match what the user assumes).
    public var displayName: String {
        switch self {
        case .system: return "跟随系统 / Auto — \(resolving().displayName)"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    /// Effective language for a given locale (used by `.system`).
    public func resolving(locale: Locale = .current) -> AppLanguage {
        guard self == .system else { return self }
        let code = locale.language.languageCode?.identifier ?? "en"
        return code.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}
