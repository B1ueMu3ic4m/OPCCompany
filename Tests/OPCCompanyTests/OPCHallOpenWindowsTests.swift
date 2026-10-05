import Foundation
import Testing

@testable import OPCCompanyCore

// v2.11.0 the hall's "at desk" chip: the throttled open-windows probe.
// The probes are INJECTED — synthetic probe/session closures and a
// synthetic clock — so the throttle is verified without real tmux and
// without sleeps. Pure logic, no disk: no seam needed.

@MainActor
@Test func hallOpenWindowProbeIsThrottledWithinItsTTL() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var probeCalls = 0
    var sessionCalls = 0

    let first = store.terminalHallOpenWindowState(
        now: Date(timeIntervalSince1970: 1_000),
        ttl: 5,
        probe: { probeCalls += 1; return [UUID()] },
        sessionProbe: { sessionCalls += 1; return true })
    #expect(first.agentIDs.count == 1 && first.sessionRunning)

    // inside the TTL: the cached state serves every render, no probes
    let second = store.terminalHallOpenWindowState(
        now: Date(timeIntervalSince1970: 1_004),
        ttl: 5,
        probe: { probeCalls += 1; return [] },
        sessionProbe: { sessionCalls += 1; return false })
    #expect(second.agentIDs.count == 1 && second.sessionRunning, "the cached state survives")
    #expect(probeCalls == 1 && sessionCalls == 1, "throttled: one probe pair total")

    // past the TTL: the probes run again
    let third = store.terminalHallOpenWindowState(
        now: Date(timeIntervalSince1970: 1_006),
        ttl: 5,
        probe: { probeCalls += 1; return [] },
        sessionProbe: { sessionCalls += 1; return false })
    #expect(third.agentIDs.isEmpty && !third.sessionRunning)
    #expect(probeCalls == 2 && sessionCalls == 2)
}

@MainActor
@Test func hallOverviewGainsTheAtDeskChipOnlyWhenASessionExists() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    // no session: the base five chips, exactly the pre-v2.11 contract —
    // a machine without tmux renders no constant-zero seat chip.
    // ttl 0 = immediately stale, so the NEXT seed below actually lands.
    var warmForMetrics = false
    _ = store.terminalHallOpenWindowState(now: Date(), ttl: 0) {
        warmForMetrics = true
        return []
    } sessionProbe: { false }
    #expect(warmForMetrics)
    let withoutSession = store.terminalHallOverviewMetrics()
    #expect(withoutSession.map(\.title) == ["团队", "运行中", "待审批", "阻塞/失败", "最近风险"],
            "no session → no at-desk chip: \(withoutSession.map(\.title))")

    // a live session with one open window: the chip appears between
    // 运行中 and 待审批, kind .ok — served from the throttle cache.
    // ttl 0 forces THIS seed to run its probes (the ttl is read-side:
    // the previous cache is already past a zero window); metrics() then
    // reads the fresh cache within its own 5s ttl.
    _ = store.terminalHallOpenWindowState(now: Date(), ttl: 0) {
        [UUID(), UUID()]
    } sessionProbe: { true }
    let withSession = store.terminalHallOverviewMetrics()
    #expect(withSession.map(\.title) == ["团队", "运行中", "在座", "待审批", "阻塞/失败", "最近风险"],
            "the at-desk chip slots after 运行中: \(withSession.map(\.title))")
    #expect(withSession.first(where: { $0.title == "在座" })?.value == 2)
    #expect(withSession.first(where: { $0.title == "在座" })?.kind == .ok)
}

@MainActor
@Test func hallAtDeskChipStaysNeutralWhenNobodyIsSeated() throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.terminalHallOpenWindowState(now: Date(), ttl: 60) {
        []
    } sessionProbe: { true }
    let metrics = store.terminalHallOverviewMetrics()
    let chip = metrics.first(where: { $0.title == "在座" })
    #expect(chip?.value == 0 && chip?.kind == .neutral,
            "a live session with everyone away renders 0, neutrally: \(String(describing: chip))")
}
