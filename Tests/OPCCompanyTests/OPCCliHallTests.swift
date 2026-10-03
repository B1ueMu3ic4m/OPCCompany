import Foundation
import Testing

@testable import OPCCompanyCore

// v2.4.0 CLI steering extras: `opc tell <agent> -` (stdin, one honest
// send per line, first refusal names its line) and `opc hall` (the
// one-paragraph terminal-office doctor, pure read). Real binary, real
// tmux for the stdin round-trip; each test seeds a private support dir
// via the CompanyPersistence.testSupportDirectoryOverride seam.

private var cliBinaryURL: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc")
}

private func runCLIWithStdin(_ args: [String], supportDir: URL, stdin: String) throws
    -> (rc: Int32, out: String, err: String)
{
    let process = Process()
    process.executableURL = cliBinaryURL
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["OPC_COMPANY_SUPPORT_DIR"] = supportDir.path
    env["OPC_ALLOW_CONCURRENT_WRITE"] = "1"
    process.environment = env
    let out = Pipe(), err = Pipe(), inPipe = Pipe()
    process.standardOutput = out
    process.standardError = err
    process.standardInput = inPipe
    try process.run()
    if let data = stdin.data(using: .utf8) {
        inPipe.fileHandleForWriting.write(data)
    }
    try inPipe.fileHandleForWriting.close()
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
@MainActor func cliHallReportsTheOfficeWithoutTouchingAnything() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-hall-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    let process = Process()
    process.executableURL = cliBinaryURL
    process.arguments = ["hall"]
    var env = ProcessInfo.processInfo.environment
    env["OPC_COMPANY_SUPPORT_DIR"] = supportDir.path
    process.environment = env
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()

    let output = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? ""
    #expect(process.terminationStatus == 0, "hall must exit 0: \(output)")
    #expect(output.contains("Terminal hall — "))
    // honest on both sides of tmux availability
    #expect(output.contains("tmux: ") || output.contains("tmux: not found"))
    #expect(output.contains("workspace session: ") || output.contains("tmux: not found"))
    #expect(output.contains("seats:"))
    #expect(output.contains("local seats: none here"),
            "a CLI visitor never sees another process's local seats")
    // no workspace started in this test: no seat can be live
    #expect(!output.contains("LIVE seat"))
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliTellStdinSendsOneHonestLinePerInputLine() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-tell-stdin-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }

    let store = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "StdinCat"
    store.addEmployee(from: draft)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCTellStdin-\(UUID().uuidString)", isDirectory: true)
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
    // The seed is on disk; drop the seam BEFORE any await. This test is
    // async (the capture loop below awaits for seconds) and a suspended
    // seam holder would point every concurrent bootstrap at THIS dir —
    // the children need only their env, the store object stays valid.
    CompanyPersistence.testSupportDirectoryOverride = nil

    guard let agent = store.agents.first(where: {
        $0.displayName == "StdinCat" && store.hasLiveTerminalSeat(agentID: $0.id)
    }) else {
        return // no seat qualified on this runner; refusals covered elsewhere
    }

    let markers = ["stdin-line-one", "stdin-line-two", "stdin-line-three"]
    let sent = try runCLIWithStdin(
        ["tell", "StdinCat", "-"], supportDir: supportDir,
        stdin: markers.joined(separator: "\n") + "\n")
    #expect(sent.rc == 0, "stdin tell must exit 0: \(sent.err)")
    #expect(sent.out.contains("→ StdinCat (3 lines)"),
            "the count is the honest summary: \(sent.out)")

    // every line echoed by the seat
    let target = try #require(store.persistentTerminalTargetForTesting(agentID: agent.id))
    let session = store.persistentTerminalSessionForTesting(target: target)
    var captured = ""
    for _ in 0..<30 {
        let r = await session.capture(workingDirectory: FileManager.default.temporaryDirectory)
        captured = r.output
        if markers.allSatisfy({ captured.contains($0) }) { break }
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    for marker in markers {
        #expect(captured.contains(marker),
                "the line must reach the seat: \(captured.suffix(400))")
    }

    // the doctor now sees the physically open window — same truth the
    // empty-office test asserted the negative side of
    let hall = try runCLIWithStdin(["hall"], supportDir: supportDir, stdin: "")
    #expect(hall.rc == 0, "hall must exit 0: \(hall.err)")
    #expect(hall.out.contains("workspace session: \(sessionName) (running)"))
    #expect(hall.out.contains("LIVE seat"))

    // empty stdin refuses honestly
    let empty = try runCLIWithStdin(["tell", "StdinCat", "-"],
                                    supportDir: supportDir, stdin: "\n\n")
    #expect(empty.rc != 0)
    #expect(empty.err.contains("stdin produced no lines"))
}
