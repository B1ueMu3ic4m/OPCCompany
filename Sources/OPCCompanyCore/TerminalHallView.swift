import SwiftUI

/// 终端大厅默认信息架构：摘要化工作台。
///
/// 设计准则（不可回退到「默认折叠」）：
/// - 架构体检 / 通信网关 / 本地稳定性三个模块**默认可见**摘要卡片；不再用 DisclosureGroup 把整块功能藏起来。
/// - 每张摘要卡片只展示：标题 + 状态 capsule + 2-3 个核心指标 chip + 1-2 行最近摘要 + 主要操作 + 「查看详情」。
/// - 长报告 / 完整配置面板（`MultiAgentArchitectureAuditCenter` / `CommunicationGatewayCommandCenter` / `LocalMaintenanceCenter`）
///   通过 `.sheet(item:)` 二级面板按需打开，**不**在主视图内联展开。
/// - Computer Use / 人工 a11y 锚点稳定可达：摘要卡片本体 + 「查看详情」按钮各自登记 enum case。
///
/// 该信息架构由 `terminalHallShowsSummaryWorkbenchInsteadOfCollapsedDisclosure` 等测试守门。
private enum TerminalHallDetail: String, Identifiable {
    case architecture
    case gateway
    case localMaintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .architecture: "多员工架构体检与闭环".L()
        case .gateway: "通信网关与手机指令".L()
        case .localMaintenance: "本地稳定性与命令行运维".L()
        }
    }
}

/// 终端大厅顶部常驻「外部调用 / 额度提示」中文文案。
///
/// 设计目的（不可静默删除）：终端大厅默认提示词输入框旁必须有一行常驻可见的成本/外部调用提醒，避免用户
/// 误把「预检」(本地干跑) 与「运行 / 运行全部」(真实命令行调用，按外部模型额度计费) 当作同等代价的动作。
/// 由 `terminalHallExternalCallNoticeAlwaysVisibleNearPrompt` 守门测试保证它常驻可见且文案完整。
internal let terminalHallExternalCallNotice = "「运行全部」与每张员工卡的「运行」会真实调用 Claude Code / Codex / Gemini CLI 等外部命令行后端，按外部模型额度计费；「预检」只生成本地审计，不调用真实模型，不消耗额度。".L()

