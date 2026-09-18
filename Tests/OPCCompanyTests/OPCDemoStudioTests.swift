import Foundation
import Testing

@testable import OPCCompanyCore

// ── The demo studio (OPCDemoStudio → OPCDemoGif) is the pipeline that
// turns REAL workstation views into README/GIF marketing frames without
// screen recording. Its contract is thin but load-bearing: the gallery
// must cover EVERY agent status, each with its own distinct desk name,
// and the canvas must be sized for the 5-column grid. A future status
// added to AgentStatus without a gallery entry would silently render a
// blank column in marketing — this test makes that a build-time red.
@MainActor
@Test func demoStudioCoversEveryAgentStatus() {
    let statuses = AgentStatus.allCases
    let names = statuses.map { OPCDemoStudio.galleryName(for: $0) }
    #expect(Set(names).count == statuses.count, "two statuses share a desk name — marketing grid would look duplicated")
    for status in statuses {
        #expect(!status.title.isEmpty, "\(status.rawValue) has no bubble title")
        // every ethnicity slot stays inside the cycle (index math bug)
        let idx = statuses.firstIndex(of: status)!
        _ = OPCDemoStudio.galleryEthnicity(index: idx)
    }
    // canvas fits 5 rigs + spacing + padding (800pt width)
    #expect(OPCDemoStudio.galleryWidth >= 5 * 142 + 4 * 10 + 36)
    #expect(OPCDemoStudio.galleryHeight >= 2 * 190 + 14 + 36)
    // the rigs themselves must still render (pure function of date)
    let agent = OPCDemoStudio.demoAgent(for: .coding, name: "T", ethnicity: .chinese)
    #expect(agent.role == .codeEngineer)
}
