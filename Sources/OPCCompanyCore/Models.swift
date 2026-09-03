import Foundation

public enum AgentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case idle
    case thinking
    case talking
    case typing
    case coding
    case reviewing
    case blocked
    case waitingApproval
    case done
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .idle: "待命".L().L()
        case .thinking: "思考中".L().L()
        case .talking: "沟通中".L().L()
        case .typing: "输入中".L().L()
        case .coding: "编码中".L().L()
        case .reviewing: "审查中".L().L()
        case .blocked: "阻塞".L().L()
        case .waitingApproval: "待批准".L().L()
        case .done: "完成".L().L()
        case .failed: "失败".L().L()
        }
    }
}

public enum MainWorkspace: String, CaseIterable, Identifiable, Sendable {
    case commandCenter
    case productDetail
    case agentDesk
    case office
    case workflow
    case terminalHall

    public var id: String { rawValue }

    public static var workNavigationCases: [MainWorkspace] {
        [.commandCenter, .productDetail, .agentDesk, .workflow, .terminalHall]
    }

    public var title: String {
        switch self {
        case .commandCenter: "总控台".L().L()
        case .productDetail: "产品详情".L().L()
        case .agentDesk: "员工工作台".L().L()
        case .office: "公司场景".L().L()
        case .workflow: "流程图".L().L()
        case .terminalHall: "终端大厅".L().L()
        }
    }
}

public enum ProductStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case discovery
    case design
    case implementation
    case testing
    case release
    case maintenance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .discovery: "调研".L().L()
        case .design: "设计".L().L()
        case .implementation: "实现".L().L()
        case .testing: "测试".L().L()
        case .release: "发布".L().L()
        case .maintenance: "维护".L().L()
        }
    }
}

public enum ProductStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case paused
    case archived

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: "进行中".L().L()
        case .paused: "暂停".L().L()
        case .archived: "归档".L().L()
        }
    }
}

public struct ProjectImportReport: Codable, Hashable, Sendable {
    public var projectName: String
    public var shortName: String
    public var rootDirectory: String
    public var ruleFiles: [String]
    public var detectedTools: [String]
    public var projectFiles: [String]
    public var summary: String
    public var importedAt: Date

    public init(projectName: String, shortName: String, rootDirectory: String, ruleFiles: [String], detectedTools: [String], projectFiles: [String], summary: String, importedAt: Date = Date()) {
        self.projectName = projectName
        self.shortName = shortName
        self.rootDirectory = rootDirectory
        self.ruleFiles = ruleFiles
        self.detectedTools = detectedTools
        self.projectFiles = projectFiles
        self.summary = summary
        self.importedAt = importedAt
    }
}

public struct ProductWorkspace: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var shortName: String
    public var rootDirectory: String
    public var status: ProductStatus
    public var stage: ProductStage
    public var assignedAgentIDs: Set<UUID>
    public var teamLeadAgentID: UUID?
    public var importReport: ProjectImportReport?
    public var enforceSandbox: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        shortName: String,
        rootDirectory: String,
        status: ProductStatus = .active,
        stage: ProductStage = .implementation,
        assignedAgentIDs: Set<UUID>,
        teamLeadAgentID: UUID? = nil,
        importReport: ProjectImportReport? = nil,
        enforceSandbox: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.rootDirectory = rootDirectory
        self.status = status
        self.stage = stage
        self.assignedAgentIDs = assignedAgentIDs
        self.teamLeadAgentID = teamLeadAgentID
        self.importReport = importReport
        self.enforceSandbox = enforceSandbox
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case boss
    case cto
    case productArchitect
    case uiDesigner
    case codeEngineer
    case reviewer
    case tester
    case researcher
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .boss: "老板".L().L()
        case .cto: "技术负责人".L().L()
        case .productArchitect: "产品架构师".L().L()
        case .uiDesigner: "界面设计师".L().L()
        case .codeEngineer: "代码工程师".L().L()
        case .reviewer: "审查员".L().L()
        case .tester: "测试工程师".L().L()
        case .researcher: "研究员".L().L()
        case .custom: "自定义角色".L().L()
        }
    }
}

public enum BackendType: String, Codable, CaseIterable, Identifiable, Sendable {
    case subscriptionCLI
    case api
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subscriptionCLI: "订阅制命令行".L().L()
        case .api: "接口模型".L().L()
        case .local: "本地占位".L().L()
        }
    }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .low: "低".L().L()
        case .medium: "中".L().L()
        case .high: "高".L().L()
        case .xhigh: "超高".L().L()
        }
    }
}

public enum EthnicityPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case chinese
    case white
    case black
    case southAsian
    case middleEastern
    case latino
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chinese: "中国人".L().L()
        case .white: "白人".L().L()
        case .black: "黑人".L().L()
        case .southAsian: "南亚人".L().L()
        case .middleEastern: "中东人".L().L()
        case .latino: "拉丁裔".L().L()
        case .custom: "自定义".L().L()
        }
    }
}

public enum GenderPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case man
    case woman
    case nonbinary
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .man: "男性".L().L()
        case .woman: "女性".L().L()
        case .nonbinary: "非二元".L().L()
        case .custom: "自定义".L().L()
        }
    }
}

public enum ClothingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case businessSuit
    case smartCasual
    case hoodie
    case designerBlack
    case labCoat
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .businessSuit: "商务西装".L().L()
        case .smartCasual: "商务休闲".L().L()
        case .hoodie: "连帽卫衣".L().L()
        case .designerBlack: "设计师黑装".L().L()
        case .labCoat: "实验白袍".L().L()
        case .custom: "自定义".L().L()
        }
    }
}

public enum AgentPermission: String, Codable, CaseIterable, Identifiable, Sendable {
    case readFiles
    case editFiles
    case runTests
    case runCommands
    case useNetwork
    case approveRisk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .readFiles: "读取文件".L().L()
        case .editFiles: "编辑文件".L().L()
        case .runTests: "运行测试".L().L()
        case .runCommands: "执行命令".L().L()
        case .useNetwork: "使用网络".L().L()
        case .approveRisk: "批准风险操作".L().L()
        }
    }
}

public struct AgentBackend: Codable, Hashable, Sendable {
    public var type: BackendType
    public var command: String
    public var model: String
    public var endpoint: String
    public var apiKey: String
    public var reasoningEffort: ReasoningEffort

    public init(type: BackendType, command: String, model: String, endpoint: String = "", apiKey: String = "", reasoningEffort: ReasoningEffort = .medium) {
        self.type = type
        self.command = command
        self.model = model
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.reasoningEffort = reasoningEffort
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case model
        case endpoint
        case apiKey
        case reasoningEffort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(BackendType.self, forKey: .type)
        command = try container.decode(String.self, forKey: .command)
        model = try container.decode(String.self, forKey: .model)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(command, forKey: .command)
        try container.encode(model, forKey: .model)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode("", forKey: .apiKey)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
    }
}

