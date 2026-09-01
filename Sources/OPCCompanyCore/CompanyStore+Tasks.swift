import Foundation
import SQLite3

// MARK: - Tasks
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {

    public func legacyTaskProductMigrationText() -> String {
        let legacyCount = legacyTaskWithoutProductIDCount
        return """
        \("旧任务产品归属迁移：预览".L())
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
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
        let record = VerificationRecord(productID: selectedProductID, status: status, title: "旧任务产品归属迁移".L().L(), detail: detail)
        verifications.insert(record, at: 0)
        appendEvent(kind: .statusChanged, title: "旧任务产品归属迁移完成".L().L(), detail: "已迁移 ".L() + "\(migrated)" + " 个旧任务到当前产品，剩余 ".L() + "\(after)" + " 个。".L(), agentID: ctoID)
        saveSnapshot()
        return record
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
            title: "员工协作收件箱已确认一条".L(),
            detail: "\(agentName(agentID))" + " 已确认「".L() + "\(agentMessages[index].subject)" + "」。".L(),
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
                title: "员工协作收件箱已标记已读".L(),
                detail: "\(agentName(agentID))" + " 的 ".L() + "\(count)" + " 条收到员工消息已标记已读。".L(),
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
                title: "员工协作消息已标记已读".L(),
                detail: "\(selectedProduct?.name ?? "当前产品") 的 ".L() + "\(count)" + " 条员工消息已标记为已读。".L(),
                agentID: ctoID
            )
            saveSnapshot()
        }
        return count
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
            successCriteria: cleanCriteria.isEmpty ? "完成后必须说明修改内容、验证命令和剩余风险。".L().L() : cleanCriteria,
            artifactPath: artifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
        tasks.insert(task, at: 0)
        appendEvent(kind: .taskCreated, title: "创建任务".L().L(), detail: "\(cleanTitle) 已加入 \(selectedProduct?.name ?? "当前产品")。", agentID: ownerID)
        if let ownerID {
            appendEvent(kind: .taskAssigned, title: "任务已分配".L().L(), detail: "\(cleanTitle)" + " 分配给 " + "\(agentName(ownerID))" + "。", agentID: ownerID)
        }
        saveSnapshot()
    }
    public func assignTask(_ taskID: UUID, to ownerID: UUID?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].ownerID = ownerID
        tasks[index].status = ownerID == nil ? .planned : .assigned
        appendEvent(kind: .taskAssigned, title: "任务负责人已更新".L().L(), detail: "\(tasks[index].title) → \(ownerID.map(agentName) ?? "未分配")。", agentID: ownerID)
        saveSnapshot()
    }
    public func updateTaskStatus(_ taskID: UUID, status: TaskStatus, note: String = "") {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        let detail = note.isEmpty ? "\(tasks[index].title)" + " 状态变更为 ".L().L() + "\(status.title)" + "。" : note
        appendEvent(kind: .statusChanged, title: "任务状态更新".L().L(), detail: detail, agentID: tasks[index].ownerID)
        saveSnapshot()
    }
    public func approveTaskRisk(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .running
        appendEvent(kind: .statusChanged, title: "老板已批准".L().L(), detail: "\(tasks[index].title)" + " 的风险/继续执行请求已批准。", agentID: tasks[index].ownerID)
        let productID = tasks[index].productID ?? selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "老板已批准任务继续执行：".L().L() + "\(tasks[index].title)" + "。请技术负责人继续调度并记录结果。"))
        saveSnapshot()
    }
    public func rejectTaskRisk(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .blocked
        appendEvent(kind: .risk, title: "老板已驳回".L().L(), detail: "\(tasks[index].title)" + " 已被驳回，要求技术负责人重新设计方案。", agentID: tasks[index].ownerID)
        let productID = tasks[index].productID ?? selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "老板驳回任务：".L().L() + "\(tasks[index].title)" + "。请重新拆解方案，不要继续原执行路径。"))
        saveSnapshot()
    }
    public func acceptTask(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .done
        let task = tasks[index]
        let productID = task.productID ?? selectedProductID
        let detail = "\(task.title)" + " 已验收完成。".L().L()
        let verification = VerificationRecord(
            productID: productID,
            status: .passed,
            title: "老板验收通过：".L().L() + "\(task.title)",
            detail: "老板已确认任务满足验收标准：".L().L() + "\(task.successCriteria)"
        )
        verifications.insert(verification, at: 0)
        if let artifactPath = task.artifactPath,
           !artifacts.contains(where: { $0.productID == productID && $0.taskID == task.id && $0.path == artifactPath }) {
            artifacts.insert(
                ArtifactRecord(
                    productID: productID,
                    taskID: task.id,
                    kind: artifactKind(for: URL(fileURLWithPath: artifactPath)),
                    title: "验收产物：".L().L() + "\(task.title)",
                    path: artifactPath,
                    summary: "老板验收通过的任务产物。".L().L()
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
            subject: "老板验收通过：".L().L() + "\(task.title)",
            body: "任务已通过老板验收，可进入交付记录。\n验收标准：".L().L() + "\(task.successCriteria)",
            persist: false
        )
        upsertReviewGate(
            for: task,
            status: .accepted,
            requesterID: bossID,
            reviewerID: task.ownerID ?? ctoID,
            summary: "老板已验收通过，任务进入交付记录。".L().L(),
            latestVerificationID: verification.id
        )
        appendEvent(kind: .artifactCreated, title: "老板验收通过".L().L(), detail: detail, agentID: task.ownerID)
        saveSnapshot()
    }
    public func bossInspectorRecentTasksOverflow() -> AgentDeskListOverflow? {
        let total = selectedProductTasks.count
        let limit = Self.bossInspectorRecentTasksDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 项任务。处理完上方任务后下一项会自动浮现。".L().L()
        )
    }
    public func commandCenterOpenTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductOpenTasks.count,
            limit: Self.commandCenterOpenTasksDefaultDisplayLimit,
            noun: "项未完成任务".L().L(),
            continuation: "这里先显示最近任务，完整任务看板在产品详情。".L().L()
        )
    }
    public func commandCenterRiskPanelTasksOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRiskTasks.count,
            limit: Self.commandCenterRiskPanelTasksDefaultDisplayLimit,
            noun: "项风险任务".L().L(),
            continuation: "打开决策中心可处理完整队列。".L().L()
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
            noun: "项" + "\(status.title)" + "任务".L().L(),
            continuation: "完整任务看板在产品详情。".L().L()
        )
    }
    public func agentDeskAssignedTasksOverflow(forAgentID agentID: UUID?) -> AgentDeskListOverflow? {
        guard let id = agentID, agents.contains(where: { $0.id == id }) else { return nil }
        let total = selectedProductTasks.filter { $0.ownerID == id }.count
        let limit = Self.agentDeskAssignedTasksDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 项分配任务。处理或入队上方任务后下一项会自动浮现。".L().L()
        )
    }
    public func agentDeskWorkQueueOverflow(forAgentID agentID: UUID?) -> AgentDeskListOverflow? {
        guard let id = agentID, agents.contains(where: { $0.id == id }) else { return nil }
        let total = selectedProductWorkQueue.filter { $0.agentID == id }.count
        let limit = Self.agentDeskWorkQueueDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 项队列任务。处理完上方任务后下一项会自动浮现。".L().L()
        )
    }
    func reworkReason(from promptPreview: String) -> String? {
        guard let range = promptPreview.range(of: "打回原因：".L()) else { return nil }
        let tail = promptPreview[range.upperBound...]
        let reason = tail
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return reason.isEmpty ? nil : reason
    }
    func requeueSupervisorGoalAfterBossRejection(bossTask: CompanyTask, approval: ApprovalRequest) {
        guard let goal = ctoSupervisorGoalKey(for: bossTask) else { return }
        let productID = approval.productID
        let rejectionReason = approval.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "老板驳回最终交付，需要补充返工后重新提交审查。".L()
            : approval.reason
        let goalTasks = tasks.filter { task in
            task.productID == productID && ctoSupervisorGoalKey(for: task) == goal
        }

        if let reviewerTask = goalTasks.first(where: { $0.title.hasPrefix("审查验收：".L()) }) {
            updateTaskStatus(
                reviewerTask.id,
                status: reviewerTask.ownerID == nil ? .planned : .assigned,
                note: "老板驳回最终交付，审查任务已退回待后续复审。".L()
            )
            upsertReviewGate(
                for: reviewerTask,
                status: .verificationWarning,
                requesterID: ctoID,
                reviewerID: reviewerTask.ownerID,
                summary: "老板驳回最终交付，需返工后重新复审：".L() + "\(rejectionReason)"
            )
            if let reviewerID = reviewerTask.ownerID {
                postAgentMessage(
                    productID: productID,
                    fromAgentID: ctoID,
                    toAgentID: reviewerID,
                    taskID: reviewerTask.id,
                    approvalID: approval.id,
                    kind: .reviewRequested,
                    subject: "等待返工后复审：".L() + "\(goal)",
                    body: "老板已驳回最终交付，等待执行员工返工后再次提交复审。\n打回原因：".L() + "\(rejectionReason)",
                    persist: false
                )
            }
        }

        guard let executionTask = goalTasks.first(where: { $0.title.hasPrefix("员工执行：".L()) }),
              let executionOwnerID = executionTask.ownerID,
              productAgents(for: productID).contains(where: { $0.id == executionOwnerID })
        else {
            appendEvent(
                productID: productID,
                kind: .risk,
                title: "老板驳回后缺少执行负责人".L(),
                detail: "\(goal)" + " 已被老板驳回，但没有可重新派发的执行员工。".L(),
                agentID: ctoID
            )
            return
        }

        updateTaskStatus(
            executionTask.id,
            status: .assigned,
            note: "老板驳回最终交付：".L() + "\(rejectionReason)" + "。任务已重新进入 ".L() + "\(agentName(executionOwnerID))" + " 的返工队列。".L()
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
            subject: "老板驳回后返工：".L().L() + "\(goal)",
            body: "老板已驳回最终交付，技术负责人已把同目标执行任务重新派发给 ".L().L() + "\(agentName(executionOwnerID))" + "。\n原因：".L().L() + "\(rejectionReason)",
            persist: false
        )
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: bossID,
            taskID: bossTask.id,
            approvalID: approval.id,
            kind: .ctoLoopProgressed,
            subject: "技术负责人已按老板驳回回拨返工：".L().L() + "\(goal)",
            body: "执行任务已重新入队，审查员等待返工后复审。\n打回原因：".L().L() + "\(rejectionReason)",
            persist: false
        )
        appendEvent(
            productID: productID,
            kind: .risk,
            title: "老板驳回后已派发返工".L().L(),
            detail: "\(goal)" + " 已退回 ".L().L() + "\(agentName(executionOwnerID))" + " 返工，完成后会重新提交审查。".L().L(),
            agentID: ctoID
        )
    }
    func completeSupervisorGoalTasks(for bossTask: CompanyTask) {
        guard let goal = ctoSupervisorGoalKey(for: bossTask) else { return }
        let productID = bossTask.productID ?? selectedProductID
        let goalTasks = tasks.filter { task in
            task.productID == productID && ctoSupervisorGoalKey(for: task) == goal
        }
        for task in goalTasks where task.status != .done && task.status != .canceled {
            updateTaskStatus(task.id, status: .done, note: "老板已批准最终交付，技术负责人闭环任务组已收束。".L().L())
        }
        appendEvent(
            productID: productID,
            kind: .ctoSummary,
            title: "技术负责人闭环已收束".L().L(),
            detail: "\(goal)" + " 的拆解、执行、审查和老板审批任务已进入完成态。".L().L(),
            agentID: ctoID
        )
    }
    public func runTaskOwner(_ taskID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let ownerID = task.ownerID,
              let owner = agents.first(where: { $0.id == ownerID }),
              owner.role != .boss
        else { return }

        let prompt = workOrderPrompt(for: task)
        enqueueWorkItem(taskID: taskID, agentID: ownerID, prompt: prompt)
        updateTaskStatus(taskID, status: .running, note: "\(task.title)" + " 已发送给 ".L() + "\(owner.displayName)" + " 的命令行来源。".L())
        runAgent(agentID: ownerID, prompt: prompt)
    }
    public func enqueueWorkItem(taskID: UUID, agentID: UUID, prompt: String? = nil) {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }
        guard task.productID == selectedProductID else {
            appendEvent(kind: .risk, title: "已阻止跨产品任务入队".L(), detail: "\(task.title)" + " 不属于当前产品，不能进入当前产品队列。".L(), agentID: agentID)
            saveSnapshot()
            return
        }
        guard productAgents(for: selectedProductID).contains(where: { $0.id == agentID }) else {
            appendEvent(kind: .risk, title: "已阻止非团队员工入队".L(), detail: "\(agentName(agentID)) 未加入 \(selectedProduct?.name ?? "当前产品")，不能接收该产品任务。", agentID: agentID)
            saveSnapshot()
            return
        }
        enqueueWorkItemForProduct(productID: selectedProductID, taskID: taskID, agentID: agentID, prompt: prompt)
    }
    func enqueueWorkItemForProduct(productID: UUID, taskID: UUID, agentID: UUID, prompt: String? = nil) {
        guard let task = tasks.first(where: { $0.id == taskID && $0.productID == productID }) else { return }
        guard productAgents(for: productID).contains(where: { $0.id == agentID }) else {
            let productName = products.first(where: { $0.id == productID })?.name ?? "目标产品".L()
            appendEvent(productID: productID, kind: .risk, title: "已阻止非团队员工入队".L(), detail: "\(agentName(agentID))" + " 未加入 ".L() + "\(productName)" + "，不能接收该产品任务。".L(), agentID: agentID)
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
        appendEvent(productID: productID, kind: .taskAssigned, title: "工作队列已更新".L(), detail: "\(task.title)" + " 已进入 ".L() + "\(agentName(agentID))" + " 的工作队列。".L(), agentID: agentID)
        let dispatchBody: String
        if fullPrompt.contains("打回原因：".L()) {
            dispatchBody = "工作项已重新进入 ".L() + "\(agentName(agentID))" + " 的队列。\n".L() + "\(String(fullPrompt.prefix(800)))"
        } else {
            dispatchBody = "工作项已进入 ".L() + "\(agentName(agentID))" + " 的队列。\n验收标准：".L() + "\(task.successCriteria)"
        }
        postAgentMessage(
            productID: productID,
            fromAgentID: ctoID,
            toAgentID: agentID,
            taskID: taskID,
            workItemID: workItemID,
            kind: .taskDispatched,
            subject: "技术负责人派发任务：".L() + "\(task.title)",
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
            updateTaskStatus(taskID, status: .needsReview, note: "工作项已完成，任务进入待审查。".L())
            if let task = tasks.first(where: { $0.id == taskID }) {
                postAgentMessage(
                    productID: task.productID ?? selectedProductID,
                    fromAgentID: agentID,
                    toAgentID: ctoID,
                    taskID: taskID,
                    workItemID: workItemID,
                    kind: .workCompleted,
                    subject: "工作项完成：".L() + "\(task.title)",
                    body: "\(agentName(agentID))" + " 已完成 ".L() + "\(task.title)" + "，请求技术负责人验收。".L(),
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
    public func acknowledgeAgentMessage(_ messageID: UUID) {
        guard let index = agentMessages.firstIndex(where: { $0.id == messageID }) else { return }
        guard agentMessages[index].status != .acknowledged else { return }
        agentMessages[index].status = .acknowledged
        agentMessages[index].acknowledgedAt = Date()
        saveSnapshot()
    }
    func isCTOSupervisorTask(_ task: CompanyTask) -> Bool {
        let prefixes = ["技术负责人拆解：".L(), "员工执行：".L(), "审查验收：".L(), "老板审批：".L()]
        return prefixes.contains { task.title.hasPrefix($0) }
    }
    public func seedStandardTaskTemplates(goal: String) {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = cleanGoal.isEmpty ? (selectedProduct?.name ?? "当前产品".L()) : cleanGoal
        let templateTasks = [
            CompanyTask(productID: selectedProductID, title: "模板：产品范围与成功标准".L(), ownerID: recommendedAgentID(forTaskTitle: "模板：产品范围与成功标准".L(), successCriteria: "明确 ".L() + "\(target)" + " 的功能范围、边界、成功标准和不做事项。".L(), fallbackRole: .productArchitect) ?? ctoID, status: .planned, successCriteria: "明确 ".L() + "\(target)" + " 的功能范围、边界、成功标准和不做事项。".L()),
            CompanyTask(productID: selectedProductID, title: "模板：界面与交互方案".L(), ownerID: recommendedAgentID(forTaskTitle: "模板：界面与交互方案".L(), successCriteria: "输出关键界面、状态、动效和用户操作路径。".L(), fallbackRole: .uiDesigner), status: .planned, successCriteria: "输出关键界面、状态、动效和用户操作路径。".L()),
            CompanyTask(productID: selectedProductID, title: "模板：工程实现任务".L(), ownerID: recommendedAgentID(forTaskTitle: "模板：工程实现任务".L(), successCriteria: "完成代码修改，并汇报文件、命令、验证和风险。".L(), fallbackRole: .codeEngineer), status: .planned, successCriteria: "完成代码修改，并汇报文件、命令、验证和风险。".L()),
            CompanyTask(productID: selectedProductID, title: "模板：测试验证清单".L(), ownerID: recommendedAgentID(forTaskTitle: "模板：测试验证清单".L(), successCriteria: "覆盖构建、主要流程、失败场景和回归检查。".L(), fallbackRole: .tester) ?? firstAgentID(withSkill: "review", fallbackRole: .reviewer), status: .planned, successCriteria: "覆盖构建、主要流程、失败场景和回归检查。".L()),
            CompanyTask(productID: selectedProductID, title: "模板：审查与交付结论".L(), ownerID: recommendedAgentID(forTaskTitle: "模板：审查与交付结论".L(), successCriteria: "给出是否可交付、风险、缺口和下一步建议。".L(), fallbackRole: .reviewer), status: .planned, successCriteria: "给出是否可交付、风险、缺口和下一步建议。".L())
        ]
        tasks.insert(contentsOf: templateTasks, at: 0)
        appendEvent(kind: .taskCreated, title: "标准任务模板已生成".L(), detail: target, agentID: ctoID)
        saveSnapshot()
    }
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
    public func terminalHallCardTaskDigestLine(prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == OPCVisibleInterfaceCopy.defaultTerminalPromptPlaceholder {
            return nil
        }
        let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        let limit = 60
        if oneLine.count <= limit {
            return "本轮任务：".L() + "\(oneLine)"
        }
        return "本轮任务：".L() + "\(oneLine.prefix(limit))" + "…".L()
    }
    func isGeneratedOperationalTask(_ task: CompanyTask) -> Bool {
        let prefixes = ["流水线 ".L(), "分支 ".L(), "分支汇总：".L(), "模板：".L(), "售前".L(), "手机指令：".L()]
        return prefixes.contains { task.title.hasPrefix($0) }
    }
}
