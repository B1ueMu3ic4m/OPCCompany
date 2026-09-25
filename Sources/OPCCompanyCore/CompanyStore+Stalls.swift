import Foundation

// v0.10.0 "the stall watch" — the ONE stall door. v0.8 answers WHAT moved,
// v0.9 answers WHO moved it; this answers what STOPPED moving and for how
// long, so the boss sees the queue jamming before the company silently
// waits on them.
//
// Ground rules, inherited from the sibling doors and not negotiable here:
//   * PURE READ. The door never touches a single record — a stall is
//     inferred at question time from non-terminal work-queue items, never
//     stored as a flag (a stored verdict would freeze a live one, the v0.7
//     lesson).
//   * `now` is injectable. Dwell math against wall-clock luck fails the
//     same way the v0.8 window tests would have; every caller passes a
//     clock in tests, production defaults to Date().
//   * Dwell comes from the work-queue item's `updatedAt` — the ONLY
//     kernel-adjacent timestamp the queue carries. The event log is
//     capped (200 entries) and cannot back a dwell claim, so it is not
//     consulted for a second source. One truth, one field.
//   * The future is refused, not guessed: an item stamped ahead of `now`
//     is excluded honestly (v0.8's discipline).
//   * Attribution reuses v0.9's three shapes: real agent, or the named
//     unattributed bucket when the roster no longer knows the id. The
//     door never invents a person.
//   * The threshold is a parameter with a default (30 minutes), NOT a
//     hidden constant — CircleCI cancels at 10min silence, GitLab marks
//     a running job stale at 1h of no updates; 30min sits in the proven
//     alert band and the caller may pick their own.
//   * waitingOnYou is a STATUS FACT (the item waits on approval), never
//     an accusation; surfaces decide their own wording.

extension CompanyStore {

    /// One stalled work item: who owns it, what state it sits in, and how
    /// long it has been frozen there as of `now`.
    public struct StallRow: Equatable, Sendable {
        public var itemID: UUID
        /// nil = the roster no longer knows this agent (honest bucket;
        /// the item itself always carries some id — it is the NAME that
        /// may be gone, so this is the same unattributed shape as v0.9)
        public var agentID: UUID?
        public var agentName: String
        public var status: WorkItemStatus
        /// whole minutes since `updatedAt`, clamped at 0 (never negative)
        public var dwellMinutes: Int
        /// true when the item's status is waitingApproval — the company is
        /// parked on a decision, whoever's desk it lands on
        public var waitingOnYou: Bool
    }

    /// Items parked in a non-terminal status for strictly MORE than
    /// [overMinutes] as of [now], longest-frozen first, unattributed
    /// rows sorted last. Terminal (completed/failed) items are never
    /// reported; a young queue honestly answers [].
    public func stallWatch(overMinutes: Int = 30, now: Date = Date()) -> [StallRow] {
        let productID = selectedProductID
        var rows: [StallRow] = []
        for item in workQueue where item.productID == productID {
            switch item.status {
            case .completed, .failed:
                continue                       // history, not a stall
            case .queued, .running, .waitingReview, .waitingApproval:
                break
            }
            // the future is refused: a stamped-ahead item is a clock lie
            // (or a write we can't interpret), never a "negative stall"
            guard item.updatedAt <= now else { continue }
            let dwell = Int(now.timeIntervalSince(item.updatedAt) / 60)
            guard dwell > overMinutes else { continue }

            let known = agents.first(where: { $0.id == item.agentID })?.displayName
            rows.append(StallRow(
                itemID: item.id,
                // the id exists (the struct forces it); what may be lost
                // is the ROSTER knowing it — that is the unattributed shape
                agentID: known == nil ? nil : item.agentID,
                agentName: known ?? "未分配".L(),
                status: item.status,
                dwellMinutes: max(0, dwell),
                waitingOnYou: item.status == .waitingApproval))
        }
        rows.sort { a, b in
            // the unattributed bucket sorts LAST (v0.9 ordering discipline:
            // an existence conditional, not a fixed position)
            if (a.agentID == nil) != (b.agentID == nil) { return b.agentID == nil }
            if a.dwellMinutes != b.dwellMinutes { return a.dwellMinutes > b.dwellMinutes }
            return a.agentName < b.agentName
        }
        return rows
    }

    /// One-sentence stall headline for the command center — the SAME door
    /// the CLI, bridge and shell read. Quiet answers quiet; it never
    /// inflates an empty watch into a jammed office and never hides a
    /// decision parked on the boss.
    public func stallHeadlineText(overMinutes: Int = 30, now: Date = Date()) -> String {
        let rows = stallWatch(overMinutes: overMinutes, now: now)
        if rows.isEmpty {
            return "没有停滞超过 ".L() + "\(overMinutes)" + " 分钟的任务".L()
        }
        let worst = rows.first!
        var line = "\(rows.count)" + " 项停滞".L() + "（>\(overMinutes)" + " 分钟".L()
            + "），最久 ".L() + "\(worst.dwellMinutes)" + " 分钟：".L() + worst.agentName
        if rows.contains(where: { $0.waitingOnYou }) {
            line += " · " + "有任务等你审批".L()
        }
        return line
    }
}
