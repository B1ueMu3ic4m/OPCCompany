import Foundation
import Testing

@testable import OPCCompanyCore

// v2.6.0 "the transcript door": `transcript` over the real @_cdecl ABI,
// plus the CLI's human/--json faces. The door serves the agent's VISIBLE
// terminal log — the SAME product-scoped, sanitized, compacted text the
// GUI's agent card renders — clipped to the last `tail` lines. Seeding
// rides the CompanyPersistence.testSupportDirectoryOverride seam (a bare
// setenv of OPC_COMPANY_SUPPORT_DIR is dead theater after the first-touch
// bake — see OPCRepoHygieneTests.supportDirOverrideRidesTheSeamNotTheEnv);
// the bridge tests run inside the serialized OPCBridgeABIDoorTests suite
// because opc_bridge_create() is a process-global singleton.

@MainActor
private func seedTranscriptCompany(now: Date) throws -> (CompanyStore, UUID) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-transcript-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let alice = store.agents.first!.id
    store.appendTerminalLog("""
    line-one-of-the-seed
    line-two-of-the-seed
    line-three-of-the-seed
    line-four-of-the-seed
    """, for: alice)
    store.saveSnapshot()
    return (store, alice)
}

extension OPCBridgeABIDoorTests {

    @MainActor
    @Test func transcriptDoorServesTheVisibleWindowOverRealABI() throws {
        let (store, alice) = try seedTranscriptCompany(now: Date())
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }
        _ = store  // seeding is the point; the bridge re-loads from disk

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }

        func command(_ payload: [String: Any]) throws -> (Int32, String) {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let p = strdup(String(decoding: data, as: UTF8.self))
            defer { free(p) }
            let verb = strdup("transcript")
            defer { free(verb) }
            let rc = opc_bridge_command(verb, p)
            return (rc, rc == 0 ? String(cString: opc_bridge_last_error()!) : String(cString: opc_bridge_last_error()!))
        }

        // the window: last 2 of the seed's lines, with the honest count
        let (rc, raw) = try command(["agentID": alice.uuidString, "tail": 2])
        #expect(rc == 0, "transcript answers over the ABI: \(raw)")
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(parsed["agentID"] as? String == alice.uuidString)
        #expect(parsed["totalLines"] as? Int == 4, "totalLines counts the visible log before clipping: \(parsed)")
        #expect(parsed["tail"] as? Int == 2)
        #expect(parsed["lines"] as? [String] == ["line-three-of-the-seed", "line-four-of-the-seed"],
                "lines is the LAST window, in order: \(parsed)")
        #expect(parsed["displayName"] != nil, "the row names its employee")

        // the knob both ways: an oversized tail serves everything, a
        // non-positive tail means no clipping at all
        let (rcBig, rawBig) = try command(["agentID": alice.uuidString, "tail": 999])
        #expect(rcBig == 0)
        let big = try #require(try JSONSerialization.jsonObject(with: Data(rawBig.utf8)) as? [String: Any])
        #expect((big["lines"] as? [String])?.count == 4)
        let (rcFull, rawFull) = try command(["agentID": alice.uuidString, "tail": 0])
        #expect(rcFull == 0)
        let full = try #require(try JSONSerialization.jsonObject(with: Data(rawFull.utf8)) as? [String: Any])
        #expect((full["lines"] as? [String])?.count == 4)

        // for a LIST-shaped answer order is the contract: same state,
        // same bytes
        let (rcAgain, rawAgain) = try command(["agentID": alice.uuidString, "tail": 2])
        #expect(rcAgain == 0 && rawAgain == raw, "byte-stable repetition")

        // an unknown id refuses honestly; an empty store is never invented
        let (rcGhost, rawGhost) = try command(["agentID": UUID().uuidString])
        #expect(rcGhost == -1, "unknown agent refuses")
        #expect(rawGhost.lowercased().contains("no agent"), "the refusal names its reason: \(rawGhost)")

        // junk payload refuses too
        let junk = strdup("transcriptx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1, "neighbors stay shut")

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}

@MainActor
@Test func transcriptCLIServesHumanAndJSONFaces() throws {
    let (store, alice) = try seedTranscriptCompany(now: Date())
    // the door's bytes, straight from the seeding store: what the CLI's
    // --json face must serve byte-for-byte
    let expectedJSON = String(
        decoding: try store.transcriptJSON(agentID: alice, tail: 2), as: UTF8.self)
    defer { CompanyPersistence.testSupportDirectoryOverride = nil }

    let cli = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc")
    guard FileManager.default.fileExists(atPath: cli.path) else {
        Issue.record("opc binary missing — build first")
        return
    }

    func run(_ args: [String]) throws -> (rc: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = cli
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["OPC_COMPANY_SUPPORT_DIR"] = CompanyPersistence.supportDirectory.path
        env["OPC_ALLOW_CONCURRENT_WRITE"] = "1"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let read: (Pipe) -> String = { pipe in
            String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        return (process.terminationStatus, read(out), read(err))
    }

    // the human face names the employee and shows the window
    let human = try run(["transcript", alice.uuidString, "--tail", "2"])
    #expect(human.rc == 0, "\(human.err)")
    #expect(human.out.contains("transcript — 2 of 4 lines"), "the header counts honestly: \(human.out)")
    #expect(human.out.contains("line-three-of-the-seed"))
    #expect(human.out.contains("line-four-of-the-seed"))
    #expect(!human.out.contains("line-one-of-the-seed"), "clipping is real")

    // the JSON face: a child cannot see this process's static seam, so
    // point it at the same dir through its env (done above); bytes must
    // match the store's own serializer exactly
    let json = try run(["transcript", alice.uuidString, "--tail", "2", "--json"])
    #expect(json.rc == 0, "\(json.err)")
    #expect(json.out.trimmingCharacters(in: .whitespacesAndNewlines)
        == expectedJSON.trimmingCharacters(in: .whitespacesAndNewlines),
        "CLI --json serves the door's exact bytes\nCLI:    \(json.out)\nSTORE:  \(expectedJSON)")

    // an unknown name refuses like resolveAgent always has
    let ghost = try run(["transcript", "nobody-here"])
    #expect(ghost.rc != 0)
    #expect(ghost.err.contains("no employee named"), "\(ghost.err)")
}
