# 跨平台终端大厅方案与落地实录（#70）

状态：**方案 A v1 已落地**（PR #77 桥动词+壳渲染面;PR #78 快照瘦身）· 2026-09-16 · 配套：[WINDOWS_PORT_RFC.md](WINDOWS_PORT_RFC.md)（M3 的 🟡 部分就是本篇）
本文续接 [TERMINAL_HALL_DESIGN.md](TERMINAL_HALL_DESIGN.md)（macOS 现状设计）；英文版见 [TERMINAL_HALL_CROSS_PLATFORM.en.md](TERMINAL_HALL_CROSS_PLATFORM.en.md)。

## 大厅今天到底是什么（实测,非假设）

macOS 大厅**不是终端仿真器**。数据流是：

1. agent 以**一次性 print 模式进程**运行（`claude -p …`、`codex exec …`、
   `gemini -p …`）——prompt 是单条 argv,输出经 `Process` **管道**流回
   （`OPCCompanyCore` 全链无 PTY；#9 落地的启动缝仍是管道）；
2. 每个 stdout/stderr 块 → `appendTerminalLog` → `productTerminalLogs:
   [String: String]`（键 = `产品UUID:agentUUID`）,纯文本、`@Published`、
   **已在持久化快照里**。旧 `terminalLogs: [UUID: String]` 镜像字段自 #78
   起保留于 schema 但不再双写增长（迁移为无损剪枝,分歧文本两侧都留）；
3. 桥的 `opc_bridge_snapshot_json` 编码 `currentSnapshot()` →
   **壳今天就已经收到终端 transcript**（就在老板面板渲染的快照载荷里）；
4. 仅有的"交互"路径（`persistentProtocol`）基于 tmux（`send-keys` +
   `capture-pane` 轮询）——tmux 在 Windows 解析不到,该能力在 Windows 上
   按设计降级为一次性（见 #9 记录）。

所以"员工席位跑在 Windows 上"**90% 已经存在**：执行已在跑（一次性、过缝、
含 `.cmd` shim），输出已进快照。缺的是**壳里一个好的观看面**,不是传输奇迹。

## 选项

### A. Transcript 镜像（v1 已落地,PR #77/#78）
壳内直接渲染员工 transcript——点员工 chip → 底部等宽 `SelectableText`
面板、自动跟随尾部、上滚即暂停（`flutter_shell/lib/main.dart`）。
零原生代码、零新插件；增量拉取靠 digest 对比游标,只拉增长的字节窗口,
日志缩短（清空/截断）→ 清屏重拉;产品切换 → 缓存按产品失效。

桥已补的两个动词（ABI 6 符号冻结不破,经 `opc_bridge_last_error` 返回,
rc=0 + last_error=JSON 是查询契约）：
- `terminal_digest {}` → 所选产品 `{agentID: 字节数}`,跨产品前缀过滤;
- `terminal_tail {agentID, afterOffset, maxBytes}` → `{text, nextOffset,
  length}` 字节窗口（纯函数 `OPCBridgeWindow.read`:不切断 UTF-8、游标必
  前进、越界钳制、字符内偏移回退对齐）。

事件驱动（动作后拉 digest）,定时轮询留 M5。原设想的 `stream_tick` /
`logRevision` 计数器实测不需要——digest 本身就是活性信号。

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
1. ~~桥的 `terminal_tail` 动词 + revision 计数器~~ —— **已完成（PR #77）**：
   `terminal_digest` + `terminal_tail` 落在 `OPCBridge.swift` 的 `command`
   派发,窗口数学抽成纯函数 `OPCBridgeWindow.read`（4 项行为不变量测试）。
2. ~~Flutter 渲染~~ —— **已完成（PR #77）**：`flutter_shell/lib/main.dart`
   的员工 chip → 底部 transcript 面板,跟随底部 + 上滚暂停,widget 测试
   用 `FakeOpcBridge`（返回 malloc 串,测试断言每个地址都被 free）。
3. ~~快照摘要化~~ —— **已完成（PR #78，#70 任务 3）**：双写已停,旧
   `terminalLogs` 镜像保留字段不删（schema 兼容）,迁移改为加载期无损剪枝
   （重复/空条目删,分歧文本两侧都留）。原设想"把日志整个移出快照载荷、
   只走 tail 动词"未采纳——实测 GUI 大厅卡片经 `terminalLogForCurrentProduct`
   读内存态、快照仍是跨进程同步通道,移出会伤现有消费方,而剪枝已拿走
   重复的那一份成本。
仍开放（欢迎认领）：
- **Boss 大厅接线**：macOS SpriteKit 场景里给员工席位加上 transcript 入口
  （与 Flutter 壳独立的一块）。
- **定时轮询**（M5）：当前是事件驱动,agent 在桥外自行增长日志时壳不会
  自动感知。
- **选项 B**：xterm.js + 原生 PTY/ConPTY,前置条件是交互式模式成为真实
  产品问题（`-p` 一次性 agent 在任何平台都没有 stdin 故事）。

欢迎评论;回复即认领。合并贡献计入 release notes（见 CONTRIBUTING.md）。
