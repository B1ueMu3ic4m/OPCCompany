import SwiftUI

enum CommandCenterSection: String, CaseIterable, Identifiable {
    case overview
    case decisions
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "老板总览"
        case .decisions: "待我决策"
        case .reports: "汇报交付"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "speedometer"
        case .decisions: "hand.raised.fill"
        case .reports: "doc.text.magnifyingglass"
        }
    }
}

struct MultiAgentArchitectureAuditCenter: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var isShowingClosureTrace = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "多员工架构体检")
                Text("按升级方案检查结构化消息总线、显式任务图、技术负责人调度闭环、交付证据库、验收门禁、持久终端可用性和老板视图是否闭合。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(store.selectedProductArchitectureCompletionScore)%")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("架构完成度")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    Spacer(minLength: 0)
                }

                Button {
                    store.runMultiAgentArchitectureAudit()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("生成架构体检报告", systemImage: "checklist.checked")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(scoreColor)

                Button {
                    _ = store.runMultiAgentArchitectureClosureDrill()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("运行闭环演练", systemImage: "arrow.trianglehead.2.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    store.runCLIRuntimeIsolationAudit()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("运行命令行与工作区隔离体检", systemImage: "rectangle.connected.to.line.below")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    isShowingClosureTrace = true
                } label: {
                    Label("查看闭环详情", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedProductClosureTraces.isEmpty)

                if let trace = store.latestSelectedProductClosureTrace {
                    Text("最近闭环：\(trace.goal) · \(trace.completionScore)% · 消息 \(trace.messageIDs.count) · 产物 \(trace.artifactIDs.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(2)
                }

                ClosureDrillSummaryCard()
                ProductReworkSummaryCard()

                Text("报告写入技术负责人对话，不进入老板首页；老板只看结果、风险和交付摘要。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
            }
            .commandPanel()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "检查项")
                ForEach(store.selectedProductArchitectureChecks) { check in
                    ArchitectureCheckRow(check: check)
                }
            }
            .commandPanel()
        }
        .sheet(isPresented: $isShowingClosureTrace) {
            MultiAgentClosureTraceSheet()
                .environmentObject(store)
        }
    }

    private var scoreColor: Color {
        switch store.selectedProductArchitectureCompletionScore {
        case 80...100: CompanyTheme.green
        case 50..<80: CompanyTheme.warning
        default: CompanyTheme.red
        }
    }
}

struct EmployeeHandoffAuditPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("员工交接巡检预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.employeeHandoffAuditText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.employeeHandoffAuditPreview.rawValue)
        .accessibilityLabel("员工交接巡检预览")
        .accessibilityValue(store.employeeHandoffAuditText())
    }
}

/// 本地维护详情：运行会话健康巡检的就地预览卡片。
/// 与按钮同列，点击「运行会话健康巡检」会写入一条新的 `VerificationRecord`，
/// 该卡片读最近一条记录并显示状态、时间和详情；尚未运行过时显示中文空态文案
/// 加上当前可执行员工的实时巡检文本兜底（`运行来源 / 来源配置 / 来源漂移` 等中文产品话术）。
struct RuntimeSessionHealthAuditPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("运行会话健康巡检预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            if let latest = store.selectedProductLatestRuntimeSessionHealthAudit() {
                Text("最近一次巡检：\(latest.status.title) · \(latest.createdAt.opcDateTimeText)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
                Text(latest.detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("尚未运行巡检 · 点击上方按钮可在此就地查看运行来源 / 来源配置 / 来源漂移结果。")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CompanyTheme.muted)
                Text(store.runtimeSessionHealthAuditText())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted.opacity(0.85))
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.runtimeSessionHealthAuditPreview.rawValue)
        .accessibilityLabel("运行会话健康巡检预览")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let latest = store.selectedProductLatestRuntimeSessionHealthAudit() {
            return """
            最近一次巡检：\(latest.status.title) · \(latest.createdAt.opcDateTimeText)
            \(latest.detail)
            """
        }
        return """
        尚未运行巡检 · 点击上方按钮可在此就地查看运行来源 / 来源配置 / 来源漂移结果。
        \(store.runtimeSessionHealthAuditText())
        """
    }
}

struct JobArchiveStaleAuditPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("命令行作业幽灵巡检预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.jobArchiveStaleAuditText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.jobArchiveStaleAuditPreview.rawValue)
        .accessibilityLabel("命令行作业幽灵巡检预览")
        .accessibilityValue(store.jobArchiveStaleAuditText())
    }
}

struct EvidenceClassificationAuditPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("运行证据分类巡检预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.evidenceClassificationAuditText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(20)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.evidenceClassificationAuditPreview.rawValue)
        .accessibilityLabel("运行证据分类巡检预览")
        .accessibilityValue(store.evidenceClassificationAuditText())
    }
}

struct MaintenanceDataPressurePreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("维护数据增长预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.maintenanceDataPressureText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(20)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceDataPressurePreview.rawValue)
        .accessibilityLabel("维护数据增长预览")
        .accessibilityValue(store.maintenanceDataPressureText())
    }
}

struct HistoryIndexAuditPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("历史索引预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.historyIndexAuditText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.historyIndexAuditPreview.rawValue)
        .accessibilityLabel("历史索引预览")
        .accessibilityValue(store.historyIndexAuditText())
    }
}

struct HistoryArchiveMigrationPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("历史归档迁移预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.historyArchiveMigrationText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.historyArchiveMigrationPreview.rawValue)
        .accessibilityLabel("历史归档迁移预览")
        .accessibilityValue(store.historyArchiveMigrationText())
    }
}

