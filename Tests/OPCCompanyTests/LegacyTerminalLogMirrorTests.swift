import Foundation
import Testing
@testable import OPCCompanyCore

/// Proposed snapshot-slimming invariants. These are in-memory tests only;
/// persistence round-trip coverage must be added before changing migration.
@MainActor
@Suite struct LegacyTerminalLogMirrorTests {
    @Test func appendGrowsScopedStoreAndLeavesLegacyMirrorEmpty() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        store.appendTerminalLog("scoped only\n", for: engineer.id)
        #expect(store.productTerminalLogs[key] == "scoped only\n")
        #expect(store.terminalLogs[engineer.id, default: ""].isEmpty)
    }

    @Test func setTerminalLogAlsoSkipsLegacyMirror() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.setTerminalLog("replaced", for: engineer.id)
        #expect(store.terminalLogs[engineer.id] == nil)
    }

    @Test func migrationClearsCopiedLegacyEntryInMemory() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.terminalLogs[engineer.id] = "legacy audit trail"
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        #expect(changed)
        #expect(store.productTerminalLogs[key] == "legacy audit trail")
        #expect(store.terminalLogs[engineer.id] == nil)
    }

    @Test func migrationDropsExactDuplicateLegacyMirror() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.setTerminalLog("double-written text", for: engineer.id)
        store.terminalLogs[engineer.id] = "double-written text"
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        #expect(changed)
        #expect(store.productTerminalLogs[key] == "double-written text")
        #expect(store.terminalLogs[engineer.id] == nil)
    }

    @Test func migrationDropsEmptyLegacyEntries() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.terminalLogs[engineer.id] = ""
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        #expect(changed)
        #expect(store.terminalLogs[engineer.id] == nil)
    }

    @Test func migrationKeepsBothSidesOnConflict() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.setTerminalLog("scoped newer", for: engineer.id)
        store.terminalLogs[engineer.id] = "legacy divergent"
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        #expect(!changed)
        #expect(store.productTerminalLogs[key] == "scoped newer")
        #expect(store.terminalLogs[engineer.id] == "legacy divergent")
    }

    @Test func migrationPreservesExplicitEmptyScopedEntry() throws {
        // An empty scoped entry is an explicit user clear; legacy text must
        // not silently resurrect into it, and must not be discarded either.
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.setTerminalLog("", for: engineer.id)
        store.terminalLogs[engineer.id] = "legacy text"
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        #expect(!changed)
        #expect(store.productTerminalLogs[key] == "")
        #expect(store.terminalLogs[engineer.id] == "legacy text")
    }

    @Test func migrationRoutesToInferredProductNotSelectedProduct() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        store.addProductWorkspace()
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        let target = try #require(store.products.last)
        let other = try #require(store.products.first { $0.id != target.id })
        store.terminalLogs[engineer.id] = "当前产品：\(target.name)\noutput\n"
        let changed = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
        #expect(changed)
        #expect(store.productTerminalLogs[store.terminalLogStorageKey(productID: target.id, agentID: engineer.id)] == "当前产品：\(target.name)\noutput\n")
        #expect(store.productTerminalLogs[store.terminalLogStorageKey(productID: other.id, agentID: engineer.id)] == nil)
        #expect(store.terminalLogs[engineer.id] == nil)
    }

    @Test func migrationIsIdempotentAndPruningPersistsAcrossRoundTrip() throws {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.terminalLogs[engineer.id] = "legacy audit trail"
        #expect(store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false))
        // Second pass over the same store must be a no-op (no oscillation).
        #expect(!store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false))
        try? FileManager.default.removeItem(at: CompanyPersistence.stateURL)
        store.saveSnapshot()
        guard let reloaded = CompanyPersistence.load() else {
            Issue.record("persisted snapshot must reload")
            return
        }
        #expect(reloaded.terminalLogs[engineer.id] == nil)
        let key = store.terminalLogStorageKey(productID: store.selectedProductID, agentID: engineer.id)
        #expect(reloaded.productTerminalLogs[key] == "legacy audit trail")
        // Schema compatibility: legacy field still encodes (empty dict survives).
        let empty = reloaded.terminalLogs
        #expect(empty.isEmpty)
        try? FileManager.default.removeItem(at: CompanyPersistence.stateURL)
    }
}
