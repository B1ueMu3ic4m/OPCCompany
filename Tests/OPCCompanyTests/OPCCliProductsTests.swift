import Foundation
import Testing

@testable import OPCCompanyCore

// Formal regression for the CLI product surface: `opc products` lists
// every workspace with the current one marked, and `opc use <id>`
// switches selection through the SAME store path as the GUI sidebar
// (selectProduct: agent-team restart + save), persisting to disk.
// Unknown ids refuse loudly — mirroring the bridge's product_select
// rule that a silent no-op is how shell/core drift starts. Reuses the
// OPCCliApprovalsTests discipline: real .build/debug/opc binary, the
// suite's temp support dir shared with the seed, state-neutral restore.

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
@MainActor func cliProductsListAndUseSwitchPersist() throws {
    let supportDir = CompanyPersistence.supportDirectory
    let stateFile = supportDir.appendingPathComponent("company-state.json")
    let priorBytes = try? Data(contentsOf: stateFile)
    defer {
        if let priorBytes {
            try? priorBytes.write(to: stateFile)
        } else {
            try? FileManager.default.removeItem(at: stateFile)
        }
    }

    // Seed: fresh store + a second product, persisted. addProductWorkspace
    // AUTO-SELECTS the new product (verified live in the office query test)
    // — so the FIRST product becomes the "switch to" target.
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let first = try #require(store.products.first)
    store.addProductWorkspace()
    let second = try #require(store.products.last { $0.id != first.id })
    store.saveSnapshot()

    // 1. products lists both, marks the CURRENT one (second) with *
    let listed = try runCLI(["products"], supportDir: supportDir)
    #expect(listed.rc == 0)
    #expect(listed.out.contains(second.id.uuidString), "second id missing: \(listed.out)")
    #expect(listed.out.contains(first.id.uuidString), "first id missing: \(listed.out)")
    let markedLine = try #require(
        listed.out.split(separator: "\n").first { $0.contains("*") })
    #expect(markedLine.contains(second.id.uuidString),
            "the * marker must sit on the selected product: \(markedLine)")

    // 2. use <first> switches, says so, and the write lands on disk
    let switched = try runCLI(["use", first.id.uuidString], supportDir: supportDir)
    #expect(switched.rc == 0, "valid switch must exit 0; got: \(switched.err)")
    #expect(switched.out.contains("Now working on: \(first.name)"))
    let after = CompanyStore.bootstrap(loadPersisted: true)
    #expect(after.selectedProductID == first.id,
            "selection must move on disk, not just on stdout")

    // 3. ghost product id refuses with guidance; junk args refuse with usage
    let ghost = try runCLI(["use", "00000000-0000-0000-0000-00000000dead"],
                           supportDir: supportDir)
    #expect(ghost.rc != 0, "an unknown product must NOT exit 0")
    #expect((ghost.out + ghost.err).contains("no product with id"))
    #expect((ghost.out + ghost.err).contains("opc products"))
    let junk = try runCLI(["use"], supportDir: supportDir)
    #expect(junk.rc != 0)
    #expect((junk.out + junk.err).contains("usage: opc use"))
}
