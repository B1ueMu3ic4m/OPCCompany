import Foundation
import Testing

@testable import OPCCompanyCore

// v0.7.0 "the delivery shelf" — the ONE existence door. Every surface
// (card pill, command-center dot, opc deliverables, bridge v1.5) reads
// `existsOnDisk`; this file is the ground truth those surfaces quote.
// Computed, not serialized: the verdict is always NOW.

@Test func shelfVerdictTracksTheFileSystemLive() throws {
    let dir = try TemporaryDirectory()  // helper below (mktemp + auto-clean)
    let product = UUID()

    let real = ArtifactRecord(productID: product, kind: .report,
                              title: "real", path: dir.append("claim.md").path,
                              summary: "s")
    #expect(!real.existsOnDisk, "an unwritten path is a MISSING claim")

    try "hello".data(using: .utf8)!.write(to: dir.append("claim.md"))
    #expect(real.existsOnDisk,
            "the same value must see the file appear — existence is computed per-read, never frozen at decode")

    // a directory is a delivery too (package-style artifact paths exist)
    let pkg = ArtifactRecord(productID: product, kind: .package,
                             title: "dist", path: dir.path, summary: "s")
    #expect(pkg.existsOnDisk)

    // stale claim: delete under it, verdict flips back
    try FileManager.default.removeItem(at: dir.append("claim.md"))
    #expect(!real.existsOnDisk)
    dir.clean()
}

@Test func shelfVerdictNeverLeaksIntoPersistence() throws {
    // Codable surface must be EXACTLY the stored fields — if existsOnDisk
    // ever got serialized, a snapshot could freeze a stale verdict.
    let a = ArtifactRecord(productID: UUID(), kind: .log, title: "t",
                           path: "/nonexistent/anywhere", summary: "s")
    let data = try JSONEncoder().encode(a)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(!obj.keys.contains("existsOnDisk"),
            "the shelf verdict must never be written to disk")
    let back = try JSONDecoder().decode(ArtifactRecord.self, from: data)
    #expect(back.existsOnDisk == false, "re-decode re-answers live")
}

private struct TemporaryDirectory {
    let url: URL
    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("opc-shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func append(_ name: String) -> URL { url.appendingPathComponent(name) }
    var path: String { url.path }
    func clean() { try? FileManager.default.removeItem(at: url) }
}
