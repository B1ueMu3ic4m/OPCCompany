import Foundation
import SwiftUI

// MARK: - Persistence
// Extracted from CompanyStore.swift (v0.2 god-class split). Implementation
// moved verbatim; only the file home changed. Behavior covered by the
// 568-test suite.

extension CompanyStore {

    func applyRestoredSnapshot(_ snapshot: CompanySnapshot) {
        agents = snapshot.agents
        selectedAgentID = snapshot.selectedAgentID
        messages = snapshot.messages
        events = snapshot.events
        tasks = snapshot.tasks
        products = snapshot.products
        selectedProductID = snapshot.selectedProductID
        workQueue = snapshot.workQueue
        approvals = snapshot.approvals
        artifacts = snapshot.artifacts
        verifications = snapshot.verifications
        memories = snapshot.memories
        agentProfiles = snapshot.agentProfiles
        communicationChannels = snapshot.communicationChannels
        communicationLogs = snapshot.communicationLogs
        branchPlans = snapshot.branchPlans
        reviewGates = snapshot.reviewGates
        terminalLogs = snapshot.terminalLogs
        productTerminalLogs = snapshot.productTerminalLogs
        runningAgentIDs.removeAll()
        mainWorkspace = .office
        ensureAgentProfiles()
        hydrateAPIKeysFromKeychain()
        repairSelectionState()
        syncAllAgentWorkspaces()
    }

    func checkpointDateText(for url: URL) -> String {
        let date = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()
        return date.opcDateTimeText
    }

