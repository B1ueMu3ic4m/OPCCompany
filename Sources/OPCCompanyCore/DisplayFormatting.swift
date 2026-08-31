import Foundation

extension Date {
    var opcDateTimeText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    var opcShortTimeText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}

func opcBackendCommandDisplayName(_ command: String) -> String {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "未配置".L() }
    let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? trimmed
    let lastPathComponent = URL(fileURLWithPath: firstToken).lastPathComponent
    let toolName = lastPathComponent.isEmpty ? firstToken : lastPathComponent
    switch toolName.lowercased() {
    case "codex": return "Codex"
    case "claude": return "Claude Code"
    case "gemini": return "Gemini"
    default: return toolName
    }
}

func opcBackendModelDisplayName(_ model: String) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "默认模型".L() : trimmed
}

func opcBackendCompactDisplay(command: String, model: String) -> String {
    "工具 ".L() + "\(opcBackendCommandDisplayName(command))" + " · " + "\(opcBackendModelDisplayName(model))"
}

func opcBackendCompactDisplay(type: BackendType, command: String, model: String) -> String {
    switch type {
    case .subscriptionCLI:
        return opcBackendCompactDisplay(command: command, model: model)
    case .api:
        return "接口模型 · ".L() + "\(opcBackendModelDisplayName(model))"
    case .local:
        let placeholder = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return placeholder.isEmpty ? "本地占位".L() : "本地占位 · \(placeholder)"
    }
}

func opcProductWorkspaceDisplayName(_ rootDirectory: String) -> String {
    let trimmed = rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "未设置本地工作区".L() }

    let expanded = NSString(string: trimmed).expandingTildeInPath
    let component = URL(fileURLWithPath: expanded).standardizedFileURL.lastPathComponent
    guard !component.isEmpty else { return "本地工作区已连接".L() }
    return "本地工作区：".L() + "\(component)"
}

