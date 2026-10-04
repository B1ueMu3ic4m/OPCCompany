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

/// THE SUPPORT-DIR SEAM LAW: `OPC_COMPANY_SUPPORT_DIR` is a process-start
/// knob by design — CompanyPersistence bakes its first resolution and
/// never re-reads the env. A test that setenvs it is dead theater: only
/// whoever wins the first touch is honored, everyone else silently
/// shares one dir and dumps into each other (the "0 rows" bridge crash,
/// the hall reading someone else's store). Tests isolate through the
/// `CompanyPersistence.testSupportDirectoryOverride` seam instead — a
/// bare setenv of the knob anywhere in Tests/ fails this gate.
@Test func supportDirOverrideRidesTheSeamNotTheEnv() throws {
    let testsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/OPCCompanyTests")
    let files = try FileManager.default.contentsOfDirectory(
        at: testsDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .filter { $0.lastPathComponent != "OPCRepoHygieneTests.swift" } // 本文件必须写出这个非法形态才能守它
    #expect(files.count > 20, "test directory moved — lint is looking at the wrong place")
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains(#"setenv("OPC_COMPANY_SUPPORT_DIR""#),
                "\(file.lastPathComponent) setenvs OPC_COMPANY_SUPPORT_DIR — dead theater after the first-touch bake; use CompanyPersistence.testSupportDirectoryOverride")
    }
}

/// THE HTTP-MOCK GATE LAW: MockURLProtocol's statics are process-global
/// and Swift Testing runs suites concurrently — a foreign reset
/// mid-flight steals the scripted responses and wipes the recording.
/// Any test file that calls mockURLSession must name withMockHTTPGate
/// (or the MockHTTPGate actor directly) so its mock lifetime is
/// serialized.
@Test func httpMockUsersMustHoldTheGate() throws {
    let testsDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/OPCCompanyTests")
    let files = try FileManager.default.contentsOfDirectory(
        at: testsDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        let uses = text.contains("mockURLSession(")
        let gated = text.contains("MockHTTPGate")
        #expect(!uses || gated,
                "\(file.lastPathComponent) calls mockURLSession without the MockHTTPGate — a foreign reset can steal the scripted responses mid-flight")
    }
}
