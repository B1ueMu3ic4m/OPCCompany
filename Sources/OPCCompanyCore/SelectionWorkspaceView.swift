import SwiftUI
import AppKit

struct ProductDeletionRequest: Equatable {
    let productID: UUID
    let productName: String

    init?(product: ProductWorkspace?) {
        guard let product else { return nil }
        self.productID = product.id
        self.productName = product.name
    }
}

struct ProductSettingsDraft: Equatable {
    var name: String
    var shortName: String
    var rootDirectory: String

    init(product: ProductWorkspace) {
        name = product.name
        shortName = product.shortName
        rootDirectory = product.rootDirectory
    }
}

struct ProductDetailWorkspace: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var showProductMessageCenter = false
    @State private var showDeliveryCenter = false
    @State private var showProductSettings = false
    @State private var pendingDeletion: ProductDeletionRequest?

    private var product: ProductWorkspace? {
        store.selectedProduct
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metrics
                HStack(alignment: .top, spacing: 14) {
                    productScope
                    productProgress
                }
                agentCollaborationPanel
                HStack(alignment: .top, spacing: 14) {
                    productTeamOffice
                    productTaskBoard
                }
                HStack(alignment: .top, spacing: 14) {
                    productArtifacts
                    productMemory
                }
            }
            .padding(18)
        }
        .background(CommandSurfaceBackground())
        .sheet(isPresented: $showProductMessageCenter) {
            AgentMessageCenterSheet(scope: .product)
                .environmentObject(store)
        }
        .sheet(isPresented: $showDeliveryCenter) {
            DeliveryAcceptanceCenterSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showProductSettings) {
            if let product {
                ProductSettingsSheet(product: product)
                    .environmentObject(store)
            }
        }
    }

    private var agentCollaborationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "员工协作链路".L())
                Spacer()
                Text("待确认 ".L() + "\(store.selectedProductPendingAgentMessages.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
            }

            HStack(spacing: 10) {
                Button {
                    store.acknowledgeSelectedProductAgentMessages()
                } label: {
                    Label("全部标记已读".L(), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedProductPendingAgentMessages.isEmpty)

                Button {
                    showProductMessageCenter = true
                } label: {
                    Label(AgentMessageCenterCopy.viewAllTitle, systemImage: "tray.full.fill")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            if store.selectedProductAgentMessages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EmptyCommandLine(text: "还没有协作消息，先让技术负责人启动协作或派发任务，老板/技术负责人/员工之间的消息会按时间排在这里。".L())
                    Button {
                        store.startCTOSupervisorGoal(goal: collaborationGoalSeed)
                    } label: {
                        Label("启动技术负责人协作".L(), systemImage: "flag.fill")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(store.selectedProductRecentAgentMessages.prefix(CompanyStore.productDetailAgentCollaborationDefaultDisplayLimit))) { message in
                        AgentMessageRow(
                            message: message,
                            fromName: agentName(message.fromAgentID),
                            toName: message.toAgentID.map(agentName) ?? "公开".L(),
                            taskTitle: taskTitle(for: message.taskID)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private func agentName(_ id: UUID) -> String {
        store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.tasks.first { $0.id == id }?.title
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(product?.name ?? "未选择产品".L())
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text("产品办公室 · ".L() + "\(teamLeadName)" + " 负责推进".L())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CompanyTheme.blue)
                Text(opcProductWorkspaceDisplayName(product?.rootDirectory ?? ""))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    ProductChip(text: product?.stage.title ?? "未知".L(), color: CompanyTheme.blue)
                    ProductChip(text: product?.status.title ?? "未知".L(), color: CompanyTheme.accent)
                }
                HStack {
                    Button {
                        showProductSettings = true
                    } label: {
                        Label("编辑产品".L(), systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .disabled(product == nil)

                    Button {
                        store.runCTOAutopilotWithVisibleProgress()
                    } label: {
                        Label(
                            store.ctoAutopilotState.buttonTitle,
                            systemImage: store.ctoAutopilotState.isRunning ? "hourglass" : "brain.head.profile"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CompanyTheme.accent)
                    .disabled(store.ctoAutopilotState.isRunning)

                    Button(role: .destructive) {
                        pendingDeletion = ProductDeletionRequest(product: product)
                    } label: {
                        Label("删除产品".L(), systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.products.count <= 1 || product == nil)
                    .confirmationDialog(
                        "确认删除产品".L(),
                        isPresented: Binding(
                            get: { pendingDeletion != nil },
                            set: { newValue in if !newValue { pendingDeletion = nil } }
                        ),
                        presenting: pendingDeletion
                    ) { request in
                        Button("永久删除「" + "\(request.productName)" + "」".L(), role: .destructive) {
                            store.deleteProduct(request.productID)
                            pendingDeletion = nil
                        }
                        Button("取消".L(), role: .cancel) {
                            pendingDeletion = nil
                        }
                    } message: { request in
                        Text("将永久移除「".L() + "\(request.productName)" + "」及其全部任务、审批、记忆与交付物，操作无法撤销。".L())
                    }
                }
                if let ctoAutopilotStatusText = store.ctoAutopilotState.statusText {
                    Text(ctoAutopilotStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.ctoAutopilotState.isRunning ? CompanyTheme.accent : CompanyTheme.green)
                }
            }
        }
        .padding(18)
        .background {
            CommandPanelBackground(accent: CompanyTheme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CompanyTheme.blue.opacity(0.24), lineWidth: 1)
        )
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            CommandMetricTile(title: "阶段进度".L(), value: "\(completionPercent)%", systemImage: "chart.line.uptrend.xyaxis", color: CompanyTheme.warning)
            CommandMetricTile(title: "任务".L(), value: "\(completedTaskCount)/\(store.selectedProductTasks.count)", systemImage: "checklist", color: CompanyTheme.accent)
            CommandMetricTile(title: "团队".L(), value: "\(store.selectedProductAgents.count)" + " 人", systemImage: "person.3.fill", color: CompanyTheme.blue)
            CommandMetricTile(title: "待审批".L(), value: "\(pendingApprovalCount)", systemImage: "hand.raised.fill", color: pendingApprovalCount == 0 ? CompanyTheme.green : CompanyTheme.red)
            CommandMetricTile(title: "交付物".L(), value: "\(store.selectedProductDeliveryArtifacts.count)", systemImage: "shippingbox.fill", color: CompanyTheme.warning)
        }
    }

    private var productScope: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "产品目标与范围".L())
            ProductScopeRow(title: "老板目标".L(), detail: ownerGoal, color: CompanyTheme.warning)
            ProductScopeRow(title: "当前版本目标".L(), detail: currentMilestone, color: CompanyTheme.blue)
            ProductScopeRow(title: successStandardTitle, detail: successStandard, color: CompanyTheme.green)
            ProductScopeRow(title: "风险边界".L(), detail: riskBoundary, color: CompanyTheme.red)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var collaborationGoalSeed: String {
        let trimmedGoal = ownerGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGoal.isEmpty || trimmedGoal.hasPrefix("老板还没有".L()) {
            return "推进 ".L() + "\(product?.name ?? "当前产品")" + " " + "\(product?.stage.title ?? "当前阶段")" + "：".L() + "\(currentMilestone)"
        }
        return trimmedGoal
    }

    private var productProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "产品进度与下一步".L())
            ProductScopeRow(title: "当前阶段".L(), detail: product?.stage.title ?? "未选择阶段".L(), color: CompanyTheme.warning)
            ProductStageRail(current: product?.stage ?? .discovery)
            ProductScopeRow(title: "下一步".L(), detail: nextAction, color: CompanyTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var productTeamOffice: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "产品团队".L())
            HStack(alignment: .top, spacing: 10) {
                ProductTeamLeadCard(leadName: teamLeadName)
                VStack(alignment: .leading, spacing: 8) {
                    Text("团队模板".L())
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(CompanyTheme.muted)
                    Menu("更换团队模板".L()) {
                        ForEach(ProductTeamTemplate.allCases) { template in
                            Button(template.title) {
                                store.applyTeamTemplateToSelectedProduct(template)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let leadID = store.teamLeadAgentIDForSelectedProduct() {
                Picker("团队负责人".L(), selection: Binding(
                    get: { leadID },
                    set: { store.updateSelectedProductTeamLead($0) }
                )) {
                    ForEach(store.selectedProductAgents.filter { $0.role != .boss }) { agent in
                        Text(agent.displayName).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(store.selectedProductAgents) { agent in
                    ProductTeamMemberCard(
                        agent: agent,
                        isLead: agent.id == store.teamLeadAgentIDForSelectedProduct(),
                        taskCount: tasks(for: agent).count,
                        activeCount: tasks(for: agent).filter { [.assigned, .running, .waiting, .needsReview].contains($0.status) }.count,
                        queueCount: store.selectedProductWorkQueue.filter { $0.agentID == agent.id }.count,
                        isRunning: store.isRunning(agentID: agent.id)
                    )
                    .onTapGesture {
                        store.selectAgent(agent.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var productTaskBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "当前任务看板".L())
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ProductTaskColumnKind.allCases) { kind in
                        ProductTaskColumn(kind: kind, tasks: tasks(with: kind.statuses), ownerName: ownerName)
                            // 142pt 是五列横排与纵向单列 fallback 的关键阈值；
                            // 调整时需要同步验证 13" MacBook 典型主区宽度下的布局。
                            .frame(minWidth: 142, maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ProductTaskColumnKind.allCases) { kind in
                        ProductTaskColumn(kind: kind, tasks: tasks(with: kind.statuses), ownerName: ownerName)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var productArtifacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "交付物与验收".L())
            HStack(spacing: 10) {
                Button {
                    store.scanProjectArtifacts()
                    store.runAutomaticVerification()
                } label: {
                    Label("扫描并验收".L(), systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)

                Button {
                    showDeliveryCenter = true
                } label: {
                    Label(DeliveryAcceptanceCenterCopy.viewAllTitle, systemImage: "shippingbox.fill")
                }
                .buttonStyle(.bordered)
            }

            if store.selectedProductDeliveryVerifications.isEmpty && store.selectedProductDeliveryArtifacts.isEmpty {
                EmptyCommandLine(text: "还没有交付记录。员工完成任务或扫描项目后，这里显示可验收结果。".L())
            }
            ForEach(store.productDetailRecentDeliveryVerifications) { record in
                VerificationRecordCard(record: record)
            }
            if let overflow = store.productDetailDeliveryVerificationsOverflow() {
                OPCListOverflowFooter(summary: overflow.summary)
            }
            ForEach(store.productDetailRecentDeliveryArtifacts) { artifact in
                ArtifactRecordCard(artifact: artifact)
            }
            if let overflow = store.productDetailDeliveryArtifactsOverflow() {
                OPCListOverflowFooter(summary: overflow.summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var productMemory: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "产品记忆库".L())
            Button {
                store.captureDecisionMemoryFromLatestReport()
            } label: {
                Label("从最新报告写入记忆".L(), systemImage: "brain.head.profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if store.selectedProductMemories.isEmpty {
                EmptyCommandLine(text: "暂无长期记忆。这里会保存关键决策、规则、风险和项目交接信息。".L())
            } else {
                ForEach(store.selectedProductVisibleMemories) { memory in
                    MemoryNoteCard(memory: memory)
                }
                if let overflow = store.selectedProductMemoryOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private func tasks(for agent: CompanyAgent) -> [CompanyTask] {
        store.selectedProductTasks.filter { $0.ownerID == agent.id }
    }

    private func tasks(with statuses: Set<TaskStatus>) -> [CompanyTask] {
        store.selectedProductTasks.filter { statuses.contains($0.status) }
    }

    private var completedTaskCount: Int {
        store.selectedProductTasks.filter { $0.status == .done }.count
    }

    private var activeTaskCount: Int {
        store.selectedProductTasks.filter { [.assigned, .running, .waiting, .needsReview].contains($0.status) }.count
    }

    private var blockedTaskCount: Int {
        store.selectedProductTasks.filter { [.needsApproval, .blocked, .failed].contains($0.status) }.count
    }

    private var pendingApprovalCount: Int {
        store.selectedProductApprovals.filter { $0.status == .pending }.count
    }

    private var completionPercent: Int {
        Int((Double(completedTaskCount) / Double(max(store.selectedProductTasks.count, 1)) * 100).rounded())
    }

    private var teamLeadName: String {
        store.teamLeadAgentIDForSelectedProduct().map(ownerName) ?? "未设置".L()
    }

    private var ownerGoal: String {
        let ctoMessages = store.messages(for: store.ctoID, in: store.selectedProductID, includingLegacyGlobal: false)
        if let message = ctoMessages.last(where: { $0.author == .user }) {
            return message.text
        }
        if let summary = product?.importReport?.summary, !summary.isEmpty {
            return summary
        }
        return "老板还没有为该产品写入明确目标。先在指挥通道告诉技术负责人产品目标即可。".L()
    }

    private var currentMilestone: String {
        switch product?.stage ?? .discovery {
        case .discovery: return "确认产品目标、需求边界、团队角色和成功标准。".L()
        case .design: return "完成产品结构、交互方案、视觉方向和技术路线。".L()
        case .implementation: return "按任务看板推进工程实现，持续回传可验收产物。".L()
        case .testing: return "完成自动化验证、人工审查和风险收敛。".L()
        case .release: return "准备交付包、发布说明和老板验收材料。".L()
        case .maintenance: return "持续维护问题、优化体验和记录长期规则。".L()
        }
    }

    private var successStandardTitle: String {
        if store.selectedProductTasks.contains(where: { $0.status != .done }) {
            return "当前待办标准".L()
        }
        return "整体成功标准".L()
    }

    private var successStandard: String {
        if let task = store.selectedProductTasks.first(where: { $0.status != .done }) {
            return task.successCriteria
        }
        return "所有任务完成，验收记录通过，并形成可交付产物。".L()
    }

    private var riskBoundary: String {
        if pendingApprovalCount > 0 { return "存在 ".L() + "\(pendingApprovalCount)" + " 项待老板审批，未经确认不应继续扩大执行范围。".L() }
        if blockedTaskCount > 0 { return "存在 ".L() + "\(blockedTaskCount)" + " 项异常任务，需要技术负责人或负责人先处理。".L() }
        return "当前未发现必须老板处理的风险，系统安全和命令行链路仍需持续检查。".L()
    }

    private var nextAction: String {
        if pendingApprovalCount > 0 { return "老板先处理审批，再由 ".L() + "\(teamLeadName)" + " 继续推进。".L() }
        if blockedTaskCount > 0 { return "\(teamLeadName)" + " 先处理阻塞任务并回报解决方案。".L() }
        if activeTaskCount > 0 { return "团队继续执行进行中任务，完成后进入验收区。".L() }
        if completedTaskCount == store.selectedProductTasks.count && !store.selectedProductTasks.isEmpty { return "当前任务已完成，建议扫描交付物并生成验收结论。".L() }
        return "让技术负责人根据产品目标拆解任务并分配团队。".L()
    }

    private func ownerName(_ id: UUID?) -> String {
        guard let id else { return "未分配".L() }
        return store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }
}

struct AgentMessageRow: View {
    let message: AgentMessageEnvelope
    let fromName: String
    let toName: String
    let taskTitle: String?
    var onAcknowledge: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: AgentMessageDisplay.icon(for: message.kind))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(AgentMessageDisplay.color(for: message.kind))
                .frame(width: 22, height: 22)
                .background(AgentMessageDisplay.color(for: message.kind).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(AgentMessageDisplay.title(for: message.kind))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    Text("\(fromName) → \(toName)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let reviewOutcome = message.reviewOutcome {
                        StatusPill(text: reviewOutcome.title, color: reviewOutcome == .passed ? CompanyTheme.green : CompanyTheme.warning)
                    } else {
                        StatusPill(text: AgentMessageDisplay.statusTitle(for: message.status), color: AgentMessageDisplay.statusColor(for: message.status))
                    }
                }
                Text(message.subject)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(2)
                if let taskTitle {
                    Text("任务：".L() + "\(taskTitle)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                }
                if let onAcknowledge {
                    Button {
                        onAcknowledge()
                    } label: {
                        Label("确认这条".L(), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct AgentMessageCenterSheet: View {
    enum Scope: Hashable {
        case product
        case agent
    }

    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AgentMessageFilter = .all

    let scope: Scope

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            filterPicker

            ScrollView {
                LazyVStack(spacing: 6) {
                    let messages = filteredMessages
                    if let blocker = membershipBlocker {
                        EmptyCommandLine(text: blocker)
                    } else if messages.isEmpty {
                        EmptyCommandLine(text: emptyText)
                    } else {
                        ForEach(messages) { message in
                            AgentMessageRow(
                                message: message,
                                fromName: agentName(message.fromAgentID),
                                toName: message.toAgentID.map(agentName) ?? "公开".L(),
                                taskTitle: taskTitle(for: message.taskID),
                                onAcknowledge: shouldOfferAcknowledgement(for: message) ? {
                                    store.acknowledgeSelectedAgentMessage(message.id)
                                } : nil
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 420)
        .background(CommandSurfaceBackground())
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sheetTitle)
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text(sheetSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                if scope == .agent {
                    Button {
                        store.acknowledgeSelectedAgentMessages()
                    } label: {
                        Label("标记我的消息已读".L(), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedAgentPendingMessages.isEmpty)
                }
                Button("关闭".L()) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(CompanyTheme.accent)
            }
        }
    }

    private var filterPicker: some View {
        Picker("筛选".L(), selection: $filter) {
            ForEach(AgentMessageFilter.allCases) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }

    private var filteredMessages: [AgentMessageEnvelope] {
        switch scope {
        case .product: store.selectedProductAgentMessages(filter: filter)
        case .agent: store.selectedAgentProductMessages(filter: filter)
        }
    }

    private var sheetTitle: String {
        switch scope {
        case .product:
            return "员工协作消息中心".L()
        case .agent:
            if let name = store.selectedAgent?.displayName {
                return "\(name)" + " 的消息中心".L()
            }
            return "员工消息中心".L()
        }
    }

    private var sheetSubtitle: String {
        switch scope {
        case .product:
            return "\(store.selectedProduct?.name ?? "当前产品")" + " 的全部员工协作消息，按时间倒序。".L()
        case .agent:
            return "当前产品里与此员工收发相关的全部消息，按时间倒序。".L()
        }
    }

    private var emptyText: String {
        switch (scope, filter) {
        case (.product, .all): "当前产品还没有协作消息，启动技术负责人目标后会出现在这里。".L()
        case (.agent, .all): "当前员工还没有协作消息，技术负责人派发任务后会出现在这里。".L()
        case (_, .pending): "没有待确认的消息。".L()
        case (_, .acknowledged): "还没有标记已读的消息。".L()
        case (_, .failed): "没有失败的消息。".L()
        }
    }

    private var membershipBlocker: String? {
        guard scope == .agent,
              let agent = store.selectedAgent,
              agent.role != .boss,
              !store.isAgentAssignedToSelectedProduct(agent.id)
        else { return nil }
        return "\(agent.displayName)" + " 还没有加入当前产品团队，不会收到该产品的协作消息。请先在产品详情把该员工加入团队。".L()
    }

    private func agentName(_ id: UUID) -> String {
        store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    private func taskTitle(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.tasks.first { $0.id == id }?.title
    }

    private func shouldOfferAcknowledgement(for message: AgentMessageEnvelope) -> Bool {
        guard scope == .agent,
              let agent = store.selectedAgent,
              agent.role != .boss
        else { return false }
        return message.productID == store.selectedProductID
            && message.toAgentID == agent.id
            && message.status == .pending
    }
}

enum AgentMessageCenterCopy {
    static let viewAllTitle = "查看全部".L()
}

enum AgentMessageDisplay {
    static func title(for kind: AgentMessageKind) -> String {
        switch kind {
        case .ctoGoalStarted: "技术负责人启动目标".L()
        case .taskDispatched: "任务派发".L()
        case .workCompleted: "员工回传".L()
        case .reviewRequested: "请求审查".L()
        case .reviewCompleted: "审查反馈".L()
        case .acceptanceCompleted: "验收通过".L()
        case .approvalRequested: "审批请求".L()
        case .approvalDecided: "审批结果".L()
        case .ctoLoopProgressed: "技术负责人循环推进".L()
        case .employeeHandoff: "员工交接".L()
        }
    }

    static func icon(for kind: AgentMessageKind) -> String {
        switch kind {
        case .ctoGoalStarted: "flag.fill"
        case .taskDispatched: "paperplane.fill"
        case .workCompleted: "checkmark.seal.fill"
        case .reviewRequested: "magnifyingglass"
        case .reviewCompleted: "shield.lefthalf.filled"
        case .acceptanceCompleted: "checkmark.seal.fill"
        case .approvalRequested: "hand.raised.fill"
        case .approvalDecided: "signature"
        case .ctoLoopProgressed: "arrow.triangle.2.circlepath"
        case .employeeHandoff: "person.2.wave.2.fill"
        }
    }

    static func color(for kind: AgentMessageKind) -> Color {
        switch kind {
        case .ctoGoalStarted: CompanyTheme.warning
        case .taskDispatched: CompanyTheme.blue
        case .workCompleted: CompanyTheme.green
        case .reviewRequested: CompanyTheme.purple
        case .reviewCompleted: CompanyTheme.purple
        case .acceptanceCompleted: CompanyTheme.green
        case .approvalRequested: CompanyTheme.red
        case .approvalDecided: CompanyTheme.accent
        case .ctoLoopProgressed: CompanyTheme.muted
        case .employeeHandoff: CompanyTheme.blue
        }
    }

    static func statusTitle(for status: AgentMessageStatus) -> String {
        switch status {
        case .pending: "待确认".L()
        case .acknowledged: "已读".L()
        case .failed: "失败".L()
        }
    }

    static func statusColor(for status: AgentMessageStatus) -> Color {
        switch status {
        case .pending: CompanyTheme.warning
        case .acknowledged: CompanyTheme.green
        case .failed: CompanyTheme.red
        }
    }
}

struct DeliveryAcceptanceCenterSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    reviewGatesSection
                    acceptanceTasksSection
                    verificationsSection
                    artifactsSection
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 520)
        .background(CommandSurfaceBackground())
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DeliveryAcceptanceCenterCopy.sheetTitle)
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(CompanyTheme.ink)
                Text("\(store.selectedProduct?.name ?? "当前产品")：\(DeliveryAcceptanceCenterCopy.sheetSubtitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    store.scanProjectArtifacts()
                    store.runAutomaticVerification()
                } label: {
                    Label("扫描并验收".L(), systemImage: "doc.viewfinder")
                }
                .buttonStyle(.bordered)

                Button("关闭".L()) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(CompanyTheme.accent)
            }
        }
    }

    private var acceptanceTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: DeliveryAcceptanceCenterCopy.acceptanceTasksSection,
                count: store.selectedProductAcceptanceTasks.count,
                color: CompanyTheme.warning
            )

            if store.selectedProductAcceptanceTasks.isEmpty {
                EmptyCommandLine(text: DeliveryAcceptanceCenterCopy.emptyAcceptanceTasks)
            } else {
                ForEach(store.selectedProductAcceptanceTasks.prefix(CompanyStore.deliveryAcceptanceCenterAcceptanceTasksDisplayLimit)) { task in
                    AcceptanceTaskCard(task: task)
                }
                if let overflow = store.deliveryAcceptanceCenterAcceptanceTasksOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
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

    private var reviewGatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: DeliveryAcceptanceCenterCopy.reviewGatesSection,
                count: store.selectedProductDeliveryReviewGates.count,
                color: CompanyTheme.purple
            )

            if store.selectedProductDeliveryReviewGates.isEmpty {
                EmptyCommandLine(text: DeliveryAcceptanceCenterCopy.emptyReviewGates)
            } else {
                ForEach(store.selectedProductDeliveryReviewGates.prefix(CompanyStore.deliveryAcceptanceCenterReviewGatesDisplayLimit)) { gate in
                    ReviewGateCard(gate: gate, taskTitle: taskTitle(for: gate.taskID))
                }
                if let overflow = store.deliveryAcceptanceCenterReviewGatesOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.purple.opacity(0.22), lineWidth: 1)
        )
    }

    private var verificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: DeliveryAcceptanceCenterCopy.verificationsSection,
                count: store.selectedProductDeliveryVerifications.count,
                color: CompanyTheme.green
            )

            if store.selectedProductDeliveryVerifications.isEmpty {
                EmptyCommandLine(text: DeliveryAcceptanceCenterCopy.emptyVerifications)
            } else {
                ForEach(store.selectedProductRecentDeliveryVerifications.prefix(CompanyStore.deliveryAcceptanceCenterVerificationsDisplayLimit)) { record in
                    VerificationRecordCard(record: record)
                }
                if let overflow = store.deliveryAcceptanceCenterVerificationsOverflow() {
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

    private var artifactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(
                title: DeliveryAcceptanceCenterCopy.artifactsSection,
                count: store.selectedProductDeliveryArtifacts.count,
                color: CompanyTheme.blue
            )

            if store.selectedProductDeliveryArtifacts.isEmpty {
                EmptyCommandLine(text: DeliveryAcceptanceCenterCopy.emptyArtifacts)
            } else {
                ForEach(store.selectedProductRecentDeliveryArtifacts.prefix(CompanyStore.deliveryAcceptanceCenterArtifactsDisplayLimit)) { artifact in
                    ArtifactRecordCard(artifact: artifact)
                }
                if let overflow = store.deliveryAcceptanceCenterArtifactsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .padding(12)
        .background(CompanyTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CompanyTheme.blue.opacity(0.22), lineWidth: 1)
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

    private func taskTitle(for id: UUID) -> String {
        store.tasks.first { $0.id == id }?.title ?? "未知任务".L()
    }
}

enum DeliveryAcceptanceCenterCopy {
    static let sheetTitle = "交付验收中心".L()
    static let sheetSubtitle = "集中查看当前产品的可验收任务、自动验收记录和交付物。".L()
    static let openTitle = "打开交付验收中心".L()
    static let viewAllTitle = "查看全部".L()
    static let reviewGatesSection = "验收门禁".L()
    static let acceptanceTasksSection = "可验收任务".L()
    static let verificationsSection = "自动验收记录".L()
    static let artifactsSection = "交付物记录".L()
    static let emptyReviewGates = "暂无验收门禁记录。送审、自动验收或老板验收后会出现在这里。".L()
    static let emptyAcceptanceTasks = "当前没有待验收或已交付任务。".L()
    static let emptyVerifications = "暂无自动验收记录。".L()
    static let emptyArtifacts = "暂无交付物记录。".L()
}

struct ReviewGateCard: View {
    let gate: ReviewGateRecord
    let taskTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(taskTitle)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                StatusPill(text: gate.status.title, color: color)
            }

            Text(gate.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)

            Text("更新：".L() + "\(gate.updatedAt.opcDateTimeText)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
        }
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private var color: Color {
        switch gate.status {
        case .reviewRequested: CompanyTheme.warning
        case .verificationPassed: CompanyTheme.green
        case .verificationWarning: CompanyTheme.warning
        case .verificationFailed: CompanyTheme.red
        case .accepted: CompanyTheme.green
        case .rejected: CompanyTheme.red
        }
    }

    private var icon: String {
        switch gate.status {
        case .reviewRequested: "magnifyingglass"
        case .verificationPassed: "checkmark.seal.fill"
        case .verificationWarning: "exclamationmark.triangle.fill"
        case .verificationFailed: "xmark.octagon.fill"
        case .accepted: "checkmark.circle.fill"
        case .rejected: "arrow.uturn.backward.circle.fill"
        }
    }
}

private struct ProductScopeRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProductStageRail: View {
    let current: ProductStage

    private let stages: [ProductStage] = [.discovery, .design, .implementation, .testing, .release]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stages) { stage in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(isReached(stage) ? CompanyTheme.warning : CompanyTheme.surfaceRaised)
                        .frame(height: 6)
                    Text(stage.title)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(stage == current ? CompanyTheme.warning : CompanyTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func isReached(_ stage: ProductStage) -> Bool {
        guard let currentIndex = stages.firstIndex(of: current),
              let stageIndex = stages.firstIndex(of: stage)
        else { return false }
        return stageIndex <= currentIndex
    }
}

private struct ProductTeamLeadCard: View {
    let leadName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("团队负责人".L())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            Text(leadName)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
                .lineLimit(1)
            Text("负责拆解、分配、汇总和向老板汇报。".L())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProductTeamMemberCard: View {
    let agent: CompanyAgent
    let isLead: Bool
    let taskCount: Int
    let activeCount: Int
    let queueCount: Int
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            CharacterBadge(agent: agent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    if isLead {
                        Text("负责人".L())
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(CompanyTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CompanyTheme.warning.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(agent.role.title) · \(opcBackendCompactDisplay(type: agent.backend.type, command: agent.backend.command, model: agent.backend.model))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
                Text("任务 ".L() + "\(taskCount) · \(activeCount) · \(queueCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
            }
            Spacer(minLength: 0)
            StatusPill(text: isRunning ? "运行中".L() : agent.status.title, color: isRunning ? CompanyTheme.accent : statusColor)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isLead ? CompanyTheme.warning : statusColor).opacity(0.18), lineWidth: 1)
        )
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

enum ProductTaskColumnKind: CaseIterable, Identifiable {
    case pending
    case active
    case review
    case blocked
    case done

    var id: Self { self }

    var title: String {
        switch self {
        case .pending: "待开始".L()
        case .active: "进行中".L()
        case .review: "待审查".L()
        case .blocked: "待审批/阻塞".L()
        case .done: "已完成".L()
        }
    }

    var statuses: Set<TaskStatus> {
        switch self {
        case .pending: [.draft, .planned, .assigned]
        case .active: [.running, .waiting]
        case .review: [.needsReview]
        case .blocked: [.needsApproval, .blocked, .failed]
        case .done: [.done]
        }
    }

    var color: Color {
        switch self {
        case .pending: CompanyTheme.muted
        case .active: CompanyTheme.blue
        case .review: CompanyTheme.warning
        case .blocked: CompanyTheme.red
        case .done: CompanyTheme.green
        }
    }

    var emptyHint: String {
        switch self {
        case .pending: "等待任务流转".L()
        case .active: "等待执行任务".L()
        case .review: "等待审查任务进入".L()
        case .blocked: "没有风险阻塞".L()
        case .done: "等待交付记录".L()
        }
    }
}

private struct ProductTaskColumn: View {
    let kind: ProductTaskColumnKind
    let tasks: [CompanyTask]
    let ownerName: (UUID?) -> String
    private let visibleTaskLimit = 2

    private var visibleTasks: [CompanyTask] {
        Array(tasks.prefix(visibleTaskLimit))
    }

    private var hiddenTaskCount: Int {
        max(tasks.count - visibleTaskLimit, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(kind.color)
                    .frame(width: 8, height: 8)
                Text(kind.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(kind.color)
            }

            if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无".L())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                    Text(kind.emptyHint)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted.opacity(0.78))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(visibleTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CompanyTheme.ink)
                            .lineLimit(2)
                        Text(ownerName(task.ownerID))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
                }
                if hiddenTaskCount > 0 {
                    Text("还有 " + "\(hiddenTaskCount)" + " 项".L())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(kind.color)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
        .background(CompanyTheme.panelRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(kind.color.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ProductSettingsSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss
    let product: ProductWorkspace
    @State private var draft: ProductSettingsDraft

    init(product: ProductWorkspace) {
        self.product = product
        _draft = State(initialValue: ProductSettingsDraft(product: product))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("编辑产品".L())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.ink)
                Text("修改产品名称、侧栏简称和本地工作区。".L())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProductSettingsField(title: "产品名称".L()) {
                    TextField("产品名称".L(), text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                ProductSettingsField(title: "侧栏简称".L()) {
                    TextField("简称".L(), text: $draft.shortName)
                        .textFieldStyle(.roundedBorder)
                }
                ProductSettingsField(title: "本地工作区".L()) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("本地工作区路径".L(), text: $draft.rootDirectory)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button {
                                draft.rootDirectory = CompanyStore.internalProductRootDirectory(for: product.id)
                            } label: {
                                Label("使用 OPC 内部工作区".L(), systemImage: "shippingbox.fill")
                            }
                            Button {
                                chooseWorkspaceDirectory()
                            } label: {
                                Label("选择现有目录".L(), systemImage: "folder")
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消".L()) {
                    dismiss()
                }
                Button("保存".L()) {
                    store.updateProductSettings(
                        productID: product.id,
                        name: draft.name,
                        shortName: draft.shortName,
                        rootDirectory: draft.rootDirectory
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(CommandSurfaceBackground())
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func chooseWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择产品工作区".L()
        panel.message = "选择当前产品要接管或执行的本地目录。".L()
        panel.prompt = "使用此目录".L()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.rootDirectory = url.path
        }
    }
}

private struct ProductSettingsField<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CompanyTheme.muted)
            content
        }
    }
}

private struct TeamOperatingSummaryCard: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "团队负责人机制".L())
            Text(store.teamOperatingSummaryText())
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(CompanyTheme.terminalInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(CompanyTheme.terminalBackground.opacity(0.90), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TeamTemplatePicker: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("团队模板".L())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            ForEach(ProductTeamTemplate.allCases) { template in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(CompanyTheme.ink)
                            Text(template.summary)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(CompanyTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("应用".L()) {
                            store.applyTeamTemplateToSelectedProduct(template)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(CompanyTheme.accent)
                    }

                    let missing = store.missingRoles(for: template)
                    if !missing.isEmpty {
                        Text("缺少：".L() + "\(missing.map(\.title).joined(separator: "、"))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CompanyTheme.warning)
                    }
                }
                .padding(9)
                .background(CompanyTheme.surfaceRaised.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct AgentDeskWorkspace: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var showAgentMessageCenter = false
    @State private var handoffRecipientID: UUID?
    @State private var handoffTaskID: UUID?
    @State private var handoffSubject: String = ""
    @State private var handoffBody: String = ""
    @State private var handoffFeedback: String?
    @State private var reviewNote: String = ""
    @State private var reviewFeedback: String?

    private var agent: CompanyAgent? {
        store.selectedAgent
    }

    private var agentTasks: [CompanyTask] {
        guard let agent else { return [] }
        return store.selectedProductTasks.filter { $0.ownerID == agent.id }
    }

    private var agentQueue: [AgentWorkItem] {
        guard let agent else { return [] }
        return store.selectedProductWorkQueue.filter { $0.agentID == agent.id }
    }

    private var canRunSelectedAgentForProduct: Bool {
        guard let agent else { return false }
        return agent.role != .boss && store.isAgentAssignedToSelectedProduct(agent.id)
    }

    private var shouldShowReviewQueue: Bool {
        guard let agent else { return false }
        return agent.role == .reviewer || store.agentHasSkill(agent.id, skill: "review")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                inboxPanel
                if shouldShowReviewQueue {
                    reviewQueuePanel
                }
                handoffComposer
                HStack(alignment: .top, spacing: 14) {
                    assignedTasks
                    terminalSummary
                }
                HStack(alignment: .top, spacing: 14) {
                    queuePanel
                    profilePanel
                }
            }
            .padding(18)
        }
        .background(CommandSurfaceBackground())
        .sheet(isPresented: $showAgentMessageCenter) {
            AgentMessageCenterSheet(scope: .agent)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var handoffComposer: some View {
        switch store.agentDeskHandoffComposerState() {
        case .collapsed(let reason):
            handoffComposerCollapsedRow(reason: reason)
        case .expanded:
            handoffComposerExpanded
        }
    }

    private func handoffComposerCollapsedRow(reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .padding(.top, 1)
            Text("发起员工交接".L())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text("员工 → 员工".L())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
            Text(reason)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var handoffComposerExpanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "发起员工交接".L())
                Spacer()
                Text("员工 → 员工".L())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("交接给".L(), selection: Binding(
                    get: { handoffRecipientID ?? store.selectedAgentHandoffRecipients.first?.id ?? UUID() },
                    set: { handoffRecipientID = $0 }
                )) {
                    ForEach(store.selectedAgentHandoffRecipients) { candidate in
                        Text("\(candidate.displayName) · \(candidate.role.title)").tag(candidate.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("关联任务".L(), selection: Binding(
                    get: { handoffTaskID },
                    set: { handoffTaskID = $0 }
                )) {
                    Text("无关联任务".L()).tag(UUID?.none)
                    ForEach(store.selectedAgentHandoffTaskCandidates) { task in
                        Text("\(task.title) · \(task.status.title)").tag(Optional(task.id))
                    }
                }
                .pickerStyle(.menu)

                TextField("主题（留空将自动生成）".L(), text: $handoffSubject)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                TextField("正文（描述已完成内容、需要对方接手的事项；留空使用默认提示）".L(), text: $handoffBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(size: 12))

                HStack(spacing: 10) {
                    Button {
                        sendHandoff()
                    } label: {
                        Label("发送交接消息".L(), systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CompanyTheme.blue)
                    .disabled(resolvedHandoffRecipientID == nil)

                    if let feedback = handoffFeedback {
                        Text(feedback)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanyTheme.green)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private var resolvedHandoffRecipientID: UUID? {
        if let id = handoffRecipientID, store.selectedAgentHandoffRecipients.contains(where: { $0.id == id }) {
            return id
        }
        return store.selectedAgentHandoffRecipients.first?.id
    }

    private func sendHandoff() {
        guard let recipientID = resolvedHandoffRecipientID else { return }
        let envelope = store.postSelectedAgentHandoff(
            toAgentID: recipientID,
            taskID: handoffTaskID,
            subject: handoffSubject,
            body: handoffBody
        )
        if envelope != nil {
            handoffSubject = ""
            handoffBody = ""
            handoffTaskID = nil
            handoffFeedback = "已写入员工协作消息总线，待对方在收件箱确认。".L()
        } else {
            handoffFeedback = "发送失败：交接对象不在当前产品团队，或选中员工不可发送。".L()
        }
    }

    private var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "我的协作收件箱".L())
                Spacer()
                Text("待确认 ".L() + "\(store.selectedAgentPendingMessages.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
            }

            HStack(spacing: 10) {
                Button {
                    store.acknowledgeSelectedAgentMessages()
                } label: {
                    Label("标记我的消息已读".L(), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedAgentPendingMessages.isEmpty)

                Button {
                    showAgentMessageCenter = true
                } label: {
                    Label(AgentMessageCenterCopy.viewAllTitle, systemImage: "tray.full.fill")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            inboxBody
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    @ViewBuilder
    private var inboxBody: some View {
        if let agent, agent.role != .boss, !store.isAgentAssignedToSelectedProduct(agent.id) {
            EmptyCommandLine(text: "\(agent.displayName)" + " 还没有加入当前产品团队，不会收到该产品的协作消息。先在产品详情把该员工加入团队，技术负责人才能给他派发任务。".L())
        } else if store.selectedAgentProductMessages.isEmpty {
            EmptyCommandLine(text: "当前员工还没有收到协作消息，技术负责人派发任务后会出现在这里。".L())
        } else {
            VStack(spacing: 6) {
                ForEach(Array(store.selectedAgentRecentProductMessages.prefix(CompanyStore.agentDeskInboxDefaultDisplayLimit))) { message in
                    AgentMessageRow(
                        message: message,
                        fromName: agentDisplayName(message.fromAgentID),
                        toName: message.toAgentID.map(agentDisplayName) ?? "公开".L(),
                        taskTitle: inboxTaskTitle(for: message.taskID),
                        onAcknowledge: shouldOfferAcknowledgement(for: message) ? {
                            store.acknowledgeSelectedAgentMessage(message.id)
                        } : nil
                    )
                }
                if let overflow = store.agentDeskInboxOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
    }

    private func agentDisplayName(_ id: UUID) -> String {
        store.agents.first { $0.id == id }?.displayName ?? "未知员工".L()
    }

    private func inboxTaskTitle(for id: UUID?) -> String? {
        guard let id else { return nil }
        return store.tasks.first { $0.id == id }?.title
    }

    private func shouldOfferAcknowledgement(for message: AgentMessageEnvelope) -> Bool {
        guard let agent, agent.role != .boss else { return false }
        return message.productID == store.selectedProductID
            && message.toAgentID == agent.id
            && message.status == .pending
    }

    private var reviewQueuePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionHeader(title: "我的待审任务".L())
                Spacer()
                Text("\(store.selectedAgentReviewQueue.count)" + " 项".L())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(CompanyTheme.surfaceRaised.opacity(0.5), in: Capsule())
            }

            if store.selectedAgentReviewQueue.isEmpty {
                EmptyCommandLine(text: "当前没有分配给你的待审查任务。技术负责人派发审查任务后会出现在这里。".L())
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("审查意见（可选，会写入协作消息和验收门禁）".L(), text: $reviewNote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .font(.system(size: 12))

                    ForEach(store.selectedAgentReviewQueue.prefix(CompanyStore.agentDeskReviewQueueDefaultDisplayLimit)) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                TaskSignalRow(task: task, ownerName: agent?.displayName ?? "未知员工".L())
                                if isReReviewTask(task) {
                                    StatusPill(text: "返工后复审".L(), color: CompanyTheme.warning)
                                }
                            }
                            HStack(spacing: 10) {
                                Button {
                                    finishReview(taskID: task.id)
                                } label: {
                                    Label("完成审查".L(), systemImage: "checkmark.seal.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(CompanyTheme.green)

                                Button {
                                    rejectReview(taskID: task.id)
                                } label: {
                                    Label("打回返工".L(), systemImage: "arrow.uturn.backward.circle.fill")
                                }
                                .buttonStyle(.bordered)

                                Spacer(minLength: 0)
                            }
                        }
                        .padding(10)
                        .background(CompanyTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let overflow = store.agentDeskReviewQueueOverflow() {
                        OPCListOverflowFooter(summary: overflow.summary)
                    }
                }
            }

            if let reviewFeedback {
                Text(reviewFeedback)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(reviewFeedback.contains("失败".L()) ? CompanyTheme.red : CompanyTheme.green)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandPanel()
    }

    private func finishReview(taskID: UUID) {
        if store.completeReviewByOwner(taskID: taskID, summary: reviewNote) {
            reviewNote = ""
            reviewFeedback = "已完成审查，并回传给技术负责人。".L()
        } else {
            reviewFeedback = "审查失败：任务状态、归属或产品团队不匹配。".L()
        }
    }

    private func rejectReview(taskID: UUID) {
        if store.rejectReviewByOwner(taskID: taskID, reason: reviewNote) {
            reviewNote = ""
            reviewFeedback = "已打回返工，并回传给技术负责人。".L()
        } else {
            reviewFeedback = "审查失败：任务状态、归属或产品团队不匹配。".L()
        }
    }

    private func isReReviewTask(_ task: CompanyTask) -> Bool {
        store.selectedProductAgentMessages.contains { message in
            message.kind == .reviewRequested
                && message.taskID == task.id
                && message.toAgentID == task.ownerID
                && message.subject.hasPrefix("返工后复审：".L())
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            if let agent {
                CharacterBadge(agent: agent, size: 68)
                VStack(alignment: .leading, spacing: 6) {
                    Text(agent.displayName)
                        .font(.system(size: 28, weight: .heavy, design: .serif))
                        .foregroundStyle(CompanyTheme.ink)
                    Text("\(agent.title) · \(agent.role.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                    StatusDot(status: agent.status)
                    if agent.role != .boss && !store.isAgentAssignedToSelectedProduct(agent.id) {
                        Text("未加入当前产品团队，不能执行当前产品任务。".L())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CompanyTheme.warning)
                    }
                }
            }

            Spacer()

            HStack {
                Button {
                    store.runSelectedAgent(prompt: OPCVisibleInterfaceCopy.defaultAgentReportPromptText)
                    store.mainWorkspace = .terminalHall
                } label: {
                    Label("运行汇报".L(), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .disabled(!canRunSelectedAgentForProduct)
            }
        }
        .padding(18)
        .background {
            CommandPanelBackground(accent: CompanyTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CompanyTheme.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private var assignedTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "负责的任务".L())
            if agentTasks.isEmpty {
                EmptyCommandLine(text: "当前产品下没有分配给该员工的任务。".L())
            } else {
                ForEach(agentTasks.prefix(CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit)) { task in
                    TaskSignalRow(task: task, ownerName: agent?.displayName ?? "未知员工".L())
                    HStack {
                        Button("入队".L()) {
                            if let agent {
                                store.enqueueWorkItem(taskID: task.id, agentID: agent.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        Button("运行".L()) {
                            store.runTaskOwner(task.id)
                            store.mainWorkspace = .terminalHall
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CompanyTheme.accent)
                        .disabled(!canRunSelectedAgentForProduct)
                    }
                }
                if let overflow = store.agentDeskAssignedTasksOverflow(forAgentID: agent?.id) {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .commandPanel()
    }

    private var terminalSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "运行状态".L())
            let log = store.currentProductTerminalLog(for: store.selectedAgentID)
            let isRunning = store.isRunning(agentID: store.selectedAgentID)
            let session = store.runtimeSession(for: store.selectedAgentID)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: isRunning ? "hourglass" : runtimeStatusIcon(session: session, log: log))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isRunning ? CompanyTheme.accent : runtimeStatusColor(session: session, log: log))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isRunning ? "模型正在生成回复".L() : terminalStatusTitle(session: session, log: log))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(CompanyTheme.ink)
                        Text(isRunning ? "模型回复生成中。命令和输出在终端大厅。".L() : terminalStatusDetail(session: session, log: log))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        store.mainWorkspace = .terminalHall
                    } label: {
                        Label("查看完整日志".L(), systemImage: "terminal.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let agent {
                            store.clearTerminalLog(for: agent.id)
                        }
                    } label: {
                        Label("清空".L(), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(log.isEmpty)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        }
        .commandPanel()
    }

    private func terminalStatusTitle(session: AgentRuntimeSession?, log: String) -> String {
        if let session {
            switch session.state {
            case .ready:
                return "会话已就绪".L()
            case .prewarming:
                return "会话预热中".L()
            case .restarting:
                return "会话重开中".L()
            case .failed:
                return "会话不可用".L()
            case .timedOut:
                return "会话曾超时".L()
            case .busy:
                return "会话占用中".L()
            case .unavailable:
                return "当前员工无真实模型来源".L()
            case .cold:
                break
            }
        }
        return log.isEmpty ? "还没有运行记录".L() : terminalStatusTitle(from: log)
    }

    private func terminalStatusDetail(session: AgentRuntimeSession?, log: String) -> String {
        if let session {
            if let operatorHint = session.cliInteractionOperatorHint, !operatorHint.isEmpty {
                return operatorHint
            }
            if !session.lastError.isEmpty {
                return visibleRuntimeError(session.lastError)
            }
            switch session.state {
            case .ready:
                return "\(session.capability.title)" + " · 命令和输出在终端大厅。".L()
            case .cold:
                return "还未预热。员工执行命令行任务或聊天后，这里只显示状态摘要。".L()
            case .prewarming, .restarting:
                return "正在检查本地命令行或接口配置。".L()
            case .busy:
                return "员工正在处理请求。".L()
            case .failed, .timedOut, .unavailable:
                return "需要检查命令行登录、命令路径、网络或模型配置。".L()
            }
        }
        return log.isEmpty ? "员工执行命令行任务或聊天后，这里只显示状态摘要。".L() : terminalStatusDetail(from: log)
    }

    private func runtimeStatusIcon(session: AgentRuntimeSession?, log: String) -> String {
        guard let session else { return log.isEmpty ? "terminal" : "checkmark.circle.fill" }
        switch session.state {
        case .ready: return "checkmark.circle.fill"
        case .busy, .prewarming, .restarting: return "hourglass"
        case .failed, .timedOut, .unavailable: return "exclamationmark.triangle.fill"
        case .cold: return "terminal"
        }
    }

    private func runtimeStatusColor(session: AgentRuntimeSession?, log: String) -> Color {
        guard let session else { return log.isEmpty ? CompanyTheme.muted : CompanyTheme.green }
        switch session.state {
        case .ready: return CompanyTheme.green
        case .busy, .prewarming, .restarting: return CompanyTheme.accent
        case .failed, .timedOut, .unavailable: return CompanyTheme.red
        case .cold: return CompanyTheme.muted
        }
    }

    private func terminalStatusTitle(from log: String) -> String {
        if log.contains("[聊天退出码 0]".L()) || log.contains("[接口聊天退出码 0]".L()) || log.contains("[chat exit 0]") || log.contains("[api chat exit 0]") {
            return "最近一次聊天已完成".L()
        }
        if log.contains("[命令退出码 0]".L()) || log.contains("[exit 0]") {
            return "最近一次命令行任务已完成".L()
        }
        if log.contains("exit 124") || log.contains("命令超时".L()) {
            return "最近一次运行超时".L()
        }
        if log.contains("[命令退出码 ".L()) || log.contains("[exit ") || log.contains("[聊天退出码 ".L()) || log.contains("[接口聊天退出码 ".L()) || log.contains("[chat exit ") || log.contains("[api chat exit ") {
            return "最近一次运行失败".L()
        }
        return "正在记录运行日志".L()
    }

    private func terminalStatusDetail(from log: String) -> String {
        let lines = log
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let exit = lines.last(where: { $0.hasPrefix("[聊天退出码".L()) || $0.hasPrefix("[接口聊天退出码".L()) || $0.hasPrefix("[命令退出码".L()) || $0.hasPrefix("[chat exit") || $0.hasPrefix("[api chat exit") || $0.hasPrefix("[exit") }) {
            return "\(visibleExitSummary(exit))" + " · 命令和输出在终端大厅。".L()
        }
        return "命令和输出在终端大厅。".L()
    }

    private func visibleRuntimeError(_ error: String) -> String {
        let clean = error
            .replacingOccurrences(of: "lastError:", with: "最近错误：".L())
            .replacingOccurrences(of: "busy", with: "运行占用".L())
            .replacingOccurrences(of: "runtime", with: "运行会话".L())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.hasPrefix("最近错误：".L()) ? clean : "最近错误：".L() + "\(clean)"
    }

    private func visibleExitSummary(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        let code = digits.isEmpty ? "未知".L() : digits
        if raw.contains("聊天退出码".L()) || raw.contains("chat exit") || raw.contains("api chat exit") {
            return "最近一次聊天退出码 ".L() + "\(code)"
        }
        return "最近一次命令行退出码 ".L() + "\(code)"
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "员工工作队列".L())
                if !store.selectedAgentReworkQueue.isEmpty {
                    Spacer()
                    Text("返工 ".L() + "\(store.selectedAgentReworkQueue.count)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(CompanyTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CompanyTheme.warning.opacity(0.12), in: Capsule())
                }
            }
            if agentQueue.isEmpty {
                EmptyCommandLine(text: "暂无队列任务。".L())
            } else {
                ForEach(agentQueue.prefix(CompanyStore.agentDeskWorkQueueDefaultDisplayLimit)) { item in
                    WorkQueueCard(item: item)
                }
                if let overflow = store.agentDeskWorkQueueOverflow(forAgentID: agent?.id) {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .commandPanel()
    }

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "模型和权限".L())
            if let agent {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(store.agentDeskProfileChips(forAgentID: agent.id)) { chip in
                        AgentDeskProfileChipView(label: chip.label, value: chip.value)
                    }
                }
                if let session = store.runtimeSession(for: agent.id) {
                    if !session.lastError.isEmpty {
                        Text(visibleRuntimeError(session.lastError))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CompanyTheme.red)
                            .lineLimit(2)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CompanyTheme.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 8) {
                        Button("预热团队".L()) {
                            store.prewarmSelectedProductAgentSessions(reason: "老板在员工工作台手动预热".L())
                        }
                        .buttonStyle(.bordered)
                        Button("重开".L()) {
                            store.restartAgentSession(agentID: agent.id, reason: "老板手动重开员工会话".L())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CompanyTheme.warning)
                    }
                }
                FlowLayout(items: agent.permissions.map(\.title).sorted())
            }
        }
        .commandPanel()
    }

}

struct OPCListOverflowFooter: View {
    let summary: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
                .padding(.top, 1)
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AgentDeskProfileChipView: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(CompanyTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: Capsule())
    }
}

struct ProfileMiniRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(CompanyTheme.ink)
                .lineLimit(1)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}
