import SwiftUI

struct CommandCenterView: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var selectedSection: CommandCenterSection = .overview
    @State private var showDecisionCenter = false
    @State private var showDeliveryCenter = false
    @State private var showReportCenter = false

    private var product: ProductWorkspace? {
        store.selectedProduct
    }

    private var openTasks: [CompanyTask] {
        store.selectedProductOpenTasks
    }

    private var riskEvents: [CompanyEvent] {
        // 老板总控台只看真实业务/审批/交付风险；技术维护类（命令行健康预警等）通过
        // selectedProductBossRiskEvents 过滤前缀剔除，避免挤占老板首页 prefix(5) / prefix(3) 容量。
        // 技术维护「全量事件流」入口是 EventLogView（员工 inspector「事件」tab）直读 store.events，
        // 不依赖全量风险 accessor。InspectorPanel / OperationsSuiteView 经轮 5/6/8 收敛后老板专属
        // 视图（recentRiskCount / BossDecisionCenterSheet.riskEvents）也已切到本过滤 accessor。
        store.selectedProductBossRiskEvents
    }

    private var runningAgents: [CompanyAgent] {
        store.selectedProductAgents.filter { store.runningAgentIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metrics
                sectionPicker

                switch selectedSection {
                case .overview:
                    overviewContent
                case .decisions:
                    bossDecisionContent
                case .reports:
                    bossReportsContent
                }
            }
            .padding(18)
        }
        .background(CommandSurfaceBackground())
        .sheet(isPresented: $showDecisionCenter) {
            BossDecisionCenterSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showDeliveryCenter) {
            DeliveryAcceptanceCenterSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showReportCenter) {
            BossReportCenterSheet()
                .environmentObject(store)
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CommandCenterSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.system(size: 12, weight: .heavy))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(selectedSection == section ? CompanyTheme.selectedDeep : CompanyTheme.secondaryInk)
                            .background(
                                selectedSection == section ? CompanyTheme.selected : CompanyTheme.panelRaised.opacity(0.58),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                executiveSummaryPanel
                    .frame(maxWidth: .infinity)
                decisionSnapshotPanel
                    .frame(maxWidth: .infinity)
            }

            deliverySnapshotPanel

            ownerNextStepPanel
        }
    }

    private var bossDecisionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            decisionSnapshotPanel
            riskAndAcceptancePanel
        }
    }

    private var bossReportsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            bossReportSnapshotPanel
            if let report = product?.importReport {
                ImportHandoffPanel(report: report)
            } else {
                HandoffEmptyPanel()
            }
            deliverySnapshotPanel
            companyProcessPanel
            employeeProgressPanel
            HStack(alignment: .top, spacing: 14) {
                taskPanel
                    .frame(maxWidth: .infinity)
                agentPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var bossReportSnapshotPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "老板汇报中心".L())
                Spacer()
                Text("\(store.selectedProductBossReportMessages.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(CompanyTheme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.blue.opacity(0.14), in: Capsule())
            }
            if let report = store.selectedProductBossReportMessages.first {
                Text(report.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
            } else {
                EmptyCommandLine(text: "还没有当前产品汇报。打开汇报中心可生成老板报告、交接摘要和健康体检。".L())
            }

            Button {
                showReportCenter = true
            } label: {
                Label("打开老板汇报中心".L(), systemImage: "doc.richtext.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.20), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("老板总览".L())
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text(product?.name ?? "当前产品".L())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CompanyTheme.blue)
                    .lineLimit(1)
                if let root = product?.rootDirectory {
                    Text(root)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    ProductChip(text: product?.stage.title ?? "未选择".L(), color: CompanyTheme.blue)
                    ProductChip(text: product?.status.title ?? "待命".L(), color: CompanyTheme.accent)
                }
                Text("老板看目标、结果、风险和需要确认的审批；执行细节由技术负责人与员工推进。".L())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .background {
            CommandPanelBackground(accent: CompanyTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CompanyTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
            CommandMetricTile(title: "产品状态".L(), value: bossStatusTitle, systemImage: "gauge.with.dots.needle.67percent", color: bossStatusColor)
            CommandMetricTile(title: "完成进度".L(), value: "\(completionPercent)%", systemImage: "chart.line.uptrend.xyaxis", color: CompanyTheme.accent)
            CommandMetricTile(title: "待老板决策".L(), value: "\(bossDecisionCount)", systemImage: "hand.raised.fill", color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
            CommandMetricTile(title: "团队运行".L(), value: "\(runningAgents.count)/\(store.selectedProductAgents.count)", systemImage: "person.3.fill", color: runningAgents.isEmpty ? CompanyTheme.muted : CompanyTheme.blue)
        }
    }

    private var ctoBriefingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "技术负责人今日汇报".L())
            Text(latestCTOBriefing)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CompanyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                BossSummaryPill(title: "阶段".L(), value: product?.stage.title ?? "未知".L(), color: CompanyTheme.blue)
                BossSummaryPill(title: "未完成".L(), value: "\(openTasks.count)", color: CompanyTheme.accent)
                BossSummaryPill(title: "风险".L(), value: "\(riskEvents.count)", color: riskEvents.isEmpty ? CompanyTheme.green : CompanyTheme.red)
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.accent.opacity(0.20), lineWidth: 1)
        )
    }

    private var executiveSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "今日结论".L())
                    Text(latestCTOBriefing)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CompanyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(5)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 9) {
                    Text("\(completionPercent)%")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(CompanyTheme.warning)
                    Text(product?.stage.title ?? "未选择阶段".L())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    ProgressView(value: Double(completedTaskCount), total: Double(max(store.selectedProductTasks.count, 1)))
                        .tint(CompanyTheme.warning)
                    Text(productProgressSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }
                .frame(width: 210, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                BossSummaryPill(title: "未完成".L(), value: "\(openTasks.count)", color: CompanyTheme.accent)
                BossSummaryPill(title: "待决策".L(), value: "\(bossDecisionCount)", color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
                BossSummaryPill(title: "风险".L(), value: "\(riskEvents.count)", color: riskEvents.isEmpty ? CompanyTheme.green : CompanyTheme.red)
            }
        }
        .padding(16)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.warning.opacity(0.18), lineWidth: 1)
        )
    }

    private var bossActionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "老板只需要做的事".L())
            BossActionRow(systemImage: "message.fill", title: "给技术负责人下达目标".L(), detail: "直接用右侧输入框发一句话，技术负责人会拆任务和调员工。".L())
            BossActionRow(systemImage: "hand.raised.fill", title: "批准或驳回风险".L(), detail: "只有涉及风险、权限、交付方向时才需要你处理。".L())
            BossActionRow(systemImage: "doc.text.magnifyingglass", title: "看汇报和交付物".L(), detail: "确认进度、结果、问题和下一步，不需要手动点后台能力。".L())
            BossActionRow(systemImage: "building.2.fill", title: "看公司现场".L(), detail: "用公司场景观察团队状态，不需要进入技术负责人后台操作。".L())
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.warning.opacity(0.20), lineWidth: 1)
        )
    }

    private var ownerNextStepPanel: some View {
        HStack(spacing: 10) {
            OwnerNextStepItem(
                systemImage: "message.fill",
                title: "下目标".L(),
                detail: "右侧输入一句话给技术负责人。".L(),
                color: CompanyTheme.warning
            )
            OwnerNextStepItem(
                systemImage: "hand.raised.fill",
                title: "批风险".L(),
                detail: bossDecisionCount == 0 ? "当前无需处理。".L() : "\(bossDecisionCount)" + " 项待你确认。",
                color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning
            )
            OwnerNextStepItem(
                systemImage: "doc.text.magnifyingglass",
                title: "看交付".L(),
                detail: "交付物和验收放在汇报页。".L(),
                color: CompanyTheme.blue
            )
            OwnerNextStepItem(
                systemImage: "building.2.fill",
                title: "看现场".L(),
                detail: "公司场景只看员工状态。".L(),
                color: CompanyTheme.accent
            )
        }
    }

    private var productProgressPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "产品进度".L())
            HStack(alignment: .firstTextBaseline) {
                Text("\(completionPercent)%")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product?.stage.title ?? "未选择阶段".L())
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    Text(productProgressSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            ProgressView(value: Double(completedTaskCount), total: Double(max(store.selectedProductTasks.count, 1)))
                .tint(CompanyTheme.warning)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                BossSummaryPill(title: "已完成".L(), value: "\(completedTaskCount)", color: CompanyTheme.green)
                BossSummaryPill(title: "推进中".L(), value: "\(activeTaskCount)", color: CompanyTheme.blue)
                BossSummaryPill(title: "待处理".L(), value: "\(bossDecisionCount)", color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.warning.opacity(0.22), lineWidth: 1)
        )
    }

    private var companyProcessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "公司流程状态".L())
            Text("按真实公司分工展示：老板决策、技术负责人调度、员工执行、系统保障。这里只看结果，不把后台能力当成老板按钮。".L())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                BackgroundCapabilityRow(
                    title: "老板决策".L(),
                    status: bossDecisionCount == 0 ? "无需处理".L() : "\(bossDecisionCount)" + " 项待批",
                    detail: "只处理方向、风险、权限和最终交付确认。".L(),
                    color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning
                )
                BackgroundCapabilityRow(
                    title: "技术负责人调度".L(),
                    status: openTasks.isEmpty ? "无待派任务".L() : "\(openTasks.count)" + " 项跟进中",
                    detail: "目标拆解、任务分配、多分支汇总由技术负责人负责。".L(),
                    color: openTasks.isEmpty ? CompanyTheme.green : CompanyTheme.accent
                )
                BackgroundCapabilityRow(
                    title: "员工执行".L(),
                    status: "\(activeTaskCount)" + " 项在推进".L(),
                    detail: "工程、设计、审查、资料任务进入员工队列并回传结果。".L(),
                    color: activeTaskCount == 0 ? CompanyTheme.muted : CompanyTheme.blue
                )
                BackgroundCapabilityRow(
                    title: "交付验收".L(),
                    status: store.selectedProductDeliveryVerifications.isEmpty ? "暂无验收".L() : "\(store.selectedProductDeliveryVerifications.count)" + " 条验收",
                    detail: "测试、审查、交付物会汇总成老板可读结论。".L(),
                    color: riskEvents.isEmpty ? CompanyTheme.green : CompanyTheme.red
                )
                BackgroundCapabilityRow(
                    title: "通信汇报".L(),
                    status: store.selectedProductCommunicationChannels.isEmpty ? "未接外部通道".L() : "\(store.selectedProductCommunicationChannels.count)" + " 个通道",
                    detail: "这是汇报和远程指令链路，不属于技术负责人业务后台。".L(),
                    color: store.selectedProductCommunicationChannels.isEmpty ? CompanyTheme.muted : CompanyTheme.blue
                )
                BackgroundCapabilityRow(
                    title: "系统保障".L(),
                    status: systemGuardStatus,
                    detail: "本地安全和命令行链路只能做检查、记录和提示，不能替老板授权。".L(),
                    color: systemGuardStatus == "正常".L() ? CompanyTheme.green : CompanyTheme.warning
                )
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var decisionSnapshotPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "待我处理".L())
                Spacer()
                Text("待决策 " + "\(bossDecisionCount)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning).opacity(0.14), in: Capsule())
            }

            if store.selectedProductPendingApprovals.isEmpty && store.selectedProductRiskTasks.isEmpty {
                EmptyCommandLine(text: "当前没有需要老板处理的事项。技术负责人可以继续后台推进。".L())
            } else {
                ForEach(store.commandCenterPendingApprovals) { approval in
                    BossApprovalRequestRow(approval: approval)
                }
                if let overflow = store.commandCenterPendingApprovalsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
                ForEach(store.commandCenterDecisionRiskTasks) { task in
                    BossTaskApprovalRow(task: task, ownerName: agentName(task.ownerID))
                }
                if let overflow = store.commandCenterDecisionRiskTasksOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }

            Button {
                showDecisionCenter = true
            } label: {
                Label(BossDecisionCenterCopy.openTitle, systemImage: "tray.full.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(bossDecisionCount == 0 ? CompanyTheme.panelRaised : CompanyTheme.warning)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning).opacity(0.22), lineWidth: 1)
        )
    }

    private var deliverySnapshotPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "最近交付与验收".L())
                Spacer()
                Text("\(store.selectedProductDeliveryArtifacts.count + store.selectedProductDeliveryVerifications.count)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(CompanyTheme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.blue.opacity(0.14), in: Capsule())
            }
            if store.selectedProductDeliveryArtifacts.isEmpty && store.selectedProductDeliveryVerifications.isEmpty {
                EmptyCommandLine(text: "还没有新的交付物。员工完成任务后，这里会显示产物、测试和验收结论。".L())
            } else {
                ForEach(store.commandCenterRecentDeliveryVerifications) { verification in
                    BossDecisionRow(title: verification.title, detail: verification.detail, color: verification.status == .passed ? CompanyTheme.green : CompanyTheme.warning)
                }
                if let overflow = store.commandCenterDeliveryVerificationsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
                ForEach(store.commandCenterRecentDeliveryArtifacts) { artifact in
                    BossDecisionRow(title: artifact.title, detail: artifact.summary, color: CompanyTheme.blue)
                }
                if let overflow = store.commandCenterDeliveryArtifactsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }

            Button {
                showDeliveryCenter = true
            } label: {
                Label(DeliveryAcceptanceCenterCopy.openTitle, systemImage: "shippingbox.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.20), lineWidth: 1)
        )
    }

    private var employeeProgressPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "员工工作进度".L())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(store.selectedProductAgents) { agent in
                    AgentProgressCard(
                        agent: agent,
                        tasks: tasks(for: agent),
                        queueItems: queueItems(for: agent),
                        isRunning: store.runningAgentIDs.contains(agent.id)
                    )
                }
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "任务推进".L())
            if openTasks.isEmpty {
                EmptyCommandLine(text: "当前没有未完成任务。".L())
            } else {
                ForEach(store.commandCenterOpenTasks) { task in
                    TaskSignalRow(task: task, ownerName: agentName(task.ownerID))
                }
                if let overflow = store.commandCenterOpenTasksOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var agentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "员工信号".L())
            ForEach(store.selectedProductAgents) { agent in
                AgentSignalCard(agent: agent, isRunning: store.runningAgentIDs.contains(agent.id))
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var riskAndAcceptancePanel: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "风险与批准".L())
                if store.selectedProductRiskTasks.isEmpty && riskEvents.isEmpty {
                    EmptyCommandLine(text: "当前没有需要老板批准的风险。".L())
                } else {
                    ForEach(store.commandCenterRiskPanelTasks) { task in
                        BossTaskApprovalRow(task: task, ownerName: agentName(task.ownerID))
                    }
                    if let overflow = store.commandCenterRiskPanelTasksOverflow() {
                        OPCListOverflowFooter(summary: overflow.summary)
                    }
                    ForEach(store.commandCenterRiskPanelEvents) { event in
                        EventSignalRow(event: event)
                    }
                    if let overflow = store.commandCenterRiskPanelEventsOverflow() {
                        OPCListOverflowFooter(summary: overflow.summary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "验收标准".L())
                ForEach(store.commandCenterAcceptanceCriteriaTasks) { task in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CompanyTheme.ink)
                            .lineLimit(1)
                        Text(task.successCriteria)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
                }
                if let overflow = store.commandCenterAcceptanceCriteriaTasksOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var totalProductTasks: Int {
        max(store.selectedProductTasks.count, 1)
    }

    private var completedTaskCount: Int {
        store.selectedProductTasks.filter { $0.status == .done }.count
    }

    private var activeTaskCount: Int {
        store.selectedProductTasks.filter { [.assigned, .running, .waiting, .needsReview].contains($0.status) }.count
    }

    private var completionPercent: Int {
        Int((Double(completedTaskCount) / Double(totalProductTasks) * 100).rounded())
    }

    private var productProgressSummary: String {
        let total = store.selectedProductTasks.count
        if total == 0 { return "当前产品还没有任务，先让技术负责人拆解目标。".L() }
        return "\(completedTaskCount)" + "/" + "\(total)" + " 个任务完成，".L() + "\(openTasks.count)" + " 个任务仍需推进。".L()
    }

    private var systemGuardStatus: String {
        let safetyOK = store.safetyCheckpointListText(limit: 1).contains("最近安全检查点".L())
        let cliOK = store.cliToolchainPreflightText().contains("通过".L())
        if safetyOK && cliOK { return "正常".L() }
        if safetyOK || cliOK { return "部分就绪".L() }
        return "需检查".L()
    }

    private var bossDecisionCount: Int {
        store.bossDecisionCount
    }

    private var bossStatusTitle: String {
        if bossDecisionCount > 0 { return "待决策".L() }
        if !riskEvents.isEmpty { return "有风险".L() }
        if !runningAgents.isEmpty { return "推进中".L() }
        if openTasks.isEmpty { return "可验收".L() }
        return "正常".L()
    }

    private var bossStatusColor: Color {
        switch bossStatusTitle {
        case "待决策".L(): CompanyTheme.warning
        case "有风险".L(): CompanyTheme.red
        case "可验收".L(): CompanyTheme.green
        case "推进中".L(): CompanyTheme.blue
        default: CompanyTheme.accent
        }
    }

    private var latestCTOBriefing: String {
        let ctoMessages = store.messages(for: store.ctoID, in: store.selectedProductID, includingLegacyGlobal: false)
        if let message = ctoMessages.last(where: { $0.author == .system || $0.author == .agent }) {
            return String(message.text.prefix(460))
        }
        return "技术负责人已接管当前产品。老板只需要提出目标、查看结果，并处理真正需要你确认的风险。".L()
    }

    private func agentName(_ id: UUID?) -> String {
        guard let id else { return "未分配".L() }
        return store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    private func tasks(for agent: CompanyAgent) -> [CompanyTask] {
        store.selectedProductTasks.filter { $0.ownerID == agent.id }
    }

    private func queueItems(for agent: CompanyAgent) -> [AgentWorkItem] {
        store.selectedProductWorkQueue.filter { $0.agentID == agent.id }
    }
}

struct BossSummaryPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BossActionRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CompanyTheme.warning)
                .frame(width: 28, height: 28)
                .background(CompanyTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct OwnerNextStepItem: View {
    let systemImage: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CompanyTheme.panel.opacity(0.90), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct BossDecisionRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BossReportCenterSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            ScrollView {
                BossReportCenter()
                    .environmentObject(store)
                    .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 520)
        .background(CommandSurfaceBackground())
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("老板汇报中心".L())
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text("\(store.selectedProduct?.name ?? "当前产品")" + "：生成当前产品汇报、交接摘要和健康体检，最近记录只按当前产品显示。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button("关闭".L()) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
        }
    }
}

