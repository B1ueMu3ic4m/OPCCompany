import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc events` (v2.43.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// stream prints EVERY kind newest-first (no boss filtering on this
// door); `--json` serves the bridge `events_list` verb's exact shape;
// the empty office answers its honest placeholder; junk args refuse
// with usage; pure-read promise holds.

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
@MainActor func cliEventsPrintsEveryKindAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-events-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let now = Date()
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: store.selectedProductID, kind: .taskAssigned,
                     title: "分配任务：CLI 冒烟", detail: "seeded by the test",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
        CompanyEvent(productID: store.selectedProductID, kind: .risk,
                     title: "风险：桥层", detail: "also rides here",
                     agentID: alice, createdAt: now.addingTimeInterval(-300)),
    ]
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["events"], supportDir: supportDir)
    #expect(s.rc == 0, "events must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("[taskAssigned] 分配任务：CLI 冒烟"),
            "the kind rides the human stream verbatim: \(s.out)")
    #expect(s.out.contains("[risk] 风险：桥层"),
            "EVERY kind rides — this door is NOT boss-filtered: \(s.out)")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["events", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 2)
    #expect(rows[0]["kind"] as? String == "risk", "newest first on the JSON face too")

    // junk args refuse loudly, exit ≠ 0
    let junk = try runCLI(["events", "extra"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc events"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliEventsShowsTheBootstrapCompanyHonestly() throws {
    // The bootstrap company is BORN with events (a fresh office is not
    // an empty office) — this door shows EVERY kind, so the honest
    // answer here is the real stream, not a placeholder. Pin the shape.
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "opc-cli-events-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    _ = CompanyStore.bootstrap(loadPersisted: false)

    let s = try runCLI(["events"], supportDir: supportDir)
    #expect(s.rc == 0, "stderr: \(s.err)")
    #expect(s.out.contains("["),
            "a fresh company still has a real event stream: \(s.out)")
    #expect(!s.out.contains("no events yet"),
            "the placeholder would be a LIE for a bootstrap company")
}
