import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc catchup` (v0.11.0 "the catch-up"): real
// .build/debug/opc, suite support dir seeded in-process, state-neutral
// restore. Pins: the page prints whole (every section, in order), the
// 25-hour-old event stays OUT of the traffic window, a ghost delivery
// is named as MISSING with its path, junk arguments are refused, and
// the pure-read promise holds (snapshot bytes must not move).

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
@MainActor func cliCatchupPrintsWholePageAndNeverWrites() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-catchup-\(UUID().uuidString)")
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
    let realFile = scratch.appendingPathComponent("ship.md")
    try "shipped".data(using: .utf8)!.write(to: realFile)

    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活",
                     detail: "d", createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .taskCreated, title: "旧活",
                     detail: "d", createdAt: now.addingTimeInterval(-25 * 3600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: store.agents.first!.id,
                        title: "等批", reason: "r", status: .pending),
    ]
    store.artifacts = [
        ArtifactRecord(productID: pid, kind: .report, title: "幽灵交付",
                       path: scratch.appendingPathComponent("ghost.md").path,
                       summary: "s", createdAt: now.addingTimeInterval(-800)),
    ]
    store.saveSnapshot()
    // pure-read baseline = the SEEDED state (priorBytes restores the
    // pre-seed state in defer; the comparison below must use this one)
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["catchup"], supportDir: supportDir)
    #expect(s.rc == 0, "read must exit 0: \(s.err)")

    // the page prints WHOLE, sections in contract order
    var cursor = s.out.startIndex
    for marker in ["# Catch-up — ", "## Traffic (last 24h)", "## Who did what",
                   "## Stuck (parked over 30 min)", "## Waiting on you (1)",
                   "## Shelf integrity (last 24h)", "Pure read — this page wrote nothing."] {
        let range = s.out.range(of: marker, range: cursor..<s.out.endIndex)
        #expect(range != nil, "CLI page out of order or missing: \(marker)")
        if let range { cursor = range.upperBound }
    }
    // window discipline: the 25h-old creation stays OUT
    let traffic = s.out.slice(from: "## Traffic", to: "## Who")
    #expect(traffic.contains("new work: 1"))
    // shelf discipline: the ghost is named with its path
    #expect(s.out.contains("MISSING: 幽灵交付"))
    #expect(s.out.contains("ghost.md"))
    // desk: the pending approval is on the page
    #expect(s.out.contains("等批"))
    // pure read: bytes must not move
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "pure read: catchup never moves state bytes")

    // junk arguments refuse loudly with the usage line
    let bad = try runCLI(["catchup", "abc"], supportDir: supportDir)
    #expect(bad.rc != 0)
    #expect(bad.err.contains("usage: opc catchup"))
}

private extension String {
    func slice(from: String, to: String) -> String {
        guard let a = range(of: from), let b = range(of: to, range: a.upperBound..<endIndex)
        else { return "" }
        return String(self[a.upperBound..<b.lowerBound])
    }
}