struct BossDecisionCenterSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    pendingApprovalsSection
                    riskTasksSection
                    riskEventsSection
                    resolvedApprovalsSection
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 480)
        .background(CommandSurfaceBackground())
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BossDecisionCenterCopy.sheetTitle)
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text("\(store.selectedProduct?.name ?? "当前产品")：\(BossDecisionCenterCopy.sheetSubtitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button("关闭".L()) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
        }
    }

    private var pendingApprovalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: BossDecisionCenterCopy.pendingApprovalsSection,
                count: store.selectedProductPendingApprovals.count,
                color: CompanyTheme.warning
            )

            if store.selectedProductPendingApprovals.isEmpty {
                EmptyCommandLine(text: BossDecisionCenterCopy.emptyPendingApprovals)
            } else {
                ForEach(store.selectedProductPendingApprovals) { approval in
                    BossApprovalRequestRow(approval: approval)
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.warning.opacity(0.22), lineWidth: 1)
        )
    }

    private var riskTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: BossDecisionCenterCopy.riskTasksSection,
                count: store.selectedProductRiskTasks.count,
                color: CompanyTheme.red
            )

            if store.selectedProductRiskTasks.isEmpty {
                EmptyCommandLine(text: BossDecisionCenterCopy.emptyRiskTasks)
            } else {
                ForEach(store.selectedProductRiskTasks) { task in
                    BossTaskApprovalRow(task: task, ownerName: agentName(task.ownerID))
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.red.opacity(0.22), lineWidth: 1)
        )
    }

    private var resolvedApprovalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: BossDecisionCenterCopy.resolvedApprovalsSection,
                count: store.selectedProductResolvedApprovals.count,
                color: CompanyTheme.green
            )

            if store.selectedProductResolvedApprovals.isEmpty {
                EmptyCommandLine(text: BossDecisionCenterCopy.emptyResolvedApprovals)
            } else {
                ForEach(store.bossDecisionCenterResolvedApprovals) { approval in
                    BossApprovalDecidedRow(approval: approval)
                }
                if let overflow = store.bossDecisionCenterResolvedApprovalsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.green.opacity(0.22), lineWidth: 1)
        )
    }

    private var riskEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: BossDecisionCenterCopy.riskEventsSection,
                count: store.selectedProductBossRiskEvents.count,
                color: CompanyTheme.red
            )

            if store.selectedProductBossRiskEvents.isEmpty {
                EmptyCommandLine(text: BossDecisionCenterCopy.emptyRiskEvents)
            } else {
                ForEach(store.bossDecisionCenterRiskEvents) { event in
                    EventSignalRow(event: event)
                }
                if let overflow = store.bossDecisionCenterRiskEventsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.red.opacity(0.22), lineWidth: 1)
        )
    }

    private func sectionHeaderRow(title: String, count: Int, color: Color) -> some View {
        HStack(alignment: .center) {
            SectionHeader(title: title)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.14), in: Capsule())
        }
    }

    private func agentName(_ id: UUID?) -> String {
        guard let id else { return "未分配".L() }
        return store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }
}

