import Foundation

/// Per-module string tables. Each module owns its own namespace file so
/// parallel localization work never conflicts. Fill ONLY your own table.
/// Rule: `zh` values must be byte-identical to the original Chinese copy.

enum StringsTableV1 {
    static let tables: (zh: [String: String], en: [String: String]) = ([:], [:])
}

enum StringsTableV2 {
    static let tables: (zh: [String: String], en: [String: String]) = ([:], [:])
}

enum StringsTableV3 {
    static let tables: (zh: [String: String], en: [String: String]) = ([:], [:])
}

enum StringsTableStore {
    static let tables: (zh: [String: String], en: [String: String]) = ([:], [:])
}
