import Foundation
import Testing

@testable import OPCCompanyCore

// v1.26 `checkpoints_list` at the serializer: the on-disk archive, newest
// first. Pins: created checkpoints land as rows (file/bytes/modifiedAt);
// the newest-first order matches the CLI text's discipline; an empty
// archive answers []; the limit knob caps; the pure-read promise holds.

@MainActor
@Test func checkpointsDoorListsTheArchiveNewestFirst() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cpl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(try (JSONSerialization.jsonObject(
        with: try store.checkpointsListJSON()) as? [[String: Any]] ?? []).isEmpty,
        "an empty archive answers [] — never a fake row")

    store.createSafetyCheckpoint(reason: "first")
    // the same-second overwrite fix guarantees distinct filenames
    store.createSafetyCheckpoint(reason: "second")
    // the CREATION writes (artifact + event + save); the DOOR must not —
    // baseline AFTER the seeds, before the reads
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let rows = try #require(JSONSerialization.jsonObject(
        with: try store.checkpointsListJSON()) as? [[String: Any]])
    #expect(rows.count == 2, "two checkpoints, two rows: \(rows)")
    #expect(rows.allSatisfy {
        ($0["file"] as? String)?.hasPrefix("checkpoint-") == true
            && ($0["file"] as? String)?.hasSuffix(".json") == true
            && $0["bytes"] is Int && $0["modifiedAt"] is Int
    })
    #expect(rows[0]["modifiedAt"] as? Int ?? 0 >= rows[1]["modifiedAt"] as? Int ?? 0,
            "newest first")

    // the limit knob caps
    let capped = try #require(JSONSerialization.jsonObject(
        with: try store.checkpointsListJSON(limit: 1)) as? [[String: Any]])
    #expect(capped.count == 1)

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}

@MainActor
@Test func checkpointsDoorMatchesTheCliTextCount() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cpl-text-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    for i in 0..<3 {
        store.createSafetyCheckpoint(reason: "door \(i)")
    }
    // one serializer, no second opinion: the door's rows and the CLI
    // text's entries describe the SAME archive
    let rows = try #require(JSONSerialization.jsonObject(
        with: try store.checkpointsListJSON()) as? [[String: Any]])
    let text = store.safetyCheckpointListText(limit: 5)
    #expect(rows.count == 3)
    #expect(text.contains("3. "), "the text numbers the same archive: \(text.prefix(60))")
}
