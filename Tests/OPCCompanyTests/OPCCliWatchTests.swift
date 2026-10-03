import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc watch` (v0.12.0 "the live office"): real
// .build/debug/opc against a private support dir seeded in-process
// through the CompanyPersistence.testSupportDirectoryOverride seam.
// The LOOP itself is untestable by design (it never returns);
// the seam is `--once`: one frame, exit 0. Pins: the frame quotes the
// store's doors (counts, stall wording, desk count), the clear escape
// leads so a terminal actually redraws in place, the wall clock is
// stamped (a live view IS about time), junk intervals refuse loudly,
// and the pure-read promise holds (snapshot bytes never move).

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
@MainActor func cliWatchOnceRendersDoorsAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-watch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-watch-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: scratch)
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    try FileManager.default.createDirectory(at: scratch,
                                            withIntermediateDirectories: true)

    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活",
                     detail: "d", createdAt: now.addingTimeInterval(-3600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: store.agents.first!.id,
                        title: "等批", reason: "r", status: .pending),
    ]
    var task = CompanyTask(productID: pid, title: "T", ownerID: store.agents.first!.id,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.workQueue = [
        AgentWorkItem(productID: pid, taskID: task.id, agentID: store.agents.first!.id,
                      status: .waitingApproval, promptPreview: "p",
                      updatedAt: now.addingTimeInterval(-90 * 60)),
    ]
    store.saveSnapshot()
    // pure-read baseline = the SEEDED state (the comparison below must
    // use these bytes, not whatever preceded the seed)
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["watch", "--once"], supportDir: supportDir)
    #expect(s.rc == 0, "one frame must exit 0: \(s.err)")

    // the clear escape LEADS, so a terminal redraws in place instead of
    // scrolling a wall of stale frames
    #expect(s.out.hasPrefix("\u{1B}[H\u{1B}[2J"),
            "frame must start with clear+home: \(s.out.prefix(12))")

    // the frame quotes the doors
    #expect(s.out.contains("OPC Company — "))
    #expect(s.out.contains("· "), "the wall-clock stamp is present")
    #expect(s.out.contains("tasks (1):"), "task counts ride the frame")
    #expect(s.out.contains("last 24h: 1 new"), "standup door rides the frame")
    #expect(s.out.contains("stuck: 1 parked over 30 min"),
            "stall door rides the frame: \(s.out)")
    #expect(s.out.contains("(WAITS ON YOU)"), "approval-parked wording intact")
    #expect(s.out.contains("awaiting you: 1 approval"), "desk count rides the frame")

    // pure read: bytes must not move
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "pure read: watch never moves state bytes")

    // junk interval refuses loudly with the usage line
    let bad = try runCLI(["watch", "abc"], supportDir: supportDir)
    #expect(bad.rc != 0)
    #expect(bad.err.contains("usage: opc watch"))

    // out-of-range intervals refuse too (negative / zero / absurd)
    for junk in ["0", "-3", "3601"] {
        let r = try runCLI(["watch", junk], supportDir: supportDir)
        #expect(r.rc != 0, "interval \(junk) must refuse")
    }
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliWatchFrameCarriesTheSeatsLine() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-watch-seats-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    // no workspace started: the frame's seats line is honest about it
    let s = try runCLI(["watch", "--once"], supportDir: supportDir)
    #expect(s.rc == 0, "watch --once must exit 0: \(s.err)")
    #expect(s.out.contains("seats: no windows open"))
}
