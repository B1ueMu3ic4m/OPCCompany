#if !canImport(Security) && canImport(CWinDPAPI)
import CWinDPAPI
import Foundation

// ═══ Windows secret store: DPAPI (issue #11) ═══
//
// API keys are encrypted with CryptProtectData bound to the CURRENT USER —
// the same guarantee the macOS Keychain gives (this-user, this-machine).
// Ciphertext lands in <support>/secrets/<account>.blob with the account UUID
// as filename; a per-app entropy value is mixed into the DPAPI derivation so
// a blob copied from another app's DPAPI usage cannot be opened by mistake.
//
// The KeychainStore.swift `#else` branch routes OPCKeychainSecretStore to
// this type when this module is present; where neither Security nor
// CWinDPAPI exists (Linux dev boxes), the fail-closed stub remains.
//
// All Win32 buffer pointers are taken via withUnsafeMutableBufferPointer so
// they stay valid for the duration of the (synchronous) Crypt* call — a raw
// `&localVar` stored in a struct and passed on the NEXT statement is only
// guaranteed valid within a single call in Swift and would be UB here.
public enum OPCDPAPIError: Error { case protectFailed(UInt32), unprotectFailed(UInt32) }

public struct OPCDPAPISecretStore: OPCSecretStoreProtocol {
    public init() {}

    /// App-domain entropy — NOT a secret (it's in the binary); its job is
    /// channel binding: blobs from other apps that also use DPAPI cannot be
    /// silently opened by us or vice versa.
    private static let entropy = Array(Data("OPCCompany.AgentAPIKey.v1".utf8))

    /// DPAPI's description parameter is a wide string (LPCWSTR = UTF-16,
    /// null-terminated). Passing a Swift String fails to compile on Windows
    /// (spike #7 caught this).
    private static let dpapiDescription: [UInt16] = Array("OPCCompany.AgentAPIKey".utf16) + [0]

    private static func secretsDir(support: URL, fileManager: FileManager) throws -> URL {
        let dir = support.appendingPathComponent("secrets", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// account is an agent UUID string — anything else maps to an empty base
    /// name (rejected on write via the caller's guard; load/delete get "" name
    /// which never matches a real .blob), so no caller can escape the secrets
    /// directory with "../" tricks regardless of discipline upstream.
    private static func blobURL(support: URL, account: String) -> URL {
        let name = UUID(uuidString: account) != nil ? account : ""
        return support.appendingPathComponent("secrets", isDirectory: true)
            .appendingPathComponent(name + ".blob")
    }

    private func protect(_ plain: [UInt8]) throws -> Data {
        var plainBuf = plain
        var entropyBuf = Self.entropy
        var outBlob = CRYPT_DATA_BLOB(cbData: 0, pbData: nil)
        let ok = plainBuf.withUnsafeMutableBufferPointer { pBuf in
            entropyBuf.withUnsafeMutableBufferPointer { eBuf in
                Self.dpapiDescription.withUnsafeBufferPointer { dBuf in
                    var inBlob = CRYPT_DATA_BLOB(cbData: DWORD(pBuf.count), pbData: pBuf.baseAddress)
                    var entropyBlob = CRYPT_DATA_BLOB(cbData: DWORD(eBuf.count), pbData: eBuf.baseAddress)
                    return CryptProtectData(&inBlob, dBuf.baseAddress, &entropyBlob,
                                            nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &outBlob)
                }
            }
        }
        guard ok else { throw OPCDPAPIError.protectFailed(GetLastError()) }
        defer { LocalFree(outBlob.pbData) }
        return Data(bytes: outBlob.pbData, count: Int(outBlob.cbData))
    }

    private func unprotect(_ cipher: Data) throws -> [UInt8] {
        var cipherBuf = [UInt8](cipher)
        var entropyBuf = Self.entropy
        var outBlob = CRYPT_DATA_BLOB(cbData: 0, pbData: nil)
        let ok = cipherBuf.withUnsafeMutableBufferPointer { cBuf in
            entropyBuf.withUnsafeMutableBufferPointer { eBuf in
                var inBlob = CRYPT_DATA_BLOB(cbData: DWORD(cBuf.count), pbData: cBuf.baseAddress)
                var entropyBlob = CRYPT_DATA_BLOB(cbData: DWORD(eBuf.count), pbData: eBuf.baseAddress)
                return CryptUnprotectData(&inBlob, nil, &entropyBlob,
                                          nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), &outBlob)
            }
        }
        guard ok else { throw OPCDPAPIError.unprotectFailed(GetLastError()) }
        defer { LocalFree(outBlob.pbData) }
        return [UInt8](UnsafeBufferPointer(start: outBlob.pbData, count: Int(outBlob.cbData)))
    }

    public func saveSecret(_ value: String, account: String) -> OPCSecretStatus {
        guard UUID(uuidString: account) != nil else { return .emptyValue }
        guard !value.isEmpty, let plain = value.data(using: .utf8) else { return .emptyValue }
        do {
            let support = CompanyPersistence.supportDirectory
            _ = try Self.secretsDir(support: support, fileManager: .default)  // mkdir -p
            let blob = try protect([UInt8](plain))
            try blob.write(to: Self.blobURL(support: support, account: account), options: [.atomic])
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
