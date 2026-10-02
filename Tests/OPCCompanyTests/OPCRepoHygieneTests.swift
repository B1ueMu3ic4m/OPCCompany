import Foundation
import Testing

// Repo-hygiene guards over CHANGELOG.md:
//   1. every `## [...]` header is either [Unreleased] or [x.y.z] - date
//   2. version sections descend strictly (newest first)
//   3. THE VERSION LAW: a 1.x release must never exist — the project's
//      ladder goes 0.x (small steps) → 2.x/3.x (capability milestones).
//      One MAJOR==1 header fails the gate, forever.

private struct ChangelogLintError: Error { let message: String }

private func versionTuple(_ v: String) -> [Int] {
    v.split(separator: ".").compactMap { Int($0) }
}

@Test func changelogHeadersCarryDatesAndObeyTheVersionLaw() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("CHANGELOG.md")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ChangelogLintError(message: "CHANGELOG.md not found")
    }
    let text = try String(contentsOf: url, encoding: .utf8)

    let headerRegex = try NSRegularExpression(pattern: #"^## \[([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$"#)
    var versions: [String] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        guard line.hasPrefix("## [") else { continue }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = headerRegex.firstMatch(in: line, range: range) else {
            throw ChangelogLintError(message: "malformed changelog header (need `## [Unreleased]` or `## [x.y.z] - YYYY-MM-DD`): \(line)")
        }
        let name = String(line[Range(match.range(at: 1), in: line)!])
        if name == "Unreleased" { continue }
        let date = match.range(at: 2).location != NSNotFound
            ? String(line[Range(match.range(at: 2), in: line)!])
            : ""
        guard !date.isEmpty else {
            throw ChangelogLintError(message: "version section without a date: \(line)")
        }
        versions.append(name)
    }

    #expect(!versions.isEmpty, "no version sections found — parser drift")

    // strictly descending, newest first
    for (a, b) in zip(versions, versions.dropFirst()) {
        let ta = versionTuple(a), tb = versionTuple(b)
        #expect(ta.count == 3 && tb.count == 3, "non-semver section: \(a) / \(b)")
        var greater = false
        for (x, y) in zip(ta, tb) where x != y {
            greater = x > y
            break
        }
        #expect(greater, "changelog versions must descend newest-first: \(a) before \(b)")
    }

    // THE VERSION LAW: no 1.x, ever.
    for name in versions {
        let t = versionTuple(name)
        #expect(!(t.count == 3 && t[0] == 1),
                "THE VERSION LAW: 1.x must never exist (0.x small steps → 2.x/3.x milestones): \(name)")
    }
}
