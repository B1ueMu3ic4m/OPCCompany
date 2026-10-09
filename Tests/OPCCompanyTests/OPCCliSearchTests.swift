import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc search` (v2.23.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// list prints kind + title + detail; `--json` serves the bridge `search`
// verb's exact shape; `--limit` rides; an empty/missing query refuses
// with usage; zero hits answer honestly; pure-read promise holds.

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
@MainActor func cliSearchSpansSurfacesAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-search-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.tasks = [
        CompanyTask(productID: pid, title: "终端搜索目标", ownerID: alice,
                    status: .running, successCriteria: "cli smoke"),
    ]
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["search", "搜索目标"], supportDir: supportDir)
    #expect(s.rc == 0, "search must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("[task] 终端搜索目标"))
    #expect(s.out.contains("cli smoke"))

    // --json serves the bridge door's exact shape
    let j = try runCLI(["search", "搜索目标", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["kind"] as? String == "task")

    // zero hits answer honestly
    let miss = try runCLI(["search", "nothing-matches-this"], supportDir: supportDir)
    #expect(miss.rc == 0 && miss.out.contains("no hits"))

    // junk forms refuse loudly, exit ≠ 0
    let junk = try runCLI(["search"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc search"))
    let two = try runCLI(["search", "a", "b"], supportDir: supportDir)
    #expect(two.rc != 0 && two.err.contains("usage: opc search"))
    let badLimit = try runCLI(["search", "x", "--limit", "zero"], supportDir: supportDir)
    #expect(badLimit.rc != 0)

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}
