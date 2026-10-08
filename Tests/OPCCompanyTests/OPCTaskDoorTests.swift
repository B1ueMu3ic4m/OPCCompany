import Foundation
import Testing

@testable import OPCCompanyCore

// v1.22 `task_show` at the serializer: one task's full file. Pins: the
// task fields with owner resolved; every edge class lands (work items,
// artifacts with existsNow judged AT READ TIME, approvals, referencing
// messages); an unknown id refuses honestly; repetition is byte-stable;
// the pure-read promise holds.

@MainActor
private func seedTaskFile() -> (CompanyStore, UUID, URL) {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-task-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    var task = CompanyTask(productID: pid, title: "实现 goals 门",
                           ownerID: alice, status: .running,
                           successCriteria: "opc goals 能读出链",
                           artifactPath: nil)
    store.tasks = [task]
    task = store.tasks[0]
    let realFile = supportDir.appendingPathComponent("ship.md")
    try! "shipped".data(using: .utf8)!.write(to: realFile)
    store.workQueue = [
        AgentWorkItem(productID: pid, taskID: task.id, agentID: alice,
                      status: .running, promptPreview: "写实现"),
    ]
    store.artifacts = [
        ArtifactRecord(productID: pid, taskID: task.id, kind: .report,
                       title: "实现报告", path: realFile.path, summary: "s"),
    ]
    store.postAgentMessage(productID: pid, fromAgentID: store.ctoID,
                           toAgentID: alice, taskID: task.id,
                           kind: .taskDispatched, subject: "派发：实现 goals 门",
                           body: "见任务卡", persist: false)
    return (store, task.id, supportDir)
}

@MainActor
@Test func taskDoorComposesTheWholeFile() throws {
    let (store, taskID, supportDir) = seedTaskFile()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: CompanyPersistence.stateURL)

    let data = try store.taskJSON(taskID: taskID)
    let d = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(d["title"] as? String == "实现 goals 门")
    #expect(d["status"] as? String == "running")
    #expect(d["owner"] as? String == store.agents.first!.displayName,
            "owner arrives resolved, not as a uuid")
    #expect(d["successCriteria"] as? String == "opc goals 能读出链")

    let workItems = try #require(d["workItems"] as? [[String: Any]])
    #expect(workItems.count == 1)
    #expect(workItems[0]["agent"] as? String == store.agents.first!.displayName)
    #expect(workItems[0]["status"] as? String == "running")

    let artifacts = try #require(d["artifacts"] as? [[String: Any]])
    #expect(artifacts.count == 1)
    #expect(artifacts[0]["existsNow"] as? Bool == true,
            "the file is real — the door judges at read time")

    let messages = try #require(d["messages"] as? [[String: Any]])
    #expect(messages.count == 1, "the dispatch message references this task")
    #expect(messages[0]["kind"] as? String == "taskDispatched")

    // approvals empty is honest — none were seeded
    #expect(try #require(d["approvals"] as? [[String: Any]]).isEmpty)

    // byte-stable repetition (sync body: nothing moved between calls)
    #expect(try store.taskJSON(taskID: taskID) == data)

    // the read left the write path clean
    #expect(try Data(contentsOf: CompanyPersistence.stateURL) == seededBytes)
}

@MainActor
@Test func taskDoorRefusesUnknownIdsAndJudgesMissingFiles() throws {
    let (store, _, supportDir) = seedTaskFile()
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    // an unknown id refuses, never fabricates an empty file
    #expect(throws: OPCBridgeRefusal.self) {
        try store.taskJSON(taskID: UUID())
    }

    // the seeded artifact's file, deleted AFTER seeding: existsNow flips
    try FileManager.default.removeItem(at: supportDir.appendingPathComponent("ship.md"))
    let d = try #require(JSONSerialization.jsonObject(
        with: try store.taskJSON(taskID: store.tasks[0].id)) as? [String: Any])
    let artifacts = try #require(d["artifacts"] as? [[String: Any]])
    #expect(artifacts[0]["existsNow"] as? Bool == false,
            "a deleted file is MISSING — the shelf never freezes a stale verdict")
}
