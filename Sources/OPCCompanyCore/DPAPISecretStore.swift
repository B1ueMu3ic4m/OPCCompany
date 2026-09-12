#if !canImport(Security) && canImport(CWinDPAPI)
import CWinDPAPI
import Foundation

// ═══ Windows secret store: DPAPI (issue #11) ═══
//
// API keys are encrypted with CryptProtectData bound to the CURRENT USER —
// the same guarantee the macOS Keychain gives (this-user, this-machine).
// Ciphertext lands in <support>/secrets/<account>.blob with the account UUID
// as filename; a per-app entropy value (below) is mixed into the DPAPI
// derivation so a blob copied from another OPC build's directory cannot be
// opened by mistake.
//
// The KeychainStore.swift `#else` branch routes OPCKeychainSecretStore to
// this type when this module is present; where neither Security nor
// CWinDPAPI exists (Linux dev boxes), the fail-closed stub remains.
public enum OPCDPAPIError: Error { case protectFailed(UInt32), unprotectFailed(UInt32) }

public struct OPCDPAPISecretStore: OPCSecretStoreProtocol {
    public init() {}

    /// App-domain entropy — NOT a secret (it's in the binary); its job is
    /// channel binding: blobs from other apps that also use DPAPI cannot be
    /// silently opened by us or vice versa.
    private static let entropy = Array(Data("OPCCompany.AgentAPIKey.v1".utf8))

    private static func secretsDir(support: URL, fileManager: FileManager) throws -> URL {
        let dir = support.appendingPathComponent("secrets", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func blobURL(support: URL, account: String) -> URL {
        // account is an agent UUID string — reject anything that could escape
        // the secrets directory regardless of caller discipline.
        let isUUID = UUID(uuidString: account) != nil
        let name = isUUID ? account : ""
        return support.appendingPathComponent("secrets", isDirectory: true)
            .appendingPathComponent(name + ".blob")
    }

    private func protect(_ plain: [UInt8]) throws -> Data {
        var inBlob = CRYPT_DATA_BLOB(
            cbData: DWORD(plain.count),
            pbData: UnsafeMutablePointer(mutating: plain))
        var outBlob = CRYPT_DATA_BLOB(cbData: 0, pbData: nil)
        var entropyCopy = Self.entropy  // mutable copy; DPAPI takes it by pointer
        var entropyBlob = CRYPT_DATA_BLOB(cbData: DWORD(entropyCopy.count),
                                          pbData: &entropyCopy)
        let ok = CryptProtectData(&inBlob, "OPCCompany.AgentAPIKey",
                                  &entropyBlob, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN),
                                  &outBlob)
        guard ok else { throw OPCDPAPIError.protectFailed(GetLastError()) }
        defer { LocalFree(outBlob.pbData) }
        return Data(bytes: outBlob.pbData, count: Int(outBlob.cbData))
    }

    private func unprotect(_ cipher: Data) throws -> [UInt8] {
        var cipherCopy = [UInt8](cipher)
        var inBlob = CRYPT_DATA_BLOB(cbData: DWORD(cipherCopy.count),
                                     pbData: &cipherCopy)
        var outBlob = CRYPT_DATA_BLOB(cbData: 0, pbData: nil)
        var entropyCopy = Self.entropy
        var entropyBlob = CRYPT_DATA_BLOB(cbData: DWORD(entropyCopy.count),
                                          pbData: &entropyCopy)
        let ok = CryptUnprotectData(&inBlob, nil, &entropyBlob, nil, nil,
                                    DWORD(CRYPTPROTECT_UI_FORBIDDEN), &outBlob)
        guard ok else { throw OPCDPAPIError.unprotectFailed(GetLastError()) }
        defer { LocalFree(outBlob.pbData) }
        return [UInt8](UnsafeBufferPointer(start: outBlob.pbData, count: Int(outBlob.cbData)))
    }

    public func saveSecret(_ value: String, account: String) -> OPCSecretStatus {
        guard UUID(uuidString: account) != nil else { return .emptyValue }
        guard !value.isEmpty, let plain = value.data(using: .utf8) else { return .emptyValue }
        do {
            let support = CompanyPersistence.supportDirectory
            _ = try Self.secretsDir(support: support, fileManager: .default)  // mkdir
            let blob = try protect([UInt8](plain))
            try blob.write(to: blobURL(support: support, account: account),
                           options: [.atomic])
            return .success
        } catch {
            return .authFailed
        }
    }

    public func loadSecret(account: String) -> String {
        guard UUID(uuidString: account) != nil else { return "" }
        let url = Self.blobURL(support: CompanyPersistence.supportDirectory, account: account)
        guard let cipher = try? Data(contentsOf: url) else { return "" }
        guard let plain = try? unprotect(cipher) else { return "" }
        return String(decoding: plain, as: UTF8.self)
    }

    public func deleteSecret(account: String) {
        guard UUID(uuidString: account) != nil else { return }
        let url = Self.blobURL(support: CompanyPersistence.supportDirectory, account: account)
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
