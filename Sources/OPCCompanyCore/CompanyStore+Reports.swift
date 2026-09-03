import Foundation
import SQLite3

// MARK: - Reports
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {

    /// Boss-facing closed-loop summary line (localized).
    static func bossLoopSummaryText(_ trace: MultiAgentClosureTrace) -> String {
        let head = "最近闭环：".L().L()
        let mid = "消息 ".L()
        let tail = "产物 ".L()
        return head + "\(trace.goal) · \(trace.completionScore)% · " + mid + "\(trace.messageIDs.count) · " + tail + "\(trace.artifactIDs.count)"
    }
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
    func closureDrillGoal(for goal: String) -> String {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.closureDrillGoalMarkerForms.contains(where: { cleanGoal.hasPrefix($0) }) { return cleanGoal }
        return "\(Self.closureDrillGoalMarker) \(cleanGoal)"
    }
    func closureDrillDisplayGoal(_ goal: String) -> String {
        var result = goal
        for form in Self.closureDrillGoalMarkerForms {
            result = result.replacingOccurrences(of: "\(form) ", with: "")
            result = result.replacingOccurrences(of: form, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func isClosureDrillTask(_ task: CompanyTask) -> Bool {
        Self.closureDrillGoalMarkerForms.contains(where: { task.title.contains($0) })
            || Self.closureDrillGoalMarkerForms.contains(where: { task.successCriteria.contains($0) })
    }
    func isClosureDrillTaskID(_ taskID: UUID?) -> Bool {
        guard let taskID,
              let task = tasks.first(where: { $0.id == taskID })
        else { return false }
        return isClosureDrillTask(task)
    }
    func isClosureDrillArtifact(_ record: ArtifactRecord) -> Bool {
        Self.closureDrillGoalMarkerForms.contains(where: { record.title.contains($0) })
            || Self.closureDrillGoalMarkerForms.contains(where: { record.summary.contains($0) })
            || isClosureDrillTaskID(record.taskID)
    }
    func isClosureDrillVerification(_ record: VerificationRecord) -> Bool {
        record.title.contains(Self.closureDrillGoalMarker)
            || record.detail.contains(Self.closureDrillGoalMarker)
    }
    func isClosureDrillEvent(_ event: CompanyEvent) -> Bool {
        event.title.contains(Self.closureDrillGoalMarker)
            || event.detail.contains(Self.closureDrillGoalMarker)
            || event.title.contains("闭环演练".L().L())
            || event.detail.contains("闭环演练".L().L())
    }
    func isClosureDrillAgentMessage(_ message: AgentMessageEnvelope) -> Bool {
        message.subject.contains(Self.closureDrillGoalMarker)
            || message.body.contains(Self.closureDrillGoalMarker)
            || isClosureDrillTaskID(message.taskID)
    }
    /// 中文预览（不写入快照）：当前产品的未分类证据巡检结果。
    public func evidenceClassificationAuditText() -> String {
        let unclassifiedVR = selectedProductUnclassifiedVerificationRecords
        let unclassifiedAR = selectedProductUnclassifiedArtifactRecords
        var lines: [String] = [
            "运行证据分类巡检：".L().L() + "\(selectedProduct?.name ?? "当前产品")",
            "未分类验证记录：".L().L() + "\(unclassifiedVR.count)" + " 条".L().L(),
            "未分类产物档案：".L().L() + "\(unclassifiedAR.count)" + " 条".L().L()
        ]
        if !unclassifiedVR.isEmpty {
            lines.append("⚠️ 未分类验证记录会从老板/交付视图过滤掉，也不在维护视图——请把标题登记到「技术维护」或「交付验收」分类清单。".L().L())
            for record in unclassifiedVR.prefix(10) {
                lines.append("- " + "\(record.title)" + "（状态：".L().L() + "\(record.status.title)" + "）")
            }
        }
        if !unclassifiedAR.isEmpty {
            lines.append("⚠️ 未分类结构化产物会按默认进入老板/交付视图——请把标题登记到「技术维护」或「交付验收」的产物分类清单。".L().L())
            lines.append("识别规则：标题含全角「：」或半角「: 」（冒号 + 空格，前缀不含 `/` `\\` 路径标记）视为结构化前缀；URL、文件路径、时间戳和普通动态文件名不会被巡检报告。".L().L())
            for record in unclassifiedAR.prefix(10) {
                lines.append("- \(record.title)")
            }
        }
        if unclassifiedVR.isEmpty && unclassifiedAR.isEmpty {
            lines.append("结论：当前产品所有运行证据都已显式分类。".L().L())
        } else {
            lines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不删除任何证据。".L().L())
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
            title: "运行证据分类巡检".L().L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        return record
    }
    func currentProductJobArchiveStorageSummary() -> (jobCount: Int, bytes: Int64) {
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
            nextStep = "下一步：先在老板决策中心处理 ".L().L() + "\(pendingApprovals)" + " 项待审批。".L().L()
        } else if blocked > 0 {
            nextStep = "下一步：阻塞/失败任务 ".L().L() + "\(blocked)" + " 项，请在产品详情或员工工作台跟进。".L().L()
        } else if recentRisks > 0 {
            nextStep = "下一步：最近风险 ".L().L() + "\(recentRisks)" + " 条，可在事件流核对。".L().L()
        } else if running == 0 && team > 0 {
            nextStep = "下一步：选择员工运行任务，或在下方摘要工作台运行常用巡检。".L().L()
        } else {
            nextStep = "下一步：保持运行；下方摘要工作台展示架构 / 通信 / 维护核心指标。".L().L()
        }
        return [
            "终端大厅运行状态：".L().L() + "\(selectedProduct?.name ?? "当前产品")",
            "团队 ".L().L() + "\(team)" + " 人 · 运行中 ".L().L() + "\(running)" + " · 待审批 ".L().L() + "\(pendingApprovals)" + " · 阻塞/失败 ".L().L() + "\(blocked)" + " · 最近风险 ".L().L() + "\(recentRisks)",
            nextStep,
            "提示：下方摘要工作台默认可见架构体检 / 通信网关 / 本地稳定性的状态、核心指标与主要操作；点击「查看详情」按需打开完整面板。".L().L()
        ].joined(separator: "\n")
    }
    /// 显式判定一条 `VerificationRecord` 是否属于"老板/交付视图应当展示"的真实交付证据。
    /// 与 `isTechnicalMaintenanceVerification` 不是简单互补——少数无名记录可能两边都不命中，
    /// 这种情况由源码扫描守门测试在 `swift test` 阶段强制让作者显式登记。
    public func isDeliveryVerification(_ record: VerificationRecord) -> Bool {
        if isClosureDrillVerification(record) { return false }
        if Self.deliveryVerificationTitleExactMatches.contains(record.title) { return true }
        return Self.deliveryVerificationTitlePrefixes.contains { record.title.hasPrefix($0) }
    }
    public func selectedProductMemoryOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductMemories.count
        let limit = Self.productMemoryDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 条长期记忆。关键决策、规则和风险会继续保留在产品记忆库。".L().L()
        )
    }
    public func closureTraceTasks(_ trace: MultiAgentClosureTrace) -> [CompanyTask] {
        let ids = Set(trace.taskIDs)
        let order = ["技术负责人拆解：".L().L(), "员工执行：".L().L(), "审查验收：".L().L(), "老板审批：".L().L()]
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

        let ctoTask = task(withPrefix: "技术负责人拆解：".L().L())
        let engineerTask = task(withPrefix: "员工执行：".L().L())
        let reviewerTask = task(withPrefix: "审查验收：".L().L())
        let bossTask = task(withPrefix: "老板审批：".L().L())

        let hasDispatch = messages.contains { $0.kind == .taskDispatched }
        let hasWorkCompleted = messages.contains { $0.kind == .workCompleted }
        let hasEmployeeHandoff = messages.contains { $0.kind == .employeeHandoff }
        let hasReviewRequested = messages.contains { $0.kind == .reviewRequested }
        let hasReviewCompleted = messages.contains { $0.kind == .reviewCompleted }
        let hasApprovalRequested = messages.contains { $0.kind == .approvalRequested }
        let hasApprovalDecided = messages.contains { $0.kind == .approvalDecided }
        let hasAcceptanceCompleted = messages.contains { $0.kind == .acceptanceCompleted }

        let nodes = [
            ctoTask.map { node(for: $0, role: "技术负责人".L().L()) },
            engineerTask.map { node(for: $0, role: "执行员工".L().L()) },
            reviewerTask.map { node(for: $0, role: "审查员".L().L()) },
            bossTask.map { node(for: $0, role: "老板".L().L()) }
        ].compactMap { $0 }

        let edges = [
            edge(
                "dispatch",
                from: ctoTask,
                to: engineerTask,
                relation: "任务派发".L().L(),
                checks: [hasDispatch],
                evidence: hasDispatch ? "消息总线已记录技术负责人派发任务。".L().L() : "缺少任务派发消息。".L().L()
            ),
            edge(
                "review",
                from: engineerTask,
                to: reviewerTask,
                relation: "执行回传与审查".L().L(),
                checks: [hasWorkCompleted, hasReviewRequested],
                evidence: "员工回传 ".L().L() + "\(hasWorkCompleted ? "已记录".L() : "未记录".L())" + "；员工交接 ".L().L() + "\(hasEmployeeHandoff ? "已记录".L() : "未记录".L())" + "；审查请求 ".L().L() + "\(hasReviewRequested ? "已记录".L() : "未记录".L())"
            ),
            edge(
                "approval",
                from: reviewerTask,
                to: bossTask,
                relation: "审查结论与审批".L().L(),
                checks: [hasReviewCompleted, hasApprovalRequested],
                evidence: "审查结论 ".L() + "\(hasReviewCompleted ? "已记录".L() : "未记录".L())" + "；审批请求 ".L().L() + "\(hasApprovalRequested ? "已记录".L() : "未记录".L())" + "。"
            ),
            edge(
                "acceptance",
                from: bossTask,
                to: ctoTask,
                relation: "老板决策回流".L().L(),
                checks: [hasApprovalDecided, hasAcceptanceCompleted],
                evidence: "审批结果 ".L() + "\(hasApprovalDecided ? "已记录".L() : "未记录".L())" + "；验收回流 ".L().L() + "\(hasAcceptanceCompleted ? "已记录".L() : "未记录".L())"
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
                ? "老板审批仍在等待 ".L() + "\(pendingApprovals)" + " 项，可进入老板决策中心确认。".L()
                : (blockingVerifications > 0
                   ? "验收记录里仍有 ".L() + "\(blockingVerifications)" + " 项不为通过，建议复看交付验收中心。".L()
                   : "闭环已通过，可在老板视图按「看结果/批风险/验交付」流程收尾。".L())
        case .warning:
            nextStep = blockingGates > 0
                ? "审查门禁有 ".L() + "\(blockingGates)" + " 项告警，请审查员补充结论或补充证据。".L()
                : (pendingApprovals > 0
                   ? "存在 ".L() + "\(pendingApprovals)" + " 项待审批，先让老板裁定再继续。".L()
                   : "完成度 ".L() + "\(trace.completionScore)" + "%，还差几步，可继续推进技术负责人调度循环。".L())
        case .failed:
            nextStep = "闭环失败：完成度 ".L() + "\(trace.completionScore)" + "%，请回到任务图查清阻塞，必要时回滚或拆解新目标。".L()
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
            let taskTitle = tasks.first { $0.id == item.taskID }?.title ?? "未知任务".L()
            let reason = reworkReason(from: item.promptPreview) ?? "未记录原因".L()
            return "- ".L() + "\(taskTitle)" + "：".L() + "\(item.status.title)" + "，执行员工 ".L() + "\(agentName(item.agentID))" + "，原因：".L() + "\(reason)"
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
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
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
            appendEvent(kind: .statusChanged, title: "闭环审计报告已存在".L(), detail: "未重复创建：".L() + "\(trace.goal)", agentID: ctoID)
            saveSnapshot()
            return true
        }

        let report = closureTraceAuditText(trace)
        let artifact = ArtifactRecord(
            productID: trace.productID,
            kind: .report,
            title: closureTraceAuditReportTitle(for: trace),
            path: path,
            summary: "多员工闭环 ".L() + "\(trace.completionScore)" + "%：任务 ".L() + "\(trace.taskIDs.count)" + "，消息 ".L() + "\(trace.messageIDs.count)" + "，产物 ".L() + "\(trace.artifactIDs.count)" + "，验收 ".L() + "\(trace.verificationIDs.count)" + "。".L()
        )
        artifacts.insert(artifact, at: 0)
        messages.append(ChatMessage(productID: trace.productID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: .artifactCreated, title: "闭环审计报告已生成".L(), detail: artifact.title, agentID: ctoID)
        saveSnapshot()
        return true
    }
    func closureTraceAuditReportPath(for trace: MultiAgentClosureTrace) -> String {
        "opc://closure-traces/\(trace.id)"
    }
    func closureTraceAuditReportTitle(for trace: MultiAgentClosureTrace) -> String {
        "闭环审计报告：".L() + "\(trace.goal)"
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
            let confirmation = "已生成公司状态简报并同步给技术负责人。".L().L()
            messages.append(ChatMessage(productID: selectedProductID, agentID: sourceAgentID, author: .system, text: confirmation))
            appendTerminalLog("\n[OPC] \(confirmation)\n", for: sourceAgentID)
        }
        appendEvent(kind: .ctoSummary, title: "技术负责人简报".L().L(), detail: "老板要求生成状态简报。".L().L(), agentID: ctoID)
        saveSnapshot()
    }
    public func requestCTOReview(for taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        messages.append(ChatMessage(productID: task.productID ?? selectedProductID, agentID: ctoID, author: .system, text: "请技术负责人复核任务：".L().L() + "\(task.title)" + "。验收标准：".L().L() + "\(task.successCriteria)"))
        upsertReviewGate(
            for: task,
            status: .reviewRequested,
            requesterID: bossID,
            reviewerID: ctoID,
            summary: "老板要求技术负责人复核任务，确认是否进入审查/验收。".L().L()
        )
        postAgentMessage(
            productID: task.productID ?? selectedProductID,
            fromAgentID: bossID,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewRequested,
            subject: "请求技术负责人复核：".L().L() + "\(task.title)",
            body: "请按验收标准复核任务，确认是否进入老板验收或返工。\n验收标准：".L().L() + "\(task.successCriteria)",
            persist: false
        )
        appendEvent(kind: .ctoSummary, title: "已要求技术负责人复核".L().L(), detail: task.title, agentID: ctoID)
        saveSnapshot()
    }
    func upsertReviewGate(
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
    public func bossInspectorCompactRecentReportsOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductBossEvents.count
        let limit = Self.bossInspectorCompactRecentReportsDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 条汇报。这里保留最近重点，更多汇报会随进展继续浮现。".L().L()
        )
    }
    public func commandCenterPendingApprovalsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductPendingApprovals.count,
            limit: Self.commandCenterPendingApprovalsDefaultDisplayLimit,
            noun: "项待处理审批".L().L(),
            continuation: "打开决策中心可处理完整队列。".L().L()
        )
    }
    public func commandCenterDecisionRiskTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRiskTasks.count,
            limit: Self.commandCenterDecisionRiskTasksDefaultDisplayLimit,
            noun: "项风险任务".L().L(),
            continuation: "打开决策中心可处理完整队列。".L().L()
        )
    }
    public func commandCenterDeliveryVerificationsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "条验收记录".L().L(),
            continuation: "打开交付验收中心可查看完整记录。".L().L()
        )
    }
    public func commandCenterDeliveryArtifactsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.commandCenterRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "项交付物".L().L(),
            continuation: "打开交付验收中心可查看完整记录。".L().L()
        )
    }
    public func commandCenterAcceptanceCriteriaTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentTasks.count,
            limit: Self.commandCenterAcceptanceCriteriaTasksDefaultDisplayLimit,
            noun: "项验收标准".L().L(),
            continuation: "完整任务和标准在产品详情任务看板。".L().L()
        )
    }
    public func productDetailDeliveryVerificationsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "条验收记录".L().L(),
            continuation: "查看全部可进入交付验收中心。".L().L()
        )
    }
    public func productDetailDeliveryArtifactsOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.productDetailRecentDeliveryRecordsDefaultDisplayLimit,
            noun: "项交付物".L().L(),
            continuation: "查看全部可进入交付验收中心。".L().L()
        )
    }
    public func deliveryAcceptanceCenterAcceptanceTasksOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductAcceptanceTasks.count,
            limit: Self.deliveryAcceptanceCenterAcceptanceTasksDisplayLimit,
            noun: "项验收任务".L().L()
        )
    }
    public func deliveryAcceptanceCenterReviewGatesOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductDeliveryReviewGates.count,
            limit: Self.deliveryAcceptanceCenterReviewGatesDisplayLimit,
            noun: "项审查门禁".L().L()
        )
    }
    public func deliveryAcceptanceCenterVerificationsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentDeliveryVerifications.count,
            limit: Self.deliveryAcceptanceCenterVerificationsDisplayLimit,
            noun: "条验收记录".L().L()
        )
    }
    public func deliveryAcceptanceCenterArtifactsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentDeliveryArtifacts.count,
            limit: Self.deliveryAcceptanceCenterArtifactsDisplayLimit,
            noun: "项交付物".L().L()
        )
    }
    public func bossReportCenterReportEventsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossReportEvents.count,
            limit: Self.bossReportCenterReportEventsDisplayLimit,
            noun: "条汇报事件".L().L()
        )
    }
    public func bossReportCenterBossMessagesOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossReportMessages.count,
            limit: Self.bossReportCenterBossMessagesDisplayLimit,
            noun: "条老板报告".L().L()
        )
    }
    public func bossDecisionCenterRiskEventsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductBossRiskEvents.count,
            limit: Self.bossDecisionCenterRiskEventsDisplayLimit,
            noun: "条风险事件".L().L()
        )
    }
    public func bossDecisionCenterResolvedApprovalsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductResolvedApprovals.count,
            limit: Self.bossDecisionCenterResolvedApprovalsDisplayLimit,
            noun: "项已处理决策".L().L()
        )
    }
    public func localMaintenanceArtifactsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentMaintenanceArtifacts.count,
            limit: Self.localMaintenanceArtifactDisplayLimit,
            noun: "项维护产物".L().L()
        )
    }
    /// 当前产品最近一次「运行会话健康巡检」VerificationRecord。
    /// 本地维护详情里运行会话健康巡检按钮下方就地预览用，按钮点击后会写入新记录，预览随之更新。
    public func selectedProductLatestRuntimeSessionHealthAudit() -> VerificationRecord? {
        selectedProductMaintenanceVerifications.first { $0.title == "运行会话健康巡检".L().L() }
    }
    public func agentDeskReviewQueueOverflow() -> AgentDeskListOverflow? {
        let total = selectedAgentReviewQueue.count
        let limit = Self.agentDeskReviewQueueDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 项待审任务。处理完上方任务后下一项会自动浮现。".L().L()
        )
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
            ? "\(reviewer.displayName)" + " 完成审查，任务可进入交付记录。".L().L()
            : cleanSummary

        updateTaskStatus(taskID, status: .done, note: "\(reviewer.displayName)" + " 已完成审查并签字通过。".L().L())
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: reviewer.id,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "审查通过：".L().L() + "\(task.title)",
            body: resolvedSummary,
            reviewOutcome: .passed,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationPassed,
            requesterID: ctoID,
            reviewerID: reviewer.id,
            summary: "审查员 ".L().L() + "\(reviewer.displayName)" + " 已签字通过：".L().L() + "\(resolvedSummary)"
        )
        appendEvent(
            kind: .ctoSummary,
            title: "审查员已完成审查".L().L(),
            detail: "\(reviewer.displayName)" + " 通过 ".L().L() + "\(task.title)" + "：" + "\(resolvedSummary)",
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
            ? "审查员 ".L().L() + "\(reviewer.displayName)" + " 打回返工，需补充材料或修复问题。".L().L()
            : cleanReason

        updateTaskStatus(taskID, status: .assigned, note: "\(reviewer.displayName)" + " 打回返工：".L().L() + "\(resolvedReason)")
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: reviewer.id,
            toAgentID: ctoID,
            taskID: task.id,
            kind: .reviewCompleted,
            subject: "审查不通过：".L().L() + "\(task.title)",
            body: resolvedReason,
            reviewOutcome: .rejected,
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .verificationWarning,
            requesterID: ctoID,
            reviewerID: reviewer.id,
            summary: "审查员 ".L().L() + "\(reviewer.displayName)" + " 打回返工：".L().L() + "\(resolvedReason)"
        )
        appendEvent(
            kind: .risk,
            title: "审查员打回返工".L().L(),
            detail: "\(reviewer.displayName)" + " 打回 ".L().L() + "\(task.title)" + "：" + "\(resolvedReason)",
            agentID: reviewer.id
        )
        requeueExecutionTaskAfterReviewRejection(reviewTask: task, reason: resolvedReason)
        saveSnapshot()
        return true
    }
    func requeueExecutionTaskAfterReviewRejection(reviewTask: CompanyTask, reason: String) {
        guard reviewTask.title.hasPrefix("审查验收：".L().L()),
              let goal = ctoSupervisorGoalKey(for: reviewTask),
              let executionTask = selectedProductTasks.first(where: {
                  $0.title == "员工执行：".L().L() + "\(goal)" && $0.productID == selectedProductID
              }),
              let executionOwnerID = executionTask.ownerID,
              selectedProductAgents.contains(where: { $0.id == executionOwnerID })
        else { return }

        updateTaskStatus(
            executionTask.id,
            status: .assigned,
            note: "审查打回返工：".L().L() + "\(reason)" + "。任务已重新进入 ".L().L() + "\(agentName(executionOwnerID))" + " 的执行队列。".L().L()
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
    func requestReviewAfterReworkCompletion(executionTask: CompanyTask, agentID: UUID, workItemID: UUID?, reason: String) {
        guard executionTask.title.hasPrefix("员工执行：".L()),
              let goal = ctoSupervisorGoalKey(for: executionTask),
              let reviewerTask = selectedProductTasks.first(where: {
                  $0.title == "审查验收：".L() + "\(goal)" && $0.productID == selectedProductID
              }),
              let reviewerID = reviewerTask.ownerID,
              selectedProductAgents.contains(where: { $0.id == reviewerID }),
              [.planned, .assigned, .needsReview].contains(reviewerTask.status)
        else { return }

        updateTaskStatus(
            reviewerTask.id,
            status: .needsReview,
            note: "\(agentName(agentID))" + " 已完成返工，重新提交 ".L() + "\(agentName(reviewerID))" + " 复审。".L()
        )
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: ctoID,
            toAgentID: reviewerID,
            taskID: reviewerTask.id,
            workItemID: workItemID,
            kind: .reviewRequested,
            subject: "返工后复审：".L() + "\(goal)",
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
            summary: "返工后重新提交复审：".L() + "\(reason)"
        )
        appendEvent(
            kind: .ctoSummary,
            title: "返工已重新提交复审".L(),
            detail: "\(agentName(agentID))" + " 完成 ".L() + "\(executionTask.title)" + "，已提交 ".L() + "\(agentName(reviewerID))" + " 复审。".L(),
            agentID: agentID
        )
    }
    func requestBossApprovalAfterSupervisorReviewPass(reviewTask: CompanyTask, summary: String) {
        guard reviewTask.title.hasPrefix("审查验收：".L()),
              let goal = ctoSupervisorGoalKey(for: reviewTask),
              let bossTask = selectedProductTasks.first(where: {
                  $0.title == "老板审批：".L() + "\(goal)" && $0.productID == selectedProductID
              }),
              !approvals.contains(where: { $0.taskID == bossTask.id && $0.status == .pending })
        else { return }

        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: bossTask.id,
            kind: .ctoLoopProgressed,
            subject: "技术负责人提交老板审批：".L() + "\(goal)",
            body: "审查员已签字通过，技术负责人已把结果提交老板决策中心。\n审查结论：".L() + "\(summary)",
            persist: false
        )
        requestApproval(
            taskID: bossTask.id,
            title: "请老板审批：".L() + "\(goal)",
            reason: "工程实现与审查均已完成，请老板做最终决策。\n审查结论：".L() + "\(summary)",
            requesterID: ctoID
        )
    }
    func finalizeSupervisorBossApprovalIfNeeded(approval: ApprovalRequest, approved: Bool) {
        guard let taskID = approval.taskID,
              let task = tasks.first(where: { $0.id == taskID }),
              task.title.hasPrefix("老板审批：".L())
        else { return }

        guard approved else {
            requeueSupervisorGoalAfterBossRejection(bossTask: task, approval: approval)
            return
        }

        completeSupervisorGoalTasks(for: task)
        updateTaskStatus(taskID, status: .done, note: "老板已批准最终交付，闭环已写入交付验收记录。".L())
        generateAcceptanceReport(for: taskID)
        acceptTask(taskID)
    }
    public func requestApproval(taskID: UUID?, title: String, reason: String, requesterID: UUID? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let resolvedReason = cleanReason.isEmpty ? "需要老板批准后继续执行。".L() : cleanReason
        let approval = ApprovalRequest(productID: selectedProductID, taskID: taskID, requesterID: requesterID, title: cleanTitle, reason: resolvedReason)
        approvals.insert(approval, at: 0)
        if let taskID {
            updateTaskStatus(taskID, status: .needsApproval)
        }
        appendEvent(kind: .risk, title: "审批请求已创建".L(), detail: cleanTitle, agentID: requesterID)
        let fromAgent = requesterID ?? ctoID
        postAgentMessage(
            productID: selectedProductID,
            fromAgentID: fromAgent,
            toAgentID: bossID,
            taskID: taskID,
            approvalID: approval.id,
            kind: .approvalRequested,
            subject: "审批请求：".L() + "\(cleanTitle)",
            body: resolvedReason,
            persist: false
        )
        saveSnapshot()
    }
}
