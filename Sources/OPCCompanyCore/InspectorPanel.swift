import SwiftUI

private enum InspectorStatsCopy {
    static func taskStatsText(doneCount: Int, activeCount: Int, blockedCount: Int, queueCount: Int) -> String {
        let head = "完成 ".L()
        let mid1 = " · 推进 ".L()
        let mid2 = " · 异常 ".L()
        let tail = " · 队列 ".L()
        return head + "\(doneCount)" + mid1 + "\(activeCount)" + mid2 + "\(blockedCount)" + tail + "\(queueCount)"
    }
}


struct InspectorPanel: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var messageText = ""
    @State private var selectedTab: InspectorTab = .chat
    @FocusState private var isMessageFieldFocused: Bool

    var body: some View {
        Group {
            if store.selectedAgent?.role == .boss {
                BossControlPanel(selectedTab: $selectedTab)
            } else {
                VStack(spacing: 0) {
                    header

                    InspectorSegmentedTabs(selectedTab: $selectedTab)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)

                    ShellHairline()

                    Group {
                        switch selectedTab {
                        case .chat:
                            chatView
                        case .tasks:
                            TaskBoardView()
                        case .events:
                            EventLogView()
                        case .profile:
                            AgentProfileView()
                        case .terminal:
                            TerminalPanel()
                        }
                    }
                }
            }
        }
        .background(InspectorBackdrop())
        .onChange(of: store.mainWorkspace) { _, workspace in
            if workspace != .terminalHall, selectedTab == .terminal {
                selectedTab = .chat
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let agent = store.selectedAgent {
                    CharacterBadge(agent: agent, size: 46, isSelected: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(OPCVisibleInterfaceCopy.intelligenceControlTitle)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(CompanyTheme.selected.opacity(0.82))
                            .textCase(.uppercase)
                        Text(agent.displayName)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(CompanyTheme.ink)
                        Text(agent.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CompanyTheme.secondaryInk)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(OPCVisibleInterfaceCopy.intelligenceControlTitle)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(CompanyTheme.selected.opacity(0.82))
                            .textCase(.uppercase)
                        Text("未选择对象".L())
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(CompanyTheme.ink)
                        Text("从办公室沙盘或左侧名单选择员工".L())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CompanyTheme.secondaryInk)
                    }
                }

                Spacer()

                if let agent = store.selectedAgent {
                    StatusDot(status: agent.status)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                InspectorTelemetryCell(label: "对象".L(), value: telemetryObject)
                InspectorTelemetryCell(label: "状态".L(), value: telemetryStatus)
                InspectorTelemetryCell(label: "产品".L(), value: telemetryProduct)
                InspectorTelemetryCell(label: "来源".L(), value: telemetryBackend)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            CompanyTheme.inspectorPanel
                .overlay(
                    LinearGradient(
                        colors: [
                            CompanyTheme.inspectorViolet.opacity(0.42),
                            .clear,
                            CompanyTheme.selected.opacity(0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        let messages = selectedAgentChatMessages
                        if messages.isEmpty {
                            EmptyCommandLine(text: "当前产品下还没有和该员工的对话。发送指令后，只会记录到当前产品。".L())
                        } else {
                            ForEach(messages) { message in
                                let agentRole = roleForMessage(message)
                                MessageBubble(
                                    message: message,
                                    agentRole: agentRole
                                )
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .background(CommunicationConsoleBackdrop())
                .onChange(of: store.messages.count) { _, _ in
                    if let last = selectedAgentChatMessages.last {
                        reader.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            ShellHairline()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(OPCVisibleInterfaceCopy.commandChannelTitle)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(CompanyTheme.selected.opacity(0.74))
                    Rectangle()
                        .fill(CompanyTheme.border.opacity(0.45))
                        .frame(height: 0.5)
                    Text(store.selectedAgent?.displayName ?? "未选择".L())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                }
                Text(OPCVisibleInterfaceCopy.commandChannelHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                HStack(spacing: 10) {
                    TextField("输入指令，例如：汇报当前阻塞并给出下一步。".L(), text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanyTheme.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .focused($isMessageFieldFocused)
                        .inspectorInputChrome(isFocused: isMessageFieldFocused || canSend)
                        .lineLimit(1...6)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? CompanyTheme.selectedDeep : CompanyTheme.muted)
                            .frame(width: 36, height: 36)
                            .background(canSend ? CompanyTheme.selected : CompanyTheme.inputSurface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(canSend ? CompanyTheme.selectedStroke.opacity(0.45) : CompanyTheme.inputBorder.opacity(0.48), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("发送指令".L())
                    .accessibilityHint("把当前指令通道里的指令文本发送给选中员工；员工不可发送或文本为空时禁用。".L())
                }
            }
            .padding(14)
            .background(
                CompanyTheme.inspectorPanel.opacity(0.98)
                    .overlay(
                        LinearGradient(
                            colors: [
                                CompanyTheme.selected.opacity(0.024),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
    }

    private func roleForMessage(_ message: ChatMessage) -> AgentRole? {
        store.agents.first { $0.id == message.agentID }?.role
    }

    private var selectedAgentChatMessages: [ChatMessage] {
        store.messages(for: store.selectedAgentID, in: store.selectedProductID, includingLegacyGlobal: false)
    }

    private var telemetryObject: String {
        store.selectedAgent?.displayName ?? "未选择".L()
    }

    private var telemetryStatus: String {
        store.selectedAgent?.status.title ?? "待机".L()
    }

    private var telemetryProduct: String {
        store.selectedProduct?.name ?? "当前产品".L()
    }

    private var telemetryBackend: String {
        guard let agent = store.selectedAgent else { return "命令行未绑定".L() }
        if store.mainWorkspace == .terminalHall {
            return opcBackendCompactDisplay(type: agent.backend.type, command: agent.backend.command, model: agent.backend.model)
        }
        return agent.role == .boss ? "老板".L() : "\(agent.role.title)" + "席位"
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        store.sendMessage(to: store.selectedAgentID, text: messageText)
        messageText = ""
    }
}

private struct InspectorBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CompanyTheme.inspectorViolet.opacity(0.72),
                    CompanyTheme.inspector,
                    Color.black.opacity(0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    CompanyTheme.purple.opacity(0.035),
                    .clear
                ],
                center: UnitPoint(x: 0.12, y: 0.05),
                startRadius: 24,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    CompanyTheme.selected.opacity(0.020),
                    .clear
                ],
                center: UnitPoint(x: 0.86, y: 0.18),
                startRadius: 34,
                endRadius: 300
            )
        }
    }
}

private struct InspectorTelemetryCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted.opacity(0.74))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(CompanyTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(CompanyTheme.inputSurface.opacity(0.58), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(CompanyTheme.border.opacity(0.30), lineWidth: 0.5)
        )
    }
}

private struct CommunicationConsoleBackdrop: View {
    var body: some View {
        CompanyTheme.inputSurface
            .overlay(
                LinearGradient(
                    colors: [
                        CompanyTheme.selected.opacity(0.012),
                        .clear,
                        CompanyTheme.blue.opacity(0.008)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(CompanyTheme.ink.opacity(0.035))
                    .frame(height: 0.5)
            }
    }
}

struct BossControlPanel: View {
    @EnvironmentObject private var store: CompanyStore
    @Binding var selectedTab: InspectorTab
    @State private var ctoMessage = ""
    @State private var showDecisionCenter = false
    @FocusState private var isCTOMessageFocused: Bool

    private var employeeCount: Int {
        store.agents.filter { $0.role != .boss }.count
    }

    private var openTaskCount: Int {
        store.selectedProductTasks.filter { $0.status != .done && $0.status != .canceled }.count
    }

    private var recentRiskCount: Int {
        // BossControlPanel 是老板首页 stat tile，「近期风险」计数应与右侧风险事件 widget 同口径，
        // 用 selectedProductBossRiskEvents 过滤维护类前缀（与 CommandCenterView 轮 9 同步）。
        store.selectedProductBossRiskEvents.count
    }

    private var completedTaskCount: Int {
        store.selectedProductTasks.filter { $0.status == .done }.count
    }

    private var totalTaskCount: Int {
        max(store.selectedProductTasks.count, 1)
    }

    private var completionPercent: Int {
        Int((Double(completedTaskCount) / Double(totalTaskCount) * 100).rounded())
    }

    private var bossDecisionCount: Int {
        store.bossDecisionCount
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ShellHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if usesCompactBossSidebar {
                        ownerApprovalPanel
                        ctoQuickMessage
                        compactRecentReports
                    } else {
                        statsGrid
                        productProgress
                        ownerApprovalPanel
                        ctoQuickMessage
                        teamProgressPanel
                        recentTasks
                        recentEvents
                    }
                }
                .padding(14)
            }
            .background(CompanyTheme.inspector)
        }
        .sheet(isPresented: $showDecisionCenter) {
            BossDecisionCenterSheet()
                .environmentObject(store)
        }
    }

    private var usesCompactBossSidebar: Bool {
        store.mainWorkspace == .commandCenter || store.mainWorkspace == .productDetail
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let boss = store.selectedAgent {
                CharacterBadge(agent: boss, size: 54, isSelected: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("老板总控台".L())
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.ink)
            Text("\(store.selectedProduct?.name ?? "当前产品") · \(store.selectedProduct?.stage.title ?? "进行中")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            Text("老板".L())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(CompanyTheme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(CompanyTheme.warning.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CompanyTheme.warning.opacity(0.28), lineWidth: 0.7)
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(CompanyTheme.inspectorPanel)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            BossStatCard(title: "员工".L(), value: "\(employeeCount)", systemImage: "person.3.fill", color: CompanyTheme.blue)
            BossStatCard(title: "运行中".L(), value: "\(store.runningAgentIDs.count)", systemImage: "terminal.fill", color: CompanyTheme.accent)
            BossStatCard(title: "未完成任务".L(), value: "\(openTaskCount)", systemImage: "checklist", color: CompanyTheme.warning)
            BossStatCard(title: BossDecisionCenterCopy.statTitle, value: "\(bossDecisionCount)", systemImage: "hand.raised.fill", color: bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
        }
    }

    private var productProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "产品进度".L())
            HStack(alignment: .firstTextBaseline) {
                Text("\(completionPercent)%")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selectedProduct?.stage.title ?? "未选择阶段".L())
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    Text("\(completedTaskCount)/\(store.selectedProductTasks.count)" + " 个任务完成，".L() + "\(openTaskCount)" + " 个未完成。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: Double(completedTaskCount), total: Double(totalTaskCount))
                .tint(CompanyTheme.warning)
        }
        .padding(12)
        .background(CompanyTheme.inspectorPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
        )
    }

    private var ownerApprovalPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SectionHeader(title: BossDecisionCenterCopy.summaryTitle)
                Spacer()
                Text("\(bossDecisionCount)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((bossDecisionCount == 0 ? CompanyTheme.green : CompanyTheme.warning).opacity(0.14), in: Capsule())
            }

            Text(bossDecisionCount == 0
                 ? BossDecisionCenterCopy.summaryEmpty
                 : BossDecisionCenterCopy.summaryDetail(count: bossDecisionCount))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showDecisionCenter = true
            } label: {
                Label(BossDecisionCenterCopy.openTitle, systemImage: "tray.full.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(CompanyTheme.inspectorPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((bossDecisionCount == 0 ? CompanyTheme.border : CompanyTheme.warning).opacity(0.64), lineWidth: 0.7)
        )
    }

    private var ctoQuickMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "给技术负责人下达目标".L())
                TextField("输入老板目标，例如：让团队检查 Gemini 终端报错并给我解决方案。".L(), text: $ctoMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(CompanyTheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .lineLimit(1...2)
                .focused($isCTOMessageFocused)
                .inspectorInputChrome(isFocused: isCTOMessageFocused || !ctoMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                let text = ctoMessage
                ctoMessage = ""
                store.selectAgent(store.ctoID)
                selectedTab = .chat
                store.sendMessage(to: store.ctoID, text: text)
            } label: {
                Label("发送给技术负责人".L(), systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanyTheme.selected)
            .disabled(ctoMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(CompanyTheme.inspectorPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.inputBorder.opacity(0.72), lineWidth: 0.7)
        )
    }

    private var teamProgressPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "员工执行进度".L())
            let employees = store.bossInspectorTeamProgressAgents
            if employees.isEmpty {
                Text("当前没有员工在运行命令行任务。".L())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.secondaryPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.54), lineWidth: 0.7)
                    )
            } else {
                ForEach(employees) { agent in
                    BossEmployeeProgressRow(
                        agent: agent,
                        tasks: store.selectedProductTasks.filter { $0.ownerID == agent.id },
                        queueCount: store.selectedProductWorkQueue.filter { $0.agentID == agent.id }.count,
                        isRunning: store.runningAgentIDs.contains(agent.id)
                    )
                }
                if let overflow = store.bossInspectorTeamProgressOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
    }

    private var recentTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "近期任务结果".L())
            ForEach(store.bossInspectorRecentTasks) { task in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(task.status == .done ? CompanyTheme.green : CompanyTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(CompanyTheme.ink)
                        Text(task.status.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanyTheme.muted)
                    }
                    Spacer()
                }
                .padding(10)
                .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
                )
            }
            if let overflow = store.bossInspectorRecentTasksOverflow() {
                OPCListOverflowFooter(summary: overflow.summary)
            }
        }
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "近期汇报".L())
            ForEach(store.bossInspectorRecentEvents) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                    Text(event.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CompanyTheme.secondaryPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CompanyTheme.border.opacity(0.54), lineWidth: 0.7)
                )
            }
            if let overflow = store.bossInspectorRecentEventsOverflow() {
                OPCListOverflowFooter(summary: overflow.summary)
            }
        }
    }

    private var compactRecentReports: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "近期汇报".L())
            ForEach(store.bossInspectorCompactRecentReports) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                    Text(event.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CompanyTheme.secondaryPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            }
            if let overflow = store.bossInspectorCompactRecentReportsOverflow() {
                OPCListOverflowFooter(summary: overflow.summary)
            }
        }
    }

    private func agentName(_ id: UUID?) -> String {
        guard let id else { return "未分配".L() }
        return store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }
}