public struct CompanyAgent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var title: String
    public var role: AgentRole
    public var backend: AgentBackend
    public var ethnicity: EthnicityPresentation
    public var gender: GenderPresentation
    public var clothing: ClothingStyle
    public var status: AgentStatus
    public var permissions: Set<AgentPermission>
    public var reportsToCTO: Bool
    public var seat: OfficeSeat

    public init(
        id: UUID = UUID(),
        displayName: String,
        title: String,
        role: AgentRole,
        backend: AgentBackend,
        ethnicity: EthnicityPresentation,
        gender: GenderPresentation,
        clothing: ClothingStyle,
        status: AgentStatus = .idle,
        permissions: Set<AgentPermission>,
        reportsToCTO: Bool = true,
        seat: OfficeSeat
    ) {
        self.id = id
        self.displayName = displayName
        self.title = title
        self.role = role
        self.backend = backend
        self.ethnicity = ethnicity
        self.gender = gender
        self.clothing = clothing
        self.status = status
        self.permissions = permissions
        self.reportsToCTO = reportsToCTO
        self.seat = seat
    }
}

public enum CommunicationChannelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case feishuWebhook
    case wecomWebhook
    case dingtalkWebhook
    case telegramBot
    case emailDigest
    case localOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feishuWebhook: "飞书群机器人".L().L()
        case .wecomWebhook: "企业微信群机器人".L().L()
        case .dingtalkWebhook: "钉钉群机器人".L().L()
        case .telegramBot: "Telegram 机器人".L().L()
        case .emailDigest: "邮件日报".L().L()
        case .localOnly: "本地指挥台".L().L()
        }
    }

    public var capabilitySummary: String {
        switch self {
        case .feishuWebhook, .wecomWebhook, .dingtalkWebhook:
            "适合把团队负责人日报、风险、完成情况推送到手机群；双向下达需要企业应用回调。".L().L()
        case .telegramBot:
            "适合个人远程双向命令，可通过机器人接口收发消息。".L().L()
        case .emailDigest:
            "适合低频日报、周报、交付摘要，不适合实时调度。".L().L()
        case .localOnly:
            "只在本机 OPC 内部记录，用于没有外部通道时验证工作流。".L().L()
        }
    }

    public var supportsOutboundReport: Bool {
        true
    }

    public var supportsInboundCommand: Bool {
        switch self {
        case .telegramBot, .localOnly: true
        case .feishuWebhook, .wecomWebhook, .dingtalkWebhook, .emailDigest: false
        }
    }
}

public enum CommunicationLogDirection: String, Codable, Sendable {
    case outbound
    case inbound

    public var title: String {
        switch self {
        case .outbound: "外发汇报".L().L()
        case .inbound: "手机指令".L().L()
        }
    }
}

public enum CommunicationLogStatus: String, Codable, Sendable {
    case planned
    case queued
    case sent
    case received
    case failed

    public var title: String {
        switch self {
        case .planned: "已规划".L().L()
        case .queued: "已入队".L().L()
        case .sent: "已发送".L().L()
        case .received: "已接收".L().L()
        case .failed: "失败".L().L()
        }
    }
}

public enum InboundCommandSource: String, Sendable {
    case localCommandConsole
    case externalSignedChannel
    case testFixture

    public var title: String {
        switch self {
        case .localCommandConsole: "本地指挥台".L().L()
        case .externalSignedChannel: "外部签名通道".L().L()
        case .testFixture: "测试夹具".L().L()
        }
    }
}

public struct CommunicationChannelConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID?
    public var name: String
    public var kind: CommunicationChannelKind
    public var endpoint: String
    public var chatID: String
    public var teamLeadAgentID: UUID?
    public var isEnabled: Bool
    public var reportsEnabled: Bool
    public var commandsEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        productID: UUID? = nil,
        name: String,
        kind: CommunicationChannelKind,
        endpoint: String = "",
        chatID: String = "",
        teamLeadAgentID: UUID? = nil,
        isEnabled: Bool = false,
        reportsEnabled: Bool = true,
        commandsEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.productID = productID
        self.name = name
        self.kind = kind
        self.endpoint = endpoint
        self.chatID = chatID
        self.teamLeadAgentID = teamLeadAgentID
        self.isEnabled = isEnabled
        self.reportsEnabled = reportsEnabled
        self.commandsEnabled = commandsEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CommunicationLogEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var channelID: UUID?
    public var productID: UUID
    public var agentID: UUID?
    public var direction: CommunicationLogDirection
    public var status: CommunicationLogStatus
    public var title: String
    public var body: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        channelID: UUID? = nil,
        productID: UUID,
        agentID: UUID? = nil,
        direction: CommunicationLogDirection,
        status: CommunicationLogStatus,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.channelID = channelID
        self.productID = productID
        self.agentID = agentID
        self.direction = direction
        self.status = status
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

public enum ProductTeamTemplate: String, CaseIterable, Identifiable, Sendable {
    case software
    case presales
    case research

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .software: "软件开发团队".L().L()
        case .presales: "售前方案团队".L().L()
        case .research: "研究监控团队".L().L()
        }
    }

    public var summary: String {
        switch self {
        case .software: "技术负责人 + 产品架构 + 界面 + 工程 + 测试/审查，适合开发应用和工具。".L().L()
        case .presales: "技术负责人 + 资料研究 + 方案架构 + 界面/排版 + 审查，适合售前方案。".L().L()
        case .research: "技术负责人 + 资料研究 + 审查，适合资料收集、竞品和趋势跟踪。".L().L()
        }
    }

    public var roles: [AgentRole] {
        switch self {
        case .software: [.cto, .productArchitect, .uiDesigner, .codeEngineer, .tester, .reviewer]
        case .presales: [.cto, .researcher, .productArchitect, .uiDesigner, .reviewer]
        case .research: [.cto, .researcher, .reviewer]
        }
    }

    public var leadRole: AgentRole {
        .cto
    }
}

public struct AgentOperatingProfile: Codable, Hashable, Sendable {
    public var mission: String
    public var responsibilities: [String]
    public var boundaries: [String]
    public var responseRules: [String]
    public var memory: [String]
    public var skills: [String]

    public init(mission: String, responsibilities: [String], boundaries: [String], responseRules: [String], memory: [String] = [], skills: [String] = []) {
        self.mission = mission
        self.responsibilities = responsibilities
        self.boundaries = boundaries
        self.responseRules = responseRules
        self.memory = memory
        self.skills = skills
    }

