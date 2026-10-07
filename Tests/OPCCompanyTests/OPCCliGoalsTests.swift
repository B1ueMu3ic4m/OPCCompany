import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc goals` (v2.17.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// ledger prints each goal with its completion score and closure steps;
// `--json` serves the bridge `goals_list` verb's exact shape; junk args
// refuse with usage; pure-read promise holds (seeded snapshot bytes must
// not move).

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
@MainActor func cliGoalsPrintsTheLedgerAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-goals-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.startCTOSupervisorGoal(goal: "print the ledger") != nil)
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["goals"], supportDir: supportDir)
    #expect(s.rc == 0, "goals must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("print the ledger"), "the goal text is the row header: \(s.out)")
    #expect(s.out.contains("%"), "the completion score rides the header")
    #expect(s.out.contains("[") && s.out.contains("]"),
            "closure steps print with their status")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["goals", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["goal"] as? String == "print the ledger")
    #expect(rows[0]["counts"] is [String: Any])

    // junk args refuse loudly, exit ≠ 0
    let junk = try runCLI(["goals", "extra"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc goals"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliGoalsEmptyOfficeAnswersItsHonestPlaceholder() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "opc-cli-goals-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    let s = try runCLI(["goals"], supportDir: supportDir)
    #expect(s.rc == 0, "stderr: \(s.err)")
    #expect(s.out.contains("no goals yet"),
            "an empty ledger says so, and names the door that fixes it: \(s.out)")
}
