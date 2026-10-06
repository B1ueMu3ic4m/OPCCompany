import Foundation

// v0.13.0 "the scriptable door" — the ONE JSON layer. The bridge's query
// verbs serialized their rows inline; `--json` on the CLI now needs the
// EXACT same bytes, and two serializers would eventually disagree (the
// v0.9 lesson, surfaces division). So the serialization moves HERE, next
// to the doors: the bridge and the CLI both call these functions, and a
// byte drift between them is now structurally impossible.
//
// Contract notes, inherited from the bridge verbatim:
//   * list payloads serialize with .sortedKeys — repeat reads are
//     byte-stable (the v1.8 discipline), so scripts can diff and cache.
//   * rows carry the door's OWN order (traffic-desc / longest-first /
//     oldest-waiting; unattributed last) — for a list, order IS the
//     contract.
//   * catchup JSON wraps the page, never re-derives it: the page IS the
//     payload (v1.9); {"page": ...} is an envelope, not a second truth.

extension CompanyStore {

    /// The FULL snapshot as JSON — byte-for-byte what the bridge's
    /// `opc_bridge_snapshot_json` serves (same encoder strategy, same
    /// encode input), now shared so the CLI's `status --json` and the
    /// shell cannot drift.
    public func snapshotJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(currentSnapshot())
    }

    /// Every pending approval of the CURRENT product (bridge v1.3
    /// `approvals_list`): id/title/reason + requesterID when the roster
    /// link exists.
    public func pendingApprovalsJSON() throws -> Data {
        let rows: [[String: Any]] = selectedProductPendingApprovals.map { a in
            var row: [String: Any] = ["id": a.id.uuidString,
                                      "title": a.title,
                                      "reason": a.reason]
            if let r = a.requesterID { row["requesterID"] = r.uuidString }
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows,
                                          options: [.sortedKeys])
    }

    /// The decision ledger as a LIST (bridge v1.4 `history_list`):
    /// RESOLVED approvals of the CURRENT product, newest-first, capped
    /// at 50 — each row carries decidedAt + status + requesterID.
    public func historyJSON() throws -> Data {
        let rows: [[String: Any]] = selectedProductResolvedApprovals.prefix(50).map { a in
            var row: [String: Any] = ["id": a.id.uuidString,
                                      "title": a.title,
                                      "reason": a.reason,
                                      "status": a.status.rawValue]
            if let d = a.decidedAt { row["decidedAt"] = d.timeIntervalSince1970 }
            if let r = a.requesterID { row["requesterID"] = r.uuidString }
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows,
                                          options: [.sortedKeys])
    }

    /// The delivery shelf as a LIST (bridge v1.5 `deliverables_list`):
    /// newest-first, capped at 50; `existsNow` computed HERE at read
    /// time, never serialized.
    public func deliverablesJSON() throws -> Data {
        let rows: [[String: Any]] = selectedProductRecentDeliveryArtifacts.prefix(50).map { a in
            var row: [String: Any] = ["id": a.id.uuidString,
                                      "title": a.title,
                                      "kind": a.kind.rawValue,
                                      "path": a.path,
                                      "existsNow": a.existsOnDisk]
            if let c = a.taskID { row["taskID"] = c.uuidString }
            row["createdAt"] = a.createdAt.timeIntervalSince1970
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows,
                                          options: [.sortedKeys])
    }

    /// One window's traffic as the seven-count OBJECT (bridge v1.6
    /// `standup_window`).
    public func standupWindowJSON(hours: Int = 24,
                                  now: Date = Date()) throws -> Data {
        let w = standupWindow(hours: hours, now: now)
        let window: [String: Any] = [
            "hours": w.hours,
            "newWork": w.newWork,
            "decisions": w.decisions,
            "deliveries": w.deliveries,
            "missing": w.missing,
            "risks": w.risks,
            "awaitingNow": w.awaitingNow,
        ]
        // .sortedKeys: the object channel predates the v1.8 discipline and
        // serialized with UNSTABLE key order every read (the bridge's own
        // test compared semantically for exactly this reason). One
        // serializer, now byte-stable everywhere.
        return try JSONSerialization.data(withJSONObject: window,
                                          options: [.sortedKeys])
    }

    /// Per-employee window contribution as a LIST (bridge v1.7
    /// `team_stats_list`): traffic-desc, the unattributed row (no
    /// agentID key) last — the door's own order.
    public func teamStatsJSON(hours: Int = 24,
                              now: Date = Date()) throws -> Data {
        let rows: [[String: Any]] = teamWindow(hours: hours, now: now).map { r in
            var row: [String: Any] = ["name": r.name,
                                      "assigned": r.assigned,
                                      "deliveries": r.deliveries,
                                      "missing": r.missing,
                                      "asked": r.asked,
                                      "risks": r.risks,
                                      "activeNow": r.activeNow]
            if let a = r.agentID { row["agentID"] = a.uuidString }
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows,
                                          options: [.sortedKeys])
    }

    /// Non-terminal work parked over the threshold as a LIST (bridge
    /// v1.8 `stalls_list`): longest-frozen first, unattributed last.
    public func stallsJSON(overMinutes: Int = 30,
                           now: Date = Date()) throws -> Data {
        let rows: [[String: Any]] = stallWatch(overMinutes: overMinutes, now: now).map { r in
            var row: [String: Any] = ["itemID": r.itemID.uuidString,
                                      "name": r.agentName,
                                      "status": r.status.rawValue,
                                      "dwellMinutes": r.dwellMinutes,
                                      "waitingOnYou": r.waitingOnYou]
            if let a = r.agentID { row["agentID"] = a.uuidString }
            return row
        }
        return try JSONSerialization.data(withJSONObject: rows,
                                          options: [.sortedKeys])
    }

    /// The weight door as an OBJECT (bridge v1.10 `weight_json`):
    /// {totalBytes, sections:[{name,bytes}], advisoryBytes,
    /// exceedsAdvisory, terminalLogBytes, logSharePercent} — sections
    /// heaviest first; the sum can differ from totalBytes by key-order
    /// overhead (documented, never fudged).
    public func weightJSON() throws -> Data {
        let w = try snapshotWeightReport()
        let object: [String: Any] = [
            "totalBytes": w.totalBytes,
            "sections": w.sections.map { ["name": $0.name, "bytes": $0.bytes] },
            "advisoryBytes": w.advisoryBytes,
            "exceedsAdvisory": w.exceedsAdvisory,
            "terminalLogBytes": w.terminalLogBytes,
            "logSharePercent": w.logSharePercent,
        ]
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys])
    }

    /// The catch-up page wrapped for machines (bridge v1.9 `catchup_md`
    /// carries the raw page; this is the same page in an envelope —
    /// never a second derivation).
    public func catchupPageJSON(hours: Int = 24, overMinutes: Int = 30,
                                now: Date = Date()) throws -> Data {
        let envelope: [String: Any] = [
            "page": catchUpPage(hours: hours, overMinutes: overMinutes, now: now)
        ]
        return try JSONSerialization.data(withJSONObject: envelope,
                                          options: [.sortedKeys])
    }

    /// The transcript door as an OBJECT (bridge v1.14 `transcript`): the
    /// agent's VISIBLE terminal log — the same product-scoped, sanitized,
    /// compacted text the GUI's agent card renders — clipped to the last
    /// `tail` lines. `totalLines` counts the visible log BEFORE clipping;
    /// `tail <= 0` means no clipping. An empty seat answers its one honest
    /// placeholder line instead of pretending output happened.
    public func transcriptJSON(agentID: UUID, tail: Int = 40) throws -> Data {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            throw OPCBridgeRefusal(message: "transcript: no agent with id \(agentID.uuidString)")
        }
        let visible = visibleTerminalLog(for: agentID)
        let allLines = visible.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let clipped: [String] = tail > 0 && allLines.count > tail
            ? Array(allLines.suffix(tail))
            : allLines
        let object: [String: Any] = [
            "agentID": agentID.uuidString,
            "displayName": agent.displayName,
            "totalLines": allLines.count,
            "tail": tail,
            "lines": clipped,
        ]
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys])
    }

    /// The agent desk as an OBJECT (bridge v1.17 `desk`): one employee's
    /// working surface — profile chips, session, assigned tasks, work
    /// queue, pending inbox — composed from the SAME accessors the
    /// macOS agent desk renders, so no surface grows a second opinion.
    /// Unknown ids refuse. Pure read.
    public func deskJSON(agentID: UUID) throws -> Data {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            throw OPCBridgeRefusal(message: "desk: no agent with id \(agentID.uuidString)")
        }
        let tasks = selectedProductTasks.filter { $0.ownerID == agentID }
        let queue = selectedProductWorkQueue.filter { $0.agentID == agentID }
        let inbox = selectedAgentRecentProductMessages.filter { $0.toAgentID == agentID && $0.status == .pending }
        var object: [String: Any] = [
            "agentID": agentID.uuidString,
            "displayName": agent.displayName,
            "role": agent.role.title,
            "onTeam": isAgentAssignedToSelectedProduct(agentID),
            "profileChips": agentDeskProfileChips(forAgentID: agentID).map { ["label": $0.label, "value": $0.value] },
            "assignedTasks": tasks.map { ["taskID": $0.id.uuidString, "title": $0.title, "status": $0.status.rawValue] },
            "workQueue": queue.map { ["itemID": $0.id.uuidString, "taskID": $0.taskID.uuidString, "status": $0.status.rawValue, "promptPreview": $0.promptPreview] },
            "pendingInboxCount": inbox.count,
            "pendingInbox": inbox.prefix(3).map { message -> [String: Any] in
                var row: [String: Any] = ["subject": message.subject, "kind": message.kind.rawValue]
                if let from = agents.first(where: { $0.id == message.fromAgentID }) {
                    row["from"] = from.displayName
                }
                return row
            },
        ]
        if let session = runtimeSession(for: agentID) {
            object["session"] = ["state": session.state.title, "capability": session.capability.title]
        } else {
            object["session"] = NSNull()
        }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys])
    }
}
