import Foundation
import Testing

@testable import OPCCompanyCore

// v1.31 `checkpoint` write receipt at the serializer: the just-created
// filing — file, bytes, the reason verbatim — read back from the archive.
// Pins: the receipt names a REAL filing with its bytes; byte-stable
// repetition; an empty archive (failed creation) refuses.

@MainActor
@Test func checkpointReceiptNamesTheFiling() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cp-receipt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.createSafetyCheckpointChecked(reason: "receipt smoke"))
    let data = try store.checkpointReceiptJSON(reason: "receipt smoke")
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((d["file"] as? String)?.hasPrefix("checkpoint-") == true)
    #expect((d["file"] as? String)?.hasSuffix(".json") == true)
    #expect(d["bytes"] is Int && (d["bytes"] as? Int ?? 0) > 0,
            "the receipt carries the filing's real size")
    #expect(d["reason"] as? String == "receipt smoke",
            "the reason rides verbatim")

    // byte-stable repetition
    #expect(try store.checkpointReceiptJSON(reason: "receipt smoke") == data)
}
