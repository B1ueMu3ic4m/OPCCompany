import Foundation

// v0.16.0 "the office calls" — the boss should not have to stare at the
// office to know it needs them. This door answers WHAT is worth calling
// them for RIGHT NOW: approvals waiting on their desk, and work that
// stopped moving. The door itself never notifies anyone — it holds the
// truth; the macOS app's thin scheduler (BossNotifier) polls it and
// delivers through UserNotifications, and the DEDUPER below decides
// what has already been said out loud.
//
// Ground rules:
//   * The alert list is a PURE READ over the existing doors (the
//     pending queue + the stall watch). Zero new math: if an alert and
//     its door disagree, the door is right.
//   * Alert identity is the DOOR's own id (the approval's UUID, the
//     work item's UUID) — an alert re-appears while its cause lives and
//     disappears when it is handled. The deduper keys on that id, so a
//     notified approval that is still pending is NOT re-shouted, but a
//     NEW approval always is.
//   * Delivery state is NOT company state. What the boss has already
//     been told lives outside the snapshot (UserDefaults via the app),
//     so notifying can never move a single company byte.
//   * Capped: a run-away office produces a summary, not a hundred
//     banners.

extension CompanyStore {

    public enum BossAlertKind: String, Equatable, Sendable {
        case approval
        case stall
    }

    public struct BossAlert: Equatable, Sendable {
        /// the DOOR's own id — stable while the cause lives
        public var id: String
        public var kind: BossAlertKind
        /// localized one-line title for the banner
        public var title: String
        /// localized body line
        public var body: String
    }

    /// What is worth calling the boss about, right now. Approvals first
    /// (oldest-waiting first — they are DECISIONS owed), then stalls
    /// (longest-frozen first), capped at `cap` alerts total.
    public func bossAlerts(overMinutes: Int = 30, now: Date = Date(),
                           cap: Int = 5) -> [BossAlert] {
        var alerts: [BossAlert] = []
        let pending = selectedProductPendingApprovals
            .sorted { $0.createdAt < $1.createdAt }
        for a in pending {
            let who = a.requesterID
                .flatMap { id in agents.first(where: { $0.id == id })?.displayName }
            alerts.append(BossAlert(
                id: a.id.uuidString,
                kind: .approval,
                title: "等你批准".L(),
                body: a.title + (who.map { " — " + $0 } ?? "")))
        }
        if alerts.count < cap {
            let stalls = stallWatch(overMinutes: overMinutes, now: now)
                .filter { !$0.waitingOnYou }   // approval-parked rows ARE the queue above
            for s in stalls where alerts.count < cap {
                alerts.append(BossAlert(
                    id: s.itemID.uuidString,
                    kind: .stall,
                    title: "任务停滞".L(),
                    body: "\(s.dwellMinutes)" + " 分钟 — ".L() + s.agentName
                        + (s.waitingOnYou ? " · " + "等你审批".L() : "")))
            }
        }
        return Array(alerts.prefix(cap))
    }
}

/// Decides what has already been said out loud. Keyed by the door's own
/// alert id; storage is injected (UserDefaults in the app, memory in
/// tests) so notifying never touches company state.
public struct BossAlertDeduper {
    private let defaults: UserDefaults
    private let key = "opc.bossAlert.deliveredIds"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func deliveredIds() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Returns the alerts NOT yet delivered, and records them. A call is
    /// atomic per invocation: read, partition, persist, hand back.
    public func partition(_ alerts: [CompanyStore.BossAlert]) -> [CompanyStore.BossAlert] {
        let seen = deliveredIds()
        let fresh = alerts.filter { !seen.contains($0.id) }
        if !fresh.isEmpty {
            defaults.set(Array(seen.union(fresh.map(\.id))), forKey: key)
        }
        return fresh
    }

    /// Handled causes leave the doors, so their ids go stale; pruning
    /// keeps the stored set from growing forever.
    public func prune(keeping aliveIds: Set<String>) {
        defaults.set(Array(deliveredIds().intersection(aliveIds)), forKey: key)
    }
}
