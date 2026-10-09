import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc ack --all` (v2.24.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the batch
// lands by agent NAME with an honest count; the state file MOVES; a
// clear inbox answers 0 and moves nothing; junk forms refuse.

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
@MainActor func cliAckAllLandsTheBatchAndCountsHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-ack-all-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let alice = store.agents.first!
    for i in 0..<2 {
        store.postAgentMessage(productID: store.selectedProductID,
                               fromAgentID: store.ctoID, toAgentID: alice.id,
                               taskID: nil, kind: .taskDispatched,
                               subject: "派发：终端批量 \(i)", body: "cli smoke",
                               persist: false)
    }
    store.saveSnapshot()
    let before = try Data(contentsOf: stateFile)

    let s = try runCLI(["ack", "--all", alice.displayName], supportDir: supportDir)
    #expect(s.rc == 0, "ack --all must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("acknowledged 2 messages for \(alice.displayName)"))
    let after = try Data(contentsOf: stateFile)
    #expect(after != before, "a batch ack is a WRITE")

    // a clear inbox: honest zero, nothing moves
    let again = try runCLI(["ack", "--all", alice.displayName], supportDir: supportDir)
    #expect(again.rc == 0 && again.out.contains("acknowledged 0 messages"))
    #expect(again.out.contains("already clear"))
    let afterAgain = try Data(contentsOf: stateFile)
    #expect(afterAgain == after)

    // junk forms refuse loudly
    let junk = try runCLI(["ack", "--all"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc ack --all"))
    let ghost = try runCLI(["ack", "--all", "ghost"], supportDir: supportDir)
    #expect(ghost.rc != 0, "an unknown agent refuses (resolveAgent)")
}
