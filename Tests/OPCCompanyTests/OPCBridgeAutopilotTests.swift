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
