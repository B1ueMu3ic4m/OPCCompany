import Foundation

/// Reverse-lookup localization for dynamic strings (enum titles, store markers).
/// The string itself is the Chinese source copy; `zh(lang)` returns its English
/// counterpart when available, or the string unchanged.
public extension String {
    /// Localize a Chinese source string for the given language.
    /// Chinese/system -> unchanged; English -> table hit or unchanged.
    func zh(_ language: AppLanguage) -> String {
        switch language.resolving() {
        case .simplifiedChinese, .system:
            return self
        case .english:
            return AppStrings.enByZh[self] ?? self
        }
    }

    /// Session-localized variant used inside enum titles and store-generated
    /// strings. Under XCTest `sessionLanguage` is forced to Chinese so the
    /// suite stays deterministic.
    func L() -> String {
        zh(AppStrings.sessionLanguage)
    }
}

extension AppStrings {
    /// Both language forms of a Chinese source string — for MATCHING persisted
    /// data (titles, prefixes, signals) that may have been stored in either
    /// language. Never use for display; use `.L()` for display instead.
    static func forms(_ zh: String) -> [String] {
        guard let en = AppStrings.enByZh[zh], en != zh else { return [zh] }
        return [zh, en]
    }

    /// zh -> en map: generated table first, then hand-written key tables.
    static let enByZh: [String: String] = {
        var map: [String: String] = AppStringsGenerated.zhToEn
        for table in tables {
            for (key, zhValue) in table.zh {
                if let en = table.en[key], map[zhValue] == nil {
                    map[zhValue] = en
                }
            }
        }
        return map
    }()
}
