import Foundation
import Testing

@testable import OPCCompanyCore

// v1.18 `doctor` over the real @_cdecl ABI. The serializer tests prove the
// math; this file proves the CHANNEL: the object rides opc_bridge_last_error
// with rc=0, the contract version travels with the payload, repetition is
// byte-stable, and the unknown-verb refusal stays shut next to the new case.
// Isolation rides the seam (the support-dir env knob is first-touch bake —
// a setenv here would be dead theater): the seed is saved IN-PROCESS before
// create, so the door sees exactly this store. No override games over the
// process-global env: the environment parameter is pinned at the serializer
// layer.

// opc_bridge_create() is a process-global singleton, so every caller
// runs serially via OPCBridgeABIDoorTests (.serialized).
extension OPCBridgeABIDoorTests {
    @MainActor
    @Test func bridgeDoctorContractOverRealABI() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-doctor-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        CompanyPersistence.testSupportDirectoryOverride = tmp
        defer { CompanyPersistence.testSupportDirectoryOverride = nil }

        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.saveSnapshot()
        _ = store  // seeding is the point

        #expect(opc_bridge_create() == 0)
        defer { opc_bridge_destroy() }
        let verb = strdup("doctor")
        defer { free(verb) }

        #expect(opc_bridge_command(verb, nil) == 0)
        let raw = String(cString: try #require(opc_bridge_last_error()))
        let d = try #require(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(d["contractVersion"] as? String == "v1.18")
        #expect(d["supportDir"] as? String == tmp.path,
                "the bridge store loads from THIS dir — the doctor says so")
        #expect(d["stateFileExists"] as? Bool == true)
        #expect(d["warnings"] is [String], "warnings is always an array, empty is honest")
        #expect(d["tmuxAvailable"] is Bool && d["appRunning"] is Bool
                && d["overrideSet"] is Bool && d["seatsRunning"] is Int,
                "every fact key carries its declared type: \(d.keys.sorted())")

        // byte-stable repetition: same store, same facts, same bytes
        #expect(opc_bridge_command(verb, nil) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // a payload is ignored, not a refusal — the door takes none
        let p = strdup("{}")
        defer { free(p) }
        #expect(opc_bridge_command(verb, p) == 0)
        #expect(String(cString: try #require(opc_bridge_last_error())) == raw)

        // neighbors still refuse (the hole can't widen next to a new case)
        let junk = strdup("doctorx")
        defer { free(junk) }
        #expect(opc_bridge_command(junk, nil) == -1)

        // the query left the write path clean
        let sv = strdup("save")
        defer { free(sv) }
        #expect(opc_bridge_command(sv, nil) == 0)
    }
}
