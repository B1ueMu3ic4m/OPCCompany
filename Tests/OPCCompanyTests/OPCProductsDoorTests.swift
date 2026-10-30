import Foundation
import Testing

@testable import OPCCompanyCore

// v1.27 `products_list` at the serializer: every product, snapshot order.
// Pins: ids are real uuids, stage names ride, `selected` marks exactly the
// store's own selection (one true, the rest false), byte-stable order IS
// the contract, and the pure-read promise holds.

@MainActor
@Test func productsDoorListsTheRosterInSnapshotOrder() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-products-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.productsListJSON()
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(rows.count == store.products.count,
            "one row per product, snapshot order: \(rows.count) vs \(store.products.count)")
    #expect(rows.allSatisfy {
        UUID(uuidString: $0["id"] as? String ?? "") != nil
            && $0["name"] is String && $0["stage"] is String
            && $0["selected"] is Bool
    })
    let selected = rows.filter { $0["selected"] as? Bool == true }
    #expect(selected.count == 1, "exactly one selection: \(selected)")
    #expect(selected[0]["id"] as? String == store.selectedProductID.uuidString)

    // byte-stable repetition (sync body)
    #expect(try store.productsListJSON() == data)

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}