struct TerminalHallView: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var prompt = OPCVisibleInterfaceCopy.defaultAgentReportPromptText
    /// 多员工「运行全部」二次确认门控。
    ///
    /// 设计契约（由 `terminalHallRunAllMultiAgentRequiresTokenConfirmation` 守门）：
    /// - 任何会同时把当前提示词发送给 ≥2 名可执行员工的运行操作都必须先弹出确认。
    /// - 旧契约只在「默认汇报提示词」时拦截；改造后**不再以提示词内容**为触发条件——任意非默认提示词、
    ///   即使用户改写过，仍然会同时消耗多名员工外部模型额度，需要二次确认。
    @State private var confirmsMultiAgentRunAll = false
    // 终端大厅顶部「本地维护」按钮、摘要卡「查看详情」按钮、辅助功能动作、整卡 onTapGesture
    // 全部统一写入 `presentedDetail`，确保只有一个 `.sheet(item:)` modifier 接管所有详情路由。
    // 历史回归：曾在同一视图挂第二个 isPresented 形式的 sheet 专跑本地维护，但 SwiftUI（macOS）同一视图
    // 挂双 sheet 会让其中一个静默失效——Computer Use 真机点击观察到本地维护详情打不开就是这种互斥。
    @State private var presentedDetail: TerminalHallDetail?

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 480), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("终端大厅".L())
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(CompanyTheme.ink)
                        Text("\(store.selectedProduct?.name ?? "当前产品")" + " · 每个员工一块独立终端。".L())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                    }

                    Spacer()

                    Button {
                        presentedDetail = .localMaintenance
                    } label: {
                        Label("本地维护".L(), systemImage: "wrench.and.screwdriver.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("打开本地维护详情".L())
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallLocalMaintenanceHeaderTrigger.rawValue)
                    .accessibilityHint("打开本地稳定性与命令行运维详情。".L())
                    // Computer Use 路径下，对带 Label(systemImage:) 的按钮发 AXPress 偶发只拿到焦点不触发闭包；
                    // 显式登记同名 AXAction 与按钮闭包写同一 presentedDetail case，提供 AXPress 失败时的命名兜底。
                    .accessibilityAction(named: "打开本地维护详情".L()) {
                        presentedDetail = .localMaintenance
                    }

                    Button {
                        if requiresRunAllTokenConfirmation {
                            confirmsMultiAgentRunAll = true
                        } else {
                            runAllExecutableAgents()
                        }
                    } label: {
                        Label("运行全部".L(), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CompanyTheme.accent)
                    .disabled(store.executableAgents.isEmpty || store.executableAgents.allSatisfy { store.isRunning(agentID: $0.id) })
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallRunAllButton.rawValue)
                    .accessibilityLabel("运行全部员工终端".L())
                    .accessibilityHint("把当前提示词发送给当前产品所有可执行且未运行员工；没有可执行员工或员工都在运行时禁用".L())
                }

                TextField("发送给员工终端的提示词".L(), text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .lineLimit(1...2)
                    .background(CompanyTheme.inputSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallHeaderPromptField.rawValue)
                    .accessibilityLabel("发送给员工终端的提示词".L())
                    .accessibilityHint("填写后会被「运行全部」按钮发送给当前产品的可执行员工".L())

                // 常驻外部调用 / 额度提示。贴在输入框正下方，与下方员工卡的「预检」「运行」二元语义对照。
                // 不允许折叠或仅在 hover 时浮现：若用户把这条提示挪到 popover/help 里，
                // `terminalHallExternalCallNoticeAlwaysVisibleNearPrompt` 会失败。
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.warning)
                    Text(terminalHallExternalCallNotice)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(CompanyTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("运行将真实调用外部命令行后端".L())
                .accessibilityHint(terminalHallExternalCallNotice)
            }
            .padding(16)
            .background {
                CommandPanelBackground(accent: CompanyTheme.blue)
            }

            Divider().overlay(CompanyTheme.line.opacity(0.78))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TerminalHallOverviewSummary()

                    MultiAgentArchitectureSummaryCard(presentedDetail: $presentedDetail)
                    CommunicationGatewaySummaryCard(presentedDetail: $presentedDetail)
                    LocalMaintenanceSummaryCard(presentedDetail: $presentedDetail)

                    LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.selectedProductAgents) { agent in
                        TerminalAgentCard(agent: agent, prompt: prompt)
                    }
                    }
                }
                .padding(16)
            }
        }
        .background(CommandSurfaceBackground())
        .sheet(item: $presentedDetail) { detail in
            TerminalHallDetailSheet(detail: detail)
                .environmentObject(store)
        }
        .confirmationDialog("确认运行全部员工终端".L(), isPresented: $confirmsMultiAgentRunAll, titleVisibility: .visible) {
            Button("发送给 ".L() + "\(runnableAgentCount)" + " 名员工".L()) {
                runAllExecutableAgents()
            }
            Button("取消".L(), role: .cancel) {}
        } message: {
            Text("即将把当前提示词同时发送给 " + "\(runnableAgentCount)" + " 名员工终端，会真实调用员工命令行后端并消耗 " + "\(runnableAgentCount)" + " 份外部模型额度。")
        }
    }

    private var runnableAgentCount: Int {
        store.executableAgents.filter { !store.isRunning(agentID: $0.id) }.count
    }

    /// 「运行全部」是否需要弹二次确认。
    ///
    /// 唯一触发条件：当前可立即运行的员工 ≥ 2 名（即一次点击会同时消耗多份外部模型额度）。
    /// 不再以「提示词等于默认汇报文案」作为门槛——任何提示词只要触达多名员工就值得让用户主动确认数量。
    private var requiresRunAllTokenConfirmation: Bool {
        runnableAgentCount > 1
    }

    private func runAllExecutableAgents() {
        store.runAllExecutableAgents(prompt: prompt)
    }
}

