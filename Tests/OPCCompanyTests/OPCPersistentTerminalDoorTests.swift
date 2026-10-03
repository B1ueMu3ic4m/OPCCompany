import Foundation
import Testing

// The real-tmux door tests, gathered under one roof. Every test here
// drives a REAL tmux server, and the machine has exactly one: run
// concurrently, a test that passes in under a second solo times out at
// the runner's deadline under the full suite's session create/kill
// churn. Swift Testing serializes them here by construction — one
// suite, .serialized, no locks. The extensions live at the end of
// OPCCompanyCoreTests.swift so the file-private helpers stay visible.

@Suite(.serialized)
struct OPCPersistentTerminalDoorTests {}
