import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc history` (v0.6.0 "every hand leaves a
// receipt"): real .build/debug/opc binary, suite temp support dir seeded
// by the in-process store, state-neutral restore. Three things this pins:
// newest-first order (manual decidedAt, not wall-clock luck), attribution
// (WHO asked lands on the row), and the pure-read promise — the snapshot
// bytes must not move across a history call.

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
@MainActor func cliHistoryOrdersAttributesAndNeverWrites() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    defer {
        if let priorBytes {
            try? priorBytes.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
    }

    // Seed: two RESOLVED approvals with decidedAt far apart (wall-clock
    // luck must never decide the order a test asserts) + one still pending
    // (it must not appear in the ledger at all).
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let pid = store.selectedProductID
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: cto.id,
        title: "旧决定", reason: "r1", status: .approved,
        decidedAt: now.addingTimeInterval(-3600)))
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: cto.id,
        title: "新决定", reason: "r2", status: .rejected,
        decidedAt: now))
    store.approvals.append(ApprovalRequest(productID: pid, requesterID: cto.id,
        title: "还在等", reason: "r3"))
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    // 1. header, attribution, statuses, and NEWEST FIRST (position-checked)
    let h = try runCLI(["history"], supportDir: supportDir)
    #expect(h.rc == 0, "history must exit 0; got: \(h.err)")
    #expect(h.out.contains("Resolved approvals (2 of 2)"), "pending leaked: \(h.out)")
    #expect(!h.out.contains("还在等"), "a pending approval is not history")
    #expect(h.out.contains("← \(cto.displayName)"), "row must name the asker")
    let newer = try #require(h.out.range(of: "新决定"))
    let older = try #require(h.out.range(of: "旧决定"))
    #expect(newer.lowerBound < older.lowerBound, "newest first, not oldest")

    // 2. n truncates — and says it truncated
    let top = try runCLI(["history", "1"], supportDir: supportDir)
    #expect(top.rc == 0)
    #expect(top.out.contains("Resolved approvals (1 of 2)"))
    #expect(top.out.contains("新决定") && !top.out.contains("旧决定"))

    // 3. junk counts refuse loudly, never silently all or nothing
    for bad in ["0", "abc", "-3"] {
        let r = try runCLI(["history", bad], supportDir: supportDir)
        #expect(r.rc != 0, "junk count \(bad) must NOT exit 0")
        #expect((r.out + r.err).contains("usage: opc history"))
    }

    // 4. the pure-read promise: snapshot bytes identical across all of it
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "history must never write the company state")
}