private struct TerminalHallOverviewSummary: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        // 与下方 SummaryCard 信息架构对齐：标题 + 5 个 MetricChip + 1 行 next-step。
        // 旧的「terminalHallOverviewSummaryText() 4 行纯文本」保留供聊天/复制/审计兜底，
        // view 层不再直接渲染（避免标题重复 + 提示行重复 SummaryCard 已默认可见的事实）。
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("终端大厅运行状态".L())
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                Text(store.selectedProduct?.name ?? "当前产品".L())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 6) {
                ForEach(store.terminalHallOverviewMetrics(), id: \.title) { metric in
                    MetricChip(text: "\(metric.title) \(metric.value)", color: chipColor(for: metric.kind))
                }
                Spacer(minLength: 0)
            }

            Text(store.terminalHallOverviewNextStepText())
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallOverviewSummary.rawValue)
        .accessibilityLabel("终端大厅运行状态概览".L())
    }

    private func chipColor(for kind: TerminalHallOverviewMetric.Kind) -> Color {
        switch kind {
        case .neutral: CompanyTheme.blue
        case .ok: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .danger: CompanyTheme.red
        }
    }
}

// MARK: - 摘要工作台卡片：架构体检与闭环

private struct MultiAgentArchitectureSummaryCard: View {
    @EnvironmentObject private var store: CompanyStore
    @Binding var presentedDetail: TerminalHallDetail?

    var body: some View {
        let checks = store.selectedProductArchitectureChecks
        let passed = checks.filter { $0.status == .passed }.count
        let warning = checks.filter { $0.status == .warning }.count
        let failed = checks.filter { $0.status == .failed }.count
        let score = store.selectedProductArchitectureCompletionScore

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("多员工架构体检与闭环".L(), systemImage: "gearshape.2")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusCapsule(text: "完成度 ".L() + "\(score)" + "%", color: scoreColor(score))
            }

            HStack(spacing: 8) {
                MetricChip(text: "已闭合 ".L() + "\(passed)", color: CompanyTheme.green)
                MetricChip(text: "待加强 ".L() + "\(warning)", color: CompanyTheme.warning)
                MetricChip(text: "未闭合 ".L() + "\(failed)", color: CompanyTheme.red)
                MetricChip(text: "检查项 ".L() + "\(checks.count)", color: CompanyTheme.blue)
            }