    public static func defaultProfile(for agent: CompanyAgent) -> AgentOperatingProfile {
        let commonRules = [
            "使用第一人称回复，不冒充老板或其他员工。".L().L(),
            "不承诺已经完成未执行的工作。".L().L(),
            "遇到权限、信息或工具不足时直接说明阻塞点。".L().L(),
            "重要进展需要同步技术负责人。".L().L()
        ]

        switch agent.role {
        case .boss:
            return AgentOperatingProfile(
                mission: "代表老板本人，只保存老板偏好、目标和决策，不执行员工任务。".L().L(),
                responsibilities: ["记录老板目标".L().L(), "保存决策偏好".L().L(), "触发技术负责人协调".L().L()],
                boundaries: ["不替员工承诺交付".L().L(), "不直接执行终端命令".L().L()],
                responseRules: ["只确认老板档案、目标或决策已记录。".L().L()] + commonRules,
                memory: ["老板希望 OPC 像本地智能公司一样运转。".L().L()],
                skills: ["planning"]
            )
        case .cto:
            return AgentOperatingProfile(
                mission: "作为总技术负责人，负责理解老板目标、拆解任务、分配员工、跟踪进度、汇总风险和交付结论。".L().L(),
                responsibilities: ["拆解目标".L().L(), "分配员工".L().L(), "检查结果".L().L(), "向老板汇报".L().L()],
                boundaries: ["不把自己称为第三方技术负责人".L().L(), "不跳过老板确认做高风险操作".L().L()],
                responseRules: commonRules + ["先复述目标，再给下一步调度动作。".L().L()],
                memory: ["OPC 的默认工作流是老板 -> 技术负责人 -> 员工 -> 技术负责人验收 -> 老板确认。".L().L()],
                skills: AgentSkillCatalog.ids(for: .cto)
            )
        case .uiDesigner:
            return AgentOperatingProfile(
                mission: "负责把产品目标转成可实现的界面、交互、视觉和动效方案。".L().L(),
                responsibilities: ["界面结构".L().L(), "视觉风格".L().L(), "动效状态".L().L(), "可用性检查".L().L()],
                boundaries: ["不直接承诺工程完成".L().L(), "没有技术负责人工单时只给设计判断".L().L()],
                responseRules: commonRules + ["说明设计输出会等待或同步技术负责人。".L().L()],
                skills: AgentSkillCatalog.ids(for: .uiDesigner)
            )
        case .codeEngineer:
            return AgentOperatingProfile(
                mission: "负责在明确范围内实现代码、修复问题、运行验证并汇报修改内容。".L().L(),
                responsibilities: ["代码实现".L().L(), "调试修复".L().L(), "测试验证".L().L(), "文件变更汇报".L().L()],
                boundaries: ["不越权改无关文件".L().L(), "不声称已运行未运行的验证".L().L()],
                responseRules: commonRules + ["说明需要明确范围或技术负责人工单。".L().L()],
                skills: AgentSkillCatalog.ids(for: .codeEngineer)
            )
        case .reviewer:
            return AgentOperatingProfile(
                mission: "负责按成功标准审查产物，优先指出问题、风险和是否可以交付。".L().L(),
                responsibilities: ["验收审查".L().L(), "风险识别".L().L(), "测试缺口".L().L(), "交付结论".L().L()],
                boundaries: ["不替工程师实现功能".L().L(), "没有标准时先要求补充验收标准".L().L()],
                responseRules: commonRules + ["优先讲风险和结论。".L().L()],
                skills: AgentSkillCatalog.ids(for: .reviewer)
            )
        case .tester:
            return AgentOperatingProfile(
                mission: "负责把任务转成可重复验证步骤，发现失败场景并记录结果。".L().L(),
                responsibilities: ["测试计划".L().L(), "失败复现".L().L(), "回归验证".L().L()],
                boundaries: ["不代替审查员给最终交付结论".L().L()],
                responseRules: commonRules + ["说明验证方式和失败条件。".L().L()],
                skills: AgentSkillCatalog.ids(for: .tester)
            )
        case .productArchitect:
            return AgentOperatingProfile(
                mission: "负责需求结构、模块边界、产品约束和成功标准。".L().L(),
                responsibilities: ["需求拆解".L().L(), "模块划分".L().L(), "PRD", "成功标准".L().L()],
                boundaries: ["不替技术负责人做最终调度".L().L()],
                responseRules: commonRules + ["输出结构化产品判断。".L().L()],
                skills: AgentSkillCatalog.ids(for: .productArchitect)
            )
        case .researcher:
            return AgentOperatingProfile(
                mission: "负责资料、竞品、行业信息和上下文收集，并提炼可复用结论。".L().L(),
                responsibilities: ["资料收集".L().L(), "竞品分析".L().L(), "行业摘要".L().L()],
                boundaries: ["不编造来源".L().L(), "不把未经验证的信息当事实".L().L()],
                responseRules: commonRules + ["说明信息来源和不确定性。".L().L()],
                skills: AgentSkillCatalog.ids(for: .researcher)
            )
        case .custom:
            return AgentOperatingProfile(
                mission: "按老板配置的自定义角色执行任务。".L().L(),
                responsibilities: ["执行自定义职责".L().L(), "同步进展".L().L(), "报告阻塞".L().L()],
                boundaries: ["不超出配置权限".L().L()],
                responseRules: commonRules,
                skills: []
            )
        }
    }

    public func promptBlock(agent: CompanyAgent, ctoName: String) -> String {
        """
        \("员工操作档案".L())
        \("姓名：".L())\(agent.displayName)
        \("职位：".L())\(agent.title)
        \("角色：".L())\(agent.role.title)
        \("汇报对象：".L())\(agent.reportsToCTO ? ctoName : "老板")

        \("使命：".L())
        \(mission)

        \("职责：".L())
        \(bulletList(responsibilities))

        \("边界：".L())
        \(bulletList(boundaries))

        \("回复规则：".L())
        \(bulletList(responseRules))

        \("长期记忆：".L())
        \(memory.isEmpty ? "- 暂无" : bulletList(memory))

        \("可用技能：".L())
        \(skills.isEmpty ? "- 暂无" : bulletList(skillDescriptions))
        """
    }

    private func bulletList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    public var skillDescriptions: [String] {
        skills.map { skill in
            if let definition = AgentSkillCatalog.skill(id: skill) {
                return "\(definition.id)：\(definition.title) - \(definition.summary)"
            }
            return skill
        }
    }
}

public struct AgentSkillDefinition: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var triggerKeywords: [String]
    public var defaultRoles: [AgentRole]

    public init(id: String, title: String, summary: String, triggerKeywords: [String], defaultRoles: [AgentRole]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.triggerKeywords = triggerKeywords
        self.defaultRoles = defaultRoles
    }
}

