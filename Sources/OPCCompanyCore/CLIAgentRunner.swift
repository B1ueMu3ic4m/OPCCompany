import Foundation

public protocol CLIAgentRunner {
    func command(for agent: CompanyAgent, prompt: String) -> [String]
}

public struct CommandExecutionResult: Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

// LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-BUFFER（角色继承期轮 30 标记）：
// `@unchecked Sendable` 在此**不是技术债** —— class 用 NSLock 同步 mutable state，
// 是「程序员承诺 thread-safe，编译器看不到 lock 语义」的正确 Sendable 声明模式。
// 添加新字段时**必须**同时把读写都包进 lock.lock()/unlock() 块，否则破坏 Sendable contract。
// 守门测试 `processOutputBufferUncheckedSendableCarriesLockProtectionMarker` 防止此标记被误删。
// 候选 ω-sendable Swift 6 升级路径（codex 决定级）：将 NSLock 替换为 Swift 6 `Mutex<(String, String)>`
// 让 Sendable 自动推断；但 Mutex 需要 macOS 15+ 部署目标，本项目 macOS 14 baseline 暂保持 NSLock。
private final class ProcessOutputBuffer: @unchecked Sendable {
    private var standardOutput = ""
    private var standardError = ""
    private let lock = NSLock()

    func append(_ text: String, isError: Bool) {
        lock.lock()
        if isError {
            standardError.append(text)
        } else {
            standardOutput.append(text)
        }
        lock.unlock()
    }

    func snapshot() -> (output: String, error: String) {
        lock.lock()
        let output = standardOutput
        let error = standardError
        lock.unlock()
        return (output, error)
    }
}

// LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-FLAG（角色继承期轮 30 标记）：
// 同 ProcessOutputBuffer：用 NSLock 保护单 Bool 标志位，`@unchecked Sendable` 是正确声明。
// 添加新字段（如 timeoutReason / wallClockMs）时必须沿用 lock.lock()/unlock() 模式。
// 守门测试 `processTimeoutStateUncheckedSendableCarriesLockProtectionMarker` 防止此标记被误删。
// 候选 ω-sendable Swift 6 升级路径（codex 决定级）：将 NSLock 替换为 `Mutex<Bool>` 让 Sendable
// 自动推断；macOS 14 baseline 暂保持 NSLock。
private final class ProcessTimeoutState: @unchecked Sendable {
    private var timedOut = false
    private let lock = NSLock()

    var didTimeout: Bool {
        lock.lock()
        let value = timedOut
        lock.unlock()
        return value
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}

public enum AgentProcessRunner {
    public static func run(command: [String], workingDirectory: URL?) async -> CommandExecutionResult {
        await runStreaming(command: command, workingDirectory: workingDirectory, onOutput: { _ in })
    }

