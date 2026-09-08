import Foundation

#if canImport(Security)
// Bridge between the platform-neutral `OPCSecretStatus` and the raw
// `OSStatus` codes this store produces — CompanyStore and the tests speak one
// language while Keychain stays the only Security-typed file.
extension OPCSecretStatus {
    init(_ status: OSStatus) { self.rawValue = status }
    var osStatus: OSStatus { rawValue }
}

public enum OPCKeychainStore {
    private static let service = "OPCCompany.AgentAPIKey"

    /// 把 API Key 写入 Keychain，并把 SecItemUpdate / SecItemAdd 的真实 OSStatus 透传给调用方。
    ///
    /// 旧实现把所有错误都吞掉，导致 disk full / Keychain 被锁 / 沙箱权限不足等失败时
    /// 调用方完全无感（CompanyStore 在快照前会立即把内存中的 apiKey 清空），下一次启动
    /// API 员工就会因为 Key 丢失而无法工作，但老板侧没有任何风险事件提示。
    ///
    /// 返回约定：
    /// - `errSecSuccess`：写入成功（更新或新增）。
    /// - `errSecParam`：value 为空或无法 utf8 编码 —— 视为「没东西可写」，调用方按需忽略。
    /// - 其他 `OSStatus`：底层 SecItem API 返回的真实错误码，调用方需要把它转成可见提示。
    @discardableResult
    public static func saveAPIKey(_ value: String, agentID: UUID) -> OSStatus {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return errSecParam }
        let account = agentID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return errSecSuccess }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                // 罕见竞态：另一个进程在 update 与 add 之间写入了同 service+account 项。
                // 删掉残留再 add 一次，把最终状态作为权威结果上报。
                SecItemDelete(query as CFDictionary)
                return SecItemAdd(addQuery as CFDictionary, nil)
            }
            return addStatus
        }

        return updateStatus
    }

    public static func loadAPIKey(agentID: UUID) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: agentID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return value
    }

    public static func deleteAPIKey(agentID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: agentID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Instance-based adapter so the Keychain can serve the platform-neutral
/// `OPCSecretStoreProtocol` (caseless enums cannot be instantiated).
public struct OPCKeychainSecretStore: OPCSecretStoreProtocol {
    public init() {}

    public func saveSecret(_ value: String, account: String) -> OPCSecretStatus {
        guard let id = UUID(uuidString: account) else { return .emptyValue }
        return OPCSecretStatus(OPCKeychainStore.saveAPIKey(value, agentID: id))
    }

    public func loadSecret(account: String) -> String {
        guard let id = UUID(uuidString: account) else { return "" }
        return OPCKeychainStore.loadAPIKey(agentID: id)
    }

    public func deleteSecret(account: String) {
        guard let id = UUID(uuidString: account) else { return }
        OPCKeychainStore.deleteAPIKey(agentID: id)
    }
}

#else
// ═══ Windows / other platforms without Security.framework ═══
//
// FAIL-CLOSED placeholder: saving a secret REFUSES (authFailed) and loading
// returns empty, so the boss-facing risk event path (CompanyStore converts any
// non-success status into a visible warning) fires immediately instead of the
// app silently storing API keys in plaintext. Plaintext-at-rest is NOT an
// acceptable interim for a local-first app that holds paid API credentials —
// see SECURITY.md.
//
// The real Windows store (DPAPI via CryptProtectData, per-user profile) is
// tracked in issue #11 (good-first-issue). When it lands, it replaces this
// stub's bodies; the type name and protocol stay the same so no call site
// changes.
public struct OPCKeychainSecretStore: OPCSecretStoreProtocol {
    public init() {}

    public func saveSecret(_ value: String, account: String) -> OPCSecretStatus {
        .authFailed
    }

    public func loadSecret(account: String) -> String {
        ""
    }

    public func deleteSecret(account: String) {
        // nothing stored — no-op
    }
}
#endif