struct BossStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.ink)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CompanyTheme.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
        )
    }
}

struct BossAgentRow: View {
    let agent: CompanyAgent

    var body: some View {
        HStack(spacing: 10) {
            CharacterBadge(agent: agent, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Text(agent.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.accent)
            }
            Spacer()
            StatusDot(status: agent.status)
        }
        .padding(10)
        .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
        )
    }
}

struct BossEmployeeProgressRow: View {
    let agent: CompanyAgent
    let tasks: [CompanyTask]
    let queueCount: Int
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CharacterBadge(agent: agent, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    Text(agent.role.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                }
                Spacer(minLength: 0)
                StatusPill(text: isRunning ? "运行中".L() : agent.status.title, color: signalColor)
            }

            ProgressView(value: progress)
                .tint(signalColor)

Text(InspectorStatsCopy.taskStatsText(doneCount: doneCount, activeCount: activeCount, blockedCount: blockedCount, queueCount: queueCount))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(1)
        }
        .padding(10)
        .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(signalColor.opacity(0.30), lineWidth: 0.7)
        )
    }

    private var signalColor: Color {
        if blockedCount > 0 { return CompanyTheme.red }
        if isRunning || activeCount > 0 { return CompanyTheme.accent }
        if !tasks.isEmpty && doneCount == tasks.count { return CompanyTheme.green }
        return CompanyTheme.muted
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case chat
    case tasks
    case events
    case profile
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "沟通".L()
        case .tasks: "任务".L()
        case .events: "事件".L()
        case .profile: "档案".L()
        case .terminal: "终端".L()
        }
    }

    static func availableTabs(for workspace: MainWorkspace) -> [InspectorTab] {
        workspace == .terminalHall ? allCases : allCases.filter { $0 != .terminal }
    }
}

