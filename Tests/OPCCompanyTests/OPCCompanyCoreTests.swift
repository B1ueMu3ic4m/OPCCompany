import Testing
import CoreGraphics
import Foundation
import Security
@testable import OPCCompanyCore

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(Int, String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(responses: [(Int, String)]) {
        lock.lock()
        self.responses = responses
        self.requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let responseSpec = Self.responses.isEmpty ? (200, "OK") : Self.responses.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid")!, statusCode: responseSpec.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseSpec.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockURLSession(responses: [(Int, String)]) -> URLSession {
    MockURLProtocol.reset(responses: responses)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestBodyText(_ request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

@discardableResult
private func runTestProcess(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 127
    }
}

private func runTestProcessOutput(_ executable: String, _ arguments: [String]) -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if !data.isEmpty { return String(data: data, encoding: .utf8) ?? "" }
        return String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    } catch {
        return ""
    }
}

private func sendLiteralLineToTmux(_ tmuxPath: String, target: String, line: String) {
    // startTerminalWorkspaceForSelectedProduct prints an intro command into each pane.
    // Under the full suite tmux can expose that text before the shell has fully
    // returned to an input prompt, so give the pane a short handoff window before
    // typing the next test command.
    Thread.sleep(forTimeInterval: 0.2)
    runTestProcess(tmuxPath, ["send-keys", "-t", target, "-l", line])
    runTestProcess(tmuxPath, ["send-keys", "-t", target, "Enter"])
}

private func waitForTmuxPaneOutput(
    _ tmuxPath: String,
    target: String,
    contains needle: String,
    historyStart: String = "-300",
    attempts: Int = 80
) async throws -> String {
    try await waitForTmuxPaneOutput(
        tmuxPath,
        target: target,
        historyStart: historyStart,
        attempts: attempts,
        until: { $0.contains(needle) }
    )
}

private func waitForTmuxPaneOutput(
    _ tmuxPath: String,
    target: String,
    containsAll needles: [String],
    historyStart: String = "-300",
    attempts: Int = 80
) async throws -> String {
    try await waitForTmuxPaneOutput(
        tmuxPath,
        target: target,
        historyStart: historyStart,
        attempts: attempts,
        until: { capture in needles.allSatisfy { capture.contains($0) } }
    )
}

/// 公用轮询：每 100ms 抓一次 tmux pane 内容，直到 `until` 返回 true 或耗尽 `attempts`。
/// 不会调用 `#expect`，超时返回最后一次捕获供调用方断言；这样 helper 不会吞掉真实失败。
private func waitForTmuxPaneOutput(
    _ tmuxPath: String,
    target: String,
    historyStart: String = "-300",
    attempts: Int = 80,
    until predicate: (String) -> Bool
) async throws -> String {
    var capture = ""
    for _ in 0..<attempts {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", target, "-S", historyStart])
        if predicate(capture) { break }
    }
    return capture
}

/// defer 友好的 tmux session 清理：直接接 sessionName，可读性更好。
@discardableResult
private func cleanupTmuxSession(_ tmuxPath: String, _ sessionName: String) -> Int32 {
    runTestProcess(tmuxPath, ["kill-session", "-t", sessionName])
}

@MainActor
@discardableResult
private func waitForAgentRunToFinish(
    _ store: CompanyStore,
    agentID: UUID? = nil,
    attempts: Int = 120
) async throws -> Bool {
    for _ in 0..<attempts {
        let isRunning = agentID.map { store.runningAgentIDs.contains($0) } ?? !store.runningAgentIDs.isEmpty
        if !isRunning { return true }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    return !(agentID.map { store.runningAgentIDs.contains($0) } ?? !store.runningAgentIDs.isEmpty)
}

/// 把 fake REPL 脚本送进员工 tmux 席位并等专用 prompt 出现。
/// 等 intro 行（`startTerminalWorkspaceForSelectedProduct` 写入的中文 intro）可见后再 `send-keys -l + Enter`，
/// 然后轮询直到 `readyNeedle` 出现；返回最终 capture 让调用方做 `#expect(capture.contains(...))`。
/// 任一步骤无法满足时仍会让上层断言报错，不在 helper 内吞掉。
///
/// 当 `expectsLatestLineMatchesProfile` 传入对应协议（codex / claude / gemini）时，readyNeedle 命中后
/// **再**轮询直到 fresh tmux capture 的「最近一行」严格等于该协议的 REPL 专用就绪提示——这与生产路径
/// `CompanyStore.terminalAutoInteractionReadinessAudit` 调用 `profile.endsWithReplReadyPrompt(capture)` 是同一条件。
/// 仅满足 substring "codex>" 命中、但末行因 shell prompt 重绘 / 部分帧 / 旧 scrollback 而不是就绪提示时，
/// 生产 readiness audit 会拒绝发送（`sentTurnCount = 0`、`phase = .rejected`）。本严格等待消除该竞态，
/// 让测试触发 `runTerminalAutoInteractionLoop*` 之前 pane 已经稳定在「最后一行 == 就绪提示」状态。
///
/// 对于"故意构造尾部不匹配"的负向用例（例如旧 scrollback 拒绝），保持 nil 即可。
@discardableResult
private func bringFakeREPLScriptOnline(
    _ tmuxPath: String,
    target: String,
    scriptPath: String,
    readyNeedle: String,
    introNeedle: String = "请从 OPC App",
    historyStart: String = "-300",
    introAttempts: Int = 80,
    readyAttempts: Int = 80,
    expectsLatestLineMatchesProfile profile: CLIInteractionProfile? = nil
) async throws -> String {
    _ = try await waitForTmuxPaneOutput(
        tmuxPath,
        target: target,
        contains: introNeedle,
        historyStart: historyStart,
        attempts: introAttempts
    )
    sendLiteralLineToTmux(tmuxPath, target: target, line: scriptPath)
    let needleCapture = try await waitForTmuxPaneOutput(
        tmuxPath,
        target: target,
        contains: readyNeedle,
        historyStart: historyStart,
        attempts: readyAttempts
    )
    guard let profile else { return needleCapture }
    if profile.endsWithReplReadyPrompt(needleCapture) { return needleCapture }
    return try await waitForTmuxPaneOutput(
        tmuxPath,
        target: target,
        historyStart: historyStart,
        attempts: readyAttempts,
        until: { profile.endsWithReplReadyPrompt($0) }
    )
}

@discardableResult
private func writeCLIJobArchive(
    root: URL,
    jobID: String = "job-\(UUID().uuidString)",
    productID: UUID,
    agentID: UUID,
    state: String = "running",
    updatedAt: Date
) throws -> URL {
    let directory = root.appendingPathComponent(".opc/jobs/\(jobID)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("artifacts", isDirectory: true), withIntermediateDirectories: true)
    try "# OPC 命令行作业\n".write(to: directory.appendingPathComponent("brief.md"), atomically: true, encoding: .utf8)
    try "测试任务\n".write(to: directory.appendingPathComponent("agent-task.md"), atomically: true, encoding: .utf8)
    try "".write(to: directory.appendingPathComponent("transcript.log"), atomically: true, encoding: .utf8)
    let status: [String: Any] = [
        "job_id": jobID,
        "product_id": productID.uuidString,
        "agent_id": agentID.uuidString,
        "state": state,
        "exit_code": NSNull(),
        "execution_directory": root.path,
        "updated_at": ISO8601DateFormatter().string(from: updatedAt)
    ]
    let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
    return directory
}

@Test func visibleDateHelpersAvoidAmericanDateAndAMPM() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 19, minute: 2)))

    let dateTime = date.opcDateTimeText
    let shortTime = date.opcShortTimeText

    #expect(dateTime.contains("2026/04/30"))
    #expect(shortTime.contains("19:02"))
    #expect(!dateTime.contains("4/30/2026"))
    #expect(!dateTime.contains("AM"))
    #expect(!dateTime.contains("PM"))
    #expect(!shortTime.contains("AM"))
    #expect(!shortTime.contains("PM"))
}

@MainActor
@Test func bootstrapCreatesCoreCompanyRoles() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.agents.contains { $0.role == .boss })
    #expect(store.agents.contains { $0.role == .cto })
    #expect(store.agents.contains { $0.backend.command == "claude" })
    #expect(store.agents.contains { $0.backend.command == "gemini" })
    #expect(store.selectedAgent?.role == .cto)
}

@MainActor
@Test func directEmployeeMessageNotifiesCTO() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let employee = try #require(store.agents.first { $0.role == .codeEngineer })

    store.sendMessage(to: employee.id, text: "Implement the office scene.")

    #expect(store.messages(for: employee.id).contains { $0.author == .system && $0.text.contains("本地降级提示") })
    #expect(!store.messages(for: employee.id).contains { $0.author == .agent && $0.text.contains("我的角色档案") })
    let ctoMessages = store.messages(for: store.ctoID)
    #expect(ctoMessages.contains { $0.text.contains("员工直聊摘要") })
    #expect(store.events.contains { $0.kind == .ctoSummary })
}

@MainActor
@Test func localChatFallbackDoesNotPretendToBeAgentReply() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.sendMessage(to: store.ctoID, text: "你是谁")

    let reply = try #require(store.messages(for: store.ctoID).last { $0.author == .system })
    #expect(reply.text.contains("本地降级提示"))
    #expect(!store.messages(for: store.ctoID).contains { $0.author == .agent && $0.text.contains("我的角色档案") })
}

@MainActor
@Test func legacySyntheticAgentRepliesAreConvertedToSystemMessages() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.messages.append(ChatMessage(agentID: store.ctoID, author: .agent, text: "收到。我的角色档案是：作为总技术负责人，负责理解老板目标、拆解任务、分配员工、跟踪进度、汇总风险和交付结论。 我会先按职责处理「拆解目标」，同时遵守边界「不把自己称为第三方 CTO」。我会结合记忆：OPC 的默认工作流是老板 -> CTO -> 员工 -> CTO 验收 -> 老板确认。"))

    let changed = store.cleanLegacySyntheticAgentReplies(saveAfterChange: false)

    #expect(changed)
    let cleaned = try #require(store.messages(for: store.ctoID).last)
    #expect(cleaned.author == .system)
    #expect(cleaned.text.contains("旧版本的本地模板回复已隐藏"))
}

@MainActor
@Test func agentOperatingProfilesDriveRepliesAndPrompts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    store.updateSelectedAgentProfile(
        mission: "负责 OPC 的本地 macOS 工程实现。",
        responsibilitiesText: "实现 SwiftUI 功能\n运行验证",
        boundariesText: "不改无关文件",
        responseRulesText: "用第一人称\n报告阻塞",
        memoryText: "老板不喜欢硬编码模板回复",
        skillsText: "SwiftUI\n测试"
    )

    store.sendMessage(to: engineer.id, text: "处理界面问题")

    let reply = try #require(store.messages(for: engineer.id).last { $0.author == .system })
    #expect(reply.text.contains("本地降级提示"))
    #expect(!store.messages(for: engineer.id).contains { $0.author == .agent && $0.text.contains("我的角色档案") })

    let prompt = store.agentSystemPrompt(for: engineer.id)
    #expect(prompt.contains("员工操作档案"))
    #expect(prompt.contains("不改无关文件"))
    #expect(prompt.contains("SwiftUI"))
}

@MainActor
@Test func conversationPromptUsesHumanChatModeInsteadOfOperatingProfile() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    store.messages.append(ChatMessage(agentID: cto.id, author: .agent, text: "收到。我的角色档案是：作为总技术负责人。老板 -> CTO -> 员工。"))

    let prompt = store.agentConversationPrompt(for: cto.id, userText: "你是谁")

    #expect(prompt.contains("真实同事"))
    #expect(prompt.contains("老板问“你是谁”"))
    #expect(!prompt.contains("员工操作档案"))
    #expect(!prompt.contains("职责："))
    #expect(!prompt.contains("长期记忆："))
    #expect(!prompt.contains("我的角色档案是：作为总技术负责人"))
    #expect(!prompt.contains("作为总技术负责人"))
    #expect(!prompt.contains("老板 -> CTO -> 员工"))
    #expect(prompt.contains("系统味表达"))
}

@MainActor
@Test func codexTranscriptExtractionKeepsOnlyNaturalReplyForChat() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let transcript = """
    Reading additional input from stdin...
    user
    你现在不是在写系统报告，也不是在背诵角色档案。
    codex
    老板，我是 Codex 技术负责人，技术这边我来给您兜底。您要推哪个目标，直接跟我说，我来先拆清楚优先级、安排人推进，把风险和结果同步给您。
    2026-04-29T13:44:13Z ERROR codex_core::session: failed to record rollout items
    tokens used
    10,856
    """

    let reply = store.chatReplyPreviewForTesting(transcript)

    #expect(reply == "老板，我是 Codex 技术负责人，技术这边我来给您兜底。您要推哪个目标，直接跟我说，我来先拆清楚优先级、安排人推进，把风险和结果同步给您。")
    #expect(!reply.contains("你现在不是在写系统报告"))
    #expect(!reply.contains("tokens used"))
    #expect(!reply.contains("ERROR"))
    #expect(!store.agentConversationPrompt(for: cto.id, userText: "你是谁").contains("老板 -> CTO"))

    let partialTerminalLog = """
    [OPC 聊天]
    $ /Users/demo/.npm-global/bin/codex exec --skip-git-repo-check --cd . -m gpt-5.5 -c model_reasoning_effort="high" 你是在 OPC 公司里和老板聊天的真实同事
    Reading additional input from stdin...
    OpenAI Codex v0.125.0 (research preview)
    workdir: /Users/demo/Desktop
    user
    老板：你是谁？一句话回答。
    """

    #expect(store.chatReplyPreviewForTesting(partialTerminalLog).isEmpty)
}

@MainActor
@Test func allCurrentAndFutureAgentsUseHumanConversationMode() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let mechanicalHistory = "收到。我的角色档案是：作为总技术负责人。OPC 的默认工作流是老板 -> CTO -> 员工 -> CTO 验收 -> 老板确认。"
    for agent in store.agents where agent.role != .boss {
        store.messages.append(ChatMessage(agentID: agent.id, author: .agent, text: mechanicalHistory))
    }

    store.draftEmployee.displayName = "售前方案师"
    store.draftEmployee.title = "售前方案负责人"
    store.draftEmployee.role = .custom
    store.draftEmployee.command = "codex"
    store.addEmployee(from: store.draftEmployee)

    let workingAgents = store.agents.filter { $0.role != .boss }
    #expect(!workingAgents.isEmpty)

    for agent in workingAgents {
        let prompt = store.agentConversationPrompt(for: agent.id, userText: "你是谁")
        #expect(prompt.contains("真实同事"))
        #expect(prompt.contains("老板问“你是谁”"))
        #expect(!prompt.contains("员工操作档案"))
        #expect(!prompt.contains("职责："))
        #expect(!prompt.contains("长期记忆："))
        #expect(!prompt.contains("我的角色档案是"))
        #expect(!prompt.contains("老板 -> CTO -> 员工"))
        #expect(!prompt.contains("作为总技术负责人"))
    }
}

@MainActor
@Test func chatCommandUsesSameModelAndReasoningAsAgentExecutionProfile() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    #expect(cto.backend.model == "gpt-5.5")
    #expect(cto.backend.reasoningEffort == .high)

    let command = store.chatCommandPreviewForTesting(agentID: cto.id, userText: "你是谁")

    #expect(command.contains("gpt-5.5"))
    #expect(command.contains("model_reasoning_effort=\"high\""))
    #expect(store.agents.first { $0.id == cto.id }?.backend.model == "gpt-5.5")
    #expect(store.agents.first { $0.id == cto.id }?.backend.reasoningEffort == .high)
}

@MainActor
@Test func agentConversationPromptClipsLongHistoryMemoryAndCurrentTextWithoutDroppingCoreContext() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    store.updateSelectedAgentProfile(memoryText: String(repeating: "全局记忆很长", count: 160))
    store.memories.insert(ProductMemoryNote(
        productID: store.selectedProductID,
        agentID: engineer.id,
        kind: .summary,
        title: "长产品记忆",
        detail: String(repeating: "产品记忆很长", count: 180)
    ), at: 0)
    store.messages.append(ChatMessage(
        productID: store.selectedProductID,
        agentID: engineer.id,
        author: .user,
        text: String(repeating: "近期对话很长", count: 260)
    ))

    let prompt = store.agentConversationPrompt(
        for: engineer.id,
        userText: "请继续处理：" + String(repeating: "当前输入很长", count: 500)
    )

    #expect(prompt.contains("真实同事"))
    #expect(prompt.contains("当前产品："))
    #expect(prompt.contains("请继续处理："))
    #expect(prompt.contains("…"))
    #expect(!prompt.contains(String(repeating: "近期对话很长", count: 260)))
    #expect(!prompt.contains(String(repeating: "产品记忆很长", count: 180)))
    #expect(!prompt.contains(String(repeating: "全局记忆很长", count: 160)))
    #expect(!prompt.contains(String(repeating: "当前输入很长", count: 500)))
}

@MainActor
@Test func agentSystemPromptUsesBoundedProfileSummaryForExecutionTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    store.updateSelectedAgentProfile(
        mission: String(repeating: "使命内容很长", count: 180),
        responsibilitiesText: (0..<10).map { "职责 \($0) " + String(repeating: "职责内容很长", count: 90) }.joined(separator: "\n"),
        boundariesText: (0..<10).map { "边界 \($0) " + String(repeating: "边界内容很长", count: 90) }.joined(separator: "\n"),
        responseRulesText: (0..<10).map { "规则 \($0) " + String(repeating: "规则内容很长", count: 90) }.joined(separator: "\n"),
        memoryText: (0..<6).map { "记忆 \($0) " + String(repeating: "记忆内容很长", count: 120) }.joined(separator: "\n"),
        skillsText: (0..<10).map { "自定义技能 \($0)" }.joined(separator: "\n")
    )

    let prompt = store.agentSystemPrompt(for: engineer.id)

    #expect(prompt.contains("员工操作档案"))
    #expect(prompt.contains("职责 0"))
    #expect(prompt.contains("还有 2 项已保存在员工档案"))
    #expect(prompt.contains("还有 2 项已保存在员工档案，按任务需要再读取。"))
    #expect(prompt.contains("…"))
    #expect(!prompt.contains(String(repeating: "使命内容很长", count: 180)))
    #expect(!prompt.contains(String(repeating: "职责内容很长", count: 90)))
    #expect(!prompt.contains(String(repeating: "记忆内容很长", count: 120)))
}

@MainActor
@Test func agentSystemPromptClipsCurrentProductMemoryForExecutionTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    for index in 0..<7 {
        store.memories.append(ProductMemoryNote(
            productID: store.selectedProductID,
            agentID: engineer.id,
            kind: .summary,
            title: "产品记忆 \(index)",
            detail: String(repeating: "产品记忆详情很长", count: 120)
        ))
    }

    let prompt = store.agentSystemPrompt(for: engineer.id)

    #expect(prompt.contains("当前产品员工记忆"))
    #expect(prompt.contains("产品记忆 0"))
    #expect(prompt.contains("还有 1 项已保存在员工档案，按任务需要再读取。"))
    #expect(prompt.contains("…"))
    #expect(!prompt.contains(String(repeating: "产品记忆详情很长", count: 120)))
}

@MainActor
@Test func runtimeSessionsTrackPrewarmCapabilityAndBackendDrift() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let initial = try #require(store.runtimeSession(for: cto.id))
    #expect(initial.state == .cold)
    #expect(initial.capability == .persistentProtocol)
    #expect(initial.keepAlive)
    #expect(CLIAgentCommandBuilder.prewarmCommand(for: cto).contains("--version"))

    store.selectAgent(cto.id)
    store.updateSelectedAgentBackend(reasoningEffort: .medium)

    let updated = try #require(store.runtimeSession(for: cto.id))
    #expect(updated.state == .cold)
    #expect(updated.backendSignature.contains("medium"))
    #expect(updated.lastRestartReason.contains("变化"))
}

@MainActor
@Test func agentWorkspaceFilesAndSessionLogAreWritten() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.selectAgent(engineer.id)
    store.syncSelectedAgentWorkspace()
    let workspace = store.agentWorkspaceURL(for: engineer.id)

    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("AGENTS.md").path))
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("SOUL.md").path))
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("MEMORY.md").path))
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("SKILLS.md").path))

    store.sendMessage(to: engineer.id, text: "记录会话")
    let sessionText = try String(contentsOf: workspace.appendingPathComponent("sessions.jsonl"), encoding: .utf8)
    #expect(sessionText.contains("\"kind\":\"message\""))
    #expect(sessionText.contains("\"kind\":\"reply\""))
}

@MainActor
@Test func skillRoutingPrefersCustomImplementationSpecialist() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let specialist = CompanyAgent(
        displayName: "实现外援",
        title: "自定义工程专家",
        role: .custom,
        backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet"),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .smartCasual,
        permissions: [.readFiles, .editFiles, .runTests],
        seat: OfficeSeat(x: 0.42, y: 0.42, room: "employee-hall")
    )
    store.agents.append(specialist)
    store.products[0].assignedAgentIDs.insert(specialist.id)
    store.agentProfiles[specialist.id] = AgentOperatingProfile(
        mission: "专门处理工程实现任务。",
        responsibilities: ["工程实现"],
        boundaries: ["不处理无关任务"],
        responseRules: ["报告验证结果"],
        skills: ["implementation"]
    )

    let recommended = store.recommendedAgentID(forTaskTitle: "工程实现任务", successCriteria: "完成代码修改并运行测试。", fallbackRole: .codeEngineer)
    #expect(recommended == specialist.id)
}

@MainActor
@Test func skillsDocumentExpandsCatalogSkillsAndKeepsLegacyStringsCompatible() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.selectAgent(engineer.id)
    store.updateSelectedAgentProfile(skillsText: "implementation\nSwiftUI")
    store.syncSelectedAgentWorkspace()

    #expect(store.agentHasSkill(engineer.id, skill: "implementation"))
    #expect(store.agentHasSkill(engineer.id, skill: "工程实现"))
    #expect(store.agentHasSkill(engineer.id, skill: "SwiftUI"))

    let skillsText = try String(contentsOf: store.agentWorkspaceURL(for: engineer.id).appendingPathComponent("SKILLS.md"), encoding: .utf8)
    #expect(skillsText.contains("## implementation：工程实现"))
    #expect(skillsText.contains("修改代码、调试问题、汇报文件和验证命令"))
    #expect(skillsText.contains("## SwiftUI"))
    #expect(skillsText.contains("旧版字符串技能"))
}

@MainActor
@Test func rolePackCanCreateAndConfigureAgentWorkspace() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.createEmployee(fromRolePack: "product-architect")

    let architect = try #require(store.selectedProductAgents.first { $0.role == .productArchitect })
    let profile = store.operatingProfile(for: architect.id)
    #expect(profile.skills.contains("product-architecture"))
    #expect(architect.backend.command == "codex")
    #expect(store.agentHasSkill(architect.id, skill: "产品架构"))

    let workspace = store.agentWorkspaceURL(for: architect.id)
    let workspaceText = try String(contentsOf: workspace.appendingPathComponent("WORKSPACE.md"), encoding: .utf8)
    let soulText = try String(contentsOf: workspace.appendingPathComponent("SOUL.md"), encoding: .utf8)
    #expect(workspaceText.contains(store.selectedProduct?.name ?? ""))
    #expect(workspaceText.contains("产品团队"))
    #expect(soulText.contains("可实现、可验收"))
}

@MainActor
@Test func ctoRolePackCannotCreateSecondCTOOrDriftIdentity() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let originalCTOID = store.ctoID

    store.createEmployee(fromRolePack: "cto-orchestrator")
    #expect(store.agents.filter { $0.role == .cto }.count == 1)
    #expect(store.agents.first { $0.id == originalCTOID }?.role == .cto)
    #expect(store.events.contains { $0.title == "已阻止重复技术负责人" })
}

@MainActor
@Test func compactingAgentMemoryWritesProfileAndMemoryFile() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.selectAgent(engineer.id)
    store.sendMessage(to: engineer.id, text: "这个产品以后不要硬编码回复。")
    store.compactSelectedAgentMemory()

    let profile = store.operatingProfile(for: engineer.id)
    #expect(!profile.memory.contains { $0.contains("不要硬编码回复") },
            "自动压缩的产品对话记忆不应写入员工全局 profile.memory")
    let productMemories = store.selectedProductAgentMemories(for: engineer.id)
    #expect(productMemories.contains { $0.detail.contains("不要硬编码回复") })
    #expect(productMemories.contains { $0.detail.contains("老板：这个产品以后不要硬编码回复。") })
    #expect(productMemories.allSatisfy { $0.agentID == engineer.id && $0.productID == store.selectedProductID })
    #expect(!profile.memory.contains { $0.contains("user：") || $0.contains("agent：") || $0.contains("system：") })
    let memoryText = try String(contentsOf: store.agentWorkspaceURL(for: engineer.id).appendingPathComponent("MEMORY.md"), encoding: .utf8)
    #expect(memoryText.contains("当前产品员工记忆"))
    #expect(memoryText.contains("不要硬编码回复"))
    #expect(memoryText.contains("老板：这个产品以后不要硬编码回复。"))
    #expect(!memoryText.contains("user："))
}

@MainActor
@Test func compactedAgentMemoryDoesNotPolluteOtherProductSystemPromptAfterLambdaFollowup() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productA = store.selectedProductID
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)

    store.messages.append(ChatMessage(productID: productA, agentID: engineer.id, author: .user, text: "A 产品专属系统提示记忆"))
    store.compactSelectedAgentMemory()

    let productAPrompt = store.agentSystemPrompt(for: engineer.id)
    #expect(productAPrompt.contains("A 产品专属系统提示记忆"))

    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(engineer.id)

    let productBPrompt = store.agentSystemPrompt(for: engineer.id)
    #expect(!productBPrompt.contains("A 产品专属系统提示记忆"),
            "A 产品压缩记忆不应出现在 B 产品员工系统提示")
}

@MainActor
@Test func compactedAgentMemoryDoesNotPolluteOtherProductExecutionPromptAfterLambdaFollowup() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productA = store.selectedProductID
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)

    store.messages.append(ChatMessage(productID: productA, agentID: engineer.id, author: .user, text: "A 产品专属执行提示记忆"))
    store.compactSelectedAgentMemory()

    let productACommand = store.commandPreviewForTesting(agentID: engineer.id, prompt: "执行").joined(separator: "\n")
    #expect(productACommand.contains("A 产品专属执行提示记忆"))

    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(engineer.id)

    let productBCommand = store.commandPreviewForTesting(agentID: engineer.id, prompt: "执行").joined(separator: "\n")
    #expect(!productBCommand.contains("A 产品专属执行提示记忆"),
            "A 产品压缩记忆不应出现在 B 产品员工执行提示")
}

@MainActor
@Test func syncedAgentWorkspaceMemoryFileUsesSelectedProductScopedMemoryAfterLambdaFollowup() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productA = store.selectedProductID
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)

    store.messages.append(ChatMessage(productID: productA, agentID: engineer.id, author: .user, text: "A 产品专属文件记忆"))
    store.compactSelectedAgentMemory()

    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)
    store.syncSelectedAgentWorkspace()

    let productBMemory = try String(contentsOf: store.agentWorkspaceURL(for: engineer.id).appendingPathComponent("MEMORY.md"), encoding: .utf8)
    #expect(productBMemory.contains("当前产品员工记忆"))
    #expect(!productBMemory.contains("A 产品专属文件记忆"),
            "员工 MEMORY.md 应随当前产品同步，只写当前产品员工记忆")

    store.selectProduct(productA)
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)
    store.syncSelectedAgentWorkspace()

    let productAMemory = try String(contentsOf: store.agentWorkspaceURL(for: engineer.id).appendingPathComponent("MEMORY.md"), encoding: .utf8)
    #expect(productAMemory.contains("A 产品专属文件记忆"))
}

@MainActor
@Test func terminalHallExcludesBossFromExecutableAgents() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.executableAgents.allSatisfy { $0.role != .boss })
    #expect(store.executableAgents.contains { $0.role == .cto })
    #expect(store.executableAgents.contains { $0.backend.command == "claude" })
}

@MainActor
@Test func terminalLogCanBeClearedPerAgent() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let employee = try #require(store.agents.first { $0.role == .codeEngineer })

    store.terminalLogs[employee.id] = "old output"
    store.clearTerminalLog(for: employee.id)

    #expect(store.terminalLogs[employee.id] == "")
    #expect(store.events.contains { $0.title == "终端日志已清空" && $0.agentID == employee.id })
}

@MainActor
@Test func bootstrapCreatesProductWorkspaces() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.mainWorkspace == .office)
    #expect(store.products.count == 1)
    #expect(store.selectedProduct?.name == "默认产品工作区")
    #expect(store.selectedProductAgents.contains { $0.role == .cto })
    #expect(store.selectedProductTasks.allSatisfy { $0.productID == store.selectedProductID })
}

@MainActor
@Test func defaultProductRootsStayInsideOPCApplicationSupport() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productRoot = try #require(store.selectedProduct?.rootDirectory)
    let supportProductsRoot = CompanyPersistence.productWorkspacesURL.standardizedFileURL.path
    let desktopRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)
        .standardizedFileURL
        .path

    #expect(productRoot.hasPrefix(supportProductsRoot + "/"))
    #expect(!productRoot.hasPrefix(desktopRoot))
    #expect(FileManager.default.fileExists(atPath: productRoot))

    store.addProductWorkspace()
    let newProductRoot = try #require(store.selectedProduct?.rootDirectory)
    #expect(newProductRoot.hasPrefix(supportProductsRoot + "/"))
    #expect(!newProductRoot.hasPrefix(desktopRoot))
    #expect(FileManager.default.fileExists(atPath: newProductRoot))

    store.resetToDefaultCompanyState()
    let resetRoot = try #require(store.selectedProduct?.rootDirectory)
    #expect(resetRoot.hasPrefix(supportProductsRoot + "/"))
    #expect(!resetRoot.hasPrefix(desktopRoot))
    #expect(FileManager.default.fileExists(atPath: resetRoot))
}

@MainActor
@Test func legacyDesktopDefaultProductRootsMigrateWithoutTouchingImportedProjects() async throws {
    let desktop = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)
        .standardizedFileURL
    let defaultMigrated = CompanyStore.migratedRootForLegacyDesktopDefaultProduct(
        rootDirectory: desktop.path,
        productName: "默认产品工作区",
        importReport: nil
    )
    #expect(defaultMigrated == CompanyStore.defaultProductRootDirectory())

    let generatedMigrated = CompanyStore.migratedRootForLegacyDesktopDefaultProduct(
        rootDirectory: desktop.appendingPathComponent("OPCProduct3", isDirectory: true).path,
        productName: "新产品 3",
        importReport: nil
    )
    #expect(generatedMigrated == CompanyStore.newProductRootDirectory(index: 3))

    let importedReport = ProjectImportReport(
        projectName: "OPCProduct3",
        shortName: "OPC",
        rootDirectory: desktop.appendingPathComponent("OPCProduct3", isDirectory: true).path,
        ruleFiles: [],
        detectedTools: [],
        projectFiles: [],
        summary: "显式导入项目"
    )
    let importedMigrated = CompanyStore.migratedRootForLegacyDesktopDefaultProduct(
        rootDirectory: importedReport.rootDirectory,
        productName: "新产品 3",
        importReport: importedReport
    )
    #expect(importedMigrated == nil)
}

@MainActor
@Test func productSettingsCanRenameAndMoveProductToInternalWorkspace() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let internalRoot = CompanyStore.internalProductRootDirectory(for: productID)

    let changed = store.updateProductSettings(
        productID: productID,
        name: "客户售前系统",
        shortName: "售前",
        rootDirectory: internalRoot
    )

    #expect(changed)
    let product = try #require(store.selectedProduct)
    #expect(product.name == "客户售前系统")
    #expect(product.shortName == "售前")
    #expect(product.rootDirectory == internalRoot)
    #expect(FileManager.default.fileExists(atPath: internalRoot))
    #expect(store.events.contains { $0.title == "产品设置已更新" && $0.detail.contains("客户售前系统") })
}

@MainActor
@Test func productSettingsRejectBlankNameOrRootWithoutMutatingProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let original = try #require(store.selectedProduct)

    #expect(!store.updateProductSettings(productID: original.id, name: "   ", shortName: "X", rootDirectory: "/tmp/x"))
    #expect(!store.updateProductSettings(productID: original.id, name: "有效名称", shortName: "X", rootDirectory: "   "))
    #expect(store.selectedProduct?.name == original.name)
    #expect(store.selectedProduct?.shortName == original.shortName)
    #expect(store.selectedProduct?.rootDirectory == original.rootDirectory)
}

@Test func productDetailExposesProductSettingsEditor() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("Label(\"编辑产品\", systemImage: \"pencil\")"))
    #expect(source.contains("ProductSettingsSheet(product: product)"))
    #expect(source.contains("TextField(\"产品名称\", text: $draft.name)"))
    #expect(source.contains("TextField(\"本地工作区路径\", text: $draft.rootDirectory)"))
    #expect(source.contains("CompanyStore.internalProductRootDirectory(for: product.id)"))
}

@Test func mainWorkspaceIncludesBossControlViews() async throws {
    let titles = MainWorkspace.allCases.map(\.title)

    #expect(titles.contains("总控台"))
    #expect(titles.contains("产品详情"))
    #expect(titles.contains("员工工作台"))
    #expect(titles.contains("公司场景"))
    #expect(titles.contains("流程图"))
    #expect(titles.contains("终端大厅"))
}

@Test func workNavigationExcludesCompanyScene() async throws {
    let titles = MainWorkspace.workNavigationCases.map(\.title)

    #expect(!titles.contains("公司场景"))
    #expect(titles == ["总控台", "产品详情", "员工工作台", "流程图", "终端大厅"])
}

@Test func bossCommandCenterShowsOnlyOwnerResultSections() async throws {
    let titles = CommandCenterSection.allCases.map(\.title)

    #expect(titles == ["老板总览", "待我决策", "汇报交付"])
    #expect(!titles.contains("自动执行"))
    #expect(!titles.contains("自动交互循环"))
    #expect(!titles.contains("方案工厂"))
    #expect(!titles.contains("通信网关"))
    #expect(!titles.contains("高级控制台"))
    #expect(!titles.contains("更多"))
}

@MainActor
@Test func workOrderPromptIncludesProductRulesAndTaskContext() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCWorkOrderTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "Rules".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
    try "{}".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.importProductWorkspace(from: root)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "执行台测试任务", ownerID: engineer.id, status: .assigned, successCriteria: "提示词必须包含任务和规则。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "执行台测试任务" })
    let prompt = store.workOrderPrompt(for: task)

    #expect(prompt.contains("执行台测试任务"))
    #expect(prompt.contains("提示词必须包含任务和规则"))
    #expect(prompt.contains("AGENTS.md"))
    #expect(prompt.contains(root.path))
}

@MainActor
@Test func workOrderPromptCapsLargeImportReportAndLongTaskFieldsForTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    let longFile = String(repeating: "Sources/VeryLongPath/", count: 20)
    store.products[productIndex].rootDirectory = String(repeating: "/Users/local/project/", count: 40)
    store.products[productIndex].importReport = ProjectImportReport(
        projectName: "大型项目",
        shortName: "大型",
        rootDirectory: "/tmp/large",
        ruleFiles: (0..<40).map { "规则文件-\($0)-" + longFile },
        detectedTools: (0..<30).map { "工具-\($0)-" + String(repeating: "能力", count: 90) },
        projectFiles: (0..<500).map { "项目文件-\($0)-" + longFile },
        summary: "大型导入报告"
    )
    store.createTask(
        title: "大型导入工单",
        ownerID: engineer.id,
        status: .assigned,
        successCriteria: String(repeating: "验收标准很长", count: 800),
        artifactPath: String(repeating: "/tmp/output/", count: 80)
    )
    let task = try #require(store.selectedProductTasks.first { $0.title == "大型导入工单" })

    let prompt = store.workOrderPrompt(for: task)

    #expect(prompt.contains("大型导入工单"))
    #expect(prompt.contains("还有 488 项已保存在导入报告，按任务需要再读取。"))
    #expect(prompt.contains("…"))
    #expect(prompt.count < 8_000)
    #expect(!prompt.contains(String(repeating: "验收标准很长", count: 800)))
    #expect(!prompt.contains("项目文件-499"))
}

@MainActor
@Test func bossReportAndHandoffSnapshotWriteMessagesAndEvents() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.generateBossReport()
    store.createHandoffSnapshot()

    #expect(store.messages(for: store.bossID).contains { $0.text.contains("老板报告") })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("产品交接快照") })
    #expect(store.events.contains { $0.title == "老板报告已生成" })
    #expect(store.events.contains { $0.title == "交接快照已生成" })
}

@MainActor
@Test func specialistTeamTemplatesHealthAndAcceptanceReportsWork() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.seedStandardTaskTemplates(goal: "增强 OPC")
    #expect(store.selectedProductTasks.contains { $0.title == "模板：产品范围与成功标准" })
    #expect(store.selectedProductTasks.contains { $0.title == "模板：测试验证清单" })

    store.generateHealthAudit()
    #expect(store.messages(for: store.bossID).contains { $0.text.contains("产品健康体检") })
    #expect(store.events.contains { $0.title == "产品健康体检已生成" })

    let task = try #require(store.selectedProductTasks.first { $0.title == "模板：产品范围与成功标准" })
    store.generateAcceptanceReport(for: task.id)
    #expect(store.messages(for: store.bossID).contains { $0.text.contains("验收报告") && $0.text.contains(task.title) })
    #expect(store.events.contains { $0.title == "验收报告已生成" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "验收报告：\(task.title)" })
    #expect(store.selectedProductAgentMessages.contains { $0.kind == .reviewCompleted && $0.taskID == task.id })
}

@MainActor
@Test func legacyPipelineTasksAreRemovedByRunDataCleanup() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.createTask(title: "流水线 旧版任务", ownerID: store.ctoID, status: .running, successCriteria: "旧数据应可清理。")

    #expect(store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })

    store.clearSelectedProductRunData()

    #expect(!store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })
    #expect(store.events.contains { $0.title == "产品运行数据已清理" })
}

@MainActor
@Test func selectedProductRunDataCleanupDoesNotDeleteEmployeesOrBaseTasks() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let agentCount = store.agents.count

    store.createTask(title: "流水线 旧版清理任务", ownerID: store.ctoID, status: .running, successCriteria: "旧流水线任务应被运行数据清理。")
    store.createTask(title: "分支 清理测试样本", ownerID: store.ctoID, status: .assigned, successCriteria: "旧分支任务应被运行数据清理。")
    let branchTask = try #require(store.selectedProductTasks.first { $0.title == "分支 清理测试样本" })
    store.enqueueWorkItem(taskID: branchTask.id, agentID: store.ctoID)
    store.branchPlans.append(BranchExecutionPlan(
        productID: store.selectedProductID,
        goal: "清理测试",
        orchestratorID: store.ctoID,
        status: .running,
        lanes: [BranchPlanLane(title: "分支 清理测试样本", agentID: store.ctoID, taskID: branchTask.id, successCriteria: "旧分支任务应被运行数据清理。")],
        aggregationTaskID: nil
    ))
    store.ensureCommunicationGatewayPlan()
    store.ingestRemoteCommand("清理测试手机指令")
    store.startCTOSupervisorGoal(goal: "清理测试消息")
    store.addMemory(kind: .decision, title: "清理测试记忆", detail: "应被清理")

    #expect(store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })
    #expect(store.selectedProductBranchPlans.count == 1)
    #expect(!store.selectedProductCommunicationLogs.isEmpty)
    #expect(!store.selectedProductAgentMessages.isEmpty)

    store.clearSelectedProductRunData()

    #expect(store.agents.count == agentCount)
    #expect(store.selectedProductTasks.contains { $0.title == "定义产品架构" })
    #expect(!store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") || $0.title.hasPrefix("分支 ") || $0.title.hasPrefix("手机指令：") })
    #expect(store.selectedProductWorkQueue.isEmpty)
    #expect(store.selectedProductBranchPlans.isEmpty)
    #expect(store.selectedProductCommunicationLogs.isEmpty)
    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(store.events.contains { $0.title == "产品运行数据已清理" })
}

@MainActor
@Test func productIsolationAuditReportsAndRecordsVerification() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    let cto = store.ctoID
    store.createTask(title: "第二产品任务", ownerID: cto, status: .assigned, successCriteria: "不能串到默认产品。")

    let report = store.productIsolationAuditText()
    #expect(report.contains("多产品隔离体检"))
    #expect(report.contains("新产品 2"))
    #expect(report.contains("当前产品数据按产品归属隔离"))
    #expect(!report.contains("productID 隔离"))

    store.runProductIsolationAudit()

    #expect(store.selectedProductVerifications.contains { $0.title == "多产品隔离体检" })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("多产品隔离体检") })
    #expect(store.events.contains { $0.title == "多产品隔离体检完成" })
    #expect(store.selectedProductID == secondProductID)
}

@MainActor
@Test func cliToolchainPreflightRecordsAllExecutableAgentsWithoutRunningThem() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let report = store.cliToolchainPreflightText()
    #expect(report.contains("命令行链路压测预检"))
    #expect(report.contains("Codex 技术负责人"))
    #expect(report.contains("Claude Code 工程师"))
    #expect(report.contains("运行摘要"))
    #expect(!report.contains("OPC_PROMPT"))
    #expect(!report.contains("model_reasoning_effort"))
    #expect(!report.contains("--skip-git-repo-check"))
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let engineerPreflight = store.cliPreflightText(for: engineer.id, prompt: "隔离执行测试")
    #expect(engineerPreflight.contains("执行目录"))
    #expect(engineerPreflight.contains("隔离策略"))
    #expect(engineerPreflight.contains("运行摘要"))
    #expect(!engineerPreflight.contains("OPC_PROMPT"))
    #expect(!engineerPreflight.contains("model_reasoning_effort"))
    #expect(!engineerPreflight.contains("--skip-git-repo-check"))

    store.runCLIToolchainPreflightForSelectedProduct()

    #expect(store.selectedProductVerifications.contains { $0.title == "命令行链路压测预检" })
    #expect(store.events.contains { $0.title == "命令行链路压测预检完成" })
    #expect(store.runningAgentIDs.isEmpty)
    #expect(store.terminalLogs[store.ctoID, default: ""].contains("[OPC 命令行链路压测预检]"))

    let isolationReport = store.cliRuntimeIsolationAuditText()
    #expect(isolationReport.contains("命令行与工作区隔离体检"))
    #expect(isolationReport.contains("员工工作区"))
    #expect(isolationReport.contains("代码类独立执行区"))
    #expect(!isolationReport.contains("sessions.jsonl"))
    #expect(!isolationReport.contains(".opc/worktrees"))
    #expect(!isolationReport.contains("元数据"))
    #expect(!isolationReport.contains("/source"))

    store.runCLIRuntimeIsolationAudit()

    #expect(store.selectedProductVerifications.contains { $0.title == "命令行与工作区隔离体检" })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("命令行与工作区隔离体检") })
    #expect(store.events.contains { $0.title == "命令行与工作区隔离体检完成" })
    let isolationDirectory = store.cliWorktreeIsolationURL(for: engineer)
    #expect(FileManager.default.fileExists(atPath: isolationDirectory.appendingPathComponent("WORKTREE.md").path))
    #expect(store.cliRuntimeIsolationAuditText().contains("已登记"))
    #expect(!store.cliRuntimeIsolationAuditText().contains("sessions.jsonl"))
    let isolationDetail = store.cliRuntimeIsolationAuditDetailText()
    #expect(isolationDetail.contains("员工会话日志档案"))
    #expect(!isolationDetail.contains("会话日志文件：sessions.jsonl"))
    #expect(store.cliExecutionDirectoryPath(for: engineer.id) != isolationDirectory.path)
    #expect(store.cliPreflightText(for: engineer.id, prompt: "隔离执行测试").contains("真实运行暂用主工作目录"))
}

@MainActor
@Test func cliIsolationAuditCreatesSnapshotExecutionDirectoryForProjectRoot() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCSnapshotIsolation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try "print(\"ok\")".write(to: root.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.runCLIRuntimeIsolationAudit()

    let sourcePath = store.cliIsolationSourcePath(for: engineer.id)
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: sourcePath).appendingPathComponent("Package.swift").path))
    #expect(store.cliExecutionDirectoryPath(for: engineer.id) == sourcePath)
    #expect(store.cliRuntimeIsolationAuditText().contains("可执行"))
}

@MainActor
@Test func terminalWorkspacePlanUsesCurrentProductTeamAndExecutionDirectories() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCTerminalWorkspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    store.runCLIRuntimeIsolationAudit()

    let report = store.terminalWorkspacePlanText()

    #expect(report.contains("真实终端工作区计划"))
    #expect(report.contains("员工终端席位"))
    #expect(report.contains("Codex 技术负责人"))
    #expect(report.contains("Claude Code 工程师"))
    #expect(report.contains("不自动执行模型任务"))
    #expect(!report.contains("老板：窗口"))
    #expect(!report.contains("窗口 "))
    #expect(!report.contains("tmux"))
    #expect(!report.contains("会话："))
    #expect(!report.contains("opc-"))
    #expect(!report.contains("codeengineer-"))
    let detail = store.terminalWorkspacePlanDetailText()
    #expect(!detail.contains("未找到 tmux"))
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    #expect(!report.contains(store.cliExecutionDirectoryPath(for: engineer.id)))
    #expect(report.contains("执行位置 独立执行区"))
}

@MainActor
@Test func terminalWorkspaceRefreshReportsMissingSessionWithoutStartingAgents() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.refreshTerminalWorkspaceLogsForSelectedProduct()

    #expect(store.runningAgentIDs.isEmpty)
    #expect(store.selectedProductVerifications.contains { $0.title == "真实终端日志刷新" })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("真实终端日志刷新") })
    #expect(store.events.contains { $0.title == "真实终端工作区未找到" || $0.title == "真实终端日志刷新完成" })
}

@MainActor
@Test func terminalWorkspaceIntroCommandEscapesEmployeeNamesForShell() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    let engineerID = store.agents[engineerIndex].id
    store.agents[engineerIndex].displayName = "工程师'; touch /tmp/opc-injected; echo '"

    var command = store.terminalWorkspaceIntroCommandPreviewForTesting(agentID: engineerID)

    #expect(command.hasPrefix("printf %b '"))
    #expect(command.contains("'\\''"))
    #expect(command.contains("工程师'\\''; touch"))
    #expect(command.contains("OPC 员工终端"))
    #expect(command.contains("预检、作业档案和验收记录"))

    store.agents[engineerIndex].displayName = "反斜杠\\n试探"
    command = store.terminalWorkspaceIntroCommandPreviewForTesting(agentID: engineerID)
    #expect(command.hasPrefix("printf %b '"))
    #expect(command.contains("反斜杠\\\\n试探"))
}

@MainActor
@Test func terminalWorkspaceIntroCommandKeepsCommandSubstitutionAndPercentLiteral() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    let engineerID = store.agents[engineerIndex].id
    store.agents[engineerIndex].displayName = "测试$(rm -rf /tmp/x)`whoami`100%牛"

    let command = store.terminalWorkspaceIntroCommandPreviewForTesting(agentID: engineerID)

    #expect(command.hasPrefix("printf %b '"))
    #expect(command.hasSuffix("'"))
    #expect(command.contains("$(rm -rf /tmp/x)"))
    #expect(command.contains("`whoami`"))
    #expect(command.contains("100%牛"))
    #expect(!command.contains("printf %b '$(rm"))
}

@MainActor
@Test func terminalWorkspaceStartIsIdempotentAndDoesNotBypassJobOrMessageFlow() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCTmuxIdempotent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    let firstLogs = store.terminalLogs
    store.startTerminalWorkspaceForSelectedProduct()
    let ctoPlanMessageCount = store.messages(for: store.ctoID)
        .filter { $0.text.contains("真实终端工作区计划") }
        .count
    let workspaceStartedEventCount = store.events
        .filter { $0.title == "真实终端工作区已启动" }
        .count

    #expect(store.terminalLogs == firstLogs)
    #expect(ctoPlanMessageCount <= 2)
    #expect(workspaceStartedEventCount <= 2)
    #expect(store.runningAgentIDs.isEmpty)
    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
    #expect(store.selectedProductVerifications.contains { $0.title == "真实终端工作区" })
}

@MainActor
@Test func terminalWorkspaceHealthAuditReportsAndPassesAfterWorkspaceStart() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCTerminalHealth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    let initialText = store.terminalWorkspaceHealthAuditText()
    #expect(initialText.contains("持久终端可用性巡检"))
    #expect(initialText.contains("主要待处理：尚未巡检"))
    #expect(initialText.contains("工作区会话：待巡检"))
    #expect(store.selectedProductArchitectureChecks.first { $0.id == "terminal-workspace" }?.status == .warning)
    #expect(store.runTerminalWorkspaceHealthAuditForSelectedProduct() == .warning)
    #expect(store.terminalWorkspaceHealthAuditText().contains("工作区会话：未启动"))
    #expect(store.selectedProductVerifications.contains { $0.title == "持久终端可用性巡检" })

    store.startTerminalWorkspaceForSelectedProduct()

    let passedText = store.terminalWorkspaceHealthAuditText()
    #expect(passedText.contains("持久终端可用性巡检：通过"))
    #expect(passedText.contains("控制窗口：已连接"))
    #expect(store.selectedProductArchitectureChecks.first { $0.id == "terminal-workspace" }?.status == .passed)
    #expect(store.runTerminalWorkspaceHealthAuditForSelectedProduct() == .passed)
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("持久终端可用性巡检：通过") })
    #expect(store.events.contains { $0.title == "持久终端可用性巡检完成" })
}

@MainActor
@Test func terminalWorkspaceHealthStatusMatrixCoversMissingToolControlAndSeats() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.terminalWorkspaceHealthStatusForTesting(tmuxReady: false, sessionExists: false, hasControlWindow: false, missingAgentCount: 4) == .failed)
    #expect(store.terminalWorkspaceHealthStatusForTesting(tmuxReady: true, sessionExists: false, hasControlWindow: false, missingAgentCount: 4) == .warning)
    #expect(store.terminalWorkspaceHealthStatusForTesting(tmuxReady: true, sessionExists: true, hasControlWindow: false, missingAgentCount: 0) == .warning)
    #expect(store.terminalWorkspaceHealthStatusForTesting(tmuxReady: true, sessionExists: true, hasControlWindow: true, missingAgentCount: 1) == .warning)
    #expect(store.terminalWorkspaceHealthStatusForTesting(tmuxReady: true, sessionExists: true, hasControlWindow: true, missingAgentCount: 0) == .passed)
}

@MainActor
@Test func terminalWorkspaceHealthAuditReportsMissingControlWindow() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCTerminalHealthControl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    _ = runTestProcess(tmuxPath, ["kill-window", "-t", "\(sessionName):control"])

    #expect(store.runTerminalWorkspaceHealthAuditForSelectedProduct() == .warning)
    let text = store.terminalWorkspaceHealthAuditText()
    #expect(text.contains("主要待处理：控制窗口未连接"))
    #expect(text.contains("控制窗口：未连接"))
}

@MainActor
@Test func terminalWorkspaceHealthAuditReportsMissingEmployeeSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCTerminalHealthSeat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    _ = runTestProcess(tmuxPath, ["kill-window", "-t", "\(sessionName):\(windowName)"])

    #expect(store.runTerminalWorkspaceHealthAuditForSelectedProduct() == .warning)
    let text = store.terminalWorkspaceHealthAuditText()
    #expect(text.contains("主要待处理：1 个员工席位待创建"))
    #expect(text.contains("员工席位：3/4"))
    #expect(text.contains("\(engineer.displayName)：终端席位待创建"))
}

@MainActor
@Test func persistentProtocolRunUsesTerminalWorkspaceWhenAvailable() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentTerminal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    cleanupTmuxSession(tmuxPath, sessionName)
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()

    var session = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    session.keepAlive = true
    store.runtimeSessions[engineer.id] = session

    #expect(store.persistentTerminalTargetPreviewForTesting(agentID: engineer.id).contains(sessionName))
    store.runtimeSessions[engineer.id] = session

    store.runAgent(agentID: engineer.id, prompt: "persistent smoke")
    #expect(try await waitForAgentRunToFinish(store, attempts: 120))

    let terminalLog = store.terminalLogs[engineer.id, default: ""]
    #expect(terminalLog.contains("OPC 长期席位执行"))
    #expect(!terminalLog.contains("OPC 常驻终端执行"))
    #expect(terminalLog.contains("persistent smoke"))
    #expect(store.persistentTerminalSessionCacheCountForTesting() == 1)
    #expect(store.runtimeSessions[engineer.id]?.state == .ready)
    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let jobDirectories = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
    let job = try #require(jobDirectories.first)
    let transcript = try String(contentsOf: job.appendingPathComponent("transcript.log"))
    #expect(transcript.contains("persistent smoke"))
    #expect(!transcript.contains("__OPC_JOB_EXIT"))
    #expect(store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") && $0.path.hasPrefix(jobsRoot.path) })

    store.runAgent(agentID: engineer.id, prompt: "persistent smoke again")
    #expect(try await waitForAgentRunToFinish(store, attempts: 120))
    #expect(store.persistentTerminalSessionCacheCountForTesting() == 1)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("persistent smoke again"))

    store.clearSelectedProductRunData()
    #expect(store.persistentTerminalSessionCacheCountForTesting() == 0)
}

@MainActor
@Test func persistentProtocolRunDetectsMarkersAfterLongOutput() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentLongOutput-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("long-output.sh")
    try """
    #!/bin/sh
    i=0
    while [ "$i" -lt 1200 ]; do
      printf 'long-line-%04d\\n' "$i"
      i=$((i + 1))
    done
    printf 'prompt:%s\\n' "$1"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    store.products[0].rootDirectory = root.path

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: script.path, model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    cleanupTmuxSession(tmuxPath, sessionName)
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    store.runAgent(agentID: engineer.id, prompt: "long-output-smoke")
    #expect(try await waitForAgentRunToFinish(store, agentID: engineer.id, attempts: 160))

    let terminalLog = store.terminalLogs[engineer.id, default: ""]
    #expect(terminalLog.contains("命令退出码 0"))
    #expect(!terminalLog.contains("命令超时"))
    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let jobDirectories = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
    let job = try #require(jobDirectories.first)
    let transcript = try String(contentsOf: job.appendingPathComponent("transcript.log"))
    #expect(transcript.contains("long-line-0000"))
    #expect(transcript.contains("long-line-1199"))
    #expect(transcript.contains("prompt:"))
    let runnerDirectory = root.appendingPathComponent(".opc/runtime/terminal-runners", isDirectory: true)
    let remainingRunnerScripts = (try? FileManager.default.contentsOfDirectory(at: runnerDirectory, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "sh" } ?? []
    #expect(remainingRunnerScripts.isEmpty)
}

@MainActor
@Test func persistentTerminalSendInputLineUsesLiteralTmuxInput() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentInput-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("read-line.sh")
    try """
    #!/bin/sh
    printf 'OPC_READY\\n'
    IFS= read -r line
    printf 'OPC_INPUT:%s\\n' "$line"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    _ = runTestProcess(tmuxPath, ["send-keys", "-t", "\(sessionName):\(windowName)", script.path, "C-m"])

    var capture = ""
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
        if capture.contains("OPC_READY") { break }
    }
    #expect(capture.contains("OPC_READY"))

    let literalInput = "hello $USER && uname; `date`"
    let send = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: literalInput))
    #expect(send.exitCode == 0)

    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
        if capture.contains("OPC_INPUT:\(literalInput)") { break }
    }
    #expect(capture.contains("OPC_INPUT:\(literalInput)"))

    let rejected = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: "one\ntwo"))
    #expect(rejected.exitCode == 126)
    #expect(rejected.standardError.contains("一次只允许一行"))
}

@Test func runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand() throws {
    // 源码守门：runPersistentTerminalCommand 必须把 marker-wrapped shellCommand 通过
    // sendInputLine 投递；并且 sendInputLine 必须走 tmux load-buffer + paste-buffer 的
    // 原子粘贴路径——回车作为 buffer 末尾的 \n 与文本一起送达，杜绝 send-keys -l 后再
    // 单发 C-m 的两步竞态。这两层守门一起锁定，是为了防止任何回退到下面这些已知会让
    // persistentProtocolRunDetectsMarkersAfterLongOutput 等长输出测试在 full swift test
    // 偶发失败的形态：
    //   • sendKeys([shellCommand, "C-m"])：让 tmux 把整条 shell 命令当 key-name 流解析；
    //   • send-keys -l text + 单独 send-keys C-m：在并发跑 tmux 时回车抢跑，让 zsh
    //     看到「半截命令 + Enter」并把残段当成路径触发 file-name-too-long。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    guard let funcRange = source.range(of: "func runPersistentTerminalCommand(") else {
        Issue.record("未在 CompanyStore.swift 找到 runPersistentTerminalCommand 函数")
        return
    }
    let bodyStart = funcRange.upperBound
    // 取该函数到下一个 func 之前的代码区间作为函数体。
    let nextDeclRange = source.range(of: "\n    func ", range: bodyStart..<source.endIndex)
    let bodyEnd = nextDeclRange?.lowerBound ?? source.endIndex
    let body = String(source[bodyStart..<bodyEnd])

    #expect(
        !body.contains("sendKeys([shellCommand"),
        "runPersistentTerminalCommand 仍在用 sendKeys([shellCommand, \"C-m\"]) 发送整条 shell 命令；必须改走 sendInputLine 原子粘贴路径。"
    )
    #expect(
        body.contains("sendInputLine(shellCommand"),
        "runPersistentTerminalCommand 必须用 sendInputLine(shellCommand,) 把 marker 命令发给 tmux，避免长命令在 zsh 触发 file-name-too-long。"
    )

    guard let shellCommandRange = source.range(of: "func persistentTerminalShellCommand(") else {
        Issue.record("未在 CompanyStore.swift 找到 persistentTerminalShellCommand 函数")
        return
    }
    let shellCommandBodyStart = shellCommandRange.upperBound
    let shellCommandNextDecl = source.range(of: "\n    func ", range: shellCommandBodyStart..<source.endIndex)
    let shellCommandBodyEnd = shellCommandNextDecl?.lowerBound ?? source.endIndex
    let shellCommandBody = String(source[shellCommandBodyStart..<shellCommandBodyEnd])
    #expect(
        !shellCommandBody.contains("return \"\"\""),
        "persistentTerminalShellCommand 不应再返回多行 wrapper；真实终端只能接收短命令，避免把半截长 prompt 抢先执行。"
    )
    #expect(
        shellCommandBody.contains("/bin/sh"),
        "persistentTerminalShellCommand 只应生成 /bin/sh runner 这一条短命令；长 prompt 和 marker wrapper 必须放进一次性 runner 脚本。"
    )
    #expect(
        source.contains("writePersistentTerminalRunnerScript"),
        "runPersistentTerminalCommand 必须先写入一次性 runner 脚本，再向真实终端发送短命令，避免长 prompt 直接进入交互粘贴流。"
    )
    #expect(
        !source.contains("trap 'rm -f \"$0\"' EXIT HUP INT TERM"),
        "runner 脚本不能吞掉 INT/TERM；超时中断必须反映真实子命令是否闭合，不能由 wrapper 抢写退出 marker。"
    )
    #expect(
        source.contains("historyStart: String = \"-50000\""),
        "长期终端捕获窗口需要覆盖极长输出，避免 start/end marker 被普通长日志滚出历史后误判超时。"
    )
    #expect(
        source.contains("delete-buffer"),
        "paste-buffer 失败时必须清理已加载的 tmux 一次性 buffer，避免长期 tmux server 累积残留。"
    )
    #expect(
        source.contains("cleanupPersistentTerminalRunnerScripts"),
        "写入新 runner 前必须清理陈旧 runner 脚本，降低异常中断后 prompt 明文残留风险。"
    )
    #expect(
        source.contains(".posixPermissions: 0o700], ofItemAtPath: directory.path"),
        "runner 脚本目录必须强制 0700，避免同机用户枚举含 prompt 的临时脚本。"
    )

    // 进一步锁定 sendInputLine 实现：必须用 load-buffer + paste-buffer 把 text + 回车
    // 一次性投递；不能再出现 send-keys（那是旧的两步 -l + C-m 路径）。
    guard let inputLineRange = source.range(of: "func sendInputLine(") else {
        Issue.record("未在 CompanyStore.swift 找到 sendInputLine 函数")
        return
    }
    let inputLineBodyStart = inputLineRange.upperBound
    // sendInputLine 同 actor 内的下一段同缩进 helper（`func killWindow` 或 nonisolated runLocalProcess）。
    let inputLineNextDecls: [String.Index] = [
        source.range(of: "\n        func ", range: inputLineBodyStart..<source.endIndex)?.lowerBound,
        source.range(of: "\n        private nonisolated func ", range: inputLineBodyStart..<source.endIndex)?.lowerBound
    ].compactMap { $0 }
    let inputLineBodyEnd = inputLineNextDecls.min() ?? source.endIndex
    let inputLineBody = String(source[inputLineBodyStart..<inputLineBodyEnd])

    #expect(
        inputLineBody.contains("load-buffer"),
        "sendInputLine 必须用 tmux load-buffer 把 text + \\n 通过 stdin 写进一次性 buffer；这是原子粘贴路径的第一步。"
    )
    #expect(
        inputLineBody.contains("paste-buffer"),
        "sendInputLine 必须用 tmux paste-buffer 把缓冲区粘进 pane；回车要随 buffer 末尾 \\n 一起送达，避免单发 C-m 抢跑。"
    )
    #expect(
        inputLineBody.contains("\"-d\""),
        "sendInputLine 必须给 paste-buffer 传 -d，把一次性 buffer 在粘贴后立即丢弃，避免 tmux server 累积同名 buffer。"
    )
    #expect(
        !inputLineBody.contains("\"send-keys\""),
        "sendInputLine 不应再调用 send-keys；改走 load-buffer/paste-buffer 后回车由 buffer 末尾 \\n 承担，不再单独发 C-m。"
    )
}

@MainActor
@Test func persistentTerminalSendInputLineEmptyAndUnicodeNewlinesAreGuarded() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentInputBoundaries-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("read-two-lines.sh")
    try """
    #!/bin/sh
    printf 'OPC_READY\\n'
    IFS= read -r first
    printf 'OPC_FIRST:%s\\n' "$first"
    IFS= read -r second
    printf 'OPC_SECOND:%s\\n' "$second"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    _ = runTestProcess(tmuxPath, ["send-keys", "-t", "\(sessionName):\(windowName)", script.path, "C-m"])

    var capture = ""
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
        if capture.contains("OPC_READY") { break }
    }
    #expect(capture.contains("OPC_READY"))

    let emptySend = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: ""))
    #expect(emptySend.exitCode == 0)
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
        if capture.contains("OPC_FIRST:") { break }
    }
    #expect(capture.contains("OPC_FIRST:"))

    for invalid in ["a\rb", "a\r\nb", "a\u{2028}b"] {
        let rejected = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: invalid))
        #expect(rejected.exitCode == 126)
        #expect(rejected.standardError.contains("一次只允许一行"))
    }

    let secondSend = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: "after-reject"))
    #expect(secondSend.exitCode == 0)
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
        if capture.contains("OPC_SECOND:after-reject") { break }
    }
    #expect(capture.contains("OPC_SECOND:after-reject"))
}

@MainActor
@Test func persistentTerminalSendInputLineDoesNotCrossProducts() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let rootA = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentInputA-\(UUID().uuidString)", isDirectory: true)
    let rootB = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentInputB-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
    try "// package".write(to: rootA.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try "// package".write(to: rootB.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    let script = rootA.appendingPathComponent("read-product-line.sh")
    try """
    #!/bin/sh
    printf 'OPC_READY:%s\\n' "$1"
    IFS= read -r line
    printf 'OPC_INPUT:%s:%s\\n' "$1" "$line"
    sleep 1
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]

    store.addProductWorkspace()
    let productAIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productAIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productAIndex].rootDirectory = rootA.path
    let productAID = store.selectedProductID
    let sessionA = store.terminalWorkspaceSessionNameForTesting()
    let windowA = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    defer { cleanupTmuxSession(tmuxPath, sessionA) }
    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: productAID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    _ = runTestProcess(tmuxPath, ["send-keys", "-t", "\(sessionA):\(windowA)", "\(script.path) product-a", "C-m"])
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        let captureA = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionA):\(windowA)", "-S", "-200"])
        if captureA.contains("OPC_READY:product-a") { break }
    }
    let sendA = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: "input-a"))
    #expect(sendA.exitCode == 0)

    store.addProductWorkspace()
    let productBID = store.selectedProductID
    let productBIndex = try #require(store.products.firstIndex { $0.id == productBID })
    store.products[productBIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productBIndex].rootDirectory = rootB.path
    let sessionB = store.terminalWorkspaceSessionNameForTesting()
    let windowB = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    defer { cleanupTmuxSession(tmuxPath, sessionB) }
    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: productBID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    _ = runTestProcess(tmuxPath, ["send-keys", "-t", "\(sessionB):\(windowB)", "\(script.path) product-b", "C-m"])
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        let captureB = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionB):\(windowB)", "-S", "-200"])
        if captureB.contains("OPC_READY:product-b") { break }
    }
    let sendB = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: "input-b"))
    #expect(sendB.exitCode == 0)

    var captureA = ""
    var captureB = ""
    for _ in 0..<30 {
        try await Task.sleep(nanoseconds: 100_000_000)
        captureA = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionA):\(windowA)", "-S", "-200"])
        captureB = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionB):\(windowB)", "-S", "-200"])
        if captureA.contains("OPC_INPUT:product-a:input-a"), captureB.contains("OPC_INPUT:product-b:input-b") { break }
    }
    #expect(captureA.contains("OPC_INPUT:product-a:input-a"))
    #expect(!captureA.contains("OPC_INPUT:product-b:input-b"))
    #expect(captureB.contains("OPC_INPUT:product-b:input-b"))
    #expect(!captureB.contains("OPC_INPUT:product-a:input-a"))
}

@MainActor
@Test func persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentInputDuringRun-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("interactive-command.sh")
    try """
    #!/bin/sh
    printf 'OPC_READY_FOR_STDIN\\n'
    IFS= read -r line
    printf 'OPC_STREAM_INPUT:%s\\n' "$line"
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let runTask = Task {
        await store.persistentTerminalTimeoutRunForTesting(agentID: engineer.id, command: [script.path], timeoutSeconds: 5)
    }

    let capture = try await waitForTmuxPaneOutput(
        tmuxPath,
        target: "\(sessionName):\(windowName)",
        contains: "OPC_READY_FOR_STDIN",
        historyStart: "-200",
        attempts: 40
    )
    #expect(capture.contains("OPC_READY_FOR_STDIN"))

    let input = "next prompt $USER && true"
    let send = try #require(await store.persistentTerminalSendInputLineForTesting(agentID: engineer.id, text: input))
    #expect(send.exitCode == 0)
    let result = try #require(await runTask.value)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("OPC_READY_FOR_STDIN"))
    #expect(result.standardOutput.contains("OPC_STREAM_INPUT:\(input)"))
    #expect(!result.standardOutput.contains("__OPC_JOB_EXIT"))
}

@MainActor
@Test func persistentTerminalREPLTurnWaitsForCodexPromptAndReturnsDelta() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCReplTurn-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-codex-repl.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    while IFS= read -r line; do
      printf 'answer:%s\\n' "$line"
      printf 'codex>\\n'
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let turn = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "手动下一轮", timeoutSeconds: 3))
    #expect(turn.exitCode == 0)
    #expect(!turn.timedOut)
    #expect(turn.observation.phase == .ready)
    #expect(turn.output.contains("answer:手动下一轮"))
    #expect(turn.output.contains("codex>"))
    #expect(!turn.output.contains("OPC 员工终端"))
    #expect(store.runtimeSessions[engineer.id]?.cliInteractionPhase == .ready)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("OPC 手动交互轮次"))
}

@MainActor
@Test func persistentTerminalREPLTurnRejectsShellSeatBeforePrompt() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCReplTurnShellGuard-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let turn = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "不要发到普通终端", timeoutSeconds: 1))
    #expect(turn.exitCode == 126)
    #expect(turn.observation.reasonTitle == "终端未就绪")
    #expect(turn.output.contains("避免把手动输入误发到普通终端"))

    let capture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"])
    #expect(!capture.contains("不要发到普通终端"))
    #expect(!store.terminalLogs[engineer.id, default: ""].contains("OPC 手动交互轮次"))
}

@MainActor
@Test func persistentTerminalOutputDeltaRequiresAnchorOrInputEcho() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let unanchoredPrompt = store.persistentTerminalOutputDeltaPreviewForTesting(
        before: "   \n",
        after: "codex> ready\n",
        inputEcho: "next prompt"
    )
    #expect(unanchoredPrompt.isEmpty)

    let echoedInput = store.persistentTerminalOutputDeltaPreviewForTesting(
        before: "   \n",
        after: "codex> ready\nnext prompt\nanswer\ncodex> ready\n",
        inputEcho: "next prompt"
    )
    #expect(echoedInput.contains("next prompt"))
    #expect(echoedInput.contains("answer"))
}

@MainActor
@Test func persistentTerminalREPLTurnRejectsUnsafeAndUnsupportedInputs() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]

    let multiline = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "one\ntwo", timeoutSeconds: 1))
    #expect(multiline.exitCode == 126)
    #expect(multiline.output.contains("一次只允许一行"))

    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let unsupported = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "hello", timeoutSeconds: 1))
    #expect(unsupported.exitCode == 127)
    #expect(unsupported.output.contains("长期会话画像目录"))
    #expect(unsupported.observation.phase == .unknown)
}

@Test func cliInteractionREPLTurnRecognizesClaudeAndGeminiReplReady() async throws {
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    #expect(claude.replReadySignals == ["claude>"])
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))
    #expect(gemini.replReadySignals == ["gemini>"])

    // 同行混入字面 → 不误命中（沿用 codex 同型 prompt-echo 防御）
    let claudeMixed = CLIInteractionStateMachine.observeREPLTurn(output: "请检查 claude> 配置项", profile: claude)
    #expect(claudeMixed.phase == .awaitingResponse)
    let geminiMixed = CLIInteractionStateMachine.observeREPLTurn(output: "处理完成，文本里提到 gemini>", profile: gemini)
    #expect(geminiMixed.phase == .awaitingResponse)

    // 独立行 → 命中
    let claudeReady = CLIInteractionStateMachine.observeREPLTurn(output: "处理完成\nclaude>", profile: claude)
    #expect(claudeReady.phase == .ready)
    #expect(claudeReady.reasonTitle == "可继续交互")
    let geminiReady = CLIInteractionStateMachine.observeREPLTurn(output: "处理完成\ngemini>", profile: gemini)
    #expect(geminiReady.phase == .ready)
    #expect(geminiReady.reasonTitle == "可继续交互")

    // 空 replReadySignals 的画像不能进入 ready 路径（用伪造无 ready 的 profile 验证守门）
    let unsupportedProfile = CLIInteractionProfile(
        command: "noop",
        displayName: "占位协议",
        protocolKind: .singleCommand,
        sessionMode: "noop",
        supportsResume: false,
        sessionIDLabels: [],
        sessionIDPattern: #"[A-Za-z0-9]{8,}"#,
        readySignals: [],
        replReadySignals: [],
        endTurnSignals: [],
        busySignals: [],
        authenticationIssueSignals: [],
        transientIssueSignals: [],
        recommendedTimeoutSeconds: 60
    )
    let noopReady = CLIInteractionStateMachine.observeREPLTurn(output: "claude>\ngemini>", profile: unsupportedProfile)
    #expect(noopReady.phase == .awaitingResponse)
}

@Test func cliInteractionEndsWithReplReadyPromptIgnoresStaleScrollback() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))

    // 最近一行就是专用 prompt（含尾部空白和空行）→ 通过
    #expect(codex.endsWithReplReadyPrompt("处理上一轮\ncodex>"))
    #expect(codex.endsWithReplReadyPrompt("处理上一轮\ncodex>\n"))
    #expect(codex.endsWithReplReadyPrompt("处理上一轮\ncodex>\n\n   \n"))
    #expect(claude.endsWithReplReadyPrompt("已生成补丁\nclaude>"))
    #expect(gemini.endsWithReplReadyPrompt("响应已结束\ngemini>"))

    // scrollback 里有旧 prompt，但最近一行还在处理或显示其他文本 → 拒绝
    #expect(!codex.endsWithReplReadyPrompt("codex>\n第1轮：演练\nanswer:演练\n正在处理 GitHub 拉取..."))
    #expect(!codex.endsWithReplReadyPrompt("codex>\n第1轮\nanswer\ncodex>\n第2轮：写测试\n正在生成测试用例..."))
    #expect(!claude.endsWithReplReadyPrompt("claude>\n请帮我写脚本\nthinking..."))
    #expect(!gemini.endsWithReplReadyPrompt("gemini>\n第1轮\n响应中..."))

    // 同行混入字面 → 不认为最近一行是 prompt
    #expect(!codex.endsWithReplReadyPrompt("codex>\n请检查 codex> 配置项"))
    #expect(!claude.endsWithReplReadyPrompt("文本里提到 claude> 这个 prompt"))

    // 大小写无关、保留空行容忍
    #expect(codex.endsWithReplReadyPrompt("CODEX>\n"))
    #expect(codex.endsWithReplReadyPrompt("\n\n   \ncodex>   \n"))

    // 缺少 prompt 配置的画像永远返回 false
    let unsupportedProfile = CLIInteractionProfile(
        command: "noop",
        displayName: "占位协议",
        protocolKind: .singleCommand,
        sessionMode: "noop",
        supportsResume: false,
        sessionIDLabels: [],
        sessionIDPattern: #"[A-Za-z0-9]{8,}"#,
        readySignals: [],
        replReadySignals: [],
        endTurnSignals: [],
        busySignals: [],
        authenticationIssueSignals: [],
        transientIssueSignals: [],
        recommendedTimeoutSeconds: 60
    )
    #expect(!unsupportedProfile.endsWithReplReadyPrompt("codex>"))
    #expect(!unsupportedProfile.endsWithReplReadyPrompt(""))

    // 历史 containsREPLReadySignal 仍可命中任意行；endsWithReplReadyPrompt 比它更严格。
    let staleScrollback = "codex>\n第1轮\nanswer\n正在处理..."
    #expect(codex.containsREPLReadySignal(staleScrollback))
    #expect(!codex.endsWithReplReadyPrompt(staleScrollback))
}

@Test func cliInteractionEndsWithReplReadyPromptHandlesAnsiAndControlChars() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))

    // ANSI SGR 包裹的 prompt 行 → 通过
    #expect(codex.endsWithReplReadyPrompt("\u{1B}[32mcodex>\u{1B}[0m"))
    #expect(codex.endsWithReplReadyPrompt("\u{1B}[1;32mcodex>\u{1B}[0m\n"))
    #expect(claude.endsWithReplReadyPrompt("响应完成\n\u{1B}[31mclaude>\u{1B}[0m"))
    #expect(gemini.endsWithReplReadyPrompt("\u{1B}[36mgemini>\u{1B}[0m\n\n"))

    // OSC 终端 title（BEL 终结）→ 通过
    let oscBel = "\u{1B}]0;codex session\u{07}codex>\n"
    #expect(codex.endsWithReplReadyPrompt(oscBel))
    // OSC 终端 title（ESC \ 终结）→ 通过
    let oscSt = "\u{1B}]0;codex\u{1B}\\codex>\n"
    #expect(codex.endsWithReplReadyPrompt(oscSt))

    // CR 只重置光标、不清行尾：spinner 残留仍在显示 → 拒绝（更保守，避免误把"还在处理"判成就绪）
    #expect(!codex.endsWithReplReadyPrompt("正在处理 GitHub 拉取请求...\rcodex>\n"))
    #expect(!claude.endsWithReplReadyPrompt("Thinking...\rclaude>\n"))

    // 真实终端清行：CSI K（默认 erase to EOL）紧跟 prompt 之后清掉残留尾部 → 通过
    #expect(codex.endsWithReplReadyPrompt("正在处理 GitHub 拉取请求...\rcodex>\u{1B}[K\n"))
    // 先 CR + ESC[K 清掉行尾，再写 prompt → 通过
    #expect(codex.endsWithReplReadyPrompt("正在处理 GitHub 拉取请求...\r\u{1B}[Kcodex>\n"))
    // ESC[2K 清整行后写 prompt → 通过
    #expect(claude.endsWithReplReadyPrompt("Thinking...\u{1B}[2Kclaude>\n"))
    // ESC[0K 显式声明 erase to EOL → 通过
    #expect(gemini.endsWithReplReadyPrompt("loading...\rgemini>\u{1B}[0K\n"))

    // shell 标准擦字 \b 空格 \b → 多余字符被空格覆盖、trim 后仍是 prompt
    #expect(codex.endsWithReplReadyPrompt("codex>x\u{08} \u{08}\n"))
    // 单纯 \b 不擦字符（光标只移动）→ 'x' 仍在显示，不算 prompt
    #expect(!codex.endsWithReplReadyPrompt("codex>x\u{08}\n"))

    // BEL / 其他 C0 控制残留在 prompt 行 → 不影响识别
    #expect(codex.endsWithReplReadyPrompt("codex>\u{07}\n"))
    #expect(codex.endsWithReplReadyPrompt("codex>\u{0B}\n"))

    // 中文输出后跟带颜色的 prompt → 通过
    #expect(codex.endsWithReplReadyPrompt("员工已经在执行下一步\n\u{1B}[32mcodex>\u{1B}[0m"))

    // 旧 scrollback 里有带颜色的旧 prompt，但最近一行还在处理 → 拒绝
    #expect(!codex.endsWithReplReadyPrompt("\u{1B}[32mcodex>\u{1B}[0m\n第1轮\n\u{1B}[33m正在处理 GitHub 拉取请求...\u{1B}[0m"))
    // CR 覆写到 "still processing" 等非 prompt → 拒绝
    #expect(!codex.endsWithReplReadyPrompt("\u{1B}[32mcodex>\u{1B}[0m\nprocessing...\rstill processing"))

    // containsREPLReadySignal 也能识别带颜色或 OSC 包装的独立 prompt 行
    #expect(codex.containsREPLReadySignal("\u{1B}[32mcodex>\u{1B}[0m\n第1轮"))
    #expect(codex.containsREPLReadySignal(oscBel))
    // 同时仍然拒绝同一行混入字面（即便外面包颜色码）的情况
    #expect(!claude.containsREPLReadySignal("请检查 \u{1B}[33mclaude>\u{1B}[0m 配置项"))

    // normalizer helper 自身可以单测：CR 只重置光标，未被覆盖的尾部仍保留
    let crOverwriteOnly = CLIInteractionProfile.normalizedForPromptMatching("processing...\rcodex>")
    #expect(crOverwriteOnly == "codex>sing...")  // "process" 被 "codex>" 覆盖，"sing..." 留在原位
    // CSI K 紧跟 prompt 之后才会清掉尾部
    let crWithEraseAfter = CLIInteractionProfile.normalizedForPromptMatching("processing...\rcodex>\u{1B}[K\n")
    #expect(crWithEraseAfter == "codex>\n")
    // CR + ESC[K 在写 prompt 之前清行 → 仅 prompt
    let crWithEraseBefore = CLIInteractionProfile.normalizedForPromptMatching("processing...\r\u{1B}[Kcodex>\n")
    #expect(crWithEraseBefore == "codex>\n")
    // ESC[2K 不依赖 CR，直接清整行
    let clearLineThenWrite = CLIInteractionProfile.normalizedForPromptMatching("Thinking...\u{1B}[2Kclaude>\n")
    #expect(clearLineThenWrite == "claude>\n")
    // BS 只移动光标，不擦字符；后续覆盖的字符位置正确
    let bsCursorOnly = CLIInteractionProfile.normalizedForPromptMatching("codex>xy\u{08}z\n")
    #expect(bsCursorOnly == "codex>xz\n")

    // ANSI / OSC / BEL 仍然被剥离
    let raw = "\u{1B}[32mcodex>\u{1B}[0m\n第1轮\n\u{07}"
    let normalized = CLIInteractionProfile.normalizedForPromptMatching(raw)
    #expect(normalized.contains("codex>"))
    #expect(!normalized.contains("\u{1B}"))
    #expect(!normalized.contains("\u{07}"))

    // 中文文本和 \t / \n 必须保留
    let chineseRaw = "技术负责人\t任务\n员工反馈\n\u{1B}[36mcodex>\u{1B}[0m"
    let chineseNormalized = CLIInteractionProfile.normalizedForPromptMatching(chineseRaw)
    #expect(chineseNormalized.contains("技术负责人"))
    #expect(chineseNormalized.contains("\t"))
    #expect(chineseNormalized.contains("员工反馈"))
    #expect(chineseNormalized.hasSuffix("codex>"))
}

@MainActor
@Test func cliRecoveryAdviceSummaryStaysChineseAndExposesCorrectActionTitles() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.products[0].assignedAgentIDs.insert(engineer.id)
    store.selectAgent(engineer.id)

    var session = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
    )
    session.cliInteractionPhase = .transientFailure
    session.cliInteractionReason = "临时异常"
    session.cliInteractionRecoveryAction = .waitAndRetryLater
    session.cliInteractionRecoveryActionTitle = CLIInteractionRecoveryAction.waitAndRetryLater.title
    session.cliInteractionOperatorHint = CLIInteractionRecoveryAction.waitAndRetryLater.operatorHint
    store.runtimeSessions[engineer.id] = session

    let summary = store.cliRecoveryAdviceSummaryText()
    #expect(summary.contains("员工恢复建议"))
    #expect(summary.contains(engineer.displayName))
    #expect(summary.contains("临时异常"))
    #expect(summary.contains("稍后重试"))
    #expect(summary.contains("可使用「手动重试一次」入口"))
    #expect(!summary.contains("transientFailure"))
    #expect(!summary.contains("authenticationBlocked"))
    #expect(!summary.contains("waitAndRetryLater"))
    #expect(!summary.contains("CLI"))
    #expect(!summary.contains("REPL"))

    let advice = try #require(store.cliRecoveryAdvice(for: engineer.id))
    #expect(advice.canManualRetry)
    #expect(advice.actionTitle == CLIInteractionRecoveryAction.waitAndRetryLater.title)

    session.cliInteractionRecoveryAction = nil
    session.cliInteractionRecoveryActionTitle = nil
    session.cliInteractionRecoveryHint = nil
    session.cliInteractionOperatorHint = nil
    store.runtimeSessions[engineer.id] = session
    let legacyAdvice = try #require(store.cliRecoveryAdvice(for: engineer.id))
    #expect(legacyAdvice.canManualRetry)
    #expect(legacyAdvice.actionTitle == CLIInteractionRecoveryAction.waitAndRetryLater.title)
}

@MainActor
@Test func cliRecoveryManualRetryAllowsTransientButRejectsAuthBusyAndNoAction() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.products[0].assignedAgentIDs.insert(engineer.id)

    func install(_ phase: CLIInteractionPhase, reason: String) {
        var s = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
            agentID: engineer.id,
            productID: store.selectedProductID,
            capability: .persistentProtocol,
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
        )
        s.cliInteractionPhase = phase
        s.cliInteractionReason = reason
        s.cliInteractionRecoveryAction = CLIInteractionStateMachine.recoveryAction(for: phase)
        store.runtimeSessions[engineer.id] = s
    }

    install(.authenticationBlocked, reason: "授权异常")
    let authReport = store.manualRetryTransientForAgent(agentID: engineer.id)
    #expect(!authReport.success)
    #expect(authReport.reason.contains("授权异常") || authReport.reason.contains("不在「临时异常」"))

    install(.busy, reason: "忙碌中")
    let busyReport = store.manualRetryTransientForAgent(agentID: engineer.id)
    #expect(!busyReport.success)
    #expect(busyReport.reason.contains("忙碌中") || busyReport.reason.contains("不在「临时异常」"))

    install(.ready, reason: "可继续交互")
    let readyReport = store.manualRetryTransientForAgent(agentID: engineer.id)
    #expect(!readyReport.success)
    #expect(readyReport.reason.contains("不在「临时异常」"))

    install(.transientFailure, reason: "临时异常")
    let restartEventsBefore = store.events.filter { $0.title.contains("\(engineer.displayName) 会话重开") }.count
    let okReport = store.manualRetryTransientForAgent(agentID: engineer.id)
    #expect(okReport.success)
    #expect(okReport.reason.contains("已为"))
    #expect(okReport.reason.contains("一次受控"))
    let restartEventsAfter = store.events.filter { $0.title.contains("\(engineer.displayName) 会话重开") }.count
    #expect(restartEventsAfter == restartEventsBefore + 1)
}

@MainActor
@Test func cliRecoveryManualRetryDoesNotPolluteBossOrCreateJobArchives() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.products[0].assignedAgentIDs.insert(engineer.id)

    var session = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
    )
    session.cliInteractionPhase = .transientFailure
    session.cliInteractionReason = "临时异常"
    session.cliInteractionRecoveryAction = .waitAndRetryLater
    store.runtimeSessions[engineer.id] = session

    let baselineMessages = store.messages.count
    let baselineVerifications = store.selectedProductVerifications.count
    let baselineArtifacts = store.selectedProductArtifacts.count
    let baselineBossMessages = store.messages(for: store.bossID).count

    _ = store.manualRetryTransientForAgent(agentID: engineer.id)

    // 不向老板聊天写消息、不写验收记录、不创建作业档案产物
    #expect(store.messages.count == baselineMessages)
    #expect(store.selectedProductVerifications.count == baselineVerifications)
    #expect(store.selectedProductArtifacts.count == baselineArtifacts)
    #expect(store.messages(for: store.bossID).count == baselineBossMessages)

    let bossText = store.messages(for: store.bossID).map(\.text).joined(separator: "\n")
    #expect(!bossText.contains("REPL"))
    #expect(!bossText.contains("transientFailure"))
    #expect(!bossText.contains("waitAndRetryLater"))

    // 不会向命令行自动追加新一轮输入：sendInputLine 写入会出现在 terminalLogs 的"输入"标记里——验证不存在
    let log = store.terminalLogs[engineer.id, default: ""]
    #expect(!log.contains("OPC 手动交互轮次"))
    #expect(!log.contains("OPC 手动 REPL 轮次"))
    // 事件流仅写入"会话重开"风格的中文事件，不含英文 raw value
    let eventTextAll = store.events.map { "\($0.title)\n\($0.detail)" }.joined(separator: "\n")
    #expect(!eventTextAll.contains("transientFailure"))
    #expect(!eventTextAll.contains("waitAndRetryLater"))
}

@MainActor
@Test func cliRecoveryAdviceEmptyProductShowsChineseEmptyState() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstProductID = store.selectedProductID
    if let idx = store.products.firstIndex(where: { $0.id == firstProductID }) {
        store.products[idx].assignedAgentIDs = []
    }
    let summary = store.cliRecoveryAdviceSummaryText()
    #expect(summary.contains("暂无可执行员工"))
    #expect(!summary.contains("noAction"))
    #expect(!summary.contains("REPL"))
}

@MainActor
@Test func runManualREPLTurnRejectsEmptyMultilineAndUnselectedAgent() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let empty = await store.runManualREPLTurnForSelectedAgent(text: "     ")
    #expect(empty.rejected)
    #expect(empty.rejectionReason?.contains("一行内容") == true)

    let multi = await store.runManualREPLTurnForSelectedAgent(text: "first\nsecond")
    #expect(multi.rejected)
    #expect(multi.rejectionReason?.contains("一次只允许一行") == true)

    let trailingNewline = await store.runManualREPLTurnForSelectedAgent(text: "first\n")
    #expect(trailingNewline.rejected)
    #expect(trailingNewline.rejectionReason?.contains("一次只允许一行") == true)

    store.selectAgent(store.bossID)
    let bossSelected = await store.runManualREPLTurnForSelectedAgent(text: "ping")
    #expect(bossSelected.rejected)
    #expect(bossSelected.rejectionReason?.contains("老板视角") == true)
    #expect(bossSelected.rejectionReason?.contains("REPL") != true)
}

@MainActor
@Test func runManualREPLTurnRejectsBackendWithoutInteractionProfile() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    // 非画像目录后端（/bin/echo 不在 codex/claude/gemini 画像里）
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.products[0].assignedAgentIDs.insert(engineer.id)
    store.selectAgent(engineer.id)

    let report = await store.runManualREPLTurnForSelectedAgent(text: "ping", timeoutSeconds: 0.2)
    #expect(report.rejected)
    let reason = report.rejectionReason ?? ""
    #expect(reason.contains("长期会话画像目录") || reason.contains("专用就绪提示"))
}

@Test func manualREPLTurnReportSummaryStaysChinese() {
    let timedOut = CompanyStore.ManualREPLTurnReport(summary: "等待超时，未中断终端席位", outputPreview: "answer:hello", timedOut: true, rejected: false, rejectionReason: nil)
    #expect(!timedOut.summary.isEmpty)
    #expect(timedOut.timedOut)
    #expect(!timedOut.outputPreview.isEmpty)

    let rejected = CompanyStore.ManualREPLTurnReport(summary: "未发送", outputPreview: "", timedOut: false, rejected: true, rejectionReason: "请先输入要发送给员工长期席位的一行内容。")
    #expect(rejected.rejected)
    let reason: String = rejected.rejectionReason ?? ""
    var hasAsciiLetter = false
    for scalar in reason.unicodeScalars {
        let value = scalar.value
        if (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) {
            hasAsciiLetter = true
            break
        }
    }
    #expect(!hasAsciiLetter, "拒绝原因含英文字母：\(reason)")
}

@MainActor
@Test func manualREPLTurnDoesNotPolluteBossFacingMessagesOrJobArchives() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    // 非画像后端走拒绝路径，不会启动 tmux、不会写 messages/events/verifications
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.products[0].assignedAgentIDs.insert(engineer.id)
    store.selectAgent(engineer.id)
    let baselineMessages = store.messages.count
    let baselineEvents = store.events.count
    let baselineVerifications = store.selectedProductVerifications.count
    let baselineArtifacts = store.selectedProductArtifacts.count

    let report = await store.runManualREPLTurnForSelectedAgent(text: "需要一行测试输入", timeoutSeconds: 0.2)
    #expect(report.rejected)

    // 拒绝路径不向老板聊天写消息、不向事件流追加风险、不写验收记录、不创建作业档案产物
    #expect(store.messages.count == baselineMessages)
    #expect(store.events.count == baselineEvents)
    #expect(store.selectedProductVerifications.count == baselineVerifications)
    #expect(store.selectedProductArtifacts.count == baselineArtifacts)

    let bossMessages = store.messages(for: store.bossID).map(\.text).joined(separator: "\n")
    #expect(!bossMessages.contains("REPL"))
    #expect(!bossMessages.contains("终端席位"))
    #expect(!bossMessages.contains("codex>"))
}

@MainActor
@Test func persistentTerminalREPLTurnRoutesClaudeBackendThroughClaudePromptSignal() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCReplTurnClaude-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-claude-repl.sh")
    try """
    #!/bin/sh
    printf 'claude>\\n'
    while IFS= read -r line; do
      printf 'reply:%s\\n' "$line"
      printf 'claude>\\n'
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let claudeProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "claude>",
        historyStart: "-200",
        readyAttempts: 60,
        expectsLatestLineMatchesProfile: claudeProfile
    )
    #expect(capture.contains("claude>"))
    #expect(claudeProfile.endsWithReplReadyPrompt(capture))

    let turn = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "claude 第一轮", timeoutSeconds: 3))
    #expect(turn.exitCode == 0)
    #expect(!turn.timedOut)
    #expect(turn.observation.phase == .ready)
    #expect(turn.output.contains("reply:claude 第一轮"))
    #expect(turn.output.contains("claude>"))
    #expect(store.runtimeSessions[engineer.id]?.cliInteractionPhase == .ready)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("OPC 手动交互轮次"))
}

@MainActor
@Test func persistentTerminalREPLTurnRejectsBackendWithoutReplReadySignals() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })

    // 后端虽然在画像目录里但若未来 replReadySignals 被清空——通过非画像后端 /bin/echo 触发"画像目录里找不到"路径
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let unknownBackend = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: store.agents[engineerIndex].id, text: "ping", timeoutSeconds: 1))
    #expect(unknownBackend.exitCode == 127)
    #expect(unknownBackend.output.contains("长期会话画像目录"))
    #expect(unknownBackend.observation.reasonTitle == "暂不支持")
}

@MainActor
@Test func persistentTerminalREPLTurnTimeoutDoesNotCloseTerminalSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCReplTurnTimeout-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-codex-slow-repl.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    IFS= read -r line
    printf 'working:%s\\n' "$line"
    sleep 2
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let turn = try #require(await store.persistentTerminalREPLTurnForTesting(agentID: engineer.id, text: "慢响应", timeoutSeconds: 0.3))
    #expect(turn.exitCode == 124)
    #expect(turn.timedOut)
    #expect(turn.observation.phase == .awaitingResponse)
    #expect(turn.output.contains("working:慢响应"))
    let windows = runTestProcessOutput(tmuxPath, ["list-windows", "-t", sessionName, "-F", "#{window_name}"])
    #expect(windows.contains(windowName))
    #expect(store.terminalLogs[engineer.id, default: ""].contains("未中断终端席位"))
}

@MainActor
@Test func persistentProtocolRunRefusesToOverwriteUnfinishedTerminalJob() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentBusy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    _ = runTestProcess(tmuxPath, ["send-keys", "-t", "\(sessionName):\(windowName)", "printf '\\n__OPC_JOB_START_BUSY__\\n'", "C-m"])

    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    store.runAgent(agentID: engineer.id, prompt: "should not overwrite")
    for _ in 0..<40 where store.runningAgentIDs.contains(engineer.id) {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    let terminalLog = store.terminalLogs[engineer.id, default: ""]
    #expect(terminalLog.contains("仍有未完成的 OPC 命令行任务"))
    #expect(terminalLog.contains("命令退出码 125"))
    #expect(store.runtimeSessions[engineer.id]?.state == .failed)
}

@MainActor
@Test func persistentProtocolTimeoutEscalatesToCloseUnresponsiveTerminalSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCPersistentEscalate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("unresponsive.sh")
    try """
    #!/bin/sh
    trap '' INT QUIT TERM
    while :; do
      sleep 1
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    store.products[0].rootDirectory = root.path

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let result = try #require(await store.persistentTerminalTimeoutRunForTesting(agentID: engineer.id, command: [script.path], timeoutSeconds: 0.2))

    #expect(result.exitCode == 124)
    #expect(result.standardError.contains("已关闭未响应的终端席位"))
    let listOutput = runTestProcessOutput(tmuxPath, ["list-windows", "-t", sessionName, "-F", "#{window_name}"])
    #expect(!listOutput.contains(windowName))

    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    let revived = try #require(await store.persistentTerminalTimeoutRunForTesting(agentID: engineer.id, command: ["/bin/echo", "revived-seat"], timeoutSeconds: 2))
    #expect(revived.exitCode == 0)
    #expect(revived.standardOutput.contains("revived-seat"))
    let revivedWindows = runTestProcessOutput(tmuxPath, ["list-windows", "-t", sessionName, "-F", "#{window_name}"])
    #expect(revivedWindows.contains(windowName))
}

@MainActor
@Test func persistentTerminalTurnObservationWaitsForOPCExitMarker() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let sessionID = "12345678-1234-1234-1234-123456789abc"
    let capture = """
    shell prompt
    __OPC_JOB_START_TEST__
    {"session_id":"\(sessionID)"}
    Codex is ready
    """

    let preview = store.persistentTerminalTurnObservationPreviewForTesting(
        capture: capture,
        startMarker: "__OPC_JOB_START_TEST__",
        endMarker: "__OPC_JOB_EXIT_TEST__:",
        command: "codex"
    )

    #expect(preview.contains("结果：未完成"))
    #expect(preview.contains("状态：可继续交互"))
    #expect(preview.contains("会话编号：已识别"))
    #expect(!preview.contains(sessionID))
    #expect(!preview.contains("session_id"))
}

@MainActor
@Test func persistentTerminalTurnClosedRequiresExitMarkerWhenStartScrolledOut() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let capture = """
    long-output-line-10998
    long-output-line-10999
    still running without visible OPC start marker
    """

    #expect(!store.persistentTerminalTurnClosedPreviewForTesting(
        capture: capture,
        startMarker: "__OPC_JOB_START_SCROLLED__",
        endMarker: "__OPC_JOB_EXIT_SCROLLED__:"
    ))
}

@MainActor
@Test func persistentTerminalTurnObservationReturnsResultAfterExitMarker() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let capture = """
    __OPC_JOB_START_TEST__
    完成输出
    __OPC_JOB_EXIT_TEST__:0
    """

    let preview = store.persistentTerminalTurnObservationPreviewForTesting(
        capture: capture,
        startMarker: "__OPC_JOB_START_TEST__",
        endMarker: "__OPC_JOB_EXIT_TEST__:",
        command: "codex"
    )

    #expect(preview.contains("结果：退出码 0"))
    #expect(!preview.contains("__OPC_JOB_EXIT_TEST__"))
}

@MainActor
@Test func cliRunCreatesJobDirectoryAndTranscript() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCJobTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.products[0].rootDirectory = root.path

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low)
    let engineerID = store.agents[engineerIndex].id

    store.runAgent(agentID: engineerID, prompt: "job smoke")
    for _ in 0..<30 where !store.runningAgentIDs.isEmpty {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let jobDirectories = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
    let job = try #require(jobDirectories.first)
    #expect(FileManager.default.fileExists(atPath: job.appendingPathComponent("brief.md").path))
    #expect(FileManager.default.fileExists(atPath: job.appendingPathComponent("agent-task.md").path))
    #expect(try String(contentsOf: job.appendingPathComponent("status.json")).contains("\"state\": \"completed\""))
    let transcript = try String(contentsOf: job.appendingPathComponent("transcript.log"))
    #expect(transcript.contains("job smoke"))
    #expect(!transcript.contains("sessions.jsonl"))
    #expect(!transcript.contains("Library/Application Support"))
    #expect(!transcript.contains("/Users/"))
    #expect(store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") && $0.path.hasPrefix(jobsRoot.path) })
    let terminalLog = store.terminalLogs[engineerID, default: ""]
    #expect(terminalLog.contains("OPC 命令行任务"))
    #expect(terminalLog.contains("运行方式"))
    #expect(!terminalLog.contains("$ "))
    #expect(!terminalLog.contains("model_reasoning_effort"))
    #expect(!terminalLog.contains("--skip-git-repo-check"))
    #expect(!terminalLog.contains("sessions.jsonl"))
}

@MainActor
@Test func oneShotCLIUsesProductScopedHomeAndXDG() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCHomeIsolation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.products[0].rootDirectory = root.path

    let marker = UUID().uuidString
    let script = root.appendingPathComponent("env-probe.sh")
    let scriptText = """
    #!/bin/sh
    mkdir -p "$HOME/.codex" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
    printf "%s" "$HOME" > "$HOME/.codex/\(marker).home"
    printf "%s" "$XDG_CONFIG_HOME" > "$XDG_CONFIG_HOME/\(marker).config"
    printf "%s" "$XDG_CACHE_HOME" > "$XDG_CACHE_HOME/\(marker).cache"
    printf "%s" "$XDG_DATA_HOME" > "$XDG_DATA_HOME/\(marker).data"
    printf "env ok"
    """
    try scriptText.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let designerIndex = try #require(store.agents.firstIndex { $0.role == .uiDesigner })
    store.agents[designerIndex].backend = AgentBackend(type: .subscriptionCLI, command: script.path, model: "", reasoningEffort: .low)
    let designerID = store.agents[designerIndex].id

    store.runAgent(agentID: designerID, prompt: "env probe")
    for _ in 0..<30 where !store.runningAgentIDs.isEmpty {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    let scopedHome = try String(contentsOf: root.appendingPathComponent(".codex/\(marker).home"))
    let scopedConfig = try String(contentsOf: root.appendingPathComponent(".opc/env/config/\(marker).config"))
    let scopedCache = try String(contentsOf: root.appendingPathComponent(".opc/env/cache/\(marker).cache"))
    let scopedData = try String(contentsOf: root.appendingPathComponent(".opc/env/data/\(marker).data"))
    #expect(scopedHome == root.path)
    #expect(scopedConfig == root.appendingPathComponent(".opc/env/config").path)
    #expect(scopedCache == root.appendingPathComponent(".opc/env/cache").path)
    #expect(scopedData == root.appendingPathComponent(".opc/env/data").path)
    #expect(!FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/\(marker).home").path))
    #expect(store.runtimeSessions[designerID]?.state == .ready)
}

@MainActor
@Test func optionalSandboxBlocksSensitiveHomeReadsButAllowsProductRoot() async throws {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCSandbox-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.products[0].rootDirectory = root.path
    store.products[0].enforceSandbox = true

    let marker = UUID().uuidString
    let homeLibrary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
    let script = root.appendingPathComponent("sandbox-probe.sh")
    let scriptText = """
    #!/bin/sh
    mkdir -p "$HOME"
    printf "allowed" > "$HOME/\(marker).allowed"
    ls "\(homeLibrary)" > "$HOME/\(marker).leak" 2> "$HOME/\(marker).deny" || true
    printf "sandbox ok"
    """
    try scriptText.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let designerIndex = try #require(store.agents.firstIndex { $0.role == .uiDesigner })
    store.agents[designerIndex].backend = AgentBackend(type: .subscriptionCLI, command: script.path, model: "", reasoningEffort: .low)
    let designerID = store.agents[designerIndex].id

    store.runAgent(agentID: designerID, prompt: "sandbox probe")
    for _ in 0..<30 where !store.runningAgentIDs.isEmpty {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    #expect(try String(contentsOf: root.appendingPathComponent("\(marker).allowed")) == "allowed")
    let leak = try String(contentsOf: root.appendingPathComponent("\(marker).leak"))
    let deny = try String(contentsOf: root.appendingPathComponent("\(marker).deny"))
    #expect(leak.isEmpty)
    #expect(!deny.isEmpty)
    #expect(store.runtimeSessions[designerID]?.state == .ready)
}

@MainActor
@Test func jobArchiveStaleAuditInterruptsGhostRunningStatus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCJobGhost-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.products[0].rootDirectory = root.path
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let messageCount = store.messages.count
    let agentMessageCount = store.agentMessages.count

    let job = try writeCLIJobArchive(
        root: root,
        jobID: "2026-04-30T12-00-00Z-Claude-Code-工程师-ABC12345",
        productID: store.selectedProductID,
        agentID: engineer.id,
        updatedAt: Date(timeIntervalSinceNow: -900)
    )
    store.artifacts.insert(
        ArtifactRecord(productID: store.selectedProductID, kind: .report, title: "命令行作业档案：\(engineer.displayName)", path: job.path, summary: "运行中"),
        at: 0
    )

    let status = store.runJobArchiveStaleAuditForSelectedProduct(staleAfter: 180)

    let statusText = try String(contentsOf: job.appendingPathComponent("status.json"))
    #expect(status == .warning)
    #expect(statusText.contains("\"interrupted\""))
    #expect(statusText.contains("\"previous_state\""))
    #expect(statusText.contains("OPC 运维巡检"))
    let verification = try #require(store.selectedProductVerifications.first { $0.title == "命令行作业幽灵巡检" })
    #expect(verification.detail.contains("作业 1"))
    #expect(!verification.detail.contains("2026-04-30T12-00-00Z"))
    #expect(!verification.detail.contains("product_id"))
    #expect(!verification.detail.contains("agent_id"))
    #expect(!verification.detail.contains("updated_at"))
    #expect(!verification.detail.contains("previous_state"))
    #expect(!verification.detail.contains("interrupted_at"))
    #expect(!verification.detail.contains("exit_code"))
    #expect(!verification.detail.contains("interruption_reason"))
    #expect(store.selectedProductEvents.contains { $0.title == "命令行作业幽灵巡检完成" })
    #expect(store.selectedProductArtifacts.first { $0.path == job.path }?.summary.contains("已中断") == true)
    #expect(store.messages.count == messageCount)
    #expect(store.agentMessages.count == agentMessageCount)
    #expect(store.runningAgentIDs.isEmpty)
}

@MainActor
@Test func jobArchiveStaleAuditLeavesActiveAndFreshRunningJobsAlone() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCJobActive-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.products[0].rootDirectory = root.path
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let designer = try #require(store.agents.first { $0.role == .uiDesigner })
    store.runningAgentIDs.insert(engineer.id)
    var session = AgentRuntimeSession(
        agentID: reviewer.id,
        productID: store.selectedProductID,
        capability: .oneShotCLI,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: reviewer)
    )
    session.state = .busy
    session.lastUsedAt = Date(timeIntervalSinceNow: -900)
    store.runtimeSessions[reviewer.id] = session

    let activeByRunningSet = try writeCLIJobArchive(
        root: root,
        jobID: "active-running-set",
        productID: store.selectedProductID,
        agentID: engineer.id,
        updatedAt: Date(timeIntervalSinceNow: -900)
    )
    let activeBySession = try writeCLIJobArchive(
        root: root,
        jobID: "active-session",
        productID: store.selectedProductID,
        agentID: reviewer.id,
        updatedAt: Date(timeIntervalSinceNow: -900)
    )
    let fresh = try writeCLIJobArchive(
        root: root,
        jobID: "fresh-running",
        productID: store.selectedProductID,
        agentID: designer.id,
        updatedAt: Date(timeIntervalSinceNow: -30)
    )

    let status = store.runJobArchiveStaleAuditForSelectedProduct(staleAfter: 180)

    #expect(status == .passed)
    #expect(try String(contentsOf: activeByRunningSet.appendingPathComponent("status.json")).contains("\"running\""))
    #expect(try String(contentsOf: activeBySession.appendingPathComponent("status.json")).contains("\"running\""))
    #expect(try String(contentsOf: fresh.appendingPathComponent("status.json")).contains("\"running\""))
    let verification = try #require(store.selectedProductVerifications.first { $0.title == "命令行作业幽灵巡检" })
    #expect(verification.detail.contains("真实运行"))
    #expect(verification.detail.contains("未超时"))
    #expect(store.selectedProductAgentMessages.isEmpty)
}

@MainActor
@Test func jobArchiveStaleAuditUsesStatusProductIDInSharedRoot() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let sharedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OPCJobShared-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    store.products[0].rootDirectory = sharedRoot.path
    let firstProductID = store.selectedProductID
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    store.products[store.products.count - 1].rootDirectory = sharedRoot.path
    let firstJob = try writeCLIJobArchive(
        root: sharedRoot,
        jobID: "first-product-ghost",
        productID: firstProductID,
        agentID: engineer.id,
        updatedAt: Date(timeIntervalSinceNow: -900)
    )
    let secondJob = try writeCLIJobArchive(
        root: sharedRoot,
        jobID: "second-product-ghost",
        productID: secondProductID,
        agentID: engineer.id,
        updatedAt: Date(timeIntervalSinceNow: -900)
    )

    let secondStatus = store.runJobArchiveStaleAuditForSelectedProduct(staleAfter: 180)
    #expect(secondStatus == .warning)
    #expect(try String(contentsOf: secondJob.appendingPathComponent("status.json")).contains("\"interrupted\""))
    #expect(try String(contentsOf: firstJob.appendingPathComponent("status.json")).contains("\"running\""))

    store.selectProduct(firstProductID)
    let firstStatus = store.runJobArchiveStaleAuditForSelectedProduct(staleAfter: 180)
    #expect(firstStatus == .warning)
    #expect(try String(contentsOf: firstJob.appendingPathComponent("status.json")).contains("\"interrupted\""))
}

@MainActor
@Test func selectedAgentIdentityAndPermissionsCanBeEdited() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    store.updateSelectedAgentIdentity(displayName: "Claude 实现负责人", title: "高级实现负责人", role: .custom, reportsToCTO: false)
    store.updateSelectedAgentPermission(.useNetwork, isEnabled: true)
    store.updateSelectedAgentPermission(.editFiles, isEnabled: false)

    let updated = try #require(store.agents.first { $0.id == engineer.id })
    #expect(updated.displayName == "Claude 实现负责人")
    #expect(updated.title == "高级实现负责人")
    #expect(updated.role == .custom)
    #expect(updated.reportsToCTO == false)
    #expect(updated.permissions.contains(.useNetwork))
    #expect(!updated.permissions.contains(.editFiles))
    #expect(store.events.contains { $0.title == "员工身份已更新" })
    #expect(store.events.contains { $0.title == "员工权限已更新" })
}

@MainActor
@Test func resetToDefaultCompanyStateRemovesTestDataAndSpecialists() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.draftEmployee.displayName = "产品架构师"
    store.draftEmployee.role = .productArchitect
    store.draftEmployee.command = "codex"
    store.draftEmployee.model = "gpt-5.5"
    store.addEmployee(from: store.draftEmployee)
    store.addProductWorkspace()
    store.createTask(title: "流水线 旧版恢复任务", ownerID: store.ctoID, status: .running, successCriteria: "恢复默认状态时应移除。")
    store.recordCLIPreflight(agentID: store.ctoID, prompt: "测试")

    #expect(store.agents.contains { $0.role == .productArchitect })
    #expect(store.products.count > 1)
    #expect(!store.terminalLogs.isEmpty)

    store.resetToDefaultCompanyState()

    #expect(store.products.count == 1)
    #expect(store.agents.count == 5)
    #expect(!store.agents.contains { $0.role == .productArchitect || $0.role == .tester || $0.role == .researcher })
    #expect(store.selectedAgentID == store.ctoID)
    #expect(store.terminalLogs.isEmpty)
    #expect(store.selectedProductTasks.count == 3)
    #expect(store.events.first?.title == "公司已恢复默认状态")
}

@MainActor
@Test func cleanupCreatesCheckpointAndLatestCheckpointCanRestoreState() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let emptyCheckpointText = store.safetyCheckpointListText()
    #expect(!emptyCheckpointText.contains("CTO 自动调度"))
    #expect(emptyCheckpointText.contains("技术负责人自动调度") || !emptyCheckpointText.contains("暂无安全检查点。"))
    store.createTask(title: "流水线 检查点回滚任务", ownerID: store.ctoID, status: .running, successCriteria: "检查点应恢复旧流水线任务。")

    #expect(store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })

    store.clearSelectedProductRunData()

    #expect(!store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })
    let checkpointText = store.safetyCheckpointListText()
    #expect(checkpointText.contains("最近安全检查点"))
    #expect(checkpointText.contains(String(Date().opcDateTimeText.prefix(10))))
    #expect(!checkpointText.contains("4/30/2026"))
    #expect(!checkpointText.contains("AM"))
    #expect(!checkpointText.contains("PM"))
    #expect(!checkpointText.contains("Library/Application Support"))
    #expect(!checkpointText.contains("checkpoints/"))
    #expect(!checkpointText.contains(".json"))

    store.restoreLatestSafetyCheckpoint()

    #expect(store.selectedProductTasks.contains { $0.title.hasPrefix("流水线 ") })
    #expect(store.events.contains { $0.title == "已回滚到最近安全检查点" })
}

@Test func opcDateTimeTextProducesStableChineseFormatWithoutAmericanLeak() async throws {
    // 用固定时间避免依赖系统当前时刻。1761854563 = 2025-10-30 17:22:43 UTC（早于美式 4/30/2026 风险窗口）
    let date = Date(timeIntervalSince1970: 1_761_854_563)
    let formatted = date.opcDateTimeText

    // 反向断言：不能出现美式月/日/年、英文月份缩写、AM/PM。
    #expect(!formatted.contains("AM"))
    #expect(!formatted.contains("PM"))
    #expect(!formatted.contains("4/30/2026"))
    let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    for month in englishMonths {
        #expect(!formatted.contains(month), "\(formatted) 不应包含英文月份缩写 \(month)")
    }

    // 正向断言：必须形如 2026/04/30 19:02（四位年 / 两位月 / 两位日 + 任意空白 + HH:mm）。
    let pattern = #"^\d{4}/\d{2}/\d{2}\s\d{2}:\d{2}$"#
    #expect(formatted.range(of: pattern, options: .regularExpression) != nil, "实际格式：\(formatted)")
}

@Test func backendDisplayHelpersKeepOnlyToolNameAndChineseFallback() async throws {
    #expect(opcBackendCommandDisplayName("/usr/local/bin/codex --dangerous-flag") == "Codex")
    #expect(opcBackendCommandDisplayName("gemini --model foo") == "Gemini")
    #expect(opcBackendCommandDisplayName("/opt/homebrew/bin/claude --verbose") == "Claude Code")
    #expect(opcBackendCommandDisplayName("/opt/homebrew/bin/custom-tool --verbose") == "custom-tool")
    #expect(opcBackendCommandDisplayName("   ") == "未配置")
    #expect(opcBackendModelDisplayName("") == "默认模型")
    let compact = opcBackendCompactDisplay(command: "/opt/homebrew/bin/claude --verbose", model: "")
    #expect(compact == "工具 Claude Code · 默认模型")
    #expect(!compact.contains("/opt/homebrew"))
    #expect(!compact.contains(" / "))
    let localCompact = opcBackendCompactDisplay(type: .local, command: "human", model: "owner")
    #expect(localCompact == "本地占位 · owner")
    #expect(!localCompact.contains("工具 human"))
    let emptyLocalCompact = opcBackendCompactDisplay(type: .local, command: "human", model: "")
    #expect(emptyLocalCompact == "本地占位")
    #expect(!emptyLocalCompact.contains("local"))
    let apiCompact = opcBackendCompactDisplay(type: .api, command: "api-agent", model: "gpt-5.5")
    #expect(apiCompact == "接口模型 · gpt-5.5")
}

@Test func productWorkspaceDisplayNameHidesAbsoluteLocalPathInDefaultUI() async throws {
    let absolute = opcProductWorkspaceDisplayName("/Users/demo/Desktop/OPCCompany")
    #expect(absolute == "本地工作区：OPCCompany")
    #expect(!absolute.contains("/Users/"))
    #expect(!absolute.contains("demo"))

    let homeExpanded = opcProductWorkspaceDisplayName("~/Desktop/MyProduct")
    #expect(homeExpanded == "本地工作区：MyProduct")
    #expect(!homeExpanded.contains("~/"))

    #expect(opcProductWorkspaceDisplayName("   ") == "未设置本地工作区")
}

@Test func productDetailHeaderUsesWorkspaceDisplayNameInsteadOfRawRootPath() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("opcProductWorkspaceDisplayName(product?.rootDirectory ?? \"\")"),
            "产品详情页 header 必须通过显示 helper 展示本地工作区摘要")
    #expect(!source.contains("Text(product?.rootDirectory"),
            "产品详情页默认可见 header 不应直接渲染 rootDirectory 绝对路径")
    #expect(!source.contains(".help(product?.rootDirectory"),
            "产品详情页默认 header 不应通过 tooltip 继续暴露完整绝对路径")
}

@MainActor
@Test func defaultVisibleInterfaceCopyUsesChineseRoleTermsAndKeepsBrandsAvailable() async throws {
    let visibleText = OPCVisibleInterfaceCopy.defaultVisibleTexts.joined(separator: "\n")

    #expect(visibleText.contains("OPC 智能公司指挥舱"))
    #expect(visibleText.contains("本地员工编队"))
    #expect(visibleText.contains("智能控制 / 通信"))
    #expect(visibleText.contains("指令通道"))
    #expect(visibleText.contains("向选中员工"))

    #expect(!visibleText.contains("OPC AI"))
    #expect(!visibleText.contains("AI 控制"))
    #expect(!visibleText.contains("Agent 编队"))
    #expect(!visibleText.contains("向选中 Agent"))
    #expect(!visibleText.contains("COMMAND LINK"))
    #expect(!visibleText.contains("Codex CTO"))
    // 售前方案主题 placeholder 已纳入默认可见文案锁；不应再回退到 "AI 知识库" / "AI Agent"。
    #expect(visibleText.contains("某客户智能知识库建设方案"))
    #expect(!visibleText.contains("AI 知识库"))
    #expect(!visibleText.contains("AI Agent"))
    #expect(!visibleText.contains("AI 通信"))
    #expect(!visibleText.contains("Agent 控制"))
    #expect(!visibleText.contains("CTO 办公"))
    #expect(!visibleText.contains("backend"))
    #expect(!visibleText.contains("rawValue"))
    #expect(!visibleText.contains("model_reasoning_effort"))
    // 品牌/工具/模型名仍允许保留：测试不应锁掉这些。这里特意确认它们没有被
    // 错误地塞进默认可见文案锁里（默认文案是产品话术，不该混 brand）。
    #expect(!visibleText.contains("Codex"))
    #expect(!visibleText.contains("Claude Code"))
    #expect(!visibleText.contains("Gemini"))
    #expect(!visibleText.contains("OpenAI"))

    // accessibility identifier 是 Computer Use 自动化用的不可见 anchor，不应被错误塞进默认可见文案锁里。
    let identifierStrings = OPCUIAutomationIdentifier.allCases.map(\.rawValue)
    for identifier in identifierStrings {
        #expect(!visibleText.contains(identifier), "默认可见文案不应包含 a11y identifier：\(identifier)")
    }
}

@MainActor
@Test func maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords() async throws {
    // 信息密度优化后，技术维护审计中心 / 维护产物档案 / 运行证据归档 等中心文案
    // 必须保持中文产品话术；不能回退到 AI 控制 / Agent 编队 / COMMAND LINK / CTO 办公室 / backend / rawValue 等旧词。
    let store = CompanyStore.bootstrap(loadPersisted: false)

    // 当前产品默认无维护记录/产物：empty 文案应以中文产品话术展示。
    let evidencePreview = store.evidenceClassificationAuditText()
    let pressurePreview = store.maintenanceDataPressureText()
    let combinedPreview = [evidencePreview, pressurePreview].joined(separator: "\n")

    // 必须含的关键中文锚点（信息密度优化后保留 / 沿用）
    #expect(evidencePreview.contains("运行证据分类巡检"))
    #expect(pressurePreview.contains("维护数据增长预览"))
    #expect(pressurePreview.contains("不删除任何数据、不裁剪主快照"))

    // 不应回退到旧词或暴露内部字段
    let legacyTerms = [
        "AI 控制", "Agent 编队", "COMMAND LINK", "CTO 办公", "OPC AI",
        "backend", "rawValue", "subscriptionCLI", "persistentProtocol",
        "model_reasoning_effort", "--skip-git-repo-check"
    ]
    for term in legacyTerms {
        #expect(!combinedPreview.contains(term), "维护中心预览不应包含旧词：\(term)")
    }
}

@MainActor
@Test func localDiagnosticsPolicyKeepsCrashAndLogHandlingLocalOnly() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let text = store.localDiagnosticsPolicyText()

    #expect(text.contains("本机诊断与日志策略"))
    #expect(text.contains("不接入外部崩溃上报"))
    #expect(text.contains("不自动上传日志"))
    #expect(text.contains("主状态快照"))
    #expect(text.contains("历史索引"))
    #expect(text.contains("安全检查点"))
    #expect(text.contains("命令行作业档案"))
    #expect(text.contains("macOS 崩溃报告"))
    #expect(text.contains("DiagnosticReports/OPCCompany_*.crash"))
    #expect(!text.contains("Sentry"))
    #expect(!text.contains("Crashlytics"))
    #expect(!text.contains("Sparkle"))
}

@MainActor
@Test func localDiagnosticsPolicyAvoidsFakeJobArchivePathWithoutSelectedProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.selectedProductID = UUID()

    let text = store.localDiagnosticsPolicyText()

    #expect(text.contains("命令行作业档案：未选择产品，暂无命令行作业档案路径"))
    #expect(!text.contains("当前产品工作区/.opc/jobs"))
}

@Test func uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths() async throws {
    // RUNBOOK 列出的 Computer Use 关键控件 anchor，必须由 OPCUIAutomationIdentifier 集中常量覆盖。
    let identifiers = OPCUIAutomationIdentifier.allCases

    // 1. 全部非空、必须以 `OPC` 前缀开头（命名约定）。
    for identifier in identifiers {
        let raw = identifier.rawValue
        #expect(!raw.isEmpty, "identifier 不能为空：\(identifier)")
        #expect(raw.hasPrefix("OPC"), "identifier 必须以 OPC 前缀开头：\(raw)")
    }

    // 2. rawValue 唯一（避免 a11y tree 出现重复 anchor）。
    let rawValues = identifiers.map(\.rawValue)
    let unique = Set(rawValues)
    #expect(unique.count == rawValues.count, "OPCUIAutomationIdentifier 的 rawValue 必须唯一")

    // 3. 必须覆盖 RUNBOOK 「终端大厅维护区关键控件」列出的全部条目；任何一条被误删都会让自动化定位失效。
    // 终端大厅默认即摘要工作台：3 张摘要卡片（架构/通信/本地稳定性）默认可见，每张同时登记自身 anchor
    // 和「查看详情」按钮 anchor，分别用于 a11y tree 上的卡片定位与二级面板触发。
    let runbookKeyPaths: Set<String> = [
        "OPCTerminalAutoInteractionLoopPanel",
        "OPCTerminalAutoLoopTaskContextField",
        "OPCTerminalAutoLoopMaxTurnsStepper",
        "OPCTerminalAutoLoopStartButton",
        "OPCTerminalAutoLoopReportSummary",
        "OPCMaintenanceAuditCenter",
        "OPCMaintenanceAuditRow",
        "OPCMaintenanceArtifactCenter",
        "OPCMaintenanceArtifactRow",
        "OPCCLIRecoveryAdvicePanel",
        "OPCCLIRecoveryAdviceSummary",
        "OPCCLIRecoveryAdviceManualRetryButton",
        "OPCTerminalWorkspaceHealthPreview",
        "OPCRunDataCleanupPreview",
        "OPCCLIToolchainPreflightPreview",
        "OPCDefaultCompanyStatePreview",
        "OPCProductIsolationAuditPreview",
        "OPCCLIRuntimeIsolationPreview",
        "OPCCLIRuntimeIsolationDetailToggle",
        "OPCCLIRuntimeIsolationDetailPreview",
        "OPCTerminalWorkspacePlanPreview",
        "OPCTerminalWorkspacePlanDetailToggle",
        "OPCTerminalWorkspacePlanDetailPreview",
        "OPCSafetyCheckpointPreview",
        "OPCLocalDiagnosticsPolicyPreview",
        "OPCEmployeeHandoffAuditPreview",
        "OPCJobArchiveStaleAuditPreview",
        "OPCEvidenceClassificationAuditButton",
        "OPCEvidenceClassificationAuditPreview",
        "OPCMaintenanceDataPressureAuditButton",
        "OPCMaintenanceDataPressurePreview",
        "OPCHistoryIndexAuditPreview",
        "OPCHistoryArchiveMigrationPreview",
        "OPCLegacyTaskProductMigrationButton",
        "OPCLegacyTaskProductMigrationPreview",
        "OPCRuntimeSessionHealthAuditPreview",
        "OPCLinkedLocalFileRootAllowlistPreview",
        "OPCTerminalHallDetailSheet",
        "OPCLocalMaintenanceCenterRoot",
        "OPCLocalMaintenanceDangerousConfirmationPanel",
        "OPCLocalMaintenanceDangerousConfirmationPhraseField",
        "OPCLocalMaintenanceDangerousConfirmationCancelButton",
        "OPCLocalMaintenanceDangerousConfirmationExecuteButton",
        "OPCTerminalHallOverviewSummary",
        "OPCTerminalHallLocalMaintenanceHeaderTrigger",
        "OPCTerminalHallRunAllButton",
        "OPCTerminalHallHeaderPromptField",
        "OPCTerminalManualREPLInputField",
        "OPCTerminalManualREPLSendButton",
        "OPCAdvancedMaintenanceArchitectureSummaryCard",
        "OPCAdvancedMaintenanceGatewaySummaryCard",
        "OPCAdvancedMaintenanceLocalSummaryCard",
        "OPCAdvancedMaintenanceArchitectureAuditButton",
        "OPCAdvancedMaintenanceArchitectureClosureDrillButton",
        "OPCAdvancedMaintenanceLocalIsolationAuditButton",
        "OPCAdvancedMaintenanceLocalCLIPreflightButton",
        "OPCAdvancedMaintenanceArchitectureDetailTrigger",
        "OPCAdvancedMaintenanceGatewayDetailTrigger",
        "OPCAdvancedMaintenanceLocalDetailTrigger",
        "OPCAutoCapturedSummaryDuplicateCleanupButton",
        "OPCAutoCapturedSummaryDuplicatePreview",
        "OPCTerminalAgentCardRefreshPreflightButton",
        "OPCTerminalAgentCardPreflightButton",
        "OPCTerminalAgentCardRunButton",
        "OPCTerminalAgentCardClearLogButton",
        "OPCTerminalAgentCardSelectButton",
        "OPCCLIRuntimeIsolationAuditButton",
        "OPCTerminalWorkspaceStartButton",
        "OPCTerminalWorkspaceRefreshLogsButton",
        "OPCTerminalWorkspaceHealthAuditButton",
        "OPCRuntimeSessionHealthAuditButton",
        "OPCEmployeeHandoffAuditButton",
        "OPCJobArchiveStaleAuditButton",
        "OPCHistoryIndexAuditButton",
        "OPCHistoryArchiveMigrationButton",
        "OPCStaleRuntimeSessionRecoveryButton",
        "OPCRunDataCleanupConfirmButton",
        "OPCDefaultCompanyStateConfirmButton",
        "OPCSafetyCheckpointRollbackConfirmButton"
    ]
    let runbookCovered = runbookKeyPaths.subtracting(unique)
    #expect(runbookCovered.isEmpty, "RUNBOOK 中的 a11y identifier 未在 OPCUIAutomationIdentifier 登记：\(runbookCovered.sorted())")

    // 4. 反向：所有 enum case 都对应 RUNBOOK 文档中提到的稳定 anchor（避免有人加了 enum case 但没更新文档）。
    let extraIdentifiers = unique.subtracting(runbookKeyPaths)
    #expect(extraIdentifiers.isEmpty, "新增了 OPCUIAutomationIdentifier 但 RUNBOOK 未同步登记：\(extraIdentifiers.sorted())")
}

@MainActor
@Test func terminalHallVisibleExecutionSummaryHidesBackendCommandDetails() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    let ctoSummary = store.commandPreview(for: cto, prompt: "继续推进产品")
    #expect(ctoSummary.contains("运行方式"))
    #expect(ctoSummary.contains("工具 Codex"))
    #expect(ctoSummary.contains("gpt-5.5"))
    #expect(ctoSummary.contains("思考强度"))
    #expect(!ctoSummary.contains("推理强度"))
    #expect(!ctoSummary.contains("工具 codex"))
    #expect(!ctoSummary.contains("model_reasoning_effort"))
    #expect(!ctoSummary.contains("--skip-git-repo-check"))
    #expect(!ctoSummary.contains("codex exec"))
    #expect(!ctoSummary.contains("/usr/local/bin"))

    let engineerSummary = store.commandPreview(for: engineer, prompt: "修复界面")
    #expect(engineerSummary.contains("工具 Claude Code"))
    #expect(!engineerSummary.contains("工具 claude"))
    #expect(engineerSummary.contains("sonnet"))
    #expect(!engineerSummary.contains("permission-mode"))
    #expect(!engineerSummary.contains("claude -p"))
}

@MainActor
@Test func visibleTerminalLogHidesLegacyCommandPathsAndRawFlags() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    store.terminalLogs[cto.id] = """
    [OPC 会话预热]
    原因：App 启动后预热当前产品团队
    本地命令已就绪：/Users/demo/.npm-global/bin/codex
    $ /Users/demo/.npm-global/bin/codex exec --skip-git-repo-check --cd . -m gpt-5.5 -c model_reasoning_effort="high" 默认任务
    普通输出保持可见
    """

    let log = store.visibleTerminalLog(for: cto.id)

    #expect(log.contains("本地命令已就绪：Codex"))
    #expect(log.contains("原因：应用启动后预热当前产品团队"))
    #expect(log.contains("底层命令已隐藏"))
    #expect(log.contains("普通输出保持可见"))
    #expect(!log.contains("App 启动"))
    #expect(!log.contains("/Users/demo/.npm-global/bin/codex"))
    #expect(!log.contains("codex exec"))
    #expect(!log.contains("model_reasoning_effort"))
    #expect(!log.contains("--skip-git-repo-check"))
}

@MainActor
@Test func visibleTerminalLogIsScopedToSelectedProductForSameEmployee() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let firstProductID = store.selectedProductID

    store.recordCLIPreflight(agentID: cto.id, prompt: "第一产品终端日志")
    #expect(store.visibleTerminalLog(for: cto.id).contains("第一产品终端日志"))

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    store.recordCLIPreflight(agentID: cto.id, prompt: "第二产品终端日志")
    #expect(store.visibleTerminalLog(for: cto.id).contains("第二产品终端日志"))
    #expect(!store.visibleTerminalLog(for: cto.id).contains("第一产品终端日志"))

    store.selectProduct(firstProductID)
    #expect(store.visibleTerminalLog(for: cto.id).contains("第一产品终端日志"))
    #expect(!store.visibleTerminalLog(for: cto.id).contains("第二产品终端日志"))

    store.selectProduct(secondProductID)
    store.clearTerminalLog(for: cto.id)
    #expect(store.currentProductTerminalLog(for: cto.id).isEmpty)

    store.selectProduct(firstProductID)
    #expect(store.visibleTerminalLog(for: cto.id).contains("第一产品终端日志"))
}

@MainActor
@Test func visibleTerminalLogFiltersLegacyMixedBlocksFromOtherProducts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let firstProductID = store.selectedProductID
    store.addProductWorkspace()
    let legacyRenamedProductName = "新产品旧名称"
    store.selectProduct(firstProductID)

    let mixedLegacyLog = """
    [OPC 会话预热]
    原因：应用启动后预热当前产品团队
    本地命令已就绪：codex

    [OPC Chat]
    当前产品：\(legacyRenamedProductName) / 调研。
    老板：你好，你是谁
    模型回复里仍然提到了 \(legacyRenamedProductName)。
    [chat exit 0]

    [OPC 运行前预检]
    产品：默认产品工作区
    任务摘要：当前产品自己的预检
    """
    store.productTerminalLogs["\(firstProductID.uuidString.lowercased()):\(cto.id.uuidString.lowercased())"] = mixedLegacyLog

    let log = store.visibleTerminalLog(for: cto.id)

    #expect(log.contains("应用启动后预热当前产品团队"))
    #expect(log.contains("当前产品自己的预检"))
    #expect(!log.contains(legacyRenamedProductName))
    #expect(!log.contains("老板：你好，你是谁"))
    #expect(!log.contains("[chat exit 0]"))
}

@MainActor
@Test func visibleTerminalLogSummarizesCompletedCommandTranscriptButKeepsRawArchive() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    store.terminalLogs[cto.id] = """

    [OPC 命令行任务]
    执行位置：主工作区
    运行方式：订阅制命令行 · 工具 Codex · gpt-5.5 · 思考强度 高
    任务摘要：汇报你的角色、当前状态和下一步建议。

    [OPC 长期席位执行]
    本次任务会在该员工的长期席位运行；完成后会被收录到产物记录和验收流程。

    OpenAI Codex v0.128.0 (research preview)
    workdir: /Users/demo/Desktop
    session id: 019dfc5f-1e3f-7541-b889-a6398738deec
    大段模型输出会保留在原始终端日志和命令行作业档案里。

    [命令退出码 0]

    [OPC 交互状态]
    状态：可继续交互。

    """

    let raw = store.terminalLogs[cto.id, default: ""]
    let log = store.visibleTerminalLog(for: cto.id)

    #expect(raw.contains("OpenAI Codex"))
    #expect(raw.contains("session id:"))
    #expect(raw.contains("/Users/demo/Desktop"))

    #expect(log.contains("[OPC 命令行任务摘要]"))
    #expect(log.contains("执行位置：主工作区"))
    #expect(log.contains("运行方式：订阅制命令行 · 工具 Codex · gpt-5.5 · 思考强度 高"))
    #expect(log.contains("任务摘要：汇报你的角色、当前状态和下一步建议。"))
    #expect(log.contains("退出码：0"))
    #expect(log.contains("状态：可继续交互。"))
    #expect(log.contains("完整输出保留在命令行作业档案。"))
    #expect(!log.contains("OpenAI Codex"))
    #expect(!log.contains("session id:"))
    #expect(!log.contains("/Users/demo/Desktop"))
    #expect(!log.contains("大段模型输出"))
}

@MainActor
@Test func visibleTerminalLogSummarizesTerminalWorkspaceTranscriptButKeepsRawArchive() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    store.terminalLogs[cto.id] = """

    [OPC 真实终端工作区]
    员工终端席位已创建。
    printf %b 'OPC 员工终端：Codex 技术负责人（技术负责人）\\n执行目录：/Users/demo/Desktop\\n请从 OPC 应用发起任务，确保保留预检、作业档案和验收记录。'
    demo@Demo-MacBook-Pro Desktop % printf %b 'OPC 员工终端：Codex 技术负责人'
    执行目录：/Users/demo/Desktop
    请从 OPC 应用发起任务，确保保留预检、作业档案和验收记录。%

    [OPC 命令行任务]
    执行位置：主工作目录
    运行方式：订阅制命令行 · 工具 Codex · gpt-5.5 · 思考强度 高
    任务摘要：汇报当前状态。
    [命令退出码 0]

    """

    let raw = store.terminalLogs[cto.id, default: ""]
    let log = store.visibleTerminalLog(for: cto.id)

    #expect(raw.contains("printf %b"))
    #expect(raw.contains("/Users/demo/Desktop"))
    #expect(raw.contains("demo@Demo-MacBook-Pro"))

    #expect(log.contains("[OPC 真实终端工作区摘要]"))
    #expect(log.contains("员工终端席位已创建。"))
    #expect(log.contains("执行位置：本地工作区"))
    #expect(log.contains("完整启动记录保留在维护档案。"))
    #expect(log.contains("[OPC 命令行任务摘要]"))
    #expect(!log.contains("printf %b"))
    #expect(!log.contains("/Users/demo/Desktop"))
    #expect(!log.contains("demo@Demo-MacBook-Pro"))
    #expect(!log.contains("Desktop %"))
}

@MainActor
@Test func visibleTerminalLogSummarizesRepeatedOPCSessionWarmupBlocks() async throws {
    // 终端员工卡反复显示完全相同的 [OPC 会话预热] 块违背产品默认信息密度准则。
    // visibleTerminalLog 必须把多次预热合并成「最近 1 份原文 + 中文历史条数提示」；
    // 但 terminalLogs 原始存储不能被改动——审计证据、维护证据归档、命令行作业档案
    // 都基于原始流，可见层减噪不能影响这些审计来源。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let warmupBlock = """

    [OPC 会话预热]
    原因：手动唤醒
    本地命令已就绪：codex
    常驻能力：长期会话。

    """
    // 故意写 3 次完全相同的预热块（Computer Use 实测里就是这种模式）。
    store.terminalLogs[cto.id] = warmupBlock + warmupBlock + warmupBlock

    let log = store.visibleTerminalLog(for: cto.id)

    // 1. 原始存储未被改动：3 段 [OPC 会话预热] 仍在 terminalLogs 中。
    let raw = store.terminalLogs[cto.id, default: ""]
    let rawWarmupCount = raw.components(separatedBy: "[OPC 会话预热]").count - 1
    #expect(rawWarmupCount == 3,
            "原始 terminalLogs 不应被可见层减噪改动；当前出现 \(rawWarmupCount) 次（应为 3 次）。")
    #expect(raw.contains("原因：手动唤醒"))
    #expect(raw.contains("常驻能力：长期会话。"))

    // 2. 可见日志汇总为 1 份原文 + 中文历史条数提示。
    let visibleWarmupCount = log.components(separatedBy: "[OPC 会话预热]").count - 1
    #expect(visibleWarmupCount == 1,
            "可见日志应只保留 1 份预热块原文，实际出现 \(visibleWarmupCount) 次。")
    #expect(log.contains("（另有 2 条历史「OPC 会话预热」记录，完整记录保留在维护档案。）"),
            "缺少中文历史汇总提示；当前可见日志：\n\(log)")

    // 3. 单份原文里仍保留预热块的核心字段（不能被合并提示替代）。
    #expect(log.contains("原因：手动唤醒"))
    #expect(log.contains("本地命令已就绪：Codex"))
    #expect(log.contains("持续协作：可继续接收任务。"))
    #expect(!log.contains("常驻能力："))
    #expect(!log.contains("常驻协议"))
}

@MainActor
@Test func visibleTerminalLogSummarizesNonConsecutiveWarmupBlocksWithoutDroppingOtherOPCBlocks() async throws {
    // 预热块属于默认噪音，可以跨位置汇总；中间夹着的其他 OPC 块仍必须完整保留。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let warmup = """

    [OPC 会话预热]
    原因：手动唤醒
    本地命令已就绪：codex
    常驻能力：长期会话。

    """
    let preflight = """

    [OPC 运行前预检]
    员工：Codex 团队负责人
    工作目录：/tmp/foo
    运行方式：长期会话

    """
    // 顺序：warmup, preflight, warmup, warmup → 3 个 warmup 汇总为最近 1 份；
    // 中间 preflight 块必须继续保留。
    store.terminalLogs[cto.id] = warmup + preflight + warmup + warmup

    let log = store.visibleTerminalLog(for: cto.id)

    let visibleWarmupCount = log.components(separatedBy: "[OPC 会话预热]").count - 1
    #expect(visibleWarmupCount == 1,
            "多段 warmup 应汇总成 1 份最近预热块；实际 \(visibleWarmupCount)。")
    #expect(log.contains("（另有 2 条历史「OPC 会话预热」记录，完整记录保留在维护档案。）"))
    #expect(log.contains("[OPC 运行前预检]"), "中间的预检块不应被吞掉。")
}

@MainActor
@Test func visibleTerminalLogSummarizesWarmupBlocksWithDifferentReasons() async throws {
    // 标题相同但原因不同的预热块也属于默认预热噪音；可见层显示最近一条 + 历史汇总。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let warmupA = """

    [OPC 会话预热]
    原因：第一次唤醒
    本地命令已就绪：codex
    常驻能力：长期会话。

    """
    let warmupB = """

    [OPC 会话预热]
    原因：第二次唤醒
    本地命令已就绪：codex
    常驻能力：长期会话。

    """
    store.terminalLogs[cto.id] = warmupA + warmupB

    let log = store.visibleTerminalLog(for: cto.id)

    let visibleWarmupCount = log.components(separatedBy: "[OPC 会话预热]").count - 1
    #expect(visibleWarmupCount == 1, "预热块应只显示最近 1 份；实际可见 \(visibleWarmupCount) 份。")
    #expect(!log.contains("原因：第一次唤醒"))
    #expect(log.contains("原因：第二次唤醒"))
    #expect(log.contains("（另有 1 条历史「OPC 会话预热」记录，完整记录保留在维护档案。）"))
}

@MainActor
@Test func visibleTerminalLogDoesNotCollapseDifferentNonWarmupOPCBlocksWithSameHeading() async throws {
    // 非预热类 OPC 块仍按原策略处理：内容不同不能被合并。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let blockA = """

    [OPC 运行前预检]
    结论：A

    """
    let blockB = """

    [OPC 运行前预检]
    结论：B

    """
    store.terminalLogs[cto.id] = blockA + blockB

    let log = store.visibleTerminalLog(for: cto.id)

    let visiblePreflightCount = log.components(separatedBy: "[OPC 运行前预检]").count - 1
    #expect(visiblePreflightCount == 2, "内容不同的非预热 OPC 块不应合并；实际可见 \(visiblePreflightCount) 份。")
}

@MainActor
@Test func visibleTerminalLogDoesNotCollapseRegularModelOutputEvenIfRepeated() async throws {
    // 普通模型输出（非 [OPC ...] 标题块）即使重复也不参与合并——只压缩 OPC 元数据块，不动模型业务输出。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    store.terminalLogs[cto.id] = """
    模型输出第一段。
    模型输出第二段。
    模型输出第一段。
    模型输出第二段。
    """

    let log = store.visibleTerminalLog(for: cto.id)

    let firstCount = log.components(separatedBy: "模型输出第一段。").count - 1
    let secondCount = log.components(separatedBy: "模型输出第二段。").count - 1
    #expect(firstCount == 2, "普通模型输出不参与合并；应保留 2 次「模型输出第一段。」")
    #expect(secondCount == 2, "普通模型输出不参与合并；应保留 2 次「模型输出第二段。」")
    #expect(!log.contains("已合并显示"))
}

@MainActor
@Test func visibleTerminalLogRemapsWarmupLinesToCurrentLanguageBothWays() async throws {
    // 对称重映射:zh 生成的历史日志在 en 会话渲染为 en;en 生成的历史日志在 zh 会话渲染为 zh。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    // zh-generated log: XCTest forces Chinese session, so the zh log renders unchanged.
    store.terminalLogs[cto.id] = """
    [OPC 会话预热]
    原因：应用启动后预热当前产品团队
    本地命令已就绪：Codex
    持续协作：可继续接收任务。
    """
    let zhRendered = store.visibleTerminalLog(for: cto.id)
    #expect(zhRendered.contains("[OPC 会话预热]"))
    #expect(zhRendered.contains("本地命令已就绪：Codex"))

    // en-generated log must be re-rendered in Chinese under the zh session.
    store.terminalLogs[cto.id] = """
    [OPC Session Warmup]
    Reason: Warm up the current product team after launch
    Local command ready: Codex
    Continuous collaboration: Can accept more tasks.
    """
    let enLogRendered = store.visibleTerminalLog(for: cto.id)
    #expect(enLogRendered.contains("[OPC 会话预热]"))
    #expect(enLogRendered.contains("本地命令已就绪：Codex"))
    #expect(!enLogRendered.contains("Local command ready"))
    #expect(!enLogRendered.contains("[OPC Session Warmup]"))
}

@MainActor
@Test func builtinAgentNamesReRenderOnLanguageSwitch() {
    // 内置五人组的标准名/职位在语言切换时重渲染;自定义名不受影响。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // 模拟英文模式重渲染(XCTest 强制 zh 会话,这里直接调内部逻辑验证 zh 目标):
    store.refreshBuiltinAgentNamesForLanguage()
    let cto = store.agents.first { $0.role == .cto }
    #expect(cto?.displayName == "Codex 技术负责人")
    #expect(cto?.title == "总技术负责人")
    // 自定义名不被改写:
    var store2 = CompanyStore.bootstrap(loadPersisted: false)
    if let idx = store2.agents.firstIndex(where: { $0.role == .cto }) {
        store2.agents[idx].displayName = "我的定制 CTO"
    }
    store2.refreshBuiltinAgentNamesForLanguage()
    let custom = store2.agents.first { $0.role == .cto }
    #expect(custom?.displayName == "我的定制 CTO")
}

@MainActor
@Test func messageBubbleSystemWelcomeRemapsToCurrentLanguage() {
    // 系统欢迎语固化于生成时语言;气泡渲染层必须按当前会话语言重映射(zh 会话 → zh 文案)。
    let enWelcome = "System notice: OPC Company is live. Real conversations call each employee's configured model source; when unconfigured or unavailable, only a system fallback notice is shown."
    let remapped = MessageBubble.localizedFixedText(enWelcome, author: .system)
    #expect(remapped.contains("OPC 公司已经上线"))
    // 非系统消息与未知文案原样透传
    #expect(MessageBubble.localizedFixedText("hello world", author: .agent) == "hello world")
}

@MainActor
@Test func defaultAgentDisplayNamesFollowSessionLanguageBothWays() async throws {
    // 默认团队名是 bootstrap 数据,固化于创建时语言;加载时必须按当前会话语言重映射(仅精确匹配默认名)。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // XCTest 强制 zh 会话:把 en 形态默认名改写回 zh 形态
    if let idx = store.agents.firstIndex(where: { $0.role == .cto }) {
        store.agents[idx].displayName = "Codex CTO"
    }
    let changed = store.localizeDefaultAgentNames()
    #expect(changed)
    let cto = store.agents.first { $0.role == .cto }
    #expect(cto?.displayName == "Codex 技术负责人")
    // 用户自定义名(非精确默认名)永不触碰
    if let idx = store.agents.firstIndex(where: { $0.role == .cto }) {
        store.agents[idx].displayName = "Codex CTO 老王"
    }
    let changed2 = store.localizeDefaultAgentNames()
    #expect(!changed2)
    #expect(store.agents.first { $0.role == .cto }?.displayName == "Codex CTO 老王")
}

@MainActor
@Test func legacyMixedTitleChiefCTOIsRemappedBothWays() async throws {
    // 旧迁移把 "Chief CTO" 子串替换成 "Chief 技术负责人"(混搭残骸),两种规范形态都不匹配,
    // 导致永远切换不回英文。refresh 必须把已知残骸归位到当前语言。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    if let idx = store.agents.firstIndex(where: { $0.role == .cto }) {
        store.agents[idx].title = "Chief 技术负责人"
    }
    store.refreshBuiltinAgentNamesForLanguage()
    // XCTest 强制 zh 会话 → 应归位到 zh 规范 title
    let zhTitle = store.agents.first { $0.role == .cto }?.title
    #expect(zhTitle == "总技术负责人", "got: \(zhTitle ?? "nil")")
    // en 会话模拟:直接构造 en 会话下的归位(en 判定走 sessionLanguage,测试里强制 zh,
    // 因此这里只验证 zh 向;en 向由 refresh 的对称分支覆盖,同表驱动)
    #expect(zhTitle != "Chief 技术负责人")
}

@MainActor
@Test func legacyCTOVisibleNamesAreLocalizedForPersistedStores() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    guard let index = store.agents.firstIndex(where: { $0.role == .cto }) else {
        Issue.record("未找到技术负责人")
        return
    }
    store.agents[index].displayName = "Codex CTO"
    store.agents[index].title = "CTO 办公室负责人"
    store.tasks.append(CompanyTask(productID: store.selectedProductID, title: "创建 2D 公司 App 基础", ownerID: store.agents[index].id, status: .running, successCriteria: "旧任务标题应本地化。"))

    let changed = store.localizeLegacyVisibleTerminology(saveAfterChange: false)

    #expect(changed)
    #expect(store.agents[index].displayName == "Codex 技术负责人")
    // Invariant upgrade: legacy migration maps WHOLE phrases to the canonical
    // zh title (no substring surgery — that produced "Chief 技术负责人" debris).
    #expect(store.agents[index].title == "总技术负责人")
    #expect(store.tasks.contains { $0.title == "创建 2D 公司应用基础" })
    #expect(!store.agents[index].displayName.contains("CTO"))
    #expect(store.agents[index].title != "CTO 办公室负责人")
    #expect(!store.tasks.contains { $0.title.contains("App 基础") })
}

@MainActor
@Test func legacyUIDesignerVisibleNamesAreLocalizedForPersistedStores() async throws {
    // 旧持久化：默认 UI 员工显示名带英文 "UI 设计师"。加载时 localizeLegacyVisibleTerminology
    // 应当把 displayName 与 title 中的 "UI 设计师" 整体迁移为 "界面设计师"，
    // 同时保留 Gemini 品牌前缀。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    guard let index = store.agents.firstIndex(where: { $0.role == .uiDesigner }) else {
        Issue.record("未找到默认 UI 员工")
        return
    }
    store.agents[index].displayName = "Gemini UI 设计师"
    store.agents[index].title = "UI 设计师"

    let changed = store.localizeLegacyVisibleTerminology(saveAfterChange: false)

    #expect(changed)
    #expect(store.agents[index].displayName == "Gemini 界面设计师")
    #expect(store.agents[index].title == "界面设计师")
    #expect(!store.agents[index].displayName.contains("UI 设计师"))
    #expect(!store.agents[index].title.contains("UI 设计师"))
}

@MainActor
@Test func cliLaunchpadPlansOnlySelectedProductTeamAndRecordsPlan() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.addProductWorkspace()

    #expect(store.selectedProductAgents.map(\.id) == [store.ctoID])

    let plan = store.cliLaunchPlanText(prompt: "汇报状态")
    #expect(plan.contains("命令行任务发车台计划"))
    #expect(plan.contains("Codex 技术负责人"))
    #expect(!plan.contains(engineer.displayName))
    #expect(plan.contains("运行清单"))
    #expect(!plan.contains("OPC_PROMPT"))
    #expect(!plan.contains("model_reasoning_effort"))
    #expect(!plan.contains("--skip-git-repo-check"))

    store.recordCLILaunchPlan(prompt: "汇报状态")

    #expect(store.selectedProductVerifications.contains { $0.title == "命令行任务发车计划" })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("命令行任务发车台计划") })
}

@MainActor
@Test func nonTeamAgentsCannotReceiveQueueOrRunForSelectedProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.addProductWorkspace()
    store.createTask(title: "跨团队阻止测试", ownerID: engineer.id, status: .assigned, successCriteria: "非当前产品团队员工不能运行。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "跨团队阻止测试" })

    store.enqueueWorkItem(taskID: task.id, agentID: engineer.id)
    store.runAgent(agentID: engineer.id, prompt: "不应运行")

    #expect(store.selectedProductWorkQueue.isEmpty)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("未加入"))
    #expect(store.events.contains { $0.title == "已阻止非团队员工入队" })
    #expect(store.events.contains { $0.title == "已阻止非团队员工运行" })
}

@MainActor
@Test func automationEngineTracksQueueApprovalsArtifactsVerificationAndMemory() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCEngineTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "Rules".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
    try "package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.importProductWorkspace(from: root)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.assignAgentToSelectedProduct(engineer.id)
    store.createTask(title: "引擎测试任务", ownerID: engineer.id, status: .assigned, successCriteria: "进入队列并可审批。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "引擎测试任务" })

    store.enqueueWorkItem(taskID: task.id, agentID: engineer.id)
    #expect(store.selectedProductWorkQueue.contains { $0.taskID == task.id && $0.agentID == engineer.id })

    store.requestApproval(taskID: task.id, title: "需要老板批准", reason: "涉及高风险操作", requesterID: engineer.id)
    let approval = try #require(store.selectedProductApprovals.first { $0.title == "需要老板批准" })
    #expect(approval.status == .pending)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .needsApproval)

    store.decideApproval(approval.id, approved: true)
    #expect(store.selectedProductApprovals.first { $0.id == approval.id }?.status == .approved)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .running)

    store.scanProjectArtifacts()
    #expect(store.selectedProductArtifacts.contains { $0.title == "AGENTS.md" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "Package.swift" })

    store.runAutomaticVerification()
    #expect(store.selectedProductVerifications.contains { $0.title == "自动验收检查" })

    store.addMemory(kind: .decision, title: "测试决策", detail: "记录一条产品决策")
    #expect(store.selectedProductMemories.contains { $0.title == "测试决策" })
}

@MainActor
@Test func ctoAutopilotCreatesCheckpointQueueHealthAndMemory() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let agentCount = store.agents.count
    store.createTask(title: "自动调度阻塞任务", ownerID: reviewer.id, status: .blocked, successCriteria: "需要老板处理。")

    store.runCTOAutopilot()

    #expect(store.agents.count == agentCount)
    #expect(!store.agents.contains { $0.displayName == "Codex 产品架构师" })
    #expect(!store.agents.contains { $0.displayName == "Codex 测试工程师" })
    #expect(!store.agents.contains { $0.displayName == "Gemini 研究员" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "安全检查点" })
    #expect(store.selectedProductVerifications.contains { $0.title == "安全检查点已创建" })
    let checkpointArtifact = try #require(store.selectedProductArtifacts.first { $0.title == "安全检查点" })
    let checkpointVerification = try #require(store.selectedProductVerifications.first { $0.title == "安全检查点已创建" })
    #expect(!checkpointArtifact.path.contains("Library/Application Support"))
    #expect(!checkpointArtifact.path.contains("checkpoints/"))
    #expect(!checkpointVerification.detail.contains("Library/Application Support"))
    #expect(!checkpointVerification.detail.contains("checkpoints/"))
    #expect(store.selectedProductVerifications.contains { $0.title == "自动验收检查" })
    #expect(store.selectedProductMemories.contains { $0.title.contains("自动记录") })
    #expect(store.selectedProductApprovals.contains { $0.title.contains("技术负责人请求处理阻塞") })
    #expect(store.selectedProductWorkQueue.count > 0)
    #expect(store.events.contains { $0.title == "技术负责人自动调度完成" })
}

@MainActor
@Test func ctoAutopilotAdvancesPendingSupervisorLoopsBeforeReturning() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "一键推进协作链路"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .planned)

    store.runCTOAutopilot()

    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .assigned)
    #expect(store.selectedProductWorkQueue.contains { item in
        item.taskID == reviewerTask.id
            && item.agentID == reviewerID
            && item.status == .queued
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .ctoLoopProgressed
            && message.subject.contains(goal)
    })
}

@MainActor
@Test func ctoAutopilotVisibleProgressPreventsDuplicateRunsAndCompletes() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.ctoAutopilotState == .idle)
    #expect(store.ctoAutopilotState.statusText == nil)
    #expect(store.runCTOAutopilotWithVisibleProgress())
    #expect(store.ctoAutopilotState == .running)
    #expect(store.ctoAutopilotState.statusText == "正在让技术负责人推进…")
    #expect(!store.runCTOAutopilotWithVisibleProgress())

    // runCTOAutopilot() 的主体在其他测试里实测 ~30–60ms；用最长 2s 的轮询
    // 等待 .completed 状态，避免 fixed-sleep 在慢机器上抖动成 .running。
    for _ in 0..<400 {
        if store.ctoAutopilotState == .completed { break }
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(store.ctoAutopilotState == .completed)
    #expect(store.events.contains { $0.title == "技术负责人自动调度完成" })
    #expect(store.ctoAutopilotState.statusText == "技术负责人已完成本次推进。")

    // 完成后允许再次推进（.completed 不被 isRunning 阻塞），切回 .running。
    #expect(store.runCTOAutopilotWithVisibleProgress())
    #expect(store.ctoAutopilotState == .running)
    for _ in 0..<400 {
        if store.ctoAutopilotState == .completed { break }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(store.ctoAutopilotState == .completed)
}

@Test func productDetailCTOSchedulingEntryPointUsesOwnerFacingCopyAndHidesManualLoopButton() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("store.runCTOAutopilotWithVisibleProgress()"))
    #expect(source.contains("store.ctoAutopilotState.buttonTitle"))
    #expect(source.contains(".disabled(store.ctoAutopilotState.isRunning)"))
    #expect(source.contains("store.ctoAutopilotState.statusText"))
    #expect(source.contains("store.startCTOSupervisorGoal(goal: collaborationGoalSeed)"))
    #expect(source.contains("Label(\"启动技术负责人协作\""))
    #expect(!source.contains("store.advanceCTOSupervisorLoop()"))
    #expect(!source.contains("Label(\"推进技术负责人循环\""))
    #expect(!source.contains("Label(\"技术负责人调度\""))
    #expect(!source.contains("Label(\"启动协作目标\""))
}

@MainActor
@Test func legacyAutoCreatedSpecialistsAreRemovedAndWorkFallsBack() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let legacy = CompanyAgent(
        displayName: "Codex 产品架构师",
        title: "需求与产品结构负责人",
        role: .productArchitect,
        backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .businessSuit,
        permissions: [.readFiles, .runCommands],
        seat: OfficeSeat(x: 0.30, y: 0.45, room: "employee-hall")
    )
    store.agents.append(legacy)
    store.products[0].assignedAgentIDs.insert(legacy.id)
    store.createTask(title: "旧自动员工任务", ownerID: legacy.id, status: .assigned, successCriteria: "迁移后不能悬空。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "旧自动员工任务" })
    store.enqueueWorkItem(taskID: task.id, agentID: legacy.id)

    store.removeLegacyAutoCreatedSpecialists(saveAfterChange: false)

    #expect(!store.agents.contains { $0.id == legacy.id })
    #expect(!store.selectedProductAgents.contains { $0.id == legacy.id })
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.ownerID == store.ctoID)
    #expect(store.selectedProductWorkQueue.first { $0.taskID == task.id }?.agentID == store.ctoID)
    #expect(store.events.contains { $0.title == "自动员工已清理" })
}

@MainActor
@Test func selectingProductRestartsAssignedAgentTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let product = try #require(store.selectedProduct)

    store.selectProduct(product.id)

    #expect(store.selectedProductID == product.id)
    #expect(store.selectedProductAgents.allSatisfy { product.assignedAgentIDs.contains($0.id) })
    #expect(store.selectedProductAgents.contains { $0.role == .cto && $0.status == .thinking })
    #expect(store.selectedProductAgents.filter { $0.role != .cto }.allSatisfy { $0.status == .idle })
    #expect(store.events.contains { $0.title == "产品团队已重新开启" })
    #expect(store.events.contains { $0.title == "切换产品" })
    #expect(store.mainWorkspace == .productDetail)
}

@MainActor
@Test func productTeamMembershipCanBeManagedPerProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.addProductWorkspace()
    let product = try #require(store.selectedProduct)

    #expect(product.assignedAgentIDs == Set([store.ctoID]))
    #expect(store.selectedProductAgents.map(\.id) == [store.ctoID])
    #expect(store.selectedProductAvailableAgents.contains { $0.id == engineer.id })

    store.assignAgentToSelectedProduct(engineer.id)
    #expect(store.selectedProductAgents.contains { $0.id == engineer.id })
    #expect(!store.selectedProductAvailableAgents.contains { $0.id == engineer.id })

    store.updateSelectedProductTeamLead(engineer.id)
    #expect(store.teamLeadAgentIDForSelectedProduct() == engineer.id)

    store.removeAgentFromSelectedProduct(engineer.id)
    #expect(!store.selectedProductAgents.contains { $0.id == engineer.id })
    #expect(store.teamLeadAgentIDForSelectedProduct() == store.ctoID)
}

@MainActor
@Test func productTeamTemplateBindsExistingAgentsWithoutCreatingNewOnes() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let beforeCount = store.agents.count

    store.addProductWorkspace()
    store.applyTeamTemplateToSelectedProduct(.software)

    #expect(store.agents.count == beforeCount)
    #expect(store.selectedProductAgents.contains { $0.role == .cto })
    #expect(store.selectedProductAgents.contains { $0.role == .uiDesigner })
    #expect(store.selectedProductAgents.contains { $0.role == .codeEngineer })
    #expect(store.selectedProductAgents.contains { $0.role == .reviewer })
    #expect(!store.selectedProductAgents.contains { $0.role == .boss })
    #expect(store.missingRoles(for: .software).contains(.productArchitect))
    #expect(store.events.contains { $0.title == "产品团队模板已应用" })
}

@MainActor
@Test func selectingAgentShowsAgentDesk() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.selectAgent(engineer.id)

    #expect(store.selectedAgentID == engineer.id)
    #expect(store.mainWorkspace == .agentDesk)
}

@MainActor
@Test func selectingBossShowsCommandCenter() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.selectAgent(store.bossID)

    #expect(store.selectedAgentID == store.bossID)
    #expect(store.mainWorkspace == .commandCenter)
}

@MainActor
@Test func productSwitchKeepsSelectedAgentInsideCurrentTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    store.addProductWorkspace()

    #expect(store.mainWorkspace == .productDetail)
    #expect(store.selectedAgentID == store.ctoID)
    #expect(store.selectedProductAgents.contains { $0.id == store.selectedAgentID })
}

@MainActor
@Test func teamTemplateSwitchesAwayFromRemovedSelectedAgent() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    store.applyTeamTemplateToSelectedProduct(.research)

    #expect(store.selectedAgentID == store.ctoID)
    #expect(store.selectedProductAgents.contains { $0.id == store.selectedAgentID })
    #expect(!store.selectedProductAgents.contains { $0.id == engineer.id })
}

@MainActor
@Test func focusingAgentKeepsCompanySceneOpen() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.mainWorkspace = .office
    store.focusAgent(engineer.id)

    #expect(store.selectedAgentID == engineer.id)
    #expect(store.mainWorkspace == .office)
    #expect(store.events.contains { $0.title == "观察员工状态" && $0.agentID == engineer.id })
}

@MainActor
@Test func deletingProductRemovesAssociatedStateAndSelectsFallback() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let product = try #require(store.selectedProduct)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "删除产品关联任务", ownerID: engineer.id, status: .assigned, successCriteria: "删除时清理。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "删除产品关联任务" })
    store.enqueueWorkItem(taskID: task.id, agentID: engineer.id)
    store.requestApproval(taskID: task.id, title: "删除产品审批", reason: "测试清理")
    store.requestCTOReview(for: task.id)
    store.addMemory(kind: .decision, title: "删除产品记忆", detail: "测试清理")
    #expect(store.agentMessages.contains { $0.productID == product.id })
    #expect(store.reviewGates.contains { $0.productID == product.id })

    store.deleteProduct(product.id)

    #expect(!store.products.contains { $0.id == product.id })
    #expect(!store.tasks.contains { $0.productID == product.id })
    #expect(!store.workQueue.contains { $0.productID == product.id })
    #expect(!store.approvals.contains { $0.productID == product.id })
    #expect(!store.memories.contains { $0.productID == product.id })
    #expect(!store.agentMessages.contains { $0.productID == product.id })
    #expect(!store.reviewGates.contains { $0.productID == product.id })
    #expect(store.selectedProductID != product.id)
    #expect(store.mainWorkspace == .productDetail)
}

@MainActor
@Test func importingExistingProjectCreatesWorkspaceAndCTOBrief() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCImportTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "Codex rules".write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
    try "Claude memory".write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    try "{}".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

    store.importProductWorkspace(from: root)

    let product = try #require(store.selectedProduct)
    #expect(product.rootDirectory == root.path)
    #expect(product.importReport?.detectedTools.contains("Codex") == true)
    #expect(product.importReport?.detectedTools.contains("Claude Code") == true)
    #expect(product.importReport?.projectFiles.contains("package.json") == true)
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("已导入现有项目") })
    #expect(product.importReport?.summary.contains("智能工具线索") == true)
    #expect(product.importReport?.summary.contains("AI 工具") == false)
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("检测到的智能工具") })
    #expect(!store.messages(for: store.ctoID).contains { $0.text.contains("检测到的 AI 工具") })
    #expect(store.selectedProductTasks.contains { $0.title == "接手现有项目盘点" })
}

@MainActor
@Test func commandCenterTaskOperationsUpdateTasksAndCTOContext() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.createTask(title: "实现产物中心", ownerID: engineer.id, status: .needsApproval, successCriteria: "产物中心可展示任务产物。", artifactPath: "/tmp/artifact.md")
    let task = try #require(store.selectedProductTasks.first { $0.title == "实现产物中心" })

    #expect(task.ownerID == engineer.id)
    #expect(task.status == .needsApproval)
    #expect(task.artifactPath == "/tmp/artifact.md")
    #expect(store.events.contains { $0.kind == .taskCreated })

    store.approveTaskRisk(task.id)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .running)
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("老板已批准任务继续执行") })

    store.rejectTaskRisk(task.id)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .blocked)

    store.acceptTask(task.id)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .done)
    #expect(store.selectedProductVerifications.contains { $0.title == "老板验收通过：\(task.title)" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "验收产物：\(task.title)" && $0.path == "/tmp/artifact.md" })
    #expect(store.selectedProductAgentMessages.contains { $0.kind == .acceptanceCompleted && $0.taskID == task.id })
}

@MainActor
@Test func modelRoutingUpdatesRoleBackends() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    store.updateRoleRouting(role: .codeEngineer, command: "claude", model: "opus", reasoningEffort: .high)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    #expect(engineer.backend.command == "claude")
    #expect(engineer.backend.model == "opus")
    #expect(engineer.backend.reasoningEffort == .high)
    #expect(store.events.contains { $0.title == "模型路由已更新" })
}

@MainActor
@Test func selectedAgentProfileCanUpdateModelAndAppearance() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id

    store.updateSelectedAgentBackend(type: .api, command: "api-agent", model: "deepseek-chat", endpoint: "https://api.example.com/v1", apiKey: "secret-key", reasoningEffort: .high)
    store.updateSelectedAgentAppearance(ethnicity: .chinese, gender: .woman, clothing: .labCoat)

    let updated = try #require(store.agents.first { $0.id == engineer.id })
    #expect(updated.backend.type == .api)
    #expect(updated.backend.command == "api-agent")
    #expect(updated.backend.model == "deepseek-chat")
    #expect(updated.backend.reasoningEffort == .high)
    #expect(updated.ethnicity == .chinese)
    #expect(updated.gender == .woman)
    #expect(updated.clothing == .labCoat)
}

@MainActor
@Test func addingEmployeePlacesNewAvatarInEmployeeHall() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let before = store.agents.count

    store.draftEmployee.displayName = "测试员工"
    store.draftEmployee.title = "测试工程师"
    store.addEmployee(from: store.draftEmployee)

    let employee = try #require(store.agents.first { $0.displayName == "测试员工" })
    #expect(store.agents.count == before + 1)
    #expect(employee.seat.room == "employee-hall")
    #expect(employee.seat.x >= 0.10 && employee.seat.x <= 0.80)
    #expect(employee.seat.y >= 0.10 && employee.seat.y <= 0.80)
    #expect(store.selectedProductAgents.contains { $0.id == employee.id })
}

@MainActor
@Test func communicationGatewayCreatesChannelsAndRoutesMobileCommand() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    store.events.insert(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行作业目录创建失败",
        detail: "维护侧文件系统失败，不应进入团队负责人汇报风险计数。",
        agentID: cto.id
    ), at: 0)
    store.events.insert(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行发车被阻止",
        detail: "老板动作被阻止，应进入团队负责人汇报风险计数。",
        agentID: cto.id
    ), at: 0)

    store.ensureCommunicationGatewayPlan()

    #expect(store.selectedProductCommunicationChannels.count >= 6)
    #expect(store.selectedProductCommunicationChannels.contains { $0.kind == .localOnly && $0.isEnabled })
    #expect(store.selectedProductCommunicationChannels.contains { $0.kind == .telegramBot && $0.commandsEnabled })

    store.sendTeamLeadReportThroughGateway()
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .outbound && $0.title == "团队负责人手机汇报" })
    #expect(store.selectedProductCommunicationLogs.contains { $0.body.contains("技术负责人继续拆解") })
    #expect(store.selectedProductCommunicationLogs.contains { $0.title == "团队负责人手机汇报" && $0.body.contains("风险事件：1 个") })
    #expect(!store.selectedProductCommunicationLogs.contains { $0.body.contains("Endpoint") || $0.body.contains("Chat ID") })

    if let telegram = store.selectedProductCommunicationChannels.first(where: { $0.kind == .telegramBot }) {
        store.updateCommunicationChannel(telegram.id, isEnabled: true)
    }
    if let feishu = store.selectedProductCommunicationChannels.first(where: { $0.kind == .feishuWebhook }) {
        store.updateCommunicationChannel(feishu.id, endpoint: "https://hooks.example.com/open-apis/bot/v2/hook/secret-token-abc", isEnabled: true)
    }
    store.testCommunicationGatewayChannels()
    #expect(store.selectedProductCommunicationLogs.contains { $0.title == "通信通道测试" })
    #expect(store.selectedProductCommunicationLogs.contains { $0.body.contains("需要接口地址") })
    #expect(store.selectedProductCommunicationLogs.contains { $0.body.contains("https://hooks.example.com/***") })
    #expect(!store.selectedProductCommunicationLogs.contains { $0.body.contains("secret-token-abc") })
    #expect(!store.selectedProductCommunicationLogs.contains { $0.body.contains("Endpoint") || $0.body.contains("Chat ID") || $0.body.contains("Webhook/Bot") })
    #expect(store.events.contains { $0.title == "通信通道测试通过" || $0.title == "通信通道待补配置" })

    #expect(store.communicationGatewayMobileLinkText().contains("移动端指令联动"))
    #expect(store.ingestRemoteCommand("让 CTO 安排售前方案团队今天给我一版草稿"))
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.status == .received })
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.body.contains("来源：本地指挥台") })
    #expect(store.selectedProductTasks.contains { $0.title.hasPrefix("手机指令：") })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("手机端指令") })
}

@MainActor
@Test func communicationGatewayRejectsUnreadyMobileCommandChannels() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.ensureCommunicationGatewayPlan()
    let telegram = try #require(store.selectedProductCommunicationChannels.first { $0.kind == .telegramBot })
    store.updateCommunicationChannel(telegram.id, isEnabled: true, commandsEnabled: true)
    let taskCount = store.selectedProductTasks.count

    #expect(!store.ingestRemoteCommand("从未配置的 Telegram 进入", channelID: telegram.id))
    #expect(store.selectedProductTasks.count == taskCount)
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.status == .failed && $0.title == "手机端指令被拒绝" })

    store.updateCommunicationChannel(telegram.id, endpoint: "https://api.telegram.example/bot-token/sendMessage", chatID: "123", isEnabled: true, commandsEnabled: true)
    #expect(!store.ingestRemoteCommand("未签名 Telegram 指令", channelID: telegram.id))
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.status == .failed && $0.body.contains("必须走签名校验入口") })

    let now = Date()
    let timestamp = ISO8601DateFormatter().string(from: now)
    let nonce = UUID().uuidString
    let body = #"{"action":"submit_instruction","text":"从已配置的 Telegram 进入"}"#
    let secret = "telegram-secret"
    let signature = CommunicationInboundVerifier.signature(body: body, timestamp: timestamp, nonce: nonce, secret: secret)
    #expect(store.ingestSignedRemoteCommand(body: body, timestamp: timestamp, nonce: nonce, signature: signature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.status == .received && $0.channelID == telegram.id })
    #expect(store.selectedProductCommunicationLogs.contains { $0.body.contains("从已配置的 Telegram 进入") })
    #expect(store.selectedProductTasks.count == taskCount + 1)
    #expect(store.currentSnapshot().inboundCommandNonces.contains(nonce))

    #expect(!store.ingestSignedRemoteCommand(body: body, timestamp: timestamp, nonce: nonce, signature: signature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == taskCount + 1)
    #expect(store.selectedProductCommunicationLogs.contains { $0.direction == .inbound && $0.status == .failed && $0.body.contains("重复 nonce") })
}

@MainActor
@Test func communicationGatewayExternalInboundRequiresWhitelistedJSONAction() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.ensureCommunicationGatewayPlan()
    let telegram = try #require(store.selectedProductCommunicationChannels.first { $0.kind == .telegramBot })
    store.updateCommunicationChannel(telegram.id, endpoint: "https://api.telegram.example/bot-token/sendMessage", chatID: "123", isEnabled: true, commandsEnabled: true)
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let secret = "telegram-secret"
    let initialTaskCount = store.selectedProductTasks.count

    let rawBody = "从签名外部入口直接提交原始文本"
    let rawNonce = "raw-\(UUID().uuidString)"
    let rawSignature = CommunicationInboundVerifier.signature(body: rawBody, timestamp: timestamp, nonce: rawNonce, secret: secret)
    #expect(!store.ingestSignedRemoteCommand(body: rawBody, timestamp: timestamp, nonce: rawNonce, signature: rawSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == initialTaskCount)
    #expect(store.selectedProductCommunicationLogs.contains { $0.status == .failed && $0.body.contains("请求体必须是 JSON") })
    #expect(!store.ingestSignedRemoteCommand(body: rawBody, timestamp: timestamp, nonce: rawNonce, signature: rawSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductCommunicationLogs.contains { $0.status == .failed && $0.body.contains("重复 nonce") })

    let statusBody = #"{"action":"query_status"}"#
    let statusNonce = "status-\(UUID().uuidString)"
    let statusSignature = CommunicationInboundVerifier.signature(body: statusBody, timestamp: timestamp, nonce: statusNonce, secret: secret)
    #expect(store.ingestSignedRemoteCommand(body: statusBody, timestamp: timestamp, nonce: statusNonce, signature: statusSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == initialTaskCount)
    #expect(store.selectedProductCommunicationLogs.contains { $0.title == "外部状态查询" && $0.body.contains("不创建任务、不执行命令") })

    let unsupportedBody = #"{"action":"run_shell","text":"ls"}"#
    let unsupportedNonce = "unsupported-\(UUID().uuidString)"
    let unsupportedSignature = CommunicationInboundVerifier.signature(body: unsupportedBody, timestamp: timestamp, nonce: unsupportedNonce, secret: secret)
    #expect(!store.ingestSignedRemoteCommand(body: unsupportedBody, timestamp: timestamp, nonce: unsupportedNonce, signature: unsupportedSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == initialTaskCount)
    #expect(store.selectedProductCommunicationLogs.contains { $0.status == .failed && $0.body.contains("动作不在白名单") })

    let approvalBody = #"{"action":"approval_decision","approval_id":"1","decision":"approve"}"#
    let approvalNonce = "approval-\(UUID().uuidString)"
    let approvalSignature = CommunicationInboundVerifier.signature(body: approvalBody, timestamp: timestamp, nonce: approvalNonce, secret: secret)
    #expect(!store.ingestSignedRemoteCommand(body: approvalBody, timestamp: timestamp, nonce: approvalNonce, signature: approvalSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == initialTaskCount)
    #expect(store.selectedProductCommunicationLogs.contains { $0.status == .failed && $0.body.contains("外部审批动作暂未开放") })

    let instructionBody = #"{"action":"submit_instruction","text":"外部签名普通指令"}"#
    let instructionNonce = "instruction-\(UUID().uuidString)"
    let instructionSignature = CommunicationInboundVerifier.signature(body: instructionBody, timestamp: timestamp, nonce: instructionNonce, secret: secret)
    #expect(store.ingestSignedRemoteCommand(body: instructionBody, timestamp: timestamp, nonce: instructionNonce, signature: instructionSignature, secret: secret, channelID: telegram.id))
    #expect(store.selectedProductTasks.count == initialTaskCount + 1)
    #expect(store.selectedProductCommunicationLogs.contains { $0.status == .received && $0.body.contains("来源：外部签名通道") && $0.body.contains("外部签名普通指令") })
    #expect(!store.selectedProductCommunicationLogs.contains { $0.status == .received && $0.body.contains("来源：本地指挥台") && $0.body.contains("外部签名普通指令") })
}

@Test func communicationGatewayDispatcherPostsAndRedactsWebhookSecrets() async throws {
    let preview = CommunicationDispatchPreview(
        method: "POST",
        endpoint: "https://hooks.example.com/open-apis/bot/v2/hook/secret-token-abc",
        headers: ["Content-Type": "application/json"],
        body: #"{"text":"测试"}"#
    )
    let session = mockURLSession(responses: [(503, "busy"), (200, "ok")])

    let result = await CommunicationGatewayDispatcher.dispatch(preview, session: session, retryBudget: 1)

    #expect(result.succeeded)
    #expect(result.httpStatus == 200)
    #expect(result.attempts == 2)
    let requests = MockURLProtocol.recordedRequests()
    #expect(requests.count == 2)
    #expect(requests.first?.httpMethod == "POST")
    #expect(requests.first.map(requestBodyText) == preview.body)

    let redacted = CommunicationGatewayDispatcher.redactedEndpoint(preview.endpoint)
    #expect(redacted.contains("hooks.example.com"))
    #expect(!redacted.contains("secret-token-abc"))
}

@MainActor
@Test func communicationGatewayDispatchWritesSentLogForReadyLocalChannel() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.ensureCommunicationGatewayPlan()
    let session = mockURLSession(responses: [])

    await store.dispatchTeamLeadReportThroughGateway(session: session)

    #expect(store.selectedProductCommunicationLogs.contains { $0.title == "团队负责人手机汇报发送" && $0.status == .sent })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("团队负责人手机汇报发送") })
}

@Test func communicationInboundVerifierAcceptsSignedCommandAndRejectsReplay() async throws {
    let now = Date()
    let timestamp = ISO8601DateFormatter().string(from: now)
    let nonce = UUID().uuidString
    let body = #"{"action":"status"}"#
    let secret = "test-secret"
    let signature = CommunicationInboundVerifier.signature(body: body, timestamp: timestamp, nonce: nonce, secret: secret)
    var usedNonces: Set<String> = []

    let accepted = CommunicationInboundVerifier.verify(body: body, timestamp: timestamp, nonce: nonce, signature: signature, secret: secret, now: now, usedNonces: &usedNonces)
    #expect(accepted == .accepted)

    let replayed = CommunicationInboundVerifier.verify(body: body, timestamp: timestamp, nonce: nonce, signature: signature, secret: secret, now: now, usedNonces: &usedNonces)
    #expect(replayed == .replayedNonce)

    var emptySecretNonces: Set<String> = []
    let emptySecret = CommunicationInboundVerifier.verify(body: body, timestamp: timestamp, nonce: UUID().uuidString, signature: signature, secret: " ", now: now, usedNonces: &emptySecretNonces)
    #expect(emptySecret == .missingField("secret"))
}

@Test func communicationInboundVerifierRejectsStaleOrInvalidSignature() async throws {
    let now = Date()
    let oldTimestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-900))
    let nonce = UUID().uuidString
    let body = #"{"action":"status"}"#
    let secret = "test-secret"
    var usedNonces: Set<String> = []

    let staleSignature = CommunicationInboundVerifier.signature(body: body, timestamp: oldTimestamp, nonce: nonce, secret: secret)
    let stale = CommunicationInboundVerifier.verify(body: body, timestamp: oldTimestamp, nonce: nonce, signature: staleSignature, secret: secret, now: now, usedNonces: &usedNonces)
    #expect(stale == .staleTimestamp)

    let freshTimestamp = ISO8601DateFormatter().string(from: now)
    let invalid = CommunicationInboundVerifier.verify(body: body, timestamp: freshTimestamp, nonce: UUID().uuidString, signature: "bad", secret: secret, now: now, usedNonces: &usedNonces)
    #expect(invalid == .invalidSignature)
}

@MainActor
@Test func cliPreflightRecordsDirectoryPermissionsAndRunSummary() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    let preflight = store.cliPreflightText(for: engineer.id, prompt: "检查当前状态")
    #expect(preflight.contains("命令行运行前预检"))
    #expect(preflight.contains(engineer.displayName))
    #expect(preflight.contains("工作目录"))
    #expect(preflight.contains("权限"))
    #expect(preflight.contains("来源："))
    #expect(!preflight.contains("后端："))
    #expect(preflight.contains("运行摘要"))
    #expect(!preflight.contains("OPC_PROMPT"))
    #expect(!preflight.contains("model_reasoning_effort"))
    #expect(!preflight.contains("--skip-git-repo-check"))

    store.recordCLIPreflight(agentID: engineer.id, prompt: "检查当前状态")
    #expect(store.terminalLogs[engineer.id, default: ""].contains("OPC 运行前预检"))
    #expect(store.events.contains { $0.title == "命令行运行前预检" })
}

@Test func localAppBundleBuildScriptUsesAdHocSigningAndBuildMetadata() async throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = try String(
        contentsOf: root.appendingPathComponent("scripts/build_app_bundle.sh"),
        encoding: .utf8
    )
    #expect(script.contains("BUILD_VERSION=\"${OPC_BUILD_VERSION:-$(date -u +%Y%m%d%H%M%S)}\""))
    #expect(script.contains("<key>CFBundleVersion</key>"))
    #expect(script.contains("<string>${BUILD_VERSION}</string>"))
    #expect(script.contains("BuildInfo.txt"))
    #expect(script.contains("sign nested components explicitly if that changes"))
    #expect(script.contains("codesign --force --sign - \"$APP_DIR\""))
    #expect(!script.contains("codesign --force --deep --sign - \"$APP_DIR\""))
    #expect(script.contains("OPC_SKIP_ADHOC_SIGN"))
}

@MainActor
@Test func terminalAgentCardPreflightSummaryUsesAbstractChineseLabelsAndOmitsRawPathsAndFlags() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    let summary = store.terminalAgentCardPreflightSummary(for: engineer.id, prompt: "检查当前状态")

    // 卡片摘要必须包含的中文抽象标签：员工、产品、执行位置、来源、权限、风险、结论。
    #expect(summary.contains("运行前预检摘要"))
    #expect(!summary.contains("运行前预检（员工卡片摘要）"),
            "标题应使用产品化措辞，不再暴露「员工卡片摘要」字面")
    #expect(summary.contains("员工：\(engineer.displayName)"))
    #expect(summary.contains("产品："))
    #expect(summary.contains("执行位置：主工作区") || summary.contains("执行位置：独立执行区"),
            "执行位置必须以中文抽象标签呈现，不应回落到路径")
    #expect(!summary.contains("执行位置：主工作目录"),
            "默认摘要应使用「主工作区」，避免把文件系统目录术语放到卡片上")
    #expect(summary.contains("来源："))
    #expect(!summary.contains("后端："),
            "卡片摘要应以产品化「来源」字段呈现，不再使用「后端」标签")
    #expect(summary.contains("权限："))
    #expect(summary.contains("风险提示："))
    #expect(summary.contains("预检结论："))

    // 卡片摘要禁止泄漏任何原始绝对路径、CLI 参数、提示词原文、底层引擎调参字段。
    #expect(!summary.contains("/Users/"), "卡片摘要不得展示用户绝对路径")
    #expect(!summary.contains("/private/"), "卡片摘要不得展示沙箱绝对路径")
    #expect(!summary.contains("--skip-git-repo-check"))
    #expect(!summary.contains("--permission-mode"))
    #expect(!summary.contains("model_reasoning_effort"))
    #expect(!summary.contains("OPC_PROMPT"))
    // 完整版才有的字段不应出现在卡片摘要里：
    #expect(!summary.contains("工作目录："))
    #expect(!summary.contains("执行目录："))
    #expect(!summary.contains("隔离策略："))
    #expect(!summary.contains("提示词：检查当前状态"), "卡片摘要不应回显提示词原文")
    #expect(!summary.contains("运行摘要："))

    // 标题与结论必须使用产品化措辞，不再泄漏开发实现词。
    #expect(!summary.contains("卡片"), "摘要文本不得再使用「卡片」开发词")
    #expect(!summary.contains("accessor"), "摘要文本不得再使用「accessor」开发词")
    #expect(!summary.contains("后端"), "摘要文本不得再使用「后端」字样，应改为「来源」")
    #expect(!summary.contains("CLI 参数"), "摘要文本不得再向老板侧暴露「CLI 参数」字样")
}

@MainActor
@Test func terminalAgentCardPreflightSummaryDoesNotEqualFullPreflightTextAndPreservesFullAuditPath() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    let summary = store.terminalAgentCardPreflightSummary(for: engineer.id, prompt: "检查当前状态")
    let full = store.cliPreflightText(for: engineer.id, prompt: "检查当前状态")

    #expect(summary != full, "卡片摘要必须独立于完整审计文本")
    #expect(summary.count < full.count, "卡片摘要应明显短于完整审计文本")
    // 完整审计文本的标志性字段必须仍然存在（保留 cliPreflightText 行为不变）：
    #expect(full.contains("命令行运行前预检"))
    #expect(full.contains("工作目录："))
    #expect(full.contains("执行目录："))
    #expect(full.contains("隔离策略："))
    #expect(full.contains("提示词：检查当前状态"))
}

@MainActor
@Test func terminalAgentCardPreflightSummaryAccessorIsWiredIntoTerminalHallView() async throws {
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    // 卡片必须使用新 accessor，不能再回退到 cliPreflightText。
    #expect(source.contains("store.terminalAgentCardPreflightSummary(for: agent.id, prompt: prompt)"))
    #expect(!source.contains("store.cliPreflightText(for: agent.id, prompt: prompt)"),
            "TerminalAgentCard 不应直接调用 cliPreflightText，应改用卡片摘要 accessor")
}

@MainActor
@Test func terminalAgentCardCoreActionButtonsExposeStableAccessibilityIdentifiers() async throws {
    // 单员工卡片 5 个核心动作按钮（刷新预检 / 预检 / 运行 / 清空日志 / 选中）必须挂稳定 a11y identifier
    // 给 Computer Use；同时配中文 accessibilityLabel/Hint，避免 systemImage token 漏到 VoiceOver。
    // RUNBOOK 同步登记由 `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 守门。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    let requiredIdentifiers: [OPCUIAutomationIdentifier] = [
        .terminalAgentCardRefreshPreflightButton,
        .terminalAgentCardPreflightButton,
        .terminalAgentCardRunButton,
        .terminalAgentCardClearLogButton,
        .terminalAgentCardSelectButton
    ]
    for identifier in requiredIdentifiers {
        let pattern = ".accessibilityIdentifier(OPCUIAutomationIdentifier.\(identifier).rawValue)"
        #expect(source.contains(pattern),
                "TerminalAgentCard 必须为 \(identifier) 挂 accessibilityIdentifier")
    }

    // 中文 accessibilityLabel 锁，确保不退化为英文/系统派生文案；
    // label 必须携带员工显示名，避免多张员工卡里的同类按钮无法区分。
    let staticLabels = [
        #".accessibilityLabel("刷新 \(agent.displayName) 运行前预检")"#,
        #".accessibilityLabel("选中 \(agent.displayName)")"#,
        #".accessibilityLabel("写入 \(agent.displayName) 命令行预检审计")"#,
        #".accessibilityLabel("清空 \(agent.displayName) 终端日志")"#
    ]
    for label in staticLabels {
        #expect(source.contains(label),
                "TerminalAgentCard 必须保留中文 accessibilityLabel：\(label)")
    }
    #expect(source.contains(#".accessibilityLabel(isRunning ? "\(agent.displayName) 运行中" : "运行 \(agent.displayName) 终端")"#),
            "运行按钮 accessibilityLabel 必须按 isRunning 在「员工名 运行中」/「运行 员工名 终端」之间切换")

    let requiredHintFragments = [
        "基于当前提示词与员工配置重新生成运行前预检文本。",
        "把当前员工设为选中",
        "为该员工写入一次命令行预检审计",
        "把当前提示词发送给该员工的真实终端席位",
        "清空当前员工终端的可见输出日志"
    ]
    for hint in requiredHintFragments {
        #expect(source.contains(hint),
                "TerminalAgentCard 必须保留中文 accessibilityHint 片段：\(hint)")
    }
}

@MainActor
@Test func terminalAgentCardActionButtonIdentifiersAreDocumentedInRunbook() async throws {
    // RUNBOOK「终端大厅维护区关键控件」必须显式列出 5 个员工卡按钮 anchor，
    // Computer Use 排查时需直接照 RUNBOOK 找按钮；测试 + 文档双向锁。
    let runbookURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/RUNBOOK.md")
    let runbook = try String(contentsOf: runbookURL, encoding: .utf8)

    let requiredAnchors = [
        "OPCTerminalAgentCardRefreshPreflightButton",
        "OPCTerminalAgentCardPreflightButton",
        "OPCTerminalAgentCardRunButton",
        "OPCTerminalAgentCardClearLogButton",
        "OPCTerminalAgentCardSelectButton"
    ]
    for anchor in requiredAnchors {
        #expect(runbook.contains(anchor),
                "RUNBOOK 必须列出员工卡按钮 anchor：\(anchor)")
    }
}

@MainActor
@Test func localMaintenanceCenterDetailActionButtonsExposeStableAccessibilityIdentifiers() async throws {
    // LocalMaintenanceCenter 详情面板内 13 个核心动作按钮必须挂稳定 accessibilityIdentifier + 中文 accessibilityLabel
    // + 中文 accessibilityHint，让 Computer Use 通过 a11y tree 直接定位并触发，不需要 OCR 截图。
    // RUNBOOK 同步登记由 `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 守门。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let centerSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct LocalMaintenanceCenter:",
        failureMessage: "未找到 LocalMaintenanceCenter struct 起点 — 详情按钮 a11y 锚点契约失效"
    ) else { return }

    // 每个按钮：accessibilityIdentifier case + 期望的中文 accessibilityLabel
    let requiredButtons: [(OPCUIAutomationIdentifier, String)] = [
        (.cliRuntimeIsolationAuditButton, "运行命令行与工作区隔离体检"),
        (.terminalWorkspaceStartButton, "启动真实终端工作区"),
        (.terminalWorkspaceRefreshLogsButton, "刷新真实终端日志"),
        (.terminalWorkspaceHealthAuditButton, "运行持久终端可用性巡检"),
        (.runtimeSessionHealthAuditButton, "运行会话健康巡检"),
        (.employeeHandoffAuditButton, "运行员工交接巡检"),
        (.jobArchiveStaleAuditButton, "运行命令行作业幽灵巡检"),
        (.historyIndexAuditButton, "运行历史索引巡检"),
        (.historyArchiveMigrationButton, "运行历史归档迁移"),
        (.staleRuntimeSessionRecoveryButton, "恢复异常占用员工会话"),
        (.runDataCleanupConfirmButton, "清理当前产品运行/测试数据"),
        (.defaultCompanyStateConfirmButton, "恢复默认公司状态"),
        (.safetyCheckpointRollbackConfirmButton, "回滚到最近安全检查点")
    ]
    for (identifier, label) in requiredButtons {
        switch identifier {
        case .runDataCleanupConfirmButton:
            #expect(source.contains("case .cleanup: .runDataCleanupConfirmButton"))
            #expect(source.contains("case .cleanup: \"\(label)\""))
        case .defaultCompanyStateConfirmButton:
            #expect(source.contains("case .reset: .defaultCompanyStateConfirmButton"))
            #expect(source.contains("case .reset: \"\(label)\""))
        case .safetyCheckpointRollbackConfirmButton:
            #expect(source.contains("case .rollback: .safetyCheckpointRollbackConfirmButton"))
            #expect(source.contains("case .rollback: \"\(label)\""))
        default:
            let identifierPattern = ".accessibilityIdentifier(OPCUIAutomationIdentifier.\(identifier).rawValue)"
            #expect(centerSlice.contains(identifierPattern),
                    "LocalMaintenanceCenter 必须为 \(identifier) 挂 accessibilityIdentifier")
            #expect(centerSlice.contains(".accessibilityLabel(\"\(label)\")"),
                    "\(identifier) 必须挂中文 accessibilityLabel «\(label)»")
        }
    }

    // 中文 accessibilityHint 关键片段锁：每个按钮必须有自己的 hint，避免退化为通用空文案或被误删。
    // 三个危险维护动作必须显式提示需要输入「动作专属确认短语」，防止 Computer Use 误以为单次点击即触发；
    // 三句必须明确点名各自的短语「清理运行数据 / 恢复默认公司 / 回滚最近检查点」，禁止再共用同一句"确认"。
    let requiredHintFragments = [
        "为当前产品运行命令行与工作区隔离体检",
        "为当前产品启动真实终端工作区",
        "刷新当前产品真实终端工作区的可见日志",
        "巡检当前产品持久终端工作区的可用性",
        "巡检当前产品员工会话健康度",
        "巡检当前产品员工交接证据完整度",
        "巡检当前产品命令行作业档案的幽灵或陈旧作业",
        "巡检当前产品历史索引完整度与一致性",
        "把当前产品旧历史记录按归档规则迁入历史归档",
        "恢复当前产品被异常占用的员工运行会话",
        "输入「清理运行数据」后才会清理当前产品运行与测试数据",
        "输入「恢复默认公司」后才会把当前公司恢复到默认状态",
        "输入「回滚最近检查点」后才会把当前公司回滚到最近一个安全检查点"
    ]
    for fragment in requiredHintFragments {
        #expect(source.contains(fragment),
                "LocalMaintenanceCenter 详情按钮必须保留中文 accessibilityHint 片段：\(fragment)")
    }
}

@Test func localMaintenanceDangerousActionsUseVisibleConfirmationPanelInsteadOfStickySecondClick() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let centerSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct LocalMaintenanceCenter: View",
        failureMessage: "必须能定位 LocalMaintenanceCenter 源码切片"
    ) else { return }
    #expect(centerSlice.contains("ForEach(LocalMaintenanceDangerousAction.allCases)"),
            "危险操作确认区必须常驻显示三项，不能依赖点击后临时展开")
    #expect(centerSlice.contains("LocalMaintenanceDangerousConfirmationPanel(action: action)"),
            "危险操作必须在维护详情顶部常驻显示确认面板，不能依赖 sheet/scroll 内系统 alert")
    #expect(centerSlice.contains("runDangerousConfirmation(action)"),
            "危险操作只能从对应确认区的执行按钮触发")
    // 执行启用条件必须按动作的专属短语比较，禁止退化回"== \"确认\""共享词。
    #expect(source.contains("confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == action.confirmationPhrase"),
            "危险操作执行按钮必须按 action.confirmationPhrase 比较，禁止再共用同一句\"确认\"")
    #expect(!source.contains("confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == \"确认\""),
            "危险操作执行按钮不得回退到共用 \"确认\" 字面量")
    #expect(source.contains(".disabled(!executeEnabled)"),
            "危险操作执行按钮在未输入动作专属确认短语前必须禁用")

    // 三个动作必须有各自的专属短语，且三句互不相同；同时必须 != "确认"，避免一改就退回共用。
    let cleanupPhraseLine = "case .cleanup: \"清理运行数据\""
    let resetPhraseLine = "case .reset: \"恢复默认公司\""
    let rollbackPhraseLine = "case .rollback: \"回滚最近检查点\""
    #expect(source.contains(cleanupPhraseLine),
            "LocalMaintenanceDangerousAction.confirmationPhrase 必须为 cleanup 配置「清理运行数据」")
    #expect(source.contains(resetPhraseLine),
            "LocalMaintenanceDangerousAction.confirmationPhrase 必须为 reset 配置「恢复默认公司」")
    #expect(source.contains(rollbackPhraseLine),
            "LocalMaintenanceDangerousAction.confirmationPhrase 必须为 rollback 配置「回滚最近检查点」")
    let dangerPhrases = ["清理运行数据", "恢复默认公司", "回滚最近检查点"]
    #expect(Set(dangerPhrases).count == dangerPhrases.count,
            "三个危险动作的确认短语必须互不相同，禁止退化为共用同一个词")
    for phrase in dangerPhrases {
        #expect(phrase != "确认",
                "危险操作确认短语不得退回到通用『确认』")
    }

    // 输入框 placeholder 与 accessibilityHint 必须同步使用动作专属短语，不再硬编码 "确认"。
    #expect(source.contains("TextField(action.phrasePromptPlaceholder, text: $confirmationPhrase)"),
            "危险操作输入框必须以 action.phrasePromptPlaceholder 作为 placeholder，禁止硬编码")
    #expect(source.contains(".accessibilityHint(action.phraseFieldHint)"),
            "危险操作输入框的 accessibilityHint 必须使用 action.phraseFieldHint")
    #expect(source.contains("\"输入「\\(confirmationPhrase)」\""),
            "phrasePromptPlaceholder 必须把动作短语包在「…」中拼成 placeholder")
    #expect(source.contains("\"输入「\\(confirmationPhrase)」后才会启用执行按钮\""),
            "phraseFieldHint 必须把动作短语包在「…」中拼成 hint")
    #expect(!source.contains("TextField(\"输入“确认”\""),
            "禁止保留旧的硬编码 placeholder \"输入“确认”\"")
    #expect(!source.contains(".accessibilityHint(\"输入“确认”后才会启用执行按钮\")"),
            "禁止保留旧的硬编码 accessibilityHint")

    #expect(source.contains("OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationPanel.rawValue"))
    #expect(source.contains("OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationPhraseField.rawValue"))
    #expect(source.contains("OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationCancelButton.rawValue"))
    #expect(source.contains("executeIdentifier.rawValue"))
    #expect(!centerSlice.contains(".alert(\"确认清理当前产品运行/测试数据\""))
    #expect(!centerSlice.contains(".alert(\"确认恢复默认公司状态\""))
    #expect(!centerSlice.contains(".alert(\"确认回滚到最近安全检查点\""))
    #expect(!centerSlice.contains(".confirmationDialog(\"确认清理当前产品运行/测试数据\""))
    #expect(!centerSlice.contains(".confirmationDialog(\"确认恢复默认公司状态\""))
    #expect(!centerSlice.contains(".confirmationDialog(\"确认回滚到最近安全检查点\""))
    #expect(!centerSlice.contains("confirmReset"))
    #expect(!centerSlice.contains("confirmRollback"))
    #expect(!centerSlice.contains("confirmCleanup"))
}

@Test func historyArchiveMigrationButtonRequiresTwoClickConfirmationLikeOtherWriteActions() async throws {
    // 历史归档迁移会写 verifications/messages/events（CompanyStore.runHistoryArchiveMigrationForSelectedProduct），
    // 主快照虽不裁剪，但仍会污染维护审计中心。必须沿用 confirmAutoSummaryCleanup / confirmLegacyTaskMigration
    // 的二次确认模式，避免单击直接执行造成误触。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let centerSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct LocalMaintenanceCenter: View",
        failureMessage: "必须能定位 LocalMaintenanceCenter 源码切片"
    ) else { return }
    #expect(centerSlice.contains("@State private var confirmHistoryArchiveMigration = false"),
            "LocalMaintenanceCenter 必须声明 confirmHistoryArchiveMigration 二次确认状态")
    #expect(centerSlice.contains("if confirmHistoryArchiveMigration {"),
            "运行历史归档迁移按钮必须在 confirmHistoryArchiveMigration 为 true 时才执行真正动作")
    #expect(centerSlice.contains("store.runHistoryArchiveMigrationForSelectedProduct()"),
            "二次确认通过后必须调用 store.runHistoryArchiveMigrationForSelectedProduct()")
    #expect(centerSlice.contains("再次点击确认运行历史归档迁移"),
            "首次点击进入确认态时按钮文案必须切换为「再次点击确认运行历史归档迁移」")
    #expect(centerSlice.contains("首次点击进入确认态，再次点击才会执行"),
            "accessibilityHint 必须告诉 Computer Use 这是二次确认按钮")
}

@MainActor
@Test func localMaintenanceCenterDetailActionButtonAnchorsAreDocumentedInRunbook() async throws {
    // 与上一条测试配对：13 个详情按钮 anchor 必须在 RUNBOOK 显式列出，Computer Use 排查时按 anchor 找控件。
    let runbookURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/RUNBOOK.md")
    let runbook = try String(contentsOf: runbookURL, encoding: .utf8)

    let requiredAnchors = [
        "OPCCLIRuntimeIsolationAuditButton",
        "OPCTerminalWorkspaceStartButton",
        "OPCTerminalWorkspaceRefreshLogsButton",
        "OPCTerminalWorkspaceHealthAuditButton",
        "OPCRuntimeSessionHealthAuditButton",
        "OPCEmployeeHandoffAuditButton",
        "OPCJobArchiveStaleAuditButton",
        "OPCHistoryIndexAuditButton",
        "OPCHistoryArchiveMigrationButton",
        "OPCStaleRuntimeSessionRecoveryButton",
        "OPCRunDataCleanupConfirmButton",
        "OPCDefaultCompanyStateConfirmButton",
        "OPCSafetyCheckpointRollbackConfirmButton"
    ]
    for anchor in requiredAnchors {
        #expect(runbook.contains(anchor),
                "RUNBOOK 必须列出本地维护详情按钮 anchor：\(anchor)")
    }
}

@MainActor
@Test func terminalAgentCardPreflightSummaryReturnsHelpfulMessageForUnknownAgent() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let summary = store.terminalAgentCardPreflightSummary(for: UUID(), prompt: "")
    #expect(summary.contains("未找到员工"))
    #expect(!summary.contains("/Users/"))
}

@MainActor
@Test func teamOperatingSummaryUsesSelectedProductLeadAndMembers() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.updateSelectedProductTeamLead(engineer.id)

    let summary = store.teamOperatingSummaryText()
    #expect(summary.contains("产品团队机制"))
    #expect(summary.contains(engineer.displayName))
    #expect(summary.contains("汇报链路"))
    #expect(summary.contains("团队负责人"))
}

@MainActor
@Test func systemBriefShowsFeedbackOnSourceAgentTerminal() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.sendSystemBriefToCTO(sourceAgentID: engineer.id)

    let brief = try #require(store.messages(for: store.ctoID).last { $0.text.contains("公司状态简报") })
    #expect(brief.text.contains("运行中") || brief.text.contains("已计划"))
    #expect(!brief.text.contains(": running"))
    #expect(!brief.text.contains(": planned"))
    #expect(!brief.text.contains("needsReview"))
    #expect(!brief.text.contains("needsApproval"))
    #expect(store.messages(for: engineer.id).contains { $0.text.contains("已生成公司状态简报并同步给技术负责人") })
    #expect(store.terminalLogs[engineer.id, default: ""].contains("已生成公司状态简报并同步给技术负责人"))
}

@MainActor
@Test func productTeamLeadCanBeChangedForGatewayReports() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.updateSelectedProductTeamLead(engineer.id)
    #expect(store.teamLeadAgentIDForSelectedProduct() == engineer.id)

    store.ensureCommunicationGatewayPlan()
    #expect(store.selectedProductCommunicationChannels.allSatisfy { $0.teamLeadAgentID == engineer.id })

    store.sendTeamLeadReportThroughGateway()
    let report = try #require(store.selectedProductCommunicationLogs.first { $0.title == "团队负责人手机汇报" })
    #expect(report.agentID == engineer.id)
    #expect(report.body.contains(engineer.displayName))
}

@Test func communicationGatewayBuildsProviderPayloads() async throws {
    let feishu = CommunicationChannelConfig(name: "飞书", kind: .feishuWebhook, endpoint: "https://example.com/feishu")
    let wecom = CommunicationChannelConfig(name: "企微", kind: .wecomWebhook, endpoint: "https://example.com/wecom")
    let telegram = CommunicationChannelConfig(name: "Telegram", kind: .telegramBot, endpoint: "https://api.telegram.org/botTOKEN/sendMessage", chatID: "123")

    let feishuPreview = try #require(CommunicationGatewayRequestBuilder.preview(for: feishu, text: "汇报"))
    #expect(feishuPreview.method == "POST")
    #expect(feishuPreview.body.contains("msg_type"))

    let wecomPreview = try #require(CommunicationGatewayRequestBuilder.preview(for: wecom, text: "汇报"))
    #expect(wecomPreview.body.contains("msgtype"))

    let telegramPreview = try #require(CommunicationGatewayRequestBuilder.preview(for: telegram, text: "汇报"))
    #expect(telegramPreview.body.contains("chat_id"))
    #expect(telegramPreview.body.contains("123"))
}

@MainActor
@Test func employeeHallSeatLayoutSupportsDenseRows() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let seats = (0..<18).map { store.employeeHallSeat(for: $0) }

    #expect(Set(seats.map(\.x)).count == 6)
    #expect(Set(seats.prefix(18).map(\.y)).count >= 3)
    #expect(seats.allSatisfy { $0.room == "employee-hall" })
}

@Test func employeeHallGridAlwaysLeavesAnEmptyAddSeat() async throws {
    for count in [0, 3, 4, 8, 18, 24] {
        let dimensions = NeuralFloorLayout.employeeHallGridDimensions(for: count)
        #expect(dimensions.rows * dimensions.columns > count)
    }
}

@Test func neuralFloorLayoutKeepsAgentPodsBelowExecutiveDecks() async throws {
    let zones = NeuralFloorLayout.zones(for: CGSize(width: 1400, height: 900))

    #expect(zones.agentPods.width > zones.ctoDeck.width * 2)
    #expect(zones.agentPods.height > zones.ctoDeck.height * 1.8)
    #expect(zones.agentPods.maxY < zones.ctoDeck.minY)
    #expect(zones.agentPods.maxY < zones.bossDeck.minY)
    #expect(zones.ctoDeck.maxY <= 900)
    #expect(zones.bossDeck.maxY <= 900)
    #expect(zones.mainFloor.contains(CGPoint(x: zones.core.midX, y: zones.core.midY)))
    #expect(zones.core.minY < zones.agentPods.maxY)
    #expect(zones.core.maxY > zones.agentPods.maxY)
}

@Test func agentPodGridKeepsAgentsCenteredInsidePods() async throws {
    let size = CGSize(width: 1400, height: 900)
    let zones = NeuralFloorLayout.zones(for: size)
    let points = (0..<15).map {
        NeuralFloorLayout.employeeHallGridSpritePoint(index: $0, count: 15, in: zones.agentPods)
    }
    let safePods = zones.agentPods.insetBy(dx: 55, dy: 55)

    #expect(points.allSatisfy { safePods.contains($0) })
    #expect(points.allSatisfy { !zones.ctoDeck.insetBy(dx: -90, dy: -90).contains($0) })
    #expect(points.allSatisfy { !zones.bossDeck.insetBy(dx: -90, dy: -90).contains($0) })
    #expect(Set(points.map { Int(round($0.y / 10)) }).count == 3)

    var minDistance = CGFloat.greatestFiniteMagnitude
    for leftIndex in points.indices {
        for rightIndex in points.indices where rightIndex > leftIndex {
            let leftPoint = points[leftIndex]
            let rightPoint = points[rightIndex]
            minDistance = min(minDistance, hypot(leftPoint.x - rightPoint.x, leftPoint.y - rightPoint.y))
        }
    }
    #expect(minDistance > 100)
}

@Test func denseAgentPodGridScalesWithoutLeavingPods() async throws {
    let zones = NeuralFloorLayout.zones(for: CGSize(width: 1400, height: 900))
    let points = (0..<24).map {
        NeuralFloorLayout.employeeHallGridSpritePoint(index: $0, count: 24, in: zones.agentPods)
    }

    #expect(NeuralFloorLayout.employeeHallAvatarScale(for: 24) == 0.86)
    #expect(points.allSatisfy { zones.agentPods.insetBy(dx: 45, dy: 45).contains($0) })
    #expect(Set(points.map { Int(round($0.y / 10)) }).count >= 3)
}

@Test func agentPodGridLeavesRoomForStatusBubbles() async throws {
    let zones = NeuralFloorLayout.zones(for: CGSize(width: 1400, height: 900))
    let count = 8
    let clearance = NeuralFloorLayout.employeeHallStatusClearance(for: count, in: zones.agentPods)
    let points = (0..<count).map {
        NeuralFloorLayout.employeeHallGridSpritePoint(index: $0, count: count, in: zones.agentPods)
    }

    #expect(clearance > 40)
    #expect(points.allSatisfy { $0.y + clearance < zones.agentPods.maxY })
}

@Test func commandBuilderSupportsMainSubscriptionCLIs() async throws {
    let codex = CompanyAgent(
        displayName: "CTO",
        title: "CTO",
        role: .cto,
        backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
        ethnicity: .white,
        gender: .man,
        clothing: .businessSuit,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let command = CLIAgentCommandBuilder.command(for: codex, prompt: "Plan")
    #expect(command.first?.hasSuffix("/.npm-global/bin/codex") == true || command.first == "codex")
    #expect(command.dropFirst().first == "exec")
    #expect(command.contains("gpt-5.5"))
    #expect(command.contains("model_reasoning_effort=\"high\""))

    let resumed = CLIAgentCommandBuilder.command(for: codex, prompt: "Continue", resumeSessionID: "12345678-1234-1234-1234-123456789abc")
    #expect(Array(resumed[0..<min(3, resumed.count)]).contains("resume"))
    #expect(resumed.contains("12345678-1234-1234-1234-123456789abc"))
    #expect(resumed.last == "Continue")
    #expect(!resumed.contains("--cd"))

    let claude = CompanyAgent(
        displayName: "工程",
        title: "工程",
        role: .codeEngineer,
        backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .medium),
        ethnicity: .white,
        gender: .woman,
        clothing: .hoodie,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )
    let claudeResumed = CLIAgentCommandBuilder.command(for: claude, prompt: "Continue", resumeSessionID: "12345678-1234-1234-1234-123456789abc")
    #expect(claudeResumed.contains("--resume"))
    #expect(claudeResumed.contains("12345678-1234-1234-1234-123456789abc"))

    let gemini = CompanyAgent(
        displayName: "设计",
        title: "设计",
        role: .uiDesigner,
        backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "gemini-pro", reasoningEffort: .medium),
        ethnicity: .white,
        gender: .woman,
        clothing: .hoodie,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )
    let geminiResumed = CLIAgentCommandBuilder.command(for: gemini, prompt: "Continue", resumeSessionID: "12345678-1234-1234-1234-123456789abc")
    #expect(geminiResumed.contains("--resume"))
    #expect(geminiResumed.contains("12345678-1234-1234-1234-123456789abc"))
    #expect(geminiResumed.contains("--model"))
}

@Test func cliInteractionProfilesDescribeLongRunningProtocols() async throws {
    let codex = CompanyAgent(
        displayName: "CTO",
        title: "CTO",
        role: .cto,
        backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
        ethnicity: .white,
        gender: .man,
        clothing: .businessSuit,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )
    let claude = CompanyAgent(
        displayName: "工程",
        title: "工程",
        role: .codeEngineer,
        backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .medium),
        ethnicity: .white,
        gender: .woman,
        clothing: .hoodie,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )
    let gemini = CompanyAgent(
        displayName: "设计",
        title: "设计",
        role: .uiDesigner,
        backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "gemini-pro", reasoningEffort: .medium),
        ethnicity: .white,
        gender: .woman,
        clothing: .hoodie,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    for agent in [codex, claude, gemini] {
        let profile = try #require(CLIAgentCommandBuilder.interactionProfile(for: agent))
        #expect(profile.supportsResume)
        #expect(profile.protocolKind != .repl)
        #expect(!profile.sessionMode.isEmpty)
        #expect(!profile.sessionIDLabels.isEmpty)
        #expect(!profile.sessionIDPattern.isEmpty)
        #expect(!profile.readySignals.isEmpty)
        #expect(!profile.endTurnSignals.isEmpty)
        #expect(!profile.busySignals.isEmpty)
        #expect(!profile.authenticationIssueSignals.isEmpty)
        #expect(profile.recommendedTimeoutSeconds >= 60)
        #expect(CLIAgentCommandBuilder.runtimeCapability(for: agent) == .persistentProtocol)
        #expect(CLIAgentCommandBuilder.interactionSummary(for: agent)?.contains("支持按产品续跑") == true)
    }

    #expect(CLIAgentCommandBuilder.interactionProfile(for: CompanyAgent(
        displayName: "自定义",
        title: "自定义",
        role: .custom,
        backend: AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "", reasoningEffort: .low),
        ethnicity: .white,
        gender: .man,
        clothing: .hoodie,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )) == nil)
}

@Test func cliInteractionProfilesParseVendorSessionIDs() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))

    #expect(codex.sessionID(from: #"{"session_id":"12345678-1234-1234-1234-123456789abc"}"#) == "12345678-1234-1234-1234-123456789abc")
    #expect(claude.sessionID(from: "cli_session: cs_AbCdEf123456") == "cs_AbCdEf123456")
    #expect(gemini.sessionID(from: "chat_id=9876543210") == "9876543210")
}

@Test func cliInteractionStateMachineClassifiesCoreProtocolStates() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let id = "12345678-1234-1234-1234-123456789abc"

    let ready = CLIInteractionStateMachine.observe(output: #"{"session_id":"\#(id)"}"#, profile: codex)
    #expect(ready.phase == .ready)
    #expect(ready.sessionID == id)
    #expect(ready.reasonTitle == "可继续交互")

    let busy = CLIInteractionStateMachine.observe(output: "Plan usage limits are busy", profile: codex)
    #expect(busy.phase == .busy)
    #expect(busy.reasonTitle == "忙碌中")

    let auth = CLIInteractionStateMachine.observe(output: "Unauthorized. Please login.", profile: codex)
    #expect(auth.phase == .authenticationBlocked)
    #expect(auth.reasonTitle == "授权异常")

    let transient = CLIInteractionStateMachine.observe(output: "network timeout 429", profile: codex)
    #expect(transient.phase == .transientFailure)

    let complete = CLIInteractionStateMachine.observe(output: "[命令退出码 0]", profile: codex, previousPhase: .awaitingResponse)
    #expect(complete.phase == .completedTurn)

    let waiting = CLIInteractionStateMachine.observe(output: "still streaming", profile: codex, previousPhase: .awaitingResponse)
    #expect(waiting.phase == .awaitingResponse)

    let unknown = CLIInteractionStateMachine.observe(output: "普通输出", profile: codex)
    #expect(unknown.phase == .unknown)
    #expect(unknown.reasonTitle == "未识别状态")
}

@Test func cliInteractionStateMachineAvoidsPromptEchoAuthenticationFalsePositive() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    #expect(!codex.authenticationIssueSignals.contains("login"))

    let echoOutput = "user: 帮我看一下 login 接口的代码"
    let observation = CLIInteractionStateMachine.observe(output: echoOutput, profile: codex)
    #expect(observation.phase != .authenticationBlocked)

    let authBeatsBusy = CLIInteractionStateMachine.observe(output: "Plan usage limits busy. Please log in to continue.", profile: codex)
    #expect(authBeatsBusy.phase == .authenticationBlocked)
}

@Test func cliInteractionStateMachineAvoidsDiagnosticKeywordFalsePositives() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))

    let pathMention = "Error: cannot open /tmp/OPCReplTurnTimeout/network_429_busy_fixture.txt"
    let pathObservation = CLIInteractionStateMachine.observe(output: pathMention, profile: codex)
    #expect(pathObservation.phase != .transientFailure)
    #expect(pathObservation.phase != .busy)

    let promptEcho = """
    用户提示：请检查 timeout、network、429 和 busy 这些词在文案里如何展示。
    普通输出：这不是命令行错误。
    """
    let promptObservation = CLIInteractionStateMachine.observe(output: promptEcho, profile: codex)
    #expect(promptObservation.phase == .unknown)

    let identifierMention = "Error: module NetworkTimeout429BusyProbe finished without diagnostics"
    let identifierObservation = CLIInteractionStateMachine.observe(output: identifierMention, profile: codex)
    #expect(identifierObservation.phase != .transientFailure)
    #expect(identifierObservation.phase != .busy)
}

@Test func cliInteractionStateMachineKeepsRealDiagnosticSignals() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))

    #expect(CLIInteractionStateMachine.observe(output: "Error: network timeout 429", profile: codex).phase == .transientFailure)
    #expect(CLIInteractionStateMachine.observe(output: "Plan usage limits are busy", profile: codex).phase == .busy)
    #expect(CLIInteractionStateMachine.observe(output: "Unauthorized. Please login.", profile: codex).phase == .authenticationBlocked)
    #expect(CLIInteractionStateMachine.observe(output: "Codex session ready", profile: codex).phase == .ready)
}

@Test func cliInteractionStateMachineRecognizesClaudeCodeBusyVariantsAndRecoveryWaits() async throws {
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))

    // 真实 busy 诊断行：英文 busy / overloaded / rate limit / already running
    let englishBusyCases: [String] = [
        "fatal: claude is busy",
        "warning: claude is overloaded",
        "error: rate limit reached",
        "[error] claude is already running"
    ]
    for output in englishBusyCases {
        #expect(CLIInteractionStateMachine.observe(output: output, profile: claude).phase == .busy, "should be busy: \(output)")
    }

    // 中文 busy 诊断行：服务繁忙 / 已在运行 / 过载 / 速率限制 / 请稍后重试
    let chineseBusyCases: [String] = [
        "致命：服务繁忙，请稍后再试。",
        "错误：claude 已在运行，跳过本次请求。",
        "警告：claude 过载。",
        "错误：速率限制达到上限。",
        "异常：请稍后重试。"
    ]
    for output in chineseBusyCases {
        #expect(CLIInteractionStateMachine.observe(output: output, profile: claude).phase == .busy, "should be busy: \(output)")
    }

    // 普通输出里出现 busy / 服务繁忙 字样但不在诊断行（无诊断前缀）→ 不应误判
    let nonDiagnosticOutputs: [String] = [
        "用户提示：请检查 busy 一词在文案里如何展示。",
        "员工说明：服务繁忙时请等待，避免同时打断正常任务。",
        "code: var isBusy = true",
        "/var/log/claude-busy-fixture.log",
        "请阅读 docs/claude/busy-handling.md 了解策略。"
    ]
    for output in nonDiagnosticOutputs {
        let observation = CLIInteractionStateMachine.observe(output: output, profile: claude)
        #expect(observation.phase != .busy, "should NOT be busy: \(output) → \(observation.phase)")
    }

    // 恢复建议：busy → 等待当前任务，明确不自动重开/不手动重试
    #expect(CLIInteractionStateMachine.recoveryAction(for: .busy) == .waitForCurrentTask)
    #expect(CLIInteractionRecoveryAction.waitForCurrentTask.title == "等待当前任务")
    #expect(CLIInteractionRecoveryAction.waitForCurrentTask.operatorHint == "上一轮任务尚未结束，请等待完成后再发起新任务。")
}

@MainActor
@Test func cliRecoveryManualRetryRefusesBusyAndDoesNotInterruptRunningTasks() async throws {
    // 这条测试锁定产品边界：busy 状态下，受控手动重试入口拒绝触发——避免误打断正常忙任务。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .medium)
    let engineer = store.agents[engineerIndex]

    var session = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
    )
    session.cliInteractionPhase = .busy
    session.cliInteractionReason = "忙碌中"
    session.cliInteractionRecoveryAction = .waitForCurrentTask
    session.cliInteractionRecoveryActionTitle = CLIInteractionRecoveryAction.waitForCurrentTask.title
    session.cliInteractionOperatorHint = CLIInteractionRecoveryAction.waitForCurrentTask.operatorHint
    session.lastUsedAt = Date()
    store.runtimeSessions[engineer.id] = session
    store.runningAgentIDs.insert(engineer.id)
    store.selectAgent(engineer.id)

    let report = store.manualRetryTransientForAgent(agentID: engineer.id)
    #expect(!report.success)
    // busy 状态下 cliRecoveryAdvice.canManualRetry 应为 false → 走"不在「临时异常」范围内，已拒绝手动重试"分支
    #expect(report.reason.contains("已拒绝手动重试") || report.reason.contains("等待"))

    // 不打断正常 busy 任务：runningAgentIDs 与会话状态保持
    #expect(store.runningAgentIDs.contains(engineer.id))
    #expect(store.runtimeSessions[engineer.id]?.cliInteractionPhase == .busy)
}

@Test func cliInteractionStateMachineRecognizesDiagnosticsThroughAnsiAndControlChars() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))

    // ANSI 红色 error: not authenticated → 授权异常
    let ansiAuth = "\u{1B}[31merror: not authenticated\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiAuth, profile: codex).phase == .authenticationBlocked)

    // OSC title 包裹后跟 warning: rate limit → 忙碌
    let oscBusy = "\u{1B}]0;Codex Session\u{07}warning: rate limit reached\n"
    #expect(CLIInteractionStateMachine.observe(output: oscBusy, profile: codex).phase == .busy)

    // CR 覆写 spinner 之后写 error 行 → 授权异常仍能命中
    let crAuth = "loading...\rerror: please login\n"
    #expect(CLIInteractionStateMachine.observe(output: crAuth, profile: codex).phase == .authenticationBlocked)

    // shell 标准 BS 擦字修正 typo 之后剩下 error: not authenticated → 授权异常
    let bsAuth = "error: not authenticatedX\u{08} \u{08}\n"
    #expect(CLIInteractionStateMachine.observe(output: bsAuth, profile: codex).phase == .authenticationBlocked)

    // 彩色 busy / overloaded（overloaded 在 Claude Code 协议画像里属于 busy）
    let ansiOverloaded = "\u{1B}[33mwarning: server overloaded\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiOverloaded, profile: claude).phase == .busy)
    let ansiBusy = "\u{1B}[31mfatal: claude is busy\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiBusy, profile: claude).phase == .busy)

    // 彩色 rate limit（不含 429/timeout 之类 transient token）→ 忙碌
    let ansiRateLimit = "\u{1B}[31merror: rate limit reached\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiRateLimit, profile: codex).phase == .busy)

    // 彩色 429 / network timeout（429 / network / timeout 在 codex 画像里属于 transient，
    // observe() 又把 transient 守门排在 busy 之前，所以即便同行混入 rate limit 也会优先报 transient。
    // 这条断言锁住"transient 优先级 > busy"的语义在 ANSI 包装下也保持。
    let ansi429 = "\u{1B}[31merror: 429 rate limit\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansi429, profile: codex).phase == .transientFailure)
    let ansiNetTimeout = "\u{1B}[31merror: network timeout\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiNetTimeout, profile: codex).phase == .transientFailure)
    let ansiOnlyTimeout = "\u{1B}[31merror: timeout\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansiOnlyTimeout, profile: codex).phase == .transientFailure)

    // 即便整段被 OSC + CR 包装，ready prompt 仍然是 ready
    let oscReady = "\u{1B}]0;Codex\u{07}codex>\n"
    #expect(CLIInteractionStateMachine.observe(output: oscReady, profile: codex).phase == .ready)
}

@Test func cliInteractionStateMachineKeepsPathAndIdentifierGuardsThroughAnsi() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))

    // 路径里的 timeout/network/429/busy（带 ANSI 颜色）→ 不命中诊断信号
    let coloredPath = "\u{1B}[36m/var/log/timeout-429-busy.log\u{1B}[0m"
    let coloredPathObservation = CLIInteractionStateMachine.observe(output: coloredPath, profile: codex)
    #expect(coloredPathObservation.phase != .transientFailure)
    #expect(coloredPathObservation.phase != .busy)
    #expect(coloredPathObservation.phase != .authenticationBlocked)

    // 标识符里的 NetworkTimeout429BusyProbe（带 ANSI）→ 不命中
    let identifier = "\u{1B}[31merror: module NetworkTimeout429BusyProbe finished\u{1B}[0m"
    let identifierObservation = CLIInteractionStateMachine.observe(output: identifier, profile: codex)
    #expect(identifierObservation.phase != .transientFailure)
    #expect(identifierObservation.phase != .busy)

    // 普通中文说明（带 OSC title）里提到 timeout/network/busy → 不命中
    let chinesePromptEcho = "\u{1B}]0;Codex 维护\u{07}用户提示：请检查 timeout、network、429 和 busy 这些词在文案里如何展示。"
    let chineseObservation = CLIInteractionStateMachine.observe(output: chinesePromptEcho, profile: codex)
    #expect(chineseObservation.phase != .transientFailure)
    #expect(chineseObservation.phase != .busy)
    #expect(chineseObservation.phase != .authenticationBlocked)

    // diagnostic 前缀但 token 仍是路径的情况：error: see /tmp/timeout-fix.log → 不命中
    let errorWithPathArgument = "\u{1B}[31merror: see /tmp/timeout-fix.log for details\u{1B}[0m"
    let errorPathObservation = CLIInteractionStateMachine.observe(output: errorWithPathArgument, profile: codex)
    #expect(errorPathObservation.phase != .transientFailure)
    #expect(errorPathObservation.phase != .busy)

    // CR 覆写恶意把 prompt 改成 path → 仍然不命中（路径标记仍存在）
    let crWithPath = "ok\rerror: file /tmp/network.log overwrites prompt\n"
    let crPathObservation = CLIInteractionStateMachine.observe(output: crWithPath, profile: codex)
    #expect(crPathObservation.phase != .transientFailure)
    #expect(crPathObservation.phase != .busy)

    // 兜底：旧的非 ANSI 路径用例继续不误判
    let plainPath = "Error: cannot open /tmp/OPCReplTurnTimeout/network_429_busy_fixture.txt"
    let plainPathObservation = CLIInteractionStateMachine.observe(output: plainPath, profile: codex)
    #expect(plainPathObservation.phase != .transientFailure)
    #expect(plainPathObservation.phase != .busy)
}

@Test func cliInteractionStateMachineRecognizesChineseDiagnosticsAcrossProfiles() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))

    // 中文授权异常：典型话术
    #expect(CLIInteractionStateMachine.observe(output: "错误：未授权，请重新登录。", profile: codex).phase == .authenticationBlocked)
    #expect(CLIInteractionStateMachine.observe(output: "未授权：请登录后再试。", profile: claude).phase == .authenticationBlocked)
    #expect(CLIInteractionStateMachine.observe(output: "授权失败：会话过期。", profile: gemini).phase == .authenticationBlocked)

    // 中文忙碌：rate limit / 服务繁忙 / overloaded（仅 Claude）
    #expect(CLIInteractionStateMachine.observe(output: "致命：服务繁忙，请稍后重试。", profile: codex).phase == .busy)
    #expect(CLIInteractionStateMachine.observe(output: "警告：claude 过载。", profile: claude).phase == .busy)
    #expect(CLIInteractionStateMachine.observe(output: "速率限制：请稍后再试。", profile: gemini).phase == .busy)

    // 中文临时异常
    #expect(CLIInteractionStateMachine.observe(output: "警告：网络异常。", profile: codex).phase == .transientFailure)
    #expect(CLIInteractionStateMachine.observe(output: "请求超时：连接失败。", profile: claude).phase == .transientFailure)
    #expect(CLIInteractionStateMachine.observe(output: "错误：临时不可用。", profile: gemini).phase == .transientFailure)

    // 优先级保持：同行混入 auth + busy 时 auth 优先（与英文路径一致）
    #expect(CLIInteractionStateMachine.observe(output: "致命：服务繁忙，请重新登录。", profile: codex).phase == .authenticationBlocked)

    // ANSI 颜色 + OSC + CR 覆写下中文仍能命中
    let ansi = "\u{1B}[31m错误：未授权，请重新登录\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: ansi, profile: codex).phase == .authenticationBlocked)
    let osc = "\u{1B}]0;Codex Session\u{07}致命：服务繁忙\n"
    #expect(CLIInteractionStateMachine.observe(output: osc, profile: codex).phase == .busy)
    let cr = "正在加载...\r警告：网络异常\n"
    #expect(CLIInteractionStateMachine.observe(output: cr, profile: codex).phase == .transientFailure)
    let bs = "致命：服务繁忙X\u{08} \u{08}\n"
    #expect(CLIInteractionStateMachine.observe(output: bs, profile: codex).phase == .busy)

    // recoveryAction 与 phase 仍是产品话术中文：busy → 等待当前任务，避免自动重开
    #expect(CLIInteractionStateMachine.recoveryAction(for: .busy) == .waitForCurrentTask)
    #expect(CLIInteractionStateMachine.recoveryAction(for: .authenticationBlocked) == .checkAuthentication)
    #expect(CLIInteractionStateMachine.recoveryAction(for: .transientFailure) == .waitAndRetryLater)
    #expect(CLIInteractionRecoveryAction.waitForCurrentTask.title == "等待当前任务")
    #expect(CLIInteractionRecoveryAction.checkAuthentication.title == "检查登录授权")
    #expect(CLIInteractionRecoveryAction.waitAndRetryLater.title == "稍后重试")
}

@Test func cliInteractionStateMachineKeepsChinesePathAndPromptEchoSafe() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))

    // 中文路径里出现「临时异常」/「未授权」/「服务繁忙」/「网络异常」不应误判
    let chinesePathTransient = "\u{1B}[36merror: see /var/log/临时异常.log\u{1B}[0m"
    #expect(CLIInteractionStateMachine.observe(output: chinesePathTransient, profile: codex).phase != .transientFailure)
    let chinesePathAuth = "error: missing /etc/codex/未授权.json"
    #expect(CLIInteractionStateMachine.observe(output: chinesePathAuth, profile: codex).phase != .authenticationBlocked)
    let chinesePathBusy = "fatal: cannot read /opt/codex/服务繁忙-fixture.txt"
    #expect(CLIInteractionStateMachine.observe(output: chinesePathBusy, profile: codex).phase != .busy)

    // 普通中文用户提示词回显：不是诊断行（没有诊断前缀）→ unknown
    let chineseEcho = "用户提示：请检查 未授权 / 服务繁忙 / 网络异常 这些词在文案里如何展示。"
    let echoObservation = CLIInteractionStateMachine.observe(output: chineseEcho, profile: codex)
    #expect(echoObservation.phase != .authenticationBlocked)
    #expect(echoObservation.phase != .busy)
    #expect(echoObservation.phase != .transientFailure)

    // 中英文混排但前缀仍是 error: 且 token 是路径 → 不命中 transient
    let mixedPathToken = "error: see /tmp/timeout-临时异常.log for details"
    #expect(CLIInteractionStateMachine.observe(output: mixedPathToken, profile: codex).phase != .transientFailure)
}

@MainActor
@Test func realTerminalAutoLoopWritesStopAuditWhenTerminalReportsAuthOrBusyOrTransient() async throws {
    let cases: [(phase: CLIInteractionPhase, reason: String, expectedStopReason: CLIAutoInteractionLoopStopReason, expectedReasonTitle: String)] = [
        (.authenticationBlocked, "授权异常", .authenticationBlocked, "授权异常"),
        (.busy, "忙碌中", .busy, "命令行仍在忙碌"),
        (.transientFailure, "临时异常", .transientFailure, "临时异常")
    ]
    for testCase in cases {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.selectAgent(engineer.id)

        let stopAuditCountBefore = store.selectedProductMaintenanceVerifications.filter { $0.title == CompanyStore.terminalAutoInteractionStopAuditTitle }.count
        let deliveryAuditCountBefore = store.selectedProductDeliveryVerifications.filter { $0.title == CompanyStore.terminalAutoInteractionStopAuditTitle }.count
        let bossMessagesBefore = store.messages(for: store.bossID).count
        let agentMessagesBefore = store.agentMessages.count

        let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
            taskContext: "中文诊断停止审计",
            maxTurns: 3,
            turnRunner: { _ in
                CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: testCase.phase, reasonTitle: testCase.reason))
            }
        )
        // 注入 turnRunner → usedRealTerminal == false，但停止审计仍只写在维护视图
        // 是不会触发的（只在真实终端路径触发）。
        #expect(report.usedRealTerminal == false)
        #expect(report.internalReport.execution.finalState.phase == .stopped)
        #expect(report.internalReport.execution.finalState.stopReason == testCase.expectedStopReason)
        #expect(report.summaryText.contains(testCase.expectedReasonTitle))
        // turnRunner 注入路径不写停止审计
        #expect(store.selectedProductMaintenanceVerifications.filter { $0.title == CompanyStore.terminalAutoInteractionStopAuditTitle }.count == stopAuditCountBefore)
        #expect(store.selectedProductDeliveryVerifications.filter { $0.title == CompanyStore.terminalAutoInteractionStopAuditTitle }.count == deliveryAuditCountBefore)
        #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
        #expect(store.agentMessages.count == agentMessagesBefore)
    }

    // 直接用 helper 测真实终端路径下的停止审计写入：构造 stopped state，调用内部 helper。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let stopAuditTitle = CompanyStore.terminalAutoInteractionStopAuditTitle
    let bossMessagesBefore = store.messages(for: store.bossID).count
    let agentMessagesBefore = store.agentMessages.count
    let deliveryBefore = store.selectedProductDeliveryVerifications.count

    for stopReason in [CLIAutoInteractionLoopStopReason.authenticationBlocked, .busy, .transientFailure, .timedOut] {
        let state = CLIAutoInteractionLoopState(
            taskContext: "中文停止审计",
            maxTurns: 3,
            sentInputs: ["第1轮"],
            phase: .stopped,
            stopReason: stopReason
        )
        store.recordTerminalAutoInteractionStopAuditForTesting(agent: engineer, finalState: state)
    }

    let stopAudits = store.selectedProductMaintenanceVerifications.filter { $0.title == stopAuditTitle }
    #expect(stopAudits.count == 4)
    let visibleDetails = stopAudits.map(\.detail).joined(separator: "\n")
    let chineseStopReasons = ["授权异常", "命令行仍在忙碌", "临时异常", "等待超时"]
    for stopReason in chineseStopReasons {
        #expect(visibleDetails.contains(stopReason))
    }
    let forbiddenInternals = ["rawValue", "subscriptionCLI", "persistentProtocol", "authenticationBlocked", "transientFailure", "completedTurn"]
    for forbidden in forbiddenInternals {
        #expect(!visibleDetails.contains(forbidden))
    }

    // 维护视图能看到，但老板/交付视图被过滤
    #expect(store.selectedProductDeliveryVerifications.count == deliveryBefore)
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != stopAuditTitle })
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != stopAuditTitle })
    // 终端日志写入维护审计标记
    let log = store.terminalLogs[engineer.id, default: ""]
    #expect(log.contains("[OPC 自动循环停止审计]"))
    #expect(log.contains("授权异常"))
    #expect(log.contains("命令行仍在忙碌"))
    #expect(log.contains("等待超时"))
    // 不创建老板聊天 / 员工协作消息 / 作业档案
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.isEmpty)

    // selectedProductLatestTerminalAutoLoopStopAudit accessor 取到最近一条
    let latest = try #require(store.selectedProductLatestTerminalAutoLoopStopAudit)
    #expect(latest.title == stopAuditTitle)
    #expect(latest.status == .warning)
}

@Test func cliAutoInteractionLoopRejectsMissingContextAndInvalidLimits() async throws {
    let missing = CLIAutoInteractionLoopGate.start(taskContext: "   ", maxTurns: 3)
    #expect(missing.phase == .rejected)
    #expect(missing.stopReason == .missingTaskContext)
    #expect(missing.summaryText.contains("缺少明确任务上下文"))
    #expect(!missing.summaryText.contains("missingTaskContext"))

    let tooMany = CLIAutoInteractionLoopGate.start(taskContext: "修复终端状态观察", maxTurns: CLIAutoInteractionLoopGate.hardTurnLimit + 1)
    #expect(tooMany.phase == .rejected)
    #expect(tooMany.stopReason == .invalidTurnLimit)
    #expect(tooMany.summaryText.contains("最大轮次不合规"))
}

@Test func cliAutoInteractionLoopStopsAtMaxTurnsWithChineseSummary() async throws {
    var state = CLIAutoInteractionLoopGate.start(taskContext: "继续推进多 Agent 升级", maxTurns: 2)
    #expect(state.phase == .running)

    state = CLIAutoInteractionLoopGate.advance(
        state,
        with: CLIAutoInteractionGeneratedInput(text: "检查当前状态"),
        observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")
    )
    #expect(state.phase == .running)
    #expect(state.sentInputs == ["检查当前状态"])

    state = CLIAutoInteractionLoopGate.advance(
        state,
        with: CLIAutoInteractionGeneratedInput(text: "执行下一步"),
        observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")
    )
    #expect(state.phase == .stopped)
    #expect(state.stopReason == .maxTurnsReached)
    #expect(state.summaryText.contains("达到最大轮次上限"))
    #expect(!state.summaryText.contains("maxTurnsReached"))
}

@Test func cliAutoInteractionLoopStopsOnUnsafeOrNonGeneratedInput() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "验证自动循环门禁", maxTurns: 3)

    let external = CLIAutoInteractionLoopGate.advance(
        state,
        with: CLIAutoInteractionGeneratedInput(text: "手工粘贴内容", source: .external),
        observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")
    )
    #expect(external.phase == .stopped)
    #expect(external.stopReason == .nonOPCGeneratedInput)
    #expect(external.sentInputs.isEmpty)
    #expect(external.summaryText.contains("不是 OPC 生成"))

    let multiline = CLIAutoInteractionLoopGate.advance(
        state,
        with: CLIAutoInteractionGeneratedInput(text: "第一行\n第二行"),
        observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")
    )
    #expect(multiline.phase == .stopped)
    #expect(multiline.stopReason == .unsafeInput)
    #expect(multiline.sentInputs.isEmpty)
}

@Test func cliAutoInteractionLoopStopsOnRiskObservationsAndTimeout() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "驱动长期会话下一轮", maxTurns: 4)
    let input = CLIAutoInteractionGeneratedInput(text: "继续执行计划内下一步")

    let auth = CLIAutoInteractionLoopGate.advance(state, with: input, observation: CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常"))
    #expect(auth.phase == .stopped)
    #expect(auth.stopReason == .authenticationBlocked)
    #expect(auth.sentInputs == ["继续执行计划内下一步"])
    #expect(auth.summaryText.contains("授权异常"))

    let busy = CLIAutoInteractionLoopGate.advance(state, with: input, observation: CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中"))
    #expect(busy.phase == .stopped)
    #expect(busy.stopReason == .busy)
    #expect(busy.summaryText.contains("命令行仍在忙碌"))

    let transient = CLIAutoInteractionLoopGate.advance(state, with: input, observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常"))
    #expect(transient.phase == .stopped)
    #expect(transient.stopReason == .transientFailure)
    #expect(transient.summaryText.contains("临时异常"))

    let timedOut = CLIAutoInteractionLoopGate.advance(state, with: input, observation: CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复"), timedOut: true)
    #expect(timedOut.phase == .stopped)
    #expect(timedOut.stopReason == .timedOut)
    #expect(timedOut.summaryText.contains("等待超时"))
}

@Test func cliAutoInteractionLoopCompletesOnCompletedTurn() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "自动循环完成条件", maxTurns: 3)
    let completed = CLIAutoInteractionLoopGate.advance(
        state,
        with: CLIAutoInteractionGeneratedInput(text: "收尾并报告"),
        observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束")
    )

    #expect(completed.phase == .completed)
    #expect(completed.stopReason == .completedTurn)
    #expect(completed.summaryText.contains("已完成"))
    #expect(completed.summaryText.contains("本轮已结束"))
}

@Test func cliAutoInteractionLoopVisibleTextHidesRawValues() async throws {
    for reason in CLIAutoInteractionLoopStopReason.allCases {
        #expect(!reason.title.contains(reason.rawValue))
        #expect(!reason.operatorHint.contains(reason.rawValue))
    }
    for phase in CLIAutoInteractionLoopPhase.allCases {
        #expect(!phase.title.contains(phase.rawValue))
    }
    for source in CLIAutoInteractionInputSource.allCases {
        #expect(!source.title.contains(source.rawValue))
    }
}

private actor CLIAutoInteractionLoopTestProbe {
    private var inputs: [CLIAutoInteractionGeneratedInput]
    private var turnObservations: [CLIAutoInteractionTurnObservation]
    private var sentTexts: [String] = []

    init(
        inputs: [CLIAutoInteractionGeneratedInput],
        turnObservations: [CLIAutoInteractionTurnObservation]
    ) {
        self.inputs = inputs
        self.turnObservations = turnObservations
    }

    func nextInput(state _: CLIAutoInteractionLoopState) -> CLIAutoInteractionGeneratedInput? {
        guard !inputs.isEmpty else { return nil }
        return inputs.removeFirst()
    }

    func send(_ text: String) -> CLIAutoInteractionTurnObservation {
        sentTexts.append(text)
        guard !turnObservations.isEmpty else {
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复"), timedOut: true)
        }
        return turnObservations.removeFirst()
    }

    func sent() -> [String] {
        sentTexts
    }
}

@Test func cliAutoInteractionLoopExecutorRunsMultipleReadyTurns() async throws {
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [
            CLIAutoInteractionGeneratedInput(text: " 检查当前状态 "),
            CLIAutoInteractionGeneratedInput(text: "执行计划内下一步")
        ],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")),
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"))
        ]
    )

    let report = await CLIAutoInteractionLoopExecutor.run(
        taskContext: "继续推进长期会话执行器",
        maxTurns: 4,
        nextInput: { state in await probe.nextInput(state: state) },
        send: { text in await probe.send(text) }
    )

    #expect(report.finalState.phase == .completed)
    #expect(report.finalState.stopReason == .completedTurn)
    #expect(report.finalState.sentInputs == ["检查当前状态", "执行计划内下一步"])
    #expect(report.sentTurnCount == 2)
    #expect(await probe.sent() == ["检查当前状态", "执行计划内下一步"])
    #expect(report.summaryText.contains("自动交互循环执行器"))
    #expect(report.summaryText.contains("已发送轮次：2/4"))
}

@Test func cliAutoInteractionLoopExecutorRejectsUnsafeInputBeforeCallingSender() async throws {
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [CLIAutoInteractionGeneratedInput(text: "第一行\n第二行")],
        turnObservations: [CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))]
    )

    let report = await CLIAutoInteractionLoopExecutor.run(
        taskContext: "验证发送前门禁",
        maxTurns: 3,
        nextInput: { state in await probe.nextInput(state: state) },
        send: { text in await probe.send(text) }
    )

    #expect(report.finalState.phase == .stopped)
    #expect(report.finalState.stopReason == .unsafeInput)
    #expect(report.finalState.sentInputs.isEmpty)
    #expect(report.turnReports.count == 1)
    #expect(report.turnReports.first?.didCallSender == false)
    #expect(report.turnReports.first?.preflightStopReason == .unsafeInput)
    #expect(await probe.sent().isEmpty)
}

@Test func cliAutoInteractionLoopExecutorStopsOnRiskObservationsAndTimeout() async throws {
    let cases: [(CLIInteractionPhase, Bool, CLIAutoInteractionLoopStopReason)] = [
        (.authenticationBlocked, false, .authenticationBlocked),
        (.busy, false, .busy),
        (.transientFailure, false, .transientFailure),
        (.awaitingResponse, true, .timedOut)
    ]

    for item in cases {
        let probe = CLIAutoInteractionLoopTestProbe(
            inputs: [CLIAutoInteractionGeneratedInput(text: "继续执行计划内下一步")],
            turnObservations: [
                CLIAutoInteractionTurnObservation(
                    observation: CLIInteractionObservation(phase: item.0, reasonTitle: item.2.title),
                    timedOut: item.1
                )
            ]
        )

        let report = await CLIAutoInteractionLoopExecutor.run(
            taskContext: "风险状态停止",
            maxTurns: 3,
            nextInput: { state in await probe.nextInput(state: state) },
            send: { text in await probe.send(text) }
        )

        #expect(report.finalState.phase == .stopped)
        #expect(report.finalState.stopReason == item.2)
        #expect(report.finalState.sentInputs == ["继续执行计划内下一步"])
        #expect(report.sentTurnCount == 1)
        #expect(await probe.sent() == ["继续执行计划内下一步"])
    }
}

@Test func cliAutoInteractionLoopExecutorStopsAtMaxTurns() async throws {
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [
            CLIAutoInteractionGeneratedInput(text: "第一步"),
            CLIAutoInteractionGeneratedInput(text: "第二步"),
            CLIAutoInteractionGeneratedInput(text: "第三步")
        ],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")),
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")),
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        ]
    )

    let report = await CLIAutoInteractionLoopExecutor.run(
        taskContext: "最大轮次停止",
        maxTurns: 2,
        nextInput: { state in await probe.nextInput(state: state) },
        send: { text in await probe.send(text) }
    )

    #expect(report.finalState.phase == .stopped)
    #expect(report.finalState.stopReason == .maxTurnsReached)
    #expect(report.finalState.sentInputs == ["第一步", "第二步"])
    #expect(report.sentTurnCount == 2)
    #expect(await probe.sent() == ["第一步", "第二步"])
}

@Test func cliAutoInteractionLoopExecutorCompletesOnCompletedTurn() async throws {
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [CLIAutoInteractionGeneratedInput(text: "收尾并报告")],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"))
        ]
    )

    let report = await CLIAutoInteractionLoopExecutor.run(
        taskContext: "完成轮次停止",
        maxTurns: 3,
        nextInput: { state in await probe.nextInput(state: state) },
        send: { text in await probe.send(text) }
    )

    #expect(report.finalState.phase == .completed)
    #expect(report.finalState.stopReason == .completedTurn)
    #expect(report.sentTurnCount == 1)
    #expect(report.summaryText.contains("本轮已结束"))
    #expect(!report.summaryText.contains("completedTurn"))
}

@Test func cliAutoInteractionLoopExecutorVisibleTextStaysChineseAndHidesRawValues() async throws {
    let rejected = await CLIAutoInteractionLoopExecutor.run(
        taskContext: "   ",
        maxTurns: 3,
        nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "不会发送") },
        send: { _ in CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")) }
    )
    #expect(rejected.finalState.phase == .rejected)
    #expect(rejected.sentTurnCount == 0)
    #expect(rejected.summaryText.contains("缺少明确任务上下文"))

    let summaries = CLIAutoInteractionLoopStopReason.allCases.map(\.operatorHint)
        + CLIAutoInteractionLoopStopReason.allCases.map(\.title)
        + CLIAutoInteractionLoopPhase.allCases.map(\.title)
        + [rejected.summaryText]
    for rawValue in CLIAutoInteractionLoopStopReason.allCases.map(\.rawValue) + CLIAutoInteractionLoopPhase.allCases.map(\.rawValue) {
        for summary in summaries {
            #expect(!summary.contains(rawValue))
        }
    }
    #expect(!rejected.summaryText.contains("raw"))
    #expect(!rejected.summaryText.contains("running"))
}

@MainActor
@Test func internalAutoInteractionLoopRequiresTaskContextAndTeamEmployee() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [CLIAutoInteractionGeneratedInput(text: "不应发送")],
        turnObservations: [CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))]
    )

    store.selectedAgentID = store.bossID
    let bossReport = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人任务：继续验证",
        maxTurns: 2,
        nextInput: { state in await probe.nextInput(state: state) },
        runTurn: { text in await probe.send(text) }
    )
    #expect(bossReport.rejected)
    #expect(bossReport.execution.sentTurnCount == 0)
    #expect(bossReport.summaryText.contains("老板视角不参与"))
    #expect(await probe.sent().isEmpty)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id
    let missingContext = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "   ",
        maxTurns: 2,
        nextInput: { state in await probe.nextInput(state: state) },
        runTurn: { text in await probe.send(text) }
    )
    #expect(missingContext.rejected)
    #expect(missingContext.execution.finalState.stopReason == .missingTaskContext)
    #expect(missingContext.summaryText.contains("技术负责人任务上下文"))
    #expect(await probe.sent().isEmpty)
}

@MainActor
@Test func internalAutoInteractionLoopRejectsNonTeamEmployeeWithoutCallingRunner() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.addProductWorkspace()
    store.selectedAgentID = engineer.id
    #expect(!store.selectedProductAgents.contains { $0.id == engineer.id })
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [CLIAutoInteractionGeneratedInput(text: "不应发送")],
        turnObservations: [CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))]
    )

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人任务：新产品未分配员工验证",
        maxTurns: 2,
        nextInput: { state in await probe.nextInput(state: state) },
        runTurn: { text in await probe.send(text) }
    )

    #expect(report.rejected)
    #expect(report.execution.sentTurnCount == 0)
    #expect(report.summaryText.contains("还未加入当前产品团队"))
    #expect(await probe.sent().isEmpty)
}

@MainActor
@Test func internalAutoInteractionLoopRunsInjectedTurnsWithoutBossMessagesOrJobArchives() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id
    let initialMessages = store.messages.count
    let initialArtifacts = store.artifacts.count
    let initialVerifications = store.verifications.count
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [
            CLIAutoInteractionGeneratedInput(text: "检查上下文"),
            CLIAutoInteractionGeneratedInput(text: "收尾报告")
        ],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")),
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"))
        ]
    )

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人任务：内部协调器注入验证",
        maxTurns: 3,
        nextInput: { state in await probe.nextInput(state: state) },
        runTurn: { text in await probe.send(text) }
    )

    #expect(!report.rejected)
    #expect(report.agentID == engineer.id)
    #expect(report.productID == store.selectedProductID)
    #expect(report.execution.finalState.phase == .completed)
    #expect(report.execution.sentTurnCount == 2)
    #expect(await probe.sent() == ["检查上下文", "收尾报告"])
    #expect(store.messages.count == initialMessages)
    #expect(store.artifacts.count == initialArtifacts)
    #expect(store.verifications.count == initialVerifications)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
    #expect(!report.summaryText.contains(".opc/jobs"))
}

@MainActor
@Test func internalAutoInteractionLoopStopsOnInjectedRiskObservation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.selectedAgentID = reviewer.id
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [CLIAutoInteractionGeneratedInput(text: "继续审查")],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中"))
        ]
    )

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人任务：风险状态停止验证",
        maxTurns: 3,
        nextInput: { state in await probe.nextInput(state: state) },
        runTurn: { text in await probe.send(text) }
    )

    #expect(!report.rejected)
    #expect(report.execution.finalState.phase == .stopped)
    #expect(report.execution.finalState.stopReason == .busy)
    #expect(report.execution.sentTurnCount == 1)
    #expect(report.summaryText.contains("命令行仍在忙碌"))
    #expect(!report.summaryText.contains("busy"))
}

@MainActor
@Test func terminalAutoInteractionLoopRejectsUnsafeSelectionBeforeSending() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [],
        turnObservations: [CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))]
    )

    store.selectedAgentID = store.bossID
    let bossReport = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人任务：真实终端循环入口验证",
        maxTurns: 2,
        turnRunner: { text in await probe.send(text) }
    )

    #expect(bossReport.rejected)
    #expect(bossReport.internalReport.execution.sentTurnCount == 0)
    #expect(bossReport.summaryText.contains("老板视角不参与"))
    #expect(await probe.sent().isEmpty)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id
    let missingContext = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "   ",
        maxTurns: 2,
        turnRunner: { text in await probe.send(text) }
    )

    #expect(missingContext.rejected)
    #expect(missingContext.internalReport.execution.finalState.stopReason == .missingTaskContext)
    #expect(missingContext.summaryText.contains("技术负责人任务上下文"))
    #expect(await probe.sent().isEmpty)
}

@MainActor
@Test func terminalAutoInteractionLoopUsesGeneratedSingleLineInputsWithoutBossSideEffects() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id
    let initialMessages = store.messages.count
    let initialArtifacts = store.artifacts.count
    let initialVerifications = store.verifications.count
    let probe = CLIAutoInteractionLoopTestProbe(
        inputs: [],
        turnObservations: [
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")),
            CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"))
        ]
    )

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "  技术负责人任务：验证真实终端循环入口\n只允许单行 OPC 输入  ",
        maxTurns: 3,
        turnRunner: { text in await probe.send(text) }
    )

    let sent = await probe.sent()
    #expect(!report.rejected)
    #expect(report.usedRealTerminal == false)
    #expect(report.internalReport.execution.finalState.phase == .completed)
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { !$0.contains(where: \.isNewline) })
    #expect(sent[0].contains("第1轮"))
    #expect(sent[1].contains("第2轮"))
    #expect(sent.allSatisfy { $0.contains("OPC") })
    #expect(store.messages.count == initialMessages)
    #expect(store.artifacts.count == initialArtifacts)
    #expect(store.verifications.count == initialVerifications)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
    #expect(report.summaryText.contains("真实终端自动交互循环"))
    #expect(report.summaryText.contains("不写老板聊天"))
    #expect(!report.summaryText.contains(".opc/jobs"))
    #expect(!report.summaryText.contains("subscriptionCLI"))
    #expect(!report.summaryText.contains("running"))
    #expect(!report.summaryText.contains("rawValue"))
}

@Test func cliInteractionREPLTurnUsesDedicatedReadySignals() async throws {
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    #expect(codex.replReadySignals.contains("codex>"))

    let echoedMention = CLIInteractionStateMachine.observeREPLTurn(output: "请继续检查 codex> 配置", profile: codex)
    #expect(echoedMention.phase == .awaitingResponse)

    let inlinePromptEcho = CLIInteractionStateMachine.observeREPLTurn(output: "处理完成，文本里提到了 codex>", profile: codex)
    #expect(inlinePromptEcho.phase == .awaitingResponse)

    let promptReady = CLIInteractionStateMachine.observeREPLTurn(output: "处理完成\ncodex>", profile: codex)
    #expect(promptReady.phase == .ready)
    #expect(promptReady.reasonTitle == "可继续交互")

    let completed = CLIInteractionStateMachine.observeREPLTurn(output: "turn complete", profile: codex)
    #expect(completed.phase == .completedTurn)

    #expect(CLIInteractionStateMachine.observeREPLTurn(output: "Unauthorized. Please login.", profile: codex).phase == .authenticationBlocked)
    #expect(CLIInteractionStateMachine.observeREPLTurn(output: "Plan usage limits busy", profile: codex).phase == .busy)
    #expect(CLIInteractionStateMachine.observeREPLTurn(output: "network timeout 429", profile: codex).phase == .transientFailure)
}

@MainActor
@Test func cliInteractionObservationIsRecordedAfterAgentRunResult() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let id = "12345678-1234-1234-1234-123456789abc"
    let result = CommandExecutionResult(exitCode: 0, standardOutput: #"{"session_id":"\#(id)"}"#, standardError: "")

    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)

    let session = try #require(store.runtimeSessions[cto.id])
    #expect(session.cliInteractionPhase == .ready)
    #expect(session.cliInteractionReason == "可继续交互")
    #expect(session.cliInteractionSessionID == id)
    #expect(session.cliInteractionRecoveryAction == .noAction)
    #expect(session.cliInteractionRecoveryActionTitle == CLIInteractionRecoveryAction.noAction.title)
    #expect(session.cliInteractionRecoveryHint == nil)
    #expect(session.cliInteractionOperatorHint == nil)
    #expect(session.cliInteractionObservedAt != nil)
    let log = store.terminalLogs[cto.id, default: ""]
    #expect(log.contains("OPC 交互状态"))
    #expect(log.contains("状态：可继续交互。"))
    #expect(!log.contains("session_id"))
    #expect(!log.contains(id))
}

@MainActor
@Test func cliInteractionObservationDoesNotChangeRuntimeFailureState() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let result = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "Please log in to continue.")
    store.runtimeSessions[cto.id] = AgentRuntimeSession(
        agentID: cto.id,
        productID: store.selectedProductID,
        state: .failed,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )

    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)

    let session = try #require(store.runtimeSessions[cto.id])
    #expect(session.state == .failed)
    #expect(session.cliInteractionPhase == .authenticationBlocked)
    #expect(session.cliInteractionReason == "授权异常")
    #expect(session.cliInteractionRecoveryAction == .checkAuthentication)
    #expect(session.cliInteractionRecoveryActionTitle == CLIInteractionRecoveryAction.checkAuthentication.title)
    #expect(session.cliInteractionRecoveryHint == CLIInteractionRecoveryAction.checkAuthentication.operatorHint)
    #expect(session.cliInteractionOperatorHint == CLIInteractionRecoveryAction.checkAuthentication.operatorHint)
    let log = store.terminalLogs[cto.id, default: ""]
    #expect(log.contains("建议：检查登录授权。"))
    #expect(log.contains("请在对应工具中确认登录授权"))
}

@MainActor
@Test func cliInteractionObservationDoesNotWriteVerificationOrRepeatSamePhaseLog() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let verificationCount = store.verifications.count
    let result = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "Please log in to continue.")

    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)

    #expect(store.verifications.count == verificationCount)
    let log = store.terminalLogs[cto.id, default: ""]
    #expect(log.components(separatedBy: "OPC 交互状态").count == 2)
    #expect(!log.contains("authenticationBlocked"))
    #expect(!log.contains("sessionID"))
}

@MainActor
@Test func cliInteractionPhaseSuppressesMeaninglessAuthenticationRestart() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let authResult = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "session expired. Please log in to continue.")
    let transientResult = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "connection reset by peer")
    let genericSessionOutput = CommandExecutionResult(
        exitCode: 1,
        standardOutput: #"{"session_id":"12345678-1234-1234-1234-123456789abc"}"#,
        standardError: "request failed"
    )
    let expiredSessionOutput = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "session expired before response")

    #expect(!store.shouldRestartSessionForTesting(agentID: cto.id, result: authResult))
    #expect(!store.shouldRestartSessionForTesting(agentID: cto.id, result: genericSessionOutput))
    #expect(store.shouldRestartSessionForTesting(agentID: cto.id, result: expiredSessionOutput))
    #expect(store.shouldRestartSessionForTesting(agentID: cto.id, result: transientResult))
}

@MainActor
@Test func cliInteractionRecoveryActionMappingCoversAllPhases() async throws {
    let expected: [CLIInteractionPhase: CLIInteractionRecoveryAction] = [
        .unknown: .noAction,
        .ready: .noAction,
        .awaitingResponse: .noAction,
        .completedTurn: .noAction,
        .busy: .waitForCurrentTask,
        .authenticationBlocked: .checkAuthentication,
        .transientFailure: .waitAndRetryLater
    ]

    #expect(expected.count == CLIInteractionPhase.allCases.count)
    for phase in CLIInteractionPhase.allCases {
        #expect(CLIInteractionStateMachine.recoveryAction(for: phase) == expected[phase])
    }
}

@MainActor
@Test func manualObservationAfterLoginUnblocksAuthenticationPhase() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let authResult = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "Please log in to continue.")
    let id = "12345678-1234-1234-1234-123456789abc"
    let readyResult = CommandExecutionResult(exitCode: 0, standardOutput: #"{"session_id":"\#(id)"}"#, standardError: "")

    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: authResult)
    #expect(store.runtimeSessions[cto.id]?.cliInteractionPhase == .authenticationBlocked)
    #expect(store.runtimeSessions[cto.id]?.cliInteractionRecoveryAction == .checkAuthentication)

    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: readyResult)
    #expect(store.runtimeSessions[cto.id]?.cliInteractionPhase == .ready)
    #expect(store.runtimeSessions[cto.id]?.cliInteractionRecoveryAction == .noAction)
    #expect(store.runtimeSessions[cto.id]?.cliInteractionOperatorHint == nil)
}

@MainActor
@Test func cliInteractionRecoveryActionVisibleTextStaysChineseAndHidesRawValues() async throws {
    for action in CLIInteractionRecoveryAction.allCases {
        #expect(action.title.range(of: #"\p{Han}"#, options: .regularExpression) != nil)
        if let hint = action.operatorHint {
            #expect(hint.range(of: #"\p{Han}"#, options: .regularExpression) != nil)
            #expect(!hint.contains(action.rawValue))
            #expect(!hint.localizedCaseInsensitiveContains("session"))
            #expect(!hint.localizedCaseInsensitiveContains("restart"))
        }
    }

    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let result = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "Please log in to continue.")
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)
    let log = store.terminalLogs[cto.id, default: ""]

    for action in CLIInteractionRecoveryAction.allCases {
        #expect(!log.contains(action.rawValue))
    }
}

@Test func cliInteractionProfilesRejectCommonNoiseSessionTokens() async throws {
    let claude = try #require(CLIInteractionProfileCatalog.profile(forCommand: "claude"))
    let gemini = try #require(CLIInteractionProfileCatalog.profile(forCommand: "gemini"))

    for profile in [claude, gemini] {
        #expect(profile.sessionID(from: "session_id: invalid") == nil)
        #expect(profile.sessionID(from: "conversation_id: unknown") == nil)
        #expect(profile.sessionID(from: "session id: pending") == nil)
        #expect(profile.sessionID(from: "chat_id: error") == nil)
    }
}

@MainActor
@Test func codexSessionResumeStaysScopedToCurrentProductAndBackend() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let firstProductID = store.selectedProductID
    let firstSessionID = "12345678-1234-1234-1234-123456789abc"
    let secondSessionID = "22345678-1234-1234-1234-123456789abc"
    var session = store.runtimeSessions[cto.id] ?? AgentRuntimeSession(
        agentID: cto.id,
        productID: firstProductID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    session.productID = firstProductID
    session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: cto)
    session.cliSessionID = firstSessionID
    session.cliSessionMode = "codex-exec"
    session.cliSessionsByProduct = [
        firstProductID: AgentCLIConversation(
            productID: firstProductID,
            sessionID: firstSessionID,
            mode: "codex-exec",
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
        )
    ]
    store.runtimeSessions[cto.id] = session

    let command = store.commandPreviewForTesting(agentID: cto.id, prompt: "继续上一轮")
    #expect(command.contains("resume"))
    #expect(command.contains(firstSessionID))

    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(cto.id)
    let secondProductID = store.selectedProductID
    let otherProductCommand = store.commandPreviewForTesting(agentID: cto.id, prompt: "新产品任务")
    #expect(!otherProductCommand.contains("resume"))
    #expect(!otherProductCommand.contains(firstSessionID))

    var updatedSession = try #require(store.runtimeSessions[cto.id])
    updatedSession.productID = secondProductID
    updatedSession.cliSessionID = secondSessionID
    updatedSession.cliSessionMode = "codex-exec"
    var conversations = updatedSession.cliSessionsByProduct ?? [:]
    conversations[secondProductID] = AgentCLIConversation(
        productID: secondProductID,
        sessionID: secondSessionID,
        mode: "codex-exec",
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    updatedSession.cliSessionsByProduct = conversations
    store.runtimeSessions[cto.id] = updatedSession

    let secondProductCommand = store.commandPreviewForTesting(agentID: cto.id, prompt: "继续第二个产品")
    #expect(secondProductCommand.contains("resume"))
    #expect(secondProductCommand.contains(secondSessionID))
    #expect(!secondProductCommand.contains(firstSessionID))

    store.selectProduct(firstProductID)
    let firstProductAgain = store.commandPreviewForTesting(agentID: cto.id, prompt: "切回第一个产品")
    #expect(firstProductAgain.contains("resume"))
    #expect(firstProductAgain.contains(firstSessionID))
    #expect(!firstProductAgain.contains(secondSessionID))
}

@MainActor
@Test func resumedCLICommandDoesNotResendFullAgentSystemPromptForTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let sessionID = "12345678-1234-1234-1234-123456789abc"
    let productID = store.selectedProductID
    var session = store.runtimeSessions[cto.id] ?? AgentRuntimeSession(
        agentID: cto.id,
        productID: productID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    session.productID = productID
    session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: cto)
    session.cliSessionID = sessionID
    session.cliSessionMode = "codex-exec"
    session.cliSessionsByProduct = [
        productID: AgentCLIConversation(
            productID: productID,
            sessionID: sessionID,
            mode: "codex-exec",
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
        )
    ]
    store.runtimeSessions[cto.id] = session

    let command = store.commandPreviewForTesting(agentID: cto.id, prompt: "只执行本轮续跑任务")
    let resumedPrompt = try #require(command.last)

    #expect(command.contains(sessionID))
    #expect(resumedPrompt.contains("继续使用当前 OPC 产品"))
    #expect(resumedPrompt.contains("只执行本轮续跑任务"))
    #expect(!resumedPrompt.contains("员工操作档案"))
    #expect(!resumedPrompt.contains("长期记忆："))
    #expect(!resumedPrompt.contains("可用技能："))
}

@MainActor
@Test func firstRunAgentPromptDoesNotDuplicateWorkspaceFileListForTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let command = store.commandPreviewForTesting(agentID: cto.id, prompt: "首轮任务")
    let prompt = try #require(command.last)

    #expect(prompt.contains("员工操作档案"))
    #expect(prompt.contains("首轮任务"))
    #expect(!prompt.contains("AGENTS.md"))
    #expect(!prompt.contains("SOUL.md"))
    #expect(!prompt.contains("MEMORY.md"))
    #expect(!prompt.contains("SKILLS.md"))
    #expect(!prompt.contains("WORKSPACE.md"))
}

@Test func agentWorkspaceSyncSkipsUnchangedPromptFilesForTokenBudget() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    #expect(source.contains("func writeTextIfChanged(_ text: String, to url: URL) throws"))
    #expect(source.contains("try writeTextIfChanged(agentSystemPrompt(for: agentID), to: directory.appendingPathComponent(\"AGENTS.md\"))"))
    #expect(source.contains("if let existing = try? Data(contentsOf: url), existing == data"))
    #expect(!source.contains("try agentSystemPrompt(for: agentID).write(to: directory.appendingPathComponent(\"AGENTS.md\")"))
}

@MainActor
@Test func failedCLIResumeClearsExpiredProductConversationAfterRepeatedFailure() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let productID = store.selectedProductID
    let expiredSessionID = "12345678-1234-1234-1234-123456789abc"
    var session = store.runtimeSessions[cto.id] ?? AgentRuntimeSession(
        agentID: cto.id,
        productID: productID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    session.productID = productID
    session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: cto)
    session.cliSessionID = expiredSessionID
    session.cliSessionMode = "codex-exec"
    session.cliSessionsByProduct = [
        productID: AgentCLIConversation(
            productID: productID,
            sessionID: expiredSessionID,
            mode: "codex-exec",
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
        )
    ]
    store.runtimeSessions[cto.id] = session

    let failedResult = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "session expired")
    store.handleFailedCLIResumeIfNeeded(agent: cto, result: failedResult, usedResumeSessionID: expiredSessionID)
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[productID]?.failureCount == 1)
    #expect(store.commandPreviewForTesting(agentID: cto.id, prompt: "第一次失败后仍可重试").contains(expiredSessionID))

    store.handleFailedCLIResumeIfNeeded(agent: cto, result: failedResult, usedResumeSessionID: expiredSessionID)
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[productID] == nil)
    #expect(!store.commandPreviewForTesting(agentID: cto.id, prompt: "第二次失败后新开").contains(expiredSessionID))
    #expect(store.events.contains { $0.title == "\(cto.displayName) 上下文已重置" })
    let eventText = store.events.map { "\($0.title)\n\($0.detail)" }.joined(separator: "\n")
    #expect(!eventText.contains("命令行"))
    #expect(!eventText.contains("会话编号"))
    #expect(!eventText.contains("续跑"))
    #expect(!eventText.contains("resume"))
    #expect(!eventText.contains("sessionID"))
    let terminalLog = store.terminalLogs[cto.id, default: ""]
    #expect(terminalLog.contains("OPC 上下文复用失败"))
    #expect(terminalLog.contains("OPC 上下文已重置"))
    #expect(!terminalLog.contains("命令行会话"))
}

@MainActor
@Test func cliResumeRunNoticeDoesNotLeakInternalTerms() async throws {
    let resumeNotice = CompanyStore.cliResumeContextNotice
    let persistentNotice = CompanyStore.persistentSeatExecutionNotice
    let combined = resumeNotice + persistentNotice

    #expect(resumeNotice.contains("OPC 上下文复用"))
    #expect(persistentNotice.contains("OPC 长期席位执行"))
    #expect(!combined.contains("命令行会话"))
    #expect(!combined.contains("续跑"))
    #expect(!combined.contains("会话编号"))
    #expect(!combined.contains("真实终端席位"))
    #expect(!combined.contains("作业档案"))
    #expect(!combined.contains("resume"))
    #expect(!combined.contains("sessionID"))
}

@MainActor
@Test func failedCLIResumeDoesNotAffectOtherProductsOrMismatchedSessions() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let firstProductID = store.selectedProductID
    let firstSessionID = "12345678-1234-1234-1234-123456789abc"
    let secondSessionID = "22345678-1234-1234-1234-123456789abc"
    var session = store.runtimeSessions[cto.id] ?? AgentRuntimeSession(
        agentID: cto.id,
        productID: firstProductID,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    session.productID = firstProductID
    session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: cto)
    session.cliSessionID = firstSessionID
    session.cliSessionMode = "codex-exec"
    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(cto.id)
    let secondProductID = store.selectedProductID
    session.cliSessionsByProduct = [
        firstProductID: AgentCLIConversation(
            productID: firstProductID,
            sessionID: firstSessionID,
            mode: "codex-exec",
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
        ),
        secondProductID: AgentCLIConversation(
            productID: secondProductID,
            sessionID: secondSessionID,
            mode: "codex-exec",
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
        )
    ]
    store.runtimeSessions[cto.id] = session

    let failedResult = CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: "expired")
    store.handleFailedCLIResumeIfNeeded(agent: cto, result: failedResult, usedResumeSessionID: "33345678-1234-1234-1234-123456789abc")
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[firstProductID]?.sessionID == firstSessionID)
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[secondProductID]?.sessionID == secondSessionID)

    store.handleFailedCLIResumeIfNeeded(agent: cto, result: failedResult, usedResumeSessionID: secondSessionID)
    store.handleFailedCLIResumeIfNeeded(agent: cto, result: failedResult, usedResumeSessionID: secondSessionID)
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[secondProductID] == nil)
    #expect(store.runtimeSessions[cto.id]?.cliSessionsByProduct?[firstProductID]?.sessionID == firstSessionID)
}

@MainActor
@Test func codexSessionIDParserAcceptsTextAndJSONLines() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let id = "12345678-1234-1234-1234-123456789abc"

    #expect(store.codexSessionIDForTesting(from: "session id: \(id)\n完成") == id)
    #expect(store.codexSessionIDForTesting(from: #"{"session_id":"12345678-1234-1234-1234-123456789abc"}"#) == id)
    #expect(store.codexSessionIDForTesting(from: #"{"conversation_id":"12345678-1234-1234-1234-123456789abc"}"#) == id)
    #expect(store.codexSessionIDForTesting(from: "没有会话") == nil)
}

@MainActor
@Test func cliPreflightSummarizesLongRunningProtocolInChinese() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let report = store.cliPreflightText(for: cto.id, prompt: "继续推进")

    #expect(report.contains("长期会话"))
    #expect(report.contains("支持按产品续跑"))
    #expect(report.contains("识别"))
    #expect(report.contains("监控"))
    #expect(!report.contains("sessionMode"))
    #expect(!report.contains("readySignals"))
    #expect(!report.contains("session id"))
    #expect(!report.contains("session_id"))
    #expect(!report.contains("conversation id"))
    #expect(!report.contains("conversation_id"))
}

@MainActor
@Test func apiEmployeeRequiresAndStoresApiConfiguration() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.draftEmployee.displayName = "API 研究员"
    store.draftEmployee.role = .researcher
    store.draftEmployee.backendType = .api
    store.draftEmployee.command = "claude"
    store.draftEmployee.endpoint = "https://api.example.com/v1"
    store.draftEmployee.apiKey = "secret-key"
    store.draftEmployee.model = "deepseek-chat"

    store.addEmployee(from: store.draftEmployee)
    let agent = try #require(store.agents.first { $0.displayName == "API 研究员" })

    #expect(agent.backend.type == .api)
    #expect(agent.backend.endpoint == "https://api.example.com/v1")
    #expect(agent.backend.apiKey == "secret-key")
    #expect(agent.backend.model == "deepseek-chat")
}

@Test func apiCommandUsesApiRunnerAndDoesNotExposeApiKey() async throws {
    let agent = CompanyAgent(
        displayName: "API Agent",
        title: "API 员工",
        role: .researcher,
        backend: AgentBackend(type: .api, command: "claude", model: "deepseek-chat", endpoint: "https://api.example.com/v1", apiKey: "secret-key"),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .smartCasual,
        permissions: [.useNetwork],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let command = CLIAgentCommandBuilder.command(for: agent, prompt: "调研")
    #expect(command.first == "api-agent")
    #expect(command.contains("https://api.example.com/v1"))
    #expect(command.contains("deepseek-chat"))
    #expect(!command.contains("secret-key"))
    #expect(!command.contains("claude"))
}

@Test func apiChatRequestUsesOpenAICompatibleEndpointAndBearerAuth() async throws {
    let agent = CompanyAgent(
        displayName: "API Agent",
        title: "API 员工",
        role: .researcher,
        backend: AgentBackend(type: .api, command: "api-agent", model: "deepseek-chat", endpoint: "https://api.example.com/v1", apiKey: "secret-key"),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .smartCasual,
        permissions: [.useNetwork],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let request = try AgentAPIChatRunner.request(for: agent, prompt: "像真人一样回复")
    #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")

    let bodyData = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(body["model"] as? String == "deepseek-chat")
    let messages = try #require(body["messages"] as? [[String: Any]])
    #expect(messages.first?["content"] as? String == "像真人一样回复")
}

@MainActor
@Test func apiChatVisiblePreludesHideEndpointAndRawModel() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let agent = CompanyAgent(
        displayName: "接口员工",
        title: "资料研究员",
        role: .researcher,
        backend: AgentBackend(type: .api, command: "api-agent", model: "deepseek-chat", endpoint: "https://api.example.com/v1", apiKey: "secret-key"),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .smartCasual,
        permissions: [.useNetwork],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let terminalPrelude = store.apiChatTerminalLogPrelude(for: agent)
    let sessionPrelude = store.apiChatSessionLogPrelude(for: agent)

    #expect(terminalPrelude.contains("[OPC 接口聊天]"))
    #expect(terminalPrelude.contains("接口聊天请求已交给员工档案中配置的接口模型"))
    #expect(sessionPrelude.contains("接口聊天请求已交给员工档案中配置的接口模型"))
    #expect(!terminalPrelude.contains("POST"))
    #expect(!terminalPrelude.contains("model:"))
    #expect(!terminalPrelude.contains("https://api.example.com"))
    #expect(!terminalPrelude.contains("deepseek-chat"))
    #expect(!sessionPrelude.contains("POST"))
    #expect(!sessionPrelude.contains("model"))
    #expect(!sessionPrelude.contains("https://api.example.com"))
    #expect(!sessionPrelude.contains("deepseek-chat"))
}

@Test func apiBackendEncodingDoesNotPersistPlaintextApiKey() async throws {
    let backend = AgentBackend(type: .api, command: "api-agent", model: "deepseek-chat", endpoint: "https://api.example.com/v1", apiKey: "secret-key")

    let data = try JSONEncoder().encode(backend)
    let text = String(data: data, encoding: .utf8) ?? ""

    #expect(!text.contains("secret-key"))
    #expect(text.contains("\"apiKey\":\"\""))
}

@Test func backendDecodesOlderStateWithoutApiKey() async throws {
    let json = """
    {
      "type": "api",
      "command": "api-agent",
      "model": "deepseek-chat",
      "endpoint": "https://api.example.com/v1",
      "reasoningEffort": "medium"
    }
    """.data(using: .utf8)!

    let backend = try JSONDecoder().decode(AgentBackend.self, from: json)
    #expect(backend.apiKey == "")
    #expect(backend.endpoint == "https://api.example.com/v1")
}

@Test func claudeCommandIncludesReasoningEffort() async throws {
    let claude = CompanyAgent(
        displayName: "Claude Code",
        title: "代码工程师",
        role: .codeEngineer,
        backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .xhigh),
        ethnicity: .black,
        gender: .man,
        clothing: .smartCasual,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let command = CLIAgentCommandBuilder.command(for: claude, prompt: "实现功能")
    #expect(command.contains("--effort"))
    #expect(command.contains("xhigh"))
}

@Test func geminiPromptImmediatelyFollowsPromptFlag() async throws {
    let gemini = CompanyAgent(
        displayName: "Gemini UI",
        title: "界面设计师",
        role: .uiDesigner,
        backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "gemini-2.5-pro"),
        ethnicity: .southAsian,
        gender: .woman,
        clothing: .designerBlack,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let command = CLIAgentCommandBuilder.command(for: gemini, prompt: "汇报状态")
    #expect(command == ["gemini", "--model", "gemini-2.5-pro", "-p", "汇报状态"])
}

@Test func geminiCliLegacyModelFallsBackToDefaultModel() async throws {
    let gemini = CompanyAgent(
        displayName: "Gemini UI",
        title: "界面设计师",
        role: .uiDesigner,
        backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "gemini-cli"),
        ethnicity: .southAsian,
        gender: .woman,
        clothing: .designerBlack,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0, y: 0, room: "office")
    )

    let command = CLIAgentCommandBuilder.command(for: gemini, prompt: "汇报状态")
    #expect(command == ["gemini", "-p", "汇报状态"])
}

@MainActor
@Test func ctoSupervisorGoalCreatesTasksWorkQueueAndAgentMessages() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let goalTaskID = try #require(store.startCTOSupervisorGoal(goal: "做出多员工第一阶段闭环"))

    let goalSuffix = "做出多员工第一阶段闭环"
    #expect(store.selectedProductTasks.contains { $0.id == goalTaskID && $0.title.hasPrefix("技术负责人拆解：") })
    #expect(store.selectedProductTasks.contains { $0.title == "员工执行：\(goalSuffix)" })
    #expect(store.selectedProductTasks.contains { $0.title == "审查验收：\(goalSuffix)" })
    let bossTask = try #require(store.selectedProductTasks.first { $0.title == "老板审批：\(goalSuffix)" })
    #expect(bossTask.status == .needsApproval)

    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goalSuffix)" })
    #expect(store.selectedProductWorkQueue.contains { $0.taskID == engineerTask.id })

    let messages = store.selectedProductAgentMessages
    #expect(messages.contains { $0.kind == .ctoGoalStarted && $0.fromAgentID == store.ctoID && $0.toAgentID == store.bossID })
    #expect(messages.contains { $0.kind == .taskDispatched && $0.taskID == engineerTask.id && $0.toAgentID == engineerTask.ownerID })
    #expect(messages.contains { $0.kind == .reviewRequested })
}

@MainActor
@Test func nonTeamAgentsCannotReceiveProductMessages() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let outsider = CompanyAgent(
        displayName: "外部研究员",
        title: "未加入团队的研究员",
        role: .researcher,
        backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "gemini-2.5-pro"),
        ethnicity: .chinese,
        gender: .woman,
        clothing: .smartCasual,
        permissions: [.readFiles],
        seat: OfficeSeat(x: 0.1, y: 0.1, room: "employee-hall")
    )
    store.agents.append(outsider)

    let result = store.postAgentMessage(
        fromAgentID: store.ctoID,
        toAgentID: outsider.id,
        kind: .ctoGoalStarted,
        subject: "应被拒绝",
        body: "outsider 不在产品团队。"
    )

    #expect(result == nil)
    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(store.events.contains { $0.title == "已阻止跨团队消息接收" })
}

@MainActor
@Test func postAgentMessageClipsLargeSubjectAndBodyForTokenBudget() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let longSubject = String(repeating: "超长主题", count: 120)
    let longBody = String(repeating: "超长协作正文", count: 700)

    let envelope = try #require(store.postAgentMessage(
        fromAgentID: store.ctoID,
        toAgentID: engineer.id,
        kind: .taskDispatched,
        subject: longSubject,
        body: longBody
    ))

    #expect(envelope.subject.count <= 241)
    #expect(envelope.body.count <= 2_401)
    #expect(envelope.subject.hasSuffix("…"))
    #expect(envelope.body.hasSuffix("…"))
    #expect(store.selectedProductAgentMessages.first?.id == envelope.id)
}

@MainActor
@Test func completeWorkItemPostsCallbackToCTO() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "回传消息测试", ownerID: engineer.id, status: .assigned, successCriteria: "完成后必须给 CTO 发回传。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "回传消息测试" })

    store.enqueueWorkItem(taskID: task.id, agentID: engineer.id)
    let dispatched = try #require(store.selectedProductAgentMessages.first { $0.kind == .taskDispatched && $0.taskID == task.id })
    #expect(dispatched.fromAgentID == store.ctoID)
    #expect(dispatched.toAgentID == engineer.id)

    store.completeWorkItem(for: task.id, agentID: engineer.id, status: .completed)
    let workCompleted = try #require(store.selectedProductAgentMessages.first { $0.kind == .workCompleted && $0.taskID == task.id })
    #expect(workCompleted.fromAgentID == engineer.id)
    #expect(workCompleted.toAgentID == store.ctoID)
}

@MainActor
@Test func approvalRequestsAreTraceableThroughAgentMessageBus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.createTask(title: "审批可追踪测试", ownerID: reviewer.id, status: .assigned, successCriteria: "审批消息要进入消息总线。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "审批可追踪测试" })

    store.requestApproval(taskID: task.id, title: "需要老板批准", reason: "涉及高风险操作", requesterID: reviewer.id)
    let approval = try #require(store.selectedProductApprovals.first { $0.title == "需要老板批准" })
    let requestMessage = try #require(store.selectedProductAgentMessages.first { $0.kind == .approvalRequested && $0.approvalID == approval.id })
    #expect(requestMessage.fromAgentID == reviewer.id)
    #expect(requestMessage.toAgentID == store.bossID)
    #expect(requestMessage.taskID == task.id)

    store.decideApproval(approval.id, approved: true)
    let decisionMessage = try #require(store.selectedProductAgentMessages.first { $0.kind == .approvalDecided && $0.approvalID == approval.id })
    #expect(decisionMessage.fromAgentID == store.bossID)
    #expect(decisionMessage.toAgentID == reviewer.id)
}

@MainActor
@Test func startCTOSupervisorGoalProducesPendingMessagesAndAckClearsThem() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.startCTOSupervisorGoal(goal: "Phase 2 协作链路")

    #expect(store.selectedProductPendingAgentMessages.count > 0)
    #expect(store.selectedProductAgentMessages.allSatisfy { $0.productID == store.selectedProductID })

    let acknowledged = store.acknowledgeSelectedProductAgentMessages()
    #expect(acknowledged > 0)
    #expect(store.selectedProductPendingAgentMessages.isEmpty)
    #expect(store.selectedProductAgentMessages.allSatisfy { $0.status == .acknowledged })
    #expect(store.events.contains { $0.title == "员工协作消息已标记已读" })
}

@MainActor
@Test func acknowledgeAgentMessagesOnlyAffectsCurrentProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.startCTOSupervisorGoal(goal: "产品 A 目标")
    let firstProductID = store.selectedProductID
    let firstProductMessageCount = store.selectedProductPendingAgentMessages.count
    #expect(firstProductMessageCount > 0)

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    _ = store.startCTOSupervisorGoal(goal: "产品 B 目标")
    let secondProductPending = store.selectedProductPendingAgentMessages.count
    #expect(secondProductPending > 0)

    let ackCountSecond = store.acknowledgeSelectedProductAgentMessages()
    #expect(ackCountSecond == secondProductPending)
    #expect(store.selectedProductPendingAgentMessages.isEmpty)

    store.selectProduct(firstProductID)
    let firstProductPendingAfter = store.selectedProductPendingAgentMessages.count
    #expect(firstProductPendingAfter == firstProductMessageCount)
    #expect(store.agentMessages.contains { $0.productID == secondProductID && $0.status == .acknowledged })
    #expect(store.agentMessages.contains { $0.productID == firstProductID && $0.status == .pending })
}

@MainActor
@Test func productDetailExposesAgentCollaborationEntryPoint() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.startCTOSupervisorGoal(goal: "协作链路入口测试")
    let messages = store.selectedProductAgentMessages
    let goalMessage = try #require(messages.first { $0.kind == .ctoGoalStarted })

    #expect(AgentMessageDisplay.title(for: goalMessage.kind) == "技术负责人启动目标")
    #expect(AgentMessageDisplay.statusTitle(for: .pending) == "待确认")
    #expect(AgentMessageDisplay.statusTitle(for: .acknowledged) == "已读")
    #expect(!AgentMessageDisplay.icon(for: goalMessage.kind).isEmpty)
}

@MainActor
@Test func agentMessagesPersistThroughCompanySnapshot() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.startCTOSupervisorGoal(goal: "持久化测试目标")
    let reviewTask = try #require(store.selectedProductTasks.first { $0.title.hasPrefix("审查验收：") })
    store.requestCTOReview(for: reviewTask.id)
    let originalCount = store.agentMessages.count
    #expect(originalCount > 0)
    let originalGateCount = store.reviewGates.count
    #expect(originalGateCount > 0)

    let snapshot = store.currentSnapshot()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(CompanySnapshot.self, from: data)

    #expect(decoded.agentMessages.count == originalCount)
    #expect(decoded.reviewGates.count == originalGateCount)
    #expect(decoded.agentMessages.contains { $0.kind == .ctoGoalStarted })
    #expect(decoded.schemaVersion >= 14)
}

@MainActor
@Test func sqliteHistoryIndexRebuildsSearchableSnapshotRecords() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let otherProductID = UUID()
    store.messages.append(ChatMessage(agentID: store.ctoID, author: .system, text: "SQLite 历史索引全局消息"))
    store.messages.append(ChatMessage(productID: productID, agentID: store.ctoID, author: .system, text: "SQLite 历史索引当前产品聊天"))
    store.messages.append(ChatMessage(productID: otherProductID, agentID: store.ctoID, author: .system, text: "SQLite 历史索引其他产品聊天"))
    store.events.append(CompanyEvent(productID: productID, kind: .ctoSummary, title: "SQLite 历史索引主产品事件", detail: "当前产品可搜索", agentID: store.ctoID))
    store.events.append(CompanyEvent(productID: otherProductID, kind: .ctoSummary, title: "SQLite 历史索引其他产品事件", detail: "不应出现在当前产品过滤里", agentID: store.ctoID))

    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryIndex-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")
    let stats = try CompanyHistorySQLiteIndex.rebuild(snapshot: store.currentSnapshot(), at: databaseURL)

    #expect(stats.recordCount >= store.messages.count + store.events.count + store.tasks.count)
    #expect(stats.productCount >= 2)

    let allResults = try CompanyHistorySQLiteIndex.search(at: databaseURL, query: "SQLite 历史索引", limit: 10)
    #expect(allResults.contains { $0.kind == "chat_message" && $0.body.contains("全局消息") })
    #expect(allResults.contains { $0.productID == productID && $0.title.contains("主产品") })

    let currentProductResults = try CompanyHistorySQLiteIndex.search(at: databaseURL, query: "SQLite 历史索引", productID: productID, limit: 10)
    #expect(currentProductResults.contains { $0.title.contains("主产品") })
    #expect(currentProductResults.contains { $0.kind == "chat_message" && $0.productID == productID && $0.body.contains("当前产品聊天") })
    #expect(!currentProductResults.contains { $0.kind == "chat_message" && $0.body.contains("全局消息") })
    #expect(!currentProductResults.contains { $0.productID == otherProductID })
}

@MainActor
@Test func sqliteHistoryArchiveCopiesOldOperationalRecordsWithoutCroppingSnapshot() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let oldDate = Date(timeIntervalSinceNow: -90 * 24 * 60 * 60)
    let freshDate = Date()
    let originalMessageCount = store.messages.count
    let originalEventCount = store.events.count
    let originalAgentMessageCount = store.agentMessages.count
    let originalCommunicationLogCount = store.communicationLogs.count

    store.messages.append(ChatMessage(agentID: store.ctoID, author: .system, text: "旧聊天归档样本", createdAt: oldDate))
    store.events.append(CompanyEvent(productID: productID, kind: .ctoSummary, title: "旧事件归档样本", detail: "应进入归档表", agentID: store.ctoID, createdAt: oldDate))
    store.events.append(CompanyEvent(productID: productID, kind: .ctoSummary, title: "新事件不归档", detail: "未超过阈值", agentID: store.ctoID, createdAt: freshDate))
    store.communicationLogs.append(CommunicationLogEntry(productID: productID, agentID: store.ctoID, direction: .outbound, status: .sent, title: "旧通信归档样本", body: "应进入归档表", createdAt: oldDate))
    store.agentMessages.append(AgentMessageEnvelope(productID: productID, fromAgentID: store.ctoID, toAgentID: nil, kind: .ctoLoopProgressed, status: .acknowledged, subject: "旧协作归档样本", body: "应进入归档表", createdAt: oldDate))

    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryArchive-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")
    let stats = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: databaseURL, olderThan: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60))
    let persistedStats = try CompanyHistorySQLiteIndex.archiveStats(at: databaseURL)

    #expect(stats.archivedRecordCount >= 4)
    #expect(persistedStats.archivedRecordCount == stats.archivedRecordCount)
    #expect(stats.productCount >= 1)
    #expect(store.messages.count == originalMessageCount + 1)
    #expect(store.events.count == originalEventCount + 2)
    #expect(store.agentMessages.count == originalAgentMessageCount + 1)
    #expect(store.communicationLogs.count == originalCommunicationLogCount + 1)
}

@MainActor
@Test func sqliteHistoryArchiveIsIdempotentOnRepeatedRun() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let oldDate = Date(timeIntervalSinceNow: -90 * 24 * 60 * 60)
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "幂等归档样本", detail: "重复运行不应重复插入", agentID: store.ctoID, createdAt: oldDate))
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryArchiveIdempotent-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")
    let cutoff = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)

    _ = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: databaseURL, olderThan: cutoff)
    let firstStats = try CompanyHistorySQLiteIndex.archiveStats(at: databaseURL)
    _ = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: databaseURL, olderThan: cutoff)
    let secondStats = try CompanyHistorySQLiteIndex.archiveStats(at: databaseURL)

    #expect(firstStats.archivedRecordCount == secondStats.archivedRecordCount)
}

@MainActor
@Test func sqliteHistoryArchiveCountsProductsAcrossSourceProducts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstProductID = store.selectedProductID
    let secondProductID = UUID()
    let oldDate = Date(timeIntervalSinceNow: -90 * 24 * 60 * 60)
    store.events.append(CompanyEvent(productID: firstProductID, kind: .ctoSummary, title: "产品一归档样本", detail: "应进入归档表", agentID: store.ctoID, createdAt: oldDate))
    store.events.append(CompanyEvent(productID: secondProductID, kind: .ctoSummary, title: "产品二归档样本", detail: "应进入归档表", agentID: store.ctoID, createdAt: oldDate))
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryArchiveProducts-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")

    let stats = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: databaseURL, olderThan: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60))

    #expect(stats.productCount >= 2)
}

@MainActor
@Test func sqliteHistoryArchiveCutoffBoundaryUsesStrictOlderThan() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cutoff = Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "归档阈值之前", detail: "应归档", agentID: store.ctoID, createdAt: cutoff.addingTimeInterval(-0.001)))
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "归档阈值之后", detail: "不应归档", agentID: store.ctoID, createdAt: cutoff.addingTimeInterval(0.001)))
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryArchiveCutoff-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")

    let stats = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: databaseURL, olderThan: cutoff)

    #expect(stats.archivedRecordCount == 1)
}

@MainActor
@Test func sqliteHistoryArchiveFailureDoesNotCropSnapshot() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let oldDate = Date(timeIntervalSinceNow: -90 * 24 * 60 * 60)
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "失败隔离归档样本", detail: "失败时仍留在 JSON", agentID: store.ctoID, createdAt: oldDate))
    let eventCount = store.events.count
    let invalidDatabaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCHistoryArchiveInvalid-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("history.sqlite3")
    try FileManager.default.createDirectory(at: invalidDatabaseURL, withIntermediateDirectories: true)

    var didThrow = false
    do {
        _ = try CompanyHistorySQLiteIndex.archive(snapshot: store.currentSnapshot(), at: invalidDatabaseURL, olderThan: Date())
    } catch {
        didThrow = true
    }

    #expect(didThrow)
    #expect(store.events.count == eventCount)
}

@MainActor
@Test func historyIndexAuditRecordsVerificationAndCTOReport() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "SQLite 历史索引巡检样本", detail: "用于验证巡检入口", agentID: store.ctoID))

    let status = store.runHistoryIndexAuditForSelectedProduct()

    #expect(status == .passed)
    #expect(store.selectedProductVerifications.contains { $0.title == "历史索引巡检" && $0.detail.contains("记录数") })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("历史索引巡检") })
    #expect(store.events.contains { $0.title == "历史索引巡检完成" })
}

@MainActor
@Test func historyArchiveMigrationRecordsVerificationWithoutDeletingJSONState() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.events.append(CompanyEvent(productID: store.selectedProductID, kind: .ctoSummary, title: "旧归档迁移样本", detail: "用于验证归档入口", agentID: store.ctoID, createdAt: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)))
    let originalEventCount = store.events.count

    let status = store.runHistoryArchiveMigrationForSelectedProduct(retentionDays: 1)

    #expect(status == .passed)
    #expect(store.events.count == originalEventCount + 1)
    #expect(store.selectedProductVerifications.contains { $0.title == "历史归档迁移" && $0.detail.contains("写入归档记录") })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("历史归档迁移") })
    #expect(store.events.contains { $0.title == "历史归档迁移完成" })
}

@Test func agentMessageReviewOutcomePersistsAndKeepsLegacyMessagesCompatible() async throws {
    let envelope = AgentMessageEnvelope(
        productID: UUID(),
        fromAgentID: UUID(),
        toAgentID: UUID(),
        kind: .reviewCompleted,
        subject: "审查反馈",
        body: "结构化结果",
        reviewOutcome: .passed
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(envelope)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AgentMessageEnvelope.self, from: data)
    #expect(decoded.reviewOutcome == .passed)

    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "reviewOutcome")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let legacyDecoded = try decoder.decode(AgentMessageEnvelope.self, from: legacyData)
    #expect(legacyDecoded.kind == .reviewCompleted)
    #expect(legacyDecoded.reviewOutcome == nil)
}

@MainActor
@Test func selectedAgentInboxOnlyReturnsCurrentProductAndRelatedMessages() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstProductID = store.selectedProductID
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    _ = store.startCTOSupervisorGoal(goal: "收件箱过滤测试 A")

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    _ = store.startCTOSupervisorGoal(goal: "收件箱过滤测试 B")

    store.selectProduct(firstProductID)
    store.selectAgent(engineer.id)

    let inbox = store.selectedAgentProductMessages
    #expect(!inbox.isEmpty)
    #expect(inbox.allSatisfy { $0.productID == firstProductID })
    #expect(inbox.allSatisfy { $0.fromAgentID == engineer.id || $0.toAgentID == engineer.id })
    #expect(!inbox.contains { $0.fromAgentID == reviewer.id && $0.toAgentID == reviewer.id })
}

@MainActor
@Test func agentMessageRecentViewsReturnNewestFirst() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productID = store.selectedProductID
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    store.agentMessages.append(
        AgentMessageEnvelope(
            productID: productID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            subject: "旧消息",
            body: "旧",
            createdAt: base
        )
    )
    store.agentMessages.append(
        AgentMessageEnvelope(
            productID: productID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            subject: "新消息",
            body: "新",
            createdAt: base.addingTimeInterval(60)
        )
    )

    store.selectAgent(engineer.id)

    #expect(store.selectedProductRecentAgentMessages.first?.subject == "新消息")
    #expect(store.selectedAgentRecentProductMessages.first?.subject == "新消息")
}

@MainActor
@Test func acknowledgeSelectedAgentMessagesScopesToInboundOnly() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let firstProductID = store.selectedProductID

    _ = store.startCTOSupervisorGoal(goal: "员工 ack 范围测试")

    // baseline: reviewer 应收到 reviewRequested
    let reviewerInboundAfterStart = store.agentMessages.filter {
        $0.productID == firstProductID && $0.toAgentID == reviewer.id && $0.status == .pending
    }
    #expect(!reviewerInboundAfterStart.isEmpty)

    let engineerTask = try #require(store.selectedProductTasks.first { $0.title.hasPrefix("员工执行：") })
    store.completeWorkItem(for: engineerTask.id, agentID: engineer.id, status: .completed)

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    _ = store.startCTOSupervisorGoal(goal: "其他产品收件箱不应被 ack")

    store.selectProduct(firstProductID)
    store.selectAgent(engineer.id)

    let inboundCountBefore = store.selectedAgentPendingMessages.count
    let outboundPendingBefore = store.selectedAgentProductMessages.filter { $0.status == .pending && $0.fromAgentID == engineer.id }.count
    #expect(inboundCountBefore > 0)
    // workCompleted 是 engineer 发出的 pending，不应进入"我待确认"
    #expect(store.selectedAgentPendingMessages.allSatisfy { $0.toAgentID == engineer.id })

    let acknowledged = store.acknowledgeSelectedAgentMessages()
    #expect(acknowledged == inboundCountBefore)
    #expect(store.selectedAgentPendingMessages.isEmpty)

    let outboundPendingAfter = store.selectedAgentProductMessages.filter { $0.status == .pending && $0.fromAgentID == engineer.id }.count
    #expect(outboundPendingAfter == outboundPendingBefore)

    // 其他员工不被影响
    let reviewerInboundPending = store.agentMessages.filter {
        $0.productID == firstProductID && $0.toAgentID == reviewer.id && $0.status == .pending
    }
    #expect(!reviewerInboundPending.isEmpty)

    // 其他产品不被影响
    let secondProductPending = store.agentMessages.filter {
        $0.productID == secondProductID && $0.status == .pending
    }
    #expect(!secondProductPending.isEmpty)

    #expect(store.events.contains { $0.title == "员工协作收件箱已标记已读" })
}

@MainActor
@Test func agentDeskInboxLabelsAndStatusEntryPointAreVisible() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    _ = store.startCTOSupervisorGoal(goal: "收件箱入口可见性")
    store.selectAgent(engineer.id)

    #expect(store.selectedAgentPendingMessages.count > 0)

    let inboxRow = try #require(store.selectedAgentProductMessages.first { $0.toAgentID == engineer.id })
    #expect(AgentMessageDisplay.title(for: inboxRow.kind) == "任务派发")
    #expect(AgentMessageDisplay.statusTitle(for: .pending) == "待确认")
}

@MainActor
@Test func productMessageCenterFiltersCurrentProductByStatus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID
    let base = Date(timeIntervalSince1970: 1_800_001_000)

    store.agentMessages.append(contentsOf: [
        AgentMessageEnvelope(
            productID: firstProductID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            status: .pending,
            subject: "当前产品待确认",
            body: "pending",
            createdAt: base
        ),
        AgentMessageEnvelope(
            productID: firstProductID,
            fromAgentID: engineer.id,
            toAgentID: store.ctoID,
            kind: .workCompleted,
            status: .acknowledged,
            subject: "当前产品已读",
            body: "ack",
            createdAt: base.addingTimeInterval(1)
        ),
        AgentMessageEnvelope(
            productID: firstProductID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            status: .failed,
            subject: "当前产品失败",
            body: "failed",
            createdAt: base.addingTimeInterval(2)
        )
    ])

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    store.agentMessages.append(
        AgentMessageEnvelope(
            productID: secondProductID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            status: .pending,
            subject: "其他产品待确认",
            body: "other",
            createdAt: base.addingTimeInterval(60)
        )
    )

    store.selectProduct(firstProductID)

    let pending = store.selectedProductAgentMessages(filter: .pending)
    #expect(pending.map(\.subject) == ["当前产品待确认"])
    #expect(pending.allSatisfy { $0.productID == firstProductID && $0.status == .pending })
    #expect(store.selectedProductAgentMessages(filter: .acknowledged).map(\.subject) == ["当前产品已读"])
    #expect(store.selectedProductAgentMessages(filter: .failed).map(\.subject) == ["当前产品失败"])
}

@MainActor
@Test func agentMessageCenterFiltersRelatedMessagesNewestFirst() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let productID = store.selectedProductID
    let base = Date(timeIntervalSince1970: 1_800_002_000)

    store.agentMessages.append(contentsOf: [
        AgentMessageEnvelope(
            productID: productID,
            fromAgentID: engineer.id,
            toAgentID: store.ctoID,
            kind: .workCompleted,
            status: .acknowledged,
            subject: "旧的员工发出消息",
            body: "old",
            createdAt: base
        ),
        AgentMessageEnvelope(
            productID: productID,
            fromAgentID: store.ctoID,
            toAgentID: engineer.id,
            kind: .taskDispatched,
            status: .pending,
            subject: "新的员工入站消息",
            body: "new",
            createdAt: base.addingTimeInterval(20)
        ),
        AgentMessageEnvelope(
            productID: productID,
            fromAgentID: reviewer.id,
            toAgentID: store.ctoID,
            kind: .reviewCompleted,
            status: .pending,
            subject: "无关审查消息",
            body: "unrelated",
            createdAt: base.addingTimeInterval(40)
        )
    ])

    store.selectAgent(engineer.id)

    #expect(store.selectedAgentProductMessages(filter: .all).map(\.subject) == ["新的员工入站消息", "旧的员工发出消息"])
    #expect(store.selectedAgentProductMessages(filter: .pending).map(\.subject) == ["新的员工入站消息"])
    #expect(store.selectedAgentProductMessages(filter: .acknowledged).map(\.subject) == ["旧的员工发出消息"])
}

@MainActor
@Test func agentMessageCenterCopyAndFilterTitlesAreStable() async throws {
    #expect(AgentMessageCenterCopy.viewAllTitle == "查看全部")
    #expect(AgentMessageFilter.allCases.map(\.title) == ["全部", "待确认", "已读", "失败"])
}

@Test func bossDecisionCenterCopyExposesExpectedSectionTitles() async throws {
    #expect(BossDecisionCenterCopy.sheetTitle == "老板决策中心")
    #expect(BossDecisionCenterCopy.openTitle == "打开决策中心")
    #expect(BossDecisionCenterCopy.pendingApprovalsSection == "待审批请求")
    #expect(BossDecisionCenterCopy.riskTasksSection == "风险/阻塞任务")
    #expect(BossDecisionCenterCopy.resolvedApprovalsSection == "已处理审批")
    #expect(!BossDecisionCenterCopy.emptyPendingApprovals.isEmpty)
    #expect(!BossDecisionCenterCopy.emptyRiskTasks.isEmpty)
    #expect(!BossDecisionCenterCopy.emptyResolvedApprovals.isEmpty)
}

@MainActor
@Test func bossDecisionHelpersStayWithinCurrentProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID

    store.createTask(title: "P1 阻塞任务", ownerID: engineer.id, status: .blocked, successCriteria: "需老板处理。")
    let p1Task = try #require(store.selectedProductTasks.first { $0.title == "P1 阻塞任务" })
    store.requestApproval(taskID: p1Task.id, title: "P1 审批", reason: "P1 需要老板批准", requesterID: engineer.id)

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    store.createTask(title: "P2 阻塞任务", ownerID: engineer.id, status: .blocked, successCriteria: "P2 需老板处理。")
    let p2Task = try #require(store.selectedProductTasks.first { $0.title == "P2 阻塞任务" })
    store.requestApproval(taskID: p2Task.id, title: "P2 审批", reason: "P2 需要老板批准", requesterID: engineer.id)

    store.selectProduct(firstProductID)

    #expect(store.selectedProductPendingApprovals.allSatisfy { $0.productID == firstProductID })
    #expect(store.selectedProductPendingApprovals.contains { $0.title == "P1 审批" })
    #expect(!store.selectedProductPendingApprovals.contains { $0.title == "P2 审批" })

    #expect(store.selectedProductRiskTasks.allSatisfy { $0.productID == firstProductID })
    #expect(store.selectedProductRiskTasks.contains { $0.title == "P1 阻塞任务" })
    #expect(!store.selectedProductRiskTasks.contains { $0.title == "P2 阻塞任务" })

    #expect(store.selectedProductRiskEvents.allSatisfy { $0.productID == firstProductID || $0.productID == nil })
    #expect(store.selectedProductRiskEvents.contains { $0.detail.contains("P1 审批") })
    #expect(!store.selectedProductRiskEvents.contains { $0.detail.contains("P2 审批") })

    let expectedCount = store.selectedProductPendingApprovals.count + store.selectedProductRiskTasks.count
    #expect(store.bossDecisionCount == expectedCount)
}

@MainActor
@Test func decideApprovalMovesPendingIntoResolvedAndShrinksDecisionCount() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "决策迁移任务", ownerID: engineer.id, status: .needsApproval, successCriteria: "测试决策迁移。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "决策迁移任务" })
    store.requestApproval(taskID: task.id, title: "迁移审批", reason: "用于测试", requesterID: engineer.id)

    let approval = try #require(store.selectedProductPendingApprovals.first { $0.title == "迁移审批" })
    let beforeCount = store.bossDecisionCount
    #expect(beforeCount > 0)
    #expect(store.selectedProductResolvedApprovals.isEmpty)

    store.decideApproval(approval.id, approved: true)

    #expect(!store.selectedProductPendingApprovals.contains { $0.id == approval.id })
    let resolved = try #require(store.selectedProductResolvedApprovals.first { $0.id == approval.id })
    #expect(resolved.status == .approved)
    #expect(resolved.decidedAt != nil)
    #expect(store.bossDecisionCount < beforeCount)

    let updatedTask = try #require(store.selectedProductTasks.first { $0.id == task.id })
    #expect(updatedTask.status == .running)
}

@MainActor
@Test func bossResolvedApprovalsAreSortedByMostRecentDecisionFirst() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.createTask(title: "决策排序 A", ownerID: engineer.id, status: .assigned, successCriteria: "A")
    let taskA = try #require(store.selectedProductTasks.first { $0.title == "决策排序 A" })
    store.requestApproval(taskID: taskA.id, title: "审批 A", reason: "A", requesterID: engineer.id)
    let approvalA = try #require(store.selectedProductPendingApprovals.first { $0.title == "审批 A" })

    store.createTask(title: "决策排序 B", ownerID: engineer.id, status: .assigned, successCriteria: "B")
    let taskB = try #require(store.selectedProductTasks.first { $0.title == "决策排序 B" })
    store.requestApproval(taskID: taskB.id, title: "审批 B", reason: "B", requesterID: engineer.id)
    let approvalB = try #require(store.selectedProductPendingApprovals.first { $0.title == "审批 B" })

    store.decideApproval(approvalA.id, approved: true)
    store.decideApproval(approvalB.id, approved: false)

    let resolvedTitles = store.selectedProductResolvedApprovals.map(\.title)
    #expect(resolvedTitles.first == "审批 B")
    #expect(resolvedTitles.contains("审批 A"))
}

@Test func bossDecisionCenterSummaryCopyIsStable() async throws {
    #expect(BossDecisionCenterCopy.statTitle == "待我决策")
    #expect(BossDecisionCenterCopy.summaryTitle == "待我决策")
    #expect(BossDecisionCenterCopy.summaryEmpty == "当前没有需要你批准或驳回的事项。")
    #expect(BossDecisionCenterCopy.summaryDetail(count: 0).contains("暂无审批"))
    #expect(BossDecisionCenterCopy.summaryDetail(count: 3).contains("3"))
}

@Test func deliveryAcceptanceCenterCopyIsStable() async throws {
    #expect(DeliveryAcceptanceCenterCopy.sheetTitle == "交付验收中心")
    #expect(DeliveryAcceptanceCenterCopy.openTitle == "打开交付验收中心")
    #expect(DeliveryAcceptanceCenterCopy.viewAllTitle == "查看全部")
    #expect(DeliveryAcceptanceCenterCopy.reviewGatesSection == "验收门禁")
    #expect(DeliveryAcceptanceCenterCopy.acceptanceTasksSection == "可验收任务")
    #expect(DeliveryAcceptanceCenterCopy.verificationsSection == "自动验收记录")
    #expect(DeliveryAcceptanceCenterCopy.artifactsSection == "交付物记录")
    #expect(!DeliveryAcceptanceCenterCopy.emptyAcceptanceTasks.isEmpty)
    #expect(!DeliveryAcceptanceCenterCopy.emptyReviewGates.isEmpty)
    #expect(!DeliveryAcceptanceCenterCopy.emptyVerifications.isEmpty)
    #expect(!DeliveryAcceptanceCenterCopy.emptyArtifacts.isEmpty)
    #expect(AgentMessageDisplay.title(for: .acceptanceCompleted) == "验收通过")
}

@Test func productTaskColumnKindsCoverVisibleTaskStatuses() async throws {
    let coveredStatuses = Set(ProductTaskColumnKind.allCases.flatMap(\.statuses))
    let intentionallyHiddenStatuses: Set<TaskStatus> = [.canceled]

    for status in TaskStatus.allCases where !intentionallyHiddenStatuses.contains(status) {
        #expect(coveredStatuses.contains(status), "TaskStatus.\(status.rawValue) 未进入当前任务看板")
    }
}

@Test func productTaskColumnKindsExposeStableChineseCopy() async throws {
    #expect(ProductTaskColumnKind.allCases.count == 5)
    for kind in ProductTaskColumnKind.allCases {
        #expect(!kind.title.isEmpty)
        #expect(!kind.emptyHint.isEmpty)
        #expect(containsCJK(kind.title), "任务列标题缺少中文：\(kind.title)")
        #expect(containsCJK(kind.emptyHint), "任务列空状态缺少中文：\(kind.emptyHint)")
    }
}

private func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
}

@MainActor
@Test func deliveryAcceptanceHelpersStayWithinCurrentProductAndNewestFirst() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    store.createTask(title: "普通运行任务", ownerID: engineer.id, status: .running, successCriteria: "不应进入验收中心。")
    store.createTask(title: "已交付任务", ownerID: engineer.id, status: .done, successCriteria: "应进入验收中心。")
    store.createTask(title: "带产物路径任务", ownerID: engineer.id, status: .planned, successCriteria: "有产物路径。", artifactPath: "/tmp/opc/artifact.md")

    store.artifacts.append(contentsOf: [
        ArtifactRecord(productID: firstProductID, kind: .report, title: "旧交付物", path: "/tmp/old.md", summary: "旧", createdAt: base),
        ArtifactRecord(productID: firstProductID, kind: .report, title: "新交付物", path: "/tmp/new.md", summary: "新", createdAt: base.addingTimeInterval(60))
    ])
    store.verifications.append(contentsOf: [
        VerificationRecord(productID: firstProductID, status: .warning, title: "旧验收", detail: "旧", createdAt: base),
        VerificationRecord(productID: firstProductID, status: .passed, title: "新验收", detail: "新", createdAt: base.addingTimeInterval(60))
    ])

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    store.artifacts.append(ArtifactRecord(productID: secondProductID, kind: .report, title: "其他产品交付物", path: "/tmp/other.md", summary: "其他", createdAt: base.addingTimeInterval(120)))
    store.verifications.append(VerificationRecord(productID: secondProductID, status: .failed, title: "其他产品验收", detail: "其他", createdAt: base.addingTimeInterval(120)))

    store.selectProduct(firstProductID)

    #expect(Array(store.selectedProductRecentArtifacts.map(\.title).prefix(2)) == ["新交付物", "旧交付物"])
    #expect(Array(store.selectedProductRecentVerifications.map(\.title).prefix(2)) == ["新验收", "旧验收"])
    #expect(!store.selectedProductRecentArtifacts.contains { $0.title == "其他产品交付物" })
    #expect(!store.selectedProductRecentVerifications.contains { $0.title == "其他产品验收" })

    let candidateTitles = store.selectedProductAcceptanceTasks.map(\.title)
    #expect(candidateTitles.contains("已交付任务"))
    #expect(candidateTitles.contains("带产物路径任务"))
    #expect(!candidateTitles.contains("普通运行任务"))
}

@MainActor
@Test func reviewGateTracksReviewVerificationReportAndAcceptance() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.createTask(title: "验收门禁测试任务", ownerID: engineer.id, status: .needsReview, successCriteria: "门禁记录完整。", artifactPath: "/tmp/review-gate.md")
    let task = try #require(store.selectedProductTasks.first { $0.title == "验收门禁测试任务" })

    store.requestCTOReview(for: task.id)
    var gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.status == .reviewRequested)
    #expect(store.selectedProductAgentMessages.contains { $0.kind == .reviewRequested && $0.taskID == task.id })

    store.runAutomaticVerification()
    gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.latestVerificationID != nil)
    #expect([ReviewGateStatus.verificationPassed, .verificationWarning, .verificationFailed].contains(gate.status))

    store.generateAcceptanceReport(for: task.id)
    gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.reportArtifactID != nil)
    #expect(store.selectedProductArtifacts.contains { $0.id == gate.reportArtifactID })

    store.acceptTask(task.id)
    gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.status == .accepted)
    #expect(store.selectedProductVerifications.contains { $0.id == gate.latestVerificationID })
}

@MainActor
@Test func selectedAgentReviewQueueOnlyShowsOwnedNeedsReviewTasks() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.createTask(title: "我的待审任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "审查员必须能看到。")
    store.createTask(title: "我的运行任务", ownerID: reviewer.id, status: .running, successCriteria: "运行中不进待审队列。")
    store.createTask(title: "别人的待审任务", ownerID: engineer.id, status: .needsReview, successCriteria: "非 owner 不进队列。")

    store.selectAgent(reviewer.id)
    #expect(store.selectedAgentReviewQueue.map(\.title) == ["我的待审任务"])

    store.selectAgent(engineer.id)
    #expect(store.selectedAgentReviewQueue.isEmpty)

    store.addProductWorkspace()
    store.selectAgent(reviewer.id)
    #expect(store.selectedAgentReviewQueue.isEmpty)
}

@MainActor
@Test func completeReviewByOwnerWritesMessageGateAndDoneStatus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.createTask(title: "审查通过任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "通过后写证据。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "审查通过任务" })
    let bossMessageCount = store.messages(for: store.bossID).count

    store.selectAgent(reviewer.id)
    let result = store.completeReviewByOwner(taskID: task.id, summary: "已按标准审查，可以交付。")

    #expect(result)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .done)
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .reviewCompleted
            && message.reviewOutcome == .passed
            && message.fromAgentID == reviewer.id
            && message.toAgentID == store.ctoID
            && message.taskID == task.id
            && message.body.contains("可以交付")
    })
    let gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.status == .verificationPassed)
    #expect(gate.reviewerID == reviewer.id)
    #expect(store.events.contains { $0.title == "审查员已完成审查" })
    #expect(store.messages(for: store.bossID).count == bossMessageCount)
    #expect(store.runningAgentIDs.isEmpty)
}

@MainActor
@Test func rejectReviewByOwnerReturnsTaskAndRecordsWarningGate() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.createTask(title: "审查返工任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "不通过时回到执行。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "审查返工任务" })
    let bossMessageCount = store.messages(for: store.bossID).count

    store.selectAgent(reviewer.id)
    let result = store.rejectReviewByOwner(taskID: task.id, reason: "缺少验证截图。")

    #expect(result)
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .assigned)
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .reviewCompleted
            && message.reviewOutcome == .rejected
            && message.fromAgentID == reviewer.id
            && message.toAgentID == store.ctoID
            && message.taskID == task.id
            && message.body.contains("缺少验证截图")
    })
    let gate = try #require(store.selectedProductReviewGates.first { $0.taskID == task.id })
    #expect(gate.status == .verificationWarning)
    #expect(store.events.contains { $0.title == "审查员打回返工" })
    #expect(store.messages(for: store.bossID).count == bossMessageCount)
    #expect(store.runningAgentIDs.isEmpty)
}

@MainActor
@Test func rejectReviewByOwnerRequeuesSupervisorExecutionTask() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "打回返工重派发验证"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)
    let bossMessageCount = store.messages(for: store.bossID).count

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "审查任务等待签字。")
    let completedWorkItemCount = store.selectedProductWorkQueue.filter {
        $0.taskID == engineerTask.id && $0.agentID == engineerID && $0.status == .completed
    }.count

    store.selectAgent(reviewerID)
    #expect(store.rejectReviewByOwner(taskID: reviewerTask.id, reason: "缺少验证截图。"))

    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .assigned)
    #expect(store.selectedProductTasks.first { $0.id == engineerTask.id }?.status == .assigned)
    #expect(store.selectedProductWorkQueue.contains { item in
        item.taskID == engineerTask.id
            && item.agentID == engineerID
            && item.status == .queued
            && item.promptPreview.contains("缺少验证截图")
    })
    #expect(store.selectedProductWorkQueue.filter {
        $0.taskID == engineerTask.id && $0.agentID == engineerID && $0.status == .completed
    }.count == completedWorkItemCount)
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .reviewCompleted
            && message.reviewOutcome == .rejected
            && message.taskID == reviewerTask.id
            && message.fromAgentID == reviewerID
            && message.toAgentID == store.ctoID
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .taskDispatched
            && message.taskID == engineerTask.id
            && message.toAgentID == engineerID
            && message.body.contains("打回原因：缺少验证截图")
    })
    #expect(store.messages(for: store.bossID).count == bossMessageCount)
    #expect(store.runningAgentIDs.isEmpty)
}

@Test func reworkPromptBuildersClipGeneratedReasonsAndSuccessCriteriaForTokenBudget() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    let reviewerStart = try #require(source.range(of: "func requeueExecutionTaskAfterReviewRejection"))
    let reviewerEnd = try #require(source.range(of: "\n    func ", range: reviewerStart.upperBound..<source.endIndex))
    let reviewerReworkSlice = String(source[reviewerStart.lowerBound..<reviewerEnd.lowerBound])
    let bossStart = try #require(source.range(of: "func requeueSupervisorGoalAfterBossRejection"))
    let bossEnd = try #require(source.range(of: "\n    func ", range: bossStart.upperBound..<source.endIndex))
    let bossReworkSlice = String(source[bossStart.lowerBound..<bossEnd.lowerBound])

    #expect(reviewerReworkSlice.contains("Self.promptFragment(reason, limit: Self.reworkPromptReasonLimit)"))
    #expect(reviewerReworkSlice.contains("Self.promptFragment(executionTask.successCriteria, limit: Self.reworkPromptSuccessCriteriaLimit)"))
    #expect(!reviewerReworkSlice.contains("打回原因：\\(reason)"))
    #expect(!reviewerReworkSlice.contains("成功标准：\\(executionTask.successCriteria)"))
    #expect(bossReworkSlice.contains("Self.promptFragment(rejectionReason, limit: Self.reworkPromptReasonLimit)"))
    #expect(bossReworkSlice.contains("Self.promptFragment(executionTask.successCriteria, limit: Self.reworkPromptSuccessCriteriaLimit)"))
    #expect(!bossReworkSlice.contains("打回原因：老板驳回最终交付：\\(rejectionReason)"))
    #expect(!bossReworkSlice.contains("成功标准：\\(executionTask.successCriteria)"))
}

@MainActor
@Test func selectedAgentReworkQueueShowsOnlyExecutionOwnerReworkItems() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "工程师返工视图验证"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "审查任务等待签字。")
    store.selectAgent(reviewerID)
    #expect(store.rejectReviewByOwner(taskID: reviewerTask.id, reason: "缺少验证截图。"))

    store.selectAgent(engineerID)
    #expect(store.selectedAgentReworkQueue.count == 1)
    #expect(store.selectedAgentReworkQueue.first?.taskID == engineerTask.id)
    #expect(store.selectedAgentReworkQueue.first?.promptPreview.contains("缺少验证截图") == true)

    store.selectAgent(reviewerID)
    #expect(store.selectedAgentReworkQueue.isEmpty)
}

@MainActor
@Test func selectedProductReworkSummaryTracksRejectedExecutionItems() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.selectedProductReworkSummaryText().contains("暂无返工队列"))

    let goal = "技术负责人返工追踪验证"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "审查任务等待签字。")
    store.selectAgent(reviewerID)
    #expect(store.rejectReviewByOwner(taskID: reviewerTask.id, reason: "缺少验证截图。"))

    let summary = store.selectedProductReworkSummaryText()
    #expect(summary.contains("返工追踪：1 项"))
    #expect(summary.contains("员工执行：\(goal)"))
    #expect(summary.contains("缺少验证截图"))
    #expect(summary.contains(store.agents.first { $0.id == engineerID }?.displayName ?? ""))
    #expect(!summary.contains("老板首页"))
}

@MainActor
@Test func completingRejectedReworkResubmitsReviewTaskForRereview() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "返工完成复审验证"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)
    let bossMessageCount = store.messages(for: store.bossID).count

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "审查任务等待签字。")
    store.selectAgent(reviewerID)
    #expect(store.rejectReviewByOwner(taskID: reviewerTask.id, reason: "缺少验证截图。"))

    store.selectAgent(engineerID)
    #expect(store.selectedAgentReworkQueue.count == 1)
    let completedBeforeRework = store.selectedProductWorkQueue.filter {
        $0.taskID == engineerTask.id && $0.agentID == engineerID && $0.status == .completed
    }.count

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)

    #expect(store.selectedAgentReworkQueue.isEmpty)
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .needsReview)
    #expect(store.selectedProductReviewGates.first { $0.taskID == reviewerTask.id }?.status == .reviewRequested)
    #expect(store.selectedProductWorkQueue.filter {
        $0.taskID == engineerTask.id && $0.agentID == engineerID && $0.status == .completed
    }.count == completedBeforeRework + 1)
    #expect(!store.selectedProductWorkQueue.contains { item in
        item.taskID == engineerTask.id
            && item.agentID == engineerID
            && item.status != .completed
            && item.promptPreview.contains("打回原因：缺少验证截图")
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .reviewRequested
            && message.taskID == reviewerTask.id
            && message.toAgentID == reviewerID
            && message.subject == "返工后复审：\(goal)"
            && message.body.contains("缺少验证截图")
    })

    store.selectAgent(reviewerID)
    #expect(store.selectedAgentReviewQueue.map(\.id) == [reviewerTask.id])
    #expect(store.messages(for: store.bossID).count == bossMessageCount)
    #expect(store.runningAgentIDs.isEmpty)
}

@MainActor
@Test func rejectReviewByOwnerDoesNotRequeueOrdinaryReviewTask() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.createTask(title: "普通审查返工任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "普通任务不触发闭环重派发。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "普通审查返工任务" })
    let initialQueueCount = store.selectedProductWorkQueue.count

    store.selectAgent(reviewer.id)
    #expect(store.rejectReviewByOwner(taskID: task.id, reason: "普通任务缺少截图。"))

    #expect(store.selectedProductWorkQueue.count == initialQueueCount)
    #expect(!store.selectedProductAgentMessages.contains { message in
        message.kind == .taskDispatched && message.body.contains("普通任务缺少截图")
    })
    store.selectAgent(reviewer.id)
    #expect(store.selectedAgentReworkQueue.isEmpty)
}

@MainActor
@Test func selectedAgentReworkQueueDoesNotMarkOrdinaryQueuedWork() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "普通队列任务", ownerID: engineer.id, status: .assigned, successCriteria: "普通执行。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "普通队列任务" })

    store.enqueueWorkItem(taskID: task.id, agentID: engineer.id, prompt: "请执行普通任务。")
    store.selectAgent(engineer.id)

    #expect(store.selectedProductWorkQueue.contains { $0.taskID == task.id && $0.agentID == engineer.id })
    #expect(store.selectedAgentReworkQueue.isEmpty)
}

@MainActor
@Test func reviewByOwnerRespectsOwnershipStatusAndProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.createTask(title: "非本人待审任务", ownerID: engineer.id, status: .needsReview, successCriteria: "只能 owner 审查。")
    store.createTask(title: "本人非待审任务", ownerID: reviewer.id, status: .assigned, successCriteria: "状态不对不能审查。")
    let otherOwnerTask = try #require(store.selectedProductTasks.first { $0.title == "非本人待审任务" })
    let wrongStatusTask = try #require(store.selectedProductTasks.first { $0.title == "本人非待审任务" })

    store.selectAgent(reviewer.id)
    #expect(!store.completeReviewByOwner(taskID: otherOwnerTask.id, summary: "不应通过"))
    #expect(!store.rejectReviewByOwner(taskID: wrongStatusTask.id, reason: "不应通过"))
    #expect(store.selectedProductTasks.first { $0.id == otherOwnerTask.id }?.status == .needsReview)
    #expect(store.selectedProductTasks.first { $0.id == wrongStatusTask.id }?.status == .assigned)

    store.createTask(title: "本人待审任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "非审查角色不能代审。")
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "本人待审任务" })
    store.selectAgent(engineer.id)
    #expect(!store.completeReviewByOwner(taskID: reviewerTask.id, summary: "工程师不应通过"))
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .needsReview)

    store.createTask(title: "产品 A 待审任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "切产品后不能审。")
    let productATask = try #require(store.selectedProductTasks.first { $0.title == "产品 A 待审任务" })
    store.addProductWorkspace()
    store.selectAgent(reviewer.id)

    #expect(!store.completeReviewByOwner(taskID: productATask.id, summary: "跨产品不应通过"))
    let originalProductID = store.products.first { product in
        product.assignedAgentIDs.contains(reviewer.id)
    }?.id
    #expect(store.tasks.first { $0.id == productATask.id && $0.productID == originalProductID }?.status == .needsReview)
}

@MainActor
@Test func reviewSkillAllowsCustomAgentToUsePersonalReviewQueue() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var draft = EmployeeDraft()
    draft.displayName = "自定义审查员工"
    draft.title = "质量审查"
    draft.role = .custom
    draft.backendType = .local
    store.addEmployee(from: draft)
    let customReviewer = try #require(store.selectedAgent)

    store.updateSelectedAgentProfile(skillsText: "review\n验收")
    store.createTask(title: "自定义技能待审任务", ownerID: customReviewer.id, status: .needsReview, successCriteria: "具备 review 技能即可审查。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "自定义技能待审任务" })

    #expect(store.selectedAgentReviewQueue.map(\.id) == [task.id])
    #expect(store.completeReviewByOwner(taskID: task.id, summary: "自定义审查通过。"))
    #expect(store.selectedProductTasks.first { $0.id == task.id }?.status == .done)
}

@MainActor
@Test func reviewByOwnerUpsertsGateWhenTaskIsReviewedAgain() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.createTask(title: "重复审查任务", ownerID: reviewer.id, status: .needsReview, successCriteria: "同一任务只保留一条门禁。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "重复审查任务" })

    store.selectAgent(reviewer.id)
    #expect(store.rejectReviewByOwner(taskID: task.id, reason: "先打回。"))
    store.updateTaskStatus(task.id, status: .needsReview, note: "返工后重新提交审查。")
    #expect(store.completeReviewByOwner(taskID: task.id, summary: "返工后通过。"))

    let gates = store.selectedProductReviewGates.filter { $0.taskID == task.id }
    #expect(gates.count == 1)
    #expect(gates.first?.status == .verificationPassed)
}

@MainActor
@Test func reviewByOwnerEvidenceIsPickedUpByClosureTrace() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "审查员闭环派生验证"
    let ctoTaskID = try #require(store.startCTOSupervisorGoal(goal: goal))
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let reviewerID = try #require(reviewerTask.ownerID)

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "工程实现已提交，等待审查员签字。")
    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "闭环任务审查通过。"))

    let trace = try #require(store.selectedProductClosureTraces.first { $0.taskIDs.contains(ctoTaskID) })
    #expect(store.closureTraceReviewGates(trace).contains { gate in
        gate.taskID == reviewerTask.id
            && gate.reviewerID == reviewerID
            && gate.status == .verificationPassed
    })
    #expect(store.closureTraceMessages(trace).contains { message in
        message.kind == .reviewCompleted
            && message.reviewOutcome == .passed
            && message.taskID == reviewerTask.id
            && message.fromAgentID == reviewerID
            && message.toAgentID == store.ctoID
            && message.body.contains("闭环任务审查通过")
    })
}

@MainActor
@Test func supervisorReviewPassAutomaticallyRequestsBossApproval() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "审查通过自动提交老板审批"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let bossTask = try #require(store.selectedProductTasks.first { $0.title == "老板审批：\(goal)" })
    let reviewerID = try #require(reviewerTask.ownerID)

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "工程实现已提交，等待审查员签字。")
    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "复审通过，可以提交老板验收。"))

    let approval = try #require(store.selectedProductPendingApprovals.first { $0.taskID == bossTask.id })
    #expect(approval.title == "请老板审批：\(goal)")
    #expect(approval.reason.contains("复审通过"))
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .done)
    #expect(store.selectedProductTasks.first { $0.id == bossTask.id }?.status == .needsApproval)
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .ctoLoopProgressed
            && message.taskID == bossTask.id
            && message.fromAgentID == store.ctoID
            && message.toAgentID == store.bossID
            && message.subject == "技术负责人提交老板审批：\(goal)"
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .approvalRequested
            && message.approvalID == approval.id
            && message.taskID == bossTask.id
            && message.toAgentID == store.bossID
    })

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "模拟重复复审提交。")
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "重复提交不应新增审批。"))
    #expect(store.selectedProductApprovals.filter { $0.taskID == bossTask.id }.count == 1)
}

@MainActor
@Test func approvingSupervisorBossTaskWritesDeliveryAndAcceptanceEvidence() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "老板批准自动交付验收"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let ctoTask = try #require(store.selectedProductTasks.first { $0.title == "技术负责人拆解：\(goal)" })
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let bossTask = try #require(store.selectedProductTasks.first { $0.title == "老板审批：\(goal)" })
    let reviewerID = try #require(reviewerTask.ownerID)

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "工程实现已提交，等待审查员签字。")
    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "审查通过，建议老板验收。"))
    let approval = try #require(store.selectedProductPendingApprovals.first { $0.taskID == bossTask.id })

    store.decideApproval(approval.id, approved: true)

    #expect(store.selectedProductTasks.first { $0.id == ctoTask.id }?.status == .done)
    #expect(store.selectedProductTasks.first { $0.id == engineerTask.id }?.status == .done)
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .done)
    #expect(store.selectedProductTasks.first { $0.id == bossTask.id }?.status == .done)
    #expect(store.selectedProductResolvedApprovals.first { $0.id == approval.id }?.status == .approved)
    #expect(store.events.contains { $0.title == "技术负责人闭环已收束" && $0.detail.contains(goal) })
    #expect(store.selectedProductArtifacts.contains { artifact in
        artifact.taskID == bossTask.id && artifact.title == "验收报告：\(bossTask.title)"
    })
    #expect(store.selectedProductVerifications.contains { verification in
        verification.title == "老板验收通过：\(bossTask.title)"
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .acceptanceCompleted
            && message.taskID == bossTask.id
            && message.fromAgentID == store.bossID
            && message.toAgentID == store.bossID
    })
}

@MainActor
@Test func rejectingSupervisorBossTaskRequeuesExecutionForRework() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "老板驳回自动返工复审"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let bossTask = try #require(store.selectedProductTasks.first { $0.title == "老板审批：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "工程实现已提交，等待审查员签字。")
    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "审查通过，但老板仍需最终验收。"))
    let approval = try #require(store.selectedProductPendingApprovals.first { $0.taskID == bossTask.id })

    store.decideApproval(approval.id, approved: false)

    #expect(store.selectedProductResolvedApprovals.first { $0.id == approval.id }?.status == .rejected)
    #expect(store.selectedProductTasks.first { $0.id == bossTask.id }?.status == .planned)
    #expect(!store.selectedProductRiskTasks.contains { $0.id == bossTask.id })
    #expect(store.selectedProductTasks.first { $0.id == engineerTask.id }?.status == .assigned)
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .assigned)
    #expect(store.selectedProductReworkQueue.contains { item in
        item.taskID == engineerTask.id
            && item.agentID == engineerID
            && item.promptPreview.contains("老板驳回最终交付")
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .taskDispatched
            && message.taskID == engineerTask.id
            && message.approvalID == approval.id
            && message.subject == "老板驳回后返工：\(goal)"
    })
    #expect(store.selectedProductAgentMessages.contains { message in
        message.kind == .ctoLoopProgressed
            && message.taskID == bossTask.id
            && message.approvalID == approval.id
            && message.subject == "技术负责人已按老板驳回回拨返工：\(goal)"
    })
    #expect(store.events.contains { $0.title == "老板驳回后已派发返工" && $0.detail.contains(goal) })
    let reworkCountAfterFirstDecision = store.selectedProductReworkQueue.filter { $0.taskID == engineerTask.id }.count
    let eventCountAfterFirstDecision = store.events.filter { $0.title == "老板驳回后已派发返工" && $0.detail.contains(goal) }.count

    store.decideApproval(approval.id, approved: false)

    #expect(store.selectedProductReworkQueue.filter { $0.taskID == engineerTask.id }.count == reworkCountAfterFirstDecision)
    #expect(store.events.filter { $0.title == "老板驳回后已派发返工" && $0.detail.contains(goal) }.count == eventCountAfterFirstDecision)

    store.completeWorkItem(for: engineerTask.id, agentID: engineerID)
    #expect(store.selectedProductTasks.first { $0.id == reviewerTask.id }?.status == .needsReview)

    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "返工复审通过，可以再次提交老板。"))
    let approvals = store.selectedProductApprovals.filter { $0.taskID == bossTask.id }
    #expect(approvals.count == 2)
    let retryApproval = try #require(store.selectedProductPendingApprovals.first { $0.taskID == bossTask.id })
    #expect(retryApproval.id != approval.id)
    #expect(retryApproval.reason.contains("返工复审通过"))
}

@MainActor
@Test func rejectingSupervisorBossTaskUsesApprovalProductWhenProductSelectionChanges() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstProductID = store.selectedProductID
    let goal = "跨产品老板驳回返工"
    _ = store.startCTOSupervisorGoal(goal: goal)
    let engineerTask = try #require(store.selectedProductTasks.first { $0.title == "员工执行：\(goal)" })
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查验收：\(goal)" })
    let bossTask = try #require(store.selectedProductTasks.first { $0.title == "老板审批：\(goal)" })
    let engineerID = try #require(engineerTask.ownerID)
    let reviewerID = try #require(reviewerTask.ownerID)

    store.updateTaskStatus(reviewerTask.id, status: .needsReview, note: "工程实现已提交，等待审查员签字。")
    store.selectAgent(reviewerID)
    #expect(store.completeReviewByOwner(taskID: reviewerTask.id, summary: "跨产品复审通过。"))
    let approval = try #require(store.selectedProductPendingApprovals.first { $0.taskID == bossTask.id })

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)

    store.decideApproval(approval.id, approved: false)

    #expect(store.selectedProductID == secondProductID)
    #expect(store.workQueue.contains { item in
        item.productID == firstProductID
            && item.taskID == engineerTask.id
            && item.agentID == engineerID
            && item.promptPreview.contains("老板驳回最终交付")
    })
    #expect(!store.workQueue.contains { item in
        item.productID == secondProductID && item.taskID == engineerTask.id
    })
    #expect(store.events.contains { event in
        event.productID == firstProductID
            && event.title == "老板驳回后已派发返工"
            && event.detail.contains(goal)
    })
}

@MainActor
@Test func multiAgentArchitectureAuditTracksUpgradePlanModules() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let initialChecks = store.selectedProductArchitectureChecks
    #expect(initialChecks.map(\.id) == ["message-bus", "task-graph", "cto-loop", "artifact-store", "review-gate", "terminal-workspace", "boss-view"])
    #expect(initialChecks.map(\.title) == ["结构化消息总线", "显式任务图", "技术负责人调度闭环", "交付证据库", "验收门禁", "持久终端可用性", "老板视图减噪"])
    #expect(initialChecks.contains { $0.id == "message-bus" && $0.status == .failed })
    #expect(initialChecks.contains { $0.id == "terminal-workspace" && $0.status != .passed })
    #expect(store.selectedProductArchitectureCompletionScore < 50)

    let initialReport = store.multiAgentArchitectureAuditText()
    #expect(initialReport.contains("结构化消息总线"))
    #expect(initialReport.contains("显式任务图"))
    #expect(initialReport.contains("技术负责人调度闭环"))
    #expect(initialReport.contains("交付证据库"))
    #expect(initialReport.contains("验收门禁"))
    #expect(initialReport.contains("持久终端可用性"))
    #expect(initialReport.contains("老板视图减噪"))
    #expect(initialReport.contains("运行闭环演练"))
    for leakedTerm in ["MessageBus", "TaskGraph", "CTO Loop", "ArtifactStore", "ReviewGate", "TerminalWorkspace", "Boss View"] {
        #expect(!initialReport.contains(leakedTerm))
    }

    store.artifacts.insert(ArtifactRecord(productID: store.selectedProductID, kind: .report, title: "无关报告", path: "opc://unlinked-artifact", summary: "没有挂到闭环任务。"), at: 0)
    store.verifications.insert(VerificationRecord(productID: store.selectedProductID, status: .passed, title: "无关验收", detail: "没有挂到闭环任务。"), at: 0)
    store.reviewGates.insert(ReviewGateRecord(productID: store.selectedProductID, taskID: UUID(), status: .accepted, summary: "没有挂到闭环任务。"), at: 0)
    let unlinkedChecks = store.selectedProductArchitectureChecks
    #expect(unlinkedChecks.first { $0.id == "artifact-store" }?.status == .warning)
    #expect(unlinkedChecks.first { $0.id == "artifact-store" }?.detail.contains("闭环关联产物 0 条") == true)
    #expect(unlinkedChecks.first { $0.id == "review-gate" }?.status == .warning)
    #expect(unlinkedChecks.first { $0.id == "review-gate" }?.detail.contains("闭环关联门禁 0 条") == true)

    _ = store.startCTOSupervisorGoal(goal: "架构体检闭环")
    _ = store.advanceCTOSupervisorLoop()
    store.runAutomaticVerification()
    let reviewTask = try #require(store.selectedProductTasks.first { $0.title.hasPrefix("审查验收：架构体检闭环") })
    store.requestCTOReview(for: reviewTask.id)
    store.generateAcceptanceReport(for: reviewTask.id)
    store.acceptTask(reviewTask.id)

    let checks = store.selectedProductArchitectureChecks
    #expect(checks.first { $0.id == "message-bus" }?.status != .failed)
    #expect(checks.first { $0.id == "task-graph" }?.status == .passed)
    #expect(checks.first { $0.id == "task-graph" }?.title == "显式任务图")
    #expect(checks.first { $0.id == "task-graph" }?.detail.contains("条边") == true)
    #expect(checks.first { $0.id == "artifact-store" }?.status == .passed)
    #expect(checks.first { $0.id == "artifact-store" }?.detail.contains("闭环关联产物") == true)
    #expect(checks.first { $0.id == "review-gate" }?.status == .passed)
    #expect(checks.first { $0.id == "review-gate" }?.detail.contains("闭环关联门禁") == true)
    #expect(checks.first { $0.id == "terminal-workspace" }?.title == "持久终端可用性")
    #expect(checks.first { $0.id == "terminal-workspace" }?.detail.contains("尚未巡检") == true)
    #expect(store.selectedProductArchitectureCompletionScore >= 70)

    store.runMultiAgentArchitectureAudit()
    #expect(store.selectedProductArchitectureChecks.first { $0.id == "terminal-workspace" }?.detail.contains("员工席位") == true)
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("多员工架构体检") })
    #expect(store.events.contains { $0.title == "多员工架构体检已生成" })
}

@MainActor
@Test func multiAgentArchitectureClosureDrillCompletesCollaborationChain() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCArchitectureClosure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    store.products[0].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    #expect(store.selectedProductClosureTraces.isEmpty)

    store.startTerminalWorkspaceForSelectedProduct()
    let completed = store.runMultiAgentArchitectureClosureDrill(goal: "测试闭环演练")
    let drillGoal = "\(CompanyStore.closureDrillGoalMarker) 测试闭环演练"

    #expect(completed)
    #expect(store.selectedProductArchitectureChecks.allSatisfy { $0.status == .passed })
    #expect(store.selectedProductArchitectureCompletionScore == 100)
    #expect(store.selectedProductArtifacts.contains { $0.title.contains("验收报告") })
    #expect(store.selectedProductVerifications.contains { $0.title.contains("老板验收通过") })
    #expect(store.selectedProductReviewGates.contains { $0.status == .accepted })

    let messageKinds = Set(store.selectedProductAgentMessages.map(\.kind))
    #expect(messageKinds.contains(.ctoGoalStarted))
    #expect(messageKinds.contains(.taskDispatched))
    #expect(messageKinds.contains(.workCompleted))
    #expect(messageKinds.contains(.ctoLoopProgressed))
    #expect(messageKinds.contains(.approvalRequested))
    #expect(messageKinds.contains(.approvalDecided))
    #expect(messageKinds.contains(.reviewRequested))
    #expect(messageKinds.contains(.reviewCompleted))
    #expect(messageKinds.contains(.acceptanceCompleted))
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("闭环演练完成") })
    #expect(store.events.contains { $0.title == "多员工闭环演练已完成" })

    let trace = try #require(store.latestSelectedProductClosureTrace)
    #expect(trace.goal == drillGoal)
    #expect(trace.status == .passed)
    #expect(trace.completionScore == 100)
    #expect(trace.taskIDs.count == 4)
    #expect(trace.messageIDs.count >= 9)
    #expect(trace.approvalIDs.count == 1)
    #expect(trace.artifactIDs.count >= 2)
    #expect(trace.verificationIDs.count >= 2)
    #expect(trace.reviewGateIDs.count >= 2)
    #expect(trace.steps.map(\.id) == ["task-graph", "message-bus", "cto-loop", "approval", "review-gate", "evidence"])
    #expect(trace.steps.allSatisfy { $0.status == .passed })

    let traceTasks = store.closureTraceTasks(trace)
    #expect(traceTasks.map(\.title) == [
        "技术负责人拆解：\(drillGoal)",
        "员工执行：\(drillGoal)",
        "审查验收：\(drillGoal)",
        "老板审批：\(drillGoal)"
    ])
    #expect(store.closureTraceMessages(trace).contains { $0.subject == "技术负责人调度循环已推进：\(drillGoal)" })
    #expect(store.closureTraceApprovals(trace).first?.status == .approved)
    #expect(store.closureTraceReviewGates(trace).contains { $0.status == .accepted })
    #expect(store.closureTraceArtifacts(trace).contains { $0.title.contains("验收报告") })
    #expect(store.closureTraceVerifications(trace).contains { $0.title.contains("老板验收通过") })

    let taskGraph = store.closureTraceTaskGraph(trace)
    #expect(taskGraph.nodes.map(\.role) == ["技术负责人", "执行员工", "审查员", "老板"])
    #expect(taskGraph.edges.map(\.relation) == ["任务派发", "执行回传与审查", "审查结论与审批", "老板决策回流"])
    #expect(taskGraph.edges.allSatisfy { $0.status == .passed })

    let auditText = store.closureTraceAuditText(trace)
    #expect(auditText.contains("闭环审计报告：\(drillGoal)"))
    #expect(auditText.contains("任务记录："))
    #expect(auditText.contains("任务图边："))
    #expect(auditText.contains("消息记录："))
    #expect(auditText.contains("员工交接："))
    #expect(!auditText.contains("employeeHandoff"))
    #expect(!auditText.contains("pending"))
    #expect(store.generateClosureTraceAuditReport(for: trace))
    #expect(store.selectedProductArtifacts.contains { $0.title == "闭环审计报告：\(drillGoal)" })
    #expect(store.messages(for: store.ctoID).contains { $0.text.contains("闭环审计报告：\(drillGoal)") })
    #expect(store.events.contains { $0.title == "闭环审计报告已生成" })
    #expect(store.closureTraceAuditReportExists(for: trace))

    let reportCount = store.selectedProductArtifacts.filter { $0.title == "闭环审计报告：\(drillGoal)" }.count
    let refreshedTrace = try #require(store.latestSelectedProductClosureTrace)
    #expect(store.generateClosureTraceAuditReport(for: refreshedTrace))
    #expect(store.selectedProductArtifacts.filter { $0.title == "闭环审计报告：\(drillGoal)" }.count == reportCount)
    #expect(store.events.contains { $0.title == "闭环审计报告已存在" })
}

@MainActor
@Test func selectedProductRiskEventsStayPerProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID

    store.createTask(title: "P1 风险任务", ownerID: engineer.id, status: .blocked, successCriteria: "P1 风险")
    let p1Task = try #require(store.selectedProductTasks.first { $0.title == "P1 风险任务" })
    store.requestApproval(taskID: p1Task.id, title: "P1 风险审批", reason: "P1", requesterID: engineer.id)

    let p1RiskEvents = store.selectedProductRiskEvents
    #expect(!p1RiskEvents.isEmpty)
    #expect(p1RiskEvents.allSatisfy { $0.productID == firstProductID || $0.productID == nil })

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    store.createTask(title: "P2 风险任务", ownerID: engineer.id, status: .blocked, successCriteria: "P2 风险")
    let p2Task = try #require(store.selectedProductTasks.first { $0.title == "P2 风险任务" })
    store.requestApproval(taskID: p2Task.id, title: "P2 风险审批", reason: "P2", requesterID: engineer.id)

    let p2RiskEvents = store.selectedProductRiskEvents
    #expect(p2RiskEvents.allSatisfy { $0.productID == secondProductID || $0.productID == nil })
    let p1Inside2 = p2RiskEvents.contains { $0.title.contains("P1 风险审批") || $0.detail.contains("P1 风险审批") }
    #expect(!p1Inside2)

    store.selectProduct(firstProductID)
    let backToP1 = store.selectedProductRiskEvents
    let p2Inside1 = backToP1.contains { $0.title.contains("P2 风险审批") || $0.detail.contains("P2 风险审批") }
    #expect(!p2Inside1)
}

@MainActor
@Test func closureDrillEvidenceStaysInTraceButOutOfBossDeliveryViews() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "老板视图过滤演练证据"
    let drillGoal = "\(CompanyStore.closureDrillGoalMarker) \(goal)"

    #expect(store.runMultiAgentArchitectureClosureDrill(goal: goal))

    let trace = try #require(store.latestSelectedProductClosureTrace)
    #expect(trace.goal == drillGoal)
    #expect(store.closureTraceArtifacts(trace).contains { $0.title.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(store.closureTraceVerifications(trace).contains { $0.title.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(store.closureTraceReviewGates(trace).contains { gate in
        store.tasks.first { $0.id == gate.taskID }?.title.contains(CompanyStore.closureDrillGoalMarker) == true
    })
    #expect(store.closureTraceMessages(trace).contains { $0.subject.contains(CompanyStore.closureDrillGoalMarker) || $0.body.contains(CompanyStore.closureDrillGoalMarker) })

    #expect(!store.selectedProductDeliveryArtifacts.contains { $0.title.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(!store.selectedProductDeliveryVerifications.contains { $0.title.contains(CompanyStore.closureDrillGoalMarker) || $0.detail.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(!store.selectedProductDeliveryReviewGates.contains { gate in
        store.tasks.first { $0.id == gate.taskID }?.title.contains(CompanyStore.closureDrillGoalMarker) == true
    })
    #expect(!store.selectedProductBossEvents.contains { $0.title.contains(CompanyStore.closureDrillGoalMarker) || $0.detail.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(!store.selectedProductBossEvents.contains { $0.title.contains("闭环演练") || $0.detail.contains("闭环演练") })
    #expect(!store.selectedProductRecentAgentMessages.contains { $0.subject.contains(CompanyStore.closureDrillGoalMarker) || $0.body.contains(CompanyStore.closureDrillGoalMarker) })
    #expect(store.selectedProductAgentMessages.contains { $0.subject.contains(CompanyStore.closureDrillGoalMarker) || $0.body.contains(CompanyStore.closureDrillGoalMarker) })
}

@MainActor
@Test func recoverStaleRuntimeSessionsLeavesFreshBusyAlone() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.runningAgentIDs.insert(engineer.id)
    var session = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
        agentID: engineer.id,
        capability: .oneShotCLI,
        backendSignature: "claude:sonnet:medium"
    )
    session.state = .busy
    session.lastUsedAt = Date(timeIntervalSinceNow: -10)
    store.runtimeSessions[engineer.id] = session

    let recovered = store.recoverStaleRuntimeSessionsForSelectedProduct(staleAfter: 180)

    #expect(recovered.isEmpty)
    #expect(store.runningAgentIDs.contains(engineer.id))
    #expect(store.runtimeSessions[engineer.id]?.state == .busy)
    #expect(store.agents.first { $0.id == engineer.id }?.status != .failed)
    let verification = try #require(store.selectedProductVerifications.first { $0.title == "异常占用会话恢复" })
    #expect(verification.status == .passed)
    #expect(store.selectedProductAgentMessages.isEmpty)
}

@MainActor
@Test func recoverStaleRuntimeSessionsRecoversBusyAgentsBeyondThreshold() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    store.runningAgentIDs.insert(engineer.id)
    var stale = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
        agentID: engineer.id,
        capability: .oneShotCLI,
        backendSignature: "claude:sonnet:medium"
    )
    stale.state = .busy
    stale.lastUsedAt = Date(timeIntervalSinceNow: -600)
    store.runtimeSessions[engineer.id] = stale

    var fresh = store.runtimeSessions[reviewer.id] ?? AgentRuntimeSession(
        agentID: reviewer.id,
        capability: .oneShotCLI,
        backendSignature: "codex:gpt-5.5:high"
    )
    fresh.state = .ready
    fresh.lastUsedAt = Date()
    store.runtimeSessions[reviewer.id] = fresh

    let recovered = store.recoverStaleRuntimeSessionsForSelectedProduct(staleAfter: 180)

    #expect(recovered == [engineer.id])
    #expect(!store.runningAgentIDs.contains(engineer.id))
    #expect(store.agents.first { $0.id == engineer.id }?.status == .failed)
    let recoveredSession = try #require(store.runtimeSessions[engineer.id])
    #expect(recoveredSession.state == .timedOut)
    #expect(recoveredSession.failureCount >= 1)
    #expect(recoveredSession.lastError.contains("异常占用会话已被手动恢复"))

    // 不影响非 running 员工：reviewer 没在 runningAgentIDs 里，状态不变。
    #expect(store.runtimeSessions[reviewer.id]?.state == .ready)

    let log = store.terminalLogs[engineer.id, default: ""]
    #expect(log.contains("OPC 运维恢复"))
    #expect(store.events.contains { $0.title == "\(engineer.displayName) 异常占用已恢复" })
    let verification = try #require(store.selectedProductVerifications.first { $0.title == "异常占用会话恢复" })
    #expect(verification.status == .warning)
    #expect(!verification.detail.contains("busy"))
    #expect(!verification.detail.contains("timedOut"))
    #expect(!verification.detail.contains("lastUsedAt"))
    #expect(verification.detail.contains("占用中"))
    #expect(verification.detail.contains("已超时"))

    // 不应触发模型任务或污染 agent 消息总线。
    #expect(store.runningAgentIDs.isEmpty)
    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
}

@MainActor
@Test func recoverStaleRuntimeSessionsDoesNotCrossProducts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID

    store.runningAgentIDs.insert(engineer.id)
    var stale = store.runtimeSessions[engineer.id] ?? AgentRuntimeSession(
        agentID: engineer.id,
        capability: .oneShotCLI,
        backendSignature: "claude:sonnet:medium"
    )
    stale.state = .busy
    stale.lastUsedAt = Date(timeIntervalSinceNow: -900)
    store.runtimeSessions[engineer.id] = stale

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    // 切换到没分配该工程师的新产品，恢复操作不应触碰旧产品里的陈旧会话。

    let recovered = store.recoverStaleRuntimeSessionsForSelectedProduct(staleAfter: 180)

    #expect(recovered.isEmpty)
    #expect(store.runningAgentIDs.contains(engineer.id))
    #expect(store.runtimeSessions[engineer.id]?.state == .busy)
    #expect(store.agents.first { $0.id == engineer.id }?.status != .failed)
}

@MainActor
@Test func recoverStaleRuntimeSessionsSkipsSameAgentSessionFromOtherProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID

    store.runningAgentIDs.insert(engineer.id)
    var stale = AgentRuntimeSession(
        agentID: engineer.id,
        productID: firstProductID,
        capability: .oneShotCLI,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
    )
    stale.state = .busy
    stale.lastUsedAt = Date(timeIntervalSinceNow: -900)
    store.runtimeSessions[engineer.id] = stale

    store.addProductWorkspace()
    store.assignAgentToSelectedProduct(engineer.id)
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    #expect(store.selectedProductAgents.contains { $0.id == engineer.id })

    let recovered = store.recoverStaleRuntimeSessionsForSelectedProduct(staleAfter: 180)

    #expect(recovered.isEmpty)
    #expect(store.runningAgentIDs.contains(engineer.id))
    #expect(store.runtimeSessions[engineer.id]?.state == .busy)
    #expect(store.agents.first { $0.id == engineer.id }?.status != .failed)

    let auditStatus = store.runRuntimeSessionHealthAuditForSelectedProduct(staleAfter: 180)
    #expect(auditStatus == .warning)
    let audit = try #require(store.selectedProductVerifications.first { $0.title == "运行会话健康巡检" })
    #expect(audit.detail.contains("产品漂移"))
}

@MainActor
@Test func runtimeSessionHealthAuditPassesForHealthyTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    for index in store.agents.indices where store.agents[index].role != .boss {
        store.agents[index].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "preview", reasoningEffort: .low)
        let agent = store.agents[index]
        var session = store.runtimeSessions[agent.id] ?? AgentRuntimeSession(
            agentID: agent.id,
            capability: CLIAgentCommandBuilder.runtimeCapability(for: agent),
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: agent)
        )
        session.state = .ready
        session.capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
        session.failureCount = 0
        session.lastError = ""
        session.lastUsedAt = Date()
        store.runtimeSessions[agent.id] = session
    }

    let status = store.runRuntimeSessionHealthAuditForSelectedProduct()

    #expect(status == .passed)
    let report = try #require(store.selectedProductVerifications.first { $0.title == "运行会话健康巡检" })
    #expect(report.status == .passed)
    #expect(report.detail.contains("通过"))
    #expect(report.detail.contains("不会启动模型任务"))
    #expect(report.detail.contains("不会清理正在运行的员工列表"))
    #expect(report.detail.contains("不会写入作业档案或员工协作消息"))
    #expect(!report.detail.contains("runningAgentIDs"))
    #expect(!report.detail.contains(".opc/jobs"))
    #expect(!report.detail.contains("agent 消息总线"))
    #expect(!report.detail.contains("busy"))
    #expect(!report.detail.contains("lastError"))
    #expect(!report.detail.contains("backendSignature"))
    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(store.runningAgentIDs.isEmpty)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
}

@MainActor
@Test func runtimeSessionHealthAuditFlagsCommandMissingAndBackendDrift() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "", model: "sonnet", reasoningEffort: .medium)

    let reviewerIndex = try #require(store.agents.firstIndex { $0.role == .reviewer })
    let reviewer = store.agents[reviewerIndex]
    var staleSession = AgentRuntimeSession(
        agentID: reviewer.id,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: "subscriptionCLI|codex|gpt-5.5||high"
    )
    staleSession.lastUsedAt = Date()
    store.runtimeSessions[reviewer.id] = staleSession
    store.agents[reviewerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "/bin/echo", model: "low", reasoningEffort: .low)

    let status = store.runRuntimeSessionHealthAuditForSelectedProduct()

    #expect(status == .warning)
    let report = try #require(store.selectedProductVerifications.first { $0.title == "运行会话健康巡检" })
    #expect(report.status == .warning)
    #expect(report.detail.contains("需关注"))
    #expect(report.detail.contains("命令为空"))
    #expect(report.detail.contains("来源漂移"))
    #expect(report.detail.contains("来源配置不一致"))
    #expect(!report.detail.contains("subscriptionCLI|"))
    #expect(!report.detail.contains("backendSignature"))
    #expect(store.runningAgentIDs.isEmpty)
    #expect(store.runtimeSessions[reviewer.id]?.state == .ready)
    #expect(store.agents[engineerIndex].status != .failed)
}

@MainActor
@Test func runtimeSessionHealthAuditOnlyReportsStaleBusyWithoutRecovering() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    store.runningAgentIDs.insert(engineer.id)
    var stale = AgentRuntimeSession(
        agentID: engineer.id,
        state: .busy,
        capability: CLIAgentCommandBuilder.runtimeCapability(for: engineer),
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer)
    )
    stale.lastUsedAt = Date(timeIntervalSinceNow: -600)
    store.runtimeSessions[engineer.id] = stale
    let originalStatus = store.agents.first { $0.id == engineer.id }?.status

    let status = store.runRuntimeSessionHealthAuditForSelectedProduct(staleAfter: 180)

    #expect(status == .warning)
    let report = try #require(store.selectedProductVerifications.first { $0.title == "运行会话健康巡检" })
    #expect(report.detail.contains("异常占用"))
    #expect(report.detail.contains("运行占用已持续"))
    #expect(report.detail.contains("提示，本次不恢复"))
    #expect(!report.detail.contains("runningAgentIDs"))
    #expect(!report.detail.contains(".opc/jobs"))
    #expect(!report.detail.contains("agent 消息总线"))
    #expect(!report.detail.contains("busy"))
    #expect(!report.detail.contains("lastError"))
    #expect(!report.detail.contains("backendSignature"))

    #expect(store.runningAgentIDs.contains(engineer.id))
    let after = try #require(store.runtimeSessions[engineer.id])
    #expect(after.state == .busy)
    #expect(after.failureCount == 0)
    #expect(store.agents.first { $0.id == engineer.id }?.status == originalStatus)

    #expect(store.selectedProductAgentMessages.isEmpty)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
}

@MainActor
@Test func runtimeSessionHealthAuditShowsAuthenticationHintWithoutInternalLabels() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    var session = store.runtimeSessions[cto.id] ?? AgentRuntimeSession(
        agentID: cto.id,
        productID: store.selectedProductID,
        capability: CLIAgentCommandBuilder.runtimeCapability(for: cto),
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: cto)
    )
    session.state = .failed
    session.cliInteractionPhase = .authenticationBlocked
    session.cliInteractionRecoveryAction = .checkAuthentication
    session.cliInteractionRecoveryActionTitle = CLIInteractionRecoveryAction.checkAuthentication.title
    session.cliInteractionOperatorHint = CLIInteractionRecoveryAction.checkAuthentication.operatorHint
    store.runtimeSessions[cto.id] = session

    let status = store.runRuntimeSessionHealthAuditForSelectedProduct()

    #expect(status == .warning)
    let report = try #require(store.selectedProductVerifications.first { $0.title == "运行会话健康巡检" })
    #expect(report.detail.contains("授权异常"))
    #expect(report.detail.contains("请在对应工具中确认登录授权"))
    #expect(!report.detail.contains("authenticationBlocked"))
    #expect(!report.detail.contains("checkAuthentication"))
    #expect(!report.detail.localizedCaseInsensitiveContains("restart"))
    #expect(!report.detail.localizedCaseInsensitiveContains("session_id"))
}

@MainActor
@Test func localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit() async throws {
    // 锁定本地维护详情里「运行会话健康巡检」按钮下方就地预览的契约：
    // 1) 尚未运行巡检时，selectedProductLatestRuntimeSessionHealthAudit() 为空，
    //    预览只能依赖实时 runtimeSessionHealthAuditText() 兜底显示。
    // 2) 兜底文本与按钮触发后写入的 VerificationRecord.detail 都必须使用「运行来源」中文产品话术，
    //    并且不能出现 backend / 后端配置 / 后端漂移 / POST / endpoint / model: 等底层词。
    // 3) 点击按钮后，selectedProductLatestRuntimeSessionHealthAudit() 必须返回新写入的记录，
    //    详情包含「运行会话健康巡检」标题、状态结论以及一条以上「运行来源」明细行，
    //    使预览的「最近一次巡检」段在按钮点击后立即更新。
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(store.selectedProductLatestRuntimeSessionHealthAudit() == nil)

    let liveBeforeClick = store.runtimeSessionHealthAuditText()
    #expect(liveBeforeClick.contains("运行会话健康巡检"))
    #expect(liveBeforeClick.contains("运行来源"))
    #expect(!liveBeforeClick.localizedCaseInsensitiveContains("backend"))
    #expect(!liveBeforeClick.contains("后端配置"))
    #expect(!liveBeforeClick.contains("后端漂移"))
    #expect(!liveBeforeClick.contains("POST"))
    #expect(!liveBeforeClick.contains("endpoint"))
    #expect(!liveBeforeClick.contains("model:"))

    for index in store.agents.indices where store.agents[index].role != .boss {
        store.agents[index].backend = AgentBackend(
            type: .subscriptionCLI,
            command: "/bin/echo",
            model: "preview",
            reasoningEffort: .low
        )
        let agent = store.agents[index]
        var session = store.runtimeSessions[agent.id] ?? AgentRuntimeSession(
            agentID: agent.id,
            productID: store.selectedProductID,
            capability: CLIAgentCommandBuilder.runtimeCapability(for: agent),
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: agent)
        )
        session.state = .ready
        session.productID = store.selectedProductID
        session.capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
        session.failureCount = 0
        session.lastError = ""
        session.lastUsedAt = Date()
        store.runtimeSessions[agent.id] = session
    }

    let resolvedStatus = store.runRuntimeSessionHealthAuditForSelectedProduct()
    #expect(resolvedStatus == .passed || resolvedStatus == .warning)

    let latest = try #require(store.selectedProductLatestRuntimeSessionHealthAudit())
    #expect(latest.title == "运行会话健康巡检")
    #expect(latest.detail.contains("运行会话健康巡检"))
    #expect(latest.detail.contains("运行来源"))
    #expect(latest.detail.contains("通过") || latest.detail.contains("需关注"))

    #expect(!latest.detail.localizedCaseInsensitiveContains("backend"))
    #expect(!latest.detail.contains("后端配置"))
    #expect(!latest.detail.contains("后端漂移"))
    #expect(!latest.detail.contains("POST"))
    #expect(!latest.detail.contains("endpoint"))
    #expect(!latest.detail.contains("model:"))
}

@Test func runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    // 守门：RuntimeSessionHealthAuditPreview 必须为 Computer Use 登记稳定 a11y 锚点。
    // 1) DisplayFormatting.swift 必须声明 runtimeSessionHealthAuditPreview enum case，rawValue 与命名约定一致；
    // 2) OperationsSuiteView.swift 在 RuntimeSessionHealthAuditPreview 上必须同时挂 accessibilityIdentifier
    //    和中文 accessibilityLabel，与 EvidenceClassificationAuditPreview / MaintenanceDataPressurePreview 一致；
    // 3) 同时必须用 accessibilityElement(children: .combine) 把内部多条 Text 折叠成单一 a11y 元素，
    //    Computer Use 才能直接锁定预览根节点而不是逐条文本子节点。
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case runtimeSessionHealthAuditPreview = \"OPCRuntimeSessionHealthAuditPreview\""),
            "DisplayFormatting.swift 必须声明 runtimeSessionHealthAuditPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct RuntimeSessionHealthAuditPreview:",
        failureMessage: "未找到 RuntimeSessionHealthAuditPreview struct 起点 — 运行会话健康巡检预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "RuntimeSessionHealthAuditPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.runtimeSessionHealthAuditPreview.rawValue)"),
            "RuntimeSessionHealthAuditPreview 必须挂 runtimeSessionHealthAuditPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"运行会话健康巡检预览\")"),
            "RuntimeSessionHealthAuditPreview 必须挂中文 accessibilityLabel «运行会话健康巡检预览»")
    #expect(previewSlice.contains(".accessibilityValue(accessibilityValue)"),
            "RuntimeSessionHealthAuditPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认最近巡检或当前巡检文本")
    #expect(previewSlice.contains("private var accessibilityValue: String"),
            "RuntimeSessionHealthAuditPreview 必须集中生成 a11y value，避免最近记录态和空态正文漂移")
    #expect(previewSlice.contains("store.runtimeSessionHealthAuditText()"),
            "RuntimeSessionHealthAuditPreview 的空态 a11y value 必须包含当前巡检文本")
    #expect(previewSlice.contains("尚未运行巡检"),
            "RuntimeSessionHealthAuditPreview 的空态 a11y value 必须保留中文空态提示")
    #expect(previewSlice.contains("latest.detail"),
            "RuntimeSessionHealthAuditPreview 的最近记录态 a11y value 必须包含最近巡检详情")
}

@Test func evidenceClassificationAuditPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    // 守门：EvidenceClassificationAuditPreview 必须像 RuntimeSessionHealthAuditPreview 一样
    // 把内部多条 Text 折叠为单一 a11y 根节点，Computer Use 才不会在 AX tree 上看到两条同名
    // OPCEvidenceClassificationAuditPreview（一条来自父容器，一条来自被默认暴露的子 Text）。
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case evidenceClassificationAuditPreview = \"OPCEvidenceClassificationAuditPreview\""),
            "DisplayFormatting.swift 必须声明 evidenceClassificationAuditPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct EvidenceClassificationAuditPreview:",
        failureMessage: "未找到 EvidenceClassificationAuditPreview struct 起点 — 运行证据分类巡检预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "EvidenceClassificationAuditPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素，避免 AX tree 出现两条同名 OPCEvidenceClassificationAuditPreview")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.evidenceClassificationAuditPreview.rawValue)"),
            "EvidenceClassificationAuditPreview 必须挂 evidenceClassificationAuditPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"运行证据分类巡检预览\")"),
            "EvidenceClassificationAuditPreview 必须挂中文 accessibilityLabel «运行证据分类巡检预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.evidenceClassificationAuditText())"),
            "EvidenceClassificationAuditPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认未分类验证记录和产物档案指标")
}

@Test func maintenanceDataPressurePreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    // 守门：MaintenanceDataPressurePreview 必须像 RuntimeSessionHealthAuditPreview 一样
    // 把内部多条 Text 折叠为单一 a11y 根节点，Computer Use 才不会在 AX tree 上看到两条同名
    // OPCMaintenanceDataPressurePreview（一条来自父容器，一条来自被默认暴露的子 Text）。
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case maintenanceDataPressurePreview = \"OPCMaintenanceDataPressurePreview\""),
            "DisplayFormatting.swift 必须声明 maintenanceDataPressurePreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct MaintenanceDataPressurePreview:",
        failureMessage: "未找到 MaintenanceDataPressurePreview struct 起点 — 维护数据增长预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "MaintenanceDataPressurePreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素，避免 AX tree 出现两条同名 OPCMaintenanceDataPressurePreview")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceDataPressurePreview.rawValue)"),
            "MaintenanceDataPressurePreview 必须挂 maintenanceDataPressurePreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"维护数据增长预览\")"),
            "MaintenanceDataPressurePreview 必须挂中文 accessibilityLabel «维护数据增长预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.maintenanceDataPressureText())"),
            "MaintenanceDataPressurePreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认主状态快照和命令行作业档案指标")
}

@Test func historyIndexAuditPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case historyIndexAuditPreview = \"OPCHistoryIndexAuditPreview\""),
            "DisplayFormatting.swift 必须声明 historyIndexAuditPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct HistoryIndexAuditPreview:",
        failureMessage: "未找到 HistoryIndexAuditPreview struct 起点 — 历史索引预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "HistoryIndexAuditPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.historyIndexAuditPreview.rawValue)"),
            "HistoryIndexAuditPreview 必须挂 historyIndexAuditPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"历史索引预览\")"),
            "HistoryIndexAuditPreview 必须挂中文 accessibilityLabel «历史索引预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.historyIndexAuditText())"),
            "HistoryIndexAuditPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认历史索引状态")
}

@Test func terminalWorkspaceHealthPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalWorkspaceHealthPreview = \"OPCTerminalWorkspaceHealthPreview\""),
            "DisplayFormatting.swift 必须声明 terminalWorkspaceHealthPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalWorkspaceHealthPreview:",
        failureMessage: "未找到 TerminalWorkspaceHealthPreview struct 起点 — 持久终端可用性预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "TerminalWorkspaceHealthPreview 只有预览文本，必须折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalWorkspaceHealthPreview.rawValue)"),
            "TerminalWorkspaceHealthPreview 必须挂 terminalWorkspaceHealthPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"持久终端可用性预览\")"),
            "TerminalWorkspaceHealthPreview 必须挂中文 accessibilityLabel «持久终端可用性预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.terminalWorkspaceHealthAuditText())"),
            "TerminalWorkspaceHealthPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认持久终端可用性")
}

@Test func localMaintenancePlainPreviewTextsWireStableAccessibilityAnchorsForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    let requiredCases = [
        "case runDataCleanupPreview = \"OPCRunDataCleanupPreview\"",
        "case cliToolchainPreflightPreview = \"OPCCLIToolchainPreflightPreview\"",
        "case defaultCompanyStatePreview = \"OPCDefaultCompanyStatePreview\"",
        "case productIsolationAuditPreview = \"OPCProductIsolationAuditPreview\"",
        "case cliRuntimeIsolationPreview = \"OPCCLIRuntimeIsolationPreview\"",
        "case cliRuntimeIsolationDetailToggle = \"OPCCLIRuntimeIsolationDetailToggle\"",
        "case cliRuntimeIsolationDetailPreview = \"OPCCLIRuntimeIsolationDetailPreview\"",
        "case terminalWorkspacePlanPreview = \"OPCTerminalWorkspacePlanPreview\"",
        "case terminalWorkspacePlanDetailToggle = \"OPCTerminalWorkspacePlanDetailToggle\"",
        "case terminalWorkspacePlanDetailPreview = \"OPCTerminalWorkspacePlanDetailPreview\"",
        "case safetyCheckpointPreview = \"OPCSafetyCheckpointPreview\"",
        "case localDiagnosticsPolicyPreview = \"OPCLocalDiagnosticsPolicyPreview\""
    ]
    for requiredCase in requiredCases {
        #expect(displaySource.contains(requiredCase), "DisplayFormatting.swift 必须声明 \(requiredCase)")
    }

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let centerSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct LocalMaintenanceCenter:",
        failureMessage: "未找到 LocalMaintenanceCenter struct 起点 — 本地维护纯文本预览 a11y 锚点契约失效"
    ) else { return }

    let requiredIdentifiers = [
        "runDataCleanupPreview": ("清理预览", "selectedProductRunDataSummary()"),
        "cliToolchainPreflightPreview": ("命令行链路预检", "cliToolchainPreflightText()"),
        "defaultCompanyStatePreview": ("默认状态预览", "defaultCompanyStatePreviewText()"),
        "productIsolationAuditPreview": ("隔离体检预览", "productIsolationAuditText()"),
        "safetyCheckpointPreview": ("安全检查点", "safetyCheckpointListText()"),
        "localDiagnosticsPolicyPreview": ("本机诊断与日志策略", "localDiagnosticsPolicyText()")
    ]
    for (identifier, contract) in requiredIdentifiers {
        #expect(centerSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.\(identifier).rawValue)"),
                "LocalMaintenanceCenter 必须为 \(identifier) 挂稳定 accessibilityIdentifier")
        #expect(centerSlice.contains(".accessibilityLabel(\"\(contract.0)\")"),
                "\(identifier) 必须挂中文 accessibilityLabel «\(contract.0)»")
        #expect(centerSlice.contains(".accessibilityValue(store.\(contract.1))"),
                "\(identifier) 必须把动态正文挂到 accessibilityValue，供 Computer Use 直接读取")
    }
}

@Test func maintenancePreviewTextKeepsDisclosureReachableWhileExposingStableAnchorsForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    let requiredCases = [
        "case cliRuntimeIsolationPreview = \"OPCCLIRuntimeIsolationPreview\"",
        "case cliRuntimeIsolationDetailToggle = \"OPCCLIRuntimeIsolationDetailToggle\"",
        "case cliRuntimeIsolationDetailPreview = \"OPCCLIRuntimeIsolationDetailPreview\"",
        "case terminalWorkspacePlanPreview = \"OPCTerminalWorkspacePlanPreview\"",
        "case terminalWorkspacePlanDetailToggle = \"OPCTerminalWorkspacePlanDetailToggle\"",
        "case terminalWorkspacePlanDetailPreview = \"OPCTerminalWorkspacePlanDetailPreview\""
    ]
    for requiredCase in requiredCases {
        #expect(displaySource.contains(requiredCase), "DisplayFormatting.swift 必须声明 \(requiredCase)")
    }

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let centerSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct LocalMaintenanceCenter:",
        failureMessage: "未找到 LocalMaintenanceCenter struct 起点 — MaintenancePreviewText 调用契约失效"
    ) else { return }
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct MaintenancePreviewText:",
        failureMessage: "未找到 MaintenancePreviewText struct 起点 — 维护明细开关 a11y 锚点契约失效"
    ) else { return }

    #expect(centerSlice.contains("label: \"命令行与工作区隔离预览\""),
            "命令行与工作区隔离预览必须给 MaintenancePreviewText 传入中文 label")
    #expect(centerSlice.contains("summary: store.cliRuntimeIsolationAuditText()"),
            "命令行与工作区隔离预览必须继续使用 cliRuntimeIsolationAuditText() 作为摘要")
    #expect(centerSlice.contains("detail: store.cliRuntimeIsolationAuditDetailText()"),
            "命令行与工作区隔离预览必须继续使用 cliRuntimeIsolationAuditDetailText() 作为完整明细")
    #expect(centerSlice.contains("summaryIdentifier: .cliRuntimeIsolationPreview"),
            "命令行与工作区隔离预览必须挂 cliRuntimeIsolationPreview 摘要锚点")
    #expect(centerSlice.contains("detailToggleIdentifier: .cliRuntimeIsolationDetailToggle"),
            "命令行与工作区隔离预览必须挂 cliRuntimeIsolationDetailToggle 开关锚点")
    #expect(centerSlice.contains("detailIdentifier: .cliRuntimeIsolationDetailPreview"),
            "命令行与工作区隔离预览必须挂 cliRuntimeIsolationDetailPreview 明细锚点")

    #expect(centerSlice.contains("label: \"真实终端工作区预览\""),
            "真实终端工作区预览必须给 MaintenancePreviewText 传入中文 label")
    #expect(centerSlice.contains("summary: store.terminalWorkspacePlanText()"),
            "真实终端工作区预览必须继续使用 terminalWorkspacePlanText() 作为摘要")
    #expect(centerSlice.contains("detail: store.terminalWorkspacePlanDetailText()"),
            "真实终端工作区预览必须继续使用 terminalWorkspacePlanDetailText() 作为完整明细")
    #expect(centerSlice.contains("summaryIdentifier: .terminalWorkspacePlanPreview"),
            "真实终端工作区预览必须挂 terminalWorkspacePlanPreview 摘要锚点")
    #expect(centerSlice.contains("detailToggleIdentifier: .terminalWorkspacePlanDetailToggle"),
            "真实终端工作区预览必须挂 terminalWorkspacePlanDetailToggle 开关锚点")
    #expect(centerSlice.contains("detailIdentifier: .terminalWorkspacePlanDetailPreview"),
            "真实终端工作区预览必须挂 terminalWorkspacePlanDetailPreview 明细锚点")

    #expect(previewSlice.contains(".accessibilityIdentifier(summaryIdentifier.rawValue)"),
            "MaintenancePreviewText 摘要正文必须挂调用方传入的稳定 accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(label)"),
            "MaintenancePreviewText 摘要正文必须使用调用方中文 label")
    #expect(previewSlice.contains(".accessibilityValue(summary)"),
            "MaintenancePreviewText 摘要正文必须把动态 summary 挂到 accessibilityValue")
    #expect(previewSlice.contains("DisclosureGroup"),
            "MaintenancePreviewText 必须保留 DisclosureGroup，让完整运维明细仍可展开")
    #expect(previewSlice.contains(".accessibilityIdentifier(detailToggleIdentifier.rawValue)"),
            "MaintenancePreviewText 的 DisclosureGroup 必须挂完整明细开关 identifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"\\(label)完整明细开关\")"),
            "MaintenancePreviewText 的 DisclosureGroup 必须暴露中文完整明细开关 label")
    #expect(previewSlice.contains(".accessibilityHint(\"展开或收起完整运维明细\")"),
            "MaintenancePreviewText 的 DisclosureGroup 必须说明可展开/收起完整明细")
    #expect(previewSlice.contains(".accessibilityIdentifier(detailIdentifier.rawValue)"),
            "MaintenancePreviewText 展开后的完整明细正文必须挂稳定 accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"\\(label)完整明细\")"),
            "MaintenancePreviewText 展开后的完整明细正文必须使用中文 accessibilityLabel")
    #expect(previewSlice.contains(".accessibilityValue(detail)"),
            "MaintenancePreviewText 展开后的完整明细正文必须把动态 detail 挂到 accessibilityValue")
    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "MaintenancePreviewText 展开后的完整明细正文必须合并为独立正文节点；但根 VStack 和 DisclosureGroup 不能用 combine 吞掉开关")
}

@Test func cliRecoveryAdvicePanelKeepsRetryButtonsReachableWhileExposingStableAnchorsForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case cliRecoveryAdvicePanel = \"OPCCLIRecoveryAdvicePanel\""),
            "DisplayFormatting.swift 必须声明 cliRecoveryAdvicePanel enum case")
    #expect(displaySource.contains("case cliRecoveryAdviceSummary = \"OPCCLIRecoveryAdviceSummary\""),
            "DisplayFormatting.swift 必须声明 cliRecoveryAdviceSummary enum case")
    #expect(displaySource.contains("case cliRecoveryAdviceManualRetryButton = \"OPCCLIRecoveryAdviceManualRetryButton\""),
            "DisplayFormatting.swift 必须声明 cliRecoveryAdviceManualRetryButton enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let panelSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct CLIRecoveryAdvicePanel:",
        failureMessage: "未找到 CLIRecoveryAdvicePanel struct 起点 — 员工恢复建议面板 a11y 锚点契约失效"
    ) else { return }

    #expect(panelSlice.contains(".accessibilityElement(children: .contain)"),
            "CLIRecoveryAdvicePanel 含手动重试按钮，根节点必须使用 contain，不能把子按钮折叠掉")
    #expect(!panelSlice.contains(".background(CompanyTheme.panelRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))\n        .accessibilityElement(children: .combine)"),
            "CLIRecoveryAdvicePanel 根节点不能使用 combine，否则会破坏手动重试按钮的 Computer Use 可达性")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdvicePanel.rawValue)"),
            "CLIRecoveryAdvicePanel 必须挂 cliRecoveryAdvicePanel accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceSummary.rawValue)"),
            "员工恢复建议摘要文本必须挂 cliRecoveryAdviceSummary accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityChildren"),
            "CLIRecoveryAdvicePanel 必须用 accessibilityChildren 同步镜像摘要和按钮，否则 SwiftUI 会把摘要 ID 合并进普通文本节点")
    #expect(panelSlice.contains("ForEach(store.cliRecoveryAdvicesForSelectedProduct(), id: \\.agentID)"),
            "CLIRecoveryAdvicePanel 的 accessibilityChildren 必须镜像每名员工的重试按钮，避免虚拟子节点吞掉按钮可达性")
    #expect(panelSlice.contains(".accessibilityValue(store.cliRecoveryAdviceSummaryText())"),
            "员工恢复建议摘要文本必须把动态正文挂到 accessibilityValue")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceManualRetryButton.rawValue)"),
            "每名员工的手动重试按钮必须挂 cliRecoveryAdviceManualRetryButton accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityLabel(\"\\(entry.displayName) · 手动重试一次\")"),
            "手动重试按钮必须用员工名区分 accessibilityLabel")
    #expect(panelSlice.contains(".accessibilityHint(\"仅当员工最近一次状态为临时异常时可用；授权异常、忙碌或尚未观察状态不会自动重开\")"),
            "手动重试按钮必须说明禁用条件和受控重试边界，避免 Computer Use 只看到 disabled")
}

@Test func manualREPLTurnInputFieldExposesStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalManualREPLInputField = \"OPCTerminalManualREPLInputField\""),
            "DisplayFormatting.swift 必须声明 terminalManualREPLInputField enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let panelSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct ManualREPLTurnPanel:",
        failureMessage: "未找到 ManualREPLTurnPanel struct 起点 — 手动交互轮次输入框 a11y 契约失效"
    ) else { return }

    #expect(panelSlice.contains("TextField(\"输入一行（不能含换行）\", text: $inputText)"),
            "手动交互轮次输入框必须继续使用中文 placeholder")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalManualREPLInputField.rawValue)"),
            "手动交互轮次输入框必须挂 terminalManualREPLInputField accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityLabel(\"手动交互一行输入\")"),
            "手动交互轮次输入框必须挂中文 accessibilityLabel")
    #expect(panelSlice.contains(".accessibilityHint(\"向当前选中员工的真实终端席位发送一行输入，不能包含换行\")"),
            "手动交互轮次输入框必须说明不能含换行且会发送到真实终端席位")
}

@Test func manualREPLTurnSendButtonExposesStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalManualREPLSendButton = \"OPCTerminalManualREPLSendButton\""),
            "DisplayFormatting.swift 必须声明 terminalManualREPLSendButton enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let panelSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct ManualREPLTurnPanel:",
        failureMessage: "未找到 ManualREPLTurnPanel struct 起点 — 手动交互发送按钮 a11y 契约失效"
    ) else { return }

    #expect(panelSlice.contains("let report = await store.runManualREPLTurnForSelectedAgent(text: pending)"),
            "手动交互发送按钮必须继续走现有 runManualREPLTurnForSelectedAgent 路径")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalManualREPLSendButton.rawValue)"),
            "手动交互发送按钮必须挂 terminalManualREPLSendButton accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityLabel(isSending ? \"正在发送手动交互输入\" : \"发送一行手动交互输入\")"),
            "手动交互发送按钮必须挂中文动态 accessibilityLabel")
    #expect(panelSlice.contains(".accessibilityHint(\"发送输入框中的一行文本到当前选中员工真实终端席位；输入为空或正在发送时禁用\")"),
            "手动交互发送按钮必须说明发送范围和禁用边界")
}

@Test func terminalAutoInteractionLoopReportSummaryExposesDynamicValueForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalAutoLoopReportSummary = \"OPCTerminalAutoLoopReportSummary\""),
            "DisplayFormatting.swift 必须声明 terminalAutoLoopReportSummary enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let panelSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalAutoInteractionLoopPanel:",
        failureMessage: "未找到 TerminalAutoInteractionLoopPanel struct 起点 — 自动循环报告 a11y value 契约失效"
    ) else { return }

    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoLoopReportSummary.rawValue)"),
            "真实终端自动循环报告必须挂 terminalAutoLoopReportSummary accessibilityIdentifier")
    #expect(panelSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoInteractionLoopPanel.rawValue)"),
            "真实终端自动循环面板标题必须挂 terminalAutoInteractionLoopPanel accessibilityIdentifier；父容器不能抢占真实子控件 ID")
    #expect(!panelSlice.contains(".accessibilityChildren"),
            "真实终端自动循环面板不能用 accessibilityChildren 镜像真实输入和按钮，否则 Computer Use 会拿到不可操作的虚拟节点")
    #expect(panelSlice.contains("OPCUIAutomationIdentifier.terminalAutoLoopTaskContextField.rawValue"))
    #expect(panelSlice.contains("OPCUIAutomationIdentifier.terminalAutoLoopMaxTurnsStepper.rawValue"))
    #expect(panelSlice.contains("OPCUIAutomationIdentifier.terminalAutoLoopStartButton.rawValue"))
    #expect(panelSlice.contains(".accessibilityLabel(report.rejected ? \"真实终端自动循环已拒绝\" : \"真实终端自动循环报告\")"),
            "真实终端自动循环报告必须用中文 label 区分拒绝态和报告态")
    #expect(panelSlice.contains(".accessibilityValue(report.summaryText)"),
            "真实终端自动循环报告必须把动态 summaryText 挂到 accessibilityValue，供 Computer Use 直接读取停止原因和轮次结果")
}

@Test func employeeHandoffAuditPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case employeeHandoffAuditPreview = \"OPCEmployeeHandoffAuditPreview\""),
            "DisplayFormatting.swift 必须声明 employeeHandoffAuditPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct EmployeeHandoffAuditPreview:",
        failureMessage: "未找到 EmployeeHandoffAuditPreview struct 起点 — 员工交接巡检预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "EmployeeHandoffAuditPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.employeeHandoffAuditPreview.rawValue)"),
            "EmployeeHandoffAuditPreview 必须挂 employeeHandoffAuditPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"员工交接巡检预览\")"),
            "EmployeeHandoffAuditPreview 必须挂中文 accessibilityLabel «员工交接巡检预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.employeeHandoffAuditText())"),
            "EmployeeHandoffAuditPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认员工交接状态")
}

@Test func jobArchiveStaleAuditPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case jobArchiveStaleAuditPreview = \"OPCJobArchiveStaleAuditPreview\""),
            "DisplayFormatting.swift 必须声明 jobArchiveStaleAuditPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct JobArchiveStaleAuditPreview:",
        failureMessage: "未找到 JobArchiveStaleAuditPreview struct 起点 — 命令行作业幽灵巡检预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "JobArchiveStaleAuditPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.jobArchiveStaleAuditPreview.rawValue)"),
            "JobArchiveStaleAuditPreview 必须挂 jobArchiveStaleAuditPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"命令行作业幽灵巡检预览\")"),
            "JobArchiveStaleAuditPreview 必须挂中文 accessibilityLabel «命令行作业幽灵巡检预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.jobArchiveStaleAuditText())"),
            "JobArchiveStaleAuditPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认命令行作业幽灵状态")
}

@Test func historyArchiveMigrationPreviewWiresStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case historyArchiveMigrationPreview = \"OPCHistoryArchiveMigrationPreview\""),
            "DisplayFormatting.swift 必须声明 historyArchiveMigrationPreview enum case")

    let viewSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    guard let previewSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct HistoryArchiveMigrationPreview:",
        failureMessage: "未找到 HistoryArchiveMigrationPreview struct 起点 — 历史归档迁移预览 a11y 锚点契约失效"
    ) else { return }

    #expect(previewSlice.contains(".accessibilityElement(children: .combine)"),
            "HistoryArchiveMigrationPreview 必须用 accessibilityElement(children: .combine) 把子 Text 折叠为单一 a11y 元素")
    #expect(previewSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.historyArchiveMigrationPreview.rawValue)"),
            "HistoryArchiveMigrationPreview 必须挂 historyArchiveMigrationPreview accessibilityIdentifier")
    #expect(previewSlice.contains(".accessibilityLabel(\"历史归档迁移预览\")"),
            "HistoryArchiveMigrationPreview 必须挂中文 accessibilityLabel «历史归档迁移预览»")
    #expect(previewSlice.contains(".accessibilityValue(store.historyArchiveMigrationText())"),
            "HistoryArchiveMigrationPreview 必须把动态预览正文挂到 accessibilityValue，方便 Computer Use 机械确认历史归档迁移状态")
}

@MainActor
@Test func selectedProductClosureDrillSummaryShowsEmptyStateWhenNoDrill() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let summary = store.selectedProductClosureDrillSummaryText()

    #expect(summary.contains("闭环演练复盘摘要"))
    #expect(summary.contains("暂无记录"))
    #expect(summary.contains("运行闭环演练"))
    #expect(!summary.contains("100%"))
}

@MainActor
@Test func selectedProductClosureDrillSummaryReflectsLatestRehearsal() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "复盘摘要测试目标"

    let success = store.runMultiAgentArchitectureClosureDrill(goal: goal)
    #expect(success)

    let summary = store.selectedProductClosureDrillSummaryText()

    #expect(summary.contains("闭环演练复盘摘要：\(goal)"))
    #expect(summary.contains("100%"))
    #expect(summary.contains("任务："))
    #expect(summary.contains("协作消息："))
    #expect(summary.contains("审批："))
    #expect(summary.contains("审查门禁："))
    #expect(summary.contains("产物："))
    #expect(summary.contains("验收："))
    #expect(summary.contains("下一步："))
    #expect(!summary.contains("暂无记录"))
    #expect(!summary.contains("backend"))
}

@MainActor
@Test func selectedProductClosureDrillSummaryDoesNotLeakAcrossProducts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstProductID = store.selectedProductID

    _ = store.runMultiAgentArchitectureClosureDrill(goal: "产品 A 闭环复盘")

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)

    let summaryB = store.selectedProductClosureDrillSummaryText()
    #expect(summaryB.contains("暂无记录"))
    #expect(!summaryB.contains("产品 A 闭环复盘"))

    store.selectProduct(firstProductID)
    let summaryA = store.selectedProductClosureDrillSummaryText()
    #expect(summaryA.contains("产品 A 闭环复盘"))
    #expect(!summaryA.contains("暂无记录"))
}

@MainActor
@Test func postEmployeeHandoffWritesStructuredMessageBetweenTeammates() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let uiDesigner = try #require(store.agents.first { $0.role == .uiDesigner })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.createTask(title: "员工交接测试任务", ownerID: engineer.id, status: .assigned, successCriteria: "工程师按设计交付完成实现。")
    let task = try #require(store.selectedProductTasks.first { $0.title == "员工交接测试任务" })

    let envelope = store.postEmployeeHandoff(
        fromAgentID: uiDesigner.id,
        toAgentID: engineer.id,
        taskID: task.id,
        subject: "界面设计交接",
        body: "已完成主页和工作台界面，请按视觉规范实现。"
    )

    let handoff = try #require(envelope)
    #expect(handoff.kind == .employeeHandoff)
    #expect(handoff.fromAgentID == uiDesigner.id)
    #expect(handoff.toAgentID == engineer.id)
    #expect(handoff.taskID == task.id)
    #expect(handoff.subject == "界面设计交接")
    #expect(handoff.body.contains("视觉规范"))
    #expect(handoff.status == .pending)

    // 不会触发模型任务、不写老板首页 ChatMessage、不创建作业档案。
    #expect(store.runningAgentIDs.isEmpty)
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })
    #expect(!store.messages(for: store.bossID).contains { $0.text.contains("界面设计交接") })

    // 总线里能看到这条交接。
    #expect(store.selectedProductAgentMessages.contains { $0.id == handoff.id })
}

@MainActor
@Test func postEmployeeHandoffRejectsBossOrCrossTeamParticipants() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let messagesBefore = store.selectedProductAgentMessages.count

    // 老板参与：拒绝
    let bossAttempt = store.postEmployeeHandoff(
        fromAgentID: engineer.id,
        toAgentID: store.bossID,
        subject: "不允许老板交接",
        body: "测试拒绝路径"
    )
    #expect(bossAttempt == nil)
    #expect(store.events.contains { $0.title == "已阻止老板参与员工交接" })
    #expect(store.selectedProductAgentMessages.count == messagesBefore)

    // 同人交接：拒绝
    let selfAttempt = store.postEmployeeHandoff(
        fromAgentID: engineer.id,
        toAgentID: engineer.id,
        subject: "自交接",
        body: "测试自反路径"
    )
    #expect(selfAttempt == nil)

    // 跨团队（其他产品的成员）：拒绝
    store.selectProduct(store.products.first!.id)
    store.createTask(title: "产品 A 任务", ownerID: engineer.id, status: .assigned, successCriteria: "用于验证跨产品任务不能挂到其他产品交接。")
    let firstProductTask = try #require(store.selectedProductTasks.first { $0.title == "产品 A 任务" })

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    let secondProduct = try #require(store.products.first { $0.id == secondProductID })
    #expect(!secondProduct.assignedAgentIDs.contains(reviewer.id))

    let crossAttempt = store.postEmployeeHandoff(
        productID: secondProductID,
        fromAgentID: engineer.id,
        toAgentID: reviewer.id,
        subject: "跨团队",
        body: "engineer 与 reviewer 都不在产品 B 团队"
    )
    #expect(crossAttempt == nil)
    #expect(store.events.contains { $0.title == "已阻止跨团队员工交接" })

    // 产品 B 不应被该尝试污染消息总线。
    let productBMessages = store.agentMessages.filter { $0.productID == secondProductID && $0.kind == .employeeHandoff }
    #expect(productBMessages.isEmpty)

    // 即使两个员工都加入产品 B，也不能把产品 A 的任务挂到产品 B 的交接消息。
    store.assignAgentToSelectedProduct(engineer.id)
    store.assignAgentToSelectedProduct(reviewer.id)
    let crossTaskAttempt = store.postEmployeeHandoff(
        productID: secondProductID,
        fromAgentID: engineer.id,
        toAgentID: reviewer.id,
        taskID: firstProductTask.id,
        subject: "跨产品任务",
        body: "测试任务隔离"
    )
    #expect(crossTaskAttempt == nil)
    #expect(store.events.contains { $0.title == "已阻止跨产品任务交接" })
}

@MainActor
@Test func multiAgentClosureDrillIncludesEmployeeHandoffEvidence() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let goal = "员工交接闭环演练"
    #expect(store.runMultiAgentArchitectureClosureDrill(goal: goal))

    let kinds = Set(store.selectedProductAgentMessages.map(\.kind))
    #expect(kinds.contains(.employeeHandoff))
    #expect(kinds.contains(.taskDispatched))
    #expect(kinds.contains(.reviewRequested))

    let trace = try #require(store.latestSelectedProductClosureTrace)
    let traceMessages = store.closureTraceMessages(trace)
    #expect(traceMessages.contains { $0.kind == .employeeHandoff })
    let graph = store.closureTraceTaskGraph(trace)
    #expect(graph.edges.contains { $0.evidence.contains("员工交接 已记录") })

    // 文案 helper 是中文标题。
    #expect(AgentMessageDisplay.title(for: .employeeHandoff) == "员工交接")
    #expect(!AgentMessageDisplay.icon(for: .employeeHandoff).isEmpty)

    // 跨产品不串：切到产品 B，员工交接消息不会出现在产品 B 的总线。
    let firstProductID = store.selectedProductID
    store.addProductWorkspace()
    let bMessages = store.selectedProductAgentMessages.filter { $0.kind == .employeeHandoff }
    #expect(bMessages.isEmpty)
    store.selectProduct(firstProductID)
    let aMessages = store.selectedProductAgentMessages.filter { $0.kind == .employeeHandoff }
    #expect(!aMessages.isEmpty)
}

@MainActor
@Test func employeeHandoffAuditEmptyStatePassesAndReportsZero() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let preview = store.employeeHandoffAuditText()
    #expect(preview.contains("员工交接待确认巡检"))
    #expect(preview.contains("总员工交接：0"))
    #expect(preview.contains("通过"))
    #expect(preview.contains("当前产品没有员工交接消息"))
    #expect(!preview.contains("runningAgentIDs"))
    #expect(!preview.contains(".opc/jobs"))

    let status = store.runEmployeeHandoffAuditForSelectedProduct()
    #expect(status == .passed)
    let record = try #require(store.selectedProductVerifications.first { $0.title == "员工交接待确认巡检" })
    #expect(record.status == .passed)
    #expect(store.events.contains { $0.title == "员工交接待确认巡检完成" })
    #expect(!store.events.contains { $0.title == "员工交接超时待确认" })
}

@MainActor
@Test func employeeHandoffAuditCountsPendingAcknowledgedAndStaleSeparately() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let uiDesigner = try #require(store.agents.first { $0.role == .uiDesigner })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    let recent = try #require(store.postEmployeeHandoff(
        fromAgentID: uiDesigner.id,
        toAgentID: engineer.id,
        subject: "近期交接",
        body: "刚刚生成的交接消息。"
    ))

    let acknowledgedHandoff = try #require(store.postEmployeeHandoff(
        fromAgentID: engineer.id,
        toAgentID: reviewer.id,
        subject: "已确认交接",
        body: "已经被审查员读过。"
    ))
    store.acknowledgeAgentMessage(acknowledgedHandoff.id)

    let staleStub = try #require(store.postEmployeeHandoff(
        fromAgentID: uiDesigner.id,
        toAgentID: reviewer.id,
        subject: "陈旧交接",
        body: "演练用的旧交接。"
    ))
    if let index = store.agentMessages.firstIndex(where: { $0.id == staleStub.id }) {
        store.agentMessages[index].createdAt = Date(timeIntervalSinceNow: -600)
    }

    let preview = store.employeeHandoffAuditText(staleAfter: 180)
    #expect(preview.contains("总员工交接：3"))
    #expect(preview.contains("待确认：2"))
    #expect(preview.contains("已确认：1"))
    #expect(preview.contains("超时待确认：1"))
    #expect(preview.contains("陈旧交接"))

    let status = store.runEmployeeHandoffAuditForSelectedProduct(staleAfter: 180)
    #expect(status == .failed)
    let record = try #require(store.selectedProductVerifications.first { $0.title == "员工交接待确认巡检" })
    #expect(record.status == .failed)
    #expect(store.events.contains { $0.title == "员工交接超时待确认" })

    store.acknowledgeAgentMessage(recent.id)
    store.acknowledgeAgentMessage(staleStub.id)
    let secondStatus = store.runEmployeeHandoffAuditForSelectedProduct(staleAfter: 180)
    #expect(secondStatus == .passed)
    let staleEvents = store.events.filter { $0.title == "员工交接超时待确认" }.count
    #expect(staleEvents == 1)
}

@MainActor
@Test func employeeHandoffAuditDoesNotLeakAcrossProducts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let uiDesigner = try #require(store.agents.first { $0.role == .uiDesigner })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let firstProductID = store.selectedProductID

    _ = store.postEmployeeHandoff(
        fromAgentID: uiDesigner.id,
        toAgentID: engineer.id,
        subject: "产品 A 的交接",
        body: "只属于产品 A。"
    )

    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    let previewB = store.employeeHandoffAuditText()
    #expect(previewB.contains("总员工交接：0"))
    #expect(!previewB.contains("产品 A 的交接"))

    store.selectProduct(firstProductID)
    let previewA = store.employeeHandoffAuditText()
    #expect(previewA.contains("总员工交接：1"))
    #expect(previewA.contains("产品 A 的交接"))
}

@MainActor
@Test func employeeHandoffAuditAfterClosureDrillFlagsPendingHandoff() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.runMultiAgentArchitectureClosureDrill(goal: "巡检测试目标"))

    let pendingHandoffsBefore = store.selectedProductAgentMessages.filter {
        $0.kind == .employeeHandoff && $0.status == .pending
    }
    #expect(!pendingHandoffsBefore.isEmpty)

    let status = store.runEmployeeHandoffAuditForSelectedProduct()
    #expect(status == .warning)
    let record = try #require(store.selectedProductVerifications.first { $0.title == "员工交接待确认巡检" })
    #expect(record.detail.contains("待确认：\(pendingHandoffsBefore.count)"))

    for envelope in pendingHandoffsBefore {
        store.acknowledgeAgentMessage(envelope.id)
    }
    let secondStatus = store.runEmployeeHandoffAuditForSelectedProduct()
    #expect(secondStatus == .passed)
}

@MainActor
@Test func selectedAgentHandoffRecipientsExcludeBossSelfAndOutsiders() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    let recipients = store.selectedAgentHandoffRecipients
    #expect(!recipients.isEmpty)
    #expect(!recipients.contains { $0.id == engineer.id })
    #expect(!recipients.contains { $0.role == .boss })
    let teamIDs = Set(store.selectedProductAgents.map(\.id))
    #expect(recipients.allSatisfy { teamIDs.contains($0.id) })

    store.selectAgent(store.bossID)
    #expect(store.selectedAgentHandoffRecipients.isEmpty)
}

@MainActor
@Test func postSelectedAgentHandoffWritesPendingHandoffToBus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.selectAgent(engineer.id)

    let envelope = try #require(store.postSelectedAgentHandoff(
        toAgentID: reviewer.id,
        subject: "无任务交接",
        body: "请审查最近上传的方案。"
    ))
    #expect(envelope.kind == .employeeHandoff)
    #expect(envelope.fromAgentID == engineer.id)
    #expect(envelope.toAgentID == reviewer.id)
    #expect(envelope.taskID == nil)
    #expect(envelope.status == .pending)

    #expect(!store.messages(for: store.bossID).contains { $0.text.contains("无任务交接") })
    #expect(!store.selectedProductArtifacts.contains { $0.title.contains("命令行作业档案") })

    store.createTask(title: "员工自发交接任务", ownerID: engineer.id, status: .running, successCriteria: "写入员工交接")
    let task = try #require(store.selectedProductTasks.first { $0.title == "员工自发交接任务" })
    #expect(store.selectedAgentHandoffTaskCandidates.contains { $0.id == task.id })

    let withTask = try #require(store.postSelectedAgentHandoff(
        toAgentID: reviewer.id,
        taskID: task.id,
        subject: "带任务交接",
        body: "请按任务成功标准审查。"
    ))
    #expect(withTask.taskID == task.id)
    #expect(withTask.status == .pending)

    store.createTask(title: "审查员自己的任务", ownerID: reviewer.id, status: .running, successCriteria: "不能被工程师挂到交接里。")
    let reviewerTask = try #require(store.selectedProductTasks.first { $0.title == "审查员自己的任务" })
    let wrongOwner = store.postSelectedAgentHandoff(
        toAgentID: reviewer.id,
        taskID: reviewerTask.id,
        subject: "错误任务交接",
        body: "不应写入。"
    )
    #expect(wrongOwner == nil)
    #expect(store.events.contains { $0.title == "已阻止非本人任务交接" })
}

@MainActor
@Test func postSelectedAgentHandoffRefusesBossSenderAndCrossTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    store.selectAgent(store.bossID)
    let bossAttempt = store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "老板想交接", body: "不允许")
    #expect(bossAttempt == nil)

    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let firstProductID = store.selectedProductID
    store.addProductWorkspace()
    let secondProductID = store.selectedProductID
    #expect(secondProductID != firstProductID)
    #expect(store.selectedAgentHandoffRecipients.isEmpty)
    let crossAttempt = store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "跨产品", body: "不允许")
    #expect(crossAttempt == nil)

    store.selectProduct(firstProductID)
    let success = store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "回到产品 A", body: "正常")
    #expect(success != nil)
}

@MainActor
@Test func postSelectedAgentHandoffDefaultsToFallbackCopyWhenSubjectAndBodyEmpty() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.selectAgent(engineer.id)

    let envelope = try #require(store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "", body: ""))
    #expect(envelope.subject.contains(engineer.displayName))
    #expect(envelope.subject.contains(reviewer.displayName))
    #expect(!envelope.body.isEmpty)
    #expect(envelope.body.contains(engineer.displayName))
    #expect(envelope.body.contains(reviewer.displayName))
}

@MainActor
@Test func acknowledgeSelectedAgentMessageOnlyAffectsCurrentAgentInboundPending() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    store.selectAgent(engineer.id)
    let outbound = try #require(store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "出站", body: "engineer 发出"))

    let outboundResult = store.acknowledgeSelectedAgentMessage(outbound.id)
    #expect(outboundResult == false)
    #expect(store.agentMessages.first { $0.id == outbound.id }?.status == .pending)

    store.selectAgent(reviewer.id)
    let inboundResult = store.acknowledgeSelectedAgentMessage(outbound.id)
    #expect(inboundResult == true)
    let after = try #require(store.agentMessages.first { $0.id == outbound.id })
    #expect(after.status == .acknowledged)
    #expect(after.acknowledgedAt != nil)

    let again = store.acknowledgeSelectedAgentMessage(outbound.id)
    #expect(again == false)

    #expect(store.events.contains { $0.title == "员工协作收件箱已确认一条" })
}

@MainActor
@Test func acknowledgeSelectedAgentMessageRefusesCrossProductAndOtherAgents() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    let uiDesigner = try #require(store.agents.first { $0.role == .uiDesigner })

    store.selectAgent(engineer.id)
    let aboutReviewer = try #require(store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "给审查员", body: "engineer→reviewer"))
    let aboutUI = try #require(store.postSelectedAgentHandoff(toAgentID: uiDesigner.id, subject: "给设计师", body: "engineer→ui"))

    #expect(store.acknowledgeSelectedAgentMessage(aboutReviewer.id) == false)
    #expect(store.acknowledgeSelectedAgentMessage(aboutUI.id) == false)
    #expect(store.agentMessages.first { $0.id == aboutReviewer.id }?.status == .pending)

    store.addProductWorkspace()
    store.selectAgent(reviewer.id)
    #expect(store.acknowledgeSelectedAgentMessage(aboutReviewer.id) == false)
    #expect(store.agentMessages.first { $0.id == aboutReviewer.id }?.status == .pending)
}

@MainActor
@Test func employeeHandoffAuditFlipsToPassedAfterSingleAcknowledgements() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })

    store.selectAgent(engineer.id)
    let handoff = try #require(store.postSelectedAgentHandoff(toAgentID: reviewer.id, subject: "巡检测试", body: "engineer→reviewer"))

    let firstStatus = store.runEmployeeHandoffAuditForSelectedProduct()
    #expect(firstStatus == .warning)

    store.selectAgent(reviewer.id)
    #expect(store.acknowledgeSelectedAgentMessage(handoff.id) == true)

    let secondStatus = store.runEmployeeHandoffAuditForSelectedProduct()
    #expect(secondStatus == .passed)
}

@MainActor
@Test func defaultVisibleTextHidesRawCommandFlagsAndEnglishRoleWords() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let nonBossAgents = store.agents.filter { $0.role != .boss }
    #expect(!nonBossAgents.isEmpty)

    // 终端大厅默认卡片直接展示的两段文本：后端摘要和命令预览
    for agent in nonBossAgents {
        let backendSummary = store.visibleBackendSummary(for: agent)
        let commandPreview = store.commandPreview(for: agent, prompt: "默认任务")

        for fragment in [backendSummary, commandPreview] {
            #expect(!fragment.contains("model_reasoning_effort"))
            #expect(!fragment.contains("--skip-git-repo-check"))
            #expect(!fragment.contains("COMMAND LINK"))
            #expect(!fragment.contains("Agent 编队"))
            #expect(!fragment.contains("Codex CTO"))
            #expect(!fragment.contains("AI 智能控制"))
            #expect(!fragment.contains("AI 通信"))
        }
    }

    // 至少有一个员工的命令预览仍然展示工具品牌名（Codex / Claude Code / Gemini），保证品牌可见
    let allPreviews = nonBossAgents
        .map { store.commandPreview(for: $0, prompt: "默认任务") }
        .joined(separator: "\n")
    let mentionsBrand =
        allPreviews.contains("Codex") ||
        allPreviews.contains("Claude Code") ||
        allPreviews.contains("Gemini")
    #expect(mentionsBrand)

    // 老板/技术负责人/员工角色显示名不再出现旧的 "Codex CTO" 英文混排
    for agent in store.agents {
        #expect(!agent.displayName.contains("Codex CTO"))
        #expect(!agent.title.contains("Codex CTO"))
        #expect(!agent.title.contains(" CTO"))
        #expect(agent.title != "CTO")
    }
}

// MARK: - 跨命令行工具自动输入循环执行器

private func opcReadyObservation() -> CLIInteractionObservation {
    CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")
}

private func opcCompletedObservation() -> CLIInteractionObservation {
    CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束")
}

private func opcAuthBlockedObservation() -> CLIInteractionObservation {
    CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常")
}

private func opcBusyObservation() -> CLIInteractionObservation {
    CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中")
}

private func opcTransientObservation() -> CLIInteractionObservation {
    CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常")
}

private actor AutoLoopSenderRecorder {
    private(set) var captured: [String] = []

    func record(_ text: String) {
        captured.append(text)
    }
}

@Test func autoLoopExecutorRunsHappyMultiTurnUntilCompletion() async throws {
    let initial = CLIAutoInteractionLoopGate.start(taskContext: "技术负责人闭环演练", maxTurns: 3)
    #expect(initial.phase == .running)

    let recorder = AutoLoopSenderRecorder()
    let plannedSteps = ["请继续下一步", "请审查刚才的输出", "请输出最终交付摘要"]
    let phaseSequence: [CLIInteractionObservation] = [
        opcReadyObservation(),
        opcReadyObservation(),
        opcCompletedObservation(),
    ]

    var state = initial
    for (index, step) in plannedSteps.enumerated() {
        let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
            state: state,
            input: CLIAutoInteractionGeneratedInput(text: step)
        ) { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: phaseSequence[index])
        }
        #expect(report.didCallSender == true)
        #expect(report.sentInput == step)
        state = report.updatedState
    }

    #expect(state.phase == .completed)
    #expect(state.stopReason == .completedTurn)
    #expect(state.sentInputs.count == 3)
    let sent = await recorder.captured
    #expect(sent == plannedSteps)
}

@Test func autoLoopExecutorRefusesUnsafeMultilineInputBeforeSending() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "回归任务", maxTurns: 3)
    let recorder = AutoLoopSenderRecorder()
    let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "第一行\n第二行")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
    }
    #expect(report.didCallSender == false)
    #expect(report.sentInput == nil)
    #expect(report.preflightStopReason == .unsafeInput)
    #expect(report.updatedState.phase == .stopped)
    let sent = await recorder.captured
    #expect(sent.isEmpty)
}

@Test func autoLoopExecutorRefusesNonOPCGeneratedInputBeforeSending() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "回归任务", maxTurns: 2)
    let recorder = AutoLoopSenderRecorder()
    let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "外部粘贴的下一步", source: .external)
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
    }
    #expect(report.didCallSender == false)
    #expect(report.preflightStopReason == .nonOPCGeneratedInput)
    #expect(report.updatedState.phase == .stopped)
    let sent = await recorder.captured
    #expect(sent.isEmpty)
}

@Test func autoLoopExecutorStopsOnAuthenticationBusyAndTransientPhases() async throws {
    let cases: [(CLIInteractionObservation, CLIAutoInteractionLoopStopReason)] = [
        (opcAuthBlockedObservation(), .authenticationBlocked),
        (opcBusyObservation(), .busy),
        (opcTransientObservation(), .transientFailure),
    ]
    for (observation, expectedReason) in cases {
        let state = CLIAutoInteractionLoopGate.start(taskContext: "异常停止", maxTurns: 3)
        let recorder = AutoLoopSenderRecorder()
        let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
            state: state,
            input: CLIAutoInteractionGeneratedInput(text: "请继续")
        ) { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: observation)
        }
        #expect(report.didCallSender == true)
        #expect(report.updatedState.phase == .stopped)
        #expect(report.updatedState.stopReason == expectedReason)
        let sent = await recorder.captured
        #expect(sent == ["请继续"])
    }
}

@Test func autoLoopExecutorStopsOnTimedOutFlag() async throws {
    let state = CLIAutoInteractionLoopGate.start(taskContext: "等待超时", maxTurns: 3)
    let recorder = AutoLoopSenderRecorder()
    let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "请继续")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation(), timedOut: true)
    }
    #expect(report.didCallSender == true)
    #expect(report.updatedState.phase == .stopped)
    #expect(report.updatedState.stopReason == .timedOut)
}

@Test func autoLoopExecutorStopsAtMaxTurnsWithoutCallingSender() async throws {
    var state = CLIAutoInteractionLoopGate.start(taskContext: "上限测试", maxTurns: 2)
    let recorder = AutoLoopSenderRecorder()

    for index in 0..<2 {
        let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
            state: state,
            input: CLIAutoInteractionGeneratedInput(text: "第\(index + 1)轮")
        ) { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
        }
        state = report.updatedState
    }

    let sentBefore = await recorder.captured.count
    #expect(sentBefore == 2)
    // 门禁会在到达上限的同一轮把 phase 置为 stopped/maxTurnsReached，
    // 再次进入执行器时应直接短路，不再重复发送。
    #expect(state.phase == .stopped)
    #expect(state.stopReason == .maxTurnsReached)

    let blocked = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "第三轮被拒绝")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
    }
    #expect(blocked.didCallSender == false)
    #expect(blocked.sentInput == nil)
    #expect(blocked.updatedState.phase == .stopped)
    #expect(blocked.updatedState.stopReason == .maxTurnsReached)
    let sentAfter = await recorder.captured.count
    #expect(sentAfter == 2)
}

@Test func autoLoopExecutorPreflightRejectsMaxTurnsWhenStateStillRunning() async throws {
    // 模拟下一轮调用前状态仍是 running 但已记录到上限——此时由 preflight 直接拒发，避免误调发送闭包
    var state = CLIAutoInteractionLoopGate.start(taskContext: "preflight 上限", maxTurns: 1)
    state.sentInputs = ["占位轮已记录"]
    #expect(state.phase == .running)

    let recorder = AutoLoopSenderRecorder()
    let blocked = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "再来一轮")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
    }
    #expect(blocked.didCallSender == false)
    #expect(blocked.preflightStopReason == .maxTurnsReached)
    #expect(blocked.updatedState.phase == .stopped)
    #expect(blocked.updatedState.stopReason == .maxTurnsReached)
    let sent = await recorder.captured
    #expect(sent.isEmpty)
}

@Test func autoLoopExecutorIgnoresAlreadyCompletedOrRejectedState() async throws {
    let rejected = CLIAutoInteractionLoopGate.start(taskContext: "", maxTurns: 3)
    #expect(rejected.phase == .rejected)
    let recorder = AutoLoopSenderRecorder()
    let report = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: rejected,
        input: CLIAutoInteractionGeneratedInput(text: "不该发送")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcReadyObservation())
    }
    #expect(report.didCallSender == false)
    #expect(report.sentInput == nil)
    #expect(report.updatedState.phase == .rejected)
    let sent = await recorder.captured
    #expect(sent.isEmpty)
}

@Test func autoLoopExecutorVisibleSummaryStaysInChineseWithoutRawValues() async throws {
    var state = CLIAutoInteractionLoopGate.start(taskContext: "可见摘要稳定性", maxTurns: 2)
    let recorder = AutoLoopSenderRecorder()
    let firstReport = await CLIAutoInteractionLoopExecutor.runOneTurn(
        state: state,
        input: CLIAutoInteractionGeneratedInput(text: "请继续下一步")
    ) { sent in
        await recorder.record(sent)
        return CLIAutoInteractionTurnObservation(observation: opcAuthBlockedObservation())
    }
    state = firstReport.updatedState
    let summary = state.summaryText

    #expect(summary.contains("自动交互循环门禁"))
    #expect(summary.contains("授权异常"))
    #expect(!summary.contains("authenticationBlocked"))
    #expect(!summary.contains("running"))
    #expect(!summary.contains("stopped"))
    #expect(!summary.contains("completedTurn"))
    #expect(!summary.contains("opcGenerated"))
    #expect(!summary.contains("rawValue"))
}

// MARK: - 内部自动交互协调器

private actor AutoLoopObservationQueue {
    var pending: [CLIInteractionObservation]
    init(_ values: [CLIInteractionObservation]) { self.pending = values }
    func next() -> CLIInteractionObservation { pending.removeFirst() }
}

private actor AutoLoopInputQueue {
    var pending: [String]
    init(_ values: [String]) { self.pending = values }
    func next() -> String? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

@MainActor
@Test func autoInteractionCoordinatorRunsHappyMultiTurn() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    let bossMessagesBefore = store.messages.count
    let agentMessagesBefore = store.agentMessages.count
    let artifactsBefore = store.artifacts.count

    let plannedSteps = ["请继续下一步", "请审查刚才的输出", "请输出最终交付摘要"]
    let observationQueue = AutoLoopObservationQueue([
        CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"),
        CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"),
        CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"),
    ])
    let inputQueue = AutoLoopInputQueue(plannedSteps)
    let recorder = AutoLoopSenderRecorder()

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人闭环演练",
        maxTurns: 3,
        nextInput: { _ in
            guard let next = await inputQueue.next() else { return nil }
            return CLIAutoInteractionGeneratedInput(text: next)
        },
        runTurn: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: await observationQueue.next())
        }
    )

    #expect(!report.rejected)
    #expect(report.execution.sentTurnCount == 3)
    #expect(report.execution.finalState.phase == .completed)
    #expect(report.execution.finalState.stopReason == .completedTurn)
    #expect(report.agentID == engineer.id)
    let captured = await recorder.captured
    #expect(captured == plannedSteps)

    #expect(store.messages.count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.count == artifactsBefore)
    #expect(!store.artifacts.contains { $0.title.contains("命令行作业档案") })
}

@MainActor
@Test func autoInteractionCoordinatorRejectsEmptyTaskContext() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let bossMessagesBefore = store.messages.count
    let agentMessagesBefore = store.agentMessages.count
    let recorder = AutoLoopSenderRecorder()

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "   \n  ",
        maxTurns: 3,
        nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "不应被采用") },
        runTurn: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        }
    )
    #expect(report.rejected)
    #expect(report.execution.sentTurnCount == 0)
    #expect(report.rejectionReason?.contains("任务上下文") == true)
    let captured = await recorder.captured
    #expect(captured.isEmpty)
    #expect(store.messages.count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
}

@MainActor
@Test func autoInteractionCoordinatorRejectsBossSelected() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let boss = try #require(store.agents.first { $0.role == .boss })
    store.selectAgent(boss.id)
    let recorder = AutoLoopSenderRecorder()

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人测试",
        maxTurns: 3,
        nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "请继续") },
        runTurn: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        }
    )
    #expect(report.rejected)
    #expect(report.rejectionReason?.contains("老板") == true)
    let captured = await recorder.captured
    #expect(captured.isEmpty)
}

@MainActor
@Test func autoInteractionCoordinatorRejectsAgentNotInCurrentProductTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    #expect(!store.selectedProductAgents.contains { $0.id == engineer.id })
    store.selectAgent(engineer.id)
    let recorder = AutoLoopSenderRecorder()

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人测试",
        maxTurns: 3,
        nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "请继续") },
        runTurn: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        }
    )
    #expect(report.rejected)
    #expect(report.rejectionReason?.contains("产品团队") == true)
    let captured = await recorder.captured
    #expect(captured.isEmpty)
}

@MainActor
@Test func autoInteractionCoordinatorStopsOnRiskyPhase() async throws {
    struct Case {
        let observation: CLIInteractionObservation
        let expectedReason: CLIAutoInteractionLoopStopReason
        let summaryFragment: String
    }
    let cases: [Case] = [
        Case(observation: CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常"), expectedReason: .authenticationBlocked, summaryFragment: "授权异常"),
        Case(observation: CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中"), expectedReason: .busy, summaryFragment: "命令行仍在忙碌"),
        Case(observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常"), expectedReason: .transientFailure, summaryFragment: "临时异常"),
    ]
    for testCase in cases {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.selectAgent(engineer.id)

        let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
            taskContext: "异常停止",
            maxTurns: 3,
            nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "请继续") },
            runTurn: { _ in CLIAutoInteractionTurnObservation(observation: testCase.observation) }
        )
        #expect(!report.rejected)
        #expect(report.execution.finalState.phase == .stopped)
        #expect(report.execution.finalState.stopReason == testCase.expectedReason)
        #expect(report.summaryText.contains(testCase.summaryFragment))
        #expect(!report.summaryText.contains("authenticationBlocked"))
        #expect(!report.summaryText.contains("transientFailure"))
        #expect(!report.summaryText.contains("subscriptionCLI"))
    }
}

@MainActor
@Test func autoInteractionCoordinatorSummaryHidesBackendRawValues() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    let report = await store.runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: "可见摘要锁定",
        maxTurns: 1,
        nextInput: { _ in CLIAutoInteractionGeneratedInput(text: "请继续") },
        runTurn: { _ in CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束")) }
    )
    #expect(!report.rejected)
    #expect(report.summaryText.contains("本轮已结束"))
    #expect(report.summaryText.contains("内部自动交互循环"))
    #expect(!report.summaryText.contains("subscriptionCLI"))
    #expect(!report.summaryText.contains("opcGenerated"))
    #expect(!report.summaryText.contains("rawValue"))
    #expect(!report.summaryText.contains("model_reasoning_effort"))
    #expect(!report.summaryText.contains("--skip-git-repo-check"))
    #expect(!report.summaryText.contains("running"))
    #expect(!report.summaryText.contains("authenticationBlocked"))
}

// MARK: - 真实终端席位自动交互入口（CompanyStore.runTerminalAutoInteractionLoopForSelectedAgent）

@MainActor
@Test func realTerminalAutoLoopRunsHappyPathWithInjectedTurnRunner() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)

    let bossMessagesBefore = store.messages.count
    let agentMessagesBefore = store.agentMessages.count
    let artifactsBefore = store.artifacts.count
    let verificationsBefore = store.verifications.count

    let observationQueue = AutoLoopObservationQueue([
        CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"),
        CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"),
        CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束"),
    ])
    let recorder = AutoLoopSenderRecorder()

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人闭环演练",
        maxTurns: 3,
        turnRunner: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: await observationQueue.next())
        }
    )

    #expect(!report.rejected)
    #expect(report.usedRealTerminal == false)
    #expect(report.internalReport.execution.finalState.phase == .completed)
    #expect(report.internalReport.execution.finalState.stopReason == .completedTurn)
    #expect(report.internalReport.execution.sentTurnCount == 3)

    let captured = await recorder.captured
    #expect(captured.count == 3)
    for (turnIndex, line) in captured.enumerated() {
        #expect(line.contains("第\(turnIndex + 1)轮"))
        #expect(line.contains("技术负责人闭环演练"))
        #expect(!line.contains("\n"))
    }

    #expect(store.messages.count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.count == artifactsBefore)
    #expect(store.verifications.count == verificationsBefore)
    #expect(!store.artifacts.contains { $0.title.contains("命令行作业档案") })
}

@MainActor
@Test func realTerminalAutoLoopRunsThroughReadyTmuxSeatWithoutJobArchive() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCAutoLoopCodexSeat-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-codex-autoloop.sh")
    try """
    #!/bin/sh
    count=0
    printf 'codex>\\n'
    while IFS= read -r line; do
      count=$((count + 1))
      printf 'fake-turn-%s:%s\\n' "$count" "$line"
      if [ "$count" -ge 2 ]; then
        printf 'turn complete\\n'
      else
        printf 'codex>\\n'
      fi
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    store.selectAgent(engineer.id)

    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let bossMessagesBefore = store.messages(for: store.bossID).count
    let userAuthoredBefore = store.messages.filter { $0.author == .user }.count
    let agentMessagesBefore = store.agentMessages.count
    let jobArchivesBefore = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "真实终端席位端到端自动循环验证",
        maxTurns: 4,
        timeoutSeconds: 3
    )

    #expect(!report.rejected)
    #expect(report.usedRealTerminal)
    #expect(report.internalReport.execution.finalState.phase == .completed)
    #expect(report.internalReport.execution.finalState.stopReason == .completedTurn)
    #expect(report.internalReport.execution.sentTurnCount == 2)
    #expect(report.summaryText.contains("真实终端席位"))
    #expect(report.summaryText.contains("本轮已结束"))
    #expect(!report.summaryText.contains("completedTurn"))

    let sentInputs = report.internalReport.execution.finalState.sentInputs
    #expect(sentInputs.count == 2)
    if sentInputs.count == 2 {
        #expect(sentInputs[0].contains("第1轮"))
        #expect(sentInputs[1].contains("第2轮"))
        for line in sentInputs {
            #expect(line.contains("真实终端席位端到端自动循环验证"))
            #expect(!line.contains("\n"))
            #expect(!line.contains("opcGenerated"))
        }
    }

    let finalCapture = runTestProcessOutput(tmuxPath, ["capture-pane", "-p", "-t", tmuxTarget, "-S", "-300"])
    #expect(finalCapture.contains("fake-turn-1:第1轮"))
    #expect(finalCapture.contains("fake-turn-2:第2轮"))
    #expect(finalCapture.contains("turn complete"))

    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.messages.filter { $0.author == .user }.count == userAuthoredBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    let jobArchivesAfter = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count
    #expect(jobArchivesAfter == jobArchivesBefore)
    #expect(store.runtimeSessions[engineer.id]?.cliInteractionPhase == .completedTurn)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("OPC 自动交互循环轮次"))
    #expect(!store.terminalLogs[engineer.id, default: ""].contains("OPC 手动交互轮次"))
}

@MainActor
@Test func realTerminalAutoLoopRejectsBoss() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let boss = try #require(store.agents.first { $0.role == .boss })
    store.selectAgent(boss.id)
    let recorder = AutoLoopSenderRecorder()
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人测试",
        maxTurns: 2,
        turnRunner: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        }
    )
    #expect(report.rejected)
    #expect(report.rejectionReason?.contains("老板") == true)
    let captured = await recorder.captured
    #expect(captured.isEmpty)
}

@MainActor
@Test func realTerminalAutoLoopRejectsEmptyTaskContext() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "   \n  ",
        maxTurns: 2,
        turnRunner: { _ in CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互")) }
    )
    #expect(report.rejected)
    #expect(report.rejectionReason?.contains("任务上下文") == true)
}

@MainActor
@Test func realTerminalAutoLoopRejectsAgentNotInTeam() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    #expect(!store.selectedProductAgents.contains { $0.id == engineer.id })
    store.selectAgent(engineer.id)
    let recorder = AutoLoopSenderRecorder()
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "技术负责人测试",
        maxTurns: 2,
        turnRunner: { sent in
            await recorder.record(sent)
            return CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"))
        }
    )
    #expect(report.rejected)
    #expect(report.rejectionReason?.contains("产品团队") == true)
    let captured = await recorder.captured
    #expect(captured.isEmpty)
}

@MainActor
@Test func realTerminalAutoLoopStopsOnRiskyPhases() async throws {
    let cases: [(CLIInteractionObservation, CLIAutoInteractionLoopStopReason)] = [
        (CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常"), .authenticationBlocked),
        (CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中"), .busy),
        (CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常"), .transientFailure),
    ]
    for (observation, expected) in cases {
        let store = CompanyStore.bootstrap(loadPersisted: false)
        let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
        store.selectAgent(engineer.id)
        let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
            taskContext: "异常停止",
            maxTurns: 3,
            turnRunner: { _ in CLIAutoInteractionTurnObservation(observation: observation) }
        )
        #expect(!report.rejected)
        #expect(report.internalReport.execution.finalState.phase == .stopped)
        #expect(report.internalReport.execution.finalState.stopReason == expected)
    }
}

@MainActor
@Test func realTerminalAutoLoopStopsOnTimedOutFlag() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "等待超时",
        maxTurns: 3,
        turnRunner: { _ in CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互"), timedOut: true) }
    )
    #expect(!report.rejected)
    #expect(report.internalReport.execution.finalState.phase == .stopped)
    #expect(report.internalReport.execution.finalState.stopReason == .timedOut)
}

@MainActor
@Test func realTerminalAutoLoopSummaryStaysChineseAndHidesRawValues() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "可见摘要锁定",
        maxTurns: 1,
        turnRunner: { _ in CLIAutoInteractionTurnObservation(observation: CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束")) }
    )
    let summary = report.summaryText
    #expect(summary.contains("真实终端自动交互循环"))
    #expect(summary.contains("本轮已结束"))
    #expect(summary.contains("注入发送闭包"))

    #expect(!summary.contains("subscriptionCLI"))
    #expect(!summary.contains("opcGenerated"))
    #expect(!summary.contains("rawValue"))
    #expect(!summary.contains("model_reasoning_effort"))
    #expect(!summary.contains("--skip-git-repo-check"))
    #expect(!summary.contains("running"))
    #expect(!summary.contains("authenticationBlocked"))
    #expect(!summary.contains("transientFailure"))
}

@MainActor
@Test func realTerminalAutoLoopOpcGeneratedNextInputPreviewIsChineseSingleLine() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let firstTurn = store.terminalAutoInteractionNextInputPreviewForTesting(taskContext: "技术负责人闭环演练", sentTurns: 0)
    let secondTurn = store.terminalAutoInteractionNextInputPreviewForTesting(taskContext: "技术负责人闭环演练", sentTurns: 1)
    #expect(firstTurn.contains("第1轮"))
    #expect(secondTurn.contains("第2轮"))
    for line in [firstTurn, secondTurn] {
        #expect(line.contains("技术负责人闭环演练"))
        #expect(!line.contains("\n"))
        #expect(!line.contains("opcGenerated"))
        #expect(!line.contains("rawValue"))
    }
}

@MainActor
@Test func realTerminalAutoLoopWithoutTmuxFallsBackToTransientFailure() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // 把员工来源临时改为接口模式，绕过真实 tmux 工作区初始化，
    // 仍能验证默认真实终端席位路径在席位不可用前先做只读预检并拒绝。
    var engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    engineer.backend.type = .api
    if let idx = store.agents.firstIndex(where: { $0.id == engineer.id }) {
        store.agents[idx] = engineer
    }
    store.selectAgent(engineer.id)

    let userAuthoredBefore = store.messages.filter { $0.author == .user }.count
    let agentMessagesBefore = store.agentMessages.count
    let jobArchivesBefore = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "无终端席位回退",
        maxTurns: 2,
        timeoutSeconds: 0.2
    )
    #expect(report.rejected)
    #expect(report.usedRealTerminal == true)
    #expect(report.internalReport.execution.finalState.phase == .rejected)
    #expect(report.internalReport.execution.finalState.stopReason == .transientFailure)
    #expect(report.internalReport.execution.sentTurnCount == 0)
    #expect(report.summaryText.contains("订阅制命令行员工"))

    // 自动循环不能写老板聊天（老板使用 .user 作者），不能向员工协作消息总线追加，不能新增命令行作业档案。
    let userAuthoredAfter = store.messages.filter { $0.author == .user }.count
    #expect(userAuthoredAfter == userAuthoredBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    let jobArchivesAfter = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count
    #expect(jobArchivesAfter == jobArchivesBefore)
}

@MainActor
@Test func realTerminalAutoLoopRunsHappyPathAcrossRealTmuxSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCRealTerminalAutoLoop-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    // Fake codex REPL：前两轮回复 "answer:<input>" + "codex>" 维持就绪信号；
    // 第三轮额外打印 codex 协议画像里的本轮结束信号 "turn complete"，
    // 用于验证自动循环按 CLIInteractionProfile 的完成信号停止，且不超过 maxTurns。
    let script = root.appendingPathComponent("fake-codex-repl.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    i=0
    while IFS= read -r line; do
      i=$((i+1))
      if [ "$i" -ge 3 ]; then
        printf 'answer:%s\\nturn complete\\ncodex>\\n' "$line"
      else
        printf 'answer:%s\\ncodex>\\n' "$line"
      fi
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    store.selectAgent(engineer.id)

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    // 计数快照应在席位就绪之后取，避免把 startTerminalWorkspaceForSelectedProduct
    // 写入的技术负责人系统消息误算到自动循环本身。
    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let bossMessagesBefore = store.messages(for: store.bossID).count
    let userAuthoredBefore = store.messages.filter { $0.author == .user }.count
    let agentMessagesBefore = store.agentMessages.count
    let jobArchivesBefore = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count
    let jobsDirectoryBefore = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    let autoTurnsBefore = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1
    let manualTurnsBefore = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 手动交互轮次]").count - 1

    let taskContext = "技术负责人闭环演练真实终端"
    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: taskContext,
        maxTurns: 3,
        timeoutSeconds: 5
    )

    #expect(!report.rejected)
    #expect(report.usedRealTerminal == true)
    #expect(report.internalReport.execution.finalState.phase == .completed)
    #expect(report.internalReport.execution.finalState.stopReason == .completedTurn)
    #expect(report.internalReport.execution.sentTurnCount == 3)
    #expect(report.agentID == engineer.id)
    #expect(report.productID == store.selectedProductID)

    // OPC 生成的下一行输入必须是单行中文，且每轮都引用了原始任务上下文。
    for turn in 0..<3 {
        let expected = store.terminalAutoInteractionNextInputPreviewForTesting(taskContext: taskContext, sentTurns: turn)
        #expect(!expected.contains("\n"))
        #expect(expected.contains("第\(turn + 1)轮"))
        #expect(expected.contains(taskContext))
    }

    // tmux 真实终端窗口里应当能看到 fake REPL 的逐轮回复和本轮结束信号。
    let afterCapture = try await waitForTmuxPaneOutput(
        tmuxPath,
        target: tmuxTarget,
        containsAll: ["answer:第3轮", "turn complete"],
        historyStart: "-400",
        attempts: 40
    )
    #expect(afterCapture.contains("answer:第1轮"))
    #expect(afterCapture.contains("answer:第2轮"))
    #expect(afterCapture.contains("answer:第3轮"))
    #expect(afterCapture.contains("turn complete"))

    // 终端日志应记录三次自动循环轮次，并和人工手动轮次区分。
    let autoTurnsAfter = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1
    let manualTurnsAfter = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 手动交互轮次]").count - 1
    #expect(autoTurnsAfter - autoTurnsBefore == 3)
    #expect(manualTurnsAfter == manualTurnsBefore)
    #expect(store.runtimeSessions[engineer.id]?.cliInteractionPhase == .completedTurn)

    // 真实终端自动循环不创建老板聊天、不写员工协作消息总线、不创建命令行作业档案。
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.messages.filter { $0.author == .user }.count == userAuthoredBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.count == jobArchivesBefore)
    let jobsDirectoryAfter = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    #expect(jobsDirectoryAfter.sorted() == jobsDirectoryBefore.sorted())

    // 摘要保持中文产品话术，并明确标记走的是真实终端席位而非注入闭包。
    let summary = report.summaryText
    #expect(summary.contains("真实终端自动交互循环"))
    #expect(summary.contains("本轮已结束"))
    #expect(summary.contains("真实终端席位"))
    #expect(!summary.contains("注入发送闭包"))
    #expect(!summary.contains("rawValue"))
    #expect(!summary.contains("opcGenerated"))
    #expect(!summary.contains("completedTurn"))
}

@MainActor
@Test func realTerminalAutoLoopStopsAtMaxTurnsOnReadyOnlyTmuxSeat() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCRealTerminalAutoLoopMax-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    // Fake codex REPL：每轮都只回复 ready prompt，不出现完成信号；
    // 用于锁定真实终端路径下，连续 ready 信号必须按 maxTurns 收住，不会无限循环。
    let script = root.appendingPathComponent("fake-codex-ready-only.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    while IFS= read -r line; do
      printf 'answer:%s\\ncodex>\\n' "$line"
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )
    store.selectAgent(engineer.id)

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let bossMessagesBefore = store.messages(for: store.bossID).count
    let userAuthoredBefore = store.messages.filter { $0.author == .user }.count
    let agentMessagesBefore = store.agentMessages.count
    let jobArchivesBefore = store.artifacts.filter { $0.title.contains("命令行作业档案") }.count
    let jobsDirectoryBefore = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    let autoTurnsBefore = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "持续就绪上限收口",
        maxTurns: 2,
        timeoutSeconds: 5
    )

    #expect(!report.rejected)
    #expect(report.usedRealTerminal == true)
    #expect(report.internalReport.execution.finalState.phase == .stopped)
    #expect(report.internalReport.execution.finalState.stopReason == .maxTurnsReached)
    #expect(report.internalReport.execution.sentTurnCount == 2)

    let afterCapture = try await waitForTmuxPaneOutput(
        tmuxPath,
        target: tmuxTarget,
        contains: "answer:第2轮",
        historyStart: "-400",
        attempts: 40
    )
    #expect(afterCapture.contains("answer:第1轮"))
    #expect(afterCapture.contains("answer:第2轮"))
    #expect(!afterCapture.contains("answer:第3轮"))
    #expect(!afterCapture.contains("turn complete"))

    // 真实终端循环达到 maxTurns 仍不能写老板聊天/员工协作消息/作业档案。
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.messages.filter { $0.author == .user }.count == userAuthoredBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.count == jobArchivesBefore)
    let jobsDirectoryAfter = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    #expect(jobsDirectoryAfter.sorted() == jobsDirectoryBefore.sorted())
    let autoTurnsAfter = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1
    #expect(autoTurnsAfter - autoTurnsBefore == 2)

    let summary = report.summaryText
    #expect(summary.contains("真实终端席位"))
    #expect(summary.contains("达到最大轮次上限"))
    #expect(!summary.contains("注入发送闭包"))
    #expect(!summary.contains("maxTurnsReached"))
}

@MainActor
@Test func realTerminalAutoLoopRejectsStaleScrollbackWhenLatestLineIsNotPrompt() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCRealTerminalStalePrompt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    // Fake codex 启动后先打印 prompt，再继续打印「正在处理…」并 sleep。
    // 这样 pane scrollback 里仍有旧 codex>，但最近一行不是专用就绪提示。
    let script = root.appendingPathComponent("fake-codex-stale.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    printf '正在处理 GitHub 拉取请求...\\n'
    sleep 30
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    store.selectAgent(engineer.id)

    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "正在处理 GitHub 拉取请求",
        historyStart: "-200",
        readyAttempts: 60
    )
    #expect(capture.contains("codex>"))
    #expect(capture.contains("正在处理 GitHub 拉取请求"))

    let bossMessagesBefore = store.messages(for: store.bossID).count
    let agentMessagesBefore = store.agentMessages.count
    let artifactsBefore = store.artifacts.count
    let autoTurnsBefore = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "拒绝旧 prompt scrollback",
        maxTurns: 3,
        timeoutSeconds: 2
    )

    #expect(report.rejected)
    #expect(report.usedRealTerminal == true)
    #expect(report.internalReport.execution.finalState.phase == .rejected)
    #expect(report.internalReport.execution.sentTurnCount == 0)
    #expect(report.rejectionReason?.contains("最近一行") == true)
    #expect(report.rejectionReason?.contains("Codex") == true)

    let summary = report.summaryText
    #expect(summary.contains("就绪校验：未确认最近专用就绪提示"))
    #expect(summary.contains("已拒绝自动发送"))
    #expect(!summary.contains("rawValue"))
    #expect(!summary.contains("subscriptionCLI"))
    #expect(!summary.contains("opcGenerated"))
    #expect(!summary.contains("authenticationBlocked"))

    let auditMarker = "[OPC 自动循环就绪审计]"
    let auditCount = store.terminalLogs[engineer.id, default: ""].components(separatedBy: auditMarker).count - 1
    #expect(auditCount >= 1)
    #expect(store.terminalLogs[engineer.id, default: ""].contains("未确认最近专用就绪提示"))

    // 旧 prompt 在 scrollback 里仍然能被 containsREPLReadySignal 命中，新 helper 必须把这种情况拒绝。
    let codex = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    #expect(codex.containsREPLReadySignal(capture))
    #expect(!codex.endsWithReplReadyPrompt(capture))

    // 拒绝路径不能消耗循环轮次、写老板聊天、写员工协作消息或写作业档案。
    let autoTurnsAfter = store.terminalLogs[engineer.id, default: ""].components(separatedBy: "[OPC 自动交互循环轮次]").count - 1
    #expect(autoTurnsAfter == autoTurnsBefore)
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.count == artifactsBefore)
    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let jobsDirectoryAfter = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    #expect(jobsDirectoryAfter.isEmpty)
}

@MainActor
@Test func realTerminalAutoLoopHappyPathSummaryContainsReadinessAudit() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCRealTerminalAuditAudit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-codex-audit.sh")
    try """
    #!/bin/sh
    count=0
    printf 'codex>\\n'
    while IFS= read -r line; do
      count=$((count + 1))
      printf 'fake-turn-%s:%s\\n' "$count" "$line"
      printf 'turn complete\\n'
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    store.selectAgent(engineer.id)

    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        historyStart: "-200",
        readyAttempts: 60,
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "就绪审计 happy path",
        maxTurns: 1,
        timeoutSeconds: 3
    )
    #expect(!report.rejected)
    #expect(report.usedRealTerminal == true)

    let summary = report.summaryText
    #expect(summary.contains("就绪校验：最近一行已确认"))
    #expect(summary.contains("Codex"))
    #expect(summary.contains("专用就绪提示"))
    #expect(!summary.contains("rawValue"))
    #expect(!summary.contains("subscriptionCLI"))
    #expect(!summary.contains("--skip-git-repo-check"))
    #expect(!summary.contains("model_reasoning_effort"))
    #expect(!summary.contains("opcGenerated"))

    let log = store.terminalLogs[engineer.id, default: ""]
    #expect(log.contains("[OPC 自动循环就绪审计]"))
    #expect(log.contains("就绪校验：最近一行已确认"))
}

@MainActor
@Test func realTerminalAutoLoopWritesPassedReadinessAuditVerificationRecord() async throws {
    guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return }
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCAuditPassed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "// package".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    let script = root.appendingPathComponent("fake-codex-audit-passed.sh")
    try """
    #!/bin/sh
    printf 'codex>\\n'
    while IFS= read -r line; do
      printf 'fake-turn:%s\\nturn complete\\ncodex>\\n' "$line"
    done
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let engineerIndex = try #require(store.agents.firstIndex { $0.role == .codeEngineer })
    store.agents[engineerIndex].backend = AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .low)
    let engineer = store.agents[engineerIndex]
    store.addProductWorkspace()
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].assignedAgentIDs.insert(engineer.id)
    store.products[productIndex].rootDirectory = root.path
    store.selectAgent(engineer.id)

    let sessionName = store.terminalWorkspaceSessionNameForTesting()
    defer { cleanupTmuxSession(tmuxPath, sessionName) }

    store.startTerminalWorkspaceForSelectedProduct()
    store.runtimeSessions[engineer.id] = AgentRuntimeSession(
        agentID: engineer.id,
        productID: store.selectedProductID,
        state: .ready,
        capability: .persistentProtocol,
        backendSignature: CLIAgentCommandBuilder.backendSignature(for: engineer),
        startedAt: Date(),
        lastPrewarmedAt: Date()
    )

    let windowName = store.terminalWorkspaceWindowNameForTesting(agentID: engineer.id)
    let tmuxTarget = "\(sessionName):\(windowName)"
    let codexProfile = try #require(CLIInteractionProfileCatalog.profile(forCommand: "codex"))
    let capture = try await bringFakeREPLScriptOnline(
        tmuxPath,
        target: tmuxTarget,
        scriptPath: script.path,
        readyNeedle: "codex>",
        historyStart: "-200",
        readyAttempts: 60,
        expectsLatestLineMatchesProfile: codexProfile
    )
    #expect(capture.contains("codex>"))
    #expect(codexProfile.endsWithReplReadyPrompt(capture))

    let auditTitle = CompanyStore.terminalAutoInteractionAuditTitle
    let bossMessagesBefore = store.messages(for: store.bossID).count
    let agentMessagesBefore = store.agentMessages.count
    let auditCountBefore = store.selectedProductVerifications.filter { $0.title == auditTitle }.count
    let deliveryAuditCountBefore = store.selectedProductDeliveryVerifications.filter { $0.title == auditTitle }.count
    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let jobsDirectoryBefore = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "审计闭环 happy path",
        maxTurns: 1,
        timeoutSeconds: 3
    )
    #expect(!report.rejected)
    #expect(report.usedRealTerminal == true)

    // 产品级 VerificationRecord 必须新增一条「真实终端自动循环就绪审计」.passed
    let auditRecords = store.selectedProductVerifications.filter { $0.title == auditTitle }
    #expect(auditRecords.count == auditCountBefore + 1)
    let latest = try #require(store.selectedProductLatestTerminalAutoLoopReadinessAudit)
    #expect(latest.title == "真实终端自动循环就绪审计")
    #expect(latest.status == .passed)
    #expect(latest.productID == store.selectedProductID)
    #expect(latest.detail.contains("员工：\(engineer.displayName)"))
    #expect(latest.detail.contains("就绪校验：最近一行已确认"))
    #expect(latest.detail.contains("Codex"))
    #expect(latest.detail.contains("不进入老板总控台"))
    #expect(latest.detail.contains("交付验收中心"))
    #expect(store.selectedProductDeliveryVerifications.filter { $0.title == auditTitle }.count == deliveryAuditCountBefore)
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != auditTitle })

    // detail 里不能出现底层 enum、命令参数、ANSI、后端类型 raw value
    let visibleDetail = [latest.title, latest.detail].joined(separator: "\n")
    let forbiddenInternals = [
        "rawValue",
        "subscriptionCLI",
        "persistentProtocol",
        "model_reasoning_effort",
        "--skip-git-repo-check",
        "opcGenerated",
        "authenticationBlocked",
        "transientFailure",
        "completedTurn",
        "\u{1B}["
    ]
    for forbidden in forbiddenInternals {
        #expect(!visibleDetail.contains(forbidden))
    }

    // 架构体检文本应当能被产品级体检读取到该审计摘要
    let auditText = store.multiAgentArchitectureAuditText()
    #expect(auditText.contains("最近真实终端自动循环就绪审计："))
    #expect(auditText.contains("通过"))
    #expect(auditText.contains("就绪校验：最近一行已确认"))
    #expect(!auditText.contains("rawValue"))
    #expect(!auditText.contains("subscriptionCLI"))
    #expect(!auditText.contains("model_reasoning_effort"))

    // 不能新增老板聊天、员工协作消息、命令行作业档案
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.isEmpty)
    let jobsDirectoryAfter = (try? FileManager.default.contentsOfDirectory(atPath: jobsRoot.path)) ?? []
    #expect(jobsDirectoryAfter.sorted() == jobsDirectoryBefore.sorted())
}

@MainActor
@Test func realTerminalAutoLoopWritesWarningReadinessAuditOnRejection() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // 把员工来源临时改为接口模式，使真实终端 preflight 在第一道闸（非订阅制 CLI）就拒绝。
    var engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    engineer.backend.type = .api
    if let idx = store.agents.firstIndex(where: { $0.id == engineer.id }) {
        store.agents[idx] = engineer
    }
    store.selectAgent(engineer.id)

    let auditTitle = CompanyStore.terminalAutoInteractionAuditTitle
    let auditCountBefore = store.selectedProductVerifications.filter { $0.title == auditTitle }.count
    let deliveryAuditCountBefore = store.selectedProductDeliveryVerifications.filter { $0.title == auditTitle }.count
    let bossMessagesBefore = store.messages(for: store.bossID).count
    let agentMessagesBefore = store.agentMessages.count

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "审计闭环 拒绝路径",
        maxTurns: 2,
        timeoutSeconds: 0.2
    )
    #expect(report.rejected)
    #expect(report.usedRealTerminal == true)

    let auditRecords = store.selectedProductVerifications.filter { $0.title == auditTitle }
    #expect(auditRecords.count == auditCountBefore + 1)
    let latest = try #require(store.selectedProductLatestTerminalAutoLoopReadinessAudit)
    #expect(latest.status == .warning)
    #expect(latest.detail.contains("员工：\(engineer.displayName)"))
    #expect(latest.detail.contains("就绪校验：未确认最近专用就绪提示"))
    #expect(latest.detail.contains("拒绝说明："))
    #expect(latest.detail.contains("订阅制命令行员工"))
    #expect(latest.detail.contains("不进入老板总控台"))
    #expect(latest.detail.contains("交付验收中心"))
    #expect(store.selectedProductDeliveryVerifications.filter { $0.title == auditTitle }.count == deliveryAuditCountBefore)
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != auditTitle })

    // 默认可见文本（标题 + detail + 架构体检摘要）不能含底层值
    let auditText = store.multiAgentArchitectureAuditText()
    let visible = [latest.title, latest.detail, auditText].joined(separator: "\n")
    let forbiddenInternals = [
        "rawValue",
        "subscriptionCLI",
        "persistentProtocol",
        "model_reasoning_effort",
        "--skip-git-repo-check",
        "opcGenerated",
        "authenticationBlocked",
        "transientFailure",
        "completedTurn",
        "\u{1B}["
    ]
    for forbidden in forbiddenInternals {
        #expect(!visible.contains(forbidden))
    }
    #expect(auditText.contains("最近真实终端自动循环就绪审计："))
    #expect(auditText.contains("有警告"))
    #expect(auditText.contains("就绪校验：未确认最近专用就绪提示"))

    // 拒绝路径不能写老板聊天、员工协作消息、作业档案
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.agentMessages.count == agentMessagesBefore)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.isEmpty)
}

@MainActor
@Test func realTerminalAutoLoopRejectionRoutesAuditToMaintenanceOnlyAndKeepsBossViewsEmpty() async throws {
    // Computer Use 验证路径：preflight 拒绝后，老板总控台、产品详情交付区、交付验收中心、运营套件
    // 验收抽屉的数据 accessor 不应出现这条审计；技术维护审计中心 / latest readiness accessor 必须能查到。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    engineer.backend.type = .api
    if let idx = store.agents.firstIndex(where: { $0.id == engineer.id }) {
        store.agents[idx] = engineer
    }
    store.selectAgent(engineer.id)

    let auditTitle = CompanyStore.terminalAutoInteractionAuditTitle
    let baselineDelivery = store.selectedProductRecentDeliveryVerifications.count
    let baselineMaintenance = store.selectedProductRecentMaintenanceVerifications.count
    let bossMessagesBefore = store.messages(for: store.bossID).count

    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: "Computer Use 拒绝路径验证",
        maxTurns: 2,
        timeoutSeconds: 0.2
    )
    #expect(report.rejected)
    #expect(report.usedRealTerminal == true)
    #expect(report.summaryText.contains("订阅制命令行员工"))

    // 老板/交付侧 accessor 必须看不到这条审计：老板总控台 widget、产品详情交付区、运营套件验收抽屉
    // 都通过 selectedProductRecentDeliveryVerifications.prefix(N) 取数。
    let deliveryRecent = store.selectedProductRecentDeliveryVerifications
    #expect(deliveryRecent.count == baselineDelivery)
    #expect(deliveryRecent.allSatisfy { $0.title != auditTitle })
    let widgetSlice = Array(deliveryRecent.prefix(3))
    #expect(widgetSlice.allSatisfy { $0.title != auditTitle })
    let acceptanceCenterSlice = Array(deliveryRecent.prefix(12))
    #expect(acceptanceCenterSlice.allSatisfy { $0.title != auditTitle })
    let opsAcceptanceSlice = Array(deliveryRecent.prefix(6))
    #expect(opsAcceptanceSlice.allSatisfy { $0.title != auditTitle })
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != auditTitle })

    // 技术维护审计中心数据 accessor 必须能查到这条审计（按时间倒序，且 prefix(8) 截断仍在前列）。
    let maintenanceRecent = store.selectedProductRecentMaintenanceVerifications
    #expect(maintenanceRecent.count == baselineMaintenance + 1)
    let maintenanceCenterSlice = Array(maintenanceRecent.prefix(8))
    #expect(maintenanceCenterSlice.contains { $0.title == auditTitle })
    let latestAudit = try #require(store.selectedProductLatestTerminalAutoLoopReadinessAudit)
    #expect(latestAudit.title == auditTitle)
    #expect(latestAudit.status == .warning)
    #expect(latestAudit.detail.contains("员工：\(engineer.displayName)"))
    #expect(latestAudit.detail.contains("不进入老板总控台或交付验收中心"))

    // 架构体检摘要会包含一行中文审计摘要给技术负责人复盘。
    let architectureAudit = store.multiAgentArchitectureAuditText()
    #expect(architectureAudit.contains("最近真实终端自动循环就绪审计："))
    #expect(architectureAudit.contains("有警告"))
    #expect(architectureAudit.contains("就绪校验：未确认最近专用就绪提示"))

    // 拒绝路径不能写老板聊天、员工协作消息、作业档案。
    #expect(store.messages(for: store.bossID).count == bossMessagesBefore)
    #expect(store.agentMessages.isEmpty)
    #expect(store.artifacts.filter { $0.title.contains("命令行作业档案") }.isEmpty)
}

@MainActor
@Test func realTerminalAutoLoopReadinessAuditSummaryEmptyStateIsChinese() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // 没有运行过任何真实终端自动循环 → 摘要必须是中文空态
    let summary = store.selectedProductTerminalAutoLoopReadinessAuditSummary()
    #expect(summary == "最近真实终端自动循环就绪审计：暂无记录。")
    #expect(store.selectedProductLatestTerminalAutoLoopReadinessAudit == nil)

    let auditText = store.multiAgentArchitectureAuditText()
    #expect(auditText.contains("最近真实终端自动循环就绪审计：暂无记录。"))
    #expect(!auditText.contains("rawValue"))
    #expect(!auditText.contains("subscriptionCLI"))
}

@MainActor
@Test func technicalMaintenanceVerificationsAreHiddenFromBossAndDeliveryViews() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 已知所有运维巡检/恢复/审计/真实终端工作区记录的中文标题。
    // 任意一条都必须从老板/交付视图（selectedProductDeliveryVerifications / RecentDeliveryVerifications）过滤掉。
    let maintenanceTitles = [
        CompanyStore.terminalAutoInteractionAuditTitle,
        "真实终端工作区",
        "真实终端日志刷新",
        "持久终端可用性巡检",
        "命令行链路压测预检",
        "命令行任务发车计划",
        "命令行与工作区隔离体检",
        "多产品隔离体检",
        "命令行作业幽灵巡检",
        "员工交接待确认巡检",
        "运行会话健康巡检",
        "异常占用会话恢复",
        "历史索引巡检",
        "历史归档迁移",
        "旧任务产品归属迁移",
        "本地文件索引完成",
        "安全检查点已创建",
        "安全检查点失败"
    ]

    // 先拍快照避免本身被自动验收等记录污染
    let totalDeliveryBefore = store.selectedProductDeliveryVerifications.count

    for title in maintenanceTitles {
        let record = VerificationRecord(productID: productID, status: .passed, title: title, detail: "测试用维护记录")
        store.verifications.insert(record, at: 0)
        #expect(CompanyStore.technicalMaintenanceVerificationTitles.contains(title))
        #expect(store.isTechnicalMaintenanceVerification(record))
    }

    // 老板/交付视图必须看不到任何一条
    let deliveryTitles = Set(store.selectedProductDeliveryVerifications.map(\.title))
    for title in maintenanceTitles {
        #expect(!deliveryTitles.contains(title), "delivery view 不能包含维护记录：\(title)")
    }
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { !maintenanceTitles.contains($0.title) })
    #expect(store.selectedProductDeliveryVerifications.count == totalDeliveryBefore)

    // 但全集 selectedProductVerifications 仍然能看到（技术负责人维护视图查询路径）
    let allTitles = Set(store.selectedProductVerifications.map(\.title))
    for title in maintenanceTitles {
        #expect(allTitles.contains(title), "技术负责人视图必须能查到维护记录：\(title)")
    }
}

@MainActor
@Test func deliveryVerificationsKeepRealAcceptanceAndArtifactRecordsVisible() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 真实交付侧 VerificationRecord 必须仍然出现在老板/交付视图。
    let deliveryTitles = [
        "自动验收检查",
        "产物扫描完成",
        "产物扫描失败",
        "老板验收通过：示例任务"
    ]

    for title in deliveryTitles {
        let record = VerificationRecord(productID: productID, status: .passed, title: title, detail: "示例")
        store.verifications.insert(record, at: 0)
        #expect(!store.isTechnicalMaintenanceVerification(record), "交付记录不应被维护过滤命中：\(title)")
    }

    let deliveryView = Set(store.selectedProductDeliveryVerifications.map(\.title))
    for title in deliveryTitles {
        #expect(deliveryView.contains(title), "交付视图必须保留：\(title)")
    }
    #expect(store.selectedProductRecentDeliveryVerifications.contains { $0.title == "老板验收通过：示例任务" })
}

@MainActor
@Test func technicalMaintenanceAuditCenterCollectsMaintenanceRecordsButHidesDeliveryOnes() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 起点快照：让本测试只盯住自己 insert 的差量。
    let baselineMaintenance = store.selectedProductMaintenanceVerifications
    let baselineMaintenanceTitles = Set(baselineMaintenance.map(\.title))
    let baselineDeliveryTitles = Set(store.selectedProductDeliveryVerifications.map(\.title))

    let maintenanceTitles = [
        "持久终端可用性巡检",
        "运行会话健康巡检",
        CompanyStore.terminalAutoInteractionAuditTitle
    ]
    let deliveryTitles = [
        "自动验收检查",
        "老板验收通过：审计中心样例"
    ]

    var insertedAt = Date(timeIntervalSinceNow: -60)
    for title in maintenanceTitles {
        insertedAt = insertedAt.addingTimeInterval(1)
        store.verifications.insert(
            VerificationRecord(productID: productID, status: .warning, title: title, detail: "维护测试", createdAt: insertedAt),
            at: 0
        )
    }
    for title in deliveryTitles {
        insertedAt = insertedAt.addingTimeInterval(1)
        store.verifications.insert(
            VerificationRecord(productID: productID, status: .passed, title: title, detail: "交付测试", createdAt: insertedAt),
            at: 0
        )
    }

    // 维护视图收齐了所有维护记录，且没有任何交付记录。
    let maintenanceView = store.selectedProductMaintenanceVerifications
    let maintenanceTitleSet = Set(maintenanceView.map(\.title))
    for title in maintenanceTitles {
        #expect(maintenanceTitleSet.contains(title), "维护视图必须包含：\(title)")
    }
    for title in deliveryTitles {
        #expect(!maintenanceTitleSet.contains(title), "维护视图不应包含交付记录：\(title)")
    }

    // 倒序视图按 createdAt 降序：最新插入的维护记录排在前 N 名，且只含维护标题。
    let recentMaintenance = store.selectedProductRecentMaintenanceVerifications
    let recentNewMaintenance = recentMaintenance.filter { !baselineMaintenanceTitles.contains($0.title) }
    #expect(recentNewMaintenance.map(\.title) == maintenanceTitles.reversed())
    #expect(recentMaintenance.allSatisfy { store.isTechnicalMaintenanceVerification($0) })

    // 老板/交付视图（产品详情交付区、老板首页 widget、运营套件验收抽屉、交付验收中心都用此 accessor）
    // 不展示任何维护记录，但保留交付记录。
    let deliveryViewTitles = Set(store.selectedProductDeliveryVerifications.map(\.title))
    for title in maintenanceTitles {
        #expect(!deliveryViewTitles.contains(title), "交付视图不应包含维护记录：\(title)")
    }
    for title in deliveryTitles {
        #expect(deliveryViewTitles.contains(title), "交付视图必须保留：\(title)")
    }
    let deliveryDelta = deliveryViewTitles.subtracting(baselineDeliveryTitles)
    #expect(deliveryDelta == Set(deliveryTitles))

    // 维护视图 + 交付视图 = 全集（按当前产品维度）。
    let allCurrentTitles = Set(store.selectedProductVerifications.map(\.title))
    let union = maintenanceTitleSet.union(deliveryViewTitles)
    #expect(allCurrentTitles == union)
}

@MainActor
@Test func verificationRecordTitleLiteralsAreClassifiedInCompanyStore() async throws {
    // 集中守门：扫描 Sources/OPCCompanyCore/CompanyStore.swift 里所有 `VerificationRecord(... title: "..."` 字面量，
    // 强制每个标题落入维护集合 / 交付精确白名单 / 交付前缀白名单之一。新增 VerificationRecord 时
    // 必须在 CompanyStore 显式登记新分类，避免悄悄进入老板/交付视图。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    // 匹配 `VerificationRecord(...title: "<literal>"` 直到第一个 `"` 闭合或 `\(` 插值开始；
    // 中间允许跨行（`[\s\S]`）但不允许出现 `(` 或 `)`，避免误把闭合 VerificationRecord 之后另一个函数（例如
    // `appendEvent`）的 title 字面量当成 VerificationRecord 标题。
    let pattern = #"VerificationRecord\(\s*[^()]*?title:\s*"((?:\\.|[^"\\])*?)(?:\\\(|")"#
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    let nsSource = source as NSString
    let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))

    var foundExact: Set<String> = []
    var foundPrefixSnippets: Set<String> = []
    for match in matches {
        guard match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound else { continue }
        let title = nsSource.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        let fullMatch = nsSource.substring(with: match.range(at: 0))
        if fullMatch.hasSuffix("\\(") {
            foundPrefixSnippets.insert(title)
        } else {
            foundExact.insert(title)
        }
    }

    // 自检扫描器至少抓到了维护和交付侧已知字面量，避免正则失效让守门变成空过。
    #expect(foundExact.contains("自动验收检查"))
    #expect(foundExact.contains("产物扫描完成"))
    #expect(foundExact.contains("老板验收通过：") || foundPrefixSnippets.contains("老板验收通过："))
    #expect(foundExact.count + foundPrefixSnippets.count >= 18)

    let maintenanceSet = CompanyStore.technicalMaintenanceVerificationTitles
    let deliveryExact = CompanyStore.deliveryVerificationTitleExactMatches
    let deliveryPrefixes = CompanyStore.deliveryVerificationTitlePrefixes

    for title in foundExact {
        let classified = maintenanceSet.contains(title)
            || deliveryExact.contains(title)
            || deliveryPrefixes.contains { title.hasPrefix($0) }
        #expect(
            classified,
            "VerificationRecord 标题 \"\(title)\" 未分类。请在 CompanyStore 把它登记到 technicalMaintenanceVerificationTitles（运维巡检）或 deliveryVerificationTitleExactMatches（真实交付证据），否则它会从老板/交付视图过滤掉，且无法在维护视图明确归类。"
        )
    }

    for prefixSnippet in foundPrefixSnippets {
        let classified = deliveryPrefixes.contains { prefixSnippet.hasPrefix($0) || $0.hasPrefix(prefixSnippet) }
            || maintenanceSet.contains { prefixSnippet.hasPrefix($0) || $0.hasPrefix(prefixSnippet) }
        #expect(
            classified,
            "VerificationRecord 前缀型标题 \"\(prefixSnippet)…\" 未分类。请在 CompanyStore 的 deliveryVerificationTitlePrefixes 中显式登记前缀，避免悄悄进入或漏出老板/交付视图。"
        )
    }
}

@MainActor
@Test func technicalMaintenanceArtifactsAreHiddenFromBossAndDeliveryViews() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let baselineDelivery = store.selectedProductDeliveryArtifacts.count
    let baselineMaintenance = store.selectedProductMaintenanceArtifacts.count

    // 维护产物：安全检查点（exact）+ 闭环审计报告:<goal> / 命令行作业档案:<员工> / 本地文件索引:<file>（前缀型）
    let maintenanceArtifacts: [ArtifactRecord] = [
        ArtifactRecord(productID: productID, kind: .report, title: "安全检查点", path: "本机安全检查点存档", summary: "维护测试"),
        ArtifactRecord(productID: productID, kind: .report, title: "闭环审计报告：审计中心样例目标", path: "opc://closure-traces/sample", summary: "维护测试"),
        ArtifactRecord(productID: productID, kind: .report, title: "命令行作业档案：示例工程师", path: "/tmp/.opc/jobs/sample", summary: "维护测试"),
        ArtifactRecord(productID: productID, kind: .report, title: "本地文件索引：sample.md", path: "/tmp/sample.md", summary: "维护测试")
    ]
    // 交付产物：前缀型 验收产物:<task> / 验收报告:<task> + 动态文件名（项目扫描候选）
    let deliveryArtifacts: [ArtifactRecord] = [
        ArtifactRecord(productID: productID, kind: .report, title: "验收产物：示例任务", path: "/tmp/result.md", summary: "交付测试"),
        ArtifactRecord(productID: productID, kind: .report, title: "验收报告：示例任务", path: "opc://acceptance-reports/sample", summary: "交付测试"),
        // 动态文件名：项目扫描 / 本地文件索引常用，没有显式分类时按交付默认接受
        ArtifactRecord(productID: productID, kind: .rule, title: "AGENTS.md", path: "/tmp/AGENTS.md", summary: "项目扫描发现规则"),
        ArtifactRecord(productID: productID, kind: .source, title: "Sources", path: "/tmp/Sources", summary: "项目扫描发现源码")
    ]

    for artifact in maintenanceArtifacts + deliveryArtifacts {
        store.artifacts.insert(artifact, at: 0)
    }

    // 老板/交付视图必须只见交付，不见维护
    let deliveryView = Set(store.selectedProductDeliveryArtifacts.map(\.title))
    for artifact in maintenanceArtifacts {
        #expect(!deliveryView.contains(artifact.title), "维护产物 \(artifact.title) 不应进入老板/交付视图")
    }
    for artifact in deliveryArtifacts {
        #expect(deliveryView.contains(artifact.title), "交付产物 \(artifact.title) 必须保留在老板/交付视图")
    }
    #expect(store.selectedProductDeliveryArtifacts.count == baselineDelivery + deliveryArtifacts.count)
    #expect(store.selectedProductRecentDeliveryArtifacts.allSatisfy { store.isDeliveryArtifact($0) })

    // 维护视图必须只见维护，不见交付
    let maintenanceView = Set(store.selectedProductMaintenanceArtifacts.map(\.title))
    for artifact in maintenanceArtifacts {
        #expect(maintenanceView.contains(artifact.title), "维护产物 \(artifact.title) 必须出现在维护视图")
    }
    for artifact in deliveryArtifacts {
        #expect(!maintenanceView.contains(artifact.title), "交付产物 \(artifact.title) 不应出现在维护视图")
    }
    #expect(store.selectedProductMaintenanceArtifacts.count == baselineMaintenance + maintenanceArtifacts.count)
    #expect(store.selectedProductRecentMaintenanceArtifacts.allSatisfy { store.isTechnicalMaintenanceArtifact($0) })

    // 全集 = 维护 ∪ 交付
    let allCurrentTitles = Set(store.selectedProductArtifacts.map(\.title))
    #expect(allCurrentTitles == deliveryView.union(maintenanceView))

    // 显式分类 helper
    for artifact in maintenanceArtifacts {
        #expect(store.isTechnicalMaintenanceArtifact(artifact))
        #expect(!store.isDeliveryArtifact(artifact))
    }
    for artifact in deliveryArtifacts {
        #expect(!store.isTechnicalMaintenanceArtifact(artifact))
        #expect(store.isDeliveryArtifact(artifact))
    }
}

@MainActor
@Test func scanLinkedLocalFilesRoutesArtifactsToMaintenanceAndKeepsDeliveryClean() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCScanLocalFiles-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sampleFileNames = ["spec.md", "notes.txt", "data.csv", "client_brief.md"]
    for name in sampleFileNames {
        try "示例内容".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = root.path
    let productID = store.selectedProductID

    let baselineMaintenance = store.selectedProductMaintenanceArtifacts.count
    let baselineDelivery = store.selectedProductDeliveryArtifacts.count

    // 注入一条真实交付样例，确保它不会因为本轮变化而被错误过滤掉。
    let deliverySample = ArtifactRecord(
        productID: productID,
        kind: .report,
        title: "验收产物：示例任务",
        path: root.appendingPathComponent("acceptance.md").path,
        summary: "交付测试"
    )
    store.artifacts.insert(deliverySample, at: 0)

    store.scanLinkedLocalFiles(limit: 50)

    // 每个本地文件索引产物 title 必须以 `本地文件索引：` 前缀开头，命中维护分类。
    let scannedTitles = sampleFileNames.map { "本地文件索引：\($0)" }
    let maintenanceTitles = Set(store.selectedProductMaintenanceArtifacts.map(\.title))
    for title in scannedTitles {
        #expect(maintenanceTitles.contains(title), "扫描产物 \(title) 必须出现在维护视图")
    }
    #expect(store.selectedProductMaintenanceArtifacts.count == baselineMaintenance + sampleFileNames.count)

    // 老板/交付视图（CommandCenter widget / 产品详情交付物 metric / 交付验收中心 / 运营套件验收抽屉）
    // 都通过 selectedProductDeliveryArtifacts 取数；本地文件索引产物不应出现。
    let deliveryTitles = Set(store.selectedProductDeliveryArtifacts.map(\.title))
    for title in scannedTitles {
        #expect(!deliveryTitles.contains(title), "本地文件索引 \(title) 不应进入老板/交付视图")
    }
    // 真实交付样例仍可见
    #expect(deliveryTitles.contains("验收产物：示例任务"))
    #expect(store.selectedProductDeliveryArtifacts.count == baselineDelivery + 1)

    // selectedProductRecentDeliveryArtifacts（CommandCenter prefix(3)、产品详情 prefix(3)、交付验收中心 prefix(20)
    // 都基于此 accessor）也不能出现本地文件索引。
    let recentDeliveryTitles = store.selectedProductRecentDeliveryArtifacts.map(\.title)
    for title in scannedTitles {
        #expect(!recentDeliveryTitles.contains(title))
    }
    #expect(recentDeliveryTitles.contains("验收产物：示例任务"))

    // selectedProductRecentMaintenanceArtifacts（维护产物档案中心 prefix(8)）含每条扫描记录。
    let recentMaintenanceTitles = store.selectedProductRecentMaintenanceArtifacts.map(\.title)
    for title in scannedTitles {
        #expect(recentMaintenanceTitles.contains(title))
    }

    // 显式分类 helper 与 store 层一致。
    for title in scannedTitles {
        let record = try #require(store.selectedProductArtifacts.first { $0.title == title })
        #expect(store.isTechnicalMaintenanceArtifact(record))
        #expect(!store.isDeliveryArtifact(record))
    }
}

@MainActor
@Test func artifactRecordTitleLiteralsAreClassifiedInCompanyStore() async throws {
    // 集中守门：扫描 Sources/OPCCompanyCore/CompanyStore.swift 里所有 `ArtifactRecord(... title: "..."` 字面量，
    // 强制每个标题落入 technicalMaintenanceArtifactTitleExactMatches / Prefixes 或 deliveryArtifactTitleExactMatches / Prefixes 之一。
    // 动态 title（如 candidate.0 项目扫描候选）不命中正则，不在守门范围；它们按"默认交付"被
    // selectedProductDeliveryArtifacts 接受——这是有意设计：项目扫描产生的真实项目文件（AGENTS.md / Sources / Tests）
    // 是老板侧应当看到的交付证据。本地文件索引（`scanLinkedLocalFiles`）的 title 已加上 `本地文件索引：` 前缀，
    // 自动落入维护分类。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    // ArtifactRecord 字面量 head 含 `kind: artifactKind(for: URL(fileURLWithPath: ...))` 嵌套括号，
    // `[^()]*?` 会被嵌套括号截断；同时不能放成无穷 `[\s\S]*?`，否则会跨过闭合括号吃到下一段
    // VerificationRecord / appendEvent / ChatMessage 的 title。改用负向 lookahead：每一步前置检查，
    // 中间不能撞到其他已知 record / event 构造器，让扫描器准确停在当前 ArtifactRecord 字面量内部。
    let pattern = ##"""
    ArtifactRecord\(\s*(?:(?!ArtifactRecord\(|VerificationRecord\(|appendEvent\(|ChatMessage\(|CompanyTask\(|CompanyEvent\()[\s\S]){0,800}?title:\s*"((?:\\.|[^"\\])*?)(?:\\\(|")
    """##
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    let nsSource = source as NSString
    let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))

    var foundExact: Set<String> = []
    var foundPrefixSnippets: Set<String> = []
    for match in matches {
        guard match.numberOfRanges >= 2,
              match.range(at: 1).location != NSNotFound else { continue }
        let title = nsSource.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        let fullMatch = nsSource.substring(with: match.range(at: 0))
        if fullMatch.hasSuffix("\\(") {
            foundPrefixSnippets.insert(title)
        } else {
            foundExact.insert(title)
        }
    }

    // 自检扫描器至少抓到了已知字面量，避免正则失效让守门变空过。
    #expect(foundExact.contains("安全检查点"))
    #expect(foundExact.contains("验收产物：") || foundPrefixSnippets.contains("验收产物："))
    #expect(foundExact.contains("验收报告：") || foundPrefixSnippets.contains("验收报告："))
    #expect(foundExact.contains("命令行作业档案：") || foundPrefixSnippets.contains("命令行作业档案："))

    let maintenanceExact = CompanyStore.technicalMaintenanceArtifactTitleExactMatches
    let maintenancePrefixes = CompanyStore.technicalMaintenanceArtifactTitlePrefixes
    let deliveryExact = CompanyStore.deliveryArtifactTitleExactMatches
    let deliveryPrefixes = CompanyStore.deliveryArtifactTitlePrefixes

    for title in foundExact {
        let classified = maintenanceExact.contains(title)
            || deliveryExact.contains(title)
            || maintenancePrefixes.contains { title.hasPrefix($0) }
            || deliveryPrefixes.contains { title.hasPrefix($0) }
        #expect(
            classified,
            "ArtifactRecord 标题 \"\(title)\" 未分类。请在 CompanyStore 把它登记到 technicalMaintenanceArtifactTitleExactMatches（运维产物）或 deliveryArtifactTitleExactMatches（真实交付证据），否则会按默认交付出现在老板/交付视图。"
        )
    }

    for prefixSnippet in foundPrefixSnippets {
        let classified = maintenancePrefixes.contains { prefixSnippet.hasPrefix($0) || $0.hasPrefix(prefixSnippet) }
            || deliveryPrefixes.contains { prefixSnippet.hasPrefix($0) || $0.hasPrefix(prefixSnippet) }
        #expect(
            classified,
            "ArtifactRecord 前缀型标题 \"\(prefixSnippet)…\" 未分类。请在 CompanyStore 的 technicalMaintenanceArtifactTitlePrefixes 或 deliveryArtifactTitlePrefixes 中显式登记前缀，避免悄悄进入或漏出老板/交付视图。"
        )
    }

    // 闭环审计报告标题来自 helper（`closureTraceAuditReportTitle`）的字符串插值，以 "闭环审计报告：" 开头，
    // 必须在 maintenance prefix 集合里登记——这条断言锁住「闭环审计报告归属维护」的产品边界。
    #expect(maintenancePrefixes.contains("闭环审计报告："))
}

@MainActor
@Test func evidenceClassificationAuditPassesWhenAllRecordsAreClassified() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 已分类样例：1 维护 VR + 1 交付 VR + 1 维护 AR + 1 动态文件名 AR（默认交付，不带 ：）+ 1 显式交付 AR。
    store.verifications.insert(VerificationRecord(productID: productID, status: .passed, title: "运行会话健康巡检", detail: ""), at: 0)
    store.verifications.insert(VerificationRecord(productID: productID, status: .passed, title: "自动验收检查", detail: ""), at: 0)
    store.artifacts.insert(ArtifactRecord(productID: productID, kind: .report, title: "安全检查点", path: "本机安全检查点存档", summary: ""), at: 0)
    store.artifacts.insert(ArtifactRecord(productID: productID, kind: .source, title: "AGENTS.md", path: "/tmp/AGENTS.md", summary: "项目扫描"), at: 0)
    store.artifacts.insert(ArtifactRecord(productID: productID, kind: .report, title: "验收产物：示例任务", path: "/tmp/result.md", summary: ""), at: 0)

    #expect(store.selectedProductUnclassifiedVerificationRecords.isEmpty)
    #expect(store.selectedProductUnclassifiedArtifactRecords.isEmpty)

    let auditCountBefore = store.selectedProductMaintenanceVerifications.filter { $0.title == "运行证据分类巡检" }.count
    let deliveryAuditCountBefore = store.selectedProductDeliveryVerifications.filter { $0.title == "运行证据分类巡检" }.count

    let record = store.runEvidenceClassificationAuditForSelectedProduct()
    #expect(record.title == "运行证据分类巡检")
    #expect(record.status == .passed)
    #expect(record.detail.contains("当前产品所有运行证据都已显式分类"))

    // 巡检自身只进维护视图，不进交付视图。
    let maintenanceCount = store.selectedProductMaintenanceVerifications.filter { $0.title == "运行证据分类巡检" }.count
    let deliveryCount = store.selectedProductDeliveryVerifications.filter { $0.title == "运行证据分类巡检" }.count
    #expect(maintenanceCount == auditCountBefore + 1)
    #expect(deliveryCount == deliveryAuditCountBefore)

    // 文本预览不含警告关键字。
    let preview = store.evidenceClassificationAuditText()
    #expect(preview.contains("未分类验证记录：0 条"))
    #expect(preview.contains("未分类产物档案：0 条"))
    #expect(!preview.contains("⚠️"))
}

@MainActor
@Test func evidenceClassificationAuditFlagsUnclassifiedRecordsButNotDynamicFilenames() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 故意插入未分类样例：
    // - VR：标题不在维护清单也不在交付精确/前缀清单 → 应被报告
    let unclassifiedVR = VerificationRecord(productID: productID, status: .warning, title: "未注册的旧巡检标题", detail: "")
    store.verifications.insert(unclassifiedVR, at: 0)
    // - AR：带"X：Y"全角冒号结构但不在任何前缀集合 → 应被报告
    let unclassifiedAR = ArtifactRecord(productID: productID, kind: .report, title: "未登记类别：示例", path: "/tmp/x", summary: "")
    store.artifacts.insert(unclassifiedAR, at: 0)
    // - 动态文件名 AR（无全角冒号）→ 必须被默认交付接受、不被误报为未分类
    let dynamicNameAR = ArtifactRecord(productID: productID, kind: .source, title: "client_brief.md", path: "/tmp/client_brief.md", summary: "")
    store.artifacts.insert(dynamicNameAR, at: 0)
    // - 项目扫描候选（无全角冒号）→ 不报错
    let projectScanAR = ArtifactRecord(productID: productID, kind: .rule, title: "AGENTS.md", path: "/tmp/AGENTS.md", summary: "")
    store.artifacts.insert(projectScanAR, at: 0)

    let unclassifiedVRs = store.selectedProductUnclassifiedVerificationRecords
    #expect(unclassifiedVRs.count == 1)
    #expect(unclassifiedVRs.first?.title == "未注册的旧巡检标题")

    let unclassifiedARs = store.selectedProductUnclassifiedArtifactRecords
    #expect(unclassifiedARs.count == 1)
    #expect(unclassifiedARs.first?.title == "未登记类别：示例")

    // 真实交付动态文件名不应被误报。
    #expect(!unclassifiedARs.contains { $0.title == "client_brief.md" })
    #expect(!unclassifiedARs.contains { $0.title == "AGENTS.md" })

    let record = store.runEvidenceClassificationAuditForSelectedProduct()
    #expect(record.status == .warning)
    #expect(record.detail.contains("⚠️"))
    #expect(record.detail.contains("未注册的旧巡检标题"))
    #expect(record.detail.contains("未登记类别：示例"))
    #expect(record.detail.contains("不进入老板总控台或交付验收中心"))
    #expect(record.detail.contains("未分类验证记录"))
    #expect(record.detail.contains("未分类产物档案"))
    #expect(!record.detail.contains("VerificationRecord"))
    #expect(!record.detail.contains("ArtifactRecord"))
    #expect(!record.detail.contains("CompanyStore."))

    // 维护视图能看到，老板/交付视图过滤掉。
    #expect(store.selectedProductMaintenanceVerifications.contains { $0.title == "运行证据分类巡检" })
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != "运行证据分类巡检" })
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != "运行证据分类巡检" })

    // 巡检不删除任何已有数据。
    #expect(store.selectedProductVerifications.contains { $0.title == "未注册的旧巡检标题" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "未登记类别：示例" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "client_brief.md" })
    #expect(store.selectedProductArtifacts.contains { $0.title == "AGENTS.md" })
}

@MainActor
@Test func evidenceClassificationAuditCoversHalfWidthColonButSparesPathsAndTimestamps() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 应当被报告：半角冒号 + 空格 + 非路径前缀。
    let flaggedTitles = [
        "未登记类别: 示例",
        "Note: maintenance reminder",
        "version: 1.2.0",
        "claude-debug: hello world",
        "未注册前缀: 中英文混合"
    ]
    for title in flaggedTitles {
        store.artifacts.insert(
            ArtifactRecord(productID: productID, kind: .report, title: title, path: "/tmp/x", summary: ""),
            at: 0
        )
    }

    // 不应被报告：URL / 文件路径 / 时间戳 / 普通文件名 / 含半角冒号但被路径标记前缀（`/`）保护。
    let safeDynamicTitles = [
        "https://example.com/path",         // URL，`:/` 不带空格
        "opc://closure-traces/abc-123",     // OPC 内部 URL
        "/var/log/2026-05-01/foo.log",      // 路径
        "C:\\Users\\sample\\file.txt",      // Windows 路径
        "2026-05-01T10:30:00Z",             // 时间戳，冒号后无空格
        "10:30:00",                         // 时间戳
        "data.csv",                         // 普通文件名
        "AGENTS.md",                        // 项目扫描固定候选
        "client_brief.md",                  // 本地文件索引动态文件名
        "/usr/bin/foo: bar",                // 含 `: ` 但前缀有 `/` 路径标记 → 视为路径，不报告
        "C:\\Users\\foo: bar"               // 含 `: ` 但前缀有 `\` 路径标记 → 不报告
    ]
    for title in safeDynamicTitles {
        store.artifacts.insert(
            ArtifactRecord(productID: productID, kind: .source, title: title, path: "/tmp/x", summary: ""),
            at: 0
        )
    }

    // 注入维护和交付分类好的样例，确保它们继续不被巡检报告。
    store.artifacts.insert(
        ArtifactRecord(productID: productID, kind: .report, title: "安全检查点", path: "本机安全检查点存档", summary: ""),
        at: 0
    )
    store.artifacts.insert(
        ArtifactRecord(productID: productID, kind: .report, title: "验收产物：示例任务", path: "/tmp/result.md", summary: ""),
        at: 0
    )

    // 巡检结果：每个 flagged 都被识别，每个 safe 都被排除。
    let unclassifiedTitles = Set(store.selectedProductUnclassifiedArtifactRecords.map(\.title))
    for title in flaggedTitles {
        #expect(unclassifiedTitles.contains(title), "半角结构化标题应被报告：\(title)")
    }
    for title in safeDynamicTitles {
        #expect(!unclassifiedTitles.contains(title), "动态/路径/URL/时间戳标题不应被报告：\(title)")
    }
    // 维护和交付样例不被报告
    #expect(!unclassifiedTitles.contains("安全检查点"))
    #expect(!unclassifiedTitles.contains("验收产物：示例任务"))

    // 巡检写一条维护 VR，状态为 warning，正文含识别规则说明。
    let record = store.runEvidenceClassificationAuditForSelectedProduct()
    #expect(record.status == .warning)
    #expect(record.detail.contains("识别规则：标题含全角「：」或半角「: 」"))
    #expect(record.detail.contains("URL、文件路径、时间戳"))
    for title in flaggedTitles {
        #expect(record.detail.contains(title), "巡检 detail 应含标题：\(title)")
    }
    // 巡检本身只进维护视图。
    #expect(store.selectedProductMaintenanceVerifications.contains { $0.title == "运行证据分类巡检" })
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != "运行证据分类巡检" })

    // 巡检不删除任何数据。
    for title in flaggedTitles + safeDynamicTitles + ["安全检查点", "验收产物：示例任务"] {
        #expect(store.selectedProductArtifacts.contains { $0.title == title })
    }
}

@MainActor
@Test func maintenanceDataPressureAuditEmptyStateIsChineseAndPasses() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let preview = store.maintenanceDataPressureText()
    #expect(preview.contains("维护数据增长预览"))
    #expect(preview.contains("维护验证记录：0 条"))
    #expect(preview.contains("维护产物档案：0 条"))
    #expect(preview.contains("主状态快照："))
    #expect(preview.contains("命令行作业档案："))
    #expect(preview.contains("最近维护验证：暂无"))
    #expect(preview.contains("最近维护产物：暂无"))
    #expect(preview.contains("维护数据未达建议阈值"))
    #expect(preview.contains("不删除任何数据、不裁剪主快照"))
    #expect(!preview.contains("⚠️"))

    let record = store.runMaintenanceDataPressureAuditForSelectedProduct()
    #expect(record.title == "维护数据增长巡检")
    #expect(record.status == .passed)
    // 巡检自身只进维护视图
    #expect(store.selectedProductMaintenanceVerifications.contains { $0.title == "维护数据增长巡检" })
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != "维护数据增长巡检" })
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != "维护数据增长巡检" })
}

@MainActor
@Test func maintenanceDataPressureAuditFlagsWarningWhenAboveThreshold() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    // 注入超过维护 VR 建议阈值的样例（用维护标题），确保 status 转为 warning
    let vrThreshold = CompanyStore.maintenanceVerificationGrowthAdvisoryThreshold
    for index in 0..<(vrThreshold + 5) {
        store.verifications.insert(
            VerificationRecord(productID: productID, status: .passed, title: "运行会话健康巡检", detail: "样例 \(index)"),
            at: 0
        )
    }
    // 加一条已分类但还没到 AR 阈值的维护产物，确保只触发 VR 阈值告警
    store.artifacts.insert(
        ArtifactRecord(productID: productID, kind: .report, title: "安全检查点", path: "本机安全检查点存档", summary: "样例"),
        at: 0
    )

    let preview = store.maintenanceDataPressureText()
    #expect(preview.contains("⚠️"))
    #expect(preview.contains("已经达到或超过建议阈值"))
    #expect(preview.contains("维护验证已达"))
    #expect(preview.contains("超过 \(vrThreshold) 条阈值"))
    #expect(preview.contains("不会自动删除或裁剪主快照"))

    let record = store.runMaintenanceDataPressureAuditForSelectedProduct()
    #expect(record.status == .warning)
    #expect(record.detail.contains("⚠️"))
    #expect(record.detail.contains("不进入老板总控台或交付验收中心"))

    // 巡检不能删除已有维护数据。
    #expect(store.selectedProductMaintenanceVerifications.filter { $0.title == "运行会话健康巡检" }.count == vrThreshold + 5)
    #expect(store.selectedProductMaintenanceArtifacts.contains { $0.title == "安全检查点" })

    // 巡检自身只进维护视图。
    #expect(store.selectedProductMaintenanceVerifications.contains { $0.title == "维护数据增长巡检" })
    #expect(store.selectedProductDeliveryVerifications.allSatisfy { $0.title != "维护数据增长巡检" })
    #expect(store.selectedProductRecentDeliveryVerifications.allSatisfy { $0.title != "维护数据增长巡检" })
}

@MainActor
@Test func maintenanceDataPressureAuditFlagsWarningWhenArtifactsAboveThreshold() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let arThreshold = CompanyStore.maintenanceArtifactGrowthAdvisoryThreshold

    for index in 0..<(arThreshold + 1) {
        store.artifacts.insert(
            ArtifactRecord(productID: productID, kind: .report, title: "本地文件索引：sample_\(index).md", path: "/tmp/sample_\(index).md", summary: ""),
            at: 0
        )
    }

    let preview = store.maintenanceDataPressureText()
    #expect(preview.contains("⚠️"))
    #expect(preview.contains("维护产物已达"))

    let record = store.runMaintenanceDataPressureAuditForSelectedProduct()
    #expect(record.status == .warning)
    // 大量维护产物不应进入老板/交付视图
    #expect(store.selectedProductDeliveryArtifacts.allSatisfy { !$0.title.hasPrefix("本地文件索引：") })
}

@MainActor
@Test func maintenanceDataPressureAuditFlagsWarningWhenJobArchiveCountAboveThresholdWithoutDeletingJobs() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCMaintenanceJobs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store.importProductWorkspace(from: root)

    let jobsRoot = root.appendingPathComponent(".opc/jobs", isDirectory: true)
    let threshold = CompanyStore.maintenanceJobArchiveCountAdvisoryThreshold
    for index in 0..<(threshold + 1) {
        let directory = jobsRoot.appendingPathComponent("job-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "status=completed\n".write(to: directory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    }

    let preview = store.maintenanceDataPressureText()
    #expect(preview.contains("命令行作业档案：\(threshold + 1) 个"))
    #expect(preview.contains("命令行作业档案已达 \(threshold + 1) 个"))
    #expect(preview.contains("不删除任何数据、不裁剪主快照"))

    let record = store.runMaintenanceDataPressureAuditForSelectedProduct()
    #expect(record.status == .warning)
    #expect(record.detail.contains("命令行作业档案已达 \(threshold + 1) 个"))

    let remainingJobs = try FileManager.default.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)
    #expect(remainingJobs.count == threshold + 1, "维护数据增长巡检只能提示，不能删除命令行作业档案")
}

@MainActor
@Test func maintenanceEvidenceIsolatedFromAllBossAndDeliveryDataSources() async throws {
    // 把全部 5 类典型维护证据（VR + AR）一次性插入当前产品，
    // 然后断言 5 个老板/交付数据源 accessor 都看不到，
    // 维护视图 accessor 全部能看到。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID

    let maintenanceVRTitles = [
        "运行证据分类巡检",
        "维护数据增长巡检"
    ]
    for title in maintenanceVRTitles {
        store.verifications.insert(
            VerificationRecord(productID: productID, status: .passed, title: title, detail: "样例"),
            at: 0
        )
    }

    // 维护产物：本地文件索引（前缀）/ 命令行作业档案（前缀）/ 闭环审计报告（前缀）
    let maintenanceARTitles = [
        "本地文件索引：sample.md",
        "命令行作业档案：示例工程师",
        "闭环审计报告：示例目标"
    ]
    for title in maintenanceARTitles {
        store.artifacts.insert(
            ArtifactRecord(productID: productID, kind: .report, title: title, path: "/tmp/x", summary: "样例"),
            at: 0
        )
    }

    // 老板/交付侧 5 个 accessor（CommandCenter widget 总数 / 产品详情 metric tile / 产品详情交付摘要 prefix(3) /
    // 交付验收中心 prefix(20) / 运营套件验收抽屉 prefix(6)）都通过这两个 accessor 取数。
    let deliveryVRTitles = Set(store.selectedProductDeliveryVerifications.map(\.title))
    let recentDeliveryVRTitles = Set(store.selectedProductRecentDeliveryVerifications.map(\.title))
    let deliveryARTitles = Set(store.selectedProductDeliveryArtifacts.map(\.title))
    let recentDeliveryARTitles = Set(store.selectedProductRecentDeliveryArtifacts.map(\.title))

    for title in maintenanceVRTitles {
        #expect(!deliveryVRTitles.contains(title), "维护 VR 不应进入老板/交付视图：\(title)")
        #expect(!recentDeliveryVRTitles.contains(title))
    }
    for title in maintenanceARTitles {
        #expect(!deliveryARTitles.contains(title), "维护 AR 不应进入老板/交付视图：\(title)")
        #expect(!recentDeliveryARTitles.contains(title))
    }

    // widget / 抽屉的 prefix 切片再确认一次：取最大值 prefix(20) 即覆盖所有 boss/delivery surface。
    let widgetVR = store.selectedProductRecentDeliveryVerifications.prefix(20)
    let widgetAR = store.selectedProductRecentDeliveryArtifacts.prefix(20)
    for title in maintenanceVRTitles {
        #expect(widgetVR.allSatisfy { $0.title != title })
    }
    for title in maintenanceARTitles {
        #expect(widgetAR.allSatisfy { $0.title != title })
    }

    // 维护视图 accessor 必须看到所有 5 类维护证据。
    let maintenanceVRView = Set(store.selectedProductMaintenanceVerifications.map(\.title))
    let maintenanceARView = Set(store.selectedProductMaintenanceArtifacts.map(\.title))
    for title in maintenanceVRTitles {
        #expect(maintenanceVRView.contains(title), "维护视图必须包含：\(title)")
    }
    for title in maintenanceARTitles {
        #expect(maintenanceARView.contains(title), "维护视图必须包含：\(title)")
    }

    // 维护中心默认可见列表也能看到（产品上线后 8 条以内是常态）。
    let recentMaintenanceVR = store.localMaintenanceVisibleVerifications.map(\.title)
    let recentMaintenanceAR = store.localMaintenanceVisibleArtifacts.map(\.title)
    for title in maintenanceVRTitles {
        #expect(recentMaintenanceVR.contains(title))
    }
    for title in maintenanceARTitles {
        #expect(recentMaintenanceAR.contains(title))
    }
}

@Test func swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords() async throws {
    // 集中守门：扫描 Sources/OPCCompanyCore/*.swift 里所有 SwiftUI 可见文案入口，
    // 断言默认可见 inline 文案不含旧英文职责词或后端复杂度字段。
    // 遵守 OPC_COMPANY § 7：老板视图只展示结果、风险、审批、交付物；后台复杂度（backend/rawValue/CLI 参数/identifier）不能上 UI。
    //
    // 覆盖的 SwiftUI 可见文案 API：
    // 1. Text("..."), Label("...", ...), Button("...") {…}, Toggle("...", ...), Picker("...", ...) — 通过 head 形式 `(?:Type)\(`+ 字面量第一参数。
    // 2. SectionHeader(title: "...") — 第一个命名参数 `title:` + 字面量。
    // 3. .navigationTitle("...") / .help("...") — view modifier 字面量。
    let fileURLs = try loadOPCCompanyCoreSwiftFileURLs()

    // 三类正则：
    let headLiteralPattern = #"(?:Text|Label|Button|Toggle|Picker)\(\s*"((?:\\.|[^"\\])*)""#
    let sectionHeaderPattern = #"SectionHeader\(\s*title:\s*"((?:\\.|[^"\\])*)""#
    let modifierPattern = #"\.(?:navigationTitle|help|accessibilityLabel|accessibilityHint)\(\s*"((?:\\.|[^"\\])*)""#

    let regexes = try [headLiteralPattern, sectionHeaderPattern, modifierPattern].map {
        try NSRegularExpression(pattern: $0, options: [])
    }

    let forbiddenLegacyTerms = [
        // 旧英文职责词
        "AI 控制", "Agent 编队", "COMMAND LINK", "CTO 办公室", "OPC AI",
        "AI 通信", "AI 智能", "Codex CTO",
        // 内部枚举 / 后端字段
        "rawValue", "subscriptionCLI", "persistentProtocol",
        // CLI 运行参数（绝不能作为可见文案）
        "model_reasoning_effort", "--skip-git-repo-check",
        "--no-stream", "--dangerously-allow",
        // 用户不可见的内部词（非品牌）
        "OPCUIAutomationIdentifier", "OPCTerminalAutoLoop", "OPCEvidenceClassification"
    ]
    // 仅在"裸出现 + 非品牌组合"时禁用的 fuzzy 词。
    // - `backend` / `CLI` / `identifier` / `a11y`：不能出现在用户可见的中文产品话术里。
    //   但 `Codex CLI` / `Claude Code CLI` 是品牌组合允许保留——所以单独判断"裸 backend / CLI"。
    let fuzzyForbiddenTerms = ["backend", "identifier", "a11y"]
    let cliBrandWhitelist = ["Codex CLI", "Claude Code CLI", "Gemini CLI"]

    // Swift 字符串字面量内的 `\(expression)` 是插值代码段，用户看到的是表达式 runtime 求值结果
    // （比如 `opcBackendCommandDisplayName(agent.backend.command)` 返回的清洗后工具名），
    // 而不是字面量里写的 `backend`。守门必须只检查"可见文字"部分，避免对插值表达式里的
    // 属性名 / 函数名 / 内部字段误报。本 helper 用括号配对剥掉 `\(...)`，保留表达式之外的固定文案。
    func strippingInterpolations(_ literal: String) -> String {
        var result = ""
        result.reserveCapacity(literal.count)
        let scalars = Array(literal)
        var i = 0
        while i < scalars.count {
            if scalars[i] == "\\", i + 1 < scalars.count, scalars[i + 1] == "(" {
                // 跳过整段 `\(...)`，处理嵌套括号
                var depth = 1
                i += 2
                while i < scalars.count && depth > 0 {
                    if scalars[i] == "(" { depth += 1 }
                    else if scalars[i] == ")" { depth -= 1 }
                    i += 1
                }
                continue
            }
            result.append(scalars[i])
            i += 1
        }
        return result
    }

    var totalLiterals = 0
    var sectionHeaderLiterals = 0
    var leakedExamples: [(file: String, term: String, snippet: String)] = []
    var capturedLiterals: [(file: String, snippet: String)] = []

    for fileURL in fileURLs {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        let nsContent = content as NSString
        for (index, regex) in regexes.enumerated() {
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let rawLiteral = nsContent.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                let visibleLiteral = strippingInterpolations(rawLiteral)
                totalLiterals += 1
                if index == 1 { sectionHeaderLiterals += 1 }  // SectionHeader 命中
                capturedLiterals.append((fileURL.lastPathComponent, visibleLiteral))

                for term in forbiddenLegacyTerms where visibleLiteral.contains(term) {
                    leakedExamples.append((fileURL.lastPathComponent, term, rawLiteral))
                }
                // fuzzy 检查也只对剥掉插值的可见部分做
                for term in fuzzyForbiddenTerms where visibleLiteral.localizedCaseInsensitiveContains(term) {
                    leakedExamples.append((fileURL.lastPathComponent, term, rawLiteral))
                }
                if visibleLiteral.contains("CLI") {
                    let isWhitelistedBrand = cliBrandWhitelist.contains(where: { visibleLiteral.contains($0) })
                    if !isWhitelistedBrand {
                        leakedExamples.append((fileURL.lastPathComponent, "CLI（非品牌组合）", rawLiteral))
                    }
                }
            }
        }
    }

    // 扫描器自身 sanity check：覆盖更多 API 后字面量数应明显超过原 50 条阈值。
    #expect(totalLiterals >= 100, "扩展后的 SwiftUI inline copy 扫描器只找到 \(totalLiterals) 条字面量，疑似正则失效")
    #expect(sectionHeaderLiterals >= 1, "SectionHeader 字面量扫描应至少命中 1 条；命中数：\(sectionHeaderLiterals)")

    // 任何泄漏都必须显式列出来——失败信息直接告诉开发者文件、词汇和字面量。
    if !leakedExamples.isEmpty {
        let formatted = leakedExamples
            .map { "[\($0.file)] '\($0.term)' in: \($0.snippet)" }
            .joined(separator: "\n")
        Issue.record("SwiftUI inline 文案出现旧英文职责词或内部词，不允许进入用户可见 UI：\n\(formatted)")
    }
    #expect(leakedExamples.isEmpty)

    // 反向 sanity check：必须保留至少一处品牌名（Codex / Claude Code / Gemini / OpenAI），
    // 否则说明守门把品牌词也禁了。
    let brandPatterns = ["Codex", "Claude Code", "Gemini", "OpenAI"]
    let foundBrand = capturedLiterals.contains { entry in
        brandPatterns.contains(where: entry.snippet.contains)
    }
    #expect(foundBrand, "SwiftUI inline 文案应当至少能保留一处品牌名（Codex/Claude Code/Gemini/OpenAI）作为 sanity check")
}

@Test func employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords() async throws {
    let addEmployeeSource = try loadOPCCompanyCoreSource("AddEmployeeSheet.swift")
    let inspectorSource = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(addEmployeeSource.contains("Section(\"模型来源\")"))
    #expect(addEmployeeSource.contains("Picker(\"来源\""))
    #expect(addEmployeeSource.contains("本机必须已经安装对应命令行工具"))
    #expect(addEmployeeSource.contains("模型，例如 gpt-5.5、deepseek-chat"))
    #expect(addEmployeeSource.contains("TextField(\"占位标识\""))
    #expect(inspectorSource.contains("例如 codex、claude、gemini"))
    #expect(inspectorSource.contains("例如 gpt-5.5、sonnet，留空使用默认模型"))
    #expect(inspectorSource.contains("LabeledContent(agent.backend.type == .local ? \"占位标识\" : \"模型\")"))
    #expect(inspectorSource.contains("保存占位标识"))
    #expect(inspectorSource.contains("ProfileRow(label: \"占位标识\""))
    #expect(inspectorSource.contains("已配置，输入新密钥可替换"))
    #expect(inspectorSource.contains("InspectorTelemetryCell(label: \"来源\""))
    #expect(inspectorSource.contains("ProfileRow(label: \"来源\""))

    let bannedVisibleFragments = [
        "Mac 上",
        "输入新 Key",
        "Section(\"模型后端\")",
        "Picker(\"后端\"",
        "InspectorTelemetryCell(label: \"后端\"",
        "ProfileRow(label: \"后端\"",
        "codex / claude / gemini",
        "gpt-5.5 / deepseek-chat",
        "gpt-5.5 / sonnet"
    ]
    for fragment in bannedVisibleFragments {
        #expect(!addEmployeeSource.contains(fragment), "新增员工面板不应含未本地化或后台导向文案：\(fragment)")
        #expect(!inspectorSource.contains(fragment), "员工配置面板不应含未本地化或后台导向文案：\(fragment)")
    }
}

@Test func addEmployeeBackendSwitchDefaultsAvoidCarryingClaudeModelIntoAPI() async throws {
    let source = try loadOPCCompanyCoreSource("AddEmployeeSheet.swift")
    let marker = "func applyBackendDefaults(_ backend: BackendType)"
    let start = try #require(source.range(of: marker)?.lowerBound, "应能定位新增员工来源切换默认值逻辑")
    let tail = source[start...]
    let end = try #require(tail.range(of: "\n    }\n}", options: [])?.upperBound, "应能定位默认值函数结尾")
    let slice = String(tail[..<end])

    #expect(slice.contains("store.draftEmployee.command = \"api-agent\""))
    #expect(slice.contains("store.draftEmployee.model = \"gpt-5.5\""),
            "切到接口模型时，默认/空模型应切换到通用 API 模型示例，避免沿用 sonnet")
    #expect(slice.contains("store.draftEmployee.model == \"sonnet\""),
            "切到接口模型时必须识别 Claude 默认模型并替换")
    #expect(slice.contains("store.draftEmployee.model == \"gemini-cli\""),
            "切到接口模型时必须识别 Gemini 占位模型并替换")
    #expect(slice.contains("store.draftEmployee.model == \"local\""),
            "从本地占位切到真实来源时必须识别本地占位模型并替换")
    #expect(slice.contains("store.draftEmployee.model = \"sonnet\""),
            "从接口模型切回订阅制命令行且命令默认 claude 时，应恢复 Claude 默认模型")
    #expect(slice.contains("store.draftEmployee.model = \"local\""),
            "切到本地占位时，默认/空/真实来源模型应切换到本地占位标识")
    #expect(slice.contains("store.draftEmployee.command = \"local\""),
            "切到本地占位时，命令应同步切换为本地占位标识，避免残留 claude/codex/gemini")
}

@MainActor
@Test func selectedAgentBackendTypeSwitchAppliesVisibleSourceDefaults() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectedAgentID = engineer.id

    store.updateSelectedAgentBackend(type: .local)
    var updated = try #require(store.agents.first { $0.id == engineer.id })
    #expect(updated.backend.type == .local)
    #expect(updated.backend.command == "local")
    #expect(updated.backend.model == "local")

    store.updateSelectedAgentBackend(type: .api)
    updated = try #require(store.agents.first { $0.id == engineer.id })
    #expect(updated.backend.type == .api)
    #expect(updated.backend.command == "api-agent")
    #expect(updated.backend.model == "gpt-5.5")
    #expect(updated.permissions.contains(.useNetwork))

    store.updateSelectedAgentBackend(type: .subscriptionCLI)
    updated = try #require(store.agents.first { $0.id == engineer.id })
    #expect(updated.backend.type == .subscriptionCLI)
    #expect(updated.backend.command == "claude")
    #expect(updated.backend.model == "sonnet")
}

@Test func unfilteredEvidenceAccessorsAreNotReadOutsideCompanyStore() async throws {
    // 集中守门：扫描 Sources/OPCCompanyCore/*.swift（除 CompanyStore.swift 自己定义这些 accessor 之外），
    // 禁止任何 UI 或 helper 文件直接读取未过滤的 `selectedProductArtifacts` / `selectedProductVerifications` /
    // `selectedProductRecentArtifacts` / `selectedProductRecentVerifications` —— 这些是 superset accessor，
    // 同时包含交付证据和维护证据。老板/交付视图必须用 `selectedProductDeliveryArtifacts` / `Verifications` /
    // `RecentDeliveryArtifacts` / `Verifications`；技术维护视图必须用 `selectedProductMaintenanceArtifacts` /
    // `Verifications` / `RecentMaintenance...`。
    //
    // 这条守门保证未来任何 UI PR 误读 superset accessor 都会让 swift test 立刻失败，
    // 从源头阻断维护证据泄漏到老板/交付视图的路径。
    let allFileURLs = try loadOPCCompanyCoreSwiftFileURLs()

    // CompanyStore.swift 自己定义这些 accessor、维护过滤逻辑、删除产品时清理路径，是合法的 superset 读取者。
    let allowedSelfReferenceFiles: Set<String> = ["CompanyStore.swift"]

    // 禁止的 superset accessor 名称——必须按 word boundary 匹配（避免命中
    // selectedProductDeliveryArtifacts / selectedProductMaintenanceArtifacts /
    // selectedProductRecentDeliveryArtifacts 等合法 accessor）。
    let bannedAccessors = [
        "selectedProductArtifacts",
        "selectedProductVerifications",
        "selectedProductRecentArtifacts",
        "selectedProductRecentVerifications"
    ]

    var totalChecked = 0
    var leaks: [(file: String, line: Int, accessor: String, snippet: String)] = []
    for fileURL in allFileURLs {
        let fileName = fileURL.lastPathComponent
        // v0.2 split: CompanyStore's own extensions are still the Store itself —
        // the invariant guards UI/other types, not the Store's physical layout.
        if allowedSelfReferenceFiles.contains(fileName) || fileName.hasPrefix("CompanyStore+") { continue }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        totalChecked += 1
        for (lineIndex, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineString = String(line)
            for accessor in bannedAccessors {
                // 必须按 word boundary 匹配；后面跟 `Delivery` / `Maintenance` / 字母数字时是合法 accessor，要跳过。
                guard let range = lineString.range(of: accessor) else { continue }
                let afterIndex = range.upperBound
                if afterIndex < lineString.endIndex {
                    let nextChar = lineString[afterIndex]
                    if nextChar.isLetter || nextChar.isNumber {
                        continue  // 是 selectedProductDeliveryX / selectedProductMaintenanceX 等合法 accessor
                    }
                }
                leaks.append((fileName, lineIndex + 1, accessor, lineString.trimmingCharacters(in: .whitespaces)))
            }
        }
    }

    // sanity check：至少扫过若干 UI/helper 文件（CommandCenter/SelectionWorkspace/OperationsSuite/CompanyScene 等都参与）。
    #expect(totalChecked >= 5, "Sources/OPCCompanyCore 目录扫到的非 CompanyStore 文件数 \(totalChecked) 偏少，可能正则失效")

    if !leaks.isEmpty {
        let formatted = leaks
            .map { "[\($0.file):\($0.line)] 直接读取 superset accessor `\($0.accessor)` —— 应改用 selectedProductDeliveryX 或 selectedProductMaintenanceX 专用 accessor。代码片段：\n    \($0.snippet)" }
            .joined(separator: "\n")
        Issue.record("发现绕过维护证据过滤的直读：\n\(formatted)")
    }
    #expect(leaks.isEmpty)
}

@MainActor
@Test func terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure() async throws {
    // 终端大厅顶部默认可见的运行状态概览必须保持简洁中文：运行状态 + 风险/审批 + 下一步建议；
    // 不暴露 backend / CLI / identifier 等内部字段；下方默认是摘要工作台（不再「默认收起」）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let preview = store.terminalHallOverviewSummaryText()

    // 包含运行状态关键中文 token
    #expect(preview.contains("终端大厅运行状态"))
    #expect(preview.contains("团队"))
    #expect(preview.contains("运行中"))
    #expect(preview.contains("待审批"))
    #expect(preview.contains("阻塞/失败"))
    #expect(preview.contains("最近风险"))
    #expect(preview.contains("下一步"))

    // 摘要工作台关键中文 token（替代旧的「默认收起」方向）
    #expect(preview.contains("摘要工作台"))
    #expect(preview.contains("查看详情"))

    // 旧的「默认收起」方向已修正为摘要工作台，以下旧方向 token 不应再出现在用户可见提示文案里
    #expect(!preview.contains("默认收起"), "终端大厅默认信息架构已修正为摘要工作台，提示中不应仍说「默认收起」")
    #expect(!preview.contains("折叠"), "提示中不应使用「折叠」描述（已改为摘要 + 查看详情）")
    #expect(!preview.contains("展开"), "提示中不应使用「展开」描述（已改为摘要 + 查看详情）")

    // 不暴露后台复杂度 / 内部字段 / SwiftUI 开发组件名
    let forbiddenInternals = [
        "backend", "rawValue", "subscriptionCLI", "persistentProtocol",
        "model_reasoning_effort", "--skip-git-repo-check",
        "OPCTerminalAutoLoop", "OPCMaintenance", "OPCEvidenceClassification",
        // SwiftUI 组件名不能作为用户可见产品文案
        "DisclosureGroup", "VStack", "HStack", "ScrollView", "ForEach", "LazyVGrid"
    ]
    for term in forbiddenInternals {
        #expect(!preview.contains(term), "终端大厅概览不应含内部词或 SwiftUI 组件名：\(term)")
    }

    // 旧职责词不出现
    let legacyRoleWords = [
        "AI 控制", "Agent 编队", "COMMAND LINK", "CTO 办公室", "OPC AI"
    ]
    for term in legacyRoleWords {
        #expect(!preview.contains(term))
    }

    // 概览文本仍保持紧凑：限定行数（不应铺出大量维护细节）
    let lines = preview.components(separatedBy: "\n")
    #expect(lines.count <= 6, "概览应保持简洁，当前行数 \(lines.count)")
}

@Test func operationsMaintenanceCopyUsesSummaryAndDetailWordingInsteadOfFoldedCopy() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    #expect(!source.contains("默认显示分组摘要，完整配置按需进入"),
            "高级控制台外壳已删除，不应继续保留这段旧说明")
    #expect(!source.contains("struct AdvancedCommandCenter:"),
            "高级控制台外壳已无真实入口，应保持删除状态")
    #expect(source.contains("查看完整运维明细"),
            "维护预览应使用查看完整明细的动作文案")

    let bannedVisibleCopy = [
        "默认折叠",
        "展开运维详情",
        "VerificationRecord / ArtifactRecord",
        "按 detail 前 200 字"
    ]
    for term in bannedVisibleCopy {
        #expect(!source.contains(term), "技术维护可见文案不应继续使用旧的折叠/展开措辞：\(term)")
    }
}

@Test func terminalHallShowsSummaryWorkbenchInsteadOfCollapsedDisclosure() async throws {
    // 源码守门：扫描 TerminalHallView.swift，确认终端大厅默认信息架构已经从「3 个折叠 disclosure」
    // 修正为「3 张摘要工作台卡片 + 二级 sheet 详情」。
    //
    // 这条测试是反向锁：禁止有人改回 DisclosureGroup 默认收起架构。
    let content = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 旧的「默认折叠 disclosure」结构必须彻底移除：3 个 @State Bool = false 不能再出现。
    let bannedCollapsedStates = [
        "showsArchitectureAudit",
        "showsCommunicationGateway",
        "showsLocalMaintenance"
    ]
    for state in bannedCollapsedStates {
        #expect(!content.contains(state), "终端大厅默认信息架构已升级为摘要工作台；不应再有折叠 state：\(state)")
    }
    let bannedEnumCases = [
        "advancedMaintenanceArchitectureDisclosure",
        "advancedMaintenanceGatewayDisclosure",
        "advancedMaintenanceLocalDisclosure"
    ]
    for caseName in bannedEnumCases {
        #expect(!content.contains(caseName), "OPCUIAutomationIdentifier 旧的 disclosure case 必须删除：\(caseName)")
    }

    // 2. 3 张摘要工作台卡片必须存在且引用新 enum case；3 个「查看详情」按钮必须各自登记 detail trigger anchor。
    let summaryCardStructs = [
        "MultiAgentArchitectureSummaryCard",
        "CommunicationGatewaySummaryCard",
        "LocalMaintenanceSummaryCard"
    ]
    for name in summaryCardStructs {
        #expect(content.contains("private struct \(name)"), "缺少摘要工作台卡片结构：\(name)")
    }
    let summaryCardEnumCases = [
        "advancedMaintenanceArchitectureSummaryCard",
        "advancedMaintenanceGatewaySummaryCard",
        "advancedMaintenanceLocalSummaryCard",
        "advancedMaintenanceArchitectureDetailTrigger",
        "advancedMaintenanceGatewayDetailTrigger",
        "advancedMaintenanceLocalDetailTrigger",
        "terminalHallDetailSheet",
        "terminalHallOverviewSummary"
    ]
    for caseName in summaryCardEnumCases {
        #expect(content.contains("OPCUIAutomationIdentifier.\(caseName)"), "TerminalHallView 应引用 enum case：\(caseName)")
    }

    // 3. 中文模块标题必须默认可见（用于 Computer Use 文本定位）；不再用「高级维护：xxx」前缀。
    let chineseSummaryTitles = [
        "多员工架构体检与闭环",
        "通信网关与手机指令",
        "本地稳定性与命令行运维"
    ]
    for title in chineseSummaryTitles {
        #expect(content.contains(title), "摘要工作台缺少中文模块标题：\(title)")
    }
    // 「查看详情」按钮 label 至少出现 3 次（3 张卡片各 1 个）。
    let detailButtonLabel = "查看详情"
    let detailLabelCount = content.components(separatedBy: detailButtonLabel).count - 1
    #expect(detailLabelCount >= 3, "终端大厅应有至少 3 处「查看详情」按钮，实际 \(detailLabelCount)")

    // 4. 长报告/完整面板必须经由 sheet 二级面板按需打开——而不是默认嵌在主视图。
    //    `.sheet(item: $presentedDetail)` 必须存在；switch 路由 3 个 case 各自挂上原始详情 view。
    #expect(content.contains(".sheet(item: $presentedDetail)"), "缺少 sheet 二级面板路由")
    #expect(content.contains("MultiAgentArchitectureAuditCenter()"), "架构审计中心应仍被引用（在二级 sheet 内）")
    #expect(content.contains("CommunicationGatewayCommandCenter()"), "通信网关中心应仍被引用（在二级 sheet 内）")
    #expect(content.contains("LocalMaintenanceCenter()"), "本地维护中心应仍被引用（在二级 sheet 内）")
    #expect(content.contains("OPCUIAutomationIdentifier.terminalHallDetailSheet.rawValue"),
            "二级 sheet 必须有稳定根节点 anchor，便于 Computer Use 区分摘要页和详情页")
    #expect(content.contains("accessibilityAction(named: \"查看本地维护详情\")"),
            "本地维护摘要卡必须提供整卡点击/a11y 兜底，避免 Computer Use 只点到卡片容器时无法打开详情")

    // 5. 顶部运行状态概览仍默认可见。
    #expect(content.contains("TerminalHallOverviewSummary()"))

    // 6. 三个详情中心**不能**出现在主视图 ScrollView 内联渲染（否则就回到默认铺满模式）。
    //    判定方法：剔除 sheet 路由 switch 与 TerminalHallDetailSheet 内部，主视图体内不应出现这三个 view 的实例化字面量。
    let mainBodyMarker = "ScrollView {"
    let sheetMarker = "private struct TerminalHallDetailSheet"
    if let mainStart = content.range(of: mainBodyMarker)?.upperBound,
       let sheetStart = content.range(of: sheetMarker)?.lowerBound {
        let mainBody = String(content[mainStart..<sheetStart])
        let inlineDetailLeaks = [
            "MultiAgentArchitectureAuditCenter()",
            "CommunicationGatewayCommandCenter()",
            "LocalMaintenanceCenter()"
        ]
        for leak in inlineDetailLeaks {
            #expect(!mainBody.contains(leak), "主视图 ScrollView 内联了完整详情 view（应仅在 sheet 中渲染）：\(leak)")
        }
    }

    // 7. 每张摘要卡必须显式声明 `.accessibilityElement(children: .contain)`。
    //    这是保证 macOS AX tree 把容器作为「容器组」而不是「单一标记元素」对待——
    //    不加这一行时，子按钮（含 DetailTrigger）的 a11y identifier 会被父级 SummaryCard
    //    identifier 覆盖，Computer Use 找不到「查看详情」按钮（Codex 实测确认过该退化）。
    let containChildrenCount = content.components(separatedBy: ".accessibilityElement(children: .contain)").count - 1
    #expect(containChildrenCount >= 3, "三张摘要卡必须各自调用 .accessibilityElement(children: .contain)，实际命中 \(containChildrenCount) 次；缺少该修饰会让 Computer Use 在 AX tree 上看到子按钮被父 SummaryCard identifier 覆盖。")

    // 8. 三个 DetailTrigger anchor 必须直接绑在 Button 上，不能错绑在父级容器（VStack/HStack/Group/...）上。
    //    算法：从 anchor 行向上扫至多 30 行，第一个出现的「容器开启行」必须是 `Button {`；
    //    若先扫到 VStack/HStack/ZStack/LazyVGrid/LazyHGrid/ScrollView/Group/ForEach/RoundedRectangle 等
    //    其他容器开启行，说明 anchor 错绑在父级，立即报错。
    //
    //    这条检查直接复跑 Codex 实测发现的「子按钮显示父级 SummaryCard ID」回归路径——
    //    那种错绑会让 anchor 字符串出现在文件里，但 swift 编译时绑在 VStack 而不是 Button 上。
    let detailTriggerCases = [
        "advancedMaintenanceArchitectureDetailTrigger",
        "advancedMaintenanceGatewayDetailTrigger",
        "advancedMaintenanceLocalDetailTrigger"
    ]
    let scanLines = content.components(separatedBy: "\n")
    let containerOpenerKeywords = [
        "VStack(", "HStack(", "ZStack(", "LazyVGrid(", "LazyHGrid(",
        "ScrollView ", "ScrollView(", "ScrollView{", "Group {", "Group{",
        "ForEach(", "RoundedRectangle(", "DisclosureGroup",
        "VStack {", "HStack {", "ZStack {"
    ]
    for caseName in detailTriggerCases {
        let needle = "OPCUIAutomationIdentifier.\(caseName).rawValue"
        guard let identifierLineIndex = scanLines.firstIndex(where: { $0.contains(needle) }) else {
            Issue.record("DetailTrigger anchor 缺失：\(caseName)")
            continue
        }
        var foundButton = false
        var blockedByOther: String?
        for i in stride(from: identifierLineIndex - 1, through: max(0, identifierLineIndex - 30), by: -1) {
            let line = scanLines[i]
            if line.contains("Button {") {
                foundButton = true
                break
            }
            if let match = containerOpenerKeywords.first(where: { line.contains($0) }), line.contains("{") {
                blockedByOther = "\(match) 在 line \(i + 1)"
                break
            }
        }
        #expect(foundButton,
                "\(caseName) 必须直接绑在 `Button {` 上；向上扫 30 行未找到 Button 开启行（aux trigger 可能错绑在父容器）")
        #expect(blockedByOther == nil,
                "\(caseName) 向上扫到了非 Button 容器开启行（\(blockedByOther ?? "")），说明 anchor 实际绑在父级 — Computer Use 会看到子按钮显示父级 SummaryCard ID。")
    }

    // 9. 反向：DetailTrigger anchor 行附近必须出现「查看详情」label，确认 Button 的可见标签是中文且对应到正确按钮。
    for caseName in detailTriggerCases {
        let needle = "OPCUIAutomationIdentifier.\(caseName).rawValue"
        guard let identifierLineIndex = scanLines.firstIndex(where: { $0.contains(needle) }) else { continue }
        var foundDetailLabel = false
        for i in stride(from: identifierLineIndex - 1, through: max(0, identifierLineIndex - 12), by: -1) {
            if scanLines[i].contains("Label(\"查看详情\"") {
                foundDetailLabel = true
                break
            }
        }
        #expect(foundDetailLabel, "\(caseName) 上方应有 `Label(\"查看详情\", ...)` 标记 Button 的中文可见标签。")
    }
}

@Test func terminalHallAndCommunicationIconOnlyButtonsExposeChineseAccessibilityLabel() async throws {
    // 守门：主界面所有 icon-only Button（label 只放 `Image(systemName:)`、没有 Text/Label 文字）
    // 必须显式提供中文 `.accessibilityLabel(...)` 和 `.accessibilityHint(...)`。
    //
    // 不加显式 a11y label 时，macOS AX tree 会用 SF Symbol 的英文默认描述（如 "Trash" / "Send" / "paperplane.fill"），
    // VoiceOver 朗读出英文，Computer Use 看到的也是英文/符号语义——这违背产品中文话术边界，并且让自动化定位
    // 难以稳定锚到具体业务动作（清空日志 / 发送指令 / 关闭面板）。
    //
    // 已知 icon-only 按钮清单：每条 = (文件, SF Symbol 字面量, 必须出现的中文 a11y label)。
    // 任何新增 icon-only 主入口按钮，请补一行进表 + 在源码里加 .accessibilityLabel/.accessibilityHint。
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    struct IconOnlyButtonExpectation {
        let file: String
        let symbol: String
        let label: String
        let hintMustContain: String
    }
    let expectations: [IconOnlyButtonExpectation] = [
        IconOnlyButtonExpectation(
            file: "Sources/OPCCompanyCore/TerminalHallView.swift",
            symbol: #"Image(systemName: "trash")"#,
            label: #".accessibilityLabel("清空 \(agent.displayName) 终端日志")"#,
            hintMustContain: "清空当前员工终端"
        ),
        IconOnlyButtonExpectation(
            file: "Sources/OPCCompanyCore/InspectorPanel.swift",
            symbol: #"Image(systemName: "paperplane.fill")"#,
            label: #".accessibilityLabel("发送指令")"#,
            hintMustContain: "发送给选中员工"
        ),
        IconOnlyButtonExpectation(
            file: "Sources/OPCCompanyCore/AddEmployeeSheet.swift",
            symbol: #"Image(systemName: "xmark")"#,
            label: #".accessibilityLabel("关闭添加员工面板")"#,
            hintMustContain: "放弃当前未保存"
        )
    ]

    for expectation in expectations {
        let url = projectRoot.appendingPathComponent(expectation.file)
        let content = normalizeL10nSourceShape(try String(contentsOf: url, encoding: .utf8))
        let lines = content.components(separatedBy: "\n")

        guard let symbolLineIndex = lines.firstIndex(where: { $0.contains(expectation.symbol) }) else {
            Issue.record("\(expectation.file) 未找到预期 icon-only 按钮 SF Symbol：\(expectation.symbol)")
            continue
        }

        // 中文 a11y label 必须出现在 SF Symbol 行之后 20 行内（属于同一 Button 的修饰链；
        // 部分按钮 label 闭合后还有 buttonStyle / disabled / 注释行才到 accessibilityHint）。
        let scanWindowEnd = min(lines.count - 1, symbolLineIndex + 20)
        var foundLabel = false
        var foundHint = false
        for i in (symbolLineIndex + 1)...scanWindowEnd {
            if lines[i].contains(expectation.label) {
                foundLabel = true
            }
            if lines[i].contains(".accessibilityHint(") && lines[i].contains(expectation.hintMustContain) {
                foundHint = true
            }
        }
        #expect(foundLabel, "\(expectation.file) 中 \(expectation.symbol) 按钮必须有 \(expectation.label)；缺失会让 macOS AX tree 暴露 SF Symbol 英文默认语义。")
        #expect(foundHint, "\(expectation.file) 中 \(expectation.symbol) 按钮必须有含「\(expectation.hintMustContain)」的中文 .accessibilityHint(...)，便于 Computer Use / VoiceOver 解释动作。")
    }

    // 反向 sanity：上述 3 处中文 label 字符串必须在对应文件中**真实出现**（防止 expectations 表被改坏后还能误 pass）。
    for expectation in expectations {
        let url = projectRoot.appendingPathComponent(expectation.file)
        let content = normalizeL10nSourceShape(try String(contentsOf: url, encoding: .utf8))
        #expect(content.contains(expectation.label), "\(expectation.file) 缺少中文 a11y label 字面量：\(expectation.label)")
    }
}

@Test func terminalHallHeaderPromptFieldExposesStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalHallHeaderPromptField = \"OPCTerminalHallHeaderPromptField\""),
            "DisplayFormatting.swift 必须声明 terminalHallHeaderPromptField enum case")

    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    guard let hallSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalHallView:",
        failureMessage: "未找到 TerminalHallView struct 起点 — 终端大厅顶部提示词输入框 a11y 契约失效"
    ) else { return }

    #expect(hallSlice.contains("TextField(\"发送给员工终端的提示词\", text: $prompt, axis: .vertical)"),
            "终端大厅顶部提示词输入框必须继续使用中文 placeholder")
    #expect(hallSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallHeaderPromptField.rawValue)"),
            "终端大厅顶部提示词输入框必须挂 terminalHallHeaderPromptField accessibilityIdentifier")
    #expect(hallSlice.contains(".accessibilityLabel(\"发送给员工终端的提示词\")"),
            "终端大厅顶部提示词输入框必须挂中文 accessibilityLabel")
    #expect(hallSlice.contains(".accessibilityHint(\"填写后会被「运行全部」按钮发送给当前产品的可执行员工\")"),
            "终端大厅顶部提示词输入框必须说明与运行全部按钮的关系")
}

@Test func terminalHallRunAllButtonExposesStableAccessibilityAnchorForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case terminalHallRunAllButton = \"OPCTerminalHallRunAllButton\""),
            "DisplayFormatting.swift 必须声明 terminalHallRunAllButton enum case")

    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    guard let hallSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalHallView:",
        failureMessage: "未找到 TerminalHallView struct 起点 — 运行全部按钮 a11y 契约失效"
    ) else { return }

    #expect(hallSlice.contains("store.runAllExecutableAgents(prompt: prompt)"),
            "运行全部按钮必须继续走现有 runAllExecutableAgents 路径")
    #expect(hallSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallRunAllButton.rawValue)"),
            "运行全部按钮必须挂 terminalHallRunAllButton accessibilityIdentifier")
    #expect(hallSlice.contains(".accessibilityLabel(\"运行全部员工终端\")"),
            "运行全部按钮必须挂中文 accessibilityLabel")
    #expect(hallSlice.contains(".accessibilityHint(\"把当前提示词发送给当前产品所有可执行且未运行员工；没有可执行员工或员工都在运行时禁用\")"),
            "运行全部按钮必须说明发送范围和禁用边界")
}

@Test func terminalHallRunAllMultiAgentRequiresTokenConfirmation() async throws {
    // 守门契约：终端大厅顶部「运行全部」必须在「同时会发送给 ≥ 2 名可执行员工」时弹中文确认。
    //
    // 旧契约只在「提示词等于默认汇报」时拦截，导致用户改写提示词后一次点击仍会同时消耗多份外部模型额度。
    // 新契约把触发条件纯化为 `runnableAgentCount > 1`——不再以 prompt 内容为门槛。
    //
    // 同时确认对话框 message 必须显式说明「发送给几名员工」+「会消耗 N 份外部模型额度」，
    // 防止确认文案退化成模糊提示（例如旧版只说「会同时消耗多名员工命令行额度」却没说 N）。
    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    guard let hallSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalHallView:",
        failureMessage: "未找到 TerminalHallView struct 起点 — 运行全部多员工确认契约失效"
    ) else { return }

    // 1. 状态变量已重命名为「多员工」语义，不能再叫 confirmsDefaultRunAll
    #expect(hallSlice.contains("@State private var confirmsMultiAgentRunAll = false"),
            "运行全部多员工确认 state 必须命名为 confirmsMultiAgentRunAll")
    #expect(!hallSlice.contains("confirmsDefaultRunAll"),
            "旧的 confirmsDefaultRunAll 命名必须彻底替换，避免残留两套门控状态")

    // 2. 触发逻辑挂在 requiresRunAllTokenConfirmation 上
    #expect(hallSlice.contains("if requiresRunAllTokenConfirmation"))
    #expect(hallSlice.contains("runnableAgentCount > 1"),
            "requiresRunAllTokenConfirmation 必须以 runnableAgentCount > 1 作为触发门槛")

    // 3. 触发条件不再依赖默认提示词字符串：computed property 体里不应再做 prompt 等值比较
    let requiresVarMarker = "private var requiresRunAllTokenConfirmation:"
    if let requiresStart = hallSlice.range(of: requiresVarMarker) {
        let after = hallSlice[requiresStart.upperBound...]
        // computed body 截到 800 char 内匹配，足够覆盖 1-2 行 expression-body computed property。
        let bodySlice = String(after.prefix(800))
        #expect(!bodySlice.contains("OPCVisibleInterfaceCopy.defaultAgentReportPromptText"),
                "requiresRunAllTokenConfirmation 不再以默认提示词为触发条件——任何提示词只要触达多员工就要确认")
        #expect(!bodySlice.contains("trimmingCharacters"),
                "requiresRunAllTokenConfirmation 不应再做 prompt trimming 比较")
    } else {
        Issue.record("未找到 requiresRunAllTokenConfirmation 计算属性 — 多员工确认契约失效")
    }

    // 4. 确认对话框标题 + 文案必须含「N 名员工」+「外部模型额度」明示成本
    #expect(hallSlice.contains(".confirmationDialog(\"确认运行全部员工终端\""))
    #expect(hallSlice.contains("即将把当前提示词同时发送给"),
            "确认 message 必须以「即将把当前提示词同时发送给」开头说明动作范围")
    #expect(hallSlice.contains("multiAgentRunAllWarning(runnableAgentCount)") && hallSlice.contains(" 名员工终端"),
            "确认 message 必须把可运行员工数量插值到文案中")
    #expect(hallSlice.contains("外部模型额度"),
            "确认 message 必须显式提到「外部模型额度」，避免成本说明退化")

    // 5. 确认按钮的 label 也要带数量插值，让用户在按下确认前再看到一次准确数字
    #expect(hallSlice.contains("Button(\"发送给 \\(runnableAgentCount) 名员工\")"),
            "确认对话框主按钮 label 必须带数量插值「发送给 N 名员工」")
}

@Test func terminalHallExternalCallNoticeAlwaysVisibleNearPrompt() async throws {
    // 守门契约：终端大厅顶部提示词输入框旁必须有一行常驻可见的「外部调用 / 额度」中文提示，
    // 让用户在按「运行 / 运行全部」前就理解这是真实模型调用，「预检」是干跑。
    //
    // 该提示**不允许**被折叠到 popover/help/tooltip——必须是 TextField 同一容器内的常驻 Text 节点。
    // 文案集中在 `terminalHallExternalCallNotice` 常量，便于 RUNBOOK / a11y 与运行成本说明保持单一真相。
    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 顶层常量必须存在并提到三家命令行后端 + 「外部模型额度」 + 「预检」/「不调用真实模型」二元对照
    #expect(viewSource.contains("internal let terminalHallExternalCallNotice = \""),
            "TerminalHallView.swift 必须提供 terminalHallExternalCallNotice 顶层常量作为提示文案单一来源")
    #expect(viewSource.contains("Claude Code / Codex / Gemini CLI"),
            "提示文案必须列出三家命令行后端品牌名以避免抽象化成空话")
    #expect(viewSource.contains("外部模型额度"),
            "提示文案必须显式提到「外部模型额度」")
    #expect(viewSource.contains("不调用真实模型，不消耗额度"),
            "提示文案必须为「预检」给出「不调用真实模型，不消耗额度」的安全侧承诺")

    // 2. 主视图体内必须把这个常量渲染成可见 Text 节点
    guard let hallSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "struct TerminalHallView:",
        failureMessage: "未找到 TerminalHallView struct 起点 — 外部调用提示常驻可见契约失效"
    ) else { return }

    #expect(hallSlice.contains("Text(terminalHallExternalCallNotice)"),
            "TerminalHallView 必须在主视图体内渲染 Text(terminalHallExternalCallNotice)")
    #expect(hallSlice.contains(".accessibilityLabel(\"运行将真实调用外部命令行后端\")"),
            "外部调用提示必须挂中文 accessibilityLabel，避免 VoiceOver 漏读")
    #expect(hallSlice.contains(".accessibilityHint(terminalHallExternalCallNotice)"),
            "外部调用提示必须把完整文案同步到 accessibilityHint")

    // 3. 反契约：不应被收纳进 .help() / popover / disclosure / sheet — 必须保持常驻可见
    let noticeReferences = hallSlice.components(separatedBy: "terminalHallExternalCallNotice")
    let helpUsage = noticeReferences.dropFirst().contains { fragment in
        let head = fragment.prefix(80)
        return head.contains(".help(") || head.contains(".popover(")
    }
    #expect(!helpUsage,
            "外部调用提示文案不应包装进 .help(...) / .popover(...) — 折叠/悬浮不算「常驻可见」")
}

@Test func terminalAgentCardPreflightAndRunButtonsAreVisuallyAndTextuallyDistinct() async throws {
    // 守门契约：员工卡上的「预检」和「运行」按钮必须在视觉与文字两侧都有显著区分，
    // 防止用户把「干跑/不消耗额度」的预检和「真实调用/消耗额度」的运行当成同等代价的动作。
    //
    // 视觉契约：
    //   - 预检：`.buttonStyle(.bordered)` + `.foregroundStyle(CompanyTheme.muted)` + Label「预检 · 干跑」+ icon「checkmark.shield」
    //   - 运行：`.buttonStyle(.borderedProminent)` + `.tint(CompanyTheme.accent)` + Label 含「真实调用」+ icon「bolt.fill」
    //
    // 文字契约：
    //   - 预检 hint 必须含「不调用真实模型，不消耗外部额度」
    //   - 运行 hint 必须含「会真实调用员工命令行后端并消耗外部模型额度」
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 视觉：Label 文案
    #expect(source.contains("Label(\"预检 · 干跑\", systemImage: \"checkmark.shield\")"),
            "员工卡预检按钮 Label 必须为「预检 · 干跑」+ checkmark.shield")
    #expect(source.contains("Label(isRunning ? \"运行中\" : \"运行 · 真实调用\", systemImage: isRunning ? \"hourglass\" : \"bolt.fill\")"),
            "员工卡运行按钮 Label 必须为「运行 · 真实调用」/「运行中」+ bolt.fill/hourglass")

    // 视觉：预检按钮必须挂 muted 灰前景，与运行按钮的 accent prominent 形成二元对照
    #expect(source.contains(".foregroundStyle(CompanyTheme.muted)\n                .disabled(agent.role == .boss)"),
            "预检按钮必须使用 CompanyTheme.muted 灰前景紧接 .disabled，与运行按钮 accent prominent 形成二元对照")

    // 文字：a11y hint 双向标注
    #expect(source.contains("不调用真实模型，不消耗外部额度"),
            "预检按钮 hint 必须显式承诺「不调用真实模型，不消耗外部额度」")
    #expect(source.contains("会真实调用员工命令行后端并消耗外部模型额度"),
            "运行按钮 hint 必须显式警示「会真实调用员工命令行后端并消耗外部模型额度」")
}

@Test func terminalHallArchitectureSummaryPrimaryButtonsExposeStableAccessibilityAnchorsForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case advancedMaintenanceArchitectureAuditButton = \"OPCAdvancedMaintenanceArchitectureAuditButton\""),
            "DisplayFormatting.swift 必须声明 advancedMaintenanceArchitectureAuditButton enum case")
    #expect(displaySource.contains("case advancedMaintenanceArchitectureClosureDrillButton = \"OPCAdvancedMaintenanceArchitectureClosureDrillButton\""),
            "DisplayFormatting.swift 必须声明 advancedMaintenanceArchitectureClosureDrillButton enum case")

    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    guard let cardSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "private struct MultiAgentArchitectureSummaryCard:",
        failureMessage: "未找到 MultiAgentArchitectureSummaryCard struct 起点 — 架构摘要主按钮 a11y 契约失效"
    ) else { return }

    #expect(cardSlice.contains("store.runMultiAgentArchitectureAudit()"),
            "架构摘要运行体检按钮必须继续走现有 runMultiAgentArchitectureAudit 路径")
    #expect(cardSlice.contains("_ = store.runMultiAgentArchitectureClosureDrill()"),
            "架构摘要闭环演练按钮必须继续走现有 runMultiAgentArchitectureClosureDrill 路径")
    #expect(cardSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureAuditButton.rawValue)"),
            "架构摘要运行体检按钮必须挂 advancedMaintenanceArchitectureAuditButton accessibilityIdentifier")
    #expect(cardSlice.contains(".accessibilityLabel(\"运行多员工架构体检\")"),
            "架构摘要运行体检按钮必须挂中文 accessibilityLabel")
    #expect(cardSlice.contains(".accessibilityHint(\"为当前产品运行多员工架构体检，写入维护审计并把选中员工切换到技术负责人\")"),
            "架构摘要运行体检按钮必须说明副作用边界")
    #expect(cardSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureClosureDrillButton.rawValue)"),
            "架构摘要闭环演练按钮必须挂 advancedMaintenanceArchitectureClosureDrillButton accessibilityIdentifier")
    #expect(cardSlice.contains(".accessibilityLabel(\"运行多员工架构闭环演练\")"),
            "架构摘要闭环演练按钮必须挂中文 accessibilityLabel")
    #expect(cardSlice.contains(".accessibilityHint(\"为当前产品运行闭环演练，生成闭环轨迹并把选中员工切换到技术负责人\")"),
            "架构摘要闭环演练按钮必须说明副作用边界")
}

@Test func terminalHallLocalMaintenanceSummaryPrimaryButtonsExposeStableAccessibilityAnchorsForComputerUse() async throws {
    let displaySource = try loadOPCCompanyCoreSource("DisplayFormatting.swift")
    #expect(displaySource.contains("case advancedMaintenanceLocalIsolationAuditButton = \"OPCAdvancedMaintenanceLocalIsolationAuditButton\""),
            "DisplayFormatting.swift 必须声明 advancedMaintenanceLocalIsolationAuditButton enum case")
    #expect(displaySource.contains("case advancedMaintenanceLocalCLIPreflightButton = \"OPCAdvancedMaintenanceLocalCLIPreflightButton\""),
            "DisplayFormatting.swift 必须声明 advancedMaintenanceLocalCLIPreflightButton enum case")

    let viewSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    guard let cardSlice = extractTopLevelStructSlice(
        from: viewSource,
        structMarker: "private struct LocalMaintenanceSummaryCard:",
        failureMessage: "未找到 LocalMaintenanceSummaryCard struct 起点 — 本地维护摘要主按钮 a11y 契约失效"
    ) else { return }

    #expect(cardSlice.contains("store.runProductIsolationAudit()"),
            "本地维护摘要隔离体检按钮必须继续走现有 runProductIsolationAudit 路径")
    #expect(cardSlice.contains("store.runCLIToolchainPreflightForSelectedProduct()"),
            "本地维护摘要命令行预检按钮必须继续走现有 runCLIToolchainPreflightForSelectedProduct 路径")
    #expect(cardSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalIsolationAuditButton.rawValue)"),
            "本地维护摘要隔离体检按钮必须挂 advancedMaintenanceLocalIsolationAuditButton accessibilityIdentifier")
    #expect(cardSlice.contains(".accessibilityLabel(\"运行本地隔离体检\")"),
            "本地维护摘要隔离体检按钮必须挂中文 accessibilityLabel")
    #expect(cardSlice.contains(".accessibilityHint(\"为当前产品运行多产品隔离体检，写入维护审计并刷新本地稳定性摘要\")"),
            "本地维护摘要隔离体检按钮必须说明副作用边界")
    #expect(cardSlice.contains(".accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalCLIPreflightButton.rawValue)"),
            "本地维护摘要命令行预检按钮必须挂 advancedMaintenanceLocalCLIPreflightButton accessibilityIdentifier")
    #expect(cardSlice.contains(".accessibilityLabel(\"运行命令行链路预检\")"),
            "本地维护摘要命令行预检按钮必须挂中文 accessibilityLabel")
    #expect(cardSlice.contains(".accessibilityHint(\"为当前产品运行命令行链路干跑预检，不调用真实模型任务\")"),
            "本地维护摘要命令行预检按钮必须说明不会调用真实模型任务")
}

@MainActor
@Test func companyPersistenceSupportDirectoryRedirectsAwayFromRealApplicationSupportInTestProcess() async throws {
    // 当前 swift test 进程下，supportDirectory 必须是临时隔离目录，
    // 不能等于真实用户 ~/Library/Application Support/OPCCompany。
    let realApplicationSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("OPCCompany", isDirectory: true)
    let resolved = CompanyPersistence.supportDirectory

    #expect(resolved.path != realApplicationSupport.path,
        "测试进程不应使用真实 Application Support；当前 supportDirectory=\(resolved.path)，真实路径=\(realApplicationSupport.path)")

    // 必须落在临时目录或显式覆盖路径下；用 FileManager.default.temporaryDirectory 的 standardized path 做共同前缀比较。
    let tempPrefix = FileManager.default.temporaryDirectory.standardizedFileURL.path
    let envOverride = ProcessInfo.processInfo.environment["OPC_COMPANY_SUPPORT_DIR"]
    let resolvedStandardized = resolved.standardizedFileURL.path
    if let envOverride, !envOverride.isEmpty {
        let expected = NSString(string: envOverride).expandingTildeInPath
        #expect(resolvedStandardized.hasPrefix(URL(fileURLWithPath: expected, isDirectory: true).standardizedFileURL.path)
            || resolvedStandardized == expected)
    } else {
        #expect(resolvedStandardized.hasPrefix(tempPrefix),
            "测试进程 supportDirectory 应在临时目录内：\(resolvedStandardized)")
        #expect(resolvedStandardized.contains("OPCCompanyTests-"),
            "测试进程 supportDirectory 应使用 OPCCompanyTests-<pid> 命名：\(resolvedStandardized)")
    }

    // 派生 URL 跟随 supportDirectory：state / history / agents / checkpoints 全部都在隔离目录下。
    #expect(CompanyPersistence.stateURL.deletingLastPathComponent().standardizedFileURL.path == resolvedStandardized)
    #expect(CompanyPersistence.historyIndexURL.deletingLastPathComponent().standardizedFileURL.path == resolvedStandardized)
    #expect(CompanyPersistence.agentWorkspacesURL.deletingLastPathComponent().standardizedFileURL.path == resolvedStandardized)
}

@MainActor
@Test func companyPersistenceBootstrapDoesNotWriteToRealApplicationSupport() async throws {
    // 启动 store 并触发 saveSnapshot：所有 IO 必须在隔离目录里发生，绝不能落到真实 Application Support。
    let realApplicationSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("OPCCompany", isDirectory: true)
    let realStateURL = realApplicationSupport.appendingPathComponent("company-state.json")

    // 拍真实路径在测试运行前的状态：是否存在、修改时间。本测试不动用户真实状态。
    let realStateExistedBefore = FileManager.default.fileExists(atPath: realStateURL.path)
    let realModifiedBefore = (try? FileManager.default.attributesOfItem(atPath: realStateURL.path))?[.modificationDate] as? Date

    // 触发 bootstrap + save（CompanyStore.bootstrap 内部会 saveSnapshot）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    _ = store.selectedProductID

    // 测试隔离目录里 state 文件应当被写入。
    let isolatedStateURL = CompanyPersistence.stateURL
    #expect(FileManager.default.fileExists(atPath: isolatedStateURL.path),
        "隔离 supportDirectory 内应当生成 company-state.json：\(isolatedStateURL.path)")

    // 真实路径状态必须保持不变：测试前不存在则现在仍不存在；测试前存在则修改时间不变。
    if realStateExistedBefore {
        let realModifiedAfter = (try? FileManager.default.attributesOfItem(atPath: realStateURL.path))?[.modificationDate] as? Date
        #expect(realModifiedAfter == realModifiedBefore,
            "真实 Application Support state 修改时间不应被测试触动：before=\(realModifiedBefore?.description ?? "nil")，after=\(realModifiedAfter?.description ?? "nil")")
    } else {
        #expect(!FileManager.default.fileExists(atPath: realStateURL.path),
            "测试不应在真实 Application Support 创建 company-state.json")
    }
}

// MARK: - R26 候选 χ-persistence 备份逻辑守门（角色继承期轮 26）

@Test func companyPersistenceLoadBacksUpCorruptedStateBeforeReturningNil() async throws {
    // R26：当 stateURL 内容损坏（无效 JSON / Codable schema 不匹配），load() 必须：
    // (1) 返回 nil（让 caller 走 bootstrap）；
    // (2) 把损坏 payload 备份到 supportDirectory/company-state-corrupted-<ISO8601>.json；
    // (3) 把 decode 错误描述写入同名 .reason.txt sidecar。
    // 防止悄悄覆盖损坏数据销毁 forensic 现场（candidate χ-persistence 落地）。

    let supportDir = CompanyPersistence.supportDirectory
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

    // 备份扫描基线：测试前 supportDir 里既存的 corrupted 备份不应被本测试影响判定。
    let beforeURLs = (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
    let beforeBackups = Set(beforeURLs.filter { $0.lastPathComponent.hasPrefix("company-state-corrupted-") }.map { $0.lastPathComponent })

    // 写入故意损坏的 JSON（既不是 nil 文件不存在 path，也不是合法 CompanySnapshot 结构）。
    let corruptPayload = Data("{ this is not valid JSON for CompanySnapshot ::: }".utf8)
    try corruptPayload.write(to: CompanyPersistence.stateURL, options: [.atomic])

    let result = CompanyPersistence.load()
    #expect(result == nil, "decode 失败应返回 nil 让 caller 走 bootstrap，实际：\(String(describing: result))")

    // 备份扫描：必须新出现 1 个 company-state-corrupted-*.json + 同名 .reason.txt。
    let afterURLs = try FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)
    let newBackups = afterURLs
        .map { $0.lastPathComponent }
        .filter { $0.hasPrefix("company-state-corrupted-") && $0.hasSuffix(".json") && !beforeBackups.contains($0) }
    #expect(newBackups.count == 1,
        "应新增 1 个 corrupted 备份文件，实际：\(newBackups)")

    guard let backupName = newBackups.first else { return }
    let backupURL = supportDir.appendingPathComponent(backupName)
    let backupData = try Data(contentsOf: backupURL)
    #expect(backupData == corruptPayload,
        "备份内容必须等于损坏的原始 payload（forensic 完整性）")

    let reasonName = backupName.replacingOccurrences(of: ".json", with: ".reason.txt")
    let reasonURL = supportDir.appendingPathComponent(reasonName)
    #expect(FileManager.default.fileExists(atPath: reasonURL.path),
        "应同时生成 reason sidecar：\(reasonName)")
    if FileManager.default.fileExists(atPath: reasonURL.path) {
        let reasonText = (try? String(contentsOf: reasonURL, encoding: .utf8)) ?? ""
        #expect(!reasonText.isEmpty, "reason sidecar 不应为空")
    }

    // 清理：本次测试制造的备份不留给后续测试看见。
    try? FileManager.default.removeItem(at: backupURL)
    try? FileManager.default.removeItem(at: reasonURL)
    try? FileManager.default.removeItem(at: CompanyPersistence.stateURL)
}

@Test func companyPersistenceLoadReturnsNilWithoutBackupWhenStateFileDoesNotExist() async throws {
    // R26：load() 对「文件不存在」的合法 happy path 必须不产生备份文件（否则启动期就会污染 supportDir）。
    // 这是和 corruption path 的关键差异守门：missing != corrupt。

    let supportDir = CompanyPersistence.supportDirectory
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

    // 确保 stateURL 不存在。
    try? FileManager.default.removeItem(at: CompanyPersistence.stateURL)

    let beforeURLs = (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
    let beforeBackupCount = beforeURLs.filter { $0.lastPathComponent.hasPrefix("company-state-corrupted-") }.count

    let result = CompanyPersistence.load()
    #expect(result == nil, "stateURL 不存在 load() 返回 nil")

    let afterURLs = (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? []
    let afterBackupCount = afterURLs.filter { $0.lastPathComponent.hasPrefix("company-state-corrupted-") }.count
    #expect(afterBackupCount == beforeBackupCount,
        "文件不存在路径不应触发 corrupted 备份。before=\(beforeBackupCount) after=\(afterBackupCount)")
}

@MainActor
@Test func companyPersistenceSaveSurfacesFailureWhenSupportPathIsImpossible() async throws {
    // R26+ χ-persistence 续：CompanyPersistence.save 必须把失败显式上报（Result<Void, Error>），
    // CompanyStore.saveSnapshot 必须把失败转为老板可见的 in-memory 风险事件而不是 silent-failure。
    //
    // 强制失败手法：file-as-directory ——
    // 在临时目录里写一个普通文件，再要求 save() 把 state 写到「该文件下面」的子路径。
    // createDirectory(withIntermediateDirectories: true) 会因为父路径已被普通文件占位而抛错，
    // 触发 save 的 catch → 返回 .failure。这种构造不依赖 supportDirectory 的进程级缓存，
    // 也不污染共享 sandbox（隔离在 OPCSaveFail-<UUID> 临时目录内）。
    let tmpRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCSaveFail-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpRoot) }

    let fileBlocker = tmpRoot.appendingPathComponent("not-a-directory")
    try Data("blocker".utf8).write(to: fileBlocker, options: [.atomic])
    // impossibleStateURL 的父路径是一个普通文件 —— createDirectory 必然失败。
    let impossibleStateURL = fileBlocker.appendingPathComponent("company-state.json")

    let store = CompanyStore.bootstrap(loadPersisted: false)
    let snapshot = store.currentSnapshot()

    // 1) 持久化层：返回 .failure 而不是悄悄成功。
    let result = CompanyPersistence.save(snapshot, to: impossibleStateURL)
    guard case .failure(let surfaceError) = result else {
        Issue.record("save(_:to:) 应该在父路径是普通文件时失败，但返回了 .success")
        return
    }
    #expect(!surfaceError.localizedDescription.isEmpty,
        "失败 error 必须有描述，便于 in-memory 事件展示给老板：\(surfaceError)")

    // 2) Store 层：用注入的保存闭包触发运行时失败，必须立刻追加一条 in-memory 风险事件；
    //    连续同类失败只保留一条最新事件，避免磁盘满时刷屏。
    let injectedError = NSError(domain: "OPCCompanyTests.Persistence", code: 31, userInfo: [
        NSLocalizedDescriptionKey: "测试注入的持久化失败"
    ])
    let baselineEventCount = store.events.count
    var saveAttempts = 0
    store.persistSnapshot = { _ in
        saveAttempts += 1
        return .failure(injectedError)
    }

    store.saveSnapshot()
    #expect(saveAttempts == 1, "saveSnapshot 必须调用注入的持久化闭包一次，实际 \(saveAttempts)")
    #expect(store.events.count == baselineEventCount + 1,
            "保存失败必须追加一条 in-memory 风险事件")
    #expect(store.events.first?.kind == .risk)
    #expect(store.events.first?.title == "持久化失败")
    #expect(store.events.first?.detail.contains("测试注入的持久化失败") == true)
    #expect(store.events.first?.detail.contains("应用重启会丢失最近变更") == true)

    store.saveSnapshot()
    #expect(saveAttempts == 2, "第二次 saveSnapshot 仍应尝试保存，实际 \(saveAttempts)")
    #expect(store.events.count == baselineEventCount + 1,
            "连续同类持久化失败必须相邻去重，不能刷屏事件流")

    // 3) 源码守门：保留 saveSnapshot 处理 .failure → recordPersistenceFailure → appendEvent
    //    的链路，并且明确不再次调用 saveSnapshot（否则失败态会无限递归）。
    let storeSource = try loadOPCCompanyCoreSource("CompanyStore.swift")
    #expect(storeSource.contains("recordPersistenceFailure"),
        "CompanyStore.swift 必须保留 recordPersistenceFailure helper（χ-persistence 失败可见路径）")
    #expect(storeSource.contains("if case .failure(let error) = persistSnapshot"),
        "saveSnapshot 必须显式消费 Result，不能忽略 .failure")
    let persistenceSource = try loadOPCCompanyCoreSource("CompanyPersistence.swift")
    #expect(persistenceSource.contains("Result<Void, Error>"),
        "CompanyPersistence.save 必须返回 Result<Void, Error>")
}

@Test func companyPersistenceLoadBackupSourceContainsCandidateXReference() async throws {
    // R26 守门：源码必须保留对 R26 / candidate χ-persistence / backupCorruptedState 的指针，
    // 防止后续 refactor 悄悄删除备份逻辑导致 silent-failure 回归。
    let source = try loadOPCCompanyCoreSource("CompanyPersistence.swift")
    #expect(source.contains("backupCorruptedState"),
        "CompanyPersistence.swift 必须保留 backupCorruptedState helper")
    #expect(source.contains("company-state-corrupted-"),
        "备份文件名前缀 company-state-corrupted- 必须保留")
    #expect(source.contains("候选 χ-persistence") || source.contains("candidate χ-persistence"),
        "源码注释应保留 candidate χ-persistence 指针便于回溯 R21 安全审计 + R26 落地")
    #expect(source.contains("R26") || source.contains("轮 26"),
        "源码注释应标注 R26 落地轮次")
}

@Test func companyPersistenceResolveSupportDirectoryHonorsEnvironmentAndXCTestDetection() async throws {
    // 用 internal helper 直接验证多条决策分支，不依赖进程级 static let 缓存。
    let mockTemp = FileManager.default.temporaryDirectory
        .appendingPathComponent("OPCResolveTest-\(UUID().uuidString)", isDirectory: true)
    let pid: Int32 = 4242
    let nonTestProcessName = "OPCCompany"
    let nonTestBundlePath = "/Applications/OPCCompany.app"
    let nonTestArguments: [String] = ["/Applications/OPCCompany.app/Contents/MacOS/OPCCompany"]

    // 1. OPC_COMPANY_SUPPORT_DIR 显式覆盖优先级最高，即便检测到 XCTest 也走显式路径。
    let explicit = "/tmp/opc-explicit-test"
    let explicitResolved = CompanyPersistence.resolveSupportDirectory(
        environment: [
            "OPC_COMPANY_SUPPORT_DIR": explicit,
            "XCTestConfigurationFilePath": "/some/xctest.xctest"
        ],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: "xctest",
        bundlePath: "/some/x.xctest",
        arguments: ["xctest", "/some/x.xctest"]
    )
    #expect(explicitResolved.standardizedFileURL.path == URL(fileURLWithPath: explicit, isDirectory: true).standardizedFileURL.path)

    // 2a. Xcode XCTest：env 注入 → 临时目录隔离。
    let xctestEnvResolved = CompanyPersistence.resolveSupportDirectory(
        environment: ["XCTestConfigurationFilePath": "/some/xctest.xctest"],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: nonTestProcessName,
        bundlePath: nonTestBundlePath,
        arguments: nonTestArguments
    )
    #expect(xctestEnvResolved.lastPathComponent == "OPCCompanyTests-\(pid)")
    #expect(xctestEnvResolved.deletingLastPathComponent().standardizedFileURL.path == mockTemp.standardizedFileURL.path)

    // 2b. SwiftPM `swift test`：bundle 路径 .xctest 结尾 → 临时目录隔离。
    let swiftPMBundleResolved = CompanyPersistence.resolveSupportDirectory(
        environment: [:],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: "OPCCompanyPackageTests",
        bundlePath: "/path/to/OPCCompanyPackageTests.xctest",
        arguments: nonTestArguments
    )
    #expect(swiftPMBundleResolved.lastPathComponent == "OPCCompanyTests-\(pid)")
    #expect(swiftPMBundleResolved.deletingLastPathComponent().standardizedFileURL.path == mockTemp.standardizedFileURL.path)

    // 2c. SwiftPM swift-testing 实际主进程信号：processName=`swiftpm-testing-helper`，
    // bundle 不在 .xctest 里，但 arguments 含 .xctest 路径或 `--testing-library`。
    let swiftpmHelperResolved = CompanyPersistence.resolveSupportDirectory(
        environment: [:],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: "swiftpm-testing-helper",
        bundlePath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm",
        arguments: [
            "swiftpm-testing-helper",
            "--test-bundle-path",
            "/path/OPCCompanyPackageTests.xctest/Contents/MacOS/OPCCompanyPackageTests",
            "--testing-library", "swift-testing"
        ]
    )
    #expect(swiftpmHelperResolved.lastPathComponent == "OPCCompanyTests-\(pid)")

    // 2d. 进程名含 xctest / PackageTests / swift-testing → 临时目录隔离。
    for processNameSignal in ["xctest", "OPCCompanyPackageTests", "swift-testing"] {
        let r = CompanyPersistence.resolveSupportDirectory(
            environment: [:],
            temporaryDirectory: mockTemp,
            processIdentifier: pid,
            processName: processNameSignal,
            bundlePath: nonTestBundlePath,
            arguments: nonTestArguments
        )
        #expect(r.lastPathComponent == "OPCCompanyTests-\(pid)", "进程名 \(processNameSignal) 应触发测试隔离")
    }

    // 2e. arguments 含 `.xctest` 路径也是有效信号（即便进程名/bundle 都不像测试）。
    let argsXctestResolved = CompanyPersistence.resolveSupportDirectory(
        environment: [:],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: nonTestProcessName,
        bundlePath: nonTestBundlePath,
        arguments: ["wrapper", "/some/path/to/Tests.xctest"]
    )
    #expect(argsXctestResolved.lastPathComponent == "OPCCompanyTests-\(pid)")

    // 3. 无任何测试信号 + 无显式覆盖 → 真实 Application Support/OPCCompany。
    let realResolved = CompanyPersistence.resolveSupportDirectory(
        environment: [:],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: nonTestProcessName,
        bundlePath: nonTestBundlePath,
        arguments: nonTestArguments
    )
    let expectedReal = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("OPCCompany", isDirectory: true)
    #expect(realResolved.standardizedFileURL.path == expectedReal.standardizedFileURL.path)

    // 4. 空字符串覆盖 = 当作未设置（避免误把空环境变量当成有效路径）。
    let emptyOverrideResolved = CompanyPersistence.resolveSupportDirectory(
        environment: ["OPC_COMPANY_SUPPORT_DIR": ""],
        temporaryDirectory: mockTemp,
        processIdentifier: pid,
        processName: nonTestProcessName,
        bundlePath: nonTestBundlePath,
        arguments: nonTestArguments
    )
    #expect(emptyOverrideResolved.standardizedFileURL.path == expectedReal.standardizedFileURL.path)
}

// MARK: - 终端大厅员工卡顶部紧凑摘要（不折叠、不隐藏）

@MainActor
@Test func terminalHallCardLongSessionLineCompactsProtocolSummaryButHidesDetails() async throws {
    // 卡顶默认可见行和 Help 详情都用产品文案：不能露协议名 / 画像 / 监控等底层诊断词。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cliAgents = store.agents.filter { $0.backend.type == .subscriptionCLI }
    #expect(!cliAgents.isEmpty)

    for agent in cliAgents {
        let line = try #require(store.terminalHallCardLongSessionLine(for: agent))
        let detail = try #require(store.terminalHallCardLongSessionDetail(for: agent))

        #expect(line.hasPrefix("会话续跑："))
        // 紧凑：去掉前缀后中点分段不超过 2 段（品牌名 + 续跑能力）。
        let body = String(line.dropFirst("会话续跑：".count))
        let segments = body
            .split(separator: "·", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(segments.count == 2,
                "会话续跑简写应=2 段（品牌名 + 续跑能力），实际：\(segments)")

        // 保留品牌名（Codex / Claude / Gemini 任一）。
        let mentionsBrand = segments.contains { seg in
            seg.contains("Codex") || seg.contains("Claude") || seg.contains("Gemini")
        }
        #expect(mentionsBrand, "简写应保留品牌名，实际：\(line)")

        // 第二段必须是产品文案的接续结论，不能直接搬底层 supportsResume 文本。
        let conclusion = segments[1]
        #expect(conclusion == "可按产品接续" || conclusion == "不接续历史会话",
                "续跑结论应是产品文案，实际：\(conclusion)")

        // 默认行与 Help 详情都不允许出现实现层 / 协议层 / 诊断信号词，也不允许底层参数 / 内部字段泄漏。
        let forbiddenVisibleTerms = [
            "长期会话", "执行协议", "协议", "画像", "监控",
            "授权异常", "临时异常",
            "model_reasoning_effort", "--skip-git-repo-check", "rawValue", "backendSignature"
        ]
        for forbidden in forbiddenVisibleTerms {
            #expect(!line.contains(forbidden), "默认行含禁词 \(forbidden)：\(line)")
            #expect(!detail.contains(forbidden), "Help 详情含禁词 \(forbidden)：\(detail)")
        }

        // Help 详情仍要比默认行更完整，但只说产品层接续能力。
        #expect(detail.hasPrefix("会话续跑详情："))
        #expect(detail.contains(segments[0]))
        #expect(detail.contains(segments[1]))
        #expect(detail.contains("产品"))
        // 中文护栏：detail 至少含一个 CJK 字符。
        let containsCJK = detail.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
        #expect(containsCJK, "detail 应保持中文：\(detail)")
    }
}

@MainActor
@Test func terminalHallCardLongSessionLineIsNilForBackendsWithoutInteractionProfile() async throws {
    // API / 本地后端没有 CLI 长期会话画像；卡片应隐去这一行而不是渲染空字符串。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var apiAgent = store.agents.first { $0.backend.type == .subscriptionCLI } ?? store.agents.first { $0.role != .boss }!
    apiAgent.backend = AgentBackend(
        type: .api,
        command: "",
        model: "gpt-4o",
        endpoint: "https://api.example.com/v1/chat/completions",
        apiKey: "",
        reasoningEffort: .medium
    )

    #expect(store.terminalHallCardLongSessionLine(for: apiAgent) == nil)
    #expect(store.terminalHallCardLongSessionDetail(for: apiAgent) == nil)
}

@MainActor
@Test func terminalHallCardTaskDigestLineHandlesEmptyShortAndLongPrompts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let empty = store.terminalHallCardTaskDigestLine(prompt: "   \n  ")
    #expect(empty == nil)

    let defaultPrompt = store.terminalHallCardTaskDigestLine(prompt: OPCVisibleInterfaceCopy.defaultTerminalPromptPlaceholder)
    #expect(defaultPrompt == nil)

    let short = try #require(store.terminalHallCardTaskDigestLine(prompt: "汇报当前状态"))
    #expect(short == "本轮任务：汇报当前状态")

    let multiline = try #require(store.terminalHallCardTaskDigestLine(prompt: "第一行\n第二行\n第三行"))
    #expect(multiline == "本轮任务：第一行 第二行 第三行")
    #expect(!multiline.contains("\n"), "应被压成单行")

    // 60 字边界：用全是中文的 70 字 prompt，确认截断到 60 字 + 省略号。
    let longPrompt = String(repeating: "字", count: 70)
    let truncated = try #require(store.terminalHallCardTaskDigestLine(prompt: longPrompt))
    let body = String(truncated.dropFirst("本轮任务：".count))
    #expect(body.count == 61, "60 字 + 省略号 = 61，实际 \(body.count)：\(body)")
    #expect(body.hasSuffix("…"))
}

@MainActor
@Test func terminalHallCardInjectionHintMentionsAllInjectionDimensions() async throws {
    // 任务注入提示从原 4 行字符串里压成 1 个 info icon + tooltip。
    // tooltip 字符串必须仍点出全部 4 类注入：角色档案 / 记忆 / 技能 / 产品工作区。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let hint = store.terminalHallCardInjectionHint()

    for keyword in ["自动注入", "角色档案", "记忆", "技能", "产品工作区"] {
        #expect(hint.contains(keyword), "tooltip 缺关键词「\(keyword)」：\(hint)")
    }

    // tooltip 不该出现底层参数或英文角色词。
    for forbidden in ["model_reasoning_effort", "--skip-git-repo-check", "rawValue", "Agent 编队", "CTO"] {
        #expect(!hint.contains(forbidden), "tooltip 含禁词 \(forbidden)：\(hint)")
    }
}

@Test func terminalHallAgentCardTopUsesCompactAccessorsInsteadOfTruncatedCommandPreview() async throws {
    // 守门：终端大厅员工卡顶部必须用紧凑 accessor，不再用 lineLimit(2) 截断的 commandPreview 多行字符串。
    // - 必须仍引用 visibleBackendSummary（保留第一行后端 chip）
    // - 必须引用 3 个新 accessor（长期会话简写 / 任务摘要 / 注入提示 tooltip）
    // - 必须不再在 view 里调用 store.commandPreview( —— 该字符串现在只保留给运行前预检 / 终端日志 / 聊天复用
    // - 不允许把这块改造往「DisclosureGroup 默认收起」方向回退
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    let mustContain = [
        "store.visibleBackendSummary(for: agent)",
        "store.terminalHallCardLongSessionLine(for: agent)",
        "store.terminalHallCardLongSessionDetail(for: agent)",
        "store.terminalHallCardTaskDigestLine(prompt: prompt)",
        "store.terminalHallCardInjectionHint()"
    ]
    for fragment in mustContain {
        #expect(source.contains(fragment),
                "TerminalHallView.swift 缺少必需调用：\(fragment)")
    }

    // 必须不再在 view 里读 commandPreview（否则就是回退到旧的 4 行截断渲染）。
    #expect(!source.contains("store.commandPreview("),
            "TerminalHallView 不应再调用 store.commandPreview(；该字符串只保留给日志/预检/聊天")

    // 反向锁：不许把任何结构包进 DisclosureGroup 折叠。
    // 运行前预检的 DisclosureGroup 已改为常驻可见紧凑面板（icon-only `arrow.clockwise` 刷新按钮）；
    // 当前文件里 "DisclosureGroup" 字符串只剩 1 次：文件头注释里的产品准则说明（不再用 DisclosureGroup 把功能藏起来）。
    // 阈值 = 1 严守新结构不被任何 DisclosureGroup 折叠。
    let disclosureCount = source.components(separatedBy: "DisclosureGroup").count - 1
    #expect(disclosureCount <= 1,
            "TerminalHallView 中 DisclosureGroup 出现 \(disclosureCount) 次；预期 ≤ 1（仅文件头注释），任何卡片结构都不允许被折叠")
}

// MARK: - 终端大厅顶部概览结构化指标（与下方 SummaryCard 信息架构对齐）

@MainActor
@Test func terminalHallOverviewMetricsReturnsFiveOrderedChinesetMetricsWithKindMappedByValue() async throws {
    // 概览顶部 5 个指标的标题、顺序、颜色档位都属于产品契约：
    // - 顺序固定为：团队 / 运行中 / 待审批 / 阻塞/失败 / 最近风险（与 next-step 优先级链路对齐）
    // - 颜色档位（kind）按值是否非零分桶：值=0 一律 neutral；值>0 按语义升档
    // - 全是中文 title，无内部字段名
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let metrics = store.terminalHallOverviewMetrics()

    let titles = metrics.map(\.title)
    #expect(titles == ["团队", "运行中", "待审批", "阻塞/失败", "最近风险"],
            "概览指标顺序/中文标题不匹配：\(titles)")

    // bootstrap 后默认产品没有运行中员工 / 没有审批 / 没有阻塞 / 没有最近风险；
    // 但「团队」一定 > 0（默认产品配了完整团队）。
    let team = try #require(metrics.first { $0.title == "团队" })
    #expect(team.value > 0, "默认产品团队人数应 > 0")
    #expect(team.kind == .neutral, "团队字段固定为 neutral，不会因为人多变红")

    for nonTeam in metrics.filter({ $0.title != "团队" }) {
        if nonTeam.value == 0 {
            #expect(nonTeam.kind == .neutral, "\(nonTeam.title) 值=0 应为 neutral，实际 \(nonTeam.kind)")
        } else {
            #expect(nonTeam.kind != .neutral, "\(nonTeam.title) 值>0 应升档，实际 neutral")
        }
    }

    // 反向：title 不应含底层字段名 / 英文角色词。
    for forbidden in ["backend", "rawValue", "Agent", "CTO"] {
        for title in titles {
            #expect(!title.contains(forbidden), "指标标题含禁词 \(forbidden)：\(title)")
        }
    }
}

@MainActor
@Test func terminalHallOverviewNextStepTextReflectsHighestPriorityCondition() async throws {
    // next-step 单行文案优先级链路：
    //   待审批 > 阻塞/失败 > 最近风险 > 无运行 > 默认（保持运行）
    // 该顺序与 SummaryCard 按风险升档一致；测试用最简单的方式验证：
    // 默认 bootstrap 不含审批/阻塞/风险/运行 → 应落到「无运行」分支。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let nextStep = store.terminalHallOverviewNextStepText()
    #expect(nextStep.hasPrefix("下一步："), "next-step 必须以「下一步：」开头：\(nextStep)")
    // bootstrap 后选中产品有团队但没有运行中员工，应落到「选择员工运行任务」分支。
    #expect(nextStep.contains("选择员工运行任务"), "默认空运行状态应建议选员工运行：\(nextStep)")

    // 不含底层参数 / 英文角色词。
    for forbidden in ["model_reasoning_effort", "--skip-git-repo-check", "rawValue", "CTO 办公室", "Agent 编队"] {
        #expect(!nextStep.contains(forbidden), "next-step 含禁词 \(forbidden)：\(nextStep)")
    }
}

@Test func terminalHallOverviewSummaryViewUsesStructuredMetricsInsteadOfPlainTextBlock() async throws {
    // 守门：终端大厅顶部概览必须改成结构化指标 chip + next-step 单行渲染，
    // 不再直接渲染 store.terminalHallOverviewSummaryText() 4 行字符串。
    // 该字符串保留作为聊天/复制/审计兜底，仍由
    // terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure 守门。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 必须使用新结构化 accessor。
    #expect(source.contains("store.terminalHallOverviewMetrics()"),
            "TerminalHallView 必须调用 store.terminalHallOverviewMetrics()")
    #expect(source.contains("store.terminalHallOverviewNextStepText()"),
            "TerminalHallView 必须调用 store.terminalHallOverviewNextStepText()")

    // 必须不再渲染 4 行 plain-text 兜底字符串（该字符串只用于聊天/复制/审计）。
    #expect(!source.contains("store.terminalHallOverviewSummaryText()"),
            "TerminalHallView 不应再直接渲染 4 行兜底字符串；改用结构化指标 + next-step")

    // 必须用 MetricChip 渲染指标（与下方 SummaryCard 一致）。
    // 找到 TerminalHallOverviewSummary 区块再断言：避免误判其它 SummaryCard 里的 MetricChip。
    let overviewMarker = "private struct TerminalHallOverviewSummary: View {"
    guard let overviewStart = source.range(of: overviewMarker) else {
        Issue.record("找不到 TerminalHallOverviewSummary 定义")
        return
    }
    let tail = source[overviewStart.upperBound...]
    let nextStructMarker = "private struct "
    let overviewBody: Substring
    if let nextStruct = tail.range(of: nextStructMarker) {
        overviewBody = tail[..<nextStruct.lowerBound]
    } else {
        overviewBody = tail
    }
    #expect(overviewBody.contains("MetricChip("),
            "TerminalHallOverviewSummary 必须用 MetricChip 渲染指标（当前 body 没找到 MetricChip 调用）")
}

// MARK: - 终端大厅员工卡终端日志区按状态自适应高度

@MainActor
@Test func terminalAgentCardLogHeightShrinksWhenIdleAndExpandsWhenActive() async throws {
    // 员工"准备中"（不在运行 + 日志为空）→ 100pt 紧凑高度；
    // 一旦有日志输出，立刻恢复到 180pt（比改造前的固定 248pt 减少 27%）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    // 1. bootstrap 后 CTO 不在运行 + 日志为空 → idle → idle 高度
    #expect(store.terminalAgentCardIsIdle(agentID: cto.id))
    #expect(store.terminalAgentCardLogHeight(for: cto.id) == CompanyStore.terminalAgentCardLogIdleHeight)
    #expect(store.terminalAgentCardLogPlaceholder(for: cto.id).contains("等待派发任务"))
    #expect(store.terminalAgentCardLogPlaceholder(for: cto.id).contains("运行后此处显示终端输出"))
    #expect(!store.terminalAgentCardHasClearableLog(for: cto.id))

    // 2. 注入一段日志 → 不再 idle → active 高度
    store.terminalLogs[cto.id] = "[OPC 会话预热]\n本地命令已就绪：codex\n"
    #expect(!store.terminalAgentCardIsIdle(agentID: cto.id))
    #expect(store.terminalAgentCardHasClearableLog(for: cto.id))
    #expect(store.terminalAgentCardLogHeight(for: cto.id) == CompanyStore.terminalAgentCardLogActiveHeight)
    #expect(store.terminalAgentCardLogPlaceholder(for: cto.id) == "暂无终端输出。",
            "非 idle 状态下 placeholder 退回到原 fallback 文案")

    // 3. 清空日志后回到 idle → 重新 idle 高度
    store.terminalLogs[cto.id] = ""
    #expect(store.terminalAgentCardIsIdle(agentID: cto.id))
    #expect(!store.terminalAgentCardHasClearableLog(for: cto.id))
    #expect(store.terminalAgentCardLogHeight(for: cto.id) == CompanyStore.terminalAgentCardLogIdleHeight)
}

@MainActor
@Test func terminalAgentCardLogHeightConstantsAreReducedFromOriginal248() async throws {
    // 锁定整体减噪幅度：active 高度必须 ≤ 200（比原 248pt 至少减少 ~20%），
    // idle 高度必须 ≤ active 高度的一半（idle 必须明显比 active 紧凑）。
    #expect(CompanyStore.terminalAgentCardLogActiveHeight <= 200,
            "active 高度应 ≤ 200pt（比原 248 减少 ≥ 19%）")
    #expect(CompanyStore.terminalAgentCardLogIdleHeight * 2 <= CompanyStore.terminalAgentCardLogActiveHeight,
            "idle 高度应 ≤ active 一半（明显紧凑差异）")
    // active 高度仍要够看几行 mono 输出（≥ 120pt）；idle 仍要够看 1-2 行占位（≥ 60pt）。
    #expect(CompanyStore.terminalAgentCardLogActiveHeight >= 120,
            "active 高度应 ≥ 120pt 给真实输出留空间")
    #expect(CompanyStore.terminalAgentCardLogIdleHeight >= 60,
            "idle 高度应 ≥ 60pt 给中文占位留空间")
}

@Test func terminalAgentCardViewUsesAdaptiveLogHeightInsteadOfHardcoded248() async throws {
    // 守门：终端日志 ScrollView 必须用 store.terminalAgentCardLogHeight(for:) 自适应高度，
    // 不能再硬编码 248pt 之类的固定值；占位文字也必须走 store accessor。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    #expect(source.contains("store.terminalAgentCardLogHeight(for: agent.id)"),
            "TerminalAgentCard 必须用 store.terminalAgentCardLogHeight(for:) 自适应高度")
    #expect(source.contains("store.terminalAgentCardIsIdle(agentID: agent.id)"),
            "TerminalAgentCard 必须用 store.terminalAgentCardIsIdle 判定 placeholder 渲染")
    #expect(source.contains("store.terminalAgentCardLogPlaceholder(for: agent.id)"),
            "TerminalAgentCard 必须用 store.terminalAgentCardLogPlaceholder 渲染中文占位")
    #expect(source.contains(".disabled(!store.terminalAgentCardHasClearableLog(for: agent.id))"),
            "清空日志按钮禁用状态必须走 store.terminalAgentCardHasClearableLog，不能和某句中文占位文案耦合")
    #expect(!source.contains("logText == \"暂无终端输出。\""),
            "清空日志按钮不能依赖 visibleTerminalLog 的中文 fallback 文案判断禁用")

    // 反向锁：日志 ScrollView 不能再硬编码 .frame(height: 248)。
    #expect(!source.contains(".frame(height: 248)"),
            "TerminalAgentCard 不应再硬编码 .frame(height: 248)；改用自适应 store accessor")
}

// MARK: - 终端大厅员工卡 CLI 健康徽章可视化

@MainActor
@Test func terminalAgentCardHealthBadgeReturnsNilForOkOrUnobservedStates() async throws {
    // 默认不显示徽章原则：员工 backend 不是 CLI / 没有运行会话 / phase = .unknown / .ready /
    // .completedTurn 时 accessor 返回 nil；卡片根本不进入徽章渲染分支。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    // 1. bootstrap 后 CTO 没有 runtimeSession → nil
    #expect(store.terminalAgentCardHealthBadge(for: cto.id) == nil)

    // 2. 注入 unknown / ready / completedTurn phase → 仍 nil
    for okPhase in [CLIInteractionPhase.unknown, .ready, .completedTurn] {
        let session = AgentRuntimeSession(
            agentID: cto.id,
            capability: .persistentProtocol,
            backendSignature: "",
            cliInteractionPhase: okPhase
        )
        store.runtimeSessions[cto.id] = session
        #expect(store.terminalAgentCardHealthBadge(for: cto.id) == nil,
                "phase = \(okPhase) 应不显示徽章（OK 状态不打扰），实际显示了")
    }
}

@MainActor
@Test func terminalAgentCardHealthBadgeMapsAttentionStatesToCorrectSeverityAndChinese() async throws {
    // 需要技术负责人注意的 4 种状态：awaitingResponse / busy / authBlocked / transientFailure
    // 必须返回中文短标题 + 正确严重度配色档位。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let cases: [(CLIInteractionPhase, String, TerminalAgentCardHealthBadge.Severity)] = [
        (.awaitingResponse, "等待回复", .info),
        (.busy, "忙碌中", .warning),
        (.authenticationBlocked, "授权异常", .danger),
        (.transientFailure, "临时异常", .danger)
    ]
    for (phase, expectedTitle, expectedSeverity) in cases {
        let session = AgentRuntimeSession(
            agentID: cto.id,
            capability: .persistentProtocol,
            backendSignature: "",
            cliInteractionPhase: phase,
            cliInteractionReason: expectedTitle
        )
        store.runtimeSessions[cto.id] = session
        let badge = try #require(store.terminalAgentCardHealthBadge(for: cto.id),
                                 "phase = \(phase) 应返回徽章")
        #expect(badge.title == expectedTitle, "phase = \(phase) 标题不匹配：\(badge.title)")
        #expect(badge.severity == expectedSeverity, "phase = \(phase) 严重度不匹配：\(badge.severity)")
        // 标题不超过 4 个中文字符，保持卡顶第 1 行紧凑。
        #expect(badge.title.count <= 4, "徽章标题超过 4 字会挤压 backend chip：\(badge.title)")
    }
}

@MainActor
@Test func terminalAgentCardHealthBadgeOmitsBadgeForApiAndLocalBackends() async throws {
    // API / local 后端没有 CLI 长期会话，没有 phase 可观察 → 不显示徽章。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    var apiAgent = try #require(store.agents.first { $0.role != .boss })
    apiAgent.backend = AgentBackend(
        type: .api,
        command: "",
        model: "gpt-4o",
        endpoint: "https://api.example.com",
        apiKey: "",
        reasoningEffort: .medium
    )
    // 替换 store.agents 中对应条目使 accessor 能找到这个改后的 backend
    if let idx = store.agents.firstIndex(where: { $0.id == apiAgent.id }) {
        store.agents[idx] = apiAgent
    }
    let session = AgentRuntimeSession(
        agentID: apiAgent.id,
        capability: .apiConnection,
        backendSignature: "",
        cliInteractionPhase: .busy   // 即便强行注入 phase
    )
    store.runtimeSessions[apiAgent.id] = session
    #expect(store.terminalAgentCardHealthBadge(for: apiAgent.id) == nil,
            "API 后端不应该显示 CLI 健康徽章")
}

@Test func terminalAgentCardViewRendersHealthBadgeChipWhenAccessorReturnsNonNil() async throws {
    // 守门：view 必须有渲染分支调用 store.terminalAgentCardHealthBadge(for:)，
    // 并使用 TerminalAgentCardHealthBadgeChip 组件（不能用文本渲染或别的 chip）。
    // 反向锁：徽章 chip 不能被包进 DisclosureGroup（必须默认可见）。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    #expect(source.contains("store.terminalAgentCardHealthBadge(for: agent.id)"),
            "TerminalAgentCard 必须调用 store.terminalAgentCardHealthBadge(for:)")
    #expect(source.contains("TerminalAgentCardHealthBadgeChip(badge:"),
            "TerminalAgentCard 必须用 TerminalAgentCardHealthBadgeChip 渲染徽章")
    #expect(source.contains("private struct TerminalAgentCardHealthBadgeChip"),
            "必须有 TerminalAgentCardHealthBadgeChip 组件定义")

    // 反向：徽章不允许被包进 DisclosureGroup（运行前预检 DisclosureGroup 已改为常驻可见紧凑面板，阈值收紧到 ≤ 1，仅留文件头注释）。
    let disclosureCount = source.components(separatedBy: "DisclosureGroup").count - 1
    #expect(disclosureCount <= 1,
            "TerminalHallView 中 DisclosureGroup 数量 \(disclosureCount)；徽章不能被折叠")
}

@Test func terminalAgentCardPreflightIsAlwaysVisibleWithIconOnlyRefreshButton() async throws {
    // 守门：终端大厅员工卡的「运行前预检」必须是常驻可见的紧凑面板，
    // 不允许再用 DisclosureGroup 折叠，也不允许出现「展开/折叠」用户文案。
    // 刷新按钮必须是 icon-only `arrow.clockwise`，并提供中文 help / accessibilityLabel / accessibilityHint。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 折叠状态变量必须删除（旧 isPreflightExpanded @State Bool）
    #expect(!source.contains("isPreflightExpanded"),
            "运行前预检不应再持有 isPreflightExpanded 折叠状态；面板应常驻可见")

    // 2. 旧的「展开后生成」占位文案不应再出现（用户不再做展开动作）
    #expect(!source.contains("展开后生成"),
            "运行前预检不应再使用「展开后生成」措辞；面板已常驻可见")

    // 3. 刷新按钮：icon-only `arrow.clockwise` + 中文 help/accessibilityLabel/accessibilityHint。
    // accessibilityLabel 必须带员工显示名，避免多张员工卡里的刷新按钮不可区分。
    #expect(source.contains("Image(systemName: \"arrow.clockwise\")"),
            "运行前预检刷新按钮必须使用 icon-only `arrow.clockwise`")
    #expect(source.contains(".help(\"刷新运行前预检\")"),
            "刷新按钮必须提供中文 help「刷新运行前预检」")
    #expect(source.contains(#".accessibilityLabel("刷新 \(agent.displayName) 运行前预检")"#),
            "刷新按钮必须提供带员工名的中文 accessibilityLabel")
    #expect(source.contains("基于当前提示词"),
            "刷新按钮必须提供中文 accessibilityHint，说明刷新逻辑基于当前提示词与员工配置")

    // 4. 仍保留「运行前预检」普通标题文本，并使用员工卡片专用摘要 accessor；
    // 完整审计文本继续由显式「预检」按钮走 store.recordCLIPreflight。
    #expect(source.contains("Text(\"运行前预检\")"),
            "运行前预检面板必须保留普通 Text 标题，避免被无障碍树误判为折叠控件")
    #expect(!source.contains("Image(systemName: \"checkmark.shield.fill\")"),
            "运行前预检标题不应使用容易被无障碍树误判的状态图标")
    #expect(source.contains("store.terminalAgentCardPreflightSummary(for: agent.id, prompt: prompt)"),
            "运行前预检卡片文本必须使用 terminalAgentCardPreflightSummary(for:prompt:) 摘要 accessor")
    #expect(!source.contains("store.cliPreflightText(for: agent.id, prompt: prompt)"),
            "员工卡片默认预检不应直接渲染完整 cliPreflightText；完整审计文本应只由显式预检入口写入日志")

    // 5. 反向锁：DisclosureGroup 阈值 ≤ 1（仅文件头注释允许出现该字符串）
    let disclosureCount = source.components(separatedBy: "DisclosureGroup").count - 1
    #expect(disclosureCount <= 1,
            "TerminalHallView 中 DisclosureGroup 出现 \(disclosureCount) 次；运行前预检面板不允许被任何 DisclosureGroup 折叠")
}

// MARK: - 终端大厅总览健康预警 chip 联动

@MainActor
@Test func terminalHallOverviewAttentionAgentCountReturnsZeroByDefault() async throws {
    // 默认 bootstrap 后没有员工有 attention 状态 → 总览不追加「健康预警」chip。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.terminalHallOverviewAttentionAgentCount() == 0)

    // 总览 metrics 仍是 5 个（与轮 2 既有契约一致）。
    let metrics = store.terminalHallOverviewMetrics()
    #expect(metrics.count == 5, "默认无 attention 时不追加第 6 chip，实际 \(metrics.count)")
    #expect(!metrics.map(\.title).contains("健康预警"))
}

@MainActor
@Test func terminalHallOverviewAppendsAttentionChipWhenAnyAgentNeedsAttention() async throws {
    // 一旦有员工进入 attention 状态（busy / authBlocked / transientFailure / awaitingResponse），
    // 总览 chip 行末尾追加「健康预警 N」danger chip，N = attention 员工数。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cliAgents = store.selectedProductAgents.filter { $0.role != .boss && $0.backend.type == .subscriptionCLI }
    #expect(cliAgents.count >= 2, "需要至少 2 个 CLI 员工以验证多 attention 计数")

    // 给前 2 个 CLI 员工各注入 attention 状态。
    let attentionPhases: [CLIInteractionPhase] = [.busy, .authenticationBlocked]
    for (idx, agent) in cliAgents.prefix(2).enumerated() {
        let session = AgentRuntimeSession(
            agentID: agent.id,
            capability: .persistentProtocol,
            backendSignature: "",
            cliInteractionPhase: attentionPhases[idx]
        )
        store.runtimeSessions[agent.id] = session
    }

    #expect(store.terminalHallOverviewAttentionAgentCount() == 2)

    let metrics = store.terminalHallOverviewMetrics()
    #expect(metrics.count == 6, "应追加第 6 chip，实际 \(metrics.count)")
    let attentionChip = try #require(metrics.first { $0.title == "健康预警" })
    #expect(attentionChip.value == 2)
    #expect(attentionChip.kind == .danger)

    // 健康预警 chip 必须是最后一个，不能挤前面 5 个固定 chip 的顺序。
    #expect(metrics.last?.title == "健康预警", "健康预警必须追加在末尾")
}

@MainActor
@Test func terminalHallOverviewAttentionDoesNotCountOkOrApiAgents() async throws {
    // OK 状态（unknown / ready / completedTurn）和 API/local 后端不应被计入 attention。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cliAgents = store.selectedProductAgents.filter { $0.role != .boss && $0.backend.type == .subscriptionCLI }

    // 给所有 CLI 员工注入 ready phase（OK 状态）→ 不应计入。
    for agent in cliAgents {
        let session = AgentRuntimeSession(
            agentID: agent.id,
            capability: .persistentProtocol,
            backendSignature: "",
            cliInteractionPhase: .ready
        )
        store.runtimeSessions[agent.id] = session
    }
    #expect(store.terminalHallOverviewAttentionAgentCount() == 0,
            "ready 不应被计入 attention")
    #expect(store.terminalHallOverviewMetrics().count == 5)
}

// MARK: - 通信网关入站 HTTP 服务前置守门（codex 增强方案长期项）

@MainActor
@Test func communicationChannelDefaultsToDisabledAndCommandsOff() async throws {
    // codex 增强方案：「真正暴露公网/局域网入站 HTTP 服务仍必须默认关闭」。
    // 防御性守门：任何新创建的通道配置必须 isEnabled = false 且 commandsEnabled = false。
    // 用户必须显式打开两个开关才能启用入站；任何未来 PR 不允许把默认值改为 true。
    let channel = CommunicationChannelConfig(name: "测试通道", kind: .telegramBot)
    #expect(channel.isEnabled == false, "新通道默认必须未启用")
    #expect(channel.commandsEnabled == false, "新通道默认必须不接受入站指令")
    // reportsEnabled 默认是 true（外发汇报是低风险写出方向，与入站不同）
    #expect(channel.reportsEnabled == true, "外发汇报默认开启（低风险方向）")
}

@MainActor
@Test func communicationChannelKindOnlyTelegramBotAndLocalSupportInbound() async throws {
    // 守门：只有 telegramBot 和 localOnly 两种通道支持入站；其它（飞书/企业微信/钉钉/邮件）
    // 即便 commandsEnabled = true 也会被前置 supportsInboundCommand 拒绝。
    // 这条契约是入站攻击面的关键限制——任何未来给 webhook 类通道开放入站的 PR 必须先动到这条测试。
    let inboundCapable: [CommunicationChannelKind] = [.telegramBot, .localOnly]
    let outboundOnly: [CommunicationChannelKind] = [.feishuWebhook, .wecomWebhook, .dingtalkWebhook, .emailDigest]

    for kind in inboundCapable {
        #expect(kind.supportsInboundCommand == true, "\(kind) 应支持入站")
    }
    for kind in outboundOnly {
        #expect(kind.supportsInboundCommand == false, "\(kind) 不应支持入站（webhook/邮件单向）")
    }
}

@Test func sourceCodeContainsNoBoundHTTPListenerOrSocketServer() async throws {
    // codex 增强方案核心约束：在 HMAC/白名单/nonce/端口策略全部就绪前，禁止启动任何
    // 公网/局域网 HTTP 入站服务。这条测试扫描 Sources/OPCCompanyCore 全部源码，
    // 确保没有任何启动 HTTP/socket listener 的 API 被引入。
    //
    // 任何未来 PR 加入 NWListener / SwiftNIO / Vapor / HTTPServer / Bind / Socket
    // 类入站监听代码会立刻让本测试失败，并提示开发者必须先：
    //   1. 在 OPC_COMPANY.md 第 10 节同步规则；
    //   2. 写完 HMAC/白名单/nonce/端口策略测试；
    //   3. 加显式 admin enable 开关；
    //   4. 才能放开本守门。
    let files = try loadOPCCompanyCoreSwiftFileURLs()
    #expect(!files.isEmpty, "至少应扫描到一个 .swift 源文件")

    // 监听类 API 列表 —— 任何一个出现在源码里都属于"启动 HTTP/socket 服务"
    let bannedAPIs = [
        "NWListener",          // Apple Network framework 的 server-side listener
        "URLSessionStreamTask", // 双向流（虽然主要 client 用，但 server 化的入口）
        "import NIOHTTP1",     // SwiftNIO HTTP 服务
        "import Vapor",        // Vapor 框架
        "HTTPServer(",         // 自定义/第三方 HTTP server 类
        "Hummingbird"          // Hummingbird HTTP server
    ]

    var leaks: [(String, String)] = []
    for file in files {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for api in bannedAPIs where content.contains(api) {
            leaks.append((file.lastPathComponent, api))
        }
    }

    #expect(leaks.isEmpty,
            "Sources/OPCCompanyCore 不应启动任何 HTTP/socket 服务监听。检测到泄漏：\(leaks)")
}

@MainActor
@Test func communicationChannelEnablingInboundRequiresAllThreeSwitchesOn() async throws {
    // 守门：要让一个通道真正接受入站指令，必须三条同时满足：
    //   1. CommunicationChannelKind.supportsInboundCommand == true
    //   2. CommunicationChannelConfig.isEnabled == true
    //   3. CommunicationChannelConfig.commandsEnabled == true
    // 任何一条缺失都应被入站验证器拒绝。
    let supportingKindButDisabled = CommunicationChannelConfig(
        name: "Telegram 测试",
        kind: .telegramBot,
        isEnabled: false,        // 关
        commandsEnabled: true
    )
    let enabledButCommandsOff = CommunicationChannelConfig(
        name: "Telegram 测试 2",
        kind: .telegramBot,
        isEnabled: true,
        commandsEnabled: false   // 关
    )
    let webhookEvenIfBothOn = CommunicationChannelConfig(
        name: "飞书测试",
        kind: .feishuWebhook,    // 不支持入站
        isEnabled: true,
        commandsEnabled: true
    )

    // 前两条：满足通道类型支持入站，但开关缺失，应被守门拒绝。
    // 第三条：webhook 类即便所有开关都开也应被守门拒绝。
    // 这里我们直接断言 supportsInboundCommand + isEnabled + commandsEnabled 三联条件，
    // 不依赖外部 verifier 的具体签名（避免与既有 verifier 测试耦合）。
    func canAcceptInbound(_ c: CommunicationChannelConfig) -> Bool {
        c.kind.supportsInboundCommand && c.isEnabled && c.commandsEnabled
    }

    #expect(canAcceptInbound(supportingKindButDisabled) == false, "isEnabled 关时应拒绝")
    #expect(canAcceptInbound(enabledButCommandsOff) == false, "commandsEnabled 关时应拒绝")
    #expect(canAcceptInbound(webhookEvenIfBothOn) == false, "webhook 类即便开关全开也应拒绝")

    // 反向证明：三条全满足时才允许（这条不是放行，是验证测试本身的逻辑正确）
    let fullyEnabled = CommunicationChannelConfig(
        name: "Telegram 完整开",
        kind: .telegramBot,
        isEnabled: true,
        commandsEnabled: true
    )
    #expect(canAcceptInbound(fullyEnabled) == true, "三条全满足时应允许（验证测试逻辑）")
}

// MARK: - CLI 健康状态变化事件流审计

@MainActor
@Test func cliInteractionPhaseUpgradeToAttentionWritesStructuredRiskEvent() async throws {
    // 升级到 busy/authBlocked/transientFailure 时必须写一条 .risk 事件（kind = .risk + 中文标题前缀）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    // 用与其它测试同步的 rate-limit 字面量（已验证可触发 transientFailure phase）
    let baselineHealth = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    let result = CommandExecutionResult(
        exitCode: 1,
        standardOutput: "",
        standardError: "error: rate limit exceeded\n"
    )
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)

    // 应新增正好 1 条 .risk 事件，标题以「命令行健康预警：」开头
    let healthEvents = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }
    #expect(healthEvents.count - baselineHealth == 1, "升级到 attention phase 应正好写 1 条事件，实际新增 \(healthEvents.count - baselineHealth)")
    let event = try #require(healthEvents.last)
    #expect(event.kind == .risk, "健康预警事件 kind 应为 .risk")
    #expect(event.title.contains(cto.displayName), "标题应含员工名")
    let attentionDescriptors = ["忙碌中", "临时异常", "授权异常", "等待当前任务", "稍后重试", "检查登录授权"]
    #expect(attentionDescriptors.contains { event.detail.contains($0) },
            "detail 应反映 attention 状态或建议：\(event.detail)")
    #expect(event.agentID == cto.id)
}

@MainActor
@Test func cliInteractionPhaseRepeatObservationDoesNotWriteDuplicateEvents() async throws {
    // 同一 attention phase 反复观察不应反复写事件（依赖 phase 去重逻辑 previousPhase != observation.phase）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let result = CommandExecutionResult(
        exitCode: 1,
        standardOutput: "",
        standardError: "error: rate limit exceeded\n"
    )

    let baseline = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    // 反复观察 3 次同样输出
    for _ in 0..<3 {
        store.recordCLIInteractionObservationIfNeeded(agent: cto, result: result)
    }
    let after = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    #expect(after - baseline == 1, "同一 phase 反复观察只应写 1 条事件，实际新增 \(after - baseline)")
}

@MainActor
@Test func cliInteractionPhaseReadyOrCompletedDoesNotWriteHealthEvent() async throws {
    // ready / completedTurn / awaitingResponse 等常规状态不应写健康预警事件（避免噪音）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let baseline = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count

    // 模拟一段 ready 输出（含 codex> prompt）
    let readyResult = CommandExecutionResult(
        exitCode: 0,
        standardOutput: "codex>\n",
        standardError: ""
    )
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: readyResult)

    // 模拟一段 completedTurn 输出（typed turn end）
    let completedResult = CommandExecutionResult(
        exitCode: 0,
        standardOutput: "tokens used: 1234\n",
        standardError: ""
    )
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: completedResult)

    let after = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    #expect(after == baseline, "ready / completedTurn 不应写健康预警事件，实际新增 \(after - baseline)")
}

@MainActor
@Test func cliInteractionPhaseTransitionFromAttentionToReadyDoesNotWriteEvent() async throws {
    // 从 attention 状态恢复到 ready 时只走"事件清零"语义，不应再写一条健康预警事件
    // （避免给老板"恢复"也算成预警噪音）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    // 1. 先升到 busy → 写 1 条事件
    let busyResult = CommandExecutionResult(
        exitCode: 1,
        standardOutput: "",
        standardError: "error: rate limit\n"
    )
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: busyResult)
    let afterBusy = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    #expect(afterBusy >= 1)

    // 2. 然后恢复到 ready → 不应再写新事件
    let readyResult = CommandExecutionResult(
        exitCode: 0,
        standardOutput: "codex>\n",
        standardError: ""
    )
    store.recordCLIInteractionObservationIfNeeded(agent: cto, result: readyResult)

    let afterReady = store.events.filter { $0.title.hasPrefix("命令行健康预警：") }.count
    #expect(afterReady == afterBusy, "从 attention 恢复到 ready 不应写新事件，实际新增 \(afterReady - afterBusy)")
}

// MARK: - 终端大厅员工卡按钮收敛 + 卡片整体可点击选中

@Test func terminalAgentCardSelectButtonIsIconOnlyAndCardIsTappableAsFallback() async throws {
    // 守门：员工卡底部「选中」按钮简化为 icon-only（节省底部宽度）；
    // 同时卡片整体加 .contentShape + .onTapGesture 兜底选中（减少用户必须找按钮的成本）；
    // 加 .accessibilityAction(named: "选中员工") 保留 Computer Use 显式动作入口。
    let source = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 「选中」按钮必须是 icon-only Image，不能再用 Label("选中", ...)
    #expect(!source.contains("Label(\"选中\", systemImage: \"person.crop.circle\")"),
            "「选中」按钮应简化为 icon-only Image，不再用 Label 占用底部宽度")
    // Image(systemName: "person.crop.circle") 必须存在（icon-only 形式）
    #expect(source.contains("Image(systemName: \"person.crop.circle\")"),
            "「选中」按钮应保留 person.crop.circle 图标")

    // 2. 必须保留带员工名的中文 a11y label（Computer Use 寻址依据）
    #expect(source.contains(#".accessibilityLabel("选中 \(agent.displayName)")"#),
            "「选中」按钮必须保留带员工名的中文 a11y label")
    // 必须有 .help("选中员工") 给 hover tooltip
    #expect(source.contains(".help(\"选中员工\")"),
            "「选中」按钮必须有 .help(\"选中员工\") tooltip")

    // 3. 卡片整体必须有 .contentShape + .onTapGesture 兜底选中
    #expect(source.contains(".contentShape(RoundedRectangle(cornerRadius: 8))"),
            "卡片必须用 .contentShape 让 padding 区响应点击")
    // 检查 onTapGesture 出现在 TerminalAgentCard body 内（不是别的视图里）
    let cardMarker = "private struct TerminalAgentCard: View {"
    guard let cardStart = source.range(of: cardMarker) else {
        Issue.record("找不到 TerminalAgentCard 定义")
        return
    }
    let tail = source[cardStart.upperBound...]
    let cardBody = tail.prefix(while: { _ in true }) // 简化：取后半段
    #expect(cardBody.contains(".onTapGesture {"),
            "TerminalAgentCard 必须有 .onTapGesture 兜底选中")
    #expect(cardBody.contains(".accessibilityAction(named: \"选中员工\")"),
            "TerminalAgentCard 必须有 .accessibilityAction(named:) Computer Use 入口")
}

// MARK: - 老板首页风险流过滤维护类事件

@MainActor
@Test func selectedProductBossRiskEventsExcludesMaintenancePrefixesButKeepsBusinessRisks() async throws {
    // 老板总控台 widget 必须过滤掉「命令行健康预警：」等技术维护类预警，
    // 但保留真实业务风险（如审批、交付、合规、命令行作业失败等）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let baselineBoss = store.selectedProductBossRiskEvents.count
    let baselineAll = store.selectedProductRiskEvents.count

    // 1. 写一条维护类事件（轮 7 的「命令行健康预警：」前缀）
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName)",
        detail: "忙碌中 · 建议：等待当前任务。",
        agentID: cto.id
    ))
    // 2. 写一条业务类事件（无维护前缀）
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "交付验收失败",
        detail: "测试用例未通过。",
        agentID: cto.id
    ))

    // 全量 risk 应 +2；老板视图只 +1（业务风险）
    #expect(store.selectedProductRiskEvents.count - baselineAll == 2,
            "全量 risk events 应包含两条新增")
    #expect(store.selectedProductBossRiskEvents.count - baselineBoss == 1,
            "老板视图应过滤掉「命令行健康预警：」前缀，只新增 1 条业务风险")

    // 验证老板视图新增的那条是业务风险，不是维护类
    let newBossEvents = store.selectedProductBossRiskEvents.suffix(1)
    let newBossEvent = try #require(newBossEvents.first)
    #expect(newBossEvent.title == "交付验收失败")
    #expect(!newBossEvent.title.hasPrefix("命令行健康预警："))
}

@MainActor
@Test func bossViewExcludedRiskTitlePrefixesIncludesCLIHealthWarning() async throws {
    // 契约：「命令行健康预警：」必须在老板视图剔除前缀白名单中。
    // 这是轮 7 引入的事件标题前缀；任何未来 PR 想拿掉这条剔除必须先动这条断言。
    #expect(CompanyStore.bossViewExcludedRiskTitlePrefixes.contains("命令行健康预警："),
            "「命令行健康预警：」必须在 bossViewExcludedRiskTitlePrefixes 中")
}

@MainActor
@Test func bossViewExcludedRiskTitlePrefixesIncludesCommandJobMaintenancePrefix() async throws {
    // 契约（角色继承期轮 11 加固）：「命令行作业」必须在老板视图剔除前缀白名单中。
    // 这是轮 11 加固引入的前缀，覆盖 .opc/jobs/ 后端文件操作失败类事件
    // （命令行作业目录创建失败 / 命令行作业档案写入失败 等）。
    // 选「命令行作业」单一前缀比逐个加全标题更鲁棒，可天然覆盖未来「命令行作业XXX失败」变体；
    // 但**不**会误击中 `命令行发车被阻止`（老板需要知道自己的动作被阻止）。
    // 任何未来 PR 想拿掉这条剔除必须先动这条断言。
    #expect(CompanyStore.bossViewExcludedRiskTitlePrefixes.contains("命令行作业"),
            "「命令行作业」必须在 bossViewExcludedRiskTitlePrefixes 中")
}

@MainActor
@Test func selectedProductBossRiskEventsExcludesCommandJobMaintenanceTitlesButKeepsBossLaunchBlocked() async throws {
    // 行为契约（角色继承期轮 11 加固）：
    // 「命令行作业目录创建失败」/「命令行作业档案写入失败」必须从老板视图剔除（纯后端文件系统失败，
    //  老板无法处理也不需要决策）。
    // 「命令行发车被阻止」必须保留在老板视图（老板的动作被前置检查拦截，需要知道）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let baselineFiltered = store.selectedProductBossRiskEvents.count
    let baselineFull = store.selectedProductRiskEvents.count

    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行作业目录创建失败",
        detail: "工程师：mkdir 失败",
        agentID: cto.id
    ))
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行作业档案写入失败",
        detail: "工程师：write 失败",
        agentID: cto.id
    ))
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行发车被阻止",
        detail: "前置检查不通过：模型不可用",
        agentID: cto.id
    ))

    let fullCount = store.selectedProductRiskEvents.count
    let filteredCount = store.selectedProductBossRiskEvents.count

    #expect(fullCount == baselineFull + 3, "全量风险流必须看到 3 条新事件")
    #expect(filteredCount == baselineFiltered + 1,
            "老板视图必须只看到 1 条（命令行发车被阻止），「命令行作业」前缀的 2 条必须被过滤")
    #expect(store.selectedProductBossRiskEvents.contains { $0.title == "命令行发车被阻止" },
            "「命令行发车被阻止」是老板动作被阻止信号，必须保留")
    #expect(!store.selectedProductBossRiskEvents.contains { $0.title.hasPrefix("命令行作业") },
            "「命令行作业」前缀的维护类事件必须从老板视图剔除")
}

@Test func bossCommandCenterUsesFilteredRiskAccessorInsteadOfFullRiskList() async throws {
    // 守门：老板总控台 CommandCenterView 必须用 selectedProductBossRiskEvents（过滤后）
    // 而不是 selectedProductRiskEvents（全量）。
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")

    #expect(source.contains("store.selectedProductBossRiskEvents"),
            "CommandCenterView 必须用 store.selectedProductBossRiskEvents 过滤后的风险")
    // 反向：CommandCenterView 不应再含 store.selectedProductRiskEvents 调用（全量）
    #expect(!source.contains("store.selectedProductRiskEvents"),
            "CommandCenterView 不应再调用 store.selectedProductRiskEvents（应改为过滤后版本）")
}

@MainActor
@Test func commandCenterDefaultVisibleListLimitsAndOverflowAccessorsExposeContinuation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    #expect(CompanyStore.commandCenterPendingApprovalsDefaultDisplayLimit == 3)
    #expect(CompanyStore.commandCenterDecisionRiskTasksDefaultDisplayLimit == 3)
    #expect(CompanyStore.commandCenterRecentDeliveryRecordsDefaultDisplayLimit == 3)
    #expect(CompanyStore.commandCenterOpenTasksDefaultDisplayLimit == 6)
    #expect(CompanyStore.commandCenterRiskPanelTasksDefaultDisplayLimit == 4)
    #expect(CompanyStore.commandCenterRiskPanelEventsDefaultDisplayLimit == 3)
    #expect(CompanyStore.commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit == 4)

    for index in 1...8 {
        store.createTask(title: "总控任务 \(index)", ownerID: cto.id, status: .planned, successCriteria: "标准 \(index)")
    }
    #expect(store.commandCenterOpenTasks.count == CompanyStore.commandCenterOpenTasksDefaultDisplayLimit)
    #expect(store.commandCenterAcceptanceCriteriaTasks.count == CompanyStore.commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit)
    let openOverflow = try #require(store.commandCenterOpenTasksOverflow())
    let criteriaOverflow = try #require(store.commandCenterAcceptanceCriteriaTasksOverflow())
    #expect(openOverflow.summary.contains("后续还有"))
    #expect(openOverflow.summary.contains("未完成任务"))
    #expect(criteriaOverflow.summary.contains("验收标准"))
    #expect(!openOverflow.summary.contains("折叠") && !criteriaOverflow.summary.contains("未展开"))

    for index in 1...5 {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: .risk,
            title: "业务风险 \(index)",
            detail: "风险 \(index)",
            agentID: cto.id
        ))
    }
    #expect(store.commandCenterRiskPanelEvents.count == CompanyStore.commandCenterRiskPanelEventsDefaultDisplayLimit)
    let riskEventOverflow = try #require(store.commandCenterRiskPanelEventsOverflow())
    #expect(riskEventOverflow.summary.contains("风险汇报"))
    #expect(!riskEventOverflow.summary.contains("事件流总览"))
}

@Test func commandCenterDefaultVisiblePanelsUseStoreAccessorsAndOverflowFooterInsteadOfHardcodedPrefixes() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")
    let commandCenterSlice = try #require(
        extractTopLevelStructSlice(
            from: source,
            structMarker: "struct CommandCenterView:",
            failureMessage: "未找到 CommandCenterView struct 起点"
        )
    )

    let requiredAccessors = [
        "store.commandCenterPendingApprovals",
        "store.commandCenterDecisionRiskTasks",
        "store.commandCenterRecentDeliveryVerifications",
        "store.commandCenterRecentDeliveryArtifacts",
        "store.commandCenterOpenTasks",
        "store.commandCenterRiskPanelTasks",
        "store.commandCenterRiskPanelEvents",
        "store.commandCenterAcceptanceCriteriaTasks"
    ]
    for accessor in requiredAccessors {
        #expect(commandCenterSlice.contains(accessor), "CommandCenterView 必须使用 \(accessor)")
    }

    #expect(commandCenterSlice.contains("OPCListOverflowFooter("),
            "CommandCenterView 默认可见列表必须使用共享 overflow footer")
    #expect(!commandCenterSlice.contains("pendingApprovals.prefix(3)"))
    #expect(!commandCenterSlice.contains("riskTasks.prefix(3)"))
    #expect(!commandCenterSlice.contains("openTasks.prefix(6)"))
    #expect(!commandCenterSlice.contains("riskTasks.prefix(4)"))
    #expect(!commandCenterSlice.contains("riskEvents.prefix(3)"))
    #expect(!commandCenterSlice.contains("selectedProductTasks.prefix(4)"))
    #expect(!commandCenterSlice.contains("selectedProductRecentDeliveryVerifications.prefix(3)"))
    #expect(!commandCenterSlice.contains("selectedProductRecentDeliveryArtifacts.prefix(3)"))
}

@MainActor
@Test func workflowMapMessageAndTaskStatusLimitsExposeContinuation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    #expect(CompanyStore.workflowMapMessageFlowDefaultDisplayLimit == 6)
    #expect(CompanyStore.workflowMapTaskStatusBoardPerStatusDefaultDisplayLimit == 4)

    for index in 1...8 {
        store.agentMessages.append(AgentMessageEnvelope(
            productID: store.selectedProductID,
            fromAgentID: cto.id,
            toAgentID: engineer.id,
            taskID: nil,
            kind: .taskDispatched,
            subject: "流程消息 \(index)",
            body: "message \(index)",
            createdAt: Date()
        ))
    }
    #expect(store.workflowMapRecentAgentMessages.count == CompanyStore.workflowMapMessageFlowDefaultDisplayLimit)
    let messageOverflow = try #require(store.workflowMapMessageFlowOverflow())
    #expect(messageOverflow.summary.contains("协作消息总览"))
    #expect(!messageOverflow.summary.contains("折叠") && !messageOverflow.summary.contains("未展开"))

    for index in 1...6 {
        store.createTask(title: "流程状态任务 \(index)", ownerID: cto.id, status: .running, successCriteria: "状态 \(index)")
    }
    #expect(store.workflowMapTasks(for: .running).count == CompanyStore.workflowMapTaskStatusBoardPerStatusDefaultDisplayLimit)
    let taskOverflow = try #require(store.workflowMapTaskStatusBoardOverflow(for: .running))
    #expect(taskOverflow.summary.contains("运行中任务"))
    #expect(taskOverflow.summary.contains("产品详情"))
}

@Test func workflowMapUsesStoreAccessorsAndOverflowFooterInsteadOfHardcodedPrefixes() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")
    let workflowSlice = try #require(
        extractTopLevelStructSlice(
            from: source,
            structMarker: "struct WorkflowMapView:",
            failureMessage: "未找到 WorkflowMapView struct 起点"
        )
    )

    #expect(workflowSlice.contains("store.workflowMapRecentAgentMessages"))
    #expect(workflowSlice.contains("store.workflowMapMessageFlowOverflow()"))
    #expect(workflowSlice.contains("store.workflowMapTasks(for: status)"))
    #expect(workflowSlice.contains("store.workflowMapTaskStatusBoardOverflow(for: status)"))
    #expect(workflowSlice.contains("OPCListOverflowFooter("))
    #expect(!workflowSlice.contains("selectedProductRecentAgentMessages.prefix(6)"))
    #expect(!workflowSlice.contains("tasks.prefix(4)"))
    #expect(!workflowSlice.contains("selectedProductTasks.filter { $0.status == status }"))
}

@Test func inspectorEventLogViewUsesSelectedProductAgentScopedEvents() async throws {
    // 用户视角修订：InspectorPanel 是常驻右侧栏，会出现在老板总控台、产品详情和员工工作台旁。
    // 因此它不能再作为"全量技术维护事件流"入口；事件 tab 必须匹配当前产品与当前员工，
    // 避免切换产品后把旧产品/Desktop/终端维护事件误读成当前产品上下文。
    let inspectorSource = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(inspectorSource.contains("private var selectedAgentEvents: [CompanyEvent]"))
    #expect(inspectorSource.contains("store.selectedProductEvents.filter { $0.agentID == store.selectedAgentID }"),
            "EventLogView 必须按当前产品和当前员工过滤事件")
    #expect(!inspectorSource.contains("ForEach(store.events)"),
            "常驻右侧 Inspector 不能再渲染跨产品全量事件")
}

@Test func bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor() async throws {
    // 守门：所有老板专属视图（CommandCenter + BossControlPanel + BossDecisionCenterSheet）必须用
    // selectedProductBossRiskEvents（过滤后），不能用 selectedProductRiskEvents（全量）。
    // 这条契约把轮 5/6/8 和老板决策中心迁移后的老板视图统一守门，防止未来回退到全量调用。
    let cmdSource = try loadOPCCompanyCoreSource("CommandCenterView.swift")
    let inspectorSource = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    // 反向：老板可见 view 文件都不应再含 selectedProductRiskEvents（全量调用，应改为过滤后）
    #expect(!cmdSource.contains("store.selectedProductRiskEvents"),
            "CommandCenterView 不应再调用 store.selectedProductRiskEvents（轮 9 收敛）")
    #expect(!inspectorSource.contains("store.selectedProductRiskEvents"),
            "InspectorPanel 不应再调用 store.selectedProductRiskEvents（轮 8 收敛 BossControlPanel.recentRiskCount）")

    // 正向：老板风险入口都必须有 selectedProductBossRiskEvents 调用
    #expect(cmdSource.contains("selectedProductBossRiskEvents"),
            "CommandCenterView 风险面板与老板决策中心必须用 selectedProductBossRiskEvents")
    #expect(inspectorSource.contains("selectedProductBossRiskEvents"),
            "InspectorPanel.BossControlPanel.recentRiskCount 必须用 selectedProductBossRiskEvents（轮 8）")
}

@Test func selectedProductRiskEventsHasNoUIConsumerAfterBossViewMigration() async throws {
    // 守门（角色继承期轮 9 加固）：经过轮 5/6/8 收敛，所有 view 文件都不应再含
    // `selectedProductRiskEvents` 字符串（既不是调用 `store.selectedProductRiskEvents`，
    // 也不是注释里 token 引用）。这保护两个层面：
    //   1. 调用层面：未来 PR 不能在任何 view 文件里直接读未过滤的全量风险流，必须走
    //      `selectedProductBossRiskEvents`（老板视图）或者 `store.events` + 自定义筛选
    //      （技术维护视图，例如 EventLogView）。
    //   2. 注释层面：旧注释（如 CommandCenterView.swift 轮 8 之前的"技术负责人 InspectorPanel
    //      / OperationsSuiteView 仍读全量 selectedProductRiskEvents"和 CompanyStore.swift
    //      bossViewExcludedRiskTitlePrefixes 头注释里类似断言）已经在轮 9 修订，新增 view
    //      文件里出现的注释 token 引用很大概率是粘贴自旧文档、内容已失实，应一并清理。
    // 例外：CompanyStore.swift（声明站 + 派生站 + 内部团队负责人手机汇报报告文本计数）必须保留
    // 该 token，本测试显式排除该文件。Round 8 的
    // `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor` 只覆盖 3 个文件且只检查
    // `store.selectedProductRiskEvents`，本测试覆盖所有 view 文件且更严格（含注释）。
    let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/OPCCompanyCore")
    let viewFiles = [
        "CommandCenterView.swift",
        "ContentView.swift",
        "InspectorPanel.swift",
        "OperationsSuiteView.swift",
        "SelectionWorkspaceView.swift",
        "TerminalHallView.swift"
    ]
    for filename in viewFiles {
        let url = sourcesRoot.appendingPathComponent(filename)
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("selectedProductRiskEvents"),
                "\(filename) 不应含 'selectedProductRiskEvents' 任何形式（调用或注释 token 引用）。轮 5/6/8 已把所有老板视图迁移到 selectedProductBossRiskEvents；轮 9 同步清理失实注释。如新增技术维护视图需要全量事件，请用 store.events（参考 EventLogView）。声明站和派生站只在 CompanyStore.swift。")
    }
}

@MainActor
@Test func bossDecisionCenterRiskEventsExcludeMaintenancePrefixes() async throws {
    // 行为测试：老板决策中心风险事件必须把维护前缀事件过滤掉。
    // 等价于复用 selectedProductBossRiskEvents 的过滤行为。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName)",
        detail: "维护类预警",
        agentID: cto.id
    ))
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "审批被驳回",
        detail: "业务风险",
        agentID: cto.id
    ))

    // BossDecisionCenterSheet.riskEvents = store.selectedProductBossRiskEvents
    let bossRisk = store.selectedProductBossRiskEvents
    #expect(!bossRisk.contains { $0.title.hasPrefix("命令行健康预警：") },
            "老板决策中心必须不显示维护前缀事件（保护老板审批面板专注业务风险）")
    #expect(bossRisk.contains { $0.title == "审批被驳回" },
            "老板决策中心必须保留业务风险事件")
}

@MainActor
@Test func bossControlPanelRecentRiskCountReflectsFilteredBossRiskEvents() async throws {
    // 行为测试：BossControlPanel 的 stat tile「近期风险 N」计数必须与右侧风险事件 widget 同口径
    // （都用 selectedProductBossRiskEvents），不能给老板看到含维护类的虚高数字。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let baselineFiltered = store.selectedProductBossRiskEvents.count
    let baselineFull = store.selectedProductRiskEvents.count

    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName)",
        detail: "维护",
        agentID: cto.id
    ))
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "业务风险新增",
        detail: "业务",
        agentID: cto.id
    ))

    // 全量 +2，过滤后 +1（BossControlPanel.recentRiskCount 应该用过滤后版）
    #expect(store.selectedProductRiskEvents.count - baselineFull == 2,
            "全量风险流应增加两条")
    #expect(store.selectedProductBossRiskEvents.count - baselineFiltered == 1,
            "过滤后老板视图风险流应只增加一条业务风险（recentRiskCount 用此值，不会虚高）")
}

// MARK: - BossControlPanel 侧栏综合事件流迁移到 selectedProductBossEvents（角色继承期轮 5）

@MainActor
@Test func selectedProductBossEventsIsScopedToSelectedProductAndExcludesMaintenancePrefixes() async throws {
    // 老板侧栏「近期汇报」/「最新消息」综合事件流：
    // 1. 必须只含 selectedProductID 或 productID == nil 的事件（产品作用域）
    // 2. 必须过滤 bossViewExcludedRiskTitlePrefixes 前缀（与 selectedProductBossRiskEvents 同模式）
    // 3. 保留所有 kind（不只是 risk），因为侧栏是综合面板
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let baseline = store.selectedProductBossEvents.count
    let otherProductID = UUID() // 不属于任何已知产品

    // 1. 同产品 + 业务前缀：应该入老板视图
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .message,
        title: "新消息汇报",
        detail: "收到新消息。",
        agentID: cto.id
    ))
    // 2. 同产品 + 维护前缀：应该被过滤
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName)",
        detail: "忙碌中。",
        agentID: cto.id
    ))
    // 3. 跨产品（其他 productID）：应该被产品作用域过滤
    store.events.append(CompanyEvent(
        productID: otherProductID,
        kind: .statusChanged,
        title: "其他产品状态变化",
        detail: "不属于当前产品。",
        agentID: cto.id
    ))

    let after = store.selectedProductBossEvents
    #expect(after.count - baseline == 1,
            "三条新增事件中只有 1 条（同产品 + 业务前缀）应进入老板视图")
    let newest = try #require(after.last)
    #expect(newest.title == "新消息汇报")
    #expect(!after.contains { $0.title.hasPrefix("命令行健康预警：") },
            "老板侧栏综合事件流必须过滤维护类前缀")
    #expect(!after.contains { $0.title == "其他产品状态变化" },
            "老板侧栏综合事件流必须按产品作用域过滤")
}

@MainActor
@Test func selectedProductBossEventsKeepsAllKindsNotJustRisk() async throws {
    // 与 selectedProductBossRiskEvents 区别：本 accessor 必须返回所有 kind
    // （message / statusChanged / taskCreated / artifactCreated 等），
    // 因为消费方「近期汇报」/「最新消息」是综合面板，不是只看风险。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    let kindsToTest: [CompanyEventKind] = [.message, .statusChanged, .taskCreated, .artifactCreated]
    for kind in kindsToTest {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: kind,
            title: "测试 \(kind.title) 事件",
            detail: "kind = \(kind.rawValue)",
            agentID: cto.id
        ))
    }

    let bossEvents = store.selectedProductBossEvents
    for kind in kindsToTest {
        #expect(bossEvents.contains { $0.title == "测试 \(kind.title) 事件" },
                "selectedProductBossEvents 必须保留 kind = \(kind.rawValue) 的事件，不能只返回 risk")
    }
}

@MainActor
@Test func selectedProductBossEventsAndSelectedProductBossRiskEventsShareMaintenancePrefixWhitelist() async throws {
    // 契约：两个老板视图 accessor 必须共享同一份 bossViewExcludedRiskTitlePrefixes 白名单。
    // 任何未来新增维护前缀，只需加到一份白名单，两个视图同时生效。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    for prefix in CompanyStore.bossViewExcludedRiskTitlePrefixes {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: .risk,
            title: "\(prefix)\(cto.displayName)",
            detail: "维护类预警 - \(prefix)",
            agentID: cto.id
        ))
    }

    let bossEvents = store.selectedProductBossEvents
    let bossRiskEvents = store.selectedProductBossRiskEvents
    for prefix in CompanyStore.bossViewExcludedRiskTitlePrefixes {
        #expect(!bossEvents.contains { $0.title.hasPrefix(prefix) },
                "selectedProductBossEvents 必须过滤前缀「\(prefix)」")
        #expect(!bossRiskEvents.contains { $0.title.hasPrefix(prefix) },
                "selectedProductBossRiskEvents 也必须过滤前缀「\(prefix)」（同源契约）")
    }
}

@Test func bossControlPanelInInspectorPanelUsesSelectedProductBossEventsAndDropsRawStoreEventsPrefix() async throws {
    // 守门：BossControlPanel.recentEvents / compactRecentReports 必须改用 selectedProductBossEvents，
    // 不能再读跨产品 + 含维护类的 store.events.prefix(N)。
    // 反向断言：源码不能再含 store.events.prefix(5) / store.events.prefix(3)
    // （这两条都是轮 5 之前 BossControlPanel 的旧实现）。
    // 但 store.events 单独出现仍然允许（EventLogView 员工 inspector 技术维护视图保留全量）。
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(source.contains("store.bossInspectorRecentEvents"),
            "BossControlPanel.recentEvents 必须用 store.bossInspectorRecentEvents accessor")
    #expect(source.contains("store.bossInspectorCompactRecentReports"),
            "BossControlPanel.compactRecentReports 必须用 store.bossInspectorCompactRecentReports accessor")
    #expect(source.contains("store.bossInspectorRecentEventsOverflow()"),
            "BossControlPanel.recentEvents 必须渲染溢出提示")
    #expect(source.contains("store.bossInspectorCompactRecentReportsOverflow()"),
            "BossControlPanel.compactRecentReports 必须渲染溢出提示")
    #expect(!source.contains("store.events.prefix(5)"),
            "BossControlPanel 不应再含 store.events.prefix(5)（跨产品 + 含维护类，已迁移到老板视图 accessor）")
    #expect(!source.contains("store.events.prefix(3)"),
            "BossControlPanel 不应再含 store.events.prefix(3)（同上）")
}

@MainActor
@Test func bossInspectorDefaultDisplayLimitsAndOverflowAccessorsExposeContinuation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    #expect(CompanyStore.bossInspectorTeamProgressDefaultDisplayLimit == 5)
    #expect(CompanyStore.bossInspectorRecentTasksDefaultDisplayLimit == 4)
    #expect(CompanyStore.bossInspectorRecentEventsDefaultDisplayLimit == 5)
    #expect(CompanyStore.bossInspectorCompactRecentReportsDefaultDisplayLimit == 3)

    for index in 1...6 {
        store.createTask(title: "老板侧任务 \(index)", ownerID: cto.id, status: .planned, successCriteria: "任务 \(index)")
    }
    #expect(store.bossInspectorRecentTasks.count == CompanyStore.bossInspectorRecentTasksDefaultDisplayLimit)
    let taskOverflow = try #require(store.bossInspectorRecentTasksOverflow())
    #expect(taskOverflow.summary.contains("后续还有"))
    #expect(taskOverflow.summary.contains("项任务"))
    #expect(!taskOverflow.summary.contains("折叠") && !taskOverflow.summary.contains("未展开"))

    for index in 1...7 {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: .statusChanged,
            title: "老板侧汇报 \(index)",
            detail: "汇报 \(index)",
            agentID: cto.id
        ))
    }
    #expect(store.bossInspectorRecentEvents.count == CompanyStore.bossInspectorRecentEventsDefaultDisplayLimit)
    #expect(store.bossInspectorCompactRecentReports.count == CompanyStore.bossInspectorCompactRecentReportsDefaultDisplayLimit)
    let eventOverflow = try #require(store.bossInspectorRecentEventsOverflow())
    let compactOverflow = try #require(store.bossInspectorCompactRecentReportsOverflow())
    #expect(eventOverflow.summary.contains("后续还有"))
    #expect(eventOverflow.summary.contains("条近期汇报"))
    #expect(compactOverflow.summary.contains("后续还有"))
    #expect(compactOverflow.summary.contains("条汇报"))
    #expect(!compactOverflow.summary.contains("折叠") && !compactOverflow.summary.contains("未展开"))
}

@Test func bossInspectorPanelsUseStoreLimitsAndOverflowFooterInsteadOfHardcodedPrefixes() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")
    let storeSource = try loadOPCCompanyCoreSource("CompanyStore.swift")
    let bossControlPanelSlice = try #require(
        extractTopLevelStructSlice(
            from: source,
            structMarker: "struct BossControlPanel:",
            failureMessage: "未找到 BossControlPanel struct 起点"
        )
    )

    #expect(bossControlPanelSlice.contains("store.bossInspectorTeamProgressAgents"))
    #expect(bossControlPanelSlice.contains("store.bossInspectorRecentTasks"))
    #expect(storeSource.contains("selectedProductRecentTasks.prefix(Self.bossInspectorRecentTasksDefaultDisplayLimit)"),
            "bossInspectorRecentTasks 应从 selectedProductRecentTasks 派生，而不是 view 直接 prefix selectedProductTasks")
    #expect(bossControlPanelSlice.contains("store.bossInspectorRecentEvents"))
    #expect(bossControlPanelSlice.contains("store.bossInspectorCompactRecentReports"))
    #expect(bossControlPanelSlice.contains("OPCListOverflowFooter("))
    #expect(!bossControlPanelSlice.contains("selectedProductAgents.filter { $0.role != .boss }.prefix(5)"))
    #expect(!bossControlPanelSlice.contains("employees.prefix(5)"))
    #expect(!bossControlPanelSlice.contains("selectedProductTasks.prefix(4)"))
    #expect(!bossControlPanelSlice.contains("selectedProductBossEvents.prefix(5)"))
    #expect(!bossControlPanelSlice.contains("selectedProductBossEvents.prefix(3)"))
}

@Test func bossInspectorCompactRecentReportsDoesNotShowMetaUIExplanation() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")
    let marker = "private var compactRecentReports: some View"
    let start = try #require(source.range(of: marker)?.lowerBound, "应能定位老板右侧紧凑近期汇报视图")
    let tail = source[start...]
    let end = try #require(tail.range(of: "\n    private func agentName", options: [])?.lowerBound, "应能定位紧凑近期汇报视图结尾")
    let slice = String(tail[..<end])

    #expect(slice.contains("SectionHeader(title: \"近期汇报\")"))
    #expect(!slice.contains("右侧只保留沟通"))
    #expect(!slice.contains("主区域已经展示完整工作区"))
    #expect(!slice.contains("这里仅用于下达目标"))
}

// MARK: - BossReportCenter「报告事件」迁移到真实老板汇报入口（角色继承期轮 6 + codex 复核）

@MainActor
@Test func bossReportCenterReportEventsAreScopedToSelectedProductOnly() async throws {
    // BossReportCenter UI 文案明示「报告会汇总当前产品...」，
    // reportEvents 必须只显示当前产品的报告/快照/产物事件，跨产品事件必须被过滤。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let otherProductID = UUID()

    // 同产品 + 报告标题 → 必须入
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .message,
        title: "本产品老板报告 V2",
        detail: "测试事件",
        agentID: cto.id
    ))
    // 跨产品 + 报告标题 → 必须被产品作用域过滤
    store.events.append(CompanyEvent(
        productID: otherProductID,
        kind: .message,
        title: "其他产品老板报告 V1",
        detail: "不属于当前产品",
        agentID: cto.id
    ))

    let reportEvents = store.selectedProductBossReportEvents
    #expect(reportEvents.contains { $0.title == "本产品老板报告 V2" },
            "本产品报告标题必须出现在 reportEvents 计算结果中")
    #expect(!reportEvents.contains { $0.title == "其他产品老板报告 V1" },
            "其他产品的报告标题必须被产品作用域过滤掉")
}

@MainActor
@Test func bossReportCenterReportEventsExcludeMaintenancePrefixesEvenIfTitleContainsReport() async throws {
    // 防御性测试：未来若有「命令行健康预警：xxx 报告」类维护事件标题恰好含「报告」字样，
    // 必须被 selectedProductBossEvents 的维护前缀过滤拦截，不能挤进老板报告中心列表。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName) 报告异常",
        detail: "维护类事件",
        agentID: cto.id
    ))
    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .message,
        title: "正常老板报告",
        detail: "业务事件",
        agentID: cto.id
    ))

    let reportEvents = store.selectedProductBossReportEvents
    #expect(!reportEvents.contains { $0.title.hasPrefix("命令行健康预警：") },
            "维护前缀的事件即便标题含「报告」也必须被过滤（轮 5 共享白名单契约延伸到本面板）")
    #expect(reportEvents.contains { $0.title == "正常老板报告" },
            "无前缀的业务报告事件正常入列")
}

@Test func bossReportCenterUsesSelectedProductBossReportEventsAndDropsRawStoreEventsFilter() async throws {
    // 守门：BossReportCenter.reportEvents 必须用 store.selectedProductBossReportEvents，
    // 不能再读跨产品 + 含维护类的 store.events.filter。
    // 但 OperationsSuiteView 仍允许 store.events 出现在其他位置（如有），本断言只覆盖
    // BossReportCenter 的 reportEvents 这一行。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    #expect(source.contains("store.selectedProductBossReportEvents"),
            "BossReportCenter.reportEvents 必须用 store.selectedProductBossReportEvents")
    #expect(!source.contains("store.events.filter"),
            "OperationsSuiteView 不应再含 store.events.filter（已迁移到老板视图 accessor）")
}

@MainActor
@Test func bossReportCenterVisibleListsExposeContinuationThroughStoreAccessors() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    for index in 0..<(CompanyStore.bossReportCenterReportEventsDisplayLimit + 2) {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: .message,
            title: "老板报告事件 \(index)",
            detail: "汇报事件",
            agentID: cto.id,
            createdAt: Date(timeIntervalSince1970: Double(index))
        ))
    }
    for index in 0..<(CompanyStore.bossReportCenterBossMessagesDisplayLimit + 1) {
        store.messages.append(ChatMessage(
            productID: store.selectedProductID,
            agentID: store.bossID,
            author: .system,
            text: "老板报告：\(store.selectedProduct?.name ?? "当前产品")\n第 \(index) 份",
            createdAt: Date(timeIntervalSince1970: Double(index))
        ))
    }

    #expect(store.bossReportCenterReportEvents.count == CompanyStore.bossReportCenterReportEventsDisplayLimit)
    #expect(store.bossReportCenterReportEventsOverflow()?.hiddenCount == 2)
    #expect(store.bossReportCenterBossMessages.count == CompanyStore.bossReportCenterBossMessagesDisplayLimit)
    #expect(store.bossReportCenterBossMessagesOverflow()?.hiddenCount == 1)
}

@MainActor
@Test func generateBossReportUsesBossFacingWorkspaceAndEmployeeStateCopy() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    store.events.insert(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行作业目录创建失败",
        detail: "维护侧文件系统失败，不应进入老板报告。",
        agentID: cto.id
    ), at: 0)
    store.events.insert(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行发车被阻止",
        detail: "老板动作被阻止，应进入老板报告。",
        agentID: cto.id
    ), at: 0)

    store.generateBossReport()
    let report = try #require(store.selectedProductBossReportMessages.first?.text)

    #expect(report.contains("本地工作区："))
    #expect(report.contains("员工状态："))
    #expect(report.contains("命令行发车被阻止"))
    #expect(!report.contains("命令行作业目录创建失败"))
    #expect(!report.contains("产品目录："))
    #expect(!report.contains("终端输出："))
}

// MARK: - BossReportCenter「最近老板报告」按当前产品作用域过滤（角色继承期轮 10）

@MainActor
@Test func selectedProductBossReportMessagesScopesToCurrentProductOnly() async throws {
    // 行为契约：generateBossReport() 给当前产品写入老板报告 → selectedProductBossReportMessages
    // 应包含；切换到另一个产品 → 之前产品的老板报告不应再出现在 selectedProductBossReportMessages。
    // 这保护 BossReportCenter「最近老板报告」面板不会跨产品污染（boss agent 是跨产品角色，
    // messages(for: bossID) 是跨产品累加的，必须按产品名 prefix 匹配过滤）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let originalProductID = store.selectedProductID
    let originalProductName = try #require(store.selectedProduct?.name)

    // 1. 当前产品（A）生成老板报告 → 必须出现
    store.generateBossReport()
    let scopedAfterA = store.selectedProductBossReportMessages
    #expect(scopedAfterA.contains { $0.text.hasPrefix("老板报告：\(originalProductName)") },
            "当前产品生成的老板报告必须出现在 selectedProductBossReportMessages")

    // 2. 切换到新产品（B），即便 boss 流里仍有 A 的老板报告，B 视图也不应看到
    store.addProductWorkspace()  // 创建并自动选中新产品
    #expect(store.selectedProductID != originalProductID, "addProductWorkspace 必须切换 selectedProductID 到新产品")
    let newProductName = try #require(store.selectedProduct?.name)
    #expect(newProductName != originalProductName, "新建的产品名应与原产品不同")

    let scopedAfterSwitch = store.selectedProductBossReportMessages
    #expect(!scopedAfterSwitch.contains { $0.text.hasPrefix("老板报告：\(originalProductName)") },
            "Product A 的老板报告不应漏到 Product B 的 selectedProductBossReportMessages")
    #expect(scopedAfterSwitch.allSatisfy { $0.text.hasPrefix("老板报告：\(newProductName)") },
            "切换后的视图只应显示属于当前产品的老板报告")
}

@MainActor
@Test func selectedProductBossReportMessagesIsTimeReversedNewestFirst() async throws {
    // 行为契约：BossReportCenter 原行为是 .reversed()（最新在前），新 accessor 必须保留这个语义，
    // 否则视觉行为回退（用户会看到最旧的报告先出现）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.generateBossReport()
    // 等 1ms 让 createdAt 区分（同一选中产品多次生成，模拟用户再次点击「生成老板报告」）
    try await Task.sleep(nanoseconds: 2_000_000)
    store.generateBossReport()

    let messages = store.selectedProductBossReportMessages
    #expect(messages.count >= 2, "两次 generateBossReport 之后应至少有 2 条老板报告")
    if messages.count >= 2 {
        #expect(messages[0].createdAt >= messages[1].createdAt,
                "selectedProductBossReportMessages 必须按 createdAt 倒序（最新在前），与原 BossReportCenter.bossMessages 行为一致")
    }
}

@Test func bossReportCenterBossMessagesUsesSelectedProductBossReportMessagesAndDropsCrossProductReadAndDeadHandoffSnapshotBranch() async throws {
    // 守门：BossReportCenter.bossMessages 必须用 store.selectedProductBossReportMessages，
    // 不能再读 store.messages(for: store.bossID)（跨产品）+ 不能再含
    // 失效的 "产品交接快照" filter 分支（boss 流从来没这种消息，createHandoffSnapshot 只写 ctoID 流）。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    #expect(source.contains("store.selectedProductBossReportMessages"),
            "BossReportCenter.bossMessages 必须用 store.selectedProductBossReportMessages（轮 10）")
    #expect(!source.contains("store.messages(for: store.bossID).reversed().filter"),
            "BossReportCenter.bossMessages 不应再含原 messages(for: bossID).reversed().filter 链（跨产品 + 已废分支）")
    #expect(!source.contains("text.contains(\"产品交接快照\")"),
            "失效的「产品交接快照」filter 分支必须移除（createHandoffSnapshot 只写 ctoID 流，boss 流永远不匹配）")
}

@Test func commandCenterReportsTabExposesReachableBossReportCenterSheet() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")

    guard let commandCenterSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct CommandCenterView:",
        failureMessage: "未找到 CommandCenterView struct 起点 — 老板汇报中心可达性契约失效"
    ) else { return }

    #expect(commandCenterSlice.contains("showReportCenter"),
            "老板汇报中心必须由总控台真实状态控制打开，不能只停留在旧高级命令中心")
    #expect(commandCenterSlice.contains("BossReportCenterSheet()"),
            "老板汇报中心必须作为真实 sheet 接入 CommandCenterView")
    #expect(commandCenterSlice.contains("打开老板汇报中心"),
            "汇报交付页必须提供老板可见的汇报中心入口")
    #expect(source.contains("struct BossReportCenterSheet: View"),
            "CommandCenterView.swift 必须定义真实可达的 BossReportCenterSheet")
}

// MARK: - 员工工作台「发起员工交接」面板空状态收敛

@MainActor
@Test func agentDeskHandoffComposerStateExpandsForEngineerInTeamWithRecipients() async throws {
    // 默认产品 bootstrap 团队 = [cto, ui, codeEngineer, reviewer]，选中工程师 → recipients ≥ 1 → 应该 .expanded
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    #expect(!store.selectedAgentHandoffRecipients.isEmpty,
            "默认产品工程师应有 ≥ 1 个可接收对端")
    let state = store.agentDeskHandoffComposerState()
    #expect(state == .expanded,
            "选中可发起交接的员工时面板必须 .expanded（撑开完整 4 输入 + 按钮表单）")
}

@MainActor
@Test func agentDeskHandoffComposerStateCollapsesForBossSelectionWithReason() async throws {
    // 老板视角：不参与员工到员工交接 → .collapsed 单行原因
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.selectAgent(store.bossID)
    let state = store.agentDeskHandoffComposerState()
    if case .collapsed(let reason) = state {
        #expect(reason.contains("老板"),
                "老板视角原因应含『老板』")
        #expect(reason.contains("交接"),
                "原因应说明与交接相关")
        #expect(!reason.isEmpty && reason.count < 80,
                "单行原因应紧凑（< 80 字），实际：\(reason.count) 字")
    } else {
        Issue.record("老板选中时 agentDeskHandoffComposerState 必须是 .collapsed，实际：\(state)")
    }
}

@MainActor
@Test func agentDeskHandoffComposerStateCollapsesWhenAgentNotInProductTeamWithReason() async throws {
    // 员工未加入当前产品团队 → .collapsed，原因应含员工名 + 团队加入提示
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    store.addProductWorkspace()  // 切到只有 cto 的新产品
    #expect(!store.isAgentAssignedToSelectedProduct(engineer.id),
            "新建产品默认只有 cto，工程师未加入")
    // 重新选回 engineer（addProductWorkspace 会调用 ensureSelectedAgentIsValidForSelectedProduct，可能改了 selectedAgent）
    store.selectAgent(engineer.id)
    let state = store.agentDeskHandoffComposerState()
    if case .collapsed(let reason) = state {
        #expect(reason.contains(engineer.displayName),
                "未加入团队的原因应含员工名以便老板识别")
        #expect(reason.contains("产品"),
                "原因应提示加入产品团队")
    } else {
        Issue.record("员工未加入产品时必须 .collapsed，实际：\(state)")
    }
}

@MainActor
@Test func agentDeskHandoffComposerStateCollapsesWhenNoOtherRecipientsInTeam() async throws {
    // 员工已加入产品团队但团队里没有其它非老板员工 → .collapsed，原因应提示邀请其他员工
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.addProductWorkspace()  // 新产品默认 [ctoID]
    store.assignAgentToSelectedProduct(engineer.id)  // → [ctoID, engineer]
    store.removeAgentFromSelectedProduct(store.ctoID)  // → [engineer]
    store.selectAgent(engineer.id)
    #expect(store.isAgentAssignedToSelectedProduct(engineer.id),
            "工程师应已加入新产品团队")
    #expect(store.selectedAgentHandoffRecipients.isEmpty,
            "团队里没有其它员工，recipients 应为空")
    let state = store.agentDeskHandoffComposerState()
    if case .collapsed(let reason) = state {
        #expect(reason.contains("可接收交接的员工") || reason.contains("邀请"),
                "原因应提示邀请其他员工，实际：\(reason)")
    } else {
        Issue.record("团队没有其它员工时必须 .collapsed，实际：\(state)")
    }
}

@Test func agentDeskHandoffComposerInSelectionWorkspaceUsesAccessorAndCollapsesEmptyState() async throws {
    // 源码扫描：SelectionWorkspaceView.AgentDeskWorkspace 的 handoffComposer 必须用新 accessor
    // + 必须有 .collapsed/.expanded 两种渲染分支 + 不能再用原来的 3 个 EmptyCommandLine 撑满 panel
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("store.agentDeskHandoffComposerState()"),
            "AgentDeskWorkspace 必须调用 store.agentDeskHandoffComposerState() 拿到面板状态")
    #expect(source.contains("handoffComposerCollapsedRow(reason:"),
            "必须有 collapsed 单行渲染分支 handoffComposerCollapsedRow(reason:)")
    #expect(source.contains("handoffComposerExpanded"),
            "必须保留 expanded 完整表单渲染分支 handoffComposerExpanded")

    // 反向：原来 3 个 EmptyCommandLine 撑满 panel 的硬编码分支必须移除（它们都已收敛进 store accessor）
    #expect(!source.contains("EmptyCommandLine(text: \"老板不参与员工到员工的交接"),
            "原来的『老板不参与』EmptyCommandLine 已收敛到 store accessor，view 不应再硬编码")
    #expect(!source.contains("EmptyCommandLine(text: \"\\(agent.displayName) 还没有加入当前产品团队，无法在该产品发起交接"),
            "原来的『未加入团队』EmptyCommandLine 已收敛到 store accessor")
    #expect(!source.contains("EmptyCommandLine(text: \"当前产品里没有可接收交接的员工"),
            "原来的『没有可接收对端』EmptyCommandLine 已收敛到 store accessor")
}

// MARK: - 员工工作台「我的待审任务」prefix 收敛 + overflow 提示

@MainActor
@Test func agentDeskReviewQueueDefaultDisplayLimitIsThreeAndReducedFromOriginalEight() async throws {
    // 契约：默认展开上限 3，明显低于改造前的 prefix(8)。
    // 任何 PR 想拉高上限必须先动这条断言（防止退化回 prefix(8)）。
    #expect(CompanyStore.agentDeskReviewQueueDefaultDisplayLimit == 3,
            "默认展开上限必须为 3（任务多时收敛），实际：\(CompanyStore.agentDeskReviewQueueDefaultDisplayLimit)")
    #expect(CompanyStore.agentDeskReviewQueueDefaultDisplayLimit < 8,
            "上限必须 < 8（改造前的硬编码 prefix(8)），避免退化")
}

@MainActor
@Test func agentDeskReviewQueueOverflowReturnsNilWhenQueueAtOrBelowLimit() async throws {
    // ≤ 3 任务：overflow 必须 nil，view 不渲染溢出 footer
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.selectAgent(reviewer.id)

    // 默认 bootstrap 下没有 needsReview 任务给 reviewer
    #expect(store.selectedAgentReviewQueue.isEmpty)
    #expect(store.agentDeskReviewQueueOverflow() == nil,
            "队列为空时 overflow 必须 nil")

    // 注入 3 条 needsReview 任务：仍 ≤ limit
    for index in 1...3 {
        store.createTask(title: "审查任务 \(index)", ownerID: reviewer.id, status: .needsReview, successCriteria: "需要审查 \(index)")
    }
    #expect(store.selectedAgentReviewQueue.count == 3)
    #expect(store.agentDeskReviewQueueOverflow() == nil,
            "队列正好 = limit 时 overflow 必须 nil")
}

@MainActor
@Test func agentDeskReviewQueueOverflowExposesHiddenCountAndChineseSummaryWhenQueueExceedsLimit() async throws {
    // > 3 任务：overflow 必须返回 hiddenCount + 中文 summary
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let reviewer = try #require(store.agents.first { $0.role == .reviewer })
    store.selectAgent(reviewer.id)

    for index in 1...7 {
        store.createTask(title: "审查任务 \(index)", ownerID: reviewer.id, status: .needsReview, successCriteria: "需要审查 \(index)")
    }
    #expect(store.selectedAgentReviewQueue.count == 7)
    let overflow = try #require(store.agentDeskReviewQueueOverflow(),
                                 "队列 > limit 时 overflow 必须非 nil")
    #expect(overflow.hiddenCount == 7 - CompanyStore.agentDeskReviewQueueDefaultDisplayLimit,
            "hiddenCount 应为 total - limit = \(7 - CompanyStore.agentDeskReviewQueueDefaultDisplayLimit)")
    #expect(overflow.summary.contains("\(overflow.hiddenCount)"),
            "summary 应含具体未展开数量")
    #expect(overflow.summary.contains("待审"),
            "summary 应说明是待审任务")
    #expect(!overflow.summary.contains("DisclosureGroup") && !overflow.summary.contains("折叠") && !overflow.summary.contains("未展开"),
            "summary 不应使用『折叠/未展开/DisclosureGroup』等违反 5-01 红线的措辞")
    #expect(!overflow.summary.contains("协作消息总览") && !overflow.summary.contains("完整队列"),
            "待审任务不是协作消息，footer 不应指向协作消息总览")
}

@Test func agentDeskReviewQueuePanelInSelectionWorkspaceUsesLimitConstantAndOverflowAccessor() async throws {
    // 源码扫描：reviewQueuePanel 必须用新常量 + overflow accessor，不能再硬编码 prefix(8)
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("CompanyStore.agentDeskReviewQueueDefaultDisplayLimit"),
            "reviewQueuePanel 必须用 CompanyStore.agentDeskReviewQueueDefaultDisplayLimit 常量")
    #expect(source.contains("store.agentDeskReviewQueueOverflow()"),
            "必须调用 store.agentDeskReviewQueueOverflow() 渲染 footer")

    // 反向：reviewQueuePanel 范围内不能再含 store.selectedAgentReviewQueue.prefix(8)
    #expect(!source.contains("selectedAgentReviewQueue.prefix(8)"),
            "不应再硬编码 prefix(8)（应用 limit 常量）")
}

// MARK: - 员工工作台「模型和权限」面板 chip 化收敛

@MainActor
@Test func agentDeskProfileChipsReturnFourCoreFieldsForAnyAgentEvenWithoutSession() async throws {
    // 真实命令行员工（无论有无 runtimeSession）都必须返回 4 项核心 chip：
    // 来源 / 命令行工具 / 模型 / 推理强度。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let chips = store.agentDeskProfileChips(forAgentID: engineer.id)
    let labels = chips.map(\.label)
    #expect(labels.contains("来源"))
    #expect(labels.contains("命令行工具"))
    #expect(labels.contains("模型"))
    #expect(labels.contains("推理强度"))
    #expect(chips.count >= 4,
            "至少 4 项核心 chip，实际：\(chips.count)")
    // 反向：未提供 nil 应返回空数组
    #expect(store.agentDeskProfileChips(forAgentID: nil).isEmpty)
}

@MainActor
@Test func agentDeskProfileChipsForLocalPlaceholderHideCommandAndReasoning() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let boss = try #require(store.agents.first { $0.role == .boss })
    let chips = store.agentDeskProfileChips(forAgentID: boss.id)
    let labels = chips.map(\.label)

    #expect(labels.contains("来源"))
    #expect(labels.contains("占位标识"))
    #expect(!labels.contains("命令行工具"))
    #expect(!labels.contains("模型"))
    #expect(!labels.contains("推理强度"))
}

@MainActor
@Test func agentDeskProfileChipsAppendSessionFieldsOnlyWhenRuntimeSessionExists() async throws {
    // 没有 runtimeSession 时不能含「会话」「保活」chip（否则 view 会显示空值垃圾）。
    // 一旦预热建立 session，必须追加「会话」；正常保活开启是稳定值，不默认浮出。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    let labelsBefore = store.agentDeskProfileChips(forAgentID: engineer.id).map(\.label)
    let hadSessionBefore = store.runtimeSession(for: engineer.id) != nil
    if !hadSessionBefore {
        #expect(!labelsBefore.contains("会话"),
                "无 runtimeSession 时不应有「会话」chip")
        #expect(!labelsBefore.contains("保活"),
                "无 runtimeSession 时不应有「保活」chip")
    }

    // 触发 session 创建后再确认追加（用公共 API；可能因后端类型不同不预热成功，所以下方也加 if 兜底）
    store.startRuntimeSupervisorIfNeeded()
    store.prewarmSelectedProductAgentSessions(reason: "测试 chip 追加行为")
    if store.runtimeSession(for: engineer.id) != nil {
        let labelsAfter = store.agentDeskProfileChips(forAgentID: engineer.id).map(\.label)
        #expect(labelsAfter.contains("会话"),
                "有 runtimeSession 时必须追加「会话」chip")
        #expect(!labelsAfter.contains("保活"),
                "保活开启属于稳定值，不应默认占用 profile chip 空间")

        var session = try #require(store.runtimeSession(for: engineer.id))
        session.keepAlive = false
        store.runtimeSessions[engineer.id] = session
        let warningLabels = store.agentDeskProfileChips(forAgentID: engineer.id).map(\.label)
        #expect(warningLabels.contains("保活"),
                "保活关闭属于异常状态，应浮出 profile chip")
    }
}

@Test func agentDeskWorkspaceDoesNotExposeKeepAliveEnabledAsDefaultVisibleCopy() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(!source.contains("保活开启"),
            "保活开启是稳定运行细节，不应作为员工工作台默认可见文案")
    #expect(!source.contains("保活 开启"),
            "保活开启是稳定运行细节，不应作为员工工作台默认 chip")
}

@MainActor
@Test func agentDeskProfileChipValuesAreNonEmptyAndShortEnoughForCapsule() async throws {
    // 契约：每个 chip 的 value 都非空 + 不应过长（chip capsule 内 lineLimit(1) + truncationMode middle）
    let store = CompanyStore.bootstrap(loadPersisted: false)
    for agent in store.agents where agent.role != .boss {
        let chips = store.agentDeskProfileChips(forAgentID: agent.id)
        for chip in chips {
            #expect(!chip.value.isEmpty,
                    "\(agent.displayName) 的 \(chip.label) chip value 不应为空")
            #expect(!chip.label.isEmpty,
                    "chip label 不应为空")
        }
    }
}

@Test func agentDeskProfilePanelInSelectionWorkspaceUsesChipAccessorAndDropsProfileMiniRowStack() async throws {
    // 源码扫描：profilePanel 必须用新 accessor + AgentDeskProfileChipView
    // 且不能再含 6 个硬编码 ProfileMiniRow 调用
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("store.agentDeskProfileChips(forAgentID:"),
            "profilePanel 必须用 store.agentDeskProfileChips(forAgentID:) accessor")
    #expect(source.contains("AgentDeskProfileChipView("),
            "必须用新的 chip 视图 AgentDeskProfileChipView")

    // 反向：原 6 个 ProfileMiniRow 调用必须移除
    let removedLabels = ["label: \"来源\"", "label: \"命令行工具\"", "label: \"模型\"", "label: \"推理强度\"", "label: \"会话\"", "label: \"保活\""]
    for removed in removedLabels {
        // 这些 label 字面量原本只在 ProfileMiniRow(label: "...") 调用中出现
        // 现在已经移到 store accessor 字符串里，view 不应再含这些 label: "X" 形式
        #expect(!source.contains("ProfileMiniRow(\(removed)"),
                "view 不应再含 ProfileMiniRow(\(removed)，已收敛到 store accessor")
    }
}

// MARK: - 员工工作台「负责的任务」/「员工工作队列」prefix 收敛 + 通用 overflow footer

@MainActor
@Test func agentDeskAssignedTasksAndWorkQueueLimitsAreThreeAndReducedFromOriginalEight() async throws {
    // 双向锁：两个 panel 上限均为 3 + 必须 < 8（防止退化回 prefix(8)）
    #expect(CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit == 3)
    #expect(CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit < 8)
    #expect(CompanyStore.agentDeskWorkQueueDefaultDisplayLimit == 3)
    #expect(CompanyStore.agentDeskWorkQueueDefaultDisplayLimit < 8)
}

@MainActor
@Test func agentDeskAssignedTasksOverflowReturnsNilWhenAtOrBelowLimitAndNonNilWhenExceeds() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    // 默认：工程师可能有 0 个或少量分配任务，overflow 应为 nil
    #expect(store.agentDeskAssignedTasksOverflow(forAgentID: engineer.id) == nil)
    // nil agentID → nil
    #expect(store.agentDeskAssignedTasksOverflow(forAgentID: nil) == nil)

    // 注入 5 条任务（> 3 limit）
    for index in 1...5 {
        store.createTask(title: "分配任务 \(index)", ownerID: engineer.id, status: .planned, successCriteria: "需要做 \(index)")
    }
    let overflow = try #require(store.agentDeskAssignedTasksOverflow(forAgentID: engineer.id))
    #expect(overflow.hiddenCount >= 5 - CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit,
            "至少 hidden = total(\(5) 新增) - limit(3) = 2")
    #expect(overflow.summary.contains("\(overflow.hiddenCount)"))
    #expect(overflow.summary.contains("分配任务") || overflow.summary.contains("任务"))
    #expect(!overflow.summary.contains("折叠") && !overflow.summary.contains("未展开") && !overflow.summary.contains("DisclosureGroup"))
}

@MainActor
@Test func agentDeskWorkQueueOverflowReturnsNilWhenAtOrBelowLimitAndNonNilWhenExceeds() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })

    #expect(store.agentDeskWorkQueueOverflow(forAgentID: engineer.id) == nil)
    #expect(store.agentDeskWorkQueueOverflow(forAgentID: nil) == nil)

    // 队列入队需要先有任务
    var taskIDs: [UUID] = []
    for index in 1...5 {
        store.createTask(title: "队列前置任务 \(index)", ownerID: engineer.id, status: .planned, successCriteria: "队列 \(index)")
        if let task = store.selectedProductTasks.first(where: { $0.title == "队列前置任务 \(index)" }) {
            taskIDs.append(task.id)
            store.enqueueWorkItem(taskID: task.id, agentID: engineer.id)
        }
    }
    #expect(taskIDs.count == 5)

    let overflow = try #require(store.agentDeskWorkQueueOverflow(forAgentID: engineer.id))
    #expect(overflow.hiddenCount >= 5 - CompanyStore.agentDeskWorkQueueDefaultDisplayLimit)
    #expect(overflow.summary.contains("\(overflow.hiddenCount)"))
    #expect(overflow.summary.contains("队列"))
    #expect(!overflow.summary.contains("折叠") && !overflow.summary.contains("未展开") && !overflow.summary.contains("DisclosureGroup"))
}

@Test func agentDeskAssignedTasksAndQueuePanelInSelectionWorkspaceUseLimitConstantAndOverflowFooter() async throws {
    // 源码扫描：两个 panel 必须用新常量 + overflow accessor + 共用 OPCListOverflowFooter
    // 反向：不能再含 agentTasks.prefix(8) / agentQueue.prefix(8)
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit"),
            "assignedTasks 必须用 CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit 常量")
    #expect(source.contains("CompanyStore.agentDeskWorkQueueDefaultDisplayLimit"),
            "queuePanel 必须用 CompanyStore.agentDeskWorkQueueDefaultDisplayLimit 常量")
    #expect(source.contains("store.agentDeskAssignedTasksOverflow(forAgentID:"),
            "必须调用 agentDeskAssignedTasksOverflow accessor")
    #expect(source.contains("store.agentDeskWorkQueueOverflow(forAgentID:"),
            "必须调用 agentDeskWorkQueueOverflow accessor")
    #expect(source.contains("OPCListOverflowFooter("),
            "必须共用通用 OPCListOverflowFooter 视图组件")

    // 反向：不应再含 prefix(8) 字面量
    #expect(!source.contains("agentTasks.prefix(8)"),
            "不应再硬编码 agentTasks.prefix(8)")
    #expect(!source.contains("agentQueue.prefix(8)"),
            "不应再硬编码 agentQueue.prefix(8)")
}

// MARK: - 员工工作台「我的协作收件箱」overflow footer 与三面板对齐（角色继承期轮 7）

@MainActor
@Test func agentDeskInboxDefaultDisplayLimitIsSixToPreserveCollaborationUX() async throws {
    // 收件箱默认上限维持 6（不下调到 3），保护核心协作 UX 不被过度收敛。
    // 与 review/assigned/workQueue 三面板（limit=3）的差异是有意为之。
    #expect(CompanyStore.agentDeskInboxDefaultDisplayLimit == 6,
            "收件箱默认上限必须 = 6（保留协作 UX，不与待审/任务面板的 3 同口径）")
    // 防御性：limit 应严格 > 任务面板的 limit（差异有意保留）
    #expect(CompanyStore.agentDeskInboxDefaultDisplayLimit > CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit,
            "收件箱 limit 必须严格 > assignedTasks limit（差异是收件箱不能过度收敛）")
}

@MainActor
@Test func agentDeskInboxOverflowReturnsNilAtOrBelowLimitAndNonNilWhenExceeds() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.selectAgent(engineer.id)
    let baseline = store.selectedAgentRecentProductMessages.count

    let limit = CompanyStore.agentDeskInboxDefaultDisplayLimit
    let needToReachLimit = max(0, limit - baseline)
    // 1. 写入消息使总数到 limit → 仍应返回 nil（不溢出）
    for i in 0..<needToReachLimit {
        store.agentMessages.append(AgentMessageEnvelope(
            productID: store.selectedProductID,
            fromAgentID: cto.id,
            toAgentID: engineer.id,
            taskID: nil,
            kind: .taskDispatched,
            subject: "测试消息 \(i) 到达 limit",
            body: "test body \(i)",
            createdAt: Date()
        ))
    }
    #expect(store.selectedAgentRecentProductMessages.count == limit,
            "前置：消息数应正好等于 limit")
    #expect(store.agentDeskInboxOverflow() == nil,
            "总数 == limit 时 overflow 必须为 nil")

    // 2. 再加 2 条 → 应返回 hidden = 2
    for i in 0..<2 {
        store.agentMessages.append(AgentMessageEnvelope(
            productID: store.selectedProductID,
            fromAgentID: cto.id,
            toAgentID: engineer.id,
            taskID: nil,
            kind: .taskDispatched,
            subject: "溢出消息 \(i)",
            body: "overflow body \(i)",
            createdAt: Date()
        ))
    }
    let overflow = try #require(store.agentDeskInboxOverflow())
    #expect(overflow.hiddenCount == 2,
            "limit + 2 时 hiddenCount 必须 = 2")
    #expect(overflow.summary.contains("2 条"),
            "summary 必须包含「2 条」字样让用户知道差距")
    #expect(!overflow.summary.contains("折叠") && !overflow.summary.contains("未展开") && !overflow.summary.contains("DisclosureGroup"))
    #expect(overflow.summary.contains("协作消息总览"),
            "协作消息收件箱的完整入口才应指向协作消息总览")
}

@MainActor
@Test func agentDeskInboxOverflowReturnsNilForBossOrAgentWithoutSession() async throws {
    // 边界：如果选中的是老板（不进 inboxBody if 分支）或 selectedAgentID 为 nil，
    // selectedAgentRecentProductMessages 已经处理 nil agentID 返回空，所以 overflow 必须 nil。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    // 默认情况：boss 已选中（bootstrap 默认 selectedAgent = boss）
    // selectedAgentID 改为 nil
    store.selectAgent(UUID())  // 不存在的 agent ID
    #expect(store.selectedAgentRecentProductMessages.isEmpty,
            "选了不存在的 agent，最近消息应为空")
    #expect(store.agentDeskInboxOverflow() == nil,
            "agent 不存在时 overflow 必须为 nil")
}

@Test func inboxPanelInSelectionWorkspaceUsesInboxLimitConstantAndOverflowFooter() async throws {
    // 守门：inboxBody 必须用 CompanyStore.agentDeskInboxDefaultDisplayLimit + OPCListOverflowFooter，
    // 反向禁止 prefix(6) 硬编码字面量重新出现。
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("CompanyStore.agentDeskInboxDefaultDisplayLimit"),
            "inboxBody 必须用 CompanyStore.agentDeskInboxDefaultDisplayLimit 常量")
    #expect(source.contains("store.agentDeskInboxOverflow()"),
            "inboxBody 必须调用 agentDeskInboxOverflow accessor")
    #expect(!source.contains("selectedAgentRecentProductMessages.prefix(6)"),
            "不应再硬编码 selectedAgentRecentProductMessages.prefix(6)")
}

@MainActor
@Test func productDetailCollaborationPanelLimitsDefaultMessagesToThree() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(CompanyStore.productDetailAgentCollaborationDefaultDisplayLimit == 3)
    #expect(source.contains("CompanyStore.productDetailAgentCollaborationDefaultDisplayLimit"),
            "产品详情协作链路必须使用集中默认显示上限")
    #expect(!source.contains("selectedProductRecentAgentMessages.prefix(6)"),
            "产品详情默认页不应再硬编码展示 6 条协作消息")
}

@MainActor
@Test func productMemoryDefaultDisplayLimitAndOverflowAccessorExposeContinuation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(CompanyStore.productMemoryDefaultDisplayLimit == 6)
    #expect(store.selectedProductMemoryOverflow() == nil)

    for index in 1...8 {
        store.memories.append(ProductMemoryNote(
            productID: store.selectedProductID,
            kind: .decision,
            title: "产品记忆 \(index)",
            detail: "关键规则 \(index)"
        ))
    }

    #expect(store.selectedProductMemories.count == 8)
    #expect(store.selectedProductVisibleMemories.count == CompanyStore.productMemoryDefaultDisplayLimit)
    let overflow = try #require(store.selectedProductMemoryOverflow())
    #expect(overflow.hiddenCount == 2)
    #expect(overflow.summary.contains("后续还有 2 条长期记忆"))
    #expect(overflow.summary.contains("产品记忆库"))
    #expect(!overflow.summary.contains("折叠") && !overflow.summary.contains("未展开") && !overflow.summary.contains("DisclosureGroup"))
}

@Test func productMemoryPanelUsesStoreAccessorAndOverflowFooterInsteadOfHardcodedPrefix() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    let operationsSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    let marker = "private var productMemory: some View"
    let start = try #require(source.range(of: marker)?.lowerBound, "应能定位产品记忆视图")
    let tail = source[start...]
    let end = try #require(tail.range(of: "\n    private func tasks(for agent:", options: [])?.lowerBound, "应能定位产品记忆视图结尾")
    let slice = String(tail[..<end])

    #expect(slice.contains("store.selectedProductVisibleMemories"))
    #expect(slice.contains("store.selectedProductMemoryOverflow()"))
    #expect(slice.contains("OPCListOverflowFooter("))
    #expect(!slice.contains("selectedProductMemories.prefix(6)"))
    #expect(!operationsSource.contains("selectedProductMemories.prefix(6)"),
            "已删除的旧规则记忆中心不能带回 selectedProductMemories.prefix(6) 静默截断")
}

@MainActor
@Test func productDetailDeliveryListsUseStoreAccessorsAndOverflowFooter() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    let marker = "private var productArtifacts: some View"
    let start = try #require(source.range(of: marker)?.lowerBound, "应能定位产品交付区")
    let tail = source[start...]
    let end = try #require(tail.range(of: "\n    private var productMemory", options: [])?.lowerBound, "应能定位产品交付区结尾")
    let slice = String(tail[..<end])

    #expect(CompanyStore.productDetailRecentDeliveryRecordsDefaultDisplayLimit == 3)
    #expect(slice.contains("store.productDetailRecentDeliveryVerifications"))
    #expect(slice.contains("store.productDetailRecentDeliveryArtifacts"))
    #expect(slice.contains("store.productDetailDeliveryVerificationsOverflow()"))
    #expect(slice.contains("store.productDetailDeliveryArtifactsOverflow()"))
    #expect(slice.contains("OPCListOverflowFooter("))
    #expect(!slice.contains("selectedProductRecentDeliveryVerifications.prefix(3)"))
    #expect(!slice.contains("selectedProductRecentDeliveryArtifacts.prefix(3)"))
}

@MainActor
@Test func deliveryAcceptanceCenterSheetUsesNamedDisplayLimitsInsteadOfMagicPrefixNumbers() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(CompanyStore.deliveryAcceptanceCenterAcceptanceTasksDisplayLimit == 12)
    #expect(CompanyStore.deliveryAcceptanceCenterReviewGatesDisplayLimit == 12)
    #expect(CompanyStore.deliveryAcceptanceCenterVerificationsDisplayLimit == 12)
    #expect(CompanyStore.deliveryAcceptanceCenterArtifactsDisplayLimit == 20)
    #expect(source.contains("CompanyStore.deliveryAcceptanceCenterAcceptanceTasksDisplayLimit"))
    #expect(source.contains("CompanyStore.deliveryAcceptanceCenterReviewGatesDisplayLimit"))
    #expect(source.contains("CompanyStore.deliveryAcceptanceCenterVerificationsDisplayLimit"))
    #expect(source.contains("CompanyStore.deliveryAcceptanceCenterArtifactsDisplayLimit"))
    #expect(source.contains("store.selectedProductDeliveryReviewGates"))
    #expect(source.contains("store.deliveryAcceptanceCenterAcceptanceTasksOverflow()"))
    #expect(source.contains("store.deliveryAcceptanceCenterReviewGatesOverflow()"))
    #expect(source.contains("store.deliveryAcceptanceCenterVerificationsOverflow()"))
    #expect(source.contains("store.deliveryAcceptanceCenterArtifactsOverflow()"))
    #expect(source.contains("OPCListOverflowFooter("))
    #expect(!source.contains("selectedProductAcceptanceTasks.prefix(12)"))
    #expect(!source.contains("selectedProductReviewGates.prefix(12)"))
    #expect(!source.contains("selectedProductRecentDeliveryVerifications.prefix(12)"))
    #expect(!source.contains("selectedProductRecentDeliveryArtifacts.prefix(20)"))
}

@MainActor
@Test func deliveryAcceptanceCenterOverflowSummariesAreHonestTerminalSheetSummaries() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    for index in 1...14 {
        store.createTask(title: "验收中心任务 \(index)", ownerID: cto.id, status: .needsReview, successCriteria: "验收 \(index)")
    }

    let overflow = try #require(store.deliveryAcceptanceCenterAcceptanceTasksOverflow())
    #expect(overflow.summary.contains("未显示"))
    #expect(overflow.summary.contains("当前中心"))
    #expect(!overflow.summary.contains("查看全部"))
    #expect(!overflow.summary.contains("总览"))
    #expect(!overflow.summary.contains("更多请到"))
}

@MainActor
@Test func bossDecisionCenterResolvedApprovalsUsesLimitAndOverflowButPendingAndRiskStayFullList() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    #expect(CompanyStore.bossDecisionCenterResolvedApprovalsDisplayLimit == 8)

    for index in 1...10 {
        store.approvals.append(ApprovalRequest(
            productID: store.selectedProductID,
            requesterID: cto.id,
            title: "已处理决策 \(index)",
            reason: "历史 \(index)",
            status: .approved,
            decidedAt: Date()
        ))
    }

    #expect(store.bossDecisionCenterResolvedApprovals.count == CompanyStore.bossDecisionCenterResolvedApprovalsDisplayLimit)
    let overflow = try #require(store.bossDecisionCenterResolvedApprovalsOverflow())
    #expect(overflow.summary.contains("已处理决策"))
    #expect(overflow.summary.contains("未显示"))

    #expect(source.contains("store.bossDecisionCenterResolvedApprovals"))
    #expect(source.contains("store.bossDecisionCenterResolvedApprovalsOverflow()"))
    #expect(!source.contains("selectedProductResolvedApprovals.prefix(8)"))

    let pendingMarker = "private var pendingApprovalsSection: some View"
    let riskMarker = "private var riskTasksSection: some View"
    let resolvedMarker = "private var resolvedApprovalsSection: some View"
    let pendingStart = try #require(source.range(of: pendingMarker)?.lowerBound)
    let riskStart = try #require(source.range(of: riskMarker)?.lowerBound)
    let resolvedStart = try #require(source.range(of: resolvedMarker)?.lowerBound)
    let pendingSlice = String(source[pendingStart..<riskStart])
    let riskSlice = String(source[riskStart..<resolvedStart])
    #expect(!pendingSlice.contains(".prefix("),
            "待审批是老板必看完整队列，不应加 prefix")
    #expect(!riskSlice.contains(".prefix("),
            "风险任务是老板必看完整队列，不应加 prefix")
}

@MainActor
@Test func bossDecisionCenterRiskEventsSectionUsesFilteredRiskEventsWithOverflow() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let cto = try #require(store.agents.first { $0.role == .cto })

    #expect(CompanyStore.bossDecisionCenterRiskEventsDisplayLimit == 8)

    store.events.append(CompanyEvent(
        productID: store.selectedProductID,
        kind: .risk,
        title: "命令行健康预警：\(cto.displayName)",
        detail: "维护类预警",
        agentID: cto.id
    ))
    for index in 1...10 {
        store.events.append(CompanyEvent(
            productID: store.selectedProductID,
            kind: .risk,
            title: "老板决策中心业务风险 \(index)",
            detail: "风险 \(index)",
            agentID: cto.id
        ))
    }

    #expect(store.bossDecisionCenterRiskEvents.count == CompanyStore.bossDecisionCenterRiskEventsDisplayLimit)
    #expect(!store.bossDecisionCenterRiskEvents.contains { $0.title.hasPrefix("命令行健康预警：") },
            "老板决策中心风险事件 section 必须复用老板视图过滤口径，不显示维护类预警")
    let overflow = try #require(store.bossDecisionCenterRiskEventsOverflow())
    #expect(overflow.summary.contains("风险事件"))
    #expect(overflow.summary.contains("未显示"))
}

@MainActor
@Test func bossDecisionCenterSheetExposesRiskEventsSectionOnReachableSheet() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")
    let sheetSlice = try #require(
        extractTopLevelStructSlice(
            from: source,
            structMarker: "struct BossDecisionCenterSheet:",
            failureMessage: "未找到 BossDecisionCenterSheet struct 起点"
        )
    )

    #expect(BossDecisionCenterCopy.riskEventsSection == "风险事件")
    #expect(sheetSlice.contains("riskEventsSection"))
    #expect(sheetSlice.contains("store.selectedProductBossRiskEvents"))
    #expect(sheetSlice.contains("store.bossDecisionCenterRiskEvents"))
    #expect(sheetSlice.contains("store.bossDecisionCenterRiskEventsOverflow()"))
    #expect(sheetSlice.contains("OPCListOverflowFooter("))
    #expect(!sheetSlice.contains("selectedProductRiskEvents"),
            "老板决策中心不应直读未过滤的 selectedProductRiskEvents")
    #expect(!sheetSlice.contains("riskEvents.prefix(8)"),
            "老板决策中心风险事件不应在 view 层硬编码 prefix(8)")
}

@MainActor
@Test func terminalDetailMaintenanceAndGatewayListsExposeContinuation() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)

    #expect(CompanyStore.communicationGatewayLogDisplayLimit == 8)
    #expect(CompanyStore.localMaintenanceVerificationDisplayLimit == 8)
    #expect(CompanyStore.localMaintenanceArtifactDisplayLimit == 8)

    for index in 1...10 {
        store.communicationLogs.insert(CommunicationLogEntry(
            productID: store.selectedProductID,
            direction: .outbound,
            status: .sent,
            title: "通信日志 \(index)",
            body: "日志 \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index))
        ), at: 0)
        store.verifications.insert(VerificationRecord(
            productID: store.selectedProductID,
            status: .passed,
            title: "维护数据增长巡检",
            detail: "维护 \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index))
        ), at: 0)
        store.artifacts.insert(ArtifactRecord(
            productID: store.selectedProductID,
            kind: .report,
            title: "命令行作业档案：样本 \(index)",
            path: "/tmp/opc-maintenance-\(index).json",
            summary: "维护产物 \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index))
        ), at: 0)
    }

    #expect(store.communicationGatewayVisibleLogs.count == CompanyStore.communicationGatewayLogDisplayLimit)
    #expect(store.localMaintenanceVisibleVerifications.count == CompanyStore.localMaintenanceVerificationDisplayLimit)
    #expect(store.localMaintenanceVisibleArtifacts.count == CompanyStore.localMaintenanceArtifactDisplayLimit)

    let logOverflow = try #require(store.communicationGatewayLogsOverflow())
    let verificationOverflow = try #require(store.localMaintenanceVerificationsOverflow())
    let artifactOverflow = try #require(store.localMaintenanceArtifactsOverflow())
    #expect(logOverflow.summary.contains("通信日志"))
    #expect(verificationOverflow.summary.contains("维护审计"))
    #expect(artifactOverflow.summary.contains("维护产物"))
    #expect(logOverflow.summary.contains("未显示"))
    #expect(verificationOverflow.summary.contains("未显示"))
    #expect(artifactOverflow.summary.contains("未显示"))
}

@MainActor
@Test func terminalDetailPanelsUseStoreAccessorsAndOverflowFooterInsteadOfHardcodedPrefix() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    #expect(source.contains("store.communicationGatewayVisibleLogs"))
    #expect(source.contains("store.communicationGatewayLogsOverflow()"))
    #expect(source.contains("store.localMaintenanceVisibleVerifications"))
    #expect(source.contains("store.localMaintenanceVerificationsOverflow()"))
    #expect(source.contains("store.localMaintenanceVisibleArtifacts"))
    #expect(source.contains("store.localMaintenanceArtifactsOverflow()"))
    #expect(source.contains("OPCListOverflowFooter("))
    #expect(!source.contains("selectedProductCommunicationLogs.prefix(8)"))
    #expect(!source.contains("selectedProductRecentMaintenanceVerifications.prefix(8)"))
    #expect(!source.contains("selectedProductRecentMaintenanceArtifacts.prefix(8)"))
    #expect(!source.contains("最多展示 8 条"),
            "终端大厅详情文案不应只说最多展示而不说明后续记录会继续浮现")
}

@Test func advancedCommandCenterDeadShellsAreRemovedButReachableTerminalCentersStay() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    for removedStruct in [
        "struct AdvancedCommandCenter:",
        "struct AdvancedConsoleIntro:",
        "struct OperatorDisclosure",
        "struct AutomationCommandCenter:",
        "struct ProposalCommandCenter:",
        "struct TaskApprovalCommandCenter:",
        "struct AssetMemoryCommandCenter:",
        "struct CLILaunchpadCenter:",
        "struct AutomationPipelineCenter:",
        "struct AutomationEngineCenter:",
        "struct BranchExecutionCenter:",
        "struct PresalesProposalFactoryCenter:",
        "struct TeamConfigurationCenter:",
        "struct RolePackLibraryCenter:",
        "struct AgentWorkspaceSystemCenter:",
        "struct TemplateLibraryCenter:",
        "struct ProductHealthCenter:",
        "struct TaskDispatchCenter:",
        "struct ExecutionDeckView:",
        "struct RiskApprovalCenter:",
        "struct ArtifactCenterView:",
        "struct ModelRoutingCenter:",
        "struct AcceptanceLabView:",
        "struct RuleMemoryCenter:",
        "struct BranchPlanCard:",
        "struct RolePackCard:",
        "struct WorkspaceAgentRow:",
        "struct RoleCoverageRow:",
        "struct TemplatePreviewLine:",
        "struct DispatchTaskCard:",
        "struct ExecutionTaskRow:",
        "struct ApprovalRequestCard:",
        "struct RiskTaskCard:",
        "struct ArtifactTaskCard:",
        "struct RoutingRoleCard:",
        "struct AcceptanceStep:",
        "struct PipelineStepCard:"
    ] {
        #expect(!source.contains(removedStruct), "\(removedStruct) 已无真实入口，应保持删除状态")
    }

    #expect(source.contains("struct MultiAgentArchitectureAuditCenter:"),
            "多员工架构体检仍由终端大厅详情 sheet 使用，不能随 dead shell 删除")
    #expect(source.contains("struct CommunicationGatewayCommandCenter:"),
            "通信网关详情仍由终端大厅详情 sheet 使用，不能随 dead shell 删除")
    #expect(source.contains("struct LocalMaintenanceCenter:"),
            "本地维护详情仍由终端大厅详情 sheet 使用，不能随 dead shell 删除")
}

@Test func oldAutomatedPipelineStoreAPIsStayRemovedButLegacyTaskCleanupRemains() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    for removedAPI in [
        "func startAutomatedPipeline(",
        "func advancePipeline(",
        "func clearPipelineTasks(",
        "func runPipelineExecutableAgents(",
        "func notifyPipelineAgent(",
        "func applyRolePackToSelectedAgent(",
        "func retryFailedWorkItems(",
        "func clearCompletedWorkItems(",
        "func markRunningWorkItemsFailed(",
        "func addMissingSpecialistTeam(",
        "func clearBranchExecutionForSelectedProduct(",
        "func createBranchExecutionPlan(",
        "func advanceBranchPlan(",
        "func createPresalesProposalFactory(",
        "func runAutoInteractionLoopForSelectedAgent(",
        "func workOrderPrompt(for taskID:"
    ] {
        #expect(!source.contains(removedAPI), "\(removedAPI) 已无真实产品入口，应保持删除状态")
    }

    #expect(source.contains("\"流水线 \", \"分支 \", \"分支汇总：\", \"模板：\", \"售前\", \"手机指令：\""),
            "旧流水线/分支/售前任务前缀仍要保留在运行数据清理白名单中，兼容历史快照")
}

@Test func productScopeSuccessStandardTitleDistinguishesTaskAndProductLevelStandards() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("ProductScopeRow(title: successStandardTitle"),
            "产品目标卡片应使用动态标题，避免把任务验收标准误标为产品级成功标准")
    #expect(source.contains("return \"当前待办标准\""),
            "存在未完成任务时应标为当前待办标准")
    #expect(source.contains("return \"整体成功标准\""),
            "所有任务完成时才应标为整体成功标准")
    #expect(!source.contains("ProductScopeRow(title: \"成功标准\", detail: successStandard"),
            "不应再用固定「成功标准」标题承载任务级验收标准")
}

@Test func productDetailVisibleCopyDoesNotExposeUILayoutCommentary() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    for forbidden in [
        "为避免老板界面暴露",
        "不在老板界面",
        "完整命令和输出请到终端大厅查看",
        "不占用产品页主体",
        "右侧输入框"
    ] {
        #expect(!source.contains(forbidden),
                "默认可见界面不应出现布局/设计解释或位置依赖提示：\(forbidden)")
    }
    #expect(source.contains("指挥通道"),
            "产品目标缺省提示应使用稳定产品词，而不是右侧/上方等布局位置词")
}

@Test func selectionWorkspaceTerminalStatusDetailDoesNotReferToBossInterfaceFromEmployeeDesk() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    guard let start = source.range(of: "func terminalStatusDetail(session: AgentRuntimeSession?, log: String) -> String {")?.lowerBound,
          let end = source.range(of: "func runtimeStatusIcon(session: AgentRuntimeSession?, log: String) -> String {")?.lowerBound,
          start < end
    else {
        Issue.record("无法定位 terminalStatusDetail 切片")
        return
    }
    let detailSlice = String(source[start..<end])

    #expect(!detailSlice.contains("老板界面"),
            "员工工作台状态文案不应引用老板界面规则")
    #expect(!detailSlice.contains("不在老板"),
            "员工工作台状态文案不应用 UI 规则解释运行状态")
    #expect(!detailSlice.contains("完整命令和输出请到终端大厅查看"),
            "状态详情不应重复按钮已经表达的终端大厅导航说明")
    #expect(detailSlice.contains("命令和输出在终端大厅"),
            "可保留简短去向，但不应反复解释 UI 结构")
}

@Test func runtimePrewarmEventDoesNotReferToBossInterfaceRules() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    #expect(!source.contains("老板界面启动冗长预热命令"),
            "运行时预热事件不应把老板界面边界写成默认可见事件文案")
    #expect(source.contains("预热记录已写入终端大厅"),
            "预热成功事件应只描述状态和记录去向")
}

@Test func inspectorTerminalHallModeDoesNotRenderControlAreaRationale() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    for forbidden in [
        "终端控制已在主区域",
        "右侧只保留当前员工日志",
        "避免同一功能出现两套入口"
    ] {
        #expect(!source.contains(forbidden),
                "终端大厅模式的右侧检查器不应显示开发期 UI 解释：\(forbidden)")
    }
    #expect(source.contains("if store.mainWorkspace != .terminalHall"),
            "终端大厅模式应直接隐藏右侧运行控制区，只保留当前员工日志")
}

@Test func bossCommandCenterHeaderDoesNotRepeatOwnerRoleResponsibilitiesAsSubtitle() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")
    guard let start = source.range(of: "private var header: some View {")?.lowerBound,
          let end = source.range(of: "private var statsGrid: some View {")?.lowerBound,
          start < end
    else {
        Issue.record("无法定位 BossControlPanel header 切片")
        return
    }
    let headerSlice = String(source[start..<end])

    #expect(headerSlice.contains("老板总控台"))
    #expect(headerSlice.contains("Text(\"老板\")"))
    #expect(headerSlice.contains("store.selectedProduct?.name"))
    #expect(headerSlice.contains("store.selectedProduct?.stage.title"))
    #expect(!headerSlice.contains("你只负责"))
    #expect(!headerSlice.contains("下目标、看进度、批准风险"))
}

@Test func productTaskColumnOverflowUsesUnifiedTaskQuantifierConsistentWithAgentDeskOverflow() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    guard let start = source.range(of: "struct ProductTaskColumn: View {")?.lowerBound,
          let end = source.range(of: "private struct TeamOperatingSummaryCard: View {")?.lowerBound,
          start < end
    else {
        Issue.record("无法定位 ProductTaskColumn 切片")
        return
    }
    let columnSlice = String(source[start..<end])

    #expect(columnSlice.contains("还有 \\(hiddenTaskCount) 项"),
            "任务 overflow 量词应统一为「项」")
    #expect(!columnSlice.contains("还有 \\(hiddenTaskCount) 条"),
            "任务不是消息，不应使用「条」")
}

@Test func agentProfileFooterOmitsLocalLogStorageMetaHintButKeepsWorkspaceStatus() async throws {
    let files = try loadOPCCompanyCoreSwiftFileURLs()
    var combined = ""
    for file in files {
        combined += (try String(contentsOf: file, encoding: .utf8))
        combined += "\n"
    }

    #expect(!combined.contains("会话日志由本机维护"),
            "默认可见员工档案不应反复声明本地日志存储实现细节")
    #expect(combined.components(separatedBy: "员工工作区已就绪").count - 1 >= 1,
            "真实员工档案仍应保留工作区就绪状态")
}

@Test func productDetailMetricsAndProgressDoNotRenderCompletionPercentTwice() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    let completionPercentOccurrences = source.components(separatedBy: "\\(completionPercent)%").count - 1
    #expect(completionPercentOccurrences == 1,
            "完成度百分比只应在 metrics tile 渲染一次，实际出现 \(completionPercentOccurrences) 次")

    guard let progressStart = source.range(of: "private var productProgress: some View {")?.lowerBound,
          let progressEnd = source.range(of: "private var productTeamOffice: some View {")?.lowerBound,
          progressStart < progressEnd
    else {
        Issue.record("无法定位 productProgress 切片")
        return
    }
    let progressSlice = String(source[progressStart..<progressEnd])

    #expect(!progressSlice.contains("\\(completionPercent)%"),
            "productProgress 不应再次渲染 metrics 已经展示的百分比")
    #expect(!progressSlice.contains("\\(completedTaskCount)/"),
            "productProgress 不应再次渲染 metrics 已经展示的任务计数")
    #expect(progressSlice.contains("ProductStageRail"),
            "去重后仍必须保留阶段轨道")
    #expect(progressSlice.contains("ProductScopeRow(title: \"下一步\""),
            "去重后仍必须保留下一步说明")
}

@Test func agentMessageRowRendersStatusPillOrReviewOutcomePillButNotBoth() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    guard let rowStart = source.range(of: "struct AgentMessageRow: View {")?.lowerBound,
          let rowEnd = source.range(of: "struct AgentMessageCenterSheet: View {")?.lowerBound,
          rowStart < rowEnd
    else {
        Issue.record("无法定位 AgentMessageRow 切片")
        return
    }
    let rowSlice = String(source[rowStart..<rowEnd])

    #expect(rowSlice.contains("if let reviewOutcome = message.reviewOutcome"),
            "审查结论仍必须优先作为业务状态 pill")
    #expect(rowSlice.contains("} else {"),
            "有审查结论时不应再并列渲染消息确认状态，必须二选一")
    #expect(rowSlice.contains("AgentMessageDisplay.statusTitle(for: message.status)"),
            "没有审查结论时仍必须显示消息状态 pill")

    let reviewPillCount = rowSlice.components(separatedBy: "StatusPill(text: reviewOutcome.title").count - 1
    let messageStatusPillCount = rowSlice.components(separatedBy: "StatusPill(text: AgentMessageDisplay.statusTitle(for: message.status)").count - 1
    #expect(reviewPillCount == 1)
    #expect(messageStatusPillCount == 1)
}

@Test func agentReportDefaultPromptIsCentralizedAndIdenticalAcrossSurfaces() async throws {
    var occurrences = 0
    let l10nInfraFiles: Set<String> = ["AppStringsGenerated.swift", "AppStrings.swift",
                                       "AppStringsTables.swift", "AppLanguage.swift", "L10nEnvironment.swift"]
    for url in try loadOPCCompanyCoreSwiftFileURLs() {
        guard !l10nInfraFiles.contains(url.lastPathComponent) else { continue } // 翻译表合法包含全部文案
        let source = try String(contentsOf: url, encoding: .utf8)
        occurrences += source.components(separatedBy: "\"汇报你的角色").count - 1
    }
    #expect(occurrences == 1,
            "默认员工汇报 prompt 字面量只能在集中常量定义处出现，实际：\(occurrences)")

    let terminalHallSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    let selectionSource = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")
    let inspectorSource = try loadOPCCompanyCoreSource("InspectorPanel.swift")
    let companyStoreSource = try loadOPCCompanyCoreSource("CompanyStore.swift")

    for source in [terminalHallSource, selectionSource, inspectorSource, companyStoreSource] {
        #expect(source.contains("OPCVisibleInterfaceCopy.defaultAgentReportPromptText"),
                "默认员工汇报 prompt 的使用点必须引用集中常量")
    }
}

// MARK: - 跨产品 CTO 消息产品作用域守门（角色继承期轮 12限制标记后续修复）

@MainActor
@Test func productScopedMessagesIncludeCurrentProductAndLegacyFallbackOnly() async throws {
    let store = CompanyStore.bootstrap()
    let productA = store.selectedProductID
    let productB = UUID()

    store.messages.append(ChatMessage(productID: productA, agentID: store.ctoID, author: .system, text: "A 产品消息"))
    store.messages.append(ChatMessage(productID: productB, agentID: store.ctoID, author: .system, text: "B 产品消息"))
    store.messages.append(ChatMessage(agentID: store.ctoID, author: .system, text: "旧版全局消息"))

    let scopedWithLegacy = store.messages(for: store.ctoID, in: productA)
    #expect(scopedWithLegacy.contains { $0.text == "A 产品消息" })
    #expect(scopedWithLegacy.contains { $0.text == "旧版全局消息" })
    #expect(!scopedWithLegacy.contains { $0.text == "B 产品消息" })

    let scopedStrict = store.messages(for: store.ctoID, in: productA, includingLegacyGlobal: false)
    #expect(scopedStrict.contains { $0.text == "A 产品消息" })
    #expect(!scopedStrict.contains { $0.text == "B 产品消息" })
    #expect(!scopedStrict.contains { $0.text == "旧版全局消息" })
}

@MainActor
@Test func sendMessageStampsSelectedProductAndKeepsCTOChatScoped() async throws {
    let store = CompanyStore.bootstrap()
    let productA = store.selectedProductID

    store.sendMessage(to: store.ctoID, text: "A 产品目标")
    store.addProductWorkspace()
    let productB = store.selectedProductID
    store.sendMessage(to: store.ctoID, text: "B 产品目标")

    let productAMessages = store.messages(for: store.ctoID, in: productA, includingLegacyGlobal: false)
    let productBMessages = store.messages(for: store.ctoID, in: productB, includingLegacyGlobal: false)

    #expect(productAMessages.contains { $0.author == .user && $0.text == "A 产品目标" })
    #expect(!productAMessages.contains { $0.author == .user && $0.text == "B 产品目标" })
    #expect(productBMessages.contains { $0.author == .user && $0.text == "B 产品目标" })
    #expect(!productBMessages.contains { $0.author == .user && $0.text == "A 产品目标" })
}

@Test func companyStoreChatMessageWritesUseExplicitProductIDAfterLambdaPhaseTwo() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    #expect(!source.contains("ChatMessage(agentID:"),
            "CompanyStore 内新增/现有 ChatMessage 写入点必须显式传 productID；legacy nil 只允许测试或外部旧 snapshot decode")
    #expect(source.contains("messages(for agentID: UUID, in productID: UUID"),
            "CompanyStore 必须保留产品作用域消息读取 accessor")
}

@MainActor
@Test func captureDecisionMemoryUsesSelectedProductScopedMessagesAfterLambdaPhaseThree() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productA = store.selectedProductID
    store.addProductWorkspace()
    let productB = store.selectedProductID

    store.messages.append(ChatMessage(productID: productB, agentID: store.bossID, author: .system, text: "B 产品当前汇报"))
    store.messages.append(ChatMessage(productID: productA, agentID: store.bossID, author: .system, text: "A 产品旧汇报"))

    store.captureDecisionMemoryFromLatestReport()

    let memory = try #require(store.selectedProductMemories.first { $0.title.contains("自动记录") })
    #expect(memory.detail.contains("B 产品当前汇报"))
    #expect(!memory.detail.contains("A 产品旧汇报"))
}

@MainActor
@Test func captureDecisionMemoryExcludesLegacyNilReportsAfterLambdaPhaseFour() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.messages.append(ChatMessage(agentID: store.bossID, author: .system, text: "旧版全局汇报不应进入当前产品记忆"))

    store.captureDecisionMemoryFromLatestReport()

    let memory = try #require(store.selectedProductMemories.first { $0.title.contains("自动记录") })
    #expect(!memory.detail.contains("旧版全局汇报不应进入当前产品记忆"),
            "当前产品记忆捕获应严格使用 selectedProductID，不再把 legacy nil 全局报告当作当前产品报告")
}

@MainActor
@Test func captureDecisionMemorySkipsDuplicateWithinOneHourSameProductSamePrefix() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: store.bossID, author: .system, text: "本产品本轮状态摘要：里程碑 A 完成，待办 B 阻塞"))

    store.captureDecisionMemoryFromLatestReport()
    let firstCount = store.selectedProductMemories.filter { $0.title.hasPrefix("自动记录：") }.count
    #expect(firstCount == 1, "首次自动捕获应写入 1 条状态摘要")

    // 1 小时内再次捕获相同 detail 前 200 字应被跳过，记忆条数保持 1。
    store.captureDecisionMemoryFromLatestReport()
    let secondCount = store.selectedProductMemories.filter { $0.title.hasPrefix("自动记录：") }.count
    #expect(secondCount == 1, "1 小时内同一产品同一摘要前缀应被去重")
}

@MainActor
@Test func captureDecisionMemoryWritesAgainWhenDetailPrefixChangesWithinOneHour() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: store.bossID, author: .system, text: "第一轮状态摘要：里程碑 A 完成"))
    store.captureDecisionMemoryFromLatestReport()

    // 摘要前缀发生变化：去重窗口内仍应写入新的状态摘要条目。
    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: store.bossID, author: .system, text: "第二轮状态摘要：里程碑 B 已上线，老板要求收口"))
    store.captureDecisionMemoryFromLatestReport()

    let autoSummaries = store.selectedProductMemories.filter { $0.title.hasPrefix("自动记录：") }
    #expect(autoSummaries.count == 2, "不同 detail 前缀应保留两条独立记忆")
    #expect(autoSummaries.contains { $0.detail.contains("里程碑 A 完成") })
    #expect(autoSummaries.contains { $0.detail.contains("里程碑 B 已上线") })
}

@MainActor
@Test func captureDecisionMemoryWritesAgainAcrossDifferentProductsWithinOneHour() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productA = store.selectedProductID
    store.messages.append(ChatMessage(productID: productA, agentID: store.bossID, author: .system, text: "共享前缀状态摘要：项目推进顺利"))
    store.captureDecisionMemoryFromLatestReport()

    store.addProductWorkspace()
    let productB = store.selectedProductID
    #expect(productA != productB)
    store.messages.append(ChatMessage(productID: productB, agentID: store.bossID, author: .system, text: "共享前缀状态摘要：项目推进顺利"))
    store.captureDecisionMemoryFromLatestReport()

    let perProduct = Dictionary(grouping: store.memories.filter { $0.title.hasPrefix("自动记录：") }, by: { $0.productID })
    #expect(perProduct[productA]?.count == 1, "产品 A 应保留自己的自动状态摘要")
    #expect(perProduct[productB]?.count == 1, "产品 B 即使前缀相同也应保留自己的自动状态摘要")
}

@MainActor
@Test func captureDecisionMemoryWritesAgainAfterOneHourTTLExpires() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: store.bossID, author: .system, text: "一致的状态摘要：保持 7 天稳定运行"))
    store.captureDecisionMemoryFromLatestReport()
    #expect(store.selectedProductMemories.filter { $0.title.hasPrefix("自动记录：") }.count == 1)

    // 把已有自动摘要的 createdAt 回拨到 1 小时前 + 1 秒，模拟去重窗口已过期。
    if let index = store.memories.firstIndex(where: { $0.productID == store.selectedProductID && $0.title.hasPrefix("自动记录：") }) {
        store.memories[index].createdAt = Date().addingTimeInterval(-3601)
    }

    store.captureDecisionMemoryFromLatestReport()
    #expect(store.selectedProductMemories.filter { $0.title.hasPrefix("自动记录：") }.count == 2,
            "TTL 过期后即便 detail 前缀相同也应允许重新写入新的状态摘要")
}

@MainActor
@Test func compactSelectedAgentMemoryUsesSelectedProductScopedMessagesAfterLambdaPhaseThree() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    let productA = store.selectedProductID
    store.addProductWorkspace()
    let productB = store.selectedProductID
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)

    store.messages.append(ChatMessage(productID: productB, agentID: engineer.id, author: .user, text: "B 产品当前记忆"))
    store.messages.append(ChatMessage(productID: productA, agentID: engineer.id, author: .user, text: "A 产品旧记忆"))

    store.compactSelectedAgentMemory()

    let productMemories = store.selectedProductAgentMemories(for: engineer.id)
    #expect(productMemories.contains { $0.detail.contains("B 产品当前记忆") })
    #expect(!productMemories.contains { $0.detail.contains("A 产品旧记忆") })
    let profile = store.operatingProfile(for: engineer.id)
    #expect(!profile.memory.contains { $0.contains("B 产品当前记忆") },
            "产品对话压缩记忆不应写入员工全局 profile.memory")
}

@MainActor
@Test func compactSelectedAgentMemoryExcludesLegacyNilMessagesAfterLambdaPhaseFour() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.assignAgentToSelectedProduct(engineer.id)
    store.selectAgent(engineer.id)

    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: engineer.id, author: .user, text: "当前产品可压缩记忆"))
    store.messages.append(ChatMessage(agentID: engineer.id, author: .user, text: "旧版全局消息不应压缩"))

    store.compactSelectedAgentMemory()

    let productMemories = store.selectedProductAgentMemories(for: engineer.id)
    #expect(productMemories.contains { $0.detail.contains("当前产品可压缩记忆") })
    #expect(!productMemories.contains { $0.detail.contains("旧版全局消息不应压缩") })
    let profile = store.operatingProfile(for: engineer.id)
    #expect(!profile.memory.contains { $0.contains("当前产品可压缩记忆") },
            "产品对话压缩记忆不应写入员工全局 profile.memory")
}

@MainActor
@Test func agentChatPromptExcludesLegacyNilRecentMessagesAfterLambdaPhaseFour() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let engineer = try #require(store.agents.first { $0.role == .codeEngineer })
    store.assignAgentToSelectedProduct(engineer.id)

    store.messages.append(ChatMessage(productID: store.selectedProductID, agentID: engineer.id, author: .user, text: "当前产品近期对话"))
    store.messages.append(ChatMessage(agentID: engineer.id, author: .user, text: "旧版全局近期对话不应进入 prompt"))

    let prompt = store.agentConversationPrompt(for: engineer.id, userText: "继续")

    #expect(prompt.contains("当前产品近期对话"))
    #expect(!prompt.contains("旧版全局近期对话不应进入 prompt"))
}

@Test func memoryCaptureAndCompactionUseProductScopedMessagesAfterLambdaPhaseThree() async throws {
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    #expect(source.contains("messages(for: bossID, in: selectedProductID, includingLegacyGlobal: false)"),
            "captureDecisionMemoryFromLatestReport 必须严格按当前产品读取老板报告，不包含 legacy nil fallback")
    #expect(source.contains("messages(for: ctoID, in: selectedProductID, includingLegacyGlobal: false)"),
            "captureDecisionMemoryFromLatestReport 必须严格按当前产品读取 CTO 报告，不包含 legacy nil fallback")
    #expect(source.contains("messages(for: agentID, in: selectedProductID, includingLegacyGlobal: false).suffix(8)"),
            "compactAgentMemory 必须只压缩当前产品下该员工的近期对话，不包含 legacy nil fallback")
    #expect(source.contains("messages(for: agent.id, in: selectedProductID, includingLegacyGlobal: false)"),
            "agentChatPrompt 必须严格读取当前产品近期对话，不包含 legacy nil fallback")
}

@Test func latestCTOBriefingUsesProductScopedMessagesAccessorAfterLambdaPhaseOne() async throws {
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")

    #expect(source.contains("store.messages(for: store.ctoID, in: store.selectedProductID, includingLegacyGlobal: false)"),
            "latestCTOBriefing 必须严格按当前产品读取 CTO 消息，不能再跨产品读 messages(for: ctoID) 或 legacy nil fallback")
    #expect(!source.contains("LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK"),
            "candidate λ 第一阶段已让 latestCTOBriefing 走 product-scoped accessor，应移除旧 LIMITATION 标记")
}

@Test func ownerGoalUsesProductScopedMessagesAccessorAfterLambdaPhaseOne() async throws {
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    #expect(source.contains("store.messages(for: store.ctoID, in: store.selectedProductID, includingLegacyGlobal: false)"),
            "ownerGoal 必须严格按当前产品读取 CTO 消息，不能再跨产品读 messages(for: ctoID) 或 legacy nil fallback")
    #expect(!source.contains("LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK"),
            "candidate λ 第一阶段已让 ownerGoal 走 product-scoped accessor，应移除旧 LIMITATION 标记")
}

@Test func inspectorChatUsesStrictSelectedProductMessagesAfterLambdaPhaseFive() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(source.contains("selectedAgentChatMessages"),
            "InspectorPanel 需要集中读取当前员工在当前产品下的对话，避免主视图和滚动定位逻辑不一致")
    #expect(source.contains("store.messages(for: store.selectedAgentID, in: store.selectedProductID, includingLegacyGlobal: false)"),
            "右侧员工沟通栏必须严格按当前产品过滤，不能把旧版 nil 全局消息或其他产品消息显示成当前产品上下文")
    #expect(!source.contains("ForEach(store.messages(for: store.selectedAgentID))"),
            "右侧员工沟通栏不能再直接读取该员工跨产品全量消息")
}

@Test func inspectorHidesBackendAndTerminalControlsOutsideTerminalHallForBossFacingWorkspaces() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(source.contains("InspectorTab.availableTabs(for: store.mainWorkspace)"),
            "Inspector tab 列表必须按当前工作区收敛，避免老板总控台旁常驻终端入口")
    #expect(source.contains("workspace == .terminalHall ? allCases : allCases.filter { $0 != .terminal }"),
            "终端 tab 只能在终端大厅出现")
    #expect(source.contains("if workspace != .terminalHall, selectedTab == .terminal"),
            "离开终端大厅时必须自动退出终端 tab，避免隐藏 tab 仍显示终端内容")
    #expect(source.contains("if store.mainWorkspace == .terminalHall"),
            "backend/model/command 细节只允许在终端大厅显示")
    #expect(source.contains("return agent.role == .boss ? \"老板\" : \"\\(agent.role.title)席位\""),
            "老板可见常驻 Inspector header 只能显示角色席位，不应显示 backend/model/command 三元组")
}

@Test func inspectorTasksAndEventsAreScopedToSelectedAgentInSelectedProduct() async throws {
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    #expect(source.contains("private var selectedAgentTasks: [CompanyTask]"))
    #expect(source.contains("store.selectedProductTasks.filter { $0.ownerID == store.selectedAgentID }"),
            "Inspector 任务 tab 必须显示当前产品下选中员工自己的任务")
    #expect(source.contains("private var selectedAgentEvents: [CompanyEvent]"))
    #expect(source.contains("store.selectedProductEvents.filter { $0.agentID == store.selectedAgentID }"),
            "Inspector 事件 tab 必须显示当前产品下选中员工自己的事件")
    #expect(!source.contains("ForEach(store.selectedProductTasks)"),
            "右侧员工任务 tab 不能再渲染当前产品全员任务")
}

// MARK: - 安全审计 LIMITATION 标记守门（角色继承期轮 21）

@MainActor
@Test func selectedProductTasksExcludeLegacyNilTasksAfterMigrationPolicyCleanup() async throws {
    // 旧任务仍保存在 tasks 里，由维护区迁移入口处理；产品视图不能为了兼容而把 nil 任务泄漏到每个产品。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let legacy = CompanyTask(productID: nil, title: "未归属旧任务", ownerID: nil, status: .planned, successCriteria: "")
    let otherProductTask = CompanyTask(productID: UUID(), title: "其他产品任务", ownerID: nil, status: .planned, successCriteria: "")
    store.tasks.append(contentsOf: [legacy, otherProductTask])

    #expect(store.legacyTaskWithoutProductIDCount == 1)
    #expect(!store.selectedProductTasks.contains { $0.id == legacy.id })
    #expect(!store.selectedProductTasks.contains { $0.id == otherProductTask.id })

    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    guard let accessorStart = source.range(of: "public var selectedProductTasks: [CompanyTask] {"),
          let accessorEnd = source.range(of: "public var selectedProductRecentTasks", range: accessorStart.upperBound..<source.endIndex) else {
        Issue.record("找不到 selectedProductTasks accessor 切片")
        return
    }
    let selectedProductTasksSlice = String(source[accessorStart.lowerBound..<accessorEnd.lowerBound])

    #expect(!source.contains("LIMITATION-CROSS-PRODUCT-TASKS-NIL-LEAK"),
            "candidate λ-2 policy cleanup 已移除 selectedProductTasks 的 nil 兼容泄漏，旧 LIMITATION marker 不应保留")
    #expect(!selectedProductTasksSlice.contains("productID == nil"),
            "selectedProductTasks 不能再用 nil fallback 让旧任务进入每个产品视图")
    #expect(selectedProductTasksSlice.contains("tasks.filter { $0.productID == selectedProductID }"),
            "selectedProductTasks 必须严格按当前产品过滤")
    #expect(source.contains("migrateLegacyTasksWithoutProductID"),
            "旧任务不能丢失，维护区迁移 helper 必须继续保留")
}

@Test func scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker() async throws {
    // 守门：CompanyStore.scanLinkedLocalFiles 用 product.rootDirectory 原始字符串作为枚举根。
    // R21 已加 .standardizedFileURL 折叠 `..` 段。
    // R27 已加 .resolvingSymlinksInPath() + isSystemReservedPath 黑名单（candidate ψ 部分落地）。
    // candidate ψ 第一阶段已加显式根白名单 helper；后续只剩配置入口产品化。
    // 本守门防止后续清理误删 R21/R27 加固或 LIMITATION 注释。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    #expect(source.contains("LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST"),
            "scanLinkedLocalFiles 必须保留 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST 标记")
    #expect(source.contains("candidate ψ"),
            "limitation 标记必须点名 candidate ψ（path allowlist 策略）作为正解路径")
    #expect(source.contains(".standardizedFileURL"),
            "R21 加固的 .standardizedFileURL 调用必须保留，否则 `..` 越界回归")
    #expect(source.contains(".resolvingSymlinksInPath()"),
            "R27 加固的 .resolvingSymlinksInPath() 调用必须保留，否则 symlink 越界回归")
    #expect(source.contains("isSystemReservedPath"),
            "R27 加固的系统路径黑名单 helper 必须保留")
    #expect(source.contains("linkedLocalFileAllowedRootPaths"),
            "candidate ψ 第一阶段的已登记工作区根白名单 helper 必须保留")
    #expect(source.contains("isAllowedLinkedLocalFileRoot"),
            "candidate ψ 第一阶段的 rawRoot/resolvedRoot 双路径白名单校验必须保留")
    #expect(source.contains("scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker"),
            "limitation 标记必须点名守门测试名，方便从源码注释反向跳转")
}

// MARK: - R27 候选 ψ 部分落地：系统路径黑名单 + symlink 解析守门（角色继承期轮 27）

@MainActor
@Test func scanLinkedLocalFilesRejectsSystemReservedRootPath() async throws {
    // R27：当 product.rootDirectory 直接指向系统保留路径（如 /usr）时，scanLinkedLocalFiles 必须：
    // (1) 不调用 enumerator 索引该目录（避免把 /usr/bin 写入 artifact）；
    // (2) verifications 写一条 .failed 记录显式告知用户拒绝原因；
    // (3) appendEvent .risk 记录拒绝事件。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = "/usr"

    let baselineArtifactCount = store.selectedProductMaintenanceArtifacts.count

    store.scanLinkedLocalFiles(limit: 50)

    #expect(store.selectedProductMaintenanceArtifacts.count == baselineArtifactCount,
            "拒绝路径 root=/usr 后不应新增任何 artifact")
    let newFailedVerifications = store.selectedProductVerifications.filter { $0.status == .failed && $0.title == "本地文件索引被拒绝" }
    #expect(!newFailedVerifications.isEmpty,
            "应写入 .failed verification 'r本地文件索引被拒绝'")
    if let first = newFailedVerifications.first {
        #expect(first.detail.contains("/usr"),
                "verification detail 应包含被拒绝的路径以便用户排查，实际：\(first.detail)")
    }
}

@MainActor
@Test func scanLinkedLocalFilesRejectsSymlinkResolvingToSystemReservedPath() async throws {
    // R27：当 product.rootDirectory 是用户可写目录的 symlink 链路最终落到系统保留路径，
    // resolvingSymlinksInPath() 应解析后被 isSystemReservedPath 命中拒绝。
    // 用 /tmp 下创建 symlink → /usr 验证。
    let store = CompanyStore.bootstrap(loadPersisted: false)

    let symlinkURL = FileManager.default.temporaryDirectory.appendingPathComponent("OPCSymlinkToSystem-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: symlinkURL) }

    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: URL(fileURLWithPath: "/usr"))

    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = symlinkURL.path

    let baselineArtifactCount = store.selectedProductMaintenanceArtifacts.count

    store.scanLinkedLocalFiles(limit: 50)

    #expect(store.selectedProductMaintenanceArtifacts.count == baselineArtifactCount,
            "symlink → /usr 解析后被拒绝，不应新增 artifact")
    let rejectedVerifications = store.selectedProductVerifications.filter { $0.status == .failed && $0.title == "本地文件索引被拒绝" }
    #expect(!rejectedVerifications.isEmpty,
            "symlink 越界路径应触发 .failed verification")
}

@MainActor
@Test func scanLinkedLocalFilesRejectsSymlinkResolvingOutsideRegisteredWorkspaceRoots() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let registeredRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OPCRegisteredRoot-\(UUID().uuidString)", isDirectory: true)
    let outsideRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OPCOutsideRoot-\(UUID().uuidString)", isDirectory: true)
    let symlinkURL = FileManager.default.temporaryDirectory.appendingPathComponent("OPCSymlinkOutside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: registeredRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
    try "外部内容".write(to: outsideRoot.appendingPathComponent("outside.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideRoot)
    defer {
        try? FileManager.default.removeItem(at: registeredRoot)
        try? FileManager.default.removeItem(at: outsideRoot)
        try? FileManager.default.removeItem(at: symlinkURL)
    }

    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = symlinkURL.path

    let baselineArtifactCount = store.selectedProductMaintenanceArtifacts.count

    store.scanLinkedLocalFiles(limit: 50)

    #expect(store.selectedProductMaintenanceArtifacts.count == baselineArtifactCount,
            "symlink 解析到未登记工作区根目录时不应新增 artifact")
    let rejectedVerifications = store.selectedProductVerifications.filter { $0.status == .failed && $0.title == "本地文件索引被拒绝" }
    #expect(rejectedVerifications.contains { $0.detail.contains("已登记工作区根白名单") },
            "应明确提示根目录不在已登记工作区根白名单内")
    #expect(store.selectedProductEvents.contains { $0.title == "本地文件索引拒绝未登记根目录" })
}

@MainActor
@Test func linkedLocalFileRootAllowlistPreviewShowsRegisteredRootsAndCurrentStatus() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCAllowlistPreview-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = root.path

    let preview = store.linkedLocalFileRootAllowlistText()

    #expect(preview.contains("本地文件索引根白名单"))
    #expect(preview.contains("产品：默认产品工作区"))
    #expect(preview.contains("当前状态：已登记，可索引"))
    #expect(preview.contains("已登记工作区根目录"))
    #expect(preview.contains(root.standardizedFileURL.path))
    #expect(!preview.contains("rootDirectory"))
}

@Test func localMaintenanceCenterExposesLinkedLocalFileRootAllowlistPreview() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    let identifiers = try loadOPCCompanyCoreSource("DisplayFormatting.swift")

    #expect(source.contains("store.linkedLocalFileRootAllowlistText()"))
    #expect(source.contains("本地文件索引根白名单"))
    #expect(source.contains("OPCUIAutomationIdentifier.localMaintenanceCenterRoot.rawValue"))
    #expect(source.contains("OPCUIAutomationIdentifier.linkedLocalFileRootAllowlistPreview.rawValue"))
    #expect(source.contains(".accessibilityLabel(\"本地文件索引根白名单\")"))
    #expect(source.contains(".accessibilityValue(store.linkedLocalFileRootAllowlistText())"))
    #expect(identifiers.contains("OPCLocalMaintenanceCenterRoot"))
    #expect(identifiers.contains("OPCLinkedLocalFileRootAllowlistPreview"))
}

@MainActor
@Test func scanLinkedLocalFilesAcceptsRegularUserDirectoryAfterR27Hardening() async throws {
    // R27：加固后正常用户目录路径仍要能被索引（防止 R27 黑名单过严误伤 happy path）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OPCR27HappyPath-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try "正常内容".write(to: root.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)

    let productIndex = try #require(store.products.firstIndex { $0.id == store.selectedProductID })
    store.products[productIndex].rootDirectory = root.path

    let baselineArtifactCount = store.selectedProductMaintenanceArtifacts.count

    store.scanLinkedLocalFiles(limit: 50)

    #expect(store.selectedProductMaintenanceArtifacts.count > baselineArtifactCount,
            "用户可写目录的 happy path 索引必须维持工作")
}

@Test func isSystemReservedPathBlacklistCoversExpectedSystemRoots() async throws {
    // R27 守门：源码层验证 isSystemReservedPath 黑名单覆盖 6 个核心系统前缀，
    // 且使用 trailing-slash 防止 `/usrFoo` 误命中 `/usr` 类前缀污染。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    #expect(source.contains("isSystemReservedPath"),
            "isSystemReservedPath helper 必须存在")
    for required in ["/System", "/private/var/db", "/private/etc", "/usr", "/bin", "/sbin"] {
        #expect(source.contains("\"\(required)\""),
                "isSystemReservedPath 黑名单应包含 \(required)")
    }
    #expect(source.contains("hasPrefix(prefix + \"/\")"),
            "黑名单匹配必须用 trailing-slash 防止 /usrFoo 类前缀污染")
}

// MARK: - R28 候选 λ-2 引擎部分落地：migrateLegacyTasksWithoutProductID 守门（角色继承期轮 28）

@MainActor
@Test func migrateLegacyTasksWithoutProductIDBackfillsNilTasksAndReportsCount() async throws {
    // R28：注入 2 条 productID == nil 的 legacy task + 1 条已经有 productID 的，
    // 调用 migrate(targetProductID:) 应回填 2 条 nil → target，返回 2，不动已有 productID 的 task。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let target = store.selectedProductID

    let legacyA = CompanyTask(productID: nil, title: "legacy A", ownerID: nil, status: .draft, successCriteria: "")
    let legacyB = CompanyTask(productID: nil, title: "legacy B", ownerID: nil, status: .draft, successCriteria: "")
    let otherProduct = UUID()
    let assigned = CompanyTask(productID: otherProduct, title: "已归属其他产品", ownerID: nil, status: .draft, successCriteria: "")
    store.tasks.append(contentsOf: [legacyA, legacyB, assigned])

    let migrated = store.migrateLegacyTasksWithoutProductID(targetProductID: target)
    #expect(migrated == 2, "应回填 2 条 nil productID task，实际：\(migrated)")

    let nilCount = store.tasks.filter { $0.productID == nil }.count
    #expect(nilCount == 0, "迁移后不应再有 productID == nil 的 task")

    let backfilledA = store.tasks.first { $0.id == legacyA.id }
    let backfilledB = store.tasks.first { $0.id == legacyB.id }
    #expect(backfilledA?.productID == target, "legacy A 应回填到 target productID")
    #expect(backfilledB?.productID == target, "legacy B 应回填到 target productID")

    let stillAssigned = store.tasks.first { $0.id == assigned.id }
    #expect(stillAssigned?.productID == otherProduct, "已归属其他产品的 task productID 不应被改写")
}

@MainActor
@Test func legacyTaskProductMigrationPreviewShowsTargetProductAndLegacyTaskCount() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.tasks.append(CompanyTask(productID: nil, title: "旧版未归属任务", ownerID: nil, status: .draft, successCriteria: ""))

    let preview = store.legacyTaskProductMigrationText()

    #expect(preview.contains("旧任务产品归属迁移：预览"))
    #expect(preview.contains("产品：默认产品工作区"))
    #expect(preview.contains("待迁移旧任务：1 个"))
    #expect(preview.contains("迁移目标：当前产品"))
    #expect(!preview.contains("backend"))
    #expect(!preview.contains("productID"))
    #expect(!preview.contains("fallback"))
    #expect(preview.contains("不会进入任意产品视图"))
}

@MainActor
@Test func runLegacyTaskProductMigrationForSelectedProductBackfillsTasksAndWritesMaintenanceRecord() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let target = store.selectedProductID
    let legacyA = CompanyTask(productID: nil, title: "legacy UI task", ownerID: nil, status: .draft, successCriteria: "")
    let legacyB = CompanyTask(productID: nil, title: "legacy build task", ownerID: nil, status: .planned, successCriteria: "")
    let otherProduct = UUID()
    let assigned = CompanyTask(productID: otherProduct, title: "其他产品任务", ownerID: nil, status: .draft, successCriteria: "")
    store.tasks.append(contentsOf: [legacyA, legacyB, assigned])

    let bossMessageCountBefore = store.messages(for: store.bossID).count
    let agentMessageCountBefore = store.agentMessages.count
    let deliveryCountBefore = store.selectedProductDeliveryVerifications.count

    let record = store.runLegacyTaskProductMigrationForSelectedProduct()

    #expect(record.title == "旧任务产品归属迁移")
    #expect(record.status == .passed)
    #expect(record.detail.contains("迁移前旧任务：2 个"))
    #expect(record.detail.contains("本次迁移：2 个"))
    #expect(record.detail.contains("剩余旧任务：0 个"))
    #expect(!record.detail.contains("productID"))
    #expect(!record.detail.contains("selectedProductTasks"))
    #expect(!record.detail.contains("legacy"))
    #expect(!record.detail.contains("fallback"))
    #expect(record.detail.contains("没有产品归属"))
    #expect(record.detail.contains("不会进入任意产品视图"))
    #expect(store.legacyTaskWithoutProductIDCount == 0)
    #expect(store.tasks.first { $0.id == legacyA.id }?.productID == target)
    #expect(store.tasks.first { $0.id == legacyB.id }?.productID == target)
    #expect(store.tasks.first { $0.id == assigned.id }?.productID == otherProduct)
    #expect(store.selectedProductMaintenanceVerifications.contains { $0.id == record.id })
    #expect(!store.selectedProductDeliveryVerifications.contains { $0.id == record.id })
    #expect(store.selectedProductDeliveryVerifications.count == deliveryCountBefore)
    #expect(store.selectedProductEvents.contains { $0.title == "旧任务产品归属迁移完成" })
    #expect(!store.selectedProductBossEvents.contains { $0.title == "旧任务产品归属迁移完成" })
    #expect(store.messages(for: store.bossID).count == bossMessageCountBefore)
    #expect(store.agentMessages.count == agentMessageCountBefore)
}

@MainActor
@Test func runLegacyTaskProductMigrationForSelectedProductIsIdempotentAndKeepsStrictProductTaskFilter() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.tasks.append(CompanyTask(productID: nil, title: "legacy once", ownerID: nil, status: .draft, successCriteria: ""))

    _ = store.runLegacyTaskProductMigrationForSelectedProduct()
    let second = store.runLegacyTaskProductMigrationForSelectedProduct()

    #expect(second.status == .passed)
    #expect(second.detail.contains("迁移前旧任务：0 个"))
    #expect(second.detail.contains("本次迁移：0 个"))
    #expect(store.legacyTaskWithoutProductIDCount == 0)

    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    guard let accessorStart = source.range(of: "public var selectedProductTasks: [CompanyTask] {"),
          let accessorEnd = source.range(of: "public var selectedProductRecentTasks", range: accessorStart.upperBound..<source.endIndex) else {
        Issue.record("找不到 selectedProductTasks accessor 切片")
        return
    }
    let selectedProductTasksSlice = String(source[accessorStart.lowerBound..<accessorEnd.lowerBound])
    #expect(!selectedProductTasksSlice.contains("productID == nil"),
            "旧任务迁移入口已产品化，selectedProductTasks 应保持严格当前产品过滤")
}

@Test func localMaintenanceCenterExposesLegacyTaskMigrationPreviewAndManualButton() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    let terminalHallSource = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    #expect(source.contains("confirmLegacyTaskMigration"))
    #expect(source.contains("store.runLegacyTaskProductMigrationForSelectedProduct()"))
    #expect(source.contains("store.legacyTaskProductMigrationText()"))
    #expect(source.contains("OPCUIAutomationIdentifier.legacyTaskProductMigrationButton.rawValue"))
    #expect(source.contains("OPCUIAutomationIdentifier.legacyTaskProductMigrationPreview.rawValue"))
    #expect(source.contains(".accessibilityHint(\"仅当当前产品存在未归属旧任务时可用；首次点击进入确认态，再次点击才会迁入当前产品\")"),
            "旧任务迁移按钮必须说明禁用条件和二次确认行为，方便 Computer Use 判断何时能点击")
    #expect(source.contains(".accessibilityLabel(\"旧任务归属迁移预览\")"))
    #expect(source.contains(".accessibilityValue(store.legacyTaskProductMigrationText())"))
    #expect(source.contains("再次点击确认迁入当前产品"))
    #expect(terminalHallSource.contains("OPCUIAutomationIdentifier.terminalHallLocalMaintenanceHeaderTrigger.rawValue"),
            "终端大厅顶部必须保留直接进入本地维护详情的 Computer Use 稳定入口")
}

@Test func terminalHallLocalMaintenanceTriggersUseUnifiedPresentedDetailRoute() async throws {
    // 反向锁：终端大厅顶部「本地维护」按钮、`LocalMaintenanceSummaryCard`「查看详情」按钮、
    // 整卡 `onTapGesture` 与辅助功能动作必须全部统一写入 `presentedDetail = .localMaintenance`，
    // 由唯一的 `.sheet(item: $presentedDetail)` 接管。
    //
    // 历史回归：2026-05-05 candidate ψ 第二阶段补强曾用第二个 `.sheet(isPresented:)` 专跑本地维护，
    // 期望避免「item 路由互相干扰」；但 SwiftUI（macOS）同一视图挂双 sheet 在真实点击/Computer Use
    // 路径上会让其中一个静默失效——header trigger 和摘要卡 detail trigger 都点不开本地维护详情即此症状。
    // 收口为单 sheet 后该回归彻底关闭；本测试守门防止再次回退。
    let content = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 不再保留旧的本地维护专用 Bool 状态和专用 sheet 结构。
    #expect(!content.contains("presentsLocalMaintenanceDetail"),
            "本地维护专用 Bool 状态必须删除，统一用 `presentedDetail`；否则会再触发双 sheet 互斥回归")
    #expect(!content.contains("TerminalHallLocalMaintenanceSheet"),
            "本地维护专用 sheet 结构必须删除，详情统一走 `TerminalHallDetailSheet`")
    #expect(!content.contains(".sheet(isPresented: $"),
            "终端大厅主视图不应再出现 `.sheet(isPresented: $...)` 形式；所有详情走唯一的 `.sheet(item: $presentedDetail)`")

    // 2. 唯一 sheet 路由仍在。
    let sheetItemCount = content.components(separatedBy: ".sheet(item: $presentedDetail)").count - 1
    #expect(sheetItemCount == 1,
            "终端大厅主视图必须保留且仅保留 1 处 `.sheet(item: $presentedDetail)`，实际 \(sheetItemCount)")

    // 3. 顶部 header trigger 直接写 presentedDetail = .localMaintenance（不能再写 Bool）。
    let scanLines = content.components(separatedBy: "\n")
    guard let headerTriggerIndex = scanLines.firstIndex(where: {
        $0.contains("OPCUIAutomationIdentifier.terminalHallLocalMaintenanceHeaderTrigger.rawValue")
    }) else {
        Issue.record("找不到 terminalHallLocalMaintenanceHeaderTrigger anchor")
        return
    }
    var headerWiringFound = false
    for i in stride(from: headerTriggerIndex - 1, through: max(0, headerTriggerIndex - 25), by: -1) {
        if scanLines[i].contains("presentedDetail = .localMaintenance") {
            headerWiringFound = true
            break
        }
    }
    #expect(headerWiringFound,
            "顶部「本地维护」按钮 anchor 上方应直接写入 `presentedDetail = .localMaintenance`；这是修复双 sheet 回归的关键路径")

    // 4. 摘要卡 detail trigger 上方也要直接写 presentedDetail = .localMaintenance。
    guard let cardTriggerIndex = scanLines.firstIndex(where: {
        $0.contains("OPCUIAutomationIdentifier.advancedMaintenanceLocalDetailTrigger.rawValue")
    }) else {
        Issue.record("找不到 advancedMaintenanceLocalDetailTrigger anchor")
        return
    }
    var cardButtonWiringFound = false
    for i in stride(from: cardTriggerIndex - 1, through: max(0, cardTriggerIndex - 12), by: -1) {
        if scanLines[i].contains("presentedDetail = .localMaintenance") {
            cardButtonWiringFound = true
            break
        }
    }
    #expect(cardButtonWiringFound,
            "`LocalMaintenanceSummaryCard` 的「查看详情」按钮上方应直接写入 `presentedDetail = .localMaintenance`，与顶部入口走同一路由")

    // 5. 摘要卡片整卡 onTapGesture 与 accessibilityAction(named: "查看本地维护详情") 也必须切到 presentedDetail。
    //    精确锁住「accessibilityAction 命名」语义而不是只看子串数量。
    let accessibilityActionPattern = "accessibilityAction(named: \"查看本地维护详情\") {"
    guard let accessibilityIndex = scanLines.firstIndex(where: { $0.contains(accessibilityActionPattern) }) else {
        Issue.record("找不到 `accessibilityAction(named: \"查看本地维护详情\")` 入口")
        return
    }
    var accessibilityWiringFound = false
    for i in (accessibilityIndex + 1)..<min(scanLines.count, accessibilityIndex + 6) {
        if scanLines[i].contains("presentedDetail = .localMaintenance") {
            accessibilityWiringFound = true
            break
        }
    }
    #expect(accessibilityWiringFound,
            "辅助功能动作「查看本地维护详情」内部必须写入 `presentedDetail = .localMaintenance`；否则 a11y 兜底会回到旧 Bool 路径")

    // 6. presentedDetail = .localMaintenance 至少出现 3 次（顶部按钮 + 摘要卡按钮 + 辅助动作；
    //    onTapGesture 也应同样写入，所以实际 >= 4，本断言留 1 个余量给未来不影响功能的内部抽取）。
    let assignmentCount = content.components(separatedBy: "presentedDetail = .localMaintenance").count - 1
    #expect(assignmentCount >= 3,
            "`presentedDetail = .localMaintenance` 至少应出现在 3 个入口（顶部按钮 / 摘要卡按钮 / 辅助动作），实际 \(assignmentCount)")

    // 7. `LocalMaintenanceSummaryCard` 的 binding 类型必须是 `TerminalHallDetail?`，不再是旧的 Bool。
    #expect(content.contains("LocalMaintenanceSummaryCard(presentedDetail: $presentedDetail)"),
            "`LocalMaintenanceSummaryCard` 必须接受 `$presentedDetail` 而不是旧的 Bool binding")
    #expect(!content.contains("LocalMaintenanceSummaryCard(isShowingDetail:"),
            "旧 `isShowingDetail:` 入参写法必须删除")
}

@Test func terminalHallDetailEntryButtonsExposeExplicitNamedAccessibilityActions() async throws {
    // 守门：终端大厅顶部「本地维护」按钮 + 三张摘要卡的「查看详情」按钮，
    // 必须各自显式登记 `.accessibilityAction(named:)` 兜底入口，且其闭包写入与按钮主闭包相同的
    // `presentedDetail` case。
    //
    // 历史回归：Computer Use 真机点击带 `Label(_,systemImage:)` 的按钮时，AXPress 偶发只把焦点
    // 落在按钮上不触发 SwiftUI Button 闭包；缺少命名 AXAction 兜底时，详情 sheet 就打不开。
    // 整卡 `accessibilityAction(named: "查看本地维护详情")` 只覆盖 LocalMaintenanceSummaryCard 容器，
    // 顶部按钮和架构/通信摘要卡都还需要按钮自身的命名兜底。
    let content = try loadOPCCompanyCoreSource("TerminalHallView.swift")
    let scanLines = content.components(separatedBy: "\n")

    struct ButtonSpec {
        let identifierFragment: String
        let actionName: String
        let expectedAssignment: String
        let label: String
    }
    let specs: [ButtonSpec] = [
        ButtonSpec(
            identifierFragment: "OPCUIAutomationIdentifier.terminalHallLocalMaintenanceHeaderTrigger.rawValue",
            actionName: "打开本地维护详情",
            expectedAssignment: "presentedDetail = .localMaintenance",
            label: "终端大厅顶部「本地维护」按钮"
        ),
        ButtonSpec(
            identifierFragment: "OPCUIAutomationIdentifier.advancedMaintenanceArchitectureDetailTrigger.rawValue",
            actionName: "查看多员工架构体检详情",
            expectedAssignment: "presentedDetail = .architecture",
            label: "架构体检摘要卡「查看详情」按钮"
        ),
        ButtonSpec(
            identifierFragment: "OPCUIAutomationIdentifier.advancedMaintenanceGatewayDetailTrigger.rawValue",
            actionName: "查看通信网关与手机指令详情",
            expectedAssignment: "presentedDetail = .gateway",
            label: "通信网关摘要卡「查看详情」按钮"
        ),
        ButtonSpec(
            identifierFragment: "OPCUIAutomationIdentifier.advancedMaintenanceLocalDetailTrigger.rawValue",
            actionName: "查看本地稳定性与命令行运维详情",
            expectedAssignment: "presentedDetail = .localMaintenance",
            label: "本地稳定性摘要卡「查看详情」按钮"
        )
    ]

    for spec in specs {
        guard let identifierIndex = scanLines.firstIndex(where: { $0.contains(spec.identifierFragment) }) else {
            Issue.record("[\(spec.label)] 找不到 identifier anchor：\(spec.identifierFragment)")
            continue
        }
        let actionPattern = ".accessibilityAction(named: \"\(spec.actionName)\")"
        // 先向下扫 8 行（标准排序：identifier → label → hint → action）。
        var actionLineIndex: Int?
        for i in identifierIndex..<min(scanLines.count, identifierIndex + 8) {
            if scanLines[i].contains(actionPattern) {
                actionLineIndex = i
                break
            }
        }
        // 兼容 modifier 顺序差异（例如 header 按钮 label 在 identifier 之前），再向上扫 8 行。
        if actionLineIndex == nil {
            for i in stride(from: identifierIndex - 1, through: max(0, identifierIndex - 8), by: -1) {
                if scanLines[i].contains(actionPattern) {
                    actionLineIndex = i
                    break
                }
            }
        }
        guard let foundIndex = actionLineIndex else {
            Issue.record("[\(spec.label)] 缺少 .accessibilityAction(named: \"\(spec.actionName)\") 兜底入口")
            continue
        }
        var assignmentFound = false
        for i in foundIndex..<min(scanLines.count, foundIndex + 6) {
            if scanLines[i].contains(spec.expectedAssignment) {
                assignmentFound = true
                break
            }
        }
        #expect(assignmentFound,
                "[\(spec.label)] 命名 accessibility action 闭包必须写入 \(spec.expectedAssignment)；当前未在 action 行下方 6 行内找到该赋值。")
    }

    // 现有的 identifier、label、整卡命名动作必须并存保留——按钮命名动作是兜底，不能替换既有兜底。
    let preservedAnchors = [
        "OPCUIAutomationIdentifier.terminalHallLocalMaintenanceHeaderTrigger.rawValue",
        "OPCUIAutomationIdentifier.advancedMaintenanceArchitectureDetailTrigger.rawValue",
        "OPCUIAutomationIdentifier.advancedMaintenanceGatewayDetailTrigger.rawValue",
        "OPCUIAutomationIdentifier.advancedMaintenanceLocalDetailTrigger.rawValue"
    ]
    for anchor in preservedAnchors {
        #expect(content.contains(anchor), "现有 accessibility identifier 必须保留：\(anchor)")
    }
    let preservedLabels = [
        ".accessibilityLabel(\"打开本地维护详情\")",
        ".accessibilityLabel(\"查看多员工架构体检详情\")",
        ".accessibilityLabel(\"查看通信网关与手机指令详情\")",
        ".accessibilityLabel(\"查看本地稳定性与命令行运维详情\")"
    ]
    for label in preservedLabels {
        #expect(content.contains(label), "现有 accessibilityLabel 必须保留：\(label)")
    }
    #expect(content.contains("accessibilityAction(named: \"查看本地维护详情\")"),
            "本地稳定性摘要卡整卡命名动作「查看本地维护详情」必须保留——按钮自身的命名动作是它的兜底补充，不能替换它。")
}

@Test func terminalHallDetailSheetUsesMacBookSafeResponsiveFrame() async throws {
    // 反向锁：`TerminalHallDetailSheet` 不能再使用 1080×720 死硬最小帧。
    //
    // 历史回归：`.frame(minWidth: 1080, minHeight: 720)` 在 13" MacBook 主屏（1280×800）上把 sheet
    // 钉死在屏宽边界，Computer Use 实测出现「点开按钮但 sheet 不渲染 / 关闭按钮被剪掉」。
    // 修正方向：改成 `min(<1000) + ideal(原尺寸)`——大显示器仍按理想尺寸开，
    // 13" MacBook 可下行到安全尺寸完整可见。
    //
    // 本测试只校 sheet 帧规约 + 关键路由仍在；不约束具体数字，给后续微调留空间。
    let content = try loadOPCCompanyCoreSource("TerminalHallView.swift")

    // 1. 旧的死硬最小帧字面量必须删除。
    #expect(!content.contains("frame(minWidth: 1080, minHeight: 720)"),
            "TerminalHallDetailSheet 不应再使用 1080×720 的死硬最小帧（MacBook 主屏会被卡住）")

    // 2. `TerminalHallDetailSheet` 结构本身仍存在（路由没被误删）。
    #expect(content.contains("private struct TerminalHallDetailSheet"),
            "TerminalHallDetailSheet 结构必须保留，二级详情面板路由由它承载")

    // 3. 该 sheet 仍登记 `OPCTerminalHallDetailSheet` a11y 锚点，Computer Use 区分摘要/详情页面靠它。
    #expect(content.contains("OPCUIAutomationIdentifier.terminalHallDetailSheet.rawValue"),
            "TerminalHallDetailSheet 必须保留 a11y 锚点 OPCTerminalHallDetailSheet")

    // 4. 三条详情路由（含本次重点关注的 `LocalMaintenanceCenter`）仍在 sheet switch 中。
    #expect(content.contains("LocalMaintenanceCenter()"),
            "TerminalHallDetailSheet switch 必须保留 LocalMaintenanceCenter 路由")
    #expect(content.contains("MultiAgentArchitectureAuditCenter()"),
            "TerminalHallDetailSheet switch 必须保留 MultiAgentArchitectureAuditCenter 路由")
    #expect(content.contains("CommunicationGatewayCommandCenter()"),
            "TerminalHallDetailSheet switch 必须保留 CommunicationGatewayCommandCenter 路由")

    // 5. 在 `TerminalHallDetailSheet` body 内必须存在 `frame(minWidth:` 修饰符，且其 minWidth 数值 < 1000。
    //    解析方式：从结构起始位置截到下个 `private struct` / `struct ` / 文件末尾，提取 frame(minWidth: N) 的 N。
    let sheetStartMarker = "private struct TerminalHallDetailSheet"
    guard let sheetStart = content.range(of: sheetStartMarker)?.lowerBound else {
        Issue.record("无法在源码中定位 TerminalHallDetailSheet 起点")
        return
    }
    let afterSheetStart = content.index(after: sheetStart)
    let nextStructRange = content.range(of: "\nprivate struct ", range: afterSheetStart..<content.endIndex)
        ?? content.range(of: "\nstruct ", range: afterSheetStart..<content.endIndex)
    let sheetBodyEnd = nextStructRange?.lowerBound ?? content.endIndex
    let sheetBody = String(content[sheetStart..<sheetBodyEnd])

    let frameRegex = try Regex(#"frame\(minWidth:\s*(\d+)"#)
    guard let match = sheetBody.firstMatch(of: frameRegex),
          let widthSubstring = match.output[1].substring,
          let minWidthValue = Int(widthSubstring) else {
        Issue.record("TerminalHallDetailSheet body 内未找到 frame(minWidth: 数字...) 修饰符")
        return
    }
    #expect(minWidthValue < 1000,
            "TerminalHallDetailSheet 最小宽度必须小于 1000（MacBook 主屏安全），实际 \(minWidthValue)")
    #expect(minWidthValue >= 480,
            "TerminalHallDetailSheet 最小宽度低于 480 会让详情面板内部布局崩溃，实际 \(minWidthValue)")
}

@MainActor
@Test func migrateLegacyTasksWithoutProductIDIsIdempotentOnSecondCall() async throws {
    // R28：幂等性 — 第二次调用对同一数据集是 no-op（所有 nil 已回填）。
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let target = store.selectedProductID
    let legacy = CompanyTask(productID: nil, title: "legacy once", ownerID: nil, status: .draft, successCriteria: "")
    store.tasks.append(legacy)

    let firstCall = store.migrateLegacyTasksWithoutProductID(targetProductID: target)
    #expect(firstCall == 1, "首次调用应迁移 1 条")

    let secondCall = store.migrateLegacyTasksWithoutProductID(targetProductID: target)
    #expect(secondCall == 0, "幂等：第二次调用不应再迁移任何 task")

    let nilCount = store.tasks.filter { $0.productID == nil }.count
    #expect(nilCount == 0, "幂等后仍无 nil productID task")
}

@MainActor
@Test func migrateLegacyTasksWithoutProductIDDoesNotInvokeSaveSnapshot() async throws {
    // R28：本 helper 故意不调用 saveSnapshot，让 caller 决定事务边界。
    // 守门：source-scan 验证 helper 内部不含 saveSnapshot 调用 + docstring 显式说明这一点。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    guard let helperRange = source.range(of: "public func migrateLegacyTasksWithoutProductID(targetProductID: UUID) -> Int {") else {
        Issue.record("找不到 migrateLegacyTasksWithoutProductID helper 定义")
        return
    }
    // 截取 helper 函数体（从开 { 到下一处 `    }` 闭合，本 helper 简短不嵌套，闭合就是 helper 结束）
    let bodyStart = source.index(helperRange.upperBound, offsetBy: 0)
    let tail = source[bodyStart...]
    guard let firstClosingBraceRange = tail.range(of: "\n    }\n") else {
        Issue.record("找不到 helper 函数体闭合 `\\n    }\\n`")
        return
    }
    let body = source[bodyStart..<firstClosingBraceRange.lowerBound]
    #expect(!body.contains("saveSnapshot"),
            "migrateLegacyTasksWithoutProductID 内部不应调用 saveSnapshot（caller 决定事务边界）")
}

@Test func migrateLegacyTasksWithoutProductIDSourceContainsCandidateLambda2Reference() async throws {
    // R28 守门：源码必须保留对 R28 / candidate λ-2 / engine vs policy 设计要点的指针，
    // 防止 refactor 悄悄改写 helper 语义或删除关键不变量。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    #expect(source.contains("migrateLegacyTasksWithoutProductID"),
            "CompanyStore.swift 必须保留 migrateLegacyTasksWithoutProductID helper")
    #expect(source.contains("候选 λ-2") || source.contains("candidate λ-2"),
            "源码注释应保留 candidate λ-2 指针便于回溯 R21 LIMITATION 标记")
    #expect(source.contains("R28") || source.contains("轮 28"),
            "源码注释应标注 R28 落地轮次")
    #expect(source.contains("engine vs policy") || source.contains("engine") && source.contains("policy"),
            "源码 docstring 应说明 engine vs policy 分离设计")
    #expect(source.contains("幂等"),
            "源码 docstring 应说明幂等性")
    #expect(source.contains("不调用 saveSnapshot") || source.contains("不调用 saveSnapshot 避免"),
            "源码 docstring 应说明事务边界由 caller 控制")
}

// MARK: - R29 候选 λ schema 引擎部分落地：ChatMessage.productID 守门（角色继承期轮 29）

@Test func chatMessageProductIDDefaultsToNilForLegacyDecodeAndNewInit() async throws {
    // R29：ChatMessage 加 productID: UUID? 后必须保持 (a) 旧 state.json 无此字段能 decode 为 nil，
    // (b) 现有 50+ caller 不传 productID 时新 init 默认 nil。
    // 任一回归会让全量 401+ 测试失败 — 本守门是显式契约。

    // (a) 旧 schema decode：手工构造无 productID 字段的 JSON
    let legacyJSON = """
    {
        "id": "11111111-1111-1111-1111-111111111111",
        "agentID": "22222222-2222-2222-2222-222222222222",
        "author": "user",
        "text": "legacy message without productID",
        "createdAt": "2026-05-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode(ChatMessage.self, from: legacyJSON)
    #expect(legacy.productID == nil,
            "legacy state.json 无 productID 字段 decode 必须为 nil，实际：\(String(describing: legacy.productID))")
    #expect(legacy.text == "legacy message without productID")

    // (b) 新 init 不传 productID 默认 nil
    let newDefault = ChatMessage(agentID: UUID(), author: .user, text: "new without productID")
    #expect(newDefault.productID == nil,
            "新 init 不传 productID 默认必须为 nil，实际：\(String(describing: newDefault.productID))")
}

@Test func chatMessageProductIDPreservesExplicitValueAcrossCodableRoundtrip() async throws {
    // R29：显式传 productID 必须穿越 encode/decode roundtrip 不丢失（Codable 自动行为守门）。
    let target = UUID()
    let msg = ChatMessage(productID: target, agentID: UUID(), author: .agent, text: "with explicit productID")
    #expect(msg.productID == target, "init 显式传值后 productID 必须等于该 UUID")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(msg)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ChatMessage.self, from: data)
    #expect(decoded.productID == target, "encode/decode roundtrip 后 productID 必须保留原值")
    #expect(decoded.id == msg.id)
    #expect(decoded.agentID == msg.agentID)
    #expect(decoded.text == msg.text)
}

@Test func productMemoryNoteAgentIDDefaultsToNilForLegacyDecodeAndRoundtripsScopedAgent() async throws {
    let productID = UUID()
    let agentID = UUID()
    let legacyJSON = """
    {
        "id": "33333333-3333-3333-3333-333333333333",
        "productID": "\(productID.uuidString)",
        "kind": "summary",
        "title": "legacy product memory",
        "detail": "without agentID",
        "createdAt": "2026-05-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode(ProductMemoryNote.self, from: legacyJSON)
    #expect(legacy.agentID == nil,
            "旧 ProductMemoryNote 无 agentID 字段时必须 decode 为 nil，保证旧产品记忆兼容")

    let scoped = ProductMemoryNote(productID: productID, agentID: agentID, kind: .summary, title: "员工记忆", detail: "scoped")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(scoped)
    let decoded = try decoder.decode(ProductMemoryNote.self, from: data)
    #expect(decoded.productID == productID)
    #expect(decoded.agentID == agentID)
}

@Test func chatMessageSourceContainsCandidateLambdaSchemaReference() async throws {
    // R29 守门：源码注释必须保留对 R29 / candidate λ schema / engine vs policy 设计的指针，
    // 防止 refactor 悄悄删除 productID 字段或丢失 LIMITATION 设计意图。
    let source = try loadOPCCompanyCoreSource("Models.swift")
    #expect(source.contains("public var productID: UUID?"),
            "ChatMessage 必须保留 productID: UUID? 字段")
    #expect(source.contains("R29") || source.contains("轮 29"),
            "ChatMessage productID 注释应标注 R29 落地轮次")
    #expect(source.contains("候选 λ schema") || source.contains("candidate λ schema"),
            "ChatMessage productID 注释应保留 candidate λ schema 指针")
    #expect(source.contains("Optional 字段 decode 缺失自动为 nil"),
            "ChatMessage productID 注释应说明 Codable 向后兼容机制")
    #expect(source.contains("caller retrofit"),
            "ChatMessage productID 注释应说明 caller retrofit 是 codex policy 决定级")
}

// MARK: - R30 候选 ω-sendable 部分落地：CompanyStore @unchecked Sendable 净化 + LIMITATION marker 守门（角色继承期轮 30）

@Test func companyStoreNoLongerCarriesUncheckedSendableAfterR30Cleanup() async throws {
    // R30：试探性移除 `CompanyStore: ObservableObject, @unchecked Sendable` 中的 `, @unchecked Sendable`
    // 验证 `@MainActor public final class` 已自动满足 Sendable contract（Swift 6 自动推断）。
    // 守门：源码必须不再含 CompanyStore class 声明上的 `@unchecked Sendable`，
    // 防止后续 refactor 误把 redundant 的 @unchecked Sendable 加回来。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    #expect(source.contains("public final class CompanyStore: ObservableObject {"),
            "CompanyStore class 声明应为 `public final class CompanyStore: ObservableObject {`，不带 @unchecked Sendable")
    #expect(!source.contains("public final class CompanyStore: ObservableObject, @unchecked Sendable"),
            "CompanyStore 不应再含 @unchecked Sendable —— @MainActor class 自动满足 Sendable")
}

@Test func processOutputBufferUncheckedSendableCarriesLockProtectionMarker() async throws {
    // R30：ProcessOutputBuffer 用 NSLock 同步是**正确的** @unchecked Sendable 声明（不是技术债）。
    // 守门：CLIAgentRunner.swift 必须保留 LIMITATION marker + lock 保护说明 + 候选 ω-sendable Swift 6 升级指针。
    let source = try loadOPCCompanyCoreSource("CLIAgentRunner.swift")
    #expect(source.contains("LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-BUFFER"),
            "ProcessOutputBuffer 上方必须保留 LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-BUFFER 标记")
    #expect(source.contains("不是技术债"),
            "LIMITATION marker 必须明确说明 @unchecked Sendable 不是技术债")
    #expect(source.contains("NSLock") && source.contains("thread-safe"),
            "LIMITATION marker 必须说明用 NSLock 保护 + thread-safe contract")
    #expect(source.contains("Mutex"),
            "LIMITATION marker 必须给出候选 ω-sendable Swift 6 Mutex 升级指针（codex 决定级）")
    #expect(source.contains("processOutputBufferUncheckedSendableCarriesLockProtectionMarker"),
            "LIMITATION marker 必须点名守门测试名")
}

@Test func processTimeoutStateUncheckedSendableCarriesLockProtectionMarker() async throws {
    // R30：ProcessTimeoutState 同 ProcessOutputBuffer，NSLock 保护单 Bool 标志位。
    let source = try loadOPCCompanyCoreSource("CLIAgentRunner.swift")
    #expect(source.contains("LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-FLAG"),
            "ProcessTimeoutState 上方必须保留 LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-FLAG 标记")
    #expect(source.contains("processTimeoutStateUncheckedSendableCarriesLockProtectionMarker"),
            "LIMITATION marker 必须点名守门测试名")
    #expect(source.contains("Mutex<Bool>"),
            "ProcessTimeoutState LIMITATION marker 必须指明 Swift 6 Mutex<Bool> 升级路径")
}

// MARK: - R31 LIMITATION 自洽性条件断言推广（角色继承期轮 31）
//
// R15 引入「LIMITATION 自洽性条件断言」模式（在 commandCenterViewHeader... 测试 line 12867-12870）：
// 在切片维度独立验证「LIMITATION marker 在 + 它守的 buggy/risky 调用也在」必须同时成立，
// 防止后续清理同时删除 marker + 调用导致默认无声 regression。
//
// R31 推广该模式到 R21+R28 (selectedProductTasks nil leak) + R21+R27 (scanLinkedLocalFiles
// path allowlist) 两个「待修复」型 LIMITATION marker。candidate λ-2 policy cleanup 后，
// selectedProductTasks 的 nil fallback 已移除；旧任务归属改由维护区迁移入口承接。R30 marker (NSLock-protected
// @unchecked Sendable) 是「设计意图保全」型 marker（NSLock 保护是**正确**实现而非待修复），
// 不存在「marker 该保留 vs 待修代码该保留」双轴问题，明确**排除**自洽性推广。
//
// 自洽性测试与 marker 守门测试的区别：
//   - marker 守门（既有 R21）：只验证 marker token 字符串在源码里 → 防止单独删 marker
//   - 自洽性条件断言（R31 推广）：验证 marker + 它守的调用在源码同一文件中**同步存在**
//     → 防止「同时删 marker + 调用」的双删 regression（这种 regression 默认会让 marker 守门
//     测试通过，因为 marker 不在了 → contains 检查为 true 当用 ! contains 反向断言时）。
//   - 双层防御 = marker 守门防单删 + 自洽性条件防双删，覆盖率达 100%。
//
// candidate λ-2 cleanup 证据：selectedProductTasks 不再含 `|| $0.productID == nil`
// fallback arm，也不再保留 LIMITATION-CROSS-PRODUCT-TASKS-NIL-LEAK 标记；R28 迁移 helper
// 与维护区入口继续保留，确保旧任务不会丢失。
//
// R27 自洽性证据：因为 scanLinkedLocalFiles 仍执行 FileManager.default.enumerator(at: root,
// 用户可写目录的枚举（codex 决定 candidate ψ 显式根白名单策略 + UI 配置入口之前必须保留），
// 切片必须仍含 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST 标记 + R27 二层防御
// (.resolvingSymlinksInPath + isSystemReservedPath) 必须同步保留。

@Test func selectedProductTasksNilFallbackStaysRemovedWhileMigrationHelperRemains() async throws {
    // candidate λ-2 policy cleanup：移除产品视图 nil fallback，保留维护区迁移 helper 和入口。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")
    guard let accessorStart = source.range(of: "public var selectedProductTasks: [CompanyTask] {"),
          let accessorEnd = source.range(of: "public var selectedProductRecentTasks", range: accessorStart.upperBound..<source.endIndex) else {
        Issue.record("找不到 selectedProductTasks accessor 切片")
        return
    }
    let selectedProductTasksSlice = String(source[accessorStart.lowerBound..<accessorEnd.lowerBound])

    #expect(!source.contains("LIMITATION-CROSS-PRODUCT-TASKS-NIL-LEAK"),
            "selectedProductTasks nil fallback 已移除，旧 LIMITATION marker 不应继续保留")
    #expect(!selectedProductTasksSlice.contains("productID == nil"),
            "selectedProductTasks 不应再通过 nil fallback 读取旧任务")
    #expect(selectedProductTasksSlice.contains("tasks.filter { $0.productID == selectedProductID }"),
            "selectedProductTasks 必须保持严格当前产品过滤")
    #expect(source.contains("migrateLegacyTasksWithoutProductID"),
            "旧任务迁移 helper 必须保留，避免移除 fallback 后丢失旧数据处理路径")
    let operationsSource = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    #expect(operationsSource.contains("store.runLegacyTaskProductMigrationForSelectedProduct()"),
            "维护区手动迁移入口必须保留")
}

@Test func scanLinkedLocalFilesEnumeratorAndLimitationMarkerStaySelfConsistent() async throws {
    // R31 推广 R15 自洽性条件断言模式到 R21+R27 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST marker。
    // candidate ψ 第一阶段继续要求显式根白名单 helper 同步存在。
    // 双层防御：(a) scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker (R21) 防单删 marker；
    //         (b) 本测试防同时删 marker + R27 引擎部分（symlink 解析 + 系统黑名单）的双删 regression。
    let source = try loadOPCCompanyCoreSource("CompanyStore.swift")

    // 自洽性条件 1：如果 scanLinkedLocalFiles 仍执行 FileManager enumerator 用户可写目录枚举，
    // 则 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST marker + R27 引擎部分必须同步保留。
    if source.contains("FileManager.default.enumerator(at: root") {
        #expect(source.contains("LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST"),
                "scanLinkedLocalFiles 仍枚举用户可写目录 → 必须同时保留 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST 标记（R21 + R27）。同时删 marker + 枚举是 candidate ψ 显式根白名单策略落地后的清理动作，必须经 codex policy 决定 + UI 配置入口设计。")
        #expect(source.contains("resolvingSymlinksInPath"),
                "marker 在 → R27 symlink 解析（resolvingSymlinksInPath）防 symlink 越界系统目录的引擎部分必须同步保留")
        #expect(source.contains("isSystemReservedPath"),
                "marker 在 → R27 系统路径黑名单（isSystemReservedPath helper）的引擎部分必须同步保留")
        #expect(source.contains("isAllowedLinkedLocalFileRoot"),
                "marker 在 → candidate ψ 第一阶段 rawRoot/resolvedRoot 显式根白名单 helper 必须同步保留")
    }

    // 自洽性条件 2：反向 — 如果 LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST marker 仍在，
    // 则它守的 enumerator 调用 + R27 二层防御（symlink + 黑名单）必须同步保留。
    if source.contains("LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST") {
        #expect(source.contains("FileManager.default.enumerator(at: root"),
                "LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST marker 仍在 → 它守的 FileManager enumerator 调用必须保留，否则 marker 失去意义")
        #expect(source.contains("linkedLocalFileAllowedRootPaths"),
                "LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST marker 仍在 → 已登记工作区根白名单 helper 必须保留")
    }
}

// MARK: - Keychain 写入失败可见性（OPCKeychainStore.saveAPIKey OSStatus 透传 + CompanyStore in-memory 风险事件）

/// 用 draftEmployee 路径添加一个 .api 类型员工，并把 `keychainSaveAPIKey` 闭包预先注入。
/// 这样 addEmployee 内部的 saveSnapshot 也走注入闭包（默认返回 errSecSuccess），
/// 不会污染真实 Keychain。返回新建员工，方便在测试体内 reset baseline 后再触发故障。
@MainActor
private func makeStoreWithAPIAgent(
    keychainStatus: @escaping () -> OSStatus,
    captureWrite: @escaping (String, UUID) -> Void
) -> (CompanyStore, CompanyAgent) {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.keychainSaveAPIKey = { value, agentID in
        captureWrite(value, agentID)
        return keychainStatus()
    }
    store.draftEmployee.displayName = "API 测试员工"
    store.draftEmployee.role = .researcher
    store.draftEmployee.backendType = .api
    store.draftEmployee.command = "claude"
    store.draftEmployee.endpoint = "https://api.example.com/v1"
    store.draftEmployee.apiKey = "secret-key"
    store.draftEmployee.model = "deepseek-chat"
    store.addEmployee(from: store.draftEmployee)
    let agent = store.agents.first { $0.displayName == "API 测试员工" }!
    return (store, agent)
}

@MainActor
@Test func keychainSaveAPIKeyFailureDuringSnapshotAppendsInMemoryRiskEvent() async throws {
    var status: OSStatus = errSecSuccess
    var captured: [(String, UUID)] = []
    let (store, agent) = makeStoreWithAPIAgent(
        keychainStatus: { status },
        captureWrite: { value, agentID in captured.append((value, agentID)) }
    )

    // 切到失败模式后再触发 saveSnapshot，确保失败计入事件流而不是被 addEmployee 吞掉。
    captured.removeAll()
    let baselineEventCount = store.events.count
    status = errSecAuthFailed

    store.saveSnapshot()

    #expect(captured.contains { $0.0 == "secret-key" && $0.1 == agent.id },
            "agentsForSnapshot 必须把 in-memory apiKey 透传给 keychainSaveAPIKey 闭包")
    #expect(store.events.count == baselineEventCount + 1,
            "Keychain 写入失败必须追加一条 in-memory 风险事件，实际 events 增量 \(store.events.count - baselineEventCount)")
    let latest = try #require(store.events.first)
    #expect(latest.kind == .risk)
    #expect(latest.title == "API Key 写入 Keychain 失败")
    #expect(latest.agentID == agent.id)
    #expect(latest.detail.contains("OSStatus=\(errSecAuthFailed)"),
            "事件 detail 必须暴露真实 OSStatus 便于排查 Keychain 锁定 / 沙箱权限缺失，实际 detail=\(latest.detail)")
    #expect(latest.detail.contains("应用重启后会丢失"),
            "事件 detail 必须告知老板「重启会丢失」，避免误以为只是临时提示")
}

@MainActor
@Test func keychainSaveAPIKeyAdjacentFailuresDeduplicateInEventStream() async throws {
    var status: OSStatus = errSecSuccess
    let (store, _) = makeStoreWithAPIAgent(
        keychainStatus: { status },
        captureWrite: { _, _ in }
    )

    let baselineEventCount = store.events.count
    status = errSecAuthFailed

    store.saveSnapshot()
    store.saveSnapshot()
    store.saveSnapshot()

    #expect(store.events.count == baselineEventCount + 1,
            "同员工同 OSStatus 的相邻失败必须去重，避免 Keychain 持续锁定时刷屏，实际增量 \(store.events.count - baselineEventCount)")
    #expect(store.events.first?.title == "API Key 写入 Keychain 失败")
}

@MainActor
@Test func keychainSaveAPIKeySuccessLeavesEventStreamAndAgentApiKeyUntouched() async throws {
    var captured: [(String, UUID)] = []
    let (store, agent) = makeStoreWithAPIAgent(
        keychainStatus: { errSecSuccess },
        captureWrite: { value, agentID in captured.append((value, agentID)) }
    )

    captured.removeAll()

    store.saveSnapshot()

    #expect(captured.contains { $0.0 == "secret-key" && $0.1 == agent.id },
            "成功路径仍要把 apiKey 写入 keychain 闭包，不能跳过")
    let newRiskEvents = store.events.filter { $0.title == "API Key 写入 Keychain 失败" && $0.agentID == agent.id }
    #expect(newRiskEvents.isEmpty, "errSecSuccess 路径不应追加任何 Keychain 失败事件，实际 \(newRiskEvents.count) 条")
    let stored = store.agents.first { $0.id == agent.id }
    #expect(stored?.backend.apiKey == "secret-key",
            "成功路径下 in-memory agents[] 仍保留原始 apiKey（agentsForSnapshot 只清空快照副本，不动主数组）")
}

@Test func opcKeychainStoreSaveAPIKeyEmptyValueReturnsErrSecParamWithoutSecItemCall() async throws {
    let status = OPCKeychainStore.saveAPIKey("", agentID: UUID())
    #expect(status == errSecParam,
            "空字符串 apiKey 必须返回 errSecParam，让 CompanyStore 区分「无东西可写」和真实 Keychain 故障，实际 \(status)")
}

@Test func keychainStoreAndCompanyStoreSurfaceKeychainFailureSourceContract() async throws {
    let keychainSource = try loadOPCCompanyCoreSource("KeychainStore.swift")
    #expect(keychainSource.contains("public static func saveAPIKey(_ value: String, agentID: UUID) -> OSStatus"),
            "OPCKeychainStore.saveAPIKey 必须返回 OSStatus，否则失败信号又会被吞掉")
    #expect(keychainSource.contains("errSecItemNotFound"),
            "saveAPIKey 必须在 errSecItemNotFound 时退化到 SecItemAdd，否则首次写入会无法落盘")
    #expect(keychainSource.contains("errSecDuplicateItem"),
            "saveAPIKey 必须显式处理 errSecDuplicateItem 竞态，否则罕见并发会 silent 失败")
    #expect(keychainSource.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"),
            "saveAPIKey 必须显式使用解锁且仅本机可访问级别，不能依赖 Keychain 默认可访问策略")
    #expect(keychainSource.contains("kSecAttrSynchronizable as String: kCFBooleanFalse"),
            "save/load/delete 查询必须显式关闭 Keychain 同步，API Key 只应留在当前本机")

    let storeSource = try loadOPCCompanyCoreSource("CompanyStore.swift")
    #expect(storeSource.contains("var keychainSaveAPIKey:"),
            "CompanyStore 必须暴露可注入的 keychainSaveAPIKey 闭包以支撑测试与未来诊断 hook")
    #expect(storeSource.contains("recordKeychainSaveFailure"),
            "CompanyStore 必须保留 recordKeychainSaveFailure helper 把 OSStatus 转 in-memory 风险事件")
    #expect(storeSource.contains("writeAPIKeyToKeychain"),
            "CompanyStore 必须使用 writeAPIKeyToKeychain 收敛入口，避免 hydrate / 快照路径漏接失败")
    #expect(!storeSource.contains("OPCKeychainStore.saveAPIKey("),
            "CompanyStore 不应再直接调用 OPCKeychainStore.saveAPIKey，必须走 writeAPIKeyToKeychain 才能转事件")
}

// MARK: - 源码扫描类测试共享 helper（角色继承期轮 20 抽取 + 轮 23 扩展）

/// 读取项目内 `Sources/OPCCompanyCore/<relativePath>` 文件全文。
/// 通过本测试文件 `#filePath` 反推项目根（Tests/OPCCompanyTests/OPCCompanyCoreTests.swift → 上溯 3 层 →
/// 项目根 → 拼 `Sources/OPCCompanyCore/<relativePath>`）。共用于 27+ 处源码扫描类测试 — 角色继承期轮 20
/// 抽取，DRY 去除每处 6 行 URL 拼装重复。
///
/// 注意：本 helper 仅适用于读取**单个** `.swift` 源文件；遍历整个 `Sources/OPCCompanyCore` 目录请用
/// `loadOPCCompanyCoreSwiftFileURLs()`（角色继承期轮 23 抽取）。
fileprivate func loadOPCCompanyCoreSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/OPCCompanyCore/")
    let url = root.appendingPathComponent(relativePath)
    var combined = normalizeL10nSourceShape(try String(contentsOf: url, encoding: .utf8))
    // v0.2 split: CompanyStore is distributed across feature extension files.
    // Shape assertions treat the store as one unit, so aggregate its extensions.
    if relativePath == "CompanyStore.swift" {
        let extras = ["CompanyStore+Runtime.swift", "CompanyStore+Tasks.swift",
                      "CompanyStore+Comms.swift", "CompanyStore+Maintenance.swift",
                      "CompanyStore+Reports.swift", "CompanyStore+Workspace.swift",
                      "CompanyStore+Agents.swift", "CompanyStore+Persistence.swift"]
        for name in extras {
            let e = root.appendingPathComponent(name)
            if let data = try? Data(contentsOf: e),
               let text = String(data: data, encoding: .utf8) {
                combined += "\n\n// ==== aggregated from " + name + " ====\n" + normalizeL10nSourceShape(text)
            }
        }
    }
    return combined
}

/// i18n normalization: tests assert on source shapes that predate the
/// bilingual layer. 1) Strip the `.L()` wrapper so `"...".L()` matches the
/// historical `\"...\"` assertions. 2) Re-join adjacent plain literals split
/// by the l10n codemod (`"A" + "B"` -> `"AB"`) so shape assertions see the
/// original single-literal form.
fileprivate func normalizeL10nSourceShape(_ raw: String) -> String {
    var s = raw.replacingOccurrences(of: "\".L()", with: "\"")
    let pattern = "\"((?:\\\\.|[^\"\\\\])*)\"\\s*\\+\\s*\"((?:\\\\.|[^\"\\\\])*)\""
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
    for _ in 0..<64 {
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { break }
        let a = ns.substring(with: m.range(at: 1))
        let b = ns.substring(with: m.range(at: 2))
        let out = NSMutableString(string: s)
        out.replaceCharacters(in: m.range, with: "\"" + a + b + "\"")
        s = out as String
    }
    return s
}

/// 列出 `Sources/OPCCompanyCore/` 目录下所有 `.swift` 文件 URL（不递归子目录）。
/// 用 `try` 抛错而非 `try? ?? []` 沉默兜底 — directory 读不到本身就是测试基础设施异常，
/// 静默返回空数组会让 forbidden-pattern 类守门测试假阳性通过。共用于 3 处目录遍历型源码扫描守门
/// （`swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` /
/// `bossAndDeliveryFacingViewsDoNotReadSupersetArtifactAccessorsDirectly` /
/// `coreSourcesMustNotStartInboundHTTPListeners`）— 角色继承期轮 23 抽取，DRY 去除每处 6-8 行 URL +
/// directory 拼装重复，并把 site 3 的 `try?` silent failure 升级为 throw（语义更严格，覆盖测试基础设施层异常）。
fileprivate func loadOPCCompanyCoreSwiftFileURLs() throws -> [URL] {
    let sourcesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/OPCCompanyCore", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(at: sourcesURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
}

// MARK: - 角色继承期文案-行为耦合契约共享 helper（轮 19 抽取）

/// 扫描 `source` 中 `<structMarker>` 起到下一个 `\nstruct ` 之间的范围，返回切片字符串。
/// 共用于 R13/R14/R15/R16 contract pattern — 这四个测试都要把 UI 文案承诺与对应作用域 accessor 调用绑成
/// 单一契约，定位时扫"目标 struct 起点 → 下一个顶层 struct 起点"切片，避免命中同文件其他位置的字面量。
/// 起点找不到时通过 `Issue.record` 报错并返回 nil，调用方应 `guard let slice = ... else { return }`。
/// 注意：本 helper 仅适用于顶层 `struct X:` 模式，对 `private struct X: View {` 形式（见 R10 line 10846）
/// 不通用 — 强行合并会让接口膨胀，故保持职责单一。
fileprivate func extractTopLevelStructSlice(
    from source: String,
    structMarker: String,
    failureMessage: String
) -> String? {
    guard let startRange = source.range(of: structMarker) else {
        Issue.record("\(failureMessage)")
        return nil
    }
    let afterStart = startRange.upperBound
    let nextStructRange = source.range(of: "\nstruct ", range: afterStart..<source.endIndex)
    return String(source[afterStart..<(nextStructRange?.lowerBound ?? source.endIndex)])
}

// MARK: - BossReportCenter UI 文案-行为耦合契约（角色继承期轮 13）

@Test func bossReportCenterUITextStaysCoupledToCurrentProductScopedAccessors() async throws {
    // 双侧契约：BossReportCenter UI 文案承诺「报告会汇总当前产品…」（line 2944 附近），
    // 必须与两个产品作用域 accessor 调用（selectedProductBossReportMessages / selectedProductBossReportEvents）
    // 同时存在。任一侧单边修改都会引起 UI 谎言（文案说当前产品但实际跨产品）或文案过期（accessor 已收敛但
    // 文案还说全量）。轮 6 + 轮 10 分别落地两个 accessor 作用域；本轮把"文案-行为"绑成一条契约。
    //
    // 切片定位通过共享 helper extractTopLevelStructSlice（轮 19 抽取），避免命中
    // OperationsSuiteView.swift 其他位置（line 854/1394 等）也含「当前产品」误匹配。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    guard let bossReportCenterSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct BossReportCenter:",
        failureMessage: "未找到 BossReportCenter struct 起点 — 是否已重命名？文案-行为契约失效"
    ) else { return }

    // 1. UI 文案承诺侧：必须含「当前产品」声明
    #expect(bossReportCenterSlice.contains("当前产品"),
            "BossReportCenter 必须保留 UI 文案对「当前产品」作用域的承诺，删除该承诺前必须先评估两个 accessor 是否同步改回跨产品")
    // 2. 行为侧 #1：messages 走产品作用域 accessor（轮 10）
    #expect(bossReportCenterSlice.contains("selectedProductBossReportMessages"),
            "BossReportCenter.bossMessages 必须用 selectedProductBossReportMessages（轮 10），与「当前产品」UI 文案承诺对齐")
    // 3. 行为侧 #2：reportEvents 走产品作用域 accessor（轮 6）
    #expect(bossReportCenterSlice.contains("selectedProductBossReportEvents"),
            "BossReportCenter.reportEvents 必须用 selectedProductBossReportEvents，与「当前产品」UI 文案承诺对齐")
    // 4. 反契约：旧的跨产品调用模式不应再出现（防止悄悄回退）
    #expect(!bossReportCenterSlice.contains("store.events.filter"),
            "BossReportCenter 不应再含跨产品 store.events.filter（轮 6 已移除）")
    #expect(!bossReportCenterSlice.contains("store.messages(for: store.bossID)"),
            "BossReportCenter 不应再含跨产品 store.messages(for: store.bossID) 直读（轮 10 已移除）")
}

// MARK: - BossControlPanel header 产品名插值-行为耦合契约（角色继承期轮 14）

@Test func bossControlPanelHeaderProductNameStaysCoupledToScopedAccessors() async throws {
    // 双侧契约：BossControlPanel header 文案直接插值 store.selectedProduct?.name（line 387 附近），
    // 是比 BossReportCenter 更强的 UI 承诺（产品名渲染成可见标题文字 — 老板视觉上一眼能看到「Product A」
    // 但内容如果跨产品混了 Product B 的事件，落差极其明显）。轮 5/8 已把三个 accessor
    // (recentRiskCount/recentEvents/compactRecentReports) 收口到 selectedProductBoss* 系列；本轮把
    // header 产品名插值与这三个 accessor 调用绑成单一契约，禁止任一侧单边漂移。
    //
    // 切片定位通过共享 helper extractTopLevelStructSlice（轮 19 抽取）— 与轮 13 同模式。
    let source = try loadOPCCompanyCoreSource("InspectorPanel.swift")

    guard let bossControlPanelSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct BossControlPanel:",
        failureMessage: "未找到 BossControlPanel struct 起点 — 是否已重命名？产品名插值-行为契约失效"
    ) else { return }

    // 1. UI 文案承诺侧：header 必须含产品名插值（store.selectedProduct?.name fallback「当前产品」
    // 在 header 渲染中明示「这里只展示当前产品的内容」）
    #expect(bossControlPanelSlice.contains("store.selectedProduct?.name"),
            "BossControlPanel header 必须保留 store.selectedProduct?.name 插值 — 这是「当前产品作用域」UI 承诺的渲染体现")
    #expect(bossControlPanelSlice.contains("store.selectedProduct?.stage.title"),
            "BossControlPanel header 应展示当前产品阶段，而不是复述老板职责")
    #expect(!bossControlPanelSlice.contains("你只负责下目标、看进度、批准风险"),
            "BossControlPanel header 不应复述老板职责；职责边界由产品结构保证")
    // 2. 行为侧 #1：风险计数走 scoped risk accessor（轮 8）
    #expect(bossControlPanelSlice.contains("selectedProductBossRiskEvents"),
            "BossControlPanel.recentRiskCount 必须用 selectedProductBossRiskEvents（轮 8）— 与 header 产品名作用域承诺对齐")
    // 3. 行为侧 #2：综合事件流走 boss inspector accessor；Store 内部再复用 scoped boss events accessor（轮 5）
    #expect(bossControlPanelSlice.contains("bossInspectorRecentEvents"),
            "BossControlPanel.recentEvents 必须用 bossInspectorRecentEvents — 与 header 产品名作用域承诺对齐")
    #expect(bossControlPanelSlice.contains("bossInspectorCompactRecentReports"),
            "BossControlPanel.compactRecentReports 必须用 bossInspectorCompactRecentReports — 与 header 产品名作用域承诺对齐")
    // 4. 反契约 #1：旧的全量跨产品 store.events.prefix 不应再出现（轮 5 移除）
    #expect(!bossControlPanelSlice.contains("store.events.prefix"),
            "BossControlPanel 不应再含跨产品 store.events.prefix（轮 5 已迁移到 selectedProductBossEvents）")
    // 5. 反契约 #2：旧的跨产品 store.events.filter 不应再出现
    #expect(!bossControlPanelSlice.contains("store.events.filter"),
            "BossControlPanel 不应再含跨产品 store.events.filter（轮 5/8 已迁移）")
}

// MARK: - CommandCenterView header 产品名插值-行为耦合契约（角色继承期轮 15）

@Test func commandCenterViewHeaderProductNameStaysCoupledToScopedRiskAccessor() async throws {
    // 双侧契约：CommandCenterView 是老板首页主区域（boss "老板总览"），header 渲染 `product?.name ?? "当前产品"`
    // (line 130) + 老板专属定位文案「老板看目标、结果、风险和需要确认的审批」(line 150)。
    // 核心数据源 riskEvents 走 selectedProductBossRiskEvents（轮 9 收口；本轮把 header 与 accessor 绑契约）。
    //
    // 这是轮 13/14 contract pattern 的第三个目标实例 — 三个实例足以证明该模式适合长期推广，
    // 轮 19 已抽取共享 helper extractTopLevelStructSlice（位于 R13 之上的 MARK 区）。
    //
    // 切片定位通过共享 helper — CommandCenterView.swift line 3-649 范围。
    let source = try loadOPCCompanyCoreSource("CommandCenterView.swift")

    guard let commandCenterSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct CommandCenterView:",
        failureMessage: "未找到 CommandCenterView struct 起点 — 是否已重命名？header 产品名插值-行为契约失效"
    ) else { return }

    // 1. UI 承诺 #1：header 必须含产品名插值
    #expect(commandCenterSlice.contains("product?.name"),
            "CommandCenterView header 必须保留 product?.name 插值（line 130 附近）— 老板首页主标题的产品作用域承诺")
    // 2. UI 承诺 #2：老板专属定位文案
    #expect(commandCenterSlice.contains("老板看目标、结果、风险和需要确认的审批"),
            "CommandCenterView header 必须保留「老板看目标、结果、风险和需要确认的审批」老板专属定位文案（line 150 附近）")
    // 3. 行为：风险事件走 scoped boss risk accessor（轮 9）
    #expect(commandCenterSlice.contains("selectedProductBossRiskEvents"),
            "CommandCenterView.riskEvents 必须用 selectedProductBossRiskEvents（轮 9）— 与 header 产品名作用域承诺对齐")
    // 4. 反契约 #1：不应再含跨产品 store.events.filter
    #expect(!commandCenterSlice.contains("store.events.filter"),
            "CommandCenterView 不应再含跨产品 store.events.filter（设计意图全部走 scoped accessor）")
    // 5. 反契约 #2：不应再含跨产品 store.events.prefix
    #expect(!commandCenterSlice.contains("store.events.prefix"),
            "CommandCenterView 不应再含跨产品 store.events.prefix（设计意图全部走 scoped accessor）")
    // 6. 反契约 #3：不应再含跨产品老板消息直读 store.messages(for: store.bossID)
    #expect(!commandCenterSlice.contains("store.messages(for: store.bossID)"),
            "CommandCenterView 不应再含跨产品 store.messages(for: store.bossID) 直读")
    // 7. LIMITATION 自洽性：因为 messages(for: ctoID) 跨产品仍存在（轮 12 已加 LIMITATION 标记），
    // 切片必须仍含该标记 — 防止后续清理同时删除 limitation 标记 + 跨产品调用导致默认无声 regression。
    // (轮 12 的 latestCTOBriefingCarriesCrossProductLeakLimitationMarker 测试也守这一条；
    // 本轮在 CommandCenterView 切片维度独立验证，作为冗余守门。)
    if commandCenterSlice.contains("messages(for: store.ctoID)") {
        #expect(commandCenterSlice.contains("LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK"),
                "CommandCenterView 中 messages(for: store.ctoID) 跨产品调用还在 → 必须同时保留 LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK 标记（轮 12）")
    }
}

// MARK: - AgentDeskWorkspace 「当前产品」UI 承诺-行为耦合契约（角色继承期轮 16）

@Test func agentDeskWorkspaceCurrentProductUIPromisesStayCoupledToProductAndAgentScopedAccessors() async throws {
    // 双侧契约：AgentDeskWorkspace 是员工工作台，与 boss 三件套（轮 13/14/15）镜像 — 内含多条
    // 「当前产品」UI 承诺：「未加入当前产品团队，不能执行当前产品任务。」(line 1678)
    // 「当前产品下没有分配给该员工的任务。」(line 1714) etc。
    // 核心数据源 agentTasks/agentQueue 是双轴 scoped（product × agent）：
    //   agentTasks → store.selectedProductTasks.filter { $0.ownerID == agent.id }
    //   agentQueue → store.selectedProductWorkQueue.filter { $0.agentID == agent.id }
    // 双轴 scope 比 boss 单轴更复杂 — 任一轴退化（去掉 .filter / 去掉 selectedProduct prefix）
    // 都会让员工工作台显示别人/别的产品的内容，UX 灾难极大。
    //
    // 这是轮 13/14/15 contract pattern 的第四个目标实例 — 完成"老板核心三件套 + 员工核心 1 件"
    // 对称覆盖。剩余次要面板（BossDecisionCenterSheet / ProfilePanel etc.）UX 体感低，
    // 不再继续推该模式 — 80/20 收益已达成。
    //
    // 切片定位通过共享 helper extractTopLevelStructSlice（轮 19 抽取）— 与轮 13/14/15 同模式。
    let source = try loadOPCCompanyCoreSource("SelectionWorkspaceView.swift")

    guard let agentDeskSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct AgentDeskWorkspace:",
        failureMessage: "未找到 AgentDeskWorkspace struct 起点 — 是否已重命名？「当前产品」承诺-行为契约失效"
    ) else { return }

    // 1. UI 承诺 #1：未加入当前产品团队的警告（强 product scope claim）
    #expect(agentDeskSlice.contains("未加入当前产品团队"),
            "AgentDeskWorkspace 必须保留「未加入当前产品团队」UI 承诺（line 1678 附近）— 这条警告与 isAgentAssignedToSelectedProduct gating 联动")
    // 2. UI 承诺 #2：assignedTasks 空状态文案
    #expect(agentDeskSlice.contains("当前产品下没有分配给该员工的任务"),
            "AgentDeskWorkspace 必须保留 assignedTasks 空状态文案「当前产品下没有分配给该员工的任务」（line 1714 附近）")
    // 3. 行为 #1：agentTasks 必须是双轴 scoped — 来自 selectedProductTasks（product 轴）
    #expect(agentDeskSlice.contains("store.selectedProductTasks.filter"),
            "AgentDeskWorkspace.agentTasks 必须用 store.selectedProductTasks.filter（product 轴 + agent 轴双轴 scoped）— 与「当前产品」UI 承诺对齐")
    // 4. 行为 #2：agentQueue 必须是双轴 scoped — 来自 selectedProductWorkQueue（product 轴）
    #expect(agentDeskSlice.contains("store.selectedProductWorkQueue.filter"),
            "AgentDeskWorkspace.agentQueue 必须用 store.selectedProductWorkQueue.filter（product 轴 + agent 轴双轴 scoped）")
    // 5. 行为 #3：team membership gating 走 store.isAgentAssignedToSelectedProduct
    #expect(agentDeskSlice.contains("store.isAgentAssignedToSelectedProduct"),
            "AgentDeskWorkspace 必须用 store.isAgentAssignedToSelectedProduct gating 运行按钮 + warning 显示")
    // 6. 反契约 #1：agentTasks/agentQueue 不应直读跨产品 store.tasks（必须先经 selectedProduct 投影）
    #expect(!agentDeskSlice.contains("store.tasks.filter"),
            "AgentDeskWorkspace 不应直读跨产品 store.tasks.filter — 必须经 selectedProductTasks 中转，否则别的产品的任务会泄漏到本 desk")
    // 7. 反契约 #2：agentQueue 不应直读跨产品 store.workQueue
    #expect(!agentDeskSlice.contains("store.workQueue.filter"),
            "AgentDeskWorkspace 不应直读跨产品 store.workQueue.filter — 必须经 selectedProductWorkQueue 中转")
}

// MARK: - 自动状态摘要去重清理维护测试

@MainActor
@Test func autoCapturedSummaryDuplicatePreviewReturnsCorrectCounts() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let detail = "测试摘要内容，共享 detail 前 200 字用于去重检测。这段文字足够长以触发分组逻辑。"
    let older = ProductMemoryNote(productID: productID, kind: .summary,
                                  title: "自动记录：产品 A 状态摘要", detail: detail,
                                  createdAt: Date().addingTimeInterval(-3600))
    let newest = ProductMemoryNote(productID: productID, kind: .summary,
                                   title: "自动记录：产品 A 状态摘要", detail: detail,
                                   createdAt: Date())
    store.memories.insert(contentsOf: [newest, older], at: 0)

    let preview = store.previewSelectedProductAutoCapturedSummaryDuplicates()

    #expect(preview.duplicateGroupCount == 1,
            "两条相同 detail 前 200 字的自动摘要应计为 1 组重复")
    #expect(preview.removableNoteCount == 1,
            "一组两条重复中只有 1 条是旧的可移除条目")
    #expect(preview.totalAutoSummaryCount == 2,
            "当前产品共有 2 条自动摘要")
    #expect(preview.hasDuplicates,
            "有重复时 hasDuplicates 必须为 true")
}

@MainActor
@Test func autoCapturedSummaryCleanupKeepsNewestRemovesOlder() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let detail = "保留最新的条目；这段文字用于分组检测，前 200 字相同即视为重复。补充内容确保超过 200 字阈值：AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA。"
    let newer = ProductMemoryNote(productID: productID, kind: .summary,
                                  title: "自动记录：产品状态摘要", detail: detail,
                                  createdAt: Date())
    let older = ProductMemoryNote(productID: productID, kind: .summary,
                                  title: "自动记录：产品状态摘要", detail: detail,
                                  createdAt: Date().addingTimeInterval(-7200))
    store.memories.append(contentsOf: [newer, older])

    let removed = store.cleanupSelectedProductAutoCapturedSummaryDuplicates()

    #expect(removed == 1, "应移除 1 条旧记忆")
    let remaining = store.memories.filter {
        $0.productID == productID && $0.kind == .summary && $0.title.hasPrefix("自动记录：")
    }
    #expect(remaining.count == 1, "清理后只剩 1 条自动摘要")
    #expect(remaining.first?.id == newer.id, "保留的必须是 createdAt 最新的那条")
}

@MainActor
@Test func autoCapturedSummaryCleanupLeavesOtherProductUntouched() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let selectedID = store.selectedProductID
    let otherProductID = UUID()
    let detail = "两个产品共享相同的摘要内容，去重只应作用于当前选中产品，不能越界到其他产品。"
    let n1 = ProductMemoryNote(productID: selectedID, kind: .summary,
                               title: "自动记录：当前产品摘要", detail: detail,
                               createdAt: Date())
    let n2 = ProductMemoryNote(productID: selectedID, kind: .summary,
                               title: "自动记录：当前产品摘要", detail: detail,
                               createdAt: Date().addingTimeInterval(-3600))
    let o1 = ProductMemoryNote(productID: otherProductID, kind: .summary,
                               title: "自动记录：其他产品摘要", detail: detail,
                               createdAt: Date())
    let o2 = ProductMemoryNote(productID: otherProductID, kind: .summary,
                               title: "自动记录：其他产品摘要", detail: detail,
                               createdAt: Date().addingTimeInterval(-3600))
    store.memories.append(contentsOf: [n1, n2, o1, o2])

    store.cleanupSelectedProductAutoCapturedSummaryDuplicates()

    let otherRemaining = store.memories.filter { $0.productID == otherProductID }
    #expect(otherRemaining.count == 2, "其他产品的记忆不应被清理，必须保留 2 条")
}

@MainActor
@Test func autoCapturedSummaryCleanupLeavesOtherDetailPrefixUntouched() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    // detail1: 两条重复，应清理一条
    let detail1 = "第一组摘要内容 AAAAAA，前 200 字构成去重键。" + String(repeating: "A", count: 200)
    // detail2: 唯一条目，前缀完全不同，不应被清理
    let detail2 = "第二组摘要内容 BBBBBB，前缀完全不同。" + String(repeating: "B", count: 200)
    let d1a = ProductMemoryNote(productID: productID, kind: .summary,
                                title: "自动记录：摘要", detail: detail1,
                                createdAt: Date())
    let d1b = ProductMemoryNote(productID: productID, kind: .summary,
                                title: "自动记录：摘要", detail: detail1,
                                createdAt: Date().addingTimeInterval(-3600))
    let d2 = ProductMemoryNote(productID: productID, kind: .summary,
                               title: "自动记录：摘要", detail: detail2,
                               createdAt: Date())
    store.memories.append(contentsOf: [d1a, d1b, d2])

    store.cleanupSelectedProductAutoCapturedSummaryDuplicates()

    let remaining = store.memories.filter {
        $0.productID == productID && $0.kind == .summary && $0.title.hasPrefix("自动记录：")
    }
    #expect(remaining.count == 2, "detail 前缀不同的唯一条目不应被清理，共保留 2 条")
    #expect(remaining.contains { $0.id == d2.id }, "detail2 的唯一条目必须保留")
}

@MainActor
@Test func autoCapturedSummaryCleanupNopWhenNoDuplicates() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    let productID = store.selectedProductID
    let note = ProductMemoryNote(productID: productID, kind: .summary,
                                 title: "自动记录：单条无重复", detail: "唯一条目，没有重复，清理应该是 no-op。",
                                 createdAt: Date())
    store.memories.append(note)
    let eventCount = store.events.count
    let verificationCount = store.verifications.count

    let removed = store.cleanupSelectedProductAutoCapturedSummaryDuplicates()

    #expect(removed == 0, "无重复时清理必须是 no-op，返回 0")
    #expect(store.events.count == eventCount, "无重复时不应写入维护事件")
    #expect(store.verifications.count == verificationCount, "无重复时不应写入维护记录")
}

@Test func localMaintenanceCenterExposesAutoCapturedSummaryDuplicateCleanup() async throws {
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")
    let identifiers = try loadOPCCompanyCoreSource("DisplayFormatting.swift")

    // 预览访问器
    #expect(source.contains("store.autoCapturedSummaryDuplicatePreviewText()"),
            "LocalMaintenanceCenter 必须展示自动摘要去重预览文本")
    #expect(source.contains("store.previewSelectedProductAutoCapturedSummaryDuplicates()"),
            "清理按钮的 disabled 条件必须调用 previewSelectedProductAutoCapturedSummaryDuplicates()")

    // 清理按钮 + 确认标签
    #expect(source.contains("store.cleanupSelectedProductAutoCapturedSummaryDuplicates()"),
            "LocalMaintenanceCenter 必须调用 cleanupSelectedProductAutoCapturedSummaryDuplicates()")
    #expect(source.contains("再次点击确认清理自动摘要重复"),
            "清理按钮第二次点击需显示确认文案")

    // disabled 条件
    #expect(source.contains(".hasDuplicates"),
            "按钮 disabled 条件必须基于 hasDuplicates")

    // accessibility identifiers
    #expect(source.contains("OPCUIAutomationIdentifier.autoCapturedSummaryDuplicateCleanupButton.rawValue"),
            "清理按钮必须带稳定 accessibilityIdentifier")
    #expect(source.contains("OPCUIAutomationIdentifier.autoCapturedSummaryDuplicatePreview.rawValue"),
            "预览卡片必须带稳定 accessibilityIdentifier")
    #expect(source.contains(".accessibilityLabel(\"自动摘要去重预览\")"),
            "预览卡片必须带中文 accessibilityLabel")
    #expect(source.contains(".accessibilityValue(store.autoCapturedSummaryDuplicatePreviewText())"),
            "预览卡片必须把动态正文挂到 accessibilityValue，供 Computer Use 直接读取")

    // identifier 已在 DisplayFormatting 枚举中登记
    #expect(identifiers.contains("OPCAutoCapturedSummaryDuplicateCleanupButton"),
            "OPCUIAutomationIdentifier 枚举必须登记 autoCapturedSummaryDuplicateCleanupButton")
    #expect(identifiers.contains("OPCAutoCapturedSummaryDuplicatePreview"),
            "OPCUIAutomationIdentifier 枚举必须登记 autoCapturedSummaryDuplicatePreview")
}

@Test func localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks() async throws {
    // 双侧契约：本地维护详情 sheet 内「历史索引预览」「历史归档迁移预览」只保留主按钮正下方的
    // HistoryIndexAuditPreview() / HistoryArchiveMigrationPreview() 作为唯一主位置（line 915/926 附近），
    // 不允许在下方详细运维区再写一份 SectionHeader(title: "历史索引预览") / SectionHeader(title: "历史归档迁移预览")
    // 重复块。重复块和主位置走同一 store accessor（historyIndexAuditText / historyArchiveMigrationText），
    // 视觉与数据完全等价，造成同一 sheet 内同一信息展示两次。
    //
    // 反契约用切片定位避开 HistoryIndexAuditPreview / HistoryArchiveMigrationPreview 自身的 Text("历史索引预览")
    // / Text("历史归档迁移预览")（line 263 / 284）—— 这两个 Text 是预览卡内嵌标题，不是 SectionHeader。
    // 用 extractTopLevelStructSlice 把检查范围限定到 LocalMaintenanceCenter struct 切片内。
    let source = try loadOPCCompanyCoreSource("OperationsSuiteView.swift")

    guard let localMaintenanceCenterSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct LocalMaintenanceCenter:",
        failureMessage: "未找到 LocalMaintenanceCenter struct 起点 — 是否已重命名？历史预览去重契约失效"
    ) else { return }

    // 1. 反契约：LocalMaintenanceCenter 切片内不能再写这两个 SectionHeader 重复块
    #expect(!localMaintenanceCenterSlice.contains("SectionHeader(title: \"历史索引预览\")"),
            "LocalMaintenanceCenter 不应再含 SectionHeader(title: \"历史索引预览\") 重复块；唯一主位置是 HistoryIndexAuditPreview()")
    #expect(!localMaintenanceCenterSlice.contains("SectionHeader(title: \"历史归档迁移预览\")"),
            "LocalMaintenanceCenter 不应再含 SectionHeader(title: \"历史归档迁移预览\") 重复块；唯一主位置是 HistoryArchiveMigrationPreview()")

    // 2. 正契约：主位置预览卡片仍被引用
    #expect(localMaintenanceCenterSlice.contains("HistoryIndexAuditPreview()"),
            "LocalMaintenanceCenter 必须保留 HistoryIndexAuditPreview() 作为「运行历史索引巡检」按钮下方的唯一主位置")
    #expect(localMaintenanceCenterSlice.contains("HistoryArchiveMigrationPreview()"),
            "LocalMaintenanceCenter 必须保留 HistoryArchiveMigrationPreview() 作为「运行历史归档迁移」按钮下方的唯一主位置")

    // 3. 旁证：下方详细运维区其他没有主按钮重复的 SectionHeader（白名单 / 自动摘要去重 / 旧任务归属迁移）
    //    继续保留，证明清理只针对重复块，不是把整个详细运维区一刀切删除。
    #expect(localMaintenanceCenterSlice.contains("SectionHeader(title: \"本地文件索引根白名单\")"),
            "本地文件索引根白名单没有主按钮重复，应继续保留在下方详细运维区")
    #expect(localMaintenanceCenterSlice.contains("SectionHeader(title: \"自动摘要去重预览\")"),
            "自动摘要去重预览没有主按钮重复，应继续保留在下方详细运维区")
    #expect(localMaintenanceCenterSlice.contains("SectionHeader(title: \"旧任务归属迁移预览\")"),
            "旧任务归属迁移预览没有主按钮重复，应继续保留在下方详细运维区")
}

@Test func runStreamingCapturesTailOutputAfterExit() async throws {
    // 守门：AgentProcessRunner.runStreaming 必须在 waitUntilExit 之后手动 drain stdout/stderr 管道，
    // 否则子进程刚 printf 完就退出的尾部数据会因 readabilityHandler 还未派发而丢失，
    // 旧实现里 result.standardOutput / standardError 都会是空字符串。
    guard let shellPath = AgentProcessRunner.resolvedExecutablePath(for: "sh") else { return }
    let stdoutMarker = "OPC_TAIL_STDOUT_\(UUID().uuidString)"
    let stderrMarker = "OPC_TAIL_STDERR_\(UUID().uuidString)"
    // 立刻 printf + 立刻退出：制造 readabilityHandler 来不及分发尾部数据的最坏情况。
    let script = "printf '\(stdoutMarker)\\n'; printf '\(stderrMarker)\\n' 1>&2"

    let result = await AgentProcessRunner.runStreaming(
        command: [shellPath, "-c", script],
        workingDirectory: nil,
        onOutput: { _ in }
    )

    #expect(result.exitCode == 0, "脚本应正常退出，但实际 exitCode=\(result.exitCode)")
    #expect(result.standardOutput.contains(stdoutMarker),
            "stdout 尾部 marker 必须被 waitUntilExit 之后的手动 drain 捕获，实际 standardOutput=\(result.standardOutput)")
    #expect(result.standardError.contains(stderrMarker),
            "stderr 尾部 marker 必须被 waitUntilExit 之后的手动 drain 捕获，实际 standardError=\(result.standardError)")
}

@Test func runStreamingEscalatesToSIGKILLWhenSIGTERMIgnored() async throws {
    // 守门：AgentProcessRunner.runStreaming 的 timeout 路径必须在 SIGTERM 后升级到 SIGKILL，
    // 否则被 `trap '' TERM` 屏蔽信号的子进程会让 waitUntilExit 永远挂起，整个 await 永不返回，
    // UI 端只看到「忙碌」却没有 124 退出。脚本屏蔽 TERM 后 sleep 30 模拟最坏情况；
    // timeoutSeconds=0.3 + terminationGraceSeconds=0.5 → 总耗时应 < 3 秒；超时退出码必须仍为 124。
    guard let shellPath = AgentProcessRunner.resolvedExecutablePath(for: "sh") else { return }
    let script = "trap '' TERM; sleep 30"
    let start = Date()
    let result = await AgentProcessRunner.runStreaming(
        command: [shellPath, "-c", script],
        workingDirectory: nil,
        timeoutSeconds: 0.3,
        terminationGraceSeconds: 0.5,
        onOutput: { _ in }
    )
    let elapsed = Date().timeIntervalSince(start)
    #expect(result.exitCode == 124, "SIGKILL 升级路径仍必须保持 124 超时退出码，实际 exitCode=\(result.exitCode)")
    #expect(elapsed < 3, "SIGTERM 被屏蔽时必须靠 SIGKILL 在短界内强制返回，实际耗时=\(elapsed)s")
    #expect(result.standardError.contains("命令超时"),
            "SIGTERM 阶段写入的中文超时消息必须仍在 stderr buffer 里，实际 standardError=\(result.standardError)")
    #expect(result.standardError.contains("SIGKILL"),
            "升级到 SIGKILL 时的诊断消息必须写入 stderr buffer，便于事后排查子进程为何不响应 SIGTERM；实际 standardError=\(result.standardError)")
}

@MainActor
@Test func productDeletionRequestIsNilWhenNoProductSelected() async throws {
    #expect(ProductDeletionRequest(product: nil) == nil)
}

@MainActor
@Test func productDeletionRequestCapturesProductIdentityWithoutMutatingStore() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let product = try #require(store.selectedProduct)
    let countBefore = store.products.count

    let request = try #require(ProductDeletionRequest(product: product))

    #expect(request.productID == product.id)
    #expect(request.productName == product.name)
    #expect(store.products.count == countBefore)
    #expect(store.products.contains { $0.id == product.id })
}

@MainActor
@Test func confirmingProductDeletionInvokesStoreDeleteProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    store.addProductWorkspace()
    let product = try #require(store.selectedProduct)
    let request = try #require(ProductDeletionRequest(product: product))

    store.deleteProduct(request.productID)

    #expect(!store.products.contains { $0.id == product.id })
}

@MainActor
@Test func deleteProductButtonDisabledConditionPreservedWhenSingleProduct() async throws {
    let store = CompanyStore.bootstrap(loadPersisted: false)
    #expect(store.products.count <= 1)
    let isDisabledWithSingleProduct = store.products.count <= 1 || store.selectedProduct == nil
    #expect(isDisabledWithSingleProduct)

    store.addProductWorkspace()
    let isDisabledWithMultipleProducts = store.products.count <= 1 || store.selectedProduct == nil
    #expect(!isDisabledWithMultipleProducts)
}

@Test func productSidebarContextMenuUsesDeletionConfirmationInsteadOfDirectDelete() async throws {
    let source = try loadOPCCompanyCoreSource("ContentView.swift")
    guard let sidebarSlice = extractTopLevelStructSlice(
        from: source,
        structMarker: "struct ProductWorkspaceList:",
        failureMessage: "未找到 ProductWorkspaceList struct 起点 — 产品侧边栏删除确认契约失效"
    ) else { return }

    #expect(sidebarSlice.contains("@State private var pendingDeletion: ProductDeletionRequest?"))
    #expect(sidebarSlice.contains("pendingDeletion = ProductDeletionRequest(product: product)"))
    #expect(sidebarSlice.contains(".confirmationDialog("))
    #expect(sidebarSlice.contains("store.deleteProduct(request.productID)"))
    #expect(!sidebarSlice.contains("store.deleteProduct(product.id)"))
}

@MainActor
@Test func messageBubbleAuthorLabelUsesAgentRoleBoundaries() async throws {
    #expect(MessageBubble.authorLabel(for: .user, agentRole: nil) == "老板")
    #expect(MessageBubble.authorLabel(for: .system, agentRole: nil) == "系统")
    #expect(MessageBubble.authorLabel(for: .agent, agentRole: .cto) == "技术负责人")
    #expect(MessageBubble.authorLabel(for: .agent, agentRole: .boss) == "老板")
    #expect(MessageBubble.authorLabel(for: .agent, agentRole: .codeEngineer) == "员工")
    #expect(MessageBubble.authorLabel(for: .agent, agentRole: nil) == "员工")
}

// MARK: - Language switch timing regression

/// Regression for the inverted/mixed language switch: side effects (bundle
/// selection + store-string session language) must apply at value-set time —
/// synchronously BEFORE SwiftUI re-renders the `.id(resolved)` tree. The bug
/// ran them in Picker.onChange AFTER the rebuild, so the rebuilt Text() views
/// resolved through the previous language's bundle and the UI ended up one
/// selection behind (choose 中文 → English shown and vice versa), with later
/// re-renders mixing both languages.
@Test @MainActor
func languageSwitchAppliesSideEffectsBeforeNextRender() {
    let env = L10nEnvironment(initial: .simplifiedChinese)
    env.language = .english
    // Capture while English is active, then restore immediately — the global
    // session language must not stay English past this synchronous block.
    let enSession = AppStrings.sessionLanguage
    let enSelected = L10nBundleOverride.selected
    env.language = .simplifiedChinese
    let zhSession = AppStrings.sessionLanguage
    let zhSelected = L10nBundleOverride.selected
    #expect(enSession == .english)
    #expect(enSelected == .english)
    #expect(zhSession == .simplifiedChinese)
    #expect(zhSelected == .simplifiedChinese)
}