struct ManualREPLTurnPanel: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var lastReport: CompanyStore.ManualREPLTurnReport?

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending && !trimmedInput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动交互轮次（仅供运维和技术负责人调试）")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text("向当前选中员工的真实终端席位发送一行输入，等待该员工的就绪提示或本轮结束信号；仅 Codex / Claude Code / Gemini 等已配置就绪提示的命令行工具可用，老板视图不展示。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
            Text("当前员工：\(store.selectedAgent?.displayName ?? "未选中员工")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.ink.opacity(0.82))

            TextField("输入一行（不能含换行）", text: $inputText)
                .disabled(isSending)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalManualREPLInputField.rawValue)
                .accessibilityLabel("手动交互一行输入")
                .accessibilityHint("向当前选中员工的真实终端席位发送一行输入，不能包含换行")

            Button {
                let pending = inputText
                inputText = ""
                isSending = true
                Task {
                    let report = await store.runManualREPLTurnForSelectedAgent(text: pending)
                    await MainActor.run {
                        self.lastReport = report
                        self.isSending = false
                    }
                }
            } label: {
                Label(isSending ? "发送中…" : "发送一行手动输入", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanyTheme.accent)
            .disabled(!canSend)
            .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalManualREPLSendButton.rawValue)
            .accessibilityLabel(isSending ? "正在发送手动交互输入" : "发送一行手动交互输入")
            .accessibilityHint("发送输入框中的一行文本到当前选中员工真实终端席位；输入为空或正在发送时禁用")

            if let report = lastReport {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一次结果")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(CompanyTheme.muted)
                    if report.rejected, let reason = report.rejectionReason, !reason.isEmpty {
                        Text("拒绝原因：\(reason)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CompanyTheme.warning)
                    } else {
                        Text("状态：\(report.summary)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(report.timedOut ? CompanyTheme.warning : CompanyTheme.ink)
                        if !report.outputPreview.isEmpty {
                            Text("输出摘要：\(report.outputPreview)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CompanyTheme.muted)
                                .lineLimit(8)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct TerminalAutoInteractionLoopPanel: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var taskContext: String = ""
    @State private var maxTurns: Int = 3
    @State private var isRunning: Bool = false
    @State private var lastReport: CompanyStore.TerminalAutoInteractionLoopReport?

    private var trimmedContext: String {
        taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRun: Bool {
        !isRunning && !trimmedContext.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("真实终端自动交互循环（技术负责人）")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoInteractionLoopPanel.rawValue)
                .accessibilityLabel("真实终端自动交互循环面板")
            Text("由 OPC 生成每轮单行输入并发送到当前选中员工的真实终端席位；授权异常、忙碌、临时异常或等待超时会立即停止。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
            Text("当前员工：\(store.selectedAgent?.displayName ?? "未选中员工")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.ink.opacity(0.82))

            TextField("填写技术负责人任务上下文", text: $taskContext, axis: .vertical)
                .lineLimit(2...4)
                .disabled(isRunning)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoLoopTaskContextField.rawValue)
                .accessibilityLabel("技术负责人任务上下文")
                .accessibilityHint("填写本轮自动循环要继续推进的任务上下文")

            Stepper("最大轮次：\(maxTurns)", value: $maxTurns, in: 1...CLIAutoInteractionLoopGate.hardTurnLimit)
                .font(.system(size: 10, weight: .semibold))
                .disabled(isRunning)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoLoopMaxTurnsStepper.rawValue)
                .accessibilityLabel("最大轮次")
                .accessibilityValue("\(maxTurns)")

            Button {
                let pendingContext = taskContext
                isRunning = true
                Task {
                    let report = await store.runTerminalAutoInteractionLoopForSelectedAgent(
                        taskContext: pendingContext,
                        maxTurns: maxTurns
                    )
                    await MainActor.run {
                        self.lastReport = report
                        self.isRunning = false
                    }
                }
            } label: {
                Label(isRunning ? "循环执行中…" : "启动受控循环", systemImage: "arrow.trianglehead.2.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanyTheme.blue)
            .disabled(!canRun)
            .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoLoopStartButton.rawValue)
            .accessibilityLabel(isRunning ? "循环执行中" : "启动受控自动循环")
            .accessibilityHint("由 OPC 生成单行输入发送到当前员工真实终端席位；遇到授权异常、忙碌、临时异常或超时会立即停止")

            if let report = lastReport {
                Text(report.summaryText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(report.rejected ? CompanyTheme.warning : CompanyTheme.muted)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalAutoLoopReportSummary.rawValue)
                    .accessibilityLabel(report.rejected ? "真实终端自动循环已拒绝" : "真实终端自动循环报告")
                    .accessibilityValue(report.summaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("真实终端自动交互循环面板")
    }
}

struct CLIRecoveryAdvicePanel: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var lastRetryReport: CompanyStore.CLIRecoveryRetryReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("员工恢复建议（仅技术负责人调试）")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text("根据最近一次命令行状态观察提示运维操作；授权异常和忙碌不允许自动重开，临时异常仅提供受控的单次手动重试入口；老板总控台不展示。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)

            Text(store.cliRecoveryAdviceSummaryText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(20)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceSummary.rawValue)
                .accessibilityLabel("员工恢复建议摘要")
                .accessibilityValue(store.cliRecoveryAdviceSummaryText())

            let advices = store.cliRecoveryAdvicesForSelectedProduct()
            if !advices.isEmpty {
                ForEach(advices, id: \.agentID) { entry in
                    HStack(spacing: 8) {
                        Text(entry.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanyTheme.ink)
                        Spacer()
                        Button {
                            let report = store.manualRetryTransientForAgent(agentID: entry.agentID)
                            lastRetryReport = report
                        } label: {
                            Label("手动重试一次", systemImage: "arrow.clockwise.circle")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(CompanyTheme.warning)
                        .disabled(!entry.canManualRetry)
                        .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceManualRetryButton.rawValue)
                        .accessibilityLabel("\(entry.displayName) · 手动重试一次")
                        .accessibilityHint("仅当员工最近一次状态为临时异常时可用；授权异常、忙碌或尚未观察状态不会自动重开")
                    }
                    .padding(.vertical, 2)
                }
            }

            if let report = lastRetryReport {
                Text(report.success ? "已发起一次：\(report.reason)" : "未发起：\(report.reason)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(report.success ? CompanyTheme.green : CompanyTheme.warning)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panelRaised.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdvicePanel.rawValue)
        .accessibilityLabel("员工恢复建议面板")
        .accessibilityChildren {
            Text(store.cliRecoveryAdviceSummaryText())
                .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceSummary.rawValue)
                .accessibilityLabel("员工恢复建议摘要")
                .accessibilityValue(store.cliRecoveryAdviceSummaryText())
            ForEach(store.cliRecoveryAdvicesForSelectedProduct(), id: \.agentID) { entry in
                Button {
                    let report = store.manualRetryTransientForAgent(agentID: entry.agentID)
                    lastRetryReport = report
                } label: {
                    Text("手动重试一次")
                }
                .disabled(!entry.canManualRetry)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRecoveryAdviceManualRetryButton.rawValue)
                .accessibilityLabel("\(entry.displayName) · 手动重试一次")
                .accessibilityHint("仅当员工最近一次状态为临时异常时可用；授权异常、忙碌或尚未观察状态不会自动重开")
            }
        }
    }
}

struct TerminalWorkspaceHealthPreview: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("持久终端可用性预览")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.terminalWorkspaceHealthAuditText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalWorkspaceHealthPreview.rawValue)
        .accessibilityLabel("持久终端可用性预览")
        .accessibilityValue(store.terminalWorkspaceHealthAuditText())
    }
}

struct ClosureDrillSummaryCard: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("闭环演练复盘摘要")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(store.selectedProductClosureDrillSummaryText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProductReworkSummaryCard: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("返工追踪")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                if !store.selectedProductReworkQueue.isEmpty {
                    StatusPill(text: "\(store.selectedProductReworkQueue.count) 项", color: CompanyTheme.warning)
                }
            }
            Text(store.selectedProductReworkSummaryText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ArchitectureCheckRow: View {
    let check: MultiAgentArchitectureCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(check.title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    StatusPill(text: check.status.title, color: color)
                    Spacer(minLength: 0)
                }
                Text(check.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch check.status {
        case .passed: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .failed: CompanyTheme.red
        }
    }

    private var icon: String {
        switch check.status {
        case .passed: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

struct CommunicationGatewayCommandCenter: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var mobileCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                gatewayOverview
                remoteCommandPanel
            }

            HStack(alignment: .top, spacing: 14) {
                channelPanel
                logPanel
            }
        }
    }

    private var gatewayOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "OPC 通信网关")
            Text("目标是让每个产品团队负责人可以通过手机向老板汇报，也能接收老板的远程指令。本机应用负责调度和执行；外部通道负责通知、回传和唤醒。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)

            EngineMetricRow(title: "通道配置", value: "\(store.selectedProductCommunicationChannels.count)", color: CompanyTheme.blue)
            EngineMetricRow(title: "启用通道", value: "\(store.selectedProductCommunicationChannels.filter(\.isEnabled).count)", color: CompanyTheme.green)
            EngineMetricRow(title: "可接收指令", value: "\(store.selectedProductCommunicationChannels.filter { $0.isEnabled && $0.commandsEnabled && $0.kind.supportsInboundCommand }.count)", color: CompanyTheme.accent)
            EngineMetricRow(title: "通信日志", value: "\(store.selectedProductCommunicationLogs.count)", color: CompanyTheme.warning)

            Button {
                store.ensureCommunicationGatewayPlan()
            } label: {
                Label("生成默认通信方案", systemImage: "network")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanyTheme.accent)

            Button {
                store.sendTeamLeadReportThroughGateway()
            } label: {
                Label("生成手机汇报", systemImage: "doc.text.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                store.dispatchTeamLeadReportThroughGateway()
            } label: {
                Label("发送到就绪通道", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CompanyTheme.blue)

            Button {
                store.testCommunicationGatewayChannels()
            } label: {
                Label("测试通信通道", systemImage: "checkmark.shield.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .commandPanel()
    }

    private var remoteCommandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "手机指令模拟")
            Text("真实接入前，先在本地模拟手机端发来的老板指令：网关会记录日志、通知团队负责人，并创建可追踪任务。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
            TextField("例如：让默认产品团队今晚前给我一版售前方案", text: $mobileCommand, axis: .vertical)
                .commandTextField(lineLimit: 2...5)
            Button {
                store.ingestRemoteCommand(mobileCommand)
                mobileCommand = ""
            } label: {
                Label("模拟手机发给 OPC", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanyTheme.warning)
            .disabled(mobileCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            RuleLine(title: "外部接入原则", detail: "网络回调通道先做外发汇报；双向指令优先走 Telegram 机器人或企业应用回调，不建议用个人微信做第一版。")
            Text(store.communicationGatewayMobileLinkText())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .commandPanel()
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "通道")
            if store.selectedProductCommunicationChannels.isEmpty {
                EmptyCommandLine(text: "还没有通信通道。点击“生成默认通信方案”。")
            } else {
                ForEach(store.selectedProductCommunicationChannels) { channel in
                    CommunicationChannelCard(channel: channel)
                }
            }
        }
        .commandPanel()
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近通信")
            if store.selectedProductCommunicationLogs.isEmpty {
                EmptyCommandLine(text: "暂无通信日志。")
            } else {
                ForEach(store.communicationGatewayVisibleLogs) { entry in
                    CommunicationLogCard(entry: entry)
                }
                if let overflow = store.communicationGatewayLogsOverflow() {
                    OPCListOverflowFooter(summary: overflow.summary)
                }
            }
        }
        .commandPanel()
    }
}

private enum LocalMaintenanceDangerousAction: String, CaseIterable, Identifiable {
    case cleanup
    case reset
    case rollback

    var id: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .cleanup: "清理当前产品运行/测试数据"
        case .reset: "恢复默认公司状态"
        case .rollback: "回滚到最近安全检查点"
        }
    }

    var title: String {
        switch self {
        case .cleanup: "确认清理当前产品运行/测试数据"
        case .reset: "确认恢复默认公司状态"
        case .rollback: "确认回滚到最近安全检查点"
        }
    }

    var message: String {
        switch self {
        case .cleanup: "只清理当前产品的运行、测试、通信和分支记录，不删除员工或项目文件。"
        case .reset: "将重建本地默认公司、产品、员工和演示数据。操作前系统会创建安全检查点。"
        case .rollback: "将恢复员工、产品、任务、消息、日志、审批、产物、记忆、通信和分支计划。"
        }
    }

    var confirmTitle: String {
        switch self {
        case .cleanup: "确认清理运行/测试数据"
        case .reset: "确认恢复默认公司状态"
        case .rollback: "确认回滚到最近安全检查点"
        }
    }

    var systemImage: String {
        switch self {
        case .cleanup: "trash.slash.fill"
        case .reset: "arrow.counterclockwise.circle.fill"
        case .rollback: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .cleanup: CompanyTheme.red
        case .reset: CompanyTheme.red
        case .rollback: CompanyTheme.warning
        }
    }

    var executeIdentifier: OPCUIAutomationIdentifier {
        switch self {
        case .cleanup: .runDataCleanupConfirmButton
        case .reset: .defaultCompanyStateConfirmButton
        case .rollback: .safetyCheckpointRollbackConfirmButton
        }
    }

    /// 动作专属确认短语：三项各不相同，避免 cleanup/reset/rollback 共用同一个 "确认" 导致误触或粘贴穿透。
    var confirmationPhrase: String {
        switch self {
        case .cleanup: "清理运行数据"
        case .reset: "恢复默认公司"
        case .rollback: "回滚最近检查点"
        }
    }

    var phrasePromptPlaceholder: String {
        "输入「\(confirmationPhrase)」"
    }

    var phraseFieldHint: String {
        "输入「\(confirmationPhrase)」后才会启用执行按钮"
    }

    var executeHint: String {
        switch self {
        case .cleanup: "输入「清理运行数据」后才会清理当前产品运行与测试数据，不会删除员工或项目文件"
        case .reset: "输入「恢复默认公司」后才会把当前公司恢复到默认状态；操作不可撤销前请人工确认"
        case .rollback: "输入「回滚最近检查点」后才会把当前公司回滚到最近一个安全检查点"
        }
    }
}

private struct LocalMaintenanceDangerousConfirmationPanel: View {
    let action: LocalMaintenanceDangerousAction
    let confirm: () -> Void
    @State private var confirmationPhrase = ""

    private var panelIdentifier: String {
        "\(OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationPanel.rawValue)-\(action.rawValue)"
    }

    private var phraseFieldIdentifier: String {
        "\(OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationPhraseField.rawValue)-\(action.rawValue)"
    }

    private var cancelIdentifier: String {
        "\(OPCUIAutomationIdentifier.localMaintenanceDangerousConfirmationCancelButton.rawValue)-\(action.rawValue)"
    }

    private var executeEnabled: Bool {
        confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == action.confirmationPhrase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(action.title, systemImage: action.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(action.tint)
            Text(action.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.ink)
            TextField(action.phrasePromptPlaceholder, text: $confirmationPhrase)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium))
                .accessibilityIdentifier(phraseFieldIdentifier)
                .accessibilityLabel("\(action.buttonTitle)确认词")
                .accessibilityHint(action.phraseFieldHint)
            HStack(spacing: 8) {
                Button("取消") {
                    confirmationPhrase = ""
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(cancelIdentifier)
                .accessibilityLabel("取消危险操作确认")
                .accessibilityHint("清空当前危险操作确认词，不执行任何维护动作")

                Button(role: .destructive) {
                    guard executeEnabled else { return }
                    confirm()
                    confirmationPhrase = ""
                } label: {
                    Text(action.buttonTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(action.tint)
                .disabled(!executeEnabled)
                .accessibilityIdentifier(action.executeIdentifier.rawValue)
                .accessibilityLabel(action.buttonTitle)
                .accessibilityHint(action.executeHint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(action.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(action.tint.opacity(0.32), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(panelIdentifier)
        .accessibilityLabel(action.title)
    }
}

struct LocalMaintenanceCenter: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var confirmLegacyTaskMigration = false
    @State private var confirmAutoSummaryCleanup = false
    @State private var confirmHistoryArchiveMigration = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "本地稳定性维护")
                Text("用于反复测试和多产品开发时保持状态干净。只清理当前产品的运行/测试记录，不删除员工、不删除项目文件。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)

                dangerousActionsPanel

                Button {
                    store.runProductIsolationAudit()
                } label: {
                    Label("运行多产品隔离体检", systemImage: "square.stack.3d.down.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalIsolationAuditButton.rawValue)
                .accessibilityLabel("运行多产品隔离体检")
                .accessibilityHint("为当前产品运行多产品隔离体检，写入维护审计并刷新本地稳定性摘要")

                Button {
                    store.runCLIToolchainPreflightForSelectedProduct()
                } label: {
                    Label("运行命令行链路压测预检", systemImage: "terminal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.advancedMaintenanceLocalCLIPreflightButton.rawValue)
                .accessibilityLabel("运行命令行链路压测预检")
                .accessibilityHint("为当前产品运行命令行链路干跑预检，不调用真实模型任务")

                Button {
                    store.runCLIRuntimeIsolationAudit()
                } label: {
                    Label("运行命令行与工作区隔离体检", systemImage: "rectangle.connected.to.line.below")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.green)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.cliRuntimeIsolationAuditButton.rawValue)
                .accessibilityLabel("运行命令行与工作区隔离体检")
                .accessibilityHint("为当前产品运行命令行与工作区隔离体检，写入维护审计并刷新预览，不会修改运行数据或员工")

                Button {
                    store.startTerminalWorkspaceForSelectedProduct()
                } label: {
                    Label("启动真实终端工作区", systemImage: "rectangle.3.group.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.warning)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalWorkspaceStartButton.rawValue)
                .accessibilityLabel("启动真实终端工作区")
                .accessibilityHint("为当前产品启动真实终端工作区，把员工任务路由到 macOS 终端真实席位")

                Button {
                    store.refreshTerminalWorkspaceLogsForSelectedProduct()
                } label: {
                    Label("刷新真实终端日志", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalWorkspaceRefreshLogsButton.rawValue)
                .accessibilityLabel("刷新真实终端日志")
                .accessibilityHint("刷新当前产品真实终端工作区的可见日志，不影响真实任务执行")

                Button {
                    store.runTerminalWorkspaceHealthAuditForSelectedProduct()
                } label: {
                    Label("运行持久终端可用性巡检", systemImage: "terminal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.terminalWorkspaceHealthAuditButton.rawValue)
                .accessibilityLabel("运行持久终端可用性巡检")
                .accessibilityHint("巡检当前产品持久终端工作区的可用性，写入维护审计并就地刷新可用性预览卡片")

                TerminalWorkspaceHealthPreview()

                ManualREPLTurnPanel()

                TerminalAutoInteractionLoopPanel()

                CLIRecoveryAdvicePanel()

                Button {
                    store.runRuntimeSessionHealthAuditForSelectedProduct()
                } label: {
                    Label("运行会话健康巡检", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.runtimeSessionHealthAuditButton.rawValue)
                .accessibilityLabel("运行会话健康巡检")
                .accessibilityHint("巡检当前产品员工会话健康度，写入维护审计并就地刷新会话健康预览卡片")

                RuntimeSessionHealthAuditPreview()

                Button {
                    store.runEmployeeHandoffAuditForSelectedProduct()
                } label: {
                    Label("运行员工交接巡检", systemImage: "person.2.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.employeeHandoffAuditButton.rawValue)
                .accessibilityLabel("运行员工交接巡检")
                .accessibilityHint("巡检当前产品员工交接证据完整度，写入维护审计并刷新员工交接巡检预览")

                EmployeeHandoffAuditPreview()

                Button {
                    store.runJobArchiveStaleAuditForSelectedProduct()
                } label: {
                    Label("运行命令行作业幽灵巡检", systemImage: "doc.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.jobArchiveStaleAuditButton.rawValue)
                .accessibilityLabel("运行命令行作业幽灵巡检")
                .accessibilityHint("巡检当前产品命令行作业档案的幽灵或陈旧作业，只写维护审计，不删除作业产物")

                JobArchiveStaleAuditPreview()

                Button {
                    store.runEvidenceClassificationAuditForSelectedProduct()
                } label: {
                    Label("运行证据分类巡检", systemImage: "checklist.checked")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.evidenceClassificationAuditButton.rawValue)
                .accessibilityHint("巡检当前产品的验证记录与产物档案，发现既不属于交付也不属于维护的未分类证据；只写维护审计、不删除数据")

                EvidenceClassificationAuditPreview()

                Button {
                    store.runMaintenanceDataPressureAuditForSelectedProduct()
                } label: {
                    Label("运行维护数据增长巡检", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceDataPressureAuditButton.rawValue)
                .accessibilityHint("巡检当前产品的维护类记录与产物增长压力；只写维护审计、不删除数据，也不裁剪主快照")

                MaintenanceDataPressurePreview()

                Button {
                    store.runHistoryIndexAuditForSelectedProduct()
                } label: {
                    Label("运行历史索引巡检", systemImage: "cylinder.split.1x2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.historyIndexAuditButton.rawValue)
                .accessibilityLabel("运行历史索引巡检")
                .accessibilityHint("巡检当前产品历史索引完整度与一致性，写入维护审计并刷新历史索引预览")

                HistoryIndexAuditPreview()

                Button {
                    if confirmHistoryArchiveMigration {
                        store.runHistoryArchiveMigrationForSelectedProduct()
                        confirmHistoryArchiveMigration = false
                    } else {
                        confirmHistoryArchiveMigration = true
                    }
                } label: {
                    Label(
                        confirmHistoryArchiveMigration ? "再次点击确认运行历史归档迁移" : "运行历史归档迁移",
                        systemImage: "archivebox.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.historyArchiveMigrationButton.rawValue)
                .accessibilityLabel("运行历史归档迁移")
                .accessibilityHint("把当前产品旧历史记录按归档规则迁入历史归档，写入维护审计并刷新归档迁移预览；首次点击进入确认态，再次点击才会执行")

                HistoryArchiveMigrationPreview()

                Button {
                    let preview = store.previewSelectedProductAutoCapturedSummaryDuplicates()
                    if confirmAutoSummaryCleanup && preview.hasDuplicates {
                        store.cleanupSelectedProductAutoCapturedSummaryDuplicates()
                        confirmAutoSummaryCleanup = false
                    } else {
                        confirmAutoSummaryCleanup = true
                    }
                } label: {
                    Label(
                        confirmAutoSummaryCleanup ? "再次点击确认清理自动摘要重复" : "清理自动状态摘要重复",
                        systemImage: "doc.badge.minus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.warning)
                .disabled(!store.previewSelectedProductAutoCapturedSummaryDuplicates().hasDuplicates)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.autoCapturedSummaryDuplicateCleanupButton.rawValue)
                .accessibilityHint("清理当前产品中重复的自动状态摘要；按摘要前 200 字分组，每组保留最新一条，移除旧条目；只有确实存在重复时才可点击")

                Button {
                    if confirmLegacyTaskMigration {
                        store.runLegacyTaskProductMigrationForSelectedProduct()
                        confirmLegacyTaskMigration = false
                    } else {
                        confirmLegacyTaskMigration = true
                    }
                } label: {
                    Label(confirmLegacyTaskMigration ? "再次点击确认迁入当前产品" : "迁移未归属旧任务到当前产品", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.blue)
                .disabled(store.legacyTaskWithoutProductIDCount == 0)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.legacyTaskProductMigrationButton.rawValue)
                .accessibilityHint("仅当当前产品存在未归属旧任务时可用；首次点击进入确认态，再次点击才会迁入当前产品")

                Button {
                    store.recoverStaleRuntimeSessionsForSelectedProduct()
                } label: {
                    Label("恢复异常占用员工会话", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CompanyTheme.red)
                .accessibilityIdentifier(OPCUIAutomationIdentifier.staleRuntimeSessionRecoveryButton.rawValue)
                .accessibilityLabel("恢复异常占用员工会话")
                .accessibilityHint("恢复当前产品被异常占用的员工运行会话，释放席位但不会修改员工配置或项目文件")

            }
            .commandPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "清理预览")
                Text(store.selectedProductRunDataSummary())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.runDataCleanupPreview.rawValue)
                    .accessibilityLabel("清理预览")
                    .accessibilityValue(store.selectedProductRunDataSummary())

                SectionHeader(title: "命令行链路预检")
                Text(store.cliToolchainPreflightText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.cliToolchainPreflightPreview.rawValue)
                    .accessibilityLabel("命令行链路预检")
                    .accessibilityValue(store.cliToolchainPreflightText())

                SectionHeader(title: "默认状态预览")
                Text(store.defaultCompanyStatePreviewText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.defaultCompanyStatePreview.rawValue)
                    .accessibilityLabel("默认状态预览")
                    .accessibilityValue(store.defaultCompanyStatePreviewText())

                SectionHeader(title: "隔离体检预览")
                Text(store.productIsolationAuditText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.productIsolationAuditPreview.rawValue)
                    .accessibilityLabel("隔离体检预览")
                    .accessibilityValue(store.productIsolationAuditText())

                SectionHeader(title: "命令行与工作区隔离预览")
                MaintenancePreviewText(
                    label: "命令行与工作区隔离预览",
                    summary: store.cliRuntimeIsolationAuditText(),
                    detail: store.cliRuntimeIsolationAuditDetailText(),
                    summaryIdentifier: .cliRuntimeIsolationPreview,
                    detailToggleIdentifier: .cliRuntimeIsolationDetailToggle,
                    detailIdentifier: .cliRuntimeIsolationDetailPreview
                )

                SectionHeader(title: "本地文件索引根白名单")
                Text(store.linkedLocalFileRootAllowlistText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.linkedLocalFileRootAllowlistPreview.rawValue)
                    .accessibilityLabel("本地文件索引根白名单")
                    .accessibilityValue(store.linkedLocalFileRootAllowlistText())

                SectionHeader(title: "自动摘要去重预览")
                Text(store.autoCapturedSummaryDuplicatePreviewText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.autoCapturedSummaryDuplicatePreview.rawValue)
                    .accessibilityLabel("自动摘要去重预览")
                    .accessibilityValue(store.autoCapturedSummaryDuplicatePreviewText())

                SectionHeader(title: "旧任务归属迁移预览")
                Text(store.legacyTaskProductMigrationText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.legacyTaskProductMigrationPreview.rawValue)
                    .accessibilityLabel("旧任务归属迁移预览")
                    .accessibilityValue(store.legacyTaskProductMigrationText())

                SectionHeader(title: "真实终端工作区预览")
                MaintenancePreviewText(
                    label: "真实终端工作区预览",
                    summary: store.terminalWorkspacePlanText(),
                    detail: store.terminalWorkspacePlanDetailText(),
                    summaryIdentifier: .terminalWorkspacePlanPreview,
                    detailToggleIdentifier: .terminalWorkspacePlanDetailToggle,
                    detailIdentifier: .terminalWorkspacePlanDetailPreview
                )

                SectionHeader(title: "安全检查点")
                Text(store.safetyCheckpointListText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.safetyCheckpointPreview.rawValue)
                    .accessibilityLabel("安全检查点")
                    .accessibilityValue(store.safetyCheckpointListText())

                SectionHeader(title: "本机诊断与日志策略")
                Text(store.localDiagnosticsPolicyText())
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CompanyTheme.terminalInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(OPCUIAutomationIdentifier.localDiagnosticsPolicyPreview.rawValue)
                    .accessibilityLabel("本机诊断与日志策略")
                    .accessibilityValue(store.localDiagnosticsPolicyText())

                SectionHeader(title: "运行证据归档（技术负责人专用）")
                Text("以下两个区块仅技术负责人/维护视图可见：聚合巡检、恢复、就绪审计等运维证据；老板总控台、产品详情交付区与交付验收中心都不展示。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)

                SectionHeader(title: "技术维护审计中心")
                Text("聚合运行巡检、恢复、就绪审计等记录，按时间倒序显示最近重点，后续记录会继续浮现。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                Group {
                    if store.selectedProductMaintenanceVerifications.isEmpty {
                        EmptyCommandLine(text: "暂无维护审计记录。运行任一巡检/恢复后会出现。")
                    } else {
                        ForEach(store.localMaintenanceVisibleVerifications) { verification in
                            VerificationRecordCard(record: verification)
                                .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceAuditRow.rawValue)
                                .accessibilityLabel("\(verification.title) · \(verification.status.title)")
                        }
                        if let overflow = store.localMaintenanceVerificationsOverflow() {
                            OPCListOverflowFooter(summary: overflow.summary)
                        }
                    }
                }
                .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceAuditCenter.rawValue)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("技术维护审计中心")

                SectionHeader(title: "维护产物档案")
                Text("聚合安全检查点、命令行作业档案、闭环审计报告、本地文件索引等产物，按时间倒序显示最近重点，后续产物会继续浮现。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                Group {
                    if store.selectedProductMaintenanceArtifacts.isEmpty {
                        EmptyCommandLine(text: "暂无维护产物档案。生成安全检查点 / 运行真实命令行任务 / 生成闭环审计报告后会出现。")
                    } else {
                        ForEach(store.localMaintenanceVisibleArtifacts) { artifact in
                            ArtifactRecordCard(artifact: artifact)
                                .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceArtifactRow.rawValue)
                                .accessibilityLabel(artifact.title)
                        }
                        if let overflow = store.localMaintenanceArtifactsOverflow() {
                            OPCListOverflowFooter(summary: overflow.summary)
                        }
                    }
                }
                .accessibilityIdentifier(OPCUIAutomationIdentifier.maintenanceArtifactCenter.rawValue)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("维护产物档案")
            }
            .commandPanel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OPCUIAutomationIdentifier.localMaintenanceCenterRoot.rawValue)
        .accessibilityLabel("本地稳定性维护中心")
    }

    @ViewBuilder
    private var dangerousActionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(LocalMaintenanceDangerousAction.allCases) { action in
                LocalMaintenanceDangerousConfirmationPanel(action: action) {
                    runDangerousConfirmation(action)
                }
            }
        }
    }

    private func runDangerousConfirmation(_ action: LocalMaintenanceDangerousAction) {
        switch action {
        case .cleanup:
            store.clearSelectedProductRunData()
        case .reset:
            store.resetToDefaultCompanyState()
        case .rollback:
            store.restoreLatestSafetyCheckpoint()
        }
    }
}

private struct MaintenancePreviewText: View {
    let label: String
    let summary: String
    let detail: String
    let summaryIdentifier: OPCUIAutomationIdentifier
    let detailToggleIdentifier: OPCUIAutomationIdentifier
    let detailIdentifier: OPCUIAutomationIdentifier

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            reportText(summary)
                .accessibilityIdentifier(summaryIdentifier.rawValue)
                .accessibilityLabel(label)
                .accessibilityValue(summary)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    reportText(detail)
                }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(label)完整明细")
                    .accessibilityValue(detail)
                    .accessibilityIdentifier(detailIdentifier.rawValue)
            } label: {
                Label("查看完整运维明细", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(CompanyTheme.muted)
                    .accessibilityIdentifier(detailToggleIdentifier.rawValue)
                    .accessibilityLabel("\(label)完整明细开关")
                    .accessibilityHint("展开或收起完整运维明细")
            }
        }
    }

    @ViewBuilder
    private func reportText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
            .foregroundStyle(CompanyTheme.terminalInk)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MultiAgentClosureTraceSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("多员工闭环详情")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(CompanyTheme.ink)
                    Text("\(store.selectedProduct?.name ?? "当前产品")：按每次技术负责人目标追踪任务、消息、审批、门禁、产物和验收证据。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }

            if store.selectedProductClosureTraces.isEmpty {
                ContentUnavailableView("暂无闭环记录", systemImage: "point.3.connected.trianglepath.dotted", description: Text("在终端大厅运行闭环演练或启动技术负责人协作目标后，这里会显示可审核链路。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.selectedProductClosureTraces) { trace in
                            MultiAgentClosureTraceCard(trace: trace)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 620)
        .background(CompanyTheme.panel)
    }
}

struct MultiAgentClosureTraceCard: View {
    @EnvironmentObject private var store: CompanyStore
    let trace: MultiAgentClosureTrace
    private var hasAuditReport: Bool {
        store.closureTraceAuditReportExists(for: trace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(trace.goal)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(CompanyTheme.ink)
                        StatusPill(text: trace.status.title, color: statusColor(trace.status))
                    }
                    Text("更新：\(trace.updatedAt.opcDateTimeText)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(trace.completionScore)%")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(statusColor(trace.status))
                    Button {
                        _ = store.generateClosureTraceAuditReport(for: trace)
                    } label: {
                        Label(hasAuditReport ? "审计报告已生成" : "生成审计报告", systemImage: hasAuditReport ? "doc.text.magnifyingglass" : "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(hasAuditReport)
                }
            }

            HStack(spacing: 8) {
                traceMetric("任务", trace.taskIDs.count)
                traceMetric("消息", trace.messageIDs.count)
                traceMetric("审批", trace.approvalIDs.count)
                traceMetric("门禁", trace.reviewGateIDs.count)
                traceMetric("产物", trace.artifactIDs.count)
                traceMetric("验收", trace.verificationIDs.count)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(trace.steps) { step in
                    MultiAgentClosureTraceStepRow(step: step)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TraceDetailSection(title: "任务图边", systemImage: "point.3.connected.trianglepath.dotted", count: store.closureTraceTaskGraph(trace).edges.count) {
                    ForEach(store.closureTraceTaskGraph(trace).edges) { edge in
                        TraceRecordRow(
                            title: "\(taskTitle(edge.fromTaskID)) → \(taskTitle(edge.toTaskID))",
                            subtitle: "\(edge.relation) · \(edge.status.title)",
                            detail: edge.evidence,
                            color: statusColor(edge.status)
                        )
                    }
                }

                TraceDetailSection(title: "任务记录", systemImage: "checklist", count: trace.taskIDs.count) {
                    ForEach(store.closureTraceTasks(trace)) { task in
                        TraceRecordRow(
                            title: task.title,
                            subtitle: "负责人：\(agentName(task.ownerID)) · 状态：\(task.status.title)",
                            detail: task.successCriteria,
                            color: taskColor(task.status)
                        )
                    }
                }

                TraceDetailSection(title: "消息记录", systemImage: "bubble.left.and.bubble.right.fill", count: trace.messageIDs.count) {
                    ForEach(store.closureTraceMessages(trace)) { message in
                        TraceRecordRow(
                            title: message.subject,
                            subtitle: "\(AgentMessageDisplay.title(for: message.kind)) · \(agentName(message.fromAgentID)) → \(agentName(message.toAgentID)) · \(AgentMessageDisplay.statusTitle(for: message.status))",
                            detail: message.body,
                            color: AgentMessageDisplay.color(for: message.kind)
                        )
                    }
                }

                TraceDetailSection(title: "审批记录", systemImage: "signature", count: trace.approvalIDs.count) {
                    ForEach(store.closureTraceApprovals(trace)) { approval in
                        TraceRecordRow(
                            title: approval.title,
                            subtitle: "申请人：\(agentName(approval.requesterID)) · 状态：\(approval.status.title)",
                            detail: approval.reason,
                            color: approval.status == .approved ? CompanyTheme.green : approval.status == .rejected ? CompanyTheme.red : CompanyTheme.warning
                        )
                    }
                }

                TraceDetailSection(title: "验收门禁", systemImage: "shield.lefthalf.filled", count: trace.reviewGateIDs.count) {
                    ForEach(store.closureTraceReviewGates(trace)) { gate in
                        TraceRecordRow(
                            title: taskTitle(gate.taskID),
                            subtitle: "状态：\(gate.status.title) · 更新：\(gate.updatedAt.opcDateTimeText)",
                            detail: gate.summary,
                            color: reviewGateColor(gate.status)
                        )
                    }
                }

                TraceDetailSection(title: "产物记录", systemImage: "doc.text.magnifyingglass", count: trace.artifactIDs.count) {
                    ForEach(store.closureTraceArtifacts(trace)) { artifact in
                        TraceRecordRow(
                            title: artifact.title,
                            subtitle: "\(artifact.kind.title) · \(artifact.path)",
                            detail: artifact.summary,
                            color: CompanyTheme.blue
                        )
                    }
                }

                TraceDetailSection(title: "验收记录", systemImage: "checkmark.seal.fill", count: trace.verificationIDs.count) {
                    ForEach(store.closureTraceVerifications(trace)) { verification in
                        TraceRecordRow(
                            title: verification.title,
                            subtitle: "状态：\(verification.status.title) · \(verification.createdAt.opcDateTimeText)",
                            detail: verification.detail,
                            color: verificationColor(verification.status)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(CompanyTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor(trace.status).opacity(0.22), lineWidth: 1)
        )
    }

    private func traceMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(CompanyTheme.ink)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CompanyTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 7))
    }

    private func statusColor(_ status: ArchitectureCheckStatus) -> Color {
        switch status {
        case .passed: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .failed: CompanyTheme.red
        }
    }

    private func agentName(_ id: UUID?) -> String {
        guard let id else { return "未分配" }
        return store.agents.first { $0.id == id }?.displayName ?? "未知员工"
    }

    private func taskTitle(_ id: UUID) -> String {
        store.tasks.first { $0.id == id }?.title ?? "未知任务"
    }

    private func taskColor(_ status: TaskStatus) -> Color {
        switch status {
        case .done: CompanyTheme.green
        case .blocked, .failed: CompanyTheme.red
        case .needsApproval, .needsReview: CompanyTheme.warning
        case .running: CompanyTheme.accent
        default: CompanyTheme.blue
        }
    }

    private func reviewGateColor(_ status: ReviewGateStatus) -> Color {
        switch status {
        case .reviewRequested, .verificationWarning: CompanyTheme.warning
        case .verificationPassed, .accepted: CompanyTheme.green
        case .verificationFailed, .rejected: CompanyTheme.red
        }
    }

    private func verificationColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .passed: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .failed: CompanyTheme.red
        }
    }
}

struct MultiAgentClosureTraceStepRow: View {
    let step: MultiAgentClosureTraceStep

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(step.title)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    StatusPill(text: step.status.title, color: color)
                }
                Text(step.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch step.status {
        case .passed: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .failed: CompanyTheme.red
        }
    }

    private var icon: String {
        switch step.status {
        case .passed: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

struct TraceDetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int
    private let content: () -> Content
    @State private var isExpanded = false

    init(title: String, systemImage: String, count: Int, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                if count == 0 {
                    EmptyCommandLine(text: "暂无记录。")
                } else {
                    content()
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CompanyTheme.accent)
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                StatusPill(text: "\(count)", color: count == 0 ? CompanyTheme.muted : CompanyTheme.accent)
            }
        }
        .padding(10)
        .background(CompanyTheme.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TraceRecordRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                        .lineLimit(3)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.34), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct EngineMetricRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CompanyTheme.ink)
            Spacer()
            StatusPill(text: value, color: color)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkQueueCard: View {
    @EnvironmentObject private var store: CompanyStore
    let item: AgentWorkItem

    private var taskTitle: String {
        store.tasks.first { $0.id == item.taskID }?.title ?? "未知任务"
    }

    private var agentName: String {
        store.agents.first { $0.id == item.agentID }?.displayName ?? "未知员工"
    }

    private var reworkReason: String? {
        guard item.status != .completed else { return nil }
        guard let range = item.promptPreview.range(of: "打回原因：") else { return nil }
        let tail = item.promptPreview[range.upperBound...]
        let reason = tail
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return reason?.isEmpty == false ? reason : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(taskTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer()
                StatusPill(text: item.status.title, color: queueColor)
            }
            if let reworkReason {
                HStack(alignment: .top, spacing: 6) {
                    StatusPill(text: "返工", color: CompanyTheme.warning)
                    Text("原因：\(reworkReason)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanyTheme.warning)
                        .lineLimit(2)
                }
            }
            Text("员工：\(agentName)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.blue)
            Text(item.promptPreview)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
            HStack {
                Button("运行") {
                    store.runTaskOwner(item.taskID)
                    store.mainWorkspace = .terminalHall
                }
                .buttonStyle(.bordered)
                Button("完成") {
                    store.completeWorkItem(for: item.taskID, agentID: item.agentID)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var queueColor: Color {
        switch item.status {
        case .completed: CompanyTheme.green
        case .failed: CompanyTheme.red
        case .running: CompanyTheme.accent
        case .waitingApproval: CompanyTheme.warning
        default: CompanyTheme.muted
        }
    }
}

struct ArtifactRecordCard: View {
    let artifact: ArtifactRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(artifact.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusPill(text: artifact.kind.title, color: CompanyTheme.blue)
            }
            Text(artifact.path)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(artifact.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BossReportCenter: View {
    @EnvironmentObject private var store: CompanyStore

    private var bossMessages: [ChatMessage] {
        // BossReportCenter UI 文案明示「报告会汇总当前产品...」，必须按当前产品作用域。
        // boss agent 是跨产品角色，messages(for: bossID) 是跨产品累加的；走 store 端
        // selectedProductBossReportMessages 按当前产品名 prefix 匹配过滤，避免 Product A
        // 的老板报告漏到 Product B 的 BossReportCenter（角色继承期轮 10 收口）。
        // 之前还有一个失效的「产品交接快照」内容过滤分支 — createHandoffSnapshot 只写
        // ctoID 流，boss 流从来没这种消息（dead branch，已随轮 10 移除）。
        store.selectedProductBossReportMessages
    }

    private var reportEvents: [CompanyEvent] {
        // BossReportCenter 是老板专属面板，UI 文案明示「报告会汇总当前产品...」，
        // 必须按产品作用域 + 老板视图维护前缀过滤（与 BossControlPanel 同源）。
        // 在 selectedProductBossEvents 基础上叠加报告/快照/产物 kind 的内容选择。
        store.selectedProductBossReportEvents
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "生成老板报告")
                Text("报告会汇总当前产品、任务、风险、员工状态和下一步建议，并同步给老板与技术负责人。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanyTheme.muted)
                Button {
                    store.generateBossReport()
                    store.selectAgent(store.bossID)
                } label: {
                    Label("生成老板报告", systemImage: "doc.richtext.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)

                Button {
                    store.createHandoffSnapshot()
                    store.selectAgent(store.ctoID)
                } label: {
                    Label("生成项目交接摘要", systemImage: "archivebox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    store.generateHealthAudit()
                    store.selectAgent(store.bossID)
                } label: {
                    Label("生成健康体检", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                SectionHeader(title: "报告事件")
                if reportEvents.isEmpty {
                    EmptyCommandLine(text: "还没有报告或产物事件。")
                } else {
                    ForEach(store.bossReportCenterReportEvents) { event in
                        EventSignalRow(event: event)
                    }
                    if let overflow = store.bossReportCenterReportEventsOverflow() {
                        OPCListOverflowFooter(summary: overflow.summary)
                    }
                }
            }
            .commandPanel()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "最近老板报告")
                if bossMessages.isEmpty {
                    EmptyCommandLine(text: "点击左侧生成老板报告后，这里会显示报告摘要。")
                } else {
                    ForEach(store.bossReportCenterBossMessages) { message in
                        ScrollView {
                            Text(message.text)
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(CompanyTheme.terminalInk)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 220)
                        .background(CompanyTheme.terminalBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let overflow = store.bossReportCenterBossMessagesOverflow() {
                        OPCListOverflowFooter(summary: overflow.summary)
                    }
                }
            }
            .commandPanel()
        }
    }
}

struct VerificationRecordCard: View {
    let record: VerificationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(record.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusPill(text: record.status.title, color: color)
            }
            Text(record.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch record.status {
        case .passed: CompanyTheme.green
        case .warning: CompanyTheme.warning
        case .failed: CompanyTheme.red
        }
    }
}

struct AcceptanceTaskCard: View {
    @EnvironmentObject private var store: CompanyStore
    let task: CompanyTask

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(task.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusPill(text: task.status.title, color: statusColor(task.status))
            }
            Text(task.successCriteria)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(2)
            HStack {
                Button("送审") {
                    store.updateTaskStatus(task.id, status: .needsReview)
                    store.requestCTOReview(for: task.id)
                }
                .buttonStyle(.bordered)
                Button("需要老板批准") {
                    store.updateTaskStatus(task.id, status: .needsApproval)
                }
                .buttonStyle(.bordered)
                Button("验收通过") {
                    store.acceptTask(task.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.green)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MemoryNoteCard: View {
    let memory: ProductMemoryNote

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(memory.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                Spacer()
                StatusPill(text: memory.kind.title, color: CompanyTheme.warning)
            }
            Text(memory.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RuleLine: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CompanyTheme.ink)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CommunicationChannelCard: View {
    @EnvironmentObject private var store: CompanyStore
    let channel: CommunicationChannelConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(channel.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(CompanyTheme.ink)
                    Text(channel.kind.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CompanyTheme.blue)
                }
                Spacer()
                StatusPill(text: channel.isEnabled ? "启用" : "未启用", color: channel.isEnabled ? CompanyTheme.green : CompanyTheme.muted)
            }

            Text(channel.kind.capabilitySummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(3)

            HStack(spacing: 10) {
                Toggle("启用", isOn: Binding(
                    get: { channel.isEnabled },
                    set: { store.updateCommunicationChannel(channel.id, isEnabled: $0) }
                ))
                Toggle("汇报", isOn: Binding(
                    get: { channel.reportsEnabled },
                    set: { store.updateCommunicationChannel(channel.id, reportsEnabled: $0) }
                ))
                Toggle("指令", isOn: Binding(
                    get: { channel.commandsEnabled },
                    set: { store.updateCommunicationChannel(channel.id, commandsEnabled: $0) }
                ))
                .disabled(!channel.kind.supportsInboundCommand)
            }
            .font(.system(size: 11, weight: .bold))

            TextField("消息回调或机器人接口地址", text: Binding(
                get: { channel.endpoint },
                set: { store.updateCommunicationChannel(channel.id, endpoint: $0) }
            ))
            .commandTextField()

            if channel.kind == .telegramBot {
                TextField("聊天标识", text: Binding(
                    get: { channel.chatID },
                    set: { store.updateCommunicationChannel(channel.id, chatID: $0) }
                ))
                .commandTextField()
            }

            if let preview = CommunicationGatewayRequestBuilder.preview(for: channel, text: "OPC 测试消息") {
                Text("\(preview.method) \(preview.endpoint)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if channel.isEnabled {
                Text("缺少必要配置，暂不能外发。")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CompanyTheme.warning)
            }
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CommunicationLogCard: View {
    @EnvironmentObject private var store: CompanyStore
    let entry: CommunicationLogEntry

    private var agentName: String {
        guard let agentID = entry.agentID else { return "OPC 网关" }
        return store.agents.first { $0.id == agentID }?.displayName ?? "未知员工"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(entry.title)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Spacer()
                StatusPill(text: entry.status.title, color: statusColor)
            }
            Text("\(entry.direction.title) · \(agentName) · \(entry.createdAt.opcShortTimeText)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CompanyTheme.blue)
            Text(entry.body)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CompanyTheme.muted)
                .lineLimit(5)
        }
        .padding(10)
        .background(CompanyTheme.surfaceRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch entry.status {
        case .sent, .received: CompanyTheme.green
        case .failed: CompanyTheme.red
        case .queued: CompanyTheme.warning
        case .planned: CompanyTheme.muted
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
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

extension View {
    func commandPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .background {
                CommandPanelBackground(accent: CompanyTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CompanyTheme.border.opacity(0.55), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
    }

    func commandTextField(lineLimit: ClosedRange<Int> = 1...1) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CompanyTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .lineLimit(lineLimit)
            .background(CompanyTheme.inputSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CompanyTheme.inputBorder.opacity(0.55), lineWidth: 0.7)
            )
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