/// 集中管理 Computer Use / UI 自动化使用的 SwiftUI accessibility identifier。
/// 这些 identifier 不是用户可见文案，但需要稳定不可重复，方便 a11y 自动化在 MacBook 内置屏的 a11y tree 上定位。
/// 所有视图改为引用本枚举常量；测试用 `OPCUIAutomationIdentifier.allCases` 做唯一性 / 非空 / 命名规则锁。
public enum OPCUIAutomationIdentifier: String, CaseIterable, Sendable {
    /// 真实终端自动交互循环面板根节点
    case terminalAutoInteractionLoopPanel = "OPCTerminalAutoInteractionLoopPanel"
    /// 真实终端自动循环：技术负责人任务上下文输入框
    case terminalAutoLoopTaskContextField = "OPCTerminalAutoLoopTaskContextField"
    /// 真实终端自动循环：最大轮次步进器
    case terminalAutoLoopMaxTurnsStepper = "OPCTerminalAutoLoopMaxTurnsStepper"
    /// 真实终端自动循环：启动受控循环按钮
    case terminalAutoLoopStartButton = "OPCTerminalAutoLoopStartButton"
    /// 真实终端自动循环：报告摘要文本块
    case terminalAutoLoopReportSummary = "OPCTerminalAutoLoopReportSummary"
    /// 技术维护审计中心区块根节点
    case maintenanceAuditCenter = "OPCMaintenanceAuditCenter"
    /// 技术维护审计中心：单条 VerificationRecord 卡片
    case maintenanceAuditRow = "OPCMaintenanceAuditRow"
    /// 维护产物档案中心区块根节点
    case maintenanceArtifactCenter = "OPCMaintenanceArtifactCenter"
    /// 维护产物档案中心：单条 ArtifactRecord 卡片
    case maintenanceArtifactRow = "OPCMaintenanceArtifactRow"
    /// 员工恢复建议面板
    case cliRecoveryAdvicePanel = "OPCCLIRecoveryAdvicePanel"
    /// 员工恢复建议摘要文本
    case cliRecoveryAdviceSummary = "OPCCLIRecoveryAdviceSummary"
    /// 员工恢复建议：单名员工手动重试按钮
    case cliRecoveryAdviceManualRetryButton = "OPCCLIRecoveryAdviceManualRetryButton"
    /// 持久终端可用性预览卡片
    case terminalWorkspaceHealthPreview = "OPCTerminalWorkspaceHealthPreview"
    /// 当前产品运行/测试数据清理预览卡片
    case runDataCleanupPreview = "OPCRunDataCleanupPreview"
    /// 命令行链路压测预检预览卡片
    case cliToolchainPreflightPreview = "OPCCLIToolchainPreflightPreview"
    /// 恢复默认公司状态预览卡片
    case defaultCompanyStatePreview = "OPCDefaultCompanyStatePreview"
    /// 多产品隔离体检预览卡片
    case productIsolationAuditPreview = "OPCProductIsolationAuditPreview"
    /// 命令行与工作区隔离预览卡片
    case cliRuntimeIsolationPreview = "OPCCLIRuntimeIsolationPreview"
    /// 命令行与工作区隔离完整明细开关
    case cliRuntimeIsolationDetailToggle = "OPCCLIRuntimeIsolationDetailToggle"
    /// 命令行与工作区隔离完整明细文本
    case cliRuntimeIsolationDetailPreview = "OPCCLIRuntimeIsolationDetailPreview"
    /// 真实终端工作区预览卡片
    case terminalWorkspacePlanPreview = "OPCTerminalWorkspacePlanPreview"
    /// 真实终端工作区完整明细开关
    case terminalWorkspacePlanDetailToggle = "OPCTerminalWorkspacePlanDetailToggle"
    /// 真实终端工作区完整明细文本
    case terminalWorkspacePlanDetailPreview = "OPCTerminalWorkspacePlanDetailPreview"
    /// 安全检查点预览卡片
    case safetyCheckpointPreview = "OPCSafetyCheckpointPreview"
    /// 本机诊断与日志策略预览卡片
    case localDiagnosticsPolicyPreview = "OPCLocalDiagnosticsPolicyPreview"
    /// 员工交接巡检预览卡片
    case employeeHandoffAuditPreview = "OPCEmployeeHandoffAuditPreview"
    /// 命令行作业幽灵巡检预览卡片
    case jobArchiveStaleAuditPreview = "OPCJobArchiveStaleAuditPreview"
    /// 运行证据分类巡检按钮
    case evidenceClassificationAuditButton = "OPCEvidenceClassificationAuditButton"
    /// 运行证据分类巡检预览卡片
    case evidenceClassificationAuditPreview = "OPCEvidenceClassificationAuditPreview"
    /// 维护数据增长巡检按钮
    case maintenanceDataPressureAuditButton = "OPCMaintenanceDataPressureAuditButton"
    /// 维护数据增长预览卡片
    case maintenanceDataPressurePreview = "OPCMaintenanceDataPressurePreview"
    /// 历史索引巡检预览卡片
    case historyIndexAuditPreview = "OPCHistoryIndexAuditPreview"
    /// 历史归档迁移预览卡片
    case historyArchiveMigrationPreview = "OPCHistoryArchiveMigrationPreview"
    /// 自动状态摘要重复清理按钮
    case autoCapturedSummaryDuplicateCleanupButton = "OPCAutoCapturedSummaryDuplicateCleanupButton"
    /// 自动状态摘要重复清理预览卡片
    case autoCapturedSummaryDuplicatePreview = "OPCAutoCapturedSummaryDuplicatePreview"
    /// 旧任务归属迁移按钮
    case legacyTaskProductMigrationButton = "OPCLegacyTaskProductMigrationButton"
    /// 旧任务归属迁移预览卡片
    case legacyTaskProductMigrationPreview = "OPCLegacyTaskProductMigrationPreview"
    /// 运行会话健康巡检预览卡片（按钮触发后就地刷新最近一次记录或显示中文空态兜底）
    case runtimeSessionHealthAuditPreview = "OPCRuntimeSessionHealthAuditPreview"
    /// 本地文件索引根白名单预览卡片
    case linkedLocalFileRootAllowlistPreview = "OPCLinkedLocalFileRootAllowlistPreview"
    /// 终端大厅二级详情 sheet 根节点
    case terminalHallDetailSheet = "OPCTerminalHallDetailSheet"
    /// 本地稳定性维护中心根节点
    case localMaintenanceCenterRoot = "OPCLocalMaintenanceCenterRoot"
    /// 本地维护详情：危险操作确认面板
    case localMaintenanceDangerousConfirmationPanel = "OPCLocalMaintenanceDangerousConfirmationPanel"
    /// 本地维护详情：危险操作确认词输入框
    case localMaintenanceDangerousConfirmationPhraseField = "OPCLocalMaintenanceDangerousConfirmationPhraseField"
    /// 本地维护详情：危险操作确认面板取消按钮
    case localMaintenanceDangerousConfirmationCancelButton = "OPCLocalMaintenanceDangerousConfirmationCancelButton"
    /// 本地维护详情：危险操作确认面板执行按钮
    case localMaintenanceDangerousConfirmationExecuteButton = "OPCLocalMaintenanceDangerousConfirmationExecuteButton"
    /// 终端大厅顶部运行概览卡片（默认可见，含运行/风险/审批/下一步建议简要文案）
    case terminalHallOverviewSummary = "OPCTerminalHallOverviewSummary"
    /// 终端大厅顶部：直接打开本地稳定性维护详情
    case terminalHallLocalMaintenanceHeaderTrigger = "OPCTerminalHallLocalMaintenanceHeaderTrigger"
    /// 终端大厅顶部：把当前提示词发送给当前产品可执行员工
    case terminalHallRunAllButton = "OPCTerminalHallRunAllButton"
    /// 终端大厅顶部：发送给员工终端的提示词输入框
    case terminalHallHeaderPromptField = "OPCTerminalHallHeaderPromptField"
    /// 本地维护详情：手动交互轮次的一行输入框
    case terminalManualREPLInputField = "OPCTerminalManualREPLInputField"
    /// 本地维护详情：发送一行手动交互输入
    case terminalManualREPLSendButton = "OPCTerminalManualREPLSendButton"
    /// 终端大厅：多员工架构体检与闭环 摘要工作台卡片（默认可见，展示完成度 / 检查项分布 / 最近闭环 / 主要操作）
    case advancedMaintenanceArchitectureSummaryCard = "OPCAdvancedMaintenanceArchitectureSummaryCard"
    /// 终端大厅：通信网关与手机指令 摘要工作台卡片（默认可见，展示通道与日志核心指标 + 主要操作）
    case advancedMaintenanceGatewaySummaryCard = "OPCAdvancedMaintenanceGatewaySummaryCard"
    /// 终端大厅：本地稳定性与命令行运维 摘要工作台卡片（默认可见，展示维护审计/产物计数 + 阈值压力 + 主要操作）
    case advancedMaintenanceLocalSummaryCard = "OPCAdvancedMaintenanceLocalSummaryCard"
    /// 摘要卡片主操作：运行多员工架构体检
    case advancedMaintenanceArchitectureAuditButton = "OPCAdvancedMaintenanceArchitectureAuditButton"
    /// 摘要卡片主操作：运行多员工架构闭环演练
    case advancedMaintenanceArchitectureClosureDrillButton = "OPCAdvancedMaintenanceArchitectureClosureDrillButton"
    /// 摘要卡片主操作：运行本地多产品隔离体检
    case advancedMaintenanceLocalIsolationAuditButton = "OPCAdvancedMaintenanceLocalIsolationAuditButton"
    /// 摘要卡片主操作：运行命令行链路预检
    case advancedMaintenanceLocalCLIPreflightButton = "OPCAdvancedMaintenanceLocalCLIPreflightButton"
    /// 摘要卡片右下「查看详情」按钮：打开多员工架构体检与闭环二级面板
    case advancedMaintenanceArchitectureDetailTrigger = "OPCAdvancedMaintenanceArchitectureDetailTrigger"
    /// 摘要卡片右下「查看详情」按钮：打开通信网关与手机指令二级面板
    case advancedMaintenanceGatewayDetailTrigger = "OPCAdvancedMaintenanceGatewayDetailTrigger"
    /// 摘要卡片右下「查看详情」按钮：打开本地稳定性与命令行运维二级面板
    case advancedMaintenanceLocalDetailTrigger = "OPCAdvancedMaintenanceLocalDetailTrigger"
    /// 终端大厅单员工卡片：刷新「运行前预检」按钮
    case terminalAgentCardRefreshPreflightButton = "OPCTerminalAgentCardRefreshPreflightButton"
    /// 终端大厅单员工卡片：写入命令行预检审计的「预检」按钮
    case terminalAgentCardPreflightButton = "OPCTerminalAgentCardPreflightButton"
    /// 终端大厅单员工卡片：把当前提示词发送到该员工真实终端的「运行」按钮
    case terminalAgentCardRunButton = "OPCTerminalAgentCardRunButton"
    /// 终端大厅单员工卡片：清空当前员工终端可见日志的按钮
    case terminalAgentCardClearLogButton = "OPCTerminalAgentCardClearLogButton"
    /// 终端大厅单员工卡片：把当前员工设为选中的「选中员工」按钮
    case terminalAgentCardSelectButton = "OPCTerminalAgentCardSelectButton"
    /// 本地维护详情：运行命令行与工作区隔离体检按钮
    case cliRuntimeIsolationAuditButton = "OPCCLIRuntimeIsolationAuditButton"
    /// 本地维护详情：启动真实终端工作区按钮
    case terminalWorkspaceStartButton = "OPCTerminalWorkspaceStartButton"
    /// 本地维护详情：刷新真实终端日志按钮
    case terminalWorkspaceRefreshLogsButton = "OPCTerminalWorkspaceRefreshLogsButton"
    /// 本地维护详情：运行持久终端可用性巡检按钮
    case terminalWorkspaceHealthAuditButton = "OPCTerminalWorkspaceHealthAuditButton"
    /// 本地维护详情：运行会话健康巡检按钮
    case runtimeSessionHealthAuditButton = "OPCRuntimeSessionHealthAuditButton"
    /// 本地维护详情:运行员工交接巡检按钮
    case employeeHandoffAuditButton = "OPCEmployeeHandoffAuditButton"
    /// 本地维护详情：运行命令行作业幽灵巡检按钮
    case jobArchiveStaleAuditButton = "OPCJobArchiveStaleAuditButton"
    /// 本地维护详情：运行历史索引巡检按钮
    case historyIndexAuditButton = "OPCHistoryIndexAuditButton"
    /// 本地维护详情：运行历史归档迁移按钮
    case historyArchiveMigrationButton = "OPCHistoryArchiveMigrationButton"
    /// 本地维护详情：恢复异常占用员工会话按钮
    case staleRuntimeSessionRecoveryButton = "OPCStaleRuntimeSessionRecoveryButton"
    /// 本地维护详情：清理当前产品运行/测试数据二次确认按钮
    case runDataCleanupConfirmButton = "OPCRunDataCleanupConfirmButton"
    /// 本地维护详情：恢复默认公司状态二次确认按钮
    case defaultCompanyStateConfirmButton = "OPCDefaultCompanyStateConfirmButton"
    /// 本地维护详情：回滚到最近安全检查点二次确认按钮
    case safetyCheckpointRollbackConfirmButton = "OPCSafetyCheckpointRollbackConfirmButton"

    public var rawIdentifier: String { rawValue }
}

public enum OPCVisibleInterfaceCopy {
    public static let intelligenceControlTitle = "智能控制 / 通信".L()
    public static let commandChannelTitle = "指令通道".L()
    public static let commandChannelHint = "向选中员工发送目标、约束或状态查询。".L()
    public static let companySceneTitle = "OPC 智能公司指挥舱".L()
    public static let companySceneSubtitle = "俯视剖面办公室沙盘 · 本地员工编队".L()
    public static let presalesTopicPlaceholder = "方案主题，例如：某客户智能知识库建设方案".L()
    public static let defaultAgentReportPromptText = "汇报你的角色、当前状态和下一步建议。".L()
    public static let defaultTerminalPromptPlaceholder = defaultAgentReportPromptText

    public static let defaultVisibleTexts = [
        intelligenceControlTitle,
        commandChannelTitle,
        commandChannelHint,
        companySceneTitle,
        companySceneSubtitle,
        presalesTopicPlaceholder,
        defaultAgentReportPromptText
    ]
}
