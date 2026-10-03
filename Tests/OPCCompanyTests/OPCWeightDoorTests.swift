import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.15 weight door: scale without opinions. Pinned here: the total
// is the encoder's truth (status --json's byte count on the same state),
// sections rank heaviest-first on the sortedKeys scale and say so (the
// sum may differ from the total by key-order overhead — honest, not
// fudged), terminal-log share rides the door permanently (the v0.70
// slimming's quantity), and the advisory flag reuses the maintenance
// panel's own constant. Repeat reads are byte-stable; the door is a
// pure read (state bytes never move).

@MainActor
private func weightSeeded(now: Date) throws -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-3600)),
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

@Test @MainActor func weightDoorMeasuresTheEncoderTruthAndRanksHonestly() throws {
    let tmp = try temporarySupportDir("weight-math")
    defer { try? FileManager.default.removeItem(at: tmp) }
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer { CompanyPersistence.testSupportDirectoryOverride = nil }

    _ = try weightSeeded(now: Date())

    let w = try CompanyStore.bootstrap(loadPersisted: true).snapshotWeightReport()

    // the total is the encoder's truth — the same bytes status --json serves
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let reference = try encoder.encode(CompanyStore.bootstrap(loadPersisted: true).currentSnapshot()).count
    #expect(w.totalBytes == reference,
            "total must be the encoder's byte count: \(w.totalBytes) vs \(reference)")

    // sections rank heaviest first; ties break by name
    let bytes = w.sections.map(\.bytes)
    #expect(bytes == bytes.sorted(by: >), "heaviest first: \(w.sections)")
    #expect(w.sections.first?.name == "events" || (w.sections.first?.bytes ?? 0) > 0)

    // the log share rides the door: terminalLogBytes is the section's
    // own size and the share is its floored percentage of the total
    let logSection = try #require(w.sections.first(where: { $0.name == "productTerminalLogs" }))
    #expect(w.terminalLogBytes == logSection.bytes)
    #expect(w.logSharePercent == Int((Double(logSection.bytes) / Double(w.totalBytes) * 100).rounded(.down)))

    // the threshold is the maintenance panel's own constant — no second opinion
    #expect(w.advisoryBytes == Int(CompanyStore.maintenanceStateSnapshotAdvisoryBytes))
    // a fresh seeded snapshot is nowhere near 20 MB
    #expect(!w.exceedsAdvisory)

    // byte-stable repeat reads
    let again = try CompanyStore.bootstrap(loadPersisted: true).snapshotWeightReport()
    #expect(again.totalBytes == w.totalBytes && again.sections == w.sections)

    // pure read: the door never moves state bytes
    let stateFile = CompanyPersistence.supportDirectory
        .appendingPathComponent("company-state.json")
    let before = try? Data(contentsOf: stateFile)
    _ = try CompanyStore.bootstrap(loadPersisted: true).snapshotWeightReport()
    #expect((try? Data(contentsOf: stateFile)) == before)
}

@Test @MainActor func weightJSONShapeIsStableAndComplete() throws {
    let tmp = try temporarySupportDir("weight-json")
    defer { try? FileManager.default.removeItem(at: tmp) }
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer { CompanyPersistence.testSupportDirectoryOverride = nil }

    _ = try weightSeeded(now: Date())
    let store = CompanyStore.bootstrap(loadPersisted: true)
    let data = try store.weightJSON()
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let keys = Set((obj ?? [:]).keys)
    #expect(keys == ["totalBytes", "sections", "advisoryBytes",
                     "exceedsAdvisory", "terminalLogBytes", "logSharePercent"],
            "six contract keys: \(keys)")
    let again = try store.weightJSON()
    #expect(again == data, "sortedKeys: repeat reads are byte-stable")
}

private func temporarySupportDir(_ tag: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
