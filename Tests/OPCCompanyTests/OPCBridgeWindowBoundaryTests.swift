import Testing
@testable import OPCCompanyCore

@Test func bridgeWindowPreservesCompleteEndCodepoint() {
    let text = "A中文😀"
    let result = OPCBridgeWindow.read(log: text, afterOffset: 0, maxBytes: 100)
    #expect(result.text == text)
    #expect(result.nextOffset == text.utf8.count)
}

@Test func bridgeWindowAlignsInteriorOffsetsAndHandlesHugeBudget() {
    let text = "A中😀Z"
    for offset in 1..<8 {
        let result = OPCBridgeWindow.read(log: text, afterOffset: offset, maxBytes: 1)
        #expect(!result.text.contains("\u{FFFD}"))
        #expect(result.nextOffset > offset)
        #expect(result.text == (offset < 4 ? "中" : "😀"))
    }
    let result = OPCBridgeWindow.read(log: text, afterOffset: 1, maxBytes: Int.max)
    #expect(result.text == "中😀Z")
    #expect(result.nextOffset == text.utf8.count)
}