public enum AgentSkillCatalog {
    public static var all: [AgentSkillDefinition] { [
        AgentSkillDefinition(id: "planning", title: "任务拆解".L().L(), summary: "把老板目标拆成阶段、任务、负责人、风险和验收标准。".L().L(), triggerKeywords: ["拆解".L().L(), "计划".L().L(), "目标".L().L(), "路线".L().L()], defaultRoles: [.cto, .productArchitect]),
        AgentSkillDefinition(id: "product-architecture", title: "产品架构".L().L(), summary: "定义需求结构、模块边界、PRD 和成功标准。".L().L(), triggerKeywords: ["产品".L().L(), "需求".L().L(), "架构".L().L(), "PRD", "模块".L().L()], defaultRoles: [.productArchitect, .cto]),
        AgentSkillDefinition(id: "ui-design", title: "界面设计".L().L(), summary: "输出界面结构、视觉风格、交互路径和动效状态。".L().L(), triggerKeywords: ["UI", "界面".L().L(), "视觉".L().L(), "交互".L().L(), "动效".L().L()], defaultRoles: [.uiDesigner]),
        AgentSkillDefinition(id: "implementation", title: "工程实现".L().L(), summary: "修改代码、调试问题、汇报文件和验证命令。".L().L(), triggerKeywords: ["实现".L().L(), "代码".L().L(), "修复".L().L(), "开发".L().L(), "编程".L().L()], defaultRoles: [.codeEngineer]),
        AgentSkillDefinition(id: "testing", title: "测试验证".L().L(), summary: "设计可重复测试、运行验证、记录失败场景。".L().L(), triggerKeywords: ["测试".L().L(), "验证".L().L(), "回归".L().L(), "失败".L().L()], defaultRoles: [.tester, .reviewer]),
        AgentSkillDefinition(id: "review", title: "验收审查".L().L(), summary: "按成功标准检查交付质量、风险和缺口。".L().L(), triggerKeywords: ["审查".L().L(), "验收".L().L(), "风险".L().L(), "交付".L().L()], defaultRoles: [.reviewer, .cto]),
        AgentSkillDefinition(id: "research", title: "资料研究".L().L(), summary: "收集资料、竞品、行业信息和上下文证据。".L().L(), triggerKeywords: ["资料".L().L(), "研究".L().L(), "竞品".L().L(), "行业".L().L(), "搜索".L().L()], defaultRoles: [.researcher]),
        AgentSkillDefinition(id: "proposal-writing", title: "方案撰写".L().L(), summary: "组织售前方案、价值表达、实施路径和交付文本。".L().L(), triggerKeywords: ["方案".L().L(), "售前".L().L(), "客户".L().L(), "文档".L().L(), "汇报".L().L()], defaultRoles: [.productArchitect, .cto])
    ] }

    public static func skill(id: String) -> AgentSkillDefinition? {
        let normalized = normalize(id)
        return all.first { normalize($0.id) == normalized || normalize($0.title) == normalized }
    }

    public static func ids(for role: AgentRole) -> [String] {
        all.filter { $0.defaultRoles.contains(role) }.map(\.id)
    }

    public static func ids(matching text: String) -> [String] {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return [] }
        return all.filter { definition in
            normalize(definition.id).contains(normalizedText)
                || normalizedText.contains(normalize(definition.id))
                || normalize(definition.title).contains(normalizedText)
                || normalizedText.contains(normalize(definition.title))
                || definition.triggerKeywords.contains { keyword in
                    normalizedText.contains(normalize(keyword))
                }
        }
        .map(\.id)
    }

    public static func canonicalID(for value: String) -> String? {
        skill(id: value)?.id
    }

    public static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct AgentRolePack: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var role: AgentRole
    public var summary: String
    public var mission: String
    public var responsibilities: [String]
    public var boundaries: [String]
    public var responseRules: [String]
    public var memorySeeds: [String]
    public var skillIDs: [String]
    public var recommendedBackend: AgentBackend
    public var recommendedPermissions: Set<AgentPermission>

    public init(
        id: String,
        title: String,
        role: AgentRole,
        summary: String,
        mission: String,
        responsibilities: [String],
        boundaries: [String],
        responseRules: [String],
        memorySeeds: [String],
        skillIDs: [String],
        recommendedBackend: AgentBackend,
        recommendedPermissions: Set<AgentPermission>
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.summary = summary
        self.mission = mission
        self.responsibilities = responsibilities
        self.boundaries = boundaries
        self.responseRules = responseRules
        self.memorySeeds = memorySeeds
        self.skillIDs = skillIDs
        self.recommendedBackend = recommendedBackend
        self.recommendedPermissions = recommendedPermissions
    }

    public var profile: AgentOperatingProfile {
        AgentOperatingProfile(
            mission: mission,
            responsibilities: responsibilities,
            boundaries: boundaries,
            responseRules: responseRules,
            memory: memorySeeds,
            skills: skillIDs
        )
    }
}

