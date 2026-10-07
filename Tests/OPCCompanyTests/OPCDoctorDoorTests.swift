import Foundation
import Testing

@testable import OPCCompanyCore

// v1.18 `doctor` at the serializer: the environment-facts object. Pins:
// the contract version string, seam-aware support dir + state file bytes,
// tmux/seats/writer-guard facts that COHERED with the same accessors the
// write guard uses (machine-independent — never hard-coded absolutes),
// override injection through the environment parameter, the first-run
// shape (no state file yet), byte-stable repetition, and the pure-read
// promise (seeded snapshot bytes must not move).

@MainActor
@Test func doctorDoorReportsFactsNotVerdicts() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-doctor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()
    let stateURL = CompanyPersistence.stateURL
    let seededBytes = try Data(contentsOf: stateURL)

    let data = try store.doctorJSON()
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(d["contractVersion"] as? String == "v1.18")
    #expect(d["supportDir"] as? String == supportDir.path,
            "the doctor reports the dir the store ACTUALLY uses")
    #expect(d["stateFileExists"] as? Bool == true)
    let expectedBytes = try #require(
        (try FileManager.default.attributesOfItem(atPath: stateURL.path))[.size] as? Int)
    #expect(d["stateFileBytes"] as? Int == expectedBytes)

    // machine-independent coherence: the doctor quotes the SAME probes the
    // write guard and the terminal hall use — never a second opinion
    #expect(d["tmuxAvailable"] as? Bool ==
        (AgentProcessRunner.resolvedExecutablePath(for: "tmux") != nil))
    #expect(d["seatsRunning"] as? Int == 0, "a fresh process spawned no seats")
    #expect(d["appRunning"] as? Bool == OPCWriteGuard.isAppRunning())
    #expect(d["overrideSet"] as? Bool == false, "the ambient env carries no override")

    let warnings = try #require(d["warnings"] as? [String])
    #expect(!warnings.contains { $0.contains("OPC_ALLOW_CONCURRENT_WRITE") },
            "no override, no override warning")
    #expect(!warnings.contains { $0.contains("no state file yet") },
            "the state file exists — no first-run warning")
    if OPCWriteGuard.isAppRunning() {
        #expect(warnings.contains { $0.contains("OPCCompany.app is running") },
                "the app-conflict fact always rides its warning")
    }

    // byte-stable repetition (sync body: nothing moved between calls)
    #expect(try store.doctorJSON() == data, "same facts, same bytes")

    // the query left the write path clean
    #expect(try Data(contentsOf: stateURL) == seededBytes)
}

@MainActor
@Test func doctorDoorSeesTheOverrideThroughTheEnvironmentParameter() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-doctor-ovr-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let d = try #require(JSONSerialization.jsonObject(
        with: try store.doctorJSON(
            environment: ["OPC_ALLOW_CONCURRENT_WRITE": "1"])) as? [String: Any])
    #expect(d["overrideSet"] as? Bool == true)
    let warnings = try #require(d["warnings"] as? [String])
    #expect(warnings.contains { $0.contains("writer guard is OFF") },
            "an overridden guard is exactly what the doctor exists to name")
}

@MainActor
@Test func doctorDoorNamesTheFirstRunHonestly() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-doctor-first-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    try FileManager.default.removeItem(at: CompanyPersistence.stateURL)
    // bootstrap persists an initial company; removing it models a genuinely
    // wiped dir — the door reads the disk at call time, never its memory

    let d = try #require(JSONSerialization.jsonObject(
        with: try store.doctorJSON()) as? [String: Any])
    #expect(d["stateFileExists"] as? Bool == false)
    #expect(d["stateFileBytes"] is NSNull, "a missing file has no byte count")
    let warnings = try #require(d["warnings"] as? [String])
    #expect(warnings.contains { $0.contains("no state file yet") },
            "first run is a fact the visitor needs, not an error")
}
