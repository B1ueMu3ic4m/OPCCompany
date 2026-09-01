import Foundation
import Security
import SwiftUI

public enum CTOAutopilotState: Equatable {
    case idle
    case running
    case completed

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var buttonTitle: String {
        switch self {
        case .idle, .completed:
            return "让技术负责人推进一次".L()
        case .running:
            return "正在推进".L()
        }
    }

    public var statusText: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "正在让技术负责人推进…".L()
        case .completed:
            return "技术负责人已完成本次推进。".L()
        }
    }
}

@MainActor
public final class CompanyStore: ObservableObject {

    /// Boss-facing closed-loop summary line (localized).
    static func bossLoopSummaryText(_ trace: MultiAgentClosureTrace) -> String {
        let head = "最近闭环：".L()
        let mid = "消息 ".L()
        let tail = "产物 ".L()
        return head + "\(trace.goal) · \(trace.completionScore)% · " + mid + "\(trace.messageIDs.count) · " + tail + "\(trace.artifactIDs.count)"
    }

    static let cliResumeContextNotice = "\n[OPC 上下文复用]\n本次任务会接续该员工在当前产品里的上一轮上下文。\n".L()
    static func defaultProductRootDirectory() -> String {
        defaultProductRootDirectoryURL().path
    }

    private static func defaultProductRootDirectoryURL() -> URL {
        internalProductWorkspaceURL(slug: "default-product")
    }

    static func newProductRootDirectory(index: Int) -> String {
        internalProductWorkspaceURL(slug: "product-\(index)").path
    }

    static func internalProductRootDirectory(for productID: UUID) -> String {
        internalProductWorkspaceURL(slug: "product-\(String(productID.uuidString.prefix(8)).lowercased())").path
    }

    private static func internalProductWorkspaceURL(slug: String) -> URL {
        let directory = CompanyPersistence.productWorkspacesURL.appendingPathComponent(slug, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func legacyDesktopURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .standardizedFileURL
    }

    private static func legacyDesktopGeneratedProductIndex(from url: URL) -> Int? {
        let last = url.lastPathComponent
        guard last.hasPrefix("OPCProduct") else { return nil }
        let suffix = last.dropFirst("OPCProduct".count)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }

    static func migratedRootForLegacyDesktopDefaultProduct(
        rootDirectory: String,
        productName: String,
        importReport: ProjectImportReport?
    ) -> String? {
        guard importReport == nil else { return nil }
        let raw = NSString(string: rootDirectory).expandingTildeInPath
        let url = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        let desktop = legacyDesktopURL()
        if url.path == desktop.path, productName == "默认产品工作区".L() {
            return defaultProductRootDirectory()
        }
        guard productName.hasPrefix("新产品 ".L()),
              url.deletingLastPathComponent().standardizedFileURL.path == desktop.path,
              let index = legacyDesktopGeneratedProductIndex(from: url)
        else {
            return nil
        }
        return newProductRootDirectory(index: index)
    }

    private static func normalizedProductShortName(name: String, proposed: String) -> String {
        let clean = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return String(clean.prefix(6))
        }
        return String(name.prefix(3))
    }

    private static let agentChatRecentMessagePromptLimit = 700
    private static let agentChatMemoryPromptLimit = 420
    private static let agentChatUserTextPromptLimit = 2_000
    private static let agentChatRepairDraftPromptLimit = 1_200
    private static let agentProfileMissionPromptLimit = 600
    private static let agentProfileListItemPromptLimit = 280
    private static let agentProfileMemoryPromptLimit = 420
    private static let agentProfileSkillPromptLimit = 220
    private static let agentProfilePromptItemLimit = 8
    private static let agentProfilePromptMemoryItemLimit = 4
    private static let agentSystemProductMemoryPromptLimit = 420
    private static let agentSystemProductMemoryPromptItemLimit = 6
    private static let workOrderPromptTextLimit = 800
    private static let workOrderPromptPathLimit = 300
    private static let workOrderPromptListItemLimit = 80
    private static let workOrderPromptRuleItemLimit = 8
    private static let workOrderPromptToolItemLimit = 8
    private static let workOrderPromptProjectFileItemLimit = 12
    private static let reworkPromptReasonLimit = 1_200
    private static let reworkPromptSuccessCriteriaLimit = 1_200
    private static let agentMessageSubjectTextLimit = 240
    private static let agentMessageBodyTextLimit = 2_400
    static let persistentSeatExecutionNotice = "\n[OPC 长期席位执行]\n本次任务会在该员工的长期席位运行；完成后会被收录到产物记录和验收流程。\n".L()

    @Published public var agents: [CompanyAgent]
    @Published public var selectedAgentID: UUID
    @Published public var messages: [ChatMessage]
    @Published public var events: [CompanyEvent]
    @Published public var tasks: [CompanyTask]
    @Published public var products: [ProductWorkspace]
    @Published public var selectedProductID: UUID
    @Published public var workQueue: [AgentWorkItem]
    @Published public var approvals: [ApprovalRequest]
    @Published public var artifacts: [ArtifactRecord]
    @Published public var verifications: [VerificationRecord]
    @Published public var memories: [ProductMemoryNote]
    @Published public var agentProfiles: [UUID: AgentOperatingProfile]
    @Published public var communicationChannels: [CommunicationChannelConfig]
    @Published public var communicationLogs: [CommunicationLogEntry]
    @Published public var branchPlans: [BranchExecutionPlan]
    @Published public var reviewGates: [ReviewGateRecord]
    @Published public var agentMessages: [AgentMessageEnvelope]
    @Published public var terminalLogs: [UUID: String] = [:]
    @Published public var productTerminalLogs: [String: String] = [:]
    @Published public var runningAgentIDs: Set<UUID> = []
    @Published public var runtimeSessions: [UUID: AgentRuntimeSession] = [:]
    @Published public var mainWorkspace: MainWorkspace = .office
    @Published public var isAddingEmployee: Bool = false
    @Published public var draftEmployee = EmployeeDraft()
    /// 「让技术负责人推进一次」执行状态：idle / running / completed。
    /// 视图层在 `running` 期间禁用按钮、显示「正在让技术负责人推进…」文案，
    /// 避免老板重复点击或误判按钮无反应。Store 同步入口 `runCTOAutopilot()`
    /// 仍按既有副作用顺序执行；异步入口 `runCTOAutopilotWithVisibleProgress()`
    /// 在 await 边界让 SwiftUI 渲染 disabled 态后再跑批处理，并在完成后保留
    /// 「技术负责人已完成本次推进」提示。
    @Published public var ctoAutopilotState: CTOAutopilotState = .idle
    public var liveChatEnabled: Bool = true
    private var runtimeSupervisorStarted = false
    private var inboundCommandNonces: Set<String>
    private var cachedTerminalWorkspaceHealthSnapshot: TerminalWorkspaceHealthSnapshot?
    private var persistentTerminalSessions: [PersistentTerminalSessionKey: PersistentTerminalSession] = [:]
    var persistSnapshot: (CompanySnapshot) -> Result<Void, Error> = CompanyPersistence.save
    /// 测试可注入的 Keychain 写入闭包，默认走真实 `OPCKeychainStore.saveAPIKey`。
    /// 与 `persistSnapshot` 同模式：把 OSStatus 透出后，store 把非 `errSecSuccess` 转换成
    /// 老板可见的 in-memory 风险事件，避免 Keychain 沉默失败导致 API Key 丢失却无人知情。
    var keychainSaveAPIKey: (String, UUID) -> OSStatus = OPCKeychainStore.saveAPIKey

    public let ctoID: UUID
    public let bossID: UUID

    public init(agents: [CompanyAgent], ctoID: UUID, bossID: UUID, messages: [ChatMessage], events: [CompanyEvent], tasks: [CompanyTask], products: [ProductWorkspace], selectedProductID: UUID, workQueue: [AgentWorkItem] = [], approvals: [ApprovalRequest] = [], artifacts: [ArtifactRecord] = [], verifications: [VerificationRecord] = [], memories: [ProductMemoryNote] = [], agentProfiles: [UUID: AgentOperatingProfile] = [:], communicationChannels: [CommunicationChannelConfig] = [], communicationLogs: [CommunicationLogEntry] = [], inboundCommandNonces: Set<String> = [], branchPlans: [BranchExecutionPlan] = [], reviewGates: [ReviewGateRecord] = [], agentMessages: [AgentMessageEnvelope] = []) {
        self.agents = agents
        self.ctoID = ctoID
        self.bossID = bossID
        self.selectedAgentID = ctoID
        self.messages = messages
        self.events = events
        self.tasks = tasks
        self.products = products
        self.selectedProductID = selectedProductID
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
        ensureAgentProfiles()
        hydrateAPIKeysFromKeychain()
        syncAllAgentWorkspaces()
        ensureRuntimeSessionsForSelectedProduct()
    }

    public static func bootstrap(loadPersisted: Bool = true, liveChatEnabled: Bool? = nil) -> CompanyStore {
        let shouldUseLiveChat = liveChatEnabled ?? loadPersisted
        if loadPersisted, let snapshot = CompanyPersistence.load(), snapshot.schemaVersion >= 7 {
            let store = CompanyStore(
                agents: snapshot.agents,
                ctoID: snapshot.ctoID,
                bossID: snapshot.bossID,
                messages: snapshot.messages,
                events: snapshot.events,
                tasks: snapshot.tasks,
                products: snapshot.products,
                selectedProductID: snapshot.selectedProductID,
                workQueue: snapshot.workQueue,
                approvals: snapshot.approvals,
                artifacts: snapshot.artifacts,
                verifications: snapshot.verifications,
                memories: snapshot.memories,
                agentProfiles: snapshot.agentProfiles,
                communicationChannels: snapshot.communicationChannels,
                communicationLogs: snapshot.communicationLogs,
                inboundCommandNonces: snapshot.inboundCommandNonces,
                branchPlans: snapshot.branchPlans,
                reviewGates: snapshot.reviewGates,
                agentMessages: snapshot.agentMessages
            )
            store.liveChatEnabled = shouldUseLiveChat
            store.selectedAgentID = snapshot.selectedAgentID
            store.terminalLogs = snapshot.terminalLogs
            store.productTerminalLogs = snapshot.productTerminalLogs
            let migratedTerminalLogs = store.migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: false)
            store.repairSelectionState()
            let migratedDesktopRoots = store.migrateLegacyDesktopDefaultProductRoots()
            let localizedLegacyTerms = store.localizeLegacyVisibleTerminology(saveAfterChange: false)
            let removedLegacyAgents = store.removeLegacyAutoCreatedSpecialists(saveAfterChange: false)
            let cleanedLegacyMessages = store.cleanLegacySyntheticAgentReplies(saveAfterChange: false)
            if migratedTerminalLogs || migratedDesktopRoots || localizedLegacyTerms || removedLegacyAgents || cleanedLegacyMessages {
                store.repairSelectionState()
                store.saveSnapshot()
            }
            return store
        }

        let bossID = UUID()
        let ctoID = UUID()
        let uiID = UUID()
        let codeID = UUID()
        let reviewID = UUID()

        let agents = [
            CompanyAgent(
                id: bossID,
                displayName: "老板".L(),
                title: "OPC 公司老板".L(),
                role: .boss,
                backend: AgentBackend(type: .local, command: "human", model: "owner"),
                ethnicity: .chinese,
                gender: .man,
                clothing: .businessSuit,
                status: .idle,
                permissions: [.approveRisk],
                reportsToCTO: false,
                seat: OfficeSeat(x: 0.74, y: 0.75, room: "boss-office")
            ),
            CompanyAgent(
                id: ctoID,
                displayName: "Codex 技术负责人".L(),
                title: "总技术负责人".L(),
                role: .cto,
                backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
                ethnicity: .white,
                gender: .man,
                clothing: .businessSuit,
                status: .thinking,
                permissions: [.readFiles, .runCommands],
                reportsToCTO: false,
                seat: OfficeSeat(x: 0.26, y: 0.75, room: "cto-office")
            ),
            CompanyAgent(
                id: uiID,
                displayName: "Gemini 界面设计师".L(),
                title: "视觉产品设计师".L(),
                role: .uiDesigner,
                backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "", reasoningEffort: .medium),
                ethnicity: .southAsian,
                gender: .woman,
                clothing: .designerBlack,
                status: .idle,
                permissions: [.readFiles],
                seat: OfficeSeat(x: 0.34, y: 0.50, room: "employee-hall")
            ),
            CompanyAgent(
                id: codeID,
                displayName: "Claude Code 工程师".L(),
                title: "高级 macOS 工程师".L(),
                role: .codeEngineer,
                backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .medium),
                ethnicity: .black,
                gender: .man,
                clothing: .smartCasual,
                status: .coding,
                permissions: [.readFiles, .editFiles, .runTests, .runCommands],
                seat: OfficeSeat(x: 0.50, y: 0.50, room: "employee-hall")
            ),
            CompanyAgent(
                id: reviewID,
                displayName: "Codex 审查员".L(),
                title: "风险与验收审查员".L(),
                role: .reviewer,
                backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
                ethnicity: .latino,
                gender: .woman,
                clothing: .businessSuit,
                status: .reviewing,
                permissions: [.readFiles, .runTests],
                seat: OfficeSeat(x: 0.66, y: 0.50, room: "employee-hall")
            )
        ]

        let events = [
            CompanyEvent(kind: .statusChanged, title: "公司已启动".L(), detail: "已创建默认技术负责人、界面、编码和审查员工。".L(), agentID: ctoID)
        ]

        let defaultProductID = UUID()
        let defaultProduct = ProductWorkspace(
            id: defaultProductID,
            name: "默认产品工作区".L(),
            shortName: "默认".L(),
            rootDirectory: defaultProductRootDirectory(),
            status: .active,
            stage: .discovery,
            assignedAgentIDs: [ctoID, uiID, codeID, reviewID],
            teamLeadAgentID: ctoID
        )

        let messages = [
            ChatMessage(productID: defaultProductID, agentID: ctoID, author: .system, text: "系统提示：OPC 公司已经上线。正式沟通会调用员工配置的真实模型来源；未配置或不可用时只显示系统降级提示。".L()),
            ChatMessage(productID: defaultProductID, agentID: uiID, author: .system, text: "系统提示：Gemini 界面设计师已创建，档案、记忆和技能已写入员工工作区。".L()),
            ChatMessage(productID: defaultProductID, agentID: codeID, author: .system, text: "系统提示：Claude Code 工程师已创建，档案、记忆和技能已写入员工工作区。".L()),
            ChatMessage(productID: defaultProductID, agentID: reviewID, author: .system, text: "系统提示：Codex 审查员已创建，档案、记忆和技能已写入员工工作区。".L())
        ]

        let tasks = [
            CompanyTask(productID: defaultProduct.id, title: "定义产品架构".L(), ownerID: ctoID, status: .done, successCriteria: "完成产品规格、技术栈和角色系统。".L()),
            CompanyTask(productID: defaultProduct.id, title: "创建 2D 公司应用基础".L(), ownerID: codeID, status: .running, successCriteria: "构建原生 macOS SwiftUI/SpriteKit 外壳，并支持点击员工沟通。".L()),
            CompanyTask(productID: defaultProduct.id, title: "审查命令行调度设计".L(), ownerID: reviewID, status: .planned, successCriteria: "确认 Codex、Claude、Gemini 命令适配器安全且可扩展。".L())
        ]

        let store = CompanyStore(
            agents: agents,
            ctoID: ctoID,
            bossID: bossID,
            messages: messages,
            events: events,
            tasks: tasks,
            products: [defaultProduct],
            selectedProductID: defaultProduct.id
        )
        store.liveChatEnabled = shouldUseLiveChat
        store.saveSnapshot()
        return store
    }

    public var selectedAgent: CompanyAgent? {
        agents.first { $0.id == selectedAgentID }
    }

    public var ctoAgent: CompanyAgent? {
        agents.first { $0.id == ctoID }
    }

    public var selectedProduct: ProductWorkspace? {
        products.first { $0.id == selectedProductID }
    }

    /// 当前产品任务必须严格按 `productID` 过滤。旧快照里 `productID == nil` 的任务不会进入任意产品视图，
    /// 只通过技术负责人维护区的「旧任务产品归属迁移」预览和手动迁移入口处理，避免多产品视图互相串任务。
    public var selectedProductTasks: [CompanyTask] {
        tasks.filter { $0.productID == selectedProductID }
    }

    /// 当前产品的近期任务流。`createTask` 和自动拆解路径默认把新任务写到队首；
    /// 这里集中命名给老板检查器使用，避免 view 层直接把 `selectedProductTasks.prefix` 当作近期语义。
    public var selectedProductRecentTasks: [CompanyTask] {
        selectedProductTasks
    }

    public var selectedProductWorkQueue: [AgentWorkItem] {
        workQueue.filter { $0.productID == selectedProductID }
    }

    public var selectedAgentReworkQueue: [AgentWorkItem] {
        let agentID = selectedAgentID
        return selectedProductWorkQueue.filter { item in
            item.agentID == agentID && item.status != .completed && reworkReason(from: item.promptPreview) != nil
        }
    }

    public var selectedProductReworkQueue: [AgentWorkItem] {
        selectedProductWorkQueue.filter { $0.status != .completed && reworkReason(from: $0.promptPreview) != nil }
    }

    public var selectedProductApprovals: [ApprovalRequest] {
        approvals.filter { $0.productID == selectedProductID }
    }

    public var selectedProductPendingApprovals: [ApprovalRequest] {
        selectedProductApprovals.filter { $0.status == .pending }
    }

    public var selectedProductResolvedApprovals: [ApprovalRequest] {
        selectedProductApprovals
            .filter { $0.status == .approved || $0.status == .rejected }
            .sorted { (lhs, rhs) in
                let lhsDate = lhs.decidedAt ?? lhs.createdAt
                let rhsDate = rhs.decidedAt ?? rhs.createdAt
                if lhsDate == rhsDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhsDate > rhsDate
            }
    }

    public var selectedProductRiskTasks: [CompanyTask] {
        selectedProductTasks.filter { [.needsApproval, .blocked, .failed].contains($0.status) }
    }

    public var selectedProductOpenTasks: [CompanyTask] {
        selectedProductRecentTasks.filter { $0.status != .done && $0.status != .canceled }
    }

    public var bossDecisionCount: Int {
        selectedProductPendingApprovals.count + selectedProductRiskTasks.count
    }

    public var selectedProductEvents: [CompanyEvent] {
        events.filter { $0.productID == selectedProductID || $0.productID == nil }
    }

    public var selectedProductRiskEvents: [CompanyEvent] {
        selectedProductEvents.filter { $0.kind == .risk }
    }

    /// 老板视图专用风险事件过滤（剔除技术维护类预警）。
    ///
    /// 技术维护「全量事件流」入口是 `EventLogView`（员工 inspector「事件」tab），它直接读
    /// `store.events`（不是 `selectedProductRiskEvents`），可看到 CLI 健康预警 / 命令行作业
    /// 幽灵等维护类事件。
    /// 角色继承期轮 5/6/8 和 2026-05-05 迁移收敛后，所有老板专属视图（`CommandCenterView.riskEvents` /
    /// `InspectorPanel.BossControlPanel.recentRiskCount` / `CommandCenterView.BossDecisionCenterSheet` 风险事件）
    /// 均改用本 accessor 过滤维护类前缀，避免技术细节挤占老板首页"最近风险".L() widget 的
    /// prefix(5) / prefix(3) 容量。**没有任何 view 仍在直接读 `selectedProductRiskEvents`**
    /// （由 `selectedProductRiskEventsHasNoUIConsumerAfterBossViewMigration` 守门），后者只用于
    /// 本 accessor 自身派生 + 内部团队负责人手机汇报报告文本计数。
    /// 与维护类 VR/AR 隔离（`technicalMaintenanceVerificationTitles` / `technicalMaintenanceArtifactTitlePrefixes`）
    /// 同模式：单独维护一份"老板视图剔除前缀"白名单，新增维护类事件标题时同步登记到此处。
    ///
    /// **白名单设计原则**（角色继承期轮 11 加固）：
    /// - 进入白名单的判定标准：纯后端/文件系统/进程层失败，老板无法处理也不需要决策。
    /// - 不进入白名单的判定标准：老板的某个动作被阻止 / 涉及业务审批 / 涉及交付物状态 — 这些都是
    ///   老板的"待决策".L()或"待理解"信号，必须保留可见。
    /// - 例：「命令行作业目录创建失败」「命令行作业档案写入失败」属于 .opc/jobs/ 后端文件操作失败，
    ///   后端继续运行不阻断业务，老板看不懂也无法处理 → 进入白名单。
    /// - 例：「命令行发车被阻止」是老板试图运行命令行任务但前置检查不通过 → 老板需要知道，**不**进入白名单。
    public static let bossViewExcludedRiskTitlePrefixes: [String] = [
        "命令行健康预警：".L(),
        "命令行作业".L(),
        "旧任务产品归属迁移".L()
    ]

    public static let closureDrillGoalMarker = "[演练]".L()

    public var selectedProductBossRiskEvents: [CompanyEvent] {
        selectedProductRiskEvents.filter { event in
            !isClosureDrillEvent(event)
                && !Self.bossViewExcludedRiskTitlePrefixes.contains { prefix in
                event.title.hasPrefix(prefix)
            }
        }
    }

    /// 老板侧栏「近期汇报」/「最新消息」综合事件流（产品作用域 + 老板视图前缀过滤）。
    ///
    /// 与 `selectedProductBossRiskEvents` 同模式（共享 `bossViewExcludedRiskTitlePrefixes` 白名单），
    /// 但保留所有 `CompanyEvent.kind`（不只 `.risk`）—— 老板侧栏综合面板会显示
    /// 风险/完成/产物/审批/事件等多类事件，不能套用 risk 限制。
    /// 当前消费方：`bossInspectorRecentEvents` / `bossInspectorCompactRecentReports`
    /// 先统一上限和溢出提示，再交给 `InspectorPanel.BossControlPanel` 渲染。
    public var selectedProductBossEvents: [CompanyEvent] {
        selectedProductEvents.filter { event in
            !isClosureDrillEvent(event)
                && !Self.bossViewExcludedRiskTitlePrefixes.contains { prefix in
                event.title.hasPrefix(prefix)
            }
        }
    }

    /// 老板专属面板「最近老板报告」专用：从 boss agent 全量消息流里
    /// 按当前产品名前缀匹配筛出由 `generateBossReport()` 为本产品生成的报告消息。
    ///
    /// 为什么这里要做产品作用域过滤：`messages(for: bossID)` 是按员工 ID 过滤
    /// （boss 是跨产品角色），所以 boss 的消息流是跨产品累加的。如果不在 view-time
    /// 按产品名过滤，Product B 选中时 BossReportCenter 会把 Product A 的老板报告
    /// 也显示出来，与 UI 文案"汇总当前产品..."相悖。
    ///
    /// 实现：`generateBossReport()` 写入的报告文本固定以 `"老板报告：<产品名>\n"`
    /// 开头（line 3294-3321 写入 bossID 流），按此前缀匹配可稳定锁定本产品报告。
    /// 时间倒序（最新在前），与原 `BossReportCenter.bossMessages` 行为一致。
    ///
    /// 2026-05-05 candidate λ 第一阶段：新报告优先按 `ChatMessage.productID`
    /// 过滤；旧 state.json 里的 nil 消息仍用产品名前缀 fallback，避免历史报告消失。
    /// 已知限制：legacy prefix 匹配在产品重命名后会失效；等历史消息迁移后可移除 fallback。
    public var selectedProductBossReportMessages: [ChatMessage] {
        let productName = selectedProduct?.name ?? "当前产品".L()
        let header = "老板报告：".L() + "\(productName)"
        let scopedReports = messages(for: bossID, in: selectedProductID, includingLegacyGlobal: false)
            .reversed()
            .filter { $0.text.hasPrefix("老板报告：".L()) }
        if !scopedReports.isEmpty {
            return Array(scopedReports)
        }
        return messages(for: bossID).reversed().filter { $0.productID == nil && $0.text.hasPrefix(header) }
    }

    public var selectedProductArtifacts: [ArtifactRecord] {
        artifacts.filter { $0.productID == selectedProductID }
    }

    public var selectedProductRecentArtifacts: [ArtifactRecord] {
        selectedProductArtifacts.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// 老板/交付视图过滤掉的技术维护类 ArtifactRecord 标题清单。
    /// 这些是技术负责人维护侧的安全检查点 / 命令行作业档案 / 闭环审计报告 / 本地文件索引等运维产物，
    /// 老板总控台、产品详情交付区、交付验收中心、运营套件验收抽屉都不展示；
    /// 真实交付（验收产物 / 验收报告 / 项目扫描出的规则与文档）仍可见。
    ///
    /// 新增 `ArtifactRecord` 时必须二选一登记：
    /// - 维护：登记到 `technicalMaintenanceArtifactTitleExactMatches` 或 `technicalMaintenanceArtifactTitlePrefixes`。
    /// - 交付：登记到 `deliveryArtifactTitleExactMatches` 或 `deliveryArtifactTitlePrefixes`，
    ///   或保持「无显式登记」由源码扫描接受动态文件名作为交付。
    /// 集中分类守门由 `artifactRecordTitleLiteralsAreClassifiedInCompanyStore` 测试在 `swift test`
    /// 阶段强制执行——任何未登记的字面量标题会让测试立刻失败。
    public static let technicalMaintenanceArtifactTitleExactMatches: Set<String> = [
        "安全检查点".L()
    ]

    public static let technicalMaintenanceArtifactTitlePrefixes: [String] = [
        "闭环审计报告：".L(),
        "命令行作业档案：".L(),
        "本地文件索引：".L()
    ]

    public static let deliveryArtifactTitleExactMatches: Set<String> = []

    public static let deliveryArtifactTitlePrefixes: [String] = [
        "验收产物：".L(),
        "验收报告：".L()
    ]

    public func isTechnicalMaintenanceArtifact(_ record: ArtifactRecord) -> Bool {
        if isClosureDrillArtifact(record) { return true }
        if Self.technicalMaintenanceArtifactTitleExactMatches.contains(record.title) { return true }
        return Self.technicalMaintenanceArtifactTitlePrefixes.contains { record.title.hasPrefix($0) }
    }

    /// 判定是否属于"老板/交付视图应当展示"的真实交付证据。
    /// 与 `isTechnicalMaintenanceArtifact` 不是简单互补——动态文件名（项目扫描候选 / 本地文件索引文件名）
    /// 不会显式命中任一前缀/精确集合，会被默认接受为交付证据；这是有意设计：项目根目录里的真实文件
    /// （AGENTS.md / Sources / Tests / 用户文档）是老板侧应当看到的交付。
    public func isDeliveryArtifact(_ record: ArtifactRecord) -> Bool {
        if isClosureDrillArtifact(record) { return false }
        return !isTechnicalMaintenanceArtifact(record)
    }

    private func closureDrillGoal(for goal: String) -> String {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanGoal.hasPrefix(Self.closureDrillGoalMarker) { return cleanGoal }
        return "\(Self.closureDrillGoalMarker) \(cleanGoal)"
    }

    private func closureDrillDisplayGoal(_ goal: String) -> String {
        goal.replacingOccurrences(of: "\(Self.closureDrillGoalMarker) ", with: "")
            .replacingOccurrences(of: Self.closureDrillGoalMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isClosureDrillTask(_ task: CompanyTask) -> Bool {
        task.title.contains(Self.closureDrillGoalMarker)
            || task.successCriteria.contains(Self.closureDrillGoalMarker)
    }

    private func isClosureDrillTaskID(_ taskID: UUID?) -> Bool {
        guard let taskID,
              let task = tasks.first(where: { $0.id == taskID })
        else { return false }
        return isClosureDrillTask(task)
    }

    private func isClosureDrillArtifact(_ record: ArtifactRecord) -> Bool {
        record.title.contains(Self.closureDrillGoalMarker)
            || record.summary.contains(Self.closureDrillGoalMarker)
            || isClosureDrillTaskID(record.taskID)
    }

    private func isClosureDrillVerification(_ record: VerificationRecord) -> Bool {
        record.title.contains(Self.closureDrillGoalMarker)
            || record.detail.contains(Self.closureDrillGoalMarker)
    }

    private func isClosureDrillEvent(_ event: CompanyEvent) -> Bool {
        event.title.contains(Self.closureDrillGoalMarker)
            || event.detail.contains(Self.closureDrillGoalMarker)
            || event.title.contains("闭环演练".L())
            || event.detail.contains("闭环演练".L())
    }

    private func isClosureDrillAgentMessage(_ message: AgentMessageEnvelope) -> Bool {
        message.subject.contains(Self.closureDrillGoalMarker)
            || message.body.contains(Self.closureDrillGoalMarker)
            || isClosureDrillTaskID(message.taskID)
    }

    /// 老板/交付视图使用：剔除运维产物。
    public var selectedProductDeliveryArtifacts: [ArtifactRecord] {
        selectedProductArtifacts.filter { isDeliveryArtifact($0) }
    }

    public var selectedProductRecentDeliveryArtifacts: [ArtifactRecord] {
        selectedProductRecentArtifacts.filter { isDeliveryArtifact($0) }
    }

    /// 技术负责人维护视图使用：仅运维产物（安全检查点 / 命令行作业档案 / 闭环审计报告 / 本地文件索引）。
    public var selectedProductMaintenanceArtifacts: [ArtifactRecord] {
        selectedProductArtifacts.filter { isTechnicalMaintenanceArtifact($0) }
    }

    public var selectedProductRecentMaintenanceArtifacts: [ArtifactRecord] {
        selectedProductRecentArtifacts.filter { isTechnicalMaintenanceArtifact($0) }
    }

    /// 当前产品下"本地文件索引".L()维护产物的数量。
    /// 售前方案工厂等需要引用本地资料索引的内部模型 prompt 用此 helper：技术负责人维护侧（不是老板/交付）
    /// 才能看到这些索引产物，但模型仍可基于 prompt 里的索引数量做判断；老板/交付视图不展示。
    public var selectedProductLocalFileIndexArtifactCount: Int {
        selectedProductMaintenanceArtifacts.filter { $0.title.hasPrefix("本地文件索引：".L()) }.count
    }

    /// 当前产品下未分类的 VerificationRecord：既不是维护类、也不是交付类。
    /// 当 `swift test` 阶段的源码扫描守门已经覆盖编译期字面量后，这条主要拦截：
    /// (1) 旧持久化快照里残留的、当前已被重命名/删除的标题；
    /// (2) 测试或运行时通过非 helper 路径直接 insert 的非法记录；
    /// (3) 未来动态构造的 title。
    public var selectedProductUnclassifiedVerificationRecords: [VerificationRecord] {
        selectedProductVerifications.filter { record in
            !isTechnicalMaintenanceVerification(record) && !isDeliveryVerification(record)
        }
    }

    /// 当前产品下未分类的 ArtifactRecord：仅检测带 `X：Y` 全角冒号结构化前缀的 title，
    /// 既不命中维护前缀/精确集合，也不命中交付前缀/精确集合。
    /// 不命中此规则的动态文件名（如 `data.csv` / `AGENTS.md`）按默认交付继续保留——避免误伤真实交付文件。
    public var selectedProductUnclassifiedArtifactRecords: [ArtifactRecord] {
        selectedProductArtifacts.filter { record in
            // 只对结构化前缀的 title 执行未分类检测：
            // (a) 含全角冒号「：」（中文产品话术里典型的 `X：Y` 标签结构，几乎不会和路径/URL/时间戳冲突）；
            // (b) 含半角 `: ` 冒号 + 空格（人类可读的英文 / 中文混合标签结构，如 `未登记类别: 示例`），
            //     但 `: ` 之前不能含 `/` 或 `\` 路径标记——这样可以排除 URL（`https://...` 是 `:/`）、
            //     时间戳（`10:30:00` 没空格）、文件路径（`/usr/bin/foo: bar` 含 `/`）等动态证据。
            guard Self.titleLooksLikeStructuredPrefix(record.title) else { return false }
            if isTechnicalMaintenanceArtifact(record) { return false }
            if Self.deliveryArtifactTitleExactMatches.contains(record.title) { return false }
            if Self.deliveryArtifactTitlePrefixes.contains(where: { record.title.hasPrefix($0) }) { return false }
            return true
        }
    }

    /// 标题是否带"X：Y" / "X: Y"结构化前缀风格（用于未分类巡检）。
    /// 仅用于报告，不参与默认交付/维护过滤。
    fileprivate static func titleLooksLikeStructuredPrefix(_ title: String) -> Bool {
        if title.contains("：") { return true }
        guard let colonSpaceRange = title.range(of: ": ") else { return false }
        let prefix = title[title.startIndex..<colonSpaceRange.lowerBound]
        // 路径/URL 含 `/` 或 `\` —— 视为动态证据，不报告。
        let hasPathMarker = prefix.contains(where: { $0 == "/" || $0 == "\\" })
        return !hasPathMarker
    }

    /// 中文预览（不写入快照）：当前产品的未分类证据巡检结果。
    public func evidenceClassificationAuditText() -> String {
        let unclassifiedVR = selectedProductUnclassifiedVerificationRecords
        let unclassifiedAR = selectedProductUnclassifiedArtifactRecords
        var lines: [String] = [
            "运行证据分类巡检：".L() + "\(selectedProduct?.name ?? "当前产品")",
            "未分类验证记录：".L() + "\(unclassifiedVR.count)" + " 条".L(),
            "未分类产物档案：".L() + "\(unclassifiedAR.count)" + " 条".L()
        ]
        if !unclassifiedVR.isEmpty {
            lines.append("⚠️ 未分类验证记录会从老板/交付视图过滤掉，也不在维护视图——请把标题登记到「技术维护」或「交付验收」分类清单。".L())
            for record in unclassifiedVR.prefix(10) {
                lines.append("- " + "\(record.title)" + "（状态：".L() + "\(record.status.title)" + "）")
            }
        }
        if !unclassifiedAR.isEmpty {
            lines.append("⚠️ 未分类结构化产物会按默认进入老板/交付视图——请把标题登记到「技术维护」或「交付验收」的产物分类清单。".L())
            lines.append("识别规则：标题含全角「：」或半角「: 」（冒号 + 空格，前缀不含 `/` `\\` 路径标记）视为结构化前缀；URL、文件路径、时间戳和普通动态文件名不会被巡检报告。".L())
            for record in unclassifiedAR.prefix(10) {
                lines.append("- \(record.title)")
            }
        }
        if unclassifiedVR.isEmpty && unclassifiedAR.isEmpty {
            lines.append("结论：当前产品所有运行证据都已显式分类。".L())
        } else {
            lines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不删除任何证据。".L())
        }
        return lines.joined(separator: "\n")
    }

    /// 运行运行证据分类巡检：写一条维护类 VerificationRecord，便于技术维护审计中心追踪。
    /// 不修改 / 不删除任何已有证据；不写老板聊天 / 员工协作消息 / 命令行作业档案。
    @discardableResult
    public func runEvidenceClassificationAuditForSelectedProduct() -> VerificationRecord {
        let detail = evidenceClassificationAuditText()
        let unclassifiedVR = selectedProductUnclassifiedVerificationRecords
        let unclassifiedAR = selectedProductUnclassifiedArtifactRecords
        let status: VerificationStatus = (unclassifiedVR.isEmpty && unclassifiedAR.isEmpty) ? .passed : .warning
        let record = VerificationRecord(
            productID: selectedProductID,
            status: status,
            title: "运行证据分类巡检".L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        return record
    }

    /// 维护数据建议阈值：维护类 VerificationRecord 累计超过 100 条 / 维护类 ArtifactRecord 累计超过 500 条
    /// 时给技术负责人提示。当前不做任何删除/裁剪：主快照仍是权威状态，长期清理仍由历史归档 RFC 决定。
    public static let maintenanceVerificationGrowthAdvisoryThreshold = 100
    public static let maintenanceArtifactGrowthAdvisoryThreshold = 500
    public static let maintenanceStateSnapshotAdvisoryBytes: Int64 = 20 * 1024 * 1024
    public static let maintenanceJobArchiveCountAdvisoryThreshold = 100
    public static let maintenanceJobArchiveBytesAdvisoryThreshold: Int64 = 100 * 1024 * 1024

    /// 中文预览（不写快照）：当前产品维护数据增长压力。
    public func maintenanceDataPressureText() -> String {
        let vrCount = selectedProductMaintenanceVerifications.count
        let arCount = selectedProductMaintenanceArtifacts.count
        let vrLatest = selectedProductRecentMaintenanceVerifications.first?.createdAt
        let arLatest = selectedProductRecentMaintenanceArtifacts.first?.createdAt
        let vrThreshold = Self.maintenanceVerificationGrowthAdvisoryThreshold
        let arThreshold = Self.maintenanceArtifactGrowthAdvisoryThreshold
        let stateSnapshotBytes = Self.fileSize(at: CompanyPersistence.stateURL)
        let jobArchiveSummary = currentProductJobArchiveStorageSummary()
        let exceedsVR = vrCount >= vrThreshold
        let exceedsAR = arCount >= arThreshold
        let exceedsState = stateSnapshotBytes >= Self.maintenanceStateSnapshotAdvisoryBytes
        let exceedsJobArchiveCount = jobArchiveSummary.jobCount >= Self.maintenanceJobArchiveCountAdvisoryThreshold
        let exceedsJobArchiveBytes = jobArchiveSummary.bytes >= Self.maintenanceJobArchiveBytesAdvisoryThreshold

        var lines: [String] = [
            "维护数据增长预览：".L() + "\(selectedProduct?.name ?? "当前产品")",
            "维护验证记录：".L() + "\(vrCount)" + " 条（建议阈值 ".L() + "\(vrThreshold)" + " 条）".L(),
            "维护产物档案：".L() + "\(arCount)" + " 条（建议阈值 ".L() + "\(arThreshold)" + " 条）".L(),
            "主状态快照：".L() + "\(stateSnapshotBytes > 0 ? Self.byteCountText(stateSnapshotBytes) : "尚未生成")" + "（建议阈值 ".L() + "\(Self.byteCountText(Self.maintenanceStateSnapshotAdvisoryBytes))" + "）",
            "命令行作业档案：".L() + "\(jobArchiveSummary.jobCount)" + " 个 · " + "\(Self.byteCountText(jobArchiveSummary.bytes))" + "（建议阈值 " + "\(Self.maintenanceJobArchiveCountAdvisoryThreshold)" + " 个 / " + "\(Self.byteCountText(Self.maintenanceJobArchiveBytesAdvisoryThreshold))" + "）"
        ]
        if let vrLatest {
            lines.append("最近维护验证：".L() + "\(vrLatest.opcDateTimeText)")
        } else {
            lines.append("最近维护验证：暂无".L())
        }
        if let arLatest {
            lines.append("最近维护产物：".L() + "\(arLatest.opcDateTimeText)")
        } else {
            lines.append("最近维护产物：暂无".L())
        }

        if exceedsVR || exceedsAR || exceedsState || exceedsJobArchiveCount || exceedsJobArchiveBytes {
            lines.append("⚠️ 已经达到或超过建议阈值。当前不会自动删除或裁剪主快照——主快照仍是权威状态，请按需在终端大厅维护区运行「历史索引巡检」或「历史归档迁移」把旧记录复制到本地归档表。".L())
            if exceedsVR { lines.append("  · 维护验证已达 ".L() + "\(vrCount)" + " 条，超过 ".L() + "\(vrThreshold)" + " 条阈值。".L()) }
            if exceedsAR { lines.append("  · 维护产物已达 ".L() + "\(arCount)" + " 条，超过 ".L() + "\(arThreshold)" + " 条阈值。".L()) }
            if exceedsState { lines.append("  · 主状态快照已达 " + "\(Self.byteCountText(stateSnapshotBytes))" + "，超过 " + "\(Self.byteCountText(Self.maintenanceStateSnapshotAdvisoryBytes))" + " 阈值。") }
            if exceedsJobArchiveCount { lines.append("  · 命令行作业档案已达 ".L() + "\(jobArchiveSummary.jobCount)" + " 个，超过 ".L() + "\(Self.maintenanceJobArchiveCountAdvisoryThreshold)" + " 个阈值。") }
            if exceedsJobArchiveBytes { lines.append("  · 命令行作业档案体积已达 " + "\(Self.byteCountText(jobArchiveSummary.bytes))" + "，超过 " + "\(Self.byteCountText(Self.maintenanceJobArchiveBytesAdvisoryThreshold))" + " 阈值。") }
        } else {
            lines.append("结论：维护数据未达建议阈值，暂不需要归档处理。".L())
        }
        lines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不删除任何数据、不裁剪主快照。".L())
        return lines.joined(separator: "\n")
    }

    public func linkedLocalFileRootAllowlistText() -> String {
        guard let product = selectedProduct else { return "本地文件索引根白名单\n当前没有选中的产品。".L() }
        let rawRoot = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath).standardizedFileURL
        let resolvedRoot = rawRoot.resolvingSymlinksInPath()
        let allowedRoots = Self.linkedLocalFileAllowedRootPaths(from: products)
        let allowed = Self.isAllowedLinkedLocalFileRoot(rawRoot: rawRoot, resolvedRoot: resolvedRoot, allowedRootPaths: allowedRoots)
        let visibleRoots = allowedRoots.sorted().prefix(8).map { "- \($0)" }
        let hiddenCount = max(0, allowedRoots.count - visibleRoots.count)
        var lines: [String] = [
            "本地文件索引根白名单".L(),
            "产品：".L() + "\(product.name)",
            "当前根目录：".L() + "\(rawRoot.path)",
            "解析后目录：".L() + "\(resolvedRoot.path)",
            "当前状态：".L() + "\(allowed ? "已登记，可索引" : "未登记，索引会被拒绝")",
            "",
            "已登记工作区根目录：".L()
        ]
        lines.append(contentsOf: visibleRoots)
        if hiddenCount > 0 {
            lines.append("- 其余 ".L() + "\(hiddenCount)" + " 个根目录已隐藏".L())
        }
        lines.append("")
        lines.append("说明：本白名单来自已导入或已创建的产品工作区根目录；本地文件索引只允许扫描这些根目录内的文件。新增根目录请通过产品导入或项目设置登记。".L())
        return lines.joined(separator: "\n")
    }

    public var legacyTaskWithoutProductIDCount: Int {
        tasks.filter { $0.productID == nil }.count
    }

    public func legacyTaskProductMigrationText() -> String {
        let legacyCount = legacyTaskWithoutProductIDCount
        return """
        \("旧任务产品归属迁移：预览".L())
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("待迁移旧任务：".L())\(legacyCount)\(" 个".L())
        \("迁移目标：当前产品".L())

        \("说明：".L())
        \("本迁移只处理旧快照里没有产品归属的任务，把它们一次性归入当前产品；不会删除任务、不会修改已有产品归属、不会启动模型任务。未迁移的旧任务不会进入任意产品视图，会留在本维护入口等待归属确认。".L())
        """
    }

    @discardableResult
    public func runLegacyTaskProductMigrationForSelectedProduct() -> VerificationRecord {
        let before = legacyTaskWithoutProductIDCount
        let migrated = migrateLegacyTasksWithoutProductID(targetProductID: selectedProductID)
        let after = legacyTaskWithoutProductIDCount
        let status: VerificationStatus = after == 0 ? .passed : .warning
        let detail = """
        \("旧任务产品归属迁移：".L())\(status.title)
        \("产品：".L())\(selectedProduct?.name ?? "当前产品")
        \("迁移前旧任务：".L())\(before)\(" 个".L())
        \("本次迁移：".L())\(migrated)\(" 个".L())
        \("剩余旧任务：".L())\(after)\(" 个".L())

        \("说明：".L())
        \("本次只把没有产品归属的旧任务回填到当前产品；已有产品归属的任务未被改写。未迁移的旧任务不会进入任意产品视图，会继续留在本维护入口等待归属确认。".L())
        """
        let record = VerificationRecord(productID: selectedProductID, status: status, title: "旧任务产品归属迁移".L(), detail: detail)
        verifications.insert(record, at: 0)
        appendEvent(kind: .statusChanged, title: "旧任务产品归属迁移完成".L(), detail: "已迁移 " + "\(migrated)" + " 个旧任务到当前产品，剩余 " + "\(after)" + " 个。", agentID: ctoID)
        saveSnapshot()
        return record
    }

    /// 运行维护数据增长巡检：写一条维护类 VerificationRecord，便于技术维护审计中心追踪。
    /// 不修改/不删除任何数据；不写老板聊天/员工协作消息/作业档案。
    @discardableResult
    public func runMaintenanceDataPressureAuditForSelectedProduct() -> VerificationRecord {
        let detail = maintenanceDataPressureText()
        let vrCount = selectedProductMaintenanceVerifications.count
        let arCount = selectedProductMaintenanceArtifacts.count
        let stateSnapshotBytes = Self.fileSize(at: CompanyPersistence.stateURL)
        let jobArchiveSummary = currentProductJobArchiveStorageSummary()
        let exceeds = vrCount >= Self.maintenanceVerificationGrowthAdvisoryThreshold
            || arCount >= Self.maintenanceArtifactGrowthAdvisoryThreshold
            || stateSnapshotBytes >= Self.maintenanceStateSnapshotAdvisoryBytes
            || jobArchiveSummary.jobCount >= Self.maintenanceJobArchiveCountAdvisoryThreshold
            || jobArchiveSummary.bytes >= Self.maintenanceJobArchiveBytesAdvisoryThreshold
        let status: VerificationStatus = exceeds ? .warning : .passed
        let record = VerificationRecord(
            productID: selectedProductID,
            status: status,
            title: "维护数据增长巡检".L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        return record
    }

    private func currentProductJobArchiveStorageSummary() -> (jobCount: Int, bytes: Int64) {
        let jobsRoot = cliWorkingDirectoryURL().appendingPathComponent(".opc/jobs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: jobsRoot.path) else { return (0, 0) }
        let jobDirectories = ((try? FileManager.default.contentsOfDirectory(
            at: jobsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return (jobDirectories.count, Self.directoryFileSize(at: jobsRoot))
    }

    private static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    private static func directoryFileSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private static func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    /// 终端大厅顶部默认可见的简洁概览：技术负责人一眼看到运行状态 + 风险 + 关键下一步。
    /// 终端大厅默认即是摘要化工作台：架构体检 / 通信网关 / 本地稳定性都以摘要卡片默认可见，
    /// 完整长报告 / 配置面板按需通过「查看详情」打开二级面板。本预览不暴露 backend / CLI / identifier 等内部字段。
    public func terminalHallOverviewSummaryText() -> String {
        let team = selectedProductAgents.count
        let running = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }.count
        let pendingApprovals = selectedProductApprovals.filter { $0.status == .pending }.count
        let blocked = selectedProductTasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }.count
        let recentRisks = selectedProductEvents.filter { $0.kind == .risk }.prefix(5).count
        let nextStep: String
        if pendingApprovals > 0 {
            nextStep = "下一步：先在老板决策中心处理 ".L() + "\(pendingApprovals)" + " 项待审批。".L()
        } else if blocked > 0 {
            nextStep = "下一步：阻塞/失败任务 ".L() + "\(blocked)" + " 项，请在产品详情或员工工作台跟进。".L()
        } else if recentRisks > 0 {
            nextStep = "下一步：最近风险 ".L() + "\(recentRisks)" + " 条，可在事件流核对。".L()
        } else if running == 0 && team > 0 {
            nextStep = "下一步：选择员工运行任务，或在下方摘要工作台运行常用巡检。".L()
        } else {
            nextStep = "下一步：保持运行；下方摘要工作台展示架构 / 通信 / 维护核心指标。".L()
        }
        return [
            "终端大厅运行状态：".L() + "\(selectedProduct?.name ?? "当前产品")",
            "团队 ".L() + "\(team)" + " 人 · 运行中 ".L() + "\(running)" + " · 待审批 ".L() + "\(pendingApprovals)" + " · 阻塞/失败 ".L() + "\(blocked)" + " · 最近风险 ".L() + "\(recentRisks)",
            nextStep,
            "提示：下方摘要工作台默认可见架构体检 / 通信网关 / 本地稳定性的状态、核心指标与主要操作；点击「查看详情」按需打开完整面板。".L()
        ].joined(separator: "\n")
    }

    /// 终端大厅顶部概览的「视觉层结构化指标」accessor（与下方 SummaryCard 信息架构对齐）。
    ///
    /// 与 `terminalHallOverviewSummaryText()` 拆开的原因：纯文本 4 行被 view 直接渲染时，
    /// 标题与卡头重复 / 提示行重复下方 SummaryCard 已默认可见的事实 / 5 个指标用 `·`
    /// 拼接信息密度低且无颜色编码。`terminalHallOverviewSummaryText` 保留作为聊天/复制/
    /// 审计兜底字符串，并仍由 `terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure`
    /// 守门，确保「摘要工作台 / 查看详情」中文方向 token 不丢失。
    public func terminalHallOverviewMetrics() -> [TerminalHallOverviewMetric] {
        let team = selectedProductAgents.count
        let running = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }.count
        let pendingApprovals = selectedProductApprovals.filter { $0.status == .pending }.count
        let blocked = selectedProductTasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }.count
        let recentRisks = selectedProductEvents.filter { $0.kind == .risk }.prefix(5).count
        var metrics: [TerminalHallOverviewMetric] = [
            TerminalHallOverviewMetric(title: "团队".L(), value: team, kind: .neutral),
            TerminalHallOverviewMetric(title: "运行中".L(), value: running, kind: running > 0 ? .ok : .neutral),
            TerminalHallOverviewMetric(title: "待审批".L(), value: pendingApprovals, kind: pendingApprovals > 0 ? .warning : .neutral),
            TerminalHallOverviewMetric(title: "阻塞/失败".L(), value: blocked, kind: blocked > 0 ? .danger : .neutral),
            TerminalHallOverviewMetric(title: "最近风险".L(), value: recentRisks, kind: recentRisks > 0 ? .danger : .neutral)
        ]
        // 健康预警 chip：当且仅当当前产品有员工处于轮 4 徽章可见状态（attention）时追加；
        // 默认情况（无 attention 员工）保持 5 个 chip 不变，避免常规场景下挤压窄屏卡片。
        let attentionCount = terminalHallOverviewAttentionAgentCount()
        if attentionCount > 0 {
            metrics.append(TerminalHallOverviewMetric(title: "健康预警".L(), value: attentionCount, kind: .danger))
        }
        return metrics
    }

    /// 当前产品所有员工里有多少处于「需要技术负责人注意」状态。
    /// 复用轮 4 `terminalAgentCardHealthBadge(for:)` 数据源；徽章 nil 的员工（OK / unknown / API/local）
    /// 不计入。该 accessor 是轮 5「健康预警 chip」的数据源，也可被未来面板独立调用。
    public func terminalHallOverviewAttentionAgentCount() -> Int {
        selectedProductAgents.filter { agent in
            terminalAgentCardHealthBadge(for: agent.id) != nil
        }.count
    }

    public func terminalHallOverviewNextStepText() -> String {
        let running = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }.count
        let team = selectedProductAgents.count
        let pendingApprovals = selectedProductApprovals.filter { $0.status == .pending }.count
        let blocked = selectedProductTasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }.count
        let recentRisks = selectedProductEvents.filter { $0.kind == .risk }.prefix(5).count
        if pendingApprovals > 0 {
            return "下一步：先在老板决策中心处理 ".L() + "\(pendingApprovals)" + " 项待审批。".L()
        } else if blocked > 0 {
            return "下一步：阻塞/失败任务 ".L() + "\(blocked)" + " 项，请在产品详情或员工工作台跟进。".L()
        } else if recentRisks > 0 {
            return "下一步：最近风险 ".L() + "\(recentRisks)" + " 条，可在事件流核对。".L()
        } else if running == 0 && team > 0 {
            return "下一步：选择员工运行任务，或在下方摘要工作台运行常用巡检。".L()
        } else {
            return "下一步：保持运行；下方摘要工作台展示架构 / 通信 / 维护核心指标。".L()
        }
    }

    public var selectedProductVerifications: [VerificationRecord] {
        verifications.filter { $0.productID == selectedProductID }
    }

    public var selectedProductRecentVerifications: [VerificationRecord] {
        selectedProductVerifications.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// 老板/交付视图过滤掉的技术维护类 VerificationRecord 标题清单。
    /// 这些是技术负责人维护侧的巡检/恢复/审计/真实终端工作区记录，老板总控台、产品详情交付区、
    /// 交付验收中心和「最近交付与验收」widget 都只展示真正的交付/验收证据，不展示运维巡检细节。
    /// 真实交付（老板验收通过、自动验收检查、产物扫描等）仍可见。
    ///
    /// 新增 `VerificationRecord` 时必须二选一登记：
    /// - `technicalMaintenanceVerificationTitles`：纯运维/巡检/审计；老板/交付视图不展示。
    /// - `deliveryVerificationTitleExactMatches` 或 `deliveryVerificationTitlePrefixes`：真实交付/验收证据；
    ///   老板首页 widget、产品详情交付区、交付验收中心、运营套件验收指标都会展示。
    /// 集中分类守门由 `verificationRecordTitlesAreClassifiedAsMaintenanceOrDelivery` 测试在 `swift test`
    /// 阶段扫描 `CompanyStore.swift` 字面量强制执行——任何未登记的新标题会让测试立刻失败。
    public static let technicalMaintenanceVerificationTitles: Set<String> = [
        terminalAutoInteractionAuditTitle,
        terminalAutoInteractionStopAuditTitle,
        "真实终端工作区".L(),
        "真实终端日志刷新".L(),
        "持久终端可用性巡检".L(),
        "命令行链路压测预检".L(),
        "命令行任务发车计划".L(),
        "命令行与工作区隔离体检".L(),
        "多产品隔离体检".L(),
        "命令行作业幽灵巡检".L(),
        "员工交接待确认巡检".L(),
        "运行会话健康巡检".L(),
        "异常占用会话恢复".L(),
        "历史索引巡检".L(),
        "历史归档迁移".L(),
        "旧任务产品归属迁移".L(),
        "本地文件索引完成".L(),
        "本地文件索引被拒绝".L(),
        "安全检查点已创建".L(),
        "安全检查点失败".L(),
        "运行证据分类巡检".L(),
        "维护数据增长巡检".L(),
        "自动状态摘要去重清理".L()
    ]

    /// 老板/交付视图必须保留的「交付/验收证据」精确标题。
    public static let deliveryVerificationTitleExactMatches: Set<String> = [
        "自动验收检查".L(),
        "产物扫描完成".L(),
        "产物扫描失败".L()
    ]

    /// 老板/交付视图必须保留的「交付/验收证据」前缀标题（带任务标题等动态后缀）。
    public static let deliveryVerificationTitlePrefixes: [String] = [
        "老板验收通过：".L()
    ]

    public func isTechnicalMaintenanceVerification(_ record: VerificationRecord) -> Bool {
        if isClosureDrillVerification(record) { return true }
        return Self.technicalMaintenanceVerificationTitles.contains(record.title)
    }

    /// 显式判定一条 `VerificationRecord` 是否属于"老板/交付视图应当展示"的真实交付证据。
    /// 与 `isTechnicalMaintenanceVerification` 不是简单互补——少数无名记录可能两边都不命中，
    /// 这种情况由源码扫描守门测试在 `swift test` 阶段强制让作者显式登记。
    public func isDeliveryVerification(_ record: VerificationRecord) -> Bool {
        if isClosureDrillVerification(record) { return false }
        if Self.deliveryVerificationTitleExactMatches.contains(record.title) { return true }
        return Self.deliveryVerificationTitlePrefixes.contains { record.title.hasPrefix($0) }
    }

    public var selectedProductDeliveryVerifications: [VerificationRecord] {
        selectedProductVerifications.filter { isDeliveryVerification($0) }
    }

    public var selectedProductRecentDeliveryVerifications: [VerificationRecord] {
        selectedProductRecentVerifications.filter { isDeliveryVerification($0) }
    }

    /// 当前产品的技术维护类验证记录（运维巡检/恢复/审计/真实终端工作区）。
    /// 只在技术负责人/终端大厅维护视图展示，老板总控台、产品详情交付区、交付验收中心都不暴露。
    public var selectedProductMaintenanceVerifications: [VerificationRecord] {
        selectedProductVerifications.filter { isTechnicalMaintenanceVerification($0) }
    }

    /// 当前产品的技术维护类验证记录（按时间倒序）。技术维护审计中心展示用。
    public var selectedProductRecentMaintenanceVerifications: [VerificationRecord] {
        selectedProductRecentVerifications.filter { isTechnicalMaintenanceVerification($0) }
    }

    public var selectedProductAcceptanceTasks: [CompanyTask] {
        selectedProductTasks.filter { task in
            task.artifactPath != nil || [.needsReview, .needsApproval, .done].contains(task.status)
        }
    }

    public var selectedProductMemories: [ProductMemoryNote] {
        memories.filter { $0.productID == selectedProductID }
    }

    /// 产品详情「产品记忆库」默认显示上限。完整记忆仍保留在产品记忆集合中，
    /// 默认卡片只浮出最近一组，避免工作区底部被历史记忆挤占。
    public static let productMemoryDefaultDisplayLimit: Int = 6

    public var selectedProductVisibleMemories: [ProductMemoryNote] {
        Array(selectedProductMemories.prefix(Self.productMemoryDefaultDisplayLimit))
    }

    public func selectedProductMemoryOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductMemories.count
        let limit = Self.productMemoryDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 条长期记忆。关键决策、规则和风险会继续保留在产品记忆库。".L()
        )
    }

    public func selectedProductAgentMemories(for agentID: UUID) -> [ProductMemoryNote] {
        memories.filter { $0.productID == selectedProductID && $0.agentID == agentID }
    }

    public var selectedProductCommunicationChannels: [CommunicationChannelConfig] {
        communicationChannels.filter { $0.productID == selectedProductID || $0.productID == nil }
    }

    public var selectedProductCommunicationLogs: [CommunicationLogEntry] {
        communicationLogs.filter { $0.productID == selectedProductID }
    }

    public var selectedProductBranchPlans: [BranchExecutionPlan] {
        branchPlans.filter { $0.productID == selectedProductID }
    }

    public var selectedProductReviewGates: [ReviewGateRecord] {
        reviewGates
            .filter { $0.productID == selectedProductID }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public var selectedProductDeliveryReviewGates: [ReviewGateRecord] {
        selectedProductReviewGates.filter { !isClosureDrillTaskID($0.taskID) }
    }

    public var selectedProductArchitectureChecks: [MultiAgentArchitectureCheck] {
        let messages = selectedProductAgentMessages
        let supervisorTasks = selectedProductTasks.filter(isCTOSupervisorTask)
        let taskGraphs = selectedProductClosureTraces.map { closureTraceTaskGraph($0) }
        let closureTraces = selectedProductClosureTraces
        let taskGraphNodeCount = taskGraphs.map(\.nodes.count).max() ?? 0
        let taskGraphEdgeCount = taskGraphs.map(\.edges.count).max() ?? 0
        let taskGraphClosedEdgeCount = taskGraphs
            .map { graph in graph.edges.filter { $0.status == .passed }.count }
            .max() ?? 0
        func strongestTraceStepStatus(_ stepID: String) -> ArchitectureCheckStatus {
            let statuses = closureTraces.compactMap { trace in
                trace.steps.first { $0.id == stepID }?.status
            }
            if statuses.contains(.passed) { return .passed }
            if statuses.contains(.warning) { return .warning }
            return .failed
        }
        let strongestEvidenceStatus = strongestTraceStepStatus("evidence")
        let strongestReviewGateStatus = strongestTraceStepStatus("review-gate")
        let linkedArtifactCount = closureTraces.map(\.artifactIDs.count).max() ?? 0
        let linkedVerificationCount = closureTraces.map(\.verificationIDs.count).max() ?? 0
        let linkedReviewGateCount = closureTraces.map(\.reviewGateIDs.count).max() ?? 0
        let hasGoalStart = messages.contains { $0.kind == .ctoGoalStarted }
        let hasLoopProgress = messages.contains { $0.kind == .ctoLoopProgressed }
        let hasDispatch = messages.contains { $0.kind == .taskDispatched }
        let hasWorkReturn = messages.contains { $0.kind == .workCompleted }
        let hasReview = messages.contains { [.reviewRequested, .reviewCompleted, .acceptanceCompleted].contains($0.kind) }
        let hasApprovalTrace = messages.contains { [.approvalRequested, .approvalDecided].contains($0.kind) }
        let hasArtifacts = !selectedProductDeliveryArtifacts.isEmpty
        let hasVerifications = !selectedProductDeliveryVerifications.isEmpty
        let hasReviewGates = !selectedProductReviewGates.isEmpty

        return [
            MultiAgentArchitectureCheck(
                id: "message-bus",
                title: "结构化消息总线".L(),
                status: messages.isEmpty ? .failed : (hasDispatch && hasWorkReturn ? .passed : .warning),
                detail: messages.isEmpty
                    ? "当前产品还没有员工协作消息。请在技术负责人后台点击「运行闭环演练」，生成任务派发、员工回传、审查和审批证据。".L()
                    : "当前产品已有 ".L() + "\(messages.count)" + " 条消息；派发 ".L() + "\(hasDispatch ? "已出现" : "未出现")" + "，回传 ".L() + "\(hasWorkReturn ? "已出现" : "未出现")" + "。"
            ),
            MultiAgentArchitectureCheck(
                id: "task-graph",
                title: "显式任务图".L(),
                status: taskGraphNodeCount >= 4 && taskGraphEdgeCount >= 4 ? .passed : (supervisorTasks.isEmpty ? .failed : .warning),
                detail: taskGraphNodeCount >= 4 && taskGraphEdgeCount >= 4
                    ? "已派生 ".L() + "\(taskGraphNodeCount)" + " 个节点、".L() + "\(taskGraphEdgeCount)" + " 条边；闭合边 ".L() + "\(taskGraphClosedEdgeCount)" + " 条。"
                    : "当前仍主要是普通任务；点击「运行闭环演练」后会形成技术负责人拆解、员工执行、审查验收和老板审批的标准任务图。".L()
            ),
            MultiAgentArchitectureCheck(
                id: "cto-loop",
                title: "技术负责人调度闭环".L(),
                status: hasGoalStart && hasLoopProgress ? .passed : (hasGoalStart ? .warning : .failed),
                detail: hasGoalStart
                    ? "技术负责人目标已启动；".L() + "\(hasLoopProgress ? "已有循环推进消息。" : "还缺少循环推进记录。")"
                    : "还没有技术负责人启动目标记录。请运行闭环演练或启动技术负责人协作目标来生成调度证据。".L()
            ),
            MultiAgentArchitectureCheck(
                id: "artifact-store",
                title: "交付证据库".L(),
                status: strongestEvidenceStatus == .passed
                    ? .passed
                    : (strongestEvidenceStatus == .warning || hasArtifacts || hasVerifications ? .warning : .failed),
                detail: "闭环关联产物 ".L() + "\(linkedArtifactCount)" + " 条、验收 ".L() + "\(linkedVerificationCount)" + " 条；当前产品总交付产物 ".L() + "\(selectedProductDeliveryArtifacts.count)" + " 条、总交付验收 " + "\(selectedProductDeliveryVerifications.count)" + " 条。闭环关联为 0 时请运行闭环演练补齐证据。"
            ),
            MultiAgentArchitectureCheck(
                id: "review-gate",
                title: "验收门禁".L(),
                status: strongestReviewGateStatus == .passed
                    ? .passed
                    : (strongestReviewGateStatus == .warning || hasReviewGates || hasReview ? .warning : .failed),
                detail: "闭环关联门禁 ".L() + "\(linkedReviewGateCount)" + " 条；当前产品总门禁 ".L() + "\(selectedProductReviewGates.count)" + " 条，审查/验收消息 ".L() + "\(hasReview ? "已出现".L() : "未出现".L())" + "。闭环关联为 0 时请运行闭环演练补齐审查和验收证据。".L()
            ),
            terminalWorkspaceArchitectureCheck(),
            MultiAgentArchitectureCheck(
                id: "boss-view",
                title: "老板视图减噪".L(),
                status: .passed,
                detail: "老板侧使用决策中心和交付验收中心入口；当前待老板决策 ".L() + "\(bossDecisionCount)" + " 项，审批追踪 " + "\(hasApprovalTrace ? "已出现" : "暂无")" + "。"
            )
        ]
    }

    public var selectedProductArchitectureCompletionScore: Int {
        let checks = selectedProductArchitectureChecks
        guard !checks.isEmpty else { return 0 }
        let points = checks.reduce(0) { partial, check in
            let value: Int
            switch check.status {
            case .passed:
                value = 2
            case .warning:
                value = 1
            case .failed:
                value = 0
            }
            return partial + value
        }
        return Int((Double(points) / Double(checks.count * 2) * 100).rounded())
    }

    public var selectedProductClosureTraces: [MultiAgentClosureTrace] {
        let goals = Set(selectedProductTasks.compactMap { task in
            isCTOSupervisorTask(task) ? ctoSupervisorGoalKey(for: task) : nil
        })
        return goals
            .map { multiAgentClosureTrace(for: $0) }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.goal < rhs.goal
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public var latestSelectedProductClosureTrace: MultiAgentClosureTrace? {
        selectedProductClosureTraces.first
    }

    public func closureTraceTasks(_ trace: MultiAgentClosureTrace) -> [CompanyTask] {
        let ids = Set(trace.taskIDs)
        let order = ["技术负责人拆解：".L(), "员工执行：".L(), "审查验收：".L(), "老板审批：".L()]
        return selectedProductTasks
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsIndex = order.firstIndex { lhs.title.hasPrefix($0) } ?? order.count
                let rhsIndex = order.firstIndex { rhs.title.hasPrefix($0) } ?? order.count
                if lhsIndex == rhsIndex {
                    return lhs.title < rhs.title
                }
                return lhsIndex < rhsIndex
            }
    }

    public func closureTraceMessages(_ trace: MultiAgentClosureTrace) -> [AgentMessageEnvelope] {
        let ids = Set(trace.messageIDs)
        return selectedProductAgentMessages
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func closureTraceApprovals(_ trace: MultiAgentClosureTrace) -> [ApprovalRequest] {
        let ids = Set(trace.approvalIDs)
        return selectedProductApprovals
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.decidedAt ?? lhs.createdAt
                let rhsDate = rhs.decidedAt ?? rhs.createdAt
                if lhsDate == rhsDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhsDate > rhsDate
            }
    }

    public func closureTraceReviewGates(_ trace: MultiAgentClosureTrace) -> [ReviewGateRecord] {
        let ids = Set(trace.reviewGateIDs)
        return selectedProductReviewGates.filter { ids.contains($0.id) }
    }

    public func closureTraceArtifacts(_ trace: MultiAgentClosureTrace) -> [ArtifactRecord] {
        let ids = Set(trace.artifactIDs)
        return selectedProductArtifacts
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func closureTraceVerifications(_ trace: MultiAgentClosureTrace) -> [VerificationRecord] {
        let ids = Set(trace.verificationIDs)
        return selectedProductVerifications
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func closureTraceTaskGraph(_ trace: MultiAgentClosureTrace) -> MultiAgentTaskGraph {
        let taskRecords = closureTraceTasks(trace)
        let messages = closureTraceMessages(trace)

        func task(withPrefix prefix: String) -> CompanyTask? {
            taskRecords.first { $0.title.hasPrefix(prefix) }
        }

        func node(for task: CompanyTask, role: String) -> MultiAgentTaskGraphNode {
            MultiAgentTaskGraphNode(
                id: "\(trace.id)-node-\(task.id.uuidString)",
                taskID: task.id,
                role: role,
                title: task.title,
                ownerID: task.ownerID,
                status: task.status
            )
        }

        func edgeStatus(_ checks: [Bool]) -> ArchitectureCheckStatus {
            if checks.allSatisfy({ $0 }) { return .passed }
            return checks.contains(true) ? .warning : .failed
        }

        func edge(
            _ key: String,
            from: CompanyTask?,
            to: CompanyTask?,
            relation: String,
            checks: [Bool],
            evidence: String
        ) -> MultiAgentTaskGraphEdge? {
            guard let from, let to else { return nil }
            return MultiAgentTaskGraphEdge(
                id: "\(trace.id)-edge-\(key)",
                fromTaskID: from.id,
                toTaskID: to.id,
                relation: relation,
                evidence: evidence,
                status: edgeStatus(checks)
            )
        }

        let ctoTask = task(withPrefix: "技术负责人拆解：".L())
        let engineerTask = task(withPrefix: "员工执行：".L())
        let reviewerTask = task(withPrefix: "审查验收：".L())
        let bossTask = task(withPrefix: "老板审批：".L())

        let hasDispatch = messages.contains { $0.kind == .taskDispatched }
        let hasWorkCompleted = messages.contains { $0.kind == .workCompleted }
        let hasEmployeeHandoff = messages.contains { $0.kind == .employeeHandoff }
        let hasReviewRequested = messages.contains { $0.kind == .reviewRequested }
        let hasReviewCompleted = messages.contains { $0.kind == .reviewCompleted }
        let hasApprovalRequested = messages.contains { $0.kind == .approvalRequested }
        let hasApprovalDecided = messages.contains { $0.kind == .approvalDecided }
        let hasAcceptanceCompleted = messages.contains { $0.kind == .acceptanceCompleted }

        let nodes = [
            ctoTask.map { node(for: $0, role: "技术负责人".L()) },
            engineerTask.map { node(for: $0, role: "执行员工".L()) },
            reviewerTask.map { node(for: $0, role: "审查员".L()) },
            bossTask.map { node(for: $0, role: "老板".L()) }
        ].compactMap { $0 }

        let edges = [
            edge(
                "dispatch",
                from: ctoTask,
                to: engineerTask,
                relation: "任务派发".L(),
                checks: [hasDispatch],
                evidence: hasDispatch ? "消息总线已记录技术负责人派发任务。".L() : "缺少任务派发消息。".L()
            ),
            edge(
                "review",
                from: engineerTask,
                to: reviewerTask,
                relation: "执行回传与审查".L(),
                checks: [hasWorkCompleted, hasReviewRequested],
                evidence: "员工回传 ".L() + "\(hasWorkCompleted ? "已记录".L() : "未记录".L())" + "；员工交接 ".L() + "\(hasEmployeeHandoff ? "已记录".L() : "未记录".L())" + "；审查请求 ".L() + "\(hasReviewRequested ? "已记录".L() : "未记录".L())"
            ),
            edge(
                "approval",
                from: reviewerTask,
                to: bossTask,
                relation: "审查结论与审批".L(),
                checks: [hasReviewCompleted, hasApprovalRequested],
                evidence: "审查结论 ".L() + "\(hasReviewCompleted ? "已记录".L() : "未记录".L())" + "；审批请求 ".L() + "\(hasApprovalRequested ? "已记录".L() : "未记录".L())" + "。"
            ),
            edge(
                "acceptance",
                from: bossTask,
                to: ctoTask,
                relation: "老板决策回流".L(),
                checks: [hasApprovalDecided, hasAcceptanceCompleted],
                evidence: "审批结果 ".L() + "\(hasApprovalDecided ? "已记录".L() : "未记录".L())" + "；验收回流 ".L() + "\(hasAcceptanceCompleted ? "已记录".L() : "未记录".L())"
            )
        ].compactMap { $0 }

        return MultiAgentTaskGraph(nodes: nodes, edges: edges)
    }

    public func selectedProductClosureDrillSummaryText() -> String {
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        guard let trace = latestSelectedProductClosureTrace else {
            return """
            \("闭环演练复盘摘要：暂无记录".L())
            \("产品：".L())\(productLabel)

            \("还没有运行多员工闭环演练。请先在技术负责人后台点击「运行闭环演练」，演练结束后这里会显示目标、完成度、任务、消息、审批、验收等关键计数和下一步提示。".L())
            """
        }

        let approvals = closureTraceApprovals(trace)
        let pendingApprovals = approvals.filter { $0.status == .pending }.count
        let resolvedApprovals = approvals.filter { $0.status != .pending }.count
        let gates = closureTraceReviewGates(trace)
        var blockingGates = 0
        let blockingGateStatuses: [ReviewGateStatus] = [.verificationFailed, .verificationWarning, .rejected]
        for gate in gates where blockingGateStatuses.contains(gate.status) {
            blockingGates += 1
        }
        let verifications = closureTraceVerifications(trace)
        let blockingVerifications = verifications.filter { $0.status != .passed }.count
        let tasksByStatus = Dictionary(grouping: closureTraceTasks(trace), by: { $0.status })
        let openTasks = tasksByStatus.values.flatMap { $0 }.filter { $0.status != .done && $0.status != .canceled }.count

        let nextStep: String
        switch trace.status {
        case .passed:
            nextStep = pendingApprovals > 0
                ? "老板审批仍在等待 \(pendingApprovals) 项，可进入老板决策中心确认。"
                : (blockingVerifications > 0
                   ? "验收记录里仍有 \(blockingVerifications) 项不为通过，建议复看交付验收中心。"
                   : "闭环已通过，可在老板视图按「看结果/批风险/验交付」流程收尾。")
        case .warning:
            nextStep = blockingGates > 0
                ? "审查门禁有 \(blockingGates) 项告警，请审查员补充结论或补充证据。"
                : (pendingApprovals > 0
                   ? "存在 \(pendingApprovals) 项待审批，先让老板裁定再继续。"
                   : "完成度 \(trace.completionScore)%，还差几步，可继续推进技术负责人调度循环。")
        case .failed:
            nextStep = "闭环失败：完成度 \(trace.completionScore)%，请回到任务图查清阻塞，必要时回滚或拆解新目标。"
        }

        return """
        \("闭环演练复盘摘要：".L())\(closureDrillDisplayGoal(trace.goal))
        \("产品：".L())\(productLabel)
        \("闭环状态：".L())\(trace.status.title)
        \("完成度：".L())\(trace.completionScore)%
        \("更新时间：".L())\(trace.updatedAt.opcDateTimeText)

        \("关键计数：".L())
        \("- 任务：".L())\(trace.taskIDs.count)\("（未完成 ".L())\(openTasks)）
        \("- 协作消息：".L())\(trace.messageIDs.count)
        \("- 审批：".L())\(approvals.count)\("（待批 ".L())\(pendingApprovals)\(" · 已处理 ".L())\(resolvedApprovals)）
        \("- 审查门禁：".L())\(gates.count)\("（告警/失败 ".L())\(blockingGates)）
        \("- 产物：".L())\(trace.artifactIDs.count)
        \("- 验收：".L())\(verifications.count)\("（未通过 ".L())\(blockingVerifications)）

        \("下一步：".L())
        \(nextStep)

        \("说明：本摘要仅写给技术负责人和运维后台复盘，不进入老板首页；明细请打开「查看闭环详情」或「打开决策中心」。".L())
        """
    }

    public func selectedProductReworkSummaryText() -> String {
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let reworkItems = selectedProductReworkQueue.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        guard !reworkItems.isEmpty else {
            return """
            \("返工追踪：暂无返工队列".L())
            \("产品：".L())\(productLabel)

            \("当前产品没有审查打回后重新派发的执行任务。".L())
            """
        }

        let lines = reworkItems.prefix(8).map { item in
            let taskTitle = tasks.first { $0.id == item.taskID }?.title ?? "未知任务"
            let reason = reworkReason(from: item.promptPreview) ?? "未记录原因"
            return "- \(taskTitle)：\(item.status.title)，执行员工 \(agentName(item.agentID))，原因：\(reason)"
        }

        return """
        \("返工追踪：".L())\(reworkItems.count)\(" 项".L())
        \("产品：".L())\(productLabel)

        \(lines.joined(separator: "\n"))

        \("下一步：".L())
        \("让对应执行员工在「员工工作台」处理返工队列；技术负责人只跟踪原因和状态，不直接启动模型任务。".L())
        """
    }

    public func closureTraceAuditText(_ trace: MultiAgentClosureTrace) -> String {
        let taskRecords = closureTraceTasks(trace)
        let taskTitlesByID = Dictionary(uniqueKeysWithValues: taskRecords.map { ($0.id, $0.title) })
        let taskGraph = closureTraceTaskGraph(trace)
        let tasks = taskRecords.map { task in
            "- " + "\(task.title)" + "：".L() + "\(task.status.title)" + "，负责人 " + "\(task.ownerID.map(agentName) ?? "未分配")" + "。" + "\(task.successCriteria)"
        }
        let taskEdges = taskGraph.edges.map { edge in
            "- \(taskTitlesByID[edge.fromTaskID] ?? "未知任务".L()) → \(taskTitlesByID[edge.toTaskID] ?? "未知任务".L())：".L() + "\(edge.relation)，\(edge.status.title)。\(edge.evidence)"
        }
        let messages = closureTraceMessages(trace).map { message in
            "- \(AgentMessageDisplay.title(for: message.kind))：".L() + "\(message.subject)（\(agentName(message.fromAgentID)) → \(message.toAgentID.map(agentName) ?? "全员".L())，\(AgentMessageDisplay.statusTitle(for: message.status))）"
        }
        let approvals = closureTraceApprovals(trace).map { approval in
            "- \(approval.title)：\(approval.status.title)。\(approval.reason)"
        }
        let gates = closureTraceReviewGates(trace).map { gate in
            "- \(taskTitlesByID[gate.taskID] ?? "未知任务".L())：".L() + "\(gate.status.title)。\(gate.summary)"
        }
        let artifactsList = closureTraceArtifacts(trace).map { artifact in
            "- \(artifact.title)：\(artifact.kind.title)，\(artifact.path)。\(artifact.summary)"
        }
        let verificationsList = closureTraceVerifications(trace).map { verification in
            "- \(verification.title)：\(verification.status.title)。\(verification.detail)"
        }

        return """
        \("闭环审计报告：".L())\(trace.goal)
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("闭环状态：".L())\(trace.status.title)
        \("完成度：".L())\(trace.completionScore)%
        \("更新时间：".L())\(trace.updatedAt.opcDateTimeText)

        \("任务记录：".L())
        \(tasks.joined(separator: "\n"))

        \("任务图边：".L())
        \(taskEdges.joined(separator: "\n"))

        \("消息记录：".L())
        \(messages.joined(separator: "\n"))

        \("审批记录：".L())
        \(approvals.joined(separator: "\n"))

        \("验收门禁：".L())
        \(gates.joined(separator: "\n"))

        \("产物记录：".L())
        \(artifactsList.joined(separator: "\n"))

        \("验收记录：".L())
        \(verificationsList.joined(separator: "\n"))
        """
    }

    public func closureTraceAuditReportExists(for trace: MultiAgentClosureTrace) -> Bool {
        let path = closureTraceAuditReportPath(for: trace)
        let title = closureTraceAuditReportTitle(for: trace)
        return artifacts.contains { artifact in
            artifact.productID == trace.productID
                && artifact.kind == .report
                && (artifact.path == path || artifact.title == title)
        }
    }

    @discardableResult
    public func generateClosureTraceAuditReport(for trace: MultiAgentClosureTrace) -> Bool {
        guard selectedProductClosureTraces.contains(where: { $0.id == trace.id }) else { return false }
        let path = closureTraceAuditReportPath(for: trace)
        if closureTraceAuditReportExists(for: trace) {
            appendEvent(kind: .statusChanged, title: "闭环审计报告已存在", detail: "未重复创建：\(trace.goal)", agentID: ctoID)
            saveSnapshot()
            return true
        }

        let report = closureTraceAuditText(trace)
        let artifact = ArtifactRecord(
            productID: trace.productID,
            kind: .report,
            title: closureTraceAuditReportTitle(for: trace),
            path: path,
            summary: "多员工闭环 \(trace.completionScore)%：任务 \(trace.taskIDs.count)，消息 \(trace.messageIDs.count)，产物 \(trace.artifactIDs.count)，验收 \(trace.verificationIDs.count)。"
        )
        artifacts.insert(artifact, at: 0)
        messages.append(ChatMessage(productID: trace.productID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .artifactCreated, title: "闭环审计报告已生成", detail: artifact.title, agentID: ctoID)
        saveSnapshot()
        return true
    }

    private func closureTraceAuditReportPath(for trace: MultiAgentClosureTrace) -> String {
        "opc://closure-traces/\(trace.id)"
    }

    private func closureTraceAuditReportTitle(for trace: MultiAgentClosureTrace) -> String {
        "闭环审计报告：\(trace.goal)"
    }

    public var selectedProductAgentMessages: [AgentMessageEnvelope] {
        agentMessages.filter { $0.productID == selectedProductID }
    }

    public var selectedProductRecentAgentMessages: [AgentMessageEnvelope] {
        selectedProductAgentMessages.filter { !isClosureDrillAgentMessage($0) }.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var selectedProductPendingAgentMessages: [AgentMessageEnvelope] {
        selectedProductAgentMessages.filter { $0.status == .pending && !isClosureDrillAgentMessage($0) }
    }

    public var selectedAgentProductMessages: [AgentMessageEnvelope] {
        let agentID = selectedAgentID
        return agentMessages.filter { envelope in
            envelope.productID == selectedProductID
                && (envelope.fromAgentID == agentID || envelope.toAgentID == agentID)
                && !isClosureDrillAgentMessage(envelope)
        }
    }

    public var selectedAgentRecentProductMessages: [AgentMessageEnvelope] {
        selectedAgentProductMessages.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var selectedAgentPendingMessages: [AgentMessageEnvelope] {
        let agentID = selectedAgentID
        return selectedAgentProductMessages.filter { envelope in
            envelope.status == .pending && envelope.toAgentID == agentID
        }
    }

    public func selectedProductAgentMessages(filter: AgentMessageFilter) -> [AgentMessageEnvelope] {
        selectedProductRecentAgentMessages.filter { filter.matches($0) }
    }

    public func selectedAgentProductMessages(filter: AgentMessageFilter) -> [AgentMessageEnvelope] {
        selectedAgentRecentProductMessages.filter { filter.matches($0) }
    }

    @discardableResult
    public func acknowledgeSelectedAgentMessage(_ messageID: UUID) -> Bool {
        let agentID = selectedAgentID
        let productID = selectedProductID
        guard let index = agentMessages.firstIndex(where: { $0.id == messageID }) else { return false }
        guard agentMessages[index].productID == productID,
              agentMessages[index].toAgentID == agentID,
              agentMessages[index].status == .pending
        else { return false }
        agentMessages[index].status = .acknowledged
        agentMessages[index].acknowledgedAt = Date()
        appendEvent(
            kind: .statusChanged,
            title: "员工协作收件箱已确认一条",
            detail: "\(agentName(agentID)) 已确认「\(agentMessages[index].subject)」。",
            agentID: agentID
        )
        saveSnapshot()
        return true
    }

    @discardableResult
    public func acknowledgeSelectedAgentMessages() -> Int {
        let agentID = selectedAgentID
        let productID = selectedProductID
        var count = 0
        let now = Date()
        for index in agentMessages.indices
            where agentMessages[index].productID == productID
            && agentMessages[index].toAgentID == agentID
            && agentMessages[index].status == .pending {
            agentMessages[index].status = .acknowledged
            agentMessages[index].acknowledgedAt = now
            count += 1
        }
        if count > 0 {
            appendEvent(
                kind: .statusChanged,
                title: "员工协作收件箱已标记已读",
                detail: "\(agentName(agentID)) 的 \(count) 条收到员工消息已标记已读。",
                agentID: agentID
            )
            saveSnapshot()
        }
        return count
    }

    @discardableResult
    public func acknowledgeSelectedProductAgentMessages() -> Int {
        var count = 0
        let now = Date()
        for index in agentMessages.indices
            where agentMessages[index].productID == selectedProductID
            && agentMessages[index].status == .pending {
            agentMessages[index].status = .acknowledged
            agentMessages[index].acknowledgedAt = now
            count += 1
        }
        if count > 0 {
            appendEvent(
                kind: .statusChanged,
                title: "员工协作消息已标记已读",
                detail: "\(selectedProduct?.name ?? "当前产品") 的 \(count) 条员工消息已标记为已读。",
                agentID: ctoID
            )
            saveSnapshot()
        }
        return count
    }

    public var selectedProductAgents: [CompanyAgent] {
        productAgents(for: selectedProductID)
    }

    private func productAgents(for productID: UUID) -> [CompanyAgent] {
        guard let product = products.first(where: { $0.id == productID }) else {
            return agents.filter { $0.role != .boss }
        }
        return agents.filter { agent in
            agent.role != .boss && product.assignedAgentIDs.contains(agent.id)
        }
    }

    public var selectedProductAvailableAgents: [CompanyAgent] {
        guard let product = selectedProduct else { return [] }
        return agents.filter { agent in
            agent.role != .boss && !product.assignedAgentIDs.contains(agent.id)
        }
    }

    public var executableAgents: [CompanyAgent] {
        selectedProductAgents.filter { agent in
            agent.role != .boss
                && agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines) != "human"
        }
    }

    public func isAgentAssignedToSelectedProduct(_ agentID: UUID) -> Bool {
        selectedProductAgents.contains { $0.id == agentID }
    }

    public var isRunningAgent: Bool {
        !runningAgentIDs.isEmpty
    }

    public func messages(for agentID: UUID) -> [ChatMessage] {
        messages.filter { $0.agentID == agentID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func messages(for agentID: UUID, in productID: UUID, includingLegacyGlobal: Bool = true) -> [ChatMessage] {
        messages
            .filter { message in
                message.agentID == agentID
                    && (message.productID == productID || (includingLegacyGlobal && message.productID == nil))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func selectAgent(_ id: UUID) {
        selectedAgentID = id
        appendEvent(kind: .message, title: "选中员工", detail: "老板选中了 \(agentName(id))。", agentID: id)
        if agents.first(where: { $0.id == id })?.role == .boss {
            mainWorkspace = .commandCenter
        } else {
            mainWorkspace = .agentDesk
        }
    }

    public func focusAgent(_ id: UUID) {
        selectedAgentID = id
        appendEvent(kind: .message, title: "观察员工状态", detail: "老板正在查看 \(agentName(id)) 的动画状态。", agentID: id)
    }

    private func ensureSelectedAgentIsValidForSelectedProduct() {
        guard let selected = selectedAgent else {
            selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
            return
        }

        if selected.role == .boss { return }
        if selectedProductAgents.contains(where: { $0.id == selected.id }) { return }

        selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
    }

    private func repairSelectionState() {
        if !products.contains(where: { $0.id == selectedProductID }), let firstProductID = products.first?.id {
            selectedProductID = firstProductID
        }
        if !agents.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
        }
        ensureSelectedAgentIsValidForSelectedProduct()
    }

    @discardableResult
    private func migrateLegacyDesktopDefaultProductRoots() -> Bool {
        var migratedNames: [String] = []
        for index in products.indices {
            guard let migratedRoot = Self.migratedRootForLegacyDesktopDefaultProduct(
                rootDirectory: products[index].rootDirectory,
                productName: products[index].name,
                importReport: products[index].importReport
            ) else {
                continue
            }
            products[index].rootDirectory = migratedRoot
            products[index].updatedAt = Date()
            migratedNames.append(products[index].name)
        }
        guard !migratedNames.isEmpty else { return false }
        appendEvent(
            kind: .statusChanged,
            title: "默认产品目录已迁移",
            detail: "已把旧版默认 Desktop 工作区迁移到 OPC 本地应用工作区：\(migratedNames.joined(separator: "、"))。",
            agentID: ctoID
        )
        syncAllAgentWorkspaces()
        return true
    }

    public func selectProduct(_ id: UUID) {
        guard let product = products.first(where: { $0.id == id }) else { return }
        selectedProductID = id
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        appendEvent(kind: .statusChanged, title: "切换产品", detail: "当前产品已切换为 \(product.name)，已重新开启技术负责人和产品员工团队。", agentID: nil)
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    public func deleteProduct(_ id: UUID) {
        guard products.count > 1, let index = products.firstIndex(where: { $0.id == id }) else { return }
        let product = products[index]
        createSafetyCheckpoint(reason: "删除产品前自动检查点：\(product.name)")
        products.remove(at: index)
        tasks.removeAll { $0.productID == id }
        workQueue.removeAll { $0.productID == id }
        branchPlans.removeAll { $0.productID == id }
        reviewGates.removeAll { $0.productID == id }
        approvals.removeAll { $0.productID == id }
        artifacts.removeAll { $0.productID == id }
        verifications.removeAll { $0.productID == id }
        memories.removeAll { $0.productID == id }
        communicationChannels.removeAll { $0.productID == id }
        communicationLogs.removeAll { $0.productID == id }
        agentMessages.removeAll { $0.productID == id }
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != id }
        let deletedProductPrefix = id.uuidString.lowercased() + ":"
        productTerminalLogs = productTerminalLogs.filter { !$0.key.hasPrefix(deletedProductPrefix) }
        if selectedProductID == id {
            selectedProductID = products[max(0, min(index, products.count - 1))].id
        }
        ensureSelectedAgentIsValidForSelectedProduct()
        appendEvent(kind: .statusChanged, title: "产品已删除", detail: "\(product.name) 及其任务/队列/审批/产物/记忆已删除。", agentID: nil)
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    public func addProductWorkspace() {
        let index = products.count + 1
        let productID = UUID()
        let product = ProductWorkspace(
            id: productID,
            name: "新产品 \(index)",
            shortName: "P\(index)",
            rootDirectory: Self.internalProductRootDirectory(for: productID),
            status: .active,
            stage: .discovery,
            assignedAgentIDs: [ctoID],
            teamLeadAgentID: ctoID
        )
        products.append(product)
        selectedProductID = product.id
        appendEvent(kind: .statusChanged, title: "新增产品工作区", detail: "\(product.name) 已创建，根目录：\(product.rootDirectory)。", agentID: nil)
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    @discardableResult
    public func updateProductSettings(productID: UUID, name: String, shortName: String, rootDirectory: String) -> Bool {
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return false }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        let cleanShortName = Self.normalizedProductShortName(name: cleanName, proposed: shortName)
        let cleanRoot = rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRoot.isEmpty else { return false }
        let expandedRoot = NSString(string: cleanRoot).expandingTildeInPath
        let normalizedRoot = URL(fileURLWithPath: expandedRoot, isDirectory: true).standardizedFileURL.path

        let oldProduct = products[index]
        let changed = oldProduct.name != cleanName
            || oldProduct.shortName != cleanShortName
            || URL(fileURLWithPath: NSString(string: oldProduct.rootDirectory).expandingTildeInPath, isDirectory: true).standardizedFileURL.path != normalizedRoot
        guard changed else { return false }

        products[index].name = cleanName
        products[index].shortName = cleanShortName
        products[index].rootDirectory = normalizedRoot
        products[index].updatedAt = Date()
        if normalizedRoot.hasPrefix(CompanyPersistence.productWorkspacesURL.standardizedFileURL.path + "/") {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: normalizedRoot, isDirectory: true), withIntermediateDirectories: true)
        }
        cachedTerminalWorkspaceHealthSnapshot = nil
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != productID }
        for agentID in products[index].assignedAgentIDs {
            syncAgentWorkspace(for: agentID)
        }
        appendEvent(kind: .statusChanged, title: "产品设置已更新", detail: "\(oldProduct.name) 已更新为 \(cleanName)，产品工作区配置已保存。", agentID: products[index].teamLeadAgentID)
        saveSnapshot()
        return true
    }

    @discardableResult
    public func updateSelectedProductSettings(name: String, shortName: String, rootDirectory: String) -> Bool {
        updateProductSettings(productID: selectedProductID, name: name, shortName: shortName, rootDirectory: rootDirectory)
    }

    public func updateSelectedProductTeamLead(_ agentID: UUID) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }),
              products[index].assignedAgentIDs.contains(agentID),
              agents.contains(where: { $0.id == agentID && $0.role != .boss })
        else { return }
        products[index].teamLeadAgentID = agentID
        products[index].updatedAt = Date()
        for channelIndex in communicationChannels.indices where communicationChannels[channelIndex].productID == selectedProductID {
            communicationChannels[channelIndex].teamLeadAgentID = agentID
            communicationChannels[channelIndex].updatedAt = Date()
        }
        appendEvent(kind: .statusChanged, title: "产品负责人已更新", detail: "\(products[index].name) 的团队负责人设为 \(agentName(agentID))。", agentID: agentID)
        saveSnapshot()
    }

    public func assignAgentToSelectedProduct(_ agentID: UUID) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }),
              agents.contains(where: { $0.id == agentID && $0.role != .boss })
        else { return }
        let inserted = products[index].assignedAgentIDs.insert(agentID).inserted
        products[index].updatedAt = Date()
        if products[index].teamLeadAgentID == nil {
            products[index].teamLeadAgentID = agentID
        }
        if inserted {
            appendEvent(kind: .statusChanged, title: "产品成员已加入", detail: "\(agentName(agentID)) 已加入 \(products[index].name)。", agentID: agentID)
            if runtimeSupervisorStarted {
                prewarmAgentSession(agentID: agentID, reason: "新员工加入当前产品团队")
            }
        }
        saveSnapshot()
    }

    public func removeAgentFromSelectedProduct(_ agentID: UUID) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }),
              products[index].assignedAgentIDs.count > 1,
              products[index].assignedAgentIDs.contains(agentID)
        else { return }
        products[index].assignedAgentIDs.remove(agentID)
        if products[index].teamLeadAgentID == agentID {
            products[index].teamLeadAgentID = products[index].assignedAgentIDs.contains(ctoID) ? ctoID : products[index].assignedAgentIDs.first
        }
        for channelIndex in communicationChannels.indices where communicationChannels[channelIndex].productID == selectedProductID && communicationChannels[channelIndex].teamLeadAgentID == agentID {
            communicationChannels[channelIndex].teamLeadAgentID = products[index].teamLeadAgentID
            communicationChannels[channelIndex].updatedAt = Date()
        }
        products[index].updatedAt = Date()
        appendEvent(kind: .statusChanged, title: "产品成员已移除", detail: "\(agentName(agentID)) 已从 \(products[index].name) 移除。", agentID: agentID)
        ensureSelectedAgentIsValidForSelectedProduct()
        saveSnapshot()
    }

    public func applyTeamTemplateToSelectedProduct(_ template: ProductTeamTemplate) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }) else { return }
        let roleSet = Set(template.roles)
        let assigned = Set(agents.filter { agent in
            agent.role != .boss && roleSet.contains(agent.role)
        }.map(\.id))
        guard !assigned.isEmpty else { return }

        products[index].assignedAgentIDs = assigned
        if let lead = agents.first(where: { assigned.contains($0.id) && $0.role == template.leadRole }) {
            products[index].teamLeadAgentID = lead.id
        } else {
            products[index].teamLeadAgentID = assigned.first
        }
        products[index].updatedAt = Date()

        let missing = missingRoles(for: template).map(\.title)
        let detail = missing.isEmpty
            ? "已应用 \(template.title)，当前团队成员：\(assigned.count) 人。"
            : "已应用 \(template.title)，当前团队成员：\(assigned.count) 人。缺少：\(missing.joined(separator: "、"))。"
        appendEvent(kind: .statusChanged, title: "产品团队模板已应用", detail: detail, agentID: products[index].teamLeadAgentID)
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        saveSnapshot()
    }

    public func missingRoles(for template: ProductTeamTemplate) -> [AgentRole] {
        template.roles.filter { role in
            !agents.contains { $0.role == role }
        }
    }

    public func importProductWorkspace(from rootURL: URL) {
        let report = ProjectImportScanner.scan(rootURL: rootURL)
        let assignedAgents: Set<UUID> = [ctoID]

        if let index = products.firstIndex(where: { $0.rootDirectory == rootURL.path }) {
            products[index].name = report.projectName
            products[index].shortName = report.shortName
            products[index].stage = .implementation
            products[index].status = .active
            products[index].assignedAgentIDs = assignedAgents
            products[index].importReport = report
            products[index].updatedAt = Date()
            selectedProductID = products[index].id
        } else {
            let product = ProductWorkspace(
                name: report.projectName,
                shortName: report.shortName,
                rootDirectory: rootURL.path,
                status: .active,
                stage: .implementation,
                assignedAgentIDs: assignedAgents,
                teamLeadAgentID: ctoID,
                importReport: report
            )
            products.append(product)
            selectedProductID = product.id
        }

        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        mainWorkspace = .productDetail
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: """
        \("已导入现有项目：".L())\(report.projectName)
        \("根目录：".L())\(report.rootDirectory)
        \("检测到的智能工具：".L())\(report.detectedTools.isEmpty ? "未发现" : report.detectedTools.joined(separator: "、"))
        \("规则/记忆文件：".L())\(report.ruleFiles.isEmpty ? "未发现" : report.ruleFiles.joined(separator: "、"))
        \("项目文件：".L())\(report.projectFiles.isEmpty ? "未发现" : report.projectFiles.joined(separator: "、"))

        \("接手要求：先读取上述规则和记忆，再盘点项目结构，不要覆盖现有 Codex / Claude Code 规则。".L())
        """))
        tasks.append(CompanyTask(productID: selectedProductID, title: "接手现有项目盘点", ownerID: ctoID, status: .running, successCriteria: "读取项目规则、记忆、技术栈和最近状态，生成继续开发计划。", artifactPath: report.rootDirectory))
        appendEvent(kind: .statusChanged, title: "导入现有项目", detail: report.summary, agentID: ctoID)
        saveSnapshot()
    }

    public func restartAgentTeamForSelectedProduct() {
        guard let product = selectedProduct else { return }
        for index in agents.indices {
            guard agents[index].role != .boss, product.assignedAgentIDs.contains(agents[index].id) else { continue }
            agents[index].status = agents[index].role == .cto ? .thinking : .idle
            syncAgentWorkspace(for: agents[index].id)
        }
        messages.append(ChatMessage(productID: product.id, agentID: ctoID, author: .system, text: "产品工作区已切换为 \(product.name)。技术负责人和该产品员工团队已重新开启，请按该产品上下文工作。"))
        appendEvent(kind: .statusChanged, title: "产品团队已重新开启", detail: "\(product.name)：技术负责人和所有分配员工已进入当前产品上下文。", agentID: ctoID)
        ensureRuntimeSessionsForSelectedProduct()
        if runtimeSupervisorStarted {
            prewarmSelectedProductAgentSessions(reason: "产品切换后重开当前团队会话")
        }
    }

    public func sendMessage(to agentID: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        _ = cleanLegacySyntheticAgentReplies(saveAfterChange: false)
        let productID = selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: agentID, author: .user, text: clean))
        appendAgentSession(agentID: agentID, kind: .message, actor: "boss", text: clean)
        appendEvent(kind: .message, title: "老板发给 \(agentName(agentID)) 的消息", detail: clean, agentID: agentID)
        setStatus(.thinking, for: agentID)

        if liveChatEnabled, let agent = agents.first(where: { $0.id == agentID }), canUseLiveChatBackend(agent) {
            startLiveChatReply(agent: agent, userText: clean)
        } else {
            let reply = localFallbackReply(for: agentID)
            messages.append(ChatMessage(productID: productID, agentID: agentID, author: .system, text: reply))
            appendAgentSession(agentID: agentID, kind: .reply, actor: "system", text: reply)
            setStatus(agentID == ctoID ? .thinking : .done, for: agentID)
            if agentID != ctoID {
                let summary = "老板直接和 \(agentName(agentID)) 沟通：\(clean)。当前未调用真实模型，等待人工运行或配置模型来源。"
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步", detail: summary, agentID: ctoID)
            }
            saveSnapshot()
        }
    }

    public func addEmployee(from draft: EmployeeDraft) {
        let count = agents.filter { $0.role != .boss && $0.role != .cto }.count
        let seat = employeeHallSeat(for: count)
        let agent = CompanyAgent(
            displayName: draft.displayName.isEmpty ? "新员工" : draft.displayName,
            title: draft.title.isEmpty ? draft.role.title : draft.title,
            role: draft.role,
            backend: AgentBackend(type: draft.backendType, command: draft.command, model: draft.model, endpoint: draft.endpoint, apiKey: draft.apiKey, reasoningEffort: draft.reasoningEffort),
            ethnicity: draft.ethnicity,
            gender: draft.gender,
            clothing: draft.clothing,
            status: .idle,
            permissions: draft.permissions,
            seat: seat
        )
        agents.append(agent)
        if let productIndex = products.firstIndex(where: { $0.id == selectedProductID }) {
            products[productIndex].assignedAgentIDs.insert(agent.id)
            products[productIndex].updatedAt = Date()
        }
        agentProfiles[agent.id] = AgentOperatingProfile.defaultProfile(for: agent)
        selectedAgentID = agent.id
        appendEvent(kind: .statusChanged, title: "新增员工", detail: "\(agent.displayName) 已加入，职位：\(agent.title)。", agentID: agent.id)
            messages.append(ChatMessage(productID: selectedProductID, agentID: agent.id, author: .system, text: "系统提示：\(agent.displayName) 已创建。正式沟通会调用该员工配置的真实模型来源。"))
        syncAgentWorkspace(for: agent.id)
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "员工创建完成，已生成本地工作区。")
        draftEmployee = EmployeeDraft()
        isAddingEmployee = false
        saveSnapshot()
    }

    public func createEmployee(fromRolePack packID: String) {
        guard let pack = AgentRolePackCatalog.pack(id: packID) else { return }
        guard pack.role != .cto else {
            appendEvent(kind: .risk, title: "已阻止重复技术负责人", detail: "技术负责人总控编排包只能应用到现有 Codex 技术负责人，不能创建第二个技术负责人。", agentID: ctoID)
            saveSnapshot()
            return
        }
        let count = agents.filter { $0.role != .boss && $0.role != .cto }.count
        let agent = CompanyAgent(
            displayName: suggestedAgentName(for: pack),
            title: pack.title,
            role: pack.role,
            backend: pack.recommendedBackend,
            ethnicity: .chinese,
            gender: .woman,
            clothing: pack.role == .uiDesigner ? .designerBlack : .smartCasual,
            status: .idle,
            permissions: pack.recommendedPermissions,
            reportsToCTO: pack.role != .cto,
            seat: pack.role == .cto ? OfficeSeat(x: 0.26, y: 0.75, room: "cto-office") : employeeHallSeat(for: count)
        )
        agents.append(agent)
        agentProfiles[agent.id] = pack.profile
        if let productIndex = products.firstIndex(where: { $0.id == selectedProductID }) {
            products[productIndex].assignedAgentIDs.insert(agent.id)
            if products[productIndex].teamLeadAgentID == nil || pack.role == .cto {
                products[productIndex].teamLeadAgentID = agent.id
            }
            products[productIndex].updatedAt = Date()
        }
        selectedAgentID = agent.id
        syncAgentWorkspace(for: agent.id)
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "已从角色包 \(pack.title) 创建员工。")
        appendEvent(kind: .statusChanged, title: "角色包员工已创建", detail: "\(agent.displayName) 已按 \(pack.title) 加入当前产品团队。", agentID: agent.id)
        saveSnapshot()
    }

    public func employeeHallSeat(for index: Int) -> OfficeSeat {
        let columns = 6
        let xPositions = [0.34, 0.50, 0.66, 0.22, 0.78, 0.12]
        let yPositions = [0.50, 0.34, 0.66, 0.18, 0.80]
        let column = index % columns
        let row = (index / columns) % yPositions.count
        return OfficeSeat(x: xPositions[column], y: yPositions[row], room: "employee-hall")
    }

    public func sendSystemBriefToCTO(sourceAgentID: UUID? = nil) {
        let activeTasks = tasks.map { "\($0.title)：\($0.status.title)" }.joined(separator: "\n")
        let recentEvents = events.suffix(5).map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        let brief = """
        \("公司状态简报：".L())
        \("任务：".L())
        \(activeTasks)

        \("最近事件：".L())
        \(recentEvents)
        """
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: brief))
        if let sourceAgentID, sourceAgentID != ctoID {
            let confirmation = "已生成公司状态简报并同步给技术负责人。".L()
            messages.append(ChatMessage(productID: selectedProductID, agentID: sourceAgentID, author: .system, text: confirmation))
            appendTerminalLog("\n[OPC] \(confirmation)\n", for: sourceAgentID)
        }
        appendEvent(kind: .ctoSummary, title: "技术负责人简报".L(), detail: "老板要求生成状态简报。".L(), agentID: ctoID)
        saveSnapshot()
    }

    public func createTask(title: String, ownerID: UUID?, status: TaskStatus = .planned, successCriteria: String, artifactPath: String? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCriteria = successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let task = CompanyTask(
            productID: selectedProductID,
            title: cleanTitle,
            ownerID: ownerID,
            status: status,
            successCriteria: cleanCriteria.isEmpty ? "完成后必须说明修改内容、验证命令和剩余风险。".L() : cleanCriteria,
            artifactPath: artifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
        tasks.insert(task, at: 0)
        appendEvent(kind: .taskCreated, title: "创建任务".L(), detail: "\(cleanTitle) 已加入 \(selectedProduct?.name ?? "当前产品")。", agentID: ownerID)
        if let ownerID {
            appendEvent(kind: .taskAssigned, title: "任务已分配".L(), detail: "\(cleanTitle)" + " 分配给 " + "\(agentName(ownerID))" + "。", agentID: ownerID)
        }
        saveSnapshot()
    }

    public func assignTask(_ taskID: UUID, to ownerID: UUID?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].ownerID = ownerID
        tasks[index].status = ownerID == nil ? .planned : .assigned
        appendEvent(kind: .taskAssigned, title: "任务负责人已更新".L(), detail: "\(tasks[index].title) → \(ownerID.map(agentName) ?? "未分配")。", agentID: ownerID)
        saveSnapshot()
    }

    public func updateTaskStatus(_ taskID: UUID, status: TaskStatus, note: String = "") {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        let detail = note.isEmpty ? "\(tasks[index].title)" + " 状态变更为 ".L() + "\(status.title)" + "。" : note
        appendEvent(kind: .statusChanged, title: "任务状态更新".L(), detail: detail, agentID: tasks[index].ownerID)
        saveSnapshot()
    }

    public func approveTaskRisk(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .running
        appendEvent(kind: .statusChanged, title: "老板已批准".L(), detail: "\(tasks[index].title)" + " 的风险/继续执行请求已批准。", agentID: tasks[index].ownerID)
        let productID = tasks[index].productID ?? selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "老板已批准任务继续执行：".L() + "\(tasks[index].title)" + "。请技术负责人继续调度并记录结果。"))
        saveSnapshot()
    }

    public func rejectTaskRisk(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .blocked
        appendEvent(kind: .risk, title: "老板已驳回".L(), detail: "\(tasks[index].title)" + " 已被驳回，要求技术负责人重新设计方案。", agentID: tasks[index].ownerID)
        let productID = tasks[index].productID ?? selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "老板驳回任务：".L() + "\(tasks[index].title)" + "。请重新拆解方案，不要继续原执行路径。"))
        saveSnapshot()
    }

    public func requestCTOReview(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        messages.append(ChatMessage(productID: task.productID ?? selectedProductID, agentID: ctoID, author: .system, text: "请技术负责人复核任务：".L() + "\(task.title)" + "。验收标准：".L() + "\(task.successCriteria)"))
        upsertReviewGate(
            for: task,
            status: .reviewRequested,
            requesterID: bossID,
            reviewerID: ctoID,
            summary: "老板要求技术负责人复核任务，确认是否进入审查/验收。".L()
        )
        postAgentMessage(
            productID: task.productID ?? selectedProductID,
            fromAgentID: bossID,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewRequested,
            subject: "请求技术负责人复核：".L() + "\(task.title)",
            body: "请按验收标准复核任务，确认是否进入老板验收或返工。\n验收标准：".L() + "\(task.successCriteria)",
            persist: false
        )
        appendEvent(kind: .ctoSummary, title: "已要求技术负责人复核".L(), detail: task.title, agentID: ctoID)
        saveSnapshot()
    }

    private func upsertReviewGate(
        for task: CompanyTask,
        status: ReviewGateStatus,
        requesterID: UUID? = nil,
        reviewerID: UUID? = nil,
        summary: String,
        latestVerificationID: UUID? = nil,
        reportArtifactID: UUID? = nil
    ) {
        let productID = task.productID ?? selectedProductID
        let now = Date()
        if let index = reviewGates.firstIndex(where: { $0.productID == productID && $0.taskID == task.id }) {
            reviewGates[index].status = status
            reviewGates[index].summary = summary
            reviewGates[index].requesterID = requesterID ?? reviewGates[index].requesterID
            reviewGates[index].reviewerID = reviewerID ?? reviewGates[index].reviewerID
            reviewGates[index].latestVerificationID = latestVerificationID ?? reviewGates[index].latestVerificationID
            reviewGates[index].reportArtifactID = reportArtifactID ?? reviewGates[index].reportArtifactID
            reviewGates[index].updatedAt = now
        } else {
            reviewGates.insert(
                ReviewGateRecord(
                    productID: productID,
                    taskID: task.id,
                    requesterID: requesterID,
                    reviewerID: reviewerID,
                    status: status,
                    summary: summary,
                    latestVerificationID: latestVerificationID,
                    reportArtifactID: reportArtifactID,
                    createdAt: now,
                    updatedAt: now
                ),
                at: 0
            )
        }
    }

    public func acceptTask(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .done
        let task = tasks[index]
        let productID = task.productID ?? selectedProductID
        let detail = "\(task.title)" + " 已验收完成。".L()
        let verification = VerificationRecord(
            productID: productID,
            status: .passed,
            title: "老板验收通过：".L() + "\(task.title)",
            detail: "老板已确认任务满足验收标准：".L() + "\(task.successCriteria)"
        )
        verifications.insert(verification, at: 0)
        if let artifactPath = task.artifactPath,
           !artifacts.contains(where: { $0.productID == productID && $0.taskID == task.id && $0.path == artifactPath }) {
            artifacts.insert(
                ArtifactRecord(
                    productID: productID,
                    taskID: task.id,
                    kind: artifactKind(for: URL(fileURLWithPath: artifactPath)),
                    title: "验收产物：".L() + "\(task.title)",
                    path: artifactPath,
                    summary: "老板验收通过的任务产物。".L()
                ),
                at: 0
            )
        }
        postAgentMessage(
            productID: productID,
            fromAgentID: bossID,
            toAgentID: task.ownerID ?? ctoID,
            taskID: task.id,
            kind: .acceptanceCompleted,
            subject: "老板验收通过：".L() + "\(task.title)",
            body: "任务已通过老板验收，可进入交付记录。\n验收标准：".L() + "\(task.successCriteria)",
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .accepted,
            requesterID: bossID,
            reviewerID: task.ownerID ?? ctoID,
            summary: "老板已验收通过，任务进入交付记录。".L(),
            latestVerificationID: verification.id
        )
        appendEvent(kind: .artifactCreated, title: "老板验收通过".L(), detail: detail, agentID: task.ownerID)
        saveSnapshot()
    }

    public var selectedAgentReviewQueue: [CompanyTask] {
        guard let agent = selectedAgent, agent.role != .boss else { return [] }
        let canReview = agent.role == .reviewer || agentHasSkill(agent.id, skill: "review")
        guard canReview else { return [] }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else { return [] }
        return selectedProductTasks
            .filter { $0.status == .needsReview && $0.ownerID == agent.id }
            .sorted { lhs, rhs in
                if lhs.title == rhs.title {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.title < rhs.title
            }
    }

    /// 员工工作台「我的待审任务」面板默认展开上限。
    /// reviewer 待审任务超过该值时只展开前 N 项 + 显示溢出 footer，
    /// 避免任务多时垂直拥挤；不引入 DisclosureGroup（仍是"内容紧凑"，不是"折叠隐藏"）。
    public static let agentDeskReviewQueueDefaultDisplayLimit: Int = 3

    public struct AgentDeskListOverflow: Equatable {
        public let hiddenCount: Int
        public let summary: String
    }

    /// 老板右侧检查器「员工执行进度」默认显示上限。
    public static let bossInspectorTeamProgressDefaultDisplayLimit: Int = 5

    /// 老板右侧检查器「近期任务结果」默认显示上限。
    public static let bossInspectorRecentTasksDefaultDisplayLimit: Int = 4

    /// 老板右侧检查器主工作区「近期汇报」默认显示上限。
    public static let bossInspectorRecentEventsDefaultDisplayLimit: Int = 5

    /// 老板右侧检查器紧凑区「近期汇报」默认显示上限。
    public static let bossInspectorCompactRecentReportsDefaultDisplayLimit: Int = 3

    public static let commandCenterPendingApprovalsDefaultDisplayLimit: Int = 3
    public static let commandCenterDecisionRiskTasksDefaultDisplayLimit: Int = 3
    public static let commandCenterRecentDeliveryRecordsDefaultDisplayLimit: Int = 3
    public static let commandCenterOpenTasksDefaultDisplayLimit: Int = 6
    public static let commandCenterRiskPanelTasksDefaultDisplayLimit: Int = 4
    public static let commandCenterRiskPanelEventsDefaultDisplayLimit: Int = 3
    public static let commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit: Int = 4
    public static let productDetailRecentDeliveryRecordsDefaultDisplayLimit: Int = 3
    public static let workflowMapMessageFlowDefaultDisplayLimit: Int = 6
    public static let workflowMapTaskStatusBoardPerStatusDefaultDisplayLimit: Int = 4
    public static let deliveryAcceptanceCenterAcceptanceTasksDisplayLimit: Int = 12
    public static let deliveryAcceptanceCenterReviewGatesDisplayLimit: Int = 12
    public static let deliveryAcceptanceCenterVerificationsDisplayLimit: Int = 12
    public static let deliveryAcceptanceCenterArtifactsDisplayLimit: Int = 20
    public static let bossReportCenterReportEventsDisplayLimit: Int = 6
    public static let bossReportCenterBossMessagesDisplayLimit: Int = 3
    public static let bossDecisionCenterRiskEventsDisplayLimit: Int = 8
    public static let bossDecisionCenterResolvedApprovalsDisplayLimit: Int = 8
    public static let communicationGatewayLogDisplayLimit: Int = 8
    public static let localMaintenanceVerificationDisplayLimit: Int = 8
    public static let localMaintenanceArtifactDisplayLimit: Int = 8

    public var bossInspectorTeamProgressAgents: [CompanyAgent] {
        Array(selectedProductAgents
            .filter { $0.role != .boss }
            .prefix(Self.bossInspectorTeamProgressDefaultDisplayLimit))
    }

    public var bossInspectorRecentTasks: [CompanyTask] {
        Array(selectedProductRecentTasks.prefix(Self.bossInspectorRecentTasksDefaultDisplayLimit))
    }

    public var bossInspectorRecentEvents: [CompanyEvent] {
        Array(selectedProductBossEvents.prefix(Self.bossInspectorRecentEventsDefaultDisplayLimit))
    }

    public var bossInspectorCompactRecentReports: [CompanyEvent] {
        Array(selectedProductBossEvents.prefix(Self.bossInspectorCompactRecentReportsDefaultDisplayLimit))
    }

    public func bossInspectorTeamProgressOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductAgents.filter { $0.role != .boss }.count
        let limit = Self.bossInspectorTeamProgressDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 位员工。这里先显示关键进度，完整团队仍在产品详情和员工工作台查看。".L()
        )
    }

    public func bossInspectorRecentTasksOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductTasks.count
        let limit = Self.bossInspectorRecentTasksDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 项任务。处理完上方任务后下一项会自动浮现。".L()
        )
    }

    public func bossInspectorRecentEventsOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductBossEvents.count
        let limit = Self.bossInspectorRecentEventsDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 条近期汇报。这里先显示最近重点，关键进展会继续浮现。".L()
        )
    }

    public func bossInspectorCompactRecentReportsOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductBossEvents.count
        let limit = Self.bossInspectorCompactRecentReportsDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 条汇报。这里保留最近重点，更多汇报会随进展继续浮现。".L()
        )
    }

    public var commandCenterPendingApprovals: [ApprovalRequest] {
        Array(selectedProductPendingApprovals.prefix(Self.commandCenterPendingApprovalsDefaultDisplayLimit))
    }

    public var commandCenterDecisionRiskTasks: [CompanyTask] {
        Array(selectedProductRiskTasks.prefix(Self.commandCenterDecisionRiskTasksDefaultDisplayLimit))
    }

    public var commandCenterRecentDeliveryVerifications: [VerificationRecord] {
        Array(selectedProductRecentDeliveryVerifications.prefix(Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit))
    }

    public var commandCenterRecentDeliveryArtifacts: [ArtifactRecord] {
        Array(selectedProductRecentDeliveryArtifacts.prefix(Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit))
    }

    public var commandCenterOpenTasks: [CompanyTask] {
        Array(selectedProductOpenTasks.prefix(Self.commandCenterOpenTasksDefaultDisplayLimit))
    }

    public var commandCenterRiskPanelTasks: [CompanyTask] {
        Array(selectedProductRiskTasks.prefix(Self.commandCenterRiskPanelTasksDefaultDisplayLimit))
    }

    public var commandCenterRiskPanelEvents: [CompanyEvent] {
        Array(selectedProductBossRiskEvents.prefix(Self.commandCenterRiskPanelEventsDefaultDisplayLimit))
    }

    public var commandCenterAcceptanceCriteriaTasks: [CompanyTask] {
        Array(selectedProductRecentTasks.prefix(Self.commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit))
    }

    public func commandCenterPendingApprovalsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductPendingApprovals.count,
            limit: Self.commandCenterPendingApprovalsDefaultDisplayLimit,
            noun: "项待处理审批".L(),
            continuation: "打开决策中心可处理完整队列。".L()
        )
    }

    public func commandCenterDecisionRiskTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRiskTasks.count,
            limit: Self.commandCenterDecisionRiskTasksDefaultDisplayLimit,
            noun: "项风险任务".L(),
            continuation: "打开决策中心可处理完整队列。".L()
        )
    }

    public func commandCenterDeliveryVerificationsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "条验收记录".L(),
            continuation: "打开交付验收中心可查看完整记录。".L()
        )
    }

    public func commandCenterDeliveryArtifactsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "项交付物".L(),
            continuation: "打开交付验收中心可查看完整记录。".L()
        )
    }

    public func commandCenterOpenTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductOpenTasks.count,
            limit: Self.commandCenterOpenTasksDefaultDisplayLimit,
            noun: "项未完成任务".L(),
            continuation: "这里先显示最近任务，完整任务看板在产品详情。".L()
        )
    }

    public func commandCenterRiskPanelTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRiskTasks.count,
            limit: Self.commandCenterRiskPanelTasksDefaultDisplayLimit,
            noun: "项风险任务".L(),
            continuation: "打开决策中心可处理完整队列。".L()
        )
    }

    public func commandCenterRiskPanelEventsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductBossRiskEvents.count,
            limit: Self.commandCenterRiskPanelEventsDefaultDisplayLimit,
            noun: "条风险汇报".L(),
            continuation: "这里先显示最近风险，关键进展会继续浮现。".L()
        )
    }

    public func commandCenterAcceptanceCriteriaTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentTasks.count,
            limit: Self.commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit,
            noun: "项验收标准".L(),
            continuation: "完整任务和标准在产品详情任务看板。".L()
        )
    }

    public var productDetailRecentDeliveryVerifications: [VerificationRecord] {
        Array(selectedProductRecentDeliveryVerifications.prefix(Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit))
    }

    public var productDetailRecentDeliveryArtifacts: [ArtifactRecord] {
        Array(selectedProductRecentDeliveryArtifacts.prefix(Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit))
    }

    public func productDetailDeliveryVerificationsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "条验收记录".L(),
            continuation: "查看全部可进入交付验收中心。".L()
        )
    }

    public func productDetailDeliveryArtifactsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "项交付物".L(),
            continuation: "查看全部可进入交付验收中心。".L()
        )
    }

    public var workflowMapRecentAgentMessages: [AgentMessageEnvelope] {
        Array(selectedProductRecentAgentMessages.prefix(Self.workflowMapMessageFlowDefaultDisplayLimit))
    }

    public func workflowMapMessageFlowOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentAgentMessages.count,
            limit: Self.workflowMapMessageFlowDefaultDisplayLimit,
            noun: "条协作消息".L(),
            continuation: "可在协作消息总览查看完整列表。".L()
        )
    }

    public func workflowMapTasks(for status: TaskStatus) -> [CompanyTask] {
        Array(selectedProductRecentTasks
            .filter { $0.status == status }
            .prefix(Self.workflowMapTaskStatusBoardPerStatusDefaultDisplayLimit))
    }

    public func workflowMapTaskStatusBoardOverflow(for status: TaskStatus) -> AgentDeskListOverflow? {
        let total = selectedProductRecentTasks.filter { $0.status == status }.count
        return listOverflow(
            total: total,
            limit: Self.workflowMapTaskStatusBoardPerStatusDefaultDisplayLimit,
            noun: "项" + "\(status.title)" + "任务".L(),
            continuation: "完整任务看板在产品详情。".L()
        )
    }

    public func deliveryAcceptanceCenterAcceptanceTasksOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductAcceptanceTasks.count,
            limit: Self.deliveryAcceptanceCenterAcceptanceTasksDisplayLimit,
            noun: "项验收任务".L()
        )
    }

    public func deliveryAcceptanceCenterReviewGatesOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductDeliveryReviewGates.count,
            limit: Self.deliveryAcceptanceCenterReviewGatesDisplayLimit,
            noun: "项审查门禁".L()
        )
    }

    public func deliveryAcceptanceCenterVerificationsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.deliveryAcceptanceCenterVerificationsDisplayLimit,
            noun: "条验收记录".L()
        )
    }

    public func deliveryAcceptanceCenterArtifactsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.deliveryAcceptanceCenterArtifactsDisplayLimit,
            noun: "项交付物".L()
        )
    }

    public var selectedProductBossReportEvents: [CompanyEvent] {
        selectedProductBossEvents.filter { event in
            event.title.contains("报告".L()) || event.title.contains("快照".L()) || event.kind == .artifactCreated
        }
    }

    public var bossReportCenterReportEvents: [CompanyEvent] {
        Array(selectedProductBossReportEvents.prefix(Self.bossReportCenterReportEventsDisplayLimit))
    }

    public var bossReportCenterBossMessages: [ChatMessage] {
        Array(selectedProductBossReportMessages.prefix(Self.bossReportCenterBossMessagesDisplayLimit))
    }

    public func bossReportCenterReportEventsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossReportEvents.count,
            limit: Self.bossReportCenterReportEventsDisplayLimit,
            noun: "条汇报事件".L()
        )
    }

    public func bossReportCenterBossMessagesOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossReportMessages.count,
            limit: Self.bossReportCenterBossMessagesDisplayLimit,
            noun: "条老板报告".L()
        )
    }

    public var bossDecisionCenterResolvedApprovals: [ApprovalRequest] {
        Array(selectedProductResolvedApprovals.prefix(Self.bossDecisionCenterResolvedApprovalsDisplayLimit))
    }

    public var bossDecisionCenterRiskEvents: [CompanyEvent] {
        Array(selectedProductBossRiskEvents.prefix(Self.bossDecisionCenterRiskEventsDisplayLimit))
    }

    public func bossDecisionCenterRiskEventsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossRiskEvents.count,
            limit: Self.bossDecisionCenterRiskEventsDisplayLimit,
            noun: "条风险事件".L()
        )
    }

    public func bossDecisionCenterResolvedApprovalsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductResolvedApprovals.count,
            limit: Self.bossDecisionCenterResolvedApprovalsDisplayLimit,
            noun: "项已处理决策".L()
        )
    }

    public var communicationGatewayVisibleLogs: [CommunicationLogEntry] {
        Array(selectedProductCommunicationLogs.prefix(Self.communicationGatewayLogDisplayLimit))
    }

    public func communicationGatewayLogsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductCommunicationLogs.count,
            limit: Self.communicationGatewayLogDisplayLimit,
            noun: "条通信日志".L()
        )
    }

    public var localMaintenanceVisibleVerifications: [VerificationRecord] {
        Array(selectedProductRecentMaintenanceVerifications.prefix(Self.localMaintenanceVerificationDisplayLimit))
    }

    public func localMaintenanceVerificationsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentMaintenanceVerifications.count,
            limit: Self.localMaintenanceVerificationDisplayLimit,
            noun: "条维护审计".L()
        )
    }

    public var localMaintenanceVisibleArtifacts: [ArtifactRecord] {
        Array(selectedProductRecentMaintenanceArtifacts.prefix(Self.localMaintenanceArtifactDisplayLimit))
    }

    public func localMaintenanceArtifactsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentMaintenanceArtifacts.count,
            limit: Self.localMaintenanceArtifactDisplayLimit,
            noun: "项维护产物".L()
        )
    }

    /// 当前产品最近一次「运行会话健康巡检」VerificationRecord。
    /// 本地维护详情里运行会话健康巡检按钮下方就地预览用，按钮点击后会写入新记录，预览随之更新。
    public func selectedProductLatestRuntimeSessionHealthAudit() -> VerificationRecord? {
        selectedProductMaintenanceVerifications.first { $0.title == "运行会话健康巡检".L() }
    }

    private func listOverflow(total: Int, limit: Int, noun: String, continuation: String) -> AgentDeskListOverflow? {
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " " + "\(noun)" + "。" + "\(continuation)"
        )
    }

    private func sheetTerminalOverflow(total: Int, limit: Int, noun: String) -> AgentDeskListOverflow? {
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " " + "\(noun)" + "未显示。当前中心先显示最近 ".L() + "\(limit)" + " 项。".L()
        )
    }

    public func agentDeskReviewQueueOverflow() -> AgentDeskListOverflow? {
        let total = selectedAgentReviewQueue.count
        let limit = Self.agentDeskReviewQueueDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 项待审任务。处理完上方任务后下一项会自动浮现。".L()
        )
    }

    /// 员工工作台「负责的任务」面板默认展开上限（与轮 2 待审队列同模式：
    /// 任务多时只展开前 N 项 + 单行 footer 提示，不引入 DisclosureGroup 折叠）。
    public static let agentDeskAssignedTasksDefaultDisplayLimit: Int = 3

    public func agentDeskAssignedTasksOverflow(forAgentID agentID: UUID?) -> AgentDeskListOverflow? {
        guard let id = agentID, agents.contains(where: { $0.id == id }) else { return nil }
        let total = selectedProductTasks.filter { $0.ownerID == id }.count
        let limit = Self.agentDeskAssignedTasksDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 项分配任务。处理或入队上方任务后下一项会自动浮现。".L()
        )
    }

    /// 员工工作台「员工工作队列」面板默认展开上限。
    public static let agentDeskWorkQueueDefaultDisplayLimit: Int = 3

    public func agentDeskWorkQueueOverflow(forAgentID agentID: UUID?) -> AgentDeskListOverflow? {
        guard let id = agentID, agents.contains(where: { $0.id == id }) else { return nil }
        let total = selectedProductWorkQueue.filter { $0.agentID == id }.count
        let limit = Self.agentDeskWorkQueueDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 项队列任务。处理完上方任务后下一项会自动浮现。".L()
        )
    }

    /// 员工工作台「我的协作收件箱」面板默认展开上限。
    /// 与轮 2/4 三面板（reviewQueue / assignedTasks / workQueue）同模式但 limit 较大（6 而非 3）：
    /// 收件箱是核心协作功能，过度收敛会损害"看到最近收到的消息"的本能；
    /// 因此 limit 维持原始 6（保留协作 UX），但溢出时也加共享 footer 提示，与三面板一致。
    public static let agentDeskInboxDefaultDisplayLimit: Int = 6

    /// 产品详情「员工协作链路」默认只展示最近 3 条；完整协作历史进入「查看全部」。
    public static let productDetailAgentCollaborationDefaultDisplayLimit: Int = 3

    public func agentDeskInboxOverflow() -> AgentDeskListOverflow? {
        let total = selectedAgentRecentProductMessages.count
        let limit = Self.agentDeskInboxDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L() + "\(hidden)" + " 条协作消息。处理或确认上方消息后下一条会自动浮现，完整收件箱可在协作消息总览查看。".L()
        )
    }

    /// 员工工作台「模型和权限」面板的紧凑 chip 数据源。
    /// 把原 6 行 ProfileMiniRow（每行 ~32pt + spacing 12pt = ~44pt × 6 = ~264pt）
    /// 收敛为 wrap chip 行（~28pt × 1-2 行 = 28-56pt），节省 ~200pt。
    /// 不影响数据语义：真实模型来源展示来源 / 命令行工具或模型 / 推理强度；
    /// 本地占位来源只展示来源 / 占位标识，避免把无意义的命令行字段暴露到默认可见 UI。
    /// 会话状态仅在 runtimeSession 存在时追加；保活只在关闭时浮出，正常开启状态不占默认空间。
    public struct AgentDeskProfileChip: Equatable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    public func agentDeskProfileChips(forAgentID agentID: UUID?) -> [AgentDeskProfileChip] {
        guard let id = agentID, let agent = agents.first(where: { $0.id == id }) else { return [] }
        let model = agent.backend.model.isEmpty ? "默认模型".L() : agent.backend.model
        var chips: [AgentDeskProfileChip]
        switch agent.backend.type {
        case .subscriptionCLI:
            chips = [
                .init(label: "来源".L(), value: agent.backend.type.title),
                .init(label: "命令行工具".L(), value: opcBackendCommandDisplayName(agent.backend.command)),
                .init(label: "模型".L(), value: model),
                .init(label: "推理强度".L(), value: agent.backend.reasoningEffort.title)
            ]
        case .api:
            chips = [
                .init(label: "来源".L(), value: agent.backend.type.title),
                .init(label: "模型".L(), value: model),
                .init(label: "推理强度".L(), value: agent.backend.reasoningEffort.title)
            ]
        case .local:
            chips = [
                .init(label: "来源".L(), value: agent.backend.type.title),
                .init(label: "占位标识".L(), value: model)
            ]
        }
        if let session = runtimeSession(for: agent.id) {
            chips.append(.init(label: "会话".L(), value: "\(session.state.title) · \(session.capability.title)"))
            if !session.keepAlive {
                chips.append(.init(label: "保活".L(), value: "关闭".L()))
            }
        }
        return chips
    }

    @discardableResult
    public func completeReviewByOwner(taskID: UUID, summary: String) -> Bool {
        guard let reviewer = selectedAgent, reviewer.role != .boss else { return false }
        guard reviewer.role == .reviewer || agentHasSkill(reviewer.id, skill: "review") else { return false }
        guard let task = tasks.first(where: { $0.id == taskID }) else { return false }
        guard (task.productID ?? selectedProductID) == selectedProductID else { return false }
        guard task.ownerID == reviewer.id else { return false }
        guard task.status == .needsReview else { return false }
        guard selectedProductAgents.contains(where: { $0.id == reviewer.id }) else { return false }

        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSummary = cleanSummary.isEmpty
            ? "\(reviewer.displayName)" + " 完成审查，任务可进入交付记录。".L()
            : cleanSummary

        updateTaskStatus(taskID, status: .done, note: "\(reviewer.displayName)" + " 已完成审查并签字通过。".L())
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: reviewer.id,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "审查通过：".L() + "\(task.title)",
            body: resolvedSummary,
            reviewOutcome: .passed,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationPassed,
            requesterID: ctoID,
            reviewerID: reviewer.id,
            summary: "审查员 ".L() + "\(reviewer.displayName)" + " 已签字通过：".L() + "\(resolvedSummary)"
        )
        appendEvent(
            kind: .ctoSummary,
            title: "审查员已完成审查".L(),
            detail: "\(reviewer.displayName)" + " 通过 ".L() + "\(task.title)" + "：" + "\(resolvedSummary)",
            agentID: reviewer.id
        )
        requestBossApprovalAfterSupervisorReviewPass(reviewTask: task, summary: resolvedSummary)
        saveSnapshot()
        return true
    }

    @discardableResult
    public func rejectReviewByOwner(taskID: UUID, reason: String) -> Bool {
        guard let reviewer = selectedAgent, reviewer.role != .boss else { return false }
        guard reviewer.role == .reviewer || agentHasSkill(reviewer.id, skill: "review") else { return false }
        guard let task = tasks.first(where: { $0.id == taskID }) else { return false }
        guard (task.productID ?? selectedProductID) == selectedProductID else { return false }
        guard task.ownerID == reviewer.id else { return false }
        guard task.status == .needsReview else { return false }
        guard selectedProductAgents.contains(where: { $0.id == reviewer.id }) else { return false }

        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReason = cleanReason.isEmpty
            ? "审查员 ".L() + "\(reviewer.displayName)" + " 打回返工，需补充材料或修复问题。".L()
            : cleanReason

        updateTaskStatus(taskID, status: .assigned, note: "\(reviewer.displayName)" + " 打回返工：".L() + "\(resolvedReason)")
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: reviewer.id,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "审查不通过：".L() + "\(task.title)",
            body: resolvedReason,
            reviewOutcome: .rejected,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationWarning,
            requesterID: ctoID,
            reviewerID: reviewer.id,
            summary: "审查员 ".L() + "\(reviewer.displayName)" + " 打回返工：".L() + "\(resolvedReason)"
        )
        appendEvent(
            kind: .risk,
            title: "审查员打回返工".L(),
            detail: "\(reviewer.displayName)" + " 打回 ".L() + "\(task.title)" + "：" + "\(resolvedReason)",
            agentID: reviewer.id
        )
        requeueExecutionTaskAfterReviewRejection(reviewTask: task, reason: resolvedReason)
        saveSnapshot()
        return true
    }

    private func requeueExecutionTaskAfterReviewRejection(reviewTask: CompanyTask, reason: String) {
        guard reviewTask.title.hasPrefix("审查验收：".L()),
              let goal = ctoSupervisorGoalKey(for: reviewTask),
              let executionTask = selectedProductTasks.first(where: {
                  $0.title == "员工执行：".L() + "\(goal)" && $0.productID == selectedProductID
              }),
              let executionOwnerID = executionTask.ownerID,
              selectedProductAgents.contains(where: { $0.id == executionOwnerID })
        else { return }

        updateTaskStatus(
            executionTask.id,
            status: .assigned,
            note: "审查打回返工：".L() + "\(reason)" + "。任务已重新进入 ".L() + "\(agentName(executionOwnerID))" + " 的执行队列。".L()
        )
        let promptReason = Self.promptFragment(reason, limit: Self.reworkPromptReasonLimit)
        let promptSuccessCriteria = Self.promptFragment(executionTask.successCriteria, limit: Self.reworkPromptSuccessCriteriaLimit)
        let prompt = """
        \("审查员已打回返工，请修复后重新提交审查。".L())
        \("目标：".L())\(goal)
        \("任务：".L())\(executionTask.title)
        \("打回原因：".L())\(promptReason)
        \("成功标准：".L())\(promptSuccessCriteria)
        """
        enqueueWorkItem(taskID: executionTask.id, agentID: executionOwnerID, prompt: prompt)
    }

    private func reworkReason(from promptPreview: String) -> String? {
        guard let range = promptPreview.range(of: "打回原因：") else { return nil }
        let tail = promptPreview[range.upperBound...]
        let reason = tail
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return reason.isEmpty ? nil : reason
    }

    private func requestReviewAfterReworkCompletion(executionTask: CompanyTask, agentID: UUID, workItemID: UUID?, reason: String) {
        guard executionTask.title.hasPrefix("员工执行："),
              let goal = ctoSupervisorGoalKey(for: executionTask),
              let reviewerTask = selectedProductTasks.first(where: {
                  $0.title == "审查验收：\(goal)" && $0.productID == selectedProductID
              }),
              let reviewerID = reviewerTask.ownerID,
              selectedProductAgents.contains(where: { $0.id == reviewerID }),
              [.planned, .assigned, .needsReview].contains(reviewerTask.status)
        else { return }

        updateTaskStatus(
            reviewerTask.id,
            status: .needsReview,
            note: "\(agentName(agentID)) 已完成返工，重新提交 \(agentName(reviewerID)) 复审。"
        )
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: ctoID,
            toAgentID: reviewerID,
            taskID: reviewerTask.id,
            workItemID: workItemID,
            kind: .reviewRequested,
            subject: "返工后复审：\(goal)",
            body: """
            \(agentName(agentID))\(" 已按审查打回意见完成返工，请重新审查。".L())
            \("目标：".L())\(goal)
            \("执行任务：".L())\(executionTask.title)
            \("打回原因：".L())\(reason)
            """,
            persist: false
        )
        upsertReviewGate(
            for: reviewerTask,
            status: .reviewRequested,
            requesterID: ctoID,
            reviewerID: reviewerID,
            summary: "返工后重新提交复审：\(reason)"
        )
        appendEvent(
            kind: .ctoSummary,
            title: "返工已重新提交复审",
            detail: "\(agentName(agentID)) 完成 \(executionTask.title)，已提交 \(agentName(reviewerID)) 复审。",
            agentID: agentID
        )
    }

    private func requestBossApprovalAfterSupervisorReviewPass(reviewTask: CompanyTask, summary: String) {
        guard reviewTask.title.hasPrefix("审查验收："),
              let goal = ctoSupervisorGoalKey(for: reviewTask),
              let bossTask = selectedProductTasks.first(where: {
                  $0.title == "老板审批：\(goal)" && $0.productID == selectedProductID
              }),
              !approvals.contains(where: { $0.taskID == bossTask.id && $0.status == .pending })
        else { return }

        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: bossTask.id,
            kind: .ctoLoopProgressed,
            subject: "技术负责人提交老板审批：\(goal)",
            body: "审查员已签字通过，技术负责人已把结果提交老板决策中心。\n审查结论：\(summary)",
            persist: false
        )
        requestApproval(
            taskID: bossTask.id,
            title: "请老板审批：\(goal)",
            reason: "工程实现与审查均已完成，请老板做最终决策。\n审查结论：\(summary)",
            requesterID: ctoID
        )
    }

    private func finalizeSupervisorBossApprovalIfNeeded(approval: ApprovalRequest, approved: Bool) {
        guard let taskID = approval.taskID,
              let task = tasks.first(where: { $0.id == taskID }),
              task.title.hasPrefix("老板审批：")
        else { return }

        guard approved else {
            requeueSupervisorGoalAfterBossRejection(bossTask: task, approval: approval)
            return
        }

        completeSupervisorGoalTasks(for: task)
        updateTaskStatus(taskID, status: .done, note: "老板已批准最终交付，闭环已写入交付验收记录。")
        generateAcceptanceReport(for: taskID)
        acceptTask(taskID)
    }

    private func requeueSupervisorGoalAfterBossRejection(bossTask: CompanyTask, approval: ApprovalRequest) {
        guard let goal = ctoSupervisorGoalKey(for: bossTask) else { return }
        let productID = approval.productID
        let rejectionReason = approval.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "老板驳回最终交付，需要补充返工后重新提交审查。"
            : approval.reason
        let goalTasks = tasks.filter { task in
            task.productID == productID && ctoSupervisorGoalKey(for: task) == goal
        }

        if let reviewerTask = goalTasks.first(where: { $0.title.hasPrefix("审查验收：") }) {
            updateTaskStatus(
                reviewerTask.id,
                status: reviewerTask.ownerID == nil ? .planned : .assigned,
                note: "老板驳回最终交付，审查任务已退回待后续复审。"
            )
            upsertReviewGate(
                for: reviewerTask,
                status: .verificationWarning,
                requesterID: ctoID,
                reviewerID: reviewerTask.ownerID,
                summary: "老板驳回最终交付，需返工后重新复审：\(rejectionReason)"
            )
            if let reviewerID = reviewerTask.ownerID {
                postAgentMessage(
                    productID: productID,
                    fromAgentID: ctoID,
                    toAgentID: reviewerID,
                    taskID: reviewerTask.id,
                    approvalID: approval.id,
                    kind: .reviewRequested,
                    subject: "等待返工后复审：\(goal)",
                    body: "老板已驳回最终交付，等待执行员工返工后再次提交复审。\n打回原因：\(rejectionReason)",
                    persist: false
                )
            }
        }

        guard let executionTask = goalTasks.first(where: { $0.title.hasPrefix("员工执行：") }),
              let executionOwnerID = executionTask.ownerID,
              productAgents(for: productID).contains(where: { $0.id == executionOwnerID })
        else {
            appendEvent(
                productID: productID,
                kind: .risk,
                title: "老板驳回后缺少执行负责人",
                detail: "\(goal) 已被老板驳回，但没有可重新派发的执行员工。",
                agentID: ctoID
            )
            return
        }

        updateTaskStatus(
            executionTask.id,
            status: .assigned,
            note: "老板驳回最终交付：\(rejectionReason)。任务已重新进入 \(agentName(executionOwnerID)) 的返工队列。"
        )
        let promptRejectionReason = Self.promptFragment(rejectionReason, limit: Self.reworkPromptReasonLimit)
        let promptSuccessCriteria = Self.promptFragment(executionTask.successCriteria, limit: Self.reworkPromptSuccessCriteriaLimit)
        let prompt = """
        \("老板已驳回最终交付，请按意见返工后重新提交审查。".L())
        \("目标：".L())\(goal)
        \("任务：".L())\(executionTask.title)
        \("打回原因：老板驳回最终交付：".L())\(promptRejectionReason)
        \("成功标准：".L())\(promptSuccessCriteria)
        """
        enqueueWorkItemForProduct(productID: productID, taskID: executionTask.id, agentID: executionOwnerID, prompt: prompt)
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: executionOwnerID,
            taskID: executionTask.id,
            approvalID: approval.id,
            kind: .taskDispatched,
            subject: "老板驳回后返工：".L() + "\(goal)",
            body: "老板已驳回最终交付，技术负责人已把同目标执行任务重新派发给 ".L() + "\(agentName(executionOwnerID))" + "。\n原因：".L() + "\(rejectionReason)",
            persist: false
        )
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: bossTask.id,
            approvalID: approval.id,
            kind: .ctoLoopProgressed,
            subject: "技术负责人已按老板驳回回拨返工：".L() + "\(goal)",
            body: "执行任务已重新入队，审查员等待返工后复审。\n打回原因：".L() + "\(rejectionReason)",
            persist: false
        )
        appendEvent(
            productID: productID,
            kind: .risk,
            title: "老板驳回后已派发返工".L(),
            detail: "\(goal)" + " 已退回 ".L() + "\(agentName(executionOwnerID))" + " 返工，完成后会重新提交审查。".L(),
            agentID: ctoID
        )
    }

    private func completeSupervisorGoalTasks(for bossTask: CompanyTask) {
        guard let goal = ctoSupervisorGoalKey(for: bossTask) else { return }
        let productID = bossTask.productID ?? selectedProductID
        let goalTasks = tasks.filter { task in
            task.productID == productID && ctoSupervisorGoalKey(for: task) == goal
        }
        for task in goalTasks where task.status != .done && task.status != .canceled {
            updateTaskStatus(task.id, status: .done, note: "老板已批准最终交付，技术负责人闭环任务组已收束。".L())
        }
        appendEvent(
            productID: productID,
            kind: .ctoSummary,
            title: "技术负责人闭环已收束".L(),
            detail: "\(goal)" + " 的拆解、执行、审查和老板审批任务已进入完成态。".L(),
            agentID: ctoID
        )
    }

    public func updateRoleRouting(role: AgentRole, command: String? = nil, model: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        var updatedNames: [String] = []
        for index in agents.indices where agents[index].role == role {
            if let command {
                agents[index].backend.command = command
            }
            if let model {
                agents[index].backend.model = model
            }
            if let reasoningEffort {
                agents[index].backend.reasoningEffort = reasoningEffort
            }
            updatedNames.append(agents[index].displayName)
        }
        guard !updatedNames.isEmpty else { return }
        appendEvent(kind: .statusChanged, title: "模型路由已更新".L(), detail: "\(role.title)：\(updatedNames.joined(separator: "、"))。", agentID: nil)
        saveSnapshot()
    }

    public func workOrderPrompt(for task: CompanyTask) -> String {
        let product = selectedProduct
        let owner = task.ownerID.flatMap { id in agents.first { $0.id == id } }
        let report = product?.importReport
        let ruleLine = Self.promptInlineList(
            report?.ruleFiles ?? [],
            empty: "无".L(),
            itemLimit: Self.workOrderPromptRuleItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let toolLine = Self.promptInlineList(
            report?.detectedTools ?? [],
            empty: "未识别".L(),
            itemLimit: Self.workOrderPromptToolItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let projectFiles = Self.promptInlineList(
            report?.projectFiles ?? [],
            empty: "无".L(),
            itemLimit: Self.workOrderPromptProjectFileItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let taskTitle = Self.promptFragment(task.title, limit: Self.workOrderPromptTextLimit)
        let successCriteria = Self.promptFragment(task.successCriteria, limit: Self.workOrderPromptTextLimit)
        let artifactPath = Self.promptFragment(task.artifactPath ?? "未指定".L(), limit: Self.workOrderPromptPathLimit)
        let productName = Self.promptFragment(product?.name ?? "当前产品".L(), limit: Self.workOrderPromptTextLimit)
        let productRoot = Self.promptFragment(product?.rootDirectory ?? "未设置".L(), limit: Self.workOrderPromptPathLimit)

        return """
        你是 OPC 公司员工：\(owner?.displayName ?? "未分配员工".L())，职位：\(owner?.title ?? "待定".L())。
        \("当前产品：".L())\(productName)
        \("项目根目录：".L())\(productRoot)
        项目阶段：\(product?.stage.title ?? "未知".L()) / \(product?.status.title ?? "未知".L())

        \("任务：".L())\(taskTitle)
        \("当前状态：".L())\(task.status.title)
        \("验收标准：".L())\(successCriteria)
        \("产物路径：".L())\(artifactPath)

        \("已检测到的工具：".L())\(toolLine)
        \("必须优先遵守的规则/记忆文件：".L())\(ruleLine)
        \("项目文件线索：".L())\(projectFiles)

        \("执行要求：".L())
        \("1. 先读取项目规则和相关文件，不要覆盖已有 Codex / Claude Code / Gemini 记忆。".L())
        \("2. 只处理本任务范围，不做无关重构。".L())
        \("3. 完成后汇报：修改文件、执行命令、验证结果、剩余风险。".L())
        \("4. 如果需要老板批准，停止并明确说明原因。".L())
        """
    }

    public func runTaskOwner(_ taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let ownerID = task.ownerID,
              let owner = agents.first(where: { $0.id == ownerID }),
              owner.role != .boss
        else { return }

        let prompt = workOrderPrompt(for: task)
        enqueueWorkItem(taskID: taskID, agentID: ownerID, prompt: prompt)
        updateTaskStatus(taskID, status: .running, note: "\(task.title) 已发送给 \(owner.displayName) 的命令行来源。")
        runAgent(agentID: ownerID, prompt: prompt)
    }

    public func enqueueWorkItem(taskID: UUID, agentID: UUID, prompt: String? = nil) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        guard task.productID == selectedProductID else {
            appendEvent(kind: .risk, title: "已阻止跨产品任务入队", detail: "\(task.title) 不属于当前产品，不能进入当前产品队列。", agentID: agentID)
            saveSnapshot()
            return
        }
        guard productAgents(for: selectedProductID).contains(where: { $0.id == agentID }) else {
            appendEvent(kind: .risk, title: "已阻止非团队员工入队", detail: "\(agentName(agentID)) 未加入 \(selectedProduct?.name ?? "当前产品")，不能接收该产品任务。", agentID: agentID)
            saveSnapshot()
            return
        }
        enqueueWorkItemForProduct(productID: selectedProductID, taskID: taskID, agentID: agentID, prompt: prompt)
    }

    private func enqueueWorkItemForProduct(productID: UUID, taskID: UUID, agentID: UUID, prompt: String? = nil) {
        guard let task = tasks.first(where: { $0.id == taskID && $0.productID == productID }) else { return }
        guard productAgents(for: productID).contains(where: { $0.id == agentID }) else {
            let productName = products.first(where: { $0.id == productID })?.name ?? "目标产品"
            appendEvent(productID: productID, kind: .risk, title: "已阻止非团队员工入队", detail: "\(agentName(agentID)) 未加入 \(productName)，不能接收该产品任务。", agentID: agentID)
            saveSnapshot()
            return
        }
        let fullPrompt = prompt ?? workOrderPrompt(for: task)
        let workItemID: UUID
        if let index = workQueue.firstIndex(where: { $0.productID == productID && $0.taskID == taskID && $0.agentID == agentID && $0.status != .completed }) {
            workQueue[index].promptPreview = String(fullPrompt.prefix(240))
            workQueue[index].updatedAt = Date()
            workItemID = workQueue[index].id
        } else {
            let item = AgentWorkItem(productID: productID, taskID: taskID, agentID: agentID, promptPreview: String(fullPrompt.prefix(240)))
            workQueue.insert(item, at: 0)
            workItemID = item.id
        }
        appendEvent(productID: productID, kind: .taskAssigned, title: "工作队列已更新", detail: "\(task.title) 已进入 \(agentName(agentID)) 的工作队列。", agentID: agentID)
        let dispatchBody: String
        if fullPrompt.contains("打回原因：") {
            dispatchBody = "工作项已重新进入 \(agentName(agentID)) 的队列。\n\(String(fullPrompt.prefix(800)))"
        } else {
            dispatchBody = "工作项已进入 \(agentName(agentID)) 的队列。\n验收标准：\(task.successCriteria)"
        }
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: agentID,
            taskID: taskID,
            workItemID: workItemID,
            kind: .taskDispatched,
            subject: "技术负责人派发任务：\(task.title)",
            body: dispatchBody,
            persist: false
        )
        saveSnapshot()
    }

    public func runNextQueuedWorkItem() {
        guard let item = selectedProductWorkQueue.first(where: { $0.status == .queued || $0.status == .failed }) else { return }
        guard tasks.contains(where: { $0.id == item.taskID }) else { return }
        runTaskOwner(item.taskID)
    }

    public func completeWorkItem(for taskID: UUID, agentID: UUID, status: WorkItemStatus = .completed) {
        var workItemID: UUID?
        var reworkReason: String?
        let matchingIndices = workQueue.indices.filter {
            workQueue[$0].taskID == taskID && workQueue[$0].agentID == agentID
        }
        let workItemIndex = matchingIndices.first { workQueue[$0].status != .completed } ?? matchingIndices.first
        if let index = workItemIndex {
            reworkReason = self.reworkReason(from: workQueue[index].promptPreview)
            workQueue[index].status = status
            workQueue[index].updatedAt = Date()
            workItemID = workQueue[index].id
        }
        if status == .completed {
            updateTaskStatus(taskID, status: .needsReview, note: "工作项已完成，任务进入待审查。")
            if let task = tasks.first(where: { $0.id == taskID }) {
                postAgentMessage(
                    productID: task.productID ?? selectedProductID,
                    fromAgentID: agentID,
                    toAgentID: ctoID,
                    taskID: taskID,
                    workItemID: workItemID,
                    kind: .workCompleted,
                    subject: "工作项完成：\(task.title)",
                    body: "\(agentName(agentID)) 已完成 \(task.title)，请求技术负责人验收。",
                    persist: false
                )
                if let reworkReason {
                    requestReviewAfterReworkCompletion(
                        executionTask: task,
                        agentID: agentID,
                        workItemID: workItemID,
                        reason: reworkReason
                    )
                }
            }
        }
        saveSnapshot()
    }

    public func requestApproval(taskID: UUID?, title: String, reason: String, requesterID: UUID? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let resolvedReason = cleanReason.isEmpty ? "需要老板批准后继续执行。" : cleanReason
        let approval = ApprovalRequest(productID: selectedProductID, taskID: taskID, requesterID: requesterID, title: cleanTitle, reason: resolvedReason)
        approvals.insert(approval, at: 0)
        if let taskID {
            updateTaskStatus(taskID, status: .needsApproval)
        }
        appendEvent(kind: .risk, title: "审批请求已创建", detail: cleanTitle, agentID: requesterID)
        let fromAgent = requesterID ?? ctoID
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: fromAgent,
            toAgentID: bossID,
            taskID: taskID,
            approvalID: approval.id,
            kind: .approvalRequested,
            subject: "审批请求：\(cleanTitle)",
            body: resolvedReason,
            persist: false
        )
        saveSnapshot()
    }

    public func decideApproval(_ approvalID: UUID, approved: Bool) {
        guard let index = approvals.firstIndex(where: { $0.id == approvalID }) else { return }
        guard approvals[index].status == .pending else { return }
        approvals[index].status = approved ? .approved : .rejected
        approvals[index].decidedAt = Date()
        let approval = approvals[index]
        let linkedTask = approval.taskID.flatMap { taskID in tasks.first(where: { $0.id == taskID }) }
        let isSupervisorBossApproval = linkedTask?.title.hasPrefix("老板审批：") == true
        if let taskID = approval.taskID {
            let nextStatus: TaskStatus = if approved {
                .running
            } else if isSupervisorBossApproval {
                .planned
            } else {
                .blocked
            }
            updateTaskStatus(taskID, status: nextStatus)
        }
        appendEvent(kind: approved ? .statusChanged : .risk, title: approved ? "审批已批准" : "审批已驳回", detail: approval.title, agentID: approval.requesterID)
        let recipient = approval.requesterID ?? ctoID
        postAgentMessage(
            productID: approval.productID,
            fromAgentID: bossID,
            toAgentID: recipient,
            taskID: approval.taskID,
            approvalID: approval.id,
            kind: .approvalDecided,
            subject: approved ? "审批已批准：\(approval.title)" : "审批已驳回：\(approval.title)",
            body: approved ? "老板已批准，请继续执行。" : (isSupervisorBossApproval ? "老板驳回最终交付，技术负责人会回拨返工并重新组织复审。" : "老板驳回该请求，请重新拆解或调整方案。"),
            persist: false
        )
        finalizeSupervisorBossApprovalIfNeeded(approval: approval, approved: approved)
        saveSnapshot()
    }

    @discardableResult
    public func postAgentMessage(
        productID: UUID? = nil,
        fromAgentID: UUID,
        toAgentID: UUID? = nil,
        taskID: UUID? = nil,
        workItemID: UUID? = nil,
        approvalID: UUID? = nil,
        kind: AgentMessageKind,
        subject: String,
        body: String,
        reviewOutcome: AgentMessageReviewOutcome? = nil,
        persist: Bool = true
    ) -> AgentMessageEnvelope? {
        let pid = productID ?? selectedProductID
        guard agents.contains(where: { $0.id == fromAgentID }) else { return nil }
        guard agentCanParticipateInProduct(fromAgentID, productID: pid) else {
            appendEvent(
                kind: .risk,
                title: "已阻止跨团队消息发送",
                detail: "\(agentName(fromAgentID)) 不在 \(productName(pid)) 团队，不能在该产品发送员工消息。",
                agentID: fromAgentID
            )
            if persist { saveSnapshot() }
            return nil
        }
        if let toAgentID {
            guard agents.contains(where: { $0.id == toAgentID }) else { return nil }
            guard agentCanParticipateInProduct(toAgentID, productID: pid) else {
                appendEvent(
                    kind: .risk,
                    title: "已阻止跨团队消息接收",
                    detail: "\(agentName(toAgentID)) 不在 \(productName(pid)) 团队，不能接收该产品员工消息。",
                    agentID: toAgentID
                )
                if persist { saveSnapshot() }
                return nil
            }
        }
        let envelope = AgentMessageEnvelope(
            productID: pid,
            fromAgentID: fromAgentID,
            toAgentID: toAgentID,
            taskID: taskID,
            workItemID: workItemID,
            approvalID: approvalID,
            kind: kind,
            subject: Self.promptFragment(subject, limit: Self.agentMessageSubjectTextLimit),
            body: Self.promptFragment(body, limit: Self.agentMessageBodyTextLimit),
            reviewOutcome: reviewOutcome
        )
        agentMessages.insert(envelope, at: 0)
        if agentMessages.count > 500 {
            agentMessages.removeLast(agentMessages.count - 500)
        }
        if persist { saveSnapshot() }
        return envelope
    }

    public var selectedAgentHandoffRecipients: [CompanyAgent] {
        guard let agent = selectedAgent, agent.role != .boss else { return [] }
        guard let product = selectedProduct, product.assignedAgentIDs.contains(agent.id) else { return [] }
        return selectedProductAgents.filter { candidate in
            candidate.id != agent.id && candidate.role != .boss
        }
    }

    public var selectedAgentHandoffTaskCandidates: [CompanyTask] {
        guard let agent = selectedAgent, agent.role != .boss else { return [] }
        let priority: [TaskStatus] = [.running, .needsReview, .assigned, .waiting, .planned, .draft, .blocked, .needsApproval, .failed, .done, .canceled]
        return selectedProductTasks
            .filter { $0.ownerID == agent.id }
            .sorted { lhs, rhs in
                let lhsIndex = priority.firstIndex(of: lhs.status) ?? priority.count
                let rhsIndex = priority.firstIndex(of: rhs.status) ?? priority.count
                if lhsIndex == rhsIndex {
                    return lhs.title < rhs.title
                }
                return lhsIndex < rhsIndex
            }
    }

    /// 员工工作台「发起员工交接」面板默认可见状态。
    /// `.collapsed` 把 3 种"无法交接"原因（老板视角 / 员工未加入团队 / 当前产品无可接收对端）
    /// 收敛为单行紧凑提示，避免空状态撑满整张 commandPanel；`.expanded` 才渲染完整 4 输入 + 按钮表单。
    public enum AgentDeskHandoffComposerState: Equatable {
        case expanded
        case collapsed(reason: String)
    }

    public func agentDeskHandoffComposerState() -> AgentDeskHandoffComposerState {
        guard let agent = selectedAgent else {
            return .collapsed(reason: "尚未选中员工。先在团队列表选择一位员工后再发起交接。")
        }
        if agent.role == .boss {
            return .collapsed(reason: "老板不参与员工到员工的交接。请选中员工再发起交接。")
        }
        if !isAgentAssignedToSelectedProduct(agent.id) {
            return .collapsed(reason: "\(agent.displayName) 还没有加入当前产品团队，无法在该产品发起交接。先在产品详情把该员工加入团队。")
        }
        if selectedAgentHandoffRecipients.isEmpty {
            return .collapsed(reason: "当前产品里没有可接收交接的员工。先在产品详情邀请其他员工加入团队。")
        }
        return .expanded
    }

    @discardableResult
    public func postSelectedAgentHandoff(
        toAgentID: UUID,
        taskID: UUID? = nil,
        subject: String = "",
        body: String = ""
    ) -> AgentMessageEnvelope? {
        guard let sender = selectedAgent, sender.role != .boss else { return nil }
        if let taskID,
           !selectedAgentHandoffTaskCandidates.contains(where: { $0.id == taskID }) {
            appendEvent(
                kind: .risk,
                title: "已阻止非本人任务交接",
                detail: "\(agentName(sender.id)) 只能交接自己在当前产品负责的任务。",
                agentID: sender.id
            )
            saveSnapshot()
            return nil
        }
        return postEmployeeHandoff(
            productID: selectedProductID,
            fromAgentID: sender.id,
            toAgentID: toAgentID,
            taskID: taskID,
            subject: subject,
            body: body
        )
    }

    @discardableResult
    public func postEmployeeHandoff(
        productID: UUID? = nil,
        fromAgentID: UUID,
        toAgentID: UUID,
        taskID: UUID? = nil,
        subject: String,
        body: String
    ) -> AgentMessageEnvelope? {
        let pid = productID ?? selectedProductID
        guard fromAgentID != toAgentID else { return nil }
        guard let fromAgent = agents.first(where: { $0.id == fromAgentID }),
              let toAgent = agents.first(where: { $0.id == toAgentID })
        else { return nil }
        guard fromAgent.role != .boss, toAgent.role != .boss else {
            appendEvent(
                kind: .risk,
                title: "已阻止老板参与员工交接",
                detail: "员工交接消息只在非老板员工之间允许，已拒绝。",
                agentID: fromAgentID
            )
            saveSnapshot()
            return nil
        }
        guard let product = products.first(where: { $0.id == pid }) else { return nil }
        guard product.assignedAgentIDs.contains(fromAgentID),
              product.assignedAgentIDs.contains(toAgentID) else {
            appendEvent(
                kind: .risk,
                title: "已阻止跨团队员工交接",
                detail: "\(fromAgent.displayName) 或 \(toAgent.displayName) 不在 \(product.name) 团队，不能完成员工交接。",
                agentID: fromAgentID
            )
            saveSnapshot()
            return nil
        }
        if let taskID,
           let task = tasks.first(where: { $0.id == taskID }),
           let taskProductID = task.productID,
           taskProductID != pid {
            appendEvent(
                kind: .risk,
                title: "已阻止跨产品任务交接",
                detail: "\(task.title) 不属于 \(product.name)，不能挂到该产品的员工交接消息。",
                agentID: fromAgentID
            )
            saveSnapshot()
            return nil
        }
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSubject = cleanSubject.isEmpty
            ? "\(fromAgent.displayName) 向 \(toAgent.displayName) 交接"
            : cleanSubject
        let resolvedBody = cleanBody.isEmpty
            ? "\(fromAgent.displayName) 完成上一阶段产物，已交给 \(toAgent.displayName) 继续推进。"
            : cleanBody
        return postAgentMessage(
            productID: pid,
            fromAgentID: fromAgentID,
            toAgentID: toAgentID,
            taskID: taskID,
            kind: .employeeHandoff,
            subject: resolvedSubject,
            body: resolvedBody
        )
    }

    public func acknowledgeAgentMessage(_ messageID: UUID) {
        guard let index = agentMessages.firstIndex(where: { $0.id == messageID }) else { return }
        guard agentMessages[index].status != .acknowledged else { return }
        agentMessages[index].status = .acknowledged
        agentMessages[index].acknowledgedAt = Date()
        saveSnapshot()
    }

    @discardableResult
    public func startCTOSupervisorGoal(goal: String) -> UUID? {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanGoal.isEmpty else { return nil }
        let productID = selectedProductID
        let productLabel = selectedProduct?.name ?? "当前产品"

        let engineerID = firstAgentID(for: .codeEngineer) ?? recommendedAgentID(
            forTaskTitle: "员工执行：\(cleanGoal)",
            successCriteria: "完成工程实现并报告修改文件、验证命令和剩余风险。",
            fallbackRole: .codeEngineer
        )
        let reviewerID = firstAgentID(for: .reviewer) ?? recommendedAgentID(
            forTaskTitle: "审查验收：\(cleanGoal)",
            successCriteria: "审查产物是否满足目标，输出可交付结论。",
            fallbackRole: .reviewer
        )

        let ctoTask = CompanyTask(
            productID: productID,
            title: "技术负责人拆解：\(cleanGoal)",
            ownerID: ctoID,
            status: .running,
            successCriteria: "把目标拆解为可执行任务，并通过消息总线派发给员工。"
        )
        let engineerTask = CompanyTask(
            productID: productID,
            title: "员工执行：\(cleanGoal)",
            ownerID: engineerID,
            status: engineerID == nil ? .planned : .assigned,
            successCriteria: "完成工程实现并报告修改文件、验证命令和剩余风险。"
        )
        let reviewerTask = CompanyTask(
            productID: productID,
            title: "审查验收：\(cleanGoal)",
            ownerID: reviewerID,
            status: .planned,
            successCriteria: "按成功标准审查工程产物，输出是否可交付结论。"
        )
        let bossTask = CompanyTask(
            productID: productID,
            title: "老板审批：\(cleanGoal)",
            ownerID: bossID,
            status: .needsApproval,
            successCriteria: "老板批准最终交付或驳回返工。"
        )
        tasks.insert(contentsOf: [ctoTask, engineerTask, reviewerTask, bossTask], at: 0)

        appendEvent(
            kind: .taskCreated,
            title: "技术负责人启动新目标",
            detail: "\(productLabel)：\(cleanGoal)",
            agentID: ctoID
        )

        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: ctoTask.id,
            kind: .ctoGoalStarted,
            subject: "技术负责人启动新目标：\(cleanGoal)",
            body: "技术负责人已收到老板目标，已经创建拆解、执行、审查和审批四个任务并通过消息总线派发。",
            persist: false
        )

        if let engineerID {
            enqueueWorkItem(taskID: engineerTask.id, agentID: engineerID, prompt: workOrderPrompt(for: engineerTask))
        }

        if let reviewerID {
            postAgentMessage(
                productID: productID,
                fromAgentID: ctoID,
                toAgentID: reviewerID,
                taskID: reviewerTask.id,
                kind: .reviewRequested,
                subject: "等待审查：\(cleanGoal)",
                body: "工程实现完成后请按成功标准审查 \(cleanGoal)，并给出是否可交付的结论。",
                persist: false
            )
        }

        saveSnapshot()
        return ctoTask.id
    }

    @discardableResult
    public func advanceCTOSupervisorLoop() -> Bool {
        let supervisorTasks = tasks.filter { $0.productID == selectedProductID && isCTOSupervisorTask($0) }
        let goals = Set(supervisorTasks.compactMap { ctoSupervisorGoalKey(for: $0) })
        var progressed = false
        var progressedGoals: [String] = []

        for goal in goals {
            let goalTasks = supervisorTasks.filter { ctoSupervisorGoalKey(for: $0) == goal }
            guard let engineerTask = goalTasks.first(where: { $0.title.hasPrefix("员工执行：") }),
                  let reviewerTask = goalTasks.first(where: { $0.title.hasPrefix("审查验收：") }),
                  let bossTask = goalTasks.first(where: { $0.title.hasPrefix("老板审批：") })
            else { continue }
            var goalProgressed = false

            if engineerTask.status == .needsReview,
               reviewerTask.status == .planned,
               let reviewerID = reviewerTask.ownerID,
               selectedProductAgents.contains(where: { $0.id == reviewerID }) {
                assignTask(reviewerTask.id, to: reviewerID)
                enqueueWorkItem(taskID: reviewerTask.id, agentID: reviewerID, prompt: workOrderPrompt(for: reviewerTask))
                postAgentMessage(
                    productID: selectedProductID,
                    fromAgentID: ctoID,
                    toAgentID: reviewerID,
                    taskID: reviewerTask.id,
                    kind: .reviewRequested,
                    subject: "请审查：\(goal)",
                    body: "工程实现已完成，请按成功标准审查并给出可交付结论。",
                    persist: false
                )
                progressed = true
                goalProgressed = true
            }

            if reviewerTask.status == .done,
               bossTask.status == .needsApproval,
               !approvals.contains(where: { $0.taskID == bossTask.id }) {
                requestApproval(
                    taskID: bossTask.id,
                    title: "请老板审批：\(goal)",
                    reason: "工程实现与审查均已完成，请老板做最终决策。",
                    requesterID: ctoID
                )
                progressed = true
                goalProgressed = true
            }

            if goalProgressed {
                progressedGoals.append(goal)
            }
        }

        if progressed {
            let goalSummary = progressedGoals.isEmpty ? "当前目标" : progressedGoals.joined(separator: "、")
            postAgentMessage(
                productID: selectedProductID,
                fromAgentID: ctoID,
                toAgentID: bossID,
                kind: .ctoLoopProgressed,
                subject: "技术负责人调度循环已推进：\(goalSummary)",
                body: "技术负责人已经在多员工协作链路上推进了一步。\n目标：\(goalSummary)",
                persist: false
            )
            saveSnapshot()
        }
        return progressed
    }

    private func isCTOSupervisorTask(_ task: CompanyTask) -> Bool {
        let prefixes = ["技术负责人拆解：", "员工执行：", "审查验收：", "老板审批："]
        return prefixes.contains { task.title.hasPrefix($0) }
    }

    private func ctoSupervisorGoalKey(for task: CompanyTask) -> String? {
        let prefixes = ["技术负责人拆解：", "员工执行：", "审查验收：", "老板审批："]
        for prefix in prefixes where task.title.hasPrefix(prefix) {
            return String(task.title.dropFirst(prefix.count))
        }
        return nil
    }

    private func multiAgentClosureTrace(for goal: String) -> MultiAgentClosureTrace {
        let goalTasks = selectedProductTasks.filter { ctoSupervisorGoalKey(for: $0) == goal }
        let taskIDs = Set(goalTasks.map(\.id))
        let relatedMessages = selectedProductAgentMessages.filter { message in
            message.subject.contains(goal)
                || message.body.contains(goal)
                || message.taskID.map { taskIDs.contains($0) } == true
        }
        let approvalRecords = selectedProductApprovals.filter { approval in
            approval.title.contains(goal)
                || approval.reason.contains(goal)
                || approval.taskID.map { taskIDs.contains($0) } == true
        }
        let relatedGates = selectedProductReviewGates.filter { taskIDs.contains($0.taskID) }
        let gateVerificationIDs = Set(relatedGates.compactMap(\.latestVerificationID))
        let gateArtifactIDs = Set(relatedGates.compactMap(\.reportArtifactID))
        let relatedArtifacts = selectedProductArtifacts.filter { artifact in
            artifact.title.contains(goal)
                || artifact.summary.contains(goal)
                || artifact.taskID.map { taskIDs.contains($0) } == true
                || gateArtifactIDs.contains(artifact.id)
        }
        let relatedVerifications = selectedProductVerifications.filter { verification in
            verification.title.contains(goal)
                || verification.detail.contains(goal)
                || gateVerificationIDs.contains(verification.id)
        }

        let hasCTOTask = goalTasks.contains { $0.title.hasPrefix("技术负责人拆解：") }
        let hasEngineerTask = goalTasks.contains { $0.title.hasPrefix("员工执行：") }
        let hasReviewerTask = goalTasks.contains { $0.title.hasPrefix("审查验收：") }
        let hasBossTask = goalTasks.contains { $0.title.hasPrefix("老板审批：") }
        let hasGoalStarted = relatedMessages.contains { $0.kind == .ctoGoalStarted }
        let hasDispatch = relatedMessages.contains { $0.kind == .taskDispatched }
        let hasWorkCompleted = relatedMessages.contains { $0.kind == .workCompleted }
        let hasLoopProgressed = relatedMessages.contains { $0.kind == .ctoLoopProgressed }
        let hasApprovalRequested = relatedMessages.contains { $0.kind == .approvalRequested }
        let hasApprovalDecided = relatedMessages.contains { $0.kind == .approvalDecided } || approvalRecords.contains { $0.status != .pending }
        let hasReviewRequested = relatedMessages.contains { $0.kind == .reviewRequested }
        let hasReviewCompleted = relatedMessages.contains { $0.kind == .reviewCompleted }
        let hasAcceptanceCompleted = relatedMessages.contains { $0.kind == .acceptanceCompleted }
        let hasAcceptedGate = relatedGates.contains { $0.status == .accepted }

        let steps = [
            MultiAgentClosureTraceStep(
                id: "task-graph",
                title: "任务图",
                status: hasCTOTask && hasEngineerTask && hasReviewerTask && hasBossTask ? .passed : (goalTasks.isEmpty ? .failed : .warning),
                detail: "技术负责人、执行、审查、老板审批任务 \(goalTasks.count)/4。"
            ),
            MultiAgentClosureTraceStep(
                id: "message-bus",
                title: "消息总线",
                status: hasDispatch && hasWorkCompleted ? .passed : (relatedMessages.isEmpty ? .failed : .warning),
                detail: "关联消息 \(relatedMessages.count) 条；派发 \(hasDispatch ? "已出现" : "未出现")，回传 \(hasWorkCompleted ? "已出现" : "未出现")。"
            ),
            MultiAgentClosureTraceStep(
                id: "cto-loop",
                title: "技术负责人调度",
                status: hasGoalStarted && hasLoopProgressed ? .passed : (hasGoalStarted ? .warning : .failed),
                detail: "目标启动 \(hasGoalStarted ? "已记录" : "未记录")；循环推进 \(hasLoopProgressed ? "已记录" : "未记录")。"
            ),
            MultiAgentClosureTraceStep(
                id: "approval",
                title: "老板审批",
                status: hasApprovalRequested && hasApprovalDecided ? .passed : (hasApprovalRequested || hasApprovalDecided ? .warning : .failed),
                detail: "审批请求 \(hasApprovalRequested ? "已创建" : "未创建")；审批结果 \(hasApprovalDecided ? "已回写" : "未回写")。"
            ),
            MultiAgentClosureTraceStep(
                id: "review-gate",
                title: "审查门禁",
                status: hasReviewRequested && hasReviewCompleted && hasAcceptanceCompleted && hasAcceptedGate ? .passed : (relatedGates.isEmpty ? .failed : .warning),
                detail: "验收门禁 \(relatedGates.count) 条；审查反馈 \(hasReviewCompleted ? "已出现" : "未出现")，老板验收 \(hasAcceptanceCompleted ? "已出现" : "未出现")。"
            ),
            MultiAgentClosureTraceStep(
                id: "evidence",
                title: "产物验收",
                status: !relatedArtifacts.isEmpty && !relatedVerifications.isEmpty ? .passed : (!relatedArtifacts.isEmpty || !relatedVerifications.isEmpty ? .warning : .failed),
                detail: "产物 \(relatedArtifacts.count) 条，验收 \(relatedVerifications.count) 条。"
            )
        ]

        let pointTotal = steps.reduce(0) { partial, step in
            switch step.status {
            case .passed: partial + 2
            case .warning: partial + 1
            case .failed: partial
            }
        }
        let completionScore = Int((Double(pointTotal) / Double(steps.count * 2) * 100).rounded())
        let status: ArchitectureCheckStatus
        if steps.allSatisfy({ $0.status == .passed }) {
            status = .passed
        } else if steps.contains(where: { $0.status == .warning || $0.status == .passed }) {
            status = .warning
        } else {
            status = .failed
        }

        let timestamps = relatedMessages.map(\.createdAt)
            + approvalRecords.map(\.createdAt)
            + approvalRecords.compactMap(\.decidedAt)
            + relatedGates.flatMap { [$0.createdAt, $0.updatedAt] }
            + relatedArtifacts.map(\.createdAt)
            + relatedVerifications.map(\.createdAt)

        return MultiAgentClosureTrace(
            id: "\(selectedProductID.uuidString)-\(goal)",
            productID: selectedProductID,
            goal: goal,
            status: status,
            completionScore: completionScore,
            taskIDs: goalTasks.map(\.id),
            messageIDs: relatedMessages.map(\.id),
            approvalIDs: approvalRecords.map(\.id),
            artifactIDs: relatedArtifacts.map(\.id),
            verificationIDs: relatedVerifications.map(\.id),
            reviewGateIDs: relatedGates.map(\.id),
            steps: steps,
            createdAt: timestamps.min() ?? .distantPast,
            updatedAt: timestamps.max() ?? .distantPast
        )
    }

    private func agentCanParticipateInProduct(_ agentID: UUID, productID: UUID) -> Bool {
        if agentID == bossID { return true }
        if agentID == ctoID { return true }
        guard let product = products.first(where: { $0.id == productID }) else { return false }
        return product.assignedAgentIDs.contains(agentID)
    }

    private func productName(_ productID: UUID) -> String {
        products.first(where: { $0.id == productID })?.name ?? "未知产品"
    }

    public func generateBossReport() {
        let product = selectedProduct
        let productTasks = selectedProductTasks
        let openTasks = productTasks.filter { $0.status != .done && $0.status != .canceled }
        let doneTasks = productTasks.filter { $0.status == .done }
        let riskEvents = selectedProductBossRiskEvents.prefix(5)
        let runningEmployees = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }

        let taskLines = productTasks.prefix(12).map { task in
            "- \(task.title)：\(task.status.title) / \(task.ownerID.map(agentName) ?? "未分配")"
        }.joined(separator: "\n")
        let riskLines = riskEvents.map { "- \($0.title)：\($0.detail)" }.joined(separator: "\n")
        let agentStateLines = selectedProductAgents.map { agent in
            let log = currentProductTerminalLog(for: agent.id)
            return "- \(agent.displayName)：\(runningAgentIDs.contains(agent.id) ? "正在推进" : "待命") / \(log.isEmpty ? "暂无新回传" : "已有工作回传")"
        }.joined(separator: "\n")
        let workspaceLine = product.map { opcProductWorkspaceDisplayName($0.rootDirectory) } ?? "未设置本地工作区"

        let report = """
        \("老板报告：".L())\(product?.name ?? "当前产品")

        \("当前阶段：".L())\(product?.stage.title ?? "未知") / \(product?.status.title ?? "未知")
        \(workspaceLine)

        \("关键数字：".L())
        \("- 员工：".L())\(selectedProductAgents.count)
        \("- 正在运行：".L())\(runningEmployees.count)
        \("- 未完成任务：".L())\(openTasks.count)
        \("- 已完成任务：".L())\(doneTasks.count)

        \("任务概览：".L())
        \(taskLines.isEmpty ? "暂无任务" : taskLines)

        \("风险：".L())
        \(riskLines.isEmpty ? "暂无近期风险" : riskLines)

        \("员工状态：".L())
        \(agentStateLines)

        \("下一步建议：".L())
        \("1. 若未完成任务存在，优先推进运行中和待审查任务。".L())
        \("2. 若风险存在，老板先在风险审批中批准或驳回。".L())
        \("3. 若任务已完成，进入验收实验室做最终批准。".L())
        """

        let productID = product?.id ?? selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: bossID, author: .system, text: report))
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "已生成老板报告，请按报告继续推进。\n\n".L() + "\(report)"))
        appendEvent(kind: .artifactCreated, title: "老板报告已生成".L(), detail: "\(product?.name ?? "当前产品".L())" + " 的状态报告已写入老板和技术负责人对话。".L(), agentID: ctoID)
        saveSnapshot()
    }

    public func createHandoffSnapshot() {
        let product = selectedProduct
        let report = product?.importReport
        let snapshot = """
        \("产品交接快照".L())
        产品：\(product?.name ?? "当前产品".L())
        根目录：\(product?.rootDirectory ?? "未设置".L())
        阶段：\(product?.stage.title ?? "未知".L()) / \(product?.status.title ?? "未知".L())
        规则文件：\(report?.ruleFiles.joined(separator: "、") ?? "无".L())
        工具线索：\(report?.detectedTools.joined(separator: "、") ?? "无".L())
        \("当前任务数：".L())\(selectedProductTasks.count)
        \("员工数：".L())\(selectedProductAgents.count)
        """
        messages.append(ChatMessage(productID: product?.id ?? selectedProductID, agentID: ctoID, author: .system, text: snapshot))
        appendEvent(kind: .artifactCreated, title: "交接快照已生成", detail: "已把当前产品上下文写入技术负责人对话。", agentID: ctoID)
        saveSnapshot()
    }

    public func missingCoreTeamRolesForSelectedProduct() -> [AgentRole] {
        let requiredRoles: [AgentRole] = [.productArchitect, .researcher, .tester]
        return requiredRoles.filter { role in
            !selectedProductAgents.contains { $0.role == role }
        }
    }

    @discardableResult
    public func assignExistingSpecialistsToSelectedProduct() -> Bool {
        let specialistRoles: Set<AgentRole> = [.productArchitect, .tester, .researcher]
        let existingIDs = Set(agents.filter { specialistRoles.contains($0.role) }.map(\.id))
        guard !existingIDs.isEmpty, let index = products.firstIndex(where: { $0.id == selectedProductID }) else {
            return false
        }

        let before = products[index].assignedAgentIDs
        products[index].assignedAgentIDs.formUnion(existingIDs)
        products[index].updatedAt = Date()
        let changed = before != products[index].assignedAgentIDs
        if changed {
            appendEvent(kind: .statusChanged, title: "现有专业员工已加入产品", detail: "只绑定已存在员工，没有自动创建新员工。", agentID: ctoID)
        }
        return changed
    }

    @discardableResult
    public func localizeLegacyVisibleTerminology(saveAfterChange: Bool = true) -> Bool {
        var changed = false
        for index in agents.indices where agents[index].role == .cto {
            if agents[index].displayName.contains("CTO") {
                agents[index].displayName = agents[index].displayName
                    .replacingOccurrences(of: "CTO ", with: "技术负责人")
                    .replacingOccurrences(of: "CTO", with: "技术负责人")
                changed = true
            }
            if agents[index].title.contains("CTO") {
                agents[index].title = agents[index].title
                    .replacingOccurrences(of: "CTO ", with: "技术负责人")
                    .replacingOccurrences(of: "CTO", with: "技术负责人")
                changed = true
            }
        }
        for index in tasks.indices {
            if tasks[index].title.contains("公司 App 基础") {
                tasks[index].title = tasks[index].title
                    .replacingOccurrences(of: "公司 App 基础", with: "公司应用基础")
                changed = true
            }
        }
        for index in agents.indices {
            if agents[index].displayName.contains("UI 设计师") {
                agents[index].displayName = agents[index].displayName
                    .replacingOccurrences(of: "UI 设计师", with: "界面设计师")
                changed = true
            }
            if agents[index].title.contains("UI 设计师") {
                agents[index].title = agents[index].title
                    .replacingOccurrences(of: "UI 设计师", with: "界面设计师")
                changed = true
            }
        }
        if changed && saveAfterChange {
            saveSnapshot()
        }
        return changed
    }

    @discardableResult
    public func removeLegacyAutoCreatedSpecialists(saveAfterChange: Bool = true) -> Bool {
        let legacyAgents = agents.filter(isLegacyAutoCreatedSpecialist)
        guard !legacyAgents.isEmpty else { return false }

        let removedIDs = Set(legacyAgents.map(\.id))
        let roleByID = Dictionary(uniqueKeysWithValues: legacyAgents.map { ($0.id, $0.role) })

        for index in tasks.indices {
            guard let ownerID = tasks[index].ownerID, removedIDs.contains(ownerID) else { continue }
            tasks[index].ownerID = replacementAgentID(forRemovedRole: roleByID[ownerID] ?? .custom)
        }

        for index in workQueue.indices {
            guard removedIDs.contains(workQueue[index].agentID) else { continue }
            workQueue[index].agentID = replacementAgentID(forRemovedRole: roleByID[workQueue[index].agentID] ?? .custom)
            workQueue[index].updatedAt = Date()
        }

        agents.removeAll { removedIDs.contains($0.id) }
        messages.removeAll { removedIDs.contains($0.agentID) }
        terminalLogs = terminalLogs.filter { !removedIDs.contains($0.key) }
        productTerminalLogs = productTerminalLogs.filter { entry in
            guard let agentIDText = entry.key.split(separator: ":").last,
                  let agentID = UUID(uuidString: String(agentIDText))
            else { return true }
            return !removedIDs.contains(agentID)
        }
        runningAgentIDs.subtract(removedIDs)

        for index in products.indices {
            products[index].assignedAgentIDs.subtract(removedIDs)
            products[index].updatedAt = Date()
        }

        if removedIDs.contains(selectedAgentID) {
            selectedAgentID = ctoID
        }

        appendEvent(
            kind: .statusChanged,
            title: "自动员工已清理",
            detail: "已移除旧版本自动生成的专业员工：\(legacyAgents.map(\.displayName).joined(separator: "、"))。以后自动能力不会偷偷创建员工。",
            agentID: ctoID
        )
        if saveAfterChange {
            saveSnapshot()
        }
        return true
    }

    @discardableResult
    public func cleanLegacySyntheticAgentReplies(saveAfterChange: Bool = true) -> Bool {
        var changed = false
        for index in messages.indices where messages[index].author == .agent && isLegacySyntheticAgentReply(messages[index].text) {
            messages[index].author = .system
            messages[index].text = "系统提示：旧版本的本地模板回复已隐藏。现在正式沟通只显示真实模型返回内容；未调用模型时只显示系统降级提示。"
            changed = true
        }

        if changed {
            appendEvent(kind: .statusChanged, title: "旧版模板回复已清理", detail: "已把历史里的本地拟人化模板回复改为系统提示，避免误认为员工真实回复。", agentID: ctoID)
            if saveAfterChange {
                saveSnapshot()
            }
        }
        return changed
    }

    public func seedStandardTaskTemplates(goal: String) {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = cleanGoal.isEmpty ? (selectedProduct?.name ?? "当前产品") : cleanGoal
        let templateTasks = [
            CompanyTask(productID: selectedProductID, title: "模板：产品范围与成功标准", ownerID: recommendedAgentID(forTaskTitle: "模板：产品范围与成功标准", successCriteria: "明确 \(target) 的功能范围、边界、成功标准和不做事项。", fallbackRole: .productArchitect) ?? ctoID, status: .planned, successCriteria: "明确 \(target) 的功能范围、边界、成功标准和不做事项。"),
            CompanyTask(productID: selectedProductID, title: "模板：界面与交互方案", ownerID: recommendedAgentID(forTaskTitle: "模板：界面与交互方案", successCriteria: "输出关键界面、状态、动效和用户操作路径。", fallbackRole: .uiDesigner), status: .planned, successCriteria: "输出关键界面、状态、动效和用户操作路径。"),
            CompanyTask(productID: selectedProductID, title: "模板：工程实现任务", ownerID: recommendedAgentID(forTaskTitle: "模板：工程实现任务", successCriteria: "完成代码修改，并汇报文件、命令、验证和风险。", fallbackRole: .codeEngineer), status: .planned, successCriteria: "完成代码修改，并汇报文件、命令、验证和风险。"),
            CompanyTask(productID: selectedProductID, title: "模板：测试验证清单", ownerID: recommendedAgentID(forTaskTitle: "模板：测试验证清单", successCriteria: "覆盖构建、主要流程、失败场景和回归检查。", fallbackRole: .tester) ?? firstAgentID(withSkill: "review", fallbackRole: .reviewer), status: .planned, successCriteria: "覆盖构建、主要流程、失败场景和回归检查。"),
            CompanyTask(productID: selectedProductID, title: "模板：审查与交付结论", ownerID: recommendedAgentID(forTaskTitle: "模板：审查与交付结论", successCriteria: "给出是否可交付、风险、缺口和下一步建议。", fallbackRole: .reviewer), status: .planned, successCriteria: "给出是否可交付、风险、缺口和下一步建议。")
        ]
        tasks.insert(contentsOf: templateTasks, at: 0)
        appendEvent(kind: .taskCreated, title: "标准任务模板已生成", detail: target, agentID: ctoID)
        saveSnapshot()
    }

    public func selectedProductRunDataSummary() -> String {
        let generatedTaskCount = selectedProductTasks.filter(isGeneratedOperationalTask).count
        return """
        \("将清理当前产品的运行/测试数据：".L())
        \("- 旧流水线、分支、模板、售前、手机指令任务：".L())\(generatedTaskCount)\(" 个".L())
        \("- 工作队列：".L())\(selectedProductWorkQueue.count)\(" 个".L())
        \("- 分支计划：".L())\(selectedProductBranchPlans.count)\(" 个".L())
        \("- 验收门禁：".L())\(selectedProductReviewGates.count)\(" 个".L())
        \("- 审批：".L())\(selectedProductApprovals.count)\(" 个".L())
        \("- 产物记录：".L())\(selectedProductArtifacts.count)\(" 个".L())
        \("- 验收记录：".L())\(selectedProductVerifications.count)\(" 个".L())
        \("- 产品记忆：".L())\(selectedProductMemories.count)\(" 条".L())
        \("- 通信日志：".L())\(selectedProductCommunicationLogs.count)\(" 条".L())

        \("不会删除员工，不会删除项目目录里的真实文件。".L())
        """
    }

    public func clearSelectedProductRunData() {
        createSafetyCheckpoint(reason: "清理当前产品运行/测试数据前自动检查点".L())
        let removableTaskIDs = Set(tasks.filter { task in
            task.productID == selectedProductID && isGeneratedOperationalTask(task)
        }.map(\.id))
        let removedTasks = removableTaskIDs.count
        let removedQueue = selectedProductWorkQueue.count
        let removedPlans = selectedProductBranchPlans.count
        let removedGates = selectedProductReviewGates.count
        let removedApprovals = selectedProductApprovals.count
        let removedArtifacts = selectedProductArtifacts.count
        let removedVerifications = selectedProductVerifications.count
        let removedMemories = selectedProductMemories.count
        let removedLogs = selectedProductCommunicationLogs.count

        tasks.removeAll { removableTaskIDs.contains($0.id) }
        workQueue.removeAll { $0.productID == selectedProductID }
        branchPlans.removeAll { $0.productID == selectedProductID }
        reviewGates.removeAll { $0.productID == selectedProductID }
        approvals.removeAll { $0.productID == selectedProductID }
        artifacts.removeAll { $0.productID == selectedProductID }
        verifications.removeAll { $0.productID == selectedProductID }
        memories.removeAll { $0.productID == selectedProductID }
        communicationLogs.removeAll { $0.productID == selectedProductID }
        agentMessages.removeAll { $0.productID == selectedProductID }
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != selectedProductID }

        appendEvent(
            kind: .statusChanged,
            title: "产品运行数据已清理".L(),
            detail: "任务 ".L() + "\(removedTasks)" + "，队列 ".L() + "\(removedQueue)" + "，分支计划 ".L() + "\(removedPlans)" + "，验收门禁 ".L() + "\(removedGates)" + "，审批 " + "\(removedApprovals)" + "，产物 " + "\(removedArtifacts)" + "，验收 " + "\(removedVerifications)" + "，记忆 " + "\(removedMemories)" + "，通信日志 " + "\(removedLogs)" + "。",
            agentID: ctoID
        )
        saveSnapshot()
    }

    public func defaultCompanyStatePreviewText() -> String {
        let extraRoles: Set<AgentRole> = [.productArchitect, .tester, .researcher, .custom]
        let extraAgents = agents.filter { extraRoles.contains($0.role) }
        let generatedTaskCount = tasks.filter(isGeneratedOperationalTask).count
        let terminalLogCount = productTerminalLogs.values.filter { !$0.isEmpty }.count
        return """
        \("恢复默认公司状态会重建本地演示数据：".L())
        \("- 产品工作区：".L())\(products.count)\(" 个 -> 1 个默认产品".L())
        \("- 员工：".L())\(agents.count)\(" 个 -> 老板、Codex 技术负责人、Gemini 界面设计师、Claude Code 工程师、Codex 审查员".L())
        - 当前额外/专业员工：\(extraAgents.map(\.displayName).joined(separator: "、").nilIfBlank ?? "无".L())
        \("- 自动/测试任务：".L())\(generatedTaskCount)\(" 个".L())
        \("- 队列/审批/产物/验收/记忆/通信/分支：".L())\(workQueue.count + approvals.count + artifacts.count + verifications.count + memories.count + communicationLogs.count + branchPlans.count)\(" 条".L())
        \("- 有终端日志员工：".L())\(terminalLogCount)\(" 个".L())

        \("不会删除真实项目目录里的文件；会清空 OPC 内部产品、任务、日志和测试员工状态。".L())
        """
    }

    public func resetToDefaultCompanyState() {
        createSafetyCheckpoint(reason: "恢复默认公司状态前自动检查点")
        let uiID = agents.first(where: { $0.role == .uiDesigner })?.id ?? UUID()
        let codeID = agents.first(where: { $0.role == .codeEngineer })?.id ?? UUID()
        let reviewID = agents.first(where: { $0.role == .reviewer })?.id ?? UUID()

        agents = [
            CompanyAgent(
                id: bossID,
                displayName: "老板",
                title: "OPC 公司老板",
                role: .boss,
                backend: AgentBackend(type: .local, command: "human", model: "owner"),
                ethnicity: .chinese,
                gender: .man,
                clothing: .businessSuit,
                status: .idle,
                permissions: [.approveRisk],
                reportsToCTO: false,
                seat: OfficeSeat(x: 0.74, y: 0.75, room: "boss-office")
            ),
            CompanyAgent(
                id: ctoID,
                displayName: "Codex 技术负责人",
                title: "总技术负责人",
                role: .cto,
                backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
                ethnicity: .white,
                gender: .man,
                clothing: .businessSuit,
                status: .thinking,
                permissions: [.readFiles, .runCommands],
                reportsToCTO: false,
                seat: OfficeSeat(x: 0.26, y: 0.75, room: "cto-office")
            ),
            CompanyAgent(
                id: uiID,
                displayName: "Gemini 界面设计师",
                title: "视觉产品设计师",
                role: .uiDesigner,
                backend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "", reasoningEffort: .medium),
                ethnicity: .southAsian,
                gender: .woman,
                clothing: .designerBlack,
                status: .idle,
                permissions: [.readFiles],
                seat: OfficeSeat(x: 0.34, y: 0.50, room: "employee-hall")
            ),
            CompanyAgent(
                id: codeID,
                displayName: "Claude Code 工程师",
                title: "高级 macOS 工程师",
                role: .codeEngineer,
                backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .medium),
                ethnicity: .black,
                gender: .man,
                clothing: .smartCasual,
                status: .coding,
                permissions: [.readFiles, .editFiles, .runTests, .runCommands],
                seat: OfficeSeat(x: 0.50, y: 0.50, room: "employee-hall")
            ),
            CompanyAgent(
                id: reviewID,
                displayName: "Codex 审查员",
                title: "风险与验收审查员",
                role: .reviewer,
                backend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
                ethnicity: .latino,
                gender: .woman,
                clothing: .businessSuit,
                status: .reviewing,
                permissions: [.readFiles, .runTests],
                seat: OfficeSeat(x: 0.66, y: 0.50, room: "employee-hall")
            )
        ]

        let defaultProduct = ProductWorkspace(
            name: "默认产品工作区",
            shortName: "默认",
            rootDirectory: Self.defaultProductRootDirectory(),
            status: .active,
            stage: .discovery,
            assignedAgentIDs: [ctoID, uiID, codeID, reviewID],
            teamLeadAgentID: ctoID
        )

        products = [defaultProduct]
        selectedProductID = defaultProduct.id
        selectedAgentID = ctoID
        messages = [
            ChatMessage(productID: defaultProduct.id, agentID: ctoID, author: .system, text: "系统提示：OPC 公司已经恢复到默认状态。正式沟通会调用员工配置的真实模型来源。"),
            ChatMessage(productID: defaultProduct.id, agentID: uiID, author: .system, text: "系统提示：Gemini 界面设计师已恢复，档案、记忆和技能已写入员工工作区。"),
            ChatMessage(productID: defaultProduct.id, agentID: codeID, author: .system, text: "系统提示：Claude Code 工程师已恢复，档案、记忆和技能已写入员工工作区。"),
            ChatMessage(productID: defaultProduct.id, agentID: reviewID, author: .system, text: "系统提示：Codex 审查员已恢复，档案、记忆和技能已写入员工工作区。")
        ]
        events = [
            CompanyEvent(kind: .statusChanged, title: "公司已恢复默认状态", detail: "已清空本地测试数据并恢复默认产品团队。", agentID: ctoID)
        ]
        tasks = [
            CompanyTask(productID: defaultProduct.id, title: "定义产品架构", ownerID: ctoID, status: .done, successCriteria: "完成产品规格、技术栈和角色系统。"),
            CompanyTask(productID: defaultProduct.id, title: "创建 2D 公司应用基础", ownerID: codeID, status: .running, successCriteria: "构建原生 macOS SwiftUI/SpriteKit 外壳，并支持点击员工沟通。"),
            CompanyTask(productID: defaultProduct.id, title: "审查命令行调度设计", ownerID: reviewID, status: .planned, successCriteria: "确认 Codex、Claude、Gemini 命令适配器安全且可扩展。")
        ]
        workQueue = []
        approvals = []
        artifacts = []
        verifications = []
        memories = []
        communicationChannels = []
        communicationLogs = []
        branchPlans = []
        reviewGates = []
        terminalLogs = [:]
        productTerminalLogs = [:]
        runningAgentIDs = []
        agentProfiles = [:]
        persistentTerminalSessions = [:]
        mainWorkspace = .office
        ensureAgentProfiles()
        syncAllAgentWorkspaces()
        saveSnapshot()
    }

    public func productIsolationAuditText() -> String {
        let validProductIDs = Set(products.map(\.id))
        let orphanTasks = tasks.filter { task in
            guard let productID = task.productID else { return false }
            return !validProductIDs.contains(productID)
        }
        let orphanQueue = workQueue.filter { !validProductIDs.contains($0.productID) }
        let orphanQueueByTask = workQueue.filter { item in
            !tasks.contains { $0.id == item.taskID }
        }
        let orphanApprovals = approvals.filter { !validProductIDs.contains($0.productID) }
        let orphanArtifacts = artifacts.filter { !validProductIDs.contains($0.productID) }
        let orphanVerifications = verifications.filter { !validProductIDs.contains($0.productID) }
        let orphanMemories = memories.filter { !validProductIDs.contains($0.productID) }
        let orphanChannels = communicationChannels.filter { channel in
            guard let productID = channel.productID else { return false }
            return !validProductIDs.contains(productID)
        }
        let orphanLogs = communicationLogs.filter { !validProductIDs.contains($0.productID) }
        let duplicateRoots = Dictionary(grouping: products, by: \.rootDirectory)
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
        let crossProductQueues = workQueue.filter { item in
            guard let task = tasks.first(where: { $0.id == item.taskID }) else { return false }
            return task.productID != nil && task.productID != item.productID
        }

        let issueCount = orphanTasks.count
            + orphanQueue.count
            + orphanQueueByTask.count
            + orphanApprovals.count
            + orphanArtifacts.count
            + orphanVerifications.count
            + orphanMemories.count
            + orphanChannels.count
            + orphanLogs.count
            + duplicateRoots.count
            + crossProductQueues.count

        let productLines = products.map { product in
            let taskCount = tasks.filter { $0.productID == product.id }.count
            let queueCount = workQueue.filter { $0.productID == product.id }.count
            let memberCount = product.assignedAgentIDs.count
            let leadName = product.teamLeadAgentID.map(agentName) ?? "未设置"
            return "- \(product.name)：成员 \(memberCount)，负责人 \(leadName)，任务 \(taskCount)，队列 \(queueCount)"
        }.joined(separator: "\n")

        return """
        \("多产品隔离体检：".L())\(issueCount == 0 ? "通过" : "发现 \(issueCount) 项问题")

        \("产品概览：".L())
        \(productLines.isEmpty ? "- 暂无产品" : productLines)

        \("隔离检查：".L())
        \("- 孤儿任务：".L())\(orphanTasks.count)
        \("- 孤儿队列：".L())\(orphanQueue.count + orphanQueueByTask.count)
        \("- 跨产品队列：".L())\(crossProductQueues.count)
        \("- 孤儿审批：".L())\(orphanApprovals.count)
        \("- 孤儿产物：".L())\(orphanArtifacts.count)
        \("- 孤儿验收：".L())\(orphanVerifications.count)
        \("- 孤儿记忆：".L())\(orphanMemories.count)
        \("- 孤儿通信配置：".L())\(orphanChannels.count)
        \("- 孤儿通信日志：".L())\(orphanLogs.count)
        \("- 重复产品目录：".L())\(duplicateRoots.count)

        \("结论：".L())
        \(issueCount == 0 ? "当前产品数据按产品归属隔离，未发现明显串线。" : "存在隔离风险，建议先清理或修复孤儿/跨产品数据。")
        """
    }

    public func runProductIsolationAudit() {
        let report = productIsolationAuditText()
        let passed = report.contains("多产品隔离体检：通过".L())
        verifications.insert(VerificationRecord(productID: selectedProductID, status: passed ? .passed : .warning, title: "多产品隔离体检".L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: passed ? .artifactCreated : .risk, title: "多产品隔离体检完成".L(), detail: passed ? "通过".L() : "发现隔离风险".L(), agentID: ctoID)
        saveSnapshot()
    }

    public func cliRuntimeIsolationAuditText() -> String {
        let agents = executableAgents
        let workspaceRows = agents.map { agent -> (CompanyAgent, URL, Bool, Bool) in
            let workspace = agentWorkspaceURL(for: agent.id)
            let hasDirectory = FileManager.default.fileExists(atPath: workspace.path)
            let hasSessionLog = FileManager.default.fileExists(atPath: workspace.appendingPathComponent("sessions.jsonl").path)
            return (agent, workspace, hasDirectory, hasSessionLog)
        }
        let workspacePaths = workspaceRows.map { $0.1.path }
        let duplicateWorkspaceCount = workspacePaths.count - Set(workspacePaths).count
        let missingWorkspaceCount = workspaceRows.filter { !$0.2 || !$0.3 }.count
        let runtimeRows = agents.map { agent -> (CompanyAgent, AgentRuntimeSession?) in
            (agent, runtimeSessions[agent.id])
        }
        let missingSessionCount = runtimeRows.filter { $0.1 == nil }.count
        let persistentCount = runtimeRows.filter { $0.1?.capability == .persistentProtocol }.count
        let codeAgents = agents.filter { requiresIsolatedCLIExecution($0) }
        let workingDirectory = cliWorkingDirectoryURL()
        let isGitRepository = FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(".git").path)
        let isolationPlanLines = codeAgents.map { agent in
            let metadataDirectory = cliWorktreeIsolationURL(for: agent)
            let marker = metadataDirectory.appendingPathComponent("WORKTREE.md")
            let hasDirectory = FileManager.default.fileExists(atPath: metadataDirectory.path)
            let hasMarker = FileManager.default.fileExists(atPath: marker.path)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let runnable = executionDirectory.standardizedFileURL.path != workingDirectory.standardizedFileURL.path
            let status = runnable ? "可执行".L() : hasDirectory && hasMarker ? "已登记，待生成源码执行区".L() : "待创建".L()
            let mode = isGitRepository ? "代码仓库独立工作区".L() : "源码快照隔离".L()
            let executionSummary = runnable ? "已使用独立执行区".L() : "暂用主工作目录".L()
            return "- \(agent.displayName)：\(status) · \(mode) · \(executionSummary)"
        }
        let workspaceLines = workspaceRows.map { agent, workspace, hasDirectory, hasSessionLog in
            "- ".L() + "\(agent.displayName)" + "：员工工作区 ".L() + "\(hasDirectory ? "已创建".L() : "缺失".L())" + " · 会话日志 ".L() + "\(hasSessionLog ? "已创建" : "缺失")"
        }
        let runtimeLines = runtimeRows.map { agent, session in
            let detail = session.map { "\($0.state.title) / \($0.capability.title)" } ?? "缺失".L()
            return "- \(agent.displayName)：\(detail)"
        }

        let issueCount = duplicateWorkspaceCount + missingWorkspaceCount + missingSessionCount
        return """
        命令行与工作区隔离体检：\(issueCount == 0 ? "通过".L() : "发现 " + "\(issueCount)" + " 项问题")

        \("产品工作目录：".L())
        - \(workingDirectory.path)

        \("员工工作区：".L())
        \(workspaceLines.isEmpty ? "- 当前产品没有可执行员工。".L() : workspaceLines.joined(separator: "\n"))

        \("运行会话：".L())
        \(runtimeLines.isEmpty ? "- 当前产品没有运行会话。".L() : runtimeLines.joined(separator: "\n"))

        \("持续协作：".L())
        \("- 可继续接收任务：".L())\(persistentCount)/\(agents.count)

        \("代码类独立执行区：".L())
        \(isolationPlanLines.isEmpty ? "- 当前产品没有代码/测试类可执行员工。".L() : isolationPlanLines.joined(separator: "\n"))

        \("结论：".L())
        \(issueCount == 0 ? "当前产品的可执行员工已具备独立工作区、会话日志和运行会话；代码类员工会优先使用独立执行区，未生成独立执行区时才临时回退到主工作目录。".L() : "请先修复缺失工作区、会话日志或运行会话，再进入并行代码执行。")
        """
    }

    public func runCLIRuntimeIsolationAudit() {
        ensureRuntimeSessionsForSelectedProduct()
        syncSelectedProductAgentWorkspaces()
        ensureCLIWorktreeIsolationForSelectedProduct()
        let report = cliRuntimeIsolationAuditText()
        let passed = report.contains("命令行与工作区隔离体检：通过")
        let status: VerificationStatus = passed ? .passed : .warning
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行与工作区隔离体检", detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: passed ? .artifactCreated : .risk, title: "命令行与工作区隔离体检完成", detail: status.title, agentID: ctoID)
        saveSnapshot()
    }

    public func cliRuntimeIsolationAuditDetailText() -> String {
        let agents = executableAgents
        let workspaceRows = agents.map { agent -> (CompanyAgent, URL, Bool, Bool) in
            let workspace = agentWorkspaceURL(for: agent.id)
            let hasDirectory = FileManager.default.fileExists(atPath: workspace.path)
            let hasSessionLog = FileManager.default.fileExists(atPath: workspace.appendingPathComponent("sessions.jsonl").path)
            return (agent, workspace, hasDirectory, hasSessionLog)
        }
        let runtimeRows = agents.map { agent -> (CompanyAgent, AgentRuntimeSession?) in
            (agent, runtimeSessions[agent.id])
        }
        let workingDirectory = cliWorkingDirectoryURL()
        let isGitRepository = FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(".git").path)
        let isolationPlanLines = agents.filter { requiresIsolatedCLIExecution($0) }.map { agent in
            let metadataDirectory = cliWorktreeIsolationURL(for: agent)
            let sourceDirectory = cliIsolationSourceURL(for: agent)
            let marker = metadataDirectory.appendingPathComponent("WORKTREE.md")
            let hasDirectory = FileManager.default.fileExists(atPath: metadataDirectory.path)
            let hasMarker = FileManager.default.fileExists(atPath: marker.path)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let runnable = executionDirectory.standardizedFileURL.path != workingDirectory.standardizedFileURL.path
            return """
            - \(agent.displayName)：\(runnable ? "可执行" : hasDirectory && hasMarker ? "已登记，待生成源码执行区" : "待创建")
              \("隔离模式：".L())\(isGitRepository ? "代码仓库独立工作区" : "源码快照隔离")
              \("元数据目录：".L())\(metadataDirectory.path)
              \("源码目录：".L())\(sourceDirectory.path)
              \("执行目录：".L())\(executionDirectory.path)
            """
        }
        let workspaceLines = workspaceRows.map { agent, workspace, hasDirectory, hasSessionLog in
            """
            - \(agent.displayName)\("：目录 ".L())\(hasDirectory ? "存在" : "缺失")\(" · 会话日志 ".L())\(hasSessionLog ? "存在" : "缺失")
              \("员工工作区：".L())\(workspace.path)
              \("会话日志文件：员工会话日志档案".L())
            """
        }
        let runtimeLines = runtimeRows.map { agent, session in
            let detail = session.map { "\($0.state.title) / \($0.capability.title)" } ?? "缺失".L()
            return "- \(agent.displayName)：\(detail)"
        }

        return """
        \("运维详情：命令行与工作区隔离".L())

        \("产品工作目录：".L())
        - \(workingDirectory.path)

        \("员工工作区详情：".L())
        \(workspaceLines.isEmpty ? "- 当前产品没有可执行员工。".L() : workspaceLines.joined(separator: "\n"))

        \("运行会话详情：".L())
        \(runtimeLines.isEmpty ? "- 当前产品没有运行会话。".L() : runtimeLines.joined(separator: "\n"))

        \("代码类隔离详情：".L())
        \(isolationPlanLines.isEmpty ? "- 当前产品没有代码/测试类可执行员工。".L() : isolationPlanLines.joined(separator: "\n"))
        """
    }

    public func terminalWorkspacePlanText() -> String {
        let agents = executableAgents
        let sessionName = terminalWorkspaceSessionName()
        let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux")
        let sessionExists = tmuxSessionExists(sessionName)
        let windowNames = sessionExists ? tmuxWindowNames(sessionName) : []
        let workingDirectory = cliWorkingDirectoryURL()
        let configuredRoot = selectedProduct?.rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directoryStatus = configuredRoot.isEmpty || configuredRoot == workingDirectory.path
            ? "使用产品根目录"
            : "产品根目录不可用，实际已回退到 \(workingDirectory.path)"
        let agentLines = agents.map { agent in
            let windowName = terminalWorkspaceWindowName(for: agent)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let status = windowNames.contains(windowName) ? "已连接" : "待创建"
            let executionSummary = executionDirectory.standardizedFileURL.path == workingDirectory.standardizedFileURL.path
                ? "主工作目录"
                : "独立执行区"
            return "- \(agent.displayName)：终端席位 \(status) · 执行位置 \(executionSummary)"
        }.joined(separator: "\n")

        return """
        \("真实终端工作区计划：".L())\(tmuxPath == nil ? "缺少终端工具" : sessionExists ? "工作区已存在" : "可创建")
        \("产品：".L())\(selectedProduct?.name ?? "当前产品")
        \("终端工具：".L())\(tmuxPath == nil ? "未找到" : "已就绪")
        \("工作目录：".L())\(workingDirectory.path)
        \("目录状态：".L())\(directoryStatus)
        \("已连接席位：".L())\(windowNames.filter { $0 != "control" }.count)/\(agents.count)

        \("员工终端席位：".L())
        \(agentLines.isEmpty ? "- 当前产品没有可执行员工。" : agentLines)

        \("说明：".L())
        \("启动后会为当前产品团队创建真实终端工作区和员工终端席位，只写入身份与目录提示，不自动执行模型任务。具体任务仍从 OPC 的运行按钮发起，避免绕过预检、作业档案和验收链路。".L())
        """
    }

    public func terminalWorkspacePlanDetailText() -> String {
        let agents = executableAgents
        let sessionName = terminalWorkspaceSessionName()
        let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux")
        let sessionExists = tmuxSessionExists(sessionName)
        let windowNames = sessionExists ? tmuxWindowNames(sessionName) : []
        let workingDirectory = cliWorkingDirectoryURL()
        let configuredRoot = selectedProduct?.rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directoryStatus = configuredRoot.isEmpty || configuredRoot == workingDirectory.path
            ? "使用产品根目录".L()
            : "产品根目录不可用，实际已回退到 ".L() + "\(workingDirectory.path)"
        let agentLines = agents.map { agent in
            let windowName = terminalWorkspaceWindowName(for: agent)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let status = windowNames.contains(windowName) ? "已连接".L() : "待创建".L()
            return """
            - \(agent.displayName)：\(status)
              \("窗口名：".L())\(windowName)
              \("执行目录：".L())\(executionDirectory.path)
            """
        }.joined(separator: "\n")

        return """
        \("运维详情：真实终端工作区".L())
        \("产品：".L())\(selectedProduct?.name ?? "当前产品")
        \("终端工具：".L())\(tmuxPath ?? "未找到终端工具")
        \("会话名：".L())\(sessionName)
        \("会话状态：".L())\(sessionExists ? "已存在" : "未创建")
        \("工作目录：".L())\(workingDirectory.path)
        \("目录状态：".L())\(directoryStatus)
        \("已有窗口：".L())\(windowNames.isEmpty ? "无" : windowNames.joined(separator: "、"))

        \("员工终端窗口详情：".L())
        \(agentLines.isEmpty ? "- 当前产品没有可执行员工。" : agentLines)
        """
    }

    public func terminalWorkspaceHealthAuditText() -> String {
        terminalWorkspaceHealthAuditText(using: currentTerminalWorkspaceHealthSnapshot())
    }

    private func terminalWorkspaceHealthAuditText(using snapshot: TerminalWorkspaceHealthSnapshot) -> String {
        let missingLines = snapshot.missingAgents.map { "- " + "\($0.displayName)" + "：终端席位待创建".L() }.joined(separator: "\n")
        let toolStatus = snapshot.isKnown ? (snapshot.tmuxReady ? "已就绪".L() : "未找到".L()) : "待巡检".L()
        let sessionStatus = snapshot.isKnown ? (snapshot.sessionExists ? "已存在".L() : "未启动".L()) : "待巡检".L()
        let controlStatus = snapshot.isKnown ? (snapshot.hasControlWindow ? "已连接".L() : "未连接".L()) : "待巡检".L()

        return """
        \("持久终端可用性巡检：".L())\(snapshot.status.title)
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("主要待处理：".L())\(snapshot.primaryIssue)
        \("终端工具：".L())\(toolStatus)
        \("工作区会话：".L())\(sessionStatus)
        \("控制窗口：".L())\(controlStatus)
        \("员工席位：".L())\(snapshot.connectedAgentCount)/\(snapshot.totalAgentCount)

        \("待处理席位：".L())
        \(missingLines.isEmpty ? "- 无".L() : missingLines)

        \("说明：".L())
        \("本巡检只读取本机终端工作区状态，不启动模型任务、不创建作业档案、不修改员工状态。若存在待创建席位，请先使用「启动真实终端工作区」补齐，再从 OPC 运行入口发起任务。".L())
        """
    }

    @discardableResult
    public func runTerminalWorkspaceHealthAuditForSelectedProduct() -> VerificationStatus {
        let snapshot = refreshTerminalWorkspaceHealthSnapshot()
        let status = snapshot.status
        let report = terminalWorkspaceHealthAuditText(using: snapshot)
        verifications.insert(
            VerificationRecord(productID: selectedProductID, status: status, title: "持久终端可用性巡检", detail: report),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: status == .passed ? .statusChanged : .risk, title: "持久终端可用性巡检完成", detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)", agentID: ctoID)
        saveSnapshot()
        return status
    }

    private struct TerminalWorkspaceHealthSnapshot {
        var productID: UUID
        var isKnown: Bool
        var tmuxReady: Bool
        var sessionExists: Bool
        var hasControlWindow: Bool
        var connectedAgentCount: Int
        var totalAgentCount: Int
        var missingAgents: [CompanyAgent]
        var status: VerificationStatus
        var primaryIssue: String
    }

    private func currentTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        if let cachedTerminalWorkspaceHealthSnapshot,
           cachedTerminalWorkspaceHealthSnapshot.productID == selectedProductID {
            return cachedTerminalWorkspaceHealthSnapshot
        }
        return terminalWorkspaceHealthUnknownSnapshot()
    }

    @discardableResult
    private func refreshTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let snapshot = readTerminalWorkspaceHealthSnapshot()
        cachedTerminalWorkspaceHealthSnapshot = snapshot
        return snapshot
    }

    private func terminalWorkspaceHealthUnknownSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let agents = executableAgents
        return TerminalWorkspaceHealthSnapshot(
            productID: selectedProductID,
            isKnown: false,
            tmuxReady: false,
            sessionExists: false,
            hasControlWindow: false,
            connectedAgentCount: 0,
            totalAgentCount: agents.count,
            missingAgents: agents,
            status: .warning,
            primaryIssue: "尚未巡检"
        )
    }

    private func readTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let agents = executableAgents
        let sessionName = terminalWorkspaceSessionName()
        let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux")
        let sessionExists = tmuxPath.map { tmuxSessionExists(sessionName, tmuxPath: $0) } ?? false
        let windowNames = sessionExists ? Set(tmuxWindowNames(sessionName, tmuxPath: tmuxPath)) : []
        let hasControlWindow = windowNames.contains("control")
        let missingAgents = agents.filter { !windowNames.contains(terminalWorkspaceWindowName(for: $0)) }
        let status = terminalWorkspaceHealthStatus(tmuxReady: tmuxPath != nil, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgents.count)
        return TerminalWorkspaceHealthSnapshot(
            productID: selectedProductID,
            isKnown: true,
            tmuxReady: tmuxPath != nil,
            sessionExists: sessionExists,
            hasControlWindow: hasControlWindow,
            connectedAgentCount: agents.count - missingAgents.count,
            totalAgentCount: agents.count,
            missingAgents: missingAgents,
            status: status,
            primaryIssue: terminalWorkspaceHealthPrimaryIssue(tmuxReady: tmuxPath != nil, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgents.count)
        )
    }

    private func terminalWorkspaceArchitectureCheck() -> MultiAgentArchitectureCheck {
        let snapshot = currentTerminalWorkspaceHealthSnapshot()
        let status: ArchitectureCheckStatus
        switch snapshot.status {
        case .passed:
            status = .passed
        case .warning:
            status = .warning
        case .failed:
            status = .failed
        }
        return MultiAgentArchitectureCheck(
            id: "terminal-workspace",
            title: "持久终端可用性",
            status: status,
            detail: snapshot.isKnown
                ? "主要待处理：\(snapshot.primaryIssue)。终端工具 \(snapshot.tmuxReady ? "已就绪" : "未找到")，工作区会话 \(snapshot.sessionExists ? "已存在" : "未启动")，控制窗口 \(snapshot.hasControlWindow ? "已连接" : "未连接")，员工席位 \(snapshot.connectedAgentCount)/\(snapshot.totalAgentCount)。"
                : "主要待处理：尚未巡检。请运行「持久终端可用性巡检」或启动真实终端工作区后复查；当前不会在界面刷新时读取终端状态。"
        )
    }

    private func terminalWorkspaceHealthStatus(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> VerificationStatus {
        guard tmuxReady else { return .failed }
        guard sessionExists, hasControlWindow, missingAgentCount == 0 else { return .warning }
        return .passed
    }

    public func terminalWorkspaceHealthStatusForTesting(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> VerificationStatus {
        terminalWorkspaceHealthStatus(tmuxReady: tmuxReady, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgentCount)
    }

    private func terminalWorkspaceHealthPrimaryIssue(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> String {
        if !tmuxReady { return "终端工具未找到" }
        if !sessionExists { return "工作区会话未启动" }
        if !hasControlWindow { return "控制窗口未连接" }
        if missingAgentCount > 0 { return "\(missingAgentCount) 个员工席位待创建" }
        return "无"
    }

    public func startTerminalWorkspaceForSelectedProduct() {
        ensureRuntimeSessionsForSelectedProduct()
        syncSelectedProductAgentWorkspaces()
        ensureCLIWorktreeIsolationForSelectedProduct()

        let sessionName = terminalWorkspaceSessionName()
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else {
            let report = terminalWorkspacePlanText()
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .warning, title: "真实终端工作区", detail: report), at: 0)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
            appendEvent(kind: .risk, title: "真实终端工作区未启动", detail: "未找到终端工具，请安装或配置终端工具后重试。", agentID: ctoID)
            refreshTerminalWorkspaceHealthSnapshot()
            saveSnapshot()
            return
        }

        let workingDirectory = cliWorkingDirectoryURL()
        if !tmuxSessionExists(sessionName, tmuxPath: tmuxPath) {
            let result = runLocalProcess(
                executable: tmuxPath,
                arguments: ["new-session", "-d", "-s", sessionName, "-n", "control", "-c", workingDirectory.path],
                workingDirectory: workingDirectory
            )
            guard result.exitCode == 0 else {
                appendEvent(kind: .risk, title: "真实终端工作区启动失败", detail: result.output, agentID: ctoID)
                saveSnapshot()
                return
            }
        }

        var windowNames = Set(tmuxWindowNames(sessionName, tmuxPath: tmuxPath))
        for agent in executableAgents {
            let windowName = terminalWorkspaceWindowName(for: agent)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            var didCreateWindow = false
            if !windowNames.contains(windowName) {
                let createWindowResult = runLocalProcess(
                    executable: tmuxPath,
                    arguments: ["new-window", "-d", "-t", sessionName, "-n", windowName, "-c", executionDirectory.path],
                    workingDirectory: workingDirectory
                )
                if createWindowResult.exitCode == 0 {
                    didCreateWindow = true
                    windowNames.insert(windowName)
                }
            }
            guard didCreateWindow else { continue }
            let intro = terminalWorkspaceIntroCommand(for: agent, executionDirectory: executionDirectory)
            _ = runLocalProcess(
                executable: tmuxPath,
                arguments: ["send-keys", "-t", "\(sessionName):\(windowName)", intro, "C-m"],
                workingDirectory: workingDirectory
            )
            let capture = runLocalProcess(
                executable: tmuxPath,
                arguments: ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-80"],
                workingDirectory: workingDirectory
            )
            if !capture.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendTerminalLog("\n[OPC 真实终端工作区]\n员工终端席位已创建。\n\(capture.output)\n", for: agent.id)
            }
        }

        let report = terminalWorkspacePlanText()
        verifications.insert(VerificationRecord(productID: selectedProductID, status: .passed, title: "真实终端工作区", detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .artifactCreated, title: "真实终端工作区已启动", detail: "\(executableAgents.count) 个员工终端席位", agentID: ctoID)
        refreshTerminalWorkspaceHealthSnapshot()
        saveSnapshot()
    }

    public func refreshTerminalWorkspaceLogsForSelectedProduct() {
        let sessionName = terminalWorkspaceSessionName()
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux"),
              tmuxSessionExists(sessionName, tmuxPath: tmuxPath)
        else {
            let report = terminalWorkspacePlanText()
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .warning, title: "真实终端日志刷新", detail: report), at: 0)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "真实终端日志刷新未完成：还没有可捕获的真实终端工作区。\n\n\(report)"))
            appendEvent(kind: .risk, title: "真实终端工作区未找到", detail: "当前产品还没有可捕获的真实终端工作区。", agentID: ctoID)
            saveSnapshot()
            return
        }

        let windowNames = Set(tmuxWindowNames(sessionName, tmuxPath: tmuxPath))
        var capturedCount = 0
        for agent in executableAgents {
            let windowName = terminalWorkspaceWindowName(for: agent)
            guard windowNames.contains(windowName) else { continue }
            let capture = runLocalProcess(
                executable: tmuxPath,
                arguments: ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-120"],
                workingDirectory: cliWorkingDirectoryURL()
            )
            let output = capture.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard capture.exitCode == 0, !output.isEmpty else { continue }
            capturedCount += 1
            appendTerminalLog("\n[OPC 真实终端日志刷新]\n员工终端席位已刷新。\n\(output)\n", for: agent.id)
        }

        let report = """
        \("真实终端日志刷新：".L())\(capturedCount > 0 ? "完成" : "没有可写入内容")
        \("产品：".L())\(selectedProduct?.name ?? "当前产品")
        \("捕获席位：".L())\(capturedCount)/\(executableAgents.count)
        """
        verifications.insert(VerificationRecord(productID: selectedProductID, status: capturedCount > 0 ? .passed : .warning, title: "真实终端日志刷新".L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: capturedCount > 0 ? .artifactCreated : .risk, title: "真实终端日志刷新完成".L(), detail: "捕获 " + "\(capturedCount)" + " 个员工终端席位", agentID: ctoID)
        saveSnapshot()
    }

    public func terminalWorkspaceIntroCommandPreviewForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        return terminalWorkspaceIntroCommand(for: agent, executionDirectory: cliExecutionDirectoryURL(for: agent))
    }

    public func terminalWorkspaceSessionNameForTesting() -> String {
        terminalWorkspaceSessionName()
    }

    public func terminalWorkspaceWindowNameForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        return terminalWorkspaceWindowName(for: agent)
    }

    public func persistentTerminalTargetPreviewForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }),
              let target = preparePersistentTerminalTarget(for: agent)
        else { return "未接入".L() }
        return "\(target.sessionName):\(target.windowName)"
    }

    public func persistentTerminalTurnObservationPreviewForTesting(capture: String, startMarker: String, endMarker: String, command: String) -> String {
        let profile = CLIInteractionProfileCatalog.profile(forCommand: command)
        let snapshot = persistentTerminalTurnSnapshot(from: capture, startMarker: startMarker, endMarker: endMarker, profile: profile)
        let resultLine = snapshot.result.map { "结果：退出码 " + "\($0.exitCode)" } ?? "结果：未完成".L()
        let phaseLine = snapshot.observation.map { "状态：".L() + "\($0.reasonTitle)" } ?? "状态：未识别".L()
        let sessionLine = snapshot.observation?.sessionID == nil ? "会话编号：未识别".L() : "会话编号：已识别".L()
        return "\(resultLine)\n\(phaseLine)\n\(sessionLine)"
    }

    public func persistentTerminalTurnClosedPreviewForTesting(capture: String, startMarker: String, endMarker: String) -> Bool {
        persistentTerminalResult(from: capture, startMarker: startMarker, endMarker: endMarker) != nil
    }

    public func persistentTerminalTimeoutRunForTesting(agentID: UUID, command: [String], timeoutSeconds: TimeInterval) async -> CommandExecutionResult? {
        guard let agent = agents.first(where: { $0.id == agentID }),
              let target = preparePersistentTerminalTarget(for: agent)
        else { return nil }
        return await runPersistentTerminalCommand(
            command: command,
            executionDirectory: cliExecutionDirectoryURL(for: agent),
            target: target,
            timeoutSeconds: timeoutSeconds,
            onOutput: { _ in }
        )
    }

    public func persistentTerminalSendInputLineForTesting(agentID: UUID, text: String) async -> CommandExecutionResult? {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return nil }
        return await sendPersistentTerminalInputLine(text, to: agent)
    }

    public func persistentTerminalREPLTurnForTesting(agentID: UUID, text: String, timeoutSeconds: TimeInterval) async -> PersistentTerminalREPLTurnResult? {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return nil }
        return await runPersistentTerminalREPLTurn(text, to: agent, timeoutSeconds: timeoutSeconds)
    }

    public struct CLIRecoveryAdviceEntry: Sendable, Hashable {
        public var agentID: UUID
        public var displayName: String
        public var phaseTitle: String
        public var actionTitle: String
        public var operatorHint: String?
        public var canManualRetry: Bool
    }

    public func cliRecoveryAdvice(for agentID: UUID) -> CLIRecoveryAdviceEntry? {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return nil }
        let session = runtimeSessions[agentID]
        let phase = session?.cliInteractionPhase
        let action = session?.cliInteractionRecoveryAction
            ?? phase.map { CLIInteractionStateMachine.recoveryAction(for: $0) }
            ?? .noAction
        let phaseTitle = session?.cliInteractionReason ?? "尚未观察".L()
        let canRetry = (phase == .transientFailure) && (action == .waitAndRetryLater)
        return CLIRecoveryAdviceEntry(
            agentID: agentID,
            displayName: agent.displayName,
            phaseTitle: phaseTitle,
            actionTitle: action.title,
            operatorHint: session?.cliInteractionOperatorHint ?? session?.cliInteractionRecoveryHint ?? action.operatorHint,
            canManualRetry: canRetry
        )
    }

    /// 终端大厅员工卡顶部「健康徽章」紧凑视觉数据（视觉层专用）。
    ///
    /// 与 `cliRecoveryAdvice(for:)` 拆开的原因：后者返回完整恢复建议字符串供「员工恢复建议」
    /// 文本面板使用；卡顶徽章只需要 4 字以内中文标题 + 严重度配色 + 完整 detail 给 tooltip。
    /// 默认情况下不显示徽章（避免噪音）：
    /// - 员工不是命令行来源 / 没有运行会话 / phase 未观察 / phase = .unknown / .ready / .completedTurn → 返回 nil
    /// - phase = .awaitingResponse → info 蓝徽章
    /// - phase = .busy → warning 黄徽章
    /// - phase = .authenticationBlocked / .transientFailure → danger 红徽章
    ///
    /// 这样默认所有员工都不显示徽章；只有真出现需要技术负责人关注的状态时徽章才浮现，
    /// 符合「老板视角优先 + 员工像人不像接口」准则——没事的时候不打扰。
    public func terminalAgentCardHealthBadge(for agentID: UUID) -> TerminalAgentCardHealthBadge? {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return nil }
        guard agent.backend.type == .subscriptionCLI else { return nil }
        guard let session = runtimeSessions[agentID], let phase = session.cliInteractionPhase else { return nil }

        let title: String
        let severity: TerminalAgentCardHealthBadge.Severity
        switch phase {
        case .unknown, .ready, .completedTurn:
            return nil
        case .awaitingResponse:
            title = "等待回复".L()
            severity = .info
        case .busy:
            title = "忙碌中".L()
            severity = .warning
        case .authenticationBlocked:
            title = "授权异常".L()
            severity = .danger
        case .transientFailure:
            title = "临时异常".L()
            severity = .danger
        }

        let action = session.cliInteractionRecoveryAction
            ?? CLIInteractionStateMachine.recoveryAction(for: phase)
        let hint = session.cliInteractionOperatorHint
            ?? session.cliInteractionRecoveryHint
            ?? action.operatorHint
        let detail: String? = hint.map { "\(action.title)：\($0)" }
        return TerminalAgentCardHealthBadge(title: title, severity: severity, detail: detail)
    }

    public func cliRecoveryAdvicesForSelectedProduct() -> [CLIRecoveryAdviceEntry] {
        selectedProductAgents
            .filter { $0.role != .boss }
            .compactMap { cliRecoveryAdvice(for: $0.id) }
    }

    public func cliRecoveryAdviceSummaryText() -> String {
        let advices = cliRecoveryAdvicesForSelectedProduct()
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        guard !advices.isEmpty else {
            return """
            \("员工恢复建议：暂无可执行员工".L())
            \("产品：".L())\(productLabel)
            \("说明：当前产品没有可观察的命令行员工。请先配置员工或启动一次任务后再来查看建议。".L())
            """
        }
        let lines = advices.map { entry in
            let hint = entry.operatorHint ?? "暂无额外建议。"
            let retryHint = entry.canManualRetry ? "可使用「手动重试一次」入口尝试一次。" : "暂不开放手动重试。"
            return "- \(entry.displayName)：状态 \(entry.phaseTitle) · 建议 \(entry.actionTitle) · \(hint) \(retryHint)"
        }
        return """
        \("员工恢复建议".L())
        \("产品：".L())\(productLabel)
        \(lines.joined(separator: "\n"))

        \("说明：本面板只显示最近一次状态观察建议，OPC 不会自动向命令行追加未确认的下一轮输入；只有在「临时异常」时才提供受控的单次手动重试入口。".L())
        """
    }

    public struct CLIRecoveryRetryReport: Sendable {
        public var success: Bool
        public var reason: String
    }

    @discardableResult
    public func manualRetryTransientForAgent(agentID: UUID) -> CLIRecoveryRetryReport {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return CLIRecoveryRetryReport(success: false, reason: "未找到该员工，无法发起手动重试。".L())
        }
        guard agent.role != .boss else {
            return CLIRecoveryRetryReport(success: false, reason: "老板视角不参与命令行手动重试。".L())
        }
        guard let advice = cliRecoveryAdvice(for: agentID), advice.canManualRetry else {
            let phaseTitle = runtimeSessions[agentID]?.cliInteractionReason ?? "尚未观察".L()
            return CLIRecoveryRetryReport(success: false, reason: "当前状态为「".L() + "\(phaseTitle)" + "」，不在「临时异常」范围内，已拒绝手动重试。".L())
        }
        guard !isRunning(agentID: agentID) else {
            return CLIRecoveryRetryReport(success: false, reason: "\(agent.displayName)" + " 当前正在运行任务，请等待完成后再发起手动重试。".L())
        }
        restartAgentSession(agentID: agentID, reason: "技术负责人针对临时异常手动发起一次重开。".L())
        return CLIRecoveryRetryReport(success: true, reason: "已为 ".L() + "\(agent.displayName)" + " 发起一次受控的手动重试。".L())
    }

    public struct ManualREPLTurnReport: Sendable {
        public var summary: String
        public var outputPreview: String
        public var timedOut: Bool
        public var rejected: Bool
        public var rejectionReason: String?

        public init(summary: String, outputPreview: String, timedOut: Bool, rejected: Bool, rejectionReason: String? = nil) {
            self.summary = summary
            self.outputPreview = outputPreview
            self.timedOut = timedOut
            self.rejected = rejected
            self.rejectionReason = rejectionReason
        }
    }

    public struct InternalAutoInteractionLoopReport: Sendable {
        public var agentID: UUID?
        public var productID: UUID
        public var execution: CLIAutoInteractionLoopExecutionReport
        public var rejected: Bool
        public var rejectionReason: String?

        public init(
            agentID: UUID?,
            productID: UUID,
            execution: CLIAutoInteractionLoopExecutionReport,
            rejected: Bool,
            rejectionReason: String? = nil
        ) {
            self.agentID = agentID
            self.productID = productID
            self.execution = execution
            self.rejected = rejected
            self.rejectionReason = rejectionReason
        }

        public var summaryText: String {
            var lines = [
                "内部自动交互循环：".L() + "\(rejected ? "已拒绝" : execution.finalState.phase.title)",
                "发送轮次：".L() + "\(execution.sentTurnCount)" + "/" + "\(execution.finalState.maxTurns)",
                "停止原因：".L() + "\(execution.finalState.stopReason.title)"
            ]
            if let rejectionReason {
                lines.append("拒绝原因：".L() + "\(rejectionReason)")
            }
            lines.append("说明：当前仅为技术负责人维护侧内部协调，不调用真实命令行、不创建作业档案、不写老板聊天。".L())
            return lines.joined(separator: "\n")
        }
    }

    public struct TerminalAutoInteractionLoopReport: Sendable {
        public var agentID: UUID?
        public var productID: UUID
        public var usedRealTerminal: Bool
        public var terminalReadinessAudit: String?
        public var internalReport: InternalAutoInteractionLoopReport

        public init(
            agentID: UUID?,
            productID: UUID,
            usedRealTerminal: Bool,
            internalReport: InternalAutoInteractionLoopReport,
            terminalReadinessAudit: String? = nil
        ) {
            self.agentID = agentID
            self.productID = productID
            self.usedRealTerminal = usedRealTerminal
            self.internalReport = internalReport
            self.terminalReadinessAudit = terminalReadinessAudit
        }

        public var rejected: Bool {
            internalReport.rejected
        }

        public var rejectionReason: String? {
            internalReport.rejectionReason
        }

        public var summaryText: String {
            let state = internalReport.execution.finalState
            var lines = [
                "真实终端自动交互循环：".L() + "\(rejected ? "已拒绝" : state.phase.title)",
                "发送链路：".L() + "\(usedRealTerminal ? "真实终端席位" : "注入发送闭包")",
                "已发送轮次：".L() + "\(internalReport.execution.sentTurnCount)" + "/" + "\(state.maxTurns)",
                "停止原因：".L() + "\(state.stopReason.title)",
                "操作建议：".L() + "\(state.stopReason.operatorHint)"
            ]
            if usedRealTerminal, let terminalReadinessAudit {
                lines.append(terminalReadinessAudit)
            }
            if let rejectionReason {
                lines.append("拒绝原因：".L() + "\(rejectionReason)")
            }
            lines.append("说明：仅在技术负责人维护区显式启动；不创建命令行作业档案、不写老板聊天、不绕过交付验收。".L())
            return lines.joined(separator: "\n")
        }
    }

    @discardableResult
    public func runManualREPLTurnForSelectedAgent(text: String, timeoutSeconds: TimeInterval = 8) async -> ManualREPLTurnReport {
        if text.contains(where: { $0.isNewline }) {
            return ManualREPLTurnReport(summary: "未发送".L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L())
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ManualREPLTurnReport(summary: "未发送".L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "请先输入要发送给员工长期席位的一行内容。".L())
        }
        guard let agent = selectedAgent, agent.role != .boss else {
            return ManualREPLTurnReport(summary: "未发送".L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "请先在员工列表选中一名要交互的员工，老板视角不参与手动交互轮次。".L())
        }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            return ManualREPLTurnReport(summary: "未发送".L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "该员工还未加入当前产品团队，请先在产品详情里加入团队。".L())
        }
        guard let result = await runPersistentTerminalREPLTurn(cleaned, to: agent, timeoutSeconds: max(timeoutSeconds, 0.1)) else {
            return ManualREPLTurnReport(summary: "未发送".L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "未找到可用的真实终端席位。请先在维护区点击「启动真实终端工作区」并确认终端工具已就绪。".L())
        }
        let preview = String(result.output.prefix(240))
        if result.exitCode == 126 || result.exitCode == 127 {
            return ManualREPLTurnReport(summary: result.observation.reasonTitle, outputPreview: "", timedOut: false, rejected: true, rejectionReason: result.output)
        }
        let summary = result.timedOut ? "等待超时，未中断终端席位".L() : result.observation.reasonTitle
        return ManualREPLTurnReport(summary: summary, outputPreview: preview, timedOut: result.timedOut, rejected: false, rejectionReason: nil)
    }

    public func runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: String,
        maxTurns: Int,
        nextInput: CLIAutoInteractionLoopExecutor.InputProvider,
        runTurn: CLIAutoInteractionLoopExecutor.TurnSender
    ) async -> InternalAutoInteractionLoopReport {
        let productID = selectedProductID
        func rejectedReport(reason: String, stopReason: CLIAutoInteractionLoopStopReason) -> InternalAutoInteractionLoopReport {
            let state = CLIAutoInteractionLoopState(
                taskContext: taskContext.trimmingCharacters(in: .whitespacesAndNewlines),
                maxTurns: max(maxTurns, 0),
                phase: .rejected,
                stopReason: stopReason
            )
            return InternalAutoInteractionLoopReport(
                agentID: selectedAgent?.id,
                productID: productID,
                execution: CLIAutoInteractionLoopExecutionReport(finalState: state, turnReports: []),
                rejected: true,
                rejectionReason: reason
            )
        }

        guard let agent = selectedAgent, agent.role != .boss else {
            return rejectedReport(reason: "请选择当前产品团队中的员工；老板视角不参与内部自动交互循环。".L(), stopReason: .missingTaskContext)
        }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            return rejectedReport(reason: "该员工还未加入当前产品团队，已拒绝内部自动交互循环。".L(), stopReason: .missingTaskContext)
        }
        guard !taskContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let execution = await CLIAutoInteractionLoopExecutor.run(
                taskContext: taskContext,
                maxTurns: maxTurns,
                nextInput: nextInput,
                send: runTurn
            )
            return InternalAutoInteractionLoopReport(
                agentID: agent.id,
                productID: productID,
                execution: execution,
                rejected: true,
                rejectionReason: "请先绑定技术负责人任务上下文，再启动内部自动交互循环。".L()
            )
        }

        let execution = await CLIAutoInteractionLoopExecutor.run(
            taskContext: taskContext,
            maxTurns: maxTurns,
            nextInput: nextInput,
            send: runTurn
        )
        return InternalAutoInteractionLoopReport(
            agentID: agent.id,
            productID: productID,
            execution: execution,
            rejected: execution.finalState.phase == .rejected,
            rejectionReason: execution.finalState.phase == .rejected ? execution.finalState.stopReason.title : nil
        )
    }

    @discardableResult
    public func runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: String,
        maxTurns: Int = 3,
        timeoutSeconds: TimeInterval = 8,
        turnRunner: CLIAutoInteractionLoopExecutor.TurnSender? = nil
    ) async -> TerminalAutoInteractionLoopReport {
        let productID = selectedProductID
        let agent = selectedAgent
        let usedRealTerminal = turnRunner == nil
        let cleanedContext = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
        var preflightAuditLine: String?
        if usedRealTerminal,
           let agent,
           agent.role != .boss,
           selectedProductAgents.contains(where: { $0.id == agent.id }),
           !cleanedContext.isEmpty,
           maxTurns >= 1,
           maxTurns <= CLIAutoInteractionLoopGate.hardTurnLimit {
            let audit = terminalAutoInteractionReadinessAudit(for: agent)
            preflightAuditLine = audit.auditLine
            appendTerminalAutoInteractionAuditLog(agent: agent, audit: audit)
            recordTerminalAutoInteractionAuditVerification(agent: agent, audit: audit)
            if let rejectionReason = audit.rejectionReason {
                let state = CLIAutoInteractionLoopState(
                    taskContext: cleanedContext,
                    maxTurns: maxTurns,
                    phase: .rejected,
                    stopReason: .transientFailure
                )
                let internalReport = InternalAutoInteractionLoopReport(
                    agentID: agent.id,
                    productID: productID,
                    execution: CLIAutoInteractionLoopExecutionReport(finalState: state, turnReports: []),
                    rejected: true,
                    rejectionReason: rejectionReason
                )
                return TerminalAutoInteractionLoopReport(
                    agentID: agent.id,
                    productID: productID,
                    usedRealTerminal: true,
                    internalReport: internalReport,
                    terminalReadinessAudit: audit.auditLine
                )
            }
        }
        let sender: CLIAutoInteractionLoopExecutor.TurnSender
        if let turnRunner {
            sender = turnRunner
        } else {
            sender = { [self] text in
                guard let agent else {
                    return CLIAutoInteractionTurnObservation(
                        observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "未选中员工".L())
                    )
                }
                guard let result = await runPersistentTerminalREPLTurn(text, to: agent, timeoutSeconds: max(timeoutSeconds, 0.1), logSource: .autoLoop) else {
                    return CLIAutoInteractionTurnObservation(
                        observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "终端席位不可用".L())
                    )
                }
                let observation: CLIInteractionObservation
                switch result.observation.phase {
                case .unknown:
                    observation = CLIInteractionObservation(phase: .transientFailure, reasonTitle: result.observation.reasonTitle)
                default:
                    observation = result.observation
                }
                return CLIAutoInteractionTurnObservation(observation: observation, timedOut: result.timedOut)
            }
        }

        let report = await runInternalAutoInteractionLoopForSelectedAgent(
            taskContext: taskContext,
            maxTurns: maxTurns,
            nextInput: { state in
                CLIAutoInteractionGeneratedInput(text: Self.terminalAutoInteractionNextInput(taskContext: taskContext, state: state))
            },
            runTurn: sender
        )
        if usedRealTerminal, let agent {
            recordTerminalAutoInteractionStopAuditIfNeeded(
                agent: agent,
                finalState: report.execution.finalState
            )
        }
        return TerminalAutoInteractionLoopReport(
            agentID: agent?.id,
            productID: productID,
            usedRealTerminal: usedRealTerminal,
            internalReport: report,
            terminalReadinessAudit: preflightAuditLine
        )
    }

    public func terminalAutoInteractionNextInputPreviewForTesting(taskContext: String, sentTurns: Int = 0) -> String {
        let state = CLIAutoInteractionLoopState(taskContext: taskContext, maxTurns: 8, sentInputs: Array(repeating: "已发送".L(), count: max(sentTurns, 0)))
        return Self.terminalAutoInteractionNextInput(taskContext: taskContext, state: state)
    }

    nonisolated private static func terminalAutoInteractionNextInput(taskContext: String, state: CLIAutoInteractionLoopState) -> String {
        let normalized = taskContext
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(normalized.prefix(140))
        let context = clipped.isEmpty ? "当前技术负责人任务".L() : clipped
        return "第".L() + "\(state.sentInputs.count + 1)" + "轮：围绕「".L() + "\(context)" + "」继续执行当前任务，只回复当前进展、阻塞和下一步。".L()
    }

    struct TerminalAutoInteractionReadinessAudit: Sendable {
        var rejectionReason: String?
        var auditLine: String
    }

    func terminalAutoInteractionReadinessAuditForTesting(for agent: CompanyAgent) -> TerminalAutoInteractionReadinessAudit {
        terminalAutoInteractionReadinessAudit(for: agent)
    }

    private func terminalAutoInteractionReadinessAudit(for agent: CompanyAgent) -> TerminalAutoInteractionReadinessAudit {
        let profile = CLIAgentCommandBuilder.interactionProfile(for: agent)
        let protocolName = profile?.displayName ?? "订阅制命令行".L()

        guard agent.backend.type == .subscriptionCLI else {
            return readinessAuditFailed(
                reason: "该员工不是订阅制命令行员工，真实终端自动交互循环已拒绝。".L(),
                detail: "未匹配订阅制命令行来源".L()
            )
        }
        guard currentRuntimeCapability(for: agent) == .persistentProtocol else {
            return readinessAuditFailed(
                reason: "该员工来源不支持持续交互，真实终端自动交互循环已拒绝。".L(),
                detail: "员工来源不支持持续交互".L()
            )
        }
        guard let profile, !profile.replReadySignals.isEmpty else {
            return readinessAuditFailed(
                reason: "该员工命令行工具没有配置专用就绪提示，真实终端自动交互循环已拒绝。".L(),
                detail: "\(protocolName)" + " 缺少专用就绪提示配置".L()
            )
        }
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else {
            return readinessAuditFailed(
                reason: "未找到本机终端控制工具，请先完成终端工具安装或配置。".L(),
                detail: "未找到本机终端控制工具".L()
            )
        }
        let sessionName = terminalWorkspaceSessionName()
        let windowName = terminalWorkspaceWindowName(for: agent)
        guard tmuxSessionExists(sessionName, tmuxPath: tmuxPath) else {
            return readinessAuditFailed(
                reason: "请先在维护区点击「启动真实终端工作区」，再启动真实终端自动交互循环。".L(),
                detail: "真实终端工作区尚未启动".L()
            )
        }
        guard tmuxWindowNames(sessionName, tmuxPath: tmuxPath).contains(windowName) else {
            return readinessAuditFailed(
                reason: "当前员工真实终端席位还未创建，请先启动真实终端工作区并确认席位齐全。".L(),
                detail: "员工真实终端席位未创建".L()
            )
        }
        let capture = runLocalProcess(
            executable: tmuxPath,
            arguments: ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"],
            workingDirectory: cliWorkingDirectoryURL()
        )
        guard capture.exitCode == 0 else {
            return readinessAuditFailed(
                reason: "读取员工真实终端席位失败，请先运行持久终端可用性巡检。".L(),
                detail: "读取员工真实终端席位失败".L()
            )
        }
        guard profile.endsWithReplReadyPrompt(capture.output) else {
            return readinessAuditFailed(
                reason: "该员工终端席位最近一行不是 ".L() + "\(profile.displayName)" + " 的专用就绪提示，已拒绝自动发送。".L(),
                detail: "终端最近一行未命中 ".L() + "\(profile.displayName)" + " 专用就绪提示".L()
            )
        }
        return TerminalAutoInteractionReadinessAudit(
            rejectionReason: nil,
            auditLine: "就绪校验：最近一行已确认 ".L() + "\(profile.displayName)" + " 的专用就绪提示。".L()
        )
    }

    private func readinessAuditFailed(reason: String, detail: String) -> TerminalAutoInteractionReadinessAudit {
        TerminalAutoInteractionReadinessAudit(
            rejectionReason: reason,
            auditLine: "就绪校验：未确认最近专用就绪提示，已拒绝自动发送。原因：".L() + "\(detail)" + "。"
        )
    }

    private func appendTerminalAutoInteractionAuditLog(agent: CompanyAgent, audit: TerminalAutoInteractionReadinessAudit) {
        appendTerminalLog(
            "\n[OPC 自动循环就绪审计]\n".L() + "\(audit.auditLine)" + "\n",
            for: agent.id
        )
    }

    /// 把真实终端自动循环 preflight 审计结果以中文结构化形式写入产品级验证记录，
    /// 便于技术负责人维护侧通过架构体检和验证记录列表回看；
    /// 老板总控台和交付验收中心会过滤该维护记录，标题和正文也不包含底层参数、`rawValue` 或后端签名字段。
    private func recordTerminalAutoInteractionAuditVerification(agent: CompanyAgent, audit: TerminalAutoInteractionReadinessAudit) {
        let employee = "\(agent.displayName)（\(agent.role.title)）"
        let status: VerificationStatus = audit.rejectionReason == nil ? .passed : .warning
        var detailLines: [String] = [
            "员工：".L() + "\(employee)",
            audit.auditLine
        ]
        if let reason = audit.rejectionReason {
            detailLines.append("拒绝说明：".L() + "\(reason)")
        }
        detailLines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不创建命令行作业档案、不写老板聊天。".L())
        let record = VerificationRecord(
            productID: selectedProductID,
            status: status,
            title: Self.terminalAutoInteractionAuditTitle,
            detail: detailLines.joined(separator: "\n")
        )
        verifications.insert(record, at: 0)
    }

    public static let terminalAutoInteractionAuditTitle = "真实终端自动循环就绪审计".L()
    public static let terminalAutoInteractionStopAuditTitle = "真实终端自动循环停止审计".L()

    /// 当前产品最近一次真实终端自动循环 preflight 审计记录；技术负责人维护视图使用。
    public var selectedProductLatestTerminalAutoLoopReadinessAudit: VerificationRecord? {
        selectedProductRecentVerifications.first { $0.title == Self.terminalAutoInteractionAuditTitle }
    }

    /// 当前产品最近一次真实终端自动循环停止审计记录（授权异常 / 忙碌 / 临时异常 / 等待超时停止时写入）。
    public var selectedProductLatestTerminalAutoLoopStopAudit: VerificationRecord? {
        selectedProductRecentVerifications.first { $0.title == Self.terminalAutoInteractionStopAuditTitle }
    }

    /// 仅用于测试：直接调用停止审计写入 helper，便于在不真实跑 tmux 的情况下覆盖维护视图边界。
    public func recordTerminalAutoInteractionStopAuditForTesting(
        agent: CompanyAgent,
        finalState: CLIAutoInteractionLoopState
    ) {
        recordTerminalAutoInteractionStopAuditIfNeeded(agent: agent, finalState: finalState)
    }

    /// 把真实终端自动循环停止事件写成中文结构化维护记录（授权异常 / 忙碌 / 临时异常 / 等待超时）。
    /// 老板/交付视图不展示；技术负责人维护视图通过 `selectedProductMaintenanceVerifications` 读取。
    /// 同时追加一条 `[OPC 自动循环停止审计]` 终端日志，便于终端大厅复盘。
    private func recordTerminalAutoInteractionStopAuditIfNeeded(
        agent: CompanyAgent,
        finalState: CLIAutoInteractionLoopState
    ) {
        guard finalState.phase == .stopped else { return }
        let stopReason = finalState.stopReason
        let trackedReasons: [CLIAutoInteractionLoopStopReason] = [
            .authenticationBlocked,
            .busy,
            .transientFailure,
            .timedOut
        ]
        guard trackedReasons.contains(stopReason) else { return }

        let employee = "\(agent.displayName)（\(agent.role.title)）"
        let detailLines = [
            "员工：".L() + "\(employee)",
            "停止原因：".L() + "\(stopReason.title)",
            "操作建议：".L() + "\(stopReason.operatorHint)",
            "已发送轮次：".L() + "\(finalState.sentInputs.count)" + " / " + "\(finalState.maxTurns)",
            "说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不创建命令行作业档案、不写老板聊天。".L()
        ]
        let record = VerificationRecord(
            productID: selectedProductID,
            status: .warning,
            title: Self.terminalAutoInteractionStopAuditTitle,
            detail: detailLines.joined(separator: "\n")
        )
        verifications.insert(record, at: 0)
        appendTerminalLog(
            "\n[OPC 自动循环停止审计]\n停止原因：".L() + "\(stopReason.title)" + "。\n操作建议：".L() + "\(stopReason.operatorHint)" + "\n",
            for: agent.id
        )
    }

    /// 把最近一次真实终端自动循环 preflight 审计渲染成中文摘要行，
    /// 用于架构体检和终端大厅维护视图；不暴露底层参数。
    public func selectedProductTerminalAutoLoopReadinessAuditSummary() -> String {
        guard let record = selectedProductLatestTerminalAutoLoopReadinessAudit else {
            return "最近真实终端自动循环就绪审计：暂无记录。".L()
        }
        let firstAuditLine = record.detail
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.hasPrefix("就绪校验：".L()) } ?? "暂无就绪校验摘要".L()
        return "最近真实终端自动循环就绪审计：".L() + "\(record.status.title)" + " · " + "\(firstAuditLine)"
    }

    public struct CLIAutoInteractionLoopRunReport: Sendable {
        public var summary: String
        public var rejected: Bool
        public var rejectionReason: String?
        public var finalState: CLIAutoInteractionLoopState?
        public var attemptedTurns: Int
        public var sentTurns: Int

        public init(
            summary: String,
            rejected: Bool,
            rejectionReason: String? = nil,
            finalState: CLIAutoInteractionLoopState? = nil,
            attemptedTurns: Int = 0,
            sentTurns: Int = 0
        ) {
            self.summary = summary
            self.rejected = rejected
            self.rejectionReason = rejectionReason
            self.finalState = finalState
            self.attemptedTurns = attemptedTurns
            self.sentTurns = sentTurns
        }
    }

    public func persistentTerminalOutputDeltaPreviewForTesting(before baseline: String, after latest: String, inputEcho: String? = nil) -> String {
        persistentTerminalOutputDelta(before: baseline, after: latest, inputEcho: inputEcho)
    }

    public func cliWorktreeIsolationURL(for agent: CompanyAgent) -> URL {
        let suffix = String(agent.id.uuidString.prefix(8))
        return cliWorkingDirectoryURL().appendingPathComponent(".opc/worktrees/\(safeFileName(agent.displayName))-\(suffix)", isDirectory: true)
    }

    public func cliIsolationSourcePath(for agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return cliWorkingDirectoryURL().path
        }
        return cliIsolationSourceURL(for: agent).path
    }

    public func cliExecutionDirectoryPath(for agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return cliWorkingDirectoryURL().path
        }
        return cliExecutionDirectoryURL(for: agent).path
    }

    private func ensureCLIWorktreeIsolationForSelectedProduct() {
        let workingDirectory = cliWorkingDirectoryURL()
        let isGitRepository = FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(".git").path)
        let codeAgents = executableAgents.filter { requiresIsolatedCLIExecution($0) }
        for agent in codeAgents {
            let directory = cliWorktreeIsolationURL(for: agent)
            let sourceDirectory = cliIsolationSourceURL(for: agent)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if isGitRepository {
                    ensureGitIsolationSource(for: agent, sourceRoot: workingDirectory, sourceDirectory: sourceDirectory)
                } else if sourceRootLooksLikeProject(workingDirectory) {
                    try ensureDirectorySnapshotIsolationSource(sourceRoot: workingDirectory, sourceDirectory: sourceDirectory)
                }
                let marker = """
                \("# OPC 独立执行区".L())

                \("员工：".L())\(agent.displayName)
                \("角色：".L())\(agent.role.title)
                产品：\(selectedProduct?.name ?? "当前产品".L())
                \("产品工作目录：".L())\(workingDirectory.path)
                \("源码执行区：".L())\(sourceDirectory.path)
                隔离模式：\(isGitRepository ? "代码仓库独立工作区".L() : "源码快照隔离".L())

                \("这个目录用于代码类员工的隔离执行。并行实现产生的改动需要经过审查和验收后，才应合入主产品工作目录。".L())
                """
                try marker.write(to: directory.appendingPathComponent("WORKTREE.md"), atomically: true, encoding: .utf8)
            } catch {
                appendEvent(kind: .risk, title: "独立执行区创建失败", detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
            }
        }
    }

    public func productHealthSnapshotText() -> String {
        let product = selectedProduct
        let productTasks = selectedProductTasks
        let openTasks = productTasks.filter { ![.done, .canceled].contains($0.status) }
        let blockedTasks = productTasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }
        let doneTasks = productTasks.filter { $0.status == .done }
        let hasRules = product?.importReport?.ruleFiles.isEmpty == false
        let runningCount = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }.count
        let logCount = selectedProductAgents.filter { !currentProductTerminalLog(for: $0.id).isEmpty }.count

        var score = 62
        score += min(doneTasks.count * 4, 16)
        score += hasRules ? 8 : -6
        score += selectedProductAgents.count >= 6 ? 8 : 0
        score += logCount > 0 ? 6 : 0
        score -= min(blockedTasks.count * 10, 30)
        score = max(0, min(100, score))

        return """
        \("产品健康体检：".L())\(product?.name ?? "当前产品")
        \("健康分：".L())\(score) / 100

        \("指标：".L())
        \("- 产品员工：".L())\(selectedProductAgents.count)
        \("- 正在运行：".L())\(runningCount)
        \("- 总任务：".L())\(productTasks.count)
        \("- 未完成任务：".L())\(openTasks.count)
        \("- 已完成任务：".L())\(doneTasks.count)
        \("- 阻塞/失败/待批准：".L())\(blockedTasks.count)
        \("- 规则文件：".L())\(hasRules ? "已接入" : "未接入")
        \("- 有终端输出员工：".L())\(logCount)

        \("建议：".L())
        \(selectedProductAgents.count < 6 ? "1. 先补齐产品架构师、测试工程师、研究员。\n" : "")\(blockedTasks.isEmpty ? "1. 当前没有高优先级阻塞，继续推进执行台任务。\n" : "1. 先处理风险审批中的阻塞/失败/待批准任务。\n")\(hasRules ? "2. 已有项目规则，执行任务时继续优先读取规则文件。" : "2. 建议导入真实项目目录，让 OPC 接入规则/记忆文件。")
        """
    }

    public func generateHealthAudit() {
        let audit = productHealthSnapshotText()
        messages.append(ChatMessage(productID: selectedProductID, agentID: bossID, author: .system, text: audit))
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "请根据健康体检修正计划：\n\n".L() + "\(audit)"))
        appendEvent(kind: .artifactCreated, title: "产品健康体检已生成".L(), detail: "健康体检已写入老板和技术负责人对话。".L(), agentID: ctoID)
        saveSnapshot()
    }

    public func multiAgentArchitectureAuditText(refreshTerminalWorkspace: Bool = false) -> String {
        if refreshTerminalWorkspace {
            refreshTerminalWorkspaceHealthSnapshot()
        }
        let checks = selectedProductArchitectureChecks
        let lines = checks.map { check in
            "- \(check.title)：\(check.status.title)。\(check.detail)"
        }
        let failedCount = checks.filter { $0.status == .failed }.count
        let warningCount = checks.filter { $0.status == .warning }.count
        return """
        多员工架构体检：\(selectedProduct?.name ?? "当前产品".L())
        \("完成度：".L())\(selectedProductArchitectureCompletionScore)%

        \("检查项：".L())
        \(lines.joined(separator: "\n"))

        \(selectedProductTerminalAutoLoopReadinessAuditSummary())

        \("CTO 下一步：".L())
        \(failedCount > 0 ? "\("优先补齐 ".L())\(failedCount)\(" 个未闭合模块。".L())" : warningCount > 0 ? "继续加强 ".L() + "\(warningCount)" + " 个待加强模块。" : "主链路已闭合，进入真实命令行持续协作和独立执行区隔离。")
        """
    }

    public func runMultiAgentArchitectureAudit() {
        let report = multiAgentArchitectureAuditText(refreshTerminalWorkspace: true)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .ctoSummary, title: "多员工架构体检已生成", detail: "完成度 \(selectedProductArchitectureCompletionScore)%", agentID: ctoID)
        saveSnapshot()
    }

    @discardableResult
    public func runMultiAgentArchitectureClosureDrill(goal: String = "多员工架构闭环演练") -> Bool {
        let drillGoal = closureDrillGoal(for: goal)
        guard startCTOSupervisorGoal(goal: drillGoal) != nil else { return false }

        let matchingTasks = selectedProductTasks.filter { ctoSupervisorGoalKey(for: $0) == drillGoal }
        guard let engineerTask = matchingTasks.first(where: { $0.title.hasPrefix("员工执行：") }),
              let reviewerTask = matchingTasks.first(where: { $0.title.hasPrefix("审查验收：") }),
              let bossTask = matchingTasks.first(where: { $0.title.hasPrefix("老板审批：") }),
              let engineerID = engineerTask.ownerID,
              let reviewerID = reviewerTask.ownerID
        else {
            appendEvent(kind: .risk, title: "多员工闭环演练未完成", detail: "缺少工程或审查员工，无法跑通完整链路。", agentID: ctoID)
            saveSnapshot()
            return false
        }

        completeWorkItem(for: engineerTask.id, agentID: engineerID)
        postEmployeeHandoff(
            fromAgentID: engineerID,
            toAgentID: reviewerID,
            taskID: reviewerTask.id,
            subject: "工程实现交接给审查",
            body: "\(agentName(engineerID)) 已完成 \(engineerTask.title) 的工程实现，请 \(agentName(reviewerID)) 按成功标准审查并给出可交付结论。"
        )
        _ = advanceCTOSupervisorLoop()

        completeWorkItem(for: reviewerTask.id, agentID: reviewerID)
        updateTaskStatus(reviewerTask.id, status: .done, note: "审查员已完成闭环演练审查，任务进入技术负责人汇总。")
        _ = advanceCTOSupervisorLoop()

        if let approval = selectedProductApprovals.first(where: { $0.taskID == bossTask.id && $0.status == .pending }) {
            decideApproval(approval.id, approved: true)
        }

        requestCTOReview(for: reviewerTask.id)
        runAutomaticVerification()
        generateAcceptanceReport(for: reviewerTask.id)
        acceptTask(reviewerTask.id)

        generateAcceptanceReport(for: bossTask.id)
        acceptTask(bossTask.id)

        let report = multiAgentArchitectureAuditText()
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "闭环演练完成。\n\n\(report)"))
        appendEvent(kind: .ctoSummary, title: "多员工闭环演练已完成", detail: "完成度 \(selectedProductArchitectureCompletionScore)%", agentID: ctoID)
        saveSnapshot()
        return true
    }

    public func generateAcceptanceReport(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        let owner = task.ownerID.map(agentName) ?? "未分配"
        let productID = task.productID ?? selectedProductID
        let report = """
        \("验收报告".L())
        \("任务：".L())\(task.title)
        \("负责人：".L())\(owner)
        \("当前状态：".L())\(task.status.title)
        \("验收标准：".L())\(task.successCriteria)
        \("产物路径：".L())\(task.artifactPath ?? "未指定")

        \("结论：".L())
        \("- 若状态为完成：可以进入老板最终确认。".L())
        \("- 若状态为待审查：需要审查员给出风险结论。".L())
        \("- 若状态为运行中：等待终端输出和验证结果。".L())
        """
        messages.append(ChatMessage(productID: productID, agentID: bossID, author: .system, text: report))
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: report))
        let artifact = ArtifactRecord(
            productID: productID,
            taskID: task.id,
            kind: .report,
            title: "验收报告：".L() + "\(task.title)",
            path: "opc://acceptance-reports/\(task.id.uuidString)",
            summary: "任务状态：".L() + "\(task.status.title)" + "；负责人：".L() + "\(owner)" + "。"
        )
        artifacts.insert(artifact, at: 0)
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "验收报告已生成：".L() + "\(task.title)",
            body: report,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationWarning,
            requesterID: ctoID,
            reviewerID: task.ownerID ?? ctoID,
            summary: "验收报告已生成，等待自动验收或老板最终确认。".L(),
            reportArtifactID: artifact.id
        )
        appendEvent(kind: .artifactCreated, title: "验收报告已生成".L(), detail: task.title, agentID: task.ownerID)
        saveSnapshot()
    }

    public func scanProjectArtifacts() {
        guard let product = selectedProduct else { return }
        let root = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: root.path) else {
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "产物扫描失败".L(), detail: "项目目录不存在：" + "\(root.path)"), at: 0)
            saveSnapshot()
            return
        }

        let candidates = [
            ("AGENTS.md", ArtifactKind.rule),
            ("CLAUDE.md", ArtifactKind.rule),
            ("Package.swift", ArtifactKind.package),
            ("package.json", ArtifactKind.package),
            ("README.md", ArtifactKind.report),
            ("Sources", ArtifactKind.source),
            ("Tests", ArtifactKind.test),
            (".codex", ArtifactKind.rule),
            (".claude", ArtifactKind.rule),
            (".gemini", ArtifactKind.rule)
        ]

        var inserted = 0
        for candidate in candidates {
            let url = root.appendingPathComponent(candidate.0)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if artifacts.contains(where: { $0.productID == selectedProductID && $0.path == url.path }) { continue }
            artifacts.insert(ArtifactRecord(productID: selectedProductID, taskID: nil, kind: candidate.1, title: candidate.0, path: url.path, summary: "项目扫描发现 ".L() + "\(candidate.1.title)" + "：".L() + "\(candidate.0)"), at: 0)
            inserted += 1
        }

        verifications.insert(VerificationRecord(productID: selectedProductID, status: inserted > 0 ? .passed : .warning, title: "产物扫描完成".L(), detail: "新增 " + "\(inserted)" + " 条产物记录。"), at: 0)
        appendEvent(kind: .artifactCreated, title: "产物扫描完成".L(), detail: "新增 " + "\(inserted)" + " 条产物记录。", agentID: ctoID)
        saveSnapshot()
    }

    public func runAutomaticVerification() {
        let productTasks = selectedProductTasks
        let pendingApprovals = selectedProductApprovals.filter { $0.status == .pending }
        let failedTasks = productTasks.filter { [.failed, .blocked].contains($0.status) }
        let missingOwners = productTasks.filter { $0.ownerID == nil && $0.status != .done }
        let rootExists = selectedProduct.map { FileManager.default.fileExists(atPath: NSString(string: $0.rootDirectory).expandingTildeInPath) } ?? false

        var status: VerificationStatus = .passed
        var details: [String] = []
        if !rootExists {
            status = .failed
            details.append("产品根目录不存在。".L())
        }
        if !pendingApprovals.isEmpty {
            status = maxSeverity(status, .warning)
            details.append("存在 ".L() + "\(pendingApprovals.count)" + " 个待审批请求。".L())
        }
        if !failedTasks.isEmpty {
            status = .failed
            details.append("存在 ".L() + "\(failedTasks.count)" + " 个阻塞/失败任务。".L())
        }
        if !missingOwners.isEmpty {
            status = maxSeverity(status, .warning)
            details.append("存在 ".L() + "\(missingOwners.count)" + " 个未分配任务。".L())
        }
        if details.isEmpty {
            details.append("任务、审批、目录基础检查通过。".L())
        }

        let verification = VerificationRecord(productID: selectedProductID, status: status, title: "自动验收检查".L(), detail: details.joined(separator: "\n"))
        verifications.insert(verification, at: 0)
        let gateStatus: ReviewGateStatus = switch status {
        case .passed: .verificationPassed
        case .warning: .verificationWarning
        case .failed: .verificationFailed
        }
        for task in selectedProductAcceptanceTasks where task.status != .done {
            upsertReviewGate(
                for: task,
                status: gateStatus,
                requesterID: ctoID,
                reviewerID: task.ownerID ?? ctoID,
                summary: "自动验收检查：".L() + "\(status.title)" + "。".L() + "\(details.joined(separator: " "))",
                latestVerificationID: verification.id
            )
        }
        appendEvent(kind: status == .failed ? .risk : .artifactCreated, title: "自动验收检查完成".L(), detail: status.title, agentID: ctoID)
        saveSnapshot()
    }

    public func addMemory(kind: ProductMemoryKind, title: String, detail: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        memories.insert(ProductMemoryNote(productID: selectedProductID, kind: kind, title: cleanTitle, detail: cleanDetail), at: 0)
        appendEvent(kind: .artifactCreated, title: "产品记忆已保存".L(), detail: cleanTitle, agentID: ctoID)
        saveSnapshot()
    }

    /// 自动状态摘要在产品记忆中保留 1 小时去重窗口的标题前缀。
    /// 只用于识别 `captureDecisionMemoryFromLatestReport` 自动写入的条目；
    /// 用户通过 `addMemory` 手工保存的同名条目不会受影响（手工保存不会以此前缀开头）。
    static let autoCapturedSummaryTitlePrefix = "自动记录：".L()

    /// 自动状态摘要去重窗口（秒）。同一产品、相同 detail 前 200 字、1 小时内只写入一条。
    static let autoCapturedSummaryDedupeWindow: TimeInterval = 3600

    /// 自动状态摘要去重比对使用的 detail 前缀长度。
    static let autoCapturedSummaryDedupePrefixLength = 200

    public func captureDecisionMemoryFromLatestReport() {
        let latest = messages(for: bossID, in: selectedProductID, includingLegacyGlobal: false).last(where: { $0.author == .system })
            ?? messages(for: ctoID, in: selectedProductID, includingLegacyGlobal: false).last(where: { $0.author == .system })
        let detail = latest?.text ?? productHealthSnapshotText()
        let trimmedDetail = String(detail.prefix(1200))
        let dedupePrefix = String(trimmedDetail.prefix(Self.autoCapturedSummaryDedupePrefixLength))
        if hasRecentAutoCapturedSummary(forProduct: selectedProductID, detailPrefix: dedupePrefix) {
            // 同产品、相同 detail 前 200 字在 `autoCapturedSummaryDedupeWindow` 秒内已经记录过，
            // 跳过重复写入；不同产品 / 不同 detail 前缀 / 超出窗口仍照常写入。
            return
        }
        addMemory(kind: .summary, title: "\(Self.autoCapturedSummaryTitlePrefix)" + "\(selectedProduct?.name ?? "当前产品".L())" + " 状态摘要".L(), detail: trimmedDetail)
    }

    private func hasRecentAutoCapturedSummary(forProduct productID: UUID, detailPrefix: String) -> Bool {
        let now = Date()
        let prefixLength = Self.autoCapturedSummaryDedupePrefixLength
        return memories.contains { note in
            guard note.productID == productID,
                  note.kind == .summary,
                  note.title.hasPrefix(Self.autoCapturedSummaryTitlePrefix),
                  now.timeIntervalSince(note.createdAt) < Self.autoCapturedSummaryDedupeWindow
            else { return false }
            return String(note.detail.prefix(prefixLength)) == detailPrefix
        }
    }

    /// 预览当前选中产品里「自动记录：…」状态摘要的重复情况，不修改任何数据。
    /// 维护视图可以基于此结构显示「找到 X 组重复，共 Y 条旧记忆可清理」的中文提示。
    public struct AutoCapturedSummaryDuplicatePreview: Equatable, Sendable {
        public var duplicateGroupCount: Int
        public var removableNoteCount: Int
        public var totalAutoSummaryCount: Int

        public var hasDuplicates: Bool { removableNoteCount > 0 }
    }

    /// 仅扫描当前选中产品下 kind == .summary、title 以 `自动记录：` 开头的产品记忆，
    /// 按 detail 前 200 字分组统计重复条数。范围之外（不同产品 / 不同 kind / 用户手工 addMemory）的记忆全部忽略。
    public func previewSelectedProductAutoCapturedSummaryDuplicates() -> AutoCapturedSummaryDuplicatePreview {
        let scoped = autoCapturedSummariesForSelectedProduct()
        let prefixLength = Self.autoCapturedSummaryDedupePrefixLength
        let groups = Dictionary(grouping: scoped) { String($0.detail.prefix(prefixLength)) }
        let duplicateGroups = groups.values.filter { $0.count >= 2 }
        let removable = duplicateGroups.reduce(0) { $0 + ($1.count - 1) }
        return AutoCapturedSummaryDuplicatePreview(
            duplicateGroupCount: duplicateGroups.count,
            removableNoteCount: removable,
            totalAutoSummaryCount: scoped.count
        )
    }

    /// 维护操作：清理当前选中产品中重复的自动状态摘要。
    /// - 仅作用于 kind == .summary 且 title 以 `自动记录：` 开头的记忆条目。
    /// - 按 detail 前 200 字分组，每组保留 createdAt 最新的一条，移除其它旧条目。
    /// - 不触碰其它产品、其它 kind、用户手工 addMemory 写入的记忆。
    /// - 仅当确实移除了条目时才写入维护型 VerificationRecord + 事件 + 快照；无重复时 no-op 返回 0。
    /// - Returns: 实际移除的旧记忆条数。
    @discardableResult
    public func cleanupSelectedProductAutoCapturedSummaryDuplicates() -> Int {
        let scoped = autoCapturedSummariesForSelectedProduct()
        let prefixLength = Self.autoCapturedSummaryDedupePrefixLength
        let groups = Dictionary(grouping: scoped) { String($0.detail.prefix(prefixLength)) }

        var idsToRemove: Set<UUID> = []
        var groupCount = 0
        for (_, notes) in groups where notes.count >= 2 {
            // createdAt 降序：最新的留下，剩下的全部计入待删除集合。
            let sorted = notes.sorted { $0.createdAt > $1.createdAt }
            for stale in sorted.dropFirst() {
                idsToRemove.insert(stale.id)
            }
            groupCount += 1
        }

        guard !idsToRemove.isEmpty else { return 0 }

        memories.removeAll { idsToRemove.contains($0.id) }

        let productName = selectedProduct?.name ?? "当前产品".L()
        let detail = "已合并 ".L() + "\(groupCount)" + " 组重复的自动状态摘要，共移除 ".L() + "\(idsToRemove.count)" + " 条旧记忆，保留每组最新一条。范围：当前产品 " + "\(productName)" + "。"
        let record = VerificationRecord(
            productID: selectedProductID,
            status: .passed,
            title: "自动状态摘要去重清理".L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        appendEvent(kind: .ctoSummary, title: "自动状态摘要去重清理".L(), detail: detail, agentID: ctoID)
        saveSnapshot()
        return idsToRemove.count
    }

    /// 格式化「自动状态摘要去重预览」中文描述，供维护视图直接展示，不修改任何数据。
    public func autoCapturedSummaryDuplicatePreviewText() -> String {
        let p = previewSelectedProductAutoCapturedSummaryDuplicates()
        guard p.totalAutoSummaryCount > 0 else {
            return "自动状态摘要去重：当前产品无自动状态摘要记忆。".L()
        }
        if !p.hasDuplicates {
            return "自动状态摘要去重：共 ".L() + "\(p.totalAutoSummaryCount)" + " 条，未发现重复，无需清理。".L()
        }
        return "自动状态摘要去重：共 ".L() + "\(p.totalAutoSummaryCount)" + " 条自动摘要，发现 ".L() + "\(p.duplicateGroupCount)" + " 组重复，可清理 ".L() + "\(p.removableNoteCount)" + " 条旧摘要，每组保留最新一条。"
    }

    private func autoCapturedSummariesForSelectedProduct() -> [ProductMemoryNote] {
        memories.filter { note in
            note.productID == selectedProductID
                && note.kind == .summary
                && note.title.hasPrefix(Self.autoCapturedSummaryTitlePrefix)
        }
    }

    public func runCTOAutopilot() {
        createSafetyCheckpoint(reason: "技术负责人自动调度前检查点".L())
        assignExistingSpecialistsToSelectedProduct()

        if selectedProductTasks.filter({ $0.status != .done }).count < 5 {
            seedStandardTaskTemplates(goal: selectedProduct?.name ?? "当前产品".L())
        }

        let executableTaskIDs = Set(selectedProductWorkQueue.map(\.taskID))
        for task in selectedProductTasks where [.planned, .assigned, .waiting].contains(task.status) {
            guard let ownerID = task.ownerID,
                  ownerID != bossID,
                  !executableTaskIDs.contains(task.id)
            else { continue }
            enqueueWorkItem(taskID: task.id, agentID: ownerID)
        }

        for task in selectedProductTasks where [.blocked, .failed].contains(task.status) {
            if !selectedProductApprovals.contains(where: { $0.taskID == task.id && $0.status == .pending }) {
                requestApproval(taskID: task.id, title: "技术负责人请求处理阻塞：".L() + "\(task.title)", reason: "任务处于 ".L() + "\(task.status.title)" + "，需要老板批准继续、驳回或重新拆解。", requesterID: ctoID)
            }
        }

        scanProjectArtifacts()
        runAutomaticVerification()
        generateHealthAudit()
        captureDecisionMemoryFromLatestReport()
        _ = advanceCTOSupervisorLoop()
        appendEvent(kind: .ctoSummary, title: "技术负责人自动调度完成".L(), detail: "已完成团队、任务、队列、产物、验收、记忆和协作链路推进。".L(), agentID: ctoID)
        saveSnapshot()
    }

    @discardableResult
    public func runCTOAutopilotWithVisibleProgress() -> Bool {
        guard !ctoAutopilotState.isRunning else { return false }
        ctoAutopilotState = .running
        Task { @MainActor in
            await Task.yield()
            runCTOAutopilot()
            ctoAutopilotState = .completed
        }
        return true
    }

    public func scanLinkedLocalFiles(limit: Int = 300) {
        guard let product = selectedProduct else { return }
        // LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST（角色继承期轮 21 标记 + 轮 27 部分落地 + candidate ψ 白名单第一阶段）：
        // product.rootDirectory 是用户可写的原始字符串。多层加固：
        // R21：用 .standardizedFileURL 折叠 `..` 段防相对路径越界。
        // R27（候选 ψ 部分落地）：(a) .resolvingSymlinksInPath 解析符号链接后判定是否落入系统保留路径；
        //                          (b) 系统路径黑名单（/System, /private/var/db, /private/etc, /usr, /bin, /sbin）；
        //                          symlink 解析仅用于安全判定，artifact 写入仍保留**原 path** 不改用户可见语义。
        //                          越界时 verifications 写 .failed + appendEvent .risk + return（不静默）。
        // candidate ψ 第一阶段：显式根白名单限定在已登记 ProductWorkspace.rootDirectory 列表；
        // rawRoot 和 resolvedRoot 都必须落在这些根之内，避免 symlink 把索引带到未登记目录。
        // 仍待后续：把根白名单配置入口产品化到技术维护/导入设置侧，不进入老板总控。
        // 守门测试 `scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker`（R21）+ `scanLinkedLocalFilesRejectsSystemReservedRootPath` / `scanLinkedLocalFilesRejectsSymlinkResolvingToSystemReservedPath`（R27）防止此加固被误删。
        // R31 自洽性条件断言推广：`scanLinkedLocalFilesEnumeratorAndLimitationMarkerStaySelfConsistent`
        // 双向验证 marker + enumerator 调用 + R27 二层防御（symlink + 黑名单）三者同步存在/同步移除（防双删 regression）。
        let rawRoot = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath).standardizedFileURL
        let resolvedRoot = rawRoot.resolvingSymlinksInPath()
        if Self.isSystemReservedPath(rawRoot) || Self.isSystemReservedPath(resolvedRoot) {
            rejectLinkedLocalFileIndexRoot(reason: "产品根目录解析后落在系统保留路径 (" + "\(resolvedRoot.path)" + ")，已拒绝索引以避免污染产物列表。请把根目录指向用户可写目录。", eventTitle: "本地文件索引拒绝系统路径".L(), eventDetail: "rootDirectory=" + "\(product.rootDirectory)" + " 解析为 " + "\(resolvedRoot.path)" + "，落在系统保留路径黑名单。")
            return
        }
        let allowedRootPaths = Self.linkedLocalFileAllowedRootPaths(from: products)
        if !Self.isAllowedLinkedLocalFileRoot(rawRoot: rawRoot, resolvedRoot: resolvedRoot, allowedRootPaths: allowedRootPaths) {
            rejectLinkedLocalFileIndexRoot(reason: "产品根目录解析后不在已登记工作区根白名单内 (" + "\(resolvedRoot.path)" + ")，已拒绝索引。请通过产品导入或项目设置登记该根目录。", eventTitle: "本地文件索引拒绝未登记根目录".L(), eventDetail: "rootDirectory=" + "\(product.rootDirectory)" + " 解析为 " + "\(resolvedRoot.path)" + "，不在已登记工作区根白名单。")
            return
        }
        let root = rawRoot
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let usefulExtensions: Set<String> = ["md", "txt", "pdf", "docx", "pptx", "xlsx", "csv", "json", "swift", "js", "ts", "tsx", "py"]
        var count = 0
        for case let url as URL in enumerator {
            if count >= limit { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            guard usefulExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if artifacts.contains(where: { $0.productID == selectedProductID && $0.path == url.path }) { continue }
            // title 必须以 `本地文件索引：` 前缀开头，进入 `technicalMaintenanceArtifactTitlePrefixes` 分类，
            // 让产物只出现在维护产物档案中心，不污染老板/交付视图。
            // summary 仍保留中文路径线索，便于技术负责人对照原文件名。
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: artifactKind(for: url), title: "本地文件索引：".L() + "\(url.lastPathComponent)", path: url.path, summary: "本地文件索引：".L() + "\(url.lastPathComponent)"), at: 0)
            count += 1
        }
        verifications.insert(VerificationRecord(productID: selectedProductID, status: count > 0 ? .passed : .warning, title: "本地文件索引完成".L(), detail: "新增 " + "\(count)" + " 个本地文件索引。"), at: 0)
        appendEvent(kind: .artifactCreated, title: "本地文件已联动".L(), detail: "新增 " + "\(count)" + " 个本地文件索引。", agentID: ctoID)
        saveSnapshot()
    }

    private func rejectLinkedLocalFileIndexRoot(reason: String, eventTitle: String, eventDetail: String) {
        verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "本地文件索引被拒绝".L(), detail: reason), at: 0)
        appendEvent(kind: .risk, title: eventTitle, detail: eventDetail, agentID: ctoID)
        saveSnapshot()
    }

    /// R28（角色继承期轮 28 落地候选 λ-2 引擎部分）：
    /// 一次性把所有 `productID == nil` 的 task 回填到给定 `targetProductID`。当前产品视图已经严格
    /// 只读当前产品；本 helper 负责把旧快照里的未归属任务显式迁入选定产品，避免旧任务丢失。
    ///
    /// 设计：engine vs policy 分离 —— 本 helper 只做**怎么迁移**，不做**何时迁移 / 目标产品如何选**。
    /// caller（codex / UI 触发器 / 一次性脚本）决定调用时机，本 helper 接受目标 productID 作为参数。
    ///
    /// 幂等：第二次调用对同一数据集是 no-op（所有原 nil task 已回填，不再有 nil 候选）。
    /// 返回值：本次迁移的 task 数量，便于 caller 写 verification record 验证迁移生效。
    ///
    /// 风险：caller 必须自行确保 `targetProductID` 是合法存在的产品。本 helper 不校验
    /// `products.contains { $0.id == targetProductID }`，因为这是 policy 决定（caller 可能
    /// 知道某个 well-known sentinel UUID 用于「未归属任务」收纳，类似邮件 Inbox）。
    /// 调用前后 caller 应自行 saveSnapshot()。本 helper 不调用 saveSnapshot 避免和 caller
    /// 的事务边界冲突（multi-step 迁移可能要原子提交）。
    ///
    /// 守门测试：`migrateLegacyTasksWithoutProductIDBackfillsNilTasksAndReportsCount` /
    /// `migrateLegacyTasksWithoutProductIDIsIdempotentOnSecondCall` /
    /// `migrateLegacyTasksWithoutProductIDLeavesNonNilTasksUntouched` /
    /// `migrateLegacyTasksWithoutProductIDSourceContainsCandidateLambda2Reference`。
    public func migrateLegacyTasksWithoutProductID(targetProductID: UUID) -> Int {
        var migrated = 0
        for index in tasks.indices where tasks[index].productID == nil {
            tasks[index].productID = targetProductID
            migrated += 1
        }
        return migrated
    }

    /// R27（角色继承期轮 27 落地候选 ψ 部分）：
    /// 判定一个**已 standardize 或 resolvingSymlinks 之后的** URL 是否落入 macOS 系统保留路径。
    /// 用途：scanLinkedLocalFiles 拒绝把产品 root 指向系统目录索引（避免误把 /usr/bin 文件写入 artifact 列表）。
    /// 这是**安全护栏**不是权限模型——OS 已经决定用户能否读，本判定只防止"使用错误"污染产物列表。
    /// 黑名单覆盖（前缀匹配，需带 trailing slash 避免 `/usrFoo` 误命中 `/usr`）：
    /// `/System`、`/private/var/db`、`/private/etc`、`/usr`、`/bin`、`/sbin`。
    /// 注意 `/usr` 在 macOS 含 `/usr/local`（用户可写），但本判定仍拒绝整个 `/usr` —
    /// `/usr/local` 也不应作为产品根目录索引（会误命中 brew/系统包路径）。
    fileprivate static func isSystemReservedPath(_ url: URL) -> Bool {
        let path = url.path
        let reserved: [String] = ["/System", "/private/var/db", "/private/etc", "/usr", "/bin", "/sbin"]
        for prefix in reserved {
            if path == prefix { return true }
            if path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    fileprivate static func linkedLocalFileAllowedRootPaths(from products: [ProductWorkspace]) -> Set<String> {
        Set(products.map { product in
            URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
                .standardizedFileURL
                .path
        })
    }

    fileprivate static func isAllowedLinkedLocalFileRoot(rawRoot: URL, resolvedRoot: URL, allowedRootPaths: Set<String>) -> Bool {
        isPath(rawRoot.path, insideAnyOf: allowedRootPaths)
            && isPath(resolvedRoot.path, insideAnyOf: allowedRootPaths)
    }

    private static func isPath(_ path: String, insideAnyOf roots: Set<String>) -> Bool {
        roots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    public func createSafetyCheckpoint(reason: String) {
        let directory = CompanyPersistence.stateURL.deletingLastPathComponent().appendingPathComponent("checkpoints", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        let fileName = "checkpoint-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"
        let url = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.opcCheckpoint.encode(currentSnapshot())
            try data.write(to: url, options: [.atomic])
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: .report, title: "安全检查点".L(), path: "本机安全检查点存档".L(), summary: reason), at: 0)
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .passed, title: "安全检查点已创建".L(), detail: "安全检查点已保存到本机存档。".L()), at: 0)
            appendEvent(kind: .artifactCreated, title: "安全检查点已创建".L(), detail: reason, agentID: ctoID)
        } catch {
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "安全检查点失败".L(), detail: error.localizedDescription), at: 0)
            appendEvent(kind: .risk, title: "安全检查点失败".L(), detail: error.localizedDescription, agentID: ctoID)
        }
        saveSnapshot()
    }

    public func safetyCheckpointListText(limit: Int = 5) -> String {
        let urls = safetyCheckpointURLs(limit: limit)
        guard !urls.isEmpty else {
            return """
            \("暂无安全检查点。".L())

            \("执行清理、重置、删除产品、技术负责人自动调度前，OPC 会自动保存当前公司状态。".L())
            """
        }

        let lines = urls.enumerated().map { index, url in
            let dateText = checkpointDateText(for: url)
            return "\(index + 1). \(dateText)\n   本机检查点已保存"
        }
        return """
        \("最近安全检查点：".L())
        \(lines.joined(separator: "\n"))

        \("一键回滚会恢复员工、产品、任务、消息、日志、审批、产物、记忆、通信和分支计划。".L())
        \("不会改动真实项目目录里的源码文件。".L())
        """
    }

    public func localDiagnosticsPolicyText() -> String {
        let supportDirectory = CompanyPersistence.stateURL.deletingLastPathComponent()
        let historyIndex = supportDirectory.appendingPathComponent("company-history.sqlite3")
        let checkpoints = supportDirectory.appendingPathComponent("checkpoints", isDirectory: true)
        let jobArchive: String
        if let productRoot = selectedProduct?.rootDirectory {
            jobArchive = URL(fileURLWithPath: productRoot)
                .appendingPathComponent(".opc/jobs", isDirectory: true)
                .path
        } else {
            jobArchive = "未选择产品，暂无命令行作业档案路径".L()
        }

        return """
        \("本机诊断与日志策略：".L())
        \("- 当前正式使用目标是单人本机使用，不接入外部崩溃上报，不自动上传日志。".L())
        \("- 默认老板界面只展示结果、风险、审批和交付；排查材料留在技术负责人维护区。".L())

        \("本机诊断位置：".L())
        \("- 主状态快照：".L())\(CompanyPersistence.stateURL.path)
        \("- 历史索引：".L())\(historyIndex.path)
        \("- 安全检查点：".L())\(checkpoints.path)
        \("- 命令行作业档案：".L())\(jobArchive)
        \("- macOS 崩溃报告：~/Library/Logs/DiagnosticReports/OPCCompany_*.crash".L())

        \("排查顺序：".L())
        \("1. 先看技术维护审计中心和员工终端摘要。".L())
        \("2. 再看命令行作业档案与历史索引。".L())
        \("3. 如应用异常退出，再到 macOS 崩溃报告目录查找 OPCCompany 记录。".L())
        \("4. 状态损坏时，优先用安全检查点回滚。".L())
        """
    }

    public func restoreLatestSafetyCheckpoint() {
        guard let url = safetyCheckpointURLs(limit: 1).first else {
            appendEvent(kind: .risk, title: "没有可恢复的安全检查点", detail: "当前本机还没有检查点文件。", agentID: ctoID)
            saveSnapshot()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder.opcCheckpoint.decode(CompanySnapshot.self, from: data)
            guard snapshot.ctoID == ctoID, snapshot.bossID == bossID else {
                appendEvent(kind: .risk, title: "检查点不属于当前公司", detail: "最近安全检查点无法用于当前公司。", agentID: ctoID)
                saveSnapshot()
                return
            }
            applyRestoredSnapshot(snapshot)
            appendEvent(kind: .statusChanged, title: "已回滚到最近安全检查点", detail: "已恢复最近一份本机安全检查点。", agentID: ctoID)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "已回滚到最近安全检查点：\(checkpointDateText(for: url))。"))
            saveSnapshot()
        } catch {
            appendEvent(kind: .risk, title: "安全检查点恢复失败", detail: error.localizedDescription, agentID: ctoID)
            saveSnapshot()
        }
    }

    private func artifactKind(for url: URL) -> ArtifactKind {
        switch url.pathExtension.lowercased() {
        case "swift", "js", "ts", "tsx", "py": .source
        case "md", "txt", "pdf", "docx", "pptx": .report
        case "json", "yml", "yaml": .package
        case "csv", "xlsx": .other
        default: .other
        }
    }

    public func commandPreview(for agent: CompanyAgent, prompt: String) -> String {
        visibleExecutionSummary(for: agent, taskPrompt: prompt)
    }

    /// 终端大厅员工卡顶部默认可见的会话续跑单行（产品层文案）。
    ///
    /// 该行直接出现在老板/技术负责人的默认卡片上，必须用产品语言：只保留品牌名 +
    /// 是否能按产品续跑结论。底层协议名、状态机画像和诊断信号关键词只留在维护逻辑。
    public func terminalHallCardLongSessionLine(for agent: CompanyAgent) -> String? {
        guard let summary = terminalHallCardLongSessionProductSummary(for: agent) else {
            return nil
        }
        return "会话续跑：\(summary.brand) · \(summary.resumeLabel)"
    }

    public func terminalHallCardLongSessionDetail(for agent: CompanyAgent) -> String? {
        guard let summary = terminalHallCardLongSessionProductSummary(for: agent) else {
            return nil
        }
        let scopeLabel = summary.supportsResume ? "可识别历史会话并按产品接续" : "仅使用当前任务上下文"
        return "会话续跑详情：\(summary.brand) · \(summary.resumeLabel) · \(scopeLabel)"
    }

    private func terminalHallCardLongSessionProductSummary(for agent: CompanyAgent) -> (brand: String, resumeLabel: String, supportsResume: Bool)? {
        guard let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) else {
            return nil
        }
        let brand: String
        switch profile.command {
        case "codex": brand = "Codex"
        case "claude": brand = "Claude Code"
        case "gemini": brand = "Gemini"
        default: brand = profile.displayName
        }
        let resumeLabel = profile.supportsResume ? "可按产品接续" : "不接续历史会话"
        return (brand, resumeLabel, profile.supportsResume)
    }

    public func terminalHallCardTaskDigestLine(prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == OPCVisibleInterfaceCopy.defaultTerminalPromptPlaceholder {
            return nil
        }
        let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        let limit = 60
        if oneLine.count <= limit {
            return "本轮任务：\(oneLine)"
        }
        return "本轮任务：\(oneLine.prefix(limit))…"
    }

    public func terminalHallCardInjectionHint() -> String {
        "自动注入：角色档案 · 记忆 · 技能 · 产品工作区。"
    }

    public func visibleBackendSummary(for agent: CompanyAgent) -> String {
        let model = agent.backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "默认模型" : agent.backend.model
        switch agent.backend.type {
        case .subscriptionCLI:
            let toolName = visibleCommandToolName(for: agent)
            return "\(agent.backend.type.title) · 工具 \(toolName) · \(model) · 思考强度 \(agent.backend.reasoningEffort.title)"
        case .api:
            return "\(agent.backend.type.title) · \(model) · 思考强度 \(agent.backend.reasoningEffort.title)"
        case .local:
            return "\(agent.backend.type.title) · 本地占位"
        }
    }

    private func visibleCommandToolName(for agent: CompanyAgent) -> String {
        opcBackendCommandDisplayName(agent.backend.command)
    }

    private func visibleExecutionSummary(for agent: CompanyAgent, taskPrompt: String) -> String {
        let task = taskPrompt.replacingOccurrences(of: "\n", with: " ").prefix(60)
        let protocolLine = CLIAgentCommandBuilder.interactionSummary(for: agent).map { "\n长期会话：\($0)" } ?? ""
        return """
        \("运行方式：".L())\(visibleBackendSummary(for: agent))
        \("任务注入：角色档案、记忆、技能和产品工作区会在运行时自动注入。".L())
        \("任务摘要：".L())\(task)\(protocolLine)
        """
    }

    private func terminalCommandSummary(title: String, agent: CompanyAgent, executionDirectory: URL, prompt: String, job: CLIJobDirectory? = nil) -> String {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "使用默认任务。".L() : String(prompt.replacingOccurrences(of: "\n", with: " ").prefix(120))
        let jobLine = job == nil ? "" : "OPC 作业档案：已创建\n".L()
        return """
        \(jobLine)[\(title)]
        执行位置：\(executionDirectory.standardizedFileURL.path == cliWorkingDirectoryURL().standardizedFileURL.path ? "主工作目录".L() : "独立执行区".L())
        \("运行方式：".L())\(visibleBackendSummary(for: agent))
        \("任务摘要：".L())\(task)

        """
    }

    public func cliPreflightText(for agentID: UUID, prompt: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return "未找到员工，无法生成运行前预检。"
        }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = cleanPrompt.isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : cleanPrompt
        let permissions = agent.permissions.map(\.title).sorted().joined(separator: "、")
        let product = selectedProduct
        let workingDirectory = cliWorkingDirectoryURL().path
        let executionDirectory = cliExecutionDirectoryURL(for: agent).path
        let isolationNote = cliExecutionIsolationNote(for: agent)
        let risks = preflightRiskLines(for: agent)

        return """
        \("命令行运行前预检".L())
        \("员工：".L())\(agent.displayName) / \(agent.title)
        \("产品：".L())\(product?.name ?? "当前产品")
        \("工作目录：".L())\(workingDirectory)
        \("执行目录：".L())\(executionDirectory)
        \("隔离策略：".L())\(isolationNote)
        \("来源：".L())\(visibleBackendSummary(for: agent))
        \("权限：".L())\(permissions.isEmpty ? "无特殊权限" : permissions)
        \("风险提示：".L())\(risks.isEmpty ? "只读或低风险执行" : risks.joined(separator: "；"))
        \("提示词：".L())\(taskPrompt)
        \("运行摘要：".L())
        \(visibleExecutionSummary(for: agent, taskPrompt: taskPrompt))

        \("预检结论：确认以上员工、目录、权限和运行方式无误后，再点击运行。底层命令参数由系统生成，不在界面展示。".L())
        """
    }

    /// 终端大厅员工卡片常驻可见的「运行前预检」摘要：仅展示中文抽象标签，
    /// 不包含 `/Users/...` 等绝对路径、`--skip-git-repo-check` / `--permission-mode` /
    /// `model_reasoning_effort` 等底层 CLI 参数、提示词原文、隔离策略字面量。
    /// 如需完整审计文本（含路径、提示词、运行摘要），仍由 `cliPreflightText(for:prompt:)`
    /// 提供，并通过显式的「预检」按钮 / `recordCLIPreflight` 写入终端日志归档。
    public func terminalAgentCardPreflightSummary(for agentID: UUID, prompt _: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return "未找到员工，无法生成运行前预检摘要。".L()
        }
        let permissions = agent.permissions.map(\.title).sorted().joined(separator: "、")
        let product = selectedProduct
        let executionLabel = cliExecutionLocationLabel(for: agent)
        let risks = preflightRiskLines(for: agent)
        return """
        \("运行前预检摘要".L())
        \("员工：".L())\(agent.displayName) / \(agent.title)
        产品：\(product?.name ?? "当前产品".L())
        \("执行位置：".L())\(executionLabel)
        \("来源：".L())\(visibleBackendSummary(for: agent))
        权限：\(permissions.isEmpty ? "无特殊权限".L() : permissions)
        风险提示：\(risks.isEmpty ? "只读或低风险执行".L() : risks.joined(separator: "；"))
        \("预检结论：以上员工、执行位置、权限和来源确认无误后再点击运行；完整目录、提示词与运行细节可通过「预检」按钮写入终端日志查看。".L())
        """
    }

    /// 把 cliExecutionDirectoryURL(for:) 与 cliWorkingDirectoryURL() 的对比结果折叠成
    /// 中文抽象标签：「主工作区」或「独立执行区」。卡片摘要使用，避免重复路径比较逻辑。
    private func cliExecutionLocationLabel(for agent: CompanyAgent) -> String {
        cliExecutionDirectoryURL(for: agent).standardizedFileURL.path
            == cliWorkingDirectoryURL().standardizedFileURL.path
            ? "主工作区"
            : "独立执行区"
    }

    /// 抽取出风险提示生成逻辑，让完整 `cliPreflightText` 与卡片摘要共享同一份中文规则。
    private func preflightRiskLines(for agent: CompanyAgent) -> [String] {
        [
            agent.permissions.contains(.editFiles) ? "可能编辑文件" : nil,
            agent.permissions.contains(.runCommands) ? "可能执行命令" : nil,
            agent.permissions.contains(.runTests) ? "可能运行测试" : nil,
            agent.permissions.contains(.useNetwork) ? "可能使用网络" : nil,
            agent.backend.type == .api ? "会使用接口地址，不在终端运行摘要中显示密钥" : nil
        ].compactMap { $0 }
    }

    public func recordCLIPreflight(agentID: UUID, prompt: String) {
        let report = cliPreflightText(for: agentID, prompt: prompt)
        appendTerminalLog("\n[OPC 运行前预检]\n\(report)\n", for: agentID)
        appendEvent(kind: .commandPlanned, title: "命令行运行前预检", detail: agentName(agentID), agentID: agentID)
        saveSnapshot()
    }

    public func visibleTerminalLog(for agentID: UUID) -> String {
        let log = terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true)
        guard !log.isEmpty else { return "暂无终端输出。" }
        let productScoped = filterTerminalLogForSelectedProductDisplay(log)
        guard !productScoped.isEmpty else { return "暂无终端输出。" }
        let sanitized = sanitizeTerminalLogForDisplay(productScoped)
        let workspaceCompacted = compactTerminalWorkspaceTranscriptsForDisplay(sanitized)
        let compacted = compactCompletedCommandTranscriptsForDisplay(workspaceCompacted)
        return collapseConsecutiveDuplicateOPCBlocks(compacted)
    }

    /// 终端大厅员工卡终端日志区的「按状态自适应」高度（视觉层）。
    ///
    /// 减噪策略：员工"准备中"（不在运行 + 原始 terminalLogs 为空）时，卡片日志区从 180pt
    /// 收缩到 100pt，显示中文等待提示。一旦员工开始运行或有任何日志输出，立刻恢复到 180pt
    /// 给用户完整阅读空间。整张卡片的整体高度比改造前的固定 248pt 减少 27%（活跃态）/ 60%（准备态）。
    ///
    /// 这是「内容驱动的高度适配」，**不是** DisclosureGroup 折叠：高度变化会被 SwiftUI 平滑过渡，
    /// 用户能看到的占位文字和清空按钮都仍然存在；不会触动 5-01 摘要工作台守门测试。
    public func terminalAgentCardLogHeight(for agentID: UUID) -> CGFloat {
        if terminalAgentCardIsIdle(agentID: agentID) {
            return terminalAgentCardLogIdleHeight
        }
        return terminalAgentCardLogActiveHeight
    }

    public func terminalAgentCardLogPlaceholder(for agentID: UUID) -> String {
        if terminalAgentCardIsIdle(agentID: agentID) {
            return "等待派发任务，运行后此处显示终端输出。"
        }
        return "暂无终端输出。"
    }

    public func terminalAgentCardIsIdle(agentID: UUID) -> Bool {
        !isRunning(agentID: agentID) && terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true).isEmpty
    }

    public func terminalAgentCardHasClearableLog(for agentID: UUID) -> Bool {
        !terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true).isEmpty
    }

    public static let terminalAgentCardLogIdleHeight: CGFloat = 80
    public static let terminalAgentCardLogActiveHeight: CGFloat = 180

    public var terminalAgentCardLogIdleHeight: CGFloat { Self.terminalAgentCardLogIdleHeight }
    public var terminalAgentCardLogActiveHeight: CGFloat { Self.terminalAgentCardLogActiveHeight }

    private func terminalLogStorageKey(productID: UUID, agentID: UUID) -> String {
        "\(productID.uuidString.lowercased()):\(agentID.uuidString.lowercased())"
    }

    private func terminalLog(agentID: UUID, productID: UUID) -> String {
        productTerminalLogs[terminalLogStorageKey(productID: productID, agentID: agentID), default: ""]
    }

    private func terminalLogForCurrentProduct(
        agentID: UUID,
        includingLegacyFallbackForTests: Bool = false
    ) -> String {
        let key = terminalLogStorageKey(productID: selectedProductID, agentID: agentID)
        if let scoped = productTerminalLogs[key] {
            return scoped
        }
        guard includingLegacyFallbackForTests,
              CompanyPersistence.isLikelyTestProcess(environment: ProcessInfo.processInfo.environment)
        else {
            return ""
        }
        return terminalLogs[agentID, default: ""]
    }

    public func currentProductTerminalLog(for agentID: UUID) -> String {
        terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true)
    }

    private func appendTerminalLog(_ text: String, for agentID: UUID, productID: UUID? = nil) {
        let scopedProductID = productID ?? selectedProductID
        let key = terminalLogStorageKey(productID: scopedProductID, agentID: agentID)
        productTerminalLogs[key, default: ""].append(text)
        terminalLogs[agentID, default: ""].append(text)
    }

    private func setTerminalLog(_ text: String, for agentID: UUID, productID: UUID? = nil) {
        let scopedProductID = productID ?? selectedProductID
        let key = terminalLogStorageKey(productID: scopedProductID, agentID: agentID)
        productTerminalLogs[key] = text
        terminalLogs[agentID] = text
    }

    @discardableResult
    private func migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: Bool = true) -> Bool {
        var changed = false
        for (agentID, log) in terminalLogs where !log.isEmpty {
            let productID = inferredProductIDForLegacyTerminalLog(log) ?? selectedProductID
            let key = terminalLogStorageKey(productID: productID, agentID: agentID)
            guard productTerminalLogs[key, default: ""].isEmpty else { continue }
            productTerminalLogs[key] = log
            changed = true
        }
        if changed && saveAfterChange {
            saveSnapshot()
        }
        return changed
    }

    private func inferredProductIDForLegacyTerminalLog(_ log: String) -> UUID? {
        for product in products {
            let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if log.contains("产品：\(name)") || log.contains("当前产品：\(name)") {
                return product.id
            }
        }
        return nil
    }

    private func filterTerminalLogForSelectedProductDisplay(_ log: String) -> String {
        guard let selectedName = selectedProduct?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedName.isEmpty
        else { return log }

        let otherProductNames = products
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != selectedName }
        guard !otherProductNames.isEmpty else { return log }

        var visibleBlocks: [[String]] = []
        var currentBlock: [String] = []
        for line in log.components(separatedBy: .newlines) {
            if line.hasPrefix("[OPC "), !currentBlock.isEmpty {
                if !terminalLogBlockBelongsToOtherProduct(currentBlock, selectedName: selectedName, otherProductNames: otherProductNames) {
                    visibleBlocks.append(currentBlock)
                }
                currentBlock = []
            }
            currentBlock.append(line)
        }
        if !currentBlock.isEmpty,
           !terminalLogBlockBelongsToOtherProduct(currentBlock, selectedName: selectedName, otherProductNames: otherProductNames) {
            visibleBlocks.append(currentBlock)
        }

        return visibleBlocks
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func terminalLogBlockBelongsToOtherProduct(
        _ block: [String],
        selectedName: String,
        otherProductNames: [String]
    ) -> Bool {
        for line in block {
            guard line.contains("当前产品：") || line.contains("产品：") else { continue }
            if line.contains(selectedName) {
                return false
            }
            if line.contains("当前产品：") {
                return true
            }
            if otherProductNames.contains(where: { line.contains($0) }) {
                return true
            }
        }
        return false
    }

    private func sanitizeTerminalLogForDisplay(_ log: String) -> String {
        log
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("本地命令已就绪：") {
                    let rawValue = String(trimmed.dropFirst("本地命令已就绪：".count))
                    return "本地命令已就绪：\(opcBackendCommandDisplayName(rawValue))"
                }
                if line.contains("App 启动后预热当前产品团队") {
                    return line.replacingOccurrences(of: "App 启动后预热当前产品团队", with: "应用启动后预热当前产品团队")
                }
                if trimmed.hasPrefix("常驻能力：") {
                    let rawValue = String(trimmed.dropFirst("常驻能力：".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " 。."))
                    let displayValue: String
                    if rawValue.contains("常驻") || rawValue.contains("长期") || rawValue.contains("可接") {
                        displayValue = AgentRuntimeCapability.persistentProtocol.title
                    } else {
                        displayValue = rawValue.isEmpty ? AgentRuntimeCapability.persistentProtocol.title : rawValue
                    }
                    return "持续协作：\(displayValue)。"
                }
                if trimmed.hasPrefix("$ "),
                   line.contains("model_reasoning_effort") ||
                   line.contains("--skip-git-repo-check") ||
                   line.contains("--permission-mode") {
                    return "底层命令已隐藏，详见命令行作业档案。"
                }
                if line.contains("model_reasoning_effort") || line.contains("--skip-git-repo-check") {
                    return line
                        .replacingOccurrences(of: "model_reasoning_effort", with: "推理强度")
                        .replacingOccurrences(of: "--skip-git-repo-check", with: "仓库检查参数")
                }
                return line
            }
            .joined(separator: "\n")
    }

    private func compactTerminalWorkspaceTranscriptsForDisplay(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[OPC 真实终端工作区]" else {
                output.append(lines[index])
                index += 1
                continue
            }

            var end = index + 1
            var created = false
            while end < lines.count {
                let current = lines[end].trimmingCharacters(in: .whitespaces)
                if end > index + 1,
                   current.hasPrefix("[OPC "),
                   current.hasSuffix("]") {
                    break
                }
                if current.contains("员工终端席位已创建") {
                    created = true
                }
                end += 1
            }

            output.append("[OPC 真实终端工作区摘要]")
            output.append(created ? "员工终端席位已创建。" : "员工终端席位已记录。")
            output.append("执行位置：本地工作区")
            output.append("结论：真实终端席位已就绪，完整启动记录保留在维护档案。")
            index = end
        }

        return output.joined(separator: "\n")
    }

    private func compactCompletedCommandTranscriptsForDisplay(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n")

        func firstLine(in range: Range<Int>, prefixedBy prefix: String) -> String? {
            for index in range where lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
                return lines[index].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        func summaryBlock(from start: Int, to end: Int) -> [String] {
            let range = start..<end
            var summary: [String] = ["[OPC 命令行任务摘要]"]
            for prefix in ["执行位置：", "运行方式：", "任务摘要："] {
                if let line = firstLine(in: range, prefixedBy: prefix) {
                    summary.append(line)
                }
            }
            if let exitLine = firstLine(in: range, prefixedBy: "[命令退出码 ") {
                let exitCode = exitLine
                    .replacingOccurrences(of: "[命令退出码 ", with: "")
                    .replacingOccurrences(of: "]", with: "")
                summary.append("退出码：\(exitCode)")
            }
            if let statusLine = firstLine(in: range, prefixedBy: "状态：") {
                summary.append(statusLine)
            }
            summary.append("完整输出保留在命令行作业档案。")
            return summary
        }

        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[OPC 命令行任务]" else {
                output.append(lines[index])
                index += 1
                continue
            }

            let searchEnd = lines.count
            var exitIndex: Int?
            for candidate in (index + 1)..<searchEnd {
                let candidateLine = lines[candidate].trimmingCharacters(in: .whitespaces)
                if candidateLine.hasPrefix("[命令退出码 ") {
                    exitIndex = candidate
                    break
                }
                if candidateLine == "[OPC 命令行任务]" {
                    break
                }
            }

            guard let exitIndex else {
                output.append(lines[index])
                index += 1
                continue
            }

            var end = exitIndex + 1
            if end < lines.count,
               lines[end].trimmingCharacters(in: .whitespaces) == "" {
                end += 1
            }
            if end < lines.count,
               lines[end].trimmingCharacters(in: .whitespaces) == "[OPC 交互状态]" {
                end += 1
                while end < lines.count {
                    let statusTrimmed = lines[end].trimmingCharacters(in: .whitespaces)
                    if statusTrimmed.hasPrefix("[OPC ") && statusTrimmed.hasSuffix("]") {
                        break
                    }
                    if statusTrimmed.hasPrefix("[") && statusTrimmed.hasSuffix("]") && !statusTrimmed.hasPrefix("[命令退出码 ") {
                        break
                    }
                    end += 1
                }
            }

            output.append(contentsOf: summaryBlock(from: index, to: end))
            index = end
        }

        return output.joined(separator: "\n")
    }

    /// 仅压缩可见日志里连续重复的 OPC 元数据块，不改动 terminalLogs 原始审计流。
    private func collapseConsecutiveDuplicateOPCBlocks(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n")

        struct Block {
            var isOPC: Bool
            var lines: [String]
            var headingLabel: String
            var comparisonKey: [String]
        }

        func isOPCHeading(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[OPC ") && trimmed.hasSuffix("]")
        }

        var blocks: [Block] = []
        var currentLines: [String] = []
        var currentIsOPC = false
        var currentHeading = ""

        func flush() {
            guard !currentLines.isEmpty else { return }
            let key = currentLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            blocks.append(Block(
                isOPC: currentIsOPC,
                lines: currentLines,
                headingLabel: currentHeading,
                comparisonKey: key
            ))
            currentLines = []
            currentIsOPC = false
            currentHeading = ""
        }

        for line in lines {
            if isOPCHeading(line) {
                flush()
                currentIsOPC = true
                currentHeading = line.trimmingCharacters(in: .whitespaces)
                currentLines.append(line)
            } else {
                currentLines.append(line)
            }
        }
        flush()

        let warmupHeading = "[OPC 会话预热]"
        let warmupBlocks = blocks.filter { $0.isOPC && $0.headingLabel == warmupHeading }
        var emittedWarmupSummary = false

        var output: [String] = []
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            guard block.isOPC else {
                output.append(block.lines.joined(separator: "\n"))
                i += 1
                continue
            }
            if block.headingLabel == warmupHeading, warmupBlocks.count > 1 {
                if !emittedWarmupSummary, let latestWarmup = warmupBlocks.last {
                    output.append(latestWarmup.lines.joined(separator: "\n"))
                    output.append("（另有 \(warmupBlocks.count - 1) 条历史「OPC 会话预热」记录，完整记录保留在维护档案。）")
                    emittedWarmupSummary = true
                }
                i += 1
                continue
            }
            var run = 1
            while i + run < blocks.count {
                let next = blocks[i + run]
                guard next.isOPC,
                      next.headingLabel == block.headingLabel,
                      next.comparisonKey == block.comparisonKey else { break }
                run += 1
            }
            output.append(block.lines.joined(separator: "\n"))
            if run >= 2 {
                let quotedTitle = block.headingLabel
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                output.append("（以上相同「\(quotedTitle)」记录连续出现 \(run) 次，已合并显示）")
            }
            i += run
        }

        return output.joined(separator: "\n")
    }

    public func cliToolchainPreflightText() -> String {
        let agents = executableAgents
        let workingDirectory = cliWorkingDirectoryURL().path
        let issueLines = cliToolchainIssueLines()
        let agentLines = agents.map { agent in
            return """
            - \(agent.displayName)：\(visibleBackendSummary(for: agent))
              \("权限：".L())\(agent.permissions.map(\.title).sorted().joined(separator: "、").nilIfBlank ?? "无特殊权限")
              \("运行摘要：角色档案、记忆、技能和产品工作区会在运行时自动注入。".L())
            """
        }.joined(separator: "\n")

        return """
        命令行链路压测预检：\(issueLines.isEmpty ? "通过".L() : "发现 " + "\(issueLines.count)" + " 项问题")
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("工作目录：".L())\(workingDirectory)
        \("可执行员工：".L())\(agents.count)

        \("员工链路：".L())
        \(agentLines.isEmpty ? "- 暂无可执行员工".L() : agentLines)

        \("问题：".L())
        \(issueLines.isEmpty ? "- 未发现配置问题。".L() : issueLines.map { "- \($0)" }.joined(separator: "\n"))

        \("说明：".L())
        \("这是本地干跑压测，不会真正调用 Codex、Claude、Gemini 或接口模型；用于确认命令、角色档案、目录和权限链路能完整生成。".L())
        """
    }

    public func runCLIToolchainPreflightForSelectedProduct() {
        let report = cliToolchainPreflightText()
        let status: VerificationStatus = cliToolchainIssueLines().isEmpty ? .passed : .warning
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行链路压测预检", detail: report), at: 0)
        for agent in executableAgents {
            appendTerminalLog("\n[OPC 命令行链路压测预检]\n\(cliPreflightText(for: agent.id, prompt: "命令行链路体检"))\n", for: agent.id)
        }
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: status == .passed ? .artifactCreated : .risk, title: "命令行链路压测预检完成", detail: status.title, agentID: ctoID)
        saveSnapshot()
    }

    public func cliLaunchPlanText(prompt: String) -> String {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = cleanPrompt.isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : cleanPrompt
        let issueLines = cliToolchainIssueLines()
        let teamIDs = Set(selectedProductAgents.map(\.id))
        let launchAgents = executableAgents.filter { teamIDs.contains($0.id) }
        let commandLines = launchAgents.map { agent in
            return """
            - \(agent.displayName)（\(agent.role.title)）
              \("工作目录：".L())\(cliWorkingDirectoryURL().path)
              \("执行目录：".L())\(cliExecutionDirectoryURL(for: agent).path)
              \("隔离策略：".L())\(cliExecutionIsolationNote(for: agent))
              \("权限：".L())\(agent.permissions.map(\.title).sorted().joined(separator: "、").nilIfBlank ?? "无特殊权限")
              \("运行摘要：".L())
              \(visibleExecutionSummary(for: agent, taskPrompt: taskPrompt))
            """
        }.joined(separator: "\n")

        return """
        命令行任务发车台计划：\(issueLines.isEmpty ? "可发车".L() : "暂缓发车".L())
        产品：\(selectedProduct?.name ?? "当前产品".L())
        团队负责人：\(teamLeadAgentIDForSelectedProduct().map(agentName) ?? "未设置".L())
        \("目标：".L())\(taskPrompt)
        \("可执行团队员工：".L())\(launchAgents.count)

        \("发车顺序：".L())
        \("1. 保存安全检查点。".L())
        \("2. 把同一任务提示词注入每个员工的角色档案、记忆、技能和当前产品工作区。".L())
        \("3. 只启动当前产品团队成员，不启动其他产品员工。".L())
        \("4. 员工输出进入各自终端日志，CTO 收到完成摘要。".L())

        \("运行清单：".L())
        \(commandLines.isEmpty ? "- 暂无可执行团队员工。".L() : commandLines)

        \("阻塞项：".L())
        \(issueLines.isEmpty ? "- 未发现配置阻塞。".L() : issueLines.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    public func recordCLILaunchPlan(prompt: String) {
        let report = cliLaunchPlanText(prompt: prompt)
        let status: VerificationStatus = cliToolchainIssueLines().isEmpty ? .passed : .warning
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行任务发车计划", detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .commandPlanned, title: "命令行任务发车计划已生成", detail: status.title, agentID: ctoID)
        saveSnapshot()
    }

    public func runCLILaunchPlan(prompt: String) {
        let issues = cliToolchainIssueLines()
        recordCLILaunchPlan(prompt: prompt)
        guard issues.isEmpty else {
            appendEvent(kind: .risk, title: "命令行发车被阻止", detail: issues.joined(separator: "；"), agentID: ctoID)
            saveSnapshot()
            return
        }

        createSafetyCheckpoint(reason: "命令行任务发车前自动检查点")
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = cleanPrompt.isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : cleanPrompt
        for agent in executableAgents where !isRunning(agentID: agent.id) {
            runAgent(agentID: agent.id, prompt: taskPrompt)
        }
    }

    public func productTeamIsolationText() -> String {
        guard let product = selectedProduct else { return "未选择产品。" }
        let teamIDs = product.assignedAgentIDs
        let members = selectedProductAgents.map { agent in
            "- \(agent.displayName)：\(agent.role.title)\(agent.id == product.teamLeadAgentID ? " / 团队负责人" : "")"
        }.joined(separator: "\n")
        let outsiders = agents.filter { $0.role != .boss && !teamIDs.contains($0.id) }.map { agent in
            "- \(agent.displayName)：不参与当前产品，不会被当前产品发车台启动。"
        }.joined(separator: "\n")

        return """
        \("产品团队隔离规则".L())
        \("产品：".L())\(product.name)
        \("根目录：".L())\(product.rootDirectory)
        \("团队负责人：".L())\(teamLeadAgentIDForSelectedProduct().map(agentName) ?? "未设置")

        \("当前产品团队：".L())
        \(members.isEmpty ? "- 暂无团队成员" : members)

        \("非当前产品员工：".L())
        \(outsiders.isEmpty ? "- 无" : outsiders)

        \("执行规则：".L())
        \("- 工作队列只允许当前产品任务进入。".L())
        \("- 命令行任务发车台只启动当前产品团队员工。".L())
        \("- 非当前产品员工不能接收当前产品队列任务。".L())
        \("- 切换产品时会重新写出团队员工工作区上下文。".L())
        """
    }

    public func teamOperatingSummaryText() -> String {
        guard let product = selectedProduct else { return "未选择产品。".L() }
        let leadID = teamLeadAgentIDForSelectedProduct()
        let leadName = leadID.map(agentName) ?? "未设置".L()
        let memberLines = selectedProductAgents.map { agent in
            let taskCount = selectedProductTasks.filter { $0.ownerID == agent.id && $0.status != .done && $0.status != .canceled }.count
            let queueCount = selectedProductWorkQueue.filter { $0.agentID == agent.id }.count
            return "- " + "\(agent.displayName)" + "：".L() + "\(agent.role.title)" + "，未完成任务 " + "\(taskCount)" + "，队列 ".L() + "\(queueCount)" + "\(agent.id == leadID ? "，团队负责人" : "")"
        }.joined(separator: "\n")

        return """
        \("产品团队机制".L())
        \("产品：".L())\(product.name)
        \("团队负责人：".L())\(leadName)
        \("汇报链路：成员 -> ".L())\(leadName)\(" -> 老板".L())
        \("负责人职责：拆分目标、分配成员、汇总结果、提示风险、给老板阶段性汇报。".L())
        \("成员分工：".L())
        \(memberLines.isEmpty ? "- 暂无成员".L() : memberLines)
        """
    }

    public func startRuntimeSupervisorIfNeeded() {
        guard !runtimeSupervisorStarted else { return }
        runtimeSupervisorStarted = true
        ensureRuntimeSessionsForSelectedProduct()
        prewarmSelectedProductAgentSessions(reason: "应用启动后预热当前产品团队")
    }

    public func ensureRuntimeSessionsForSelectedProduct() {
        runtimeSessions = runtimeSessions.filter { entry in
            agents.contains { $0.id == entry.key }
        }
        for agent in selectedProductAgents where agent.role != .boss {
            let currentSession = runtimeSessions[agent.id]
            let state = currentSession?.productID == selectedProductID ? currentSession?.state ?? .cold : .cold
            upsertRuntimeSession(for: agent, state: state)
        }
    }

    public func runtimeSession(for agentID: UUID) -> AgentRuntimeSession? {
        runtimeSessions[agentID]
    }

    public func prewarmSelectedProductAgentSessions(reason: String = "手动预热当前产品团队") {
        ensureRuntimeSessionsForSelectedProduct()
        for agent in selectedProductAgents where agent.role != .boss && !isRunning(agentID: agent.id) {
            prewarmAgentSession(agentID: agent.id, reason: reason)
        }
    }

    @discardableResult
    public func recoverStaleRuntimeSessionsForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> [UUID] {
        let threshold = max(seconds, 60)
        let now = Date()
        var recoveredIDs: [UUID] = []
        var recoveredLines: [String] = []

        for agent in selectedProductAgents {
            guard runningAgentIDs.contains(agent.id),
                  var session = runtimeSessions[agent.id],
                  session.productID == nil || session.productID == selectedProductID,
                  session.state == .busy,
                  let lastUsedAt = session.lastUsedAt
            else { continue }
            let idleSeconds = now.timeIntervalSince(lastUsedAt)
            guard idleSeconds >= threshold else { continue }

            runningAgentIDs.remove(agent.id)
            setStatus(.failed, for: agent.id)
            session.state = .timedOut
            session.failureCount += 1
            session.lastError = "异常占用会话已被手动恢复（空闲 \(Int(idleSeconds)) 秒）。"
            session.lastRestartReason = "运维手动恢复异常占用会话"
            runtimeSessions[agent.id] = session

            appendTerminalLog(
                "\n[OPC 运维恢复]\n\(agent.displayName) 已被标记为超时（空闲 \(Int(idleSeconds)) 秒）。下次运行前请确认上一轮命令是否真的结束，避免再次卡住。\n",
                for: agent.id
            )
            appendEvent(
                kind: .risk,
                title: "\(agent.displayName) 异常占用已恢复",
                detail: "运行状态已从占用中重置为已超时，等待下一次手动运行重新预热。空闲 \(Int(idleSeconds)) 秒，超过阈值 \(Int(threshold))。",
                agentID: agent.id
            )
            recoveredIDs.append(agent.id)
            recoveredLines.append("- \(agent.displayName)：空闲 \(Int(idleSeconds)) 秒 → 标记已超时")
        }

        let productLabel = selectedProduct?.name ?? "当前产品"
        let report = """
        \("异常占用会话恢复：".L())\(recoveredIDs.isEmpty ? "无需处理" : "完成 \(recoveredIDs.count) 个员工")
        \("产品：".L())\(productLabel)
        \("阈值：".L())\(Int(threshold))\(" 秒".L())
        \("恢复明细：".L())
        \(recoveredLines.isEmpty ? "- 当前没有占用中超过阈值的运行会话。" : recoveredLines.joined(separator: "\n"))

        \("说明：".L())
        \("只恢复运行状态为占用中且上次使用时间超过阈值的员工运行会话。正常占用中任务不会被打断；不会自动启动模型任务，下一次任务仍需从 OPC 运行入口手动发起，以保留预检、作业档案和验收链路。".L())
        """
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: recoveredIDs.isEmpty ? .passed : .warning,
                title: "异常占用会话恢复".L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: recoveredIDs.isEmpty ? .statusChanged : .risk,
            title: "异常占用会话恢复完成".L(),
            detail: "\(productLabel)" + " · 恢复 ".L() + "\(recoveredIDs.count)" + " 个员工".L(),
            agentID: ctoID
        )
        saveSnapshot()
        return recoveredIDs
    }

    public func employeeHandoffAuditText(staleAfter seconds: TimeInterval = 180) -> String {
        let summary = employeeHandoffAuditSummary(staleAfter: seconds)
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let header = """
        员工交接待确认巡检：\(summary.passed ? "通过".L() : (summary.staleCount > 0 ? "存在超时" : "需关注"))
        \("产品：".L())\(productLabel)
        \("总员工交接：".L())\(summary.totalCount)
        \("待确认：".L())\(summary.pendingCount)\(" · 已确认：".L())\(summary.acknowledgedCount)\(" · 超时待确认：".L())\(summary.staleCount)
        \("阈值：".L())\(Int(max(seconds, 60)))\(" 秒".L())
        """
        let body = summary.lines.isEmpty
            ? "- 当前产品没有员工交接消息。"
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("交接明细：".L())
        \(body)

        \("说明：".L())
        \("本次只读巡检，仅统计当前产品的员工交接消息，不会清理运行员工列表、不会修改交接状态、不会启动模型任务，也不会写入作业档案或新增员工协作消息。如需把待确认交接标记为已确认，请由对应员工在「我的协作收件箱」点击「标记我的消息已读」。".L())
        """
    }

    @discardableResult
    public func runEmployeeHandoffAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        let report = employeeHandoffAuditText(staleAfter: seconds)
        let summary = employeeHandoffAuditSummary(staleAfter: seconds)
        let status: VerificationStatus
        if summary.staleCount > 0 {
            status = .failed
        } else if !summary.passed {
            status = .warning
        } else {
            status = .passed
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "员工交接待确认巡检".L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        let eventKind: CompanyEventKind = status == .passed ? .statusChanged : .risk
        appendEvent(
            kind: eventKind,
            title: "员工交接待确认巡检完成".L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        if summary.staleCount > 0 {
            appendEvent(
                kind: .risk,
                title: "员工交接超时待确认".L(),
                detail: "有 ".L() + "\(summary.staleCount)" + " 条员工交接超过 ".L() + "\(Int(max(seconds, 60)))" + " 秒仍未确认。".L(),
                agentID: ctoID
            )
        }
        saveSnapshot()
        return status
    }

    private struct EmployeeHandoffAuditSummary {
        var totalCount = 0
        var pendingCount = 0
        var acknowledgedCount = 0
        var staleCount = 0
        var lines: [String] = []
        var passed: Bool { staleCount == 0 && pendingCount == 0 }
    }

    private func employeeHandoffAuditSummary(staleAfter seconds: TimeInterval) -> EmployeeHandoffAuditSummary {
        var summary = EmployeeHandoffAuditSummary()
        let threshold = max(seconds, 60)
        let now = Date()
        let handoffs = agentMessages
            .filter { $0.productID == selectedProductID && $0.kind == .employeeHandoff }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
        summary.totalCount = handoffs.count

        for envelope in handoffs {
            let fromName = agentName(envelope.fromAgentID)
            let toName = envelope.toAgentID.map(agentName) ?? "未指定".L()
            let elapsed = Int(now.timeIntervalSince(envelope.createdAt))
            switch envelope.status {
            case .pending:
                summary.pendingCount += 1
                let isStale = TimeInterval(elapsed) >= threshold
                if isStale {
                    summary.staleCount += 1
                    summary.lines.append("- 超时：".L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)" + "（" + "\(elapsed)" + " 秒未确认）")
                } else {
                    summary.lines.append("- 待确认：".L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)" + "（" + "\(elapsed)" + " 秒）".L())
                }
            case .acknowledged:
                summary.acknowledgedCount += 1
                summary.lines.append("- 已确认：".L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)")
            case .failed:
                summary.lines.append("- 失败：".L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)")
            }
        }
        return summary
    }

    public func jobArchiveStaleAuditText(staleAfter seconds: TimeInterval = 180) -> String {
        let summary = jobArchiveStaleAuditSummary(staleAfter: seconds)
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let header = """
        命令行作业幽灵巡检：\(summary.passed ? "通过".L() : "需处理")
        \("产品：".L())\(productLabel)
        \("作业档案：".L())\(summary.totalCount)
        \("运行中：".L())\(summary.runningCount)\(" · 幽灵运行：".L())\(summary.staleGhostCount)\(" · 真实运行：".L())\(summary.activeRunningCount)\(" · 未超时：".L())\(summary.freshRunningCount)\(" · 无法读取：".L())\(summary.invalidCount)
        \("阈值：".L())\(Int(max(seconds, 60)))\(" 秒".L())
        """
        let body = summary.lines.isEmpty
            ? "- 当前产品没有命令行作业档案。"
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("作业档案明细：".L())
        \(body)

        \("说明：".L())
        \("本次预览只扫描当前产品根目录的命令行作业档案。实际巡检只会把已经超时、仍标记运行中、但没有员工运行占用的旧作业标记为已中断；不会启动模型任务、不会写老板聊天、不会新增员工协作消息。".L())
        """
    }

    @discardableResult
    public func runJobArchiveStaleAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        var summary = jobArchiveStaleAuditSummary(staleAfter: seconds)
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var interruptedLines: [String] = []
        var interruptedCount = 0
        let reportBefore = jobArchiveStaleAuditText(staleAfter: seconds)

        for record in summary.staleGhostRecords {
            do {
                if try interruptCLIJobArchive(record, now: now, formatter: formatter) {
                    let elapsed = Int(now.timeIntervalSince(record.updatedAt))
                    interruptedLines.append("- " + "\(record.visibleName)" + "：已标记已中断（静置 ".L() + "\(elapsed)" + " 秒）".L())
                    interruptedCount += 1
                } else {
                    interruptedLines.append("- " + "\(record.visibleName)" + "：磁盘状态已变化，跳过写回。".L())
                }
            } catch {
                summary.invalidCount += 1
                interruptedLines.append("- " + "\(record.visibleName)" + "：写回失败，".L() + "\(error.localizedDescription)")
            }
        }

        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let status: VerificationStatus = (summary.staleGhostCount == 0 && summary.invalidCount == 0) ? .passed : .warning
        let report = """
        \(reportBefore)

        \("处理结果：".L())
        \(interruptedLines.isEmpty ? "- 没有需要中断的幽灵作业档案。".L() : interruptedLines.joined(separator: "\n"))
        """
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "命令行作业幽灵巡检",
                detail: report
            ),
            at: 0
        )
        appendEvent(
            kind: .statusChanged,
            title: "命令行作业幽灵巡检完成",
            detail: "\(productLabel) · 中断 \(interruptedCount) 个幽灵作业 · \(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }

    private struct CLIJobArchiveAuditSummary {
        var totalCount = 0
        var runningCount = 0
        var staleGhostCount = 0
        var activeRunningCount = 0
        var freshRunningCount = 0
        var invalidCount = 0
        var lines: [String] = []
        var staleGhostRecords: [CLIJobArchiveRecord] = []
        var passed: Bool { staleGhostCount == 0 && invalidCount == 0 }
    }

    private struct CLIJobArchiveRecord {
        var jobID: String
        var directory: URL
        var statusURL: URL
        var visibleName: String
        var agentID: UUID?
        var productID: UUID?
        var state: String
        var updatedAt: Date
        var status: [String: Any]
    }

    private func jobArchiveStaleAuditSummary(staleAfter seconds: TimeInterval) -> CLIJobArchiveAuditSummary {
        var summary = CLIJobArchiveAuditSummary()
        let threshold = max(seconds, 60)
        let now = Date()
        let jobsRoot = cliWorkingDirectoryURL().appendingPathComponent(".opc/jobs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: jobsRoot.path) else {
            return summary
        }

        let jobDirectories: [URL]
        do {
            jobDirectories = try FileManager.default.contentsOfDirectory(
                at: jobsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            summary.invalidCount += 1
            summary.lines.append("- 无法读取作业目录：\(error.localizedDescription)")
            return summary
        }

        summary.totalCount = jobDirectories.count
        for (offset, directory) in jobDirectories.enumerated() {
            let visibleName = "作业 \(offset + 1)"
            let statusURL = directory.appendingPathComponent("status.json")
            do {
                var record = try readCLIJobArchiveRecord(directory: directory, statusURL: statusURL)
                record.visibleName = visibleName
                guard let productID = record.productID else {
                    summary.invalidCount += 1
                    summary.lines.append("- 无法读取：\(record.visibleName)，缺少产品归属。")
                    continue
                }
                if productID != selectedProductID {
                    continue
                }
                guard cliJobStateIsRunning(record.state) else {
                    summary.lines.append("- 已结束：\(record.visibleName)（\(cliJobStateDisplayName(record.state))）")
                    continue
                }

                summary.runningCount += 1
                let elapsed = now.timeIntervalSince(record.updatedAt)
                let agentLabel = record.agentID.map(agentName) ?? "未知员工"
                let isStillOccupied = record.agentID.map { agentID in
                    let session = runtimeSessions[agentID]
                    let sessionBelongsToCurrentProduct = session?.productID == nil || session?.productID == selectedProductID
                    let sessionBusy = sessionBelongsToCurrentProduct && session?.state == .busy
                    let runningFlagCanRepresentCurrentProduct = runningAgentIDs.contains(agentID) && sessionBelongsToCurrentProduct
                    return sessionBusy || runningFlagCanRepresentCurrentProduct
                } ?? false

                if isStillOccupied {
                    summary.activeRunningCount += 1
                    summary.lines.append("- 真实运行：\(record.visibleName)（\(agentLabel)，\(Int(elapsed)) 秒，有运行占用）")
                } else if elapsed >= threshold {
                    summary.staleGhostCount += 1
                    summary.staleGhostRecords.append(record)
                    summary.lines.append("- 幽灵运行：\(record.visibleName)（\(agentLabel)，\(Int(elapsed)) 秒，无运行占用）")
                } else {
                    summary.freshRunningCount += 1
                    summary.lines.append("- 未超时：\(record.visibleName)（\(agentLabel)，\(Int(elapsed)) 秒，无运行占用）")
                }
            } catch {
                summary.invalidCount += 1
                summary.lines.append("- 无法读取：\(visibleName)，作业档案格式或权限异常。")
            }
        }

        return summary
    }

    private func readCLIJobArchiveRecord(directory: URL, statusURL: URL) throws -> CLIJobArchiveRecord {
        let data = try Data(contentsOf: statusURL)
        guard var status = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let jobID = stringValue(in: status, keys: ["job_id", "jobID", "作业编号"]) ?? directory.lastPathComponent
        let state = stringValue(in: status, keys: ["state", "status", "状态"]) ?? "unknown"
        let agentID = uuidValue(in: status, keys: ["agent_id", "agentID", "员工ID"])
        let productID = uuidValue(in: status, keys: ["product_id", "productID", "产品ID"])
        let updatedText = stringValue(in: status, keys: ["updated_at", "updatedAt", "更新时间"])
        let updatedAt = updatedText.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? ((try? FileManager.default.attributesOfItem(atPath: statusURL.path)[.modificationDate]) as? Date)
            ?? Date.distantPast

        if status["job_id"] == nil {
            status["job_id"] = jobID
        }

        return CLIJobArchiveRecord(
            jobID: jobID,
            directory: directory,
            statusURL: statusURL,
            visibleName: jobID,
            agentID: agentID,
            productID: productID,
            state: state,
            updatedAt: updatedAt,
            status: status
        )
    }

    @discardableResult
    private func interruptCLIJobArchive(_ record: CLIJobArchiveRecord, now: Date, formatter: ISO8601DateFormatter) throws -> Bool {
        let latest = try readCLIJobArchiveRecord(directory: record.directory, statusURL: record.statusURL)
        guard latest.productID == selectedProductID, cliJobStateIsRunning(latest.state) else {
            return false
        }
        var status = latest.status
        status["previous_state"] = record.state
        status["state"] = "interrupted"
        status["exit_code"] = NSNull()
        status["interrupted_at"] = formatter.string(from: now)
        status["updated_at"] = formatter.string(from: now)
        status["interruption_reason"] = "OPC 运维巡检发现该作业仍标记运行中，但当前产品没有对应员工运行占用。"
        let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: record.statusURL, options: .atomic)

        let archivePath = record.directory.standardizedFileURL.path
        if let index = artifacts.firstIndex(where: {
            $0.productID == selectedProductID && URL(fileURLWithPath: $0.path).standardizedFileURL.path == archivePath
        }) {
            artifacts[index].summary = "已中断 · 幽灵巡检已标记。"
        }
        return true
    }

    private func cliJobStateIsRunning(_ state: String) -> Bool {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "running" || normalized == "运行中"
    }

    private func cliJobStateDisplayName(_ state: String) -> String {
        switch state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running", "运行中": "运行中"
        case "completed", "done", "完成", "已完成": "已完成"
        case "failed", "失败": "失败"
        case "interrupted", "中断", "已中断": "已中断"
        default: "未知状态"
        }
    }

    private func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private func uuidValue(in dictionary: [String: Any], keys: [String]) -> UUID? {
        stringValue(in: dictionary, keys: keys).flatMap(UUID.init(uuidString:))
    }

    public func runtimeSessionHealthAuditText(staleAfter seconds: TimeInterval = 180) -> String {
        let summary = runtimeSessionHealthAuditSummary(staleAfter: seconds)
        let productLabel = selectedProduct?.name ?? "当前产品"
        let header = """
        \("运行会话健康巡检：".L())\(summary.passed ? "通过" : "需关注")
        \("产品：".L())\(productLabel)
        \("可执行员工：".L())\(summary.lines.count)
        \("失败次数合计：".L())\(summary.totalFailureCount)
        \("缺命令：".L())\(summary.commandMissingCount)\(" · 来源漂移：".L())\(summary.backendDriftCount)\(" · 产品漂移：".L())\(summary.productDriftCount)\(" · 缺会话：".L())\(summary.missingSessionCount)\(" · 授权异常：".L())\(summary.authenticationBlockedCount)\(" · 异常占用：".L())\(summary.staleBusyCount)
        \("阈值：".L())\(Int(max(seconds, 60)))\(" 秒".L())
        """
        let body = summary.lines.isEmpty
            ? "- 当前产品没有可执行员工。".L()
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("员工运行会话明细：".L())
        \(body)

        \("说明：".L())
        \("本次只读巡检，不会清理正在运行的员工列表、不会改员工状态、不会启动模型任务，也不会写入作业档案或员工协作消息。需要恢复异常占用请使用「恢复异常占用员工会话」按钮，需要重开会话请用员工档案里的会话操作。".L())
        """
    }

    @discardableResult
    public func runRuntimeSessionHealthAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        let report = runtimeSessionHealthAuditText(staleAfter: seconds)
        let summary = runtimeSessionHealthAuditSummary(staleAfter: seconds)
        let status: VerificationStatus = summary.passed ? .passed : .warning
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "运行会话健康巡检",
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .passed ? .statusChanged : .risk,
            title: "运行会话健康巡检完成",
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }

    public func historyIndexAuditText() -> String {
        let productLabel = selectedProduct?.name ?? "当前产品"
        let indexURL = CompanyPersistence.historyIndexURL
        let fileExists = FileManager.default.fileExists(atPath: indexURL.path)
        let stats = try? CompanyHistorySQLiteIndex.stats(at: indexURL)
        let productResultCount = (try? CompanyHistorySQLiteIndex.search(at: indexURL, query: productLabel, productID: selectedProductID, limit: 100).count) ?? 0
        let indexedAt = stats?.lastIndexedAt?.opcDateTimeText ?? "尚未生成"
        let statusText: String
        if let stats, stats.recordCount > 0 {
            statusText = "通过"
        } else if fileExists {
            statusText = "需重建"
        } else {
            statusText = "未创建"
        }

        return """
        \("历史索引巡检：".L())\(statusText)
        \("产品：".L())\(productLabel)
        \("索引位置：".L())\(indexURL.path)
        \("索引文件：".L())\(fileExists ? "已存在" : "未创建")
        \("记录数：".L())\(stats?.recordCount ?? 0)
        \("产品数：".L())\(stats?.productCount ?? 0)
        \("最近索引：".L())\(indexedAt)
        \("当前产品可检索记录：".L())\(productResultCount)

        \("说明：".L())
        \("主快照仍是权威状态；本地历史索引只作为可重建的查询层，用于大规模消息、事件、任务、审批、产物、验收、记忆、通信日志和员工协作消息检索。索引损坏时可以直接重建，不影响产品主状态。".L())
        """
    }

    @discardableResult
    public func runHistoryIndexAuditForSelectedProduct() -> VerificationStatus {
        let status: VerificationStatus
        let report: String
        do {
            let stats = try CompanyPersistence.rebuildHistoryIndex(currentSnapshot())
            status = stats.recordCount > 0 ? .passed : .warning
            report = """
            \("历史索引巡检：".L())\(status.title)
            产品：\(selectedProduct?.name ?? "当前产品".L())
            \("索引位置：".L())\(CompanyPersistence.historyIndexURL.path)
            \("记录数：".L())\(stats.recordCount)
            \("产品数：".L())\(stats.productCount)
            \("最近索引：".L())\(stats.lastIndexedAt?.opcDateTimeText ?? "刚刚完成")

            \("说明：".L())
            \("本次已从当前主快照重建本地历史索引。主快照仍是权威状态；历史索引只作为可重建查询层，不替代主状态存储。".L())
            """
        } catch {
            status = .failed
            report = """
            \("历史索引巡检：失败".L())
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("索引位置：".L())\(CompanyPersistence.historyIndexURL.path)
            \("错误：".L())\(error.localizedDescription)

            \("说明：".L())
            \("主快照没有被修改；本地历史索引只是可重建查询层。本次失败表示历史检索不可用，但不会影响当前产品状态读写。".L())
            """
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "历史索引巡检".L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .failed ? .risk : .statusChanged,
            title: "历史索引巡检完成".L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }

    public func historyArchiveMigrationText(retentionDays: Int = 30) -> String {
        let safeDays = max(retentionDays, 1)
        let cutoffAt = Date(timeIntervalSinceNow: -TimeInterval(safeDays * 24 * 60 * 60))
        let archiveStats = try? CompanyPersistence.historyArchiveStats()
        let archiveCount = archiveStats?.archivedRecordCount ?? 0
        let archivedAt = archiveStats?.lastArchivedAt?.opcDateTimeText ?? (archiveCount > 0 ? "未知（旧归档表）".L() : "尚未迁移".L())
        return """
        \("历史归档迁移：预览".L())
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
        \("已归档记录：".L())\(archiveCount)
        \("最近归档：".L())\(archivedAt)

        \("说明：".L())
        \("本迁移只把旧消息、事件、通信日志和员工协作消息复制到本地归档表；主快照仍是权威状态，本轮不会裁剪主快照、不会删除本地文件、不会启动模型任务。归档表可由主快照重建，归档失败不影响产品主状态。".L())
        """
    }

    @discardableResult
    public func runHistoryArchiveMigrationForSelectedProduct(retentionDays: Int = 30) -> VerificationStatus {
        let safeDays = max(retentionDays, 1)
        let cutoffAt = Date(timeIntervalSinceNow: -TimeInterval(safeDays * 24 * 60 * 60))
        let status: VerificationStatus
        let report: String
        do {
            let stats = try CompanyPersistence.archiveHistory(currentSnapshot(), olderThan: cutoffAt)
            status = .passed
            report = """
            \("历史归档迁移：通过".L())
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
            \("写入归档记录：".L())\(stats.archivedRecordCount)
            \("覆盖产品数：".L())\(stats.productCount)
            \("最近归档：".L())\(stats.lastArchivedAt?.opcDateTimeText ?? "刚刚完成")

            \("说明：".L())
            \("本次只把旧消息、事件、通信日志和员工协作消息复制到本地归档表；主快照仍是权威状态，本轮不裁剪主快照、不删除本地文件、不启动模型任务。后续只有在快照体积和加载性能达到阈值时，才考虑安全裁剪主快照中的旧历史。".L())
            """
        } catch {
            status = .failed
            report = """
            \("历史归档迁移：失败".L())
            产品：\(selectedProduct?.name ?? "当前产品".L())
            \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
            \("错误：".L())\(error.localizedDescription)

            \("说明：".L())
            \("主快照没有被修改；本地归档表只是可重建的历史迁移层。本次失败不会影响当前产品状态读写。".L())
            """
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "历史归档迁移",
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .failed ? .risk : .statusChanged,
            title: "历史归档迁移完成",
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }

    private struct RuntimeSessionHealthSummary {
        var lines: [String] = []
        var commandMissingCount = 0
        var backendDriftCount = 0
        var productDriftCount = 0
        var missingSessionCount = 0
        var authenticationBlockedCount = 0
        var staleBusyCount = 0
        var failedSessionCount = 0
        var totalFailureCount = 0
        var passed: Bool {
            commandMissingCount == 0
                && backendDriftCount == 0
                && productDriftCount == 0
                && missingSessionCount == 0
                && authenticationBlockedCount == 0
                && staleBusyCount == 0
                && failedSessionCount == 0
        }
    }

    private func runtimeSessionHealthAuditSummary(staleAfter seconds: TimeInterval) -> RuntimeSessionHealthSummary {
        var summary = RuntimeSessionHealthSummary()
        let threshold = max(seconds, 60)
        let now = Date()
        let agentsToInspect = executableAgents

        for agent in agentsToInspect {
            var notes: [String] = []
            let expectedSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
            let expectedCapability = CLIAgentCommandBuilder.runtimeCapability(for: agent)

            // Command resolvability
            switch agent.backend.type {
            case .subscriptionCLI:
                let trimmedCommand = agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCommand.isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("命令为空")
                } else if AgentProcessRunner.resolvedExecutablePath(for: trimmedCommand) == nil {
                    summary.commandMissingCount += 1
                    notes.append("命令不可解析：\(trimmedCommand)")
                }
            case .api:
                if agent.backend.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口地址未配置")
                }
                if agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口密钥未配置")
                }
                if agent.backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口模型未配置")
                }
            case .local:
                notes.append("本地占位")
            }

            // Session presence + drift
            let stateLabel: String
            let capabilityLabel: String
            let backendLabel: String
            if let session = runtimeSessions[agent.id] {
                stateLabel = session.state.title
                capabilityLabel = session.capability.title
                backendLabel = session.backendSignature == expectedSignature ? "匹配" : "不匹配"
                if let sessionProductID = session.productID, sessionProductID != selectedProductID {
                    summary.productDriftCount += 1
                    notes.append("产品漂移：会话属于其他产品")
                }
                if session.backendSignature != expectedSignature {
                    summary.backendDriftCount += 1
                    notes.append("来源漂移：员工档案和当前会话的来源配置不一致")
                }
                if session.capability != expectedCapability {
                    summary.backendDriftCount += 1
                    notes.append("能力漂移：会话能力 \(session.capability.title) ≠ 当前 \(expectedCapability.title)")
                }
                summary.totalFailureCount += session.failureCount
                if session.state == .failed {
                    summary.failedSessionCount += 1
                    notes.append("最近一次会话失败")
                }
                if !session.lastError.isEmpty {
                    notes.append("最近错误：\(session.lastError.prefix(80))")
                }
                if session.cliInteractionPhase == .authenticationBlocked {
                    summary.authenticationBlockedCount += 1
                    let hint = session.cliInteractionOperatorHint ?? CLIInteractionRecoveryAction.checkAuthentication.operatorHint ?? "请确认登录授权后再重新发起任务。"
                    notes.append("授权异常：\(hint)")
                }
                if session.state == .busy, let lastUsedAt = session.lastUsedAt {
                    let idle = now.timeIntervalSince(lastUsedAt)
                    if idle >= threshold {
                        summary.staleBusyCount += 1
                        notes.append("运行占用已持续 \(Int(idle)) 秒，超过阈值 \(Int(threshold))（提示，本次不恢复）")
                    }
                }
            } else {
                summary.missingSessionCount += 1
                stateLabel = "无会话"
                capabilityLabel = "—"
                backendLabel = "未检查"
                notes.append("缺少运行会话，员工档案需先预热")
            }

            let noteSuffix = notes.isEmpty ? "正常" : notes.joined(separator: "；")
            summary.lines.append(
                "- \(agent.displayName)（\(agent.role.title)）：状态 \(stateLabel) · 能力 \(capabilityLabel) · 运行来源 \(backendLabel) · \(noteSuffix)"
            )
        }

        return summary
    }

    public func restartAgentSession(agentID: UUID, reason: String = "手动重开会话") {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return }
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.state = .restarting
        session.restartCount += 1
        session.lastRestartReason = reason
        session.lastError = ""
        runtimeSessions[agent.id] = session
        appendEvent(kind: .statusChanged, title: "\(agent.displayName) 会话重开", detail: reason, agentID: agent.id)
        prewarmAgentSession(agentID: agent.id, reason: reason)
    }

    public func isRunning(agentID: UUID) -> Bool {
        runningAgentIDs.contains(agentID)
    }

    public func clearTerminalLog(for agentID: UUID) {
        setTerminalLog("", for: agentID)
        appendEvent(kind: .statusChanged, title: "终端日志已清空", detail: "\(agentName(agentID)) 的终端日志已清空。", agentID: agentID)
        saveSnapshot()
    }

    private func newRuntimeSession(for agent: CompanyAgent, state: AgentRuntimeState = .cold) -> AgentRuntimeSession {
        AgentRuntimeSession(
            agentID: agent.id,
            productID: selectedProductID,
            state: agent.backend.type == .local ? .unavailable : state,
            capability: CLIAgentCommandBuilder.runtimeCapability(for: agent),
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: agent)
        )
    }

    private func upsertRuntimeSession(for agent: CompanyAgent, state: AgentRuntimeState? = nil) {
        let signature = CLIAgentCommandBuilder.backendSignature(for: agent)
        let capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent, state: state ?? .cold)
        if session.backendSignature != signature || session.capability != capability || session.productID != selectedProductID {
            let retainedCLIConversations = session.cliSessionsByProduct
            session = newRuntimeSession(for: agent, state: .cold)
            session.cliSessionsByProduct = retainedCLIConversations
            session.lastRestartReason = "产品、来源、模型或思考强度已变化，需要重新预热。"
        } else if let state {
            session.state = state
        }
        session.productID = selectedProductID
        session.capability = capability
        session.backendSignature = signature
        runtimeSessions[agent.id] = session
    }

    private func markRuntimeBusy(for agent: CompanyAgent) {
        upsertRuntimeSession(for: agent)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.state = .busy
        session.lastUsedAt = Date()
        session.lastError = ""
        runtimeSessions[agent.id] = session
    }

    private func markRuntimeFinished(for agent: CompanyAgent, result: CommandExecutionResult, context: String) {
        upsertRuntimeSession(for: agent)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.lastUsedAt = Date()
        if result.exitCode == 0 {
            session.state = .ready
            session.lastError = ""
            session.failureCount = 0
        } else if result.exitCode == 124 {
            session.state = .timedOut
            session.failureCount += 1
            session.lastError = "超时：\(context)"
            runtimeSessions[agent.id] = session
            restartAgentSessionIfNeeded(agent: agent, reason: "上次 \(context) 超时，重开会话。")
            return
        } else {
            session.state = .failed
            session.failureCount += 1
            session.lastError = displayableChatError(from: result.combinedOutput)
            runtimeSessions[agent.id] = session
            if shouldAutomaticallyRestartSession(after: result, agent: agent) {
                restartAgentSessionIfNeeded(agent: agent, reason: "上次 \(context) 异常退出，重开会话。")
            }
            return
        }
        runtimeSessions[agent.id] = session
    }

    private func restartAgentSessionIfNeeded(agent: CompanyAgent, reason: String) {
        guard !isRunning(agentID: agent.id) else { return }
        let failures = runtimeSessions[agent.id]?.failureCount ?? 0
        guard failures <= 2 else {
            appendEvent(kind: .risk, title: "\(agent.displayName) 会话未自动重开", detail: "连续失败 \(failures) 次，请先检查登录、网络或模型配置。", agentID: agent.id)
            return
        }
        restartAgentSession(agentID: agent.id, reason: reason)
    }

    private func shouldAutomaticallyRestartSession(after result: CommandExecutionResult, agent: CompanyAgent) -> Bool {
        if let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) {
            let observation = CLIInteractionStateMachine.observe(output: result.combinedOutput, profile: profile, previousPhase: .awaitingResponse)
            if observation.phase == .authenticationBlocked || observation.phase == .busy {
                return false
            }
        }
        let output = result.combinedOutput.lowercased()
        if result.exitCode == 124 { return true }
        let restartMarkers = [
            "broken pipe",
            "connection reset",
            "connection refused",
            "timed out",
            "timeout",
            "not inside a trusted directory",
            "failed to fetch",
            "ssl",
            "bad record mac",
            "session expired",
            "session terminated",
            "session not found",
            "session unavailable",
            "thread"
        ]
        return restartMarkers.contains { output.contains($0) }
    }

    private func prewarmAgentSession(agentID: UUID, reason: String) {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else { return }
        upsertRuntimeSession(for: agent, state: .prewarming)

        if agent.backend.type == .local {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            session.state = .unavailable
            session.lastError = "本地占位员工没有可预热的真实模型来源。"
            runtimeSessions[agent.id] = session
            return
        }

        if agent.backend.type == .api {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            if canUseLiveChatBackend(agent) {
                session.state = .ready
                session.lastPrewarmedAt = Date()
                session.lastError = ""
            } else {
                session.state = .failed
                session.failureCount += 1
                session.lastError = "接口地址、密钥或模型名未配置完整。"
            }
            runtimeSessions[agent.id] = session
            return
        }

        let command = CLIAgentCommandBuilder.prewarmCommand(for: agent)
        guard let executable = command.first, !executable.isEmpty else {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            session.state = .failed
            session.failureCount += 1
            session.lastError = "没有可用的预热命令。"
            runtimeSessions[agent.id] = session
            return
        }

        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.lastPrewarmedAt = Date()
        session.startedAt = session.startedAt ?? Date()
        if let resolved = AgentProcessRunner.resolvedExecutablePath(for: executable) {
            session.state = .ready
            session.lastError = ""
            session.failureCount = 0
            runtimeSessions[agent.id] = session
            appendTerminalLog("\n[OPC 会话预热]\n原因：\(reason)\n本地命令已就绪：\(opcBackendCommandDisplayName(resolved))\n持续协作：\(session.capability.title)。\n", for: agent.id)
            appendEvent(kind: .statusChanged, title: "\(agent.displayName) 会话已就绪", detail: "已确认本地命令行可执行；预热记录已写入终端大厅。", agentID: agent.id)
        } else {
            session.state = .failed
            session.failureCount += 1
            session.lastError = "找不到可执行命令：\(executable)。请检查命令行工具安装路径。"
            runtimeSessions[agent.id] = session
            appendEvent(kind: .risk, title: "\(agent.displayName) 会话预热失败", detail: session.lastError, agentID: agent.id)
        }
        saveSnapshot()
    }

    public func updateSelectedAgentIdentity(displayName: String? = nil, title: String? = nil, role: AgentRole? = nil, reportsToCTO: Bool? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanName, !cleanName.isEmpty {
            agents[index].displayName = cleanName
        }
        if let cleanTitle, !cleanTitle.isEmpty {
            agents[index].title = cleanTitle
        }
        if let role {
            if agents[index].id == ctoID {
                agents[index].role = .cto
            } else if agents[index].id == bossID {
                agents[index].role = .boss
            } else {
                agents[index].role = role
            }
        }
        if let reportsToCTO {
            agents[index].reportsToCTO = agents[index].role == .boss || agents[index].role == .cto ? false : reportsToCTO
        }
        if agentProfiles[agents[index].id] == nil {
            agentProfiles[agents[index].id] = AgentOperatingProfile.defaultProfile(for: agents[index])
        }
        syncAgentWorkspace(for: agents[index].id)
        appendEvent(kind: .statusChanged, title: "员工身份已更新", detail: "\(agents[index].displayName) 的姓名、职位、角色或汇报关系已更新。", agentID: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentPermission(_ permission: AgentPermission, isEnabled: Bool) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if isEnabled {
            agents[index].permissions.insert(permission)
        } else {
            agents[index].permissions.remove(permission)
        }
        appendEvent(kind: .statusChanged, title: "员工权限已更新", detail: "\(agents[index].displayName)：\(permission.title) \(isEnabled ? "已开启" : "已关闭")。", agentID: agents[index].id)
        syncAgentWorkspace(for: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentBackend(type: BackendType? = nil, command: String? = nil, model: String? = nil, endpoint: String? = nil, apiKey: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if let type {
            agents[index].backend.type = type
            switch type {
            case .api:
                agents[index].backend.command = "api-agent"
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "sonnet"
                    || agents[index].backend.model == "gemini-cli"
                    || agents[index].backend.model == "local" {
                    agents[index].backend.model = "gpt-5.5"
                }
                agents[index].permissions.insert(.useNetwork)
            case .subscriptionCLI:
                if agents[index].backend.command.isEmpty
                    || agents[index].backend.command == "api-agent"
                    || agents[index].backend.command == "local" {
                    agents[index].backend.command = "claude"
                }
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "gpt-5.5"
                    || agents[index].backend.model == "local" {
                    agents[index].backend.model = "sonnet"
                }
            case .local:
                agents[index].backend.command = "local"
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "sonnet"
                    || agents[index].backend.model == "gpt-5.5"
                    || agents[index].backend.model == "gemini-cli" {
                    agents[index].backend.model = "local"
                }
            }
        }
        if let command {
            agents[index].backend.command = command
        }
        if let model {
            agents[index].backend.model = model
        }
        if let endpoint {
            agents[index].backend.endpoint = endpoint
        }
        if let apiKey {
            agents[index].backend.apiKey = apiKey
        }
        if let reasoningEffort {
            agents[index].backend.reasoningEffort = reasoningEffort
        }
        upsertRuntimeSession(for: agents[index], state: .cold)
        if runtimeSupervisorStarted && selectedProductAgents.contains(where: { $0.id == agents[index].id }) {
            prewarmAgentSession(agentID: agents[index].id, reason: "模型配置变更后重新预热")
        }
        appendEvent(kind: .statusChanged, title: "模型配置已更新", detail: "\(agents[index].displayName) 的模型配置已更新。", agentID: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentAppearance(ethnicity: EthnicityPresentation? = nil, gender: GenderPresentation? = nil, clothing: ClothingStyle? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if let ethnicity {
            agents[index].ethnicity = ethnicity
        }
        if let gender {
            agents[index].gender = gender
        }
        if let clothing {
            agents[index].clothing = clothing
        }
        appendEvent(kind: .statusChanged, title: "员工外观已更新", detail: "\(agents[index].displayName) 的人物、性别或着装配置已更新。", agentID: agents[index].id)
        syncAgentWorkspace(for: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentProfile(mission: String? = nil, responsibilitiesText: String? = nil, boundariesText: String? = nil, responseRulesText: String? = nil, memoryText: String? = nil, skillsText: String? = nil) {
        guard let agent = selectedAgent else { return }
        var profile = operatingProfile(for: agent.id)
        if let mission {
            profile.mission = mission
        }
        if let responsibilitiesText {
            profile.responsibilities = listItems(from: responsibilitiesText)
        }
        if let boundariesText {
            profile.boundaries = listItems(from: boundariesText)
        }
        if let responseRulesText {
            profile.responseRules = listItems(from: responseRulesText)
        }
        if let memoryText {
            profile.memory = listItems(from: memoryText)
        }
        if let skillsText {
            profile.skills = listItems(from: skillsText)
        }
        agentProfiles[agent.id] = profile
        syncAgentWorkspace(for: agent.id)
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "员工操作档案已更新。")
        appendEvent(kind: .statusChanged, title: "员工操作档案已更新", detail: "\(agent.displayName) 的角色、记忆和规则已更新。", agentID: agent.id)
        saveSnapshot()
    }

    public func ensureCommunicationGatewayPlan() {
        let productID = selectedProductID
        let existingKinds = Set(communicationChannels.filter { $0.productID == productID }.map(\.kind))
        let leadID = teamLeadAgentIDForSelectedProduct()
        let defaults: [CommunicationChannelConfig] = [
            CommunicationChannelConfig(productID: productID, name: "本地 OPC 指挥台", kind: .localOnly, teamLeadAgentID: leadID, isEnabled: true, reportsEnabled: true, commandsEnabled: true),
            CommunicationChannelConfig(productID: productID, name: "飞书手机汇报群", kind: .feishuWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "企业微信项目群", kind: .wecomWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "钉钉老板通知群", kind: .dingtalkWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "Telegram 双向指令", kind: .telegramBot, teamLeadAgentID: leadID, commandsEnabled: true),
            CommunicationChannelConfig(productID: productID, name: "邮件日报", kind: .emailDigest, teamLeadAgentID: leadID)
        ]
        let missing = defaults.filter { !existingKinds.contains($0.kind) }
        guard !missing.isEmpty else { return }
        communicationChannels.append(contentsOf: missing)
        appendEvent(kind: .statusChanged, title: "OPC 通信网关已规划", detail: "已为当前产品创建 \(missing.count) 个通信通道配置。", agentID: leadID)
        saveSnapshot()
    }

    public func updateCommunicationChannel(_ id: UUID, endpoint: String? = nil, chatID: String? = nil, isEnabled: Bool? = nil, reportsEnabled: Bool? = nil, commandsEnabled: Bool? = nil) {
        guard let index = communicationChannels.firstIndex(where: { $0.id == id }) else { return }
        if let endpoint {
            communicationChannels[index].endpoint = endpoint
        }
        if let chatID {
            communicationChannels[index].chatID = chatID
        }
        if let isEnabled {
            communicationChannels[index].isEnabled = isEnabled
        }
        if let reportsEnabled {
            communicationChannels[index].reportsEnabled = reportsEnabled
        }
        if let commandsEnabled {
            communicationChannels[index].commandsEnabled = commandsEnabled
        }
        communicationChannels[index].updatedAt = Date()
        appendEvent(kind: .statusChanged, title: "通信通道已更新", detail: "\(communicationChannels[index].name) 配置已更新。", agentID: communicationChannels[index].teamLeadAgentID)
        saveSnapshot()
    }

    public func sendTeamLeadReportThroughGateway() {
        ensureCommunicationGatewayPlan()
        guard let product = selectedProduct else { return }
        let leadID = teamLeadAgentIDForSelectedProduct()
        let leadName = leadID.map(agentName) ?? "团队负责人"
        let enabledChannels = selectedProductCommunicationChannels.filter { $0.isEnabled && $0.reportsEnabled && $0.kind.supportsOutboundReport }
        let readyChannels = enabledChannels.filter(communicationChannelCanDispatch)
        let blockedChannels = enabledChannels.filter { !communicationChannelCanDispatch($0) }
        let status: CommunicationLogStatus = readyChannels.isEmpty || !blockedChannels.isEmpty ? .queued : .sent
        let targetNames: String
        if enabledChannels.isEmpty {
            targetNames = "暂无已启用通道，先进入本地队列"
        } else if readyChannels.isEmpty {
            targetNames = "已启用通道缺少接口地址或聊天标识，暂存待发送"
        } else if blockedChannels.isEmpty {
            targetNames = readyChannels.map(\.name).joined(separator: "、")
        } else {
            targetNames = "\(readyChannels.map(\.name).joined(separator: "、"))；\(blockedChannels.count) 个通道缺少配置"
        }
        let body = """
        \(product.name)\(" 团队负责人汇报".L())
        \("负责人：".L())\(leadName)
        \("阶段：".L())\(product.stage.title)
        \("任务：".L())\(selectedProductTasks.count)\(" 个，未完成 ".L())\(selectedProductTasks.filter { $0.status != .done && $0.status != .canceled }.count)\(" 个".L())
        \("工作队列：".L())\(selectedProductWorkQueue.count)\(" 个".L())
        \("风险事件：".L())\(selectedProductBossRiskEvents.count)\(" 个".L())
        \("下一步：技术负责人继续拆解、派发、验收，并把重要进展同步给老板。".L())
        \("通道：".L())\(targetNames)
        """
        communicationLogs.insert(CommunicationLogEntry(channelID: readyChannels.first?.id ?? enabledChannels.first?.id, productID: selectedProductID, agentID: leadID, direction: .outbound, status: status, title: "团队负责人手机汇报".L(), body: body), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID ?? ctoID, author: .system, text: "OPC 通信网关已生成团队负责人汇报：\n".L() + "\(body)"))
        appendEvent(kind: .ctoSummary, title: "通信网关汇报".L(), detail: "已生成 " + "\(product.name)" + " 的团队负责人手机汇报。", agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
    }

    public func dispatchTeamLeadReportThroughGateway() {
        Task { @MainActor in
            await dispatchTeamLeadReportThroughGateway(session: .shared)
        }
    }

    public func dispatchTeamLeadReportThroughGateway(session: URLSession) async {
        ensureCommunicationGatewayPlan()
        guard let product = selectedProduct else { return }
        let leadID = teamLeadAgentIDForSelectedProduct()
        let leadName = leadID.map(agentName) ?? "团队负责人".L()
        let body = """
        \(product.name)\(" 团队负责人汇报".L())
        \("负责人：".L())\(leadName)
        \("阶段：".L())\(product.stage.title)
        \("任务：".L())\(selectedProductTasks.count)\(" 个，未完成 ".L())\(selectedProductTasks.filter { $0.status != .done && $0.status != .canceled }.count)\(" 个".L())
        \("工作队列：".L())\(selectedProductWorkQueue.count)\(" 个".L())
        \("风险事件：".L())\(selectedProductBossRiskEvents.count)\(" 个".L())
        \("下一步：技术负责人继续拆解、派发、验收，并把重要进展同步给老板。".L())
        """
        let readyChannels = selectedProductCommunicationChannels.filter {
            $0.isEnabled && $0.reportsEnabled && $0.kind.supportsOutboundReport && communicationChannelCanDispatch($0)
        }
        guard !readyChannels.isEmpty else {
            communicationLogs.insert(CommunicationLogEntry(
                productID: selectedProductID,
                agentID: leadID,
                direction: .outbound,
                status: .queued,
                title: "团队负责人手机汇报发送",
                body: "没有配置就绪的外发通道，已保留为待发送。"
            ), at: 0)
            appendEvent(kind: .risk, title: "通信网关发送待配置", detail: "没有配置就绪的外发通道。", agentID: leadID)
            trimCommunicationLogs()
            saveSnapshot()
            return
        }

        var lines: [String] = []
        var anyFailed = false
        for channel in readyChannels {
            guard let preview = CommunicationGatewayRequestBuilder.preview(for: channel, text: body) else { continue }
            let result = await CommunicationGatewayDispatcher.dispatch(preview, session: session)
            if result.succeeded {
                lines.append("- 已发送：\(channel.name)\(result.httpStatus.map { "（HTTP \($0)）" } ?? "（本地通道）")，尝试 \(result.attempts) 次")
            } else {
                anyFailed = true
                lines.append("- 失败：\(channel.name)，尝试 \(result.attempts) 次，\(result.error ?? "未知错误")")
            }
        }

        let report = """
        \("团队负责人手机汇报发送：".L())\(anyFailed ? "部分失败" : "完成")
        \("产品：".L())\(product.name)
        \(lines.joined(separator: "\n"))
        """
        communicationLogs.insert(CommunicationLogEntry(
            channelID: readyChannels.first?.id,
            productID: selectedProductID,
            agentID: leadID,
            direction: .outbound,
            status: anyFailed ? .failed : .sent,
            title: "团队负责人手机汇报发送".L(),
            body: report
        ), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID ?? ctoID, author: .system, text: report))
        appendEvent(kind: anyFailed ? .risk : .ctoSummary, title: "通信网关发送完成".L(), detail: anyFailed ? "部分通道发送失败。".L() : "就绪通道已发送。".L(), agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
    }

    public func testCommunicationGatewayChannels() {
        ensureCommunicationGatewayPlan()
        let enabledChannels = selectedProductCommunicationChannels.filter(\.isEnabled)
        guard !enabledChannels.isEmpty else {
            communicationLogs.insert(CommunicationLogEntry(
                productID: selectedProductID,
                agentID: teamLeadAgentIDForSelectedProduct(),
                direction: .outbound,
                status: .failed,
                title: "通信通道测试".L(),
                body: "没有启用的通信通道。请先启用本地指挥台或配置外部网络回调/机器人。".L()
            ), at: 0)
            appendEvent(kind: .risk, title: "通信通道测试失败".L(), detail: "没有启用的通信通道。".L(), agentID: teamLeadAgentIDForSelectedProduct())
            saveSnapshot()
            return
        }

        let lines = enabledChannels.map { channel in
            if let preview = CommunicationGatewayRequestBuilder.preview(for: channel, text: "OPC 通信测试".L()) {
                let endpoint = preview.method == "LOCAL" ? preview.endpoint : CommunicationGatewayDispatcher.redactedEndpoint(preview.endpoint)
                return "通过：".L() + "\(channel.name)" + " · " + "\(preview.method)" + " " + "\(endpoint)"
            }
            return "缺配置：".L() + "\(channel.name)" + " · 需要接口地址" + "\(channel.kind == .telegramBot ? "和聊天标识" : "")"
        }
        let hasMissingConfiguration = lines.contains { $0.hasPrefix("缺配置：".L()) }
        communicationLogs.insert(CommunicationLogEntry(
            channelID: enabledChannels.first?.id,
            productID: selectedProductID,
            agentID: teamLeadAgentIDForSelectedProduct(),
            direction: .outbound,
            status: hasMissingConfiguration ? .queued : .sent,
            title: "通信通道测试".L(),
            body: lines.joined(separator: "\n")
        ), at: 0)
        appendEvent(
            kind: hasMissingConfiguration ? .risk : .statusChanged,
            title: hasMissingConfiguration ? "通信通道待补配置".L() : "通信通道测试通过".L(),
            detail: lines.joined(separator: "；"),
            agentID: teamLeadAgentIDForSelectedProduct()
        )
        trimCommunicationLogs()
        saveSnapshot()
    }

    public func communicationGatewayMobileLinkText() -> String {
        let inboundChannels = selectedProductCommunicationChannels.filter { $0.kind.supportsInboundCommand }
        let enabledInboundChannels = inboundChannels.filter { $0.isEnabled && $0.commandsEnabled }
        let readyInboundChannels = enabledInboundChannels.filter(communicationChannelCanDispatch)
        let inboundLogs = selectedProductCommunicationLogs.filter { $0.direction == .inbound }
        let leadName = teamLeadAgentIDForSelectedProduct().map(agentName) ?? "团队负责人".L()
        let channelLines = inboundChannels.map { channel in
            let state: String
            if !channel.isEnabled {
                state = "未启用".L()
            } else if !channel.commandsEnabled {
                state = "未开启指令".L()
            } else if communicationChannelCanDispatch(channel) {
                state = "可接收".L()
            } else {
                state = "缺配置".L()
            }
            return "- \(channel.name)：\(channel.kind.title) · \(state)"
        }.joined(separator: "\n")

        return """
        移动端指令联动：\(readyInboundChannels.isEmpty ? "待配置".L() : "可接收".L())
        产品：\(selectedProduct?.name ?? "当前产品".L())
        \("接收负责人：".L())\(leadName)
        \("可入站通道：".L())\(inboundChannels.count)
        \("已启用指令通道：".L())\(enabledInboundChannels.count)
        \("配置就绪通道：".L())\(readyInboundChannels.count)
        \("已接收指令：".L())\(inboundLogs.filter { $0.status == .received }.count)
        \("被拒绝/失败指令：".L())\(inboundLogs.filter { $0.status == .failed }.count)

        \("通道状态：".L())
        \(channelLines.isEmpty ? "- 当前产品没有支持入站指令的通道。".L() : channelLines)

        \("说明：".L())
        \("手机指令只会写入通信日志、通知团队负责人并创建可追踪任务；不会直接执行命令、不会跳过老板/技术负责人审批，也不会修改本地文件。外部双向通道必须同时满足启用、允许指令、支持入站和配置完整。".L())
        """
    }

    @discardableResult
    public func ingestRemoteCommand(_ text: String, channelID: UUID? = nil, source: InboundCommandSource = .localCommandConsole) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        ensureCommunicationGatewayPlan()
        guard let channel = inboundCommandChannel(channelID: channelID) else {
            rejectInboundCommand(channelID: channelID, reason: "没有可接收手机指令的已启用通道。指令内容已拒绝进入任务队列。")
            return false
        }
        guard channel.kind == .localOnly else {
            rejectInboundCommand(channelID: channel.id, reason: "\(channel.name) 是外部入站通道，必须走签名校验入口。")
            return false
        }
        return recordAcceptedInboundCommand(clean, channel: channel, source: source)
    }

    @discardableResult
    public func ingestSignedRemoteCommand(
        body: String,
        timestamp: String?,
        nonce: String?,
        signature: String?,
        secret: String,
        channelID: UUID
    ) -> Bool {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        ensureCommunicationGatewayPlan()
        guard let channel = inboundCommandChannel(channelID: channelID) else {
            rejectInboundCommand(channelID: channelID, reason: "没有可接收手机指令的已启用通道。指令内容已拒绝进入任务队列。")
            return false
        }
        guard channel.kind != .localOnly else {
            rejectInboundCommand(channelID: channel.id, reason: "本地指挥台不接受外部签名回调，请使用本地模拟入口。")
            return false
        }
        guard communicationChannelCanDispatch(channel) else {
            rejectInboundCommand(channelID: channel.id, reason: "\(channel.name) 缺少必要配置，暂不能接收外部指令。")
            return false
        }
        let verification = CommunicationInboundVerifier.verify(
            body: clean,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature,
            secret: secret,
            usedNonces: &inboundCommandNonces
        )
        guard verification == .accepted else {
            rejectInboundCommand(channelID: channel.id, reason: "外部指令签名校验失败：\(inboundVerificationTitle(verification))。")
            return false
        }
        let parsedCommand = CommunicationInboundCommandParser.parse(clean)
        switch parsedCommand {
        case .accepted(let command):
            switch command.action {
            case .queryStatus:
                return recordInboundStatusQuery(channel: channel)
            case .submitInstruction:
                return recordAcceptedInboundCommand(command.text, channel: channel, source: .externalSignedChannel)
            case .approvalDecision:
                rejectInboundCommand(channelID: channel.id, reason: "外部指令动作被拒绝：外部审批动作暂未开放。")
                return false
            }
        case .invalidJSON, .missingField, .unsupportedAction, .emptyInstruction, .approvalActionDisabled:
            rejectInboundCommand(channelID: channel.id, reason: "外部指令动作被拒绝：\(CommunicationInboundCommandParser.parseFailureTitle(parsedCommand))。")
            return false
        }
    }

    private func recordAcceptedInboundCommand(_ clean: String, channel: CommunicationChannelConfig, source: InboundCommandSource) -> Bool {
        let leadID = teamLeadAgentIDForSelectedProduct() ?? ctoID
        let limited = String(clean.prefix(2_000))
        let logBody = """
        \("来源：".L())\(source.title)
        \("内容：".L())\(limited)
        """
        communicationLogs.insert(CommunicationLogEntry(channelID: channel.id, productID: selectedProductID, agentID: leadID, direction: .inbound, status: .received, title: "手机端老板指令".L(), body: logBody), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID, author: .user, text: "【手机端指令】".L() + "\(limited)"))
        tasks.insert(CompanyTask(productID: selectedProductID, title: "手机指令：".L() + "\(String(limited.prefix(24)))", ownerID: leadID, status: .assigned, successCriteria: "团队负责人理解手机端指令，拆解下一步并向老板汇报；涉及高风险操作时必须回到老板审批。".L()), at: 0)
        setStatus(.thinking, for: leadID)
        appendEvent(kind: .message, title: "收到手机端指令".L(), detail: limited, agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
        return true
    }

    private func recordInboundStatusQuery(channel: CommunicationChannelConfig) -> Bool {
        let leadID = teamLeadAgentIDForSelectedProduct() ?? ctoID
        let productName = selectedProduct?.name ?? "当前产品".L()
        let openTaskCount = selectedProductTasks.filter { $0.status != .done && $0.status != .canceled }.count
        let report = """
        \("外部状态查询已接收".L())
        \("产品：".L())\(productName)
        \("负责人：".L())\(agentName(leadID))
        \("未完成任务：".L())\(openTaskCount)
        \("待审批：".L())\(selectedProductPendingApprovals.count)
        \("风险事件：".L())\(selectedProductBossRiskEvents.count)

        \("说明：".L())
        \("本次只返回当前产品状态摘要，不创建任务、不执行命令、不修改文件，也不处理审批。".L())
        """
        communicationLogs.insert(CommunicationLogEntry(channelID: channel.id, productID: selectedProductID, agentID: leadID, direction: .inbound, status: .received, title: "外部状态查询", body: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID, author: .system, text: report))
        appendEvent(kind: .message, title: "收到外部状态查询", detail: "\(channel.name) 查询了 \(productName) 的状态。", agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
        return true
    }

    private func rejectInboundCommand(channelID: UUID?, reason: String) {
        communicationLogs.insert(CommunicationLogEntry(
            channelID: channelID,
            productID: selectedProductID,
            agentID: teamLeadAgentIDForSelectedProduct() ?? ctoID,
            direction: .inbound,
            status: .failed,
            title: "手机端指令被拒绝",
            body: reason
        ), at: 0)
        appendEvent(kind: .risk, title: "手机端指令被拒绝", detail: reason, agentID: teamLeadAgentIDForSelectedProduct() ?? ctoID)
        trimCommunicationLogs()
        saveSnapshot()
    }

    private func inboundVerificationTitle(_ result: CommunicationInboundVerificationResult) -> String {
        switch result {
        case .accepted: "已通过"
        case .missingField(let field): "缺少 \(field)"
        case .staleTimestamp: "时间戳过期"
        case .replayedNonce: "重复 nonce"
        case .invalidSignature: "签名无效"
        }
    }

    public func syncSelectedAgentWorkspace() {
        syncAgentWorkspace(for: selectedAgentID)
        appendEvent(kind: .artifactCreated, title: "员工工作区已同步", detail: "\(agentName(selectedAgentID)) 的本地档案文件已写出。", agentID: selectedAgentID)
        saveSnapshot()
    }

    public func syncSelectedProductAgentWorkspaces() {
        for agent in selectedProductAgents {
            syncAgentWorkspace(for: agent.id)
        }
        appendEvent(kind: .artifactCreated, title: "产品团队工作区已同步", detail: "\(selectedProduct?.name ?? "当前产品") 的 \(selectedProductAgents.count) 个员工工作区已写出。", agentID: ctoID)
        saveSnapshot()
    }

    public func compactSelectedAgentMemory() {
        compactAgentMemory(agentID: selectedAgentID)
        saveSnapshot()
    }

    public func runSelectedAgent(prompt: String) {
        runAgent(agentID: selectedAgentID, prompt: prompt)
    }

    public func runAllExecutableAgents(prompt: String) {
        for agent in executableAgents where !isRunning(agentID: agent.id) {
            runAgent(agentID: agent.id, prompt: prompt)
        }
    }

    public func runAgent(agentID: UUID, prompt: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        guard agent.role != .boss else { return }
        guard !isRunning(agentID: agent.id) else { return }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            appendTerminalLog("\n[OPC 已阻止运行] \(agent.displayName) 未加入 \(selectedProduct?.name ?? "当前产品")，不能启动当前产品命令行任务。\n", for: agent.id)
            appendEvent(kind: .risk, title: "已阻止非团队员工运行", detail: "\(agent.displayName) 未加入当前产品团队。", agentID: agent.id)
            saveSnapshot()
            return
        }

        let productID = selectedProductID
        let resumeSessionID = cliResumeSessionID(for: agent)
        let preparedPrompt = agentCommandPrompt(for: agent, userPrompt: prompt, resumeSessionID: resumeSessionID)
        let command = CLIAgentCommandBuilder.command(for: agent, prompt: preparedPrompt, resumeSessionID: resumeSessionID)
        let executionDirectory = cliExecutionDirectoryURL(for: agent)
        let persistentTarget = preparePersistentTerminalTarget(for: agent)
        let timeoutSeconds = CLIAgentCommandBuilder.interactionProfile(for: agent)?.recommendedTimeoutSeconds ?? 60
        let job = createCLIJobDirectory(agent: agent, prompt: prompt, command: command, executionDirectory: executionDirectory)
        appendTerminalLog(terminalCommandSummary(title: "OPC 命令行任务", agent: agent, executionDirectory: executionDirectory, prompt: prompt, job: job), for: agent.id, productID: productID)
        if resumeSessionID != nil {
            appendTerminalLog(Self.cliResumeContextNotice, for: agent.id, productID: productID)
        }
        if persistentTarget != nil {
            appendTerminalLog(Self.persistentSeatExecutionNotice, for: agent.id, productID: productID)
        }
        appendAgentSession(agentID: agent.id, kind: .command, actor: "system", text: "运行方式：\(visibleBackendSummary(for: agent))")
        appendEvent(kind: .commandPlanned, title: "正在运行 \(agent.displayName)", detail: "\(agent.displayName) 已按中文运行摘要启动。", agentID: agent.id)
        setStatus(.typing, for: agent.id)
        runningAgentIDs.insert(agent.id)
        markRuntimeBusy(for: agent)

        Task { @MainActor in
            let result: CommandExecutionResult
            if let persistentTarget {
                result = await runPersistentTerminalCommand(command: command, executionDirectory: executionDirectory, target: persistentTarget, timeoutSeconds: timeoutSeconds) { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendTerminalLog(chunk, for: agent.id, productID: productID)
                    }
                }
            } else {
                result = await AgentProcessRunner.runStreaming(command: command, workingDirectory: executionDirectory, environmentOverrides: environmentOverrides(for: agent), isolatedHome: isolatedHomeURL(for: agent, executionDirectory: executionDirectory), sandboxProfile: sandboxProfile(for: agent, executionDirectory: executionDirectory), timeoutSeconds: timeoutSeconds) { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendTerminalLog(chunk, for: agent.id, productID: productID)
                    }
                }
            }
            if result.combinedOutput.isEmpty {
                appendTerminalLog("（无输出）", for: agent.id, productID: productID)
            }
            if !result.standardError.isEmpty,
               terminalLog(agentID: agent.id, productID: productID).contains(result.standardError) == false {
                appendTerminalLog(result.standardError, for: agent.id, productID: productID)
            }
            appendTerminalLog("\n[命令退出码 \(result.exitCode)]\n", for: agent.id, productID: productID)
            if let job {
                updateCLIJobDirectory(job, agent: agent, result: result)
            }
            appendAgentSession(agentID: agent.id, kind: .result, actor: "system", text: "退出码 \(result.exitCode)。\(String(result.combinedOutput.prefix(1200)))")
            setStatus(result.exitCode == 0 ? .done : .failed, for: agent.id)
            appendEvent(
                kind: result.exitCode == 0 ? .artifactCreated : .risk,
                title: "\(agent.displayName) 命令结束",
                detail: "退出码 \(result.exitCode)。输出已记录到终端日志。",
                agentID: agent.id
            )
            if agent.id != ctoID {
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "\(agent.displayName) 完成了一次命令行执行，退出码 \(result.exitCode)。"))
            }
            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "任务运行")
            recordCLIInteractionObservationIfNeeded(agent: agent, result: result)
            handleFailedCLIResumeIfNeeded(agent: agent, result: result, usedResumeSessionID: resumeSessionID)
            recordCLISessionIfNeeded(agent: agent, result: result, usedResumeSessionID: resumeSessionID)
            saveSnapshot()
        }
    }

    public func saveSnapshot() {
        if case .failure(let error) = persistSnapshot(currentSnapshot()) {
            recordPersistenceFailure(error)
        }
    }

    /// 把一次 `CompanyPersistence.save` 失败转换成老板可见的 in-memory 风险事件。
    /// 关键约束：
    /// 1. **不能再次调用 saveSnapshot** —— 当前 save 通道刚刚失败，递归 save 会无限失败 + 无限插事件；
    ///    所以这里只 mutate `events` 数组，让 SwiftUI 视图自动刷新，但不持久化（重启会丢，符合 in-memory 语义）。
    /// 2. **去重相邻同类失败**：磁盘满 / 路径不可写时 saveSnapshot 会被高频调用，若每次都 append
    ///    会刷屏 events 列表。如果当前最新一条已经是同标题的「持久化失败」风险事件，则跳过这一次 append，
    ///    避免事件流被同一种故障淹没；不同标题的失败仍会照常上报。
    /// 3. 详情仅暴露 `localizedDescription`，不打印底层路径或文件描述符以避免泄露 sandbox 细节给老板视图。
    private func recordPersistenceFailure(_ error: Error) {
        let title = "持久化失败"
        if let latest = events.first, latest.kind == .risk, latest.title == title { return }
        let detail = "company-state.json 写入失败：\(error.localizedDescription)。后续操作仍在内存中，应用重启会丢失最近变更。"
        appendEvent(kind: .risk, title: title, detail: detail, agentID: nil)
    }

    func currentSnapshot() -> CompanySnapshot {
        CompanySnapshot(
            agents: agentsForSnapshot(),
            ctoID: ctoID,
            bossID: bossID,
            selectedAgentID: selectedAgentID,
            products: products,
            selectedProductID: selectedProductID,
            messages: messages,
            events: events,
            tasks: tasks,
            terminalLogs: terminalLogs,
            productTerminalLogs: productTerminalLogs,
            workQueue: workQueue,
            approvals: approvals,
            artifacts: artifacts,
            verifications: verifications,
            memories: memories,
            agentProfiles: agentProfiles,
            communicationChannels: communicationChannels,
            communicationLogs: communicationLogs,
            inboundCommandNonces: inboundCommandNonces,
            branchPlans: branchPlans,
            reviewGates: reviewGates,
            agentMessages: agentMessages
        )
    }

    private func isGeneratedOperationalTask(_ task: CompanyTask) -> Bool {
        let prefixes = ["流水线 ", "分支 ", "分支汇总：", "模板：", "售前", "手机指令："]
        return prefixes.contains { task.title.hasPrefix($0) }
    }

    private func canUseLiveChatBackend(_ agent: CompanyAgent) -> Bool {
        guard agent.role != .boss, agent.backend.type != .local else { return false }
        if agent.backend.type == .api {
            guard !agent.backend.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard !agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard !agent.backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        } else {
            guard !agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        return selectedProductAgents.contains { $0.id == agent.id }
    }

    private func localFallbackReply(for agentID: UUID) -> String {
        let name = agentName(agentID)
        return "本地降级提示：当前没有调用 \(name) 的真实模型来源。请确认该员工使用订阅制命令行或接口模型，并且已经加入当前产品团队；正式聊天会直接显示模型返回内容。"
    }

    private func chatCommand(for agent: CompanyAgent, prompt: String) -> [String] {
        CLIAgentCommandBuilder.command(for: agent, prompt: prompt)
    }

    public func commandPreviewForTesting(agentID: UUID, prompt: String) -> [String] {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return [] }
        let resumeSessionID = cliResumeSessionID(for: agent)
        return CLIAgentCommandBuilder.command(
            for: agent,
            prompt: agentCommandPrompt(for: agent, userPrompt: prompt, resumeSessionID: resumeSessionID),
            resumeSessionID: resumeSessionID
        )
    }

    public func codexSessionIDForTesting(from output: String) -> String? {
        codexSessionID(from: output)
    }

    public func shouldRestartSessionForTesting(agentID: UUID, result: CommandExecutionResult) -> Bool {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return false }
        return shouldAutomaticallyRestartSession(after: result, agent: agent)
    }

    private func startLiveChatReply(agent: CompanyAgent, userText: String) {
        let productID = selectedProductID
        guard !isRunning(agentID: agent.id) else {
            messages.append(ChatMessage(productID: productID, agentID: agent.id, author: .system, text: "\(agent.displayName) 当前正在执行任务，等这次运行结束后再发起新对话。"))
            saveSnapshot()
            return
        }

        let prompt = agentChatPrompt(for: agent, userText: userText)
        if agent.backend.type == .api {
            startAPIChatReply(agent: agent, prompt: prompt, userText: userText)
            return
        }

        let command = chatCommand(for: agent, prompt: prompt)
        let executionDirectory = cliExecutionDirectoryURL(for: agent)
        appendTerminalLog("\n" + terminalCommandSummary(title: "OPC 聊天", agent: agent, executionDirectory: executionDirectory, prompt: userText), for: agent.id, productID: productID)
        appendAgentSession(agentID: agent.id, kind: .command, actor: "聊天", text: "聊天运行方式：\(visibleBackendSummary(for: agent))")
        runningAgentIDs.insert(agent.id)
        setStatus(.typing, for: agent.id)
        markRuntimeBusy(for: agent)
        let streamingMessageID = UUID()
        upsertChatMessage(id: streamingMessageID, productID: productID, agentID: agent.id, author: .agent, text: "\(agent.displayName) 正在回复...")

        Task { @MainActor in
            let result = await AgentProcessRunner.runStreaming(command: command, workingDirectory: executionDirectory, environmentOverrides: environmentOverrides(for: agent), isolatedHome: isolatedHomeURL(for: agent, executionDirectory: executionDirectory), sandboxProfile: sandboxProfile(for: agent, executionDirectory: executionDirectory), timeoutSeconds: 60) { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    self.appendTerminalLog(chunk, for: agent.id, productID: productID)
                }
            }

            let raw = displayableChatReply(from: result.combinedOutput)
            let reply: String
            let author: MessageAuthor
            if result.exitCode == 0 {
                reply = raw.isEmpty ? "模型没有返回内容。请检查该员工的命令行或接口配置。" : trimmedChatReply(raw)
                author = raw.isEmpty ? .system : .agent
            } else {
                reply = displayableChatError(from: result.combinedOutput)
                author = .system
            }
            upsertChatMessage(id: streamingMessageID, productID: productID, agentID: agent.id, author: author, text: reply)
            appendAgentSession(agentID: agent.id, kind: .reply, actor: result.exitCode == 0 ? agent.displayName : "system", text: reply)
            appendTerminalLog("\n[聊天退出码 \(result.exitCode)]\n", for: agent.id, productID: productID)
            setStatus(result.exitCode == 0 ? (agent.id == ctoID ? .thinking : .done) : .failed, for: agent.id)

            if agent.id != ctoID {
                let summary = "老板直接和 \(agent.displayName) 沟通：\(userText)。员工模型回复：\(String(reply.prefix(600)))"
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步", detail: summary, agentID: ctoID)
            }

            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "聊天")
            saveSnapshot()
        }
    }

    private func startAPIChatReply(agent: CompanyAgent, prompt: String, userText: String) {
        let productID = selectedProductID
        appendTerminalLog(apiChatTerminalLogPrelude(for: agent), for: agent.id, productID: productID)
        appendAgentSession(agentID: agent.id, kind: .command, actor: "接口聊天", text: apiChatSessionLogPrelude(for: agent))
        runningAgentIDs.insert(agent.id)
        setStatus(.typing, for: agent.id)
        markRuntimeBusy(for: agent)

        Task { @MainActor in
            let result = await AgentAPIChatRunner.run(agent: agent, prompt: prompt)
            let raw = displayableChatReply(from: result.combinedOutput)
            let reply = result.exitCode == 0
                ? (raw.isEmpty ? "接口没有返回内容。请检查接口地址、密钥、模型名和网络连接。" : trimmedChatReply(raw))
                : displayableChatError(from: result.combinedOutput)
            let author: MessageAuthor = result.exitCode == 0 && !raw.isEmpty ? .agent : .system
            messages.append(ChatMessage(productID: productID, agentID: agent.id, author: author, text: reply))
            appendAgentSession(agentID: agent.id, kind: .reply, actor: result.exitCode == 0 ? agent.displayName : "system", text: reply)
            appendTerminalLog("\n[接口聊天退出码 \(result.exitCode)]\n", for: agent.id, productID: productID)
            setStatus(result.exitCode == 0 ? (agent.id == ctoID ? .thinking : .done) : .failed, for: agent.id)

            if agent.id != ctoID {
                let summary = "老板直接和 \(agent.displayName) 沟通：\(userText)。员工模型回复：\(String(reply.prefix(600)))"
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步", detail: summary, agentID: ctoID)
            }

            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "接口聊天")
            saveSnapshot()
        }
    }

    func apiChatTerminalLogPrelude(for _: CompanyAgent) -> String {
        """

        \("[OPC 接口聊天]".L())
        \("接口聊天请求已交给员工档案中配置的接口模型。".L())
        \("连接信息：使用受控配置，不在可见日志展示接口地址或模型原文。".L())
        """
    }

    func apiChatSessionLogPrelude(for _: CompanyAgent) -> String {
        "接口聊天请求已交给员工档案中配置的接口模型；连接信息保留在受控配置中。"
    }

    public func agentConversationPrompt(for agentID: UUID, userText: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return userText }
        return agentChatPrompt(for: agent, userText: userText)
    }

    public func chatReplyPreviewForTesting(_ output: String) -> String {
        displayableChatReply(from: output)
    }

    public func chatCommandPreviewForTesting(agentID: UUID, userText: String) -> [String] {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return [] }
        return chatCommand(for: agent, prompt: agentChatPrompt(for: agent, userText: userText))
    }

    private func upsertChatMessage(id: UUID, productID: UUID? = nil, agentID: UUID, author: MessageAuthor, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].productID = productID
            messages[index].author = author
            messages[index].text = text
        } else {
            messages.append(ChatMessage(id: id, productID: productID, agentID: agentID, author: author, text: text))
        }
    }

    private func agentChatPrompt(for agent: CompanyAgent, userText: String) -> String {
        let profile = operatingProfile(for: agent.id)
        let recent = messages(for: agent.id, in: selectedProductID, includingLegacyGlobal: false)
            .filter { message in
                message.author != .system && !isLegacySyntheticAgentReply(message.text) && !needsConversationalRepair(message.text)
            }
            .suffix(3)
            .map { message in "\(messageAuthorTitle(message.author))：\(Self.promptFragment(message.text, limit: Self.agentChatRecentMessagePromptLimit))" }
            .joined(separator: "\n")
        let memory = agentPromptMemoryItems(for: agent.id, profile: profile)
            .prefix(4)
            .joined(separator: "；")
        let workSummary = conversationalWorkSummary(for: agent, profile: profile)
        let style = conversationalStyleGuide(for: agent)
        let currentUserText = Self.promptFragment(userText, limit: Self.agentChatUserTextPromptLimit)
        let activeTasks = selectedProductTasks
            .filter { $0.ownerID == agent.id && $0.status != .done && $0.status != .canceled }
            .prefix(3)
            .map(\.title)
            .joined(separator: "；")

        return """
        \("你是在 OPC 公司里和老板聊天的真实同事，只输出最终回复。".L())

        \("身份：".L())\(agent.displayName)，\(agent.title)。
        \("当前产品：".L())\(selectedProduct?.name ?? "当前产品") / \(selectedProduct?.stage.title ?? "未设置")。
        \("手上任务：".L())\(activeTasks.isEmpty ? "暂无明确任务" : activeTasks)。
        \("记忆：".L())\(memory.isEmpty ? "老板喜欢自然、具体、短一点的回复。" : memory)。
        \("工作重心：".L())\(workSummary)。

        \("最近聊天：".L())
        \(recent.isEmpty ? "暂无。" : recent)

        \("老板：".L())\(currentUserText)

        \("回复规则：".L())
        \("- 老板问“你是谁”时，用真人口吻一句话说明你是谁和能帮他做什么。".L())
        \("- 禁止档案式开头、职责清单、流程背诵和系统味表达；默认 1 到 3 句。".L())
        - \(style)
        """
    }

    private func conversationalStyleGuide(for agent: CompanyAgent) -> String {
        switch agent.role {
        case .cto:
            "你是老板身边的技术负责人，语气要像能扛事的合伙人，不要像说明书。".L()
        case .uiDesigner:
            "你是视觉设计同事，语气可以更轻快一点，但要给出清楚的设计判断。".L()
        case .codeEngineer:
            "你是工程同事，语气直接、务实，说明下一步会看哪里或改哪里。".L()
        case .reviewer:
            "你是审查同事，语气冷静，优先把风险和判断说清楚。".L()
        case .tester:
            "你是测试同事，语气细致，优先说明验证方法。".L()
        case .researcher:
            "你是研究同事，语气清楚，说明会查什么和如何避免编造。".L()
        case .productArchitect:
            "你是产品架构同事，语气有结构，但不要列职责清单。".L()
        case .boss:
            "你是老板本人，不要冒充员工。".L()
        case .custom:
            "按你的角色自然回复，不要念配置。".L()
        }
    }

    private func conversationalWorkSummary(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
        switch agent.role {
        case .cto:
            return "把老板的目标拆成清楚的任务，安排合适的人推进，并把风险和结果讲明白".L()
        case .uiDesigner:
            return "把产品想法转成界面结构、视觉方向、交互细节和动效状态".L()
        case .codeEngineer:
            return "在明确范围内改代码、修问题、跑验证，并把改动结果说清楚".L()
        case .reviewer:
            return "按成功标准检查产物，优先指出问题、风险和能不能交付".L()
        case .tester:
            return "把任务转成可重复验证步骤，发现失败场景并记录结果".L()
        case .researcher:
            return "查资料、看竞品和行业信息，把可靠结论整理出来".L()
        case .productArchitect:
            return "梳理需求结构、模块边界、产品约束和成功标准".L()
        case .boss:
            return "保存老板目标、偏好和关键决策".L()
        case .custom:
            let mission = profile.mission
                .replacingOccurrences(of: "作为".L(), with: "")
                .replacingOccurrences(of: "负责".L(), with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return mission.isEmpty ? "按配置的角色完成工作并同步进展".L() : mission
        }
    }

    private func repairedChatResultIfNeeded(_ result: CommandExecutionResult, agent: CompanyAgent, userText: String) async -> CommandExecutionResult {
        guard result.exitCode == 0 else { return result }
        let raw = displayableChatReply(from: result.combinedOutput)
        guard needsConversationalRepair(raw) else { return result }

        let productID = selectedProductID
        let repairPrompt = agentChatRepairPrompt(agent: agent, userText: userText, draft: raw)
        appendTerminalLog("\n[OPC 聊天修正]\n".L(), for: agent.id, productID: productID)

        let repaired: CommandExecutionResult
        if agent.backend.type == .api {
            repaired = await AgentAPIChatRunner.run(agent: agent, prompt: repairPrompt)
        } else {
            let command = chatCommand(for: agent, prompt: repairPrompt)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            appendTerminalLog(terminalCommandSummary(title: "OPC 聊天修正".L(), agent: agent, executionDirectory: executionDirectory, prompt: userText), for: agent.id, productID: productID)
            repaired = await AgentProcessRunner.runStreaming(command: command, workingDirectory: executionDirectory, environmentOverrides: environmentOverrides(for: agent), isolatedHome: isolatedHomeURL(for: agent, executionDirectory: executionDirectory), sandboxProfile: sandboxProfile(for: agent, executionDirectory: executionDirectory), timeoutSeconds: 45) { [weak self] chunk in
                Task { @MainActor in
                    self?.appendTerminalLog(chunk, for: agent.id, productID: productID)
                }
            }
        }

        let repairedText = displayableChatReply(from: repaired.combinedOutput)
        if repaired.exitCode == 0 && !needsConversationalRepair(repairedText) && !isLegacySyntheticAgentReply(repairedText) {
            return repaired
        }
        let blocked = "模型返回仍然像角色档案或流程背诵，OPC 已拦截这次员工回复。请重新发送一句更具体的问题，或检查该员工模型配置。".L()
        return CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: blocked)
    }

    private func agentChatRepairPrompt(agent: CompanyAgent, userText: String, draft: String) -> String {
        let currentUserText = Self.promptFragment(userText, limit: Self.agentChatUserTextPromptLimit)
        let draftText = Self.promptFragment(draft, limit: Self.agentChatRepairDraftPromptLimit)
        return """
        \("下面这段回复太像系统档案或工作报告，不适合直接发给老板。请把它改写成自然聊天口吻。".L())

        \("员工：".L())\(agent.displayName)，\(agent.title)
        \("老板原话：".L())\(currentUserText)

        \("机械草稿：".L())
        \(draftText)

        \("改写要求：".L())
        \("- 只输出最终要发给老板的话。".L())
        \("- 不要说“我的角色档案是”“作为...”“我的职责是”“工作流是”。".L())
        \("- 像真人同事一样，1 到 3 句中文。".L())
        \("- 保留有用信息，但删掉流程背诵和身份档案背诵。".L())
        """
    }

    private func needsConversationalRepair(_ text: String) -> Bool {
        let markers = [
            "我的角色档案",
            "角色档案",
            "作为总技术负责人",
            "作为视觉产品设计师",
            "作为高级 macOS 工程师",
            "作为风险与验收审查员",
            "我的职责",
            "我的档案",
            "我会结合记忆",
            "工作流是",
            "流程是老板",
            "老板 -> CTO",
            "老板->CTO",
            "CTO -> 员工"
        ]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func displayableChatReply(from output: String) -> String {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        if let marker = clean.range(of: "\ncodex\n", options: .backwards) {
            let tail = String(clean[marker.upperBound...])
            let lines = tail.split(whereSeparator: \.isNewline).map(String.init)
            let usefulLines = lines.prefix { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "tokens used" { return false }
                if trimmed.contains(" ERROR ") { return false }
                if trimmed.hasPrefix("202") && trimmed.contains("ERROR") { return false }
                return true
            }
            let extracted = usefulLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty {
                return extracted
            }
        }

        let logOnlyMarkers = [
            "[OPC Chat]",
            "[OPC 聊天]",
            "OpenAI Codex",
            "Reading additional input from stdin",
            "workdir:",
            "approval:",
            "sandbox:",
            "session id:",
            "tokens used"
        ]
        if logOnlyMarkers.contains(where: { clean.contains($0) }) {
            return ""
        }

        return clean
    }

    private func displayableChatError(from output: String) -> String {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return "模型调用失败，但没有返回错误详情。请查看该员工的终端日志。"
        }
        let lines = clean.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let timeout = lines.last(where: { $0.contains("命令超时") }) {
            return timeout
        }
        if let error = lines.last(where: { $0.hasPrefix("ERROR:") || $0.contains("unexpected status") || $0.contains("requires a newer version") }) {
            return error
        }
        return "模型调用失败。请打开该员工的终端日志查看详情。"
    }

    private func trimmedChatReply(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 4000 { return clean }
        return String(clean.suffix(4000))
    }

    private func messageAuthorTitle(_ author: MessageAuthor) -> String {
        switch author {
        case .user: "老板"
        case .agent: "员工"
        case .system: "系统"
        }
    }

    private func setStatus(_ status: AgentStatus, for agentID: UUID) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        agents[index].status = status
        appendEvent(kind: .statusChanged, title: "\(agents[index].displayName)：\(status.title)", detail: "状态已变更为 \(status.title)。", agentID: agentID)
    }

    private func setOptionalStatus(_ status: AgentStatus, for agentID: UUID?) {
        guard let agentID else { return }
        setStatus(status, for: agentID)
    }

    private func appendEvent(productID: UUID? = nil, kind: CompanyEventKind, title: String, detail: String, agentID: UUID?) {
        events.insert(CompanyEvent(productID: productID ?? selectedProductID, kind: kind, title: title, detail: detail, agentID: agentID), at: 0)
        if events.count > 200 {
            events.removeLast(events.count - 200)
        }
    }

    private func cliWorkingDirectoryURL() -> URL {
        if let product = selectedProduct {
            let url = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app", bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return Self.defaultProductRootDirectoryURL()
    }

    private func requiresIsolatedCLIExecution(_ agent: CompanyAgent) -> Bool {
        agent.permissions.contains(.editFiles) || [.codeEngineer, .tester].contains(agent.role)
    }

    private func cliIsolationSourceURL(for agent: CompanyAgent) -> URL {
        cliWorktreeIsolationURL(for: agent).appendingPathComponent("source", isDirectory: true)
    }

    private func cliExecutionDirectoryURL(for agent: CompanyAgent) -> URL {
        let workingDirectory = cliWorkingDirectoryURL()
        guard requiresIsolatedCLIExecution(agent) else { return workingDirectory }

        let sourceDirectory = cliIsolationSourceURL(for: agent)
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: workingDirectory) {
            return sourceDirectory
        }
        return workingDirectory
    }

    private func cliExecutionIsolationNote(for agent: CompanyAgent) -> String {
        guard requiresIsolatedCLIExecution(agent) else {
            return "无需隔离：只读或协调型员工使用主工作目录。"
        }
        let workingDirectory = cliWorkingDirectoryURL()
        let isolationDirectory = cliIsolationSourceURL(for: agent)
        if cliIsolationDirectoryIsRunnable(isolationDirectory, sourceRoot: workingDirectory) {
            return "已启用隔离执行目录。"
        }
        if FileManager.default.fileExists(atPath: cliWorktreeIsolationURL(for: agent).appendingPathComponent("WORKTREE.md").path) {
            return "隔离目录已登记但还没有生成源码执行区，真实运行暂用主工作目录。"
        }
        return "隔离目录尚未创建，真实运行暂用主工作目录。"
    }

    private struct CLIJobDirectory {
        var id: String
        var directory: URL
        var transcriptURL: URL
        var statusURL: URL
    }

    private func createCLIJobDirectory(agent: CompanyAgent, prompt: String, command: [String], executionDirectory: URL) -> CLIJobDirectory? {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = UUID().uuidString.prefix(8)
        let jobID = "\(timestamp)-\(safeFileName(agent.displayName))-\(suffix)"
        let directory = cliWorkingDirectoryURL().appendingPathComponent(".opc/jobs/\(jobID)", isDirectory: true)
        let transcriptURL = directory.appendingPathComponent("transcript.log")
        let statusURL = directory.appendingPathComponent("status.json")

        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("artifacts", isDirectory: true), withIntermediateDirectories: true)
            let taskPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : prompt
            let brief = """
            \("# OPC 命令行作业".L())

            \("作业编号：".L())\(jobID)
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("员工：".L())\(agent.displayName)
            \("角色：".L())\(agent.role.title)
            \("产品工作目录：".L())\(cliWorkingDirectoryURL().path)
            \("执行目录：".L())\(executionDirectory.path)
            \("隔离策略：".L())\(cliExecutionIsolationNote(for: agent))

            \("命令：".L())
            \(command.joined(separator: " "))
            """
            let agentTask = """
            \("# 员工任务".L())

            \(taskPrompt)
            """
            try brief.write(to: directory.appendingPathComponent("brief.md"), atomically: true, encoding: .utf8)
            try agentTask.write(to: directory.appendingPathComponent("agent-task.md"), atomically: true, encoding: .utf8)
            try "".write(to: transcriptURL, atomically: true, encoding: .utf8)
            try cliJobStatusJSON(jobID: jobID, agent: agent, state: "running", exitCode: nil, executionDirectory: executionDirectory).write(to: statusURL, atomically: true, encoding: .utf8)
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: .report, title: "命令行作业档案：\(agent.displayName)", path: directory.path, summary: "运行中 · \(agent.role.title) · \(jobID)"), at: 0)
            return CLIJobDirectory(id: jobID, directory: directory, transcriptURL: transcriptURL, statusURL: statusURL)
        } catch {
            appendEvent(kind: .risk, title: "命令行作业目录创建失败", detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
            return nil
        }
    }

    private func updateCLIJobDirectory(_ job: CLIJobDirectory, agent: CompanyAgent, result: CommandExecutionResult) {
        do {
            try result.combinedOutput.write(to: job.transcriptURL, atomically: true, encoding: .utf8)
            try cliJobStatusJSON(jobID: job.id, agent: agent, state: result.exitCode == 0 ? "completed" : "failed", exitCode: result.exitCode, executionDirectory: cliExecutionDirectoryURL(for: agent)).write(to: job.statusURL, atomically: true, encoding: .utf8)
            if let index = artifacts.firstIndex(where: { $0.productID == selectedProductID && $0.path == job.directory.path }) {
                artifacts[index].summary = "退出码 \(result.exitCode) · 运行记录已写入。"
            }
        } catch {
            appendEvent(kind: .risk, title: "命令行作业档案写入失败", detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
        }
    }

    private func cliJobStatusJSON(jobID: String, agent: CompanyAgent, state: String, exitCode: Int32?, executionDirectory: URL) -> String {
        let exitValue = exitCode.map(String.init) ?? "null"
        return """
        {
          "job_id": "\(jsonEscaped(jobID))",
          "product_id": "\(selectedProductID.uuidString)",
          "agent_id": "\(agent.id.uuidString)",
          "agent": "\(jsonEscaped(agent.displayName))",
          "state": "\(jsonEscaped(state))",
          "exit_code": \(exitValue),
          "execution_directory": "\(jsonEscaped(executionDirectory.path))",
          "updated_at": "\(jsonEscaped(ISO8601DateFormatter().string(from: Date())))"
        }
        """
    }

    private func jsonEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func cliIsolationDirectoryIsRunnable(_ directory: URL, sourceRoot: URL) -> Bool {
        let sourceIndicators = [".git", "Package.swift", "package.json", "pyproject.toml", "Sources", "src"]
        return sourceIndicators.contains { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        } && directory.standardizedFileURL.path != sourceRoot.standardizedFileURL.path
    }

    private func ensureGitIsolationSource(for agent: CompanyAgent, sourceRoot: URL, sourceDirectory: URL) {
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: sourceRoot) { return }
        if FileManager.default.fileExists(atPath: sourceDirectory.path),
           (try? FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path).isEmpty) == false {
            appendEvent(kind: .risk, title: "独立代码仓库工作区未创建".L(), detail: "\(agent.displayName)" + "：目标目录已有内容，暂不覆盖。" + "\(sourceDirectory.path)", agentID: agent.id)
            return
        }

        let result = runLocalProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", sourceRoot.path, "worktree", "add", "--detach", sourceDirectory.path, "HEAD"],
            workingDirectory: sourceRoot
        )
        if result.exitCode != 0 {
            appendEvent(kind: .risk, title: "独立代码仓库工作区创建失败".L(), detail: "\(agent.displayName)：\(result.output)", agentID: agent.id)
            if sourceRootLooksLikeProject(sourceRoot), !FileManager.default.fileExists(atPath: sourceDirectory.path) {
                try? ensureDirectorySnapshotIsolationSource(sourceRoot: sourceRoot, sourceDirectory: sourceDirectory)
            }
        }
    }

    private func ensureDirectorySnapshotIsolationSource(sourceRoot: URL, sourceDirectory: URL) throws {
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: sourceRoot) { return }
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try copyProjectSnapshot(from: sourceRoot, to: sourceDirectory, maxFiles: 2_000)
        try copyProjectRootEssentials(from: sourceRoot, to: sourceDirectory)
    }

    private func sourceRootLooksLikeProject(_ sourceRoot: URL) -> Bool {
        [".git", "Package.swift", "package.json", "pyproject.toml", "Sources", "src"].contains { name in
            FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(name).path)
        }
    }

    private func copyProjectSnapshot(from sourceRoot: URL, to targetRoot: URL, maxFiles: Int) throws {
        let excludedNames: Set<String> = [".git", ".opc", ".build", "node_modules", "dist", "DerivedData", ".DS_Store"]
        guard let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        var copiedFiles = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if excludedNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let relative = String(url.path.dropFirst(sourceRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { continue }
            let destination = targetRoot.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            guard copiedFiles < maxFiles else { break }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            try FileManager.default.copyItem(at: url, to: destination)
            copiedFiles += 1
        }
    }

    private func copyProjectRootEssentials(from sourceRoot: URL, to targetRoot: URL) throws {
        let essentialNames = ["Package.swift", "package.json", "pyproject.toml", "Sources", "src"]
        for name in essentialNames {
            let source = sourceRoot.appendingPathComponent(name)
            let destination = targetRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path)
            else { continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func runLocalProcess(executable: String, arguments: [String], workingDirectory: URL) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, [output, error].filter { !$0.isEmpty }.joined(separator: "\n"))
        } catch {
            return (127, error.localizedDescription)
        }
    }

    private struct PersistentTerminalTarget {
        var agentID: UUID
        var tmuxPath: String
        var sessionName: String
        var windowName: String
    }

    private struct PersistentTerminalSessionKey: Hashable, Sendable {
        var productID: UUID
        var agentID: UUID
        var tmuxPath: String
        var sessionName: String
        var windowName: String
    }

    private struct PersistentTerminalTurnSnapshot {
        var result: CommandExecutionResult?
        var observation: CLIInteractionObservation?
        var partialOutput: String
    }

    private struct PersistentTerminalProcessResult: Sendable {
        var exitCode: Int32
        var output: String
    }

    public struct PersistentTerminalREPLTurnResult: Sendable {
        public var exitCode: Int32
        public var output: String
        public var observation: CLIInteractionObservation
        public var timedOut: Bool
    }

    private actor PersistentTerminalSession {
        private let target: PersistentTerminalTarget

        init(target: PersistentTerminalTarget) {
            self.target = target
        }

        private var targetPane: String {
            "\(target.sessionName):\(target.windowName)"
        }

        func capture(historyStart: String = "-50000", workingDirectory: URL) -> PersistentTerminalProcessResult {
            runLocalProcess(
                executable: target.tmuxPath,
                arguments: ["capture-pane", "-p", "-t", targetPane, "-S", historyStart],
                workingDirectory: workingDirectory
            )
        }

        func sendKeys(_ keys: [String], workingDirectory: URL) -> PersistentTerminalProcessResult {
            runLocalProcess(
                executable: target.tmuxPath,
                arguments: ["send-keys", "-t", targetPane] + keys,
                workingDirectory: workingDirectory
            )
        }

        func sendInputLine(_ text: String, workingDirectory: URL) -> PersistentTerminalProcessResult {
            // 把 text + 回车一次性原子投递到 pane：先用 `tmux load-buffer -b NAME -` 通过 stdin
            // 把字面文本（含末尾 \n）写进一个一次性 tmux buffer，再用 `tmux paste-buffer -d -b NAME -t pane`
            // 把整段 buffer 粘进 pane。这样 pane 永远不会先看到一段「半截命令」、再被独立的 C-m 抢跑触发执行——
            // 那种两步发送在 full swift test 并发跑 tmux 时会让 zsh 把残缺的 marker-wrapped 长 shellCommand
            // 当作路径解析，偶发触发 file name too long，进而让 persistentProtocolRunDetectsMarkersAfterLongOutput
            // 等 marker 检测失败。
            let bufferName = "opc-input-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let load = runLocalProcessWithStdin(
                executable: target.tmuxPath,
                arguments: ["load-buffer", "-b", bufferName, "-"],
                workingDirectory: workingDirectory,
                stdinText: text + "\n"
            )
            guard load.exitCode == 0 else { return load }
            let paste = runLocalProcess(
                executable: target.tmuxPath,
                arguments: ["paste-buffer", "-d", "-b", bufferName, "-t", targetPane],
                workingDirectory: workingDirectory
            )
            if paste.exitCode != 0 {
                _ = runLocalProcess(
                    executable: target.tmuxPath,
                    arguments: ["delete-buffer", "-b", bufferName],
                    workingDirectory: workingDirectory
                )
            }
            return paste
        }

        func killWindow(workingDirectory: URL) -> PersistentTerminalProcessResult {
            runLocalProcess(
                executable: target.tmuxPath,
                arguments: ["kill-window", "-t", targetPane],
                workingDirectory: workingDirectory
            )
        }

        private nonisolated func runLocalProcess(executable: String, arguments: [String], workingDirectory: URL) -> PersistentTerminalProcessResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return PersistentTerminalProcessResult(exitCode: process.terminationStatus, output: [output, error].filter { !$0.isEmpty }.joined(separator: "\n"))
            } catch {
                return PersistentTerminalProcessResult(exitCode: 127, output: error.localizedDescription)
            }
        }

        private nonisolated func runLocalProcessWithStdin(
            executable: String,
            arguments: [String],
            workingDirectory: URL,
            stdinText: String
        ) -> PersistentTerminalProcessResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            do {
                try process.run()
                if let data = stdinText.data(using: .utf8), !data.isEmpty {
                    inputPipe.fileHandleForWriting.write(data)
                }
                try? inputPipe.fileHandleForWriting.close()
                process.waitUntilExit()
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return PersistentTerminalProcessResult(exitCode: process.terminationStatus, output: [output, error].filter { !$0.isEmpty }.joined(separator: "\n"))
            } catch {
                return PersistentTerminalProcessResult(exitCode: 127, output: error.localizedDescription)
            }
        }
    }

    private func preparePersistentTerminalTarget(for agent: CompanyAgent) -> PersistentTerminalTarget? {
        guard agent.backend.type == .subscriptionCLI else { return nil }
        guard currentRuntimeCapability(for: agent) == .persistentProtocol else { return nil }
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return nil }

        startTerminalWorkspaceForSelectedProduct()

        let sessionName = terminalWorkspaceSessionName()
        let windowName = terminalWorkspaceWindowName(for: agent)
        guard tmuxSessionExists(sessionName, tmuxPath: tmuxPath),
              tmuxWindowNames(sessionName, tmuxPath: tmuxPath).contains(windowName)
        else { return nil }
        return PersistentTerminalTarget(agentID: agent.id, tmuxPath: tmuxPath, sessionName: sessionName, windowName: windowName)
    }

    private func persistentTerminalSession(for target: PersistentTerminalTarget) -> PersistentTerminalSession {
        prunePersistentTerminalSessionCache()
        let key = PersistentTerminalSessionKey(
            productID: selectedProductID,
            agentID: target.agentID,
            tmuxPath: target.tmuxPath,
            sessionName: target.sessionName,
            windowName: target.windowName
        )
        if let existing = persistentTerminalSessions[key] {
            return existing
        }
        let session = PersistentTerminalSession(target: target)
        persistentTerminalSessions[key] = session
        return session
    }

    private func prunePersistentTerminalSessionCache() {
        let productByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let agentByID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        let currentTmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux")
        persistentTerminalSessions = persistentTerminalSessions.filter { entry in
            let key = entry.key
            guard let product = productByID[key.productID],
                  let agent = agentByID[key.agentID],
                  product.assignedAgentIDs.contains(key.agentID),
                  key.sessionName == terminalWorkspaceSessionName(for: product, productID: key.productID),
                  key.windowName == terminalWorkspaceWindowName(for: agent),
                  let currentTmuxPath,
                  key.tmuxPath == currentTmuxPath
            else {
                return false
            }
            return true
        }
    }

    public func persistentTerminalSessionCacheCountForTesting() -> Int {
        persistentTerminalSessions.count
    }

    private func sendPersistentTerminalInputLine(_ text: String, to agent: CompanyAgent) async -> CommandExecutionResult? {
        guard !text.contains(where: { $0.isNewline }) else {
            return CommandExecutionResult(
                exitCode: 126,
                standardOutput: "",
                standardError: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L()
            )
        }
        guard let target = preparePersistentTerminalTarget(for: agent) else { return nil }
        let terminalSession = persistentTerminalSession(for: target)
        let result = await terminalSession.sendInputLine(text, workingDirectory: cliWorkingDirectoryURL())
        return CommandExecutionResult(
            exitCode: result.exitCode,
            standardOutput: result.exitCode == 0 ? result.output : "",
            standardError: result.exitCode == 0 ? "" : result.output
        )
    }

    private enum PersistentTerminalREPLLogSource {
        case manual
        case autoLoop

        var title: String {
            switch self {
            case .manual:
                return "OPC 手动交互轮次".L()
            case .autoLoop:
                return "OPC 自动交互循环轮次".L()
            }
        }
    }

    private func runPersistentTerminalREPLTurn(
        _ text: String,
        to agent: CompanyAgent,
        timeoutSeconds: TimeInterval,
        logSource: PersistentTerminalREPLLogSource = .manual
    ) async -> PersistentTerminalREPLTurnResult? {
        guard !text.contains(where: { $0.isNewline }) else {
            let observation = CLIInteractionObservation(phase: .transientFailure, reasonTitle: "输入不合规".L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 126,
                output: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L(),
                observation: observation,
                timedOut: false
            )
        }
        guard let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "暂不支持".L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 127,
                output: "该员工的命令行来源不在长期会话画像目录里，手动交互轮次暂不支持。".L(),
                observation: observation,
                timedOut: false
            )
        }
        guard !profile.replReadySignals.isEmpty else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "暂不支持".L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 127,
                output: "\(opcBackendCommandDisplayName(profile.command))" + " 暂未配置专用就绪提示，手动交互轮次仅对配置了独立行就绪提示的命令行工具开放。".L(),
                observation: observation,
                timedOut: false
            )
        }
        guard let target = preparePersistentTerminalTarget(for: agent) else { return nil }

        let terminalSession = persistentTerminalSession(for: target)
        let workingDirectory = cliWorkingDirectoryURL()
        let baseline = await terminalSession.capture(workingDirectory: workingDirectory)
        guard baseline.exitCode == 0 else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "终端不可用".L())
            return PersistentTerminalREPLTurnResult(exitCode: baseline.exitCode, output: baseline.output, observation: observation, timedOut: false)
        }
        guard profile.endsWithReplReadyPrompt(baseline.output) else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "终端未就绪".L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 126,
                output: "该员工终端席位最近一行不是 ".L() + "\(profile.displayName)" + " 的交互就绪提示。为避免把手动输入误发到普通终端，请先通过员工任务运行入口启动对应命令行工具，看到最近一行的独立就绪提示后再发送手动交互轮次。",
                observation: observation,
                timedOut: false
            )
        }

        let send = await terminalSession.sendInputLine(text, workingDirectory: workingDirectory)
        guard send.exitCode == 0 else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "输入发送失败".L())
            return PersistentTerminalREPLTurnResult(exitCode: send.exitCode, output: send.output, observation: observation, timedOut: false)
        }

        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0.1))
        var latestDelta = ""
        var latestObservation = CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复".L())
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let capture = await terminalSession.capture(workingDirectory: workingDirectory)
            guard capture.exitCode == 0 else { continue }
            latestDelta = persistentTerminalOutputDelta(before: baseline.output, after: capture.output, inputEcho: text)
            let observation = CLIInteractionStateMachine.observeREPLTurn(output: latestDelta, profile: profile)
            if observation.phase != .unknown {
                latestObservation = observation
                recordPersistentTerminalREPLObservation(agent: agent, observation: observation)
            }
            switch observation.phase {
            case .ready, .completedTurn:
                appendPersistentTerminalREPLLog(agent: agent, observation: observation, timedOut: false, source: logSource)
                return PersistentTerminalREPLTurnResult(exitCode: 0, output: latestDelta, observation: observation, timedOut: false)
            case .authenticationBlocked:
                appendPersistentTerminalREPLLog(agent: agent, observation: observation, timedOut: false, source: logSource)
                return PersistentTerminalREPLTurnResult(exitCode: 126, output: latestDelta, observation: observation, timedOut: false)
            case .busy:
                appendPersistentTerminalREPLLog(agent: agent, observation: observation, timedOut: false, source: logSource)
                return PersistentTerminalREPLTurnResult(exitCode: 125, output: latestDelta, observation: observation, timedOut: false)
            case .transientFailure:
                appendPersistentTerminalREPLLog(agent: agent, observation: observation, timedOut: false, source: logSource)
                return PersistentTerminalREPLTurnResult(exitCode: 75, output: latestDelta, observation: observation, timedOut: false)
            case .awaitingResponse, .unknown:
                continue
            }
        }

        appendPersistentTerminalREPLLog(agent: agent, observation: latestObservation, timedOut: true, source: logSource)
        return PersistentTerminalREPLTurnResult(exitCode: 124, output: latestDelta, observation: latestObservation, timedOut: true)
    }

    private func persistentTerminalOutputDelta(before baseline: String, after latest: String, inputEcho: String? = nil) -> String {
        if latest.hasPrefix(baseline) {
            return String(latest.dropFirst(baseline.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let baselineLines = baseline.split(whereSeparator: \.isNewline).map(String.init)
        if let lastLine = baselineLines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
           let range = latest.range(of: lastLine) {
            return String(latest[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let inputEcho,
           !inputEcho.isEmpty,
           let range = latest.range(of: inputEcho) {
            return String(latest[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func recordPersistentTerminalREPLObservation(agent: CompanyAgent, observation: CLIInteractionObservation) {
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.productID = selectedProductID
        session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
        session.capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        session.cliInteractionPhase = observation.phase
        session.cliInteractionReason = observation.reasonTitle
        session.cliInteractionObservedAt = Date()
        session.cliInteractionSessionID = observation.sessionID
        let recoveryAction = CLIInteractionStateMachine.recoveryAction(for: observation.phase)
        session.cliInteractionRecoveryAction = recoveryAction
        session.cliInteractionRecoveryActionTitle = recoveryAction.title
        session.cliInteractionRecoveryHint = recoveryAction.operatorHint
        session.cliInteractionOperatorHint = recoveryAction.operatorHint
        runtimeSessions[agent.id] = session
    }

    private func appendPersistentTerminalREPLLog(
        agent: CompanyAgent,
        observation: CLIInteractionObservation,
        timedOut: Bool,
        source: PersistentTerminalREPLLogSource = .manual
    ) {
        let timeoutLine = timedOut ? "结果：本轮等待超时，未中断终端席位。\n".L() : ""
        appendTerminalLog(
            "\n[" + "\(source.title)" + "]\n" + "\(timeoutLine)" + "状态：".L() + "\(observation.reasonTitle)" + "。\n",
            for: agent.id
        )
    }

    private func runPersistentTerminalCommand(
        command: [String],
        executionDirectory: URL,
        target: PersistentTerminalTarget,
        timeoutSeconds: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> CommandExecutionResult {
        guard !command.isEmpty else {
            return CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: "没有提供命令。".L())
        }

        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let startMarker = "__OPC_JOB_START_\(marker)__"
        let endMarker = "__OPC_JOB_EXIT_\(marker)__:"
        let interactionProfile = command.first.flatMap { CLIInteractionProfileCatalog.profile(forCommand: $0) }
        let terminalSession = persistentTerminalSession(for: target)
        let workingDirectory = cliWorkingDirectoryURL()

        let preflightCapture = await terminalSession.capture(workingDirectory: workingDirectory)
        if preflightCapture.exitCode == 0, persistentTerminalHasUnfinishedOPCJob(preflightCapture.output) {
            let message = "\n终端席位仍有未完成的 OPC 命令行任务，已拒绝覆盖发送。请先刷新真实终端日志或恢复异常占用会话。\n".L()
            onOutput(message)
            return CommandExecutionResult(exitCode: 125, standardOutput: "", standardError: message)
        }

        guard let runnerScriptURL = writePersistentTerminalRunnerScript(
            command: command,
            executionDirectory: executionDirectory,
            startMarker: startMarker,
            endMarker: endMarker
        ) else {
            let message = "OPC 未能创建长期终端任务 runner 脚本。".L()
            onOutput(message)
            return CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: message)
        }

        let shellCommand = persistentTerminalShellCommand(runnerScriptURL: runnerScriptURL)
        // 真实终端只接收一条短命令：`/bin/sh runner`。长 prompt、换行参数和 marker wrapper
        // 已写入一次性 runner 脚本，避免交互 pane 解析半截多行命令导致 file-name-too-long 或 marker 丢失。
        let send = await terminalSession.sendInputLine(shellCommand, workingDirectory: workingDirectory)
        guard send.exitCode == 0 else {
            try? FileManager.default.removeItem(at: runnerScriptURL)
            return CommandExecutionResult(exitCode: send.exitCode, standardOutput: "", standardError: send.output)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var latestCapture = ""
        var latestObservation: CLIInteractionObservation?
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let capture = await terminalSession.capture(workingDirectory: workingDirectory)
            guard capture.exitCode == 0 else { continue }
            latestCapture = capture.output
            let snapshot = persistentTerminalTurnSnapshot(from: latestCapture, startMarker: startMarker, endMarker: endMarker, profile: interactionProfile)
            if let observation = snapshot.observation, observation.phase != .unknown {
                latestObservation = observation
            }
            if let result = snapshot.result {
                onOutput(result.standardOutput)
                return result
            }
        }

        let interruptSummary = await interruptPersistentTerminalCommand(
            terminalSession: terminalSession,
            workingDirectory: workingDirectory,
            startMarker: startMarker,
            endMarker: endMarker
        )
        let observationLine = latestObservation.map { "最后观察状态：".L() + "\($0.reasonTitle)" + "。\n" } ?? ""
        let message = "\n命令超时：".L() + "\(Int(timeoutSeconds))" + " 秒内没有返回，OPC 已停止等待该终端任务，并尝试中断长期席位。\n".L() + "\(observationLine)" + "\(interruptSummary)"
        onOutput(message)
        return CommandExecutionResult(
            exitCode: 124,
            standardOutput: persistentTerminalPartialOutput(from: latestCapture, startMarker: startMarker),
            standardError: message
        )
    }

    private func interruptPersistentTerminalCommand(
        terminalSession: PersistentTerminalSession,
        workingDirectory: URL,
        startMarker: String,
        endMarker: String
    ) async -> String {
        _ = await terminalSession.sendKeys(["C-c"], workingDirectory: workingDirectory)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if await persistentTerminalTurnClosed(terminalSession: terminalSession, workingDirectory: workingDirectory, startMarker: startMarker, endMarker: endMarker) {
            return "中断处理：普通中断已生效。\n".L()
        }

        _ = await terminalSession.sendKeys(["C-\\"], workingDirectory: workingDirectory)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if await persistentTerminalTurnClosed(terminalSession: terminalSession, workingDirectory: workingDirectory, startMarker: startMarker, endMarker: endMarker) {
            return "中断处理：强中断已生效。\n".L()
        }

        _ = await terminalSession.killWindow(workingDirectory: workingDirectory)
        return "中断处理：已关闭未响应的终端席位，下次运行会重新创建席位。\n".L()
    }

    private func persistentTerminalTurnClosed(
        terminalSession: PersistentTerminalSession,
        workingDirectory: URL,
        startMarker: String,
        endMarker: String
    ) async -> Bool {
        let capture = await terminalSession.capture(workingDirectory: workingDirectory)
        guard capture.exitCode == 0 else { return true }
        return persistentTerminalResult(from: capture.output, startMarker: startMarker, endMarker: endMarker) != nil
    }

    private func writePersistentTerminalRunnerScript(command: [String], executionDirectory: URL, startMarker: String, endMarker: String) -> URL? {
        let directory = cliWorkingDirectoryURL()
            .appendingPathComponent(".opc", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("terminal-runners", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("\(safeFileName(startMarker)).sh")
        let commandLine = command.map(shellSingleQuoted).joined(separator: " ")
        let script = """
        #!/bin/sh
        trap 'rm -f "$0"' EXIT
        printf '\\n\(startMarker)\\n'
        cd \(shellSingleQuoted(executionDirectory.path)) || {
          __opc_cd_exit=$?
          printf '\\n\(endMarker)%s\\n' "$__opc_cd_exit"
          exit "$__opc_cd_exit"
        }
        \(commandLine)
        __opc_exit=$?
        printf '\\n\(endMarker)%s\\n' "$__opc_exit"
        exit "$__opc_exit"
        """
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            cleanupPersistentTerminalRunnerScripts(in: directory)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            return scriptURL
        } catch {
            return nil
        }
    }

    private func cleanupPersistentTerminalRunnerScripts(in directory: URL, staleInterval: TimeInterval = 6 * 60 * 60, now: Date = Date()) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }
        for file in files where file.pathExtension == "sh" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > staleInterval
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func persistentTerminalShellCommand(runnerScriptURL: URL) -> String {
        "/bin/sh \(shellSingleQuoted(runnerScriptURL.path))"
    }

    private func persistentTerminalResult(from capture: String, startMarker: String, endMarker: String) -> CommandExecutionResult? {
        guard let startRange = capture.range(of: startMarker, options: .backwards),
              let endRange = capture.range(of: endMarker, range: startRange.upperBound..<capture.endIndex)
        else { return nil }

        let output = String(capture[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCodeText = capture[endRange.upperBound...]
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let exitCode = Int32(exitCodeText) ?? 1
        return CommandExecutionResult(exitCode: exitCode, standardOutput: output, standardError: "")
    }

    private func persistentTerminalTurnSnapshot(from capture: String, startMarker: String, endMarker: String, profile: CLIInteractionProfile?) -> PersistentTerminalTurnSnapshot {
        let partialOutput = persistentTerminalPartialOutput(from: capture, startMarker: startMarker)
        let observation = profile.map {
            CLIInteractionStateMachine.observe(output: partialOutput, profile: $0, previousPhase: .awaitingResponse)
        }
        return PersistentTerminalTurnSnapshot(
            result: persistentTerminalResult(from: capture, startMarker: startMarker, endMarker: endMarker),
            observation: observation,
            partialOutput: partialOutput
        )
    }

    private func persistentTerminalHasUnfinishedOPCJob(_ capture: String) -> Bool {
        guard let latestStart = capture.range(of: "__OPC_JOB_START_", options: .backwards) else { return false }
        guard let latestExit = capture.range(of: "__OPC_JOB_EXIT_", options: .backwards) else { return true }
        return latestExit.lowerBound < latestStart.lowerBound
    }

    private func persistentTerminalPartialOutput(from capture: String, startMarker: String) -> String {
        guard let startRange = capture.range(of: startMarker, options: .backwards) else {
            return capture.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(capture[startRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func terminalWorkspaceSessionName() -> String {
        terminalWorkspaceSessionName(for: selectedProduct, productID: selectedProductID)
    }

    private func terminalWorkspaceSessionName(for product: ProductWorkspace?, productID: UUID) -> String {
        let productPart = safeTmuxName(product?.name ?? "product")
        let suffix = String(productID.uuidString.prefix(12)).lowercased()
        return "opc-\(productPart)-\(suffix)"
    }

    private func terminalWorkspaceWindowName(for agent: CompanyAgent) -> String {
        let rolePart = safeTmuxName(agent.role.rawValue)
        let suffix = String(agent.id.uuidString.prefix(6)).lowercased()
        return "\(rolePart)-\(suffix)"
    }

    private func safeTmuxName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let cleaned = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
        let compact = cleaned.isEmpty ? "workspace" : cleaned
        return String(compact.prefix(24))
    }

    private func tmuxSessionExists(_ sessionName: String, tmuxPath: String? = nil) -> Bool {
        guard let executable = tmuxPath ?? AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return false }
        let result = runLocalProcess(
            executable: executable,
            arguments: ["has-session", "-t", sessionName],
            workingDirectory: cliWorkingDirectoryURL()
        )
        return result.exitCode == 0
    }

    private func tmuxWindowNames(_ sessionName: String, tmuxPath: String? = nil) -> [String] {
        guard let executable = tmuxPath ?? AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return [] }
        let result = runLocalProcess(
            executable: executable,
            arguments: ["list-windows", "-t", sessionName, "-F", "#W"],
            workingDirectory: cliWorkingDirectoryURL()
        )
        guard result.exitCode == 0 else { return [] }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func terminalWorkspaceIntroCommand(for agent: CompanyAgent, executionDirectory: URL) -> String {
        let text = """
        \("OPC 员工终端：".L())\(agent.displayName)（\(agent.role.title)）
        \("执行目录：".L())\(executionDirectory.path)
        \("请从 OPC 应用发起任务，确保保留预检、作业档案和验收记录。".L())
        """
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "printf %b \(shellSingleQuoted(escaped))"
    }

    private func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func cliToolchainIssueLines() -> [String] {
        var issues: [String] = []
        if executableAgents.isEmpty {
            issues.append("当前产品没有可执行员工。".L())
        }
        let workingDirectory = cliWorkingDirectoryURL()
        if !FileManager.default.fileExists(atPath: workingDirectory.path) {
            issues.append("工作目录不存在：".L() + "\(workingDirectory.path)")
        }
        for agent in executableAgents {
            let command = agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty {
                issues.append("\(agent.displayName)" + " 没有配置命令。".L())
            }
            switch agent.backend.type {
            case .api:
                if agent.backend.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(agent.displayName)" + " 是接口模式，但没有接口地址。".L())
                }
                if agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(agent.displayName)" + " 是接口模式，但没有接口密钥。".L())
                }
            case .subscriptionCLI:
                if command == "api-agent" || command == "human" {
                    issues.append("\(agent.displayName)" + " 是订阅制命令行模式，但命令配置不合理：".L() + "\(command)" + "。")
                }
            case .local:
                if agent.role != .boss {
                    issues.append("\(agent.displayName)" + " 是本地占位模式，不能真正运行外部模型。".L())
                }
            }
        }
        return issues
    }

    private func agentName(_ id: UUID) -> String {
        agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    public func agentHasSkill(_ agentID: UUID, skill: String) -> Bool {
        let target = canonicalSkillID(for: skill) ?? AgentSkillCatalog.normalize(skill)
        guard !target.isEmpty else { return false }
        let profile = operatingProfile(for: agentID)
        return profile.skills.contains { agentSkill in
            let candidate = canonicalSkillID(for: agentSkill) ?? AgentSkillCatalog.normalize(agentSkill)
            return candidate == target
        }
    }

    public func firstAgentID(withSkill skill: String, fallbackRole: AgentRole? = nil) -> UUID? {
        let candidates = selectedProductAgents.filter { agent in
            agent.role != .boss && agentHasSkill(agent.id, skill: skill)
        }
        if let custom = candidates.first(where: { $0.role == .custom }) {
            return custom.id
        }
        if let fallbackRole, let roleMatch = candidates.first(where: { $0.role == fallbackRole }) {
            return roleMatch.id
        }
        if let skilled = candidates.first {
            return skilled.id
        }
        if let fallbackRole {
            return firstAgentID(for: fallbackRole)
        }
        return nil
    }

    public func recommendedAgentID(forTaskTitle title: String, successCriteria: String, fallbackRole: AgentRole? = nil) -> UUID? {
        let inferredSkills = recommendedSkillIDs(forTaskTitle: title, successCriteria: successCriteria)
        for skill in inferredSkills {
            if let agentID = firstAgentID(withSkill: skill, fallbackRole: fallbackRole) {
                return agentID
            }
        }
        if let fallbackRole {
            return firstAgentID(for: fallbackRole)
        }
        return nil
    }

    public func teamLeadAgentIDForSelectedProduct() -> UUID? {
        if let leadID = selectedProduct?.teamLeadAgentID,
           selectedProductAgents.contains(where: { $0.id == leadID && $0.role != .boss }) {
            return leadID
        }
        if selectedProductAgents.contains(where: { $0.id == ctoID }) {
            return ctoID
        }
        return selectedProductAgents.first { $0.role != .boss }?.id
    }

    private func communicationChannelCanDispatch(_ channel: CommunicationChannelConfig) -> Bool {
        switch channel.kind {
        case .localOnly:
            return true
        case .telegramBot:
            return !channel.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !channel.chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .feishuWebhook, .wecomWebhook, .dingtalkWebhook, .emailDigest:
            return !channel.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func inboundCommandChannel(channelID: UUID?) -> CommunicationChannelConfig? {
        let candidates = selectedProductCommunicationChannels.filter {
            $0.isEnabled && $0.commandsEnabled && $0.kind.supportsInboundCommand
        }
        if let channelID {
            return candidates.first { $0.id == channelID }
        }
        return candidates.first { $0.kind == .localOnly } ?? candidates.first
    }

    private func firstAgentID(for role: AgentRole) -> UUID? {
        selectedProductAgents.first { $0.role == role }?.id
    }

    private func trimCommunicationLogs() {
        if communicationLogs.count > 200 {
            communicationLogs.removeLast(communicationLogs.count - 200)
        }
    }

    private func recommendedSkillIDs(forTaskTitle title: String, successCriteria: String) -> [String] {
        let text = "\(title)\n\(successCriteria)"
        var ids: [String] = []
        for id in AgentSkillCatalog.ids(matching: text) where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    private func canonicalSkillID(for value: String) -> String? {
        AgentSkillCatalog.canonicalID(for: value)
    }

    public func operatingProfile(for agentID: UUID) -> AgentOperatingProfile {
        if let profile = agentProfiles[agentID] {
            return profile
        }
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return AgentOperatingProfile(
                mission: "接收消息并按上下文回复。".L(),
                responsibilities: ["确认消息".L()],
                boundaries: ["不执行未知操作".L()],
                responseRules: ["简洁回复".L()],
                memory: [],
                skills: []
            )
        }
        let profile = AgentOperatingProfile.defaultProfile(for: agent)
        agentProfiles[agentID] = profile
        return profile
    }

    public func agentSystemPrompt(for agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        let profile = operatingProfile(for: agentID)
        let productMemories = agentProductMemoryPromptBlock(for: agentID, productID: selectedProductID)
        return """
        \(agentPromptProfileBlock(for: agent, profile: profile))

        \("当前产品员工记忆：".L())
        \(productMemories)
        """
    }

    private func agentPromptProfileBlock(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
        """
        \("员工操作档案".L())
        \("姓名：".L())\(agent.displayName)
        \("职位：".L())\(agent.title)
        \("角色：".L())\(agent.role.title)
        汇报对象：\(agent.reportsToCTO ? agentName(ctoID) : "老板".L())

        \("使命：".L())
        \(Self.promptFragment(profile.mission, limit: Self.agentProfileMissionPromptLimit))

        \("职责：".L())
        \(promptList(profile.responsibilities, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("边界：".L())
        \(promptList(profile.boundaries, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("回复规则：".L())
        \(promptList(profile.responseRules, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("长期记忆：".L())
        \(profile.memory.isEmpty ? "- 暂无".L() : promptList(profile.memory, limit: Self.agentProfileMemoryPromptLimit, itemLimit: Self.agentProfilePromptMemoryItemLimit))

        \("可用技能：".L())
        \(profile.skillDescriptions.isEmpty ? "- 暂无".L() : promptList(profile.skillDescriptions, limit: Self.agentProfileSkillPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))
        """
    }

    public func agentWorkspaceURL(for agentID: UUID) -> URL {
        let agent = agents.first { $0.id == agentID }
        let name = safeFileName(agent?.displayName ?? "agent")
        let suffix = String(agentID.uuidString.prefix(8))
        return CompanyPersistence.agentWorkspacesURL.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
    }

    private func agentExecutionPrompt(for agent: CompanyAgent, userPrompt: String) -> String {
        """
        \(agentSystemPrompt(for: agent.id))

        \("本地员工档案已由 OPC 同步；路径、会话和执行日志属于运维内部信息，回复用户时不要复述具体本地路径或文件名。".L())

        \("用户任务".L())
        \(userPrompt)
        """
    }

    private func agentCommandPrompt(for agent: CompanyAgent, userPrompt: String, resumeSessionID: String?) -> String {
        guard let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return agentExecutionPrompt(for: agent, userPrompt: userPrompt)
        }
        return """
        \("继续使用当前 OPC 产品和 ".L())\(agent.displayName)\(" 的既有命令行会话上下文。".L())

        \("用户任务".L())
        \(userPrompt)
        """
    }

    private func syncAllAgentWorkspaces() {
        for agent in agents {
            syncAgentWorkspace(for: agent.id)
        }
    }

    private func syncAgentWorkspace(for agentID: UUID) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        let profile = operatingProfile(for: agentID)
        let directory = agentWorkspaceURL(for: agentID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeTextIfChanged(agentSystemPrompt(for: agentID), to: directory.appendingPathComponent("AGENTS.md"))
            try writeTextIfChanged(soulDocument(for: agent, profile: profile), to: directory.appendingPathComponent("SOUL.md"))
            try writeTextIfChanged(memoryDocument(for: profile, agentID: agentID), to: directory.appendingPathComponent("MEMORY.md"))
            try writeTextIfChanged(skillsDocument(for: profile), to: directory.appendingPathComponent("SKILLS.md"))
            try writeTextIfChanged(workspaceDocument(for: agent), to: directory.appendingPathComponent("WORKSPACE.md"))
            let sessionURL = directory.appendingPathComponent("sessions.jsonl")
            if !FileManager.default.fileExists(atPath: sessionURL.path) {
                try "".write(to: sessionURL, atomically: true, encoding: .utf8)
            }
        } catch {
            appendEvent(kind: .risk, title: "员工工作区同步失败".L(), detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agentID)
        }
    }

    private func appendAgentSession(agentID: UUID, kind: AgentSessionKind, actor: String, text: String) {
        guard agents.contains(where: { $0.id == agentID }) else { return }
        syncAgentWorkspace(for: agentID)
        let entry = AgentSessionEntry(agentID: agentID, kind: kind, actor: actor, text: text)
        let url = agentWorkspaceURL(for: agentID).appendingPathComponent("sessions.jsonl")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            guard let line = String(data: data, encoding: .utf8) else { return }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        } catch {
            appendEvent(kind: .risk, title: "员工会话日志写入失败".L(), detail: error.localizedDescription, agentID: agentID)
        }
    }

    private func compactAgentMemory(agentID: UUID) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        let recent = messages(for: agentID, in: selectedProductID, includingLegacyGlobal: false).suffix(8).map { message in
            "\(messageAuthorTitle(message.author))：\(message.text)"
        }
        guard !recent.isEmpty else { return }
        let summary = "自动压缩记忆 " + "\(Date().opcDateTimeText)" + "：".L() + "\(recent.joined(separator: " / ").prefix(900))"
        memories.insert(ProductMemoryNote(productID: selectedProductID, agentID: agentID, kind: .summary, title: "员工记忆：".L() + "\(agent.displayName)", detail: String(summary)), at: 0)
        trimProductAgentMemories(agentID: agentID, productID: selectedProductID, limit: 12)
        syncAgentWorkspace(for: agentID)
        appendAgentSession(agentID: agentID, kind: .memory, actor: "system", text: "已压缩近期对话为长期记忆。".L())
        appendEvent(kind: .artifactCreated, title: "员工记忆已压缩".L(), detail: "\(agent.displayName)" + " 的近期对话已写入长期记忆。", agentID: agentID)
    }

    private func writeTextIfChanged(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if let existing = try? Data(contentsOf: url), existing == data {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private func soulDocument(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
        """
        # \(agent.displayName)

        \("## 使命".L())
        \(profile.mission)

        \("## 职责".L())
        \(markdownList(profile.responsibilities))

        \("## 边界".L())
        \(markdownList(profile.boundaries))

        \("## 回复规则".L())
        \(markdownList(profile.responseRules))
        """
    }

    private func memoryDocument(for profile: AgentOperatingProfile, agentID: UUID) -> String {
        let productMemories = agentProductMemoryLines(for: agentID, productID: selectedProductID)
        return """
        # MEMORY

        \("## 全局员工记忆".L())
        \(profile.memory.isEmpty ? "- 暂无".L() : markdownList(profile.memory))

        \("## 当前产品员工记忆".L())
        \(productMemories.isEmpty ? "- 暂无".L() : markdownList(productMemories))
        """
    }

    private func agentProductMemoryLines(for agentID: UUID, productID: UUID) -> [String] {
        memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .prefix(6)
            .map { note in "\(note.title)：\(note.detail)" }
    }

    private func agentProductMemoryPromptBlock(for agentID: UUID, productID: UUID) -> String {
        let items = memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .map { note in "\(note.title)：\(note.detail)" }
        return promptList(
            items,
            limit: Self.agentSystemProductMemoryPromptLimit,
            itemLimit: Self.agentSystemProductMemoryPromptItemLimit
        )
    }

    private func agentPromptMemoryItems(for agentID: UUID, profile: AgentOperatingProfile) -> [String] {
        let productMemories = agentProductMemoryLines(for: agentID, productID: selectedProductID)
        let globalMemories = profile.memory
            .filter { !isLegacySyntheticAgentReply($0) && !needsConversationalRepair($0) }
        return (productMemories + globalMemories).map {
            Self.promptFragment($0, limit: Self.agentChatMemoryPromptLimit)
        }
    }

    private static func promptFragment(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))…"
    }

    private static func promptInlineList(_ items: [String], empty: String, itemLimit: Int, itemTextLimit: Int) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return empty }
        let visible = cleaned.prefix(itemLimit).map {
            promptFragment($0, limit: itemTextLimit)
        }
        let hiddenCount = max(0, cleaned.count - itemLimit)
        let line = visible.joined(separator: "、")
        guard hiddenCount > 0 else { return line }
        return "\(line)；还有 \(hiddenCount) 项已保存在导入报告，按任务需要再读取。"
    }

    private func promptList(_ items: [String], limit: Int, itemLimit: Int) -> String {
        let visible = items.prefix(itemLimit).map {
            "- \(Self.promptFragment($0, limit: limit))"
        }
        let hiddenCount = max(0, items.count - itemLimit)
        guard !visible.isEmpty else { return "- 暂无" }
        if hiddenCount == 0 {
            return visible.joined(separator: "\n")
        }
        return (visible + ["- 还有 \(hiddenCount) 项已保存在员工档案，按任务需要再读取。"]).joined(separator: "\n")
    }

    private func trimProductAgentMemories(agentID: UUID, productID: UUID, limit: Int) {
        let overflowIDs = memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .dropFirst(limit)
            .map(\.id)
        guard !overflowIDs.isEmpty else { return }
        let overflowSet = Set(overflowIDs)
        memories.removeAll { overflowSet.contains($0.id) }
    }

    private func skillsDocument(for profile: AgentOperatingProfile) -> String {
        """
        # SKILLS

        \(profile.skills.isEmpty ? "- 暂无技能".L() : skillModuleList(profile.skills))
        """
    }

    private func workspaceDocument(for agent: CompanyAgent) -> String {
        let product = selectedProduct
        let team = selectedProductAgents.map { member in
            "- \(member.displayName)：\(member.title) / \(member.role.title)\(member.id == product?.teamLeadAgentID ? " / 团队负责人" : "")"
        }.joined(separator: "\n")
        let activePlans = selectedProductBranchPlans.prefix(5).map { plan in
            "- \(plan.goal)：\(plan.status.title)，分支 \(plan.lanes.count) 条"
        }.joined(separator: "\n")
        let tasksLine = selectedProductTasks.prefix(12).map { task in
            "- \(task.title)：\(task.status.title) / \(task.ownerID.map(agentName) ?? "未分配")"
        }.joined(separator: "\n")

        return """
        # WORKSPACE

        \("## 当前产品".L())
        \("- 名称：".L())\(product?.name ?? "未选择")
        \("- 根目录：".L())\(product?.rootDirectory ?? "未设置")
        \("- 阶段：".L())\(product?.stage.title ?? "未知")
        \("- 状态：".L())\(product?.status.title ?? "未知")

        \("## 当前员工".L())
        \("- 姓名：".L())\(agent.displayName)
        \("- 职位：".L())\(agent.title)
        \("- 角色：".L())\(agent.role.title)

        \("## 产品团队".L())
        \(team.isEmpty ? "- 暂无团队成员" : team)

        \("## 多分支计划".L())
        \(activePlans.isEmpty ? "- 暂无多分支计划" : activePlans)

        \("## 近期任务".L())
        \(tasksLine.isEmpty ? "- 暂无任务" : tasksLine)
        """
    }

    private func skillModuleList(_ skills: [String]) -> String {
        skills.map { skill in
            if let definition = AgentSkillCatalog.skill(id: skill) {
                return """
                ## \(definition.id)：\(definition.title)

                \("- 说明：".L())\(definition.summary)
                \("- 触发词：".L())\(definition.triggerKeywords.joined(separator: "、"))
                \("- 默认角色：".L())\(definition.defaultRoles.map(\.title).joined(separator: "、"))
                """
            }
            return """
            ## \(skill)

            \("- 类型：自定义技能".L())
            \("- 说明：旧版字符串技能，按员工档案原文保留，可继续用于精确匹配。".L())
            """
        }
        .joined(separator: "\n\n")
    }

    private func markdownList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "agent" : result
    }

    private func suggestedAgentName(for pack: AgentRolePack) -> String {
        let base: String
        switch pack.role {
        case .cto: base = "Codex 技术负责人".L()
        case .productArchitect: base = "产品架构师".L()
        case .uiDesigner: base = "Gemini 界面设计师".L()
        case .codeEngineer: base = "Claude Code 工程师".L()
        case .reviewer: base = "Codex 审查员".L()
        case .tester: base = "测试工程师".L()
        case .researcher: base = "资料研究员".L()
        case .boss: base = "老板".L()
        case .custom: base = pack.title
        }
        if !agents.contains(where: { $0.displayName == base }) {
            return base
        }
        let count = agents.filter { $0.displayName.hasPrefix(base) }.count + 1
        return "\(base) \(count)"
    }

    private func hydrateAPIKeysFromKeychain() {
        for index in agents.indices where agents[index].backend.type == .api {
            if !agents[index].backend.apiKey.isEmpty {
                writeAPIKeyToKeychain(agents[index].backend.apiKey, agentID: agents[index].id, context: "启动时回写".L())
            } else {
                agents[index].backend.apiKey = OPCKeychainStore.loadAPIKey(agentID: agents[index].id)
            }
        }
    }

    private func agentsForSnapshot() -> [CompanyAgent] {
        agents.map { agent in
            var copy = agent
            if copy.backend.type == .api {
                if !copy.backend.apiKey.isEmpty {
                    writeAPIKeyToKeychain(copy.backend.apiKey, agentID: copy.id, context: "快照前归档".L())
                }
                // 即便 keychain 写失败也仍然清空 in-memory copy，保留「snapshot 不携带明文 apiKey」
                // 的既有约束（持久化层未变更）；失败已经通过 writeAPIKeyToKeychain 转成 in-memory 风险事件，
                // 老板可在事件流看到 API Key 写入 Keychain 失败提示并重新填写。
                copy.backend.apiKey = ""
            }
            return copy
        }
    }

    /// 调用注入的 keychain 写入闭包并把非成功 OSStatus 转换成老板可见的 in-memory 风险事件。
    /// 把 hydrate / 快照两条路径上的 keychain 写入收敛到一处，避免遗漏其中一处不上报。
    @discardableResult
    private func writeAPIKeyToKeychain(_ value: String, agentID: UUID, context: String) -> OSStatus {
        let status = keychainSaveAPIKey(value, agentID)
        if status != errSecSuccess {
            recordKeychainSaveFailure(status: status, agentID: agentID, context: context)
        }
        return status
    }

    /// 把一次 Keychain 写入失败转换成 in-memory 风险事件，与 `recordPersistenceFailure` 同模式：
    /// 1. **不调用 saveSnapshot**：失败发生在快照前归档路径，递归 save 会再次触发同一次 keychain 写入失败。
    /// 2. **相邻同员工同状态去重**：避免锁屏 / 沙箱权限缺失等持续性故障刷屏老板事件流。
    /// 3. **保留员工 ID**：方便事件流按员工聚合，老板可定位到具体 API 员工的 Key 配置。
    private func recordKeychainSaveFailure(status: OSStatus, agentID: UUID, context: String) {
        let title = "API Key 写入 Keychain 失败".L()
        let name = agents.first(where: { $0.id == agentID })?.displayName ?? "未知员工".L()
        let detail = "\(name)" + " · " + "\(context)" + " · OSStatus=".L() + "\(status)" + "。本次输入的 Key 仍在内存中可用，但应用重启后会丢失，需要重新填写并确认 Keychain 是否被锁定或权限受限。".L()
        if let latest = events.first,
           latest.kind == .risk,
           latest.title == title,
           latest.agentID == agentID,
           latest.detail == detail {
            return
        }
        appendEvent(kind: .risk, title: title, detail: detail, agentID: agentID)
    }

    private func safetyCheckpointURLs(limit: Int) -> [URL] {
        let directory = CompanyPersistence.stateURL.deletingLastPathComponent().appendingPathComponent("checkpoints", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = ((try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                let rightDate = ((try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
        return Array(sorted.prefix(max(0, limit)))
    }

    private func checkpointDateText(for url: URL) -> String {
        let date = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()
        return date.opcDateTimeText
    }

    private func applyRestoredSnapshot(_ snapshot: CompanySnapshot) {
        agents = snapshot.agents
        selectedAgentID = snapshot.selectedAgentID
        messages = snapshot.messages
        events = snapshot.events
        tasks = snapshot.tasks
        products = snapshot.products
        selectedProductID = snapshot.selectedProductID
        workQueue = snapshot.workQueue
        approvals = snapshot.approvals
        artifacts = snapshot.artifacts
        verifications = snapshot.verifications
        memories = snapshot.memories
        agentProfiles = snapshot.agentProfiles
        communicationChannels = snapshot.communicationChannels
        communicationLogs = snapshot.communicationLogs
        branchPlans = snapshot.branchPlans
        reviewGates = snapshot.reviewGates
        terminalLogs = snapshot.terminalLogs
        productTerminalLogs = snapshot.productTerminalLogs
        runningAgentIDs.removeAll()
        mainWorkspace = .office
        ensureAgentProfiles()
        hydrateAPIKeysFromKeychain()
        repairSelectionState()
        syncAllAgentWorkspaces()
    }

    private func ensureAgentProfiles() {
        for agent in agents where agentProfiles[agent.id] == nil {
            agentProfiles[agent.id] = AgentOperatingProfile.defaultProfile(for: agent)
        }
    }

    private func listItems(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-• "))
            }
            .filter { !$0.isEmpty }
    }

    private func replacementAgentID(forRemovedRole role: AgentRole) -> UUID {
        switch role {
        case .tester:
            agents.first { $0.role == .reviewer }?.id ?? ctoID
        default:
            ctoID
        }
    }

    private func isLegacyAutoCreatedSpecialist(_ agent: CompanyAgent) -> Bool {
        switch agent.role {
        case .productArchitect:
            agent.displayName == "Codex 产品架构师".L()
                && agent.title == "需求与产品结构负责人".L()
                && agent.backend.command == "codex"
        case .tester:
            agent.displayName == "Codex 测试工程师".L()
                && agent.title == "自动化验证负责人".L()
                && agent.backend.command == "codex"
        case .researcher:
            agent.displayName == "Gemini 研究员".L()
                && agent.title == "资料与竞品研究员".L()
                && agent.backend.command == "gemini"
        default:
            false
        }
    }

    private func isLegacySyntheticAgentReply(_ text: String) -> Bool {
        let patterns = [
            "我的角色档案".L(),
            "我会把这件事拆成任务计划".L(),
            "我会结合记忆".L(),
            "OPC 公司已经上线".L(),
            "OPC 公司已经恢复到默认状态".L(),
            "我负责把产品想法转成视觉方向".L(),
            "我负责按技术负责人的任务卡实现代码".L(),
            "我负责按照成功标准审查结果".L(),
            "我已经配置完成".L(),
            "我已加入当前产品团队".L(),
            "我会按技术负责人 → UI/产品 → 工程 → 测试 → 审查 → 老板批准".L()
        ]
        return patterns.contains { text.contains($0) }
    }

    private func environmentOverrides(for agent: CompanyAgent) -> [String: String] {
        guard agent.backend.type == .api else { return [:] }
        return [
            "OPC_AGENT_API_KEY": agent.backend.apiKey,
            "OPC_AGENT_ENDPOINT": agent.backend.endpoint,
            "OPC_AGENT_MODEL": agent.backend.model
        ]
    }

    private func cliResumeSessionID(for agent: CompanyAgent) -> String? {
        guard agent.backend.type == .subscriptionCLI,
              supportsCLIResume(agent),
              let session = runtimeSessions[agent.id]
        else { return nil }
        let signature = CLIAgentCommandBuilder.backendSignature(for: agent)
        let mode = cliSessionMode(for: agent)
        if let entry = session.cliSessionsByProduct?[selectedProductID],
           entry.productID == selectedProductID,
           entry.backendSignature == signature,
           entry.mode == mode {
            let id = entry.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        }

        guard session.productID == selectedProductID,
              session.backendSignature == signature,
              session.cliSessionMode == mode,
              let id = session.cliSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else { return nil }
        return id
    }

    private func recordCLISessionIfNeeded(agent: CompanyAgent, result: CommandExecutionResult, usedResumeSessionID: String?) {
        guard result.exitCode == 0,
              agent.backend.type == .subscriptionCLI,
              supportsCLIResume(agent)
        else { return }

        let detectedID = cliSessionID(from: result.combinedOutput) ?? usedResumeSessionID
        guard let detectedID, !detectedID.isEmpty else { return }

        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.productID = selectedProductID
        session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
        session.capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        session.cliSessionID = detectedID
        session.cliSessionMode = cliSessionMode(for: agent)
        session.lastUsedAt = Date()
        var conversations = session.cliSessionsByProduct ?? [:]
        conversations[selectedProductID] = AgentCLIConversation(
            productID: selectedProductID,
            sessionID: detectedID,
            mode: cliSessionMode(for: agent),
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: agent),
            lastUsedAt: session.lastUsedAt ?? Date(),
            failureCount: 0,
            lastFailureReason: nil
        )
        session.cliSessionsByProduct = conversations
        runtimeSessions[agent.id] = session
    }

    func handleFailedCLIResumeIfNeeded(agent: CompanyAgent, result: CommandExecutionResult, usedResumeSessionID: String?) {
        guard result.exitCode != 0,
              agent.backend.type == .subscriptionCLI,
              supportsCLIResume(agent),
              let usedResumeSessionID,
              var session = runtimeSessions[agent.id]
        else { return }

        let mode = cliSessionMode(for: agent)
        guard var entry = session.cliSessionsByProduct?[selectedProductID],
              entry.sessionID == usedResumeSessionID,
              entry.mode == mode,
              entry.backendSignature == CLIAgentCommandBuilder.backendSignature(for: agent)
        else { return }

        let nextFailureCount = (entry.failureCount ?? 0) + 1
        let reason = displayableChatError(from: result.combinedOutput)
        entry.failureCount = nextFailureCount
        entry.lastFailureReason = String(reason.prefix(240))
        entry.lastUsedAt = Date()

        var conversations = session.cliSessionsByProduct ?? [:]
        if nextFailureCount >= 2 {
            conversations.removeValue(forKey: selectedProductID)
            session.cliSessionID = session.cliSessionID == usedResumeSessionID ? nil : session.cliSessionID
            session.cliSessionMode = session.cliSessionMode == mode ? nil : session.cliSessionMode
            appendTerminalLog("\n[OPC 上下文已重置]\n当前产品的上一轮上下文连续不可用 ".L() + "\(nextFailureCount)" + " 次，后续任务将重新开始。\n".L(), for: agent.id)
            appendEvent(kind: .statusChanged, title: "\(agent.displayName)" + " 上下文已重置", detail: "当前产品的上一轮任务上下文连续不可用，已自动重置；下一次会重新开始。".L(), agentID: agent.id)
        } else {
            conversations[selectedProductID] = entry
            appendTerminalLog("\n[OPC 上下文复用失败]\n当前产品的上一轮上下文暂时不可用 ".L() + "\(nextFailureCount)" + " 次；再次不可用会自动重置。\n".L(), for: agent.id)
        }
        session.cliSessionsByProduct = conversations.isEmpty ? nil : conversations
        runtimeSessions[agent.id] = session
    }

    func recordCLIInteractionObservationIfNeeded(agent: CompanyAgent, result: CommandExecutionResult) {
        guard let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) else { return }
        let previousPhase = runtimeSessions[agent.id]?.cliInteractionPhase
        let observation = CLIInteractionStateMachine.observe(output: result.combinedOutput, profile: profile, previousPhase: previousPhase ?? .awaitingResponse)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.productID = selectedProductID
        session.backendSignature = CLIAgentCommandBuilder.backendSignature(for: agent)
        session.capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        session.cliInteractionPhase = observation.phase
        session.cliInteractionReason = observation.reasonTitle
        session.cliInteractionObservedAt = Date()
        session.cliInteractionSessionID = observation.sessionID
        let recoveryAction = CLIInteractionStateMachine.recoveryAction(for: observation.phase)
        session.cliInteractionRecoveryAction = recoveryAction
        session.cliInteractionRecoveryActionTitle = recoveryAction.title
        session.cliInteractionRecoveryHint = recoveryAction.operatorHint
        session.cliInteractionOperatorHint = recoveryAction.operatorHint
        runtimeSessions[agent.id] = session

        if previousPhase != observation.phase, observation.phase != .unknown {
            let recoveryLine: String
            if let operatorHint = recoveryAction.operatorHint {
                recoveryLine = "建议：".L() + "\(recoveryAction.title)" + "。" + "\(operatorHint)" + "\n"
            } else {
                recoveryLine = ""
            }
            appendTerminalLog("\n[OPC 交互状态]\n状态：".L() + "\(observation.reasonTitle)" + "。\n" + "\(recoveryLine)", for: agent.id)

            // 升级到 attention 状态（技术负责人和老板都应看到的健康风险）写一条结构化事件，
            // 便于回查"过去一段时间出现过几次授权异常 / 忙碌 / 临时异常"。
            // ready / completedTurn / awaitingResponse 等常规状态不写事件，避免噪音。
            // phase 去重逻辑（previousPhase != observation.phase）保证同一 attention 状态
            // 不会被反复写事件。
            if isCLIAttentionPhaseForAuditEvent(observation.phase) {
                let detail: String
                if let hint = recoveryAction.operatorHint {
                    detail = "\(observation.reasonTitle)" + " · 建议：".L() + "\(recoveryAction.title)" + "。" + "\(hint)"
                } else {
                    detail = "\(observation.reasonTitle)" + " · 建议：".L() + "\(recoveryAction.title)" + "。"
                }
                appendEvent(
                    kind: .risk,
                    title: "命令行健康预警：".L() + "\(agent.displayName)",
                    detail: detail,
                    agentID: agent.id
                )
            }
        }
    }

    /// 是否需要为该 phase 写一条结构化健康预警事件（仅升级到 attention 状态时写）。
    /// 与轮 4 `terminalAgentCardHealthBadge` 的可视化口径一致：
    /// busy / authenticationBlocked / transientFailure 进事件流；
    /// awaitingResponse 不进（属于常规等待，不是预警）；
    /// ready / completedTurn / unknown 不进。
    private func isCLIAttentionPhaseForAuditEvent(_ phase: CLIInteractionPhase) -> Bool {
        switch phase {
        case .busy, .authenticationBlocked, .transientFailure:
            return true
        case .unknown, .ready, .awaitingResponse, .completedTurn:
            return false
        }
    }

    private func codexSessionID(from output: String) -> String? {
        cliSessionID(from: output)
    }

    private func cliSessionID(from output: String) -> String? {
        CLIInteractionProfileCatalog.sessionID(from: output)
    }

    private func supportsCLIResume(_ agent: CompanyAgent) -> Bool {
        CLIAgentCommandBuilder.interactionProfile(for: agent)?.supportsResume == true
    }

    private func cliSessionMode(for agent: CompanyAgent) -> String {
        CLIAgentCommandBuilder.interactionProfile(for: agent)?.sessionMode ?? "unknown"
    }

    private func isolatedHomeURL(for agent: CompanyAgent, executionDirectory: URL) -> URL? {
        guard agent.backend.type == .subscriptionCLI else { return nil }
        guard currentRuntimeCapability(for: agent) != .persistentProtocol else { return nil }
        return executionDirectory
    }

    private func sandboxProfile(for agent: CompanyAgent, executionDirectory: URL) -> String? {
        guard selectedProduct?.enforceSandbox == true else { return nil }
        guard currentRuntimeCapability(for: agent) != .persistentProtocol else { return nil }
        let productRoot = executionDirectory.standardizedFileURL.path
        let userHome = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let escapedProductRoot = sandboxEscaped(productRoot)
        let deniedHomeRules = [
            "\(userHome)/.ssh",
            "\(userHome)/.codex",
            "\(userHome)/.claude",
            "\(userHome)/.gemini",
            "\(userHome)/Library"
        ].map { "(deny file* (subpath \"\(sandboxEscaped($0))\"))" }.joined(separator: "\n")
        return """
        (version 1)
        (allow default)
        \(deniedHomeRules)
        (allow file-read* (subpath "\(escapedProductRoot)"))
        (allow file-write* (subpath "\(escapedProductRoot)"))
        """
    }

    private func sandboxEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func currentRuntimeCapability(for agent: CompanyAgent) -> AgentRuntimeCapability {
        let signature = CLIAgentCommandBuilder.backendSignature(for: agent)
        if let session = runtimeSessions[agent.id],
           session.backendSignature == signature,
           session.productID == selectedProductID {
            return session.capability
        }
        return CLIAgentCommandBuilder.runtimeCapability(for: agent)
    }

    private func maxSeverity(_ lhs: VerificationStatus, _ rhs: VerificationStatus) -> VerificationStatus {
        if lhs == .failed || rhs == .failed { return .failed }
        if lhs == .warning || rhs == .warning { return .warning }
        return .passed
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

private extension JSONEncoder {
    static var opcCheckpoint: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var opcCheckpoint: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 终端大厅员工卡顶部「健康徽章」紧凑视觉数据。
///
/// 由 `terminalAgentCardHealthBadge(for:)` 返回；view 用配色短徽章渲染。
/// 默认不显示（返回 nil）；只有 awaitingResponse / busy / authenticationBlocked / transientFailure
/// 等需要技术负责人注意的状态才浮现徽章，避免常规状态下打扰。
public struct TerminalAgentCardHealthBadge: Hashable, Sendable {
    public enum Severity: Sendable {
        case info, warning, danger
    }

    public let title: String
    public let severity: Severity
    public let detail: String?

    public init(title: String, severity: Severity, detail: String?) {
        self.title = title
        self.severity = severity
        self.detail = detail
    }
}

/// 终端大厅顶部「运行状态」概览的视觉层结构化指标。
///
/// 由 `terminalHallOverviewMetrics()` 返回；view 用 `MetricChip` 渲染，颜色按 `kind` 映射。
/// 与下方 3 张 SummaryCard 的 chip 视觉风格一致，避免顶部纯文本与下方 chip 风格割裂。
public struct TerminalHallOverviewMetric: Hashable, Sendable {
    public enum Kind: Sendable {
        case neutral, ok, warning, danger
    }

    public let title: String
    public let value: Int
    public let kind: Kind

    public init(title: String, value: Int, kind: Kind) {
        self.title = title
        self.value = value
        self.kind = kind
    }
}

public struct EmployeeDraft: Sendable {
    public var displayName: String = ""
    public var title: String = ""
    public var role: AgentRole = .custom
    public var backendType: BackendType = .subscriptionCLI
    public var command: String = "claude"
    public var model: String = "sonnet"
    public var endpoint: String = ""
    public var apiKey: String = ""
    public var reasoningEffort: ReasoningEffort = .medium
    public var ethnicity: EthnicityPresentation = .chinese
    public var gender: GenderPresentation = .woman
    public var clothing: ClothingStyle = .smartCasual
    public var permissions: Set<AgentPermission> = [.readFiles]

    public init() {}
}