public enum AgentRolePackCatalog {
    public static var all: [AgentRolePack] { [
        AgentRolePack(
            id: "cto-orchestrator",
            title: "技术负责人总控编排包".L().L(),
            role: .cto,
            summary: "负责老板目标理解、拆分、分派、汇总、验收和风险升级。".L().L(),
            mission: "作为 OPC 总技术负责人，把老板目标拆成可并行执行的任务，并保证所有员工结果最终可验收。".L().L(),
            responsibilities: ["目标澄清".L().L(), "多分支拆解".L().L(), "员工分派".L().L(), "结果汇总".L().L(), "风险升级".L().L(), "老板汇报".L().L()],
            boundaries: ["不绕过老板做高风险决策".L().L(), "不把未验证结果当成完成".L().L(), "不让员工互相覆盖工作".L().L()],
            responseRules: ["先给调度结论，再给分支安排".L().L(), "任何阻塞必须说明负责人和下一步".L().L(), "最终汇报必须包含完成项、风险和待老板决策".L().L()],
            memorySeeds: ["OPC 的核心工作流是老板 -> 技术负责人 -> 专业员工并行 -> 技术负责人聚合 -> 审查 -> 老板确认。".L().L()],
            skillIDs: ["planning", "product-architecture", "review"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
            recommendedPermissions: [.readFiles, .runCommands]
        ),
        AgentRolePack(
            id: "product-architect",
            title: "产品架构师包".L().L(),
            role: .productArchitect,
            summary: "把想法转成 PRD、模块边界、成功标准和任务输入。".L().L(),
            mission: "负责把模糊产品目标变成可实现、可验收、可分派的产品结构。".L().L(),
            responsibilities: ["需求结构".L().L(), "PRD", "模块边界".L().L(), "成功标准".L().L(), "交付范围控制".L().L()],
            boundaries: ["不替工程师承诺代码完成".L().L(), "不扩大老板未确认的范围".L().L()],
            responseRules: ["输出结构化条目".L().L(), "明确做什么和不做什么".L().L(), "每个模块必须有验收标准".L().L()],
            memorySeeds: ["产品架构输出必须能直接转成工程任务和审查标准。".L().L()],
            skillIDs: ["planning", "product-architecture", "proposal-writing"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
            recommendedPermissions: [.readFiles, .runCommands]
        ),
        AgentRolePack(
            id: "ui-visual-designer",
            title: "界面视觉设计包".L().L(),
            role: .uiDesigner,
            summary: "负责界面风格、交互状态、动效和视觉验收要求。".L().L(),
            mission: "负责把产品目标转成高审美、可实现、可验证的界面和动效方案。".L().L(),
            responsibilities: ["视觉方向".L().L(), "交互流程".L().L(), "组件状态".L().L(), "动效规范".L().L(), "截图问题分析".L().L()],
            boundaries: ["不直接改工程实现范围".L().L(), "不只给抽象审美词，必须落到界面元素".L().L()],
            responseRules: ["先指出当前界面问题".L().L(), "再给可执行设计指令".L().L(), "每次输出都要覆盖颜色、层级、布局和状态".L().L()],
            memorySeeds: ["老板偏好深色、炫酷、有审美但不要廉价荧光和杂乱网格。".L().L()],
            skillIDs: ["ui-design", "review"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "", reasoningEffort: .high),
            recommendedPermissions: [.readFiles]
        ),
        AgentRolePack(
            id: "code-implementation",
            title: "工程实现包".L().L(),
            role: .codeEngineer,
            summary: "负责按明确任务修改代码、运行验证并汇报文件变更。".L().L(),
            mission: "负责在技术负责人明确范围内实现代码、修复缺陷、运行验证并给出可审查结果。".L().L(),
            responsibilities: ["代码实现".L().L(), "调试修复".L().L(), "测试运行".L().L(), "变更汇报".L().L(), "阻塞说明".L().L()],
            boundaries: ["不改无关文件".L().L(), "不删除用户内容".L().L(), "不声称运行了未运行的验证".L().L()],
            responseRules: ["汇报必须包含修改文件".L().L(), "汇报必须包含验证命令和结果".L().L(), "失败时给出最小复现和下一步".L().L()],
            memorySeeds: ["工程实现优先保持现有架构和本地模式，不做无关重构。".L().L()],
            skillIDs: ["implementation", "testing"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet", reasoningEffort: .high),
            recommendedPermissions: [.readFiles, .editFiles, .runTests, .runCommands]
        ),
        AgentRolePack(
            id: "reviewer-acceptance",
            title: "审查验收包".L().L(),
            role: .reviewer,
            summary: "负责按成功标准找问题、风险、遗漏和是否可交付。".L().L(),
            mission: "负责站在老板和交付质量角度，审查任务结果是否真的满足目标。".L().L(),
            responsibilities: ["质量审查".L().L(), "风险识别".L().L(), "验收结论".L().L(), "测试缺口".L().L(), "返工建议".L().L()],
            boundaries: ["不替工程师实现".L().L(), "没有验收标准时先要求补齐".L().L()],
            responseRules: ["问题优先".L().L(), "按严重度排序".L().L(), "明确可交付/不可交付".L().L()],
            memorySeeds: ["审查不是总结，要优先发现会影响老板目标的问题。".L().L()],
            skillIDs: ["review", "testing"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "codex", model: "gpt-5.5", reasoningEffort: .high),
            recommendedPermissions: [.readFiles, .runTests]
        ),
        AgentRolePack(
            id: "researcher-presales",
            title: "资料研究/售前包".L().L(),
            role: .researcher,
            summary: "负责本地资料、客户背景、竞品、行业信息和售前素材。".L().L(),
            mission: "负责收集、整理和提炼可引用资料，为售前方案和产品判断提供依据。".L().L(),
            responsibilities: ["资料检索".L().L(), "本地文件索引".L().L(), "竞品分析".L().L(), "行业摘要".L().L(), "证据归档".L().L()],
            boundaries: ["不编造来源".L().L(), "不把未验证信息当事实".L().L()],
            responseRules: ["结论必须区分事实和推断".L().L(), "输出可复用资料清单".L().L(), "标出不确定性".L().L()],
            memorySeeds: ["售前资料需要能直接支撑方案正文、排版和最终审查。".L().L()],
            skillIDs: ["research", "proposal-writing"],
            recommendedBackend: AgentBackend(type: .subscriptionCLI, command: "gemini", model: "", reasoningEffort: .medium),
            recommendedPermissions: [.readFiles, .useNetwork]
        )
    ] }

    public static func pack(id: String) -> AgentRolePack? {
        all.first { $0.id == id }
    }

    public static func packs(for role: AgentRole) -> [AgentRolePack] {
        all.filter { $0.role == role }
    }
}

public enum AgentSessionKind: String, Codable, Sendable {
    case message
    case reply
    case command
    case result
    case memory
}

public enum AgentRuntimeState: String, Codable, CaseIterable, Identifiable, Sendable {
    case cold
    case prewarming
    case ready
    case busy
    case restarting
    case failed
    case timedOut
    case unavailable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cold: "未预热".L().L()
        case .prewarming: "预热中".L().L()
        case .ready: "已就绪".L().L()
        case .busy: "占用中".L().L()
        case .restarting: "重开中".L().L()
        case .failed: "失败".L().L()
        case .timedOut: "超时".L().L()
        case .unavailable: "不可用".L().L()
        }
    }
}

public enum AgentRuntimeCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case oneShotCLI
    case persistentProtocol
    case apiConnection
    case localPlaceholder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneShotCLI: "一次性命令行".L().L()
        case .persistentProtocol: "可继续接收任务".L().L()
        case .apiConnection: "接口连接".L().L()
        case .localPlaceholder: "本地占位".L().L()
        }
    }
}

public struct AgentRuntimeSession: Codable, Hashable, Sendable {
    public var agentID: UUID
    public var productID: UUID?
    public var state: AgentRuntimeState
    public var capability: AgentRuntimeCapability
    public var backendSignature: String
    public var startedAt: Date?
    public var lastUsedAt: Date?
    public var lastPrewarmedAt: Date?
    public var lastError: String
    public var failureCount: Int
    public var restartCount: Int
    public var lastRestartReason: String
    public var keepAlive: Bool
    public var cliSessionID: String?
    public var cliSessionMode: String?
    public var cliSessionsByProduct: [UUID: AgentCLIConversation]?
    public var cliInteractionPhase: CLIInteractionPhase?
    public var cliInteractionReason: String?
    public var cliInteractionObservedAt: Date?
    public var cliInteractionSessionID: String?
    public var cliInteractionRecoveryAction: CLIInteractionRecoveryAction?
    public var cliInteractionRecoveryActionTitle: String?
    public var cliInteractionRecoveryHint: String?
    public var cliInteractionOperatorHint: String?

