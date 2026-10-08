import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc ack` (v2.21.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the ack
// lands by agent NAME (the roster door's discipline), the state file
// MOVES (a write, not a pretend), stale/double acks refuse with usage,
// and junk args refuse loudly.

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
@MainActor func cliAckLandsTheWriteAndRefusesStale() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-ack-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let alice = store.agents.first!
    store.postAgentMessage(productID: store.selectedProductID,
                           fromAgentID: store.ctoID, toAgentID: alice.id,
                           taskID: nil, kind: .taskDispatched,
                           subject: "派发：终端确认", body: "cli smoke",
                           persist: false)
    store.saveSnapshot()
    let messageID = try #require(
        store.selectedProductRecentAgentMessages.first(where: { $0.toAgentID == alice.id })?.id)
    let before = try Data(contentsOf: stateFile)

    // the ack lands by agent NAME
    let s = try runCLI(["ack", messageID.uuidString, alice.displayName],
                       supportDir: supportDir)
    #expect(s.rc == 0, "ack must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("acknowledged"))
    let after = try Data(contentsOf: stateFile)
    #expect(after != before, "an ack is a WRITE — the snapshot moves")

    // double ack refuses loudly
    let stale = try runCLI(["ack", messageID.uuidString, alice.displayName],
                           supportDir: supportDir)
    #expect(stale.rc != 0 && stale.err.contains("ack refused"))

    // junk args refuse loudly
    let junk = try runCLI(["ack", "nope", alice.displayName], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc ack"))
    let short = try runCLI(["ack", messageID.uuidString], supportDir: supportDir)
    #expect(short.rc != 0 && short.err.contains("usage: opc ack"))
    let unknownAgent = try runCLI(["ack", messageID.uuidString, "ghost"],
                                  supportDir: supportDir)
    #expect(unknownAgent.rc != 0, "an unknown agent refuses (resolveAgent)")
}