    public static func runStreaming(command: [String], workingDirectory: URL?, environmentOverrides: [String: String] = [:], isolatedHome: URL? = nil, sandboxProfile: String? = nil, timeoutSeconds: TimeInterval? = nil, terminationGraceSeconds: TimeInterval = 2, onOutput: @escaping @Sendable (String) -> Void) async -> CommandExecutionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var launchCommand = command
                if let sandboxProfile {
                    let sandboxExecutable = "/usr/bin/sandbox-exec"
                    guard FileManager.default.isExecutableFile(atPath: sandboxExecutable) else {
                        let error = "严格沙盒不可用：当前系统没有可执行的 sandbox-exec。".L()
                        onOutput(error)
                        continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error))
                        return
                    }
                    launchCommand = [sandboxExecutable, "-p", sandboxProfile] + command
                }

                guard let executable = launchCommand.first else {
                    let error = "没有提供命令。".L()
                    onOutput(error)
                    continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error))
                    return
                }

                let resolvedExecutable = resolveExecutable(executable)
                guard FileManager.default.isExecutableFile(atPath: resolvedExecutable) else {
                    let searched = searchPaths(for: executable).joined(separator: "\n- ")
                    let error = """
                    找不到可执行命令：\(executable)

                    这通常是因为从 macOS 应用启动时 PATH 不包含你的终端环境。
                    已搜索：
                    - \(searched)

                    请确认命令行工具已安装并可执行，或在员工模型来源里填完整路径。
                    """
                    onOutput(error)
                    continuation.resume(returning: CommandExecutionResult(
                        exitCode: 127,
                        standardOutput: "",
                        standardError: error
                    ))
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: resolvedExecutable)
                process.arguments = Array(launchCommand.dropFirst())
                process.currentDirectoryURL = workingDirectory
                process.environment = mergedEnvironment(overrides: environmentOverrides, isolatedHome: isolatedHome)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                let input = FileHandle(forReadingAtPath: "/dev/null")
                process.standardInput = input
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let outputBuffer = ProcessOutputBuffer()
                let timeoutState = ProcessTimeoutState()

                let appendOutput: @Sendable (Data, Bool) -> Void = { data, isError in
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                    outputBuffer.append(text, isError: isError)
                    onOutput(text)
                }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    appendOutput(handle.availableData, false)
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    appendOutput(handle.availableData, true)
                }

                do {
                    try process.run()
                    if let timeoutSeconds, timeoutSeconds > 0 {
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                            guard process.isRunning else { return }
                            timeoutState.markTimedOut()
                            let message = "\n命令超时：\(Int(timeoutSeconds)) 秒内没有返回，OPC 已停止这次调用。\n"
                            outputBuffer.append(message, isError: true)
                            onOutput(message)
                            process.terminate()
                            // SIGTERM→SIGKILL 升级：被 `trap '' TERM` 屏蔽或卡在不可中断系统调用的子进程
                            // 不会响应 process.terminate()，waitUntilExit 将永远挂起，导致整个 await
                            // 永不返回。grace 后再用 Darwin kill(pid, SIGKILL) 强制结束，保证调用方
                            // 一定能拿到 124 退出。pid 在 isRunning 为真时取，被 reuse 的概率可忽略。
                            let pid = process.processIdentifier
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(terminationGraceSeconds, 0)) {
                                guard process.isRunning else { return }
                                let killMessage = "\n命令在 SIGTERM 后仍在运行，已升级到 SIGKILL 强制结束。\n".L()
                                outputBuffer.append(killMessage, isError: true)
                                onOutput(killMessage)
                                kill(pid, SIGKILL)
                            }
                        }
                    }
                    process.waitUntilExit()
                    // 子进程退出后，内核管道缓冲区可能仍残留 readabilityHandler 还没分发的尾部数据；
                    // 必须先把 handler 清掉避免与我们的同步 drain 抢同一个 fd，再用 readDataToEndOfFile
                    // 把剩余字节读到 EOF。写端已随子进程关闭，readDataToEndOfFile 不会阻塞。
                    // 缓冲区有 NSLock 保护，即使最后一次 handler 派发与我们的 drain 并发也能安全 append。
                    //
                    // 例外：timeout 升级 SIGKILL 的路径下，被 kill 的是直接子进程，但其孤儿孙进程
                    // 可能还持有 stdout/stderr 管道写端的 dup 副本（macOS pipe EOF 语义要所有写端关闭
                    // 才会发出），这会让 readDataToEndOfFile 一直阻塞到孤儿自己退出 —— 直接抹掉
                    // SIGKILL 升级带来的「短界返回」承诺。timeout 已在 SIGTERM 阶段同步写入中文超时
                    // 消息、在 SIGKILL 阶段同步写入升级诊断消息，超时之后的孤儿尾部输出已无价值，
                    // 所以这条路径上跳过 trailing drain，让调用方立刻拿到 124。
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    if !timeoutState.didTimeout {
                        let trailingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        appendOutput(trailingOutput, false)
                        let trailingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        appendOutput(trailingError, true)
                    }
                    let snapshot = outputBuffer.snapshot()
                    let output = snapshot.output
                    let error = snapshot.error
                    let exitCode: Int32 = timeoutState.didTimeout ? 124 : process.terminationStatus
                    continuation.resume(returning: CommandExecutionResult(exitCode: exitCode, standardOutput: output, standardError: error))
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    onOutput(error.localizedDescription)
                    continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error.localizedDescription))
                }
            }
        }
    }

    private static func resolveExecutable(_ executable: String) -> String {
        if executable.contains("/") {
            return NSString(string: executable).expandingTildeInPath
        }

        return searchPaths(for: executable).first { FileManager.default.isExecutableFile(atPath: $0) } ?? executable
    }

    public static func resolvedExecutablePath(for executable: String) -> String? {
        let resolved = resolveExecutable(executable)
        return FileManager.default.isExecutableFile(atPath: resolved) ? resolved : nil
    }

    private static func searchPaths(for executable: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathValues = [
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        return pathValues.map { "\($0)/\(executable)" }
    }

    private static func mergedEnvironment(overrides: [String: String] = [:], isolatedHome: URL? = nil) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var environment = ProcessInfo.processInfo.environment
        let appPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = [
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        environment["PATH"] = (extra + [appPath]).joined(separator: ":")
        if let isolatedHome {
            let homePath = isolatedHome.path
            environment["HOME"] = homePath
            environment["XDG_CONFIG_HOME"] = "\(homePath)/.opc/env/config"
            environment["XDG_CACHE_HOME"] = "\(homePath)/.opc/env/cache"
            environment["XDG_DATA_HOME"] = "\(homePath)/.opc/env/data"
        } else {
            environment["HOME"] = home
        }
        for (key, value) in overrides where !value.isEmpty {
            environment[key] = value
        }
        return environment
    }
}

