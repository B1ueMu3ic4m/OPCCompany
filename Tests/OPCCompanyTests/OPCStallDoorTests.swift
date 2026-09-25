import Foundation
import Testing

@testable import OPCCompanyCore

// The v0.10 stall door. Same discipline as the standup/team files: a
// FIXED clock everywhere (dwell math against wall luck is the same class
// of bug as window math against it), real seeds, and honesty about what
// the door may NOT claim.

@MainActor
private func seededStore(now: Date) -> CompanyStore {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let pid = store.selectedProductID
    let alice = store.agents.first!.id
    let ghost = UUID()   // an id the roster does not know
    var task = CompanyTask(productID: pid, title: "T", ownerID: alice,
                           status: .running, successCriteria: "s")
    store.tasks = [task]
    task = store.tasks[0]

    func item(_ agent: UUID, _ status: WorkItemStatus, ageMinutes: TimeInterval,
              id: UUID = UUID()) -> AgentWorkItem {
        AgentWorkItem(id: id, productID: pid, taskID: task.id, agentID: agent,
                      status: status, promptPreview: "p",
                      createdAt: now.addingTimeInterval(-86_400),
                      updatedAt: now.addingTimeInterval(-ageMinutes * 60))
    }
    // note: item ids stay distinct; tests below match by status+dwell,
    // the door returns itemID so every assertion can pin the exact row.
    store.workQueue = [
        item(alice, .running, ageMinutes: 45),          // stall
        item(alice, .waitingApproval, ageMinutes: 90),  // stall ON YOU
        item(alice, .waitingReview, ageMinutes: 20),    // under threshold
        item(alice, .completed, ageMinutes: 600),       // terminal: never
        item(alice, .failed, ageMinutes: 600),          // terminal: never
        item(alice, .queued, ageMinutes: -10),          // FUTURE stamp: refused
        item(ghost, .running, ageMinutes: 31),          // unattributed stall
    ]
    return store
}

@Test @MainActor func stallDoorCountsOnlyRealStallsOnFixedClock() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = seededStore(now: now)
    let rows = store.stallWatch(now: now)

    // exactly three stall rows: the 90m approval, 45m run, 31m ghost.
    // The 20m item (under), both terminals, and the future stamp are out.
    #expect(rows.count == 3, "only non-terminal over-threshold items stall: \(rows)")
    // longest-frozen first among attributed; unattributed sorts LAST
    // (existence conditional, v0.9 lesson: never assert position blindly)
    #expect(rows[0].dwellMinutes == 90 && rows[0].waitingOnYou)
    #expect(rows[1].dwellMinutes == 45 && !rows[1].waitingOnYou)
    #expect(rows.last?.agentID == nil, "the ghost row is present and last: \(rows)")
    // dwell is whole minutes of the fixed clock, clamped — never negative,
    // and the door does not round a 45m item to an hour
    #expect(rows.map(\.dwellMinutes) == [90, 45, 31])
}

@Test @MainActor func stallDoorThresholdIsAParameterNotAnOpinion() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = seededStore(now: now)
    // a caller who wants CircleCI-grade noise gets MORE rows, never fewer
    let stricter = store.stallWatch(overMinutes: 10, now: now)
    #expect(stricter.count == 4, "the 20m waitingReview joins at >10: \(stricter)")
    #expect(!stricter.contains { $0.dwellMinutes == 600 },
            "terminal history never joins at any threshold")
    // a boss who trusts GitLab's 1h line sees only the approval jam
    let lazier = store.stallWatch(overMinutes: 60, now: now)
    #expect(lazier.count == 1 && lazier[0].waitingOnYou)
}

@Test @MainActor func stallDoorWaitingOnYouIsStatusFactNotAccusation() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = seededStore(now: now)
    let rows = store.stallWatch(now: now)
    // the 90m waitingApproval is waitingOnYou; the 45m running is NOT —
    // even though a human could argue an agent is "parked" either way.
    let onYou = rows.filter(\.waitingOnYou)
    #expect(onYou.count == 1 && onYou[0].dwellMinutes == 90)
    // and the flag survives attribution loss: a ghost waitingApproval row
    // still says waitingOnYou (it is the STATUS, not the person). NOTE:
    // CompanyStore is a class — an isolated scenario needs its OWN
    // bootstrap, `var s = store` would alias every later assertion.
    let s = CompanyStore.bootstrap(loadPersisted: false)
    s.workQueue = [AgentWorkItem(productID: s.selectedProductID,
                                 taskID: s.tasks.first?.id ?? UUID(),
                                 agentID: UUID(),
                                 status: .waitingApproval, promptPreview: "p",
                                 updatedAt: now.addingTimeInterval(-7200))]
    let g = s.stallWatch(now: now)
    #expect(g.count == 1 && g[0].waitingOnYou && g[0].agentID == nil,
            "the fact outlives the name: \(g)")
}

@Test @MainActor func stallDoorIsPureReadAndQuietWhenEmpty() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = seededStore(now: now)
    // ask twice: deterministic, no mutation (same array = same answer)
    let first = store.stallWatch(now: now)
    #expect(store.stallWatch(now: now) == first)
    // the headline BEFORE any further mutation: three stalls, worst first
    let line = store.stallHeadlineText(now: now)
    #expect(line.contains("90") && line.contains("等你审批"),
            "the headline quotes the door's worst row: \(line)")
    // a young company answers [] and the headline says so honestly — on
    // its OWN store (class aliasing would drain the stalled one above)
    let quiet = CompanyStore.bootstrap(loadPersisted: false)
    quiet.workQueue = []
    #expect(quiet.stallWatch(now: now).isEmpty)
    #expect(quiet.stallHeadlineText(now: now).contains("没有停滞"),
            "quiet = no stall sentence: \(quiet.stallHeadlineText(now: now))")
}
