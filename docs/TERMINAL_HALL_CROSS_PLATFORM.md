# 跨平台终端大厅方案（#70 · 讨论征集）

状态：**提案,欢迎评论** · 2026-09-16 · 配套：[WINDOWS_PORT_RFC.md](WINDOWS_PORT_RFC.md)（M3 的 🟡 部分就是本篇）
本文续接 [TERMINAL_HALL_DESIGN.md](TERMINAL_HALL_DESIGN.md)（macOS 现状设计）；英文版见 [TERMINAL_HALL_CROSS_PLATFORM.en.md](TERMINAL_HALL_CROSS_PLATFORM.en.md)。

## 大厅今天到底是什么（实测,非假设）

macOS 大厅**不是终端仿真器**。数据流是：

1. agent 以**一次性 print 模式进程**运行（`claude -p …`、`codex exec …`、
   `gemini -p …`）——prompt 是单条 argv,输出经 `Process` **管道**流回
   （`OPCCompanyCore` 全链无 PTY；#9 落地的启动缝仍是管道）；
2. 每个 stdout/stderr 块 → `appendTerminalLog` → `terminalLogs: [UUID: String]`,
   纯文本、`@Published`、**已在持久化快照里**；
3. 桥的 `opc_bridge_snapshot_json` 编码 `currentSnapshot()` →
   **壳今天就已经收到终端 transcript**（就在老板面板渲染的快照载荷里）；
4. 仅有的"交互"路径（`persistentProtocol`）基于 tmux（`send-keys` +
   `capture-pane` 轮询）——tmux 在 Windows 解析不到,该能力在 Windows 上
   按设计降级为一次性（见 #9 记录）。

所以"员工席位跑在 Windows 上"**90% 已经存在**：执行已在跑（一次性、过缝、
含 `.cmd` shim），输出已进快照。缺的是**壳里一个好的观看面**,不是传输奇迹。

## 选项

### A. Transcript 镜像（推荐 v1）
壳内直接渲染 `terminalLogs`——每员工一 tab/行、自动跟随尾部、等宽
`SelectableText`。零原生代码、零新插件；数据在壳本来就拉的每次快照里。

需要桥补两个小动词才不卡：
- `terminal_tail {agentID, maxBytes, afterOffset}` → 返回 `{text, nextOffset}`,
  O(窗口) 成本（避免每次快照刷新重传兆级日志；快照本体可只留
  `terminalLogSizes` 摘要）；
- `stream_tick {since}` 廉价活性探针,让壳知道何时拉尾（或现有 @Published
  变更已可驱动一个 `logRevision: Int` 计数器,壳 diff 它即可）。

诚实属性：所见即 macOS 非 tmux 路径所显示——不是二等体验,是同一种体验。

### B. xterm.js + WebView + 原生 PTY
真仿真：TUI、颜色、交互 REPL、resize。代价：桌面 WebView 插件（xterm 需
`webview_windows`/macOS `WKWebView` 桥接——新增供应链与插件注册）、核心从未
有过的 PTY 层（`forkpty`/ConPTY）、以及 escape 序列的来源：print 模式一次性
输出本来就几乎纯文本——**B 主要服务的是交互模式,而核心今天除 macOS-only
tmux 外并不运行交互模式**。除非有维护者愿意接,推迟到 M5；B 不阻塞 Windows。

### C. 先 A 后 B,同一动词面
`terminal_tail` 契约在 PTY 到来时不需要改变；壳 UI 可在不破桥 ABI 的前提下
换渲染器（动词是加法）。

## 结论
**选 C**：A 作为 Windows 可见大厅的 v1（小、诚实、复用壳已有的快照）；
B 作为 M5 选项,前提是真正的交互模式需求成立（那本身是个产品问题：
`-p` 一次性 agent 在任何平台都没有 stdin 故事）。

## 招募（具体）
1. **桥的 `terminal_tail` 动词 + revision 计数器**——约 100 行 Swift + 3 个
   测试；入口：`OPCBridge.swift` 的 `command` 派发（现有 goal/advance/decide/
   save 处理处）+ `CompanyStore+Runtime.swift` 的 `appendTerminalLog` 挂钩。
   good-first-issue 体量。
2. **Flutter 渲染**：可滚动逐员工 transcript,跟随底部 + 手动滚动即暂停
   （经典日志查看器 UX）。`company_home_test.dart` 展示了 widget 测试缝
   （FakeOpcBridge）——期望带 UI 测试。
3. 快照摘要化的意见（`terminalLogs` 从全量快照载荷移出、只走 tail 动词?
   会不会伤 GUI?——大概率不会,GUI 读内存态,快照消费方是 CLI/桥——
   **动手前先验证**,`opc report` 会读 transcript 邻近字段）。

欢迎评论;回复即认领。合并贡献计入 release notes（见 CONTRIBUTING.md）。
