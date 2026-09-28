import Foundation

// v0.11.0 "the catch-up" — the ONE page door. v0.8 answers WHAT moved,
// v0.9 answers WHO moved it, v0.10 answers what STOPPED moving; this
// composes the three (plus the boss's own desk and the shelf) into the
// single artifact the boss actually asked for: one page that brings
// them up to speed after being away.
//
// Ground rules, inherited from the sibling doors and not negotiable:
//   * PURE READ. The page never writes a record — it is recomputed per
//     read from the same product-scoped doors every other surface uses
//     (standupWindow / teamWindow / stallWatch / pending approvals /
//     the v0.7 existence door). Zero new math: if the page and a door
//     ever disagree, the DOOR is right and this file is wrong.
//   * The page is a TERMINAL artifact: stable English prose, the same
//     choice every CLI surface made. The localized surface for this
//     door is the report center card, which renders the same page —
//     one artifact, no per-surface prose to drift.
//   * BYTE-STABILITY: no wall-clock timestamps inside the page (only
//     window parameters and door outputs). For a given company state,
//     parameters and localization, two reads are byte-identical — the
//     same discipline the list channel pinned at v1.8, so the shell
//     can cache/compare and tests can pin shapes exactly.
//   * SECTION ORDER IS THE CONTRACT: traffic, who, stuck, desk, shelf,
//     footer. A quiet section answers with its quiet line and keeps
//     its place — never omitted (an omitted section would make the
//     page shape reader-dependent).
//   * Every list rides its door's own order (team: traffic-desc with
//     the unattributed row last; stalls: longest-frozen first; desk:
//     oldest-waiting first) and is CAPPED at 8 rows with an honest
//     "...and N more" tail — a page that never ends is a report, not
//     a catch-up.

extension CompanyStore {

    /// Rows-per-section cap: beyond this the page says "...and N more"
    /// instead of pretending everything fits on one screen.
    private static let catchUpRowCap = 8

    /// The page. `now` is injectable (every window and dwell math runs
    /// against it — no surface races the wall clock); `hours` scopes
    /// the traffic/team windows, `overMinutes` the stuck threshold.
    public func catchUpPage(hours: Int = 24, overMinutes: Int = 30,
                            now: Date = Date()) -> String {
        let product = selectedProduct?.name ?? "the selected product"
        var page: [String] = []
        page.append("# Catch-up — \(product)")
        page.append("")

        // 1. Traffic — the standup door, verbatim counts.
        let w = standupWindow(hours: hours, now: now)
        page.append("## Traffic (last \(hours)h)")
        page.append("- new work: \(w.newWork)")
        page.append("- decided: \(w.decisions)")
        page.append("- delivered: \(w.deliveries)"
            + (w.missing > 0 ? "  (\(w.missing) MISSING on disk NOW)" : ""))
        page.append("- risks raised: \(w.risks)")
        if w.quiet {
            page.append("- a quiet window — nothing moved.")
        }

        // 2. Who — the team door, its own order, capped.
        page.append("")
        page.append("## Who did what (last \(hours)h)")
        let team = teamWindow(hours: hours, now: now)
        if team.isEmpty {
            page.append("- nobody — a quiet window.")
        } else {
            for (index, r) in team.enumerated() {
                if index == Self.catchUpRowCap {
                    page.append("- ...and \(team.count - index) more.")
                    break
                }
                var line = "- \(r.name): traffic \(r.assigned + r.deliveries + r.asked + r.risks)"
                    + " (assigned \(r.assigned) · delivered \(r.deliveries)"
                    + (r.missing > 0 ? ", \(r.missing) MISSING" : "")
                    + " · asked \(r.asked) · risks \(r.risks)"
                    + (r.activeNow > 0 ? " · \(r.activeNow) active now" : "") + ")"
                if r.agentID == nil { line += " — unattributed" }
                page.append(line)
            }
        }

        // 3. Stuck — the stall watch, its own order, capped.
        page.append("")
        page.append("## Stuck (parked over \(overMinutes) min)")
        let stalls = stallWatch(overMinutes: overMinutes, now: now)
        if stalls.isEmpty {
            page.append("- nothing stuck.")
        } else {
            for (index, r) in stalls.enumerated() {
                if index == Self.catchUpRowCap {
                    page.append("- ...and \(stalls.count - index) more.")
                    break
                }
                page.append("- \(r.dwellMinutes) min — \(r.status.rawValue) — \(r.agentName)"
                    + (r.waitingOnYou ? " — WAITS ON YOU" : ""))
            }
        }

        // 4. Your desk — the live pending queue, oldest-waiting first,
        //    capped. The one section that is never windowed: these are
        //    owed RIGHT NOW.
        let desk = selectedProductPendingApprovals
            .sorted { $0.createdAt < $1.createdAt }
        page.append("")
        page.append("## Waiting on you (\(desk.count))")
        if desk.isEmpty {
            page.append("- nothing — your desk is clear.")
        } else {
            for (index, a) in desk.enumerated() {
                if index == Self.catchUpRowCap {
                    page.append("- ...and \(desk.count - index) more.")
                    break
                }
                let who = a.requesterID
                    .flatMap { id in agents.first(where: { $0.id == id })?.displayName }
                page.append("- \(a.title)"
                    + (who.map { " — raised by \($0)" } ?? ""))
            }
        }

        // 5. Shelf — the v0.7 existence door over the window's
        //    deliveries: what the company claims it shipped but the
        //    filesystem disagrees about RIGHT NOW.
        let missing = artifacts
            .filter { $0.productID == selectedProductID
                && $0.createdAt >= now.addingTimeInterval(-Double(hours) * 3600)
                && $0.createdAt <= now
                && isDeliveryArtifact($0)
                && !$0.existsOnDisk }
            .sorted { $0.createdAt < $1.createdAt }
        page.append("")
        page.append("## Shelf integrity (last \(hours)h)")
        if missing.isEmpty {
            page.append("- every delivery in the window is on disk.")
        } else {
            for (index, a) in missing.enumerated() {
                if index == Self.catchUpRowCap {
                    page.append("- ...and \(missing.count - index) more.")
                    break
                }
                page.append("- MISSING: \(a.title) — \(a.path)")
            }
        }

        page.append("")
        page.append("---")
        page.append("Pure read — this page wrote nothing. Refresh any time: `opc catchup [hours]`.")
        return page.joined(separator: "\n")
    }
}
