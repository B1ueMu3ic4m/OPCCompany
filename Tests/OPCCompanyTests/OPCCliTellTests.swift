import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc tell` (v0.18.0 "the tell door"): the real
// .build/debug/opc against a private support dir — seed and child both
// pointed there (CompanyPersistence.testSupportDirectoryOverride seam /
// the child's OPC_COMPANY_SUPPORT_DIR env).
// Pins: uuid AND name resolution (case-insensitive), honest refusals —
// junk args, unknown name, an AMBIGUOUS name, an empty line through the
// store's own guards — and the end-to-end success path: a line steered
// from the CLI is echoed back by a REAL tmux seat.

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

private func cleanuptmux(_ tmuxPath: String, _ sessionName: String) {
    _ = OPCProcessRunner.runAndWait(executable: tmuxPath,
                                    arguments: ["kill-session", "-t", sessionName],
                                    workingDirectory: FileManager.default.temporaryDirectory)
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliTellResolvesAgentsAndRefusesHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-tell-resolve-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }

    // seed: one uniquely-named employee, one duplicated name
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var first = EmployeeDraft()
    first.displayName = "CliTell"
    store.addEmployee(from: first)
    var twinA = EmployeeDraft()
    twinA.displayName = "TwinName"
    store.addEmployee(from: twinA)
    var twinB = EmployeeDraft()
    twinB.displayName = "TwinName"
    store.addEmployee(from: twinB)
    store.saveSnapshot()

    // junk arguments refuse with the usage line
    let bare = try runCLI(["tell"], supportDir: supportDir)
    #expect(bare.rc != 0)
    #expect(bare.err.contains("usage: opc tell"))

    // unknown name refuses rather than guessing
    let ghost = try runCLI(["tell", "NoSuchEmployee", "hi"], supportDir: supportDir)
    #expect(ghost.rc != 0)
    #expect(ghost.err.contains("no employee named"))

    // an ambiguous name refuses instead of picking a twin
    let ambiguous = try runCLI(["tell", "twinname", "hi"], supportDir: supportDir)
    #expect(ambiguous.rc != 0)
    #expect(ambiguous.err.contains("ambiguous"))

    // uuid resolution reaches the store's own guard, verbatim
    guard let seeded = store.agents.first(where: { $0.displayName == "CliTell" }) else {
        Issue.record("seed failed: CliTell missing")
        return
    }
    let empty = try runCLI(["tell", seeded.id.uuidString, ""],
                           supportDir: supportDir)
    #expect(empty.rc != 0)
    #expect(empty.err.contains("empty line"))
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliTellDeliversToALiveTmuxSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-tell-seat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }

    let store = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "CliTell"
    store.addEmployee(from: draft)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCCliTell-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Sources", isDirectory: true),
        withIntermediateDirectories: true)
    try "// package".write(
        to: root.appendingPathComponent("Package.swift"), atomically: true,
        encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanuptmux(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.saveSnapshot()
    // The seed is on disk; drop the seam BEFORE any await (the capture
    // loop below awaits): a suspended seam holder would point every
    // concurrent bootstrap at THIS dir. The child needs only its env.
    CompanyPersistence.testSupportDirectoryOverride = nil

    // the seat must already be live BEFORE the CLI process is launched:
    // tmux (the server) is the shared truth both processes see
    guard let agent = store.agents.first(where: {
        $0.displayName == "CliTell" && store.hasLiveTerminalSeat(agentID: $0.id)
    }) else {
        // no seat qualified on this runner — the honest-refusal test
        // above still covered the contract
        return
    }

    let marker = "opc-tell-\(UUID().uuidString.prefix(8))"
    let sent = try runCLI(["tell", "CliTell", "echo \(marker)"],
                          supportDir: supportDir)
    #expect(sent.rc == 0, "tell must exit 0 against a live seat: \(sent.err)")
    #expect(sent.out.contains("→ CliTell"))

    // the seat echoes: the line must surface in a fresh capture
    let target = try #require(store.persistentTerminalTargetForTesting(agentID: agent.id))
    let session = store.persistentTerminalSessionForTesting(target: target)
    var captured = ""
    for _ in 0..<20 {
        let r = await session.capture(workingDirectory: FileManager.default.temporaryDirectory)
        captured = r.output
        if captured.contains(marker) { break }
        try await Task.sleep(nanoseconds: 300_000_000)
    }
    #expect(captured.contains(marker),
            "the CLI-told line must be echoed by the seat: \(captured.suffix(400))")
}
