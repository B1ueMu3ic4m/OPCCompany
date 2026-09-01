import Foundation
import SQLite3

// MARK: - Runtime
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {

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
            TerminalHallOverviewMetric(title: "团队".L().L(), value: team, kind: .neutral),
            TerminalHallOverviewMetric(title: "运行中".L().L(), value: running, kind: running > 0 ? .ok : .neutral),
            TerminalHallOverviewMetric(title: "待审批".L().L(), value: pendingApprovals, kind: pendingApprovals > 0 ? .warning : .neutral),
            TerminalHallOverviewMetric(title: "阻塞/失败".L().L(), value: blocked, kind: blocked > 0 ? .danger : .neutral),
            TerminalHallOverviewMetric(title: "最近风险".L().L(), value: recentRisks, kind: recentRisks > 0 ? .danger : .neutral)
        ]
        // 健康预警 chip：当且仅当当前产品有员工处于轮 4 徽章可见状态（attention）时追加；
        // 默认情况（无 attention 员工）保持 5 个 chip 不变，避免常规场景下挤压窄屏卡片。
        let attentionCount = terminalHallOverviewAttentionAgentCount()
        if attentionCount > 0 {
            metrics.append(TerminalHallOverviewMetric(title: "健康预警".L().L(), value: attentionCount, kind: .danger))
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
            return "下一步：先在老板决策中心处理 ".L().L() + "\(pendingApprovals)" + " 项待审批。".L().L()
        } else if blocked > 0 {
            return "下一步：阻塞/失败任务 ".L().L() + "\(blocked)" + " 项，请在产品详情或员工工作台跟进。".L().L()
        } else if recentRisks > 0 {
            return "下一步：最近风险 ".L().L() + "\(recentRisks)" + " 条，可在事件流核对。".L().L()
        } else if running == 0 && team > 0 {
            return "下一步：选择员工运行任务，或在下方摘要工作台运行常用巡检。".L().L()
        } else {
            return "下一步：保持运行；下方摘要工作台展示架构 / 通信 / 维护核心指标。".L().L()
        }
    }
    public func selectedProductAgentMemories(for agentID: UUID) -> [ProductMemoryNote] {
        memories.filter { $0.productID == selectedProductID && $0.agentID == agentID }
    }
    func productAgents(for productID: UUID) -> [CompanyAgent] {
        guard let product = products.first(where: { $0.id == productID }) else {
            return agents.filter { $0.role != .boss }
        }
        return agents.filter { agent in
            agent.role != .boss && product.assignedAgentIDs.contains(agent.id)
        }
    }
    public func isAgentAssignedToSelectedProduct(_ agentID: UUID) -> Bool {
        selectedProductAgents.contains { $0.id == agentID }
    }
    public func selectAgent(_ id: UUID) {
        selectedAgentID = id
        appendEvent(kind: .message, title: "选中员工".L(), detail: "老板选中了 ".L() + "\(agentName(id))" + "。".L(), agentID: id)
        if agents.first(where: { $0.id == id })?.role == .boss {
            mainWorkspace = .commandCenter
        } else {
            mainWorkspace = .agentDesk
        }
    }
    public func focusAgent(_ id: UUID) {
        selectedAgentID = id
        appendEvent(kind: .message, title: "观察员工状态".L(), detail: "老板正在查看 ".L() + "\(agentName(id))" + " 的动画状态。".L(), agentID: id)
    }
    func ensureSelectedAgentIsValidForSelectedProduct() {
        guard let selected = selectedAgent else {
            selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
            return
        }

        if selected.role == .boss { return }
        if selectedProductAgents.contains(where: { $0.id == selected.id }) { return }

        selectedAgentID = selectedProduct?.teamLeadAgentID ?? ctoID
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
            appendEvent(kind: .statusChanged, title: "产品成员已加入".L(), detail: "\(agentName(agentID))" + " 已加入 ".L() + "\(products[index].name)" + "。".L(), agentID: agentID)
            if runtimeSupervisorStarted {
                prewarmAgentSession(agentID: agentID, reason: "新员工加入当前产品团队".L())
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
        appendEvent(kind: .statusChanged, title: "产品成员已移除".L(), detail: "\(agentName(agentID))" + " 已从 ".L() + "\(products[index].name)" + " 移除。".L(), agentID: agentID)
        ensureSelectedAgentIsValidForSelectedProduct()
        saveSnapshot()
    }
    public func restartAgentTeamForSelectedProduct() {
        guard let product = selectedProduct else { return }
        for index in agents.indices {
            guard agents[index].role != .boss, product.assignedAgentIDs.contains(agents[index].id) else { continue }
            agents[index].status = agents[index].role == .cto ? .thinking : .idle
            syncAgentWorkspace(for: agents[index].id)
        }
        messages.append(ChatMessage(productID: product.id, agentID: ctoID, author: .system, text: "产品工作区已切换为 ".L() + "\(product.name)" + "。技术负责人和该产品员工团队已重新开启，请按该产品上下文工作。".L()))
        appendEvent(kind: .statusChanged, title: "产品团队已重新开启".L(), detail: "\(product.name)" + "：技术负责人和所有分配员工已进入当前产品上下文。".L(), agentID: ctoID)
        ensureRuntimeSessionsForSelectedProduct()
        if runtimeSupervisorStarted {
            prewarmSelectedProductAgentSessions(reason: "产品切换后重开当前团队会话".L())
        }
    }
    public func addEmployee(from draft: EmployeeDraft) {
        let count = agents.filter { $0.role != .boss && $0.role != .cto }.count
        let seat = employeeHallSeat(for: count)
        let agent = CompanyAgent(
            displayName: draft.displayName.isEmpty ? "新员工".L() : draft.displayName,
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
        appendEvent(kind: .statusChanged, title: "新增员工".L(), detail: "\(agent.displayName)" + " 已加入，职位：".L() + "\(agent.title)" + "。".L(), agentID: agent.id)
            messages.append(ChatMessage(productID: selectedProductID, agentID: agent.id, author: .system, text: "系统提示：".L() + "\(agent.displayName)" + " 已创建。正式沟通会调用该员工配置的真实模型来源。".L()))
        syncAgentWorkspace(for: agent.id)
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "员工创建完成，已生成本地工作区。".L())
        draftEmployee = EmployeeDraft()
        isAddingEmployee = false
        saveSnapshot()
    }
    public func createEmployee(fromRolePack packID: String) {
        guard let pack = AgentRolePackCatalog.pack(id: packID) else { return }
        guard pack.role != .cto else {
            appendEvent(kind: .risk, title: "已阻止重复技术负责人".L(), detail: "技术负责人总控编排包只能应用到现有 Codex 技术负责人，不能创建第二个技术负责人。".L(), agentID: ctoID)
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
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "已从角色包 ".L() + "\(pack.title)" + " 创建员工。".L())
        appendEvent(kind: .statusChanged, title: "角色包员工已创建".L(), detail: "\(agent.displayName)" + " 已按 ".L() + "\(pack.title)" + " 加入当前产品团队。".L(), agentID: agent.id)
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
    public func commandCenterRiskPanelEventsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductBossRiskEvents.count,
            limit: Self.commandCenterRiskPanelEventsDefaultDisplayLimit,
            noun: "条风险汇报".L().L(),
            continuation: "这里先显示最近风险，关键进展会继续浮现。".L().L()
        )
    }
    func sheetTerminalOverflow(total: Int, limit: Int, noun: String) -> AgentDeskListOverflow? {
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " " + "\(noun)" + "未显示。当前中心先显示最近 ".L().L() + "\(limit)" + " 项。".L().L()
        )
    }
    public func agentDeskProfileChips(forAgentID agentID: UUID?) -> [AgentDeskProfileChip] {
        guard let id = agentID, let agent = agents.first(where: { $0.id == id }) else { return [] }
        let model = agent.backend.model.isEmpty ? "默认模型".L().L() : agent.backend.model
        var chips: [AgentDeskProfileChip]
        switch agent.backend.type {
        case .subscriptionCLI:
            chips = [
                .init(label: "来源".L().L(), value: agent.backend.type.title),
                .init(label: "命令行工具".L().L(), value: opcBackendCommandDisplayName(agent.backend.command)),
                .init(label: "模型".L().L(), value: model),
                .init(label: "推理强度".L().L(), value: agent.backend.reasoningEffort.title)
            ]
        case .api:
            chips = [
                .init(label: "来源".L().L(), value: agent.backend.type.title),
                .init(label: "模型".L().L(), value: model),
                .init(label: "推理强度".L().L(), value: agent.backend.reasoningEffort.title)
            ]
        case .local:
            chips = [
                .init(label: "来源".L().L(), value: agent.backend.type.title),
                .init(label: "占位标识".L().L(), value: model)
            ]
        }
        if let session = runtimeSession(for: agent.id) {
            chips.append(.init(label: "会话".L().L(), value: "\(session.state.title) · \(session.capability.title)"))
            if !session.keepAlive {
                chips.append(.init(label: "保活".L().L(), value: "关闭".L().L()))
            }
        }
        return chips
    }
    public func agentDeskHandoffComposerState() -> AgentDeskHandoffComposerState {
        guard let agent = selectedAgent else {
            return .collapsed(reason: "尚未选中员工。先在团队列表选择一位员工后再发起交接。".L())
        }
        if agent.role == .boss {
            return .collapsed(reason: "老板不参与员工到员工的交接。请选中员工再发起交接。".L())
        }
        if !isAgentAssignedToSelectedProduct(agent.id) {
            return .collapsed(reason: "\(agent.displayName)" + " 还没有加入当前产品团队，无法在该产品发起交接。先在产品详情把该员工加入团队。".L())
        }
        if selectedAgentHandoffRecipients.isEmpty {
            return .collapsed(reason: "当前产品里没有可接收交接的员工。先在产品详情邀请其他员工加入团队。".L())
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
                title: "已阻止非本人任务交接".L(),
                detail: "\(agentName(sender.id))" + " 只能交接自己在当前产品负责的任务。".L(),
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
                title: "已阻止老板参与员工交接".L(),
                detail: "员工交接消息只在非老板员工之间允许，已拒绝。".L(),
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
                title: "已阻止跨团队员工交接".L(),
                detail: "\(fromAgent.displayName)" + " 或 ".L() + "\(toAgent.displayName)" + " 不在 ".L() + "\(product.name)" + " 团队，不能完成员工交接。".L(),
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
                title: "已阻止跨产品任务交接".L(),
                detail: "\(task.title)" + " 不属于 ".L() + "\(product.name)" + "，不能挂到该产品的员工交接消息。".L(),
                agentID: fromAgentID
            )
            saveSnapshot()
            return nil
        }
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSubject = cleanSubject.isEmpty
            ? "\(fromAgent.displayName)" + " 向 ".L() + "\(toAgent.displayName)" + " 交接".L()
            : cleanSubject
        let resolvedBody = cleanBody.isEmpty
            ? "\(fromAgent.displayName)" + " 完成上一阶段产物，已交给 ".L() + "\(toAgent.displayName)" + " 继续推进。".L()
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
    func agentCanParticipateInProduct(_ agentID: UUID, productID: UUID) -> Bool {
        if agentID == bossID { return true }
        if agentID == ctoID { return true }
        guard let product = products.first(where: { $0.id == productID }) else { return false }
        return product.assignedAgentIDs.contains(agentID)
    }
    @discardableResult
    public func cleanLegacySyntheticAgentReplies(saveAfterChange: Bool = true) -> Bool {
        var changed = false
        for index in messages.indices where messages[index].author == .agent && isLegacySyntheticAgentReply(messages[index].text) {
            messages[index].author = .system
            messages[index].text = "系统提示：旧版本的本地模板回复已隐藏。现在正式沟通只显示真实模型返回内容；未调用模型时只显示系统降级提示。".L()
            changed = true
        }

        if changed {
            appendEvent(kind: .statusChanged, title: "旧版模板回复已清理".L(), detail: "已把历史里的本地拟人化模板回复改为系统提示，避免误认为员工真实回复。".L(), agentID: ctoID)
            if saveAfterChange {
                saveSnapshot()
            }
        }
        return changed
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
            let status = runnable ? "可执行".L().L() : hasDirectory && hasMarker ? "已登记，待生成源码执行区".L().L() : "待创建".L().L()
            let mode = isGitRepository ? "代码仓库独立工作区".L().L() : "源码快照隔离".L().L()
            let executionSummary = runnable ? "已使用独立执行区".L().L() : "暂用主工作目录".L().L()
            return "- \(agent.displayName)：\(status) · \(mode) · \(executionSummary)"
        }
        let workspaceLines = workspaceRows.map { agent, workspace, hasDirectory, hasSessionLog in
            "- ".L() + "\(agent.displayName)" + "：员工工作区 ".L() + "\(hasDirectory ? "已创建".L() : "缺失".L())" + " · 会话日志 ".L().L() + "\(hasSessionLog ? "已创建" : "缺失")"
        }
        let runtimeLines = runtimeRows.map { agent, session in
            let detail = session.map { "\($0.state.title) / \($0.capability.title)" } ?? "缺失".L().L()
            return "- \(agent.displayName)：\(detail)"
        }

        let issueCount = duplicateWorkspaceCount + missingWorkspaceCount + missingSessionCount
        return """
        \("命令行与工作区隔离体检：".L())\(issueCount == 0 ? "通过".L() : "发现 " + "\(issueCount)" + " 项问题")

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
        let passed = report.contains("命令行与工作区隔离体检：通过".L())
        let status: VerificationStatus = passed ? .passed : .warning
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行与工作区隔离体检".L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: passed ? .artifactCreated : .risk, title: "命令行与工作区隔离体检完成".L(), detail: status.title, agentID: ctoID)
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
            let detail = session.map { "\($0.state.title) / \($0.capability.title)" } ?? "缺失".L().L()
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
            ? "使用产品根目录".L()
            : "产品根目录不可用，实际已回退到 ".L() + "\(workingDirectory.path)"
        let agentLines = agents.map { agent in
            let windowName = terminalWorkspaceWindowName(for: agent)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let status = windowNames.contains(windowName) ? "已连接".L() : "待创建".L()
            let executionSummary = executionDirectory.standardizedFileURL.path == workingDirectory.standardizedFileURL.path
                ? "主工作目录".L()
                : "独立执行区".L()
            return "- ".L() + "\(agent.displayName)" + "：终端席位 ".L() + "\(status)" + " · 执行位置 ".L() + "\(executionSummary)"
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
            ? "使用产品根目录".L().L()
            : "产品根目录不可用，实际已回退到 ".L().L() + "\(workingDirectory.path)"
        let agentLines = agents.map { agent in
            let windowName = terminalWorkspaceWindowName(for: agent)
            let executionDirectory = cliExecutionDirectoryURL(for: agent)
            let status = windowNames.contains(windowName) ? "已连接".L().L() : "待创建".L().L()
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
    func terminalWorkspaceArchitectureCheck() -> MultiAgentArchitectureCheck {
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
            title: "持久终端可用性".L(),
            status: status,
            detail: snapshot.isKnown
                ? "主要待处理：\(snapshot.primaryIssue)。终端工具 \(snapshot.tmuxReady ? "已就绪" : "未找到")，工作区会话 \(snapshot.sessionExists ? "已存在" : "未启动")，控制窗口 \(snapshot.hasControlWindow ? "已连接" : "未连接")，员工席位 ".L() + "\(snapshot.connectedAgentCount)" + "/".L() + "\(snapshot.totalAgentCount)" + "。".L()
                : "主要待处理：尚未巡检。请运行「持久终端可用性巡检」或启动真实终端工作区后复查；当前不会在界面刷新时读取终端状态。".L()
        )
    }
    public func startTerminalWorkspaceForSelectedProduct() {
        ensureRuntimeSessionsForSelectedProduct()
        syncSelectedProductAgentWorkspaces()
        ensureCLIWorktreeIsolationForSelectedProduct()

        let sessionName = terminalWorkspaceSessionName()
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else {
            let report = terminalWorkspacePlanText()
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .warning, title: "真实终端工作区".L(), detail: report), at: 0)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
            appendEvent(kind: .risk, title: "真实终端工作区未启动".L(), detail: "未找到终端工具，请安装或配置终端工具后重试。".L(), agentID: ctoID)
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
                appendEvent(kind: .risk, title: "真实终端工作区启动失败".L(), detail: result.output, agentID: ctoID)
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
                appendTerminalLog("\n[OPC 真实终端工作区]\n员工终端席位已创建。\n".L() + "\(capture.output)" + "\n".L(), for: agent.id)
            }
        }

        let report = terminalWorkspacePlanText()
        verifications.insert(VerificationRecord(productID: selectedProductID, status: .passed, title: "真实终端工作区".L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .artifactCreated, title: "真实终端工作区已启动".L(), detail: "\(executableAgents.count)" + " 个员工终端席位".L(), agentID: ctoID)
        refreshTerminalWorkspaceHealthSnapshot()
        saveSnapshot()
    }
    public func refreshTerminalWorkspaceLogsForSelectedProduct() {
        let sessionName = terminalWorkspaceSessionName()
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux"),
              tmuxSessionExists(sessionName, tmuxPath: tmuxPath)
        else {
            let report = terminalWorkspacePlanText()
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .warning, title: "真实终端日志刷新".L(), detail: report), at: 0)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "真实终端日志刷新未完成：还没有可捕获的真实终端工作区。\n\n".L() + "\(report)"))
            appendEvent(kind: .risk, title: "真实终端工作区未找到".L(), detail: "当前产品还没有可捕获的真实终端工作区。".L(), agentID: ctoID)
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
            appendTerminalLog("\n[OPC 真实终端日志刷新]\n员工终端席位已刷新。\n".L() + "\(output)" + "\n".L(), for: agent.id)
        }

        let report = """
        \("真实终端日志刷新：".L())\(capturedCount > 0 ? "完成" : "没有可写入内容")
        \("产品：".L())\(selectedProduct?.name ?? "当前产品")
        \("捕获席位：".L())\(capturedCount)/\(executableAgents.count)
        """
        verifications.insert(VerificationRecord(productID: selectedProductID, status: capturedCount > 0 ? .passed : .warning, title: "真实终端日志刷新".L().L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: capturedCount > 0 ? .artifactCreated : .risk, title: "真实终端日志刷新完成".L().L(), detail: "捕获 " + "\(capturedCount)" + " 个员工终端席位", agentID: ctoID)
        saveSnapshot()
    }
    public func terminalWorkspaceSessionNameForTesting() -> String {
        terminalWorkspaceSessionName()
    }
    public func terminalWorkspaceWindowNameForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        return terminalWorkspaceWindowName(for: agent)
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
    public func cliRecoveryAdvice(for agentID: UUID) -> CLIRecoveryAdviceEntry? {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return nil }
        let session = runtimeSessions[agentID]
        let phase = session?.cliInteractionPhase
        let action = session?.cliInteractionRecoveryAction
            ?? phase.map { CLIInteractionStateMachine.recoveryAction(for: $0) }
            ?? .noAction
        let phaseTitle = session?.cliInteractionReason ?? "尚未观察".L().L()
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
    public func cliRecoveryAdvicesForSelectedProduct() -> [CLIRecoveryAdviceEntry] {
        selectedProductAgents
            .filter { $0.role != .boss }
            .compactMap { cliRecoveryAdvice(for: $0.id) }
    }
    @discardableResult
    public func manualRetryTransientForAgent(agentID: UUID) -> CLIRecoveryRetryReport {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return CLIRecoveryRetryReport(success: false, reason: "未找到该员工，无法发起手动重试。".L().L())
        }
        guard agent.role != .boss else {
            return CLIRecoveryRetryReport(success: false, reason: "老板视角不参与命令行手动重试。".L().L())
        }
        guard let advice = cliRecoveryAdvice(for: agentID), advice.canManualRetry else {
            let phaseTitle = runtimeSessions[agentID]?.cliInteractionReason ?? "尚未观察".L().L()
            return CLIRecoveryRetryReport(success: false, reason: "当前状态为「".L().L() + "\(phaseTitle)" + "」，不在「临时异常」范围内，已拒绝手动重试。".L().L())
        }
        guard !isRunning(agentID: agentID) else {
            return CLIRecoveryRetryReport(success: false, reason: "\(agent.displayName)" + " 当前正在运行任务，请等待完成后再发起手动重试。".L().L())
        }
        restartAgentSession(agentID: agentID, reason: "技术负责人针对临时异常手动发起一次重开。".L().L())
        return CLIRecoveryRetryReport(success: true, reason: "已为 ".L().L() + "\(agent.displayName)" + " 发起一次受控的手动重试。".L().L())
    }
    @discardableResult
    public func runManualREPLTurnForSelectedAgent(text: String, timeoutSeconds: TimeInterval = 8) async -> ManualREPLTurnReport {
        if text.contains(where: { $0.isNewline }) {
            return ManualREPLTurnReport(summary: "未发送".L().L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "为避免多行粘贴误触发，长期会话输入一次只允许一行。".L().L())
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ManualREPLTurnReport(summary: "未发送".L().L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "请先输入要发送给员工长期席位的一行内容。".L().L())
        }
        guard let agent = selectedAgent, agent.role != .boss else {
            return ManualREPLTurnReport(summary: "未发送".L().L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "请先在员工列表选中一名要交互的员工，老板视角不参与手动交互轮次。".L().L())
        }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            return ManualREPLTurnReport(summary: "未发送".L().L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "该员工还未加入当前产品团队，请先在产品详情里加入团队。".L().L())
        }
        guard let result = await runPersistentTerminalREPLTurn(cleaned, to: agent, timeoutSeconds: max(timeoutSeconds, 0.1)) else {
            return ManualREPLTurnReport(summary: "未发送".L().L(), outputPreview: "", timedOut: false, rejected: true, rejectionReason: "未找到可用的真实终端席位。请先在维护区点击「启动真实终端工作区」并确认终端工具已就绪。".L().L())
        }
        let preview = String(result.output.prefix(240))
        if result.exitCode == 126 || result.exitCode == 127 {
            return ManualREPLTurnReport(summary: result.observation.reasonTitle, outputPreview: "", timedOut: false, rejected: true, rejectionReason: result.output)
        }
        let summary = result.timedOut ? "等待超时，未中断终端席位".L().L() : result.observation.reasonTitle
        return ManualREPLTurnReport(summary: summary, outputPreview: preview, timedOut: result.timedOut, rejected: false, rejectionReason: nil)
    }
    func terminalAutoInteractionReadinessAuditForTesting(for agent: CompanyAgent) -> TerminalAutoInteractionReadinessAudit {
        terminalAutoInteractionReadinessAudit(for: agent)
    }
    func terminalAutoInteractionReadinessAudit(for agent: CompanyAgent) -> TerminalAutoInteractionReadinessAudit {
        let profile = CLIAgentCommandBuilder.interactionProfile(for: agent)
        let protocolName = profile?.displayName ?? "订阅制命令行".L().L()

        guard agent.backend.type == .subscriptionCLI else {
            return readinessAuditFailed(
                reason: "该员工不是订阅制命令行员工，真实终端自动交互循环已拒绝。".L().L(),
                detail: "未匹配订阅制命令行来源".L().L()
            )
        }
        guard currentRuntimeCapability(for: agent) == .persistentProtocol else {
            return readinessAuditFailed(
                reason: "该员工来源不支持持续交互，真实终端自动交互循环已拒绝。".L().L(),
                detail: "员工来源不支持持续交互".L().L()
            )
        }
        guard let profile, !profile.replReadySignals.isEmpty else {
            return readinessAuditFailed(
                reason: "该员工命令行工具没有配置专用就绪提示，真实终端自动交互循环已拒绝。".L().L(),
                detail: "\(protocolName)" + " 缺少专用就绪提示配置".L().L()
            )
        }
        guard let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux") else {
            return readinessAuditFailed(
                reason: "未找到本机终端控制工具，请先完成终端工具安装或配置。".L().L(),
                detail: "未找到本机终端控制工具".L().L()
            )
        }
        let sessionName = terminalWorkspaceSessionName()
        let windowName = terminalWorkspaceWindowName(for: agent)
        guard tmuxSessionExists(sessionName, tmuxPath: tmuxPath) else {
            return readinessAuditFailed(
                reason: "请先在维护区点击「启动真实终端工作区」，再启动真实终端自动交互循环。".L().L(),
                detail: "真实终端工作区尚未启动".L().L()
            )
        }
        guard tmuxWindowNames(sessionName, tmuxPath: tmuxPath).contains(windowName) else {
            return readinessAuditFailed(
                reason: "当前员工真实终端席位还未创建，请先启动真实终端工作区并确认席位齐全。".L().L(),
                detail: "员工真实终端席位未创建".L().L()
            )
        }
        let capture = runLocalProcess(
            executable: tmuxPath,
            arguments: ["capture-pane", "-p", "-t", "\(sessionName):\(windowName)", "-S", "-200"],
            workingDirectory: cliWorkingDirectoryURL()
        )
        guard capture.exitCode == 0 else {
            return readinessAuditFailed(
                reason: "读取员工真实终端席位失败，请先运行持久终端可用性巡检。".L().L(),
                detail: "读取员工真实终端席位失败".L().L()
            )
        }
        guard profile.endsWithReplReadyPrompt(capture.output) else {
            return readinessAuditFailed(
                reason: "该员工终端席位最近一行不是 ".L().L() + "\(profile.displayName)" + " 的专用就绪提示，已拒绝自动发送。".L().L(),
                detail: "终端最近一行未命中 ".L().L() + "\(profile.displayName)" + " 专用就绪提示".L().L()
            )
        }
        return TerminalAutoInteractionReadinessAudit(
            rejectionReason: nil,
            auditLine: "就绪校验：最近一行已确认 ".L().L() + "\(profile.displayName)" + " 的专用就绪提示。".L().L()
        )
    }
    func appendTerminalAutoInteractionAuditLog(agent: CompanyAgent, audit: TerminalAutoInteractionReadinessAudit) {
        appendTerminalLog(
            "\n[OPC 自动循环就绪审计]\n".L().L() + "\(audit.auditLine)" + "\n",
            for: agent.id
        )
    }
    /// 把真实终端自动循环 preflight 审计结果以中文结构化形式写入产品级验证记录，
    /// 便于技术负责人维护侧通过架构体检和验证记录列表回看；
    /// 老板总控台和交付验收中心会过滤该维护记录，标题和正文也不包含底层参数、`rawValue` 或后端签名字段。
    func recordTerminalAutoInteractionAuditVerification(agent: CompanyAgent, audit: TerminalAutoInteractionReadinessAudit) {
        let employee = "\(agent.displayName)（\(agent.role.title)）"
        let status: VerificationStatus = audit.rejectionReason == nil ? .passed : .warning
        var detailLines: [String] = [
            "员工：".L().L() + "\(employee)",
            audit.auditLine
        ]
        if let reason = audit.rejectionReason {
            detailLines.append("拒绝说明：".L().L() + "\(reason)")
        }
        detailLines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不创建命令行作业档案、不写老板聊天。".L().L())
        let record = VerificationRecord(
            productID: selectedProductID,
            status: status,
            title: Self.terminalAutoInteractionAuditTitle,
            detail: detailLines.joined(separator: "\n")
        )
        verifications.insert(record, at: 0)
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
    func recordTerminalAutoInteractionStopAuditIfNeeded(
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
            "员工：".L().L() + "\(employee)",
            "停止原因：".L().L() + "\(stopReason.title)",
            "操作建议：".L().L() + "\(stopReason.operatorHint)",
            "已发送轮次：".L().L() + "\(finalState.sentInputs.count)" + " / " + "\(finalState.maxTurns)",
            "说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不创建命令行作业档案、不写老板聊天。".L().L()
        ]
        let record = VerificationRecord(
            productID: selectedProductID,
            status: .warning,
            title: Self.terminalAutoInteractionStopAuditTitle,
            detail: detailLines.joined(separator: "\n")
        )
        verifications.insert(record, at: 0)
        appendTerminalLog(
            "\n[OPC 自动循环停止审计]\n停止原因：".L().L() + "\(stopReason.title)" + "。\n操作建议：".L().L() + "\(stopReason.operatorHint)" + "\n",
            for: agent.id
        )
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
    func ensureCLIWorktreeIsolationForSelectedProduct() {
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
                \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
                \("产品工作目录：".L())\(workingDirectory.path)
                \("源码执行区：".L())\(sourceDirectory.path)
                \("隔离模式：".L())\(isGitRepository ? "代码仓库独立工作区".L() : "源码快照隔离".L())

                \("这个目录用于代码类员工的隔离执行。并行实现产生的改动需要经过审查和验收后，才应合入主产品工作目录。".L())
                """
                try marker.write(to: directory.appendingPathComponent("WORKTREE.md"), atomically: true, encoding: .utf8)
            } catch {
                appendEvent(kind: .risk, title: "独立执行区创建失败".L(), detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
            }
        }
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
        \("多员工架构体检：".L())\(selectedProduct?.name ?? "当前产品".L())
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
        appendEvent(kind: .ctoSummary, title: "多员工架构体检已生成".L(), detail: "完成度 ".L() + "\(selectedProductArchitectureCompletionScore)" + "%".L(), agentID: ctoID)
        saveSnapshot()
    }
    /// 终端大厅员工卡顶部默认可见的会话续跑单行（产品层文案）。
    ///
    /// 该行直接出现在老板/技术负责人的默认卡片上，必须用产品语言：只保留品牌名 +
    /// 是否能按产品续跑结论。底层协议名、状态机画像和诊断信号关键词只留在维护逻辑。
    public func terminalHallCardLongSessionLine(for agent: CompanyAgent) -> String? {
        guard let summary = terminalHallCardLongSessionProductSummary(for: agent) else {
            return nil
        }
        return "会话续跑：".L() + "\(summary.brand)" + " · ".L() + "\(summary.resumeLabel)"
    }
    public func terminalHallCardLongSessionDetail(for agent: CompanyAgent) -> String? {
        guard let summary = terminalHallCardLongSessionProductSummary(for: agent) else {
            return nil
        }
        let scopeLabel = summary.supportsResume ? "可识别历史会话并按产品接续".L() : "仅使用当前任务上下文".L()
        return "会话续跑详情：".L() + "\(summary.brand)" + " · ".L() + "\(summary.resumeLabel)" + " · ".L() + "\(scopeLabel)"
    }
    public func terminalHallCardInjectionHint() -> String {
        "自动注入：角色档案 · 记忆 · 技能 · 产品工作区。".L()
    }
    func visibleCommandToolName(for agent: CompanyAgent) -> String {
        opcBackendCommandDisplayName(agent.backend.command)
    }
    public func cliPreflightText(for agentID: UUID, prompt: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return "未找到员工，无法生成运行前预检。".L()
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
    /// 把 cliExecutionDirectoryURL(for:) 与 cliWorkingDirectoryURL() 的对比结果折叠成
    /// 中文抽象标签：「主工作区」或「独立执行区」。卡片摘要使用，避免重复路径比较逻辑。
    func cliExecutionLocationLabel(for agent: CompanyAgent) -> String {
        cliExecutionDirectoryURL(for: agent).standardizedFileURL.path
            == cliWorkingDirectoryURL().standardizedFileURL.path
            ? "主工作区".L()
            : "独立执行区".L()
    }
    /// 抽取出风险提示生成逻辑，让完整 `cliPreflightText` 与卡片摘要共享同一份中文规则。
    func preflightRiskLines(for agent: CompanyAgent) -> [String] {
        [
            agent.permissions.contains(.editFiles) ? "可能编辑文件".L() : nil,
            agent.permissions.contains(.runCommands) ? "可能执行命令".L() : nil,
            agent.permissions.contains(.runTests) ? "可能运行测试".L() : nil,
            agent.permissions.contains(.useNetwork) ? "可能使用网络".L() : nil,
            agent.backend.type == .api ? "会使用接口地址，不在终端运行摘要中显示密钥".L() : nil
        ].compactMap { $0 }
    }
    public func recordCLIPreflight(agentID: UUID, prompt: String) {
        let report = cliPreflightText(for: agentID, prompt: prompt)
        appendTerminalLog("\n[OPC 运行前预检]\n".L() + "\(report)" + "\n".L(), for: agentID)
        appendEvent(kind: .commandPlanned, title: "命令行运行前预检".L(), detail: agentName(agentID), agentID: agentID)
        saveSnapshot()
    }
    public func visibleTerminalLog(for agentID: UUID) -> String {
        let log = terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true)
        guard !log.isEmpty else { return "暂无终端输出。".L() }
        let productScoped = filterTerminalLogForSelectedProductDisplay(log)
        guard !productScoped.isEmpty else { return "暂无终端输出。".L() }
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
            return "等待派发任务，运行后此处显示终端输出。".L()
        }
        return "暂无终端输出。".L()
    }
    public func terminalAgentCardIsIdle(agentID: UUID) -> Bool {
        !isRunning(agentID: agentID) && terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true).isEmpty
    }
    public func terminalAgentCardHasClearableLog(for agentID: UUID) -> Bool {
        !terminalLogForCurrentProduct(agentID: agentID, includingLegacyFallbackForTests: true).isEmpty
    }
    func terminalLogStorageKey(productID: UUID, agentID: UUID) -> String {
        "\(productID.uuidString.lowercased()):\(agentID.uuidString.lowercased())"
    }
    func terminalLog(agentID: UUID, productID: UUID) -> String {
        productTerminalLogs[terminalLogStorageKey(productID: productID, agentID: agentID), default: ""]
    }
    func terminalLogForCurrentProduct(
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
    func appendTerminalLog(_ text: String, for agentID: UUID, productID: UUID? = nil) {
        let scopedProductID = productID ?? selectedProductID
        let key = terminalLogStorageKey(productID: scopedProductID, agentID: agentID)
        productTerminalLogs[key, default: ""].append(text)
        terminalLogs[agentID, default: ""].append(text)
    }
    func setTerminalLog(_ text: String, for agentID: UUID, productID: UUID? = nil) {
        let scopedProductID = productID ?? selectedProductID
        let key = terminalLogStorageKey(productID: scopedProductID, agentID: agentID)
        productTerminalLogs[key] = text
        terminalLogs[agentID] = text
    }
    @discardableResult
    func migrateLegacyTerminalLogsToProductScopedLogs(saveAfterChange: Bool = true) -> Bool {
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
    func inferredProductIDForLegacyTerminalLog(_ log: String) -> UUID? {
        for product in products {
            let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if log.contains("产品：".L() + "\(name)") || log.contains("当前产品：".L() + "\(name)") {
                return product.id
            }
        }
        return nil
    }
    func filterTerminalLogForSelectedProductDisplay(_ log: String) -> String {
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
    func terminalLogBlockBelongsToOtherProduct(
        _ block: [String],
        selectedName: String,
        otherProductNames: [String]
    ) -> Bool {
        for line in block {
            guard line.contains("当前产品：".L()) || line.contains("产品：".L()) else { continue }
            if line.contains(selectedName) {
                return false
            }
            if line.contains("当前产品：".L()) {
                return true
            }
            if otherProductNames.contains(where: { line.contains($0) }) {
                return true
            }
        }
        return false
    }
    func sanitizeTerminalLogForDisplay(_ log: String) -> String {
        log
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Bilingual prefix match: historical logs may have been generated in the other language.
                let readyPrefixes = ["本地命令已就绪：", "Local command ready: "]
                if let matched = readyPrefixes.first(where: { trimmed.hasPrefix($0) }) {
                    let rawValue = String(trimmed.dropFirst(matched.count))
                    return "本地命令已就绪：".L() + "\(opcBackendCommandDisplayName(rawValue))"
                }
                if line.contains("App 启动后预热当前产品团队".L()) {
                    return line.replacingOccurrences(of: "App 启动后预热当前产品团队".L(), with: "应用启动后预热当前产品团队".L())
                }
                let residentPrefixes = ["常驻能力：", "Resident capability: "]
                if let matched = residentPrefixes.first(where: { trimmed.hasPrefix($0) }) {
                    let rawValue = String(trimmed.dropFirst(matched.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " 。."))
                    let displayValue: String
                    if rawValue.contains("常驻".L()) || rawValue.contains("长期".L()) || rawValue.contains("可接".L()) {
                        displayValue = AgentRuntimeCapability.persistentProtocol.title
                    } else {
                        displayValue = rawValue.isEmpty ? AgentRuntimeCapability.persistentProtocol.title : rawValue
                    }
                    return "持续协作：".L() + "\(displayValue)" + "。".L()
                }
                if trimmed.hasPrefix("$ "),
                   line.contains("model_reasoning_effort") ||
                   line.contains("--skip-git-repo-check") ||
                   line.contains("--permission-mode") {
                    return "底层命令已隐藏，详见命令行作业档案。".L()
                }
                if line.contains("model_reasoning_effort") || line.contains("--skip-git-repo-check") {
                    return line
                        .replacingOccurrences(of: "model_reasoning_effort", with: "推理强度".L())
                        .replacingOccurrences(of: "--skip-git-repo-check", with: "仓库检查参数".L())
                }
                return line
            }
            .joined(separator: "\n")
    }
    func compactTerminalWorkspaceTranscriptsForDisplay(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[OPC 真实终端工作区]".L() else {
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
                if current.contains("员工终端席位已创建".L()) {
                    created = true
                }
                end += 1
            }

            output.append("[OPC 真实终端工作区摘要]".L())
            output.append(created ? "员工终端席位已创建。".L() : "员工终端席位已记录。".L())
            output.append("执行位置：本地工作区".L())
            output.append("结论：真实终端席位已就绪，完整启动记录保留在维护档案。".L())
            index = end
        }

        return output.joined(separator: "\n")
    }
    func compactCompletedCommandTranscriptsForDisplay(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n")

        func firstLine(in range: Range<Int>, prefixedBy prefix: String) -> String? {
            for index in range where lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(prefix) {
                return lines[index].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        func summaryBlock(from start: Int, to end: Int) -> [String] {
            let range = start..<end
            var summary: [String] = ["[OPC 命令行任务摘要]".L()]
            for prefix in ["执行位置：".L(), "运行方式：".L(), "任务摘要：".L()] {
                if let line = firstLine(in: range, prefixedBy: prefix) {
                    summary.append(line)
                }
            }
            if let exitLine = firstLine(in: range, prefixedBy: "[命令退出码 ".L()) {
                let exitCode = exitLine
                    .replacingOccurrences(of: "[命令退出码 ".L(), with: "")
                    .replacingOccurrences(of: "]", with: "")
                summary.append("退出码：".L() + "\(exitCode)")
            }
            if let statusLine = firstLine(in: range, prefixedBy: "状态：".L()) {
                summary.append(statusLine)
            }
            summary.append("完整输出保留在命令行作业档案。".L())
            return summary
        }

        var output: [String] = []
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[OPC 命令行任务]".L() else {
                output.append(lines[index])
                index += 1
                continue
            }

            let searchEnd = lines.count
            var exitIndex: Int?
            for candidate in (index + 1)..<searchEnd {
                let candidateLine = lines[candidate].trimmingCharacters(in: .whitespaces)
                if candidateLine.hasPrefix("[命令退出码 ".L()) {
                    exitIndex = candidate
                    break
                }
                if candidateLine == "[OPC 命令行任务]".L() {
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
               lines[end].trimmingCharacters(in: .whitespaces) == "[OPC 交互状态]".L() {
                end += 1
                while end < lines.count {
                    let statusTrimmed = lines[end].trimmingCharacters(in: .whitespaces)
                    if statusTrimmed.hasPrefix("[OPC ") && statusTrimmed.hasSuffix("]") {
                        break
                    }
                    if statusTrimmed.hasPrefix("[") && statusTrimmed.hasSuffix("]") && !statusTrimmed.hasPrefix("[命令退出码 ".L()) {
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
        \("命令行链路压测预检：".L())\(issueLines.isEmpty ? "通过".L() : "发现 " + "\(issueLines.count)" + " 项问题")
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
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
        verifications.insert(VerificationRecord(productID: selectedProductID, status: status, title: "命令行链路压测预检".L(), detail: report), at: 0)
        for agent in executableAgents {
            appendTerminalLog("\n[OPC 命令行链路压测预检]\n\(cliPreflightText(for: agent.id, prompt: "命令行链路体检"))\n", for: agent.id)
        }
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: status == .passed ? .artifactCreated : .risk, title: "命令行链路压测预检完成".L(), detail: status.title, agentID: ctoID)
        saveSnapshot()
    }
}
