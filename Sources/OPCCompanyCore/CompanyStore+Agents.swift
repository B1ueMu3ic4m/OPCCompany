import Foundation
import SwiftUI

// MARK: - Agents
// Extracted from CompanyStore.swift (v0.2 god-class split). Implementation
// moved verbatim; only the file home changed. Behavior covered by the
// 568-test suite.

extension CompanyStore {

    func isLegacySyntheticAgentReply(_ text: String) -> Bool {
        let patterns = [
            "我的角色档案".L().L(),
            "我会把这件事拆成任务计划".L().L(),
            "我会结合记忆".L().L(),
            "OPC 公司已经上线".L(),
            "OPC 公司已经恢复到默认状态".L(),
            "我负责把产品想法转成视觉方向".L().L(),
            "我负责按技术负责人的任务卡实现代码".L().L(),
            "我负责按照成功标准审查结果".L().L(),
            "我已经配置完成".L().L(),
            "我已加入当前产品团队".L().L(),
            "我会按技术负责人 → UI/产品 → 工程 → 测试 → 审查 → 老板批准".L().L()
        ]
        return patterns.contains { text.contains($0) }
    }

    func replacementAgentID(forRemovedRole role: AgentRole) -> UUID {
        switch role {
        case .tester:
            agents.first { $0.role == .reviewer }?.id ?? ctoID
        default:
            ctoID
        }
    }

    func ensureAgentProfiles() {
        for agent in agents where agentProfiles[agent.id] == nil {
            agentProfiles[agent.id] = AgentOperatingProfile.defaultProfile(for: agent)
        }
    }

    func agentsForSnapshot() -> [CompanyAgent] {
        agents.map { agent in
            var copy = agent
            if copy.backend.type == .api {
                if !copy.backend.apiKey.isEmpty {
                    writeAPIKeyToKeychain(copy.backend.apiKey, agentID: copy.id, context: "快照前归档".L().L())
                }
                // 即便 keychain 写失败也仍然清空 in-memory copy，保留「snapshot 不携带明文 apiKey」
                // 的既有约束（持久化层未变更）；失败已经通过 writeAPIKeyToKeychain 转成 in-memory 风险事件，
                // 老板可在事件流看到 API Key 写入 Keychain 失败提示并重新填写。
                copy.backend.apiKey = ""
            }
            return copy
        }
    }

    func suggestedAgentName(for pack: AgentRolePack) -> String {
        let base: String
        switch pack.role {
        case .cto: base = "Codex 技术负责人".L().L()
        case .productArchitect: base = "产品架构师".L().L()
        case .uiDesigner: base = "Gemini 界面设计师".L().L()
        case .codeEngineer: base = "Claude Code 工程师".L().L()
        case .reviewer: base = "Codex 审查员".L().L()
        case .tester: base = "测试工程师".L().L()
        case .researcher: base = "资料研究员".L().L()
        case .boss: base = "老板".L().L()
        case .custom: base = pack.title
        }
        if !agents.contains(where: { $0.displayName == base }) {
            return base
        }
        let count = agents.filter { $0.displayName.hasPrefix(base) }.count + 1
        return "\(base) \(count)"
    }

    func skillModuleList(_ skills: [String]) -> String {
        skills.map { skill in
            if let definition = AgentSkillCatalog.skill(id: skill) {
                return """
                ## \(definition.id)：\(definition.title)

                \("- 说明：".L())\(definition.summary)
                \("- 触发词：".L())\(definition.triggerKeywords.joined(separator: "、"))
                \("- 默认角色：".L())\(definition.defaultRoles.map(\.title).joined(separator: "、"))
                """
            }
            return """
            ## \(skill)

            \("- 类型：自定义技能".L())
            \("- 说明：旧版字符串技能，按员工档案原文保留，可继续用于精确匹配。".L())
            """
        }
        .joined(separator: "\n\n")
    }

    func skillsDocument(for profile: AgentOperatingProfile) -> String {
        """
        # SKILLS

        \(profile.skills.isEmpty ? "- 暂无技能".L() : skillModuleList(profile.skills))
        """
    }

    func agentPromptMemoryItems(for agentID: UUID, profile: AgentOperatingProfile) -> [String] {
        let productMemories = agentProductMemoryLines(for: agentID, productID: selectedProductID)
        let globalMemories = profile.memory
            .filter { !isLegacySyntheticAgentReply($0) && !needsConversationalRepair($0) }
        return (productMemories + globalMemories).map {
            Self.promptFragment($0, limit: Self.agentChatMemoryPromptLimit)
        }
    }

    func memoryDocument(for profile: AgentOperatingProfile, agentID: UUID) -> String {
        let productMemories = agentProductMemoryLines(for: agentID, productID: selectedProductID)
        return """
        # MEMORY

        \("## 全局员工记忆".L())
        \(profile.memory.isEmpty ? "- 暂无".L() : markdownList(profile.memory))

        \("## 当前产品员工记忆".L())
        \(productMemories.isEmpty ? "- 暂无".L() : markdownList(productMemories))
        """
    }

