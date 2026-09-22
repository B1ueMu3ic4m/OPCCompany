import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc standup` (v0.8.0 "the morning standup"):
// real .build/debug/opc, suite support dir seeded in-process, state-
// neutral restore. Pins: window traffic counts print as counted (new
// work / decided / delivered+MISSING / risks / awaiting-you), a
// 25-hour-old event does NOT count in the default window, the quiet
// company answers with quiet honesty, junk hours are refused, and the
// pure-read promise holds (snapshot bytes must not move).

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
@MainActor func cliStandupCountsTrafficAndNeverWrites() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-standup-\(UUID().uuidString)")
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
    let realFile = scratch.appendingPathComponent("morning.md")
    try "shipped".data(using: .utf8)!.write(to: realFile)

    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活一",
                     detail: "d", createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .taskCreated, title: "旧活",
                     detail: "d", createdAt: now.addingTimeInterval(-25 * 3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "风险一",
                     detail: "d", createdAt: now.addingTimeInterval(-600)),
        CompanyEvent(productID: pid, kind: .risk, title: "风险二",
                     detail: "d", createdAt: now.addingTimeInterval(-900)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, title: "批一", reason: "r",
                        status: .approved, decidedAt: now.addingTimeInterval(-700)),
        ApprovalRequest(productID: pid, title: "等一", reason: "r",
                        status: .pending),
    ]
    store.artifacts = [
        ArtifactRecord(productID: pid, kind: .report, title: "真交付",
                       path: realFile.path, summary: "s",
                       createdAt: now.addingTimeInterval(-800)),
    ]
    store.saveSnapshot()
    // pure-read baseline = the SEEDED state (restore to priorBytes still
    // neutralizes the seed itself; the comparison below must not use it)
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["standup"], supportDir: supportDir)
    #expect(s.rc == 0, "read must exit 0: \(s.err)")
    let lines = s.out.split(separator: "\n").map(String.init)
    let row = try #require(lines.first { $0.contains("new work") })
    #expect(row.contains("1"), "the 25h-old creation must stay OUT: \(row)")
    #expect(try #require(lines.first { $0.contains("risks") }).contains("2"))
    #expect(try #require(lines.first { $0.contains("decided") }).contains("1"))
    let deliv = try #require(lines.first { $0.contains("delivered") })
    #expect(deliv.contains("1") && !deliv.contains("MISSING"),
            "one delivery, file on disk — no warning: \(deliv)")
    let awaitLine = try #require(lines.first { $0.contains("awaiting") })
    #expect(awaitLine.contains("1"), "the live queue is not windowed: \(awaitLine)")

    // delete the file between calls: the SAME command flips to MISSING
    try FileManager.default.removeItem(at: realFile)
    let after = try runCLI(["standup"], supportDir: supportDir)
    let afterDeliv = try #require(after.out.split(separator: "\n")
        .first { $0.contains("delivered") })
    #expect(afterDeliv.contains("MISSING"),
            "standup rides the live existence door, not a stored claim: \(afterDeliv)")

    // widen the window: yesterday's task comes in
    let wide = try runCLI(["standup", "48"], supportDir: supportDir)
    #expect(try #require(wide.out.split(separator: "\n")
        .first { $0.contains("new work") }).contains("2"))

    // junk refuses
    let junk = try runCLI(["standup", "yesterday"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage"),
            "a non-numeric window must be refused, not guessed")

    // pure-read promise: the CLI runs never moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliStandupQuietCompanyAnswersQuietly() throws {
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
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.events = []
    store.approvals = []
    store.artifacts = []
    store.saveSnapshot()
    let s = try runCLI(["standup"], supportDir: supportDir)
    #expect(s.rc == 0)
    #expect(s.out.contains("nothing in the last 24h"),
            "quiet must say quiet: \(s.out)")
}
