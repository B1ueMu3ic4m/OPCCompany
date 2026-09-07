import Foundation

/// Platform-neutral result code for secret-store operations.
///
/// On Apple platforms the raw values mirror the underlying `OSStatus` codes
/// (0 = success, -50 = errSecParam, -25293 = errSecAuthFailed) so existing
/// diagnostics keep their meaning. On Windows the same codes are produced by
/// the DPAPI/file fallback store, keeping the boss-facing failure events
/// identical across platforms.
public struct OPCSecretStatus: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let success = OPCSecretStatus(rawValue: 0)
    /// Nothing to write (empty value / undecodable) — callers may ignore.
    public static let emptyValue = OPCSecretStatus(rawValue: -50)
    /// The platform secret store refused the operation (locked keychain,
    /// unavailable credential API, sandbox restriction).
    public static let authFailed = OPCSecretStatus(rawValue: -25293)

    public var isSuccess: Bool { self == .success }
}

/// Abstraction over the OS credential store.
///
/// Apple: `OPCKeychainStore` (Security.framework / Keychain Services).
/// Windows: `OPCFileSecretStore` (per-user profile directory, 0600-equivalent
/// ACL; DPAPI hardening is tracked in the Windows port RFC).
public protocol OPCSecretStoreProtocol: Sendable {
    func saveSecret(_ value: String, account: String) -> OPCSecretStatus
    func loadSecret(account: String) -> String
    func deleteSecret(account: String)
}

/// Where OPC persists its per-user support files, resolved once per platform.
///
/// Apple: `~/Library/Application Support/OPCCompany` (unchanged — existing
/// installs keep their data). Windows: `%APPDATA%\OPCCompany`.
public enum OPCAppPaths {
    public static func supportDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        #if os(Windows)
        if let appData = environment["APPDATA"] ?? environment["LocalAppData"] {
            return URL(fileURLWithPath: appData, isDirectory: true)
                .appendingPathComponent("OPCCompany", isDirectory: true)
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #else
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("OPCCompany", isDirectory: true) }
        #endif
    }
}
