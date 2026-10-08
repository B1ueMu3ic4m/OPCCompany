import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc task` (v2.20.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// file prints the task header, its edges, and the MISSING verdict on a
// dead path; `--json` serves the bridge `task_show` verb's exact shape;
// junk/unknown ids refuse with usage; pure-read promise holds.

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
@MainActor func cliTaskPrintsTheFileAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-task-\(UUID().uuidString)", isDirectory: true)
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
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-task-cli-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let deadFile = scratch.appendingPathComponent("claimed.md")
    try "ghost".data(using: .utf8)!.write(to: deadFile)
    var task = CompanyTask(productID: pid, title: "终端读任务",
                           ownerID: alice, status: .running,
                           successCriteria: "cli smoke")
    store.tasks = [task]
    task = store.tasks[0]
    store.artifacts = [
        ArtifactRecord(productID: pid, taskID: task.id, kind: .report,
                       title: "幽灵报告", path: deadFile.path, summary: "s"),
    ]
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)
    // the claimed file dies AFTER seeding — the door judges at read time
    try FileManager.default.removeItem(at: deadFile)

    let s = try runCLI(["task", task.id.uuidString], supportDir: supportDir)
    #expect(s.rc == 0, "task must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("终端读任务"))
    #expect(s.out.contains("cli smoke"), "the success criteria rides the file")
    #expect(s.out.contains("[MISSING]"), "a deleted claim is judged, not believed: \(s.out)")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["task", task.id.uuidString, "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let d = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [String: Any])
    #expect(d["taskID"] as? String == task.id.uuidString)
    let artifacts = try #require(d["artifacts"] as? [[String: Any]])
    #expect(artifacts[0]["existsNow"] as? Bool == false)

    // junk ids refuse loudly, exit ≠ 0
    let junk = try runCLI(["task", "not-a-uuid"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc task"))
    let unknown = try runCLI(["task", UUID().uuidString], supportDir: supportDir)
    #expect(unknown.rc != 0, "an unknown-but-valid uuid refuses honestly")

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}