    public init(
        agentID: UUID,
        productID: UUID? = nil,
        state: AgentRuntimeState = .cold,
        capability: AgentRuntimeCapability,
        backendSignature: String,
        startedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        lastPrewarmedAt: Date? = nil,
        lastError: String = "",
        failureCount: Int = 0,
        restartCount: Int = 0,
        lastRestartReason: String = "",
        keepAlive: Bool = true,
        cliSessionID: String? = nil,
        cliSessionMode: String? = nil,
        cliSessionsByProduct: [UUID: AgentCLIConversation]? = nil,
        cliInteractionPhase: CLIInteractionPhase? = nil,
        cliInteractionReason: String? = nil,
        cliInteractionObservedAt: Date? = nil,
        cliInteractionSessionID: String? = nil,
        cliInteractionRecoveryAction: CLIInteractionRecoveryAction? = nil,
        cliInteractionRecoveryActionTitle: String? = nil,
        cliInteractionRecoveryHint: String? = nil,
        cliInteractionOperatorHint: String? = nil
    ) {
        self.agentID = agentID
        self.productID = productID
        self.state = state
        self.capability = capability
        self.backendSignature = backendSignature
        self.startedAt = startedAt
        self.lastUsedAt = lastUsedAt
        self.lastPrewarmedAt = lastPrewarmedAt
        self.lastError = lastError
        self.failureCount = failureCount
        self.restartCount = restartCount
        self.lastRestartReason = lastRestartReason
        self.keepAlive = keepAlive
        self.cliSessionID = cliSessionID
        self.cliSessionMode = cliSessionMode
        self.cliSessionsByProduct = cliSessionsByProduct
        self.cliInteractionPhase = cliInteractionPhase
        self.cliInteractionReason = cliInteractionReason
        self.cliInteractionObservedAt = cliInteractionObservedAt
        self.cliInteractionSessionID = cliInteractionSessionID
        self.cliInteractionRecoveryAction = cliInteractionRecoveryAction
        self.cliInteractionRecoveryActionTitle = cliInteractionRecoveryActionTitle
        self.cliInteractionRecoveryHint = cliInteractionRecoveryHint
        self.cliInteractionOperatorHint = cliInteractionOperatorHint
    }
}

public struct AgentCLIConversation: Codable, Hashable, Sendable {
    public var productID: UUID
    public var sessionID: String
    public var mode: String
    public var backendSignature: String
    public var lastUsedAt: Date
    public var failureCount: Int?
    public var lastFailureReason: String?

    public init(productID: UUID, sessionID: String, mode: String, backendSignature: String, lastUsedAt: Date = Date(), failureCount: Int? = nil, lastFailureReason: String? = nil) {
        self.productID = productID
        self.sessionID = sessionID
        self.mode = mode
        self.backendSignature = backendSignature
        self.lastUsedAt = lastUsedAt
        self.failureCount = failureCount
        self.lastFailureReason = lastFailureReason
    }
}

public struct AgentSessionEntry: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var agentID: UUID
    public var kind: AgentSessionKind
    public var actor: String
    public var text: String

    public init(createdAt: Date = Date(), agentID: UUID, kind: AgentSessionKind, actor: String, text: String) {
        self.createdAt = createdAt
        self.agentID = agentID
        self.kind = kind
        self.actor = actor
        self.text = text
    }
}

public struct OfficeSeat: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var room: String

    public init(x: Double, y: Double, room: String) {
        self.x = x
        self.y = y
        self.room = room
    }
}

public enum MessageAuthor: String, Codable, Sendable {
    case user
    case agent
    case system
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// R29（角色继承期轮 29 落地候选 λ schema 引擎部分）：
    /// nil 表示「全局/未指定产品」消息（sentinel 含义由 caller policy 决定 — codex CTO 决定级）。
    /// 默认 nil 保证：(a) 旧 state.json 无此字段 decode 时为 nil（Swift Optional 字段 decode 缺失自动为 nil）；
    ///                (b) 50+ 处现有 `messages.append(ChatMessage(...))` caller 不传 productID 时行为等价；
    ///                (c) caller retrofit 是逐步 policy 决定（哪些用 selectedProductID / 哪些保留 nil
    ///                    / 哪些用 sentinel UUID 收纳），不强制工程师层一次性改 50 处。
    /// 2026-05-05 codex 接回复核后 candidate λ 第一阶段已落地：
    ///   (1) `messages(for:in:includingLegacyGlobal:)` 产品作用域 accessor；
    ///   (2) 老板/技术负责人当前产品视图改走产品作用域读取；
    ///   (3) `sendMessage` / boss report / handoff snapshot / live chat 等产品上下文明确路径
    ///       开始写入 productID。
    /// 剩余 retrofit 仍按策略分阶段推进：只有产品上下文明确的 caller 才写 productID；
    /// nil 保留为 legacy/global fallback，迁移审计稳定后再收紧。
    /// 守门测试：`chatMessageProductIDDefaultsToNilForLegacyDecodeAndNewInit` /
    /// `chatMessageProductIDPreservesExplicitValueAcrossCodableRoundtrip` /
    /// `chatMessageSourceContainsCandidateLambdaSchemaReference`。
    public var productID: UUID?
    public var agentID: UUID
    public var author: MessageAuthor
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), productID: UUID? = nil, agentID: UUID, author: MessageAuthor, text: String, createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.agentID = agentID
        self.author = author
        self.text = text
        self.createdAt = createdAt
    }
}

public enum CompanyEventKind: String, Codable, Sendable {
    case message
    case ctoSummary
    case taskCreated
    case taskAssigned
    case statusChanged
    case artifactCreated
    case commandPlanned
    case risk

    public var title: String {
        switch self {
        case .message: "消息".L().L()
        case .ctoSummary: "技术负责人摘要".L().L()
        case .taskCreated: "创建任务".L().L()
        case .taskAssigned: "分配任务".L().L()
        case .statusChanged: "状态变化".L().L()
        case .artifactCreated: "产物".L().L()
        case .commandPlanned: "命令".L().L()
        case .risk: "风险".L().L()
        }
    }
}

public struct CompanyEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID?
    public var kind: CompanyEventKind
    public var title: String
    public var detail: String
    public var agentID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), productID: UUID? = nil, kind: CompanyEventKind, title: String, detail: String, agentID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.agentID = agentID
        self.createdAt = createdAt
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft
    case planned
    case assigned
    case running
    case waiting
    case blocked
    case needsReview
    case needsApproval
    case done
    case failed
    case canceled

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .draft: "草稿".L().L()
        case .planned: "已计划".L().L()
        case .assigned: "已分配".L().L()
        case .running: "运行中".L().L()
        case .waiting: "等待中".L().L()
        case .blocked: "阻塞".L().L()
        case .needsReview: "待审查".L().L()
        case .needsApproval: "待批准".L().L()
        case .done: "完成".L().L()
        case .failed: "失败".L().L()
        case .canceled: "已取消".L().L()
        }
    }
}

