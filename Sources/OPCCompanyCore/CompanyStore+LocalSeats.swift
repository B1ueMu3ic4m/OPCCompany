import Foundation

// v2.0.0 "the Windows office opens" — Option B phase 2. macOS seats are
// tmux-backed; THIS is the other half of the parity: LONG-LIVED local
// seats (the employee's CLI in interactive mode, stdin kept open) so a
// shell on a machine without tmux — Windows — can start its own
// employees natively. Pipe-mode, no tmux, no ConPTY (see
// docs/TERMINAL_HALL_OPTION_B.md for why ConPTY stays rejected).
//
// Ground rules, inherited from the sibling doors and not negotiable:
//   * The seat registry is a RUNTIME fact — a process is alive or it
//     isn't. Never persisted, never guessed across restarts (the v0.7
//     lesson: a stored liveness verdict freezes a live one).
//   * The TRANSCRIPT persists: output appends into the SAME per-seat
//     log keys tmux seats write (productTerminalLogs), so
//     terminal_digest / terminal_tail / the weight door see local-seat
//     traffic with zero new surface — the shell's transcript works
//     unchanged.
//   * Honest refusals: unknown agent, API/local employees have no CLI
//     seat, codex is one-shot-only (its TUI needs a real TTY), double
//     spawn, steering a seat that isn't there. Never a fake ack.
//   * terminal_send steers "the seat" — tmux first (macOS), local pipe
//     seat second (Windows) — one verb, whichever office you're in.

extension CompanyStore {

    /// Start a LONG-LIVED local seat for [agentID]: the agent's CLI in
    /// its interactive mode, output streaming into the per-seat
    /// transcript. Refuses honestly; see the file header.
    public func spawnLocalSeat(agentID: UUID) throws {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            throw OPCBridgeRefusal(message: "seat_spawn: no agent with id \(agentID.uuidString)")
        }
        guard agent.backend.type == .subscriptionCLI else {
            throw OPCBridgeRefusal(message: "seat_spawn: \(agent.displayName) is not a CLI employee — API/local employees have no local seat")
        }
        guard localSeatProcesses[agentID]?.isAlive != true else {
            throw OPCBridgeRefusal(message: "seat_spawn: \(agent.displayName) already has a live local seat")
        }
        guard let command = CLIAgentCommandBuilder.interactiveCommand(for: agent) else {
            throw OPCBridgeRefusal(message: "seat_spawn: \(agent.backend.command) runs one-shot; no interactive seat (its TUI needs a real TTY)")
        }
        let scopedProductID = selectedProductID
        let rootDirectory = products.first(where: { $0.id == scopedProductID })?.rootDirectory ?? ""
        let root = rootDirectory.isEmpty
            ? nil
            : URL(fileURLWithPath: rootDirectory)
        let process = OPCLocalSeatProcess(
            command: command,
            workingDirectory: root,
            onOutput: { [weak self] text in
                Task { @MainActor in
                    self?.appendTerminalLog(text, for: agentID, productID: scopedProductID)
                }
            })
        do {
            try process.spawn()
        } catch let e as OPCLocalSeatProcess.SpawnFailure {
            throw OPCBridgeRefusal(message: "seat_spawn: \(e.message)")
        }
        localSeatProcesses[agentID] = process
    }

    /// Stop the agent's local seat (stdin EOF first, then SIGINT →
    /// SIGTERM; see OPCLocalSeatProcess.stop). Forgets the registry
    /// entry either way — a stopped seat stops being this store's fact.
    public func stopLocalSeat(agentID: UUID) throws {
        guard let process = localSeatProcesses.removeValue(forKey: agentID) else {
            throw OPCBridgeRefusal(message: "seat_stop: no local seat for \(agentID.uuidString)")
        }
        process.stop()
    }

    /// Runtime liveness of the agent's local seat — a process fact,
    /// never a stored verdict.
    public func hasLiveLocalSeat(agentID: UUID) -> Bool {
        localSeatProcesses[agentID]?.isAlive == true
    }

    /// One steering line into the agent's live LOCAL seat. The same
    /// guards terminal_send applies (empty / >4096 bytes / liveness),
    /// answered with the same honest refusals.
    public func sendLocalSeatLine(agentID: UUID, line: String) throws {
        guard !line.isEmpty else {
            throw OPCBridgeRefusal(message: "terminal_send: empty line")
        }
        guard line.utf8.count <= 4096 else {
            throw OPCBridgeRefusal(message: "terminal_send: line exceeds 4096 bytes")
        }
        guard let process = localSeatProcesses[agentID], process.isAlive else {
            throw OPCBridgeRefusal(message: "terminal_send: no live local seat for this agent")
        }
        do {
            try process.writeLine(line)
        } catch let e as OPCLocalSeatProcess.SpawnFailure {
            throw OPCBridgeRefusal(message: "terminal_send: \(e.message)")
        }
    }
}