struct InspectorSegmentedTabs: View {
    @EnvironmentObject private var store: CompanyStore
    @Binding var selectedTab: InspectorTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.availableTabs(for: store.mainWorkspace)) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .foregroundStyle(selectedTab == tab ? CompanyTheme.selected : CompanyTheme.secondaryInk.opacity(0.76))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                        Capsule()
                            .fill(selectedTab == tab ? CompanyTheme.selected.opacity(0.72) : Color.clear)
                            .frame(width: 18, height: 1.5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? CompanyTheme.secondaryPanel.opacity(0.30) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(CompanyTheme.panel.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CompanyTheme.border.opacity(0.32), lineWidth: 0.5)
        )
    }
}

private struct InspectorInputChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(CompanyTheme.inputSurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isFocused ? CompanyTheme.selectedStroke.opacity(0.48) : CompanyTheme.inputBorder.opacity(0.50), lineWidth: 0.5)
            )
    }
}

extension View {
    func inspectorInputChrome(isFocused: Bool = false) -> some View {
        modifier(InspectorInputChrome(isFocused: isFocused))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let agentRole: AgentRole?

    var body: some View {
        HStack {
            if message.author == .user { Spacer(minLength: 58) }
            VStack(alignment: .leading, spacing: 5) {
                Text(author)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(labelColor)
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(message.author == .user ? warmUserText : CompanyTheme.ink)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background.opacity(0.82), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            if message.author != .user { Spacer(minLength: 58) }
        }
    }

    private var author: String {
        Self.authorLabel(for: message.author, agentRole: agentRole)
    }

    static func authorLabel(for author: MessageAuthor, agentRole: AgentRole?) -> String {
        switch author {
        case .user: "老板".L()
        case .agent:
            switch agentRole {
            case .cto: "技术负责人".L()
            case .boss: "老板".L()
            case .none: "员工".L()
            default: "员工".L()
            }
        case .system: "系统".L()
        }
    }

    private var labelColor: Color {
        switch message.author {
        case .user: CompanyTheme.selected.opacity(0.78)
        case .agent: CompanyTheme.blue.opacity(0.82)
        case .system: CompanyTheme.secondaryInk.opacity(0.76)
        }
    }

    private var background: Color {
        switch message.author {
        case .user: CompanyTheme.chatUserBubble
        case .agent: CompanyTheme.chatAgentBubble
        case .system: CompanyTheme.chatSystemBubble
        }
    }

    private var borderColor: Color {
        switch message.author {
        case .user: CompanyTheme.selectedStroke.opacity(0.22)
        case .agent: CompanyTheme.inputBorder.opacity(0.30)
        case .system: CompanyTheme.blue.opacity(0.18)
        }
    }

    private var warmUserText: Color {
        Color(red: 0.98, green: 0.91, blue: 0.80)
    }
}

struct TaskBoardView: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let tasks = selectedAgentTasks
                if tasks.isEmpty {
                    EmptyCommandLine(text: "当前产品下没有分配给该员工的任务。".L())
                } else {
                    ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(task.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(CompanyTheme.ink)
                            Spacer()
                            Text(task.status.title)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(statusColor(task.status))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor(task.status).opacity(0.16), in: Capsule())
                        }
                        Text(task.successCriteria)
                            .font(.system(size: 12))
                            .foregroundStyle(CompanyTheme.muted)
                        if let owner = task.ownerID.flatMap({ id in store.agents.first { $0.id == id } }) {
                            Text("负责人：".L() + "\(owner.displayName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CompanyTheme.accent)
                        }
                    }
                    .padding(12)
                    .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
                    )
                    }
                }
            }
            .padding(14)
        }
        .background(CompanyTheme.inspector)
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

    private var selectedAgentTasks: [CompanyTask] {
        store.selectedProductTasks.filter { $0.ownerID == store.selectedAgentID }
    }
}

