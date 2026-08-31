# OPC Company Runbook

Last updated: 2026-05-07

Current baseline: OPC Company is ready for single-user local formal use on this Mac. Latest verified bundle is `dist/OPCCompany.app` with bundle version `20260507033423`; full test baseline is `swift test --no-parallel` 555/555.

## Build

```bash
cd ~/Desktop/OPCCompany
swift build
```

## Run

```bash
cd ~/Desktop/OPCCompany
swift run OPCCompany
```

This launches the native macOS SwiftUI application from Swift Package Manager.

## Build Local App Bundle

```bash
cd ~/Desktop/OPCCompany
scripts/build_app_bundle.sh
open dist/OPCCompany.app
```

This creates a local ad-hoc signed app bundle suitable for personal use on this Mac. Developer ID signing, notarization, DMG packaging, and an updater are only needed if the app is later distributed to other Macs or other users.

Verify the current local bundle:

```bash
codesign --verify --deep --strict dist/OPCCompany.app
plutil -p dist/OPCCompany.app/Contents/Info.plist | rg "CFBundleVersion|CFBundleShortVersionString"
```

## Safe Project Cleanup

Safe cleanup before formal local use:

```bash
cd ~/Desktop/OPCCompany
rm -rf .build
```

Keep these unless the user explicitly requests a deeper reset:

- `Tests/OPCCompanyTests/**`: regression suite, not disposable test data.
- `dist/OPCCompany.app`: latest usable local app bundle.
- `OPC_COMPANY.md`, `CLAUDE.md`, `AGENTS.md`, and `docs/**`: product memory and operating rules.
- `.claude/`: project-level goal/settings state.
- `.ccb/`: collaboration logs and handoff trace; can be large, but keep while audit traceability matters.
- `~/Library/Application Support/OPCCompany/**`: real local product state, history index, checkpoints, and employee workspaces.

## 单人本地正式使用边界

本项目当前正式使用目标是「同一台 Mac 上单人长期本地使用」，不是 Mac App Store 上架或对外分发。

- **不作为正式使用阻塞**：通信网关移动端联动、公网/局域网入站服务、Developer ID 签名、notarization、DMG 分发包、Sparkle 自动更新、对外崩溃上报服务。
- **正式使用前保留**：本地 ad-hoc signed app bundle 构建脚本、全量 `swift test --no-parallel`、MacBook 主屏 Computer Use 验证、可恢复的本地状态备份/检查点。
- **正式使用前必须稳定**：默认可见界面不暴露后台路径/命令参数/原始模型 transcript；Codex / Claude Code / Gemini 订阅制命令行链路可运行并有清晰失败提示；主状态不会被测试污染；命令行作业档案和维护审计可用于追查问题。
- **后续按实际使用再评估**：如果需要在多台 Mac 同步、给他人使用或远程控制，再重新评估 Developer ID 签名、notarization、自动更新、外部崩溃报告、通信网关移动端联动和外部入站服务。

## 本机诊断与日志策略

当前不接入 Sentry、Crashlytics 或其他外部崩溃/日志上报。排查材料只保留在本机：

- 主状态快照：`~/Library/Application Support/OPCCompany/company-state.json`
- 历史索引：`~/Library/Application Support/OPCCompany/company-history.sqlite3`
- 安全检查点：`~/Library/Application Support/OPCCompany/checkpoints/`
- 命令行作业档案：当前产品根目录下 `.opc/jobs/`
- macOS 崩溃报告：`~/Library/Logs/DiagnosticReports/OPCCompany_*.crash`

技术负责人维护区的「本机诊断与日志策略」会显示这些位置。老板默认界面不展示诊断路径或日志实现细节。

**命令行作业尾部输出捕获契约**：`AgentProcessRunner.runStreaming` 在 `process.waitUntilExit()` 返回后必须先把 stdout / stderr 的 `readabilityHandler` 置 `nil`，再用 `readDataToEndOfFile()` 同步把残留尾部数据补到 `ProcessOutputBuffer`。子进程 printf 完立即退出的场景里，readabilityHandler 可能还没分发最后一段数据；缺了这次手动 drain，作业档案里就会出现「子进程已退出但末尾几行结果丢失」「[命令退出码] 之前的最终回执缺失」一类排查噩梦。守门测试 `runStreamingCapturesTailOutputAfterExit` 防止此次回归。

## CCB Agent Health Checks

When `ccb ps` shows an agent as `healthy`, `restored`, or `busy`, do not assume the agent is actually working. First inspect the real terminal pane.

For the current OPC project:

```bash
cd ~/Desktop/OPCCompany
ccb ps
tmux -S .ccb/ccbd/tmux.sock capture-pane -p -t %4 -S -120
```

Common cases:

- `busy` + normal model output: the agent is executing.
- `busy` + `Not logged in · Run /login`: the queue is blocked by Claude Code authentication, not by code execution.
- `healthy/restored` + empty prompt: the runtime exists but may be idle.
- `queued` jobs behind a stuck job: inspect the first job with `ccb pend <job_id> 1`.

Resolution order:

1. Confirm the agent workspace path belongs to this project.
2. Capture the provider terminal pane.
3. Fix login/auth or waiting prompt before sending more work.
4. Only after the provider is actually ready, send the engineering task.

## Product Status

Implemented:

