import Foundation
import Testing

@testable import OPCCompanyCore

// v2.9.0 "the autopilot": `opc autopilot` — cycle after cycle of the
// SAME store primitive the desktop app's autopilot button drives, with
// two honest stop conditions: an approval waiting on the boss pauses
// the loop (the terminal visitor never decides for the boss), and a
// cycle where nothing moved ends it. Seeds ride the CompanyPersistence
// testSupportDirectoryOverride seam into private dirs; the child gets
// the same dir through its process env.

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

private struct AutopilotSeedError: Error {}

/// A private support dir behind the seam, seeded with one goal so the
/// first autopilot cycle has real work to move.
@MainActor
private func makeSeededDir(name: String) throws -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-autopilot-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    let store = CompanyStore.bootstrap(loadPersisted: false)
    guard store.startCTOSupervisorGoal(goal: "ship the demo") != nil else {
        throw AutopilotSeedError() // the test premise is broken — fail loudly
    }
    store.saveSnapshot()
    return tmp
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func autopilotOnceMovesTheOfficeAndPrintsTheFrame() throws {
    let tmp = try makeSeededDir(name: "once")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    let s = try runCLI(["autopilot", "--once"], supportDir: tmp)
    #expect(s.rc == 0, "\(s.err)")
    #expect(s.out.contains("Autopilot — 1 cycle(s)"), "the header states the plan: \(s.out.prefix(200))")
    #expect(s.out.contains("── autopilot cycle 1/1 ──"))
    #expect(s.out.contains("OPC Company — "), "every cycle prints the honest frame")
    #expect(s.out.contains("awaiting you:"), "the frame carries the boss's desk")
    // a goal was filed: the cycle had work to move, and it says so
    #expect(s.out.contains("nothing moved this cycle") == false,
            "a seeded goal must produce a moving first cycle: \(s.out.suffix(300))")
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func autopilotStopsWhenTheBossIsNeeded() throws {
    let tmp = try makeSeededDir(name: "boss")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    // a pending approval ON the books before the first cycle: the loop
    // must stop and say why — it never decides for the boss
    let store = CompanyStore.bootstrap(loadPersisted: true)
    store.approvals.append(ApprovalRequest(
        productID: store.selectedProductID,
        requesterID: store.ctoID,
        title: "等待老板的测试批准",
        reason: "the autopilot must stop here",
        status: .pending))
    store.saveSnapshot()

    let s = try runCLI(["autopilot", "--once"], supportDir: tmp)
    #expect(s.rc == 0, "\(s.err)")
    #expect(s.out.contains("stops here: approval(s) are waiting on the boss"),
            "a pending approval must pause the loop: \(s.out.suffix(400))")
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func autopilotQuietOfficeStopsHonestly() throws {
    let tmp = try makeSeededDir(name: "quiet")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    // first run moves the seeded goal; the SECOND run finds an office
    // where the autopilot dispatch no longer changes anything
    _ = try runCLI(["autopilot", "--once"], supportDir: tmp)
    let second = try runCLI(["autopilot", "--once"], supportDir: tmp)
    #expect(second.rc == 0, "\(second.err)")
    #expect(second.out.contains("nothing moved this cycle"),
            "a quiet office must end the run honestly: \(second.out.suffix(300))")
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func autopilotRefusesJunkKnobs() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-autopilot-junk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    for args in [["autopilot", "--cycles", "0"],
                 ["autopilot", "--cycles", "101"],
                 ["autopilot", "--interval", "0"],
                 ["autopilot", "--interval", "3601"],
                 ["autopilot", "--wat"]] {
        let s = try runCLI(args, supportDir: tmp)
        #expect(s.rc != 0, "\(args) must refuse: \(s.out)")
        #expect(s.err.contains("usage: opc autopilot"), "\(args) must name the usage: \(s.err)")
    }
}