public struct CompanyTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID?
    public var title: String
    public var ownerID: UUID?
    public var status: TaskStatus
    public var successCriteria: String
    public var artifactPath: String?

    public init(id: UUID = UUID(), productID: UUID? = nil, title: String, ownerID: UUID?, status: TaskStatus, successCriteria: String, artifactPath: String? = nil) {
        self.id = id
        self.productID = productID
        self.title = title
        self.ownerID = ownerID
        self.status = status
        self.successCriteria = successCriteria
        self.artifactPath = artifactPath
    }
}

public enum WorkItemStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case queued
    case running
    case waitingReview
    case waitingApproval
    case completed
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .queued: "排队中".L().L()
        case .running: "运行中".L().L()
        case .waitingReview: "待审查".L().L()
        case .waitingApproval: "待批准".L().L()
        case .completed: "已完成".L().L()
        case .failed: "失败".L().L()
        }
    }
}

public struct AgentWorkItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var taskID: UUID
    public var agentID: UUID
    public var status: WorkItemStatus
    public var promptPreview: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), productID: UUID, taskID: UUID, agentID: UUID, status: WorkItemStatus = .queued, promptPreview: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.taskID = taskID
        self.agentID = agentID
        self.status = status
        self.promptPreview = promptPreview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AgentMessageKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ctoGoalStarted
    case taskDispatched
    case workCompleted
    case reviewRequested
    case reviewCompleted
    case acceptanceCompleted
    case approvalRequested
    case approvalDecided
    case ctoLoopProgressed
    case employeeHandoff

    public var id: String { rawValue }
}

public enum AgentMessageStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case acknowledged
    case failed

    public var id: String { rawValue }
}

public enum AgentMessageReviewOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case passed
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .passed: "审查通过".L().L()
        case .rejected: "审查打回".L().L()
        }
    }
}

public enum BossDecisionCenterCopy {
    public static var sheetTitle: String { "老板决策中心".L().L() }
    public static var sheetSubtitle: String { "把所有需要老板确认的审批、风险任务和已处理记录集中在一处。".L().L() }
    public static var openTitle: String { "打开决策中心".L().L() }
    public static var pendingApprovalsSection: String { "待审批请求".L() }
    public static var riskTasksSection: String { "风险/阻塞任务".L() }
    public static var riskEventsSection: String { "风险事件".L() }
    public static var resolvedApprovalsSection: String { "已处理审批".L() }
    public static var emptyPendingApprovals: String { "当前没有待审批请求。".L().L() }
    public static var emptyRiskTasks: String { "当前没有风险或阻塞任务。".L().L() }
    public static var emptyRiskEvents: String { "近期没有需要老板关注的风险事件。".L().L() }
    public static var emptyResolvedApprovals: String { "还没有已处理的审批记录。".L().L() }
    public static var statTitle: String { "待我决策".L().L() }
    public static var summaryTitle: String { "待我决策".L().L() }
    public static var summaryEmpty: String { "当前没有需要你批准或驳回的事项。".L().L() }

    public static func summaryDetail(count: Int) -> String {
        count == 0
            ? "暂无审批或风险待处理，技术负责人可以继续后台推进。".L().L()
            : "有 ".L().L() + "\(count)" + " 项待你确认（审批请求 + 风险/阻塞任务）。".L().L()
    }
}

public enum AgentMessageFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pending
    case acknowledged
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部".L().L()
        case .pending: "待确认".L().L()
        case .acknowledged: "已读".L().L()
        case .failed: "失败".L().L()
        }
    }

    public func matches(_ envelope: AgentMessageEnvelope) -> Bool {
        switch self {
        case .all: true
        case .pending: envelope.status == .pending
        case .acknowledged: envelope.status == .acknowledged
        case .failed: envelope.status == .failed
        }
    }
}

public struct AgentMessageEnvelope: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var fromAgentID: UUID
    public var toAgentID: UUID?
    public var taskID: UUID?
    public var workItemID: UUID?
    public var approvalID: UUID?
    public var kind: AgentMessageKind
    public var status: AgentMessageStatus
    public var subject: String
    public var body: String
    public var createdAt: Date
    public var acknowledgedAt: Date?
    public var reviewOutcome: AgentMessageReviewOutcome?

    public init(
        id: UUID = UUID(),
        productID: UUID,
        fromAgentID: UUID,
        toAgentID: UUID? = nil,
        taskID: UUID? = nil,
        workItemID: UUID? = nil,
        approvalID: UUID? = nil,
        kind: AgentMessageKind,
        status: AgentMessageStatus = .pending,
        subject: String,
        body: String,
        createdAt: Date = Date(),
        acknowledgedAt: Date? = nil,
        reviewOutcome: AgentMessageReviewOutcome? = nil
    ) {
        self.id = id
        self.productID = productID
        self.fromAgentID = fromAgentID
        self.toAgentID = toAgentID
        self.taskID = taskID
        self.workItemID = workItemID
        self.approvalID = approvalID
        self.kind = kind
        self.status = status
        self.subject = subject
        self.body = body
        self.createdAt = createdAt
        self.acknowledgedAt = acknowledgedAt
        self.reviewOutcome = reviewOutcome
    }
}

public enum BranchPlanStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned
    case running
    case aggregating
    case needsReview
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .planned: "已计划".L().L()
        case .running: "并行中".L().L()
        case .aggregating: "汇总中".L().L()
        case .needsReview: "待审查".L().L()
        case .done: "完成".L().L()
        }
    }
}

public struct BranchPlanLane: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var agentID: UUID?
    public var taskID: UUID
    public var successCriteria: String

    public init(id: UUID = UUID(), title: String, agentID: UUID?, taskID: UUID, successCriteria: String) {
        self.id = id
        self.title = title
        self.agentID = agentID
        self.taskID = taskID
        self.successCriteria = successCriteria
    }
}

public struct BranchExecutionPlan: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var goal: String
    public var orchestratorID: UUID
    public var status: BranchPlanStatus
    public var lanes: [BranchPlanLane]
    public var aggregationTaskID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), productID: UUID, goal: String, orchestratorID: UUID, status: BranchPlanStatus = .planned, lanes: [BranchPlanLane], aggregationTaskID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.goal = goal
        self.orchestratorID = orchestratorID
        self.status = status
        self.lanes = lanes
        self.aggregationTaskID = aggregationTaskID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ReviewGateStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case reviewRequested
    case verificationPassed
    case verificationWarning
    case verificationFailed
    case accepted
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reviewRequested: "待审查".L().L()
        case .verificationPassed: "验收通过".L().L()
        case .verificationWarning: "验收警告".L().L()
        case .verificationFailed: "验收失败".L().L()
        case .accepted: "老板已验收".L().L()
        case .rejected: "老板已驳回".L().L()
        }
    }
}

