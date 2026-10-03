import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.11 catch-up door: a COMPOSITION, not new math. Every number in
// the page must equal the door it quotes (standupWindow / teamWindow /
// stallWatch / the pending queue / the v0.7 existence door) on the same
// fixed clock — if this file and a door ever disagree, the DOOR is
// right. Pinned here: section order IS the contract (quiet sections
// keep their place), lists ride their door's own order with the
// unattributed row last, the 8-row cap says "...and N more" instead of
// pretending, no wall-clock lives inside (repeat reads are byte-stable),
// and the pure-read promise holds (state bytes never move).

@MainActor
private func catchUpSeeded(now: Date) -> (CompanyStore, UUID, UUID, UUID) {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    let bob = store.agents[1].id
    let ghost = UUID()   // an id the roster does not know

    store.events = [
        CompanyEvent(productID: pid, kind: .taskCreated, title: "新活", detail: "d",
                     createdAt: now.addingTimeInterval(-3600)),
        CompanyEvent(productID: pid, kind: .risk, title: "风险", detail: "d",
                     agentID: alice, createdAt: now.addingTimeInterval(-1800)),
        // 25h ago — outside the default window
        CompanyEvent(productID: pid, kind: .taskCreated, title: "旧活", detail: "d",
                     createdAt: now.addingTimeInterval(-25 * 3600)),
    ]
    store.approvals = [
        ApprovalRequest(productID: pid, requesterID: alice, title: "批", reason: "r",
                        status: .approved, decidedAt: now.addingTimeInterval(-600)),
        ApprovalRequest(productID: pid, requesterID: bob, title: "等最久", reason: "r",
                        status: .pending, createdAt: now.addingTimeInterval(-7200)),
        ApprovalRequest(productID: pid, requesterID: nil, title: "等较新", reason: "r",
                        status: .pending, createdAt: now.addingTimeInterval(-60)),
    ]

    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]
    func item(_ agent: UUID, _ status: WorkItemStatus, ageMinutes: TimeInterval) -> AgentWorkItem {
        AgentWorkItem(id: UUID(), productID: pid, taskID: task.id, agentID: agent,
                      status: status, promptPreview: "p",
                      createdAt: now.addingTimeInterval(-86_400),
                      updatedAt: now.addingTimeInterval(-ageMinutes * 60))
    }
    store.workQueue = [
        item(alice, .waitingApproval, ageMinutes: 90),  // stuck ON YOU
        item(ghost, .running, ageMinutes: 45),          // stuck, unattributed
        item(alice, .waitingReview, ageMinutes: 5),     // under threshold
    ]
    return (store, alice, bob, ghost)
}

@Test @MainActor func catchUpPageComposesTheDoorsOnOneFixedClock() throws {
    let tmp = try temporarySupportDir("catchup-compose")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let (store, alice, _, _) = catchUpSeeded(now: now)

    let real = tmp.appendingPathComponent("ship.md")
    try "x".data(using: .utf8)!.write(to: real)
    store.artifacts = [
        ArtifactRecord(productID: store.selectedProductID, taskID: taskID(store),
                       kind: .report, title: "在", path: real.path, summary: "s",
                       createdAt: now.addingTimeInterval(-900)),
        ArtifactRecord(productID: store.selectedProductID, taskID: taskID(store),
                       kind: .report, title: "没了", path: tmp.appendingPathComponent("ghost").path,
                       summary: "s", createdAt: now.addingTimeInterval(-900)),
    ]

    let page = store.catchUpPage(now: now)

    // section order IS the contract — quiet or not, all six appear, in order
    let order = ["# Catch-up — ", "## Traffic (last 24h)", "## Who did what (last 24h)",
                 "## Stuck (parked over 30 min)", "## Waiting on you (2)",
                 "## Shelf integrity (last 24h)", "Pure read — this page wrote nothing."]
    var cursor = page.startIndex
    for marker in order {
        let range = page.range(of: marker, range: cursor..<page.endIndex)
        #expect(range != nil, "section out of order or missing: \(marker)")
        if let range { cursor = range.upperBound }
    }

    // traffic numbers equal the standup door on the same clock
    let w = store.standupWindow(now: now)
    #expect(page.contains("new work: \(w.newWork)"))
    #expect(page.contains("delivered: \(w.deliveries)  (1 MISSING on disk NOW)"))

    // stuck rows ride the stall door's order: longest first, ghost LAST,
    // and the approval-parked row says WAITS ON YOU
    let stalls = store.stallWatch(now: now)
    #expect(stalls.count == 2)
    let stuck = page.slice(from: "## Stuck", to: "## Waiting")
    #expect(stuck.contains("90 min — waitingApproval"))
    #expect(stuck.contains("WAITS ON YOU"))
    let ghostLine = stuck.line(containing: "45 min")
    #expect(ghostLine != nil && ghostLine!.hasSuffix("— unattributed") == false)
    #expect(page.slice(from: "## Stuck", to: "## Waiting")
        .line(containing: "90 min")!.contains("45 min") == false)

    // desk: oldest-waiting first, "raised by" rides the real roster edge,
    // the requester-less row still shows (title only)
    let desk = page.slice(from: "## Waiting", to: "## Shelf")
    let oldest = desk.line(containing: "等最久")
    #expect(oldest != nil && oldest!.contains(store.agents[1].displayName))
    #expect(desk.contains("等较新"))
    #expect(desk.line(containing: "等较新")!.contains("raised by") == false)

    // shelf: the ghost delivery is named with its PATH; the real one isn't
    let shelf = page.slice(from: "## Shelf", to: "---")
    #expect(shelf.contains("MISSING: 没了"))
    #expect(!shelf.contains("MISSING: 在"))
    _ = alice
}

