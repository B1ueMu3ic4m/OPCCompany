import Foundation

// v0.9.0 "the name behind the work" — the ONE team door. v0.8 answers
// WHAT happened in the window; this answers WHO did it, so the boss can
// point at a desk and say "we need to talk". Same window discipline as
// the standup (product-scoped, pure read, `now` injectable, future
// timestamps excluded, legacy honesty). Attribution NEVER fabricates:
// events carry agentID; artifacts carry none — their owner is reached
// through the task chain (artifact.taskID -> task.ownerID) and anything
// that dead-ends lands in the unattributed row, named exactly as the
// approvals door names it (未分配 / 未知员工), never guessed.

extension CompanyStore {
    /// One employee's window of contribution, plus their live load.
    public struct TeamWindowRow: Equatable, Sendable {
        /// nil = the unattributed bucket (no agent id / dead task chain)
        public var agentID: UUID?
        public var name: String
        public var assigned: Int     // taskAssigned events for this agent
        public var deliveries: Int   // delivery-view artifacts owned via task chain
        public var missing: Int      // ...of those, files NOT on disk right now
        public var asked: Int        // approvals raised by this agent in window
        public var risks: Int        // risk events attributed to this agent
        public var activeNow: Int    // open work-queue items RIGHT NOW

        public var traffic: Int { assigned + deliveries + asked + risks }
    }

    /// The team door. One row per agent that MOVED in the window (or
    /// holds open work), plus one unattributed row when needed. Sorted
    /// by traffic desc, name asc; the unattributed bucket always last —
    /// the boss reads names first, silence last.
    public func teamWindow(hours: Int = 24, now: Date = Date()) -> [TeamWindowRow] {
        let since = now.addingTimeInterval(-Double(hours) * 3600)
        let productID = selectedProductID
        let inWindow: (Date) -> Bool = { $0 >= since && $0 <= now }

        struct Bucket {
            var assigned = 0, deliveries = 0, missing = 0, asked = 0, risks = 0
        }
        var buckets: [UUID?: Bucket] = [:]
        // a known-name for sorting/fallback resolution (nil bucket)
        func note(_ key: UUID?, _ f: (inout Bucket) -> Void) {
            f(&buckets[key, default: Bucket()])
        }

        for event in events {
            guard event.productID == productID, inWindow(event.createdAt) else { continue }
            switch event.kind {
            case .taskAssigned: note(event.agentID) { $0.assigned += 1 }
            case .risk:         note(event.agentID) { $0.risks += 1 }
            default: break
            }
        }

        for approval in approvals where approval.productID == productID {
            if approval.status == .pending {
                // the live queue belongs on the window headline of v0.8;
                // here only RAISED-and-decided work counts as traffic.
                continue
            }
            let decided = approval.decidedAt ?? approval.createdAt
            if inWindow(decided) {
                note(approval.requesterID) { $0.asked += 1 }
            }
        }

        // artifact -> owner through the TASK CHAIN only; a missing task,
        // a nil owner, or an unknown id each dead-end honestly.
        let ownerByTask: [UUID: UUID?] = Dictionary(
            uniqueKeysWithValues: tasks.compactMap { t in
                t.productID == productID ? (t.id, t.ownerID) : nil
            })
        for artifact in artifacts where artifact.productID == productID
            && inWindow(artifact.createdAt) && isDeliveryArtifact(artifact) {
            let key: UUID? = artifact.taskID.flatMap { ownerByTask[$0] ?? nil }
            note(key) { b in
                b.deliveries += 1
                if !artifact.existsOnDisk { b.missing += 1 }
            }
        }

        var actives: [UUID?: Int] = [:]
        for item in selectedProductWorkQueue where item.status != .completed {
            actives[item.agentID, default: 0] += 1
        }

        let keys = Set(buckets.keys).union(actives.keys)
        var rows: [TeamWindowRow] = []
        for key in keys {
            let b = buckets[key] ?? Bucket()
            let active = actives[key] ?? 0
            guard b.assigned + b.deliveries + b.asked + b.risks > 0 || active > 0 else {
                continue
            }
            let name: String
            if let id = key {
                name = agents.first { $0.id == id }?.displayName ?? "未知员工".L()
            } else {
                name = "未分配".L()
            }
            rows.append(TeamWindowRow(agentID: key, name: name,
                                      assigned: b.assigned, deliveries: b.deliveries,
                                      missing: b.missing, asked: b.asked, risks: b.risks,
                                      activeNow: active))
        }
        rows.sort { a, b in
            if (a.agentID == nil) != (b.agentID == nil) { return b.agentID == nil }
            if a.traffic != b.traffic { return a.traffic > b.traffic }
            return a.name < b.name
        }
        return rows
    }

    /// One-sentence team headline for the command center, riding the SAME
    /// door as CLI `opc team` and the shell panel. Names the busiest agent
    /// and flags unattributed work; never inflates a quiet window into a
    /// fake busy office.
    public func teamHeadlineText(hours: Int = 24, now: Date = Date()) -> String {
        let rows = teamWindow(hours: hours, now: now)
        if rows.isEmpty {
            return "过去 ".L() + "\(hours)" + " 小时：".L() + "团队无人动".L()
        }
        let top = rows.first!
        var line = "过去 ".L() + "\(hours)" + " 小时：".L()
        line += "\(top.name)" + " 最忙".L() + "（\(top.traffic)）"
        if rows.contains(where: { $0.agentID == nil && $0.traffic > 0 }) {
            line += " · " + "有未归属工作".L()
        }
        return line
    }
}