public struct ReviewGateRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var taskID: UUID
    public var requesterID: UUID?
    public var reviewerID: UUID?
    public var status: ReviewGateStatus
    public var summary: String
    public var latestVerificationID: UUID?
    public var reportArtifactID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        productID: UUID,
        taskID: UUID,
        requesterID: UUID? = nil,
        reviewerID: UUID? = nil,
        status: ReviewGateStatus,
        summary: String,
        latestVerificationID: UUID? = nil,
        reportArtifactID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.productID = productID
        self.taskID = taskID
        self.requesterID = requesterID
        self.reviewerID = reviewerID
        self.status = status
        self.summary = summary
        self.latestVerificationID = latestVerificationID
        self.reportArtifactID = reportArtifactID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ArchitectureCheckStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case passed
    case warning
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .passed: "已闭合".L().L()
        case .warning: "待加强".L().L()
        case .failed: "未闭合".L().L()
        }
    }
}

public struct MultiAgentArchitectureCheck: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: ArchitectureCheckStatus
    public var detail: String

    public init(id: String, title: String, status: ArchitectureCheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct MultiAgentClosureTraceStep: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: ArchitectureCheckStatus
    public var detail: String

    public init(id: String, title: String, status: ArchitectureCheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct MultiAgentTaskGraphNode: Identifiable, Hashable, Sendable {
    public var id: String
    public var taskID: UUID
    public var role: String
    public var title: String
    public var ownerID: UUID?
    public var status: TaskStatus

    public init(id: String, taskID: UUID, role: String, title: String, ownerID: UUID?, status: TaskStatus) {
        self.id = id
        self.taskID = taskID
        self.role = role
        self.title = title
        self.ownerID = ownerID
        self.status = status
    }
}

public struct MultiAgentTaskGraphEdge: Identifiable, Hashable, Sendable {
    public var id: String
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var relation: String
    public var evidence: String
    public var status: ArchitectureCheckStatus

    public init(
        id: String,
        fromTaskID: UUID,
        toTaskID: UUID,
        relation: String,
        evidence: String,
        status: ArchitectureCheckStatus
    ) {
        self.id = id
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.relation = relation
        self.evidence = evidence
        self.status = status
    }
}

public struct MultiAgentTaskGraph: Hashable, Sendable {
    public var nodes: [MultiAgentTaskGraphNode]
    public var edges: [MultiAgentTaskGraphEdge]

    public init(nodes: [MultiAgentTaskGraphNode], edges: [MultiAgentTaskGraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct MultiAgentClosureTrace: Identifiable, Hashable, Sendable {
    public var id: String
    public var productID: UUID
    public var goal: String
    public var status: ArchitectureCheckStatus
    public var completionScore: Int
    public var taskIDs: [UUID]
    public var messageIDs: [UUID]
    public var approvalIDs: [UUID]
    public var artifactIDs: [UUID]
    public var verificationIDs: [UUID]
    public var reviewGateIDs: [UUID]
    public var steps: [MultiAgentClosureTraceStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        productID: UUID,
        goal: String,
        status: ArchitectureCheckStatus,
        completionScore: Int,
        taskIDs: [UUID],
        messageIDs: [UUID],
        approvalIDs: [UUID],
        artifactIDs: [UUID],
        verificationIDs: [UUID],
        reviewGateIDs: [UUID],
        steps: [MultiAgentClosureTraceStep],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.productID = productID
        self.goal = goal
        self.status = status
        self.completionScore = completionScore
        self.taskIDs = taskIDs
        self.messageIDs = messageIDs
        self.approvalIDs = approvalIDs
        self.artifactIDs = artifactIDs
        self.verificationIDs = verificationIDs
        self.reviewGateIDs = reviewGateIDs
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ApprovalStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case approved
    case rejected

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pending: "待审批".L().L()
        case .approved: "已批准".L().L()
        case .rejected: "已驳回".L().L()
        }
    }
}

public struct ApprovalRequest: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var taskID: UUID?
    public var requesterID: UUID?
    public var title: String
    public var reason: String
    public var status: ApprovalStatus
    public var createdAt: Date
    public var decidedAt: Date?

    public init(id: UUID = UUID(), productID: UUID, taskID: UUID? = nil, requesterID: UUID? = nil, title: String, reason: String, status: ApprovalStatus = .pending, createdAt: Date = Date(), decidedAt: Date? = nil) {
        self.id = id
        self.productID = productID
        self.taskID = taskID
        self.requesterID = requesterID
        self.title = title
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }
}

public enum ArtifactKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case source
    case rule
    case package
    case test
    case log
    case report
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .source: "源码".L().L()
        case .rule: "规则/记忆".L().L()
        case .package: "项目配置".L().L()
        case .test: "测试".L().L()
        case .log: "日志".L().L()
        case .report: "报告".L().L()
        case .other: "其他".L().L()
        }
    }
}

public struct ArtifactRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var taskID: UUID?
    public var kind: ArtifactKind
    public var title: String
    public var path: String
    public var summary: String
    public var createdAt: Date

    public init(id: UUID = UUID(), productID: UUID, taskID: UUID? = nil, kind: ArtifactKind, title: String, path: String, summary: String, createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.taskID = taskID
        self.kind = kind
        self.title = title
        self.path = path
        self.summary = summary
        self.createdAt = createdAt
    }
}

public enum VerificationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case passed
    case warning
    case failed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .passed: "通过".L().L()
        case .warning: "有警告".L().L()
        case .failed: "失败".L().L()
        }
    }
}

public struct VerificationRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var status: VerificationStatus
    public var title: String
    public var detail: String
    public var createdAt: Date

    public init(id: UUID = UUID(), productID: UUID, status: VerificationStatus, title: String, detail: String, createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.status = status
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

public enum ProductMemoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case decision
    case lesson
    case risk
    case handoff
    case summary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .decision: "决策".L().L()
        case .lesson: "经验".L().L()
        case .risk: "风险".L().L()
        case .handoff: "交接".L().L()
        case .summary: "摘要".L().L()
        }
    }
}

public struct ProductMemoryNote: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var productID: UUID
    public var agentID: UUID?
    public var kind: ProductMemoryKind
    public var title: String
    public var detail: String
    public var createdAt: Date

    public init(id: UUID = UUID(), productID: UUID, agentID: UUID? = nil, kind: ProductMemoryKind, title: String, detail: String, createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.agentID = agentID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}
