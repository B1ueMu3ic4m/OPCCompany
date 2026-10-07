import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for `opc doctor` (v2.16.0): real .build/debug/opc
// against a private support dir seeded in-process through the
// CompanyPersistence.testSupportDirectoryOverride seam. Pins: the human
// report names the contract version and the writer-guard OVERRIDE the
// subprocess itself runs under (runCLI sets it — the doctor must see it);
// `--json` serves the bridge `doctor` verb's shape; junk args refuse with
// usage; pure-read promise holds (seeded snapshot bytes must not move).

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

@Test(.enabled(if: FileManager.default.fileExists(
    atPath: cliBinaryURL.path)))
@MainActor func cliDoctorPrintsFactsAndNeverWrites() throws {
    let supportDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("opc-cli-doctor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    CompanyPersistence.testSupportDirectoryOverride = supportDir
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    defer {
        CompanyPersistence.testSupportDirectoryOverride = nil
        try? FileManager.default.removeItem(at: supportDir)
    }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.saveSnapshot()
    let seededBytes = try Data(contentsOf: stateFile)

    let s = try runCLI(["doctor"], supportDir: supportDir)
    #expect(s.rc == 0, "doctor must exit clean, stderr: \(s.err)")
    #expect(s.out.contains("opc doctor — contract v1.18"))
    #expect(s.out.contains(supportDir.path),
            "the doctor names the dir it actually looked at")
    #expect(s.out.contains("state file: present"))
    #expect(s.out.contains("writer guard: OVERRIDDEN"),
            "the subprocess runs under the override — it must say so")
    #expect(s.out.contains("writer guard is OFF"),
            "and the fact rides the warnings list too")

    // --json serves the bridge door's exact shape
    let j = try runCLI(["doctor", "--json"], supportDir: supportDir)
    #expect(j.rc == 0, "stderr: \(j.err)")
    let d = try #require(JSONSerialization.jsonObject(
        with: Data(j.out.utf8)) as? [String: Any])
    #expect(d["contractVersion"] as? String == "v1.18")
    #expect(d["supportDir"] as? String == supportDir.path)
    #expect(d["overrideSet"] as? Bool == true)
    #expect(d["stateFileExists"] as? Bool == true)

    // junk args refuse loudly, exit ≠ 0
    let junk = try runCLI(["doctor", "now"], supportDir: supportDir)
    #expect(junk.rc != 0 && junk.err.contains("usage: opc doctor"))

    // pure-read: neither run moved the seeded snapshot
    #expect(try Data(contentsOf: stateFile) == seededBytes)
}