    func compactAgentMemory(agentID: UUID) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        let recent = messages(for: agentID, in: selectedProductID, includingLegacyGlobal: false).suffix(8).map { message in
            "\(messageAuthorTitle(message.author))：\(message.text)"
        }
        guard !recent.isEmpty else { return }
        let summary = "自动压缩记忆 " + "\(Date().opcDateTimeText)" + "：".L() + "\(recent.joined(separator: " / ").prefix(900))"
        memories.insert(ProductMemoryNote(productID: selectedProductID, agentID: agentID, kind: .summary, title: "员工记忆：".L().L() + "\(agent.displayName)", detail: String(summary)), at: 0)
        trimProductAgentMemories(agentID: agentID, productID: selectedProductID, limit: 12)
        syncAgentWorkspace(for: agentID)
        appendAgentSession(agentID: agentID, kind: .memory, actor: "system", text: "已压缩近期对话为长期记忆。".L().L())
        appendEvent(kind: .artifactCreated, title: "员工记忆已压缩".L().L(), detail: "\(agent.displayName)" + " 的近期对话已写入长期记忆。", agentID: agentID)
    }

    func appendAgentSession(agentID: UUID, kind: AgentSessionKind, actor: String, text: String) {
        guard agents.contains(where: { $0.id == agentID }) else { return }
        syncAgentWorkspace(for: agentID)
        let entry = AgentSessionEntry(agentID: agentID, kind: kind, actor: actor, text: text)
        let url = agentWorkspaceURL(for: agentID).appendingPathComponent("sessions.jsonl")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            guard let line = String(data: data, encoding: .utf8) else { return }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        } catch {
            appendEvent(kind: .risk, title: "员工会话日志写入失败".L().L(), detail: error.localizedDescription, agentID: agentID)
        }
    }

    func agentCommandPrompt(for agent: CompanyAgent, userPrompt: String, resumeSessionID: String?) -> String {
        guard let resumeSessionID, !resumeSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return agentExecutionPrompt(for: agent, userPrompt: userPrompt)
        }
        return """
        \("继续使用当前 OPC 产品和 ".L())\(agent.displayName)\(" 的既有命令行会话上下文。".L())

        \("用户任务".L())
        \(userPrompt)
        """
    }

    func agentExecutionPrompt(for agent: CompanyAgent, userPrompt: String) -> String {
        """
        \(agentSystemPrompt(for: agent.id))

        \("本地员工档案已由 OPC 同步；路径、会话和执行日志属于运维内部信息，回复用户时不要复述具体本地路径或文件名。".L())

        \("用户任务".L())
        \(userPrompt)
        """
    }

    func agentPromptProfileBlock(for agent: CompanyAgent, profile: AgentOperatingProfile) -> String {
        """
        \("员工操作档案".L())
        \("姓名：".L())\(agent.displayName)
        \("职位：".L())\(agent.title)
        \("角色：".L())\(agent.role.title)
        \("汇报对象：".L())\(agent.reportsToCTO ? agentName(ctoID) : "老板".L())

        \("使命：".L())
        \(Self.promptFragment(profile.mission, limit: Self.agentProfileMissionPromptLimit))

        \("职责：".L())
        \(promptList(profile.responsibilities, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("边界：".L())
        \(promptList(profile.boundaries, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("回复规则：".L())
        \(promptList(profile.responseRules, limit: Self.agentProfileListItemPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))

        \("长期记忆：".L())
        \(profile.memory.isEmpty ? "- 暂无".L() : promptList(profile.memory, limit: Self.agentProfileMemoryPromptLimit, itemLimit: Self.agentProfilePromptMemoryItemLimit))

        \("可用技能：".L())
        \(profile.skillDescriptions.isEmpty ? "- 暂无".L() : promptList(profile.skillDescriptions, limit: Self.agentProfileSkillPromptLimit, itemLimit: Self.agentProfilePromptItemLimit))
        """
    }

    public func agentSystemPrompt(for agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        let profile = operatingProfile(for: agentID)
        let productMemories = agentProductMemoryPromptBlock(for: agentID, productID: selectedProductID)
        return """
        \(agentPromptProfileBlock(for: agent, profile: profile))

        \("当前产品员工记忆：".L())
        \(productMemories)
        """
    }

    func canonicalSkillID(for value: String) -> String? {
        AgentSkillCatalog.canonicalID(for: value)
    }

    func recommendedSkillIDs(forTaskTitle title: String, successCriteria: String) -> [String] {
        let text = "\(title)\n\(successCriteria)"
        var ids: [String] = []
        for id in AgentSkillCatalog.ids(matching: text) where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    func firstAgentID(for role: AgentRole) -> UUID? {
        selectedProductAgents.first { $0.role == role }?.id
    }

    public func recommendedAgentID(forTaskTitle title: String, successCriteria: String, fallbackRole: AgentRole? = nil) -> UUID? {
        let inferredSkills = recommendedSkillIDs(forTaskTitle: title, successCriteria: successCriteria)
        for skill in inferredSkills {
            if let agentID = firstAgentID(withSkill: skill, fallbackRole: fallbackRole) {
                return agentID
            }
        }
        if let fallbackRole {
            return firstAgentID(for: fallbackRole)
        }
        return nil
    }

    public func firstAgentID(withSkill skill: String, fallbackRole: AgentRole? = nil) -> UUID? {
        let candidates = selectedProductAgents.filter { agent in
            agent.role != .boss && agentHasSkill(agent.id, skill: skill)
        }
        if let custom = candidates.first(where: { $0.role == .custom }) {
            return custom.id
        }
        if let fallbackRole, let roleMatch = candidates.first(where: { $0.role == fallbackRole }) {
            return roleMatch.id
        }
        if let skilled = candidates.first {
            return skilled.id
        }
        if let fallbackRole {
            return firstAgentID(for: fallbackRole)
        }
        return nil
    }

    public func agentHasSkill(_ agentID: UUID, skill: String) -> Bool {
        let target = canonicalSkillID(for: skill) ?? AgentSkillCatalog.normalize(skill)
        guard !target.isEmpty else { return false }
        let profile = operatingProfile(for: agentID)
        return profile.skills.contains { agentSkill in
            let candidate = canonicalSkillID(for: agentSkill) ?? AgentSkillCatalog.normalize(agentSkill)
            return candidate == target
        }
    }

    func agentName(_ id: UUID) -> String {
        agents.first { $0.id == id }?.displayName ?? "未知员工".L().L()
    }

    func agentChatRepairPrompt(agent: CompanyAgent, userText: String, draft: String) -> String {
        let currentUserText = Self.promptFragment(userText, limit: Self.agentChatUserTextPromptLimit)
        let draftText = Self.promptFragment(draft, limit: Self.agentChatRepairDraftPromptLimit)
        return """
        \("下面这段回复太像系统档案或工作报告，不适合直接发给老板。请把它改写成自然聊天口吻。".L())

        \("员工：".L())\(agent.displayName)，\(agent.title)
        \("老板原话：".L())\(currentUserText)

        \("机械草稿：".L())
        \(draftText)

        \("改写要求：".L())
        \("- 只输出最终要发给老板的话。".L())
        \("- 不要说“我的角色档案是”“作为...”“我的职责是”“工作流是”。".L())
        \("- 像真人同事一样，1 到 3 句中文。".L())
        \("- 保留有用信息，但删掉流程背诵和身份档案背诵。".L())
        """
    }

    func agentChatPrompt(for agent: CompanyAgent, userText: String) -> String {
        let profile = operatingProfile(for: agent.id)
        let recent = messages(for: agent.id, in: selectedProductID, includingLegacyGlobal: false)
            .filter { message in
                message.author != .system && !isLegacySyntheticAgentReply(message.text) && !needsConversationalRepair(message.text)
            }
            .suffix(3)
            .map { message in "\(messageAuthorTitle(message.author))：\(Self.promptFragment(message.text, limit: Self.agentChatRecentMessagePromptLimit))" }
            .joined(separator: "\n")
        let memory = agentPromptMemoryItems(for: agent.id, profile: profile)
            .prefix(4)
            .joined(separator: "；")
        let workSummary = conversationalWorkSummary(for: agent, profile: profile)
        let style = conversationalStyleGuide(for: agent)
        let currentUserText = Self.promptFragment(userText, limit: Self.agentChatUserTextPromptLimit)
        let activeTasks = selectedProductTasks
            .filter { $0.ownerID == agent.id && $0.status != .done && $0.status != .canceled }
            .prefix(3)
            .map(\.title)
            .joined(separator: "；")

        return """
        \("你是在 OPC 公司里和老板聊天的真实同事，只输出最终回复。".L())

        \("身份：".L())\(agent.displayName)，\(agent.title)。
        \("当前产品：".L())\(selectedProduct?.name ?? "当前产品") / \(selectedProduct?.stage.title ?? "未设置")。
        \("手上任务：".L())\(activeTasks.isEmpty ? "暂无明确任务" : activeTasks)。
        \("记忆：".L())\(memory.isEmpty ? "老板喜欢自然、具体、短一点的回复。" : memory)。
        \("工作重心：".L())\(workSummary)。

        \("最近聊天：".L())
        \(recent.isEmpty ? "暂无。" : recent)

        \("老板：".L())\(currentUserText)

        \("回复规则：".L())
        \("- 老板问“你是谁”时，用真人口吻一句话说明你是谁和能帮他做什么。".L())
        \("- 禁止档案式开头、职责清单、流程背诵和系统味表达；默认 1 到 3 句。".L())
        - \(style)
        """
    }

    public func agentConversationPrompt(for agentID: UUID, userText: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return userText }
        return agentChatPrompt(for: agent, userText: userText)
    }

    public func runAgent(agentID: UUID, prompt: String) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        guard agent.role != .boss else { return }
        guard !isRunning(agentID: agent.id) else { return }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            appendTerminalLog("\n[OPC 已阻止运行] \(agent.displayName) 未加入 \(selectedProduct?.name ?? "当前产品")，不能启动当前产品命令行任务。\n".L(), for: agent.id)
            appendEvent(kind: .risk, title: "已阻止非团队员工运行".L(), detail: "\(agent.displayName)" + " 未加入当前产品团队。".L(), agentID: agent.id)
            saveSnapshot()
            return
        }

        let productID = selectedProductID
        let resumeSessionID = cliResumeSessionID(for: agent)
        let preparedPrompt = agentCommandPrompt(for: agent, userPrompt: prompt, resumeSessionID: resumeSessionID)
        let command = CLIAgentCommandBuilder.command(for: agent, prompt: preparedPrompt, resumeSessionID: resumeSessionID)
        let executionDirectory = cliExecutionDirectoryURL(for: agent)
        let persistentTarget = preparePersistentTerminalTarget(for: agent)
        let timeoutSeconds = CLIAgentCommandBuilder.interactionProfile(for: agent)?.recommendedTimeoutSeconds ?? 60
        let job = createCLIJobDirectory(agent: agent, prompt: prompt, command: command, executionDirectory: executionDirectory)
        appendTerminalLog(terminalCommandSummary(title: "OPC 命令行任务".L(), agent: agent, executionDirectory: executionDirectory, prompt: prompt, job: job), for: agent.id, productID: productID)
        if resumeSessionID != nil {
            appendTerminalLog(Self.cliResumeContextNotice, for: agent.id, productID: productID)
        }
        if persistentTarget != nil {
            appendTerminalLog(Self.persistentSeatExecutionNotice, for: agent.id, productID: productID)
        }
        appendAgentSession(agentID: agent.id, kind: .command, actor: "system", text: "运行方式：".L() + "\(visibleBackendSummary(for: agent))")
        appendEvent(kind: .commandPlanned, title: "正在运行 ".L() + "\(agent.displayName)", detail: "\(agent.displayName)" + " 已按中文运行摘要启动。".L(), agentID: agent.id)
        setStatus(.typing, for: agent.id)
        runningAgentIDs.insert(agent.id)
        markRuntimeBusy(for: agent)

        Task { @MainActor in
            let result: CommandExecutionResult
            if let persistentTarget {
                result = await runPersistentTerminalCommand(command: command, executionDirectory: executionDirectory, target: persistentTarget, timeoutSeconds: timeoutSeconds) { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendTerminalLog(chunk, for: agent.id, productID: productID)
                    }
                }
            } else {
                result = await AgentProcessRunner.runStreaming(command: command, workingDirectory: executionDirectory, environmentOverrides: environmentOverrides(for: agent), isolatedHome: isolatedHomeURL(for: agent, executionDirectory: executionDirectory), sandboxProfile: sandboxProfile(for: agent, executionDirectory: executionDirectory), timeoutSeconds: timeoutSeconds) { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendTerminalLog(chunk, for: agent.id, productID: productID)
                    }
                }
            }
            if result.combinedOutput.isEmpty {
                appendTerminalLog("（无输出）".L(), for: agent.id, productID: productID)
            }
            if !result.standardError.isEmpty,
               terminalLog(agentID: agent.id, productID: productID).contains(result.standardError) == false {
                appendTerminalLog(result.standardError, for: agent.id, productID: productID)
            }
            appendTerminalLog("\n[命令退出码 ".L() + "\(result.exitCode)" + "]\n".L(), for: agent.id, productID: productID)
            if let job {
                updateCLIJobDirectory(job, agent: agent, result: result)
            }
            appendAgentSession(agentID: agent.id, kind: .result, actor: "system", text: "退出码 ".L() + "\(result.exitCode)" + "。".L() + "\(String(result.combinedOutput.prefix(1200)))")
            setStatus(result.exitCode == 0 ? .done : .failed, for: agent.id)
            appendEvent(
                kind: result.exitCode == 0 ? .artifactCreated : .risk,
                title: "\(agent.displayName)" + " 命令结束".L(),
                detail: "退出码 ".L() + "\(result.exitCode)" + "。输出已记录到终端日志。".L(),
                agentID: agent.id
            )
            if agent.id != ctoID {
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "\(agent.displayName)" + " 完成了一次命令行执行，退出码 ".L() + "\(result.exitCode)" + "。".L()))
            }
            runningAgentIDs.remove(agent.id)
            markRuntimeFinished(for: agent, result: result, context: "任务运行".L())
            recordCLIInteractionObservationIfNeeded(agent: agent, result: result)
            handleFailedCLIResumeIfNeeded(agent: agent, result: result, usedResumeSessionID: resumeSessionID)
            recordCLISessionIfNeeded(agent: agent, result: result, usedResumeSessionID: resumeSessionID)
            saveSnapshot()
        }
    }

    public func runAllExecutableAgents(prompt: String) {
        for agent in executableAgents where !isRunning(agentID: agent.id) {
            runAgent(agentID: agent.id, prompt: prompt)
        }
    }

    public func runSelectedAgent(prompt: String) {
        runAgent(agentID: selectedAgentID, prompt: prompt)
    }

    public func compactSelectedAgentMemory() {
        compactAgentMemory(agentID: selectedAgentID)
        saveSnapshot()
    }

    public func updateSelectedAgentProfile(mission: String? = nil, responsibilitiesText: String? = nil, boundariesText: String? = nil, responseRulesText: String? = nil, memoryText: String? = nil, skillsText: String? = nil) {
        guard let agent = selectedAgent else { return }
        var profile = operatingProfile(for: agent.id)
        if let mission {
            profile.mission = mission
        }
        if let responsibilitiesText {
            profile.responsibilities = listItems(from: responsibilitiesText)
        }
        if let boundariesText {
            profile.boundaries = listItems(from: boundariesText)
        }
        if let responseRulesText {
            profile.responseRules = listItems(from: responseRulesText)
        }
        if let memoryText {
            profile.memory = listItems(from: memoryText)
        }
        if let skillsText {
            profile.skills = listItems(from: skillsText)
        }
        agentProfiles[agent.id] = profile
        syncAgentWorkspace(for: agent.id)
        appendAgentSession(agentID: agent.id, kind: .memory, actor: "system", text: "员工操作档案已更新。".L())
        appendEvent(kind: .statusChanged, title: "员工操作档案已更新".L(), detail: "\(agent.displayName)" + " 的角色、记忆和规则已更新。".L(), agentID: agent.id)
        saveSnapshot()
    }

    public func updateSelectedAgentAppearance(ethnicity: EthnicityPresentation? = nil, gender: GenderPresentation? = nil, clothing: ClothingStyle? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if let ethnicity {
            agents[index].ethnicity = ethnicity
        }
        if let gender {
            agents[index].gender = gender
        }
        if let clothing {
            agents[index].clothing = clothing
        }
        appendEvent(kind: .statusChanged, title: "员工外观已更新".L(), detail: "\(agents[index].displayName)" + " 的人物、性别或着装配置已更新。".L(), agentID: agents[index].id)
        syncAgentWorkspace(for: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentBackend(type: BackendType? = nil, command: String? = nil, model: String? = nil, endpoint: String? = nil, apiKey: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if let type {
            agents[index].backend.type = type
            switch type {
            case .api:
                agents[index].backend.command = "api-agent"
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "sonnet"
                    || agents[index].backend.model == "gemini-cli"
                    || agents[index].backend.model == "local" {
                    agents[index].backend.model = "gpt-5.5"
                }
                agents[index].permissions.insert(.useNetwork)
            case .subscriptionCLI:
                if agents[index].backend.command.isEmpty
                    || agents[index].backend.command == "api-agent"
                    || agents[index].backend.command == "local" {
                    agents[index].backend.command = "claude"
                }
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "gpt-5.5"
                    || agents[index].backend.model == "local" {
                    agents[index].backend.model = "sonnet"
                }
            case .local:
                agents[index].backend.command = "local"
                if agents[index].backend.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agents[index].backend.model == "sonnet"
                    || agents[index].backend.model == "gpt-5.5"
                    || agents[index].backend.model == "gemini-cli" {
                    agents[index].backend.model = "local"
                }
            }
        }
        if let command {
            agents[index].backend.command = command
        }
        if let model {
            agents[index].backend.model = model
        }
        if let endpoint {
            agents[index].backend.endpoint = endpoint
        }
        if let apiKey {
            agents[index].backend.apiKey = apiKey
        }
        if let reasoningEffort {
            agents[index].backend.reasoningEffort = reasoningEffort
        }
        upsertRuntimeSession(for: agents[index], state: .cold)
        if runtimeSupervisorStarted && selectedProductAgents.contains(where: { $0.id == agents[index].id }) {
            prewarmAgentSession(agentID: agents[index].id, reason: "模型配置变更后重新预热".L())
        }
        appendEvent(kind: .statusChanged, title: "模型配置已更新".L(), detail: "\(agents[index].displayName)" + " 的模型配置已更新。".L(), agentID: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentPermission(_ permission: AgentPermission, isEnabled: Bool) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        if isEnabled {
            agents[index].permissions.insert(permission)
        } else {
            agents[index].permissions.remove(permission)
        }
        appendEvent(kind: .statusChanged, title: "员工权限已更新".L(), detail: "\(agents[index].displayName)：\(permission.title) \(isEnabled ? "已开启" : "已关闭")。", agentID: agents[index].id)
        syncAgentWorkspace(for: agents[index].id)
        saveSnapshot()
    }

    public func updateSelectedAgentIdentity(displayName: String? = nil, title: String? = nil, role: AgentRole? = nil, reportsToCTO: Bool? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == selectedAgentID }) else { return }
        let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanName, !cleanName.isEmpty {
            agents[index].displayName = cleanName
        }
        if let cleanTitle, !cleanTitle.isEmpty {
            agents[index].title = cleanTitle
        }
        if let role {
            if agents[index].id == ctoID {
                agents[index].role = .cto
            } else if agents[index].id == bossID {
                agents[index].role = .boss
            } else {
                agents[index].role = role
            }
        }
        if let reportsToCTO {
            agents[index].reportsToCTO = agents[index].role == .boss || agents[index].role == .cto ? false : reportsToCTO
        }
        if agentProfiles[agents[index].id] == nil {
            agentProfiles[agents[index].id] = AgentOperatingProfile.defaultProfile(for: agents[index])
        }
        syncAgentWorkspace(for: agents[index].id)
        appendEvent(kind: .statusChanged, title: "员工身份已更新".L(), detail: "\(agents[index].displayName)" + " 的姓名、职位、角色或汇报关系已更新。".L(), agentID: agents[index].id)
        saveSnapshot()
    }

    func prewarmAgentSession(agentID: UUID, reason: String) {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else { return }
        upsertRuntimeSession(for: agent, state: .prewarming)

        if agent.backend.type == .local {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            session.state = .unavailable
            session.lastError = "本地占位员工没有可预热的真实模型来源。".L()
            runtimeSessions[agent.id] = session
            return
        }

        if agent.backend.type == .api {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            if canUseLiveChatBackend(agent) {
                session.state = .ready
                session.lastPrewarmedAt = Date()
                session.lastError = ""
            } else {
                session.state = .failed
                session.failureCount += 1
                session.lastError = "接口地址、密钥或模型名未配置完整。".L()
            }
            runtimeSessions[agent.id] = session
            return
        }

        let command = CLIAgentCommandBuilder.prewarmCommand(for: agent)
        guard let executable = command.first, !executable.isEmpty else {
            var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
            session.state = .failed
            session.failureCount += 1
            session.lastError = "没有可用的预热命令。".L()
            runtimeSessions[agent.id] = session
            return
        }

        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.lastPrewarmedAt = Date()
        session.startedAt = session.startedAt ?? Date()
        if let resolved = AgentProcessRunner.resolvedExecutablePath(for: executable) {
            session.state = .ready
            session.lastError = ""
            session.failureCount = 0
            runtimeSessions[agent.id] = session
            appendTerminalLog("\n[OPC 会话预热]\n原因：".L() + "\(reason)" + "\n本地命令已就绪：".L() + "\(opcBackendCommandDisplayName(resolved))" + "\n持续协作：".L() + "\(session.capability.title)" + "。\n".L(), for: agent.id)
            appendEvent(kind: .statusChanged, title: "\(agent.displayName)" + " 会话已就绪".L(), detail: "已确认本地命令行可执行；预热记录已写入终端大厅。".L(), agentID: agent.id)
        } else {
            session.state = .failed
            session.failureCount += 1
            session.lastError = "找不到可执行命令：".L() + "\(executable)" + "。请检查命令行工具安装路径。".L()
            runtimeSessions[agent.id] = session
            appendEvent(kind: .risk, title: "\(agent.displayName)" + " 会话预热失败".L(), detail: session.lastError, agentID: agent.id)
        }
        saveSnapshot()
    }

    func restartAgentSessionIfNeeded(agent: CompanyAgent, reason: String) {
        guard !isRunning(agentID: agent.id) else { return }
        let failures = runtimeSessions[agent.id]?.failureCount ?? 0
        guard failures <= 2 else {
            appendEvent(kind: .risk, title: "\(agent.displayName)" + " 会话未自动重开".L(), detail: "连续失败 ".L() + "\(failures)" + " 次，请先检查登录、网络或模型配置。".L(), agentID: agent.id)
            return
        }
        restartAgentSession(agentID: agent.id, reason: reason)
    }

    public func restartAgentSession(agentID: UUID, reason: String = "手动重开会话".L()) {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return }
        var session = runtimeSessions[agent.id] ?? newRuntimeSession(for: agent)
        session.state = .restarting
        session.restartCount += 1
        session.lastRestartReason = reason
        session.lastError = ""
        runtimeSessions[agent.id] = session
        appendEvent(kind: .statusChanged, title: "\(agent.displayName)" + " 会话重开".L(), detail: reason, agentID: agent.id)
        prewarmAgentSession(agentID: agent.id, reason: reason)
    }

    public func terminalAgentCardPreflightSummary(for agentID: UUID, prompt _: String) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else {
            return "未找到员工，无法生成运行前预检摘要。".L().L()
        }
        let permissions = agent.permissions.map(\.title).sorted().joined(separator: "、")
        let product = selectedProduct
        let executionLabel = cliExecutionLocationLabel(for: agent)
        let risks = preflightRiskLines(for: agent)
        return """
        \("运行前预检摘要".L())
        \("员工：".L())\(agent.displayName) / \(agent.title)
        \("产品：".L())\(product?.name ?? "当前产品".L())
        \("执行位置：".L())\(executionLabel)
        \("来源：".L())\(visibleBackendSummary(for: agent))
        \("权限：".L())\(permissions.isEmpty ? "无特殊权限".L() : permissions)
        \("风险提示：".L())\(risks.isEmpty ? "只读或低风险执行".L() : risks.joined(separator: "；"))
        \("预检结论：以上员工、执行位置、权限和来源确认无误后再点击运行；完整目录、提示词与运行细节可通过「预检」按钮写入终端日志查看。".L())
        """
    }

    public func captureDecisionMemoryFromLatestReport() {
        let latest = messages(for: bossID, in: selectedProductID, includingLegacyGlobal: false).last(where: { $0.author == .system })
            ?? messages(for: ctoID, in: selectedProductID, includingLegacyGlobal: false).last(where: { $0.author == .system })
        let detail = latest?.text ?? productHealthSnapshotText()
        let trimmedDetail = String(detail.prefix(1200))
        let dedupePrefix = String(trimmedDetail.prefix(Self.autoCapturedSummaryDedupePrefixLength))
        if hasRecentAutoCapturedSummary(forProduct: selectedProductID, detailPrefix: dedupePrefix) {
            // 同产品、相同 detail 前 200 字在 `autoCapturedSummaryDedupeWindow` 秒内已经记录过，
            // 跳过重复写入；不同产品 / 不同 detail 前缀 / 超出窗口仍照常写入。
            return
        }
        addMemory(kind: .summary, title: "\(Self.autoCapturedSummaryTitlePrefix)" + "\(selectedProduct?.name ?? "当前产品".L())" + " 状态摘要".L().L(), detail: trimmedDetail)
    }

    public func addMemory(kind: ProductMemoryKind, title: String, detail: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        memories.insert(ProductMemoryNote(productID: selectedProductID, kind: kind, title: cleanTitle, detail: cleanDetail), at: 0)
        appendEvent(kind: .artifactCreated, title: "产品记忆已保存".L().L(), detail: cleanTitle, agentID: ctoID)
        saveSnapshot()
    }

    public func runMultiAgentArchitectureClosureDrill(goal: String = "多员工架构闭环演练".L()) -> Bool {
        let drillGoal = closureDrillGoal(for: goal)
        guard startCTOSupervisorGoal(goal: drillGoal) != nil else { return false }

        let matchingTasks = selectedProductTasks.filter { ctoSupervisorGoalKey(for: $0) == drillGoal }
        guard let engineerTask = matchingTasks.first(where: { $0.title.hasPrefix("员工执行：".L()) }),
              let reviewerTask = matchingTasks.first(where: { $0.title.hasPrefix("审查验收：".L()) }),
              let bossTask = matchingTasks.first(where: { $0.title.hasPrefix("老板审批：".L()) }),
              let engineerID = engineerTask.ownerID,
              let reviewerID = reviewerTask.ownerID
        else {
            appendEvent(kind: .risk, title: "多员工闭环演练未完成".L(), detail: "缺少工程或审查员工，无法跑通完整链路。".L(), agentID: ctoID)
            saveSnapshot()
            return false
        }

        completeWorkItem(for: engineerTask.id, agentID: engineerID)
        postEmployeeHandoff(
            fromAgentID: engineerID,
            toAgentID: reviewerID,
            taskID: reviewerTask.id,
            subject: "工程实现交接给审查".L(),
            body: "\(agentName(engineerID))" + " 已完成 ".L() + "\(engineerTask.title)" + " 的工程实现，请 ".L() + "\(agentName(reviewerID))" + " 按成功标准审查并给出可交付结论。".L()
        )
        _ = advanceCTOSupervisorLoop()

        completeWorkItem(for: reviewerTask.id, agentID: reviewerID)
        updateTaskStatus(reviewerTask.id, status: .done, note: "审查员已完成闭环演练审查，任务进入技术负责人汇总。".L())
        _ = advanceCTOSupervisorLoop()

        if let approval = selectedProductApprovals.first(where: { $0.taskID == bossTask.id && $0.status == .pending }) {
            decideApproval(approval.id, approved: true)
        }

        requestCTOReview(for: reviewerTask.id)
        runAutomaticVerification()
        generateAcceptanceReport(for: reviewerTask.id)
        acceptTask(reviewerTask.id)

        generateAcceptanceReport(for: bossTask.id)
        acceptTask(bossTask.id)

        let report = multiAgentArchitectureAuditText()
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "闭环演练完成。\n\n".L() + "\(report)"))
        appendEvent(kind: .ctoSummary, title: "多员工闭环演练已完成".L(), detail: "完成度 ".L() + "\(selectedProductArchitectureCompletionScore)" + "%".L(), agentID: ctoID)
        saveSnapshot()
        return true
    }

    public func runTerminalAutoInteractionLoopForSelectedAgent(
        taskContext: String,
        maxTurns: Int = 3,
        timeoutSeconds: TimeInterval = 8,
        turnRunner: CLIAutoInteractionLoopExecutor.TurnSender? = nil
    ) async -> TerminalAutoInteractionLoopReport {
        let productID = selectedProductID
        let agent = selectedAgent
        let usedRealTerminal = turnRunner == nil
        let cleanedContext = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
        var preflightAuditLine: String?
        if usedRealTerminal,
           let agent,
           agent.role != .boss,
           selectedProductAgents.contains(where: { $0.id == agent.id }),
           !cleanedContext.isEmpty,
           maxTurns >= 1,
           maxTurns <= CLIAutoInteractionLoopGate.hardTurnLimit {
            let audit = terminalAutoInteractionReadinessAudit(for: agent)
            preflightAuditLine = audit.auditLine
            appendTerminalAutoInteractionAuditLog(agent: agent, audit: audit)
            recordTerminalAutoInteractionAuditVerification(agent: agent, audit: audit)
            if let rejectionReason = audit.rejectionReason {
                let state = CLIAutoInteractionLoopState(
                    taskContext: cleanedContext,
                    maxTurns: maxTurns,
                    phase: .rejected,
                    stopReason: .transientFailure
                )
                let internalReport = InternalAutoInteractionLoopReport(
                    agentID: agent.id,
                    productID: productID,
                    execution: CLIAutoInteractionLoopExecutionReport(finalState: state, turnReports: []),
                    rejected: true,
                    rejectionReason: rejectionReason
                )
                return TerminalAutoInteractionLoopReport(
                    agentID: agent.id,
                    productID: productID,
                    usedRealTerminal: true,
                    internalReport: internalReport,
                    terminalReadinessAudit: audit.auditLine
                )
            }
        }
        let sender: CLIAutoInteractionLoopExecutor.TurnSender
        if let turnRunner {
            sender = turnRunner
        } else {
            sender = { [self] text in
                guard let agent else {
                    return CLIAutoInteractionTurnObservation(
                        observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "未选中员工".L().L())
                    )
                }
                guard let result = await runPersistentTerminalREPLTurn(text, to: agent, timeoutSeconds: max(timeoutSeconds, 0.1), logSource: .autoLoop) else {
                    return CLIAutoInteractionTurnObservation(
                        observation: CLIInteractionObservation(phase: .transientFailure, reasonTitle: "终端席位不可用".L().L())
                    )
                }
                let observation: CLIInteractionObservation
                switch result.observation.phase {
                case .unknown:
                    observation = CLIInteractionObservation(phase: .transientFailure, reasonTitle: result.observation.reasonTitle)
                default:
                    observation = result.observation
                }
                return CLIAutoInteractionTurnObservation(observation: observation, timedOut: result.timedOut)
            }
        }

        let report = await runInternalAutoInteractionLoopForSelectedAgent(
            taskContext: taskContext,
            maxTurns: maxTurns,
            nextInput: { state in
                CLIAutoInteractionGeneratedInput(text: Self.terminalAutoInteractionNextInput(taskContext: taskContext, state: state))
            },
            runTurn: sender
        )
        if usedRealTerminal, let agent {
            recordTerminalAutoInteractionStopAuditIfNeeded(
                agent: agent,
                finalState: report.execution.finalState
            )
        }
        return TerminalAutoInteractionLoopReport(
            agentID: agent?.id,
            productID: productID,
            usedRealTerminal: usedRealTerminal,
            internalReport: report,
            terminalReadinessAudit: preflightAuditLine
        )
    }

    public func runInternalAutoInteractionLoopForSelectedAgent(
        taskContext: String,
        maxTurns: Int,
        nextInput: CLIAutoInteractionLoopExecutor.InputProvider,
        runTurn: CLIAutoInteractionLoopExecutor.TurnSender
    ) async -> InternalAutoInteractionLoopReport {
        let productID = selectedProductID
        func rejectedReport(reason: String, stopReason: CLIAutoInteractionLoopStopReason) -> InternalAutoInteractionLoopReport {
            let state = CLIAutoInteractionLoopState(
                taskContext: taskContext.trimmingCharacters(in: .whitespacesAndNewlines),
                maxTurns: max(maxTurns, 0),
                phase: .rejected,
                stopReason: stopReason
            )
            return InternalAutoInteractionLoopReport(
                agentID: selectedAgent?.id,
                productID: productID,
                execution: CLIAutoInteractionLoopExecutionReport(finalState: state, turnReports: []),
                rejected: true,
                rejectionReason: reason
            )
        }

        guard let agent = selectedAgent, agent.role != .boss else {
            return rejectedReport(reason: "请选择当前产品团队中的员工；老板视角不参与内部自动交互循环。".L().L(), stopReason: .missingTaskContext)
        }
        guard selectedProductAgents.contains(where: { $0.id == agent.id }) else {
            return rejectedReport(reason: "该员工还未加入当前产品团队，已拒绝内部自动交互循环。".L().L(), stopReason: .missingTaskContext)
        }
        guard !taskContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let execution = await CLIAutoInteractionLoopExecutor.run(
                taskContext: taskContext,
                maxTurns: maxTurns,
                nextInput: nextInput,
                send: runTurn
            )
            return InternalAutoInteractionLoopReport(
                agentID: agent.id,
                productID: productID,
                execution: execution,
                rejected: true,
                rejectionReason: "请先绑定技术负责人任务上下文，再启动内部自动交互循环。".L().L()
            )
        }

        let execution = await CLIAutoInteractionLoopExecutor.run(
            taskContext: taskContext,
            maxTurns: maxTurns,
            nextInput: nextInput,
            send: runTurn
        )
        return InternalAutoInteractionLoopReport(
            agentID: agent.id,
            productID: productID,
            execution: execution,
            rejected: execution.finalState.phase == .rejected,
            rejectionReason: execution.finalState.phase == .rejected ? execution.finalState.stopReason.title : nil
        )
    }

    public func terminalAgentCardHealthBadge(for agentID: UUID) -> TerminalAgentCardHealthBadge? {
        guard let agent = agents.first(where: { $0.id == agentID }), agent.role != .boss else { return nil }
        guard agent.backend.type == .subscriptionCLI else { return nil }
        guard let session = runtimeSessions[agentID], let phase = session.cliInteractionPhase else { return nil }

        let title: String
        let severity: TerminalAgentCardHealthBadge.Severity
        switch phase {
        case .unknown, .ready, .completedTurn:
            return nil
        case .awaitingResponse:
            title = "等待回复".L().L()
            severity = .info
        case .busy:
            title = "忙碌中".L().L()
            severity = .warning
        case .authenticationBlocked:
            title = "授权异常".L().L()
            severity = .danger
        case .transientFailure:
            title = "临时异常".L().L()
            severity = .danger
        }

        let action = session.cliInteractionRecoveryAction
            ?? CLIInteractionStateMachine.recoveryAction(for: phase)
        let hint = session.cliInteractionOperatorHint
            ?? session.cliInteractionRecoveryHint
            ?? action.operatorHint
        let detail: String? = hint.map { "\(action.title)：\($0)" }
        return TerminalAgentCardHealthBadge(title: title, severity: severity, detail: detail)
    }

    func multiAgentClosureTrace(for goal: String) -> MultiAgentClosureTrace {
        let goalTasks = selectedProductTasks.filter { ctoSupervisorGoalKey(for: $0) == goal }
        let taskIDs = Set(goalTasks.map(\.id))
        let relatedMessages = selectedProductAgentMessages.filter { message in
            message.subject.contains(goal)
                || message.body.contains(goal)
                || message.taskID.map { taskIDs.contains($0) } == true
        }
        let approvalRecords = selectedProductApprovals.filter { approval in
            approval.title.contains(goal)
                || approval.reason.contains(goal)
                || approval.taskID.map { taskIDs.contains($0) } == true
        }
        let relatedGates = selectedProductReviewGates.filter { taskIDs.contains($0.taskID) }
        let gateVerificationIDs = Set(relatedGates.compactMap(\.latestVerificationID))
        let gateArtifactIDs = Set(relatedGates.compactMap(\.reportArtifactID))
        let relatedArtifacts = selectedProductArtifacts.filter { artifact in
            artifact.title.contains(goal)
                || artifact.summary.contains(goal)
                || artifact.taskID.map { taskIDs.contains($0) } == true
                || gateArtifactIDs.contains(artifact.id)
        }
        let relatedVerifications = selectedProductVerifications.filter { verification in
            verification.title.contains(goal)
                || verification.detail.contains(goal)
                || gateVerificationIDs.contains(verification.id)
        }

        let hasCTOTask = goalTasks.contains { $0.title.hasPrefix("技术负责人拆解：".L()) }
        let hasEngineerTask = goalTasks.contains { $0.title.hasPrefix("员工执行：".L()) }
        let hasReviewerTask = goalTasks.contains { $0.title.hasPrefix("审查验收：".L()) }
        let hasBossTask = goalTasks.contains { $0.title.hasPrefix("老板审批：".L()) }
        let hasGoalStarted = relatedMessages.contains { $0.kind == .ctoGoalStarted }
        let hasDispatch = relatedMessages.contains { $0.kind == .taskDispatched }
        let hasWorkCompleted = relatedMessages.contains { $0.kind == .workCompleted }
        let hasLoopProgressed = relatedMessages.contains { $0.kind == .ctoLoopProgressed }
        let hasApprovalRequested = relatedMessages.contains { $0.kind == .approvalRequested }
        let hasApprovalDecided = relatedMessages.contains { $0.kind == .approvalDecided } || approvalRecords.contains { $0.status != .pending }
        let hasReviewRequested = relatedMessages.contains { $0.kind == .reviewRequested }
        let hasReviewCompleted = relatedMessages.contains { $0.kind == .reviewCompleted }
        let hasAcceptanceCompleted = relatedMessages.contains { $0.kind == .acceptanceCompleted }
        let hasAcceptedGate = relatedGates.contains { $0.status == .accepted }

        let steps = [
            MultiAgentClosureTraceStep(
                id: "task-graph",
                title: "任务图".L(),
                status: hasCTOTask && hasEngineerTask && hasReviewerTask && hasBossTask ? .passed : (goalTasks.isEmpty ? .failed : .warning),
                detail: "技术负责人、执行、审查、老板审批任务 ".L() + "\(goalTasks.count)" + "/4。".L()
            ),
            MultiAgentClosureTraceStep(
                id: "message-bus",
                title: "消息总线".L(),
                status: hasDispatch && hasWorkCompleted ? .passed : (relatedMessages.isEmpty ? .failed : .warning),
                detail: "关联消息 \(relatedMessages.count) 条；派发 \(hasDispatch ? "已出现" : "未出现")，回传 \(hasWorkCompleted ? "已出现" : "未出现")。"
            ),
            MultiAgentClosureTraceStep(
                id: "cto-loop",
                title: "技术负责人调度".L(),
                status: hasGoalStarted && hasLoopProgressed ? .passed : (hasGoalStarted ? .warning : .failed),
                detail: "目标启动 \(hasGoalStarted ? "已记录" : "未记录")；循环推进 \(hasLoopProgressed ? "已记录" : "未记录")。"
            ),
            MultiAgentClosureTraceStep(
                id: "approval",
                title: "老板审批".L(),
                status: hasApprovalRequested && hasApprovalDecided ? .passed : (hasApprovalRequested || hasApprovalDecided ? .warning : .failed),
                detail: "审批请求 \(hasApprovalRequested ? "已创建" : "未创建")；审批结果 \(hasApprovalDecided ? "已回写" : "未回写")。"
            ),
            MultiAgentClosureTraceStep(
                id: "review-gate",
                title: "审查门禁".L(),
                status: hasReviewRequested && hasReviewCompleted && hasAcceptanceCompleted && hasAcceptedGate ? .passed : (relatedGates.isEmpty ? .failed : .warning),
                detail: "验收门禁 \(relatedGates.count) 条；审查反馈 \(hasReviewCompleted ? "已出现" : "未出现")，老板验收 \(hasAcceptanceCompleted ? "已出现" : "未出现")。"
            ),
            MultiAgentClosureTraceStep(
                id: "evidence",
                title: "产物验收".L(),
                status: !relatedArtifacts.isEmpty && !relatedVerifications.isEmpty ? .passed : (!relatedArtifacts.isEmpty || !relatedVerifications.isEmpty ? .warning : .failed),
                detail: "产物 ".L() + "\(relatedArtifacts.count)" + " 条，验收 ".L() + "\(relatedVerifications.count)" + " 条。".L()
            )
        ]

        let pointTotal = steps.reduce(0) { partial, step in
            switch step.status {
            case .passed: partial + 2
            case .warning: partial + 1
            case .failed: partial
            }
        }
        let completionScore = Int((Double(pointTotal) / Double(steps.count * 2) * 100).rounded())
        let status: ArchitectureCheckStatus
        if steps.allSatisfy({ $0.status == .passed }) {
            status = .passed
        } else if steps.contains(where: { $0.status == .warning || $0.status == .passed }) {
            status = .warning
        } else {
            status = .failed
        }

        let timestamps = relatedMessages.map(\.createdAt)
            + approvalRecords.map(\.createdAt)
            + approvalRecords.compactMap(\.decidedAt)
            + relatedGates.flatMap { [$0.createdAt, $0.updatedAt] }
            + relatedArtifacts.map(\.createdAt)
            + relatedVerifications.map(\.createdAt)

        return MultiAgentClosureTrace(
            id: "\(selectedProductID.uuidString)-\(goal)",
            productID: selectedProductID,
            goal: goal,
            status: status,
            completionScore: completionScore,
            taskIDs: goalTasks.map(\.id),
            messageIDs: relatedMessages.map(\.id),
            approvalIDs: approvalRecords.map(\.id),
            artifactIDs: relatedArtifacts.map(\.id),
            verificationIDs: relatedVerifications.map(\.id),
            reviewGateIDs: relatedGates.map(\.id),
            steps: steps,
            createdAt: timestamps.min() ?? .distantPast,
            updatedAt: timestamps.max() ?? .distantPast
        )
    }
}