public enum AgentAPIChatRunner {
    public enum APIError: Error, LocalizedError {
        case invalidEndpoint
        case missingAPIKey
        case invalidHTTPResponse
        case httpError(Int, String)
        case emptyReply

        public var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "接口地址无效。请填写兼容 OpenAI 的基础地址，例如 https://api.openai.com/v1。".L()
            case .missingAPIKey:
                "接口密钥为空。接口模式需要在员工档案里配置密钥。".L()
            case .invalidHTTPResponse:
                "接口没有返回有效网络响应。".L()
            case let .httpError(status, body):
                "接口请求失败：网络状态 \(status)。\(body)"
            case .emptyReply:
                "接口返回成功，但没有解析到模型回复内容。".L()
            }
        }
    }

    public static func run(agent: CompanyAgent, prompt: String) async -> CommandExecutionResult {
        do {
            let request = try request(for: agent, prompt: prompt)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidHTTPResponse
            }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw APIError.httpError(httpResponse.statusCode, bodyText)
            }
            let reply = try parseReply(from: data)
            return CommandExecutionResult(exitCode: 0, standardOutput: reply, standardError: "")
        } catch {
            return CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public static func request(for agent: CompanyAgent, prompt: String) throws -> URLRequest {
        guard let url = chatCompletionsURL(from: agent.backend.endpoint) else {
            throw APIError.invalidEndpoint
        }
        guard !agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(agent.backend.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": agent.backend.model.isEmpty ? "default" : agent.backend.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    public static func chatCompletionsURL(from endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: "\(trimmed)/chat/completions")
    }

    public static func parseReply(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first
        else {
            throw APIError.emptyReply
        }

        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        if let text = first["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        throw APIError.emptyReply
    }
}

public enum CLIAgentCommandBuilder {
    public static func command(for agent: CompanyAgent, prompt: String) -> [String] {
        command(for: agent, prompt: prompt, resumeSessionID: nil)
    }

    public static func command(for agent: CompanyAgent, prompt: String, resumeSessionID: String?) -> [String] {
        if agent.backend.type == .api {
            return ["api-agent", "--endpoint", agent.backend.endpoint, "--model", agent.backend.model, "--prompt", prompt]
        }

        switch agent.backend.command {
        case "codex":
            if let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [preferredCodexExecutable(), "exec", "resume", "--skip-git-repo-check", "-m", agent.backend.model, "-c", "model_reasoning_effort=\"\(agent.backend.reasoningEffort.rawValue)\"", resumeSessionID, prompt]
            }
            return [preferredCodexExecutable(), "exec", "--skip-git-repo-check", "--cd", ".", "-m", agent.backend.model, "-c", "model_reasoning_effort=\"\(agent.backend.reasoningEffort.rawValue)\"", prompt]
        case "claude":
            if let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ["claude", "-p", "--permission-mode", "auto", "--model", agent.backend.model, "--effort", claudeEffort(agent.backend.reasoningEffort), "--resume", resumeSessionID, prompt]
            }
            return ["claude", "-p", "--permission-mode", "auto", "--model", agent.backend.model, "--effort", claudeEffort(agent.backend.reasoningEffort), prompt]
        case "gemini":
            if agent.backend.model.isEmpty || agent.backend.model == "gemini-cli" {
                if let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ["gemini", "--resume", resumeSessionID, "-p", prompt]
                }
                return ["gemini", "-p", prompt]
            }
            if let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ["gemini", "--resume", resumeSessionID, "--model", agent.backend.model, "-p", prompt]
            }
            return ["gemini", "--model", agent.backend.model, "-p", prompt]
        default:
            return [agent.backend.command, prompt]
        }
    }

    public static func prewarmCommand(for agent: CompanyAgent) -> [String] {
        switch agent.backend.type {
        case .api, .local:
            return []
        case .subscriptionCLI:
            switch agent.backend.command {
            case "codex":
                return [preferredCodexExecutable(), "--version"]
            case "claude":
                return ["claude", "--version"]
            case "gemini":
                return ["gemini", "--version"]
            default:
                let command = agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines)
                return command.isEmpty ? [] : [command, "--version"]
            }
        }
    }

    public static func runtimeCapability(for agent: CompanyAgent) -> AgentRuntimeCapability {
        switch agent.backend.type {
        case .api:
            return .apiConnection
        case .local:
            return .localPlaceholder
        case .subscriptionCLI:
            if interactionProfile(for: agent) != nil {
                return .persistentProtocol
            }
            return .oneShotCLI
        }
    }

    public static func interactionProfile(for agent: CompanyAgent) -> CLIInteractionProfile? {
        guard agent.backend.type == .subscriptionCLI else { return nil }
        return CLIInteractionProfileCatalog.profile(forCommand: agent.backend.command)
    }

    public static func interactionSummary(for agent: CompanyAgent) -> String? {
        guard let profile = interactionProfile(for: agent) else { return nil }
        let resumeText = profile.supportsResume ? "支持按产品续跑".L() : "不续跑历史会话".L()
        return "\(profile.displayName) · \(resumeText) · 识别会话编号关键词 · 监控\(profile.healthSignalSummary)"
    }

    public static func backendSignature(for agent: CompanyAgent) -> String {
        [
            agent.backend.type.rawValue,
            agent.backend.command,
            agent.backend.model,
            agent.backend.endpoint,
            agent.backend.reasoningEffort.rawValue
        ].joined(separator: "|")
    }

    private static func preferredCodexExecutable() -> String {
        let npmCodex = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/codex"
        if FileManager.default.isExecutableFile(atPath: npmCodex) {
            return npmCodex
        }
        return "codex"
    }

    private static func claudeEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        }
    }
}

