import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc messages` (v2.19.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// bus prints kind + route + subject; `--json` serves the bridge
// `messages_list` verb's exact shape; the quiet bus answers its honest
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
@MainActor func cliMessagesPrintsTheBusAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-bus-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.postAgentMessage(productID: store.selectedProductID,
                           fromAgentID: store.ctoID,
                           toAgentID: store.agents.first!.id,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：终端读总线",
                           body: "cli smoke", persist: false)
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["messages"], supportDir: supportDir)
    #expect(s.rc == 0, "messages must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("派发：终端读总线"))
    #expect(s.out.contains("→"), "the route rides who → whom: \(s.out)")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["messages", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["subject"] as? String == "派发：终端读总线")
    #expect(rows[0]["kind"] as? String == "taskDispatched")

    // junk args refuse loudly, exit ≠ 0
    let junk = try runCLI(["messages", "extra"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc messages"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliMessagesQuietBusAnswersItsHonestPlaceholder() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "opc-cli-bus-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    let s = try runCLI(["messages"], supportDir: supportDir)
    #expect(s.rc == 0, "stderr: \(s.err)")
    #expect(s.out.contains("the bus is quiet"),
            "a quiet bus says so: \(s.out)")
}