struct BossApprovalDecidedRow: View {
    let approval: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: approval.status == .approved ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(badgeColor)
                Text(approval.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(text: approval.status.title, color: badgeColor)
            }

            Text(approval.reason)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)

            if let decidedAt = approval.decidedAt {
                Text("已处理：" + "\(decidedAt.opcDateTimeText)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
            }
        }
        .padding(10)
        .background(badgeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(badgeColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var badgeColor: Color {
        approval.status == .approved ? CompanyTheme.green : CompanyTheme.red
    }
}

struct BossApprovalRequestRow: View {
    @EnvironmentObject private var store: CompanyStore
    let approval: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.warning)
                Text(approval.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(text: approval.status.title, color: CompanyTheme.warning)
            }

            Text(approval.reason)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button {
                    store.decideApproval(approval.id, approved: true)
                } label: {
                    Label("批准".L(), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.green)

                Button {
                    store.decideApproval(approval.id, approved: false)
                } label: {
                    Label("驳回".L(), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.red)
            }
        }
        .padding(10)
        .background(CompanyTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.warning.opacity(0.20), lineWidth: 1)
        )
    }
}

struct BossTaskApprovalRow: View {
    @EnvironmentObject private var store: CompanyStore
    let task: CompanyTask
    let ownerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(task.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(text: task.status.title, color: statusColor)
            }

