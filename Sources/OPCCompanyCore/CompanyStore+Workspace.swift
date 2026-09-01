import Foundation
import SwiftUI

// MARK: - Workspace
// Extracted from CompanyStore.swift (v0.2 god-class split). Implementation
// moved verbatim; only the file home changed. Behavior covered by the
// 568-test suite.

extension CompanyStore {

    func trimProductAgentMemories(agentID: UUID, productID: UUID, limit: Int) {
        let overflowIDs = memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .dropFirst(limit)
            .map(\.id)
        guard !overflowIDs.isEmpty else { return }
        let overflowSet = Set(overflowIDs)
        memories.removeAll { overflowSet.contains($0.id) }
    }

    func agentProductMemoryPromptBlock(for agentID: UUID, productID: UUID) -> String {
        let items = memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .map { note in "\(note.title)：\(note.detail)" }
        return promptList(
            items,
            limit: Self.agentSystemProductMemoryPromptLimit,
            itemLimit: Self.agentSystemProductMemoryPromptItemLimit
        )
    }

    func agentProductMemoryLines(for agentID: UUID, productID: UUID) -> [String] {
        memories
            .filter { $0.productID == productID && $0.agentID == agentID }
            .prefix(6)
            .map { note in "\(note.title)：\(note.detail)" }
    }

