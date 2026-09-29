import Foundation

// v0.15.0 "the weight door" — the ONE scale door. The snapshot is the
// company's single source of truth, and it only ever grows: events are
// capped (200) but terminal logs, messages and profiles are not, and
// the v0.70-era slimming taught exactly where the bytes pool. This door
// answers the question BEFORE the maintenance advisories fire: how much
// does the company weigh RIGHT NOW, which sections hold the mass, and
// how close is it to the advisory threshold the maintenance panel
// already enforces.
//
// Ground rules:
//   * PURE READ. The door serializes the snapshot the same way every
//     consumer does (JSONEncoder + iso8601 — byte-for-byte what the
//     bridge's snapshot_json and `status --json` serve) and never
//     writes a record.
//   * The TOTAL is the encoder's truth (≈ the file on disk). Section
//     sizes are measured on the SAME payload re-serialized per top-
//     level key with .sortedKeys — one consistent scale for ranking
//     and shares; the sum can differ from the encoder total by key-
//     order overhead, and the door says so instead of fudging.
//   * The threshold is NOT a new opinion: it reuses the maintenance
//     panel's own advisory constant (20 MB), so the CLI, the shell and
//     the GUI cannot disagree about what "heavy" means.
//   * Terminal-log share rides the door as its own number — the exact
//     quantity the v0.70 slimming was about, kept observable forever.

extension CompanyStore {

    public struct SnapshotWeightSection: Equatable, Sendable {
        public var name: String
        public var bytes: Int
    }

    public struct SnapshotWeightReport: Equatable, Sendable {
        public var totalBytes: Int
        public var sections: [SnapshotWeightSection]   // heaviest first
        public var advisoryBytes: Int
        public var exceedsAdvisory: Bool
        /// bytes held by `productTerminalLogs` — the pool the v0.70
        /// slimming drained, kept on the gauge permanently
        public var terminalLogBytes: Int
        /// 0–100, floor-rounded; 0 on an empty snapshot
        public var logSharePercent: Int
    }

    /// The door. Throws only if snapshot serialization fails (a broken
    /// encoder is a bug this door refuses to hide behind an empty 0).
    public func snapshotWeightReport() throws -> SnapshotWeightReport {
        let data = try snapshotDataForWeight()
        let total = data.count

        let object = try JSONSerialization.jsonObject(with: data)
        var sections: [SnapshotWeightSection] = []
        if let dict = object as? [String: Any] {
            for (name, value) in dict {
                let bytes = try JSONSerialization.data(withJSONObject: [name: value],
                                                       options: [.sortedKeys]).count
                sections.append(SnapshotWeightSection(name: name, bytes: bytes))
            }
        }
        sections.sort { a, b in
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            return a.name < b.name
        }

        let advisory = Int(Self.maintenanceStateSnapshotAdvisoryBytes)
        let logBytes = sections.first(where: { $0.name == "productTerminalLogs" })?.bytes ?? 0
        return SnapshotWeightReport(
            totalBytes: total,
            sections: sections,
            advisoryBytes: advisory,
            exceedsAdvisory: total >= advisory,
            terminalLogBytes: logBytes,
            logSharePercent: total > 0 ? Int((Double(logBytes) / Double(total) * 100).rounded(.down)) : 0)
    }

    /// One serializer, one truth: the same bytes `status --json` and the
    /// bridge's snapshot_json serve (JSONEncoder, iso8601 dates).
    private func snapshotDataForWeight() throws -> Data {
        guard let data = snapshotJSONData() else {
            throw OPCWeightError(message: "snapshot serialization failed")
        }
        return data
    }
}

public struct OPCWeightError: Error { public let message: String
    public init(message: String) { self.message = message } }