struct EventLogView: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let events = selectedAgentEvents
                if events.isEmpty {
                    EmptyCommandLine(text: "当前产品下还没有该员工相关事件。".L())
                } else {
                    ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CompanyTheme.ink)
                            Spacer()
                            Text(event.kind.title)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(CompanyTheme.muted)
                        }
                        Text(event.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(CompanyTheme.muted)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
                    )
                    }
                }
            }
            .padding(14)
        }
        .background(CompanyTheme.inspector)
    }

    private var selectedAgentEvents: [CompanyEvent] {
        store.selectedProductEvents.filter { $0.agentID == store.selectedAgentID }
    }
}

struct AgentProfileView: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var displayNameDraft = ""
    @State private var titleDraft = ""
    @State private var commandDraft = ""
    @State private var modelDraft = ""
    @State private var endpointDraft = ""
    @State private var apiKeyDraft = ""
    @State private var missionDraft = ""
    @State private var responsibilitiesDraft = ""
    @State private var boundariesDraft = ""
    @State private var responseRulesDraft = ""
    @State private var memoryDraft = ""
    @State private var skillsDraft = ""

    var body: some View {
        ScrollView {
            if let agent = store.selectedAgent {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("身份与汇报".L())
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(CompanyTheme.muted)
                            .textCase(.uppercase)

                        LabeledContent("显示名称".L()) {
                            TextField("员工名称".L(), text: Binding(
                                get: { displayNameDraft.isEmpty ? agent.displayName : displayNameDraft },
                                set: { displayNameDraft = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanyTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .inspectorInputChrome()
                        }

                        LabeledContent("职位名称".L()) {
                            TextField("员工职位".L(), text: Binding(
                                get: { titleDraft.isEmpty ? agent.title : titleDraft },
                                set: { titleDraft = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanyTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .inspectorInputChrome()
                        }

                        Picker("角色".L(), selection: Binding(
                            get: { agent.role },
                            set: { store.updateSelectedAgentIdentity(role: $0) }
                        )) {
                            ForEach(AgentRole.allCases) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .disabled(agent.id == store.ctoID || agent.id == store.bossID)

                        Toggle("向技术负责人汇报".L(), isOn: Binding(
                            get: { agent.reportsToCTO },
                            set: { store.updateSelectedAgentIdentity(reportsToCTO: $0) }
                        ))
                        .disabled(agent.role == .boss || agent.role == .cto)

                        Button("保存身份配置".L()) {
                            store.updateSelectedAgentIdentity(
                                displayName: displayNameDraft.isEmpty ? agent.displayName : displayNameDraft,
                                title: titleDraft.isEmpty ? agent.title : titleDraft
                            )
                            displayNameDraft = ""
                            titleDraft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CompanyTheme.accent)
                    }
                    .padding(12)
                    .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("模型配置".L())
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(CompanyTheme.muted)
                            .textCase(.uppercase)

                        Picker("来源".L(), selection: Binding(
                            get: { agent.backend.type },
                            set: { store.updateSelectedAgentBackend(type: $0) }
                        )) {
                            ForEach(BackendType.allCases) { backend in
                                Text(backend.title).tag(backend)
                            }
                        }

                        if agent.backend.type == .api {
                            LabeledContent("接口地址".L()) {
                                TextField("https://api.example.com/v1", text: Binding(
                                    get: { endpointDraft.isEmpty ? agent.backend.endpoint : endpointDraft },
                                    set: { endpointDraft = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(CompanyTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .inspectorInputChrome()
                                .onSubmit {
                                    store.updateSelectedAgentBackend(endpoint: endpointDraft)
                                }
                            }

                            LabeledContent("接口密钥".L()) {
                                SecureField(agent.backend.apiKey.isEmpty ? "未配置".L() : "已配置，输入新密钥可替换".L(), text: $apiKeyDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CompanyTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .inspectorInputChrome()
                            }
                        } else if agent.backend.type == .subscriptionCLI {
                            LabeledContent("命令".L()) {
                                TextField("例如 codex、claude、gemini".L(), text: Binding(
                                    get: { commandDraft.isEmpty ? agent.backend.command : commandDraft },
                                    set: { commandDraft = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(CompanyTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .inspectorInputChrome()
                                .onSubmit {
                                    store.updateSelectedAgentBackend(command: commandDraft)
                                }
                            }
                        }

                        LabeledContent(agent.backend.type == .local ? "占位标识".L() : "模型".L()) {
                            TextField(agent.backend.type == .local ? "例如 local、owner".L() : "例如 gpt-5.5、sonnet，留空使用默认模型".L(), text: Binding(
                                get: { modelDraft.isEmpty ? agent.backend.model : modelDraft },
                                set: { modelDraft = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanyTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .inspectorInputChrome()
                            .onSubmit {
                                store.updateSelectedAgentBackend(model: modelDraft)
                            }
                        }

                        if agent.backend.type != .local {
                            Picker("推理强度".L(), selection: Binding(
                                get: { agent.backend.reasoningEffort },
                                set: { store.updateSelectedAgentBackend(reasoningEffort: $0) }
                            )) {
                                ForEach(ReasoningEffort.allCases) { effort in
                                    Text(effort.title).tag(effort)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Button(agent.backend.type == .api ? "保存接口配置".L() : (agent.backend.type == .local ? "保存占位标识".L() : "保存命令和模型".L())) {
                            store.updateSelectedAgentBackend(
                                command: commandDraft.isEmpty ? agent.backend.command : commandDraft,
                                model: modelDraft.isEmpty ? agent.backend.model : modelDraft,
                                endpoint: endpointDraft.isEmpty ? agent.backend.endpoint : endpointDraft,
                                apiKey: apiKeyDraft.isEmpty ? agent.backend.apiKey : apiKeyDraft
                            )
                            commandDraft = ""
                            modelDraft = ""
                            endpointDraft = ""
                            apiKeyDraft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CompanyTheme.accent)
                    }
                    .padding(12)
                    .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("人物与外观".L())
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(CompanyTheme.muted)
                            .textCase(.uppercase)

                        Picker("人种/外观".L(), selection: Binding(
                            get: { agent.ethnicity },
                            set: { store.updateSelectedAgentAppearance(ethnicity: $0) }
                        )) {
                            ForEach(EthnicityPresentation.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("性别".L(), selection: Binding(
                            get: { agent.gender },
                            set: { store.updateSelectedAgentAppearance(gender: $0) }
                        )) {
                            ForEach(GenderPresentation.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("着装".L(), selection: Binding(
                            get: { agent.clothing },
                            set: { store.updateSelectedAgentAppearance(clothing: $0) }
                        )) {
                            ForEach(ClothingStyle.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(12)
                    .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("员工操作档案".L())
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(CompanyTheme.muted)
                            .textCase(.uppercase)

                        let profile = store.operatingProfile(for: agent.id)

                        LabeledContent("使命".L()) {
                            TextField("这个员工存在的目的".L(), text: Binding(
                                get: { missionDraft.isEmpty ? profile.mission : missionDraft },
                                set: { missionDraft = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(CompanyTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .inspectorInputChrome()
                        }

                        ProfileEditorBlock(title: "职责".L(), text: Binding(
                            get: { responsibilitiesDraft.isEmpty ? profile.responsibilities.joined(separator: "\n") : responsibilitiesDraft },
                            set: { responsibilitiesDraft = $0 }
                        ))

                        ProfileEditorBlock(title: "边界".L(), text: Binding(
                            get: { boundariesDraft.isEmpty ? profile.boundaries.joined(separator: "\n") : boundariesDraft },
                            set: { boundariesDraft = $0 }
                        ))

                        ProfileEditorBlock(title: "回复规则".L(), text: Binding(
                            get: { responseRulesDraft.isEmpty ? profile.responseRules.joined(separator: "\n") : responseRulesDraft },
                            set: { responseRulesDraft = $0 }
                        ))

                        ProfileEditorBlock(title: "长期记忆".L(), text: Binding(
                            get: { memoryDraft.isEmpty ? profile.memory.joined(separator: "\n") : memoryDraft },
                            set: { memoryDraft = $0 }
                        ))

                        ProfileEditorBlock(title: "可用技能".L(), text: Binding(
                            get: { skillsDraft.isEmpty ? profile.skills.joined(separator: "\n") : skillsDraft },
                            set: { skillsDraft = $0 }
                        ))

                        Button("保存员工档案".L()) {
                            store.updateSelectedAgentProfile(
                                mission: missionDraft.isEmpty ? profile.mission : missionDraft,
                                responsibilitiesText: responsibilitiesDraft.isEmpty ? profile.responsibilities.joined(separator: "\n") : responsibilitiesDraft,
                                boundariesText: boundariesDraft.isEmpty ? profile.boundaries.joined(separator: "\n") : boundariesDraft,
                                responseRulesText: responseRulesDraft.isEmpty ? profile.responseRules.joined(separator: "\n") : responseRulesDraft,
                                memoryText: memoryDraft.isEmpty ? profile.memory.joined(separator: "\n") : memoryDraft,
                                skillsText: skillsDraft.isEmpty ? profile.skills.joined(separator: "\n") : skillsDraft
                            )
                            missionDraft = ""
                            responsibilitiesDraft = ""
                            boundariesDraft = ""
                            responseRulesDraft = ""
                            memoryDraft = ""
                            skillsDraft = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CompanyTheme.blue)

                        HStack(spacing: 10) {
                            Button {
                                store.syncSelectedAgentWorkspace()
                            } label: {
                                Label("同步本地工作区".L(), systemImage: "folder.badge.gearshape")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                store.compactSelectedAgentMemory()
                            } label: {
                                Label("压缩近期记忆".L(), systemImage: "brain.head.profile")
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("员工工作区已就绪".L())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(CompanyTheme.muted)
                    }
                    .padding(12)
                    .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
                    )

                    ProfileRow(label: "来源".L(), value: agent.backend.type.title)
                    if agent.backend.type == .local {
                        ProfileRow(label: "占位标识".L(), value: agent.backend.model.isEmpty ? "local" : agent.backend.model)
                    } else {
                        if agent.backend.type == .subscriptionCLI {
                            ProfileRow(label: "命令行工具".L(), value: opcBackendCommandDisplayName(agent.backend.command))
                        }
                        ProfileRow(label: "模型".L(), value: agent.backend.model.isEmpty ? "默认模型".L() : agent.backend.model)
                    }
                    if agent.backend.type == .api {
                        ProfileRow(label: "接口地址".L(), value: agent.backend.endpoint.isEmpty ? "未配置".L() : agent.backend.endpoint)
                        ProfileRow(label: "接口密钥".L(), value: agent.backend.apiKey.isEmpty ? "未配置".L() : "已配置".L())
                    }
                    if agent.backend.type != .local {
                        ProfileRow(label: "推理强度".L(), value: agent.backend.reasoningEffort.title)
                    }
                    ProfileRow(label: "人种/外观".L(), value: agent.ethnicity.title)
                    ProfileRow(label: "性别".L(), value: agent.gender.title)
                    ProfileRow(label: "服装".L(), value: agent.clothing.title)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("权限".L())
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(CompanyTheme.muted)
                            .textCase(.uppercase)
                        ForEach(AgentPermission.allCases) { permission in
                            Toggle(permission.title, isOn: Binding(
                                get: { agent.permissions.contains(permission) },
                                set: { store.updateSelectedAgentPermission(permission, isEnabled: $0) }
                            ))
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .padding(14)
                .onChange(of: agent.id) { _, _ in
                    displayNameDraft = ""
                    titleDraft = ""
                    commandDraft = ""
                    modelDraft = ""
                    endpointDraft = ""
                    apiKeyDraft = ""
                    missionDraft = ""
                    responsibilitiesDraft = ""
                    boundariesDraft = ""
                    responseRulesDraft = ""
                    memoryDraft = ""
                    skillsDraft = ""
                }
            }
        }
    }
}

struct TerminalPanel: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var prompt = OPCVisibleInterfaceCopy.defaultAgentReportPromptText

    var body: some View {
        VStack(spacing: 0) {
            if store.mainWorkspace != .terminalHall {
                controlArea
                    .padding(14)
                    .background(CompanyTheme.inspectorPanel)

                ShellHairline()
            }

            ScrollView {
                Text(store.visibleTerminalLog(for: store.selectedAgentID))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(CompanyTheme.terminalBackground)
        }
    }

    private var isSelectedAgentRunning: Bool {
        store.isRunning(agentID: store.selectedAgentID)
    }

    private var canRunSelectedAgentForProduct: Bool {
        guard let agent = store.selectedAgent else { return false }
        return agent.role != .boss && store.isAgentAssignedToSelectedProduct(agent.id)
    }

    @ViewBuilder
    private var controlArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("运行选中的员工".L())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .textCase(.uppercase)
            TextField("提示词".L(), text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(CompanyTheme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .inspectorInputChrome()
                .lineLimit(1...2)
            HStack {
                Button("预检".L()) {
                    store.recordCLIPreflight(agentID: store.selectedAgentID, prompt: prompt)
                }
                .buttonStyle(.bordered)
                .disabled(!canRunSelectedAgentForProduct)

                Button {
                    store.runSelectedAgent(prompt: prompt)
                } label: {
                    Label(isSelectedAgentRunning ? "运行中".L() : "运行命令行任务".L(), systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .disabled(isSelectedAgentRunning || !canRunSelectedAgentForProduct)

                Button("简报给技术负责人".L()) {
                    store.sendSystemBriefToCTO(sourceAgentID: store.selectedAgentID)
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup {
                Text(store.cliPreflightText(for: store.selectedAgentID, prompt: prompt))
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(CompanyTheme.terminalBackground.opacity(0.90), in: RoundedRectangle(cornerRadius: 8))
            } label: {
                Label("运行前预检".L(), systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(CompanyTheme.warning)
            }
        }
    }
}

struct ProfileEditorBlock: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CompanyTheme.muted)
            TextEditor(text: $text)
                .font(.system(size: 11))
                .foregroundStyle(CompanyTheme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 48)
                .padding(6)
                .inspectorInputChrome()
        }
    }
}

struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CompanyTheme.terminalInk)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CompanyTheme.secondaryPanel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CompanyTheme.border.opacity(0.58), lineWidth: 0.7)
        )
    }
}

struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CompanyTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(CompanyTheme.accent.opacity(0.14), in: Capsule())
            }
        }
    }
}
