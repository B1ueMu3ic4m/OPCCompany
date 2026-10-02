import Foundation
import Testing

@testable import OPCCompanyCore

// Docs-drift guard: every verb `opc_bridge_command` HANDLES must be
// DOCUMENTED in include/opc_bridge.h, and every documented verb must
// exist in the Swift switch — in both directions, exactly. The header
// is the contract; the switch is the behavior; this test keeps them
// the same list so neither can quietly drift (a verb documented but
// refused is a contract lie; a verb handled but undocumented is a
// contract nobody agreed to).

private struct BridgeVerbDocError: Error { let message: String }

private func packageRootURL() -> URL {
    // test working directory is the package root (same assumption the
    // CLI binary tests make when they locate .build/debug/opc)
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

private func documentedHeaderVerbs() throws -> Set<String> {
    let url = packageRootURL()
        .appendingPathComponent("include/opc_bridge.h")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw BridgeVerbDocError(message: "opc_bridge.h not found at \(url.path)")
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    // a documented verb line: ` *   "verb" {` — the ONLY anchor shape.
    // Payload-key lines inside the block carry `":"` right after the
    // token (never `{`), and prose lines like ` *       "over_minutes"
    // (default 30, ...)` start a parenthesis, not a brace — neither
    // matches, so the documented set stays exactly the verb lines.
    let regex = try NSRegularExpression(
        pattern: #"(?m)^\s*\*\s+"([a-z_]+)"\s+\{"#)
    let range = NSRange(text.startIndex..., in: text)
    var verbs = Set<String>()
    for match in regex.matches(in: text, range: range) {
        if let r = Range(match.range(at: 1), in: text) {
            verbs.insert(String(text[r]))
        }
    }
    return verbs
}

private func handledSwitchVerbs() throws -> Set<String> {
    let url = packageRootURL()
        .appendingPathComponent("Sources/OPCCompanyCore/OPCBridge.swift")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw BridgeVerbDocError(message: "OPCBridge.swift not found at \(url.path)")
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"case "([a-z_]+)":"#)
    let range = NSRange(text.startIndex..., in: text)
    var verbs = Set<String>()
    for match in regex.matches(in: text, range: range) {
        if let r = Range(match.range(at: 1), in: text) {
            verbs.insert(String(text[r]))
        }
    }
    return verbs
}

@Test func bridgeHeaderVerbsMatchTheSwiftSwitchExactly() throws {
    let documented = try documentedHeaderVerbs()
    let handled = try handledSwitchVerbs()

    #expect(!documented.isEmpty, "the header documents no verbs — parser drift")
    #expect(!handled.isEmpty, "the switch handles no verbs — parser drift")

    let undocumented = handled.subtracting(documented)
    #expect(undocumented.isEmpty,
            "handled in OPCBridge but NOT documented in opc_bridge.h: \(undocumented.sorted())")

    let unimplemented = documented.subtracting(handled)
    #expect(unimplemented.isEmpty,
            "documented in opc_bridge.h but NOT handled in OPCBridge: \(unimplemented.sorted())")
}
