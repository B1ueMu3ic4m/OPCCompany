import Foundation
import SQLite3

// MARK: - Maintenance
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {

static func legacyDesktopGeneratedProductIndex(from url: URL) -> Int? {
        let last = url.lastPathComponent
        guard last.hasPrefix("OPCProduct") else { return nil }
        let suffix = last.dropFirst("OPCProduct".count)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }
    /// 中文预览（不写快照）：当前产品维护数据增长压力。
    public func maintenanceDataPressureText() -> String {
        let vrCount = selectedProductMaintenanceVerifications.count
        let arCount = selectedProductMaintenanceArtifacts.count
        let vrLatest = selectedProductRecentMaintenanceVerifications.first?.createdAt
        let arLatest = selectedProductRecentMaintenanceArtifacts.first?.createdAt
        let vrThreshold = Self.maintenanceVerificationGrowthAdvisoryThreshold
        let arThreshold = Self.maintenanceArtifactGrowthAdvisoryThreshold
        let stateSnapshotBytes = Self.fileSize(at: CompanyPersistence.stateURL)
        let jobArchiveSummary = currentProductJobArchiveStorageSummary()
        let exceedsVR = vrCount >= vrThreshold
        let exceedsAR = arCount >= arThreshold
        let exceedsState = stateSnapshotBytes >= Self.maintenanceStateSnapshotAdvisoryBytes
        let exceedsJobArchiveCount = jobArchiveSummary.jobCount >= Self.maintenanceJobArchiveCountAdvisoryThreshold
        let exceedsJobArchiveBytes = jobArchiveSummary.bytes >= Self.maintenanceJobArchiveBytesAdvisoryThreshold

        var lines: [String] = [
            "维护数据增长预览：".L().L() + "\(selectedProduct?.name ?? "当前产品")",
            "维护验证记录：".L().L() + "\(vrCount)" + " 条（建议阈值 ".L().L() + "\(vrThreshold)" + " 条）".L().L(),
            "维护产物档案：".L().L() + "\(arCount)" + " 条（建议阈值 ".L().L() + "\(arThreshold)" + " 条）".L().L(),
            "主状态快照：".L() + "\(stateSnapshotBytes > 0 ? Self.byteCountText(stateSnapshotBytes) : "尚未生成")" + "（建议阈值 ".L() + "\(Self.byteCountText(Self.maintenanceStateSnapshotAdvisoryBytes))" + "）",
            "命令行作业档案：".L() + "\(jobArchiveSummary.jobCount)" + " 个 · " + "\(Self.byteCountText(jobArchiveSummary.bytes))" + "（建议阈值 " + "\(Self.maintenanceJobArchiveCountAdvisoryThreshold)" + " 个 / " + "\(Self.byteCountText(Self.maintenanceJobArchiveBytesAdvisoryThreshold))" + "）"
        ]
        if let vrLatest {
            lines.append("最近维护验证：".L().L() + "\(vrLatest.opcDateTimeText)")
        } else {
            lines.append("最近维护验证：暂无".L().L())
        }
        if let arLatest {
            lines.append("最近维护产物：".L().L() + "\(arLatest.opcDateTimeText)")
        } else {
            lines.append("最近维护产物：暂无".L().L())
        }

        if exceedsVR || exceedsAR || exceedsState || exceedsJobArchiveCount || exceedsJobArchiveBytes {
            lines.append("⚠️ 已经达到或超过建议阈值。当前不会自动删除或裁剪主快照——主快照仍是权威状态，请按需在终端大厅维护区运行「历史索引巡检」或「历史归档迁移」把旧记录复制到本地归档表。".L().L())
            if exceedsVR { lines.append("  · 维护验证已达 ".L().L() + "\(vrCount)" + " 条，超过 ".L().L() + "\(vrThreshold)" + " 条阈值。".L().L()) }
            if exceedsAR { lines.append("  · 维护产物已达 ".L().L() + "\(arCount)" + " 条，超过 ".L().L() + "\(arThreshold)" + " 条阈值。".L().L()) }
            if exceedsState { lines.append("  · 主状态快照已达 " + "\(Self.byteCountText(stateSnapshotBytes))" + "，超过 " + "\(Self.byteCountText(Self.maintenanceStateSnapshotAdvisoryBytes))" + " 阈值。") }
            if exceedsJobArchiveCount { lines.append("  · 命令行作业档案已达 ".L().L() + "\(jobArchiveSummary.jobCount)" + " 个，超过 ".L().L() + "\(Self.maintenanceJobArchiveCountAdvisoryThreshold)" + " 个阈值。") }
            if exceedsJobArchiveBytes { lines.append("  · 命令行作业档案体积已达 " + "\(Self.byteCountText(jobArchiveSummary.bytes))" + "，超过 " + "\(Self.byteCountText(Self.maintenanceJobArchiveBytesAdvisoryThreshold))" + " 阈值。") }
        } else {
            lines.append("结论：维护数据未达建议阈值，暂不需要归档处理。".L().L())
        }
        lines.append("说明：仅技术负责人维护侧记录；不进入老板总控台或交付验收中心、不删除任何数据、不裁剪主快照。".L().L())
        return lines.joined(separator: "\n")
    }
    /// 运行维护数据增长巡检：写一条维护类 VerificationRecord，便于技术维护审计中心追踪。
    /// 不修改/不删除任何数据；不写老板聊天/员工协作消息/作业档案。
    @discardableResult
    public func runMaintenanceDataPressureAuditForSelectedProduct() -> VerificationRecord {
        let detail = maintenanceDataPressureText()
        let vrCount = selectedProductMaintenanceVerifications.count
        let arCount = selectedProductMaintenanceArtifacts.count
        let stateSnapshotBytes = Self.fileSize(at: CompanyPersistence.stateURL)
        let jobArchiveSummary = currentProductJobArchiveStorageSummary()
        let exceeds = vrCount >= Self.maintenanceVerificationGrowthAdvisoryThreshold
            || arCount >= Self.maintenanceArtifactGrowthAdvisoryThreshold
            || stateSnapshotBytes >= Self.maintenanceStateSnapshotAdvisoryBytes
            || jobArchiveSummary.jobCount >= Self.maintenanceJobArchiveCountAdvisoryThreshold
            || jobArchiveSummary.bytes >= Self.maintenanceJobArchiveBytesAdvisoryThreshold
        let status: VerificationStatus = exceeds ? .warning : .passed
        let record = VerificationRecord(
            productID: selectedProductID,
            status: status,
            title: "维护数据增长巡检".L().L(),
            detail: detail
        )
        verifications.insert(record, at: 0)
        return record
    }
    public func isTechnicalMaintenanceVerification(_ record: VerificationRecord) -> Bool {
        if isClosureDrillVerification(record) { return true }
        return Self.technicalMaintenanceVerificationTitles.contains(record.title)
    }
    public func localMaintenanceVerificationsOverflow() -> AgentDeskListOverflow? {
        sheetTerminalOverflow(
            total: selectedProductRecentMaintenanceVerifications.count,
            limit: Self.localMaintenanceVerificationDisplayLimit,
            noun: "条维护审计".L().L()
        )
    }
    public func productIsolationAuditText() -> String {
        let validProductIDs = Set(products.map(\.id))
        let orphanTasks = tasks.filter { task in
            guard let productID = task.productID else { return false }
            return !validProductIDs.contains(productID)
        }
        let orphanQueue = workQueue.filter { !validProductIDs.contains($0.productID) }
        let orphanQueueByTask = workQueue.filter { item in
            !tasks.contains { $0.id == item.taskID }
        }
        let orphanApprovals = approvals.filter { !validProductIDs.contains($0.productID) }
        let orphanArtifacts = artifacts.filter { !validProductIDs.contains($0.productID) }
        let orphanVerifications = verifications.filter { !validProductIDs.contains($0.productID) }
        let orphanMemories = memories.filter { !validProductIDs.contains($0.productID) }
        let orphanChannels = communicationChannels.filter { channel in
            guard let productID = channel.productID else { return false }
            return !validProductIDs.contains(productID)
        }
        let orphanLogs = communicationLogs.filter { !validProductIDs.contains($0.productID) }
        let duplicateRoots = Dictionary(grouping: products, by: \.rootDirectory)
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
        let crossProductQueues = workQueue.filter { item in
            guard let task = tasks.first(where: { $0.id == item.taskID }) else { return false }
            return task.productID != nil && task.productID != item.productID
        }

        let issueCount = orphanTasks.count
            + orphanQueue.count
            + orphanQueueByTask.count
            + orphanApprovals.count
            + orphanArtifacts.count
            + orphanVerifications.count
            + orphanMemories.count
            + orphanChannels.count
            + orphanLogs.count
            + duplicateRoots.count
            + crossProductQueues.count

        let productLines = products.map { product in
            let taskCount = tasks.filter { $0.productID == product.id }.count
            let queueCount = workQueue.filter { $0.productID == product.id }.count
            let memberCount = product.assignedAgentIDs.count
            let leadName = product.teamLeadAgentID.map(agentName) ?? "未设置".L()
            return "- ".L() + "\(product.name)" + "：成员 ".L() + "\(memberCount)" + "，负责人 ".L() + "\(leadName)" + "，任务 ".L() + "\(taskCount)" + "，队列 ".L() + "\(queueCount)"
        }.joined(separator: "\n")

        return """
        \("多产品隔离体检：".L())\(issueCount == 0 ? "通过" : "发现 \(issueCount) 项问题")

        \("产品概览：".L())
        \(productLines.isEmpty ? "- 暂无产品" : productLines)

        \("隔离检查：".L())
        \("- 孤儿任务：".L())\(orphanTasks.count)
        \("- 孤儿队列：".L())\(orphanQueue.count + orphanQueueByTask.count)
        \("- 跨产品队列：".L())\(crossProductQueues.count)
        \("- 孤儿审批：".L())\(orphanApprovals.count)
        \("- 孤儿产物：".L())\(orphanArtifacts.count)
        \("- 孤儿验收：".L())\(orphanVerifications.count)
        \("- 孤儿记忆：".L())\(orphanMemories.count)
        \("- 孤儿通信配置：".L())\(orphanChannels.count)
        \("- 孤儿通信日志：".L())\(orphanLogs.count)
        \("- 重复产品目录：".L())\(duplicateRoots.count)

        \("结论：".L())
        \(issueCount == 0 ? "当前产品数据按产品归属隔离，未发现明显串线。" : "存在隔离风险，建议先清理或修复孤儿/跨产品数据。")
        """
    }
    public func runProductIsolationAudit() {
        let report = productIsolationAuditText()
        let passed = report.contains("多产品隔离体检：通过".L().L())
        verifications.insert(VerificationRecord(productID: selectedProductID, status: passed ? .passed : .warning, title: "多产品隔离体检".L().L(), detail: report), at: 0)
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(kind: passed ? .artifactCreated : .risk, title: "多产品隔离体检完成".L().L(), detail: passed ? "通过".L().L() : "发现隔离风险".L().L(), agentID: ctoID)
        saveSnapshot()
    }
    func readinessAuditFailed(reason: String, detail: String) -> TerminalAutoInteractionReadinessAudit {
        TerminalAutoInteractionReadinessAudit(
            rejectionReason: reason,
            auditLine: "就绪校验：未确认最近专用就绪提示，已拒绝自动发送。原因：".L().L() + "\(detail)" + "。"
        )
    }
    public func scanLinkedLocalFiles(limit: Int = 300) {
        guard let product = selectedProduct else { return }
        // LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST（角色继承期轮 21 标记 + 轮 27 部分落地 + candidate ψ 白名单第一阶段）：
        // product.rootDirectory 是用户可写的原始字符串。多层加固：
        // R21：用 .standardizedFileURL 折叠 `..` 段防相对路径越界。
        // R27（候选 ψ 部分落地）：(a) .resolvingSymlinksInPath 解析符号链接后判定是否落入系统保留路径；
        //                          (b) 系统路径黑名单（/System, /private/var/db, /private/etc, /usr, /bin, /sbin）；
        //                          symlink 解析仅用于安全判定，artifact 写入仍保留**原 path** 不改用户可见语义。
        //                          越界时 verifications 写 .failed + appendEvent .risk + return（不静默）。
        // candidate ψ 第一阶段：显式根白名单限定在已登记 ProductWorkspace.rootDirectory 列表；
        // rawRoot 和 resolvedRoot 都必须落在这些根之内，避免 symlink 把索引带到未登记目录。
        // 仍待后续：把根白名单配置入口产品化到技术维护/导入设置侧，不进入老板总控。
        // 守门测试 `scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker`（R21）+ `scanLinkedLocalFilesRejectsSystemReservedRootPath` / `scanLinkedLocalFilesRejectsSymlinkResolvingToSystemReservedPath`（R27）防止此加固被误删。
        // R31 自洽性条件断言推广：`scanLinkedLocalFilesEnumeratorAndLimitationMarkerStaySelfConsistent`
        // 双向验证 marker + enumerator 调用 + R27 二层防御（symlink + 黑名单）三者同步存在/同步移除（防双删 regression）。
        let rawRoot = URL(fileURLWithPath: NSString(string: product.rootDirectory).expandingTildeInPath).standardizedFileURL
        let resolvedRoot = rawRoot.resolvingSymlinksInPath()
        if Self.isSystemReservedPath(rawRoot) || Self.isSystemReservedPath(resolvedRoot) {
            rejectLinkedLocalFileIndexRoot(reason: "产品根目录解析后落在系统保留路径 (\(resolvedRoot.path))，已拒绝索引以避免污染产物列表。请把根目录指向用户可写目录。".L(), eventTitle: "本地文件索引拒绝系统路径".L(), eventDetail: "rootDirectory=\(product.rootDirectory) 解析为 \(resolvedRoot.path)，落在系统保留路径黑名单。".L())
            return
        }
        let allowedRootPaths = Self.linkedLocalFileAllowedRootPaths(from: products)
        if !Self.isAllowedLinkedLocalFileRoot(rawRoot: rawRoot, resolvedRoot: resolvedRoot, allowedRootPaths: allowedRootPaths) {
            rejectLinkedLocalFileIndexRoot(reason: "产品根目录解析后不在已登记工作区根白名单内 (\(resolvedRoot.path))，已拒绝索引。请通过产品导入或项目设置登记该根目录。".L(), eventTitle: "本地文件索引拒绝未登记根目录".L(), eventDetail: "rootDirectory=\(product.rootDirectory) 解析为 \(resolvedRoot.path)，不在已登记工作区根白名单。".L())
            return
        }
        let root = rawRoot
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let usefulExtensions: Set<String> = ["md", "txt", "pdf", "docx", "pptx", "xlsx", "csv", "json", "swift", "js", "ts", "tsx", "py"]
        var count = 0
        for case let url as URL in enumerator {
            if count >= limit { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            guard usefulExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if artifacts.contains(where: { $0.productID == selectedProductID && $0.path == url.path }) { continue }
            // title 必须以 `本地文件索引：` 前缀开头，进入 `technicalMaintenanceArtifactTitlePrefixes` 分类，
            // 让产物只出现在维护产物档案中心，不污染老板/交付视图。
            // summary 仍保留中文路径线索，便于技术负责人对照原文件名。
            artifacts.insert(ArtifactRecord(productID: selectedProductID, kind: artifactKind(for: url), title: "本地文件索引：".L().L() + "\(url.lastPathComponent)", path: url.path, summary: "本地文件索引：".L().L() + "\(url.lastPathComponent)"), at: 0)
            count += 1
        }
        verifications.insert(VerificationRecord(productID: selectedProductID, status: count > 0 ? .passed : .warning, title: "本地文件索引完成".L().L(), detail: "新增 " + "\(count)" + " 个本地文件索引。"), at: 0)
        appendEvent(kind: .artifactCreated, title: "本地文件已联动".L().L(), detail: "新增 " + "\(count)" + " 个本地文件索引。", agentID: ctoID)
        saveSnapshot()
    }
    func rejectLinkedLocalFileIndexRoot(reason: String, eventTitle: String, eventDetail: String) {
        verifications.insert(VerificationRecord(productID: selectedProductID, status: .failed, title: "本地文件索引被拒绝".L().L(), detail: reason), at: 0)
        appendEvent(kind: .risk, title: eventTitle, detail: eventDetail, agentID: ctoID)
        saveSnapshot()
    }
    public func productTeamIsolationText() -> String {
        guard let product = selectedProduct else { return "未选择产品。".L() }
        let teamIDs = product.assignedAgentIDs
        let members = selectedProductAgents.map { agent in
            "- \(agent.displayName)：\(agent.role.title)\(agent.id == product.teamLeadAgentID ? " / 团队负责人" : "")"
        }.joined(separator: "\n")
        let outsiders = agents.filter { $0.role != .boss && !teamIDs.contains($0.id) }.map { agent in
            "- ".L() + "\(agent.displayName)" + "：不参与当前产品，不会被当前产品发车台启动。".L()
        }.joined(separator: "\n")

        return """
        \("产品团队隔离规则".L())
        \("产品：".L())\(product.name)
        \("根目录：".L())\(product.rootDirectory)
        \("团队负责人：".L())\(teamLeadAgentIDForSelectedProduct().map(agentName) ?? "未设置")

        \("当前产品团队：".L())
        \(members.isEmpty ? "- 暂无团队成员" : members)

        \("非当前产品员工：".L())
        \(outsiders.isEmpty ? "- 无" : outsiders)

        \("执行规则：".L())
        \("- 工作队列只允许当前产品任务进入。".L())
        \("- 命令行任务发车台只启动当前产品团队员工。".L())
        \("- 非当前产品员工不能接收当前产品队列任务。".L())
        \("- 切换产品时会重新写出团队员工工作区上下文。".L())
        """
    }
    public func jobArchiveStaleAuditText(staleAfter seconds: TimeInterval = 180) -> String {
        let summary = jobArchiveStaleAuditSummary(staleAfter: seconds)
        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let header = """
        \("命令行作业幽灵巡检：".L())\(summary.passed ? "通过".L() : "需处理")
        \("产品：".L())\(productLabel)
        \("作业档案：".L())\(summary.totalCount)
        \("运行中：".L())\(summary.runningCount)\(" · 幽灵运行：".L())\(summary.staleGhostCount)\(" · 真实运行：".L())\(summary.activeRunningCount)\(" · 未超时：".L())\(summary.freshRunningCount)\(" · 无法读取：".L())\(summary.invalidCount)
        \("阈值：".L())\(Int(max(seconds, 60)))\(" 秒".L())
        """
        let body = summary.lines.isEmpty
            ? "- 当前产品没有命令行作业档案。".L()
            : summary.lines.joined(separator: "\n")
        return """
        \(header)

        \("作业档案明细：".L())
        \(body)

        \("说明：".L())
        \("本次预览只扫描当前产品根目录的命令行作业档案。实际巡检只会把已经超时、仍标记运行中、但没有员工运行占用的旧作业标记为已中断；不会启动模型任务、不会写老板聊天、不会新增员工协作消息。".L())
        """
    }
    @discardableResult
    public func runJobArchiveStaleAuditForSelectedProduct(staleAfter seconds: TimeInterval = 180) -> VerificationStatus {
        var summary = jobArchiveStaleAuditSummary(staleAfter: seconds)
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var interruptedLines: [String] = []
        var interruptedCount = 0
        let reportBefore = jobArchiveStaleAuditText(staleAfter: seconds)

        for record in summary.staleGhostRecords {
            do {
                if try interruptCLIJobArchive(record, now: now, formatter: formatter) {
                    let elapsed = Int(now.timeIntervalSince(record.updatedAt))
                    interruptedLines.append("- " + "\(record.visibleName)" + "：已标记已中断（静置 ".L().L() + "\(elapsed)" + " 秒）".L().L())
                    interruptedCount += 1
                } else {
                    interruptedLines.append("- " + "\(record.visibleName)" + "：磁盘状态已变化，跳过写回。".L().L())
                }
            } catch {
                summary.invalidCount += 1
                interruptedLines.append("- " + "\(record.visibleName)" + "：写回失败，".L().L() + "\(error.localizedDescription)")
            }
        }

        let productLabel = selectedProduct?.name ?? "当前产品".L()
        let status: VerificationStatus = (summary.staleGhostCount == 0 && summary.invalidCount == 0) ? .passed : .warning
        let report = """
        \(reportBefore)

        \("处理结果：".L())
        \(interruptedLines.isEmpty ? "- 没有需要中断的幽灵作业档案。".L() : interruptedLines.joined(separator: "\n"))
        """
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "命令行作业幽灵巡检".L(),
                detail: report
            ),
            at: 0
        )
        appendEvent(
            kind: .statusChanged,
            title: "命令行作业幽灵巡检完成".L(),
            detail: "\(productLabel)" + " · 中断 ".L() + "\(interruptedCount)" + " 个幽灵作业 · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }
    public func historyIndexAuditText() -> String {
        let productLabel = selectedProduct?.name ?? "当前产品"
        let indexURL = CompanyPersistence.historyIndexURL
        let fileExists = FileManager.default.fileExists(atPath: indexURL.path)
        let stats = try? CompanyHistorySQLiteIndex.stats(at: indexURL)
        let productResultCount = (try? CompanyHistorySQLiteIndex.search(at: indexURL, query: productLabel, productID: selectedProductID, limit: 100).count) ?? 0
        let indexedAt = stats?.lastIndexedAt?.opcDateTimeText ?? "尚未生成"
        let statusText: String
        if let stats, stats.recordCount > 0 {
            statusText = "通过"
        } else if fileExists {
            statusText = "需重建"
        } else {
            statusText = "未创建"
        }

        return """
        \("历史索引巡检：".L())\(statusText)
        \("产品：".L())\(productLabel)
        \("索引位置：".L())\(indexURL.path)
        \("索引文件：".L())\(fileExists ? "已存在" : "未创建")
        \("记录数：".L())\(stats?.recordCount ?? 0)
        \("产品数：".L())\(stats?.productCount ?? 0)
        \("最近索引：".L())\(indexedAt)
        \("当前产品可检索记录：".L())\(productResultCount)

        \("说明：".L())
        \("主快照仍是权威状态；本地历史索引只作为可重建的查询层，用于大规模消息、事件、任务、审批、产物、验收、记忆、通信日志和员工协作消息检索。索引损坏时可以直接重建，不影响产品主状态。".L())
        """
    }
    @discardableResult
    public func runHistoryIndexAuditForSelectedProduct() -> VerificationStatus {
        let status: VerificationStatus
        let report: String
        do {
            let stats = try CompanyPersistence.rebuildHistoryIndex(currentSnapshot())
            status = stats.recordCount > 0 ? .passed : .warning
            report = """
            \("历史索引巡检：".L())\(status.title)
            \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
            \("索引位置：".L())\(CompanyPersistence.historyIndexURL.path)
            \("记录数：".L())\(stats.recordCount)
            \("产品数：".L())\(stats.productCount)
            \("最近索引：".L())\(stats.lastIndexedAt?.opcDateTimeText ?? "刚刚完成")

            \("说明：".L())
            \("本次已从当前主快照重建本地历史索引。主快照仍是权威状态；历史索引只作为可重建查询层，不替代主状态存储。".L())
            """
        } catch {
            status = .failed
            report = """
            \("历史索引巡检：失败".L())
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("索引位置：".L())\(CompanyPersistence.historyIndexURL.path)
            \("错误：".L())\(error.localizedDescription)

            \("说明：".L())
            \("主快照没有被修改；本地历史索引只是可重建查询层。本次失败表示历史检索不可用，但不会影响当前产品状态读写。".L())
            """
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "历史索引巡检".L().L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .failed ? .risk : .statusChanged,
            title: "历史索引巡检完成".L().L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }
    public func historyArchiveMigrationText(retentionDays: Int = 30) -> String {
        let safeDays = max(retentionDays, 1)
        let cutoffAt = Date(timeIntervalSinceNow: -TimeInterval(safeDays * 24 * 60 * 60))
        let archiveStats = try? CompanyPersistence.historyArchiveStats()
        let archiveCount = archiveStats?.archivedRecordCount ?? 0
        let archivedAt = archiveStats?.lastArchivedAt?.opcDateTimeText ?? (archiveCount > 0 ? "未知（旧归档表）".L() : "尚未迁移".L())
        return """
        \("历史归档迁移：预览".L())
        \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
        \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
        \("已归档记录：".L())\(archiveCount)
        \("最近归档：".L())\(archivedAt)

        \("说明：".L())
        \("本迁移只把旧消息、事件、通信日志和员工协作消息复制到本地归档表；主快照仍是权威状态，本轮不会裁剪主快照、不会删除本地文件、不会启动模型任务。归档表可由主快照重建，归档失败不影响产品主状态。".L())
        """
    }
    @discardableResult
    public func runHistoryArchiveMigrationForSelectedProduct(retentionDays: Int = 30) -> VerificationStatus {
        let safeDays = max(retentionDays, 1)
        let cutoffAt = Date(timeIntervalSinceNow: -TimeInterval(safeDays * 24 * 60 * 60))
        let status: VerificationStatus
        let report: String
        do {
            let stats = try CompanyPersistence.archiveHistory(currentSnapshot(), olderThan: cutoffAt)
            status = .passed
            report = """
            \("历史归档迁移：通过".L())
            \("产品：".L())\(selectedProduct?.name ?? "当前产品")
            \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
            \("写入归档记录：".L())\(stats.archivedRecordCount)
            \("覆盖产品数：".L())\(stats.productCount)
            \("最近归档：".L())\(stats.lastArchivedAt?.opcDateTimeText ?? "刚刚完成")

            \("说明：".L())
            \("本次只把旧消息、事件、通信日志和员工协作消息复制到本地归档表；主快照仍是权威状态，本轮不裁剪主快照、不删除本地文件、不启动模型任务。后续只有在快照体积和加载性能达到阈值时，才考虑安全裁剪主快照中的旧历史。".L())
            """
        } catch {
            status = .failed
            report = """
            \("历史归档迁移：失败".L())
            \("产品：".L())\(selectedProduct?.name ?? "当前产品".L())
            \("归档阈值：早于 ".L())\(cutoffAt.opcDateTimeText)\(" 的历史记录".L())
            \("错误：".L())\(error.localizedDescription)

            \("说明：".L())
            \("主快照没有被修改；本地归档表只是可重建的历史迁移层。本次失败不会影响当前产品状态读写。".L())
            """
        }
        verifications.insert(
            VerificationRecord(
                productID: selectedProductID,
                status: status,
                title: "历史归档迁移".L(),
                detail: report
            ),
            at: 0
        )
        messages.append(ChatMessage(productID: selectedProductID, agentID: ctoID, author: .system, text: report))
        appendEvent(
            kind: status == .failed ? .risk : .statusChanged,
            title: "历史归档迁移完成".L(),
            detail: "\(selectedProduct?.name ?? "当前产品".L())" + " · ".L() + "\(status.title)",
            agentID: ctoID
        )
        saveSnapshot()
        return status
    }
    func ensureGitIsolationSource(for agent: CompanyAgent, sourceRoot: URL, sourceDirectory: URL) {
        if cliIsolationDirectoryIsRunnable(sourceDirectory, sourceRoot: sourceRoot) { return }
        if FileManager.default.fileExists(atPath: sourceDirectory.path),
           (try? FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path).isEmpty) == false {
            appendEvent(kind: .risk, title: "独立代码仓库工作区未创建".L().L(), detail: "\(agent.displayName)" + "：目标目录已有内容，暂不覆盖。" + "\(sourceDirectory.path)", agentID: agent.id)
            return
        }

        let result = runLocalProcess(
            executable: "/usr/bin/git",
            arguments: ["-C", sourceRoot.path, "worktree", "add", "--detach", sourceDirectory.path, "HEAD"],
            workingDirectory: sourceRoot
        )
        if result.exitCode != 0 {
            appendEvent(kind: .risk, title: "独立代码仓库工作区创建失败".L().L(), detail: "\(agent.displayName)：\(result.output)", agentID: agent.id)
            if sourceRootLooksLikeProject(sourceRoot), !FileManager.default.fileExists(atPath: sourceDirectory.path) {
                try? ensureDirectorySnapshotIsolationSource(sourceRoot: sourceRoot, sourceDirectory: sourceDirectory)
            }
        }
    }
}
