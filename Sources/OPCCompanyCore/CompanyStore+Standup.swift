import Foundation

// v0.8.0 "the morning standup" — the ONE traffic door. Existing
// surfaces answer WHAT THERE IS (status, report, ledger, shelf); this
// answers what HAPPENED in the last window — the boss's first question
// of the day. Pure numbers: the door holds truth, each surface writes
// its own prose. Never stored, never serialized — recomputed per read
// from the same product-scoped view every other surface uses.

extension CompanyStore {
    /// One window's worth of company traffic, aggregated from three
    /// independent truth sources (events, approvals, artifacts). All
    /// counts are for the CURRENT product; `awaitingNow` is the live
    /// queue (not windowed — the boss owes these RIGHT NOW).
    public struct StandupWindow: Equatable, Sendable {
        public var hours: Int
        public var newWork: Int        // tasks created in the window
        public var decisions: Int      // approvals decided in the window
        public var deliveries: Int     // delivery-view artifacts recorded in the window
        public var missing: Int        // ...of those, files NOT on disk right now
        public var risks: Int          // risk events in the window
        public var awaitingNow: Int    // pending approvals as of this instant
        public var quiet: Bool {
            newWork + decisions + deliveries + risks == 0
        }
    }

    /// The door. `now` is injectable so tests (and scripts) pin the
    /// window without racing the wall clock. Decided rows WITHOUT
    /// decidedAt are legacy pre-v0.6 receipts: honestly excluded,
    /// never guessed. Events are the newest-first ledger already
    /// product-scoped at write time.
    public func standupWindow(hours: Int = 24, now: Date = Date()) -> StandupWindow {
        let since = now.addingTimeInterval(-Double(hours) * 3600)
        let productID = selectedProductID

        var newWork = 0
        var risks = 0
        for event in events {
            guard event.productID == productID,
                  event.createdAt >= since, event.createdAt <= now else { continue }
            switch event.kind {
            case .taskCreated: newWork += 1
            case .risk: risks += 1
            default: break
            }
        }

        var decisions = 0
        for approval in approvals where approval.productID == productID {
            if let decided = approval.decidedAt, decided >= since, decided <= now {
                decisions += 1
            }
        }

        var deliveries = 0
        var missing = 0
        for artifact in artifacts where artifact.productID == productID
            && artifact.createdAt >= since && artifact.createdAt <= now
            && isDeliveryArtifact(artifact) {
            deliveries += 1
            if !artifact.existsOnDisk { missing += 1 }
        }

        let awaitingNow = approvals.filter {
            $0.productID == productID && $0.status == .pending
        }.count

        return StandupWindow(hours: hours, newWork: newWork,
                             decisions: decisions, deliveries: deliveries,
                             missing: missing, risks: risks,
                             awaitingNow: awaitingNow)
    }

    /// The sentence every surface may quote: GUI headline (CLI prints
    /// the same math as rows, the shell as its card). Built from fixed
    /// Chinese-as-key fragments; numbers ride outside the lookups, the
    /// same pattern productProgressSummary uses.
    public func standupHeadlineText(hours: Int = 24, now: Date = Date()) -> String {
        let w = standupWindow(hours: hours, now: now)
        var parts: [String] = []
        if w.newWork > 0 { parts.append("\(w.newWork) " + "项新工作".L()) }
        if w.decisions > 0 { parts.append("\(w.decisions) " + "个决定".L()) }
        if w.deliveries > 0 { parts.append("\(w.deliveries) " + "项交付".L()) }
        if w.missing > 0 { parts.append("\(w.missing) " + "项缺失".L()) }
        if w.risks > 0 { parts.append("\(w.risks) " + "条风险".L()) }
        let traffic = parts.isEmpty ? "一切安静".L() : parts.joined(separator: " · ")
        var line = "过去 ".L() + "\(w.hours)" + " 小时：".L() + traffic
        if w.awaitingNow > 0 {
            line += " · " + "\(w.awaitingNow) " + "项审批等你".L()
        }
        return line
    }
}
