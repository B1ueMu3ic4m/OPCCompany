import Foundation

public enum CLIAutoInteractionInputSource: String, Codable, CaseIterable, Sendable {
    case opcGenerated
    case external

    public var title: String {
        switch self {
        case .opcGenerated:
            return "OPC 生成".L().L()
        case .external:
            return "外部输入".L().L()
        }
    }
}

public struct CLIAutoInteractionGeneratedInput: Codable, Hashable, Sendable {
    public var text: String
    public var source: CLIAutoInteractionInputSource

    public init(text: String, source: CLIAutoInteractionInputSource = .opcGenerated) {
        self.text = text
        self.source = source
    }
}

public enum CLIAutoInteractionLoopPhase: String, Codable, CaseIterable, Sendable {
    case rejected
    case running
    case stopped
    case completed

    public var title: String {
        switch self {
        case .rejected:
            return "已拒绝".L().L()
        case .running:
            return "可继续".L().L()
        case .stopped:
            return "已停止".L().L()
        case .completed:
            return "已完成".L().L()
        }
    }
}

public enum CLIAutoInteractionLoopStopReason: String, Codable, CaseIterable, Sendable {
    case none
    case missingTaskContext
    case invalidTurnLimit
    case nonOPCGeneratedInput
    case unsafeInput
    case maxTurnsReached
    case authenticationBlocked
    case busy
    case transientFailure
    case timedOut
    case completedTurn

    public var title: String {
        switch self {
        case .none:
            return "无需停止".L().L()
        case .missingTaskContext:
            return "缺少明确任务上下文".L().L()
        case .invalidTurnLimit:
            return "最大轮次不合规".L().L()
        case .nonOPCGeneratedInput:
            return "下一步输入不是 OPC 生成".L().L()
        case .unsafeInput:
            return "下一步输入不合规".L().L()
        case .maxTurnsReached:
            return "达到最大轮次上限".L().L()
        case .authenticationBlocked:
            return "授权异常".L().L()
        case .busy:
            return "命令行仍在忙碌".L().L()
        case .transientFailure:
            return "临时异常".L().L()
        case .timedOut:
            return "等待超时".L().L()
        case .completedTurn:
            return "本轮已结束".L().L()
        }
    }

    public var operatorHint: String {
        switch self {
        case .none:
            return "当前循环仍可继续，但下一轮仍必须由 OPC 生成明确输入。".L().L()
        case .missingTaskContext:
            return "请先绑定任务、工作项或技术负责人目标，再允许自动交互循环。".L().L()
        case .invalidTurnLimit:
            return "最大轮次必须在 1 到 ".L().L() + "\(CLIAutoInteractionLoopGate.hardTurnLimit)" + " 之间。".L().L()
        case .nonOPCGeneratedInput:
            return "自动循环只允许发送 OPC 生成的下一步文本，不能接收手工粘贴或外部通道原文。".L().L()
        case .unsafeInput:
            return "下一步文本必须是一行非空内容，不能包含换行。".L().L()
        case .maxTurnsReached:
            return "循环已到达预设上限，需要技术负责人查看上下文后重新发起。".L().L()
        case .authenticationBlocked:
            return "请先完成对应命令行工具登录，再由技术负责人重新发起。".L().L()
        case .busy:
            return "请等待当前命令行任务结束，避免向同一席位追加输入。".L().L()
        case .transientFailure:
            return "请先使用恢复建议或手动重试入口处理临时异常。".L().L()
        case .timedOut:
            return "本轮等待已超时，系统不会中断终端席位，也不会继续追加输入。".L().L()
        case .completedTurn:
            return "命令行已经报告本轮结束，循环无需继续追加输入。".L().L()
        }
    }
}

public struct CLIAutoInteractionLoopState: Codable, Hashable, Sendable {
    public var taskContext: String
    public var maxTurns: Int
    public var sentInputs: [String]
    public var phase: CLIAutoInteractionLoopPhase
    public var stopReason: CLIAutoInteractionLoopStopReason