public struct CLIInteractionProfile: Hashable, Sendable {
    public var command: String
    public var displayName: String
    public var protocolKind: CLIInteractionProtocolKind
    public var sessionMode: String
    public var supportsResume: Bool
    public var sessionIDLabels: [String]
    public var sessionIDPattern: String
    public var readySignals: [String]
    public var replReadySignals: [String]
    public var endTurnSignals: [String]
    public var busySignals: [String]
    public var authenticationIssueSignals: [String]
    public var transientIssueSignals: [String]
    public var recommendedTimeoutSeconds: TimeInterval

    public init(
        command: String,
        displayName: String,
        protocolKind: CLIInteractionProtocolKind = .singleCommand,
        sessionMode: String,
        supportsResume: Bool,
        sessionIDLabels: [String],
        sessionIDPattern: String = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
        readySignals: [String],
        replReadySignals: [String] = [],
        endTurnSignals: [String] = [],
        busySignals: [String],
        authenticationIssueSignals: [String],
        transientIssueSignals: [String],
        recommendedTimeoutSeconds: TimeInterval = 60
    ) {
        self.command = command
        self.displayName = displayName
        self.protocolKind = protocolKind
        self.sessionMode = sessionMode
        self.supportsResume = supportsResume
        self.sessionIDLabels = sessionIDLabels
        self.sessionIDPattern = sessionIDPattern
        self.readySignals = readySignals
        self.replReadySignals = replReadySignals
        self.endTurnSignals = endTurnSignals
        self.busySignals = busySignals
        self.authenticationIssueSignals = authenticationIssueSignals
        self.transientIssueSignals = transientIssueSignals
        self.recommendedTimeoutSeconds = recommendedTimeoutSeconds
    }

    public var healthSignalSummary: String {
        [
            readySignals.isEmpty ? nil : "就绪".L(),
            busySignals.isEmpty ? nil : "忙碌".L(),
            authenticationIssueSignals.isEmpty ? nil : "授权异常".L(),
            transientIssueSignals.isEmpty ? nil : "临时异常".L()
        ].compactMap { $0 }.joined(separator: "、")
    }

    public func sessionID(from output: String) -> String? {
        let escapedLabels = sessionIDLabels
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = #""?(?:\#(escapedLabels))"?\s*[:=]\s*"?(\#(sessionIDPattern))"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: match.numberOfRanges - 1), in: output)
        else { return nil }
        return String(output[matchRange])
    }

    public func containsAuthenticationIssue(_ output: String) -> Bool {
        containsDiagnosticSignal(authenticationIssueSignals, in: output)
    }

    public func containsBusySignal(_ output: String) -> Bool {
        containsDiagnosticSignal(busySignals, in: output)
    }

    public func containsReadySignal(_ output: String) -> Bool {
        containsAnyText(readySignals, in: output)
    }