- Native SwiftUI app shell.
- SpriteKit 2D office floor.
- Boss office, CTO office, employee hall.
- 老板、技术负责人、Gemini 界面设计师、Claude Code 工程师和 Codex 审查员角色。
- Desks, chairs implied by desk modules, computers, nameplates, status indicators.
- Clickable characters.
- Dedicated boss command center panel with company status, CTO quick commands, running employee overview, recent tasks, and recent events.
- Dialogue panel for each agent.
- Direct employee conversations summarized to CTO.
- Task board.
- Event log.
- Agent profile panel.
- Add employee sheet with role, backend, appearance, and permission settings.
- CLI command preview for Codex, Claude, Gemini, API, and custom backends.
- Terminal panel with a real process runner entry for selected CLI-backed employees.
- Terminal hall workspace with per-employee terminal cards, streaming stdout/stderr, per-agent run state, log clearing, selection, and run-all execution.
- Local JSON persistence in `~/Library/Application Support/OPCCompany/company-state.json`.
- Product spec, role rules, GitHub research, and orchestration design docs.
- Multi-product workspace design for running several products under one OPC company.

Next product-hardening work:

- Tune technical maintenance thresholds after real local usage: main snapshot size, `.opc/jobs/` archive count/size, and history archive volume.
- Continue SQLite history archive migration only when local state size or query latency crosses the documented maintenance threshold; JSON snapshot remains the authority.
- Add git worktree manager.
- Replace vector placeholder characters with Rive/Spine asset packs.
- If the app is later used on other Macs or by other people, re-evaluate Developer ID signing, notarization, DMG packaging, Sparkle updates, and hosted crash reporting.

## 持久化失败可见性

`CompanyPersistence.save(_:)` 返回 `Result<Void, Error>`：

- `.success(())`：snapshot 已落盘到 `~/Library/Application Support/OPCCompany/company-state.json`。
- `.failure(error)`：createDirectory / encode / write 任一步失败。`CompanyStore.saveSnapshot()` 会在 `events` 头部插入一条 `.risk`「持久化失败」事件，老板侧事件流可见；连续同类失败做相邻去重，避免事件流被 disk-full / sandbox 不可写场景刷屏。

注意事项：

- 失败事件**只在内存**（保存到 events 数组），**不会被持久化** —— 因为持久化通道刚刚失败再 save 也会失败。重启后这条提示会消失，但故障原因（如 disk full）若仍存在，下次写入仍会重新触发。
- `recordPersistenceFailure` 不调用 `saveSnapshot()`，避免递归。运维若发现老板侧反复出现「持久化失败」事件应排查 `~/Library/Application Support/OPCCompany/` 的可写性 / 磁盘剩余空间。
- 测试桩通过 `CompanyPersistence.save(_:to:)` 内部重载注入显式 URL，验证持久化层 `.failure`；再通过 `CompanyStore.persistSnapshot` 测试闭包注入失败结果，验证 `saveSnapshot()` 会追加一条 in-memory「持久化失败」风险事件并相邻去重。

## Keychain 写入失败可见性

`OPCKeychainStore.saveAPIKey(_:agentID:)` 返回 `OSStatus`：

- `errSecSuccess`：API Key 已写入 macOS Keychain（`SecItemUpdate` 命中或 `SecItemAdd` 新增）。
- `errSecParam`：传入 value 为空或无法 utf8 编码 —— 视为「没东西可写」，调用方按需忽略。
- 其他 `OSStatus`（例如 `errSecAuthFailed`、`errSecInteractionNotAllowed`、`errSecMissingEntitlement`）：底层 SecItem API 真实返回，调用方必须把它转成可见提示。

`CompanyStore` 在两条路径上消费返回值，并在非成功时通过 `recordKeychainSaveFailure` 在 `events` 头部插入一条 `.risk`「API Key 写入 Keychain 失败」事件，老板侧事件流可见；同员工同 OSStatus 的相邻失败做去重，避免 Keychain 持续锁定时刷屏：

- `hydrateAPIKeysFromKeychain`：启动 / 恢复快照后回写 in-memory apiKey 到 Keychain。
- `agentsForSnapshot`：每次 `saveSnapshot()` 前把 in-memory apiKey 归档到 Keychain，再清空快照副本以维持「snapshot 不携带明文 apiKey」的既有约束。

注意事项：

- 失败事件**只在内存**（保存到 events 数组），**不会被持久化** —— 因为 keychain 写失败时通常 saveSnapshot 仍可能成功，但这条事件本身不再触发 saveSnapshot（避免递归 + 失败态再次走快照前 keychain 写入），所以重启后这条提示会消失，但故障原因（Keychain 锁定 / 沙箱权限缺失）若仍存在，下次写入仍会重新触发。
- 即便 Keychain 写失败，`agentsForSnapshot` 仍会清空快照副本里的 apiKey（持久化层未变更）。in-memory `agents[]` 主数组的 apiKey 保留，本次会话仍可调用 API 员工，但**应用重启后该员工 API Key 会丢失**。事件 detail 已显式提示老板「需要重新填写并确认 Keychain 是否被锁定或权限受限」。
- 测试桩通过 `CompanyStore.keychainSaveAPIKey` 闭包注入显式 OSStatus，验证失败事件追加 / 相邻去重 / 成功路径不污染事件流，全程不接触真实 Keychain。

## 测试运行边界（持久化隔离）

`swift test` 必须使用隔离持久化目录，不得污染真实 App 状态。`CompanyPersistence.supportDirectory` 在测试进程下自动重定向到 `<TemporaryDirectory>/OPCCompanyTests-<pid>`，所有 `company-state.json` / `company-history.sqlite3` / `agents/` / 安全检查点都跟随。

按优先级生效：
1. 环境变量 `OPC_COMPANY_SUPPORT_DIR=/your/sandbox/path`（CI / 调试可显式覆盖）。
2. 检测到 XCTest / swift-testing / SwiftPM `swift test` 进程 → `<TemporaryDirectory>/OPCCompanyTests-<pid>`。
3. 真实 App 运行 → `~/Library/Application Support/OPCCompany`。