    public init(
        taskContext: String,
        maxTurns: Int,
        sentInputs: [String] = [],
        phase: CLIAutoInteractionLoopPhase = .running,
        stopReason: CLIAutoInteractionLoopStopReason = .none
    ) {
        self.taskContext = taskContext
        self.maxTurns = maxTurns
        self.sentInputs = sentInputs
        self.phase = phase
        self.stopReason = stopReason
    }

    public var canSendNextTurn: Bool {
        phase == .running && sentInputs.count < maxTurns
    }

    public var summaryText: String {
        let context = taskContext.isEmpty ? "未绑定".L().L() : taskContext
        return """
        \("自动交互循环门禁：".L())\(phase.title)
        \("任务上下文：".L())\(context)
        \("已发送轮次：".L())\(sentInputs.count)/\(maxTurns)
        \("停止原因：".L())\(stopReason.title)
        \("操作建议：".L())\(stopReason.operatorHint)
        """
    }
}

public enum CLIAutoInteractionLoopGate {
    public static let hardTurnLimit = 8

    public static func start(taskContext: String, maxTurns: Int) -> CLIAutoInteractionLoopState {
        let cleanedContext = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedContext.isEmpty else {
            return CLIAutoInteractionLoopState(taskContext: "", maxTurns: max(maxTurns, 0), phase: .rejected, stopReason: .missingTaskContext)
        }
        guard maxTurns >= 1 && maxTurns <= hardTurnLimit else {
            return CLIAutoInteractionLoopState(taskContext: cleanedContext, maxTurns: max(maxTurns, 0), phase: .rejected, stopReason: .invalidTurnLimit)
        }
        return CLIAutoInteractionLoopState(taskContext: cleanedContext, maxTurns: maxTurns)
    }

    public static func advance(
        _ state: CLIAutoInteractionLoopState,
        with nextInput: CLIAutoInteractionGeneratedInput,
        observation: CLIInteractionObservation,
        timedOut: Bool = false
    ) -> CLIAutoInteractionLoopState {
        guard state.phase == .running else { return state }
        if let stopReason = rejectionReasonBeforeSending(state, nextInput: nextInput) {
            return stop(state, reason: stopReason)
        }

        let cleanedInput = nextInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = state
        updated.sentInputs.append(cleanedInput)

        if timedOut {
            return stop(updated, reason: .timedOut)
        }

        switch observation.phase {
        case .authenticationBlocked:
            return stop(updated, reason: .authenticationBlocked)
        case .busy:
            return stop(updated, reason: .busy)
        case .transientFailure:
            return stop(updated, reason: .transientFailure)
        case .completedTurn:
            updated.phase = .completed
            updated.stopReason = .completedTurn
            return updated
        case .ready:
            if updated.sentInputs.count >= updated.maxTurns {
                return stop(updated, reason: .maxTurnsReached)
            }
            updated.phase = .running
            updated.stopReason = .none
            return updated
        case .awaitingResponse, .unknown:
            updated.phase = .running
            updated.stopReason = .none
            return updated
        }
    }

    public static func rejectionReasonBeforeSending(
        _ state: CLIAutoInteractionLoopState,
        nextInput: CLIAutoInteractionGeneratedInput
    ) -> CLIAutoInteractionLoopStopReason? {
        guard state.phase == .running else { return nil }
        guard state.sentInputs.count < state.maxTurns else { return .maxTurnsReached }
        guard nextInput.source == .opcGenerated else { return .nonOPCGeneratedInput }

        let cleanedInput = nextInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty, !cleanedInput.contains(where: { $0.isNewline }) else {
            return .unsafeInput
        }
        return nil
    }

    public static func stop(_ state: CLIAutoInteractionLoopState, reason: CLIAutoInteractionLoopStopReason) -> CLIAutoInteractionLoopState {
        var updated = state
        updated.phase = reason == .completedTurn ? .completed : .stopped
        updated.stopReason = reason
        return updated
    }
}