@Test @MainActor func catchUpPageIsByteStableAndNeverWrites() throws {
    // Seam-PRIVATE dir: this test used to pure-read the SUITE-shared dir
    // (seeding nothing), so an async bystander's cleanup could delete the
    // bytes under it — tonight's flake. Now: a fresh private dir, the seam
    // set first, a seeded-and-SAVED state file, then the same pins run
    // against that dir. A dir only this atomic body can name has no
    // bystanders and needs no restore dance.
    let tmp = try temporarySupportDir("catchup-stable")
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let (store, _, _, _) = catchUpSeeded(now: now)
    store.saveSnapshot()  // the pure-read pin needs state bytes ON DISK

    let stateFile = tmp.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)

    let first = store.catchUpPage(now: now)
    let second = store.catchUpPage(now: now)
    #expect(first == second, "no wall-clock inside: two reads of one state are byte-identical")
    #expect(!first.contains("\(Date().timeIntervalSince1970)"))

    let afterBytes = try? Data(contentsOf: stateFile)
    #expect(priorBytes == afterBytes, "pure read: the page never moves state bytes")
    #expect(FileManager.default.fileExists(atPath: stateFile.path) == (priorBytes != nil))
}

@Test @MainActor func catchUpQuietCompanyKeepsEverySectionHonest() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // an EMPTY company: no events, no approvals, no queue, no artifacts
    store.events = []
    store.approvals = []
    store.workQueue = []
    store.artifacts = []
    let page = store.catchUpPage(now: now)

    #expect(page.contains("- a quiet window — nothing moved."))
    #expect(page.contains("- nobody — a quiet window."))
    #expect(page.contains("- nothing stuck."))
    #expect(page.contains("- nothing — your desk is clear."))
    #expect(page.contains("- every delivery in the window is on disk."))
    #expect(page.contains("## Waiting on you (0)"))
    // quiet never collapses the shape: every section header still present
    for marker in ["## Traffic", "## Who did what", "## Stuck",
                   "## Waiting on you", "## Shelf integrity"] {
        #expect(page.contains(marker), "quiet company keeps its section: \(marker)")
    }
}

@Test @MainActor func catchUpCapsLongListsWithAnHonestTail() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    store.events = []
    store.workQueue = []
    var approvals: [ApprovalRequest] = []
    for i in 1...11 {
        approvals.append(ApprovalRequest(productID: pid, title: "等\(i)分钟", reason: "r",
                                         status: .pending,
                                         createdAt: now.addingTimeInterval(Double(-i * 60))))
    }
    store.approvals = approvals

    let desk = store.catchUpPage(now: now).slice(from: "## Waiting", to: "## Shelf")
    // oldest-waiting first: 等11分钟 waited longest, so the 8 rendered
    // rows are 等11分钟…等4分钟 (createdAt ascending == door's order)
    #expect(desk.contains("等11分钟"), "the longest-waiting row renders first")
    #expect(desk.contains("等4分钟"), "the 8th row (4 minutes) still renders")
    #expect(!desk.contains("等3分钟"), "row 9 is past the cap")
    #expect(desk.contains("...and 3 more."), "the tail counts honestly: 11 - 8")
}

// ——— tiny slice/line helpers local to this file ———

@MainActor
private func taskID(_ store: CompanyStore) -> UUID? {
    store.tasks.first?.id
}

private func temporarySupportDir(_ tag: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("opc-\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension String {
    func slice(from: String, to: String) -> String {
        guard let a = range(of: from), let b = range(of: to, range: a.upperBound..<endIndex)
        else { return "" }
        return String(self[a.upperBound..<b.lowerBound])
    }
    func line(containing needle: String) -> String? {
        components(separatedBy: "\n").first { $0.contains(needle) }
    }
}