    func safetyCheckpointURLs(limit: Int) -> [URL] {
        let directory = CompanyPersistence.stateURL.deletingLastPathComponent().appendingPathComponent("checkpoints", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = ((try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                let rightDate = ((try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
        return Array(sorted.prefix(max(0, limit)))
    }

    func persistentTerminalPartialOutput(from capture: String, startMarker: String) -> String {
        guard let startRange = capture.range(of: startMarker, options: .backwards) else {
            return capture.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(capture[startRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func persistentTerminalHasUnfinishedOPCJob(_ capture: String) -> Bool {
        guard let latestStart = capture.range(of: "__OPC_JOB_START_", options: .backwards) else { return false }
        guard let latestExit = capture.range(of: "__OPC_JOB_EXIT_", options: .backwards) else { return true }
        return latestExit.lowerBound < latestStart.lowerBound
    }

    func persistentTerminalTurnSnapshot(from capture: String, startMarker: String, endMarker: String, profile: CLIInteractionProfile?) -> PersistentTerminalTurnSnapshot {
        let partialOutput = persistentTerminalPartialOutput(from: capture, startMarker: startMarker)
        let observation = profile.map {
            CLIInteractionStateMachine.observe(output: partialOutput, profile: $0, previousPhase: .awaitingResponse)
        }
        return PersistentTerminalTurnSnapshot(
            result: persistentTerminalResult(from: capture, startMarker: startMarker, endMarker: endMarker),
            observation: observation,
            partialOutput: partialOutput
        )
    }

    func persistentTerminalResult(from capture: String, startMarker: String, endMarker: String) -> CommandExecutionResult? {
        guard let startRange = capture.range(of: startMarker, options: .backwards),
              let endRange = capture.range(of: endMarker, range: startRange.upperBound..<capture.endIndex)
        else { return nil }

        let output = String(capture[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exitCodeText = capture[endRange.upperBound...]
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let exitCode = Int32(exitCodeText) ?? 1
        return CommandExecutionResult(exitCode: exitCode, standardOutput: output, standardError: "")
    }

    func persistentTerminalShellCommand(runnerScriptURL: URL) -> String {
        "/bin/sh \(shellSingleQuoted(runnerScriptURL.path))"
    }

    func persistentTerminalTurnClosed(
        terminalSession: PersistentTerminalSession,
        workingDirectory: URL,
        startMarker: String,
        endMarker: String
    ) async -> Bool {
        let capture = await terminalSession.capture(workingDirectory: workingDirectory)
        guard capture.exitCode == 0 else { return true }
        return persistentTerminalResult(from: capture.output, startMarker: startMarker, endMarker: endMarker) != nil
    }

    func persistentTerminalOutputDelta(before baseline: String, after latest: String, inputEcho: String? = nil) -> String {
        if latest.hasPrefix(baseline) {
            return String(latest.dropFirst(baseline.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let baselineLines = baseline.split(whereSeparator: \.isNewline).map(String.init)
        if let lastLine = baselineLines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
           let range = latest.range(of: lastLine) {
            return String(latest[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let inputEcho,
           !inputEcho.isEmpty,
           let range = latest.range(of: inputEcho) {
            return String(latest[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    public func persistentTerminalSessionCacheCountForTesting() -> Int {
        persistentTerminalSessions.count
    }

    func persistentTerminalSession(for target: PersistentTerminalTarget) -> PersistentTerminalSession {
        prunePersistentTerminalSessionCache()
        let key = PersistentTerminalSessionKey(
            productID: selectedProductID,
            agentID: target.agentID,
            tmuxPath: target.tmuxPath,
            sessionName: target.sessionName,
            windowName: target.windowName
        )
        if let existing = persistentTerminalSessions[key] {
            return existing
        }
        let session = PersistentTerminalSession(target: target)
        persistentTerminalSessions[key] = session
        return session
    }

    func copyProjectSnapshot(from sourceRoot: URL, to targetRoot: URL, maxFiles: Int) throws {
        let excludedNames: Set<String> = [".git", ".opc", ".build", "node_modules", "dist", "DerivedData", ".DS_Store"]
        guard let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        var copiedFiles = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if excludedNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let relative = String(url.path.dropFirst(sourceRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { continue }
            let destination = targetRoot.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            guard copiedFiles < maxFiles else { break }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            try FileManager.default.copyItem(at: url, to: destination)
            copiedFiles += 1
        }
    }

    func currentSnapshot() -> CompanySnapshot {
        CompanySnapshot(
            agents: agentsForSnapshot(),
            ctoID: ctoID,
            bossID: bossID,
            selectedAgentID: selectedAgentID,
            products: products,
            selectedProductID: selectedProductID,
            messages: messages,
            events: events,
            tasks: tasks,
            terminalLogs: terminalLogs,
            productTerminalLogs: productTerminalLogs,
            workQueue: workQueue,
            approvals: approvals,
            artifacts: artifacts,
            verifications: verifications,
            memories: memories,
            agentProfiles: agentProfiles,
            communicationChannels: communicationChannels,
            communicationLogs: communicationLogs,
            inboundCommandNonces: inboundCommandNonces,
            branchPlans: branchPlans,
            reviewGates: reviewGates,
            agentMessages: agentMessages
        )
    }

    public func saveSnapshot() {
        if case .failure(let error) = persistSnapshot(currentSnapshot()) {
            recordPersistenceFailure(error)
        }
    }

    func interruptCLIJobArchive(_ record: CLIJobArchiveRecord, now: Date, formatter: ISO8601DateFormatter) throws -> Bool {
        let latest = try readCLIJobArchiveRecord(directory: record.directory, statusURL: record.statusURL)
        guard latest.productID == selectedProductID, cliJobStateIsRunning(latest.state) else {
            return false
        }
        var status = latest.status
        status["previous_state"] = record.state
        status["state"] = "interrupted"
        status["exit_code"] = NSNull()
        status["interrupted_at"] = formatter.string(from: now)
        status["updated_at"] = formatter.string(from: now)
        status["interruption_reason"] = "OPC 运维巡检发现该作业仍标记运行中，但当前产品没有对应员工运行占用。".L()
        let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: record.statusURL, options: .atomic)

        let archivePath = record.directory.standardizedFileURL.path
        if let index = artifacts.firstIndex(where: {
            $0.productID == selectedProductID && URL(fileURLWithPath: $0.path).standardizedFileURL.path == archivePath
        }) {
            artifacts[index].summary = "已中断 · 幽灵巡检已标记。".L()
        }
        return true
    }

    func readCLIJobArchiveRecord(directory: URL, statusURL: URL) throws -> CLIJobArchiveRecord {
        let data = try Data(contentsOf: statusURL)
        guard var status = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let jobID = stringValue(in: status, keys: ["job_id", "jobID", "作业编号".L()]) ?? directory.lastPathComponent
        let state = stringValue(in: status, keys: ["state", "status", "状态".L()]) ?? "unknown"
        let agentID = uuidValue(in: status, keys: ["agent_id", "agentID", "员工ID".L()])
        let productID = uuidValue(in: status, keys: ["product_id", "productID", "产品ID".L()])
        let updatedText = stringValue(in: status, keys: ["updated_at", "updatedAt", "更新时间"])
        let updatedAt = updatedText.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? ((try? FileManager.default.attributesOfItem(atPath: statusURL.path)[.modificationDate]) as? Date)
            ?? Date.distantPast

        if status["job_id"] == nil {
            status["job_id"] = jobID
        }

        return CLIJobArchiveRecord(
            jobID: jobID,
            directory: directory,
            statusURL: statusURL,
            visibleName: jobID,
            agentID: agentID,
            productID: productID,
            state: state,
            updatedAt: updatedAt,
            status: status
        )
    }

    func jobArchiveStaleAuditSummary(staleAfter seconds: TimeInterval) -> CLIJobArchiveAuditSummary {
        var summary = CLIJobArchiveAuditSummary()
        let threshold = max(seconds, 60)
        let now = Date()
        let jobsRoot = cliWorkingDirectoryURL().appendingPathComponent(".opc/jobs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: jobsRoot.path) else {
            return summary
        }

        let jobDirectories: [URL]
        do {
            jobDirectories = try FileManager.default.contentsOfDirectory(
                at: jobsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            summary.invalidCount += 1
            summary.lines.append("- 无法读取作业目录：".L() + "\(error.localizedDescription)")
            return summary
        }

        summary.totalCount = jobDirectories.count
        for (offset, directory) in jobDirectories.enumerated() {
            let visibleName = "作业 ".L() + "\(offset + 1)"
            let statusURL = directory.appendingPathComponent("status.json")
            do {
                var record = try readCLIJobArchiveRecord(directory: directory, statusURL: statusURL)
                record.visibleName = visibleName
                guard let productID = record.productID else {
                    summary.invalidCount += 1
                    summary.lines.append("- 无法读取：".L() + "\(record.visibleName)" + "，缺少产品归属。".L())
                    continue
                }
                if productID != selectedProductID {
                    continue
                }
                guard cliJobStateIsRunning(record.state) else {
                    summary.lines.append("- 已结束：".L() + "\(record.visibleName)" + "（".L() + "\(cliJobStateDisplayName(record.state))" + "）".L())
                    continue
                }

                summary.runningCount += 1
                let elapsed = now.timeIntervalSince(record.updatedAt)
                let agentLabel = record.agentID.map(agentName) ?? "未知员工"
                let isStillOccupied = record.agentID.map { agentID in
                    let session = runtimeSessions[agentID]
                    let sessionBelongsToCurrentProduct = session?.productID == nil || session?.productID == selectedProductID
                    let sessionBusy = sessionBelongsToCurrentProduct && session?.state == .busy
                    let runningFlagCanRepresentCurrentProduct = runningAgentIDs.contains(agentID) && sessionBelongsToCurrentProduct
                    return sessionBusy || runningFlagCanRepresentCurrentProduct
                } ?? false

                if isStillOccupied {
                    summary.activeRunningCount += 1
                    summary.lines.append("- 真实运行：".L() + "\(record.visibleName)" + "（".L() + "\(agentLabel)" + "，".L() + "\(Int(elapsed))" + " 秒，有运行占用）".L())
                } else if elapsed >= threshold {
                    summary.staleGhostCount += 1
                    summary.staleGhostRecords.append(record)
                    summary.lines.append("- 幽灵运行：".L() + "\(record.visibleName)" + "（".L() + "\(agentLabel)" + "，".L() + "\(Int(elapsed))" + " 秒，无运行占用）".L())
                } else {
                    summary.freshRunningCount += 1
                    summary.lines.append("- 未超时：".L() + "\(record.visibleName)" + "（".L() + "\(agentLabel)" + "，".L() + "\(Int(elapsed))" + " 秒，无运行占用）".L())
                }
            } catch {
                summary.invalidCount += 1
                summary.lines.append("- 无法读取：".L() + "\(visibleName)" + "，作业档案格式或权限异常。".L())
            }
        }

        return summary
    }

    public func restoreLatestSafetyCheckpoint() {
        guard let url = safetyCheckpointURLs(limit: 1).first else {
            appendEvent(kind: .risk, title: "没有可恢复的安全检查点".L(), detail: "当前本机还没有检查点文件。".L(), agentID: ctoID)
            saveSnapshot()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder.opcCheckpoint.decode(CompanySnapshot.self, from: data)
            guard snapshot.ctoID == ctoID, snapshot.bossID == bossID else {
                appendEvent(kind: .risk, title: "检查点不属于当前公司".L(), detail: "最近安全检查点无法用于当前公司。".L(), agentID: ctoID)
                saveSnapshot()
                return
            }
            applyRestoredSnapshot(snapshot)
            appendEvent(kind: .statusChanged, title: "已回滚到最近安全检查点".L(), detail: "已恢复最近一份本机安全检查点。".L(), agentID: ctoID)
            messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: "已回滚到最近安全检查点：\(checkpointDateText(for: url))。"))
            saveSnapshot()
        } catch {
            appendEvent(kind: .risk, title: "安全检查点恢复失败".L(), detail: error.localizedDescription, agentID: ctoID)
            saveSnapshot()
        }
    }

    public func safetyCheckpointListText(limit: Int = 5) -> String {
        let urls = safetyCheckpointURLs(limit: limit)
        guard !urls.isEmpty else {
            return """
            \("暂无安全检查点。".L())

            \("执行清理、重置、删除产品、技术负责人自动调度前，OPC 会自动保存当前公司状态。".L())
            """
        }

        let lines = urls.enumerated().map { index, url in
            let dateText = checkpointDateText(for: url)
            return "\(index + 1)" + ". ".L() + "\(dateText)" + "\n   本机检查点已保存".L()
        }
        return """
        \("最近安全检查点：".L())
        \(lines.joined(separator: "\n"))

        \("一键回滚会恢复员工、产品、任务、消息、日志、审批、产物、记忆、通信和分支计划。".L())
        \("不会改动真实项目目录里的源码文件。".L())
        """
    }

    public func createSafetyCheckpoint(reason: String) {
        let directory = CompanyPersistence.stateURL.deletingLastPathComponent().appendingPathComponent("checkpoints", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        let fileName = "checkpoint-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"
        let url = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.opcCheckpoint.encode(currentSnapshot())
            try data.write(to: url, options: [.atomic])
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: .report, title: "安全检查点".L().L(), path: "本机安全检查点存档".L().L(), summary: reason), at: 0)
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .passed, title: "安全检查点已创建".L().L(), detail: "安全检查点已保存到本机存档。".L().L()), at: 0)
            appendEvent(kind: .artifactCreated, title: "安全检查点已创建".L().L(), detail: reason, agentID: ctoID)
        } catch {
            verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "安全检查点失败".L().L(), detail: error.localizedDescription), at: 0)
            appendEvent(kind: .risk, title: "安全检查点失败".L().L(), detail: error.localizedDescription, agentID: ctoID)
        }
        saveSnapshot()
    }

    public func persistentTerminalOutputDeltaPreviewForTesting(before baseline: String, after latest: String, inputEcho: String? = nil) -> String {
        persistentTerminalOutputDelta(before: baseline, after: latest, inputEcho: inputEcho)
    }

    public func persistentTerminalTurnClosedPreviewForTesting(capture: String, startMarker: String, endMarker: String) -> Bool {
        persistentTerminalResult(from: capture, startMarker: startMarker, endMarker: endMarker) != nil
    }

    public func persistentTerminalTurnObservationPreviewForTesting(capture: String, startMarker: String, endMarker: String, command: String) -> String {
        let profile = CLIInteractionProfileCatalog.profile(forCommand: command)
        let snapshot = persistentTerminalTurnSnapshot(from: capture, startMarker: startMarker, endMarker: endMarker, profile: profile)
        let resultLine = snapshot.result.map { "结果：退出码 " + "\($0.exitCode)" } ?? "结果：未完成".L().L()
        let phaseLine = snapshot.observation.map { "状态：".L().L() + "\($0.reasonTitle)" } ?? "状态：未识别".L().L()
        let sessionLine = snapshot.observation?.sessionID == nil ? "会话编号：未识别".L().L() : "会话编号：已识别".L().L()
        return "\(resultLine)\n\(phaseLine)\n\(sessionLine)"
    }

    public func persistentTerminalTargetPreviewForTesting(agentID: UUID) -> String {
        guard let agent = agents.first(where: { $0.id == agentID }),
              let target = preparePersistentTerminalTarget(for: agent)
        else { return "未接入".L().L() }
        return "\(target.sessionName):\(target.windowName)"
    }

    public func createHandoffSnapshot() {
        let product = selectedProduct
        let report = product?.importReport
        let snapshot = """
        \("产品交接快照".L())
        \("产品：".L())\(product?.name ?? "当前产品".L())
        \("根目录：".L())\(product?.rootDirectory ?? "未设置".L())
        \("阶段：".L())\(product?.stage.title ?? "未知".L()) / \(product?.status.title ?? "未知".L())
        \("规则文件：".L())\(report?.ruleFiles.joined(separator: "、") ?? "无".L())
        \("工具线索：".L())\(report?.detectedTools.joined(separator: "、") ?? "无".L())
        \("当前任务数：".L())\(selectedProductTasks.count)
        \("员工数：".L())\(selectedProductAgents.count)
        """
        messages.append(ChatMessage(productID: product?.id ?? selectedProductID, agentID: ctoID, author: .system, text: snapshot))
        appendEvent(kind: .artifactCreated, title: "交接快照已生成".L(), detail: "已把当前产品上下文写入技术负责人对话。".L(), agentID: ctoID)
        saveSnapshot()
    }
}

private extension JSONEncoder {
    static var opcCheckpoint: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}


private extension JSONDecoder {
    static var opcCheckpoint: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}