            Text("负责人：".L() + "\(ownerName)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.muted)

            Text(task.successCriteria)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    store.approveTaskRisk(task.id)
                } label: {
                    Label("批准继续".L(), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.green)

                Button {
                    store.rejectTaskRisk(task.id)
                } label: {
                    Label("驳回重做".L(), systemImage: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.red)

                Button {
                    store.requestCTOReview(for: task.id)
                } label: {
                    Label("问技术负责人".L(), systemImage: "person.text.rectangle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(statusColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.20), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch task.status {
        case .done: CompanyTheme.green
        case .failed, .blocked: CompanyTheme.red
        case .needsApproval: CompanyTheme.warning
        case .running, .needsReview: CompanyTheme.accent
        default: CompanyTheme.muted
        }
    }
}

struct BackgroundCapabilityRow: View {
    let title: String
    let status: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer(minLength: 0)
                Text(status)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AgentProgressCard: View {
    let agent: CompanyAgent
    let tasks: [CompanyTask]
    let queueItems: [AgentWorkItem]
    let isRunning: Bool

    private var doneCount: Int {
        tasks.filter { $0.status == .done }.count
    }

    private var activeCount: Int {
        tasks.filter { [.assigned, .running, .waiting, .needsReview].contains($0.status) }.count
    }

    private var blockedCount: Int {
        tasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }.count
    }

    private var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(doneCount) / Double(tasks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CharacterBadge(agent: agent, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    Text("\(agent.role.title) · \(opcBackendCompactDisplay(type: agent.backend.type, command: agent.backend.command, model: agent.backend.model))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                StatusPill(text: isRunning ? "运行中".L() : agent.status.title, color: signalColor)
            }

            ProgressView(value: progress)
                .tint(signalColor)

            HStack(spacing: 8) {
                MiniProgressPill(title: "完成".L(), value: "\(doneCount)", color: CompanyTheme.green)
                MiniProgressPill(title: "推进".L(), value: "\(activeCount)", color: CompanyTheme.blue)
                MiniProgressPill(title: "异常".L(), value: "\(blockedCount)", color: blockedCount == 0 ? CompanyTheme.muted : CompanyTheme.red)
                MiniProgressPill(title: "队列".L(), value: "\(queueItems.count)", color: queueItems.isEmpty ? CompanyTheme.muted : CompanyTheme.warning)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(signalColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var signalColor: Color {
        if blockedCount > 0 { return CompanyTheme.red }
        if isRunning || activeCount > 0 { return CompanyTheme.accent }
        if !tasks.isEmpty && doneCount == tasks.count { return CompanyTheme.green }
        return CompanyTheme.muted
    }
}

struct MiniProgressPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct WorkflowMapView: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var showProductMessageCenter = false

    private var productName: String {
        store.selectedProduct?.name ?? "当前产品".L()
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                header
                workflow
                messageFlow
                taskStatusBoard
            }
            .padding(18)
            .frame(minWidth: 1060, alignment: .leading)
        }
        .background(CommandSurfaceBackground())
        .sheet(isPresented: $showProductMessageCenter) {
            AgentMessageCenterSheet(scope: .product)
                .environmentObject(store)
        }
    }

    private var messageFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "消息流 / 协作链路".L())
                Spacer()
                Text("待确认 " + "\(store.selectedProductPendingAgentMessages.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
                Button {
                    showProductMessageCenter = true
                } label: {
                    Label(AgentMessageCenterCopy.viewAllTitle, systemImage: "tray.full.fill")
                }
                .buttonStyle(.bordered)
            }
            Text("老板目标 → 技术负责人拆解 → 员工执行 → 审查验收 → 老板审批".L())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CompanyTheme.muted)

            if store.selectedProductAgentMessages.isEmpty {
                EmptyCommandLine(text: "还没有协作消息，先让技术负责人启动目标或派发任务，员工/审查/审批的消息会按时间排在这里。".L())
            } else {
                VStack(spacing: 6) {
                    ForEach(store.workflowMapRecentAgentMessages) { message in
                        AgentMessageRow(
                            message: message,
                            fromName: agentName(message.fromAgentID),
                            toName: message.toAgentID.map(agentName) ?? "公开".L(),
                            taskTitle: taskTitle(for: message.taskID)
                        )
                    }
                }
                if let overflow = store.workflowMapMessageFlowOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private func agentName(_ id: UUID) -> String {
        store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.tasks.first { $0.id == id }?.title
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("任务流程图".L())
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text("\(productName)" + " 的智能公司生产线，从老板目标到验收交付。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
            }
            Spacer()
        }
    }

    private var workflow: some View {
        HStack(alignment: .center, spacing: 12) {
            WorkflowNodeView(
                title: "老板目标".L(),
                subtitle: "一句话描述产品方向".L(),
                systemImage: "person.fill",
                color: CompanyTheme.accent,
                statusText: "输入".L()
            )
            WorkflowConnector(color: CompanyTheme.accent)
            WorkflowNodeView(
                title: "技术负责人拆解".L(),
                subtitle: "拆任务、定标准、派员工".L(),
                systemImage: "brain.head.profile",
                color: CompanyTheme.blue,
                statusText: store.ctoAgent?.status.title ?? "待命".L()
            )
            WorkflowConnector(color: CompanyTheme.blue)
            VStack(spacing: 12) {
                WorkflowNodeView(
                    title: "产品与设计".L(),
                    subtitle: "规格、界面、交互、动效".L(),
                    systemImage: "square.grid.2x2.fill",
                    color: CompanyTheme.blue,
                    statusText: statusText(for: .uiDesigner)
                )
                WorkflowNodeView(
                    title: "工程实现".L(),
                    subtitle: "代码修改、命令执行、日志".L(),
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    color: CompanyTheme.accent,
                    statusText: statusText(for: .codeEngineer)
                )
                WorkflowNodeView(
                    title: "测试验证".L(),
                    subtitle: "可复现检查与失败回放".L(),
                    systemImage: "checkmark.seal.fill",
                    color: CompanyTheme.warning,
                    statusText: statusText(for: .tester)
                )
            }
            WorkflowConnector(color: CompanyTheme.warning)
            WorkflowNodeView(
                title: "审查员验收".L(),
                subtitle: "风险、缺陷、是否可交付".L(),
                systemImage: "shield.lefthalf.filled",
                color: CompanyTheme.purple,
                statusText: statusText(for: .reviewer)
            )
            WorkflowConnector(color: CompanyTheme.purple)
            WorkflowNodeView(
                title: "老板批准".L(),
                subtitle: "看结果、批风险、定下一步".L(),
                systemImage: "signature",
                color: CompanyTheme.warning,
                statusText: "最终决定".L()
            )
        }
        .padding(18)
        .background {
            CommandPanelBackground(accent: CompanyTheme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var taskStatusBoard: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach([TaskStatus.planned, .running, .needsReview, .needsApproval, .done], id: \.self) { status in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle()
                            .fill(statusColor(status))
                            .frame(width: 8, height: 8)
                        Text(status.title)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(CompanyTheme.ink)
                        Spacer()
                    }
                    let tasks = store.workflowMapTasks(for: status)
                    if tasks.isEmpty {
                        Text("暂无".L())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(tasks) { task in
                            Text(task.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CompanyTheme.ink)
                                .lineLimit(2)
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if let overflow = store.workflowMapTaskStatusBoardOverflow(for: status) {
                            OPCListOverflowFooter(summary: overflow.summary)
                        }
                    }
                }
                .frame(width: 190, alignment: .topLeading)
                .padding(12)
                .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private func statusText(for role: AgentRole) -> String {
        let statuses = store.selectedProductAgents.filter { $0.role == role }.map { $0.status.title }
        return statuses.first ?? "待配置".L()
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .done: CompanyTheme.green
        case .failed, .blocked: CompanyTheme.red
        case .running, .needsReview: CompanyTheme.accent
        case .needsApproval: CompanyTheme.warning
        default: CompanyTheme.muted
        }
    }
}

struct ImportHandoffPanel: View {
    let report: ProjectImportReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "现有项目接手".L())
                Spacer()
                Text(report.importedAt, style: .date)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
            }

            Text(report.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                HandoffColumn(title: "规则/记忆".L(), items: report.ruleFiles, empty: "未发现".L())
                HandoffColumn(title: "智能工具".L(), items: report.detectedTools, empty: "未发现".L())
                HandoffColumn(title: "项目线索".L(), items: report.projectFiles, empty: "未发现".L())
            }
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.26), lineWidth: 1)
        )
    }
}