    public func containsREPLReadySignal(_ output: String) -> Bool {
        let normalized = Self.normalizedForPromptMatching(output)
        return normalized.split(whereSeparator: \.isNewline).contains { line in
            let trimmedLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            return replReadySignals.contains { signal in
                trimmedLine.compare(signal, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    /// 严格判断：终端最近一段输出的最后一非空行是否就是该协议的专用 REPL 提示。
    /// 用于真实终端席位 preflight，避免长 scrollback 里残留的旧 prompt 把"正在处理"
    /// 之类的当前状态误判为可继续交互。
    public func endsWithReplReadyPrompt(_ output: String) -> Bool {
        guard !replReadySignals.isEmpty else { return false }
        let normalized = Self.normalizedForPromptMatching(output)
        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let lastNonEmpty = lines.reversed().first(where: { line in
            !String(line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return false }
        let trimmed = String(lastNonEmpty).trimmingCharacters(in: .whitespacesAndNewlines)
        return replReadySignals.contains { signal in
            trimmed.compare(signal, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// 把真实终端输出规范化到便于 prompt 匹配的形态：按行模拟终端光标：
    /// - 普通可见字符按光标位置覆盖或追加；
    /// - CR（`\r`）只把当前行光标重置到列 0，**不擦掉尾部**；后续可见字符会逐个覆盖已有字符，未被覆盖的尾部仍保留；
    /// - BS（`\b`）只把光标左移一位，不擦掉字符；shell 标准擦字 `\b \b` 才会用空格覆盖；
    /// - CSI K / ESC[0K 清光标到行尾；ESC[1K 把行首到光标位置改成空格；ESC[2K 清整行；其他 CSI 无影响地剥离；
    /// - OSC（`ESC ] … BEL` 或 `ESC ] … ESC \`）整段剥离；
    /// - 保留 `\t`、`\n` 和所有可见字符（含中文）；其余 C0 控制字节和 DEL 直接丢弃。
    /// 该规范化只服务 REPL prompt 静态识别，不参与真实终端轮询期增量解析或 `__OPC_JOB_EXIT_<id>__` 退出协议。
    public static func normalizedForPromptMatching(_ output: String) -> String {
        let scalars = Array(output.unicodeScalars)
        var lines: [[Unicode.Scalar]] = []
        var line: [Unicode.Scalar] = []
        var cursor = 0

        func writeChar(_ c: Unicode.Scalar) {
            if cursor < line.count {
                line[cursor] = c
            } else {
                line.append(c)
            }
            cursor += 1
        }

        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            switch s.value {
            case 0x1B:
                i += 1
                guard i < scalars.count else { break }
                let next = scalars[i]
                if next.value == 0x5B {
                    // CSI: ESC [ 参数与中间字节… 终结字节(0x40-0x7E)
                    i += 1
                    let paramStart = i
                    var finalByte: UInt32 = 0
                    while i < scalars.count {
                        let c = scalars[i]
                        i += 1
                        if c.value >= 0x40 && c.value <= 0x7E {
                            finalByte = c.value
                            break
                        }
                    }
                    if finalByte == 0x4B { // 'K' = erase-line
                        let paramView = String.UnicodeScalarView(scalars[paramStart..<(i - 1)])
                        let mode = Int(String(paramView)) ?? 0
                        switch mode {
                        case 0:
                            // 清光标到行尾
                            if cursor < line.count {
                                line.removeSubrange(cursor..<line.count)
                            }
                        case 1:
                            // 清行首到光标位置（含光标），保留行尾
                            let upper = min(cursor + 1, line.count)
                            if upper > 0 {
                                for j in 0..<upper {
                                    line[j] = " "
                                }
                            }
                        case 2:
                            // 清整行（光标位置不变，但 line 内容清空）
                            line.removeAll(keepingCapacity: true)
                        default:
                            break
                        }
                    }
                    // 其他 CSI（颜色、光标位置、可见性等）按"无可见副作用"剥离
                } else if next.value == 0x5D {
                    // OSC: ESC ] 内容 BEL，或 ESC ] 内容 ESC \
                    i += 1
                    while i < scalars.count {
                        let c = scalars[i]
                        if c.value == 0x07 {
                            i += 1
                            break
                        }
                        if c.value == 0x1B,
                           i + 1 < scalars.count,
                           scalars[i + 1].value == 0x5C {
                            i += 2
                            break
                        }
                        i += 1
                    }
                } else {
                    // 其他单字节转义（ESC ( B 等）：跳过紧跟的中间字节
                    i += 1
                }
            case 0x08:
                // BS：只回退光标，不擦字符
                if cursor > 0 { cursor -= 1 }
                i += 1
            case 0x0A:
                // \n：把当前行落地，光标回到下一行行首
                lines.append(line)
                line = []
                cursor = 0
                i += 1
            case 0x0D:
                // \r：光标回到行首，行内容保持
                cursor = 0
                i += 1
            case 0x09:
                // \t 当作可见字符保留
                writeChar(s)
                i += 1
            case 0x7F:
                // DEL 丢弃
                i += 1
            default:
                if s.value < 0x20 {
                    // 其他 C0 控制字节（BEL、垂直制表等）丢弃
                    i += 1
                } else {
                    writeChar(s)
                    i += 1
                }
            }
        }
        lines.append(line)

        var view = String.UnicodeScalarView()
        for (idx, segment) in lines.enumerated() {
            view.append(contentsOf: segment)
            if idx < lines.count - 1 {
                view.append(Unicode.Scalar(0x0A)!)
            }
        }
        return String(view)
    }

    public func containsEndTurnSignal(_ output: String) -> Bool {
        containsAnyText(endTurnSignals, in: output)
    }

    public func containsTransientIssue(_ output: String) -> Bool {
        containsDiagnosticSignal(transientIssueSignals, in: output)
    }

    private func containsAnyText(_ signals: [String], in output: String) -> Bool {
        signals.contains { output.localizedCaseInsensitiveContains($0) }
    }

    private func containsDiagnosticSignal(_ signals: [String], in output: String) -> Bool {
        // 先把 ANSI 颜色码、OSC title、CR 覆写、BS 光标移动等控制字符规范化掉，
        // 让真实终端里被颜色或 spinner 包裹的诊断行也能命中守门；
        // 后续仍然必须满足 isDiagnosticLine 前缀闸 + lineContainsAnyDiagnosticSignal 单词闸，
        // 因此路径、文件名、标识符里的 timeout/network/429/busy 不会被误判。
        let normalized = Self.normalizedForPromptMatching(output)
        return normalized.split(whereSeparator: \.isNewline).contains { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.isDiagnosticLine(line) && Self.lineContainsAnyDiagnosticSignal(signals, line: line)
        }
    }

    fileprivate static let diagnosticPrefixes: [String] = [
        "error:", "error ", "fatal:", "fatal ", "warning:", "warn:", "warn ",
        "[error]", "[fatal]", "[warn]", "[warning]",
        "panic:", "exception:", "exception ", "errno",
        "session expired", "authentication failed", "auth failed",
        "not authenticated", "please login", "please log in", "login required",
        "sign in to your account", "unauthorized", "invalid api key",
        "plan usage limits", "already running", "rate limit", "quota", "overloaded", "busy",
        "network error", "network timeout", "connection timed out", "request timed out",
        "temporarily unavailable", "timeout", "429",
        // 中文诊断前缀：覆盖工具中文输出。同样要求出现在行首，普通中文句子不会误命中。
        "错误：".L(), "错误 ".L(), "致命：".L(), "致命 ".L(), "致命错误：".L(), "严重：".L(), "严重错误：".L(),
        "警告：".L(), "警告 ".L(), "异常：".L(), "异常 ".L(),
        "授权失败".L(), "授权异常".L(), "登录失败".L(), "未授权".L(), "请登录".L(), "请重新登录".L(),
        "网络错误".L(), "网络异常".L(), "请求超时".L(), "连接超时".L(), "连接失败".L(),
        "临时不可用".L(), "临时异常".L(), "服务繁忙".L(), "已忙碌".L(), "速率限制".L(), "配额已用尽".L(),
        "请稍后重试".L()
    ]

    fileprivate static let pathOrIdentifierMarkers: Set<Character> = ["/", "\\", "-", "_", "."]

    fileprivate static let tokenStrippingCharacters = CharacterSet(charactersIn: ".,;:!?\"'()[]{}<>`")

    fileprivate static func isDiagnosticLine(_ line: String) -> Bool {
        let lowerLine = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowerLine.isEmpty else { return false }
        return diagnosticPrefixes.contains { prefix in
            lowerLine.hasPrefix(prefix)
        }
    }

    fileprivate static func lineContainsAnyDiagnosticSignal(_ signals: [String], line: String) -> Bool {
        let lowerLine = line.lowercased()
        return signals.contains { signal in
            let lowerSignal = signal.lowercased()
            // 中文等非 ASCII 短语没有空格、token 切分不工作；改成 substring 命中加前后字符
            // 路径标记防御。这样 `错误：临时异常` / `致命：服务繁忙` 能命中，
            // `error: /tmp/临时异常.log` 这类路径上下文不会被误判。
            let containsNonASCII = lowerSignal.unicodeScalars.contains { !$0.isASCII }
            if containsNonASCII {
                return linePhraseHitAvoidingPathContext(line: lowerLine, phrase: lowerSignal)
            }
            if lowerSignal.contains(" ") {
                return lowerLine.contains(lowerSignal)
            }
            return lineContainsDiagnosticToken(line: lowerLine, word: lowerSignal)
        }
    }

    fileprivate static func lineContainsDiagnosticToken(line lowerLine: String, word lowerWord: String) -> Bool {
        let tokens = lowerLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tokens.contains { raw in
            let token = raw.trimmingCharacters(in: tokenStrippingCharacters)
            if token.isEmpty { return false }
            if token.contains(where: { pathOrIdentifierMarkers.contains($0) }) { return false }
            return token == lowerWord
        }
    }

    /// 中文/非 ASCII 短语命中：substring 命中后再看前后字符是否构成路径或标识符上下文。
    /// 任意一侧紧贴 `/\-_.` 即视为路径误判，跳过这次命中并继续向后查找；其他位置（行边界、空白、
    /// 中英文标点、字母数字）都视为合法诊断短语边界。
    fileprivate static func linePhraseHitAvoidingPathContext(line: String, phrase: String) -> Bool {
        var searchStart = line.startIndex
        while let range = line.range(of: phrase, range: searchStart..<line.endIndex) {
            let prevChar = range.lowerBound > line.startIndex
                ? line[line.index(before: range.lowerBound)]
                : nil
            let nextChar = range.upperBound < line.endIndex
                ? line[range.upperBound]
                : nil
            let prevIsPath = prevChar.map { pathOrIdentifierMarkers.contains($0) } ?? false
            let nextIsPath = nextChar.map { pathOrIdentifierMarkers.contains($0) } ?? false
            if !prevIsPath && !nextIsPath {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

}

public enum CLIInteractionProtocolKind: String, Codable, CaseIterable, Sendable {
    case singleCommand
    case printMode
    case promptMode
    case repl
}

public enum CLIInteractionPhase: String, Codable, CaseIterable, Sendable {
    case unknown
    case ready
    case awaitingResponse
    case completedTurn
    case busy
    case authenticationBlocked
    case transientFailure
}

public struct CLIInteractionObservation: Codable, Hashable, Sendable {
    public var phase: CLIInteractionPhase
    public var reasonTitle: String
    public var sessionID: String?

    public init(phase: CLIInteractionPhase, reasonTitle: String, sessionID: String? = nil) {
        self.phase = phase
        self.reasonTitle = reasonTitle
        self.sessionID = sessionID
    }
}

public enum CLIInteractionRecoveryAction: String, Codable, CaseIterable, Sendable {
    case noAction = "none"
    case checkAuthentication
    case waitAndRetryLater
    case waitForCurrentTask

    public var title: String {
        switch self {
        case .noAction:
            return "无需处理".L()
        case .checkAuthentication:
            return "检查登录授权".L()
        case .waitAndRetryLater:
            return "稍后重试".L()
        case .waitForCurrentTask:
            return "等待当前任务".L()
        }
    }

    public var operatorHint: String? {
        switch self {
        case .noAction:
            return nil
        case .checkAuthentication:
            return "请在对应工具中确认登录授权，再重新发起任务。".L()
        case .waitAndRetryLater:
            return "网络或模型来源临时不可用，请稍后再发起任务。".L()
        case .waitForCurrentTask:
            return "上一轮任务尚未结束，请等待完成后再发起新任务。".L()
        }
    }
}

public enum CLIInteractionStateMachine {
    public static func observe(output: String, profile: CLIInteractionProfile, previousPhase: CLIInteractionPhase = .unknown) -> CLIInteractionObservation {
        let sessionID = profile.sessionID(from: output)
        if profile.containsAuthenticationIssue(output) {
            return CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常".L(), sessionID: sessionID)
        }
        if profile.containsTransientIssue(output) {
            return CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常".L(), sessionID: sessionID)
        }
        if profile.containsBusySignal(output) {
            return CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中".L(), sessionID: sessionID)
        }
        if profile.containsEndTurnSignal(output) {
            return CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束".L(), sessionID: sessionID)
        }
        if profile.containsReadySignal(output) || sessionID != nil {
            return CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互".L(), sessionID: sessionID)
        }
        if previousPhase == .awaitingResponse {
            return CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复".L(), sessionID: sessionID)
        }
        return CLIInteractionObservation(phase: .unknown, reasonTitle: "未识别状态".L(), sessionID: sessionID)
    }

    public static func recoveryAction(for phase: CLIInteractionPhase) -> CLIInteractionRecoveryAction {
        switch phase {
        case .unknown:
            return .noAction
        case .ready:
            return .noAction
        case .awaitingResponse:
            return .noAction
        case .completedTurn:
            return .noAction
        case .busy:
            return .waitForCurrentTask
        case .authenticationBlocked:
            return .checkAuthentication
        case .transientFailure:
            return .waitAndRetryLater
        }
    }

    public static func observeREPLTurn(output: String, profile: CLIInteractionProfile, previousPhase: CLIInteractionPhase = .awaitingResponse) -> CLIInteractionObservation {
        let sessionID = profile.sessionID(from: output)
        if profile.containsAuthenticationIssue(output) {
            return CLIInteractionObservation(phase: .authenticationBlocked, reasonTitle: "授权异常".L(), sessionID: sessionID)
        }
        if profile.containsTransientIssue(output) {
            return CLIInteractionObservation(phase: .transientFailure, reasonTitle: "临时异常".L(), sessionID: sessionID)
        }
        if profile.containsBusySignal(output) {
            return CLIInteractionObservation(phase: .busy, reasonTitle: "忙碌中".L(), sessionID: sessionID)
        }
        if profile.containsEndTurnSignal(output) {
            return CLIInteractionObservation(phase: .completedTurn, reasonTitle: "本轮已结束".L(), sessionID: sessionID)
        }
        if profile.containsREPLReadySignal(output) || sessionID != nil {
            return CLIInteractionObservation(phase: .ready, reasonTitle: "可继续交互".L(), sessionID: sessionID)
        }
        if previousPhase == .awaitingResponse {
            return CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复".L(), sessionID: sessionID)
        }
        return CLIInteractionObservation(phase: .unknown, reasonTitle: "未识别状态".L(), sessionID: sessionID)
    }
}

public enum CLIInteractionProfileCatalog {
    public static let profiles: [CLIInteractionProfile] = [
        CLIInteractionProfile(
            command: "codex",
            displayName: "Codex 命令行交互".L(),
            protocolKind: .singleCommand,
            sessionMode: "codex-exec",
            supportsResume: true,
            sessionIDLabels: ["session id", "session_id", "conversation id", "conversation_id"],
            sessionIDPattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
            readySignals: ["codex", "OpenAI Codex", "codex-cli"],
            replReadySignals: ["codex>"],
            endTurnSignals: ["[命令退出码".L(), "turn complete", "response completed"],
            busySignals: ["busy", "already running", "rate limit", "Plan usage limits", "服务繁忙".L(), "已忙碌".L(), "已在运行".L(), "速率限制".L(), "配额已用尽".L(), "请稍后重试".L()],
            authenticationIssueSignals: ["not authenticated", "please login", "please log in", "login required", "sign in to your account", "Unauthorized", "invalid api key", "未授权".L(), "请登录".L(), "请重新登录".L(), "授权失败".L(), "授权异常".L(), "登录失败".L()],
            transientIssueSignals: ["timeout", "network", "temporarily unavailable", "429", "请求超时".L(), "连接超时".L(), "网络异常".L(), "网络错误".L(), "连接失败".L(), "临时不可用".L()],
            recommendedTimeoutSeconds: 600
        ),
        CLIInteractionProfile(
            command: "claude",
            displayName: "Claude Code 命令行交互".L(),
            protocolKind: .printMode,
            sessionMode: "claude-print",
            supportsResume: true,
            sessionIDLabels: ["session id", "session_id", "conversation id", "conversation_id", "cli_session"],
            sessionIDPattern: #"(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9]{8,32}|(?:cs|cli|chat|conv|claude)[_-][A-Za-z0-9._:-]{6,127}|[A-Za-z][A-Za-z0-9]*[_:.-][A-Za-z0-9._:-]{3,127})"#,
            readySignals: ["Claude Code", "claude"],
            replReadySignals: ["claude>"],
            endTurnSignals: ["completion_reason", "Done", "result"],
            busySignals: ["busy", "already running", "overloaded", "rate limit", "服务繁忙".L(), "已忙碌".L(), "已在运行".L(), "过载".L(), "速率限制".L(), "请稍后重试".L()],
            authenticationIssueSignals: ["not authenticated", "please login", "please log in", "login required", "sign in to your account", "Unauthorized", "invalid api key", "未授权".L(), "请登录".L(), "请重新登录".L(), "授权失败".L(), "授权异常".L(), "登录失败".L()],
            transientIssueSignals: ["timeout", "network", "temporarily unavailable", "429", "请求超时".L(), "连接超时".L(), "网络异常".L(), "网络错误".L(), "连接失败".L(), "临时不可用".L()],
            recommendedTimeoutSeconds: 600
        ),
        CLIInteractionProfile(
            command: "gemini",
            displayName: "Gemini 命令行交互".L(),
            protocolKind: .promptMode,
            sessionMode: "gemini-prompt",
            supportsResume: true,
            sessionIDLabels: ["session id", "session_id", "conversation id", "conversation_id", "chat id", "chat_id"],
            sessionIDPattern: #"(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9]{8,32}|(?:cs|cli|chat|conv|gemini)[_-][A-Za-z0-9._:-]{6,127}|[A-Za-z][A-Za-z0-9]*[_:.-][A-Za-z0-9._:-]{3,127})"#,
            readySignals: ["Gemini", "gemini"],
            replReadySignals: ["gemini>"],
            endTurnSignals: ["turn complete", "response completed", "Done"],
            busySignals: ["busy", "already running", "rate limit", "quota", "服务繁忙".L(), "已忙碌".L(), "已在运行".L(), "速率限制".L(), "配额已用尽".L(), "请稍后重试".L()],
            authenticationIssueSignals: ["not authenticated", "please login", "please log in", "login required", "sign in to your account", "Unauthorized", "invalid api key", "未授权".L(), "请登录".L(), "请重新登录".L(), "授权失败".L(), "授权异常".L(), "登录失败".L()],
            transientIssueSignals: ["timeout", "network", "temporarily unavailable", "429", "请求超时".L(), "连接超时".L(), "网络异常".L(), "网络错误".L(), "连接失败".L(), "临时不可用".L()],
            recommendedTimeoutSeconds: 600
        )
    ]

    public static func profile(forCommand command: String) -> CLIInteractionProfile? {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.command == normalized }
    }

    public static func sessionID(from output: String) -> String? {
        profiles.lazy.compactMap { $0.sessionID(from: output) }.first
    }
}
