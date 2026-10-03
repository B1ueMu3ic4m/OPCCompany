import Foundation
import Testing

// The bridge ABI door tests, gathered under one roof. opc_bridge_create()
// is a process-global singleton — it refuses a second create while one is
// alive — so these tests must take turns. Swift Testing serializes them
// here by construction: one suite, .serialized, no locks. Everything else
// in the repo keeps running in parallel.

@Suite(.serialized)
struct OPCBridgeABIDoorTests {}