如果之前的 `swift test` 在升级前误污染了真实 `~/Library/Application Support/OPCCompany`，请用户确认后人工清理：

```bash
# 先备份再清理（用户决定时间，本仓库代码不主动删除真实状态）
mv ~/Library/Application\ Support/OPCCompany ~/Desktop/OPCCompany-backup-$(date +%Y%m%d)
```

## Computer Use 验证路径

OPC 的 UI 验证（Computer Use 或人工）必须在 **MacBook 内置屏** 上执行；外接显示器**不作为目标屏**，因为 SwiftUI 的可访问性树和 SF Symbol 渲染密度会随外接屏 DPI 变化，自动化定位会偶发漂移。

### 终端大厅维护区关键控件

终端大厅维护区（`LocalMaintenanceCenter`，同时被 `TerminalHallView` 和 `OperationsSuiteView` 引用）已为 Computer Use 加上稳定 accessibility identifier，可直接通过 a11y tree 定位。所有 identifier 集中声明在 `Sources/OPCCompanyCore/DisplayFormatting.swift` 的 `OPCUIAutomationIdentifier` 枚举中——这是 RUNBOOK 唯一权威来源；`uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 测试锁定下列每条都登记在 enum 中，且每条 enum case 都对应本文档：

- `OPCTerminalAutoInteractionLoopPanel`（`.terminalAutoInteractionLoopPanel`）：真实终端自动交互循环面板标题锚点；父容器不挂 identifier，避免抢占下列真实输入框和按钮的可操作节点。
  - `OPCTerminalAutoLoopTaskContextField`（`.terminalAutoLoopTaskContextField`）：任务上下文输入框（accessibilityLabel：技术负责人任务上下文）。
  - `OPCTerminalAutoLoopMaxTurnsStepper`（`.terminalAutoLoopMaxTurnsStepper`）：最大轮次步进器（accessibilityValue 为当前轮数）。
  - `OPCTerminalAutoLoopStartButton`（`.terminalAutoLoopStartButton`）：启动受控循环按钮（accessibilityLabel 在执行中切换为「循环执行中」）。
  - `OPCTerminalAutoLoopReportSummary`（`.terminalAutoLoopReportSummary`）：拒绝或完成后的中文摘要文本块（accessibilityLabel 在拒绝态/报告态之间切换；accessibilityValue 为本轮 `report.summaryText`，用于直接读取停止原因和轮次结果）。
- `OPCTerminalHallHeaderPromptField`（`.terminalHallHeaderPromptField`）：终端大厅顶部「发送给员工终端的提示词」输入框（accessibilityLabel：发送给员工终端的提示词；accessibilityHint 说明会被「运行全部」按钮发送给当前产品可执行员工）。
- `OPCTerminalHallRunAllButton`（`.terminalHallRunAllButton`）：终端大厅顶部「运行全部」按钮（accessibilityLabel：运行全部员工终端；accessibilityHint 说明会把当前提示词发送给当前产品所有可执行且未运行员工，没有可执行员工或员工都在运行时禁用）。
- `OPCTerminalManualREPLInputField`（`.terminalManualREPLInputField`）：本地维护详情「手动交互轮次」的一行输入框（accessibilityLabel：手动交互一行输入；accessibilityHint 说明会发送到当前选中员工真实终端席位，且不能包含换行）。
- `OPCTerminalManualREPLSendButton`（`.terminalManualREPLSendButton`）：本地维护详情「发送一行手动输入」按钮（accessibilityLabel 在空闲/发送中切换；accessibilityHint 说明会发送输入框中的一行文本到当前选中员工真实终端席位，输入为空或正在发送时禁用）。
- `OPCMaintenanceAuditCenter`（`.maintenanceAuditCenter`）：技术维护审计中心区块根节点（accessibilityLabel：技术维护审计中心）。
  - `OPCMaintenanceAuditRow`（`.maintenanceAuditRow`）：每条维护记录卡片（accessibilityLabel 为「标题 · 状态」）。
- `OPCMaintenanceArtifactCenter`（`.maintenanceArtifactCenter`）：维护产物档案中心区块根节点（accessibilityLabel：维护产物档案）。
  - `OPCMaintenanceArtifactRow`（`.maintenanceArtifactRow`）：每条维护产物卡片。
- `OPCCLIRecoveryAdvicePanel`（`.cliRecoveryAdvicePanel`）：员工恢复建议面板根节点（accessibilityLabel：员工恢复建议面板）；根节点使用 `.accessibilityElement(children: .contain)`，并通过 `accessibilityChildren` 同步镜像摘要和每位员工的手动重试按钮，避免 SwiftUI 合并文本时丢失摘要 ID 或覆盖按钮可达性。
  - `OPCCLIRecoveryAdviceSummary`（`.cliRecoveryAdviceSummary`）：员工恢复建议摘要文本（accessibilityLabel：员工恢复建议摘要；accessibilityValue 为当前 `cliRecoveryAdviceSummaryText()` 正文）。
  - `OPCCLIRecoveryAdviceManualRetryButton`（`.cliRecoveryAdviceManualRetryButton`）：每名员工的「手动重试一次」按钮（accessibilityLabel 为「员工名 · 手动重试一次」；accessibilityHint 说明仅临时异常可用，授权异常、忙碌或尚未观察状态不会自动重开；禁用状态保留在按钮自身）。
- `OPCTerminalWorkspaceHealthPreview`（`.terminalWorkspaceHealthPreview`）：持久终端可用性巡检按钮下方的就地预览卡片（accessibilityLabel：持久终端可用性预览；accessibilityValue 为当前 `terminalWorkspaceHealthAuditText()` 正文）；根节点用 `.accessibilityElement(children: .combine)` 折叠为单一可定位节点。
- `OPCRunDataCleanupPreview`（`.runDataCleanupPreview`）：清理预览文本块（accessibilityLabel：清理预览；accessibilityValue 为当前 `selectedProductRunDataSummary()` 正文）。
- `OPCCLIToolchainPreflightPreview`（`.cliToolchainPreflightPreview`）：命令行链路预检文本块（accessibilityLabel：命令行链路预检；accessibilityValue 为当前 `cliToolchainPreflightText()` 正文）。
- `OPCDefaultCompanyStatePreview`（`.defaultCompanyStatePreview`）：默认状态预览文本块（accessibilityLabel：默认状态预览；accessibilityValue 为当前 `defaultCompanyStatePreviewText()` 正文）。
- `OPCProductIsolationAuditPreview`（`.productIsolationAuditPreview`）：隔离体检预览文本块（accessibilityLabel：隔离体检预览；accessibilityValue 为当前 `productIsolationAuditText()` 正文）。
- `OPCCLIRuntimeIsolationPreview`（`.cliRuntimeIsolationPreview`）：命令行与工作区隔离预览摘要文本块（accessibilityLabel：命令行与工作区隔离预览；accessibilityValue 为当前 `cliRuntimeIsolationAuditText()` 正文）。
  - `OPCCLIRuntimeIsolationDetailToggle`（`.cliRuntimeIsolationDetailToggle`）：命令行与工作区隔离完整明细开关（accessibilityLabel：命令行与工作区隔离预览完整明细开关）；用于展开/收起同卡片的完整运维明细。
  - `OPCCLIRuntimeIsolationDetailPreview`（`.cliRuntimeIsolationDetailPreview`）：命令行与工作区隔离展开后的完整明细文本块（accessibilityLabel：命令行与工作区隔离预览完整明细；accessibilityValue 为当前 `cliRuntimeIsolationAuditDetailText()` 正文）。
- `OPCTerminalWorkspacePlanPreview`（`.terminalWorkspacePlanPreview`）：真实终端工作区预览摘要文本块（accessibilityLabel：真实终端工作区预览；accessibilityValue 为当前 `terminalWorkspacePlanText()` 正文）。
  - `OPCTerminalWorkspacePlanDetailToggle`（`.terminalWorkspacePlanDetailToggle`）：真实终端工作区完整明细开关（accessibilityLabel：真实终端工作区预览完整明细开关）；用于展开/收起同卡片的完整运维明细。
  - `OPCTerminalWorkspacePlanDetailPreview`（`.terminalWorkspacePlanDetailPreview`）：真实终端工作区展开后的完整明细文本块（accessibilityLabel：真实终端工作区预览完整明细；accessibilityValue 为当前 `terminalWorkspacePlanDetailText()` 正文）。
- `OPCSafetyCheckpointPreview`（`.safetyCheckpointPreview`）：安全检查点文本块（accessibilityLabel：安全检查点；accessibilityValue 为当前 `safetyCheckpointListText()` 正文）。
- `OPCLocalDiagnosticsPolicyPreview`（`.localDiagnosticsPolicyPreview`）：本机诊断与日志策略文本块（accessibilityLabel：本机诊断与日志策略；accessibilityValue 为当前 `localDiagnosticsPolicyText()` 正文）。
- `OPCEmployeeHandoffAuditPreview`（`.employeeHandoffAuditPreview`）：员工交接巡检按钮下方的就地预览卡片（accessibilityLabel：员工交接巡检预览；accessibilityValue 为当前 `employeeHandoffAuditText()` 正文）。
- `OPCJobArchiveStaleAuditPreview`（`.jobArchiveStaleAuditPreview`）：命令行作业幽灵巡检按钮下方的就地预览卡片（accessibilityLabel：命令行作业幽灵巡检预览；accessibilityValue 为当前 `jobArchiveStaleAuditText()` 正文）。
- `OPCEvidenceClassificationAuditButton`（`.evidenceClassificationAuditButton`）：运行证据分类巡检按钮。
  - `OPCEvidenceClassificationAuditPreview`（`.evidenceClassificationAuditPreview`）：运行证据分类巡检预览卡片（accessibilityLabel：运行证据分类巡检预览）；与 `OPCRuntimeSessionHealthAuditPreview` 一致，根节点用 `.accessibilityElement(children: .combine)` 把多条 Text 折叠为**单一可定位 a11y 根节点**，AX tree 上仅出现一条同名节点供 Computer Use 锁定。
- `OPCMaintenanceDataPressureAuditButton`（`.maintenanceDataPressureAuditButton`）：维护数据增长巡检按钮。
  - `OPCMaintenanceDataPressurePreview`（`.maintenanceDataPressurePreview`）：维护数据增长预览卡片（accessibilityLabel：维护数据增长预览）；与 `OPCRuntimeSessionHealthAuditPreview` 一致，根节点用 `.accessibilityElement(children: .combine)` 把多条 Text 折叠为**单一可定位 a11y 根节点**，AX tree 上仅出现一条同名节点供 Computer Use 锁定。
- `OPCHistoryIndexAuditPreview`（`.historyIndexAuditPreview`）：历史索引巡检按钮下方的就地预览卡片（accessibilityLabel：历史索引预览；accessibilityValue 为当前 `historyIndexAuditText()` 正文）。
- `OPCHistoryArchiveMigrationPreview`（`.historyArchiveMigrationPreview`）：历史归档迁移按钮下方的就地预览卡片（accessibilityLabel：历史归档迁移预览；accessibilityValue 为当前 `historyArchiveMigrationText()` 正文）。
- `OPCAutoCapturedSummaryDuplicatePreview`（`.autoCapturedSummaryDuplicatePreview`）：自动摘要去重预览文本块（accessibilityLabel：自动摘要去重预览；accessibilityValue 为当前 `autoCapturedSummaryDuplicatePreviewText()` 正文）。
- `OPCLegacyTaskProductMigrationButton`（`.legacyTaskProductMigrationButton`）：旧任务归属迁移按钮。
  - 按钮 hint 明确说明：仅当当前产品存在未归属旧任务时可用；首次点击进入确认态，再次点击才会迁入当前产品。
  - `OPCLegacyTaskProductMigrationPreview`（`.legacyTaskProductMigrationPreview`）：旧任务归属迁移预览文本块（accessibilityLabel：旧任务归属迁移预览；accessibilityValue 为当前 `legacyTaskProductMigrationText()` 正文）。
- `OPCRuntimeSessionHealthAuditPreview`（`.runtimeSessionHealthAuditPreview`）：运行会话健康巡检按钮下方的就地预览卡片（accessibilityLabel：运行会话健康巡检预览）；按钮触发后该卡片就地刷新「最近一次巡检」段，未运行过时显示中文空态 + 实时 `runtimeSessionHealthAuditText()` 兜底。
- `OPCLinkedLocalFileRootAllowlistPreview`（`.linkedLocalFileRootAllowlistPreview`）：本地文件索引根白名单预览文本块（accessibilityLabel：本地文件索引根白名单；accessibilityValue 为当前 `linkedLocalFileRootAllowlistText()` 正文）。

`LocalMaintenanceCenter` 详情面板内的核心动作按钮已在 `Sources/OPCCompanyCore/OperationsSuiteView.swift` 内为 Computer Use 挂稳定 anchor，accessibilityLabel/Hint 全部为中文短句，accessibilityIdentifier 由 `OPCUIAutomationIdentifier` 集中登记。**不要**通过 OCR 截图寻找这些按钮——直接按 anchor 在 a11y tree 上定位：

- `OPCCLIRuntimeIsolationAuditButton`（`.cliRuntimeIsolationAuditButton`）：「运行命令行与工作区隔离体检」按钮（accessibilityLabel：运行命令行与工作区隔离体检；accessibilityHint：为当前产品运行命令行与工作区隔离体检，写入维护审计并刷新预览，不会修改运行数据或员工）。
- `OPCTerminalWorkspaceStartButton`（`.terminalWorkspaceStartButton`）：「启动真实终端工作区」按钮（accessibilityLabel：启动真实终端工作区；accessibilityHint：为当前产品启动真实终端工作区，把员工任务路由到 macOS 终端真实席位）。
- `OPCTerminalWorkspaceRefreshLogsButton`（`.terminalWorkspaceRefreshLogsButton`）：「刷新真实终端日志」按钮（accessibilityLabel：刷新真实终端日志；accessibilityHint：刷新当前产品真实终端工作区的可见日志，不影响真实任务执行）。
- `OPCTerminalWorkspaceHealthAuditButton`（`.terminalWorkspaceHealthAuditButton`）：「运行持久终端可用性巡检」按钮（accessibilityLabel：运行持久终端可用性巡检；accessibilityHint：巡检当前产品持久终端工作区的可用性，写入维护审计并就地刷新可用性预览卡片）。
- `OPCRuntimeSessionHealthAuditButton`（`.runtimeSessionHealthAuditButton`）：「运行会话健康巡检」按钮（accessibilityLabel：运行会话健康巡检；accessibilityHint：巡检当前产品员工会话健康度，写入维护审计并就地刷新会话健康预览卡片）。
- `OPCEmployeeHandoffAuditButton`（`.employeeHandoffAuditButton`）：「运行员工交接巡检」按钮（accessibilityLabel：运行员工交接巡检；accessibilityHint：巡检当前产品员工交接证据完整度，写入维护审计并刷新员工交接巡检预览）。
- `OPCJobArchiveStaleAuditButton`（`.jobArchiveStaleAuditButton`）：「运行命令行作业幽灵巡检」按钮（accessibilityLabel：运行命令行作业幽灵巡检；accessibilityHint：巡检当前产品命令行作业档案的幽灵或陈旧作业，只写维护审计，不删除作业产物）。
- `OPCHistoryIndexAuditButton`（`.historyIndexAuditButton`）：「运行历史索引巡检」按钮（accessibilityLabel：运行历史索引巡检；accessibilityHint：巡检当前产品历史索引完整度与一致性，写入维护审计并刷新历史索引预览）。
- `OPCHistoryArchiveMigrationButton`（`.historyArchiveMigrationButton`）：「运行历史归档迁移」按钮（accessibilityLabel：运行历史归档迁移；accessibilityHint：把当前产品旧历史记录按归档规则迁入历史归档，写入维护审计并刷新归档迁移预览）。
- `OPCStaleRuntimeSessionRecoveryButton`（`.staleRuntimeSessionRecoveryButton`）：「恢复异常占用员工会话」按钮（accessibilityLabel：恢复异常占用员工会话；accessibilityHint：恢复当前产品被异常占用的员工运行会话，释放席位但不会修改员工配置或项目文件）。
- `OPCRunDataCleanupConfirmButton`（`.runDataCleanupConfirmButton`）：「清理当前产品运行/测试数据」执行按钮；它位于常驻确认区内，必须先在同区输入框输入「确认」才会启用；accessibilityLabel 固定为「清理当前产品运行/测试数据」，accessibilityHint 说明不会删除员工或项目文件。
- `OPCDefaultCompanyStateConfirmButton`（`.defaultCompanyStateConfirmButton`）：「恢复默认公司状态」执行按钮；它位于常驻确认区内，必须先在同区输入框输入「确认」才会启用；accessibilityLabel 固定为「恢复默认公司状态」。
- `OPCSafetyCheckpointRollbackConfirmButton`（`.safetyCheckpointRollbackConfirmButton`）：「回滚到最近安全检查点」执行按钮；它位于常驻确认区内，必须先在同区输入框输入「确认」才会启用；accessibilityLabel 固定为「回滚到最近安全检查点」。
  - 这三个危险确认区常驻在本地维护详情顶部，不再依赖“点击后展开”或系统 alert，避免 sheet/scroll 内临时确认 UI 在辅助功能点击时不可见。
  - Computer Use 验证时应只确认三个执行按钮初始为禁用、确认词输入框可定位、点击「取消」会清空确认词；不要点击已启用的执行按钮，除非真实需要执行危险维护动作。
- `OPCLocalMaintenanceDangerousConfirmationPanel`（`.localMaintenanceDangerousConfirmationPanel`）：本地维护危险操作确认面板 ID 前缀；实际节点按动作追加 `-cleanup`、`-reset`、`-rollback`，显示对应危险操作标题和影响说明。
- `OPCLocalMaintenanceDangerousConfirmationPhraseField`（`.localMaintenanceDangerousConfirmationPhraseField`）：危险操作确认词输入框 ID 前缀；实际节点按动作追加 `-cleanup`、`-reset`、`-rollback`，输入「确认」后对应执行按钮才启用。
- `OPCLocalMaintenanceDangerousConfirmationCancelButton`（`.localMaintenanceDangerousConfirmationCancelButton`）：危险操作确认区「取消」按钮 ID 前缀；实际节点按动作追加 `-cleanup`、`-reset`、`-rollback`，点击后只清空确认词，不执行维护动作。
- `OPCLocalMaintenanceDangerousConfirmationExecuteButton`（`.localMaintenanceDangerousConfirmationExecuteButton`）：保留为危险操作执行按钮类别锚点；当前实际执行按钮使用对应业务 ID（`OPCRunDataCleanupConfirmButton`、`OPCDefaultCompanyStateConfirmButton`、`OPCSafetyCheckpointRollbackConfirmButton`）以便 Computer Use 直接定位具体动作。

- `OPCTerminalHallDetailSheet`（`.terminalHallDetailSheet`）：终端大厅二级详情 sheet 根节点，用于确认已从摘要页进入详情面板。
- `OPCLocalMaintenanceCenterRoot`（`.localMaintenanceCenterRoot`）：本地稳定性维护中心根节点。
- `OPCTerminalHallOverviewSummary`（`.terminalHallOverviewSummary`）：终端大厅顶部默认可见的运行状态概览卡片。
- `OPCTerminalHallLocalMaintenanceHeaderTrigger`（`.terminalHallLocalMaintenanceHeaderTrigger`）：终端大厅顶部「本地维护」直接入口，点击打开本地稳定性与命令行运维详情面板。
- 终端大厅默认可见的**单员工终端卡片** `TerminalAgentCard` 已为 5 个核心动作按钮挂稳定 anchor，全部走 `Sources/OPCCompanyCore/TerminalHallView.swift` 内的 `TerminalAgentCard` 实现；同名按钮在每张员工卡上各出现一次，accessibilityLabel 必须带员工显示名，方便 Computer Use 区分目标员工：
  - `OPCTerminalAgentCardRefreshPreflightButton`（`.terminalAgentCardRefreshPreflightButton`）：员工卡顶部「运行前预检」标题右侧的 `arrow.clockwise` icon-only 刷新按钮（accessibilityLabel：刷新 `{员工名}` 运行前预检；accessibilityHint 说明会基于当前提示词与员工配置重新生成运行前预检文本）。
  - `OPCTerminalAgentCardSelectButton`（`.terminalAgentCardSelectButton`）：员工卡底部 `person.crop.circle` 「选中员工」按钮（accessibilityLabel：选中 `{员工名}`；accessibilityHint 说明会高亮卡片并把右侧检查器切换到该员工）。
  - `OPCTerminalAgentCardPreflightButton`（`.terminalAgentCardPreflightButton`）：员工卡底部「预检」按钮，触发 `recordCLIPreflight(agentID:prompt:)` 写入命令行预检审计（accessibilityLabel：写入 `{员工名}` 命令行预检审计；accessibilityHint 说明老板角色禁用）。
  - `OPCTerminalAgentCardRunButton`（`.terminalAgentCardRunButton`）：员工卡底部「运行 / 运行中」主按钮，调用 `runAgent(agentID:prompt:)`（accessibilityLabel 在「运行 `{员工名}` 终端」/「`{员工名}` 运行中」之间切换；accessibilityHint 说明会把当前提示词发送给该员工的真实终端席位，员工运行中或老板角色时禁用）。
  - `OPCTerminalAgentCardClearLogButton`（`.terminalAgentCardClearLogButton`）：员工卡底部 `trash` icon-only 「清空日志」按钮（accessibilityLabel：清空 `{员工名}` 终端日志；accessibilityHint 说明只清空可见输出日志，不影响运行中任务与员工持续会话；当卡片显示「暂无终端输出。」时禁用）。
- `OPCAdvancedMaintenanceArchitectureSummaryCard`（`.advancedMaintenanceArchitectureSummaryCard`）：终端大厅默认可见的「多员工架构体检与闭环」**摘要工作台卡片**，展示完成度 / 已闭合 · 待加强 · 未闭合 · 检查项 / 最近闭环摘要 + 主要操作按钮。
  - `OPCAdvancedMaintenanceArchitectureAuditButton`（`.advancedMaintenanceArchitectureAuditButton`）：摘要卡片主操作「运行体检」按钮（accessibilityLabel：运行多员工架构体检；accessibilityHint 说明会为当前产品运行体检、写入维护审计并把选中员工切换到技术负责人）。
  - `OPCAdvancedMaintenanceArchitectureClosureDrillButton`（`.advancedMaintenanceArchitectureClosureDrillButton`）：摘要卡片主操作「闭环演练」按钮（accessibilityLabel：运行多员工架构闭环演练；accessibilityHint 说明会生成闭环轨迹并把选中员工切换到技术负责人）。
- `OPCAdvancedMaintenanceGatewaySummaryCard`（`.advancedMaintenanceGatewaySummaryCard`）：终端大厅默认可见的「通信网关与手机指令」**摘要工作台卡片**，展示通道总数 · 启用 · 可入站 · 通信日志 + 最近通信摘要 + 主要操作按钮。
- `OPCAdvancedMaintenanceLocalSummaryCard`（`.advancedMaintenanceLocalSummaryCard`）：终端大厅默认可见的「本地稳定性与命令行运维」**摘要工作台卡片**，展示维护审计/产物计数与阈值压力 + 最近维护摘要 + 主要操作按钮。
  - `OPCAdvancedMaintenanceLocalIsolationAuditButton`（`.advancedMaintenanceLocalIsolationAuditButton`）：摘要卡片主操作「运行隔离体检」按钮（accessibilityLabel：运行本地隔离体检；accessibilityHint 说明会为当前产品运行多产品隔离体检、写入维护审计并刷新摘要）。
  - `OPCAdvancedMaintenanceLocalCLIPreflightButton`（`.advancedMaintenanceLocalCLIPreflightButton`）：摘要卡片主操作「命令行预检」按钮（accessibilityLabel：运行命令行链路预检；accessibilityHint 说明这是干跑预检，不调用真实模型任务）。
- `OPCAdvancedMaintenanceArchitectureDetailTrigger`（`.advancedMaintenanceArchitectureDetailTrigger`）：摘要卡片右下「查看详情」按钮，点击打开二级 sheet 面板，渲染完整 `MultiAgentArchitectureAuditCenter`（含闭环演练摘要、重做摘要、闭环详情 sheet、检查项列表）。
- `OPCAdvancedMaintenanceGatewayDetailTrigger`（`.advancedMaintenanceGatewayDetailTrigger`）：摘要卡片右下「查看详情」按钮，点击打开二级 sheet 面板，渲染完整 `CommunicationGatewayCommandCenter`（含通道配置、手机指令模拟、完整通信日志、安全基础件）。
- `OPCAdvancedMaintenanceLocalDetailTrigger`（`.advancedMaintenanceLocalDetailTrigger`）：摘要卡片右下「查看详情」按钮，点击打开二级 sheet 面板，渲染完整 `LocalMaintenanceCenter`，**维护审计中心 / 维护产物档案 / 运行证据分类巡检 / 维护数据增长巡检 / 真实终端自动循环面板**等深层控件全部嵌在此二级面板内部。

**重要**：终端大厅默认即摘要化工作台。默认页面除「终端大厅运行状态概览」+ 员工终端卡片外，还会**默认可见**三张摘要工作台卡片（架构 / 通信 / 本地稳定性）。**不再使用 DisclosureGroup 折叠隐藏**——Computer Use / 人工验证维护类深层 anchor（`OPCMaintenanceAuditCenter` / `OPCMaintenanceArtifactCenter` / `OPCEvidenceClassificationAudit*` / `OPCMaintenanceDataPressure*` / `OPCTerminalAutoInteractionLoopPanel` / `OPCTerminalAutoLoop*`）的步骤是：先点击对应「查看详情」按钮（一般是 `OPCAdvancedMaintenanceLocalDetailTrigger`）打开二级 sheet 面板，再在面板内部下钻到具体控件。摘要卡片本身展示状态/指标/最近摘要/主要操作，常规巡检不需要打开二级面板即可触发。

**详情入口命名 accessibility action 兜底**：上述 4 个详情入口按钮（顶部 `OPCTerminalHallLocalMaintenanceHeaderTrigger` 与三张摘要卡的 `OPCAdvancedMaintenance{Architecture,Gateway,Local}DetailTrigger`）除主按钮闭包外，还各自登记了与 `accessibilityLabel` 同名的 `.accessibilityAction(named:)` 兜底——分别为「打开本地维护详情」「查看多员工架构体检详情」「查看通信网关与手机指令详情」「查看本地稳定性与命令行运维详情」。它们与按钮主闭包写入同一个 `presentedDetail` case，专为 Computer Use 在 AXPress 只拿到焦点不触发 SwiftUI 闭包时使用：可通过 `NSAccessibilityElement.action(name:)` / `osascript ... AX action` 改用命名动作直接触发详情 sheet。`LocalMaintenanceSummaryCard` 整卡同时仍保留容器级动作「查看本地维护详情」，与按钮自身的「查看本地稳定性与命令行运维详情」并存。

二级 sheet 面板内部的「运行证据归档（技术负责人专用）」SectionHeader 仍然存在（位于 `LocalMaintenanceCenter` 详情面板下半部），便于 Computer Use 通过 SectionHeader 文本快速定位维护审计 / 维护产物档案分组，再下钻到具体 a11y identifier。

**历史索引 / 历史归档迁移预览的唯一主位置**：`LocalMaintenanceCenter` 详情 sheet 内，「历史索引预览」由 `HistoryIndexAuditPreview()` 承载（紧贴「运行历史索引巡检」按钮下方，anchor：`OPCHistoryIndexAuditPreview`），「历史归档迁移预览」由 `HistoryArchiveMigrationPreview()` 承载（紧贴「运行历史归档迁移」按钮下方，anchor：`OPCHistoryArchiveMigrationPreview`）；下方详细运维区**不再写**重复的 `SectionHeader(title: "历史索引预览")` / `SectionHeader(title: "历史归档迁移预览")` 块。Computer Use 定位历史预览时直接锁定上述两个预览卡片自身，并读取 accessibilityValue 中的当前正文，不需要截图 OCR。下方详细运维区只保留没有主按钮重复的「本地文件索引根白名单」「自动摘要去重预览」「旧任务归属迁移预览」等 SectionHeader 块。

**员工卡命令行任务日志摘要**：终端大厅员工卡调用 `visibleTerminalLog(for:)`，已完成的 `[OPC 命令行任务] ... [命令退出码 N] ... [OPC 交互状态]` transcript 会在默认卡片中显示为 `[OPC 命令行任务摘要]`，只保留执行位置、运行方式、任务摘要、退出码和交互状态，并提示完整输出保留在命令行作业档案。原始 `terminalLogs`、作业档案、右侧终端原始审计来源不改；没有完整退出码边界的普通模型输出仍按既有规则保留。

**员工卡真实终端工作区日志摘要**：`[OPC 真实终端工作区]` 启动 transcript 在默认员工卡中显示为 `[OPC 真实终端工作区摘要]`，只保留席位创建状态、抽象执行位置和维护档案提示；原始 shell 命令、用户提示符、`printf` 文本和绝对路径只留在原始 `terminalLogs` / 维护档案排查来源，不进入默认卡片。

**持久终端完整任务 runner**：完整员工任务提交不再把长 prompt / 多行参数直接粘进真实终端 pane。OPC 会在当前产品根目录下写入 `.opc/runtime/terminal-runners/<marker>.sh` 一次性 runner，真实 pane 只收到 `/bin/sh <runner>` 短命令；runner 内负责 start/end marker、执行目录切换、命令参数、退出码回传和退出自清理。runner 目录必须保持 `0700`，新任务启动前会清理 6 小时以上陈旧 `.sh`；如果 Computer Use 或人工排查看到该目录残留大量脚本，优先检查上一轮终端任务是否被系统外部强制杀掉。

**员工 prompt token 预算边界**：员工聊天 prompt 会裁剪最近聊天、长期记忆、当前聊天文本和聊天修正草稿的超长片段，保留当前产品、身份、任务、记忆摘要和「还有 N 项」追踪提示；员工执行 prompt 的档案块会裁剪使命、职责、边界、回复规则、长期记忆、当前产品员工记忆和技能摘要，完整配置仍保留在员工工作区文件中。不要裁剪 `agentExecutionPrompt` 的当前 `userPrompt` 任务正文；该正文是本轮真实工作指令，截断会降低执行能力。

**员工任务 prompt 预算边界**：`workOrderPrompt` 只保留导入报告中的少量规则、工具和项目文件线索，长路径、长验收标准和长条目会被裁剪，并用「还有 N 项已保存在导入报告」提示完整线索仍可按需读取；审查/老板打回产生的返工 prompt 会裁剪长原因和长成功标准。不要把导入项目的完整文件清单、超长验收文字或大段返工说明直接拼进员工命令行 prompt。

**员工协作消息 token 预算边界**：结构化协作消息总线只保存短 subject 和有限 body，避免审查结论、验收标准、报告正文或交接说明变成第二份无限上下文。需要完整长报告时应写入产物、员工工作区或审计档案，再在协作消息里放摘要和定位线索。

**长期 CLI 会话 token 预算边界**：首次运行会发送员工操作档案和本轮任务；同一产品、同一员工、同一后端的续会话只发送本轮任务和一行上下文提示，不重复发送完整使命、职责、记忆和技能。员工档案文件同步使用内容差异判断，内容未变化时不刷新规则/记忆文件，减少 CLI 因文件变化重新读取上下文的机会。

**终端大厅运行全部 token 预算边界**：顶部「运行全部」仍保留，但当提示词是默认汇报且会同时发送给多名可运行员工时，必须先出现中文确认。这样不禁用工作流，也避免误点一次消耗整支团队的命令行额度。

### 维护记录过滤可视化验证

真实终端自动循环 preflight 拒绝场景（最易复现：把员工来源切到接口模式，再点「启动受控循环」）：

1. 老板总控台「最近交付与验收」widget：不应出现「真实终端自动循环就绪审计」标题。
2. 产品详情交付区 prefix(3) 和交付验收中心 prefix(12)：同上。
3. 运营套件验收抽屉 prefix(6)：同上。
4. 终端大厅维护区「技术维护审计中心」：能看到这条「真实终端自动循环就绪审计 · 有警告」。
5. 架构体检文本：末尾有「最近真实终端自动循环就绪审计：有警告 · 就绪校验：未确认最近专用就绪提示」。

数据 accessor 层面的等价验证由 `realTerminalAutoLoopRejectionRoutesAuditToMaintenanceOnlyAndKeepsBossViewsEmpty` 测试守门，未来 a11y 标识符或 view 数据源被改坏会立刻被 swift test 捕获。

## Distribution

For personal local use, run from source or build a local executable.

The current formal-use target is single-user local use on this Mac, so Developer ID signing, notarization, DMG packaging, Sparkle updates, and hosted crash reporting are not blockers. `scripts/build_app_bundle.sh` performs ad-hoc signing to keep the local app identity more stable for macOS privacy prompts.

For product distribution outside the Mac App Store:

- Enroll in Apple Developer Program.
- Sign with Developer ID.
- Notarize the app.
- Ship a DMG or ZIP.
- Use Sparkle for updates.
