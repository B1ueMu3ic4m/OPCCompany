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
            return "让技术负责人推进一次".L().L()
        case .running:
            return "正在推进".L().L()
        }
    }

    public var statusText: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "正在让技术负责人推进…".L().L()
        case .completed:
            return "技术负责人已完成本次推进。".L().L()
        }
    }
}

@MainActor
public final class CompanyStore: ObservableObject {


    static let cliResumeContextNotice = "\n[OPC 上下文复用]\n本次任务会接续该员工在当前产品里的上一轮上下文。\n".L().L()

static func defaultProductRootDirectoryURL() -> URL {
        internalProductWorkspaceURL(slug: "default-product")
    }



static func internalProductWorkspaceURL(slug: String) -> URL {
        let directory = CompanyPersistence.productWorkspacesURL.appendingPathComponent(slug, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

static func legacyDesktopURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .standardizedFileURL
    }



static func normalizedProductShortName(name: String, proposed: String) -> String {
        let clean = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return String(clean.prefix(6))
        }
        return String(name.prefix(3))
    }

static let agentChatRecentMessagePromptLimit = 700
static let agentChatMemoryPromptLimit = 420
static let agentChatUserTextPromptLimit = 2_000
static let agentChatRepairDraftPromptLimit = 1_200
static let agentProfileMissionPromptLimit = 600
static let agentProfileListItemPromptLimit = 280
static let agentProfileMemoryPromptLimit = 420
static let agentProfileSkillPromptLimit = 220
static let agentProfilePromptItemLimit = 8
static let agentProfilePromptMemoryItemLimit = 4
static let agentSystemProductMemoryPromptLimit = 420
static let agentSystemProductMemoryPromptItemLimit = 6
static let workOrderPromptTextLimit = 800
static let workOrderPromptPathLimit = 300
static let workOrderPromptListItemLimit = 80
static let workOrderPromptRuleItemLimit = 8
static let workOrderPromptToolItemLimit = 8
static let workOrderPromptProjectFileItemLimit = 12
static let reworkPromptReasonLimit = 1_200
static let reworkPromptSuccessCriteriaLimit = 1_200
static let agentMessageSubjectTextLimit = 240
static let agentMessageBodyTextLimit = 2_400
    static let persistentSeatExecutionNotice = "\n[OPC 长期席位执行]\n本次任务会在该员工的长期席位运行；完成后会被收录到产物记录和验收流程。\n".L().L()

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
    var runtimeSupervisorStarted = false
    var inboundCommandNonces: Set<String>
    var cachedTerminalWorkspaceHealthSnapshot: TerminalWorkspaceHealthSnapshot?
    var persistentTerminalSessions: [PersistentTerminalSessionKey: PersistentTerminalSession] = [:]
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
                displayName: "老板".L().L(),
                title: "OPC 公司老板".L().L(),
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
                displayName: "Codex 技术负责人".L().L(),
                title: "总技术负责人".L().L(),
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
                displayName: "Gemini 界面设计师".L().L(),
                title: "视觉产品设计师".L().L(),
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
                displayName: "Claude Code 工程师".L().L(),
                title: "高级 macOS 工程师".L().L(),
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
                displayName: "Codex 审查员".L().L(),
                title: "风险与验收审查员".L().L(),
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
            CompanyEvent(kind: .statusChanged, title: "公司已启动".L().L(), detail: "已创建默认技术负责人、界面、编码和审查员工。".L().L(), agentID: ctoID)
        ]

        let defaultProductID = UUID()
        let defaultProduct = ProductWorkspace(
            id: defaultProductID,
            name: "默认产品工作区".L().L(),
            shortName: "默认".L().L(),
            rootDirectory: defaultProductRootDirectory(),
            status: .active,
            stage: .discovery,
            assignedAgentIDs: [ctoID, uiID, codeID, reviewID],
            teamLeadAgentID: ctoID
        )

        let messages = [
            ChatMessage(productID: defaultProductID, agentID: ctoID, author: .system, text: "系统提示：OPC 公司已经上线。正式沟通会调用员工配置的真实模型来源；未配置或不可用时只显示系统降级提示。".L().L()),
            ChatMessage(productID: defaultProductID, agentID: uiID, author: .system, text: "系统提示：Gemini 界面设计师已创建，档案、记忆和技能已写入员工工作区。".L().L()),
            ChatMessage(productID: defaultProductID, agentID: codeID, author: .system, text: "系统提示：Claude Code 工程师已创建，档案、记忆和技能已写入员工工作区。".L().L()),
            ChatMessage(productID: defaultProductID, agentID: reviewID, author: .system, text: "系统提示：Codex 审查员已创建，档案、记忆和技能已写入员工工作区。".L().L())
        ]

        let tasks = [
            CompanyTask(productID: defaultProduct.id, title: "定义产品架构".L().L(), ownerID: ctoID, status: .done, successCriteria: "完成产品规格、技术栈和角色系统。".L().L()),
            CompanyTask(productID: defaultProduct.id, title: "创建 2D 公司应用基础".L().L(), ownerID: codeID, status: .running, successCriteria: "构建原生 macOS SwiftUI/SpriteKit 外壳，并支持点击员工沟通。".L().L()),
            CompanyTask(productID: defaultProduct.id, title: "审查命令行调度设计".L().L(), ownerID: reviewID, status: .planned, successCriteria: "确认 Codex、Claude、Gemini 命令适配器安全且可扩展。".L().L())
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
    /// 均改用本 accessor 过滤维护类前缀，避免技术细节挤占老板首页"最近风险".L().L() widget 的
    /// prefix(5) / prefix(3) 容量。**没有任何 view 仍在直接读 `selectedProductRiskEvents`**
    /// （由 `selectedProductRiskEventsHasNoUIConsumerAfterBossViewMigration` 守门），后者只用于
    /// 本 accessor 自身派生 + 内部团队负责人手机汇报报告文本计数。
    /// 与维护类 VR/AR 隔离（`technicalMaintenanceVerificationTitles` / `technicalMaintenanceArtifactTitlePrefixes`）
    /// 同模式：单独维护一份"老板视图剔除前缀"白名单，新增维护类事件标题时同步登记到此处。
    ///
    /// **白名单设计原则**（角色继承期轮 11 加固）：
    /// - 进入白名单的判定标准：纯后端/文件系统/进程层失败，老板无法处理也不需要决策。
    /// - 不进入白名单的判定标准：老板的某个动作被阻止 / 涉及业务审批 / 涉及交付物状态 — 这些都是
    ///   老板的"待决策".L().L()或"待理解"信号，必须保留可见。
    /// - 例：「命令行作业目录创建失败」「命令行作业档案写入失败」属于 .opc/jobs/ 后端文件操作失败，
    ///   后端继续运行不阻断业务，老板看不懂也无法处理 → 进入白名单。
    /// - 例：「命令行发车被阻止」是老板试图运行命令行任务但前置检查不通过 → 老板需要知道，**不**进入白名单。
    public static let bossViewExcludedRiskTitlePrefixes: [String] = [
        "命令行健康预警：".L().L(),
        "命令行作业".L().L(),
        "旧任务产品归属迁移".L().L()
    ]

    public static let closureDrillGoalMarker = "[演练]".L().L()

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
        let productName = selectedProduct?.name ?? "当前产品".L().L()
        let header = "老板报告：".L().L() + "\(productName)"
        let scopedReports = messages(for: bossID, in: selectedProductID, includingLegacyGlobal: false)
            .reversed()
            .filter { $0.text.hasPrefix("老板报告：".L().L()) }
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
        "安全检查点".L().L()
    ]

    public static let technicalMaintenanceArtifactTitlePrefixes: [String] = [
        "闭环审计报告：".L().L(),
        "命令行作业档案：".L().L(),
        "本地文件索引：".L().L()
    ]

    public static let deliveryArtifactTitleExactMatches: Set<String> = []

    public static let deliveryArtifactTitlePrefixes: [String] = [
        "验收产物：".L().L(),
        "验收报告：".L().L()
    ]











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

    /// 当前产品下"本地文件索引".L().L()维护产物的数量。
    /// 售前方案工厂等需要引用本地资料索引的内部模型 prompt 用此 helper：技术负责人维护侧（不是老板/交付）
    /// 才能看到这些索引产物，但模型仍可基于 prompt 里的索引数量做判断；老板/交付视图不展示。
    public var selectedProductLocalFileIndexArtifactCount: Int {
        selectedProductMaintenanceArtifacts.filter { $0.title.hasPrefix("本地文件索引：".L().L()) }.count
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
    static func titleLooksLikeStructuredPrefix(_ title: String) -> Bool {
        if title.contains("：") { return true }
        guard let colonSpaceRange = title.range(of: ": ") else { return false }
        let prefix = title[title.startIndex..<colonSpaceRange.lowerBound]
        // 路径/URL 含 `/` 或 `\` —— 视为动态证据，不报告。
        let hasPathMarker = prefix.contains(where: { $0 == "/" || $0 == "\\" })
        return !hasPathMarker
    }



    /// 维护数据建议阈值：维护类 VerificationRecord 累计超过 100 条 / 维护类 ArtifactRecord 累计超过 500 条
    /// 时给技术负责人提示。当前不做任何删除/裁剪：主快照仍是权威状态，长期清理仍由历史归档 RFC 决定。
    public static let maintenanceVerificationGrowthAdvisoryThreshold = 100
    public static let maintenanceArtifactGrowthAdvisoryThreshold = 500
    public static let maintenanceStateSnapshotAdvisoryBytes: Int64 = 20 * 1024 * 1024
    public static let maintenanceJobArchiveCountAdvisoryThreshold = 100
    public static let maintenanceJobArchiveBytesAdvisoryThreshold: Int64 = 100 * 1024 * 1024



    public var legacyTaskWithoutProductIDCount: Int {
        tasks.filter { $0.productID == nil }.count
    }





static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

static func directoryFileSize(at url: URL) -> Int64 {
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

static func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
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
        "真实终端工作区".L().L(),
        "真实终端日志刷新".L().L(),
        "持久终端可用性巡检".L().L(),
        "命令行链路压测预检".L().L(),
        "命令行任务发车计划".L().L(),
        "命令行与工作区隔离体检".L().L(),
        "多产品隔离体检".L().L(),
        "命令行作业幽灵巡检".L().L(),
        "员工交接待确认巡检".L().L(),
        "运行会话健康巡检".L().L(),
        "异常占用会话恢复".L().L(),
        "历史索引巡检".L().L(),
        "历史归档迁移".L().L(),
        "旧任务产品归属迁移".L().L(),
        "本地文件索引完成".L().L(),
        "本地文件索引被拒绝".L().L(),
        "安全检查点已创建".L().L(),
        "安全检查点失败".L().L(),
        "运行证据分类巡检".L().L(),
        "维护数据增长巡检".L().L(),
        "自动状态摘要去重清理".L().L()
    ]

    /// 老板/交付视图必须保留的「交付/验收证据」精确标题。
    public static let deliveryVerificationTitleExactMatches: Set<String> = [
        "自动验收检查".L().L(),
        "产物扫描完成".L().L(),
        "产物扫描失败".L().L()
    ]

    /// 老板/交付视图必须保留的「交付/验收证据」前缀标题（带任务标题等动态后缀）。
    public static let deliveryVerificationTitlePrefixes: [String] = [
        "老板验收通过：".L().L()
    ]



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
                title: "结构化消息总线".L().L(),
                status: messages.isEmpty ? .failed : (hasDispatch && hasWorkReturn ? .passed : .warning),
                detail: messages.isEmpty
                    ? "当前产品还没有员工协作消息。请在技术负责人后台点击「运行闭环演练」，生成任务派发、员工回传、审查和审批证据。".L().L()
                    : "当前产品已有 ".L().L() + "\(messages.count)" + " 条消息；派发 ".L().L() + "\(hasDispatch ? "已出现" : "未出现")" + "，回传 ".L().L() + "\(hasWorkReturn ? "已出现" : "未出现")" + "。"
            ),
            MultiAgentArchitectureCheck(
                id: "task-graph",
                title: "显式任务图".L().L(),
                status: taskGraphNodeCount >= 4 && taskGraphEdgeCount >= 4 ? .passed : (supervisorTasks.isEmpty ? .failed : .warning),
                detail: taskGraphNodeCount >= 4 && taskGraphEdgeCount >= 4
                    ? "已派生 ".L().L() + "\(taskGraphNodeCount)" + " 个节点、".L().L() + "\(taskGraphEdgeCount)" + " 条边；闭合边 ".L().L() + "\(taskGraphClosedEdgeCount)" + " 条。"
                    : "当前仍主要是普通任务；点击「运行闭环演练」后会形成技术负责人拆解、员工执行、审查验收和老板审批的标准任务图。".L().L()
            ),
            MultiAgentArchitectureCheck(
                id: "cto-loop",
                title: "技术负责人调度闭环".L().L(),
                status: hasGoalStart && hasLoopProgress ? .passed : (hasGoalStart ? .warning : .failed),
                detail: hasGoalStart
                    ? "技术负责人目标已启动；".L().L() + "\(hasLoopProgress ? "已有循环推进消息。" : "还缺少循环推进记录。")"
                    : "还没有技术负责人启动目标记录。请运行闭环演练或启动技术负责人协作目标来生成调度证据。".L().L()
            ),
            MultiAgentArchitectureCheck(
                id: "artifact-store",
                title: "交付证据库".L().L(),
                status: strongestEvidenceStatus == .passed
                    ? .passed
                    : (strongestEvidenceStatus == .warning || hasArtifacts || hasVerifications ? .warning : .failed),
                detail: "闭环关联产物 ".L().L() + "\(linkedArtifactCount)" + " 条、验收 ".L().L() + "\(linkedVerificationCount)" + " 条；当前产品总交付产物 ".L().L() + "\(selectedProductDeliveryArtifacts.count)" + " 条、总交付验收 " + "\(selectedProductDeliveryVerifications.count)" + " 条。闭环关联为 0 时请运行闭环演练补齐证据。"
            ),
            MultiAgentArchitectureCheck(
                id: "review-gate",
                title: "验收门禁".L().L(),
                status: strongestReviewGateStatus == .passed
                    ? .passed
                    : (strongestReviewGateStatus == .warning || hasReviewGates || hasReview ? .warning : .failed),
                detail: "闭环关联门禁 ".L().L() + "\(linkedReviewGateCount)" + " 条；当前产品总门禁 ".L().L() + "\(selectedProductReviewGates.count)" + " 条，审查/验收消息 ".L().L() + "\(hasReview ? "已出现".L() : "未出现".L())" + "。闭环关联为 0 时请运行闭环演练补齐审查和验收证据。".L().L()
            ),
            terminalWorkspaceArchitectureCheck(),
            MultiAgentArchitectureCheck(
                id: "boss-view",
                title: "老板视图减噪".L().L(),
                status: .passed,
                detail: "老板侧使用决策中心和交付验收中心入口；当前待老板决策 ".L().L() + "\(bossDecisionCount)" + " 项，审批追踪 " + "\(hasApprovalTrace ? "已出现" : "暂无")" + "。"
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






    public var selectedProductAgents: [CompanyAgent] {
        productAgents(for: selectedProductID)
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


    public var isRunningAgent: Bool {
        !runningAgentIDs.isEmpty
    }






    func repairSelectionState() {
        if !products.contains(where: { $0.id == selectedProductID }), let firstProductID = products.first?.id {
            selectedProductID = firstProductID
        }
        if !agents.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
        }
        ensureSelectedAgentIsValidForSelectedProduct()
    }











    public func missingRoles(for template: ProductTeamTemplate) -> [AgentRole] {
        template.roles.filter { role in
            !agents.contains { $0.role == role }
        }
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
            summary: "后续还有 ".L().L() + "\(hidden)" + " 位员工。这里先显示关键进度，完整团队仍在产品详情和员工工作台查看。".L().L()
        )
    }


    public func bossInspectorRecentEventsOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductBossEvents.count
        let limit = Self.bossInspectorRecentEventsDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 条近期汇报。这里先显示最近重点，关键进展会继续浮现。".L().L()
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









    public var productDetailRecentDeliveryVerifications: [VerificationRecord] {
        Array(selectedProductRecentDeliveryVerifications.prefix(Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit))
    }

    public var productDetailRecentDeliveryArtifacts: [ArtifactRecord] {
        Array(selectedProductRecentDeliveryArtifacts.prefix(Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit))
    }



    public var workflowMapRecentAgentMessages: [AgentMessageEnvelope] {
        Array(selectedProductRecentAgentMessages.prefix(Self.workflowMapMessageFlowDefaultDisplayLimit))
    }








    public var selectedProductBossReportEvents: [CompanyEvent] {
        selectedProductBossEvents.filter { event in
            event.title.contains("报告".L().L()) || event.title.contains("快照".L().L()) || event.kind == .artifactCreated
        }
    }

    public var bossReportCenterReportEvents: [CompanyEvent] {
        Array(selectedProductBossReportEvents.prefix(Self.bossReportCenterReportEventsDisplayLimit))
    }

    public var bossReportCenterBossMessages: [ChatMessage] {
        Array(selectedProductBossReportMessages.prefix(Self.bossReportCenterBossMessagesDisplayLimit))
    }



    public var bossDecisionCenterResolvedApprovals: [ApprovalRequest] {
        Array(selectedProductResolvedApprovals.prefix(Self.bossDecisionCenterResolvedApprovalsDisplayLimit))
    }

    public var bossDecisionCenterRiskEvents: [CompanyEvent] {
        Array(selectedProductBossRiskEvents.prefix(Self.bossDecisionCenterRiskEventsDisplayLimit))
    }



    public var communicationGatewayVisibleLogs: [CommunicationLogEntry] {
        Array(selectedProductCommunicationLogs.prefix(Self.communicationGatewayLogDisplayLimit))
    }


    public var localMaintenanceVisibleVerifications: [VerificationRecord] {
        Array(selectedProductRecentMaintenanceVerifications.prefix(Self.localMaintenanceVerificationDisplayLimit))
    }


    public var localMaintenanceVisibleArtifacts: [ArtifactRecord] {
        Array(selectedProductRecentMaintenanceArtifacts.prefix(Self.localMaintenanceArtifactDisplayLimit))
    }



    func listOverflow(total: Int, limit: Int, noun: String, continuation: String) -> AgentDeskListOverflow? {
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " " + "\(noun)" + "。" + "\(continuation)"
        )
    }



    /// 员工工作台「负责的任务」面板默认展开上限（与轮 2 待审队列同模式：
    /// 任务多时只展开前 N 项 + 单行 footer 提示，不引入 DisclosureGroup 折叠）。
    public static let agentDeskAssignedTasksDefaultDisplayLimit: Int = 3


    /// 员工工作台「员工工作队列」面板默认展开上限。
    public static let agentDeskWorkQueueDefaultDisplayLimit: Int = 3


    /// 员工工作台「我的协作收件箱」面板默认展开上限。
    /// 与轮 2/4 三面板（reviewQueue / assignedTasks / workQueue）同模式但 limit 较大（6 而非 3）：
    /// 收件箱是核心协作功能，过度收敛会损害"看到最近收到的消息"的本能；
    /// 因此 limit 维持原始 6（保留协作 UX），但溢出时也加共享 footer 提示，与三面板一致。
    public static let agentDeskInboxDefaultDisplayLimit: Int = 6

    /// 产品详情「员工协作链路」默认只展示最近 3 条；完整协作历史进入「查看全部」。
    public static let productDetailAgentCollaborationDefaultDisplayLimit: Int = 3


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
        appendEvent(kind: .statusChanged, title: "模型路由已更新".L().L(), detail: "\(role.title)：\(updatedNames.joined(separator: "、"))。", agentID: nil)
        saveSnapshot()
    }

    public func workOrderPrompt(for task: CompanyTask) -> String {
        let product = selectedProduct
        let owner = task.ownerID.flatMap { id in agents.first { $0.id == id } }
        let report = product?.importReport
        let ruleLine = Self.promptInlineList(
            report?.ruleFiles ?? [],
            empty: "无".L().L(),
            itemLimit: Self.workOrderPromptRuleItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let toolLine = Self.promptInlineList(
            report?.detectedTools ?? [],
            empty: "未识别".L().L(),
            itemLimit: Self.workOrderPromptToolItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let projectFiles = Self.promptInlineList(
            report?.projectFiles ?? [],
            empty: "无".L().L(),
            itemLimit: Self.workOrderPromptProjectFileItemLimit,
            itemTextLimit: Self.workOrderPromptListItemLimit
        )
        let taskTitle = Self.promptFragment(task.title, limit: Self.workOrderPromptTextLimit)
        let successCriteria = Self.promptFragment(task.successCriteria, limit: Self.workOrderPromptTextLimit)
        let artifactPath = Self.promptFragment(task.artifactPath ?? "未指定".L().L(), limit: Self.workOrderPromptPathLimit)
        let productName = Self.promptFragment(product?.name ?? "当前产品".L().L(), limit: Self.workOrderPromptTextLimit)
        let productRoot = Self.promptFragment(product?.rootDirectory ?? "未设置".L().L(), limit: Self.workOrderPromptPathLimit)

        return """
        \("你是 OPC 公司员工：".L())\(owner?.displayName ?? "未分配员工".L())\("，职位：".L())\(owner?.title ?? "待定".L())。
        \("当前产品：".L())\(productName)
        \("项目根目录：".L())\(productRoot)
        \("项目阶段：".L())\(product?.stage.title ?? "未知".L()) / \(product?.status.title ?? "未知".L())

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







    public func decideApproval(_ approvalID: UUID, approved: Bool) {
        guard let index = approvals.firstIndex(where: { $0.id == approvalID }) else { return }
        guard approvals[index].status == .pending else { return }
        approvals[index].status = approved ? .approved : .rejected
        approvals[index].decidedAt = Date()
        let approval = approvals[index]
        let linkedTask = approval.taskID.flatMap { taskID in tasks.first(where: { $0.id == taskID }) }
        let isSupervisorBossApproval = linkedTask?.title.hasPrefix("老板审批：".L()) == true
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
        appendEvent(kind: approved ? .statusChanged : .risk, title: approved ? "审批已批准".L() : "审批已驳回".L(), detail: approval.title, agentID: approval.requesterID)
        let recipient = approval.requesterID ?? ctoID
        postAgentMessage(
            productID: approval.productID,
            fromAgentID: bossID,
            toAgentID: recipient,
            taskID: approval.taskID,
            approvalID: approval.id,
            kind: .approvalDecided,
            subject: approved ? "审批已批准：".L() + "\(approval.title)" : "审批已驳回：".L() + "\(approval.title)",
            body: approved ? "老板已批准，请继续执行。".L() : (isSupervisorBossApproval ? "老板驳回最终交付，技术负责人会回拨返工并重新组织复审。".L() : "老板驳回该请求，请重新拆解或调整方案。".L()),
            persist: false
        )
        finalizeSupervisorBossApprovalIfNeeded(approval: approval, approved: approved)
        saveSnapshot()
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





    public func startCTOSupervisorGoal(goal: String) -> UUID? {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanGoal.isEmpty else { return nil }
        let productID = selectedProductID
        let productLabel = selectedProduct?.name ?? "当前产品"

        let engineerID = firstAgentID(for: .codeEngineer) ?? recommendedAgentID(
            forTaskTitle: "员工执行：".L() + "\(cleanGoal)",
            successCriteria: "完成工程实现并报告修改文件、验证命令和剩余风险。".L(),
            fallbackRole: .codeEngineer
        )
        let reviewerID = firstAgentID(for: .reviewer) ?? recommendedAgentID(
            forTaskTitle: "审查验收：".L() + "\(cleanGoal)",
            successCriteria: "审查产物是否满足目标，输出可交付结论。".L(),
            fallbackRole: .reviewer
        )

        let ctoTask = CompanyTask(
            productID: productID,
            title: "技术负责人拆解：".L() + "\(cleanGoal)",
            ownerID: ctoID,
            status: .running,
            successCriteria: "把目标拆解为可执行任务，并通过消息总线派发给员工。".L()
        )
        let engineerTask = CompanyTask(
            productID: productID,
            title: "员工执行：".L() + "\(cleanGoal)",
            ownerID: engineerID,
            status: engineerID == nil ? .planned : .assigned,
            successCriteria: "完成工程实现并报告修改文件、验证命令和剩余风险。".L()
        )
        let reviewerTask = CompanyTask(
            productID: productID,
            title: "审查验收：".L() + "\(cleanGoal)",
            ownerID: reviewerID,
            status: .planned,
            successCriteria: "按成功标准审查工程产物，输出是否可交付结论。".L()
        )
        let bossTask = CompanyTask(
            productID: productID,
            title: "老板审批：".L() + "\(cleanGoal)",
            ownerID: bossID,
            status: .needsApproval,
            successCriteria: "老板批准最终交付或驳回返工。".L()
        )
        tasks.insert(contentsOf: [ctoTask, engineerTask, reviewerTask, bossTask], at: 0)

        appendEvent(
            kind: .taskCreated,
            title: "技术负责人启动新目标".L(),
            detail: "\(productLabel)：\(cleanGoal)",
            agentID: ctoID
        )

        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: ctoTask.id,
            kind: .ctoGoalStarted,
            subject: "技术负责人启动新目标：".L() + "\(cleanGoal)",
            body: "技术负责人已收到老板目标，已经创建拆解、执行、审查和审批四个任务并通过消息总线派发。".L(),
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
                subject: "等待审查：".L() + "\(cleanGoal)",
                body: "工程实现完成后请按成功标准审查 ".L() + "\(cleanGoal)" + "，并给出是否可交付的结论。".L(),
                persist: false
            )
        }

        saveSnapshot()
        return ctoTask.id
    }

    public func advanceCTOSupervisorLoop() -> Bool {
        let supervisorTasks = tasks.filter { $0.productID == selectedProductID && isCTOSupervisorTask($0) }
        let goals = Set(supervisorTasks.compactMap { ctoSupervisorGoalKey(for: $0) })
        var progressed = false
        var progressedGoals: [String] = []

        for goal in goals {
            let goalTasks = supervisorTasks.filter { ctoSupervisorGoalKey(for: $0) == goal }
            guard let engineerTask = goalTasks.first(where: { $0.title.hasPrefix("员工执行：".L()) }),
                  let reviewerTask = goalTasks.first(where: { $0.title.hasPrefix("审查验收：".L()) }),
                  let bossTask = goalTasks.first(where: { $0.title.hasPrefix("老板审批：".L()) })
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
                    subject: "请审查：".L() + "\(goal)",
                    body: "工程实现已完成，请按成功标准审查并给出可交付结论。".L(),
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
                    title: "请老板审批：".L() + "\(goal)",
                    reason: "工程实现与审查均已完成，请老板做最终决策。".L(),
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
            let goalSummary = progressedGoals.isEmpty ? "当前目标".L() : progressedGoals.joined(separator: "、")
            postAgentMessage(
                productID: selectedProductID,
                fromAgentID: ctoID,
                toAgentID: bossID,
                kind: .ctoLoopProgressed,
                subject: "技术负责人调度循环已推进：".L() + "\(goalSummary)",
                body: "技术负责人已经在多员工协作链路上推进了一步。\n目标：".L() + "\(goalSummary)",
                persist: false
            )
            saveSnapshot()
        }
        return progressed
    }


    func ctoSupervisorGoalKey(for task: CompanyTask) -> String? {
        let prefixes = ["技术负责人拆解：".L(), "员工执行：".L(), "审查验收：".L(), "老板审批：".L()]
        for prefix in prefixes where task.title.hasPrefix(prefix) {
            return String(task.title.dropFirst(prefix.count))
        }
        return nil
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
        let workspaceLine = product.map { opcProductWorkspaceDisplayName($0.rootDirectory) } ?? "未设置本地工作区".L()

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
        appendEvent(kind: .artifactCreated, title: "老板报告已生成".L().L(), detail: "\(product?.name ?? "当前产品".L())" + " 的状态报告已写入老板和技术负责人对话。".L().L(), agentID: ctoID)
        saveSnapshot()
    }




    public func localizeLegacyVisibleTerminology(saveAfterChange: Bool = true) -> Bool {
        var changed = false
        for index in agents.indices where agents[index].role == .cto {
            if agents[index].displayName.contains("CTO") {
                agents[index].displayName = agents[index].displayName
                    .replacingOccurrences(of: "CTO ", with: "技术负责人".L())
                    .replacingOccurrences(of: "CTO", with: "技术负责人".L())
                changed = true
            }
            if agents[index].title.contains("CTO") {
                agents[index].title = agents[index].title
                    .replacingOccurrences(of: "CTO ", with: "技术负责人".L())
                    .replacingOccurrences(of: "CTO", with: "技术负责人".L())
                changed = true
            }
        }
        for index in tasks.indices {
            if tasks[index].title.contains("公司 App 基础".L()) {
                tasks[index].title = tasks[index].title
                    .replacingOccurrences(of: "公司 App 基础".L(), with: "公司应用基础".L())
                changed = true
            }
        }
        for index in agents.indices {
            if agents[index].displayName.contains("UI 设计师".L()) {
                agents[index].displayName = agents[index].displayName
                    .replacingOccurrences(of: "UI 设计师".L(), with: "界面设计师".L())
                changed = true
            }
            if agents[index].title.contains("UI 设计师".L()) {
                agents[index].title = agents[index].title
                    .replacingOccurrences(of: "UI 设计师".L(), with: "界面设计师".L())
                changed = true
            }
        }
        if changed && saveAfterChange {
            saveSnapshot()
        }
        return changed
    }

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
            title: "自动员工已清理".L(),
            detail: "已移除旧版本自动生成的专业员工：\(legacyAgents.map(\.displayName).joined(separator: "、"))。以后自动能力不会偷偷创建员工。".L(),
            agentID: ctoID
        )
        if saveAfterChange {
            saveSnapshot()
        }
        return true
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
        \("- 当前额外/专业员工：".L())\(extraAgents.map(\.displayName).joined(separator: "、").nilIfBlank ?? "无".L())
        \("- 自动/测试任务：".L())\(generatedTaskCount)\(" 个".L())
        \("- 队列/审批/产物/验收/记忆/通信/分支：".L())\(workQueue.count + approvals.count + artifacts.count + verifications.count + memories.count + communicationLogs.count + branchPlans.count)\(" 条".L())
        \("- 有终端日志员工：".L())\(terminalLogCount)\(" 个".L())

        \("不会删除真实项目目录里的文件；会清空 OPC 内部产品、任务、日志和测试员工状态。".L())
        """
    }

    public func resetToDefaultCompanyState() {
        createSafetyCheckpoint(reason: "恢复默认公司状态前自动检查点".L())
        let uiID = agents.first(where: { $0.role == .uiDesigner })?.id ?? UUID()
        let codeID = agents.first(where: { $0.role == .codeEngineer })?.id ?? UUID()
        let reviewID = agents.first(where: { $0.role == .reviewer })?.id ?? UUID()

        agents = [
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

        let defaultProduct = ProductWorkspace(
            name: "默认产品工作区".L(),
            shortName: "默认".L(),
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
            ChatMessage(productID: defaultProduct.id, agentID: ctoID, author: .system, text: "系统提示：OPC 公司已经恢复到默认状态。正式沟通会调用员工配置的真实模型来源。".L()),
            ChatMessage(productID: defaultProduct.id, agentID: uiID, author: .system, text: "系统提示：Gemini 界面设计师已恢复，档案、记忆和技能已写入员工工作区。".L()),
            ChatMessage(productID: defaultProduct.id, agentID: codeID, author: .system, text: "系统提示：Claude Code 工程师已恢复，档案、记忆和技能已写入员工工作区。".L()),
            ChatMessage(productID: defaultProduct.id, agentID: reviewID, author: .system, text: "系统提示：Codex 审查员已恢复，档案、记忆和技能已写入员工工作区。".L())
        ]
        events = [
            CompanyEvent(kind: .statusChanged, title: "公司已恢复默认状态".L(), detail: "已清空本地测试数据并恢复默认产品团队。".L(), agentID: ctoID)
        ]
        tasks = [
            CompanyTask(productID: defaultProduct.id, title: "定义产品架构".L(), ownerID: ctoID, status: .done, successCriteria: "完成产品规格、技术栈和角色系统。".L()),
            CompanyTask(productID: defaultProduct.id, title: "创建 2D 公司应用基础".L(), ownerID: codeID, status: .running, successCriteria: "构建原生 macOS SwiftUI/SpriteKit 外壳，并支持点击员工沟通。".L()),
            CompanyTask(productID: defaultProduct.id, title: "审查命令行调度设计".L(), ownerID: reviewID, status: .planned, successCriteria: "确认 Codex、Claude、Gemini 命令适配器安全且可扩展。".L())
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











    struct TerminalWorkspaceHealthSnapshot {
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




















    public struct CLIRecoveryAdviceEntry: Sendable, Hashable {
        public var agentID: UUID
        public var displayName: String
        public var phaseTitle: String
        public var actionTitle: String
        public var operatorHint: String?
        public var canManualRetry: Bool
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
            let hint = entry.operatorHint ?? "暂无额外建议。".L()
            let retryHint = entry.canManualRetry ? "可使用「手动重试一次」入口尝试一次。".L() : "暂不开放手动重试。".L()
            return "- ".L() + "\(entry.displayName)" + "：状态 ".L() + "\(entry.phaseTitle)" + " · 建议 ".L() + "\(entry.actionTitle)" + " · ".L() + "\(hint)" + " ".L() + "\(retryHint)"
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
                "内部自动交互循环：".L().L() + "\(rejected ? "已拒绝" : execution.finalState.phase.title)",
                "发送轮次：".L().L() + "\(execution.sentTurnCount)" + "/" + "\(execution.finalState.maxTurns)",
                "停止原因：".L().L() + "\(execution.finalState.stopReason.title)"
            ]
            if let rejectionReason {
                lines.append("拒绝原因：".L().L() + "\(rejectionReason)")
            }
            lines.append("说明：当前仅为技术负责人维护侧内部协调，不调用真实命令行、不创建作业档案、不写老板聊天。".L().L())
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
                "真实终端自动交互循环：".L().L() + "\(rejected ? "已拒绝" : state.phase.title)",
                "发送链路：".L().L() + "\(usedRealTerminal ? "真实终端席位" : "注入发送闭包")",
                "已发送轮次：".L().L() + "\(internalReport.execution.sentTurnCount)" + "/" + "\(state.maxTurns)",
                "停止原因：".L().L() + "\(state.stopReason.title)",
                "操作建议：".L().L() + "\(state.stopReason.operatorHint)"
            ]
            if usedRealTerminal, let terminalReadinessAudit {
                lines.append(terminalReadinessAudit)
            }
            if let rejectionReason {
                lines.append("拒绝原因：".L().L() + "\(rejectionReason)")
            }
            lines.append("说明：仅在技术负责人维护区显式启动；不创建命令行作业档案、不写老板聊天、不绕过交付验收。".L().L())
            return lines.joined(separator: "\n")
        }
    }




    public func terminalAutoInteractionNextInputPreviewForTesting(taskContext: String, sentTurns: Int = 0) -> String {
        let state = CLIAutoInteractionLoopState(taskContext: taskContext, maxTurns: 8, sentInputs: Array(repeating: "已发送".L().L(), count: max(sentTurns, 0)))
        return Self.terminalAutoInteractionNextInput(taskContext: taskContext, state: state)
    }

    nonisolated internal static func terminalAutoInteractionNextInput(taskContext: String, state: CLIAutoInteractionLoopState) -> String {
        let normalized = taskContext
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(normalized.prefix(140))
        let context = clipped.isEmpty ? "当前技术负责人任务".L().L() : clipped
        return "第".L().L() + "\(state.sentInputs.count + 1)" + "轮：围绕「".L().L() + "\(context)" + "」继续执行当前任务，只回复当前进展、阻塞和下一步。".L().L()
    }

    struct TerminalAutoInteractionReadinessAudit: Sendable {
        var rejectionReason: String?
        var auditLine: String
    }






    public static let terminalAutoInteractionAuditTitle = "真实终端自动循环就绪审计".L().L()
    public static let terminalAutoInteractionStopAuditTitle = "真实终端自动循环停止审计".L().L()

    /// 当前产品最近一次真实终端自动循环 preflight 审计记录；技术负责人维护视图使用。
    public var selectedProductLatestTerminalAutoLoopReadinessAudit: VerificationRecord? {
        selectedProductRecentVerifications.first { $0.title == Self.terminalAutoInteractionAuditTitle }
    }

    /// 当前产品最近一次真实终端自动循环停止审计记录（授权异常 / 忙碌 / 临时异常 / 等待超时停止时写入）。
    public var selectedProductLatestTerminalAutoLoopStopAudit: VerificationRecord? {
        selectedProductRecentVerifications.first { $0.title == Self.terminalAutoInteractionStopAuditTitle }
    }



    /// 把最近一次真实终端自动循环 preflight 审计渲染成中文摘要行，
    /// 用于架构体检和终端大厅维护视图；不暴露底层参数。

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







    public func generateHealthAudit() {
        let audit = productHealthSnapshotText()
        messages.append(ChatMessage(productID: selectedProductID, agentID: bossID, author: .system, text: audit))
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "请根据健康体检修正计划：\n\n".L() + "\(audit)"))
        appendEvent(kind: .artifactCreated, title: "产品健康体检已生成".L().L(), detail: "健康体检已写入老板和技术负责人对话。".L().L(), agentID: ctoID)
        saveSnapshot()
    }




    public func generateAcceptanceReport(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        let owner = task.ownerID.map(agentName) ?? "未分配".L()
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
            title: "验收报告：".L().L() + "\(task.title)",
            path: "opc://acceptance-reports/\(task.id.uuidString)",
            summary: "任务状态：".L().L() + "\(task.status.title)" + "；负责人：".L().L() + "\(owner)" + "。"
        )
        artifacts.insert(artifact, at: 0)
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "验收报告已生成：".L().L() + "\(task.title)",
            body: report,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationWarning,
            requesterID: ctoID,
            reviewerID: task.ownerID ?? ctoID,
            summary: "验收报告已生成，等待自动验收或老板最终确认。".L().L(),
            reportArtifactID: artifact.id
        )
        appendEvent(kind: .artifactCreated, title: "验收报告已生成".L().L(), detail: task.title, agentID: task.ownerID)
        saveSnapshot()
    }

    public func scanProjectArtifacts() {
        guard let product = selectedProduct else { return }
        let root = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: root.path) else {
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "产物扫描失败".L().L(), detail: "项目目录不存在：" + "\(root.path)"), at: 0)
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
            artifacts.insert(ArtifactRecord(productID: selectedProductID, taskID: nil, kind: candidate.1, title: candidate.0, path: url.path, summary: "项目扫描发现 ".L().L() + "\(candidate.1.title)" + "：".L() + "\(candidate.0)"), at: 0)
            inserted += 1
        }

        verifications.insert(VerificationRecord(productID: selectedProductID, status: inserted > 0 ? .passed : .warning, title: "产物扫描完成".L().L(), detail: "新增 " + "\(inserted)" + " 条产物记录。"), at: 0)
        appendEvent(kind: .artifactCreated, title: "产物扫描完成".L().L(), detail: "新增 " + "\(inserted)" + " 条产物记录。", agentID: ctoID)
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
            details.append("产品根目录不存在。".L().L())
        }
        if !pendingApprovals.isEmpty {
            status = maxSeverity(status, .warning)
            details.append("存在 ".L().L() + "\(pendingApprovals.count)" + " 个待审批请求。".L().L())
        }
        if !failedTasks.isEmpty {
            status = .failed
            details.append("存在 ".L().L() + "\(failedTasks.count)" + " 个阻塞/失败任务。".L().L())
        }
        if !missingOwners.isEmpty {
            status = maxSeverity(status, .warning)
            details.append("存在 ".L().L() + "\(missingOwners.count)" + " 个未分配任务。".L().L())
        }
        if details.isEmpty {
            details.append("任务、审批、目录基础检查通过。".L().L())
        }

        let verification = VerificationRecord(productID: selectedProductID, status: status, title: "自动验收检查".L().L(), detail: details.joined(separator: "\n"))
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
                summary: "自动验收检查：".L().L() + "\(status.title)" + "。".L() + "\(details.joined(separator: " "))",
                latestVerificationID: verification.id
            )
        }
        appendEvent(kind: status == .failed ? .risk : .artifactCreated, title: "自动验收检查完成".L().L(), detail: status.title, agentID: ctoID)
        saveSnapshot()
    }


    /// 自动状态摘要在产品记忆中保留 1 小时去重窗口的标题前缀。
    /// 只用于识别 `captureDecisionMemoryFromLatestReport` 自动写入的条目；
    /// 用户通过 `addMemory` 手工保存的同名条目不会受影响（手工保存不会以此前缀开头）。
    static let autoCapturedSummaryTitlePrefix = "自动记录：".L().L()

    /// 自动状态摘要去重窗口（秒）。同一产品、相同 detail 前 200 字、1 小时内只写入一条。
    static let autoCapturedSummaryDedupeWindow: TimeInterval = 3600

    /// 自动状态摘要去重比对使用的 detail 前缀长度。
    static let autoCapturedSummaryDedupePrefixLength = 200


    func hasRecentAutoCapturedSummary(forProduct productID: UUID, detailPrefix: String) -> Bool {
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

    /// 维护操作：清理当前选中产品中重复的自动状态摘要。
    /// - 仅作用于 kind == .summary 且 title 以 `自动记录：` 开头的记忆条目。
    /// - 按 detail 前 200 字分组，每组保留 createdAt 最新的一条，移除其它旧条目。
    /// - 不触碰其它产品、其它 kind、用户手工 addMemory 写入的记忆。
    /// - 仅当确实移除了条目时才写入维护型 VerificationRecord + 事件 + 快照；无重复时 no-op 返回 0。
    /// - Returns: 实际移除的旧记忆条数。

    /// 格式化「自动状态摘要去重预览」中文描述，供维护视图直接展示，不修改任何数据。
    public func autoCapturedSummaryDuplicatePreviewText() -> String {
        let p = previewSelectedProductAutoCapturedSummaryDuplicates()
        guard p.totalAutoSummaryCount > 0 else {
            return "自动状态摘要去重：当前产品无自动状态摘要记忆。".L().L()
        }
        if !p.hasDuplicates {
            return "自动状态摘要去重：共 ".L().L() + "\(p.totalAutoSummaryCount)" + " 条，未发现重复，无需清理。".L().L()
        }
        return "自动状态摘要去重：共 ".L().L() + "\(p.totalAutoSummaryCount)" + " 条自动摘要，发现 ".L().L() + "\(p.duplicateGroupCount)" + " 组重复，可清理 ".L().L() + "\(p.removableNoteCount)" + " 条旧摘要，每组保留最新一条。"
    }


    public func runCTOAutopilot() {
        createSafetyCheckpoint(reason: "技术负责人自动调度前检查点".L().L())
        assignExistingSpecialistsToSelectedProduct()

        if selectedProductTasks.filter({ $0.status != .done }).count < 5 {
            seedStandardTaskTemplates(goal: selectedProduct?.name ?? "当前产品".L().L())
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
                requestApproval(taskID: task.id, title: "技术负责人请求处理阻塞：".L().L() + "\(task.title)", reason: "任务处于 ".L().L() + "\(task.status.title)" + "，需要老板批准继续、驳回或重新拆解。", requesterID: ctoID)
            }
        }

        scanProjectArtifacts()
        runAutomaticVerification()
        generateHealthAudit()
        captureDecisionMemoryFromLatestReport()
        _ = advanceCTOSupervisorLoop()
        appendEvent(kind: .ctoSummary, title: "技术负责人自动调度完成".L().L(), detail: "已完成团队、任务、队列、产物、验收、记忆和协作链路推进。".L().L(), agentID: ctoID)
        saveSnapshot()
    }

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



    /// R28（角色继承期轮 28 落地候选 λ-2 引擎部分）：
    /// 一次性把所有 `productID == nil` 的 task 回填到给定 `targetProductID`。当前产品视图已经严格
    /// 只读当前产品；本 helper 负责把旧快照里的未归属任务显式迁入选定产品，避免旧任务丢失。
    ///
    /// 设计：engine vs policy 分离 —— 本 helper 只做**怎么迁移**，不做**何时迁移 / 目标产品如何选**。
    /// caller（codex / UI 触发器 / 一次性脚本）决定调用时机，本 helper 接受目标 productID 作为参数。
    ///
    /// 幂等：第二次调用对同一数据集是 no-op（所有原 nil task 已回填，不再有 nil 候选）。

    /// R27（角色继承期轮 27 落地候选 ψ 部分）：
    /// 判定一个**已 standardize 或 resolvingSymlinks 之后的** URL 是否落入 macOS 系统保留路径。
    /// 用途：scanLinkedLocalFiles 拒绝把产品 root 指向系统目录索引（避免误把 /usr/bin 文件写入 artifact 列表）。
    /// 这是**安全护栏**不是权限模型——OS 已经决定用户能否读，本判定只防止"使用错误"污染产物列表。
    /// 黑名单覆盖（前缀匹配，需带 trailing slash 避免 `/usrFoo` 误命中 `/usr`）：
    /// `/System`、`/private/var/db`、`/private/etc`、`/usr`、`/bin`、`/sbin`。
    /// 注意 `/usr` 在 macOS 含 `/usr/local`（用户可写），但本判定仍拒绝整个 `/usr` —
    /// `/usr/local` 也不应作为产品根目录索引（会误命中 brew/系统包路径）。
    static func isSystemReservedPath(_ url: URL) -> Bool {
        let path = url.path
        let reserved: [String] = ["/System", "/private/var/db", "/private/etc", "/usr", "/bin", "/sbin"]
        for prefix in reserved {
            if path == prefix { return true }
            if path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }



static func isPath(_ path: String, insideAnyOf roots: Set<String>) -> Bool {
        roots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
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
            jobArchive = "未选择产品，暂无命令行作业档案路径".L().L()
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


    func artifactKind(for url: URL) -> ArtifactKind {
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






    public func visibleBackendSummary(for agent: CompanyAgent) -> String {
        let model = agent.backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "默认模型".L() : agent.backend.model
        switch agent.backend.type {
        case .subscriptionCLI:
            let toolName = visibleCommandToolName(for: agent)
            return "\(agent.backend.type.title)" + " · 工具 ".L() + "\(toolName)" + " · ".L() + "\(model)" + " · 思考强度 ".L() + "\(agent.backend.reasoningEffort.title)"
        case .api:
            return "\(agent.backend.type.title)" + " · ".L() + "\(model)" + " · 思考强度 ".L() + "\(agent.backend.reasoningEffort.title)"
        case .local:
            return "\(agent.backend.type.title)" + " · ".L() + "本地占位".L()
        }
    }


    func visibleExecutionSummary(for agent: CompanyAgent, taskPrompt: String) -> String {
        let task = taskPrompt.replacingOccurrences(of: "\n", with: " ").prefix(60)
        let protocolLine = CLIAgentCommandBuilder.interactionSummary(for: agent).map { "\n长期会话：".L() + "\($0)" } ?? ""
        return """
        \("运行方式：".L())\(visibleBackendSummary(for: agent))
        \("任务注入：角色档案、记忆、技能和产品工作区会在运行时自动注入。".L())
        \("任务摘要：".L())\(task)\(protocolLine)
        """
    }

    func terminalCommandSummary(title: String, agent: CompanyAgent, executionDirectory: URL, prompt: String, job: CLIJobDirectory? = nil) -> String {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "使用默认任务。".L().L() : String(prompt.replacingOccurrences(of: "\n", with: " ").prefix(120))
        let jobLine = job == nil ? "" : "OPC 作业档案：已创建\n".L().L()
        return """
        \(jobLine)[\(title)]
        \("执行位置：".L())\(executionDirectory.standardizedFileURL.path == cliWorkingDirectoryURL().standardizedFileURL.path ? "主工作目录".L() : "独立执行区".L())
        \("运行方式：".L())\(visibleBackendSummary(for: agent))
        \("任务摘要：".L())\(task)

        """
    }


    /// 终端大厅员工卡片常驻可见的「运行前预检」摘要：仅展示中文抽象标签，
    /// 不包含 `/Users/...` 等绝对路径、`--skip-git-repo-check` / `--permission-mode` /
    /// `model_reasoning_effort` 等底层 CLI 参数、提示词原文、隔离策略字面量。
    /// 如需完整审计文本（含路径、提示词、运行摘要），仍由 `cliPreflightText(for:prompt:)`
    /// 提供，并通过显式的「预检」按钮 / `recordCLIPreflight` 写入终端日志归档。









    public static let terminalAgentCardLogIdleHeight: CGFloat = 80
    public static let terminalAgentCardLogActiveHeight: CGFloat = 180

    public var terminalAgentCardLogIdleHeight: CGFloat { Self.terminalAgentCardLogIdleHeight }
    public var terminalAgentCardLogActiveHeight: CGFloat { Self.terminalAgentCardLogActiveHeight }














    /// 仅压缩可见日志里连续重复的 OPC 元数据块，不改动 terminalLogs 原始审计流。
    func collapseConsecutiveDuplicateOPCBlocks(_ log: String) -> String {
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

        let warmupHeading = "[OPC 会话预热]".L()
        let warmupHeadings: Set<String> = ["[OPC 会话预热]", "[OPC Session Warmup]", warmupHeading]
        let warmupBlocks = blocks.filter { $0.isOPC && warmupHeadings.contains($0.headingLabel) }
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
                    output.append("（另有 ".L() + "\(warmupBlocks.count - 1)" + " 条历史「OPC 会话预热」记录，完整记录保留在维护档案。）".L())
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
                output.append("（以上相同「".L() + "\(quotedTitle)" + "」记录连续出现 ".L() + "\(run)" + " 次，已合并显示）".L())
            }
            i += run
        }

        return output.joined(separator: "\n")
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
        \("命令行任务发车台计划：".L())\(issueLines.isEmpty ? "可发车".L() : "暂缓发车".L())
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
        \("团队负责人：".L())\(teamLeadAgentIDForSelectedProduct().map(agentName) ?? "未设置".L())
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
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行任务发车计划".L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .commandPlanned, title: "命令行任务发车计划已生成".L(), detail: status.title, agentID: ctoID)
        saveSnapshot()
    }

    public func runCLILaunchPlan(prompt: String) {
        let issues = cliToolchainIssueLines()
        recordCLILaunchPlan(prompt: prompt)
        guard issues.isEmpty else {
            appendEvent(kind: .risk, title: "命令行发车被阻止".L(), detail: issues.joined(separator: "；"), agentID: ctoID)
            saveSnapshot()
            return
        }

        createSafetyCheckpoint(reason: "命令行任务发车前自动检查点".L())
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPrompt = cleanPrompt.isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : cleanPrompt
        for agent in executableAgents where !isRunning(agentID: agent.id) {
            runAgent(agentID: agent.id, prompt: taskPrompt)
        }
    }


    public func teamOperatingSummaryText() -> String {
        guard let product = selectedProduct else { return "未选择产品。".L().L() }
        let leadID = teamLeadAgentIDForSelectedProduct()
        let leadName = leadID.map(agentName) ?? "未设置".L().L()
        let memberLines = selectedProductAgents.map { agent in
            let taskCount = selectedProductTasks.filter { $0.ownerID == agent.id && $0.status != .done && $0.status != .canceled }.count
            let queueCount = selectedProductWorkQueue.filter { $0.agentID == agent.id }.count
            return "- " + "\(agent.displayName)" + "：".L() + "\(agent.role.title)" + "，未完成任务 " + "\(taskCount)" + "，队列 ".L().L() + "\(queueCount)" + "\(agent.id == leadID ? "，团队负责人" : "")"
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
        prewarmSelectedProductAgentSessions(reason: "应用启动后预热当前产品团队".L())
    }


    public func runtimeSession(for agentID: UUID) -> AgentRuntimeSession? {
        runtimeSessions[agentID]
    }



    public func employeeHandoffAuditText(staleAfter seconds: TimeInterval = 180) -> String {
        let summary = employeeHandoffAuditSummary(staleAfter: seconds)
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let header = """
        \("员工交接待确认巡检：".L())\(summary.passed ? "通过".L() : (summary.staleCount > 0 ? "存在超时" : "需关注"))
        \("产品：".L())\(productLabel)
        \("总员工交接：".L())\(summary.totalCount)
        \("待确认：".L())\(summary.pendingCount)\(" · 已确认：".L())\(summary.acknowledgedCount)\(" · 超时待确认：".L())\(summary.staleCount)
        \("阈值：".L())\(Int(max(seconds, 60)))\(" 秒".L())
        """
        let body = summary.lines.isEmpty
            ? "- 当前产品没有员工交接消息。".L()
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("交接明细：".L())
        \(body)

        \("说明：".L())
        \("本次只读巡检，仅统计当前产品的员工交接消息，不会清理运行员工列表、不会修改交接状态、不会启动模型任务，也不会写入作业档案或新增员工协作消息。如需把待确认交接标记为已确认，请由对应员工在「我的协作收件箱」点击「标记我的消息已读」。".L())
        """
    }


    struct EmployeeHandoffAuditSummary {
        var totalCount = 0
        var pendingCount = 0
        var acknowledgedCount = 0
        var staleCount = 0
        var lines: [String] = []
        var passed: Bool { staleCount == 0 && pendingCount == 0 }
    }

    func employeeHandoffAuditSummary(staleAfter seconds: TimeInterval) -> EmployeeHandoffAuditSummary {
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
            let toName = envelope.toAgentID.map(agentName) ?? "未指定".L().L()
            let elapsed = Int(now.timeIntervalSince(envelope.createdAt))
            switch envelope.status {
            case .pending:
                summary.pendingCount += 1
                let isStale = TimeInterval(elapsed) >= threshold
                if isStale {
                    summary.staleCount += 1
                    summary.lines.append("- 超时：".L().L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)" + "（" + "\(elapsed)" + " 秒未确认）")
                } else {
                    summary.lines.append("- 待确认：".L().L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)" + "（" + "\(elapsed)" + " 秒）".L().L())
                }
            case .acknowledged:
                summary.acknowledgedCount += 1
                summary.lines.append("- 已确认：".L().L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)")
            case .failed:
                summary.lines.append("- 失败：".L().L() + "\(fromName)" + " → " + "\(toName)" + "：" + "\(envelope.subject)")
            }
        }
        return summary
    }



    struct CLIJobArchiveAuditSummary {
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

    struct CLIJobArchiveRecord {
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



    @discardableResult

    func cliJobStateIsRunning(_ state: String) -> Bool {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "running" || normalized == "运行中".L()
    }

    func cliJobStateDisplayName(_ state: String) -> String {
        switch state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running", "运行中".L(): "运行中".L()
        case "completed", "done", "完成".L(), "已完成".L(): "已完成".L()
        case "failed", "失败".L(): "失败".L()
        case "interrupted", "中断".L(), "已中断".L(): "已中断".L()
        default: "未知状态".L()
        }
    }

    func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    func uuidValue(in dictionary: [String: Any], keys: [String]) -> UUID? {
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
            ? "- 当前产品没有可执行员工。".L().L()
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("员工运行会话明细：".L())
        \(body)

        \("说明：".L())
        \("本次只读巡检，不会清理正在运行的员工列表、不会改员工状态、不会启动模型任务，也不会写入作业档案或员工协作消息。需要恢复异常占用请使用「恢复异常占用员工会话」按钮，需要重开会话请用员工档案里的会话操作。".L())
        """
    }






    struct RuntimeSessionHealthSummary {
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

    func runtimeSessionHealthAuditSummary(staleAfter seconds: TimeInterval) -> RuntimeSessionHealthSummary {
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
                    notes.append("命令为空".L())
                } else if AgentProcessRunner.resolvedExecutablePath(for: trimmedCommand) == nil {
                    summary.commandMissingCount += 1
                    notes.append("命令不可解析：".L() + "\(trimmedCommand)")
                }
            case .api:
                if agent.backend.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口地址未配置".L())
                }
                if agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口密钥未配置".L())
                }
                if agent.backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summary.commandMissingCount += 1
                    notes.append("接口模型未配置".L())
                }
            case .local:
                notes.append("本地占位".L())
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
                    notes.append("产品漂移：会话属于其他产品".L())
                }
                if session.backendSignature != expectedSignature {
                    summary.backendDriftCount += 1
                    notes.append("来源漂移：员工档案和当前会话的来源配置不一致".L())
                }
                if session.capability != expectedCapability {
                    summary.backendDriftCount += 1
                    notes.append("能力漂移：会话能力 ".L() + "\(session.capability.title)" + " ≠ 当前 ".L() + "\(expectedCapability.title)")
                }
                summary.totalFailureCount += session.failureCount
                if session.state == .failed {
                    summary.failedSessionCount += 1
                    notes.append("最近一次会话失败".L())
                }
                if !session.lastError.isEmpty {
                    notes.append("最近错误：".L() + "\(session.lastError.prefix(80))")
                }
                if session.cliInteractionPhase == .authenticationBlocked {
                    summary.authenticationBlockedCount += 1
                    let hint = session.cliInteractionOperatorHint ?? CLIInteractionRecoveryAction.checkAuthentication.operatorHint ?? "请确认登录授权后再重新发起任务。".L()
                    notes.append("授权异常：".L() + "\(hint)")
                }
                if session.state == .busy, let lastUsedAt = session.lastUsedAt {
                    let idle = now.timeIntervalSince(lastUsedAt)
                    if idle >= threshold {
                        summary.staleBusyCount += 1
                        notes.append("运行占用已持续 ".L() + "\(Int(idle))" + " 秒，超过阈值 ".L() + "\(Int(threshold))" + "（提示，本次不恢复）".L())
                    }
                }
            } else {
                summary.missingSessionCount += 1
                stateLabel = "无会话"
                capabilityLabel = "—"
                backendLabel = "未检查"
                notes.append("缺少运行会话，员工档案需先预热".L())
            }

            let noteSuffix = notes.isEmpty ? "正常".L() : notes.joined(separator: "；")
            summary.lines.append(
                "- ".L() + "\(agent.displayName)" + "（".L() + "\(agent.role.title)" + "）：状态 ".L() + "\(stateLabel)" + " · 能力 ".L() + "\(capabilityLabel)" + " · 运行来源 ".L() + "\(backendLabel)" + " · ".L() + "\(noteSuffix)"
            )
        }

        return summary
    }


    public func isRunning(agentID: UUID) -> Bool {
        runningAgentIDs.contains(agentID)
    }

    public func clearTerminalLog(for agentID: UUID) {
        setTerminalLog("", for: agentID)
        appendEvent(kind: .statusChanged, title: "终端日志已清空".L(), detail: "\(agentName(agentID))" + " 的终端日志已清空。".L(), agentID: agentID)
        saveSnapshot()
    }

    func newRuntimeSession(for agent: CompanyAgent, state: AgentRuntimeState = .cold) -> AgentRuntimeSession {
        AgentRuntimeSession(
            agentID: agent.id,
            productID: selectedProductID,
            state: agent.backend.type == .local ? .unavailable : state,
            capability: CLIAgentCommandBuilder.runtimeCapability(for: agent),
            backendSignature: CLIAgentCommandBuilder.backendSignature(for: agent)
        )
    }

    func upsertRuntimeSession(for agent: CompanyAgent, state: AgentRuntimeState? = nil) {
        let signature = CLIAgentCommandBuilder.backendSignature(for: agent)
        let capability = CLIAgentCommandBuilder.runtimeCapability(for: agent)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent, state: state ?? .cold)
        if session.backendSignature != signature || session.capability != capability || session.productID != selectedProductID {
            let retainedCLIConversations = session.cliSessionsByProduct
            session = newRuntimeSession(for: agent, state: .cold)
            session.cliSessionsByProduct = retainedCLIConversations
            session.lastRestartReason = "产品、来源、模型或思考强度已变化，需要重新预热。".L()
        } else if let state {
            session.state = state
        }
        session.productID = selectedProductID
        session.capability = capability
        session.backendSignature = signature
        runtimeSessions[agent.id] = session
    }

    func markRuntimeBusy(for agent: CompanyAgent) {
        upsertRuntimeSession(for: agent)
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.state = .busy
        session.lastUsedAt = Date()
        session.lastError = ""
        runtimeSessions[agent.id] = session
    }

    func markRuntimeFinished(for agent: CompanyAgent, result: CommandExecutionResult, context: String) {
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
            session.lastError = "超时：".L() + "\(context)"
            runtimeSessions[agent.id] = session
            restartAgentSessionIfNeeded(agent: agent, reason: "上次 ".L() + "\(context)" + " 超时，重开会话。".L())
            return
        } else {
            session.state = .failed
            session.failureCount += 1
            session.lastError = displayableChatError(from: result.combinedOutput)
            runtimeSessions[agent.id] = session
            if shouldAutomaticallyRestartSession(after: result, agent: agent) {
                restartAgentSessionIfNeeded(agent: agent, reason: "上次 ".L() + "\(context)" + " 异常退出，重开会话。".L())
            }
            return
        }
        runtimeSessions[agent.id] = session
    }


    func shouldAutomaticallyRestartSession(after result: CommandExecutionResult, agent: CompanyAgent) -> Bool {
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









    public func sendTeamLeadReportThroughGateway() {
        ensureCommunicationGatewayPlan()
        guard let product = selectedProduct else { return }
        let leadID = teamLeadAgentIDForSelectedProduct()
        let leadName = leadID.map(agentName) ?? "团队负责人".L()
        let enabledChannels = selectedProductCommunicationChannels.filter { $0.isEnabled && $0.reportsEnabled && $0.kind.supportsOutboundReport }
        let readyChannels = enabledChannels.filter(communicationChannelCanDispatch)
        let blockedChannels = enabledChannels.filter { !communicationChannelCanDispatch($0) }
        let status: CommunicationLogStatus = readyChannels.isEmpty || !blockedChannels.isEmpty ? .queued : .sent
        let targetNames: String
        if enabledChannels.isEmpty {
            targetNames = "暂无已启用通道，先进入本地队列".L()
        } else if readyChannels.isEmpty {
            targetNames = "已启用通道缺少接口地址或聊天标识，暂存待发送".L()
        } else if blockedChannels.isEmpty {
            targetNames = readyChannels.map(\.name).joined(separator: "、")
        } else {
            targetNames = "\(readyChannels.map(\.name).joined(separator: "、"))；".L() + "\(blockedChannels.count)" + " 个通道缺少配置".L()
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
        communicationLogs.insert(CommunicationLogEntry(channelID: readyChannels.first?.id ?? enabledChannels.first?.id, productID: selectedProductID, agentID: leadID, direction: .outbound, status: status, title: "团队负责人手机汇报".L().L(), body: body), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID ?? ctoID, author: .system, text: "OPC 通信网关已生成团队负责人汇报：\n".L() + "\(body)"))
        appendEvent(kind: .ctoSummary, title: "通信网关汇报".L().L(), detail: "已生成 " + "\(product.name)" + " 的团队负责人手机汇报。", agentID: leadID)
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
        let leadName = leadID.map(agentName) ?? "团队负责人".L().L()
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
                title: "团队负责人手机汇报发送".L(),
                body: "没有配置就绪的外发通道，已保留为待发送。".L()
            ), at: 0)
            appendEvent(kind: .risk, title: "通信网关发送待配置".L(), detail: "没有配置就绪的外发通道。".L(), agentID: leadID)
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
                lines.append("- 已发送：\(channel.name)\(result.httpStatus.map { "（HTTP \($0)）" } ?? "（本地通道）")，尝试 ".L() + "\(result.attempts)" + " 次".L())
            } else {
                anyFailed = true
                lines.append("- 失败：".L() + "\(channel.name)" + "，尝试 ".L() + "\(result.attempts)" + " 次，".L() + "\(result.error ?? "未知错误".L())")
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
            title: "团队负责人手机汇报发送".L().L(),
            body: report
        ), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID ?? ctoID, author: .system, text: report))
        appendEvent(kind: anyFailed ? .risk : .ctoSummary, title: "通信网关发送完成".L().L(), detail: anyFailed ? "部分通道发送失败。".L().L() : "就绪通道已发送。".L().L(), agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
    }



    public func ingestRemoteCommand(_ text: String, channelID: UUID? = nil, source: InboundCommandSource = .localCommandConsole) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        ensureCommunicationGatewayPlan()
        guard let channel = inboundCommandChannel(channelID: channelID) else {
            rejectInboundCommand(channelID: channelID, reason: "没有可接收手机指令的已启用通道。指令内容已拒绝进入任务队列。".L())
            return false
        }
        guard channel.kind == .localOnly else {
            rejectInboundCommand(channelID: channel.id, reason: "\(channel.name)" + " 是外部入站通道，必须走签名校验入口。".L())
            return false
        }
        return recordAcceptedInboundCommand(clean, channel: channel, source: source)
    }

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
            rejectInboundCommand(channelID: channelID, reason: "没有可接收手机指令的已启用通道。指令内容已拒绝进入任务队列。".L())
            return false
        }
        guard channel.kind != .localOnly else {
            rejectInboundCommand(channelID: channel.id, reason: "本地指挥台不接受外部签名回调，请使用本地模拟入口。".L())
            return false
        }
        guard communicationChannelCanDispatch(channel) else {
            rejectInboundCommand(channelID: channel.id, reason: "\(channel.name)" + " 缺少必要配置，暂不能接收外部指令。".L())
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
            rejectInboundCommand(channelID: channel.id, reason: "外部指令签名校验失败：".L() + "\(inboundVerificationTitle(verification))" + "。".L())
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
                rejectInboundCommand(channelID: channel.id, reason: "外部指令动作被拒绝：外部审批动作暂未开放。".L())
                return false
            }
        case .invalidJSON, .missingField, .unsupportedAction, .emptyInstruction, .approvalActionDisabled:
            rejectInboundCommand(channelID: channel.id, reason: "外部指令动作被拒绝：".L() + "\(CommunicationInboundCommandParser.parseFailureTitle(parsedCommand))" + "。".L())
            return false
        }
    }

    func recordAcceptedInboundCommand(_ clean: String, channel: CommunicationChannelConfig, source: InboundCommandSource) -> Bool {
        let leadID = teamLeadAgentIDForSelectedProduct() ?? ctoID
        let limited = String(clean.prefix(2_000))
        let logBody = """
        \("来源：".L())\(source.title)
        \("内容：".L())\(limited)
        """
        communicationLogs.insert(CommunicationLogEntry(channelID: channel.id, productID: selectedProductID, agentID: leadID, direction: .inbound, status: .received, title: "手机端老板指令".L().L(), body: logBody), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID, author: .user, text: "【手机端指令】".L().L() + "\(limited)"))
        tasks.insert(CompanyTask(productID: selectedProductID, title: "手机指令：".L().L() + "\(String(limited.prefix(24)))", ownerID: leadID, status: .assigned, successCriteria: "团队负责人理解手机端指令，拆解下一步并向老板汇报；涉及高风险操作时必须回到老板审批。".L().L()), at: 0)
        setStatus(.thinking, for: leadID)
        appendEvent(kind: .message, title: "收到手机端指令".L().L(), detail: limited, agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
        return true
    }

    func recordInboundStatusQuery(channel: CommunicationChannelConfig) -> Bool {
        let leadID = teamLeadAgentIDForSelectedProduct() ?? ctoID
        let productName = selectedProduct?.name ?? "当前产品".L().L()
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
        communicationLogs.insert(CommunicationLogEntry(channelID: channel.id, productID: selectedProductID, agentID: leadID, direction: .inbound, status: .received, title: "外部状态查询".L(), body: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: leadID, author: .system, text: report))
        appendEvent(kind: .message, title: "收到外部状态查询".L(), detail: "\(channel.name)" + " 查询了 ".L() + "\(productName)" + " 的状态。".L(), agentID: leadID)
        trimCommunicationLogs()
        saveSnapshot()
        return true
    }

    func rejectInboundCommand(channelID: UUID?, reason: String) {
        communicationLogs.insert(CommunicationLogEntry(
            channelID: channelID,
            productID: selectedProductID,
            agentID: teamLeadAgentIDForSelectedProduct() ?? ctoID,
            direction: .inbound,
            status: .failed,
            title: "手机端指令被拒绝".L(),
            body: reason
        ), at: 0)
        appendEvent(kind: .risk, title: "手机端指令被拒绝".L(), detail: reason, agentID: teamLeadAgentIDForSelectedProduct() ?? ctoID)
        trimCommunicationLogs()
        saveSnapshot()
    }

    func inboundVerificationTitle(_ result: CommunicationInboundVerificationResult) -> String {
        switch result {
        case .accepted: "已通过".L()
        case .missingField(let field): "缺少 ".L() + "\(field)"
        case .staleTimestamp: "时间戳过期".L()
        case .replayedNonce: "重复 nonce".L()
        case .invalidSignature: "签名无效".L()
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
    func recordPersistenceFailure(_ error: Error) {
        let title = "持久化失败".L()
        if let latest = events.first, latest.kind == .risk, latest.title == title { return }
        let detail = "company-state.json 写入失败：".L() + "\(error.localizedDescription)" + "。后续操作仍在内存中，应用重启会丢失最近变更。".L()
        appendEvent(kind: .risk, title: title, detail: detail, agentID: nil)
    }



    func canUseLiveChatBackend(_ agent: CompanyAgent) -> Bool {
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

    func localFallbackReply(for agentID: UUID) -> String {
        let name = agentName(agentID)
        return "本地降级提示：当前没有调用 ".L() + "\(name)" + " 的真实模型来源。请确认该员工使用订阅制命令行或接口模型，并且已经加入当前产品团队；正式聊天会直接显示模型返回内容。".L()
    }

    func chatCommand(for agent: CompanyAgent, prompt: String) -> [String] {
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

    func startLiveChatReply(agent: CompanyAgent, userText: String) {
        let productID = selectedProductID
        guard !isRunning(agentID: agent.id) else {
            messages.append(ChatMessage(productID: productID, agentID: agent.id, author: .system, text: "\(agent.displayName)" + " 当前正在执行任务，等这次运行结束后再发起新对话。".L()))
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
        appendTerminalLog("\n" + terminalCommandSummary(title: "OPC 聊天".L(), agent: agent, executionDirectory: executionDirectory, prompt: userText), for: agent.id, productID: productID)
        appendAgentSession(agentID: agent.id, kind: .command, actor: "聊天".L(), text: "聊天运行方式：".L() + "\(visibleBackendSummary(for: agent))")
        runningAgentIDs.insert(agent.id)
        setStatus(.typing, for: agent.id)
        markRuntimeBusy(for: agent)
        let streamingMessageID = UUID()
        upsertChatMessage(id: streamingMessageID, productID: productID, agentID: agent.id, author: .agent, text: "\(agent.displayName)" + " 正在回复...".L())

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
                reply = raw.isEmpty ? "模型没有返回内容。请检查该员工的命令行或接口配置。".L() : trimmedChatReply(raw)
                author = raw.isEmpty ? .system : .agent
            } else {
                reply = displayableChatError(from: result.combinedOutput)
                author = .system
            }
            upsertChatMessage(id: streamingMessageID, productID: productID, agentID: agent.id, author: author, text: reply)
            appendAgentSession(agentID: agent.id, kind: .reply, actor: result.exitCode == 0 ? agent.displayName : "system", text: reply)
            appendTerminalLog("\n[聊天退出码 ".L() + "\(result.exitCode)" + "]\n".L(), for: agent.id, productID: productID)
            setStatus(result.exitCode == 0 ? (agent.id == ctoID ? .thinking : .done) : .failed, for: agent.id)

            if agent.id != ctoID {
                let summary = "老板直接和 ".L() + "\(agent.displayName)" + " 沟通：".L() + "\(userText)" + "。员工模型回复：".L() + "\(String(reply.prefix(600)))"
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：".L() + "\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步".L(), detail: summary, agentID: ctoID)
            }

            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "聊天".L())
            saveSnapshot()
        }
    }

    func startAPIChatReply(agent: CompanyAgent, prompt: String, userText: String) {
        let productID = selectedProductID
        appendTerminalLog(apiChatTerminalLogPrelude(for: agent), for: agent.id, productID: productID)
        appendAgentSession(agentID: agent.id, kind: .command, actor: "接口聊天".L(), text: apiChatSessionLogPrelude(for: agent))
        runningAgentIDs.insert(agent.id)
        setStatus(.typing, for: agent.id)
        markRuntimeBusy(for: agent)

        Task { @MainActor in
            let result = await AgentAPIChatRunner.run(agent: agent, prompt: prompt)
            let raw = displayableChatReply(from: result.combinedOutput)
            let reply = result.exitCode == 0
                ? (raw.isEmpty ? "接口没有返回内容。请检查接口地址、密钥、模型名和网络连接。".L() : trimmedChatReply(raw))
                : displayableChatError(from: result.combinedOutput)
            let author: MessageAuthor = result.exitCode == 0 && !raw.isEmpty ? .agent : .system
            messages.append(ChatMessage(productID: productID, agentID: agent.id, author: author, text: reply))
            appendAgentSession(agentID: agent.id, kind: .reply, actor: result.exitCode == 0 ? agent.displayName : "system", text: reply)
            appendTerminalLog("\n[接口聊天退出码 ".L() + "\(result.exitCode)" + "]\n".L(), for: agent.id, productID: productID)
            setStatus(result.exitCode == 0 ? (agent.id == ctoID ? .thinking : .done) : .failed, for: agent.id)

            if agent.id != ctoID {
                let summary = "老板直接和 ".L() + "\(agent.displayName)" + " 沟通：".L() + "\(userText)" + "。员工模型回复：".L() + "\(String(reply.prefix(600)))"
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：".L() + "\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步".L(), detail: summary, agentID: ctoID)
            }

            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "接口聊天".L())
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
        "接口聊天请求已交给员工档案中配置的接口模型；连接信息保留在受控配置中。".L()
    }


    public func chatReplyPreviewForTesting(_ output: String) -> String {
        displayableChatReply(from: output)
    }

    public func chatCommandPreviewForTesting(agentID: UUID, userText: String) -> [String] {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return [] }
        return chatCommand(for: agent, prompt: agentChatPrompt(for: agent, userText: userText))
    }



    func conversationalStyleGuide(for agent: CompanyAgent) -> String {
        switch agent.role {
        case .cto:
            "你是老板身边的技术负责人，语气要像能扛事的合伙人，不要像说明书。".L().L()
        case .uiDesigner:
            "你是视觉设计同事，语气可以更轻快一点，但要给出清楚的设计判断。".L().L()
        case .codeEngineer:
            "你是工程同事，语气直接、务实，说明下一步会看哪里或改哪里。".L().L()
        case .reviewer:
            "你是审查同事，语气冷静，优先把风险和判断说清楚。".L().L()
        case .tester:
            "你是测试同事，语气细致，优先说明验证方法。".L().L()
        case .researcher:
            "你是研究同事，语气清楚，说明会查什么和如何避免编造。".L().L()
        case .productArchitect:
            "你是产品架构同事，语气有结构，但不要列职责清单。".L().L()
        case .boss:
            "你是老板本人，不要冒充员工。".L().L()
        case .custom:
            "按你的角色自然回复，不要念配置。".L().L()
        }
    }

    func conversationalWorkSummary(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
        switch agent.role {
        case .cto:
            return "把老板的目标拆成清楚的任务，安排合适的人推进，并把风险和结果讲明白".L().L()
        case .uiDesigner:
            return "把产品想法转成界面结构、视觉方向、交互细节和动效状态".L().L()
        case .codeEngineer:
            return "在明确范围内改代码、修问题、跑验证，并把改动结果说清楚".L().L()
        case .reviewer:
            return "按成功标准检查产物，优先指出问题、风险和能不能交付".L().L()
        case .tester:
            return "把任务转成可重复验证步骤，发现失败场景并记录结果".L().L()
        case .researcher:
            return "查资料、看竞品和行业信息，把可靠结论整理出来".L().L()
        case .productArchitect:
            return "梳理需求结构、模块边界、产品约束和成功标准".L().L()
        case .boss:
            return "保存老板目标、偏好和关键决策".L().L()
        case .custom:
            let mission = profile.mission
                .replacingOccurrences(of: "作为".L().L(), with: "")
                .replacingOccurrences(of: "负责".L().L(), with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return mission.isEmpty ? "按配置的角色完成工作并同步进展".L().L() : mission
        }
    }

    func repairedChatResultIfNeeded(_ result: CommandExecutionResult, agent: CompanyAgent, userText: String) async -> CommandExecutionResult {
        guard result.exitCode == 0 else { return result }
        let raw = displayableChatReply(from: result.combinedOutput)
        guard needsConversationalRepair(raw) else { return result }

        let productID = selectedProductID
        let repairPrompt = agentChatRepairPrompt(agent: agent, userText: userText, draft: raw)
        appendTerminalLog("\n[OPC 聊天修正]\n".L().L(), for: agent.id, productID: productID)

        let repaired: CommandExecutionResult
        if agent.backend.type == .api {
            repaired = await AgentAPIChatRunner.run(agent: agent, prompt: repairPrompt)
        } else {
            let command = chatCommand(for: agent, prompt: repairPrompt)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            appendTerminalLog(terminalCommandSummary(title: "OPC 聊天修正".L().L(), agent: agent, executionDirectory: executionDirectory, prompt: userText), for: agent.id, productID: productID)
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
        let blocked = "模型返回仍然像角色档案或流程背诵，OPC 已拦截这次员工回复。请重新发送一句更具体的问题，或检查该员工模型配置。".L().L()
        return CommandExecutionResult(exitCode: 1, standardOutput: "", standardError: blocked)
    }


    func needsConversationalRepair(_ text: String) -> Bool {
        let markers = [
            "我的角色档案".L(),
            "角色档案".L(),
            "作为总技术负责人".L(),
            "作为视觉产品设计师".L(),
            "作为高级 macOS 工程师".L(),
            "作为风险与验收审查员".L(),
            "我的职责".L(),
            "我的档案".L(),
            "我会结合记忆".L(),
            "工作流是".L(),
            "流程是老板".L(),
            "老板 -> CTO".L(),
            "老板->CTO".L(),
            "CTO -> 员工".L()
        ]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    func displayableChatReply(from output: String) -> String {
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
            "[OPC 聊天]".L(),
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

    func displayableChatError(from output: String) -> String {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return "模型调用失败，但没有返回错误详情。请查看该员工的终端日志。".L()
        }
        let lines = clean.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let timeout = lines.last(where: { $0.contains("命令超时".L()) }) {
            return timeout
        }
        if let error = lines.last(where: { $0.hasPrefix("ERROR:") || $0.contains("unexpected status") || $0.contains("requires a newer version") }) {
            return error
        }
        return "模型调用失败。请打开该员工的终端日志查看详情。".L()
    }

    func trimmedChatReply(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 4000 { return clean }
        return String(clean.suffix(4000))
    }


    func setStatus(_ status: AgentStatus, for agentID: UUID) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        agents[index].status = status
        appendEvent(kind: .statusChanged, title: "\(agents[index].displayName)：\(status.title)", detail: "状态已变更为 ".L() + "\(status.title)" + "。".L(), agentID: agentID)
    }

    func setOptionalStatus(_ status: AgentStatus, for agentID: UUID?) {
        guard let agentID else { return }
        setStatus(status, for: agentID)
    }

    func appendEvent(productID: UUID? = nil, kind: CompanyEventKind, title: String, detail: String, agentID: UUID?) {
        events.insert(CompanyEvent(productID: productID ?? selectedProductID, kind: kind, title: title, detail: detail, agentID: agentID), at: 0)
        if events.count > 200 {
            events.removeLast(events.count - 200)
        }
    }


    func requiresIsolatedCLIExecution(_ agent: CompanyAgent) -> Bool {
        agent.permissions.contains(.editFiles) || [.codeEngineer, .tester].contains(agent.role)
    }

    func cliIsolationSourceURL(for agent: CompanyAgent) -> URL {
        cliWorktreeIsolationURL(for: agent).appendingPathComponent("source", isDirectory: true)
    }


    func cliExecutionIsolationNote(for agent: CompanyAgent) -> String {
        guard requiresIsolatedCLIExecution(agent) else {
            return "无需隔离：只读或协调型员工使用主工作目录。".L()
        }
        let workingDirectory = cliWorkingDirectoryURL()
        let isolationDirectory = cliIsolationSourceURL(for: agent)
        if cliIsolationDirectoryIsRunnable(isolationDirectory, sourceRoot: workingDirectory) {
            return "已启用隔离执行目录。".L()
        }
        if FileManager.default.fileExists(atPath: cliWorktreeIsolationURL(for: agent).appendingPathComponent("WORKTREE.md").path) {
            return "隔离目录已登记但还没有生成源码执行区，真实运行暂用主工作目录。".L()
        }
        return "隔离目录尚未创建，真实运行暂用主工作目录。".L()
    }

    struct CLIJobDirectory {
        var id: String
        var directory: URL
        var transcriptURL: URL
        var statusURL: URL
    }



    func cliJobStatusJSON(jobID: String, agent: CompanyAgent, state: String, exitCode: Int32?, executionDirectory: URL) -> String {
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

    func jsonEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }







    func runLocalProcess(executable: String, arguments: [String], workingDirectory: URL) -> (exitCode: Int32, output: String) {
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

    struct PersistentTerminalTarget {
        var agentID: UUID
        var tmuxPath: String
        var sessionName: String
        var windowName: String
    }

    struct PersistentTerminalSessionKey: Hashable, Sendable {
        var productID: UUID
        var agentID: UUID
        var tmuxPath: String
        var sessionName: String
        var windowName: String
    }

    struct PersistentTerminalTurnSnapshot {
        var result: CommandExecutionResult?
        var observation: CLIInteractionObservation?
        var partialOutput: String
    }

    struct PersistentTerminalProcessResult: Sendable {
        var exitCode: Int32
        var output: String
    }

    public struct PersistentTerminalREPLTurnResult: Sendable {
        public var exitCode: Int32
        public var output: String
        public var observation: CLIInteractionObservation
        public var timedOut: Bool
    }

    actor PersistentTerminalSession {
        internal let target: PersistentTerminalTarget

        init(target: PersistentTerminalTarget) {
            self.target = target
        }

        internal var targetPane: String {
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

    func preparePersistentTerminalTarget(for agent: CompanyAgent) -> PersistentTerminalTarget? {
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


    func prunePersistentTerminalSessionCache() {
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


    func sendPersistentTerminalInputLine(_ text: String, to agent: CompanyAgent) async -> CommandExecutionResult? {
        guard !text.contains(where: { $0.isNewline }) else {
            return CommandExecutionResult(
                exitCode: 126,
                standardOutput: "",
                standardError: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L().L()
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

    enum PersistentTerminalREPLLogSource {
        case manual
        case autoLoop

        var title: String {
            switch self {
            case .manual:
                return "OPC 手动交互轮次".L().L()
            case .autoLoop:
                return "OPC 自动交互循环轮次".L().L()
            }
        }
    }

    func runPersistentTerminalREPLTurn(
        _ text: String,
        to agent: CompanyAgent,
        timeoutSeconds: TimeInterval,
        logSource: PersistentTerminalREPLLogSource = .manual
    ) async -> PersistentTerminalREPLTurnResult? {
        guard !text.contains(where: { $0.isNewline }) else {
            let observation = CLIInteractionObservation(phase: .transientFailure, reasonTitle: "输入不合规".L().L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 126,
                output: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L().L(),
                observation: observation,
                timedOut: false
            )
        }
        guard let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "暂不支持".L().L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 127,
                output: "该员工的命令行来源不在长期会话画像目录里，手动交互轮次暂不支持。".L().L(),
                observation: observation,
                timedOut: false
            )
        }
        guard !profile.replReadySignals.isEmpty else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "暂不支持".L().L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 127,
                output: "\(opcBackendCommandDisplayName(profile.command))" + " 暂未配置专用就绪提示，手动交互轮次仅对配置了独立行就绪提示的命令行工具开放。".L().L(),
                observation: observation,
                timedOut: false
            )
        }
        guard let target = preparePersistentTerminalTarget(for: agent) else { return nil }

        let terminalSession = persistentTerminalSession(for: target)
        let workingDirectory = cliWorkingDirectoryURL()
        let baseline = await terminalSession.capture(workingDirectory: workingDirectory)
        guard baseline.exitCode == 0 else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "终端不可用".L().L())
            return PersistentTerminalREPLTurnResult(exitCode: baseline.exitCode, output: baseline.output, observation: observation, timedOut: false)
        }
        guard profile.endsWithReplReadyPrompt(baseline.output) else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "终端未就绪".L().L())
            return PersistentTerminalREPLTurnResult(
                exitCode: 126,
                output: "该员工终端席位最近一行不是 ".L().L() + "\(profile.displayName)" + " 的交互就绪提示。为避免把手动输入误发到普通终端，请先通过员工任务运行入口启动对应命令行工具，看到最近一行的独立就绪提示后再发送手动交互轮次。",
                observation: observation,
                timedOut: false
            )
        }

        let send = await terminalSession.sendInputLine(text, workingDirectory: workingDirectory)
        guard send.exitCode == 0 else {
            let observation = CLIInteractionObservation(phase: .unknown, reasonTitle: "输入发送失败".L().L())
            return PersistentTerminalREPLTurnResult(exitCode: send.exitCode, output: send.output, observation: observation, timedOut: false)
        }

        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0.1))
        var latestDelta = ""
        var latestObservation = CLIInteractionObservation(phase: .awaitingResponse, reasonTitle: "等待回复".L().L())
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


    func recordPersistentTerminalREPLObservation(agent: CompanyAgent, observation: CLIInteractionObservation) {
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

    func appendPersistentTerminalREPLLog(
        agent: CompanyAgent,
        observation: CLIInteractionObservation,
        timedOut: Bool,
        source: PersistentTerminalREPLLogSource = .manual
    ) {
        let timeoutLine = timedOut ? "结果：本轮等待超时，未中断终端席位。\n".L().L() : ""
        appendTerminalLog(
            "\n[" + "\(source.title)" + "]\n" + "\(timeoutLine)" + "状态：".L().L() + "\(observation.reasonTitle)" + "。\n",
            for: agent.id
        )
    }

    func runPersistentTerminalCommand(
        command: [String],
        executionDirectory: URL,
        target: PersistentTerminalTarget,
        timeoutSeconds: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> CommandExecutionResult {
        guard !command.isEmpty else {
            return CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: "没有提供命令。".L().L())
        }

        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let startMarker = "__OPC_JOB_START_\(marker)__"
        let endMarker = "__OPC_JOB_EXIT_\(marker)__:"
        let interactionProfile = command.first.flatMap { CLIInteractionProfileCatalog.profile(forCommand: $0) }
        let terminalSession = persistentTerminalSession(for: target)
        let workingDirectory = cliWorkingDirectoryURL()

        let preflightCapture = await terminalSession.capture(workingDirectory: workingDirectory)
        if preflightCapture.exitCode == 0, persistentTerminalHasUnfinishedOPCJob(preflightCapture.output) {
            let message = "\n终端席位仍有未完成的 OPC 命令行任务，已拒绝覆盖发送。请先刷新真实终端日志或恢复异常占用会话。\n".L().L()
            onOutput(message)
            return CommandExecutionResult(exitCode: 125, standardOutput: "", standardError: message)
        }

        guard let runnerScriptURL = writePersistentTerminalRunnerScript(
            command: command,
            executionDirectory: executionDirectory,
            startMarker: startMarker,
            endMarker: endMarker
        ) else {
            let message = "OPC 未能创建长期终端任务 runner 脚本。".L().L()
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
        let observationLine = latestObservation.map { "最后观察状态：".L().L() + "\($0.reasonTitle)" + "。\n" } ?? ""
        let message = "\n命令超时：".L().L() + "\(Int(timeoutSeconds))" + " 秒内没有返回，OPC 已停止等待该终端任务，并尝试中断长期席位。\n".L().L() + "\(observationLine)" + "\(interruptSummary)"
        onOutput(message)
        return CommandExecutionResult(
            exitCode: 124,
            standardOutput: persistentTerminalPartialOutput(from: latestCapture, startMarker: startMarker),
            standardError: message
        )
    }

    func interruptPersistentTerminalCommand(
        terminalSession: PersistentTerminalSession,
        workingDirectory: URL,
        startMarker: String,
        endMarker: String
    ) async -> String {
        _ = await terminalSession.sendKeys(["C-c"], workingDirectory: workingDirectory)
        try? await Task.sleep(nanoseconds: 500_000_000)
        if await persistentTerminalTurnClosed(terminalSession: terminalSession, workingDirectory: workingDirectory, startMarker: startMarker, endMarker: endMarker) {
            return "中断处理：普通中断已生效。\n".L().L()
        }

        _ = await terminalSession.sendKeys(["C-\\"], workingDirectory: workingDirectory)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if await persistentTerminalTurnClosed(terminalSession: terminalSession, workingDirectory: workingDirectory, startMarker: startMarker, endMarker: endMarker) {
            return "中断处理：强中断已生效。\n".L().L()
        }

        _ = await terminalSession.killWindow(workingDirectory: workingDirectory)
        return "中断处理：已关闭未响应的终端席位，下次运行会重新创建席位。\n".L().L()
    }


    func writePersistentTerminalRunnerScript(command: [String], executionDirectory: URL, startMarker: String, endMarker: String) -> URL? {
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

    func cleanupPersistentTerminalRunnerScripts(in directory: URL, staleInterval: TimeInterval = 6 * 60 * 60, now: Date = Date()) {
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









    func safeTmuxName(_ value: String) -> String {
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

    func tmuxSessionExists(_ sessionName: String, tmuxPath: String? = nil) -> Bool {
        guard let executable = tmuxPath ?? AgentProcessRunner.resolvedExecutablePath(for: "tmux") else { return false }
        let result = runLocalProcess(
            executable: executable,
            arguments: ["has-session", "-t", sessionName],
            workingDirectory: cliWorkingDirectoryURL()
        )
        return result.exitCode == 0
    }

    func tmuxWindowNames(_ sessionName: String, tmuxPath: String? = nil) -> [String] {
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


    func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func cliToolchainIssueLines() -> [String] {
        var issues: [String] = []
        if executableAgents.isEmpty {
            issues.append("当前产品没有可执行员工。".L().L())
        }
        let workingDirectory = cliWorkingDirectoryURL()
        if !FileManager.default.fileExists(atPath: workingDirectory.path) {
            issues.append("工作目录不存在：".L().L() + "\(workingDirectory.path)")
        }
        for agent in executableAgents {
            let command = agent.backend.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty {
                issues.append("\(agent.displayName)" + " 没有配置命令。".L().L())
            }
            switch agent.backend.type {
            case .api:
                if agent.backend.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(agent.displayName)" + " 是接口模式，但没有接口地址。".L().L())
                }
                if agent.backend.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append("\(agent.displayName)" + " 是接口模式，但没有接口密钥。".L().L())
                }
            case .subscriptionCLI:
                if command == "api-agent" || command == "human" {
                    issues.append("\(agent.displayName)" + " 是订阅制命令行模式，但命令配置不合理：".L().L() + "\(command)" + "。")
                }
            case .local:
                if agent.role != .boss {
                    issues.append("\(agent.displayName)" + " 是本地占位模式，不能真正运行外部模型。".L().L())
                }
            }
        }
        return issues
    }









    func trimCommunicationLogs() {
        if communicationLogs.count > 200 {
            communicationLogs.removeLast(communicationLogs.count - 200)
        }
    }



    public func operatingProfile(for agentID: UUID) -> AgentOperatingProfile {
        if let profile = agentProfiles[agentID] {
            return profile
        }
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return AgentOperatingProfile(
                mission: "接收消息并按上下文回复。".L().L(),
                responsibilities: ["确认消息".L().L()],
                boundaries: ["不执行未知操作".L().L()],
                responseRules: ["简洁回复".L().L()],
                memory: [],
                skills: []
            )
        }
        let profile = AgentOperatingProfile.defaultProfile(for: agent)
        agentProfiles[agentID] = profile
        return profile
    }










    func writeTextIfChanged(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if let existing = try? Data(contentsOf: url), existing == data {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    func soulDocument(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
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





static func promptFragment(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))…"
    }

static func promptInlineList(_ items: [String], empty: String, itemLimit: Int, itemTextLimit: Int) -> String {
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
        return "\(line)" + "；还有 ".L() + "\(hiddenCount)" + " 项已保存在导入报告，按任务需要再读取。".L()
    }

    func promptList(_ items: [String], limit: Int, itemLimit: Int) -> String {
        let visible = items.prefix(itemLimit).map {
            "- \(Self.promptFragment($0, limit: limit))"
        }
        let hiddenCount = max(0, items.count - itemLimit)
        guard !visible.isEmpty else { return "- 暂无".L() }
        if hiddenCount == 0 {
            return visible.joined(separator: "\n")
        }
        return (visible + ["- 还有 ".L() + "\(hiddenCount)" + " 项已保存在员工档案，按任务需要再读取。".L()]).joined(separator: "\n")
    }



    func workspaceDocument(for agent: CompanyAgent) -> String {
        let product = selectedProduct
        let team = selectedProductAgents.map { member in
            "- \(member.displayName)：\(member.title) / \(member.role.title)\(member.id == product?.teamLeadAgentID ? " / 团队负责人" : "")"
        }.joined(separator: "\n")
        let activePlans = selectedProductBranchPlans.prefix(5).map { plan in
            "- ".L() + "\(plan.goal)" + "：".L() + "\(plan.status.title)" + "，分支 ".L() + "\(plan.lanes.count)" + " 条".L()
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


    func markdownList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "agent" : result
    }


    func hydrateAPIKeysFromKeychain() {
        for index in agents.indices where agents[index].backend.type == .api {
            if !agents[index].backend.apiKey.isEmpty {
                writeAPIKeyToKeychain(agents[index].backend.apiKey, agentID: agents[index].id, context: "启动时回写".L().L())
            } else {
                agents[index].backend.apiKey = OPCKeychainStore.loadAPIKey(agentID: agents[index].id)
            }
        }
    }


    /// 调用注入的 keychain 写入闭包并把非成功 OSStatus 转换成老板可见的 in-memory 风险事件。
    /// 把 hydrate / 快照两条路径上的 keychain 写入收敛到一处，避免遗漏其中一处不上报。
    @discardableResult
    func writeAPIKeyToKeychain(_ value: String, agentID: UUID, context: String) -> OSStatus {
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
    func recordKeychainSaveFailure(status: OSStatus, agentID: UUID, context: String) {
        let title = "API Key 写入 Keychain 失败".L().L()
        let name = agents.first(where: { $0.id == agentID })?.displayName ?? "未知员工".L().L()
        let detail = "\(name)" + " · " + "\(context)" + " · OSStatus=".L() + "\(status)" + "。本次输入的 Key 仍在内存中可用，但应用重启后会丢失，需要重新填写并确认 Keychain 是否被锁定或权限受限。".L().L()
        if let latest = events.first,
           latest.kind == .risk,
           latest.title == title,
           latest.agentID == agentID,
           latest.detail == detail {
            return
        }
        appendEvent(kind: .risk, title: title, detail: detail, agentID: agentID)
    }





    func listItems(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-• "))
            }
            .filter { !$0.isEmpty }
    }


    func isLegacyAutoCreatedSpecialist(_ agent: CompanyAgent) -> Bool {
        switch agent.role {
        case .productArchitect:
            agent.displayName == "Codex 产品架构师".L().L()
                && agent.title == "需求与产品结构负责人".L().L()
                && agent.backend.command == "codex"
        case .tester:
            agent.displayName == "Codex 测试工程师".L().L()
                && agent.title == "自动化验证负责人".L().L()
                && agent.backend.command == "codex"
        case .researcher:
            agent.displayName == "Gemini 研究员".L().L()
                && agent.title == "资料与竞品研究员".L().L()
                && agent.backend.command == "gemini"
        default:
            false
        }
    }


    func environmentOverrides(for agent: CompanyAgent) -> [String: String] {
        guard agent.backend.type == .api else { return [:] }
        return [
            "OPC_AGENT_API_KEY": agent.backend.apiKey,
            "OPC_AGENT_ENDPOINT": agent.backend.endpoint,
            "OPC_AGENT_MODEL": agent.backend.model
        ]
    }

    func cliResumeSessionID(for agent: CompanyAgent) -> String? {
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

    func recordCLISessionIfNeeded(agent: CompanyAgent, result: CommandExecutionResult, usedResumeSessionID: String?) {
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
            appendTerminalLog("\n[OPC 上下文已重置]\n当前产品的上一轮上下文连续不可用 ".L().L() + "\(nextFailureCount)" + " 次，后续任务将重新开始。\n".L().L(), for: agent.id)
            appendEvent(kind: .statusChanged, title: "\(agent.displayName)" + " 上下文已重置", detail: "当前产品的上一轮任务上下文连续不可用，已自动重置；下一次会重新开始。".L().L(), agentID: agent.id)
        } else {
            conversations[selectedProductID] = entry
            appendTerminalLog("\n[OPC 上下文复用失败]\n当前产品的上一轮上下文暂时不可用 ".L().L() + "\(nextFailureCount)" + " 次；再次不可用会自动重置。\n".L().L(), for: agent.id)
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
                recoveryLine = "建议：".L().L() + "\(recoveryAction.title)" + "。" + "\(operatorHint)" + "\n"
            } else {
                recoveryLine = ""
            }
            appendTerminalLog("\n[OPC 交互状态]\n状态：".L().L() + "\(observation.reasonTitle)" + "。\n" + "\(recoveryLine)", for: agent.id)

            // 升级到 attention 状态（技术负责人和老板都应看到的健康风险）写一条结构化事件，
            // 便于回查"过去一段时间出现过几次授权异常 / 忙碌 / 临时异常"。
            // ready / completedTurn / awaitingResponse 等常规状态不写事件，避免噪音。
            // phase 去重逻辑（previousPhase != observation.phase）保证同一 attention 状态
            // 不会被反复写事件。
            if isCLIAttentionPhaseForAuditEvent(observation.phase) {
                let detail: String
                if let hint = recoveryAction.operatorHint {
                    detail = "\(observation.reasonTitle)" + " · 建议：".L().L() + "\(recoveryAction.title)" + "。" + "\(hint)"
                } else {
                    detail = "\(observation.reasonTitle)" + " · 建议：".L().L() + "\(recoveryAction.title)" + "。"
                }
                appendEvent(
                    kind: .risk,
                    title: "命令行健康预警：".L().L() + "\(agent.displayName)",
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
    func isCLIAttentionPhaseForAuditEvent(_ phase: CLIInteractionPhase) -> Bool {
        switch phase {
        case .busy, .authenticationBlocked, .transientFailure:
            return true
        case .unknown, .ready, .awaitingResponse, .completedTurn:
            return false
        }
    }

    func codexSessionID(from output: String) -> String? {
        cliSessionID(from: output)
    }

    func cliSessionID(from output: String) -> String? {
        CLIInteractionProfileCatalog.sessionID(from: output)
    }

    func supportsCLIResume(_ agent: CompanyAgent) -> Bool {
        CLIAgentCommandBuilder.interactionProfile(for: agent)?.supportsResume == true
    }

    func cliSessionMode(for agent: CompanyAgent) -> String {
        CLIAgentCommandBuilder.interactionProfile(for: agent)?.sessionMode ?? "unknown"
    }

    func isolatedHomeURL(for agent: CompanyAgent, executionDirectory: URL) -> URL? {
        guard agent.backend.type == .subscriptionCLI else { return nil }
        guard currentRuntimeCapability(for: agent) != .persistentProtocol else { return nil }
        return executionDirectory
    }

    func sandboxProfile(for agent: CompanyAgent, executionDirectory: URL) -> String? {
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

    func sandboxEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func currentRuntimeCapability(for agent: CompanyAgent) -> AgentRuntimeCapability {
        let signature = CLIAgentCommandBuilder.backendSignature(for: agent)
        if let session = runtimeSessions[agent.id],
           session.backendSignature == signature,
           session.productID == selectedProductID {
            return session.capability
        }
        return CLIAgentCommandBuilder.runtimeCapability(for: agent)
    }

    func maxSeverity(_ lhs: VerificationStatus, _ rhs: VerificationStatus) -> VerificationStatus {
        if lhs == .failed || rhs == .failed { return .failed }
        if lhs == .warning || rhs == .warning { return .warning }
        return .passed
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


// MARK: - Deterministic UUID tiebreak (shared sort helper)

extension Sequence {
    /// Sorts by a primary date and breaks ties deterministically by UUID,
    /// keeping list rendering stable across identical timestamps.
    func sortedByDateThenID<T: Comparable>(
        by date: (Element) -> T,
        tieBreakID: (Element) -> UUID
    ) -> [Element] {
        sorted { lhs, rhs in
            let l = date(lhs), r = date(rhs)
            return l == r ? tieBreakID(lhs).uuidString < tieBreakID(rhs).uuidString : l < r
        }
    }
}
