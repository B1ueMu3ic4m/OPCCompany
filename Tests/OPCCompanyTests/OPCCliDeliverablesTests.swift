import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc deliverables` (v0.7.0 "the delivery shelf"):
// real .build/debug/opc, suite support dir seeded in-process, state-
// neutral restore. Pins: both verdict marks reach the terminal ([OK] for
// a path that EXISTS, [MISSING] for a claim whose file is gone/never
// was), the missing-tally line, truncation honesty, and the pure-read
// promise (snapshot bytes must not move).

private var cliBinaryURL: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc")
}

private func runCLI(_ args: [String], supportDir: URL) throws
    -> (rc: Int32, out: String, err: String)
{
    let process = Process()
    process.executableURL = cliBinaryURL
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["OPC_COMPANY_SUPPORT_DIR"] = supportDir.path
    env["OPC_ALLOW_CONCURRENT_WRITE"] = "1"
    process.environment = env
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    let read: (Pipe) -> String = { pipe in
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
               encoding: .utf8) ?? ""
    }
    return (process.terminationStatus, read(out), read(err))
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliDeliverablesStampsLiveVerdictsAndNeverWrites() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-shelf-cli-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: scratch)
        if let priorBytes {
            try? priorBytes.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
    }
    try FileManager.default.createDirectory(at: scratch,
                                            withIntermediateDirectories: true)
    let realFile = scratch.appendingPathComponent("handed-over.md")
    try "shipped".data(using: .utf8)!.write(to: realFile)

    // Seed: one TRUE delivery (file written NOW) + one PHANTOM (never was).
    // createdAt pinned far apart — ordering assertions must not ride luck.
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    store.artifacts.append(ArtifactRecord(productID: pid, kind: .report,
        title: "真交付", path: realFile.path, summary: "s1",
        createdAt: base))
    store.artifacts.append(ArtifactRecord(productID: pid, kind: .source,
        title: "幽灵交付", path: scratch.appendingPathComponent("ghost.rs").path,
        summary: "s2", createdAt: base.addingTimeInterval(3600)))
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let d = try runCLI(["deliverables"], supportDir: supportDir)
    #expect(d.rc == 0, "deliverables must exit 0; got: \(d.err)")
    #expect(d.out.contains("[OK]"), "the real file must print the OK mark: \(d.out)")
    #expect(d.out.contains("真交付") && d.out.contains("[MISSING]"),
            "both rows print, the phantom must be caught: \(d.out)")
    let ghostLine = try #require(d.out.split(separator: "\n")
        .first { $0.contains("幽灵交付") })
    #expect(ghostLine.contains("[MISSING]"),
            "MISSING mark must ride the ghost's OWN row: \(ghostLine)")
    #expect(d.out.contains("1 of 2 recorded deliveries have NO file on disk"),
            "the tally line must count the ghost: \(d.out)")

    // the verdict is LIVE, not serialized: delete the real file, re-ask
    try FileManager.default.removeItem(at: realFile)
    let after = try runCLI(["deliverables"], supportDir: supportDir)
    let realLine = try #require(after.out.split(separator: "\n")
        .first { $0.contains("真交付") })
    #expect(realLine.contains("[MISSING]"),
            "a file deleted after delivery must flip the row — the shelf answers NOW, not at record time: \(realLine)")
    #expect(!after.out.contains("[OK]"),
            "once BOTH files are gone no row may keep an OK mark: \(after.out)")
    #expect(after.out.contains("2 of 2 recorded deliveries"),
            "tally re-counts on the same data")

    // truncation says what it truncated; junk counts refuse loudly
    let top = try runCLI(["deliverables", "1"], supportDir: supportDir)
    #expect(top.out.contains("Deliverables (1 of 2)"))
    for bad in ["0", "xyz"] {
        let r = try runCLI(["deliverables", bad], supportDir: supportDir)
        #expect(r.rc != 0, "junk count \(bad) must NOT exit 0")
        #expect((r.out + r.err).contains("usage: opc deliverables"))
    }

    // pure-read promise: nothing above moved the snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "deliverables must never write company state")
}
