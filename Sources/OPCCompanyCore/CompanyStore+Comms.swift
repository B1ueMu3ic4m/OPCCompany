import Foundation
import SQLite3

// MARK: - Comms
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {

    public func selectedProductAgentMessages(filter: AgentMessageFilter) -> [AgentMessageEnvelope] {
        selectedProductRecentAgentMessages.filter { filter.matches($0) }
    }
    public func selectedAgentProductMessages(filter: AgentMessageFilter) -> [AgentMessageEnvelope] {
        selectedAgentRecentProductMessages.filter { filter.matches($0) }
    }
    public func messages(for agentID: UUID) -> [ChatMessage] {
        messages.filter { $0.agentID == agentID }.sorted { $0.createdAt < $1.createdAt }
    }
    public func messages(for agentID: UUID, in productID: UUID, includingLegacyGlobal: Bool = true) -> [ChatMessage] {
        messages
            .filter { message in
                message.agentID == agentID
                    && (message.productID == productID || (includingLegacyGlobal && message.productID == nil))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
    public func sendMessage(to agentID: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        _ = cleanLegacySyntheticAgentReplies(saveAfterChange: false)
        let productID = selectedProductID
        messages.append(ChatMessage(productID: productID, agentID: agentID, author: .user, text: clean))
        appendAgentSession(agentID: agentID, kind: .message, actor: "boss", text: clean)
        appendEvent(kind: .message, title: "老板发给 ".L() + "\(agentName(agentID))" + " 的消息".L(), detail: clean, agentID: agentID)
        setStatus(.thinking, for: agentID)

        if liveChatEnabled, let agent = agents.first(where: { $0.id == agentID }), canUseLiveChatBackend(agent) {
            startLiveChatReply(agent: agent, userText: clean)
        } else {
            let reply = localFallbackReply(for: agentID)
            messages.append(ChatMessage(productID: productID, agentID: agentID, author: .system, text: reply))
            appendAgentSession(agentID: agentID, kind: .reply, actor: "system", text: reply)
            setStatus(agentID == ctoID ? .thinking : .done, for: agentID)
            if agentID != ctoID {
                let summary = "老板直接和 ".L() + "\(agentName(agentID))" + " 沟通：".L() + "\(clean)" + "。当前未调用真实模型，等待人工运行或配置模型来源。".L()
                messages.append(ChatMessage(productID: productID, agentID: ctoID, author: .system, text: "员工直聊摘要：".L() + "\(summary)"))
                appendEvent(kind: .ctoSummary, title: "技术负责人已同步".L(), detail: summary, agentID: ctoID)
            }
            saveSnapshot()
        }
    }
    public func workflowMapMessageFlowOverflow() -> AgentDeskListOverflow? {
        listOverflow(
            total: selectedProductRecentAgentMessages.count,
            limit: Self.workflowMapMessageFlowDefaultDisplayLimit,
            noun: "条协作消息".L().L(),
            continuation: "可在协作消息总览查看完整列表。".L().L()
        )
    }
    public func communicationGatewayLogsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductCommunicationLogs.count,
            limit: Self.communicationGatewayLogDisplayLimit,
            noun: "条通信日志".L().L()
        )
    }
    public func agentDeskInboxOverflow() -> AgentDeskListOverflow? {
        let total = selectedAgentRecentProductMessages.count
        let limit = Self.agentDeskInboxDefaultDisplayLimit
        guard total > limit else { return nil }
        let hidden = total - limit
        return AgentDeskListOverflow(
            hiddenCount: hidden,
            summary: "后续还有 ".L().L() + "\(hidden)" + " 条协作消息。处理或确认上方消息后下一条会自动浮现，完整收件箱可在协作消息总览查看。".L().L()
        )
    }
    @discardableResult
    public func postAgentMessage(
        productID: UUID? = nil,
        fromAgentID: UUID,
        toAgentID: UUID? = nil,
        taskID: UUID? = nil,
        workItemID: UUID? = nil,
        approvalID: UUID? = nil,
        kind: AgentMessageKind,
        subject: String,
        body: String,
        reviewOutcome: AgentMessageReviewOutcome? = nil,
        persist: Bool = true
    ) -> AgentMessageEnvelope? {
        let pid = productID ?? selectedProductID
        guard agents.contains(where: { $0.id == fromAgentID }) else { return nil }
        guard agentCanParticipateInProduct(fromAgentID, productID: pid) else {
            appendEvent(
                kind: .risk,
                title: "已阻止跨团队消息发送".L(),
                detail: "\(agentName(fromAgentID))" + " 不在 ".L() + "\(productName(pid))" + " 团队，不能在该产品发送员工消息。".L(),
                agentID: fromAgentID
            )
            if persist { saveSnapshot() }
            return nil
        }
        if let toAgentID {
            guard agents.contains(where: { $0.id == toAgentID }) else { return nil }
            guard agentCanParticipateInProduct(toAgentID, productID: pid) else {
                appendEvent(
                    kind: .risk,
                    title: "已阻止跨团队消息接收".L(),
                    detail: "\(agentName(toAgentID))" + " 不在 ".L() + "\(productName(pid))" + " 团队，不能接收该产品员工消息。".L(),
                    agentID: toAgentID
                )
                if persist { saveSnapshot() }
                return nil
            }
        }
        let envelope = AgentMessageEnvelope(
            productID: pid,
            fromAgentID: fromAgentID,
            toAgentID: toAgentID,
            taskID: taskID,
            workItemID: workItemID,
            approvalID: approvalID,
            kind: kind,
            subject: Self.promptFragment(subject, limit: Self.agentMessageSubjectTextLimit),
            body: Self.promptFragment(body, limit: Self.agentMessageBodyTextLimit),
            reviewOutcome: reviewOutcome
        )
        agentMessages.insert(envelope, at: 0)
        if agentMessages.count > 500 {
            agentMessages.removeLast(agentMessages.count - 500)
        }
        if persist { saveSnapshot() }
        return envelope
    }
    public func ensureCommunicationGatewayPlan() {
        let productID = selectedProductID
        let existingKinds = Set(communicationChannels.filter { $0.productID == productID }.map(\.kind))
        let leadID = teamLeadAgentIDForSelectedProduct()
        let defaults: [CommunicationChannelConfig] = [
            CommunicationChannelConfig(productID: productID, name: "本地 OPC 指挥台".L(), kind: .localOnly, teamLeadAgentID: leadID, isEnabled: true, reportsEnabled: true, commandsEnabled: true),
            CommunicationChannelConfig(productID: productID, name: "飞书手机汇报群".L(), kind: .feishuWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "企业微信项目群".L(), kind: .wecomWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "钉钉老板通知群".L(), kind: .dingtalkWebhook, teamLeadAgentID: leadID),
            CommunicationChannelConfig(productID: productID, name: "Telegram 双向指令".L(), kind: .telegramBot, teamLeadAgentID: leadID, commandsEnabled: true),
            CommunicationChannelConfig(productID: productID, name: "邮件日报".L(), kind: .emailDigest, teamLeadAgentID: leadID)
        ]
        let missing = defaults.filter { !existingKinds.contains($0.kind) }
        guard !missing.isEmpty else { return }
        communicationChannels.append(contentsOf: missing)
        appendEvent(kind: .statusChanged, title: "OPC 通信网关已规划".L(), detail: "已为当前产品创建 ".L() + "\(missing.count)" + " 个通信通道配置。".L(), agentID: leadID)
        saveSnapshot()
    }
    public func updateCommunicationChannel(_ id: UUID, endpoint: String? = nil, chatID: String? = nil, isEnabled: Bool? = nil, reportsEnabled: Bool? = nil, commandsEnabled: Bool? = nil) {
        guard let index = communicationChannels.firstIndex(where: { $0.id == id }) else { return }
        if let endpoint {
            communicationChannels[index].endpoint = endpoint
        }
        if let chatID {
            communicationChannels[index].chatID = chatID
        }
        if let isEnabled {
            communicationChannels[index].isEnabled = isEnabled
        }
        if let reportsEnabled {
            communicationChannels[index].reportsEnabled = reportsEnabled
        }
        if let commandsEnabled {
            communicationChannels[index].commandsEnabled = commandsEnabled
        }
        communicationChannels[index].updatedAt = Date()
        appendEvent(kind: .statusChanged, title: "通信通道已更新".L(), detail: "\(communicationChannels[index].name)" + " 配置已更新。".L(), agentID: communicationChannels[index].teamLeadAgentID)
        saveSnapshot()
    }
    public func testCommunicationGatewayChannels() {
        ensureCommunicationGatewayPlan()
        let enabledChannels = selectedProductCommunicationChannels.filter(\.isEnabled)
        guard !enabledChannels.isEmpty else {
            communicationLogs.insert(CommunicationLogEntry(
                productID: selectedProductID,
                agentID: teamLeadAgentIDForSelectedProduct(),
                direction: .outbound,
                status: .failed,
                title: "通信通道测试".L().L(),
                body: "没有启用的通信通道。请先启用本地指挥台或配置外部网络回调/机器人。".L().L()
            ), at: 0)
            appendEvent(kind: .risk, title: "通信通道测试失败".L().L(), detail: "没有启用的通信通道。".L().L(), agentID: teamLeadAgentIDForSelectedProduct())
            saveSnapshot()
            return
        }

        let lines = enabledChannels.map { channel in
            if let preview = CommunicationGatewayRequestBuilder.preview(for: channel, text: "OPC 通信测试".L().L()) {
                let endpoint = preview.method == "LOCAL" ? preview.endpoint : CommunicationGatewayDispatcher.redactedEndpoint(preview.endpoint)
                return "通过：".L().L() + "\(channel.name)" + " · " + "\(preview.method)" + " " + "\(endpoint)"
            }
            return "缺配置：".L().L() + "\(channel.name)" + " · 需要接口地址" + "\(channel.kind == .telegramBot ? "和聊天标识" : "")"
        }
        let hasMissingConfiguration = lines.contains { $0.hasPrefix("缺配置：".L().L()) }
        communicationLogs.insert(CommunicationLogEntry(
            channelID: enabledChannels.first?.id,
            productID: selectedProductID,
            agentID: teamLeadAgentIDForSelectedProduct(),
            direction: .outbound,
            status: hasMissingConfiguration ? .queued : .sent,
            title: "通信通道测试".L().L(),
            body: lines.joined(separator: "\n")
        ), at: 0)
        appendEvent(
            kind: hasMissingConfiguration ? .risk : .statusChanged,
            title: hasMissingConfiguration ? "通信通道待补配置".L().L() : "通信通道测试通过".L().L(),
            detail: lines.joined(separator: "；"),
            agentID: teamLeadAgentIDForSelectedProduct()
        )
        trimCommunicationLogs()
        saveSnapshot()
    }
    public func communicationGatewayMobileLinkText() -> String {
        let inboundChannels = selectedProductCommunicationChannels.filter { $0.kind.supportsInboundCommand }
        let enabledInboundChannels = inboundChannels.filter { $0.isEnabled && $0.commandsEnabled }
        let readyInboundChannels = enabledInboundChannels.filter(communicationChannelCanDispatch)
        let inboundLogs = selectedProductCommunicationLogs.filter { $0.direction == .inbound }
        let leadName = teamLeadAgentIDForSelectedProduct().map(agentName) ?? "团队负责人".L().L()
        let channelLines = inboundChannels.map { channel in
            let state: String
            if !channel.isEnabled {
                state = "未启用".L().L()
            } else if !channel.commandsEnabled {
                state = "未开启指令".L().L()
            } else if communicationChannelCanDispatch(channel) {
                state = "可接收".L().L()
            } else {
                state = "缺配置".L().L()
            }
            return "- \(channel.name)：\(channel.kind.title) · \(state)"
        }.joined(separator: "\n")

        return """
        \("移动端指令联动：".L())\(readyInboundChannels.isEmpty ? "待配置".L() : "可接收".L())
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
        \("接收负责人：".L())\(leadName)
        \("可入站通道：".L())\(inboundChannels.count)
        \("已启用指令通道：".L())\(enabledInboundChannels.count)
        \("配置就绪通道：".L())\(readyInboundChannels.count)
        \("已接收指令：".L())\(inboundLogs.filter { $0.status == .received }.count)
        \("被拒绝/失败指令：".L())\(inboundLogs.filter { $0.status == .failed }.count)

        \("通道状态：".L())
        \(channelLines.isEmpty ? "- 当前产品没有支持入站指令的通道。".L() : channelLines)

        \("说明：".L())
        \("手机指令只会写入通信日志、通知团队负责人并创建可追踪任务；不会直接执行命令、不会跳过老板/技术负责人审批，也不会修改本地文件。外部双向通道必须同时满足启用、允许指令、支持入站和配置完整。".L())
        """
    }
    func upsertChatMessage(id: UUID, productID: UUID? = nil, agentID: UUID, author: MessageAuthor, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].productID = productID
            messages[index].author = author
            messages[index].text = text
        } else {
            messages.append(ChatMessage(id: id, productID: productID, agentID: agentID, author: author, text: text))
        }
    }
    func messageAuthorTitle(_ author: MessageAuthor) -> String {
        switch author {
        case .user: "老板".L()
        case .agent: "员工".L()
        case .system: "系统".L()
        }
    }
    func communicationChannelCanDispatch(_ channel: CommunicationChannelConfig) -> Bool {
        switch channel.kind {
        case .localOnly:
            return true
        case .telegramBot:
            return !channel.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !channel.chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .feishuWebhook, .wecomWebhook, .dingtalkWebhook, .emailDigest:
            return !channel.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    func inboundCommandChannel(channelID: UUID?) -> CommunicationChannelConfig? {
        let candidates = selectedProductCommunicationChannels.filter {
            $0.isEnabled && $0.commandsEnabled && $0.kind.supportsInboundCommand
        }
        if let channelID {
            return candidates.first { $0.id == channelID }
        }
        return candidates.first { $0.kind == .localOnly } ?? candidates.first
    }
}
