import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for the CLI boss surface: `opc approvals` and
// `opc decide` must (a) see the store's pending approvals, (b) resolve
// them through the SAME checked path as the bridge verb, and (c) refuse
// double-decides / ghost ids / malformed args with exit codes, never a
// silent rc=0. Runs the real .build/debug/opc binary against an
// isolated OPC_COMPANY_SUPPORT_DIR — the user's snapshot is untouchable
// by construction, and the whole test self-deletes.
//
// Skips (not fails) when the CLI binary is absent: the enabled-if gate
// keeps this green under partial builds while CI (swift build first)
// always runs it.

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
    // The concurrent-writer guard is real behavior; this suite owns the
    // snapshot copy and may run while a dev's GUI app is open.
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
@MainActor func cliApprovalsAndDecideRoundTrip() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-e2e-\(ProcessInfo.processInfo.processIdentifier)",
                                isDirectory: true)
    defer { try? FileManager.default.removeItem(at: supportDir) }
    try FileManager.default.createDirectory(at: supportDir,
                                            withIntermediateDirectories: true)

    // Seed through the SAME hooks the CLI reads: fresh store, one task in
    // needsApproval, one pending approval, then persist. bootstrap's
    // supportDirectory honors OPC_COMPANY_SUPPORT_DIR; set it process-wide
    // for the seed (suite runs --no-parallel; the defer keeps it clean).
    let envKey = "OPC_COMPANY_SUPPORT_DIR"
    let previous = ProcessInfo.processInfo.environment[envKey]
    setenv(envKey, supportDir.path, 1)
    defer {
        if let previous { setenv(envKey, previous, 1) } else { unsetenv(envKey) }
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "CLI 审批回归", ownerID: engineer.id,
                     status: .needsApproval, successCriteria: "回归。")
    let task = try #require(store.selectedProductTasks
        .first { $0.title == "CLI 审批回归" })
    store.requestApproval(taskID: task.id, title: "CLI 回归审批",
                          reason: "端到端", requesterID: engineer.id)
    let approval = try #require(store.selectedProductPendingApprovals
        .first { $0.title == "CLI 回归审批" })
    store.saveSnapshot()

    // 1. approvals lists it (uuid uppercase from uuidString)
    let listed = try runCLI(["approvals"], supportDir: supportDir)
    #expect(listed.rc == 0)
    #expect(listed.out.contains(approval.id.uuidString.uppercased()),
            "opc approvals must print the approval id; got: \(listed.out)")

    // 2. decide approves through the checked path (lowercase input works
    //    too — UUID(uuidString:) is case-insensitive; keep one form and
    //    assert the state moved on disk)
    let decided = try runCLI(["decide", approval.id.uuidString, "approve"],
                             supportDir: supportDir)
    #expect(decided.rc == 0, "valid approve must exit 0; got: \(decided.err)")
    #expect(decided.out.contains("Approved."))
    let afterDecide = CompanyStore.bootstrap(loadPersisted: true)
    #expect(afterDecide.approvals.first { $0.id == approval.id }?.status
            == .approved, "the CLI's write must be on disk, not just stdout")

    // 3. double-decide refuses with the SHARED wording
    let twice = try runCLI(["decide", approval.id.uuidString, "reject"],
                           supportDir: supportDir)
    #expect(twice.rc != 0, "a second decide must NOT exit 0")
    #expect((twice.out + twice.err).contains("already decided"))

    // 4. ghost id refuses loudly, usage noise refuses with guidance
    let ghost = try runCLI(["decide",
                            "00000000-0000-0000-0000-00000000beef", "approve"],
                           supportDir: supportDir)
    #expect(ghost.rc != 0)
    #expect((ghost.out + ghost.err).contains("no approval with id"))
    let junk = try runCLI(["decide", "not-a-uuid", "yes"],
                          supportDir: supportDir)
    #expect(junk.rc != 0)
    #expect((junk.out + junk.err).contains("usage: opc decide"))

    // 5. approvals now reads empty for that title (state coherence)
    let emptyAgain = try runCLI(["approvals"], supportDir: supportDir)
    #expect(emptyAgain.rc == 0)
    #expect(!emptyAgain.out.contains("CLI 回归审批"))
}
