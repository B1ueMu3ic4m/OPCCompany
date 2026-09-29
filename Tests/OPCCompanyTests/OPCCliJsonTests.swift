import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for the v0.13.0 `--json` surface: real .build/debug/opc
// over an ISOLATED support dir, then the SAME state read back through the
// REAL @_cdecl bridge. The soul of this file is the anti-drift pin: the
// CLI's --json bytes and the bridge's smuggle-channel bytes must be
// IDENTICAL, because both now print CompanyStore+JSONDoors's one
// serializer. Plus: schema shapes, flag-position tolerance, junk refuses,
// and the pure-read promise.

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

/// The bridge's answer for a query verb, over the CURRENT snapshot on disk.
/// The dir is set EXPLICITLY here because CompanyPersistence caches its
/// first resolution: whatever dir the seed used, the bridge must be
/// pointed at the same one through the env it actually reads.
@MainActor
private func bridgeBytes(verb: String, payload: [String: Any],
                         supportDir: URL) throws -> String {
    setenv("OPC_COMPANY_SUPPORT_DIR", supportDir.path, 1)
    #expect(opc_bridge_create() == 0)
    defer { opc_bridge_destroy() }
    let v = strdup(verb)
    defer { free(v) }
    var payloadJSON: UnsafeMutablePointer<CChar>? = nil
    if !payload.isEmpty {
        let data = try JSONSerialization.data(withJSONObject: payload)
        payloadJSON = strdup(String(decoding: data, as: UTF8.self))
    }
    defer { if let p = payloadJSON { free(p) } }
    #expect(opc_bridge_command(v, payloadJSON) == 0)
    return String(cString: try #require(opc_bridge_last_error()))
}

@MainActor
private func seedScriptableCompany(now: Date, supportDir: URL) throws -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "风险", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: alice, title: "等批", reason: "r",
                        status: .pending),
    ]
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    store.workQueue = [
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .waitingApproval, promptPreview: "p",
                      updatedAt: now.addingTimeInterval(-90 * 60)),
    ]
    store.saveSnapshot()
    return store
}

@Suite(.serialized)
struct OPCCliJsonTests {

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliJSONMatchesTheBridgeByteForByte() throws {
    // Follow whatever dir CompanyPersistence has CACHED (its first
    // resolution wins process-wide — a private setenv gate here would be
    // a lie under the full suite). Seed, CLI and bridge all point at
    // that one dir; the snapshot is restored afterwards.
    let supportDir = CompanyPersistence.supportDirectory
    let tmp = supportDir
    let stateFile = tmp.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    defer {
        if let priorBytes {
            try? priorBytes.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
        unsetenv("OPC_COMPANY_SUPPORT_DIR")
    }

    let now = Date()
    _ = try seedScriptableCompany(now: now, supportDir: tmp)

    // THE anti-drift pin: CLI stdout bytes == bridge last_error bytes.
    let pairs: [(args: [String], verb: String, payload: [String: Any])] = [
        (["approvals", "--json"], "approvals_list", [:]),
        (["standup", "--json"], "standup_window", [:]),
        (["team", "12", "--json"], "team_stats_list", ["hours": 12]),
        (["stalls", "--json"], "stalls_list", [:]),
        (["history", "--json"], "history_list", [:]),
        (["deliverables", "--json"], "deliverables_list", [:]),
        (["weight", "--json"], "weight_json", [:]),
    ]
    for pair in pairs {
        let s = try runCLI(pair.args, supportDir: tmp)
        #expect(s.rc == 0, "\(pair.args) must exit 0: \(s.err)")
        let fromBridge = try bridgeBytes(verb: pair.verb, payload: pair.payload,
                                     supportDir: supportDir)
        let fromCLI = s.out.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(fromCLI == fromBridge,
                "CLI \(pair.args) must print the bridge's exact bytes\nCLI:   \(fromCLI)\nBRIDGE: \(fromBridge)")
    }

    // catchup is the one deliberate shape difference: the bridge carries
    // the RAW page (the page IS the payload), the CLI's --json wraps the
    // SAME page in a {"page": ...} envelope for jq. Compare the page.
    let cu = try runCLI(["catchup", "--json"], supportDir: tmp)
    let envelope = try JSONSerialization.jsonObject(with: Data(cu.out.utf8))
        as? [String: Any]
    let cliPage = try #require(envelope?["page"] as? String)
    let bridgePage = try bridgeBytes(verb: "catchup_md", payload: [:],
                                     supportDir: tmp)
    #expect(cliPage == bridgePage,
            "the envelope wraps the bridge's page byte-for-byte")
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliJSONShapesFlagsAndPurity() throws {
    // the suite-shared support dir: CompanyPersistence.supportDirectory
    // caches per-process, so a second test's setenv is a lie — instead,
    // seed AND every runCLI read the SAME (cached) dir, and the pure-read
    // pin compares seeded-vs-after bytes in that dir
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    defer {
        if let priorBytes {
            try? priorBytes.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
    }

    let now = Date()
    _ = try seedScriptableCompany(now: now, supportDir: supportDir)
    // pure-read baseline = the SEEDED state
    let seededBytes = try Data(contentsOf: stateFile)

    // schema shapes
    let st = try runCLI(["standup", "--json"], supportDir: supportDir)
    let obj = try JSONSerialization.jsonObject(with: Data(st.out.utf8)) as? [String: Any]
    #expect(obj?["newWork"] as? Int == 1, "standup JSON is the seven-count object: \(st.out)")
    #expect(obj?["awaitingNow"] as? Int == 1)

    let ap = try runCLI(["approvals", "--json"], supportDir: supportDir)
    let rows = try JSONSerialization.jsonObject(with: Data(ap.out.utf8)) as? [[String: Any]]
    #expect(rows?.count == 1)
    #expect(rows?.first?["title"] as? String == "等批")
    #expect(rows?.first?["requesterID"] != nil, "roster link rides the row")

    // the catchup envelope wraps the page, never re-derives it
    let cu = try runCLI(["catchup", "--json"], supportDir: supportDir)
    let env = try JSONSerialization.jsonObject(with: Data(cu.out.utf8)) as? [String: Any]
    #expect(env?.keys.count == 1 && env?.keys.first == "page")
    #expect((env?["page"] as? String)?.contains("# Catch-up — ") == true)

    // flag position is tolerated before or after the positional
    let pre = try runCLI(["standup", "--json", "6"], supportDir: supportDir)
    let post = try runCLI(["standup", "6", "--json"], supportDir: supportDir)
    #expect(pre.rc == 0 && post.rc == 0)
    #expect(pre.out == post.out, "flag position must not change the bytes")
    #expect((try JSONSerialization.jsonObject(with: Data(pre.out.utf8))
        as? [String: Any])?["hours"] as? Int == 6)

    // pure read: bytes never move
    #expect(try Data(contentsOf: stateFile) == seededBytes,
            "pure read: --json never moves state bytes")
}
}
