import Foundation
import Testing

@testable import OPCCompanyCore

// v1.15 `autopilot` over the real @_cdecl ABI: ONE full store dispatch
// per call — the same primitive the desktop app's button and
// `opc autopilot` drive — then a save. The bridge never decides how
// many cycles the office deserves; a loop is the caller's job. Lives
// in the serialized OPCBridgeABIDoorTests suite (the bridge is a
// process-global singleton); seeding rides the CompanyPersistence seam.

extension OPCBridgeABIDoorTests {

    @MainActor
    @Test func bridgeAutopilotDispatchesOnceOverRealABI() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-bridge-autopilot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer {
            CompanyPersistence.testSupportDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tmp)
        }
        let store = CompanyStore.bootstrap(loadPersisted: false)
        guard store.startCTOSupervisorGoal(goal: "ship the autopilot demo") != nil else {
            Issue.record("goal seed refused — the test premise broke")
            return
        }
        store.saveSnapshot()
        let queueBefore = store.workQueue.filter { $0.productID == store.selectedProductID }.count

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("autopilot")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0, "the dispatch answers over the ABI")
        // the dispatch moved the seeded goal: the work queue grew
        let reloaded = try #require(CompanyPersistence.load())
        let queueAfter = reloaded.workQueue
            .filter { $0.productID == store.selectedProductID }.count
        #expect(queueAfter > queueBefore,
                "one full dispatch enqueues the goal's work: \(queueBefore) → \(queueAfter)")

        // a second dispatch stays rc=0 — idempotent at the bridge mouth
        #expect(opc_bridge_command(verb, nil) == 0)

        // neighbors stay shut
        let junk = strdup("autopilotx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the write path left the snapshot savable
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}


extension OPCBridgeABIDoorTests {

    @MainActor
    @Test func bridgeCheckpointFilesWithTheBossReasonOverRealABI() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-bridge-checkpoint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer {
            CompanyPersistence.testSupportDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tmp)
        }
        CompanyStore.bootstrap(loadPersisted: false).saveSnapshot()

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }

        func command(_ payload: [String: Any]) throws -> (Int32, String) {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let p = strdup(String(decoding: data, as: UTF8.self))
            defer { free(p) }
            let verb = strdup("checkpoint")
            defer { free(verb) }
            let rc = opc_bridge_command(verb, p)
            return (rc, String(cString: opc_bridge_last_error()!))
        }

        // a landed checkpoint: rc=0, and the archive exists on disk
        let (rc, _) = try command(["reason": "before the jump"])
        #expect(rc == 0)
        let archives = try FileManager.default.contentsOfDirectory(
            at: tmp.appendingPathComponent("checkpoints", isDirectory: true),
            includingPropertiesForKeys: nil)
        #expect(archives.count == 1, "the archive actually landed")

        // an empty reason refuses before any write
        let (rcEmpty, msgEmpty) = try command(["reason": "   "])
        #expect(rcEmpty == -1)
        #expect(msgEmpty.contains("non-empty reason"), "\(msgEmpty)")

        // a missing reason refuses too
        let (rcMissing, msgMissing) = try command([:])
        #expect(rcMissing == -1)
        #expect(msgMissing.contains("non-empty reason"), "\(msgMissing)")

        // neighbors stay shut
        let junk = strdup("checkpointx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)
    }
}
