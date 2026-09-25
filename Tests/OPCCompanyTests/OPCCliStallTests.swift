import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc stalls` (v0.10.0 "the stall watch"): real
// .build/debug/opc against the shared suite support dir, seeded in-process
// (save BEFORE create/run so the child sees exactly this), state-neutral
// restore. Pins: longest stall prints first with WAITS ON YOU; the
// threshold is a real knob through argv; junk refuses with usage; the
// quiet company says "nothing parked"; the pure-read promise holds —
// seeded snapshot bytes never move. Baseline captured AFTER the seed's
// own saveSnapshot (v0.8 lesson, do not "optimize" it back).

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

/// The CLI reads its own clock, so dwell ages ride a REAL Date() — the
/// door guarantees ordering and thresholds, not the test's frozen clock.
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliStallsPrintsTheDoorAndNeverWrites() throws {
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

    let realNow = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.workQueue = [
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingApproval, promptPreview: "p",
                      updatedAt: realNow.addingTimeInterval(-90 * 60)),
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .running, promptPreview: "q",
                      updatedAt: realNow.addingTimeInterval(-45 * 60)),
        // under-threshold and terminal noise: must never print
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingReview, promptPreview: "r",
                      updatedAt: realNow.addingTimeInterval(-5 * 60)),
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .completed, promptPreview: "d",
                      updatedAt: realNow.addingTimeInterval(-999 * 60)),
    ]
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["stalls"], supportDir: supportDir)
    #expect(s.rc == 0, "stalls must exit clean, stderr: \(s.err)")
    let lines = s.out.split(separator: "\n")
    let approval = try #require(
        lines.first { $0.contains("90 min") }, "worst row present: \(s.out)")
    #expect(approval.contains("WAITS ON YOU"),
            "the status fact travels: \(approval)")
    // data rows are indented and lead with their dwell number; parsing
    // it beats substring tests, which collide ("45 min" contains "5 min")
    let dwells = lines.filter { $0.hasPrefix("  ") }
        .compactMap { Int($0.drop { $0 == " " }.prefix { $0.isNumber }) }
    #expect(dwells.contains(45), "the running stall prints too: \(s.out)")
    #expect(!dwells.contains(5), "under-threshold stays out: \(dwells)")
    #expect(!dwells.contains(999), "terminal history never stalls: \(dwells)")
    // rows print longest-frozen first (dwell numbers, exact sequence)
    #expect(dwells == dwells.sorted(by: >),
            "rows print longest-frozen first: \(dwells)")

    // the threshold is a knob through argv, not an opinion baked in
    let strict = try runCLI(["stalls", "60"], supportDir: supportDir)
    #expect(strict.rc == 0)
    #expect(strict.out.contains("90 min") && !strict.out.contains("45 min"),
            "a 60-minute ask drops the 45: \(strict.out)")

    // junk refuses with usage, never a stack
    let junk = try runCLI(["stalls", "zero"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc stalls"),
            "junk gets usage: \(junk.err)")

    // pure-read: neither run moved the seeded bytes
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "stalls must never write state")
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliStallsQuietCompanySaysNothingParked() throws {
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
    store.workQueue = []
    store.saveSnapshot()

    let s = try runCLI(["stalls"], supportDir: supportDir)
    #expect(s.rc == 0, "a quiet watch still exits clean: \(s.err)")
    #expect(s.out.contains("nothing parked"),
            "empty answers empty, never a fake jam: \(s.out)")
}