struct HandoffEmptyPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "现有项目接手".L())
            Text("还没有导入正在开发的产品项目。导入后这里会显示 Codex、Claude Code、Gemini 等规则/记忆文件和项目线索，技术负责人会按原上下文接手。".L())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct HandoffColumn: View {
    let title: String
    let items: [String]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted.opacity(0.75))
            } else {
                FlowLayout(items: items.prefix(5).map { $0 })
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct CommandMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.ink)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CompanyTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.20), lineWidth: 1)
        )
    }
}

struct AgentSignalCard: View {
    let agent: CompanyAgent
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            CharacterBadge(agent: agent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Text("\(agent.role.title) · \(opcBackendCompactDisplay(type: agent.backend.type, command: agent.backend.command, model: agent.backend.model))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(isRunning ? "运行".L() : agent.status.title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(isRunning ? CompanyTheme.accent : statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((isRunning ? CompanyTheme.accent : statusColor).opacity(0.14), in: Capsule())
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch agent.status {
        case .failed, .blocked: CompanyTheme.red
        case .done: CompanyTheme.green
        case .coding, .typing, .thinking, .reviewing: CompanyTheme.accent
        default: CompanyTheme.muted
        }
    }
}

struct TaskSignalRow: View {
    let task: CompanyTask
    let ownerName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(task.status.title)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(statusColor)
                }
                Text("负责人：".L() + "\(ownerName)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
                Text(task.successCriteria)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch task.status {
        case .done: CompanyTheme.green
        case .failed, .blocked: CompanyTheme.red
        case .running, .needsReview: CompanyTheme.accent
        case .needsApproval: CompanyTheme.warning
        default: CompanyTheme.muted
        }
    }
}

