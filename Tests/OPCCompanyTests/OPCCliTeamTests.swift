import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc team` (v0.9.0 "the name behind the work"):
// real .build/debug/opc against the suite support dir, seeded in-process,
// state-neutral restore. Pins: each employee's window prints under their
// name; a 25h-old assignment does NOT count; MISSING rides the shelf
// door; the unattributed row is named, never personified; junk hours
// refuse; pure-read promise holds (seeded snapshot bytes must not move).

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
@MainActor func cliTeamPrintsPerEmployeeAndNeverWrites() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-team-\(UUID().uuidString)")
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
    let alice = store.agents.first!.id
    let aliceName = store.agents.first!.displayName
    store.events = [
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .taskAssigned, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-25 * 3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "e", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-1800)),
    ]
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.artifacts = [
        ArtifactRecord(productID: pid, taskID: task.id, kind: .report, title: "在",
                       path: realFile.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
    ]
    store.saveSnapshot()
    // pure-read baseline = the SEEDED state (v0.8 lesson)
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["team"], supportDir: supportDir)
    #expect(s.rc == 0, "team must exit clean, stderr: \(s.err)")
    let aliceLine = s.out.split(separator: "\n")
        .first { $0.contains(aliceName) }.map(String.init) ?? ""
    #expect(aliceLine.contains("1 assigned"),
            "the 25h-old assignment must stay outside: \(aliceLine)")
    #expect(aliceLine.contains("1 delivered"),
            "task-chain delivery attributes to the owner: \(aliceLine)")
    #expect(aliceLine.contains("1 risks"))
    #expect(!aliceLine.contains("MISSING"), "the file is real, no ghost mark")

    // junk hours refuse loudly, exit ≠ 0
    let junk = try runCLI(["team", "0"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc team"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliTeamUnattributedRowIsNamed() throws {
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
    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.events = []
    store.tasks = []
    // an artifact whose task id points at NOTHING: dead chain
    store.artifacts = [
        ArtifactRecord(productID: store.selectedProductID, taskID: UUID(),
                       kind: .report, title: "链断", path: "/nonexistent/x",
                       summary: "s", createdAt: now.addingTimeInterval(-600)),
    ]
    store.saveSnapshot()

    let s = try runCLI(["team"], supportDir: supportDir)
    #expect(s.rc == 0, "team must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("未分配"),
            "a dead chain lands in the named bucket: \(s.out)")
    #expect(s.out.contains("MISSING"), "the ghost file is still judged")
}
