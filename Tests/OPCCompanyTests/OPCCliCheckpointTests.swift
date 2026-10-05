import Foundation
import Testing

@testable import OPCCompanyCore

// v2.12.0 "the checkpoint door": `opc checkpoint <reason>` — the same
// store primitive the app runs before every risky operation, driven
// from the terminal. The checked facade reports whether the checkpoint
// actually LANDED (the create path reports failure through a
// verification record, not a throw); the empty reason refuses; the
// output counts the archives on disk. Seeds ride the
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
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
               encoding: .utf8) ?? ""
    }
    return (process.terminationStatus, read(out), read(err))
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func checkpointDoorFilesAnHonestArchive() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-checkpoint-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = tmp
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()

    let s = try runCLI(["checkpoint", "before", "the", "jump"], supportDir: tmp)
    #expect(s.rc == 0, "\(s.err)")
    #expect(s.out.contains("✓ checkpoint filed"), "the door confirms the landing: \(s.out)")
    #expect(s.out.contains("reason: before the jump"), "the reason rides verbatim: \(s.out)")
    #expect(s.out.contains("(1 on disk)"), "the disk count is the honest summary: \(s.out)")

    // the archive actually exists, and the STORE (the child's own
    // process) recorded the verdict — reload from disk to read it
    let archives = try FileManager.default.contentsOfDirectory(
        at: tmp.appendingPathComponent("checkpoints", isDirectory: true),
        includingPropertiesForKeys: nil)
    #expect(archives.count == 1)
    let reloaded = try #require(CompanyPersistence.load())
    #expect(reloaded.verifications.first?.status == .passed,
            "the checked facade's verdict rode the snapshot")

    // a second filing counts both
    let again = try runCLI(["checkpoint", "second"], supportDir: tmp)
    #expect(again.rc == 0, "\(again.err)")
    #expect(again.out.contains("(2 on disk)"))
}

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
func checkpointDoorRefusesAnEmptyReason() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-checkpoint-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    for args in [["checkpoint"], ["checkpoint", "   "]] {
        let s = try runCLI(args, supportDir: tmp)
        #expect(s.rc != 0, "\(args) must refuse")
        #expect(s.err.contains("usage: opc checkpoint"), "\(args) must name the usage: \(s.err)")
    }
}