struct EventSignalRow: View {
    let event: CompanyEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                Text(event.kind.title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.red)
            }
            Text(event.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
        }
        .padding(10)
        .background(CompanyTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkflowNodeView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(statusText)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.13), in: Capsule())
            }

            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(width: 154, height: 126, alignment: .topLeading)
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.30), lineWidth: 1)
        )
    }
}

struct WorkflowConnector: View {
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color.opacity(0.45))
                .frame(width: 34, height: 2)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color.opacity(0.75))
        }
        .frame(width: 46)
    }
}

struct ProductChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct EmptyCommandLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CompanyTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CommandPanelBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            CompanyTheme.panel.opacity(0.96)
            LinearGradient(
                colors: [
                    accent.opacity(0.10),
                    Color.clear,
                    CompanyTheme.selected.opacity(0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct CommandSurfaceBackground: View {
    var body: some View {
        ZStack {
            MainWorkspaceBackdrop()
            LinearGradient(
                colors: [
                    CompanyTheme.blue.opacity(0.018),
                    Color.clear,
                    CompanyTheme.selected.opacity(0.010)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            OrthogonalMicroGrid()
                .stroke(CompanyTheme.ink.opacity(0.012), lineWidth: 0.55)
        }
        .ignoresSafeArea()
    }
}

struct OrthogonalMicroGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 42
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}
