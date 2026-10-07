import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc risks` (v2.18.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// ledger prints risk titles newest-first; `--json` serves the bridge
// `risks_list` verb's exact shape; the empty office answers its honest
// placeholder; junk args refuse with usage; pure-read promise holds.

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
@MainActor func cliRisksPrintsTheBossViewAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-risks-\(UUID().uuidString)", isDirectory: true)
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
        CompanyEvent(productID: store.selectedProductID, kind: .risk,
                     title: "编译失败：CLI 冒烟", detail: "seeded by the test",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
        CompanyEvent(productID: store.selectedProductID, kind: .risk,
                     title: "命令行作业档案写入失败", detail: "whitelisted",
                     agentID: alice, createdAt: now.addingTimeInterval(-300)),
    ]
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["risks"], supportDir: supportDir)
    #expect(s.rc == 0, "risks must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("编译失败：CLI 冒烟"))
    #expect(!s.out.contains("命令行作业档案写入失败"),
            "the whitelist holds on the CLI surface too: \(s.out)")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["risks", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["title"] as? String == "编译失败：CLI 冒烟")

    // junk args refuse loudly, exit ≠ 0
    let junk = try runCLI(["risks", "extra"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc risks"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliRisksEmptyOfficeAnswersItsHonestPlaceholder() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "opc-cli-risks-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    let s = try runCLI(["risks"], supportDir: supportDir)
    #expect(s.rc == 0, "stderr: \(s.err)")
    #expect(s.out.contains("no risks on the boss desk"),
            "a quiet office says so: \(s.out)")
}
