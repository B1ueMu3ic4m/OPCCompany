import Foundation
import Testing

@testable import OPCCompanyCore

// v2.15.0 "the archive list": `opc checkpoints` — what safety
// checkpoints exist on disk, newest first, the same text the app's
// maintenance sheet renders. Empty answers honestly. Seeds ride the
// CompanyPersistence.testSupportDirectoryOverride seam into private
// dirs; the child gets the same dir through its process env.

private var cliBinaryURL: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/debug/opc")
}

private func runCLI(_ args: [String], supportDir: URL) throws
    -> (rc: Int32, out: String, err: String)
{
    let process = Process()
    process.executableURL = cliBinaryURL
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["OPC_COMPANY_SUPPORT_DIR"] = supportDir.path
    env["OPC_ALLOW_CONCURRENT_WRITE"] = "1"
    process.environment = env
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    let read: (Pipe) -> String = { pipe in
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    return (process.terminationStatus, read(out), read(err))
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func checkpointsListAnswersEmptyThenCountsFilings() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-checkpoints-list-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    CompanyStore.bootstrap(loadPersisted: false).saveSnapshot()

    // empty: the honest placeholder, never an invented archive
    let empty = try runCLI(["checkpoints"], supportDir: tmp)
    #expect(empty.rc == 0, "\(empty.err)")
    #expect(empty.out.contains("暂无安全检查点"), "empty answers honestly: \(empty.out)")

    // after a filing: the list names it, newest first
    _ = try runCLI(["checkpoint", "the drill archive"], supportDir: tmp)
    let listed = try runCLI(["checkpoints"], supportDir: tmp)
    #expect(listed.rc == 0, "\(listed.err)")
    #expect(listed.out.contains("最近安全检查点"), "\(listed.out)")
    #expect(listed.out.contains("本机检查点已保存"), "\(listed.out)")
    #expect(!listed.out.contains("暂无"), "a filing replaces the empty state")
}

// v2.28.0: `checkpoints --json` serves the bridge checkpoints_list verb's
// exact shape (the one-serializer discipline); junk JSON flag forms stay
// refused; the read never moves the archive.
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor
func checkpointsJSONServesTheBridgeShape() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-checkpoints-json-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    CompanyStore.bootstrap(loadPersisted: false).saveSnapshot()
    _ = try runCLI(["checkpoint", "json shape"], supportDir: tmp)

    let j = try runCLI(["checkpoints", "--json"], supportDir: tmp)
    #expect(j.rc == 0, "\(j.err)")
    let rows = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [[String: Any]])
    #expect(rows.count == 1)
    #expect((rows[0]["file"] as? String)?.hasPrefix("checkpoint-") == true)
    #expect(rows[0]["bytes"] is Int && rows[0]["modifiedAt"] is Int)

    // archive bytes on disk: listing must not add or touch filings
    let archive = tmp.appendingPathComponent("checkpoints")
    let countBefore = try FileManager.default.contentsOfDirectory(atPath: archive.path).count
    _ = try runCLI(["checkpoints", "--json"], supportDir: tmp)
    let countAfter = try FileManager.default.contentsOfDirectory(atPath: archive.path).count
    #expect(countAfter == countBefore, "a listing never mints filings")
}
