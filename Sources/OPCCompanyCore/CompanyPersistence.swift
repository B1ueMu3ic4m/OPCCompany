import Foundation

public struct CompanySnapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var agents: [CompanyAgent]
    public var ctoID: UUID
    public var bossID: UUID
    public var selectedAgentID: UUID
    public var products: [ProductWorkspace]
    public var selectedProductID: UUID
    public var messages: [ChatMessage]
    public var events: [CompanyEvent]
    public var tasks: [CompanyTask]
    public var terminalLogs: [UUID: String]
    public var productTerminalLogs: [String: String]
    public var workQueue: [AgentWorkItem]
    public var approvals: [ApprovalRequest]
    public var artifacts: [ArtifactRecord]
    public var verifications: [VerificationRecord]
    public var memories: [ProductMemoryNote]
    public var agentProfiles: [UUID: AgentOperatingProfile]
    public var communicationChannels: [CommunicationChannelConfig]
    public var communicationLogs: [CommunicationLogEntry]
    public var inboundCommandNonces: Set<String>
    public var branchPlans: [BranchExecutionPlan]
    public var reviewGates: [ReviewGateRecord]
    public var agentMessages: [AgentMessageEnvelope]

    public init(
        agents: [CompanyAgent],
        ctoID: UUID,
        bossID: UUID,
        selectedAgentID: UUID,
        products: [ProductWorkspace],
        selectedProductID: UUID,
        messages: [ChatMessage],
        events: [CompanyEvent],
        tasks: [CompanyTask],
        terminalLogs: [UUID: String],
        productTerminalLogs: [String: String] = [:],
        workQueue: [AgentWorkItem] = [],
        approvals: [ApprovalRequest] = [],
        artifacts: [ArtifactRecord] = [],
        verifications: [VerificationRecord] = [],
        memories: [ProductMemoryNote] = [],
        agentProfiles: [UUID: AgentOperatingProfile] = [:],
        communicationChannels: [CommunicationChannelConfig] = [],
        communicationLogs: [CommunicationLogEntry] = [],
        inboundCommandNonces: Set<String> = [],
        branchPlans: [BranchExecutionPlan] = [],
        reviewGates: [ReviewGateRecord] = [],
        agentMessages: [AgentMessageEnvelope] = []
    ) {
        self.schemaVersion = 14
        self.agents = agents
        self.ctoID = ctoID
        self.bossID = bossID
        self.selectedAgentID = selectedAgentID
        self.products = products
        self.selectedProductID = selectedProductID
        self.messages = messages
        self.events = events
        self.tasks = tasks
        self.terminalLogs = terminalLogs
        self.productTerminalLogs = productTerminalLogs
        self.workQueue = workQueue
        self.approvals = approvals
        self.artifacts = artifacts
        self.verifications = verifications
        self.memories = memories
        self.agentProfiles = agentProfiles
        self.communicationChannels = communicationChannels
        self.communicationLogs = communicationLogs
        self.inboundCommandNonces = inboundCommandNonces
        self.branchPlans = branchPlans
        self.reviewGates = reviewGates
        self.agentMessages = agentMessages
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case agents
        case ctoID
        case bossID
        case selectedAgentID
        case products
        case selectedProductID
        case messages
        case events
        case tasks
        case terminalLogs
        case productTerminalLogs
        case workQueue
        case approvals
        case artifacts
        case verifications
        case memories
        case agentProfiles
        case communicationChannels
        case communicationLogs
        case inboundCommandNonces
        case branchPlans
        case reviewGates
        case agentMessages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        agents = try container.decode([CompanyAgent].self, forKey: .agents)
        ctoID = try container.decode(UUID.self, forKey: .ctoID)
        bossID = try container.decode(UUID.self, forKey: .bossID)
        selectedAgentID = try container.decode(UUID.self, forKey: .selectedAgentID)
        products = try container.decode([ProductWorkspace].self, forKey: .products)
        selectedProductID = try container.decode(UUID.self, forKey: .selectedProductID)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        events = try container.decode([CompanyEvent].self, forKey: .events)
        tasks = try container.decode([CompanyTask].self, forKey: .tasks)
        terminalLogs = try container.decode([UUID: String].self, forKey: .terminalLogs)
        productTerminalLogs = try container.decodeIfPresent([String: String].self, forKey: .productTerminalLogs) ?? [:]
        workQueue = try container.decodeIfPresent([AgentWorkItem].self, forKey: .workQueue) ?? []
        approvals = try container.decodeIfPresent([ApprovalRequest].self, forKey: .approvals) ?? []
        artifacts = try container.decodeIfPresent([ArtifactRecord].self, forKey: .artifacts) ?? []
        verifications = try container.decodeIfPresent([VerificationRecord].self, forKey: .verifications) ?? []
        memories = try container.decodeIfPresent([ProductMemoryNote].self, forKey: .memories) ?? []
        agentProfiles = try container.decodeIfPresent([UUID: AgentOperatingProfile].self, forKey: .agentProfiles) ?? [:]
        communicationChannels = try container.decodeIfPresent([CommunicationChannelConfig].self, forKey: .communicationChannels) ?? []
        communicationLogs = try container.decodeIfPresent([CommunicationLogEntry].self, forKey: .communicationLogs) ?? []
        inboundCommandNonces = try container.decodeIfPresent(Set<String>.self, forKey: .inboundCommandNonces) ?? []
        branchPlans = try container.decodeIfPresent([BranchExecutionPlan].self, forKey: .branchPlans) ?? []
        reviewGates = try container.decodeIfPresent([ReviewGateRecord].self, forKey: .reviewGates) ?? []
        agentMessages = try container.decodeIfPresent([AgentMessageEnvelope].self, forKey: .agentMessages) ?? []
    }
}

