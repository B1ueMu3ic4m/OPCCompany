import Foundation
import Testing

@testable import OPCCompanyCore

// v2.14.0 "the desk door": `desk` over the real @_cdecl ABI plus the
// CLI's human/--json faces. One employee's working surface — profile
// chips, session, assigned tasks, work queue, pending inbox — composed
// from the SAME accessors the macOS agent desk renders. Seeding rides
// the CompanyPersistence.testSupportDirectoryOverride seam; the bridge
// tests live in the serialized OPCBridgeABIDoorTests suite (the bridge
// is a process-global singleton).

extension OPCBridgeABIDoorTests {

    @MainActor
    @Test func bridgeDeskComposesTheWorkingSurfaceOverRealABI() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-bridge-desk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer {
            CompanyPersistence.testSupportDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tmp)
        }
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        let pid = store.selectedProductID
        var task = CompanyTask(productID: pid, title: "定义产品架构", ownerID: engineer.id,
                               status: .running, successCriteria: "s")
        store.tasks = [task]
        task = store.tasks[0]
        store.workQueue = [
            AgentWorkItem(productID: pid, taskID: task.id, agentID: engineer.id,
                          status: .running, promptPreview: "build the frame",
                          updatedAt: Date()),
        ]
        store.saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }

        func command(_ payload: [String: Any]) throws -> (Int32, String) {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let p = strdup(String(decoding: data, as: UTF8.self))
            defer { free(p) }
            let verb = strdup("desk")
            defer { free(verb) }
            let rc = opc_bridge_command(verb, p)
            return (rc, String(cString: opc_bridge_last_error()!))
        }

        let (rc, raw) = try command(["agentID": engineer.id.uuidString])
        #expect(rc == 0, "\(raw)")
        let desk = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(desk["agentID"] as? String == engineer.id.uuidString)
        #expect(desk["onTeam"] as? Bool == true)
        #expect(desk["pendingInboxCount"] as? Int == 0)
        let assigned = try #require(desk["assignedTasks"] as? [[String: Any]])
        #expect(assigned.count == 1 && assigned.first?["title"] as? String == "定义产品架构")
        let queue = try #require(desk["workQueue"] as? [[String: Any]])
        #expect(queue.count == 1 && queue.first?["promptPreview"] as? String == "build the frame")
        #expect(desk["profileChips"] != nil, "the chips ride the desk")
        #expect(desk["session"] != nil, "the desk names the session state")

        // byte-stable repetition: one state, one desk, same bytes
        let (rcAgain, rawAgain) = try command(["agentID": engineer.id.uuidString])
        #expect(rcAgain == 0 && rawAgain == raw, "one state serves one desk, byte-stable")

        // an unknown id refuses honestly
        let (rcGhost, msgGhost) = try command(["agentID": UUID().uuidString])
        #expect(rcGhost == -1)
        #expect(msgGhost.contains("no agent with id"), "\(msgGhost)")

        // neighbors stay shut
        let junk = strdup("deskx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the read left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc").path)))
func deskCLIServesHumanAndJSONFaces() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-desk-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.saveSnapshot()
    let expectedJSON = String(
        decoding: try store.deskJSON(agentID: engineer.id), as: UTF8.self)
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    let cli = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc")
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

    // the human face names the employee and counts honestly
    let human = try run(["desk", engineer.id.uuidString])
    #expect(human.rc == 0, "\(human.err)")
    #expect(human.out.contains("— desk ("), "the header names the role: \(human.out)")
    #expect(human.out.contains("assigned tasks:"), "\(human.out)")
    #expect(human.out.contains("work queue:"), "\(human.out)")

    // the JSON face serves the store serializer's exact bytes
    let json = try run(["desk", engineer.id.uuidString, "--json"])
    #expect(json.rc == 0, "\(json.err)")
    #expect(json.out.trimmingCharacters(in: .whitespacesAndNewlines)
        == expectedJSON.trimmingCharacters(in: .whitespacesAndNewlines),
        "CLI --json serves the door's exact bytes")

    // an unknown name refuses like resolveAgent always has
    let ghost = try run(["desk", "nobody-here"])
    #expect(ghost.rc != 0)
    #expect(ghost.err.contains("no employee named"), "\(ghost.err)")
}
