import Foundation
import Testing

@testable import OPCCompanyCore

// v1.29 `goal` write receipt at the serializer: the handed goal plus the
// chain's just-created tasks — ids ready for `opc task <id>`. Pins: the
// shape, byte-stable repetition.

@MainActor
@Test func goalReceiptShapeIsStable() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-goal-receipt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var task = CompanyTask(productID: store.selectedProductID, title: "技术负责人拆解：ship it",
                           ownerID: store.ctoID, status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]

    let data = try store.goalReceiptJSON(goal: "ship it", created: [task])
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(d["goal"] as? String == "ship it")
    let tasks = try #require(d["tasks"] as? [[String: Any]])
    #expect(tasks.count == 1)
    #expect(tasks[0]["id"] as? String == task.id.uuidString)
    #expect(tasks[0]["status"] as? String == "running")
    #expect(UUID(uuidString: tasks[0]["id"] as! String) != nil,
            "the id a script sees feeds opc task directly")

    // byte-stable repetition
    #expect(try store.goalReceiptJSON(goal: "ship it", created: [task]) == data)
}