    func syncAgentWorkspace(for agentID: UUID) {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return }
        let profile = operatingProfile(for: agentID)
        let directory = agentWorkspaceURL(for: agentID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeTextIfChanged(agentSystemPrompt(for: agentID), to: directory.appendingPathComponent("AGENTS.md"))
            try writeTextIfChanged(soulDocument(for: agent, profile: profile), to: directory.appendingPathComponent("SOUL.md"))
            try writeTextIfChanged(memoryDocument(for: profile, agentID: agentID), to: directory.appendingPathComponent("MEMORY.md"))
            try writeTextIfChanged(skillsDocument(for: profile), to: directory.appendingPathComponent("SKILLS.md"))
            try writeTextIfChanged(workspaceDocument(for: agent), to: directory.appendingPathComponent("WORKSPACE.md"))
            let sessionURL = directory.appendingPathComponent("sessions.jsonl")
            if !FileManager.default.fileExists(atPath: sessionURL.path) {
                try "".write(to: sessionURL, atomically: true, encoding: .utf8)
            }
        } catch {
            appendEvent(kind: .risk, title: "员工工作区同步失败".L().L(), detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agentID)
        }
    }

    func syncAllAgentWorkspaces() {
        for agent in agents {
            syncAgentWorkspace(for: agent.id)
        }
    }

    public func agentWorkspaceURL(for agentID: UUID) -> URL {
        let agent = agents.first { $0.id == agentID }
        let name = safeFileName(agent?.displayName ?? "agent")
        let suffix = String(agentID.uuidString.prefix(8))
        return CompanyPersistence.agentWorkspacesURL.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
    }

    public func teamLeadAgentIDForSelectedProduct() -> UUID? {
        if let leadID = selectedProduct?.teamLeadAgentID,
           selectedProductAgents.contains(where: { $0.id == leadID && $0.role != .boss }) {
            return leadID
        }
        if selectedProductAgents.contains(where: { $0.id == ctoID }) {
            return ctoID
        }
        return selectedProductAgents.first { $0.role != .boss }?.id
    }

    func terminalWorkspaceIntroCommand(for agent: CompanyAgent, executionDirectory: URL) -> String {
        let text = """
        \("OPC 员工终端：".L())\(agent.displayName)（\(agent.role.title)）
        \("执行目录：".L())\(executionDirectory.path)
        \("请从 OPC 应用发起任务，确保保留预检、作业档案和验收记录。".L())
        """
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "printf %b \(shellSingleQuoted(escaped))"
    }

    func terminalWorkspaceWindowName(for agent: CompanyAgent) -> String {
        let rolePart = safeTmuxName(agent.role.rawValue)
        let suffix = String(agent.id.uuidString.prefix(6)).lowercased()
        return "\(rolePart)-\(suffix)"
    }

    func terminalWorkspaceSessionName(for product: ProductWorkspace?, productID: UUID) -> String {
        let productPart = safeTmuxName(product?.name ?? "product")
        let suffix = String(productID.uuidString.prefix(12)).lowercased()
        return "opc-\(productPart)-\(suffix)"
    }

    func terminalWorkspaceSessionName() -> String {
        terminalWorkspaceSessionName(for: selectedProduct, productID: selectedProductID)
    }

    func copyProjectRootEssentials(from sourceRoot: URL, to targetRoot: URL) throws {
        let essentialNames = ["Package.swift", "package.json", "pyproject.toml", "Sources", "src"]
        for name in essentialNames {
            let source = sourceRoot.appendingPathComponent(name)
            let destination = targetRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path)
            else { continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func sourceRootLooksLikeProject(_ sourceRoot: URL) -> Bool {
        [".git", "Package.swift", "package.json", "pyproject.toml", "Sources", "src"].contains { name in
            FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(name).path)
        }
    }

    func ensureDirectorySnapshotIsolationSource(sourceRoot: URL, sourceDirectory: URL) throws {
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: sourceRoot) { return }
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try copyProjectSnapshot(from: sourceRoot, to: sourceDirectory, maxFiles: 2_000)
        try copyProjectRootEssentials(from: sourceRoot, to: sourceDirectory)
    }

    func cliIsolationDirectoryIsRunnable(_ directory: URL, sourceRoot: URL) -> Bool {
        let sourceIndicators = [".git", "Package.swift", "package.json", "pyproject.toml", "Sources", "src"]
        return sourceIndicators.contains { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        } && directory.standardizedFileURL.path != sourceRoot.standardizedFileURL.path
    }

    func updateCLIJobDirectory(_ job: CLIJobDirectory, agent: CompanyAgent, result: CommandExecutionResult) {
        do {
            try result.combinedOutput.write(to: job.transcriptURL, atomically: true, encoding: .utf8)
            try cliJobStatusJSON(jobID: job.id, agent: agent, state: result.exitCode == 0 ? "completed" : "failed", exitCode: result.exitCode, executionDirectory: cliExecutionDirectoryURL(for: agent)).write(to: job.statusURL, atomically: true, encoding: .utf8)
            if let index = artifacts.firstIndex(where: { $0.productID == selectedProductID && $0.path == job.directory.path }) {
                artifacts[index].summary = "退出码 ".L() + "\(result.exitCode)" + " · 运行记录已写入。".L()
            }
        } catch {
            appendEvent(kind: .risk, title: "命令行作业档案写入失败".L(), detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
        }
    }

    func createCLIJobDirectory(agent: CompanyAgent, prompt: String, command: [String], executionDirectory: URL) -> CLIJobDirectory? {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = UUID().uuidString.prefix(8)
        let jobID = "\(timestamp)-\(safeFileName(agent.displayName))-\(suffix)"
        let directory = cliWorkingDirectoryURL().appendingPathComponent(".opc/jobs/\(jobID)", isDirectory: true)
        let transcriptURL = directory.appendingPathComponent("transcript.log")
        let statusURL = directory.appendingPathComponent("status.json")

        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("artifacts", isDirectory: true), withIntermediateDirectories: true)
            let taskPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OPCVisibleInterfaceCopy.defaultAgentReportPromptText : prompt
            let brief = """
            \("# OPC 命令行作业".L())

            \("作业编号：".L())\(jobID)
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("员工：".L())\(agent.displayName)
            \("角色：".L())\(agent.role.title)
            \("产品工作目录：".L())\(cliWorkingDirectoryURL().path)
            \("执行目录：".L())\(executionDirectory.path)
            \("隔离策略：".L())\(cliExecutionIsolationNote(for: agent))

            \("命令：".L())
            \(command.joined(separator: " "))
            """
            let agentTask = """
            \("# 员工任务".L())

            \(taskPrompt)
            """
            try brief.write(to: directory.appendingPathComponent("brief.md"), atomically: true, encoding: .utf8)
            try agentTask.write(to: directory.appendingPathComponent("agent-task.md"), atomically: true, encoding: .utf8)
            try "".write(to: transcriptURL, atomically: true, encoding: .utf8)
            try cliJobStatusJSON(jobID: jobID, agent: agent, state: "running", exitCode: nil, executionDirectory: executionDirectory).write(to: statusURL, atomically: true, encoding: .utf8)
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: .report, title: "命令行作业档案：".L() + "\(agent.displayName)", path: directory.path, summary: "运行中 · ".L() + "\(agent.role.title)" + " · ".L() + "\(jobID)"), at: 0)
            return CLIJobDirectory(id: jobID, directory: directory, transcriptURL: transcriptURL, statusURL: statusURL)
        } catch {
            appendEvent(kind: .risk, title: "命令行作业目录创建失败".L(), detail: "\(agent.displayName)：\(error.localizedDescription)", agentID: agent.id)
            return nil
        }
    }

    func cliExecutionDirectoryURL(for agent: CompanyAgent) -> URL {
        let workingDirectory = cliWorkingDirectoryURL()
        guard requiresIsolatedCLIExecution(agent) else { return workingDirectory }

        let sourceDirectory = cliIsolationSourceURL(for: agent)
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: workingDirectory) {
            return sourceDirectory
        }
        return workingDirectory
    }

    func cliWorkingDirectoryURL() -> URL {
        if let product = selectedProduct {
            let url = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app", bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return Self.defaultProductRootDirectoryURL()
    }

    public func syncSelectedProductAgentWorkspaces() {
        for agent in selectedProductAgents {
            syncAgentWorkspace(for: agent.id)
        }
        appendEvent(kind: .artifactCreated, title: "产品团队工作区已同步".L(), detail: "\(selectedProduct?.name ?? "当前产品") 的 ".L() + "\(selectedProductAgents.count)" + " 个员工工作区已写出。".L(), agentID: ctoID)
        saveSnapshot()
    }

    public func syncSelectedAgentWorkspace() {
        syncAgentWorkspace(for: selectedAgentID)
        appendEvent(kind: .artifactCreated, title: "员工工作区已同步".L(), detail: "\(agentName(selectedAgentID))" + " 的本地档案文件已写出。".L(), agentID: selectedAgentID)
        saveSnapshot()
    }

    public func runRuntimeSessionHealthAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        let report = runtimeSessionHealthAuditText(staleAfter: seconds)
        let summary = runtimeSessionHealthAuditSummary(staleAfter: seconds)
        let status: VerificationStatus = summary.passed ? .passed : .warning
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "运行会话健康巡检".L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .passed ? .statusChanged : .risk,
            title: "运行会话健康巡检完成".L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }

    public func runEmployeeHandoffAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        let report = employeeHandoffAuditText(staleAfter: seconds)
        let summary = employeeHandoffAuditSummary(staleAfter: seconds)
        let status: VerificationStatus
        if summary.staleCount > 0 {
            status = .failed
        } else if !summary.passed {
            status = .warning
        } else {
            status = .passed
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "员工交接待确认巡检".L().L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        let eventKind: CompanyEventKind = status == .passed ? .statusChanged : .risk
        appendEvent(
            kind: eventKind,
            title: "员工交接待确认巡检完成".L().L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        if summary.staleCount > 0 {
            appendEvent(
                kind: .risk,
                title: "员工交接超时待确认".L().L(),
                detail: "有 ".L().L() + "\(summary.staleCount)" + " 条员工交接超过 ".L().L() + "\(Int(max(seconds, 60)))" + " 秒仍未确认。".L().L(),
                agentID: ctoID
            )
        }
        saveSnapshot()
        return status
    }

    public func recoverStaleRuntimeSessionsForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> [UUID] {
        let threshold = max(seconds, 60)
        let now = Date()
        var recoveredIDs: [UUID] = []
        var recoveredLines: [String] = []

        for agent in selectedProductAgents {
            guard runningAgentIDs.contains(agent.id),
                  var session = runtimeSessions[agent.id],
                  session.productID == nil || session.productID == selectedProductID,
                  session.state == .busy,
                  let lastUsedAt = session.lastUsedAt
            else { continue }
            let idleSeconds = now.timeIntervalSince(lastUsedAt)
            guard idleSeconds >= threshold else { continue }

            runningAgentIDs.remove(agent.id)
            setStatus(.failed, for: agent.id)
            session.state = .timedOut
            session.failureCount += 1
            session.lastError = "异常占用会话已被手动恢复（空闲 ".L() + "\(Int(idleSeconds))" + " 秒）。".L()
            session.lastRestartReason = "运维手动恢复异常占用会话".L()
            runtimeSessions[agent.id] = session

            appendTerminalLog(
                "\n[OPC 运维恢复]\n".L() + "\(agent.displayName)" + " 已被标记为超时（空闲 ".L() + "\(Int(idleSeconds))" + " 秒）。下次运行前请确认上一轮命令是否真的结束，避免再次卡住。\n".L(),
                for: agent.id
            )
            appendEvent(
                kind: .risk,
                title: "\(agent.displayName)" + " 异常占用已恢复".L(),
                detail: "运行状态已从占用中重置为已超时，等待下一次手动运行重新预热。空闲 ".L() + "\(Int(idleSeconds))" + " 秒，超过阈值 ".L() + "\(Int(threshold))" + "。".L(),
                agentID: agent.id
            )
            recoveredIDs.append(agent.id)
            recoveredLines.append("- ".L() + "\(agent.displayName)" + "：空闲 ".L() + "\(Int(idleSeconds))" + " 秒 → 标记已超时".L())
        }

        let productLabel = selectedProduct?.name ?? "当前产品"
        let report = """
        \("异常占用会话恢复：".L())\(recoveredIDs.isEmpty ? "无需处理" : "完成 \(recoveredIDs.count) 个员工")
        \("产品：".L())\(productLabel)
        \("阈值：".L())\(Int(threshold))\(" 秒".L())
        \("恢复明细：".L())
        \(recoveredLines.isEmpty ? "- 当前没有占用中超过阈值的运行会话。" : recoveredLines.joined(separator: "\n"))

        \("说明：".L())
        \("只恢复运行状态为占用中且上次使用时间超过阈值的员工运行会话。正常占用中任务不会被打断；不会自动启动模型任务，下一次任务仍需从 OPC 运行入口手动发起，以保留预检、作业档案和验收链路。".L())
        """
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: recoveredIDs.isEmpty ? .passed : .warning,
                title: "异常占用会话恢复".L().L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: recoveredIDs.isEmpty ? .statusChanged : .risk,
            title: "异常占用会话恢复完成".L().L(),
            detail: "\(productLabel)" + " · 恢复 ".L().L() + "\(recoveredIDs.count)" + " 个员工".L().L(),
            agentID: ctoID
        )
        saveSnapshot()
        return recoveredIDs
    }

    public func prewarmSelectedProductAgentSessions(reason: String = "手动预热当前产品团队".L()) {
        ensureRuntimeSessionsForSelectedProduct()
        for agent in selectedProductAgents where agent.role != .boss && !isRunning(agentID: agent.id) {
            prewarmAgentSession(agentID: agent.id, reason: reason)
        }
    }

    public func ensureRuntimeSessionsForSelectedProduct() {
        runtimeSessions = runtimeSessions.filter { entry in
            agents.contains { $0.id == entry.key }
        }
        for agent in selectedProductAgents where agent.role != .boss {
            let currentSession = runtimeSessions[agent.id]
            let state = currentSession?.productID == selectedProductID ? currentSession?.state ?? .cold : .cold
            upsertRuntimeSession(for: agent, state: state)
        }
    }

    func terminalHallCardLongSessionProductSummary(for agent: CompanyAgent) -> (brand: String, resumeLabel: String, supportsResume: Bool)? {
        guard let profile = CLIAgentCommandBuilder.interactionProfile(for: agent) else {
            return nil
        }
        let brand: String
        switch profile.command {
        case "codex": brand = "Codex"
        case "claude": brand = "Claude Code"
        case "gemini": brand = "Gemini"
        default: brand = profile.displayName
        }
        let resumeLabel = profile.supportsResume ? "可按产品接续" : "不接续历史会话"
        return (brand, resumeLabel, profile.supportsResume)
    }

    static func isAllowedLinkedLocalFileRoot(rawRoot: URL, resolvedRoot: URL, allowedRootPaths: Set<String>) -> Bool {
        isPath(rawRoot.path, insideAnyOf: allowedRootPaths)
            && isPath(resolvedRoot.path, insideAnyOf: allowedRootPaths)
    }

    static func linkedLocalFileAllowedRootPaths(from products: [ProductWorkspace]) -> Set<String> {
        Set(products.map { product in
            URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath)
                .standardizedFileURL
                .path
        })
    }

    func autoCapturedSummariesForSelectedProduct() -> [ProductMemoryNote] {
        memories.filter { note in
            note.productID == selectedProductID
                && note.kind == .summary
                && note.title.hasPrefix(Self.autoCapturedSummaryTitlePrefix)
        }
    }

    public func cleanupSelectedProductAutoCapturedSummaryDuplicates() -> Int {
        let scoped = autoCapturedSummariesForSelectedProduct()
        let prefixLength = Self.autoCapturedSummaryDedupePrefixLength
        let groups = Dictionary(grouping: scoped) { String($0.detail.prefix(prefixLength)) }

        var idsToRemove: Set<UUID> = []
        var groupCount = 0
        for (_, notes) in groups where notes.count >= 2 {
            // createdAt 降序：最新的留下，剩下的全部计入待删除集合。
            let sorted = notes.sorted { $0.createdAt > $1.createdAt }
            for stale in sorted.dropFirst() {
                idsToRemove.insert(stale.id)
            }
            groupCount += 1
        }

        guard !idsToRemove.isEmpty else { return 0 }

        memories.removeAll { idsToRemove.contains($0.id) }

        let productName = selectedProduct?.name ?? "当前产品".L().L()
        let detail = "已合并 ".L().L() + "\(groupCount)" + " 组重复的自动状态摘要，共移除 ".L().L() + "\(idsToRemove.count)" + " 条旧记忆，保留每组最新一条。范围：当前产品 " + "\(productName)" + "。"
        let record = VerificationRecord(
            productID: selectedProductID,
            status: .passed,
            title: "自动状态摘要去重清理".L().L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        appendEvent(kind: .ctoSummary, title: "自动状态摘要去重清理".L().L(), detail: detail, agentID: ctoID)
        saveSnapshot()
        return idsToRemove.count
    }

    public func previewSelectedProductAutoCapturedSummaryDuplicates() -> AutoCapturedSummaryDuplicatePreview {
        let scoped = autoCapturedSummariesForSelectedProduct()
        let prefixLength = Self.autoCapturedSummaryDedupePrefixLength
        let groups = Dictionary(grouping: scoped) { String($0.detail.prefix(prefixLength)) }
        let duplicateGroups = groups.values.filter { $0.count >= 2 }
        let removable = duplicateGroups.reduce(0) { $0 + ($1.count - 1) }
        return AutoCapturedSummaryDuplicatePreview(
            duplicateGroupCount: duplicateGroups.count,
            removableNoteCount: removable,
            totalAutoSummaryCount: scoped.count
        )
    }

    public func productHealthSnapshotText() -> String {
        let product = selectedProduct
        let productTasks = selectedProductTasks
        let openTasks = productTasks.filter { ![.done, .canceled].contains($0.status) }
        let blockedTasks = productTasks.filter { [.blocked, .failed, .needsApproval].contains($0.status) }
        let doneTasks = productTasks.filter { $0.status == .done }
        let hasRules = product?.importReport?.ruleFiles.isEmpty == false
        let runningCount = selectedProductAgents.filter { runningAgentIDs.contains($0.id) }.count
        let logCount = selectedProductAgents.filter { !currentProductTerminalLog(for: $0.id).isEmpty }.count

        var score = 62
        score += min(doneTasks.count * 4, 16)
        score += hasRules ? 8 : -6
        score += selectedProductAgents.count >= 6 ? 8 : 0
        score += logCount > 0 ? 6 : 0
        score -= min(blockedTasks.count * 10, 30)
        score = max(0, min(100, score))

        return """
        \("产品健康体检：".L())\(product?.name ?? "当前产品")
        \("健康分：".L())\(score) / 100

        \("指标：".L())
        \("- 产品员工：".L())\(selectedProductAgents.count)
        \("- 正在运行：".L())\(runningCount)
        \("- 总任务：".L())\(productTasks.count)
        \("- 未完成任务：".L())\(openTasks.count)
        \("- 已完成任务：".L())\(doneTasks.count)
        \("- 阻塞/失败/待批准：".L())\(blockedTasks.count)
        \("- 规则文件：".L())\(hasRules ? "已接入" : "未接入")
        \("- 有终端输出员工：".L())\(logCount)

        \("建议：".L())
        \(selectedProductAgents.count < 6 ? "1. 先补齐产品架构师、测试工程师、研究员。\n" : "")\(blockedTasks.isEmpty ? "1. 当前没有高优先级阻塞，继续推进执行台任务。\n" : "1. 先处理风险审批中的阻塞/失败/待批准任务。\n")\(hasRules ? "2. 已有项目规则，执行任务时继续优先读取规则文件。" : "2. 建议导入真实项目目录，让 OPC 接入规则/记忆文件。")
        """
    }

    public func selectedProductTerminalAutoLoopReadinessAuditSummary() -> String {
        guard let record = selectedProductLatestTerminalAutoLoopReadinessAudit else {
            return "最近真实终端自动循环就绪审计：暂无记录。".L().L()
        }
        let firstAuditLine = record.detail
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.hasPrefix("就绪校验：".L().L()) } ?? "暂无就绪校验摘要".L().L()
        return "最近真实终端自动循环就绪审计：".L().L() + "\(record.status.title)" + " · " + "\(firstAuditLine)"
    }

    public func terminalWorkspaceIntroCommandPreviewForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }) else { return "" }
        return terminalWorkspaceIntroCommand(for: agent, executionDirectory: cliExecutionDirectoryURL(for: agent))
    }

    func terminalWorkspaceHealthPrimaryIssue(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> String {
        if !tmuxReady { return "终端工具未找到".L() }
        if !sessionExists { return "工作区会话未启动".L() }
        if !hasControlWindow { return "控制窗口未连接".L() }
        if missingAgentCount > 0 { return "\(missingAgentCount)" + " 个员工席位待创建".L() }
        return "无".L()
    }

    public func terminalWorkspaceHealthStatusForTesting(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> VerificationStatus {
        terminalWorkspaceHealthStatus(tmuxReady: tmuxReady, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgentCount)
    }

    func terminalWorkspaceHealthStatus(tmuxReady: Bool, sessionExists: Bool, hasControlWindow: Bool, missingAgentCount: Int) -> VerificationStatus {
        guard tmuxReady else { return .failed }
        guard sessionExists, hasControlWindow, missingAgentCount == 0 else { return .warning }
        return .passed
    }

    func readTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let agents = executableAgents
        let sessionName = terminalWorkspaceSessionName()
        let tmuxPath = AgentProcessRunner.resolvedExecutablePath(for: "tmux")
        let sessionExists = tmuxPath.map { tmuxSessionExists(sessionName, tmuxPath: $0) } ?? false
        let windowNames = sessionExists ? Set(tmuxWindowNames(sessionName, tmuxPath: tmuxPath)) : []
        let hasControlWindow = windowNames.contains("control")
        let missingAgents = agents.filter { !windowNames.contains(terminalWorkspaceWindowName(for: $0)) }
        let status = terminalWorkspaceHealthStatus(tmuxReady: tmuxPath != nil, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgents.count)
        return TerminalWorkspaceHealthSnapshot(
            productID: selectedProductID,
            isKnown: true,
            tmuxReady: tmuxPath != nil,
            sessionExists: sessionExists,
            hasControlWindow: hasControlWindow,
            connectedAgentCount: agents.count - missingAgents.count,
            totalAgentCount: agents.count,
            missingAgents: missingAgents,
            status: status,
            primaryIssue: terminalWorkspaceHealthPrimaryIssue(tmuxReady: tmuxPath != nil, sessionExists: sessionExists, hasControlWindow: hasControlWindow, missingAgentCount: missingAgents.count)
        )
    }

    func terminalWorkspaceHealthUnknownSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let agents = executableAgents
        return TerminalWorkspaceHealthSnapshot(
            productID: selectedProductID,
            isKnown: false,
            tmuxReady: false,
            sessionExists: false,
            hasControlWindow: false,
            connectedAgentCount: 0,
            totalAgentCount: agents.count,
            missingAgents: agents,
            status: .warning,
            primaryIssue: "尚未巡检".L()
        )
    }

    func refreshTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        let snapshot = readTerminalWorkspaceHealthSnapshot()
        cachedTerminalWorkspaceHealthSnapshot = snapshot
        return snapshot
    }

    func currentTerminalWorkspaceHealthSnapshot() -> TerminalWorkspaceHealthSnapshot {
        if let cachedTerminalWorkspaceHealthSnapshot,
           cachedTerminalWorkspaceHealthSnapshot.productID == selectedProductID {
            return cachedTerminalWorkspaceHealthSnapshot
        }
        return terminalWorkspaceHealthUnknownSnapshot()
    }

    public func runTerminalWorkspaceHealthAuditForSelectedProduct() -> VerificationStatus {
        let snapshot = refreshTerminalWorkspaceHealthSnapshot()
        let status = snapshot.status
        let report = terminalWorkspaceHealthAuditText(using: snapshot)
        verifications.insert(
            VerificationRecord(productID: selectedProductID, status: status, title: "持久终端可用性巡检".L(), detail: report),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: status == .passed ? .statusChanged : .risk, title: "持久终端可用性巡检完成".L(), detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)", agentID: ctoID)
        saveSnapshot()
        return status
    }

    func terminalWorkspaceHealthAuditText(using snapshot: TerminalWorkspaceHealthSnapshot) -> String {
        let missingLines = snapshot.missingAgents.map { "- " + "\($0.displayName)" + "：终端席位待创建".L().L() }.joined(separator: "\n")
        let toolStatus = snapshot.isKnown ? (snapshot.tmuxReady ? "已就绪".L().L() : "未找到".L().L()) : "待巡检".L().L()
        let sessionStatus = snapshot.isKnown ? (snapshot.sessionExists ? "已存在".L().L() : "未启动".L().L()) : "待巡检".L().L()
        let controlStatus = snapshot.isKnown ? (snapshot.hasControlWindow ? "已连接".L().L() : "未连接".L().L()) : "待巡检".L().L()

        return """
        \("持久终端可用性巡检：".L())\(snapshot.status.title)
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
        \("主要待处理：".L())\(snapshot.primaryIssue)
        \("终端工具：".L())\(toolStatus)
        \("工作区会话：".L())\(sessionStatus)
        \("控制窗口：".L())\(controlStatus)
        \("员工席位：".L())\(snapshot.connectedAgentCount)/\(snapshot.totalAgentCount)

        \("待处理席位：".L())
        \(missingLines.isEmpty ? "- 无".L() : missingLines)

        \("说明：".L())
        \("本巡检只读取本机终端工作区状态，不启动模型任务、不创建作业档案、不修改员工状态。若存在待创建席位，请先使用「启动真实终端工作区」补齐，再从 OPC 运行入口发起任务。".L())
        """
    }

    public func terminalWorkspaceHealthAuditText() -> String {
        terminalWorkspaceHealthAuditText(using: currentTerminalWorkspaceHealthSnapshot())
    }

    public func clearSelectedProductRunData() {
        createSafetyCheckpoint(reason: "清理当前产品运行/测试数据前自动检查点".L().L())
        let removableTaskIDs = Set(tasks.filter { task in
            task.productID == selectedProductID && isGeneratedOperationalTask(task)
        }.map(\.id))
        let removedTasks = removableTaskIDs.count
        let removedQueue = selectedProductWorkQueue.count
        let removedPlans = selectedProductBranchPlans.count
        let removedGates = selectedProductReviewGates.count
        let removedApprovals = selectedProductApprovals.count
        let removedArtifacts = selectedProductArtifacts.count
        let removedVerifications = selectedProductVerifications.count
        let removedMemories = selectedProductMemories.count
        let removedLogs = selectedProductCommunicationLogs.count

        tasks.removeAll { removableTaskIDs.contains($0.id) }
        workQueue.removeAll { $0.productID == selectedProductID }
        branchPlans.removeAll { $0.productID == selectedProductID }
        reviewGates.removeAll { $0.productID == selectedProductID }
        approvals.removeAll { $0.productID == selectedProductID }
        artifacts.removeAll { $0.productID == selectedProductID }
        verifications.removeAll { $0.productID == selectedProductID }
        memories.removeAll { $0.productID == selectedProductID }
        communicationLogs.removeAll { $0.productID == selectedProductID }
        agentMessages.removeAll { $0.productID == selectedProductID }
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != selectedProductID }

        appendEvent(
            kind: .statusChanged,
            title: "产品运行数据已清理".L().L(),
            detail: "任务 ".L().L() + "\(removedTasks)" + "，队列 ".L().L() + "\(removedQueue)" + "，分支计划 ".L().L() + "\(removedPlans)" + "，验收门禁 ".L().L() + "\(removedGates)" + "，审批 " + "\(removedApprovals)" + "，产物 " + "\(removedArtifacts)" + "，验收 " + "\(removedVerifications)" + "，记忆 " + "\(removedMemories)" + "，通信日志 " + "\(removedLogs)" + "。",
            agentID: ctoID
        )
        saveSnapshot()
    }

    public func selectedProductRunDataSummary() -> String {
        let generatedTaskCount = selectedProductTasks.filter(isGeneratedOperationalTask).count
        return """
        \("将清理当前产品的运行/测试数据：".L())
        \("- 旧流水线、分支、模板、售前、手机指令任务：".L())\(generatedTaskCount)\(" 个".L())
        \("- 工作队列：".L())\(selectedProductWorkQueue.count)\(" 个".L())
        \("- 分支计划：".L())\(selectedProductBranchPlans.count)\(" 个".L())
        \("- 验收门禁：".L())\(selectedProductReviewGates.count)\(" 个".L())
        \("- 审批：".L())\(selectedProductApprovals.count)\(" 个".L())
        \("- 产物记录：".L())\(selectedProductArtifacts.count)\(" 个".L())
        \("- 验收记录：".L())\(selectedProductVerifications.count)\(" 个".L())
        \("- 产品记忆：".L())\(selectedProductMemories.count)\(" 条".L())
        \("- 通信日志：".L())\(selectedProductCommunicationLogs.count)\(" 条".L())

        \("不会删除员工，不会删除项目目录里的真实文件。".L())
        """
    }

    public func assignExistingSpecialistsToSelectedProduct() -> Bool {
        let specialistRoles: Set<AgentRole> = [.productArchitect, .tester, .researcher]
        let existingIDs = Set(agents.filter { specialistRoles.contains($0.role) }.map(\.id))
        guard !existingIDs.isEmpty, let index = products.firstIndex(where: { $0.id == selectedProductID }) else {
            return false
        }

        let before = products[index].assignedAgentIDs
        products[index].assignedAgentIDs.formUnion(existingIDs)
        products[index].updatedAt = Date()
        let changed = before != products[index].assignedAgentIDs
        if changed {
            appendEvent(kind: .statusChanged, title: "现有专业员工已加入产品".L(), detail: "只绑定已存在员工，没有自动创建新员工。".L(), agentID: ctoID)
        }
        return changed
    }

    public func missingCoreTeamRolesForSelectedProduct() -> [AgentRole] {
        let requiredRoles: [AgentRole] = [.productArchitect, .researcher, .tester]
        return requiredRoles.filter { role in
            !selectedProductAgents.contains { $0.role == role }
        }
    }

    func productName(_ productID: UUID) -> String {
        products.first(where: { $0.id == productID })?.name ?? "未知产品".L()
    }

    public func importProductWorkspace(from rootURL: URL) {
        let report = ProjectImportScanner.scan(rootURL: rootURL)
        let assignedAgents: Set<UUID> = [ctoID]

        if let index = products.firstIndex(where: { $0.rootDirectory == rootURL.path }) {
            products[index].name = report.projectName
            products[index].shortName = report.shortName
            products[index].stage = .implementation
            products[index].status = .active
            products[index].assignedAgentIDs = assignedAgents
            products[index].importReport = report
            products[index].updatedAt = Date()
            selectedProductID = products[index].id
        } else {
            let product = ProductWorkspace(
                name: report.projectName,
                shortName: report.shortName,
                rootDirectory: rootURL.path,
                status: .active,
                stage: .implementation,
                assignedAgentIDs: assignedAgents,
                teamLeadAgentID: ctoID,
                importReport: report
            )
            products.append(product)
            selectedProductID = product.id
        }

        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        mainWorkspace = .productDetail
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: """
        \("已导入现有项目：".L())\(report.projectName)
        \("根目录：".L())\(report.rootDirectory)
        \("检测到的智能工具：".L())\(report.detectedTools.isEmpty ? "未发现" : report.detectedTools.joined(separator: "、"))
        \("规则/记忆文件：".L())\(report.ruleFiles.isEmpty ? "未发现" : report.ruleFiles.joined(separator: "、"))
        \("项目文件：".L())\(report.projectFiles.isEmpty ? "未发现" : report.projectFiles.joined(separator: "、"))

        \("接手要求：先读取上述规则和记忆，再盘点项目结构，不要覆盖现有 Codex / Claude Code 规则。".L())
        """))
        tasks.append(CompanyTask(productID: selectedProductID, title: "接手现有项目盘点".L(), ownerID: ctoID, status: .running, successCriteria: "读取项目规则、记忆、技术栈和最近状态，生成继续开发计划。".L(), artifactPath: report.rootDirectory))
        appendEvent(kind: .statusChanged, title: "导入现有项目".L(), detail: report.summary, agentID: ctoID)
        saveSnapshot()
    }

    public func applyTeamTemplateToSelectedProduct(_ template: ProductTeamTemplate) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }) else { return }
        let roleSet = Set(template.roles)
        let assigned = Set(agents.filter { agent in
            agent.role != .boss && roleSet.contains(agent.role)
        }.map(\.id))
        guard !assigned.isEmpty else { return }

        products[index].assignedAgentIDs = assigned
        if let lead = agents.first(where: { assigned.contains($0.id) && $0.role == template.leadRole }) {
            products[index].teamLeadAgentID = lead.id
        } else {
            products[index].teamLeadAgentID = assigned.first
        }
        products[index].updatedAt = Date()

        let missing = missingRoles(for: template).map(\.title)
        let detail = missing.isEmpty
            ? "已应用 ".L() + "\(template.title)" + "，当前团队成员：".L() + "\(assigned.count)" + " 人。".L()
            : "已应用 \(template.title)，当前团队成员：\(assigned.count) 人。缺少：\(missing.joined(separator: "、"))。"
        appendEvent(kind: .statusChanged, title: "产品团队模板已应用".L(), detail: detail, agentID: products[index].teamLeadAgentID)
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        saveSnapshot()
    }

    public func updateSelectedProductTeamLead(_ agentID: UUID) {
        guard let index = products.firstIndex(where: { $0.id == selectedProductID }),
              products[index].assignedAgentIDs.contains(agentID),
              agents.contains(where: { $0.id == agentID && $0.role != .boss })
        else { return }
        products[index].teamLeadAgentID = agentID
        products[index].updatedAt = Date()
        for channelIndex in communicationChannels.indices where communicationChannels[channelIndex].productID == selectedProductID {
            communicationChannels[channelIndex].teamLeadAgentID = agentID
            communicationChannels[channelIndex].updatedAt = Date()
        }
        appendEvent(kind: .statusChanged, title: "产品负责人已更新".L(), detail: "\(products[index].name)" + " 的团队负责人设为 ".L() + "\(agentName(agentID))" + "。".L(), agentID: agentID)
        saveSnapshot()
    }

    public func updateSelectedProductSettings(name: String, shortName: String, rootDirectory: String) -> Bool {
        updateProductSettings(productID: selectedProductID, name: name, shortName: shortName, rootDirectory: rootDirectory)
    }

    public func updateProductSettings(productID: UUID, name: String, shortName: String, rootDirectory: String) -> Bool {
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return false }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        let cleanShortName = Self.normalizedProductShortName(name: cleanName, proposed: shortName)
        let cleanRoot = rootDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRoot.isEmpty else { return false }
        let expandedRoot = NSString(string: cleanRoot).expandingTildeInPath
        let normalizedRoot = URL(fileURLWithPath: expandedRoot, isDirectory: true).standardizedFileURL.path

        let oldProduct = products[index]
        let changed = oldProduct.name != cleanName
            || oldProduct.shortName != cleanShortName
            || URL(fileURLWithPath: NSString(string: oldProduct.rootDirectory).expandingTildeInPath, isDirectory: true).standardizedFileURL.path != normalizedRoot
        guard changed else { return false }

        products[index].name = cleanName
        products[index].shortName = cleanShortName
        products[index].rootDirectory = normalizedRoot
        products[index].updatedAt = Date()
        if normalizedRoot.hasPrefix(CompanyPersistence.productWorkspacesURL.standardizedFileURL.path + "/") {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: normalizedRoot, isDirectory: true), withIntermediateDirectories: true)
        }
        cachedTerminalWorkspaceHealthSnapshot = nil
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != productID }
        for agentID in products[index].assignedAgentIDs {
            syncAgentWorkspace(for: agentID)
        }
        appendEvent(kind: .statusChanged, title: "产品设置已更新".L(), detail: "\(oldProduct.name)" + " 已更新为 ".L() + "\(cleanName)" + "，产品工作区配置已保存。".L(), agentID: products[index].teamLeadAgentID)
        saveSnapshot()
        return true
    }

    public func addProductWorkspace() {
        let index = products.count + 1
        let productID = UUID()
        let product = ProductWorkspace(
            id: productID,
            name: "新产品 ".L() + "\(index)",
            shortName: "P\(index)",
            rootDirectory: Self.internalProductRootDirectory(for: productID),
            status: .active,
            stage: .discovery,
            assignedAgentIDs: [ctoID],
            teamLeadAgentID: ctoID
        )
        products.append(product)
        selectedProductID = product.id
        appendEvent(kind: .statusChanged, title: "新增产品工作区".L(), detail: "\(product.name)" + " 已创建，根目录：".L() + "\(product.rootDirectory)" + "。".L(), agentID: nil)
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    public func deleteProduct(_ id: UUID) {
        guard products.count > 1, let index = products.firstIndex(where: { $0.id == id }) else { return }
        let product = products[index]
        createSafetyCheckpoint(reason: "删除产品前自动检查点：".L() + "\(product.name)")
        products.remove(at: index)
        tasks.removeAll { $0.productID == id }
        workQueue.removeAll { $0.productID == id }
        branchPlans.removeAll { $0.productID == id }
        reviewGates.removeAll { $0.productID == id }
        approvals.removeAll { $0.productID == id }
        artifacts.removeAll { $0.productID == id }
        verifications.removeAll { $0.productID == id }
        memories.removeAll { $0.productID == id }
        communicationChannels.removeAll { $0.productID == id }
        communicationLogs.removeAll { $0.productID == id }
        agentMessages.removeAll { $0.productID == id }
        persistentTerminalSessions = persistentTerminalSessions.filter { $0.key.productID != id }
        let deletedProductPrefix = id.uuidString.lowercased() + ":"
        productTerminalLogs = productTerminalLogs.filter { !$0.key.hasPrefix(deletedProductPrefix) }
        if selectedProductID == id {
            selectedProductID = products[max(0, min(index, products.count - 1))].id
        }
        ensureSelectedAgentIsValidForSelectedProduct()
        appendEvent(kind: .statusChanged, title: "产品已删除".L(), detail: "\(product.name)" + " 及其任务/队列/审批/产物/记忆已删除。".L(), agentID: nil)
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    public func selectProduct(_ id: UUID) {
        guard let product = products.first(where: { $0.id == id }) else { return }
        selectedProductID = id
        restartAgentTeamForSelectedProduct()
        ensureSelectedAgentIsValidForSelectedProduct()
        appendEvent(kind: .statusChanged, title: "切换产品".L(), detail: "当前产品已切换为 ".L() + "\(product.name)" + "，已重新开启技术负责人和产品员工团队。".L(), agentID: nil)
        mainWorkspace = .productDetail
        saveSnapshot()
    }

    func migrateLegacyDesktopDefaultProductRoots() -> Bool {
        var migratedNames: [String] = []
        for index in products.indices {
            guard let migratedRoot = Self.migratedRootForLegacyDesktopDefaultProduct(
                rootDirectory: products[index].rootDirectory,
                productName: products[index].name,
                importReport: products[index].importReport
            ) else {
                continue
            }
            products[index].rootDirectory = migratedRoot
            products[index].updatedAt = Date()
            migratedNames.append(products[index].name)
        }
        guard !migratedNames.isEmpty else { return false }
        appendEvent(
            kind: .statusChanged,
            title: "默认产品目录已迁移".L(),
            detail: "已把旧版默认 Desktop 工作区迁移到 OPC 本地应用工作区：\(migratedNames.joined(separator: "、"))。",
            agentID: ctoID
        )
        syncAllAgentWorkspaces()
        return true
    }

    public func linkedLocalFileRootAllowlistText() -> String {
        guard let product = selectedProduct else { return "本地文件索引根白名单\n当前没有选中的产品。".L().L() }
        let rawRoot = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath).standardizedFileURL
        let resolvedRoot = rawRoot.resolvingSymlinksInPath()
        let allowedRoots = Self.linkedLocalFileAllowedRootPaths(from: products)
        let allowed = Self.isAllowedLinkedLocalFileRoot(rawRoot: rawRoot, resolvedRoot: resolvedRoot, allowedRootPaths: allowedRoots)
        let visibleRoots = allowedRoots.sorted().prefix(8).map { "- \($0)" }
        let hiddenCount = max(0, allowedRoots.count - visibleRoots.count)
        var lines: [String] = [
            "本地文件索引根白名单".L().L(),
            "产品：".L().L() + "\(product.name)",
            "当前根目录：".L().L() + "\(rawRoot.path)",
            "解析后目录：".L().L() + "\(resolvedRoot.path)",
            "当前状态：".L().L() + "\(allowed ? "已登记，可索引" : "未登记，索引会被拒绝")",
            "",
            "已登记工作区根目录：".L().L()
        ]
        lines.append(contentsOf: visibleRoots)
        if hiddenCount > 0 {
            lines.append("- 其余 ".L().L() + "\(hiddenCount)" + " 个根目录已隐藏".L().L())
        }
        lines.append("")
        lines.append("说明：本白名单来自已导入或已创建的产品工作区根目录；本地文件索引只允许扫描这些根目录内的文件。新增根目录请通过产品导入或项目设置登记。".L().L())
        return lines.joined(separator: "\n")
    }

    static func migratedRootForLegacyDesktopDefaultProduct(
        rootDirectory: String,
        productName: String,
        importReport: ProjectImportReport?
    ) -> String? {
        guard importReport == nil else { return nil }
        let raw = NSString(string: rootDirectory).expandingTildeInPath
        let url = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        let desktop = legacyDesktopURL()
        if url.path == desktop.path, productName == "默认产品工作区".L().L() {
            return defaultProductRootDirectory()
        }
        guard productName.hasPrefix("新产品 ".L().L()),
              url.deletingLastPathComponent().standardizedFileURL.path == desktop.path,
              let index = legacyDesktopGeneratedProductIndex(from: url)
        else {
            return nil
        }
        return newProductRootDirectory(index: index)
    }

    static func internalProductRootDirectory(for productID: UUID) -> String {
        internalProductWorkspaceURL(slug: "product-\(String(productID.uuidString.prefix(8)).lowercased())").path
    }

    static func newProductRootDirectory(index: Int) -> String {
        internalProductWorkspaceURL(slug: "product-\(index)").path
    }

    static func defaultProductRootDirectory() -> String {
        defaultProductRootDirectoryURL().path
    }
}
