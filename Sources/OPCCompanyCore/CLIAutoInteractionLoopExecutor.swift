import Foundation

public struct CLIAutoInteractionTurnObservation: Codable, Hashable, Sendable {
    public var observation: CLIInteractionObservation
    public var timedOut: Bool

    public init(observation: CLIInteractionObservation, timedOut: Bool = false) {
        self.observation = observation
        self.timedOut = timedOut
    }
}

public struct CLIAutoInteractionExecutorTurnReport: Codable, Hashable, Sendable {
    public var updatedState: CLIAutoInteractionLoopState
    public var sentInput: String?
    public var didCallSender: Bool
    public var preflightStopReason: CLIAutoInteractionLoopStopReason?

    public init(
        updatedState: CLIAutoInteractionLoopState,
        sentInput: String?,
        didCallSender: Bool,
        preflightStopReason: CLIAutoInteractionLoopStopReason?
    ) {
        self.updatedState = updatedState
        self.sentInput = sentInput
        self.didCallSender = didCallSender
        self.preflightStopReason = preflightStopReason
    }
}

public struct CLIAutoInteractionLoopExecutionReport: Codable, Hashable, Sendable {
    public var finalState: CLIAutoInteractionLoopState
    public var turnReports: [CLIAutoInteractionExecutorTurnReport]

    public init(
        finalState: CLIAutoInteractionLoopState,
        turnReports: [CLIAutoInteractionExecutorTurnReport]
    ) {
        self.finalState = finalState
        self.turnReports = turnReports
    }

    public var attemptedTurnCount: Int {
        turnReports.count
    }

    public var sentTurnCount: Int {
        turnReports.filter(\.didCallSender).count
    }

    public var summaryText: String {
        """
        自动交互循环执行器：\(finalState.phase.title)
        已尝试轮次：\(attemptedTurnCount)
        已发送轮次：\(sentTurnCount)/\(finalState.maxTurns)
        停止原因：\(finalState.stopReason.title)
        操作建议：\(finalState.stopReason.operatorHint)
        """
    }
}

public enum CLIAutoInteractionLoopExecutor {
    public typealias TurnSender = @Sendable (String) async -> CLIAutoInteractionTurnObservation
    public typealias InputProvider = @Sendable (CLIAutoInteractionLoopState) async -> CLIAutoInteractionGeneratedInput?

    public static func run(
        taskContext: String,
        maxTurns: Int,
        nextInput: InputProvider,
        send: TurnSender
    ) async -> CLIAutoInteractionLoopExecutionReport {
        var state = CLIAutoInteractionLoopGate.start(taskContext: taskContext, maxTurns: maxTurns)
        var turnReports: [CLIAutoInteractionExecutorTurnReport] = []

        while state.canSendNextTurn {
            guard let input = await nextInput(state) else {
                state = CLIAutoInteractionLoopGate.stop(state, reason: .unsafeInput)
                break
            }
            let report = await runOneTurn(state: state, input: input, send: send)
            turnReports.append(report)
            state = report.updatedState
        }

        return CLIAutoInteractionLoopExecutionReport(finalState: state, turnReports: turnReports)
    }

    public static func runOneTurn(
        state: CLIAutoInteractionLoopState,
        input: CLIAutoInteractionGeneratedInput,
        send: TurnSender
    ) async -> CLIAutoInteractionExecutorTurnReport {
        guard state.phase == .running else {
            return CLIAutoInteractionExecutorTurnReport(
                updatedState: state,
                sentInput: nil,
                didCallSender: false,
                preflightStopReason: nil
            )
        }
        if let stopReason = CLIAutoInteractionLoopGate.rejectionReasonBeforeSending(state, nextInput: input) {
            return CLIAutoInteractionExecutorTurnReport(
                updatedState: CLIAutoInteractionLoopGate.stop(state, reason: stopReason),
                sentInput: nil,
                didCallSender: false,
                preflightStopReason: stopReason
            )
        }
        let cleaned = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let turn = await send(cleaned)
        let advanced = CLIAutoInteractionLoopGate.advance(
            state,
            with: CLIAutoInteractionGeneratedInput(text: cleaned, source: .opcGenerated),
            observation: turn.observation,
            timedOut: turn.timedOut
        )
        return CLIAutoInteractionExecutorTurnReport(
            updatedState: advanced,
            sentInput: cleaned,
            didCallSender: true,
            preflightStopReason: nil
        )
    }
}
