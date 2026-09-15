import Foundation

// ═══ M0/M3: cross-process write guard, now a core-layer service ═══
//
// Extracted verbatim from the CLI's private helper (M3 prep): every
// snapshot-writing *external* entry point — the `opc` CLI today, the Flutter
// shell's FFI bridge tomorrow — must pass through this guard before saving.
// One rule, one place: the CLI can no longer drift from the bridge because
// they share this implementation.
//
// The desktop app itself does NOT call this guard: it is the state the guard
// detects. (A future in-app "safe mode" could, if multi-surface editing ever
// ships.)
//
// Detection contract (unchanged from the CLI audit, 2026-09-09):
// - pgrep -x OPCCompany (exact comm name; the CLI's own name is `opc`, so
//   sequential CLI runs never self-match);
// - on platforms without pgrep the check no-ops — a real lock file arrives
//   with the Flutter shell (this milestone), since only then does a
//   second persistent writer exist on those platforms;
// - override: OPC_ALLOW_CONCURRENT_WRITE=1 (headless CI, scripted setups).

public struct OPCConcurrentWriterError: Error, Equatable {
    public let message: String
    public init(message: String) { self.message = message }
}

public enum OPCWriteGuard {
    /// Throws when another snapshot writer appears active. Callers translate
    /// the error into their own surface (CLI: stderr+exit 1; FFI: errno-ish
    /// return code + message pointer).
    public static func ensureExclusiveAccess(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if environment["OPC_ALLOW_CONCURRENT_WRITE"] == "1" { return }
        // #9 seam: the launch lives in OPCProcessRunner (pgrep is absent on
        // Windows → runQuietly returns nil → "no detection available", which
        // matches the documented no-op contract and the old throw-to-false).
        let status = OPCProcessRunner.runQuietly(
            executable: "/usr/bin/pgrep",
            arguments: ["-x", "OPCCompany"])
        let appRunning = status == 0
        if appRunning {
            throw OPCConcurrentWriterError(message:
                "OPCCompany.app is running — the desktop app shares this snapshot "
                + "and last writer wins. Quit it first, or set OPC_ALLOW_CONCURRENT_WRITE=1 if you are "
                + "sure nothing else writes.")
        }
    }
}