            if let trace = store.latestSelectedProductClosureTrace {
                Text("最近闭环：\(trace.goal)\(" · ".L())\(trace.completionScore)% · 消息 \(trace.messageIDs.count) · 产物 \(trace.artifactIDs.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("最近闭环：暂无；点击「运行体检」即可生成首次记录。".L())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
            }

            HStack(spacing: 8) {
                Button {
                    store.runMultiAgentArchitectureAudit()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("运行体检".L(), systemImage: "checklist.checked")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureAuditButton.rawValue)
                .accessibilityLabel("运行多员工架构体检".L())
                .accessibilityHint("为当前产品运行多员工架构体检，写入维护审计并把选中员工切换到技术负责人".L())

                Button {
                    _ = store.runMultiAgentArchitectureClosureDrill()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("闭环演练".L(), systemImage: "arrow.trianglehead.2.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureClosureDrillButton.rawValue)
                .accessibilityLabel("运行多员工架构闭环演练".L())
                .accessibilityHint("为当前产品运行闭环演练，生成闭环轨迹并把选中员工切换到技术负责人".L())

                Spacer()

                Button {
                    presentedDetail = .architecture
                } label: {
                    Label("查看详情".L(), systemImage: "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureDetailTrigger.rawValue)
                .accessibilityLabel("查看多员工架构体检详情".L())
                .accessibilityHint("打开二级面板：完整检查项 / 闭环演练摘要 / 重做摘要 / 闭环详情。".L())
                .accessibilityAction(named: "查看多员工架构体检详情".L()) {
                    presentedDetail = .architecture
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.border.opacity(0.45), lineWidth: 0.8)
        )
        // `.contain` 让卡片本身是容器组，子按钮（含 DetailTrigger）保留各自的 a11y identifier；
        // 不加这一行的话 macOS AX tree 会把容器的 identifier 反映到子按钮，Computer Use 点不到详情按钮。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceArchitectureSummaryCard.rawValue)
        .accessibilityLabel("多员工架构体检与闭环 摘要工作台".L())
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: CompanyTheme.green
        case 50..<80: CompanyTheme.warning
        default: CompanyTheme.red
        }
    }
}

// MARK: - 摘要工作台卡片：通信网关与手机指令

private struct CommunicationGatewaySummaryCard: View {
    @EnvironmentObject private var store: CompanyStore
    @Binding var presentedDetail: TerminalHallDetail?

    var body: some View {
        let channels = store.selectedProductCommunicationChannels
        let enabled = channels.filter(\.isEnabled).count
        let inbound = channels.filter { $0.isEnabled && $0.commandsEnabled && $0.kind.supportsInboundCommand }.count
        let logs = store.selectedProductCommunicationLogs

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("通信网关与手机指令".L(), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusCapsule(text: enabled > 0 ? "已启用 " + "\(enabled)" + "/" + "\(channels.count)" : "未启用".L(), color: enabled > 0 ? CompanyTheme.green : CompanyTheme.muted)
            }

            HStack(spacing: 8) {
                MetricChip(text: "通道 ".L() + "\(channels.count)", color: CompanyTheme.blue)
                MetricChip(text: "可入站 ".L() + "\(inbound)", color: CompanyTheme.accent)
                MetricChip(text: "通信日志 ".L() + "\(logs.count)", color: CompanyTheme.warning)
            }

            if let latest = logs.first {
                let directionText = latest.direction == .inbound ? "入站".L() : "出站".L()
                Text("最近通信：".L() + "\(directionText)" + " · ".L() + "\(latest.title)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
            } else {
                Text("最近通信：暂无；先点「生成手机汇报」可触发首条出站日志。".L())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
            }

            HStack(spacing: 8) {
                Button {
                    store.sendTeamLeadReportThroughGateway()
                } label: {
                    Label("生成手机汇报".L(), systemImage: "doc.text.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)

                Button {
                    store.testCommunicationGatewayChannels()
                } label: {
                    Label("测试通道".L(), systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    presentedDetail = .gateway
                } label: {
                    Label("查看详情".L(), systemImage: "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceGatewayDetailTrigger.rawValue)
                .accessibilityLabel("查看通信网关与手机指令详情".L())
                .accessibilityHint("打开二级面板：通道配置 / 手机指令模拟 / 完整通信日志。".L())
                .accessibilityAction(named: "查看通信网关与手机指令详情".L()) {
                    presentedDetail = .gateway
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.border.opacity(0.45), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceGatewaySummaryCard.rawValue)
        .accessibilityLabel("通信网关与手机指令 摘要工作台".L())
    }
}

// MARK: - 摘要工作台卡片：本地稳定性与命令行运维

private struct LocalMaintenanceSummaryCard: View {
    @EnvironmentObject private var store: CompanyStore
    @Binding var presentedDetail: TerminalHallDetail?

    var body: some View {
        let maintenanceVR = store.selectedProductMaintenanceVerifications
        let maintenanceAR = store.selectedProductMaintenanceArtifacts
        let recentVR = store.selectedProductRecentMaintenanceVerifications.first
        let vrThreshold = CompanyStore.maintenanceVerificationGrowthAdvisoryThreshold
        let arThreshold = CompanyStore.maintenanceArtifactGrowthAdvisoryThreshold
        let pressureExceeds = maintenanceVR.count >= vrThreshold || maintenanceAR.count >= arThreshold

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("本地稳定性与命令行运维".L(), systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusCapsule(
                    text: pressureExceeds ? "维护数据增长触线".L() : "维护审计 " + "\(maintenanceVR.count)" + " 条",
                    color: pressureExceeds ? CompanyTheme.warning : CompanyTheme.blue
                )
            }

            HStack(spacing: 8) {
                MetricChip(text: "维护审计 ".L() + "\(maintenanceVR.count)" + "/" + "\(vrThreshold)", color: maintenanceVR.count >= vrThreshold ? CompanyTheme.warning : CompanyTheme.blue)
                MetricChip(text: "维护产物 ".L() + "\(maintenanceAR.count)" + "/" + "\(arThreshold)", color: maintenanceAR.count >= arThreshold ? CompanyTheme.warning : CompanyTheme.green)
                MetricChip(text: "可用巡检 9 项".L(), color: CompanyTheme.accent)
            }

            if let recent = recentVR {
                Text("最近维护：".L() + "\(recent.title) · \(recent.status.title)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
            } else {
                Text("最近维护：暂无；点击「运行隔离体检」生成第一条审计。".L())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
            }

            HStack(spacing: 8) {
                Button {
                    store.runProductIsolationAudit()
                } label: {
                    Label("运行隔离体检".L(), systemImage: "square.stack.3d.down.right.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalIsolationAuditButton.rawValue)
                .accessibilityLabel("运行本地隔离体检".L())
                .accessibilityHint("为当前产品运行多产品隔离体检，写入维护审计并刷新本地稳定性摘要".L())

                Button {
                    store.runCLIToolchainPreflightForSelectedProduct()
                } label: {
                    Label("命令行预检".L(), systemImage: "terminal.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalCLIPreflightButton.rawValue)
                .accessibilityLabel("运行命令行链路预检".L())
                .accessibilityHint("为当前产品运行命令行链路干跑预检，不调用真实模型任务".L())

                Spacer()

                Button {
                    presentedDetail = .localMaintenance
                } label: {
                    Label("查看详情".L(), systemImage: "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalDetailTrigger.rawValue)
                .accessibilityLabel("查看本地稳定性与命令行运维详情".L())
                .accessibilityHint("打开二级面板：完整巡检 / 真实终端工作区 / 自动循环 / 维护审计中心 / 维护产物档案 / 运行证据分类巡检 / 维护数据增长巡检。".L())
                .accessibilityAction(named: "查看本地稳定性与命令行运维详情".L()) {
                    presentedDetail = .localMaintenance
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.border.opacity(0.45), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            presentedDetail = .localMaintenance
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalSummaryCard.rawValue)
        .accessibilityLabel("本地稳定性与命令行运维 摘要工作台".L())
        .accessibilityAction(named: "查看本地维护详情".L()) {
            presentedDetail = .localMaintenance
        }
    }
}

// MARK: - 摘要卡片复用控件

private struct StatusCapsule: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct MetricChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 员工卡顶部 CLI 健康徽章 chip。
/// 默认不渲染（store accessor 返回 nil 时根本不进入此视图）；只有需要技术负责人注意的状态浮现。
private struct TerminalAgentCardHealthBadgeChip: View {
    let badge: TerminalAgentCardHealthBadge

    var body: some View {
        Text(badge.title)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .help(badge.detail ?? badge.title)
            .accessibilityLabel("命令行健康状态：".L() + "\(badge.title)")
            .accessibilityHint(badge.detail ?? "")
    }

    private var color: Color {
        switch badge.severity {
        case .info: CompanyTheme.blue
        case .warning: CompanyTheme.warning
        case .danger: CompanyTheme.red
        }
    }
}

// MARK: - 二级详情面板（按需 sheet 打开，长报告/完整配置不在主视图内联）

private struct TerminalHallDetailSheet: View {
    let detail: TerminalHallDetail
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(detail.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("关闭".L(), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(CompanyTheme.surfaceRaised.opacity(0.55))

            Divider()

            ScrollView {
                Group {
                    switch detail {
                    case .architecture:
                        MultiAgentArchitectureAuditCenter()
                    case .gateway:
                        CommunicationGatewayCommandCenter()
                    case .localMaintenance:
                        LocalMaintenanceCenter()
                    }
                }
                .padding(16)
            }
        }
        // MacBook 主屏（13" Air 1280×800 / 14" Pro 1512×982）安全帧：
        // 不再用 1080×720 死硬最小值——那个值会卡住 13" 主屏，sheet 要么开不出来要么剪掉关闭按钮。
        // 改成 min(720,560) + ideal(1080,720)：13" 主屏可下行至 720×560 仍完整可见，
        // 大显示器开 sheet 仍按 1080×720 理想尺寸呈现，与改造前的视觉目标一致。
        .frame(minWidth: 720, idealWidth: 1080, minHeight: 560, idealHeight: 720)
        .background(CommandSurfaceBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalHallDetailSheet.rawValue)
        .accessibilityLabel("\(detail.title)" + "详情面板")
    }
}

// MARK: - 员工终端卡片（保持不变）

private struct TerminalAgentCard: View {
    @EnvironmentObject private var store: CompanyStore
    let agent: CompanyAgent
    let prompt: String
    @State private var preflightText = ""

    private var isRunning: Bool {
        store.isRunning(agentID: agent.id)
    }

    private var logText: String {
        store.visibleTerminalLog(for: agent.id)
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                CharacterBadge(agent: agent, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(agent.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CompanyTheme.ink)
                            .lineLimit(1)
                        StatusDot(status: agent.status)
                    }

                    Text(agent.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            // 卡片顶部紧凑摘要（不折叠、不隐藏）：
            // - 第 1 行：后端单行（工具 / 模型 / 推理强度）+ 任务注入说明 info icon。
            // - 第 2 行：会话续跑摘要（仅在该员工来源有 CLI 交互画像时渲染），产品层详情走 .help() tooltip。
            // - 第 3 行：本轮任务摘要单行（前 60 字 + …）。
            // 旧的 commandPreview 多行字符串保留供运行前预检 / 终端日志 / 聊天会话日志复用，
            // 不再在卡片顶部直接渲染（避免「运行方式」与上方 backendSummary 重复 + lineLimit(2) 截断）。
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.visibleBackendSummary(for: agent))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanyTheme.accent)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let badge = store.terminalAgentCardHealthBadge(for: agent.id) {
                        TerminalAgentCardHealthBadgeChip(badge: badge)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(CompanyTheme.muted)
                        .help(store.terminalHallCardInjectionHint())
                        .accessibilityLabel("任务注入说明".L())
                        .accessibilityHint(store.terminalHallCardInjectionHint())
                }

                if let longSession = store.terminalHallCardLongSessionLine(for: agent) {
                    Text(longSession)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .help(store.terminalHallCardLongSessionDetail(for: agent) ?? longSession)
                        .accessibilityLabel(longSession)
                        .accessibilityHint(store.terminalHallCardLongSessionDetail(for: agent) ?? "")
                }

                if let taskDigest = store.terminalHallCardTaskDigestLine(prompt: prompt) {
                    Text(taskDigest)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(CompanyTheme.muted)
                        .italic()
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            // 运行前预检：常驻可见紧凑面板。
            // - header：标题徽章 + icon-only `arrow.clockwise` 刷新按钮（中文 help / accessibilityLabel / accessibilityHint）。
            // - body：preflightText 始终渲染；首帧 .onAppear 自动生成；prompt / agent 切换时自动重算。
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("运行前预检".L())
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(CompanyTheme.warning)

                    Spacer()

                    Button {
                        refreshPreflightText()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(CompanyTheme.muted)
                    .help("刷新运行前预检".L())
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAgentCardRefreshPreflightButton.rawValue)
                    .accessibilityLabel("刷新 ".L() + "\(agent.displayName)" + " 运行前预检".L())
                    .accessibilityHint("基于当前提示词与员工配置重新生成运行前预检文本。".L())
                }

                Text(preflightText.isEmpty ? "运行前预检准备中…".L() : preflightText)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(CompanyTheme.terminalBackground.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            }
            .onAppear {
                if preflightText.isEmpty {
                    refreshPreflightText()
                }
            }
            .onChange(of: prompt) { _, _ in
                refreshPreflightText()
            }
            .onChange(of: agent.id) { _, _ in
                refreshPreflightText()
            }

            // 日志区按状态自适应高度：员工准备中 → 100pt + 中文等待提示；
            // 运行中或有日志输出 → 180pt（比改造前的固定 248pt 减少 27%）。
            // 高度变化由 SwiftUI 自动 animate；占位文字、清空按钮等控件全部保留。
            ScrollView {
                Text(store.terminalAgentCardIsIdle(agentID: agent.id)
                     ? store.terminalAgentCardLogPlaceholder(for: agent.id)
                     : logText)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(store.terminalAgentCardIsIdle(agentID: agent.id) ? CompanyTheme.muted : CompanyTheme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: store.terminalAgentCardLogHeight(for: agent.id))
            .animation(.easeOut(duration: 0.2), value: store.terminalAgentCardIsIdle(agentID: agent.id))
            .background(CompanyTheme.terminalBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CompanyTheme.inputBorder.opacity(0.45), lineWidth: 0.8)
            )

            HStack(spacing: 8) {
                // 「选中」按钮简化为 icon-only：保留显式入口给 Computer Use 与精确点击；
                // 同时卡片整体加 .contentShape + .onTapGesture 兜底（见下方），减少用户必须找到按钮的成本。
                Button {
                    store.selectAgent(agent.id)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .buttonStyle(.bordered)
                .help("选中员工".L())
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAgentCardSelectButton.rawValue)
                .accessibilityLabel("选中 ".L() + "\(agent.displayName)")
                .accessibilityHint("把当前员工设为选中，会高亮卡片并把右侧检查器切换到该员工。".L())

                // 「预检」按钮：本地干跑，安全。
                // 视觉：低对比度 bordered + 中性灰前景 + 「干跑」副标，与下方 borderedProminent + 加重图标的「运行」按钮形成
                // 二元安全/危险对照，避免用户把两个按钮当作同一类操作而误点。
                Button {
                    store.recordCLIPreflight(agentID: agent.id, prompt: prompt)
                } label: {
                    Label("预检 · 干跑".L(), systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(CompanyTheme.muted)
                .disabled(agent.role == .boss)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAgentCardPreflightButton.rawValue)
                .accessibilityLabel("写入 ".L() + "\(agent.displayName)" + " 命令行预检审计".L())
                .accessibilityHint("基于当前提示词为该员工写入一次命令行预检审计；不调用真实模型，不消耗外部额度；老板角色禁用。".L())

                // 「运行」按钮：真实调用员工命令行后端，按外部模型额度计费。
                // 视觉：borderedProminent + accent tint + 「真实调用」副标 + bolt 图标，明示真实外部成本动作。
                Button {
                    store.runAgent(agentID: agent.id, prompt: prompt)
                } label: {
                    Label(isRunning ? "运行中".L() : "运行 · 真实调用".L(), systemImage: isRunning ? "hourglass" : "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .disabled(isRunning || agent.role == .boss)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAgentCardRunButton.rawValue)
                .accessibilityLabel(isRunning ? "\(agent.displayName)" + " 运行中".L() : "运行 ".L() + "\(agent.displayName)" + " 终端".L())
                .accessibilityHint("把当前提示词发送给该员工的真实终端席位，会真实调用员工命令行后端并消耗外部模型额度；员工正在运行或为老板角色时禁用。".L())

                Spacer()

                Button {
                    store.clearTerminalLog(for: agent.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(CompanyTheme.muted)
                .help("清空日志".L())
                .disabled(!store.terminalAgentCardHasClearableLog(for: agent.id))
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAgentCardClearLogButton.rawValue)
                .accessibilityLabel("清空 ".L() + "\(agent.displayName)" + " 终端日志".L())
                .accessibilityHint("清空当前员工终端的可见输出日志，不影响运行中任务和员工持续会话。".L())
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(12)
        .background {
            CommandPanelBackground(accent: store.selectedAgentID == agent.id ? CompanyTheme.selected : CompanyTheme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(store.selectedAgentID == agent.id ? CompanyTheme.selectedStroke.opacity(0.58) : CompanyTheme.border.opacity(0.50), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
        // 卡片整体可点击选中：SwiftUI 中内部 Button 的 tap 高优先级，不会被父 onTapGesture 抢走；
        // 用户点击空白处即可选中员工，减少必须找「选中」按钮的成本。.contentShape 让 padding 区也响应点击。
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            store.selectAgent(agent.id)
        }
        .accessibilityAction(named: "选中员工".L()) {
            store.selectAgent(agent.id)
        }
    }

    private func refreshPreflightText() {
        preflightText = store.terminalAgentCardPreflightSummary(for: agent.id, prompt: prompt)
    }
}