public enum CompanyPersistence {
    /// 解析当前进程的持久化根目录。优先级：
    /// 1. 环境变量 `OPC_COMPANY_SUPPORT_DIR` 显式覆盖（CI / 调试 / 自定义沙盒可用）；
    /// 2. 检测到 XCTest / swift-testing / SwiftPM `swift test` 进程 →
    ///    使用 `<TemporaryDirectory>/OPCCompanyTests-<pid>` 隔离临时目录，避免污染真实 App 状态；
    ///    检测信号包括：Xcode 注入的 `XCTestConfigurationFilePath` / `XCTestSessionIdentifier` /
    ///    `XCTEST_HOST_BUNDLE_PATH`；进程名含 `xctest` / `PackageTests` / `swift-testing`；
    ///    main bundle 路径以 `.xctest` 结尾或位于 `.xctest/` 内（SwiftPM `swift test` 标志）；
    /// 3. 正常运行：使用 `~/Library/Application Support/OPCCompany`。
    /// 该 helper 暴露为 `internal` 以便测试可以注入 env / temp / pid / processName / bundlePath 参数验证决策。
    static func resolveSupportDirectory(
        environment: [String: String],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        processName: String = ProcessInfo.processInfo.processName,
        bundlePath: String = Bundle.main.bundlePath,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        if let override = environment["OPC_COMPANY_SUPPORT_DIR"], !override.isEmpty {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        if isLikelyTestProcess(environment: environment, processName: processName, bundlePath: bundlePath, arguments: arguments) {
            return temporaryDirectory.appendingPathComponent("OPCCompanyTests-\(processIdentifier)", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return base.appendingPathComponent("OPCCompany", isDirectory: true)
    }

    /// 综合多个信号判定当前是否在 XCTest / swift-testing / SwiftPM `swift test` 进程内。
    /// 任一命中即视为测试进程。覆盖：
    /// - Xcode XCTest 注入的 env：`XCTestConfigurationFilePath` / `XCTestSessionIdentifier` / `XCTEST_HOST_BUNDLE_PATH`；
    /// - 进程名：`xctest` / `PackageTests` / `swift-testing` / `swiftpm-testing-helper`（SwiftPM swift test 实际主进程名）；
    /// - main bundle：`.xctest` 结尾或在 `.xctest/` 内；
    /// - 进程参数：含 `.xctest` 路径或 `--testing-library` 标志（SwiftPM swift test 用 swiftpm-testing-helper 调用 .xctest bundle）。
    static func isLikelyTestProcess(
        environment: [String: String],
        processName: String = ProcessInfo.processInfo.processName,
        bundlePath: String = Bundle.main.bundlePath,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if environment["XCTEST_HOST_BUNDLE_PATH"] != nil { return true }
        let lowerName = processName.lowercased()
        if lowerName.contains("xctest") { return true }
        if lowerName.contains("packagetests") { return true }
        if lowerName.contains("swift-testing") { return true }
        if lowerName.contains("swiftpm-testing-helper") { return true }
        if lowerName.contains("testing-helper") { return true }
        if bundlePath.hasSuffix(".xctest") { return true }
        if bundlePath.contains(".xctest/") { return true }
        for arg in arguments {
            if arg.contains(".xctest") { return true }
            if arg == "--testing-library" { return true }
        }
        return false
    }

    /// 进程级缓存：一次解析后整个进程稳定。设置 `OPC_COMPANY_SUPPORT_DIR` 必须在进程启动前完成，
    /// 启动后改环境变量不会再次被读到——这是有意设计：避免运行时切换持久化路径制造分裂状态。
    private static let resolvedSupportDirectory: URL =
        resolveSupportDirectory(environment: ProcessInfo.processInfo.environment)

    public static var supportDirectory: URL { resolvedSupportDirectory }

    public static var stateURL: URL {
        supportDirectory.appendingPathComponent("company-state.json")
    }

    public static var historyIndexURL: URL {
        supportDirectory.appendingPathComponent("company-history.sqlite3")
    }

    public static var agentWorkspacesURL: URL {
        supportDirectory.appendingPathComponent("agents", isDirectory: true)
    }

    public static var productWorkspacesURL: URL {
        supportDirectory.appendingPathComponent("products", isDirectory: true)
    }

    public static func load() -> CompanySnapshot? {
        let url = stateURL
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // 文件不存在或不可读 → 走 bootstrap 全新（合法 happy path）
            return nil
        }
        do {
            return try JSONDecoder.opc.decode(CompanySnapshot.self, from: data)
        } catch {
            // R26（角色继承期轮 26 落地候选 χ-persistence）：
            // decode 失败说明 state.json 损坏 / Codable schema 演进 bug / 部分写入。
            // 不能悄悄 bootstrap 覆盖 — 必须留 forensic 副本到 corrupted 备份文件，
            // 让 codex / 用户能事后调查损坏原因。备份失败不阻塞应用启动。
            backupCorruptedState(at: url, payload: data, reason: String(describing: error))
            return nil
        }
    }

    /// 把损坏的 state.json 原子重命名 + 写入备份文件，文件名带 ISO8601 时间戳避免互相覆盖。
    /// 备份失败本身只静默吞错——损坏处理不能阻塞应用启动（caller 仍然走 bootstrap）。
    /// 备份文件落在 `supportDirectory` 下：`company-state-corrupted-<ISO8601>.json`。
    /// reason 写入同名 `.reason.txt` sidecar 便于 forensic 调查。
    private static func backupCorruptedState(at originalURL: URL, payload: Data, reason: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = supportDirectory.appendingPathComponent("company-state-corrupted-\(timestamp).json")
        let reasonURL = supportDirectory.appendingPathComponent("company-state-corrupted-\(timestamp).reason.txt")
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try payload.write(to: backupURL, options: [.atomic])
            try Data(reason.utf8).write(to: reasonURL, options: [.atomic])
        } catch {
            // backup-of-backup 不再尝试 — 应用启动优先于 forensic
        }
    }

    /// 持久化 `snapshot` 到默认 `stateURL`。返回 `Result<Void, Error>`：
    /// `.success(())` 表示已落盘；`.failure(error)` 表示 createDirectory / encode / write 任一阶段失败，
    /// caller（当前为 `CompanyStore.saveSnapshot()`）必须处理失败 — 例如落一条 in-memory 风险事件让老板可见。
    /// 历史背景：旧版本 `save(_:)` 直接 swallow 异常，是项目里典型的 silent-failure 反例（χ-persistence Risk）；
    /// 升级为返回 Result 后，policy（ignore / surface / retry）由 caller 决定，持久化层只负责报告。
    /// 标 `@discardableResult` 是为了向后兼容那些在意「尽力保存」但不关心是否失败的极少数 caller —
    /// 但 `CompanyStore.saveSnapshot` 必须显式消费 Result，不允许忽略。
    @discardableResult
    public static func save(_ snapshot: CompanySnapshot) -> Result<Void, Error> {
        save(snapshot, to: stateURL)
    }

    /// 测试用 / 显式注入路径的重载：把 stateURL 解耦出来，便于在测试里指向一个故意「不可写」的 URL
    /// （例如父路径是一个普通文件 → createDirectory 必然失败）来触发 `.failure` 路径，
    /// 避免 mutate 进程级共享的 `supportDirectory` 沙盒。
    @discardableResult
    static func save(_ snapshot: CompanySnapshot, to url: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.opc.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    public static func rebuildHistoryIndex(_ snapshot: CompanySnapshot) throws -> CompanyHistoryIndexStats {
        try CompanyHistorySQLiteIndex.rebuild(snapshot: snapshot, at: historyIndexURL)
    }

    public static func historyIndexStats() throws -> CompanyHistoryIndexStats {
        try CompanyHistorySQLiteIndex.stats(at: historyIndexURL)
    }

    public static func searchHistoryIndex(query: String, productID: UUID? = nil, limit: Int = 20) throws -> [CompanyHistorySearchResult] {
        try CompanyHistorySQLiteIndex.search(at: historyIndexURL, query: query, productID: productID, limit: limit)
    }

    public static func archiveHistory(_ snapshot: CompanySnapshot, olderThan cutoffAt: Date) throws -> CompanyHistoryArchiveStats {
        try CompanyHistorySQLiteIndex.archive(snapshot: snapshot, at: historyIndexURL, olderThan: cutoffAt)
    }

    public static func historyArchiveStats() throws -> CompanyHistoryArchiveStats {
        try CompanyHistorySQLiteIndex.archiveStats(at: historyIndexURL)
    }
}

private extension JSONEncoder {
    static var opc: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var opc: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
