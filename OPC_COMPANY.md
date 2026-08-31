# OPC 公司产品总纲

最后更新：2026-05-07

这个文件是 OPC 公司的长期产品总纲，作用类似 `CLAUDE.md`/项目宪法。任何后续开发、角色设定、架构调整、UI 改造、功能取舍和验收，都必须优先遵守这里的规则。碎片文档可以存在，但不能和本文件冲突。

## 1. 产品定位

OPC 公司是一个本地 macOS AI 公司管理 App。

老板不直接面对模型、命令和复杂后台，而是面对一个拟人化的 AI 公司：

- 老板负责提出目标、确认方向、审批风险、验收结果。
- CTO 负责理解目标、拆解任务、分配员工、调度进度、控制风险、汇报结果。
- 员工 Agent 负责具体执行，例如 UI 设计、代码实现、审查、测试、资料研究、售前方案编写。
- 每个产品工作区拥有独立团队、任务、记忆、终端、产物和验收记录。

核心体验不是“多模型聊天工具”，而是“本地 AI 公司操作系统”。

## 2. 产品原则

### 老板视角优先

- 老板总控台只展示结果、进度、风险、待决策事项和交付物。
- 不把 CTO 后台、CLI 链路、模型调度、任务拆解细节堆到老板首页。
- 老板能做的事应该接近真实公司老板：定目标、看汇报、批风险、验成果、找人沟通。

### CTO 负责后台复杂度

- 任务拆解、员工分配、多分支执行、验收回流、失败重试、上下文同步都由 CTO 承担。
- CTO 可以有后台视图，但后台视图不能污染老板视图。
- CTO 的汇报必须讲结果、风险和下一步，不背诵流程。

### 员工像人，不像接口

- 员工有角色、记忆、规则、工作边界、沟通风格和长期档案。
- 聊天回复必须来自真实模型链路或明确的本地降级提示。
- 不能用硬编码模板伪装员工人格。
- 默认回复短、自然、具体；执行任务时再输出结构化报告。

### 公司场景不是装饰

- 2D 公司场景是核心入口，不是附属页面。
- 小人的位置、动画、状态、办公室和工位必须映射真实工作状态。
- 点小人主要用于查看状态和沟通，不应该无故跳到复杂后台。

### 多产品是基本能力

- OPC 不是只服务一个项目。
- 每个产品是一个独立工作区，有自己的根目录、团队、任务、记忆和产物。
- 同一个员工可以服务多个产品，但执行时必须明确当前产品上下文。

## 3. 目标用户和典型场景

### 目标用户

- 独立开发者、产品负责人、售前顾问、创业者。
- 不想手动协调多个 AI 工具，希望用“公司团队”方式推进工作。

### 核心场景

- App / 软件产品开发：老板提出想法，CTO 拆解，UI/工程/审查/测试并行推进。
- 售前方案自动化：总控理解客户需求，研究员找资料，方案员工编写，审查员检查，CTO 汇总交付。
- 多产品并行管理：多个产品各有团队，老板只看每个产品的进展、风险和交付。
- 本地文件接管：导入已有项目目录，保留原有规则、记忆、CLI 设置，OPC 团队接手继续开发。

## 4. 当前产品状态

已经具备的基础：

- SwiftUI macOS 本地 App。
- 左侧产品和员工列表。
- 右侧沟通、任务、事件、档案、终端面板。
- 2D 公司场景，包含老板、CTO、员工办公区和像素小人。
- 多产品工作区。
- 员工档案、角色、模型后端、推理强度、外观配置。
- Codex / Claude / Gemini / API 后端配置入口。
- 终端大厅和 CLI 命令执行入口。
- 本地 JSON 持久化。
- 角色包、记忆、技能、工作区隔离的第一版结构。
- 常驻会话/预热状态的基础模型。
- 老板总控台、产品详情、员工工作台、流程图、终端大厅。

多 Agent 架构升级方案已经闭合的能力：

- 结构化员工协作消息总线已接入 CTO 派发、员工回传、审查请求、老板审批和员工交接。
- 技术负责人调度闭环已形成可测试链路：目标拆解、员工执行、审查验收、老板审批、交付证据和验收门禁可以通过闭环演练跑到 100%。
- 显式任务图、交付证据库、审批、验收和闭环追踪已经联动；散落的无关证据不会冒充完整闭环。
- 老板视图已按职责减噪：老板只看结果、风险、审批和交付入口，后台维护、命令行和运维细节留在技术负责人/终端大厅。
- 默认可见界面进一步中文化和减噪：公司场景、右侧通信面板和终端大厅默认摘要使用「智能控制 / 通信」「指令通道」「本地员工编队」「技术负责人」等中文职责词；Codex、Claude Code、Gemini、gpt-5.5、sonnet 等品牌/模型名保留；底层命令参数、完整命令数组、旧终端日志里的完整工具路径和内部字段不进入默认卡片。
- 产品详情和员工工作台默认密度已继续收敛：产品详情不再重复展示阶段百分比/任务数，协作链路默认只浮出最近 3 条，开发期元说明不进入老板界面；任务级验收标准标为「当前待办标准」，完成后才显示「整体成功标准」；员工队列 footer 使用「后续还有…」表达连续浮现，不用折叠/未展开叙述。
- 终端大厅默认日志显示继续收敛：多段会话预热记录在默认卡片中显示最近一条 + 历史条数汇总；真实终端工作区启动 transcript 在默认卡片中显示为中文席位摘要，不再铺出 shell 命令、用户提示符、`printf` 原文或绝对路径；已完成的命令行任务 transcript 在默认卡片中显示为中文任务摘要、退出码和交互状态，不再整段铺出模型原始输出、会话编号或绝对路径；原始 `terminalLogs` 审计流和命令行作业档案不改。终端大厅模式下右侧终端 tab 只保留当前员工日志，不再解释 UI 入口设计。
- 终端大厅员工卡的「运行前预检」已从折叠式控件改为常驻可见中文预检区，刷新使用 icon-only 按钮和中文无障碍说明；默认卡片只展示员工、产品、抽象执行位置、来源、权限、风险和结论，不展示绝对路径、底层 CLI 参数或提示词原文；显式「预检」按钮继续写入完整审计日志，默认卡片不再使用“展开后生成”等折叠语义。
- 终端大厅二级详情统一走单一 `TerminalHallDetail` 路由和一处 `.sheet(item:)`；架构体检、通信网关和本地维护的顶部按钮、摘要卡按钮、整卡点击和辅助功能动作都必须写入同一详情状态，不能再为某个详情新增第二个 sheet modifier，避免 macOS SwiftUI sheet 互斥导致真实点击失效。
- 终端大厅详情 sheet 必须使用 MacBook 主屏安全尺寸：不能再把最小宽度钉死到 1080；应使用小于 1000 的最小宽度并保留 1080 左右的理想宽度，确保 MacBook 主屏 Computer Use 验证能真实打开 `OPCTerminalHallDetailSheet`，大屏仍保持原有阅读密度。
- 接口聊天和运行健康的默认可见日志只展示产品语义：接口聊天可以显示「接口聊天」「接口模型」「受控配置」，不能把 `POST`、接口地址、原始模型字段或 `model:` 这类请求细节写进普通可见日志；运行健康使用「运行来源 / 来源配置 / 来源漂移」，不再把“后端配置 / 后端漂移”作为老板或技术负责人默认可见词。
- 老板侧紧凑标题和列表计量继续收敛：右侧老板检查器标题只显示当前产品与阶段，不重复老板职责；产品任务隐藏计数统一用「项」；员工工作区和维护中心默认可见文案不再说明本地会话日志存储机制。
- 老板侧列表和产品记忆默认显示已统一到 Store 层上限和 overflow accessor：员工执行进度、近期任务、近期汇报、紧凑汇报、产品详情记忆和维护中心记忆都用同一类「后续还有…」footer，不再静默截断，也不引入折叠隐藏。
- 老板总控台和流程图默认列表继续治理：待处理审批/风险任务、交付验收、任务推进、风险与批准、验收标准、流程图协作消息和任务状态列都通过 Store 层命名上限和 overflow footer 表达「后续还有…」，不再在默认老板视图静默丢掉后续项。
- 交付验收中心和老板决策中心也已对齐：sheet 内各 section 的数量徽标、列表上限和「后续还有…未显示」提示保持一致；待审批和风险任务在老板决策中心保持完整列表，不因统一样式被裁剪。
- 终端大厅二级详情继续治理：通信网关最近通信、技术维护审计中心和维护产物档案都改用 Store 层命名上限、可见列表和「后续还有…未显示」footer；默认文案表达后续记录会继续浮现，不再只写“最多展示”造成静默截断。
- 老板决策中心继续接收原风险审批中心的有效职责：真实可达的老板决策 sheet 已新增「风险事件」区，使用当前产品过滤后的老板风险事件和 Store 层 overflow，不把命令行维护类风险带进老板决策入口，也不把旧未挂载内部中心作为产品能力来源。
- 老板汇报中心也已迁入真实总控台：「汇报交付」页新增老板汇报中心入口和 sheet，复用当前产品老板报告/报告事件 accessor 与 Store 层 overflow；生成的老板报告把绝对目录和终端输出改写为「本地工作区」和「员工状态」，避免把后台字段当成老板汇报内容。
- 高级控制台历史壳层、旧叶子视图和孤立 helper 已清理：未挂载的 `AdvancedCommandCenter`、`AdvancedConsoleIntro`、`OperatorDisclosure`、旧分组 wrapper、17 个无入口 leaf view、12 个只服务旧 leaf 的 helper 以及旧流水线卡片 `PipelineStepCard` 已删除；真实可达的终端大厅详情中心、老板决策中心、老板汇报中心和员工工作台 helper 继续保留，后续清理必须以可达性和职责边界为准。
- 旧自动流水线 Store API 已清理：`startAutomatedPipeline`、`advancePipeline`、`clearPipelineTasks`、`runPipelineExecutableAgents` 和流水线员工通知 helper 没有真实产品入口，已删除；`runTaskOwner` 作为员工工作台真实执行入口保留；旧 `流水线 ` 任务前缀继续用于历史运行数据清理。
- 旧高级控制台 Store API 第二批已清理：旧分支执行、旧售前方案工厂、旧角色包直接套用、旧工作队列恢复按钮和公开自动交互 wrapper 没有真实产品入口，已删除；当前保留 `runCTOAutopilot`、`runTaskOwner`、`requestCTOReview`、`seedStandardTaskTemplates` 等真实调度/验收入口。交付物分类也随之移除旧「售前方案交付物」精确标题，只保留真实可生产的验收产物/验收报告前缀与项目扫描动态交付证据。
- 产品详情里的技术负责人入口已收敛为老板视角：header 只保留「让技术负责人推进一次」，会自动执行团队、队列、验收、记忆和协作链路推进；点击后按钮会进入「正在推进」禁用态并显示中文进度提示，完成后显示「技术负责人已完成本次推进。」；协作面板空状态保留「启动技术负责人协作」作为初始化入口；原本默认可见的「推进技术负责人循环」手动按钮已移除，底层 `advanceCTOSupervisorLoop` 仅作为 CTO 内部推进能力保留。只测试调用的 `workOrderPrompt(for: taskID:)` 包装重载也已删除，真实任务执行继续使用 `workOrderPrompt(for: task:)`。
- 产品记忆自动记录已增加短期去重和维护清理：同一产品在 1 小时内重复捕获相同状态摘要前 200 字时不会反复写入「自动记录」摘要；技术维护中心提供自动摘要去重预览和二次确认清理按钮，可显式移除既有重复旧摘要并保留每组最新一条；不同产品、不同摘要内容或超过 1 小时后的新摘要仍会正常沉淀，手动记忆入口不受影响。
- 闭环演练证据已和老板真实交付/协作/事件视图隔离：演练任务、验收报告、门禁、员工协作消息和事件继续完整保留在闭环追踪中，但默认交付验收、老板事件和近期协作视图不再显示 `[演练]` 或「闭环演练」记录，避免演练证据冒充真实业务交付。
- 员工工作台具备收件箱、个人审查队列、返工队列和员工交接入口。
- 支持持续协作的员工可以优先接入真实终端工作区席位执行任务；命令发送、单行字面量输入、输出捕获、超时中断和窗口关闭已收敛到按产品和员工隔离缓存的专用持久终端会话抽象，退出码、输出、作业档案和验收链路仍由 OPC 统一记录。没有可用终端席位时回退到一次性命令行。
- 一次性命令行员工的 `HOME`、`XDG_CONFIG_HOME`、`XDG_CACHE_HOME` 和 `XDG_DATA_HOME` 会重定向到当前产品执行目录，避免自定义命令默认读写用户真实 Home。
- 产品可显式开启严格沙盒；开启后一次性命令会通过系统沙盒保护用户 Home 下的敏感目录，同时保留当前产品根目录读写能力。默认关闭，避免影响现有 CLI 登录态和老板工作流。
- Codex / Claude Code / Gemini 的命令行续跑协议第一阶段已接入：当 OPC 从命令行输出中识别到明确会话 ID 后，会按产品分别保存到该员工的运行档案；后续同员工、同产品、同后端配置的任务会使用对应命令行工具的续跑参数接回上下文，切换到其他产品不会复用或覆盖原产品会话；不会使用可能串线的“最近一次会话”选择。
- Codex / Claude Code / Gemini 的长期会话交互协议画像已接入：系统集中记录各命令行工具的协议形态、会话模式、会话编号字段、可配置编号格式、就绪/本轮结束/忙碌/授权异常/临时异常信号和建议超时；运行前预检用中文摘要展示。系统已具备第一版交互状态观察器，可把输出归类为可继续交互、等待回复、本轮结束、忙碌、授权异常或临时异常；员工任务结束后会把观察结果写入运行会话档案，并在状态变化时写入终端日志中文摘要。任务是否完成仍以退出码和 OPC 作业边界为准，状态观察不改变退出码、不自动重试、不自动向命令行续写输入。真实终端席位的轮询会同时观察命令行状态和 OPC 退出标记：看到会话编号、就绪提示或忙碌提示只更新诊断，不会误判任务完成；长输出场景已扩大终端历史捕获窗口，避免作业边界标记被滚动输出冲掉。授权异常和忙碌状态会阻止系统在失败后进行无意义的自动重开，但不阻止老板或技术负责人再次手动运行任务；用户重新完成命令行工具登录后，下次手动任务输出会重新探测并解除异常状态。续跑失败会按产品累计并在连续失败后清理旧会话，避免过期会话反复重试。
- 命令行交互状态观察器已区分普通就绪/结束信号与授权、忙碌、临时异常等诊断信号：就绪和结束仍按协议画像识别；异常类信号只在错误前缀、授权失败、额度/忙碌、网络/超时等诊断语境行内匹配，并跳过路径、文件名和标识符里的关键词，避免普通提示词回显或路径名里的 timeout/network/429/busy 被误判为真实异常。
- 持久终端执行已增加未完成任务守门和超时中断升级：同一真实终端席位仍存在未闭合 OPC 任务 marker 时会拒绝覆盖发送；超时后会停止等待，先发送普通中断，再尝试强中断，仍未闭合时关闭未响应的终端席位，下次运行重新创建席位。
- 持久终端会话的输入路径分工明确：完整任务提交继续走带 OPC marker、超时中断和作业档案的命令执行路径，但真实终端 pane 只接收 `/bin/sh runner` 短命令；长 prompt、多行参数和 marker wrapper 写入产品内 `.opc/runtime/terminal-runners/` 一次性 runner 脚本，runner 目录强制 0700、执行后自清理、启动前清理陈旧脚本，避免长命令在 zsh 触发 file-name-too-long 或两步发送竞态导致整套测试失败。单行字面量输入仍只用于向正在运行的长期席位注入一行 stdin，底层使用 tmux `load-buffer` + `paste-buffer -d` 原子粘贴，不写 marker、不写作业档案，并且不影响同一席位上完整任务的 marker 检测和超时中断。
- 手动交互轮次原语已按命令行协议画像扩展到 Codex / Claude Code / Gemini，并接入终端大厅/技术负责人维护区的中文产品入口：技术负责人可以在维护区选中员工，输入一行内容后由 OPC 明确发起；发送前必须先观察到对应工具的独立行就绪提示，避免把手动输入误发到普通终端；发送后只观察该输入之后新增的终端输出，按对应画像里的独立行就绪提示（`codex>` / `claude>` / `gemini>`）或本轮结束信号判定本轮完成，并把观察状态写入员工运行档案和终端日志；非交互型、缺少专用就绪提示或席位未就绪的后端会被中文拒绝，等待超时只报告“等待回复”，不自动中断或关闭终端席位；老板总控台不展示该入口；OPC 永远不会自动向会话追加用户未确认的下一轮输入，也不会创建作业档案或启动模型任务。
- 跨命令行工具自动输入循环已具备第一版状态机、执行器、技术负责人内部协调器和真实终端席位入口：自动循环必须由技术负责人在维护区显式启动，必须绑定明确任务上下文，必须设置 1 到 8 轮的最大轮次，下一轮输入必须由 OPC 生成且只能是一行非空文本；执行器在调用发送闭包前复用同一门禁校验，输入不合规时不会调用发送链路；内部协调器只允许当前产品团队中的非老板员工参与，并通过真实终端轮次或测试注入闭包接收观察结果；真实终端路径发送前还会只读预检终端工作区、员工席位和专用就绪提示，未就绪时直接中文拒绝且不消耗轮次；已用 fake REPL + tmux 席位覆盖就绪后真实发送、完成信号停止和无老板聊天/无作业档案副作用；真实终端自动循环会写入独立的「OPC 自动交互循环轮次」终端日志，和人工触发的「OPC 手动交互轮次」区分；一旦观察到授权异常、忙碌、临时异常或等待超时会立即停止并输出中文停止原因。该入口不创建老板入口、不写老板聊天、不创建命令行作业档案、不绕过交付验收。
- 员工恢复建议已接入终端大厅/技术负责人维护区的中文诊断面板：根据最近一次命令行状态观察展示授权异常 / 临时异常 / 忙碌中 / 可继续交互的中文摘要和应对建议；只有「临时异常」会出现一个受控的「手动重试一次」按钮，由技术负责人显式点击触发，授权异常和忙碌仍然继续阻止系统自动重开。该入口不写老板聊天、不写验收记录、不创建作业档案、不向命令行追加任何下一轮输入，老板总控台不展示。
- 持久终端可用性已接入多员工架构体检：技术负责人可在主架构检查里看到终端工具、真实终端会话、控制窗口和员工席位是否齐全；该检查只读，不启动模型任务、不创建作业档案、不修改员工状态，并且架构面板只读取最近巡检/启动后的内存快照，避免界面刷新时反复读取终端状态。
- 通信网关已具备默认通道规划、本地手机指令模拟、就绪通道出站发送、外部双向通道入站守门，以及 HMAC 签名、时间戳、nonce 重放校验和外部 JSON 动作白名单基础件。
- 本地历史索引和旧历史归档表已作为主快照的旁路历史层接入：维护巡检时可重建 `company-history.sqlite3`，用于搜索消息、事件、任务、审批、产物、验收、记忆、通信日志和员工协作消息；归档迁移可把旧消息、旧事件、旧通信日志和旧协作消息复制到本地归档表。主快照仍是权威状态，当前不裁剪主快照。

仍在多 Agent 完整体之外继续推进的长期项：

- Codex / Claude / Gemini 的生产级交互协议适配还需要继续加强；当前已具备真实终端席位复用、明确会话 ID 的 resume 续跑、协议画像、状态观察结果记录、持久终端轮询期状态诊断、诊断语境级异常信号匹配、授权/忙碌状态的自动重开抑制、续跑失败清理、未完成任务守门、长输出边界保护、超时中断升级、专用持久终端会话抽象、安全单行输入基础件、状态观察驱动的中文恢复建议、按画像支持 Codex / Claude Code / Gemini 的手动交互轮次原语、跨命令行工具自动输入循环的安全门禁状态机、自动输入循环执行器的可注入发送闭包安全核心、技术负责人内部协调器，以及技术负责人维护区的真实终端受控循环入口；状态观察已经用于恢复建议、受控临时异常单次重试和受控跨轮循环停止条件，后续还需要继续加强真实模型链路的生产级容错、审计和可视化。
- 通信网关外发已具备本机发送能力；真正暴露公网/局域网入站 HTTP 服务仍必须默认关闭，并在 HMAC、白名单、nonce 和端口策略全部就绪后再打开。
- 本地历史索引当前作为可重建索引和旧历史归档表，不替代主状态；只有当快照体积和查询性能达到阈值时，才考虑从主快照裁剪已归档旧历史。

## 5. 完整体架构

### 5.1 App 层

- SwiftUI：主界面、表单、面板、列表、总控台。
- SpriteKit：2D 公司场景、像素小人、状态动画。
- AppKit Bridge：未来接入 PTY/终端视图、窗口控制和系统能力。

### 5.2 公司业务层

- `CompanyStore`：公司状态、产品状态、员工状态、任务和聊天的主状态容器。
- `ProductWorkspace`：一个产品一个工作区。
- `AgentProfile`：员工档案，包含角色、模型、规则、记忆、外观、权限。
- `AgentWorkspace`：每个员工在每个产品下的工作目录、记忆和产物。
- `AgentRuntimeSession`：员工运行时会话、预热状态、能力、失败重启策略。
- 任务图：任务节点、依赖、分支、审查和验收路径。
- 交付证据库：方案、代码改动、报告、测试结果、截图、交付物。
- `ApprovalCenter`：老板审批、风险放行、权限确认。

### 5.3 多 Agent 架构

OPC 采用“公司层级 + 任务图 + 消息总线”的多 Agent 架构。

```text
老板
  |
  v
技术负责人调度
  |
  +-- 任务图：拆解目标、建立依赖、分支并行
  +-- 员工路由：选择员工和模型后端
  +-- 消息总线：员工之间传递任务、上下文和结果
  +-- 交付证据库：沉淀产物和验收证据
  +-- 验收门禁：审查、风险、老板审批
  |
  +--> 界面设计师
  +--> 代码工程师
  +--> 测试工程师
  +--> 审查员
  +--> 研究员
  +--> 方案顾问
```

关键规则：

- 老板不直接管理复杂任务图。
- CTO 是默认调度者和最终汇报者。
- 员工可以协作，但跨员工交接必须留下消息和产物记录。
- 多分支执行必须可追踪、可回滚、可验收。
- 代码类并行任务最终应使用独立源码执行区或独立目录隔离。

### 5.4 模型和 CLI 后端

- Codex：CTO、架构、审查、复杂判断。
- Claude Code：代码实现、修复、重构、测试。
- Gemini：UI 设计、视觉分析、多模态检查。
- API 模型：批量文本、低成本任务、定制模型、国内模型。

原则：

- 员工角色和模型后端分离，同一个模型可以创建多个员工。
- 普通聊天和工作任务默认使用员工档案里配置的同一个模型，不做隐式低配切换。
- 速度优化优先靠常驻会话、预热、缩短上下文、缓存记忆摘要，而不是偷偷换低版本模型。

## 6. 角色规则

### 老板

老板只需要：

- 设定目标。
- 查看产品状态。
- 审批风险和关键决策。
- 验收最终结果。
- 找 CTO 或员工沟通。

老板不应该被要求：

- 手动拆任务图。
- 手动选择所有分支执行细节。
- 手动判断每个 CLI 后台状态。
- 手动维护每个 Agent 的内部上下文。

### CTO

CTO 必须：

- 把老板目标变成可执行任务。
- 给每个任务定义成功标准。
- 选择合适员工。
- 控制任务依赖和并行分支。
- 汇总员工结果。
- 发起审查和验收。
- 向老板汇报“结果、风险、需要老板决定的事”。

CTO 不应该：

- 把后台细节全部推给老板。
- 用机械模板回复老板。
- 在没有验收证据时说完成。

### 员工 Agent

员工必须：

- 遵守自己的角色档案。
- 只处理被分配或被老板直接问到的事情。
- 输出与角色相关的结果。
- 任务完成后报告产物、修改、验证和风险。
- 和老板聊天时自然简短，不背诵档案。

员工不应该：

- 自作主张改产品方向。
- 把系统提示、CLI 命令、后台日志暴露给老板聊天区。
- 在没有真实模型调用时伪装成真实回复。

## 7. UI 信息架构

### 老板总控台

只展示：

- 产品健康状态。
- 总进度。
- 待老板决策/审批。
- 最近交付和验收。
- CTO 今日汇报。
- 员工工作进度摘要。

不展示：

- 复杂后台按钮堆。
- 重复入口。
- CLI 链路细节。
- 模型调度细节。
- 只有 CTO 才需要看的内部状态。

### 产品详情

展示：

- 产品目标和阶段。
- 当前团队和负责人。
- 任务列表和进度。
- 产物和验收。
- 长期记忆。
- 导入项目和接管状态。

### 员工工作台

展示：

- 员工档案。
- 模型/后端/推理强度。
- 当前任务。
- 工作队列。
- 记忆和技能。
- 会话状态。
- 与老板沟通。

### 公司场景

展示：

- 老板办公室。
- 技术负责人办公室。
- 当前产品团队工位。
- 每个小人的状态动画。
- 空工位新增员工。
- 点击员工只查看状态和沟通，不默认跳复杂后台。

### 终端大厅

展示：

- 每个 CLI 员工的终端状态。
- 正在运行的任务。
- 必要的输出摘要。
- 真实日志应在终端大厅，不进入普通聊天区。

## 8. 数据和文件规则

### 本地状态

当前使用：

```text
~/Library/Application Support/OPCCompany/company-state.json
~/Library/Application Support/OPCCompany/products/
```

长期目标：

```text
.opc/
  products/
  agents/
  jobs/
  artifacts/
  memory/
  approvals/
  events/
```

当前已落地 `.opc/jobs/` 命令行作业档案和 `company-history.sqlite3` 历史查询索引；其余子目录仍作为后续持久化迁移目标，不阻塞本轮多 Agent 协作链路。

历史数据策略：

- 主快照仍是权威状态，便于本地备份、检查点和回滚。
- 本地历史索引先作为可重建索引层，覆盖任务、聊天、事件、产物、验收、记忆、通信日志和员工协作消息。
- 后续只有当主快照超过明确体积阈值或加载/搜索性能下降时，才考虑裁剪已归档旧历史。

### 项目导入

导入已有项目时，OPC 必须读取并尊重：

- `AGENTS.md`
- `CLAUDE.md`
- `.codex/`
- `.claude/`
- 项目 README、规则和记忆文件。

导入后应创建：

- 产品工作区。
- 默认团队。
- 产品记忆摘要。
- 当前风险和可执行任务建议。

### 项目内执行记忆

这些规则只适用于本项目，不写入全局长期记忆。

- 使用 Claude Code 时可以多分配任务，但必须同时优化 Claude Code token 使用量。
- 给 Claude Code 的任务应保持窄边界：一句 Objective、明确 Scope、可机械识别的 Constraints、具体 Done when、明确 Stop if。
- 不把整段长历史、无关日志、大范围代码上下文或宽泛“全部优化”目标塞给 Claude Code；优先给它必要文件路径、目标函数、失败命令和期望输出格式。
- 任务难度与上下文预算要匹配：简单只读复核用短 prompt 和低上下文；实现任务给最小可写范围；复杂架构判断再提供方案背景。
- Claude Code 出现 busy 时先判断是否正常执行；正常忙不打断，异常空转、登录阻塞或补全缺口时，让 Claude Code 自己补全或拆小任务续跑。
- 目标是在保证质量和能力不下降的前提下，提高 Claude Code 接任务数量和有效产出，避免把 token 花在重复叙述、无关历史和过宽任务边界上。
- 2026-05-07 起，用户的 Claude Code 可用量按 Max 5x 套餐和官方新增额度策略评估，后续 goal-loop 默认提高 Claude Code 分支占比：优先把窄范围只读审计、候选缺口定位、局部实现方案和测试失败归因交给 Claude Code；Codex 保留 CTO 切分、最终代码复核、全量测试、bundle 构建和 MacBook 主屏 Computer Use 验证职责。
- 2026-05-07 起，goal-loop 不允许自行扩大问题，不允许重复修复已经达到正式使用标准的功能，也不允许为了维持循环而强行挑低价值问题消耗 Codex 或 Claude Code。后续只能处理正式使用阻塞项、明确验证缺口或用户点名的问题；已经可用且测试/实测通过的能力应停止继续打磨。
- 2026-05-07 起，goal-loop 达到「可正式使用」阶段后不能立刻结束：必须进入一次全局代码审计与功能审计，覆盖代码质量、代码优化、测试代码、无用代码、代码 bug、漏洞、安全性，以及功能可用性、逻辑性、联动性和必要压力测试。所有检查完成后，只对审计发现的真实问题进行全面修复；审计和修复不得变成对已达标功能的重复打磨或无边界扩大。

## 9. 安全和权限规则

当前用户希望大多数本地执行不要频繁弹授权，但产品仍必须保留风险边界：

- 普通读文件、分析、生成方案可以自动执行。
- 写代码、运行测试、生成产物可以按产品权限执行。
- 删除文件、重置 Git、覆盖重要文件、联网发布、安装依赖、系统级权限必须进入审批。
- API Key 必须进入 Keychain，不能明文保存在聊天、日志或 JSON 状态里。
- 员工不能越过产品根目录随意读写无关目录，除非老板授权。

## 10. 通信网关

通信网关的目标是让老板不在电脑前也能收到汇报和下达任务。

当前正式使用目标是单人本地化使用，通信网关移动端联动、公网/局域网入站服务和外部 HTTP 服务不作为正式使用阻塞项；这些能力保持默认关闭或仅本地模拟，后续由实际使用体验决定是否完全实现。

当前实现状态：

- 出站汇报：已支持本地生成、就绪通道发送和失败记录；飞书、企业微信、钉钉、Telegram、邮件日报使用统一请求预览和调度器。
- 入站指令：已支持本地指挥台模拟和外部双向通道守门；指令只会进入通信日志、通知团队负责人并创建可追踪任务，不直接执行命令。
- 安全基础件：已具备 HMAC-SHA256 签名、时间戳窗口、nonce 重放校验和外部 JSON 动作白名单；真正外部 HTTP 入站服务默认关闭，后续必须加端口策略和显式启用开关。
- 审批消息：仍通过老板决策中心和结构化审批记录闭环，不允许远程指令绕过审批。

实现原则：

- 默认本地运行，不依赖云端托管。
- 需要外部平台 API 时，由老板明确配置 Token/Webhook。
- 所有远程指令必须标记来源，并进入事件日志。
- 外部地址或机器人 token 不得写入老板汇报、事件明细或错误日志；错误只显示脱敏后的主机级地址。

## 11. 变更记录

### 2026-05-07 终端日志按当前产品隔离

- **方向**：修复终端大厅按员工全局显示日志的问题。同一个员工服务多个产品时，切回默认产品不应看到其它产品的终端片段、聊天运行摘要或旧工作区上下文。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyPersistence.swift`：快照新增 `productTerminalLogs`，以 `productID:agentID` 存储产品级终端日志；旧 `terminalLogs` 继续作为兼容归档字段。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：预检、真实运行、聊天、API 聊天、预热、终端工作区刷新、清空日志和状态摘要统一读写当前产品日志；加载旧状态时尽量按日志中的产品名迁移旧日志，避免未识别旧日志污染其它产品视图。
  - `Sources/OPCCompanyCore/SelectionWorkspaceView.swift`：员工工作台运行状态改读当前产品日志。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `visibleTerminalLogIsScopedToSelectedProductForSameEmployee`，守门同一员工跨产品日志互不串台，且清空当前产品日志不影响其它产品。
- **验证**：定向 `swift test --no-parallel --filter 'visibleTerminalLogIsScoped|visibleTerminalLog|terminalAgentCard'` 25 项通过；全量 `swift test --no-parallel` 567 项通过。

### 2026-05-07 终端大厅运行成本与多员工确认收紧

- **方向**：修复终端大厅「运行全部」只在默认提示词时二次确认的问题。用户改写提示词后仍可能一次触发多名员工真实命令行运行并消耗额度，必须按影响范围而不是按提示词内容确认。
- **实施**：
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：`运行全部` 改为只要当前会发送给 2 名及以上可执行员工就弹确认；确认文案和主按钮显示员工数量；提示词输入框下方新增常驻「外部调用 / 额度」提示；员工卡的「预检」改为「预检 · 干跑」，hint 明确不调用真实模型、不消耗额度。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增/更新运行全部多员工确认与常驻额度提示守门，防止确认条件再次绑定默认提示词。
- **验证**：分支定向测试 `terminalHallRunAllMultiAgentRequiresTokenConfirmation`、`terminalHallExternalCallNoticeAlwaysVisibleNearPrompt` 随全量测试验证。

### 2026-05-07 本地维护危险动作专属确认词

- **方向**：修复本地维护区 cleanup/reset/rollback 共用「确认」导致误触和动作间肌肉记忆穿透的问题；历史归档迁移虽不删除文件，但会写入审计/消息，也不应单击即执行。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：危险动作改为动作专属确认短语：`清理运行数据`、`恢复默认公司`、`回滚最近检查点`；输入框 placeholder、执行启用条件与 accessibility hint 统一由 action 语义驱动；「运行历史归档迁移」改为二次点击确认。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：更新危险动作确认面板守门，新增专属短语互斥、禁止回退通用「确认」、placeholder/hint 同步和历史归档迁移二次确认守门。
- **验证**：Claude Code 分支定向运行 `swift test --no-parallel --filter 'localMaintenance|historyArchiveMigration|dangerous|Dangerous|HistoryArchive'`，17 项通过；全量测试随本轮收尾执行。

### 2026-05-07 右侧员工沟通按当前产品隔离

- **方向**：修复真实使用时切换/新增产品后，右侧员工沟通栏仍显示旧版全局消息、旧产品报告或旧 Desktop 工作区信息的问题。老板视角只应看到当前产品上下文，旧消息不能被误读为当前产品状态。
- **实施**：
  - `Sources/OPCCompanyCore/InspectorPanel.swift`：员工沟通列表改为严格读取 `selectedProductID` 下的消息，并关闭 legacy nil 全局消息 fallback；无当前产品对话时显示明确空状态。
  - `Sources/OPCCompanyCore/InspectorPanel.swift`：终端 tab 只在终端大厅显示；常驻 header 在非终端大厅不再暴露 backend / command / model 三元组；任务/事件 tab 改为当前产品 + 当前员工作用域，避免老板视图旁边混入全员或跨产品信息。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `inspectorChatUsesStrictSelectedProductMessagesAfterLambdaPhaseFive`、`inspectorHidesBackendAndTerminalControlsOutsideTerminalHallForBossFacingWorkspaces`、`inspectorTasksAndEventsAreScopedToSelectedAgentInSelectedProduct` 守门，防止右侧常驻 Inspector 再次泄漏跨产品消息、终端入口或后台配置细节。
- **验证**：随本轮全量 `swift test --no-parallel` 验证。

### 2026-05-07 产品设置编辑入口与新增产品目录修正

- **方向**：修复产品详情里产品名称无法修改的问题，并继续收紧新增空产品目录策略，避免空产品仍以 Desktop 目录作为工作区。
- **实施**：
  - `Sources/OPCCompanyCore/SelectionWorkspaceView.swift`：产品详情 header 新增「编辑产品」入口；设置 sheet 支持修改产品名称、侧栏简称、本地工作区，并提供「使用 OPC 内部工作区」和「选择现有目录」两个明确动作。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增 `updateProductSettings` / `updateSelectedProductSettings`；保存时更新名称、简称、工作区、员工工作区档案和运行会话缓存；新增空产品改用按产品 ID 生成的 OPC 内部目录。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增产品设置保存、空名称/空目录拒绝、产品详情编辑入口和默认内部目录守门。
- **验证**：定向测试 `productSettingsCanRenameAndMoveProductToInternalWorkspace`、`productDetailExposesProductSettingsEditor`、`defaultProductRootsStayInsideOPCApplicationSupport` 通过；全量测试随本轮收尾执行。

### 2026-05-07 默认产品工作区移出 Desktop 权限域

- **方向**：修复运行时反复弹出 macOS Desktop 文件访问授权的问题。默认产品和新增空产品不应默认把根目录放在 `~/Desktop`，只有用户显式导入 Desktop 下真实项目时才应触发系统授权。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyPersistence.swift`：新增 `productWorkspacesURL`，默认产品工作区统一放到 `~/Library/Application Support/OPCCompany/products/`。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：默认产品、新增产品、恢复默认公司状态都使用 OPC 内部产品工作区；加载旧快照时把旧版默认 `~/Desktop` / `~/Desktop/OPCProductN` 根目录迁移到内部工作区；显式导入项目不迁移。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增默认/新增/重置产品根目录守门，以及旧 Desktop 默认路径迁移但显式导入路径不改写的守门。
- **验证**：定向测试 `bootstrapCreatesProductWorkspaces` 通过；新增权限路径守门会随全量 `swift test --no-parallel` 验证。

### 2026-05-07 文档基线与本地清理边界同步

- **方向**：把接管期、正式使用基线、单人本地边界、通信网关暂缓项、SQLite 历史旁路策略、多产品工作区状态和终端大厅产品化状态同步到项目文档，避免后续 agent 继续按旧任务卡或旧接管记录执行。
- **文档变更**：
  - `AGENTS.md` / `CLAUDE.md`：确认当前为单人本地正式使用基线，后续只能做有边界的维护、真实缺陷修复或用户明确需求；`swift test --no-parallel` 是非平凡代码变更的默认全量验证。
  - `docs/RUNBOOK.md`：补充安全清理边界，明确 `.build/` 是可删除缓存；`Tests/`、`dist/OPCCompany.app`、`.claude/`、`.ccb/`、项目文档和真实 App 支持目录默认保留。
  - `docs/IMPLEMENTATION_PLAN.md`：从首轮实现任务卡改为当前维护计划；历史首构建目标仅保留为归档。
  - `docs/CLAUDE_CODE_HANDOFF.md`：标记为历史交接档案，不再作为新的任务入口。
  - `docs/COMMUNICATION_GATEWAY_SECURITY.md` / `docs/HISTORY_ARCHIVE_RFC.md` / `docs/MULTI_PRODUCT_WORKSPACES.md` / `docs/TERMINAL_HALL_DESIGN.md` 等专题文档同步 2026-05-07 当前状态。
- **清理结果**：已删除 `.build/` Swift 可再生构建缓存；未删除 `Tests/`、`dist/OPCCompany.app`、`.ccb/`、`.claude/` 或真实本地产品状态。
- **验证**：文档一致性检索已覆盖旧日期、旧“建议新增”语气、旧首构建标题、旧 `swift test` 验收写法和默认可见中英混排示例。文档变更不运行 `swift test`，避免刚清理的 `.build/` 被重新生成；代码验证基线仍以本日最新 `swift test --no-parallel` 555/555 和 bundle `20260507033423` 为准。

### 2026-05-07 员工 agent token 预算二次收口

- **方向**：把本轮 goal 中“各个 agent 的 token 最大优化”作为硬性验收项处理，但不通过降低模型、裁剪真实用户任务正文或隐藏必要信息来省 token。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：结构化员工协作消息 `postAgentMessage` 入口统一裁剪超长 subject/body，避免审查结论、验收标准、报告正文或交接说明变成第二份无限上下文；完整长内容应进入产物、员工工作区或审计档案，消息总线只保留摘要。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：长期 CLI 会话续跑时不再重复发送完整员工操作档案，只发送本轮任务和一行上下文提示；首次运行仍保留员工档案，产品级 session resume 和后端隔离不变。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：员工执行 prompt 不再重复列出 `AGENTS.md` / `SOUL.md` / `MEMORY.md` / `SKILLS.md` / `WORKSPACE.md` 文件清单，减少与 CLI 自动读取规则文件的重复 token；员工档案文件同步改成内容变化才写，未变化时不刷新 mtime。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：终端大厅「运行全部」在“默认汇报提示词 + 多名员工可运行”时先弹出中文确认，避免误点一次消耗整支团队命令行额度；确认后仍走原运行路径，不禁用工作流。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 与 `docs/RUNBOOK.md`：新增协作消息、续会话、首轮执行 prompt 和员工档案同步的 token 预算守门。
- **验证**：token 预算新增目标测试 5/5 通过；既有 prompt token 预算目标测试 4/4 通过；既有产品级 CLI resume 隔离测试继续通过；全量 `swift test --no-parallel` 555/555 通过。`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，bundle version `20260507033423`，`codesign --verify --deep --strict dist/OPCCompany.app` 通过。Computer Use 已在 MacBook 主屏验证最新 bundle：老板总控台可打开，汇报交付页显示老板汇报中心且风险段为「暂无近期风险」；终端大厅可打开，摘要工作台、运行前预检、四个员工卡和运行按钮可见；点击默认提示词下的「运行全部」会先出现「确认运行全部员工终端」弹窗并提示会消耗多名员工命令行额度，取消后没有启动员工任务。Claude Code 2.1.132 已更新确认，并完成只读 token 审计；Codex 复核后落地不牺牲能力的高信号项。
- **边界**：不禁用现有命令行入口，不改变员工模型配置，不裁剪当前用户任务正文，不把通信网关移动端联动或发布上架链路纳入本轮阻塞项。

### 2026-05-07 侧边栏产品删除确认补齐

- **方向**：继续按单人本地正式使用标准处理真实阻塞项。R3 审计发现产品详情页删除产品已经有确认弹窗，但左侧产品列表右键菜单仍可直接调用 `deleteProduct`，属于同一危险动作的确认缺口。
- **实施**：
  - `Sources/OPCCompanyCore/ContentView.swift`：`ProductWorkspaceList` 新增 `pendingDeletion: ProductDeletionRequest?`，右键「删除产品」只生成待确认请求；真正删除移动到 `confirmationDialog` 的 destructive 确认分支，取消会清空请求。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `productSidebarContextMenuUsesDeletionConfirmationInsteadOfDirectDelete` 源码守门，禁止侧边栏右键菜单重新出现 `store.deleteProduct(product.id)` 直删路径。
- **验证**：侧边栏删除确认目标测试 4/4 通过；全量 `swift test --no-parallel` 550/550 通过。Claude Code 2.1.132 只读复核在单人本地正式使用范围内未发现其他阻塞项；Codex 额外交叉审计补齐此侧边栏直删缺口。
- **边界**：不改变 `deleteProduct` 的清理语义，不执行真实删除，不处理通信网关移动端联动、分发签名、公证、更新机制或泛 UI 打磨。

### 2026-05-07 老板报告风险源收口 + 员工 prompt token 预算边界

- **方向**：按单人本地正式使用标准继续处理真实阻塞项，不扩大成泛泛优化。本轮收口两类高信号问题：老板报告/团队负责人汇报不能把维护类风险写给老板；各员工 prompt 不能因长历史、长记忆或长档案无上限膨胀 token。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`generateBossReport()`、`sendTeamLeadReportThroughGateway()`、`dispatchTeamLeadReportThroughGateway(session:)` 和外部状态查询报告里的风险段改用 `selectedProductBossRiskEvents`，与老板首页、老板决策中心和老板报告中心的维护风险过滤口径一致；命令行作业等纯维护风险不再进入老板/团队负责人汇报，老板动作被阻止等业务风险继续保留。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增集中 prompt 片段裁剪规则；员工聊天 prompt 会裁剪最近聊天、记忆片段、当前聊天文本和聊天修正草稿；员工执行 prompt 的档案块会裁剪使命、职责、边界、回复规则、长期记忆、当前产品员工记忆和技能摘要，并用「还有 N 项已保存在员工档案」提示保留追踪语义。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`workOrderPrompt(for:)` 只保留导入报告中的少量规则、工具和项目文件线索，并裁剪长路径、长验收标准和长条目；审查员/老板打回返工生成的系统 prompt 裁剪长原因和长成功标准，避免系统生成内容放大每个员工命令行调用的 token。
  - 当前执行任务正文 `agentExecutionPrompt(... userPrompt:)` 不裁剪，避免为了省 token 截掉真实工作指令；完整员工配置和记忆仍保留在员工工作区文件中。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 与 `docs/RUNBOOK.md`：新增 token 预算边界守门和运行说明。
- **验证**：`generateBossReportUsesBossFacingWorkspaceAndEmployeeStateCopy`、`communicationGatewayCreatesChannelsAndRoutesMobileCommand`、`communicationGatewayExternalInboundRequiresWhitelistedJSONAction` 3/3 通过；聊天 prompt 相关目标测试 4/4 通过；员工档案 prompt / 记忆 / 工作区相关目标测试 4/4 通过；工单/返工 prompt token 预算目标测试 4/4 通过；全量 `swift test --no-parallel` 549/549 通过。`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，bundle version `20260507025429`，`codesign --verify --deep --strict dist/OPCCompany.app` 通过。Claude Code 2.1.132 只读复核确认本地维护三项危险动作无旧弹窗/二次点击残留，并确认 token 预算边界未裁剪当前执行任务正文；后续交叉审计补齐当前产品员工记忆、工单导入清单和返工 prompt 的裁剪守门。Computer Use 已在 MacBook 主屏验证最新 bundle：老板总控台/汇报交付可打开，老板报告风险段显示「暂无近期风险」；终端大厅可打开，摘要工作台、员工卡、运行前预检和稳定锚点可见。
- **边界**：不降低员工模型、不改变员工配置、不裁剪当前执行任务正文、不把通信网关移动端联动纳入正式使用阻塞。

### 2026-05-07 正式使用阶段全局审计第一批高优先级修复

- **方向**：进入「可正式使用后全局代码审计与功能审计」阶段后，只处理真实风险，不扩大到低价值打磨。本批收口 5 个高信号问题：产品删除无确认、CLI 超时后可能永久 busy、Keychain 默认可访问策略、消息气泡角色错标、危险维护动作长期停留二次确认态。
- **实施**：
  - `Sources/OPCCompanyCore/SelectionWorkspaceView.swift`：删除产品按钮改为先生成 `ProductDeletionRequest` 并打开系统确认对话框；只有 destructive 确认分支才调用 `store.deleteProduct`，单产品禁用条件不变。
  - `Sources/OPCCompanyCore/CLIAgentRunner.swift`：`runStreaming` 超时后先发 SIGTERM，再按 `terminationGraceSeconds` 升级 SIGKILL；超时路径跳过可能被孤儿子进程管道写端阻塞的 trailing drain，保证调用方拿到 124 并解除 busy。
  - `Sources/OPCCompanyCore/KeychainStore.swift`：Keychain 写入/读取/删除显式关闭同步，并把 API Key 新增/更新为 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。
  - `Sources/OPCCompanyCore/InspectorPanel.swift`：消息气泡按 `agentID` 对应角色显示「技术负责人 / 老板 / 员工」，不再把 CTO 回复统一标为「员工」。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：清理运行数据、恢复默认公司状态、回滚安全检查点改为常驻可见确认区；每个危险动作都必须先在独立输入框输入「确认」才会启用执行按钮，「取消」只清空输入并重新禁用执行按钮，不再依赖 macOS 系统确认弹窗或点击后展开的短暂状态。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 与 `docs/RUNBOOK.md`：补齐对应契约测试和维护锚点说明。
- **验证**：
  - Claude Code 负责产品删除确认和 CLI SIGKILL 升级两项窄范围实现，并分别跑通目标测试 4/4、7/7；Codex 复核后补齐 Keychain、角色气泡和危险维护确认修复。
  - 合并目标测试通过：Keychain/删除确认/CLI 强杀/角色气泡/维护确认相关 9/9 与 6/6 均通过。
  - 常驻确认区目标测试 `localMaintenanceDangerousActionsUseVisibleConfirmationPanelInsteadOfStickySecondClick`、`localMaintenanceCenterDetailActionButtonsExposeStableAccessibilityIdentifiers`、`uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 3/3 通过；全量 `swift test --no-parallel` 543/544，通过失败项为既知 tmux 时序用例 `persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection`，该用例单独复跑 0.760s 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，bundle version `20260507020509`，`codesign --verify --deep --strict dist/OPCCompany.app` 通过。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：终端大厅本地维护二级详情可打开，三个危险动作的常驻确认区、输入框、取消按钮和执行按钮均暴露稳定锚点；执行按钮默认禁用，输入「确认」后对应执行按钮启用，点击「取消」会清空输入并重新禁用；验证过程中未执行真实危险维护动作。
- **边界**：不处理通信网关移动端联动；不改外部分发、签名、notarization、更新机制；不把审计扩展成无边界 UI 打磨。通信网关 nonce 顺序、SQLite rollback 二次失败、历史索引 task 时间戳等审计发现按当前单人本地正式使用口径暂不列为本批阻塞，后续只在真实使用或用户点名时单独处理。

### 2026-05-07 终端卡片清空日志禁用状态去文案耦合

- **方向**：继续处理正式使用审计中剩余的真实小缺口。终端大厅员工卡片的“清空日志”按钮不能靠 `visibleTerminalLog` 的中文 fallback 文案判断是否禁用，否则后续中文文案调整会误伤按钮行为。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增 `terminalAgentCardHasClearableLog(for:)`，以原始 `terminalLogs` 是否为空作为唯一业务判断。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：清空日志按钮改为 `.disabled(!store.terminalAgentCardHasClearableLog(for: agent.id))`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：补齐 idle/active/清空三态断言，并加源码反向锁，禁止回退到 `logText == "暂无终端输出。"`。
- **验证**：目标测试 `terminalAgentCardLogHeightShrinksWhenIdleAndExpandsWhenActive`、`terminalAgentCardViewUsesAdaptiveLogHeightInsteadOfHardcoded248`、`terminalAgentCardCoreActionButtonsExposeStableAccessibilityIdentifiers` 3/3 通过；全量 `swift test --no-parallel` 544/544 通过；`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，bundle version `20260507004005`，`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过；Computer Use 已在 MacBook 主屏验证最新进程 `58126` 的终端大厅可见，员工卡片清空日志按钮在有真实日志时保持可用，并暴露中文 `OPCTerminalAgentCardClearLogButton` 描述和帮助。

### 2026-05-07 API Key 写入 Keychain 失败显式上报

- **方向**：收口正式使用前最后一类敏感配置静默失败风险。API 员工的 Key 必须进入 Keychain；如果 Keychain 被锁、权限受限或 SecItem 写入失败，系统不能在快照前清空明文副本后让老板无感丢 Key。
- **实施**：
  - `Sources/OPCCompanyCore/KeychainStore.swift`：`OPCKeychainStore.saveAPIKey(_:agentID:)` 改为返回真实 `OSStatus`；首次写入走 `SecItemAdd`，并显式处理 `errSecDuplicateItem` 竞态；空值返回 `errSecParam`。
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增可注入 `keychainSaveAPIKey` 闭包；`hydrateAPIKeysFromKeychain` 和 `agentsForSnapshot` 统一走 `writeAPIKeyToKeychain`；非成功状态写入 in-memory `.risk` 事件「API Key 写入 Keychain 失败」，同员工同状态相邻去重，不递归保存。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：补齐失败事件、相邻去重、成功路径、空值安全返回和源码契约测试；Runbook 说明事件只在内存中提示、快照仍不保存明文 Key。
- **验证**：
  - Claude Code 负责窄范围实现；Codex 复核确认测试不触碰真实 Keychain，且 `agentsForSnapshot` 只清空快照副本、不清空运行期主数组。
  - 定向测试 `keychainSaveAPIKeyFailureDuringSnapshotAppendsInMemoryRiskEvent|keychainSaveAPIKeyAdjacentFailuresDeduplicateInEventStream|keychainSaveAPIKeySuccessLeavesEventStreamAndAgentApiKeyUntouched|opcKeychainStoreSaveAPIKeyEmptyValueReturnsErrSecParamWithoutSecItemCall|keychainStoreAndCompanyStoreSurfaceKeychainFailureSourceContract|apiEmployeeRequiresAndStoresApiConfiguration|apiCommandUsesApiRunnerAndDoesNotExposeApiKey` 7/7 通过。
  - 全量 `swift test --no-parallel` 537/537 通过。
- **边界**：不改 Keychain UI，不改 API 员工配置界面，不把 API Key 写入 JSON、聊天、日志或测试真实 Keychain；通信网关移动端联动不纳入本轮。

### 2026-05-07 本地维护详情页动作补齐稳定 Computer Use 锚点

- **方向**：终端大厅进入本地维护详情后，维护巡检、真实终端工作区、历史索引/归档迁移、异常会话恢复和危险二次确认按钮必须能被 Computer Use 稳定定位；不能只停留在摘要卡主操作层。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增本地维护详情页动作按钮 identifier，覆盖命令行隔离体检、真实终端工作区启动/日志刷新/可用性巡检、会话健康、员工交接、作业幽灵、历史索引、历史归档迁移、异常会话恢复、运行数据清理、恢复默认公司状态和安全检查点回滚。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：为 `LocalMaintenanceCenter` 的详情页按钮补齐稳定 identifier、中文 accessibilityLabel 和中文 accessibilityHint；两处摘要同源动作复用既有 summary anchor；hint 中不再混入英文 `pane`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：同步登记 13 个详情页动作锚点及中文说明，保持 enum、源码、RUNBOOK 三方一致。
- **验证**：
  - Claude Code 负责窄范围实现；Codex 复核后补齐详情页最上方两处同源动作锚点并清理中英文混杂。
  - 定向测试 `localMaintenanceCenterDetailActionButtonsExposeStableAccessibilityIdentifiers|localMaintenanceCenterDetailActionButtonAnchorsAreDocumentedInRunbook|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords|localMaintenanceCenterExposesLegacyTaskMigrationPreviewAndManualButton|localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks` 6/6 通过。
  - 全量 `swift test --no-parallel` 531/531 通过。
- **边界**：不改变按钮动作闭包、不执行危险维护动作、不新增通信网关移动端联动、不进入老板默认界面。

### 2026-05-07 终端大厅单员工卡片操作补齐可区分 Computer Use 锚点

- **方向**：终端大厅摘要层和全局运行按钮已可被 Computer Use 稳定定位后，继续补齐单员工卡片里的「刷新预检 / 选中 / 预检 / 运行 / 清空日志」动作，避免只能运行全部员工，无法精确复核某一个员工终端。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `OPCTerminalAgentCardRefreshPreflightButton`、`OPCTerminalAgentCardSelectButton`、`OPCTerminalAgentCardPreflightButton`、`OPCTerminalAgentCardRunButton`、`OPCTerminalAgentCardClearLogButton`。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：为单员工卡片 5 个按钮补齐稳定 identifier，并把员工显示名写入中文 accessibilityLabel，确保多张员工卡里的同类按钮可区分。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：同步登记员工卡按钮锚点、中文 label/hint、员工名区分契约和 icon-only 中文无障碍守门。
- **验证**：
  - Claude Code 负责窄范围实现；Codex 复核后增强 label 区分度并修正旧测试契约。
  - 定向测试 `terminalHallAndCommunicationIconOnlyButtonsExposeChineseAccessibilityLabel|terminalAgentCardCoreActionButtonsExposeStableAccessibilityIdentifiers|terminalAgentCardActionButtonIdentifiersAreDocumentedInRunbook|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|terminalAgentCardPreflightIsAlwaysVisibleWithIconOnlyRefreshButton|terminalAgentCardSelectButtonIsIconOnlyAndCardIsTappableAsFallback` 6/6 通过。
  - 全量 `swift test --no-parallel` 529/529 通过。
- **边界**：不改变按钮动作语义、不运行真实员工任务、不新增通信网关移动端联动、不进入老板默认界面。

### 2026-05-07 员工命令行作业补齐退出后尾部输出捕获

- **方向**：修复一次性 CLI 员工作业在子进程退出瞬间丢失 stdout/stderr 最后几行的可靠性缺口，避免技术负责人只能看到退出码却看不到 `swift test`、Codex、Claude Code 或 Gemini 末尾回执。
- **实施**：
  - `Sources/OPCCompanyCore/CLIAgentRunner.swift`：`AgentProcessRunner.runStreaming` 在 `process.waitUntilExit()` 返回后先解除 stdout/stderr 的 `readabilityHandler`，再同步 drain 两个 pipe 的剩余数据并写入 `ProcessOutputBuffer`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `runStreamingCapturesTailOutputAfterExit`，用子进程立刻写入 stdout/stderr 后退出的方式守住尾部输出捕获契约。
  - `docs/RUNBOOK.md`：补充「命令行作业尾部输出捕获契约」，说明退出后 drain 顺序和对应守门测试。
- **验证**：
  - Claude Code 负责窄范围实现和目标测试；Codex 复核补丁后重新运行 `swift test --filter runStreamingCapturesTailOutputAfterExit`，1/1 通过。
  - 全量 `swift test --no-parallel` 527/527 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506165842`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
- **边界**：不改变 UI、通信网关移动端联动、签名发布策略、Package 配置或持久终端席位协议；这次只修复一次性 `AgentProcessRunner.runStreaming` 的输出收尾行为。

### 2026-05-07 终端大厅摘要主操作按钮补齐稳定 Computer Use 锚点

- **方向**：继续收口终端大厅默认可见摘要工作台的高频副作用按钮，避免 Computer Use 只能靠中文按钮文案匹配「运行体检 / 闭环演练 / 运行隔离体检 / 命令行预检」。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `OPCAdvancedMaintenanceArchitectureAuditButton`、`OPCAdvancedMaintenanceArchitectureClosureDrillButton`、`OPCAdvancedMaintenanceLocalIsolationAuditButton`、`OPCAdvancedMaintenanceLocalCLIPreflightButton`。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：为多员工架构摘要卡的「运行体检」「闭环演练」和本地维护摘要卡的「运行隔离体检」「命令行预检」补齐 identifier、中文 label、中文 hint。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：同步登记守门，确保四个按钮仍走原有维护/架构操作路径。
- **验证**：
  - Claude Code 只读审查确认缺口集中在摘要卡主操作按钮；通信网关主操作按当前正式使用标准暂不纳入本轮。
  - 定向测试 `terminalHallArchitectureSummaryPrimaryButtonsExposeStableAccessibilityAnchorsForComputerUse|terminalHallLocalMaintenanceSummaryPrimaryButtonsExposeStableAccessibilityAnchorsForComputerUse|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 3/3 通过；全量 `swift test --no-parallel` 526/526 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506163100`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 4518），进入「终端大厅」后确认 `OPCAdvancedMaintenanceArchitectureAuditButton`、`OPCAdvancedMaintenanceArchitectureClosureDrillButton`、`OPCAdvancedMaintenanceLocalIsolationAuditButton`、`OPCAdvancedMaintenanceLocalCLIPreflightButton` 均暴露稳定 ID、中文 Description 和中文 Help。
- **边界**：不点击四个副作用按钮、不新增通信网关移动端联动、不改变体检/闭环/预检执行策略、不进入老板默认界面。

### 2026-05-07 终端大厅运行提交按钮补齐稳定 Computer Use 锚点

- **方向**：闭合两条真实终端操作链路的提交端：终端大厅顶部「运行全部」和本地维护「发送一行手动输入」按钮；此前输入框已可被 Computer Use 定位，但配套提交按钮仍依赖可见文案。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `OPCTerminalHallRunAllButton` 和 `OPCTerminalManualREPLSendButton`。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：为「运行全部」按钮补齐 identifier、中文 label、发送范围和禁用边界 hint。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：为「发送一行手动输入」按钮补齐 identifier、中文动态 label、发送范围和禁用边界 hint。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：同步登记守门，保证按钮仍走原有 `runAllExecutableAgents` / `runManualREPLTurnForSelectedAgent` 路径。
- **验证**：
  - Claude Code 只读审查返回同一结论：这两个按钮分别是新补输入框的“动作伴侣”，不补齐会让 CUA 的“填充 -> 点击 -> 观察”链路断在提交端。
  - 定向测试 `terminalHallRunAllButtonExposesStableAccessibilityAnchorForComputerUse|manualREPLTurnSendButtonExposesStableAccessibilityAnchorForComputerUse|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 3/3 通过；全量 `swift test --no-parallel` 524/524 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506161610`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 1858），`OPCTerminalHallRunAllButton` 暴露 Description「运行全部员工终端」和禁用边界 Help；进入「本地稳定性与命令行运维详情」后，`OPCTerminalManualREPLSendButton` 在空输入时禁用，输入一行文本后启用，Description 为「发送一行手动交互输入」，Help 为「发送输入框中的一行文本到当前选中员工真实终端席位；输入为空或正在发送时禁用」。
- **边界**：不点击「运行全部」、不点击「发送一行手动输入」、不运行员工任务、不改变发送策略、不进入老板默认界面、不做通信网关移动端联动。

### 2026-05-06 终端大厅两处提示词输入框补齐稳定 Computer Use 锚点

- **方向**：收口两个仍依赖占位文字的输入框：终端大厅顶部「发送给员工终端的提示词」和本地维护「手动交互轮次」一行输入；让 Computer Use 能用稳定 identifier、中文 label 和 hint 定位，不依赖 placeholder。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `OPCTerminalHallHeaderPromptField` 和 `OPCTerminalManualREPLInputField`。
  - `Sources/OPCCompanyCore/TerminalHallView.swift`：为终端大厅顶部提示词输入框补齐 identifier、label、hint。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：为本地维护手动交互一行输入框补齐 identifier、label、hint。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 和 `docs/RUNBOOK.md`：同步登记守门，避免后续回退为只靠占位文字识别。
- **验证**：
  - Claude Code 只读审查先定位两处高价值 Computer Use 断点；本轮只做输入框可定位、可解释、可赋值，不改发送和执行策略。
  - 定向测试 `terminalHallHeaderPromptFieldExposesStableAccessibilityAnchorForComputerUse|manualREPLTurnInputFieldExposesStableAccessibilityAnchorForComputerUse|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 3/3 通过；全量 `swift test --no-parallel` 522/522 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506155712`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 37813），`OPCTerminalHallHeaderPromptField` 是真实 settable 输入框，Description 为「发送给员工终端的提示词」，Help 为「填写后会被「运行全部」按钮发送给当前产品的可执行员工」；进入「本地稳定性与命令行运维详情」后，`OPCTerminalManualREPLInputField` 是真实 settable 输入框，Description 为「手动交互一行输入」，Help 为「向当前选中员工的真实终端席位发送一行输入，不能包含换行」。
- **边界**：不点击手动发送、不运行员工任务、不改变自动循环/手动交互策略、不进入老板默认界面、不做通信网关移动端联动。

### 2026-05-06 员工恢复建议手动重试按钮补齐禁用边界说明

- **方向**：继续收口技术负责人维护区的 Computer Use 操作边界，让员工恢复建议里的「手动重试一次」按钮不仅有稳定 ID 和员工名 label，还能说明为什么禁用、什么时候可用。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：为真实按钮和 `accessibilityChildren` 镜像按钮同步补齐 `accessibilityHint`，说明仅员工最近一次状态为临时异常时可用，授权异常、忙碌或尚未观察状态不会自动重开。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：扩展 `cliRecoveryAdvicePanelKeepsRetryButtonsReachableWhileExposingStableAnchorsForComputerUse`，把禁用边界 hint 纳入守门。
  - `docs/RUNBOOK.md`：更新 `OPCCLIRecoveryAdviceManualRetryButton` 登记，明确 label、hint 和禁用状态职责。
- **验证**：
  - Claude Code 只读审查确认恢复建议面板仍属终端大厅/本地维护范围；本轮只做手动重试按钮 hint 补齐，不改重试策略。
  - 定向测试 `cliRecoveryAdvicePanelKeepsRetryButtonsReachableWhileExposingStableAnchorsForComputerUse|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 2/2 通过；全量 `swift test --no-parallel` 520/520 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506153807`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 39070），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCCLIRecoveryAdviceManualRetryButton` 四个员工按钮都显示 Help「仅当员工最近一次状态为临时异常时可用；授权异常、忙碌或尚未观察状态不会自动重开」。
- **边界**：不改变恢复策略、不自动重开授权异常或忙碌员工、不写老板聊天、不进入老板默认界面、不做通信网关移动端联动。

### 2026-05-06 自动循环报告和旧任务迁移按钮补齐机械可读状态

- **方向**：收口终端大厅本地维护面板的两处 Computer Use 读写断点：自动循环报告必须可读取动态停止原因，旧任务迁移按钮必须说明禁用条件和二次确认规则。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`OPCTerminalAutoLoopReportSummary` 暴露动态 `accessibilityValue(report.summaryText)`；`OPCLegacyTaskProductMigrationButton` 暴露禁用条件和二次确认 hint；自动循环面板标题承接 `OPCTerminalAutoInteractionLoopPanel` 锚点，父容器不再抢占真实输入框、步进器、启动按钮和报告摘要的 identifier。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增报告摘要动态 value 守门，并扩展旧任务迁移按钮 hint 断言，防止后续把真实输入/按钮替换成不可操作的虚拟 accessibility 子节点。
  - `docs/RUNBOOK.md`：登记自动循环面板标题锚点、上下文字段、最大轮次、启动按钮、报告摘要动态 value 和旧任务迁移按钮二次确认说明。
- **验证**：
  - 定向测试 `terminalAutoInteractionLoopReportSummaryExposesDynamicValueForComputerUse|localMaintenanceCenterExposesLegacyTaskMigrationPreviewAndManualButton|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 3/3 通过；全量 `swift test --no-parallel` 520/520 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506144522`；`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 71005），进入「终端大厅 → 本地稳定性与命令行运维详情」，确认 `OPCTerminalAutoInteractionLoopPanel`、`OPCTerminalAutoLoopTaskContextField`、`OPCTerminalAutoLoopMaxTurnsStepper`、`OPCTerminalAutoLoopStartButton` 均为真实可达节点；填入上下文后启动按钮可执行；拒绝报告以 `OPCTerminalAutoLoopReportSummary` 暴露 value，包含「已拒绝」「停止原因：临时异常」和「不创建命令行作业档案、不写老板聊天、不绕过交付验收」；`OPCLegacyTaskProductMigrationButton` 在无待迁移旧任务时保持禁用，并暴露“仅当当前产品存在未归属旧任务时可用；首次点击进入确认态，再次点击才会迁入当前产品”。
- **边界**：不改 Store/schema/任务迁移策略，不进入老板默认界面，不做通信网关移动端联动。

### 2026-05-06 维护详情余下三处文本预览补齐 label 和 value

- **方向**：完成终端大厅本地维护详情右栏文本预览的无障碍一致性收口，把仍然只有 identifier 的「本地文件索引根白名单」「自动摘要去重预览」「旧任务归属迁移预览」补齐中文 label 和动态 value；保持它们只在技术负责人维护区可见，不进入老板默认视图。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：为 `OPCLinkedLocalFileRootAllowlistPreview`、`OPCAutoCapturedSummaryDuplicatePreview`、`OPCLegacyTaskProductMigrationPreview` 分别补 `.accessibilityLabel(...)` 和 `.accessibilityValue(store.<accessor>())`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：扩展三条既有本地维护守门，确认这三个预览不再只登记 identifier，还必须暴露中文 label 和动态正文 value。
  - `docs/RUNBOOK.md`：把三处锚点登记更新为可直接读取 `linkedLocalFileRootAllowlistText()`、`autoCapturedSummaryDuplicatePreviewText()`、`legacyTaskProductMigrationText()` 的 value。
- **验证**：
  - Claude Code 只读扫描确认这三处是当前本地维护右栏最小、低风险、非老板界面的真实缺口；本轮按其建议只做机械补齐，不扩大到通信网关移动端联动。
  - 定向测试 `localMaintenanceCenterExposesLinkedLocalFileRootAllowlistPreview|localMaintenanceCenterExposesLegacyTaskMigrationPreviewAndManualButton|localMaintenanceCenterExposesAutoCapturedSummaryDuplicateCleanup|uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 4/4 通过；全量 `swift test --no-parallel` 519/519 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506140504`；`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 75098），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCLinkedLocalFileRootAllowlistPreview` 显示 Description「本地文件索引根白名单」且 value 含当前根目录与登记根目录；`OPCAutoCapturedSummaryDuplicatePreview` 显示 Description「自动摘要去重预览」且 value 含重复摘要统计；`OPCLegacyTaskProductMigrationPreview` 显示 Description「旧任务归属迁移预览」且 value 含待迁移旧任务数和迁移说明。
- **边界**：不改维护巡检数据、不改按钮行为、不新增 identifier、不改老板视图、不处理通信网关移动端联动；只修复现有文本预览的 Computer Use 机械读取通道。

### 2026-05-06 可展开维护预览补齐摘要、开关和明细 Computer Use 锚点

- **方向**：继续收口终端大厅本地维护详情的真机机械验证链路，把两个 `MaintenancePreviewText` 可展开维护预览拆成摘要、展开开关和完整明细三个稳定锚点；保留 `DisclosureGroup` 的真实展开/收起行为，避免为了测试可读性牺牲人工操作。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `OPCCLIRuntimeIsolationPreview`、`OPCCLIRuntimeIsolationDetailToggle`、`OPCCLIRuntimeIsolationDetailPreview`、`OPCTerminalWorkspacePlanPreview`、`OPCTerminalWorkspacePlanDetailToggle`、`OPCTerminalWorkspacePlanDetailPreview`。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`MaintenancePreviewText` 改为显式接收摘要、开关和明细 identifier；摘要暴露动态 value，展开标签保留中文开关 label/hint，展开后的明细正文以独立节点暴露完整运维文本。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增守门，确认两个调用点都接入三段锚点、`DisclosureGroup` 仍存在、开关仍可达、明细正文继续暴露稳定 value，并纳入 RUNBOOK 覆盖。
  - `docs/RUNBOOK.md`：登记两个可展开维护预览的摘要/开关/明细锚点，后续 Computer Use 可直接读 value，不再依赖截图 OCR 或标题扫描。
- **验证**：
  - Claude Code 已做只读 API 形态复核，建议保持摘要、开关、明细三锚点分离，避免把开关和明细合并导致真实点击不可达。
  - 定向测试 `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|maintenancePreviewTextKeepsDisclosureReachableWhileExposingStableAnchorsForComputerUse` 2/2 通过；全量 `swift test --no-parallel` 519/519 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506135003`；`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 9407），进入「终端大厅 → 本地稳定性与命令行运维详情」，可定位 `OPCCLIRuntimeIsolationPreview`、`OPCCLIRuntimeIsolationDetailToggle`、`OPCCLIRuntimeIsolationDetailPreview`、`OPCTerminalWorkspacePlanPreview`、`OPCTerminalWorkspacePlanDetailToggle`、`OPCTerminalWorkspacePlanDetailPreview`；两个开关均可从 off 切到 on，展开后的明细节点分别包含「运维详情：命令行与工作区隔离」和「运维详情：真实终端工作区」。
- **边界**：不改维护业务数据、不改 Store 文本、不新增老板入口、不把本地维护细节带进老板默认视图；只补齐可展开维护预览的可验证性和无障碍定位稳定性。

### 2026-05-06 本地维护纯文本预览补齐稳定 Computer Use 锚点

- **方向**：继续收口终端大厅本地维护详情的真机机械验证链路，把 6 个没有交互按钮的维护纯文本预览升级为可由 Computer Use 直接读取的稳定锚点；这些内容仍只在技术负责人维护区可见，不进入老板默认视图。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `runDataCleanupPreview`、`cliToolchainPreflightPreview`、`defaultCompanyStatePreview`、`productIsolationAuditPreview`、`safetyCheckpointPreview`、`localDiagnosticsPolicyPreview` 六个 UI 自动化 identifier。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：给「清理预览」「命令行链路预检」「默认状态预览」「隔离体检预览」「安全检查点」「本机诊断与日志策略」正文文本挂载中文 label、稳定 identifier 和动态 accessibility value，避免 Computer Use 只能依赖标题或截图 OCR。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增本地维护纯文本预览锚点守门，并纳入 RUNBOOK 覆盖检查。
  - `docs/RUNBOOK.md`：登记 6 个维护预览锚点，明确 CUA 直接读取对应正文 value。
- **验证**：
  - Claude Code 只读扫描建议优先处理 4 个无交互维护预览；本轮在同一低风险纯文本边界内同步补齐「安全检查点」和「本机诊断与日志策略」。
  - 定向测试通过：`swift test --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|localMaintenancePlainPreviewTextsWireStableAccessibilityAnchorsForComputerUse"`，2/2。
  - 全量测试通过：`swift test --no-parallel`，518/518。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506132442`，`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏关闭旧窗口后启动最新 bundle（pid 4532），进入「终端大厅 → 本地稳定性与命令行运维详情」，可直接定位 `OPCRunDataCleanupPreview`、`OPCCLIToolchainPreflightPreview`、`OPCDefaultCompanyStatePreview`、`OPCProductIsolationAuditPreview`、`OPCSafetyCheckpointPreview`、`OPCLocalDiagnosticsPolicyPreview`，各自 value 均包含对应中文预览正文。
- **边界**：不改任何巡检/清理/回滚/预检动作，不改变按钮状态，不改老板视图，不处理带 `DisclosureGroup` 的完整运维明细预览。

### 2026-05-06 持久终端可用性与员工恢复建议补齐稳定 Computer Use 锚点

- **方向**：继续收口终端大厅本地维护详情的真机机械验证链路，把「持久终端可用性预览」和「员工恢复建议」补成可由 Computer Use 直接读取的稳定锚点，同时保留每名员工的手动重试按钮可达性。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `terminalWorkspaceHealthPreview`、`cliRecoveryAdvicePanel`、`cliRecoveryAdviceSummary`、`cliRecoveryAdviceManualRetryButton` 四个 UI 自动化 identifier。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`TerminalWorkspaceHealthPreview` 折叠为单一 a11y 元素并挂载动态巡检正文；`CLIRecoveryAdvicePanel` 保持 `.accessibilityElement(children: .contain)`，并通过 `accessibilityChildren` 同步镜像摘要和每名员工的手动重试按钮，避免 SwiftUI 文本合并导致摘要 ID 丢失或按钮被覆盖。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：补齐持久终端可用性预览、员工恢复建议面板、摘要和手动重试按钮的源码契约守门，并纳入 RUNBOOK 覆盖检查。
  - `docs/RUNBOOK.md`：登记新增锚点，明确恢复建议面板的虚拟 accessibility children 必须同时镜像摘要和按钮。
- **验证**：
  - Claude Code 使用前已执行 `claude update` 检查，结果为 `Claude Code is up to date (2.1.131)`；随后只读复核指出恢复建议根节点不能简单 `.combine`，需要保留按钮可达性。
  - 定向测试通过：`swift test --filter "cliRecoveryAdvicePanelKeepsRetryButtonsReachableWhileExposingStableAnchorsForComputerUse"`，1/1。
  - 全量测试通过：`swift test --no-parallel`，517/517。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506130807`，`codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 29757），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCTerminalWorkspaceHealthPreview` value 包含「持久终端可用性巡检：有警告」和 4 个待创建席位；`OPCCLIRecoveryAdvicePanel`、`OPCCLIRecoveryAdviceSummary` 均可定位；4 个 `OPCCLIRecoveryAdviceManualRetryButton` 分别对应 Codex 技术负责人、Gemini 界面设计师、Claude Code 工程师、Codex 审查员，当前状态均为禁用，符合「尚未观察/暂不开放手动重试」策略。
- **边界**：不改 CLI 恢复策略，不新增自动重试，不绕过忙碌/授权异常守门，不写老板聊天、不写验收记录、不创建作业档案，不改变老板视图。

### 2026-05-06 员工交接与命令行作业巡检预览登记稳定 Computer Use 锚点

- **方向**：继续收口本地维护详情的机械验证链路，把「员工交接巡检预览」和「命令行作业幽灵巡检预览」补成与运行健康、证据分类、维护数据增长、历史维护预览一致的稳定 a11y 节点。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `employeeHandoffAuditPreview` / `jobArchiveStaleAuditPreview` 两个 UI 自动化 identifier。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`EmployeeHandoffAuditPreview` 和 `JobArchiveStaleAuditPreview` 折叠为单一 a11y 元素，分别挂载稳定 identifier、中文 label 和动态 `accessibilityValue`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：补齐两个预览的 a11y 守门，并把 `OPCEmployeeHandoffAuditPreview` / `OPCJobArchiveStaleAuditPreview` 纳入 RUNBOOK 覆盖检查。
  - `docs/RUNBOOK.md`：登记两个维护预览锚点，明确 Computer Use 直接读取当前预览正文。
- **验证**：
  - Claude Code 使用前已执行 `claude update` 检查，结果为 `Claude Code is up to date (2.1.131)`；随后只读审查任务因 Claude Code 额度限制返回「resets 8:10pm (Asia/Shanghai)」，本轮未继续消耗 Claude。
  - 定向测试通过：`swift test --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|employeeHandoffAuditPreviewWiresStableAccessibilityAnchorForComputerUse|jobArchiveStaleAuditPreviewWiresStableAccessibilityAnchorForComputerUse"`，3/3。
  - 全量测试通过：`swift test --no-parallel`，515/515。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506120922`，`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 66736），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCEmployeeHandoffAuditPreview` value 包含「员工交接待确认巡检：通过」「总员工交接：0」「待确认：0」，`OPCJobArchiveStaleAuditPreview` value 包含「命令行作业幽灵巡检：通过」「作业档案：4」「幽灵运行：0」和 4 条已结束作业明细。
- **边界**：不改员工交接或命令行作业巡检逻辑，不新增老板入口，不改维护记录写入，不删除作业档案，不改变可见 UI 布局。

### 2026-05-06 历史维护预览登记稳定 Computer Use 锚点

- **方向**：延续本地维护详情的真机可验证性收口，把「历史索引预览」和「历史归档迁移预览」从中文标题扫描升级为稳定 Computer Use 锚点；两个预览仍只作为技术负责人维护区的唯一主位置，不进入老板视图。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `historyIndexAuditPreview` / `historyArchiveMigrationPreview` 两个 UI 自动化 identifier。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`HistoryIndexAuditPreview` 和 `HistoryArchiveMigrationPreview` 折叠为单一 a11y 元素，分别挂载稳定 identifier、中文 label 和动态 `accessibilityValue`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：补齐两个历史维护预览的锚点守门，并把 `OPCHistoryIndexAuditPreview` / `OPCHistoryArchiveMigrationPreview` 纳入 RUNBOOK 覆盖检查。
  - `docs/RUNBOOK.md`：登记两个历史维护预览锚点，明确 Computer Use 直接读取预览卡 value，不再依赖截图 OCR 或同名标题扫描。
- **验证**：
  - Claude Code 2.1.131 只读复核确认：两个历史预览此前缺少 identifier / label / value，本轮最小修复应只补 a11y 与测试文档，不改历史索引/归档业务逻辑。
  - 定向测试通过：`swift test --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|historyIndexAuditPreviewWiresStableAccessibilityAnchorForComputerUse|historyArchiveMigrationPreviewWiresStableAccessibilityAnchorForComputerUse|localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks"`，4/4。
  - 全量测试通过：`swift test --no-parallel`，513/513。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506115039`，`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 19068），进入「终端大厅 → 本地稳定性与命令行运维详情」，可直接定位 `OPCHistoryIndexAuditPreview` 和 `OPCHistoryArchiveMigrationPreview`；前者 value 包含「历史索引巡检：通过」「索引位置」「记录数：243」，后者 value 包含「历史归档迁移：预览」「已归档记录：74」以及“不裁剪主快照、不删除本地文件、不启动模型任务”的说明。
- **边界**：不改历史索引/归档迁移逻辑，不新增重复 UI，不新增老板入口，不改 schema 或存储位置，不自动裁剪主快照或删除本地文件。

### 2026-05-06 维护数据增长巡检扩展到主快照与命令行作业档案

- **方向**：吸收 Claude Code 只读复核建议，把单人本地长期使用最容易累积的物理数据纳入技术负责人维护巡检：主状态快照大小、当前产品 `.opc/jobs/` 作业数量和档案体积。巡检只提示，不自动删除、不裁剪主快照。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`maintenanceDataPressureText()` 新增「主状态快照」和「命令行作业档案」指标，增加主快照 20 MB、作业档案 100 个 / 100 MB 的建议阈值；`runMaintenanceDataPressureAuditForSelectedProduct()` 把这些指标纳入 warning 判定，但仍只写单条「维护数据增长巡检」维护记录。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`MaintenanceDataPressurePreview` 在保留中文 label 的同时，把动态预览正文挂到 `accessibilityValue`，便于 Computer Use 直接确认主状态快照和命令行作业档案指标。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：补充空态预览断言、作业档案数量超阈值 warning 测试，并确认巡检不会删除 `.opc/jobs/` 目录；同时锁定维护数据增长预览的动态 a11y value 契约。
  - `docs/RUNBOOK.md`：下一步硬化清单从“添加指标”改为“根据真实本地使用调阈值”。
- **验证**：
  - Claude Code 2.1.131 只读复核确认：实现应复用维护数据增长巡检，不新增 VerificationRecord title，不新增 a11y identifier，不做自动删除/迁移/裁剪。
  - Claude Code 2.1.131 只读复核确认：给 `MaintenanceDataPressurePreview` 增加 `accessibilityValue(store.maintenanceDataPressureText())` 属于纯 a11y 补强，不改变视觉布局或点击行为，能让 CUA 不依赖截图 OCR 读取动态正文。
  - 定向测试通过：`swift test --filter "maintenanceDataPressureAuditEmptyStateIsChineseAndPasses|maintenanceDataPressureAuditFlagsWarningWhenAboveThreshold|maintenanceDataPressureAuditFlagsWarningWhenArtifactsAboveThreshold|maintenanceDataPressureAuditFlagsWarningWhenJobArchiveCountAboveThresholdWithoutDeletingJobs|maintenanceDataPressurePreviewWiresStableAccessibilityAnchorForComputerUse"`，5/5。
  - 全量测试通过：`swift test --no-parallel`，511/511。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506112222`，`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 69976），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCMaintenanceDataPressurePreview` 的 a11y value 直接暴露动态正文，包含「主状态快照：213 KB（建议阈值 21 MB）」和「命令行作业档案：4 个 · 82 KB（建议阈值 100 个 / 104.9 MB）」。
- **边界**：不修改 `CompanySnapshot` schema，不新增外部存储，不调用 `saveSnapshot()`，不新增老板可见事件，不删除或压缩 `.opc/jobs/`，不改变历史索引/归档迁移语义。

### 2026-05-06 维护详情预览正文支持 Computer Use 机械读取

- **方向**：上一轮 CUA 复核发现同款维护预览只暴露标题时，Computer Use 需要依赖截图才能确认正文。本轮把已登记稳定锚点的维护预览正文统一挂到 `accessibilityValue`，让真机验证可以直接读取实际状态文本。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`RuntimeSessionHealthAuditPreview` 新增集中计算的 `accessibilityValue`，最近巡检态包含最近记录详情，空态包含中文提示和实时巡检文本；`EvidenceClassificationAuditPreview` 新增 `accessibilityValue(store.evidenceClassificationAuditText())`；`MaintenanceDataPressurePreview` 延续上一轮 value 契约。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：扩展三个预览的 a11y 守门测试，锁定 runtime / evidence / maintenance 都有动态正文 value，且 runtime 同时覆盖最近记录态与空态文本来源。
- **验证**：
  - Claude Code 2.1.131 只读复核确认：补丁为纯 a11y 加性修饰，不改变视觉、状态或业务行为；runtime 计算属性与可见分支同源，evidence 直接复用 `evidenceClassificationAuditText()`。
  - 定向测试通过：`swift test --filter "runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|evidenceClassificationAuditPreviewWiresStableAccessibilityAnchorForComputerUse|maintenanceDataPressurePreviewWiresStableAccessibilityAnchorForComputerUse"`，3/3。
  - 全量测试通过：`swift test --no-parallel`，511/511。
  - bundle 构建通过：`scripts/build_app_bundle.sh`，`CFBundleVersion = 20260506113259`，`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`。
  - Computer Use 真机复核通过：在 MacBook 主屏启动最新 bundle（pid 14539），进入「终端大厅 → 本地稳定性与命令行运维详情」，`OPCRuntimeSessionHealthAuditPreview` value 包含「运行会话健康巡检：通过」和 4 名员工明细，`OPCEvidenceClassificationAuditPreview` value 包含「未分类验证记录：0 条 / 未分类产物档案：0 条」，`OPCMaintenanceDataPressurePreview` value 继续包含主状态快照与命令行作业档案指标。
- **边界**：不新增老板入口，不改变维护巡检写入策略，不改变可见 UI 文案和布局，不把其他无稳定锚点的预览临时纳入本轮。

### 2026-05-06 旧任务产品归属泄漏收口

- **方向**：继续按单人本地正式使用标准收口多产品隔离。旧快照里没有产品归属的任务不能再因为兼容读取出现在每个产品视图；这些旧任务应只留在技术负责人维护区等待显式迁移。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`selectedProductTasks` 改为严格按当前 `selectedProductID` 过滤，移除 `productID == nil` 兼容读取；`legacyTaskProductMigrationText()` 和迁移结果文案同步说明“未迁移旧任务不会进入任意产品视图，会留在维护入口等待归属确认”。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：把旧 LIMITATION 守门改为严格产品过滤守门，新增行为断言：未归属旧任务仍保存在 `tasks` 和迁移计数中，但不会进入当前产品任务列表；维护区手动迁移入口继续存在。
  - `docs/RUNBOOK.md`：下一步硬化清单改为主快照大小/加载耗时和 `.opc/jobs/` 档案体积指标；不再把已落地的 PTY/tmux runner 当成待办。
- **验证**：
  - Claude Code 2.1.131 只读复核确认：本轮约束下无正式使用阻塞；建议继续观察主快照增长、`.opc/jobs/` 档案增长和 CLI 协议漂移。
  - 定向测试通过：`swift test --filter "selectedProductTasksExcludeLegacyNilTasksAfterMigrationPolicyCleanup|selectedProductTasksNilFallbackStaysRemovedWhileMigrationHelperRemains|legacyTaskProductMigrationPreviewShowsTargetProductAndLegacyTaskCount|runLegacyTaskProductMigrationForSelectedProductBackfillsTasksAndWritesMaintenanceRecord|runLegacyTaskProductMigrationForSelectedProductIsIdempotentAndKeepsStrictProductTaskFilter"`，5/5。
  - 全量测试通过：`swift test --no-parallel`，510/510。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`；`codesign -dv` 显示 `Signature=adhoc`、`Identifier=local.opc.company`；`BuildInfo.txt` 构建号 `20260506105704`。
  - Computer Use 已在 MacBook 主屏关闭旧进程 sheet、重新打开最新 bundle（pid 63549），进入终端大厅本地维护详情，确认「旧任务产品归属迁移预览」显示“未迁移的旧任务不会进入任意产品视图，会留在本维护入口等待归属确认”，按钮在待迁移 0 个时保持禁用。
- **边界**：不删除任何旧任务，不自动把旧任务迁到当前产品，不改变 `CompanyTask` schema，不把旧任务迁移入口放进老板总控台。

### 2026-05-06 单人本地正式使用标准收口

- **方向**：用户明确 OPC Company 只供本人在本机长期使用，不存在上架或对外分发要求；通信网关移动端联动由实际使用后再评估，不应作为正式使用阻塞项。本轮把正式使用口径从“产品分发”改为“单人本地可长期稳定使用”。
- **实施**：
  - `docs/RUNBOOK.md`：新增「单人本地正式使用边界」，明确 Developer ID 签名、notarization、DMG、Sparkle、对外崩溃上报、通信网关移动端联动和外部入站服务不作为当前正式使用阻塞；保留全量测试、bundle 构建、MacBook 主屏验证、状态备份和默认界面减噪作为当前硬门槛。
  - `OPC_COMPANY.md`：通信网关章节补充当前本地正式使用边界；后续是否完全实现移动端联动由实际使用体验决定。
  - `Sources/OPCCompanyCore/CompanyStore.swift` / `SelectionWorkspaceView.swift` / `CLIAgentRunner.swift`：把默认可见系统提示、员工状态和命令行失败建议里的「后端」改为「模型来源 / 命令行来源 / 接口模型」，减少实现词进入普通界面。
  - `scripts/build_app_bundle.sh`：本地 bundle 写入 UTC 构建标识和 `BuildInfo.txt`，并默认执行 ad-hoc 签名；这不是上架签名，只用于本机自用时保持 macOS 隐私授权身份更稳定。
- **验证**：
  - 默认可见文案与终端摘要定向测试通过：`swift test --no-parallel --filter "localAppBundleBuildScriptUsesAdHocSigningAndBuildMetadata|cliPreflightRecordsDirectoryPermissionsAndRunSummary|terminalAgentCardPreflightSummaryUsesAbstractChineseLabelsAndOmitsRawPathsAndFlags|visibleTerminalLog"`。
  - 全量测试通过：`swift test --no-parallel`，508/508。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`；`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`；`Info.plist` / `BuildInfo.txt` 写入构建号 `20260506102238`。
  - Claude Code 只读复核确认：通信网关移动端联动、Developer ID、notarization、Sparkle 和外部崩溃上报均未被列为单人本地正式使用阻塞；无阻塞级修复项。
  - Computer Use 已在 MacBook 主屏复核最新 bundle：终端大厅默认员工卡显示「来源」和中文运行摘要，不显示 `后端：`、raw prompt、绝对路径或完整模型 transcript；本地稳定性与命令行运维详情 sheet 可打开，维护区深层控件可达。
- **边界**：不删除通信网关已有本地模拟、HMAC、nonce、白名单或出站能力；不引入 Developer ID / notarization / Sparkle / 外部崩溃上报；不改变 CLI 命令构造、模型配置、持久化 schema 或终端执行链路。

### 2026-05-06 本机诊断与日志策略落地

- **方向**：继续按单人本地正式使用标准处理崩溃/日志策略：不接入 Sentry、Crashlytics 或其他外部上报，不把诊断路径暴露到老板默认视图；把本机排查位置和顺序放到技术负责人维护区与 Runbook。
- **实施**：
  - `CompanyStore.swift`：新增 `localDiagnosticsPolicyText()`，列出主状态快照、历史索引、安全检查点、命令行作业档案和 macOS `DiagnosticReports` 崩溃报告位置，并明确不自动上传日志。
  - `OperationsSuiteView.swift`：本地稳定性与命令行运维详情新增「本机诊断与日志策略」区块，仅在技术负责人维护详情内显示。
  - `docs/RUNBOOK.md`：新增「本机诊断与日志策略」，记录本机排查位置和不接外部崩溃/日志平台的正式使用口径。
  - `OPCCompanyCoreTests.swift`：新增 `localDiagnosticsPolicyKeepsCrashAndLogHandlingLocalOnly`，锁定本机诊断文案和不引入 Sentry / Crashlytics / Sparkle。
- **验证**：
  - 定向测试通过：`swift test --no-parallel --filter "localDiagnosticsPolicyKeepsCrashAndLogHandlingLocalOnly|localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks|maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords"`。
  - 边界修复后补充测试通过：`swift test --no-parallel --filter "localDiagnosticsPolicyKeepsCrashAndLogHandlingLocalOnly|localDiagnosticsPolicyAvoidsFakeJobArchivePathWithoutSelectedProduct"`。
  - 全量测试通过：`swift test --no-parallel`，510/510。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`；`codesign -dv dist/OPCCompany.app` 显示 `Signature=adhoc`、`Identifier=local.opc.company`；`Info.plist` / `BuildInfo.txt` 写入构建号 `20260506103544`。
  - Claude Code 只读复核确认：外部崩溃/日志上报、Developer ID、notarization、Sparkle 和通信网关移动端联动未被列为单人本地正式使用阻塞；诊断策略只在技术负责人维护区可见。复核指出未选中产品时作业档案路径会形成伪路径，已改为中文空态并加测试。
  - Computer Use 已在 MacBook 主屏复核最新 bundle：终端大厅默认员工卡继续显示「来源」和中文摘要；本地维护详情 sheet 可打开，且「本机诊断与日志策略」区块显示不接外部崩溃上报、不自动上传日志、本机诊断位置和排查顺序。
- **边界**：不新增后台守护进程、不上传日志、不采集隐私数据、不改变持久化 schema，不把诊断位置放进老板总控台。

### 2026-05-06 终端大厅员工卡：真实终端工作区启动 transcript 可见层摘要化

- **方向**：MacBook 主屏验证已确认命令行任务 transcript 摘要化生效，但同一默认日志区里的 `[OPC 真实终端工作区]` 启动 transcript 仍显示 `printf %b`、用户 shell prompt 和 `/Users/...` 绝对路径。本轮继续只改 `visibleTerminalLog(for:)` 可见层，把真实终端席位启动记录压成中文摘要，不改原始 `terminalLogs`、终端启动、tmux 或作业档案。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增 `compactTerminalWorkspaceTranscriptsForDisplay`，在命令行任务 transcript 摘要化之前先把完整 `[OPC 真实终端工作区]` 块改写成 `[OPC 真实终端工作区摘要]`，只保留「员工终端席位已创建」「执行位置：本地工作区」「完整启动记录保留在维护档案」。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `visibleTerminalLogSummarizesTerminalWorkspaceTranscriptButKeepsRawArchive`，断言 raw `terminalLogs` 仍含 `printf %b`、`/Users/...` 和 shell prompt，但 `visibleTerminalLog` 不再含这些原文，同时后续 `[OPC 命令行任务]` 仍会继续摘要化。
  - `docs/RUNBOOK.md`：补充员工卡真实终端工作区日志摘要说明，明确默认卡片只看席位摘要，原始启动 transcript 留在维护档案排查来源。
- **验证**：
  - `swift test --no-parallel --filter visibleTerminalLog` 8/8 通过。
  - `swift test --no-parallel` 全量 507/507 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
  - Computer Use 已在 MacBook 主屏打开最新 bundle 并进入终端大厅；四个员工卡默认日志均显示 `[OPC 真实终端工作区摘要]` 和 `[OPC 命令行任务摘要]`，不再显示真实终端启动 transcript 里的 `/Users/...`、`printf %b` 或 shell prompt。
- **边界**：不改终端工作区启动行为、执行目录选择、tmux session/window、作业档案、老板视图、右侧终端 tab 路由或持久化 schema；不引入折叠/隐藏控件。

### 2026-05-06 持久终端完整任务：runner 脚本隔离长 prompt 与真实 pane

- **方向**：虽然完整任务提交已改走 `sendInputLine` 原子粘贴，但全量测试仍暴露长 prompt / 多行参数在真实交互 pane 中存在解析风险。本轮把完整任务的长 wrapper 从 pane 输入流迁到产品内一次性 runner 脚本，真实终端只收到 `/bin/sh runner` 一行短命令；同时吸收 Claude Code 只读复核建议，补齐 runner 目录权限、孤儿脚本清理、tmux buffer 失败清理和更大历史捕获窗口。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`runPersistentTerminalCommand` 先写入 `.opc/runtime/terminal-runners/<marker>.sh`，脚本内保留 start/end marker、执行目录切换、原始命令参数、退出码回传和 `trap EXIT` 自清理；`persistentTerminalShellCommand` 只生成 `/bin/sh <runner>` 短命令。runner 目录强制 `0700`，写入前清理 6 小时以上陈旧脚本；`sendInputLine` 在 `paste-buffer` 失败时补 `delete-buffer`；终端捕获窗口从 `-10000` 扩到 `-50000`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：扩展持久终端源码守门，要求完整任务路径使用 runner 脚本、禁止回退多行 wrapper、锁定 `delete-buffer`、runner 清理和目录 `0700`；`persistentProtocolRunDetectsMarkersAfterLongOutput` 增加 runner 脚本执行后无 `.sh` 残留断言；`persistentProtocolTimeoutEscalatesToCloseUnresponsiveTerminalSeat` 继续验证真正不响应中断时会关闭员工终端席位。
- **验证**：
  - Claude Code 2.1.131 已做只读复核，确认未发现“长 prompt 直接进入交互终端”的回退路径；复核建议中的 runner 权限、陈旧清理、tmux buffer 清理、`cd` 失败上报和捕获窗口已吸收。
  - `swift test --no-parallel --filter "persistentProtocolRunDetectsMarkersAfterLongOutput|persistentProtocolTimeoutEscalatesToCloseUnresponsiveTerminalSeat|runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand|visibleTerminalLogSummarizesCompletedCommandTranscriptButKeepsRawArchive"` 4/4 通过。
  - `swift test --no-parallel` 全量 506/506 通过。
  - 后续真实终端工作区摘要化完成后，`swift test --no-parallel` 全量 507/507 通过，`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
- **边界**：不改 `CLIAgentCommandBuilder`、模型配置、老板视图、终端大厅路由、作业档案 schema 或验收链路；runner 脚本只用于完整任务提交，人工/自动单行 REPL 输入仍走原单行安全门禁。

### 2026-05-06 终端大厅员工卡：已完成命令行任务 transcript 可见层摘要化

- **方向**：终端大厅员工卡仍会把已完成命令行任务的完整 transcript 直接显示在默认日志区，包括模型 banner、session id、工作目录和大段模型输出；这类信息已保留在原始终端日志和命令行作业档案中，默认卡片重复铺出会降低扫描效率。本轮只改 `visibleTerminalLog(for:)` 可见层，把完整命令行任务 transcript 压成中文摘要，不用折叠隐藏，也不改原始审计流。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`visibleTerminalLog(for:)` 在原有 `sanitizeTerminalLogForDisplay` 之后新增 `compactCompletedCommandTranscriptsForDisplay` 步骤；当可见日志存在完整 `[OPC 命令行任务] ... [命令退出码 N] ... [OPC 交互状态]` 边界时，输出 `[OPC 命令行任务摘要]`，保留执行位置、运行方式、任务摘要、退出码和交互状态，并提示「完整输出保留在命令行作业档案。」；随后继续走既有 OPC 块合并逻辑。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `visibleTerminalLogSummarizesCompletedCommandTranscriptButKeepsRawArchive`，断言 raw `terminalLogs` 仍保留 `OpenAI Codex`、`session id` 和 `/Users/...`，但 `visibleTerminalLog` 只显示中文摘要、退出码和状态，不再显示模型 banner、session id、绝对路径或大段模型输出。
- **验证**：
  - `swift test --no-parallel --filter visibleTerminalLog` 7/7 通过。
  - 后续持久终端 runner 修复完成后，`swift test --no-parallel` 全量 506/506 通过。
- **边界**：不改 `terminalLogs` 原始存储、不改命令行作业档案、不改任务运行、退出码、交互状态观察或持久终端协议；没有完整命令退出码边界的普通模型输出仍按既有契约保留；`[OPC 会话预热]` 汇总和 `[OPC 运行前预检]` 保留逻辑不变。

### 2026-05-06 本地维护详情：历史索引/归档迁移预览去重为唯一主位置

- **方向**：`LocalMaintenanceCenter` 详情 sheet 内同时存在两份完全等价的「历史索引预览」「历史归档迁移预览」展示——上方主按钮（「运行历史索引巡检」/「运行历史归档迁移」）紧跟 `HistoryIndexAuditPreview()` / `HistoryArchiveMigrationPreview()` 主预览卡，下方「详细运维区」又重复写了两份 `SectionHeader(title: ...) + Text(store.historyIndexAuditText()) / Text(store.historyArchiveMigrationText())` 块，读取的是同一 store accessor，纯重复信息。本轮按"减少重复展示，不用折叠隐藏替代"的方向，把下方两块直接删除，让主按钮下方的预览卡作为唯一主位置；不动老板视图、不改 store 行为。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：删除 `LocalMaintenanceCenter` body 内下方详细运维区的 `SectionHeader(title: "历史索引预览")` 和 `SectionHeader(title: "历史归档迁移预览")` 两块（含各自的 `Text(store.historyIndexAuditText())` / `Text(store.historyArchiveMigrationText())` 渲染段）；上方主按钮下的 `HistoryIndexAuditPreview()` / `HistoryArchiveMigrationPreview()` 保持不动；下方「本地文件索引根白名单」「自动摘要去重预览」「旧任务归属迁移预览」等没有主按钮重复的 SectionHeader 块继续保留。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks` 源码守门，使用共享 `extractTopLevelStructSlice` helper 把检查范围限定到 `LocalMaintenanceCenter` 切片，断言切片内不再含 `SectionHeader(title: "历史索引预览")` 与 `SectionHeader(title: "历史归档迁移预览")`，同时仍含 `HistoryIndexAuditPreview()` 与 `HistoryArchiveMigrationPreview()`，并旁证三个无主按钮重复的 SectionHeader（「本地文件索引根白名单」「自动摘要去重预览」「旧任务归属迁移预览」）继续保留——避免后续重构整体一刀切删除详细运维区。
  - `docs/RUNBOOK.md`：在「终端大厅维护区关键控件」末尾补一段说明，写明历史索引 / 历史归档迁移预览的唯一主位置是上方两个预览卡，Computer Use 直接锁定预览卡内的中文标题 `Text("历史索引预览")` / `Text("历史归档迁移预览")` 即可，详细运维区已不再重复写同名 SectionHeader。
- **验证**：
  - `swift test --no-parallel --filter "localMaintenanceCenterDoesNotDuplicateHistoryIndexAndArchivePreviewBlocks|localMaintenanceCenterExposesAutoCapturedSummaryDuplicateCleanup"` 2/2 通过。
  - `swift test --no-parallel` 全量 505/505 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
  - Computer Use 已在 MacBook 主屏打开最新 bundle，进入终端大厅并通过命名辅助动作打开 `OPCTerminalHallDetailSheet`；本地维护详情中上方主位置仍显示「历史索引预览」和「历史归档迁移预览」，下方详细运维区不再重复显示这两个同名块，只保留「本地文件索引根白名单」「自动摘要去重预览」「旧任务归属迁移预览」等非重复维护信息。
- **边界**：不改 store accessor (`historyIndexAuditText` / `historyArchiveMigrationText`) 行为；不改老板视图、不改摘要卡、不引入折叠/隐藏 UI；不动 `project.pbxproj` / 持久化字段 / 测试基础设施约定。

### 2026-05-06 终端大厅维护预览：相邻巡检卡折叠为单一 a11y 节点

- **方向**：MacBook 主屏 Computer Use 复核本地维护详情时确认 `OPCRuntimeSessionHealthAuditPreview` 已是单一节点，但相邻 `OPCEvidenceClassificationAuditPreview` 与 `OPCMaintenanceDataPressurePreview` 仍各暴露两条同名 AX 节点。该问题会让真机自动化在维护巡检区误选父/子节点，影响后续功能验证稳定性。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：`EvidenceClassificationAuditPreview` 与 `MaintenanceDataPressurePreview` 根节点补 `.accessibilityElement(children: .combine)`，并继续挂现有中文 `accessibilityLabel` 与 `OPCUIAutomationIdentifier`，不改按钮、文案、巡检逻辑或 sheet 路由。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增两条源码守门，分别锁定证据分类巡检预览和维护数据增长预览必须同时具备 enum rawValue、`.accessibilityElement(children: .combine)`、identifier 和中文 label，防止后续重构重新暴露重复节点。
  - `docs/RUNBOOK.md`：维护区关键控件说明同步写明这两个预览卡是单一可定位 a11y 根节点。
- **验证**：
  - `swift test --no-parallel --filter "runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|evidenceClassificationAuditPreviewWiresStableAccessibilityAnchorForComputerUse|maintenanceDataPressurePreviewWiresStableAccessibilityAnchorForComputerUse"` 3/3 通过。
  - `swift test --no-parallel` 全量 504/504 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
  - Computer Use 已在 MacBook 主屏打开最新 bundle，点击本地维护详情后可定位 `OPCTerminalHallDetailSheet`、`OPCLocalMaintenanceCenterRoot`、`OPCRuntimeSessionHealthAuditPreview`、`OPCEvidenceClassificationAuditPreview` 和 `OPCMaintenanceDataPressurePreview`；三类预览节点各只出现一次。
- **边界**：不改老板视图、不新增维护入口、不隐藏终端大厅摘要信息、不改巡检数据和维护审计写入；只修复 Computer Use / 无障碍树的定位稳定性。

### 2026-05-06 持久终端命令发送：sendInputLine 改走 tmux 原子粘贴路径

- **方向**：上一轮把 `runPersistentTerminalCommand` 切到 `sendInputLine`（`tmux send-keys -l text` + 单独 `send-keys C-m`）后，`persistentProtocolRunDetectsMarkersAfterLongOutput` 在 full `swift test` 仍偶发失败：长 marker-wrapped `shellCommand` 由两个独立 tmux 进程相继投递时，回车有时早于文本被 pty 消化，让 zsh 看到「半截命令 + Enter」并把残段当成路径触发 `file name too long`，进而漏发整段命令、长输出测试拿不到 `__OPC_JOB_EXIT` marker。本轮把 `sendInputLine` 底层改成原子粘贴，文本与回车一次送达，杜绝两步竞态。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`PersistentTerminalSession.sendInputLine` 不再 `send-keys -l text` + `send-keys C-m`，改为 `tmux load-buffer -b NAME -`（通过 stdin 把 `text + "\n"` 写进一次性 buffer）后再 `tmux paste-buffer -d -b NAME -t pane`（`-d` 让 buffer 粘完即丢）。新增 `runLocalProcessWithStdin` actor-内 helper 提供 stdin 管道，仍保持 nonisolated；不再依赖任何 shell 字符串拼接处理用户文本。`runPersistentTerminalCommand` 调用点保持 `sendInputLine(shellCommand,...)`，注释改写为「原子粘贴路径」。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：扩展 `runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand` 源码守门，除原有「禁止 `sendKeys([shellCommand`、要求 `sendInputLine(shellCommand`」外，新增三条断言锁定 `sendInputLine` 函数体必须出现 `load-buffer`、`paste-buffer`、`"-d"`，且不能再出现 `"send-keys"`。其余四个行为测试（`persistentProtocolRunDetectsMarkersAfterLongOutput` / `persistentTerminalSendInputLineUsesLiteralTmuxInput` / `persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection` / `persistentTerminalSendInputLineEmptyAndUnicodeNewlinesAreGuarded`）保持原断言不动——它们走的是真实 tmux pane，行为契约（特殊字符字面量送达、marker 检测、空行 + 多行守门）天然继续覆盖原子粘贴路径。
- **验证**：
  - `swift test --no-parallel --filter "persistentProtocolRunDetectsMarkersAfterLongOutput|persistentTerminalSendInputLineUsesLiteralTmuxInput|persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection|runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand"` 4/4 通过。
  - `swift test --no-parallel --filter "persistentTerminal|persistentProtocol|runPersistentTerminalCommand"` 全部通过。
  - `swift test --no-parallel` 全量 504/504 通过。
  - `scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
- **边界**：不改 `CLIAgentCommandBuilder`、模型、UI、终端大厅路由或 sheet 尺寸；不改用户可见产品文案；不改变作业档案、OPC marker、超时中断、验收链路、a11y 锚点；不动 `project.pbxproj` / schema / 持久化字段。

### 2026-05-06 持久终端命令发送：长命令改走字面量输入路径

- **方向**：全量 `swift test --no-parallel` 在 `persistentProtocolRunDetectsMarkersAfterLongOutput` 暴露顺序依赖失败：完整任务提交路径把 marker-wrapped `shellCommand` 直接交给 `tmux send-keys` key-name 解析，长 prompt 在 zsh 中触发 `file name too long`。同一文件已有单行字面量输入路径，本轮把完整任务提交复用该底层。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`runPersistentTerminalCommand` 从 `terminalSession.sendKeys([shellCommand, "C-m"], ...)` 改为 `terminalSession.sendInputLine(shellCommand, ...)`，即 `tmux send-keys -l` 发送完整命令文本，再单独发送 `C-m`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand` 源码守门，禁止回退到 `sendKeys([shellCommand`，并要求完整任务路径调用 `sendInputLine(shellCommand`；不削弱长输出行为测试断言。
  - `OPC_COMPANY.md`：在当前状态中补充完整任务提交与手动单行输入的路径分工。
- **验证**：
  - `swift test --no-parallel --filter "runPersistentTerminalCommandUsesLiteralTmuxInputForShellCommand|persistentTerminalSendInputLineUsesLiteralTmuxInput|persistentProtocolRunDetectsMarkersAfterLongOutput"` 3/3 通过。
  - `swift test --filter "persistentTerminal|persistentProtocol|runPersistentTerminalCommand" --no-parallel` 19/19 通过。
  - `swift test --no-parallel` 全量 501/501 通过。
- **边界**：不改 `CLIAgentCommandBuilder`、模型、UI、终端大厅路由或 sheet 尺寸；不改用户可见产品文案；不改变作业档案、OPC marker、超时中断和验收链路。

### 2026-05-06 运行会话健康巡检预览：折叠子 Text 为单一 a11y 元素

- **方向**：上一轮在 `RuntimeSessionHealthAuditPreview` 上挂了 `accessibilityIdentifier` + 中文 `accessibilityLabel`，但 SwiftUI 默认仍把内部「标题 / 最近一次巡检 / 详情」三段 `Text` 暴露成多条可抓取 a11y 节点；Computer Use 在抓 AX 树时会看到多个同名落点，定位不稳。本轮把预览根节点改为单一 a11y 元素，identifier 仍稳定挂在它身上，子文本被折叠成根元素的 value。
- **实施**：
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：在 `RuntimeSessionHealthAuditPreview` 根节点 `.background(...)` 之后、`.accessibilityIdentifier(...)` 之前插入 `.accessibilityElement(children: .combine)`，使 identifier / label 落在新合并出来的单一元素上；按钮 / 视图结构 / 文案 / sheet 尺寸 / `OPCRuntimeSessionHealthAuditPreview` 命名 / `TerminalHall` 路由全部不动。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：在既有 `runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse` 守门里再追加一条 `#expect`，要求 `RuntimeSessionHealthAuditPreview` 切片包含 `.accessibilityElement(children: .combine)`，与 identifier / label 三者同形锁定。
- **验证**：
  - `swift test --filter "runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit"` 通过。
  - codex 复核后补跑 `swift test --no-parallel --filter "runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit"` 通过。
  - 后续持久终端修复完成后，`swift test --no-parallel` 全量 501/501 通过，`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
  - Computer Use 已在 MacBook 主屏确认最新 bundle 能进入终端大厅并读取 `OPCTerminalHallLocalMaintenanceHeaderTrigger` / `OPCAdvancedMaintenanceLocalDetailTrigger`；本轮 CUA 对终端大厅内容区按钮只聚焦不触发 SwiftUI action，未完成 sheet 内单一锚点复核，列入后续真机验证复查。
- **边界**：未改 `OPCUIAutomationIdentifier` enum / rawValue，未改 `RUNBOOK.md`；未改任何用户可见文案；未触碰 schema、`VerificationRecord`、store 行为或 `project.pbxproj`；视图样式 / sheet 尺寸 / 路由保持不变。

### 2026-05-06 运行会话健康巡检预览：补齐 Computer Use a11y 锚点

- **方向**：上一轮把「运行会话健康巡检」改造成「按钮 + 就地预览」组合时，明确把 `OPCUIAutomationIdentifier` / `RUNBOOK.md` 留在 scope 之外。本轮收尾：给 `RuntimeSessionHealthAuditPreview` 登记稳定 a11y 锚点，让 Computer Use 不再依赖中文标题文本扫描就能直接落点。
- **实施**：
  - `Sources/OPCCompanyCore/DisplayFormatting.swift`：新增 `runtimeSessionHealthAuditPreview` 枚举条目，rawValue `OPCRuntimeSessionHealthAuditPreview`，与既有命名约定一致。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：在 `RuntimeSessionHealthAuditPreview` 根节点同时挂 `accessibilityIdentifier(...)` 与中文 `accessibilityLabel("运行会话健康巡检预览")`，与 `EvidenceClassificationAuditPreview` / `MaintenanceDataPressurePreview` 同形；不动按钮 / 视图结构 / 文案。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：在 `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 的 `runbookKeyPaths` 中补登 `OPCRuntimeSessionHealthAuditPreview`；新增 `runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse` 源码扫描守门，锁定 enum 声明、视图上的 identifier + 中文 label 三者同时存在。
  - `docs/RUNBOOK.md`：在「终端大厅维护区关键控件」清单中加入 `OPCRuntimeSessionHealthAuditPreview` 条目，与 enum case 双向锁。
- **验证**：
  - `swift test --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit"` 通过。
  - codex 复核后补跑 `swift test --no-parallel --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|runtimeSessionHealthAuditPreviewWiresStableAccessibilityAnchorForComputerUse|localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit"` 通过，`swift test --no-parallel` 全量 500/500 通过，`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：顶部「本地维护」可打开 `OPCTerminalHallDetailSheet`，详情内可定位 `OPCLocalMaintenanceCenterRoot` 与 `OPCRuntimeSessionHealthAuditPreview`，点击「运行会话健康巡检」后右侧记录刷新。
- **边界**：不改 `VerificationRecord` 或任何 schema/数据模型；不改 `TerminalHall` 路由 / sheet 尺寸；不改用户可见文案（仅文档与 a11y 锚点）；未触碰 `project.pbxproj`。

### 2026-05-06 运行会话健康巡检：按钮下方就地预览

- **方向**：本地维护详情里「运行会话健康巡检」按钮原本只把结果写入摘要卡和右侧维护审计中心，操作者点完按钮要往下拉、再往右看才能确认结论；与「员工交接巡检」「命令行作业幽灵巡检」「证据分类巡检」等同列条目不一致。本轮把该巡检也补齐为「按钮 + 就地预览」组合，预览始终显示当前产品最近一次记录或中文空态，按钮点击后预览就地刷新。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增 `selectedProductLatestRuntimeSessionHealthAudit()`，从当前产品维护类验证记录中取最近一条「运行会话健康巡检」。不动任何 schema、不新增持久化字段。
  - `Sources/OPCCompanyCore/OperationsSuiteView.swift`：新增 `RuntimeSessionHealthAuditPreview` 视图，与 `EmployeeHandoffAuditPreview` 同款样式；`LocalMaintenanceCenter` 在「运行会话健康巡检」按钮正下方挂入。预览显示「最近一次巡检：通过/需关注 · 时间」+ 详情，无记录时显示「尚未运行巡检 · 点击上方按钮可在此就地查看运行来源 / 来源配置 / 来源漂移结果」并以实时 `runtimeSessionHealthAuditText()` 兜底。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit`，锁定空态、点击后写入新记录、详情含「运行会话健康巡检 / 运行来源」等中文产品话术，并守门 `backend / 后端配置 / 后端漂移 / POST / endpoint / model:` 等底层词不出现。
- **验证**：
  - 目标测试 5/5 通过：`localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit` 新通过；既有 `runtimeSessionHealthAuditPassesForHealthyTeam` / `*FlagsCommandMissingAndBackendDrift` / `*OnlyReportsStaleBusyWithoutRecovering` / `*ShowsAuthenticationHintWithoutInternalLabels` 仍通过。
  - `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 与 `maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords` 通过，确认未误改 a11y 锚点登记和中文术语守门。
  - 命令：`swift test --filter "localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit|runtimeSessionHealthAuditPassesForHealthyTeam|runtimeSessionHealthAuditFlagsCommandMissingAndBackendDrift|runtimeSessionHealthAuditOnlyReportsStaleBusyWithoutRecovering|runtimeSessionHealthAuditShowsAuthenticationHintWithoutInternalLabels"`、`swift test --filter "uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths|maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords"`。
- **边界**：不改老板总控台 / 产品详情 / 员工工作台；不新增折叠隐藏；不改 `VerificationRecord` schema 或 `runtimeSessionHealthAuditText` 文案；不新增 `OPCUIAutomationIdentifier` 案例（`DisplayFormatting.swift` 与 `RUNBOOK.md` 在本轮 scope 外）。

### 2026-05-05 产品记忆自动摘要去重：避免重复 CTO 推进刷屏

- **方向**：产品详情一键推进会把 CTO/老板状态报告沉淀为产品记忆；连续验证或重复点击时，完全相同的自动摘要会在短时间内堆叠，增加老板默认记忆区噪音。本轮只治理自动捕获路径，不改变手动记忆和历史记忆 schema。
- **实施**：
  - `CompanyStore.swift`：为 `captureDecisionMemoryFromLatestReport()` 增加同产品、同摘要前 200 字、1 小时窗口的自动摘要去重；自动摘要标题统一使用 `自动记录：` 前缀识别。
  - `CompanyStore.swift`：新增当前产品既有重复自动摘要预览和显式维护清理 API；按摘要前 200 字分组，每组保留最新一条，移除旧重复并写入维护审计记录。
  - `OperationsSuiteView.swift` / `DisplayFormatting.swift`：本地稳定性维护中心新增「自动摘要去重预览」和「清理自动状态摘要重复」二次确认按钮，带稳定 Computer Use identifier；默认老板/产品记忆列表不做隐藏或折叠。
  - `OPCCompanyCoreTests.swift`：新增同产品重复跳过、内容变化仍写入、不同产品仍写入、超过 1 小时仍写入，以及维护清理预览、清理保留最新、跨产品不越界、不同摘要不误删、无重复 no-op、维护 UI 可达性守门。
- **验证**：
  - 目标记忆捕获测试 10/10 通过；维护清理与 UI 守门 7/7 通过。
  - `swift test --no-parallel` 489/489 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证产品详情和产品记忆库正常渲染；点击「从最新报告写入记忆」后没有新增重复自动摘要。
  - Computer Use 已在 MacBook 主屏验证终端大厅可打开本地稳定性维护详情，维护区能看到「自动摘要去重预览」和「清理自动状态摘要重复」按钮；预览显示当前有 2 条自动摘要、1 组重复、可清理 1 条旧摘要。
- **边界**：不改 `ProductMemoryNote` Codable/schema，不改手动 `addMemory` 写入路径，不静默隐藏老板/产品记忆列表；既有重复只由技术维护中心显式二次确认清理。

### 2026-05-05 终端大厅日志与右侧终端减噪：预热历史汇总、去掉入口设计解释

- **方向**：Computer Use 复核和 Claude Code 只读审查都指向同一类问题：终端大厅默认卡片虽然已经合并连续重复预热块，但仍会显示多段相同会话预热记录；右侧检查器在终端大厅模式下还显示“终端控制已在主区域 / 避免同一功能出现两套入口”这类开发期解释。本轮把默认日志做成最近预热 + 历史条数汇总，并让终端大厅模式的右侧终端只保留当前员工日志。
- **实施**：
  - `CompanyStore.swift`：`visibleTerminalLog(for:)` 的 OPC 元数据块减噪增加会话预热专用汇总，多段 `[OPC 会话预热]` 只显示最近一段和历史条数；原始 `terminalLogs` 不变。
  - `InspectorPanel.swift`：`TerminalPanel` 在 `mainWorkspace == .terminalHall` 时不再渲染右侧运行控制区和开发期说明，只显示当前员工可见日志。
  - `SelectionWorkspaceView.swift`：员工工作台 `terminalStatusDetail` 去掉“老板界面”引用和重复的“完整命令和输出请到终端大厅查看”长句。
  - `CompanyStore.swift`：待审队列 overflow footer 不再把任务队列错误指向协作消息总览；协作消息收件箱仍保留协作消息总览入口。
  - `OPCCompanyCoreTests.swift`：新增/更新日志汇总、终端状态文案、右侧终端控制区、待审队列 footer 守门。
- **验证**：
  - `swift test --filter visibleTerminalLog --no-parallel` 6/6 通过。
  - `swift test --filter selectionWorkspaceTerminalStatusDetailDoesNotReferToBossInterfaceFromEmployeeDesk --no-parallel` 1/1 通过。
  - `swift test --filter "terminalStatusDetail|inspectorTerminalHall|agentDeskReviewQueueOverflow|agentDeskInboxOverflow" --no-parallel` 命中 5/5 通过。
  - `swift test --no-parallel` 458/458 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：终端大厅员工卡和右侧终端 tab 均显示“另有 N 条历史「OPC 会话预热」记录，完整记录保留在维护档案”，不再显示“终端控制已在主区域 / 避免同一功能出现两套入口”。
- **边界**：本轮只改默认可见日志和说明文案；真实终端运行、预检、自动循环、原始日志归档和维护证据不改。

### 2026-05-05 产品详情默认工作区减噪：进度去重、协作密度和标准标题校正

- **方向**：Claude Code 并行只读审查和 Computer Use 复核共同指出，产品详情页存在几类默认噪音：阶段进度在指标卡和进度卡重复出现，任务数在指标卡和进度卡重复出现；员工协作链路默认展示过多；“成功标准”标题实际承载的是首个未完成任务的验收标准，容易误读为产品级总标准。本轮把老板默认页改成更清晰的业务摘要。
- **实施**：
  - `SelectionWorkspaceView.swift`：产品进度卡只保留当前阶段、阶段轨道和下一步，不再重复大号百分比/任务计数；产品目标卡把任务级标准标题改为“当前待办标准”，所有任务完成时才显示“整体成功标准”。
  - `CompanyStore.swift`：新增 `productDetailAgentCollaborationDefaultDisplayLimit = 3`，产品详情协作链路默认只展示最近 3 条，完整历史走“查看全部”。
  - `OPCCompanyCoreTests.swift`：新增产品详情密度、文案和动态标准标题守门，防止回退。
- **验证**：
  - `swift test --no-parallel` 455/455 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：产品详情指标卡仍显示阶段进度和任务数；“产品进度与下一步”不再重复百分比/任务数；产品目标卡显示“当前待办标准”，协作链路默认为空态且保持紧凑。
- **边界**：不隐藏业务进度和任务状态；只消除重复展示和误导标题。完整协作历史、完整任务看板和验收证据仍有入口。

### 2026-05-05 默认汇报指令集中：终端大厅、员工工作台和检查器共用同一中文指令

- **方向**：Claude Code 并行只读审查指出，默认“运行汇报”指令在终端大厅、员工工作台、右侧检查器和 Store fallback 中有多个近似版本。多份默认文案会造成不同入口行为不一致，也增加后续中文化回退风险。本轮把默认汇报指令集中到单一可见文案常量。
- **实施**：
  - `DisplayFormatting.swift`：新增 `OPCVisibleInterfaceCopy.defaultAgentReportPromptText`，并让 `defaultTerminalPromptPlaceholder` 复用它。
  - `TerminalHallView.swift`、`SelectionWorkspaceView.swift`、`InspectorPanel.swift`、`CompanyStore.swift`：默认汇报、空 prompt fallback 和可见默认文案统一为“汇报你的角色、当前状态和下一步建议。”。
  - `OPCCompanyCoreTests.swift`：新增源码守门，确保默认汇报指令字面量只保留一处，所有入口引用同一常量。
- **验证**：
  - `swift test --no-parallel` 455/455 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：终端大厅输入框默认值为“汇报你的角色、当前状态和下一步建议。”。
- **边界**：不改变用户自定义 prompt、不改变员工执行链路、不改品牌/模型名显示。

### 2026-05-05 员工消息状态标签去重与 footer 语义校正

- **方向**：Claude Code 并行只读审查指出，带审查结果的员工消息可能同时显示消息状态标签和审查结果标签，造成重复；员工工作台溢出 footer 使用“未展开”容易被误解为折叠隐藏。本轮把状态表达改为单一决策结果优先，并把 footer 文案改为“后续还有…下一项会自动浮现”。
- **实施**：
  - `SelectionWorkspaceView.swift`：`AgentMessageRow` 有 `reviewOutcome` 时只显示审查结果标签；没有审查结果时才显示消息状态标签。
  - `CompanyStore.swift`：待审任务、分配任务、工作队列和协作收件箱 overflow summary 改为“后续还有…”，不再使用“未展开”。
  - `OPCCompanyCoreTests.swift`：新增状态标签互斥守门，并加强 footer 文案禁止“折叠/未展开/DisclosureGroup”回退。
- **验证**：
  - `swift test --no-parallel` 455/455 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏抽样验证产品详情和终端大厅默认可见面；状态标签互斥由源码守门覆盖。
- **边界**：不改变消息状态、审查结果、确认逻辑和完整消息中心；只改变默认可见标签与 footer 说明。

### 2026-05-05 员工工作台稳定保活状态减噪：只浮出异常保活关闭

- **方向**：Computer Use 复核发现，员工工作台“模型和权限”和运行状态仍默认显示“保活 开启 / 保活开启”。保活开启是正常稳定运行细节，不是用户需要处理的状态；只有保活关闭才值得浮出。本轮把默认可见状态收口为会话能力和完整日志入口。
- **实施**：
  - `CompanyStore.swift`：`agentDeskProfileChips(forAgentID:)` 在存在运行会话时继续展示“会话”，但仅当 `keepAlive == false` 时追加“保活 关闭”异常 chip。
  - `SelectionWorkspaceView.swift`：员工工作台运行状态详情删除“保活开启”，保留“可继续接收任务 · 完整命令和输出请到终端大厅查看”。
  - `OPCCompanyCoreTests.swift`：更新 `agentDeskProfileChipsAppendSessionFieldsOnlyWhenRuntimeSessionExists`，新增 `agentDeskWorkspaceDoesNotExposeKeepAliveEnabledAsDefaultVisibleCopy`，守住稳定保活状态不回到默认可见 UI。
- **验证**：
  - `swift test --no-parallel` 449/449 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：员工工作台运行状态不再显示“保活开启”；“模型和权限”只显示“会话 已就绪 · 可继续接收任务”，不再显示“保活 开启”。
- **边界**：保活关闭仍作为异常状态浮出；真实会话能力、命令行工具、模型和推理强度仍按来源类型展示。

### 2026-05-05 终端大厅默认任务摘要减噪：默认占位不再重复成卡片摘要

- **方向**：Claude Code 并行复核指出，终端大厅员工卡会把默认输入框占位“汇报你的角色、当前状态和下一步建议。”重复渲染成每张卡的“本轮任务”摘要。默认占位没有新增信息，多个员工卡重复显示会放大噪音。本轮把空输入和默认占位视为无摘要，只有用户输入非默认任务时才显示“本轮任务”。
- **实施**：
  - `DisplayFormatting.swift`：新增 `OPCVisibleInterfaceCopy.defaultTerminalPromptPlaceholder`，供终端大厅默认 prompt 和摘要判断复用。
  - `CompanyStore.swift`：`terminalHallCardTaskDigestLine(prompt:)` 改为返回 `String?`；空输入或默认占位返回 nil，非默认短/长/多行任务保留原来的单行化、60 字截断和“本轮任务：”前缀。
  - `TerminalHallView.swift`：员工卡顶部用 `if let` 渲染任务摘要；摘要为 nil 时完全不占位。
  - `OPCCompanyCoreTests.swift`：更新 `terminalHallCardTaskDigestLineHandlesEmptyShortAndLongPrompts`，守住空/默认占位不渲染、非默认任务仍渲染。
- **验证**：
  - `swift test --filter terminalHallCardTaskDigestLineHandlesEmptyShortAndLongPrompts --filter terminalHallAgentCardTopUsesCompactAccessorsInsteadOfTruncatedCommandPreview --no-parallel` 通过。
  - `swift test --no-parallel` 448/448 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：终端大厅默认提示词仍在输入框，但员工卡顶部不再显示默认“本轮任务”摘要；运行方式、长期会话和任务注入说明仍保留。
- **边界**：不修改员工执行、预检、发车计划和聊天命令里的默认任务兜底；本轮只处理终端大厅员工卡的默认可见摘要。

### 2026-05-05 老板右侧紧凑区元说明减噪：只保留近期汇报

- **方向**：Claude Code 并行只读审查指出，老板在总控台/产品详情等主区已展示完整工作区时，右侧检查器仍显示“右侧只保留沟通 / 主区域已经展示完整工作区...”这类解释界面结构的文案。这是开发期元说明，不是老板需要处理的业务信息。本轮删除该默认可见说明，只保留近期汇报事件。
- **实施**：
  - `InspectorPanel.swift`：`compactRecentReports` 的标题统一为“近期汇报”，删除解释 UI 布局的说明卡片，继续读取 `store.selectedProductBossEvents.prefix(3)`。
  - `OPCCompanyCoreTests.swift`：新增 `bossInspectorCompactRecentReportsDoesNotShowMetaUIExplanation`，守住该区域不再回退到元说明文案。
- **验证**：
  - `swift test --filter bossInspectorCompactRecentReportsDoesNotShowMetaUIExplanation --filter bossControlPanelInInspectorPanelUsesSelectedProductBossEventsAndDropsRawStoreEventsPrefix --no-parallel` 通过。
  - `swift test --no-parallel` 448/448 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：选中老板时，右侧紧凑区只显示“近期汇报”和实际事件，不再显示“右侧只保留沟通 / 主区域已经展示完整工作区”。
- **边界**：老板输入目标、审批和近期汇报仍保留；只删除解释布局的低信息密度文案。

### 2026-05-05 本地占位紧凑摘要减噪：默认卡片不再显示工具 human

- **方向**：老板和本地占位角色的左侧员工卡、右侧检查器顶部、团队卡片仍会通过旧紧凑摘要显示“工具 human · owner”或类似命令式文案。这和本地占位不是执行链路的产品语义不一致。本轮把紧凑摘要按来源类型分支显示。
- **实施**：
  - `DisplayFormatting.swift`：新增带 `BackendType` 的 `opcBackendCompactDisplay(type:command:model:)`。订阅制命令行继续显示“工具 X · 模型”，接口模型显示“接口模型 · 模型”，本地占位显示“本地占位 · 标识”。
  - `ContentView.swift`、`InspectorPanel.swift`、`SelectionWorkspaceView.swift`、`CommandCenterView.swift`：默认卡片和检查器统一调用带来源类型的紧凑摘要 helper，避免各处重复拼“工具”。
  - `OPCCompanyCoreTests.swift`：扩展 `backendDisplayHelpersKeepOnlyToolNameAndChineseFallback`，覆盖本地占位和接口模型紧凑摘要。
- **验证**：
  - `swift test --filter backendDisplayHelpersKeepOnlyToolNameAndChineseFallback --no-parallel` 通过。
  - `swift test --no-parallel` 447/447 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：左侧老板卡显示“本地占位 · owner”，右侧选中老板摘要不再出现 `工具 human · owner`。
- **边界**：真实订阅制命令行员工仍保留工具名和模型名；终端大厅、维护区等技术上下文仍可展示更完整执行链路。

### 2026-05-05 本地占位摘要减噪：员工工作台不再显示命令行字段

- **方向**：本地占位配置面板已收口后，员工工作台和档案底部摘要仍会显示“命令行工具 local / 模型 local / 推理强度高”。这些字段对本地占位没有执行意义，会让老板或配置用户误以为本地占位仍是命令行员工。本轮把本地占位摘要改成只展示来源和占位标识。
- **实施**：
  - `CompanyStore.swift`：`agentDeskProfileChips(forAgentID:)` 按来源类型生成 chip。订阅制命令行继续展示来源、命令行工具、模型、推理强度；接口模型展示来源、模型、推理强度；本地占位只展示来源和占位标识。
  - `InspectorPanel.swift`：员工档案底部摘要对本地占位只显示“占位标识”，不显示命令行工具、模型和推理强度。
  - `OPCCompanyCoreTests.swift`：新增 `agentDeskProfileChipsForLocalPlaceholderHideCommandAndReasoning`，守住本地占位摘要不回退。
- **验证**：
  - `swift test --filter agentDeskProfileChipsForLocalPlaceholderHideCommandAndReasoning --filter employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords --no-parallel` 通过。
  - `swift test --no-parallel` 447/447 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：选中老板进入员工工作台后，“模型和权限”只显示“来源 本地占位 / 占位标识 owner”，不再显示“命令行工具 / 模型 / 推理强度”。
- **边界**：真实命令行员工和接口模型员工仍展示必要的工具、模型和推理强度；技术维护区仍可展示完整运行信息。

### 2026-05-05 本地占位配置减噪：隐藏无意义命令字段

- **方向**：Computer Use 复核来源切换时发现，本地占位来源虽然内部使用 `local`，但配置界面仍展示“命令 local”。本地占位不是可执行模型链路，继续显示命令会把底层执行概念暴露给配置用户。本轮把本地占位配置界面收口为“占位标识”，同时补齐员工档案里切换来源时的默认值同步。
- **实施**：
  - `AddEmployeeSheet.swift`：本地占位分支只显示“占位标识”，不再显示“命令”和“模型/标识”两行。
  - `InspectorPanel.swift`：员工档案本地占位分支只显示“占位标识”和“保存占位标识”，不展示命令字段和推理强度。
  - `CompanyStore.swift`：`updateSelectedAgentBackend(type:)` 在切换到接口模型、订阅制命令行、本地占位时同步默认命令/模型，避免档案编辑路径残留上一来源的默认值；接口模型会自动补上网络权限。
  - `OPCCompanyCoreTests.swift`：新增 `selectedAgentBackendTypeSwitchAppliesVisibleSourceDefaults`，并扩展配置文案守门。
- **验证**：
  - `swift test --filter selectedAgentBackendTypeSwitchAppliesVisibleSourceDefaults --filter employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords --filter addEmployeeBackendSwitchDefaultsAvoidCarryingClaudeModelIntoAPI --no-parallel` 通过。
  - `swift test --no-parallel` 446/446 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：新增员工弹窗切到“本地占位”后只显示“占位标识 local”；员工档案切到“本地占位”后只显示“占位标识 local”和“保存占位标识”，不再显示命令和推理强度。验证后已恢复 CTO 原配置为 `codex / gpt-5.5 / 高`。
- **边界**：本轮只收敛本地占位的配置体验；订阅制命令行和接口模型仍展示各自必要配置项。

### 2026-05-05 新增员工来源切换默认值修复：避免来源间残留默认值

- **方向**：Computer Use 实测新增员工弹窗时发现，从“订阅制命令行”切到“接口模型”后模型字段仍保留 `sonnet`，切到“本地占位”后命令字段仍保留 `claude`。这会把真实 CLI 的默认值带到其他来源配置里，容易误导用户。本轮修正来源切换默认值逻辑：接口/订阅制命令行只替换空值或已知默认/占位模型，本地占位明确使用 `local` 标识。
- **实施**：
  - `AddEmployeeSheet.swift`：切到接口模型时，命令设为 `api-agent`；若模型为空、`sonnet`、`gemini-cli` 或 `local`，自动设为 `gpt-5.5`；切回订阅制命令行时，若模型为空或接口/本地默认值，恢复为 `sonnet`；切到本地占位时，命令和模型/标识都设为 `local`。
  - `OPCCompanyCoreTests.swift`：新增 `addEmployeeBackendSwitchDefaultsAvoidCarryingClaudeModelIntoAPI` 源码守门，防止默认值切换逻辑回退。
- **验证**：
  - `swift test --filter addEmployeeBackendSwitchDefaultsAvoidCarryingClaudeModelIntoAPI --no-parallel` 通过。
  - `swift test --no-parallel` 445/445 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：新增员工弹窗从“订阅制命令行”切到“接口模型”后，模型值显示 `gpt-5.5`，不再残留 `sonnet`；切到“本地占位”后，命令和模型/标识都显示 `local`。
- **边界**：如果用户已经手动输入非默认模型名，切到接口/订阅制命令行时本逻辑不覆盖；本地占位是非执行来源，切换时统一重置为 `local`。

### 2026-05-05 配置占位文案中文化：模型和命令示例去斜杠

- **方向**：配置表单的占位提示也属于默认可见 UI。`codex / claude / gemini`、`gpt-5.5 / sonnet / 留空` 这类斜杠写法偏工程参数表达，本轮统一为中文顿号/逗号表达，保留工具和模型品牌名。
- **实施**：
  - `AddEmployeeSheet.swift`：接口模型占位从“模型，例如 gpt-5.5 / deepseek-chat”改为“模型，例如 gpt-5.5、deepseek-chat”。
  - `InspectorPanel.swift`：命令占位从“codex / claude / gemini”改为“例如 codex、claude、gemini”；模型占位从“例如 gpt-5.5 / sonnet / 留空”改为“例如 gpt-5.5、sonnet，留空使用默认模型”。
  - `OPCCompanyCoreTests.swift`：扩展 `employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords`，禁止这些斜杠式占位文案回退。
- **验证**：
  - `swift test --filter employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords --no-parallel` 通过。
  - `swift test --no-parallel` 444/444 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：新增员工弹窗切到“接口模型”后显示“模型，例如 gpt-5.5、deepseek-chat”。
- **边界**：测试注释和内部协议说明仍可用 `codex / claude / gemini` 表示枚举关系；本轮只改用户可见占位文本。

### 2026-05-05 默认模型摘要显示减噪：斜杠摘要改为工具短句

- **方向**：左侧员工卡和右侧检查器顶部是高频默认可见区域，`codex / gpt-5.5` 这类斜杠摘要更像运维参数，不像产品化状态描述。本轮改为“工具 Codex · gpt-5.5”，保留品牌名和模型名，但降低命令行感。
- **实施**：
  - `DisplayFormatting.swift`：`opcBackendCompactDisplay` 从 `工具名 / 模型名` 改为 `工具 工具名 · 模型名`。
  - `OPCCompanyCoreTests.swift`：`backendDisplayHelpersKeepOnlyToolNameAndChineseFallback` 同步守住不暴露完整路径、不回退到 ` / ` 分隔。
- **验证**：
  - `swift test --filter backendDisplayHelpersKeepOnlyToolNameAndChineseFallback --no-parallel` 通过。
  - `swift test --no-parallel` 444/444 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：左侧员工卡和右侧检查器顶部显示“工具 Codex · gpt-5.5”。
- **边界**：终端大厅、维护区、运行预检仍可展示更完整的执行方式；本轮只改默认卡片和检查器的紧凑摘要。

### 2026-05-05 产品详情本地路径减噪：绝对路径改为工作区摘要

- **方向**：产品详情页是老板/产品负责人高频视图，header 默认显示 `/Users/...` 绝对路径会把本机目录细节暴露到产品主界面。按照老板视角优先和默认界面减噪原则，主视图只展示“本地工作区：目录名”，完整路径继续留在导入报告、本地索引白名单、维护巡检和运维详情。
- **实施**：
  - `DisplayFormatting.swift`：新增 `opcProductWorkspaceDisplayName(_:)`，把绝对路径或 `~` 路径转成“本地工作区：最后一级目录”，空值显示“未设置本地工作区”。
  - `SelectionWorkspaceView.swift`：产品详情 header 从直接 `Text(product?.rootDirectory...)` 改为调用 `opcProductWorkspaceDisplayName(product?.rootDirectory ?? "")`。
  - `OPCCompanyCoreTests.swift`：新增 `productWorkspaceDisplayNameHidesAbsoluteLocalPathInDefaultUI` 和 `productDetailHeaderUsesWorkspaceDisplayNameInsteadOfRawRootPath`，守住不回退到默认可见绝对路径。
- **验证**：
  - 两条定向测试通过。
  - `swift test --no-parallel` 444/444 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：产品详情页显示“本地工作区：Desktop”，不再显示 `~/Desktop`。
- **边界**：本轮不改变 `ProductWorkspace.rootDirectory` 数据语义，也不影响本地文件索引、工作区白名单、导入报告和运维巡检中的完整路径。

### 2026-05-05 员工配置默认可见标签收口：后端改为来源

- **方向**：上一轮真机复核发现员工档案摘要仍显示“后端”。该标签虽是中文，但属于后台实现视角，默认可见 UI 应统一用“来源”表达配置来源，避免把模型/命令链路复杂度推给老板或普通使用者。
- **实施**：
  - `InspectorPanel.swift`：检查器顶部遥测 `InspectorTelemetryCell` 从“后端”改为“来源”；员工档案摘要 `ProfileRow` 从“后端”改为“来源”。
  - `CompanyStore.swift`：员工工作台「模型和权限」chip 数据源从 `label: "后端"` 改为 `label: "来源"`，注释同步更新。
  - `OPCCompanyCoreTests.swift`：`agentDeskProfileChipsReturnFourCoreFieldsForAnyAgentEvenWithoutSession` 改为断言“来源”；`employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords` 增加检查器遥测和档案摘要的防回退守门。
- **验证**：
  - `swift test --filter agentDeskProfileChipsReturnFourCoreFieldsForAnyAgentEvenWithoutSession --no-parallel` 通过。
  - `swift test --filter employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords --no-parallel` 通过。
  - `swift test --no-parallel` 442/442 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：员工档案摘要显示“来源 订阅制命令行”，员工工作台「模型和权限」chip 显示“来源 订阅制命令行”。
- **边界**：内部源码注释、审计报告、运维诊断和长期会话协议仍可使用“后端”指代实现层概念；本轮只改默认可见标签。

### 2026-05-05 员工配置文案本地化：模型来源与密钥提示

- **方向**：延续默认可见界面中文化和减噪原则，员工创建和档案编辑属于老板/技术负责人会直接操作的配置面板，不能继续出现 “Key”“Mac 上” 或把配置入口称为“模型后端/后端”。品牌名、模型名和命令名继续保留原文。
- **实施**：
  - `AddEmployeeSheet.swift`：新增员工说明从“本地占位后端”改为“本地占位来源”；配置分组从“模型后端”改为“模型来源”；选择器从“后端”改为“来源”；运行提示从“Mac 上必须”改为“本机必须”。
  - `InspectorPanel.swift`：员工档案编辑区模型选择器从“后端”改为“来源”；接口密钥占位提示从“已配置，输入新 Key 可替换”改为“已配置，输入新密钥可替换”。
  - `OPCCompanyCoreTests.swift`：新增 `employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords` 源码守门，禁止上述默认可见文案回退。
- **验证**：
  - `swift test --filter employeeConfigurationVisibleCopyAvoidsUnlocalizedKeyAndMachineWords --no-parallel` 通过。
  - `swift test --no-parallel` 442/442 通过。
  - `scripts/build_app_bundle.sh` 通过，`dist/OPCCompany.app` 已重建。
  - Computer Use 已在 MacBook 主屏验证最新 bundle：新增员工弹窗显示“模型来源 / 来源 / 本机必须已经安装对应命令行工具”；员工档案编辑区显示“来源”。
- **后续**：本轮真机复核时发现员工档案摘要区仍有一个默认可见“后端”标签，下一轮继续评估是否应统一改为“来源”，并同步调整相关契约测试。

### 2026-05-05 技术维护文案减噪：摘要优先与完整明细

- **方向**：继续处理默认可见界面里的“折叠/展开”旧话术。用户关注点是信息展示要优化，而不是简单藏起来；本轮只改技术负责人/维护层可见文案，不改变老板视图职责边界。
- **实施**：
  - `AdvancedConsoleIntro` 说明从“默认折叠”改为“默认显示分组摘要，完整配置按需进入”。
  - `MaintenancePreviewText` 的运维明细入口从“展开运维详情”改为“查看完整运维明细”，强调摘要先显示、完整明细按需查看。
- **测试与实测**：新增 `operationsMaintenanceCopyUsesSummaryAndDetailWordingInsteadOfFoldedCopy` 守门；定向测试通过，全量 `swift test --no-parallel` **441/441** 通过；`scripts/build_app_bundle.sh` 已重新生成 `dist/OPCCompany.app`；Computer Use 在 MacBook 主屏验证最新 bundle 中维护详情显示“查看完整运维明细”。
- **边界**：本轮没有改 `OperatorDisclosure` 的高级控制台分组行为，也没有把运维后台推入老板总控台。

### 2026-05-05 candidate ψ 第二阶段补强：终端大厅维护详情可测入口

- **方向**：延续根白名单维护区可视化入口。终端大厅仍保持“默认摘要工作台 + 二级详情”的信息架构，不把维护后台细节堆到主视图；本轮只加强 Computer Use 和人工操作能稳定进入维护详情的路径。
- **实施**：
  - 新增 `OPCTerminalHallDetailSheet` 与 `OPCLocalMaintenanceCenterRoot` 两个可访问锚点，并同步到 `docs/RUNBOOK.md`。
  - 终端大厅顶部“本地维护”改为专用详情 sheet 路由，避免与通用详情 item 路由在辅助功能点击场景下互相干扰。
  - “本地稳定性与命令行运维”摘要卡片保留默认可见摘要，并增加点击/辅助功能动作兜底；完整 `LocalMaintenanceCenter` 仍只在详情面板内展示。
- **测试与构建**：`terminalHallShowsSummaryWorkbenchInsteadOfCollapsedDisclosure`、`localMaintenanceCenterExposesLinkedLocalFileRootAllowlistPreview`、`uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths` 均通过；全量 `swift test --no-parallel` **440/440** 通过；`scripts/build_app_bundle.sh` 已重新生成 `dist/OPCCompany.app`。
- **Computer Use 验证**：在 MacBook 主屏实际操作确认：关闭详情后，终端大厅顶部“本地维护”按钮可重新打开 `OPCTerminalHallDetailSheet`；摘要卡片辅助功能动作“查看本地维护详情”也可打开同一详情；详情内可定位 `OPCLocalMaintenanceCenterRoot`、`OPCLinkedLocalFileRootAllowlistPreview` 与 `OPCLegacyTaskProductMigrationPreview`。
- **边界**：老板总控台不新增维护入口；根白名单仍只展示登记状态，不新增任意路径手填框。

### 2026-05-06 终端大厅本地维护详情：运行健康预览与 MacBook 安全 sheet

- **方向**：本地维护详情里的巡检按钮需要与同列预览一一对应；同时详情 sheet 必须能在 MacBook 主屏真实打开，不能只在大外接屏上可用。
- **实施**：
  - `CompanyStore.selectedProductLatestRuntimeSessionHealthAudit()` 提供当前产品最近一次「运行会话健康巡检」记录。
  - `OperationsSuiteView.swift` 新增 `RuntimeSessionHealthAuditPreview`，按钮下方就地展示最近一次巡检状态、时间和详情；未运行过时使用中文空态和实时巡检文本兜底。
  - `TerminalHallDetailSheet` 从 `frame(minWidth: 1080, minHeight: 720)` 改为 `frame(minWidth: 720, idealWidth: 1080, minHeight: 560, idealHeight: 720)`，保留大屏理想尺寸，同时让 MacBook 主屏可见。
- **测试与构建**：新增 `localMaintenanceRuntimeSessionHealthAuditPreviewUsesChineseSourceWordingAndUpdatesOnAudit` 与 `terminalHallDetailSheetUsesMacBookSafeResponsiveFrame`；定向守门通过，全量 `swift test --no-parallel` **499/499** 通过；`scripts/build_app_bundle.sh` 已重新生成 `dist/OPCCompany.app`。
- **Computer Use 验证**：在 MacBook 主屏启动最新 bundle 后，顶部“本地维护”能打开 `OPCTerminalHallDetailSheet`，详情内可定位 `OPCLocalMaintenanceCenterRoot` 与「运行会话健康巡检预览」；点击「运行会话健康巡检」后预览时间更新到 2026/05/06 15:28，关闭详情后摘要卡维护审计从 4 条变为 5 条并保持「最近维护：运行会话健康巡检 · 通过」。
- **边界**：未改老板总控台、产品详情或员工工作台；未新增折叠隐藏；未改 schema；未改 `project.pbxproj`。

### 2026-05-06 终端大厅详情入口：命名 accessibility action 兜底

- **方向**：Computer Use 真机点击带 `Label(systemImage:)` 的详情入口按钮时，AXPress 偶发只把焦点落在按钮上不触发 SwiftUI 闭包；此前只有 `LocalMaintenanceSummaryCard` 整卡有兜底动作，顶部「本地维护」按钮和架构 / 通信摘要卡的「查看详情」按钮缺少同等兜底。本轮在按钮自身上补一条命名 AXAction 与按钮主闭包写同一 `presentedDetail` case，作为 AXPress 失败时的可寻址替代路径，不改主闭包、不改 sheet 路由、不改尺寸约束。
- **实施**：
  - `Sources/OPCCompanyCore/TerminalHallView.swift` 为以下 4 个按钮各加一条 `.accessibilityAction(named:)`，名称与按钮 `accessibilityLabel` 一致：顶部「本地维护」（`打开本地维护详情` → `.localMaintenance`）、架构摘要卡查看详情（`查看多员工架构体检详情` → `.architecture`）、通信摘要卡查看详情（`查看通信网关与手机指令详情` → `.gateway`）、本地稳定性摘要卡查看详情（`查看本地稳定性与命令行运维详情` → `.localMaintenance`）。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 新增 `terminalHallDetailEntryButtonsExposeExplicitNamedAccessibilityActions`，按 identifier anchor 上下扫描验证每条命名动作存在且闭包写入对应 `presentedDetail` case，并守门现有 identifier、accessibilityLabel、整卡命名动作未被替换。
  - `docs/RUNBOOK.md` 在终端大厅维护区关键控件章节末尾新增「详情入口命名 accessibility action 兜底」段，列出 4 条命名动作与触发路径。
- **测试与构建**：定向跑 `swift test --no-parallel --filter terminalHall`，命名动作守门 + 已有路由/帧守门测试均通过；codex 复核后全量 `swift test --no-parallel` **502/502** 通过；`scripts/build_app_bundle.sh` 已重新生成 `dist/OPCCompany.app`；未改 `project.pbxproj`。
- **Computer Use 验证**：在 MacBook 主屏启动最新 bundle 后，进入终端大厅，对顶部 `OPCTerminalHallLocalMaintenanceHeaderTrigger` 执行命名动作「打开本地维护详情」可打开 `OPCTerminalHallDetailSheet`；详情内可定位 `OPCLocalMaintenanceCenterRoot` 和单一 `OPCRuntimeSessionHealthAuditPreview`，点击「运行会话健康巡检」后维护详情中的巡检记录刷新。实测同时发现相邻 `OPCEvidenceClassificationAuditPreview` 与 `OPCMaintenanceDataPressurePreview` 仍各暴露两条同名 a11y 节点，下一轮继续统一治理维护预览卡锚点。
- **边界**：不改 sheet 尺寸、`TerminalHallDetail` enum、`OperationsSuiteView`、`CompanyStore`、schema、`project.pbxproj`；中文/英文可见文案保持原样。

### 2026-05-05 codex 接回复核：Claude 接管期变更确认 + §5.2 策略决策落档

- **复核范围**：按 `docs/CLAUDE_CODE_HANDOFF.md` §0 / §0.1 / §5 处理 Claude 接管期工作。`swift test --no-parallel` 当前基线 **420/420** 通过；`scripts/build_app_bundle.sh` 已重新生成 `dist/OPCCompany.app`；Computer Use 已在 MacBook 主屏抽样复核任务接力 R1-R9 + 角色继承 R1-R11 的 UI 行为。
- **Computer Use 结论**：终端大厅的结构化指标、员工卡紧凑摘要、长期会话/任务摘要、图标按钮和可访问标签正常；员工工作台的交接表单展开/压缩、档案芯片、老板视角压缩说明正常；老板总控/汇报交付视图仍只暴露目标、进度、决策、交付和业务风险，未把命令行维护细节推给老板。
- **§5.2 策略结论**：
  - candidate λ：保留 `ChatMessage.productID` schema，下一阶段只 retrofit 产品上下文明确的 message 创建点，并引入产品作用域读取；`productID == nil` 仅作为 legacy fallback。
  - candidate λ-2：任务 nil 归属迁移采用技术维护侧“预览 → 手动执行”，不做启动期自动迁移；nil fallback 需等迁移审计为 0 后再和守门测试一起移除。
  - candidate ψ：显式根白名单限定为当前产品根目录 + 用户登记工作区根目录；配置入口在技术维护/产品导入或项目设置侧，不进老板总控。
  - candidate ω：当前不做 actor 大重构；Swift 6 `Mutex` 现代化等项目明确要求 Swift 6 toolchain 后再推进。
  - candidate χ-persistence：R26 forensic 备份保留；后续提示放在技术维护侧非阻塞本地化提示，不做老板业务弹窗。
  - `extractTopLevelStructSlice` 命名选择 A：保留现名；“待修复型 LIMITATION marker”后续默认使用自洽性条件断言守门。
- **文档处理**：本节接管期条目中的 `reviewer = Claude Code 自审` 已统一改为 `codex 已复核（2026-05-05）`。

### 2026-05-05 candidate λ 第一阶段：产品作用域消息读取 + 明确上下文写入 retrofit

- **方向**：执行 codex 接回复核后确定的 candidate λ 分阶段策略。目标不是一次性改完 50+ `ChatMessage` caller，而是先修复最直接的老板/技术负责人当前产品视图跨产品泄漏：`latestCTOBriefing`、`ownerGoal`、老板报告消息读取，以及老板给技术负责人的目标输入。
- **实施**：
  - `CompanyStore.messages(for:in:includingLegacyGlobal:)` 新增产品作用域 accessor，默认包含 legacy `productID == nil` fallback；调用方可用 `includingLegacyGlobal: false` 做严格当前产品读取。
  - `CommandCenterView.latestCTOBriefing` 与 `SelectionWorkspaceView.ownerGoal` 改为 `store.messages(for: store.ctoID, in: store.selectedProductID)`，移除 R12 的 `LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK` 标记。
  - `selectedProductBossReportMessages` 新报告优先走 `productID` 过滤，旧报告保留产品名前缀 fallback，避免历史报告突然消失。
  - `sendMessage`、产品切换提示、老板报告、交接快照、任务风险审批/驳回/复核、live/API chat 回复等“当前产品上下文明确”的路径开始写入 `productID`。（旧自动流水线入口已在 2026-05-05 后续清理中移除，旧 `流水线 ` 任务前缀仅作为历史运行数据清理兼容项保留。）
  - `agentChatPrompt` 的近期对话历史改为当前产品作用域读取，避免 Product A 的员工/技术负责人对话污染 Product B prompt。
- **测试守门**：新增/调整 4 条测试：`productScopedMessagesIncludeCurrentProductAndLegacyFallbackOnly`、`sendMessageStampsSelectedProductAndKeepsCTOChatScoped`、`latestCTOBriefingUsesProductScopedMessagesAccessorAfterLambdaPhaseOne`、`ownerGoalUsesProductScopedMessagesAccessorAfterLambdaPhaseOne`；目标测试 5/5 通过。
- **边界**：仍保留 `messages(for:)` 作为员工全量历史/Inspector/legacy 读取工具；没有执行全量 caller retrofit；`productID == nil` 仍是历史兼容 fallback。

### 2026-05-05 candidate λ 第二阶段：CompanyStore 内 ChatMessage 写入点显式产品归属

- **方向**：继续执行 goal 模式下的 candidate λ 分阶段 retrofit。本轮不使用 Claude Code，只处理 `CompanyStore` 内仍然直接 `ChatMessage(agentID:...)` 的写入点；这些写入点要么绑定默认/重置产品，要么绑定当前产品、任务产品、trace 产品或通信产品。
- **实施**：
  - 默认 bootstrap / reset 默认状态的 8 条初始化消息写入默认产品 `productID`。
  - 项目导入、系统简报、员工创建/加入团队、产品隔离/命令行隔离/终端工作区/健康巡检/架构体检/交接巡检/历史索引与归档等当前产品报告写入 `selectedProductID`。
  - 闭环审计报告使用 `trace.productID`；验收报告使用 `task.productID`；通信网关汇报/手机指令/状态查询使用 `selectedProductID`。
  - 员工命令行执行完成后的 CTO 摘要补上当前产品归属；旧流水线员工通知写入点已在后续死代码清理中删除。
- **测试守门**：新增 `companyStoreChatMessageWritesUseExplicitProductIDAfterLambdaPhaseTwo`，禁止 `CompanyStore.swift` 再出现裸 `ChatMessage(agentID:)` 写入；保留产品作用域 accessor 守门。
- **边界**：测试文件仍可构造 legacy nil `ChatMessage` 验证旧 snapshot 兼容；`messages(for:)` 仍保留给 Inspector/员工全量历史和旧数据读取。

### 2026-05-05 candidate λ 第三阶段：当前产品记忆读取收口

- **方向**：继续收窄 CompanyStore 内“当前产品语义”但仍读全局消息的路径。本轮不调用 Claude Code，不改 Inspector 员工全量聊天历史，只修产品记忆和员工记忆压缩的跨产品污染风险。
- **实施**：
  - `captureDecisionMemoryFromLatestReport()` 改为按 `selectedProductID` 读取老板/CTO 的系统报告，再写入当前产品记忆。
  - `compactAgentMemory(agentID:)` 改为只压缩当前产品下该员工的最近消息，避免 Product A 的对话进入 Product B 的长期记忆。
- **测试守门**：新增 `captureDecisionMemoryUsesSelectedProductScopedMessagesAfterLambdaPhaseThree`、`compactSelectedAgentMemoryUsesSelectedProductScopedMessagesAfterLambdaPhaseThree`、`memoryCaptureAndCompactionUseProductScopedMessagesAfterLambdaPhaseThree`；目标测试 5/5 通过。
- **token/推理强度策略**：本轮按低强度做检索与源码守门定位，中强度做两处小实现，高强度只用于判断 Inspector 全量历史是否应保留；当前运行时不暴露精确 token 计数。

### 2026-05-05 candidate λ-2 产品化入口：旧任务归属手动迁移

- **方向**：执行 §5.2 的 λ-2 策略决定：不做启动期自动迁移，不移除 `selectedProductTasks` 的 legacy fallback；先在技术维护侧提供“预览 → 手动执行”的产品化入口，让旧快照中 `productID == nil` 的任务可显式迁入当前产品。
- **实施**：
  - 新增 `legacyTaskWithoutProductIDCount`、`legacyTaskProductMigrationText()`、`runLegacyTaskProductMigrationForSelectedProduct()`；wrapper 调用既有 R28 helper，写维护类 `VerificationRecord`，写技术事件，保存快照。
  - `LocalMaintenanceCenter` 新增二次确认按钮“迁移未归属旧任务到当前产品”和“旧任务归属迁移预览”；按钮仅技术维护区可见，0 条旧任务时禁用。
  - 终端大厅顶部新增“本地维护”直接入口，作为 Computer Use / 人工操作的稳定维护详情入口；摘要卡片的“查看详情”按钮仍保留。
  - 迁移事件标题纳入老板视图过滤前缀，维护记录纳入 `technicalMaintenanceVerificationTitles`；老板/交付视图不展示这类维护细节。
- **测试与实测**：新增/调整 4 条 λ-2 产品化测试与 3 条既有分类守门；目标测试 9/9 通过，全量 `swift test --no-parallel` 430/430 通过；`dist/OPCCompany.app` 已重建，并用 Computer Use 在 MacBook 主屏验证“本地维护”入口和旧任务迁移预览/按钮可见。
- **边界**：仍保留 `selectedProductTasks` 的 `productID == nil` fallback 和相关 LIMITATION 自洽性测试；后续只有在真实迁移审计长期为 0 后，才单独移除 fallback。

### 2026-05-05 candidate λ 第四阶段：严格当前产品消息读取 + 历史索引 productID 修复

- **方向**：继续收口 candidate λ。第一到三阶段已经让关键 caller 走产品作用域 accessor，但默认还包含 legacy `productID == nil` fallback；本轮把“当前产品语义”的读取切到严格模式，避免旧全局消息继续进入当前产品视图、记忆或 prompt。
- **实施**：
  - `latestCTOBriefing`、`ownerGoal`、`captureDecisionMemoryFromLatestReport()`、`agentChatPrompt`、`compactAgentMemory(agentID:)` 全部改为 `includingLegacyGlobal: false`。
  - `CompanyHistorySQLiteIndex` 的聊天记录索引改为使用 `ChatMessage.productID`，产品过滤搜索可以命中当前产品聊天，也不会把 legacy nil 全局聊天混入产品过滤结果。
- **测试守门**：新增 `captureDecisionMemoryExcludesLegacyNilReportsAfterLambdaPhaseFour`、`compactSelectedAgentMemoryExcludesLegacyNilMessagesAfterLambdaPhaseFour`、`agentChatPromptExcludesLegacyNilRecentMessagesAfterLambdaPhaseFour`，并增强 `sqliteHistoryIndexRebuildsSearchableSnapshotRecords` 与 existing λ 源码守门；定向 7/7 通过。
- **边界**：`messages(for:)` 与 `messages(for:in:)` 默认 legacy fallback 仍保留，供 Inspector 全量历史、旧快照兼容和非当前产品语义调用使用；产品级长期员工记忆仍是下一轮单独处理对象。

### 2026-05-05 candidate λ 第五阶段：产品级员工长期记忆隔离

- **方向**：修复员工自动压缩记忆的跨产品污染。`AgentOperatingProfile.memory` 继续作为员工全局偏好、角色规则和长期身份记忆；由当前产品聊天压缩出来的工作记忆不再写入全局 profile。
- **实施**：
  - `ProductMemoryNote` 增加可选 `agentID`，旧产品记忆缺失该字段时仍 decode 为 `nil`；产品级员工记忆用 `productID + agentID` 精确归属。
  - `compactAgentMemory(agentID:)` 把当前产品近期对话压缩为 `ProductMemoryNote(productID: selectedProductID, agentID: agentID, kind: .summary, ...)`，并限制同一产品同一员工最多保留 12 条自动压缩记忆。
  - `agentSystemPrompt`、`agentExecutionPrompt`、`agentChatPrompt` 与员工工作区 `MEMORY.md` 只注入当前产品下该员工的产品记忆；切换产品后不会带入其他产品的压缩摘要。
  - SQLite 历史索引中的产品记忆记录会保留 `memory.agentID`，方便后续按产品和员工检索。
- **测试守门**：新增/调整 `compactingAgentMemoryWritesProfileAndMemoryFile`、`compactedAgentMemoryDoesNotPolluteOtherProductSystemPromptAfterLambdaFollowup`、`compactedAgentMemoryDoesNotPolluteOtherProductExecutionPromptAfterLambdaFollowup`、`syncedAgentWorkspaceMemoryFileUsesSelectedProductScopedMemoryAfterLambdaFollowup`、`productMemoryNoteAgentIDDefaultsToNilForLegacyDecodeAndRoundtripsScopedAgent`；定向 5/5 通过。
- **边界**：没有移除手工维护的全局 `AgentOperatingProfile.memory`；它仍可用于跨产品员工偏好和职责规则。下一轮继续推进 candidate ψ 显式根白名单。

### 2026-05-05 candidate ψ 第一阶段：本地文件索引显式根白名单

- **方向**：继续处理接管期留下的 `scanLinkedLocalFiles` 路径 allowlist 风险。老板视图不新增任何入口；该能力仍属于技术负责人/终端大厅维护域。
- **实施**：
  - `scanLinkedLocalFiles` 在 R21 `.standardizedFileURL`、R27 symlink 解析和系统路径黑名单之外，新增“已登记工作区根白名单”校验。
  - 白名单来源为当前主状态里的 `ProductWorkspace.rootDirectory` 列表；扫描根的 `rawRoot` 和 `resolvedRoot` 都必须落在已登记根之内，防止 symlink 把索引带到未登记目录。
  - 未通过白名单时写维护类失败验证「本地文件索引被拒绝」和技术风险事件「本地文件索引拒绝未登记根目录」，不写老板消息、不写交付产物。
- **测试守门**：新增 `scanLinkedLocalFilesRejectsSymlinkResolvingOutsideRegisteredWorkspaceRoots`，增强 `scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker` 与 `scanLinkedLocalFilesEnumeratorAndLimitationMarkerStaySelfConsistent`；定向 7/7 通过。
- **边界**：这是一阶段安全门禁；后续还需要把根白名单配置/登记入口产品化到技术维护或产品导入设置侧，不进入老板总控。

### 2026-05-05 candidate ψ 第二阶段：根白名单维护区可视化入口

- **方向**：把本地文件索引根白名单从纯代码策略推进到技术维护区可见入口，避免维护人员不知道当前哪些目录已登记、当前产品根目录是否可索引。
- **实施**：
  - 新增 `linkedLocalFileRootAllowlistText()`，中文展示当前产品、当前根目录、解析后目录、是否已登记、已登记工作区根目录列表和登记方式说明。
  - `LocalMaintenanceCenter` 右侧预览区新增「本地文件索引根白名单」卡片，使用 `OPCLinkedLocalFileRootAllowlistPreview` 作为 Computer Use 稳定定位点。
  - 入口只在技术维护区展示，不进入老板总控台；新增根目录仍通过产品导入或后续项目设置登记。
- **测试守门**：新增 `linkedLocalFileRootAllowlistPreviewShowsRegisteredRootsAndCurrentStatus`、`localMaintenanceCenterExposesLinkedLocalFileRootAllowlistPreview`，并把新 identifier 加入 `uiAutomationIdentifiersAreUniqueAndNonEmptyAndCoverRunbookKeyPaths`；定向 5/5 通过。
- **边界**：本轮提供可视化入口和登记状态，不新增任意路径手填框，避免绕过导入/项目设置的信任边界。

### 2026-05-07 CompanyPersistence.save 失败显式上报与 saveSnapshot 风险事件落地

- **方向**：正式使用阻塞项收口 — 旧版 `CompanyPersistence.save(_:)` 直接吞掉异常是数据丢失风险；磁盘满、沙盒路径不可写或父路径被普通文件占用时，用户必须看到风险信号。本轮只做最小工程修复：persistence 层返回失败，store 层追加一条内存风险事件。
- **核心设计**：
  - `CompanyPersistence.save(_:)` 改为 `@discardableResult` 返回 `Result<Void, Error>`，不再吞错；新增 internal `save(_:to:)` 重载暴露显式 URL 注入点，避免测试需要 mutate 进程级 `supportDirectory` 缓存。
  - `CompanyStore.saveSnapshot()` 显式 `if case .failure` 消费 Result → 调用 private `recordPersistenceFailure(_:)` 在 `events` 头部插入一条 `.risk` 事件（标题「持久化失败」+ localizedDescription），**绝不再次调用 saveSnapshot**（递归 save 会无限失败 + 无限插事件）；连续相同失败做相邻去重，避免高频故障刷屏 events。
  - `CompanyStore.persistSnapshot` 默认指向 `CompanyPersistence.save`，仅供测试注入失败闭包；生产路径不改变调用语义。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyPersistence.swift`：`save(_:)` 签名升级为 `Result<Void, Error>` + 新增 `save(_:to:)` 内部重载；旧的 swallow-comment 移除，docstring 解释 silent-failure 历史 + 升级理由。
  - `Sources/OPCCompanyCore/CompanyStore.swift` line 8448：`saveSnapshot()` 改为消费 Result + 新增私有 `recordPersistenceFailure(_:)` helper（含「不递归」和「相邻去重」两条不变量的 docstring 解释）。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：新增 `companyPersistenceSaveSurfacesFailureWhenSupportPathIsImpossible` —— file-as-directory 构造触发 createDirectory 失败并断言 `save(_:to:)` 返回 `.failure`；再注入失败保存闭包，运行时断言 `saveSnapshot()` 追加一条「持久化失败」风险事件并相邻去重。
- **不动的边界**：唯一 `CompanyPersistence.save` caller（CompanyStore line 8449）已同步更新；`@discardableResult` 保留向后兼容（无其他 caller 出现）；UI / Keychain / 终端 / 通信网关 / Package 文件 / 其他 saveSnapshot 调用点 100% 不动；schema 100% 不动。
- **验证**：`swift test --filter "companyPersistenceSaveSurfacesFailureWhenSupportPathIsImpossible|companyPersistence|Persistence"` 7/7 通过；全量 `swift test --no-parallel` 532/532 通过；`scripts/build_app_bundle.sh` 已重建 `dist/OPCCompany.app`，`CFBundleVersion = 20260506180112`；`swift build` 和 `codesign --verify --deep --strict --verbose=2 dist/OPCCompany.app` 通过。失败可见 = in-memory `.risk` 事件；事件本身不被持久化是故意的，符合「save 失败时不能再 save」语义。

### 2026-05-04 §5.2 最终项落地：LIMITATION 自洽性条件断言推广至 R28+R27 + extractStructSlice 命名复核结论（角色继承期轮 31）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：§5.2 七项 codex 决定级 followup 最后一项 — (a) `extractStructSlice` helper 命名复核（R19 已落地的 `extractTopLevelStructSlice`）+ (b) R15 引入的 LIMITATION 自洽性条件断言模式是否值得推广到所有 LIMITATION 标记。R30 完成后 §5.2 6/7 项已落地，R31 收尾纯文档/测试评估，无产品代码改动（除 marker docstring 加 R31 测试名 traceability 引用）。
- **(a) extractStructSlice helper 命名复核结论**：
  - R19 已抽取的 helper 名为 `extractTopLevelStructSlice(from:structMarker:failureMessage:)` — 比 §5.2 提议的 `extractStructSlice(in:named:)` 更精确（明确「top-level」区别于 nested struct，与实际 R13/R14/R15/R16 用例匹配）
  - **推荐 codex 选 A：保留现名**，关闭 §5.2 此项（R31 评估结论）
  - 选项 B（重命名）回报极低且引入 4 处 caller 同步修改，违反 80/20
- **(b) LIMITATION 自洽性条件断言推广评估结论**：
  - 当前 6 个 LIMITATION marker 实例分两类：
    - 「待修复」型（4 marker / 3 unique）：R12 CTO leak ×2 + R21+R28 tasks nil + R21+R27 path allowlist
    - 「设计意图保全」型（2 marker / 1 unique）：R30 NSLock-protected `@unchecked Sendable` ×2
  - **R30 排除推广**：「设计意图保全」型 marker 是「确认正确实现 + 解释为何绕过编译器静态检查」，不存在「marker 该保留 vs 待修代码该保留」双轴问题，自洽性概念不适用
  - **推广目标确定**：R28 (tasks nil leak) + R27 (path allowlist) 两个「待修复」型 marker — R12 已由 R15 测试覆盖
  - **ROI**：每个推广 = 1 standalone test + 双向条件断言（marker 在 ↔ buggy 调用在）；2 推广 = +2 test，纯回归保险无产品代码改动
- **实施**（2 测试 + 2 marker docstring R31 追溯引用）：
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 新增 R31 MARK 区 + 2 自洽性条件断言测试：
    - `selectedProductTasksFilterArmAndLimitationMarkerStaySelfConsistent`：双向条件验证 R21+R28 marker — 如果 `$0.productID == nil` filter arm 还在 → marker 必须保留 + R28 helper migrateLegacyTasksWithoutProductID 必须保留；反向 — 如果 marker 还在 → filter arm + helper 也必须保留
    - `scanLinkedLocalFilesEnumeratorAndLimitationMarkerStaySelfConsistent`：双向条件验证 R21+R27 marker — 如果 `FileManager.default.enumerator(at: root` 还在 → marker + R27 二层防御（resolvingSymlinksInPath + isSystemReservedPath）必须保留；反向 — 如果 marker 还在 → enumerator 调用必须保留
  - `Sources/OPCCompanyCore/CompanyStore.swift` 两处 marker docstring 各加 R31 自洽性测试名 traceability 引用（line 252 R28 marker + line 5562 R27 marker），无可执行代码改动
- **核心设计：双层防御覆盖率达 100%**：
  - marker 守门（既有 R21）：只验证 marker token 字符串在源码 → 防止单删 marker
  - 自洽性条件断言（R31 推广）：验证 marker + 它守的调用同步存在/同步移除 → 防止「同时删 marker + 调用」的双删 regression
  - 双删 regression 默认会让 marker 守门测试通过（因为 marker 不在 → contains 检查 false，但反向断言 ! contains 为 true），所以单层防御不够
- **测试守门**：418 → **420**（+2）。`swift build` 8.38s pass + 2 R31 测试隔离 0.002s+0.038s 各 pass + 全量 420/420（仅 R23/R24 既知 flaky tmux 1 次失败，隔离重跑 0.763s pass）+ bundle 重建 57.41s。
- **不动的边界**：CompanyStore 可执行代码 100% 不变（仅 marker docstring 加 R31 测试名引用）；CLIAgentRunner 100% 不变；UI 100% 不变；schema / persistence / accessor 100% 不变。
- **降级声明 + Round 31 决策记录**：caller / UI / 行为 100% 不变。无需 Computer Use 真机视觉确认（纯测试加固 + docstring traceability）。按 §7.3 三停止条件：(1) Computer Use 不构成停止，(2) CCB Rubrics 自审 PASS（overall 9.2：safety 9.5 / readability 9.5 / scope 10.0 / consistency 9.0 / correctness 8.0 — correctness 扣分仅因 R30 浮现的 tmux flake baseline 仍存在），(3) 用户未显式 stop。**§5.2 七项 codex 决定级 followup 全部完成**（5 项 R25-R30 引擎部分落地 + R31 自洽性推广 + extractStructSlice 命名结论）— 接管期工程师层 + 引擎层方向真正穷尽。后续推进只剩 codex 决定级 policy（caller retrofit / UI scope / 触发策略 / 目标产品 / fallback 移除时机 / Swift 6 Mutex 现代化 / actor 重构 / extractStructSlice 二选一），需 codex quota 恢复（sentinel `test -f .claude/codex-back`）接手。

### 2026-05-04 候选 ω-sendable 引擎部分落地：CompanyStore 移除 @unchecked Sendable + ProcessOutputBuffer/ProcessTimeoutState LIMITATION 标记（角色继承期轮 30）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 全局安全审计 candidate ω 项 — `CompanyStore: @unchecked Sendable` 跨 9684 行类全面静默编译器 actor 检查。R25 已落地 bare Task 显式 `@MainActor in` 子集，但 `@unchecked Sendable` 本身仍在。R30 按 R28/R29「engine vs policy 分离」模式裁剪 — 落地引擎部分（移除冗余 `@unchecked Sendable` + 给 NSLock 保护的合法 `@unchecked Sendable` 加 LIMITATION 标记），剩余 Swift 6 Mutex 现代化 / actor 重构 / 全文件 Sendable 严格化策略留给 codex policy。
- **核心设计：分类合法性 vs 冗余性**：
  - `CompanyStore` 是 `@MainActor` 隔离类 → `@unchecked Sendable` 冗余（@MainActor 类自动获得 Sendable conformance 在主 actor 边界），编译器移除后 build pass 一次过 = 无 Sendable 违规
  - `ProcessOutputBuffer` / `ProcessTimeoutState` 是 NSLock 保护的可变状态结构 → `@unchecked Sendable` 是**正确设计**而非 tech debt（NSLock 提供 happens-before 保证，符合 `Sendable` 协议语义合约）
- **核心设计：LIMITATION 标记不是「待修复」而是「设计意图保全」**：
  - 区别 R12/R21/R27/R28 的「待 codex 落地修复」标记
  - R30 ProcessOutputBuffer/ProcessTimeoutState marker 是「确认已正确实现 Sendable 但绕过编译器静态检查；解释 NSLock 保护机制 + Swift 6 Mutex 升级路径作为 codex policy」
  - 防止后续 refactor 以为这是 tech debt 而错误移除 `@unchecked Sendable` 引入 build error
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift` line 1：`public final class CompanyStore: ObservableObject, @unchecked Sendable {` → `public final class CompanyStore: ObservableObject {`（移除 `, @unchecked Sendable`）
  - `Sources/OPCCompanyCore/CLIAgentRunner.swift` line 23：`ProcessOutputBuffer` 上方加 `LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-BUFFER` 多行注释 marker（解释 NSLock 保护 + Swift 6 Mutex codex policy）
  - 同文件 line 47：`ProcessTimeoutState` 上方加 `LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-FLAG` marker（同模式）
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：R30 MARK 区 + 3 守门测试（CompanyStore 不再带 `@unchecked Sendable` 源码守门 + ProcessOutputBuffer/ProcessTimeoutState marker 4 关键词守门 each）
- **测试守门**：415 → **418**（+3）。`swift build` pass 12.11s + 隔离 R30 测试 0.001-0.011s 各 pass + bundle 重建 57.12s。
- **不动的边界**：CompanyStore runtime 行为 100% 不变（@MainActor 类内 Sendable conformance 自动）；ProcessOutputBuffer/ProcessTimeoutState 实现 100% 不变（仍 `@unchecked Sendable`，只加上方注释 marker）；caller 100% 不动。
- **新增 flake 调查**：R30 后 `swift test` 全量在并行模式下出现 5-6 个 tmux/persistent-terminal 测试间歇失败（共 13-15 issues），但 6 个隔离重跑 3.487s 全 pass。判定为 R23/R24 既知 flaky 同族（process-spawning 测试在并行 CPU 争抢下 stdin/stdout pipe 饥饿），与 R30 CompanyStore Sendable 改动无关 — R30 仅移除编译器 attribute，runtime 等价。
- **降级声明 + Round 30 决策记录**：caller / UI / 行为 100% 不变。无需 Computer Use 真机视觉确认（runtime 等价 + Sendable 仅编译器静态检查 attribute）。按 §7.3 三停止条件：(1) Computer Use 不构成停止，(2) CCB Rubrics 自审 PASS（overall 9.1：safety 9.5 / readability 9.0 / scope 9.5 / consistency 9.0 / correctness 8.5 — 唯一扣分是 R30 后浮现的 tmux 测试 parallel flake 让 baseline 不再「干净 415/415」），(3) 用户未显式 stop — 继续推进 §5.2 余下 1 项 codex followup。下一轮 R31 候选 = `extractStructSlice` helper 命名复核 + LIMITATION 自洽性条件断言推广评估（§5.2 最后一项，纯文档/测试层评估，无产品代码改动）。

### 2026-05-04 候选 λ schema 引擎部分落地：ChatMessage 加 productID 字段（角色继承期轮 29）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 全局安全审计 candidate λ schema 项 — `ChatMessage` 无 productID 字段，message 全局共享违反多产品隔离铁律。R29 按 R28「engine vs policy 分离」模式裁剪 — 只做 schema additive 引擎部分，让 50 caller retrofit + UI scope + accessor 引入留给 codex policy。
- **核心设计**：
  - **additive 不破坏 caller**：Optional 字段默认 nil + Codable 自动兼容旧 state.json（Optional 字段 decode 缺失自动为 nil，不需 migration script）+ 50+ 现有 caller 全部走 default nil path
  - **裁剪复杂度**：完整 candidate λ 是 hours-scale 工作；R29 只做 schema additive 引擎部分裁剪到 minutes-scale
  - **build 一次过 = 50 caller 无回归硬性证明**
- **实施**：
  - `Sources/OPCCompanyCore/Models.swift` `ChatMessage`：加 `public var productID: UUID?` 字段（位于 id 后 / agentID 前）+ `init` 加 `productID: UUID? = nil` 默认参数 + 完整 docstring 含 R29 标注 / candidate λ schema / engine vs policy / 三类剩余 codex 决策。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：R29 MARK 区 + 3 守门测试（legacy decode 默认 nil + explicit roundtrip 保留 + 源码 5 关键词指针守门）。
- **测试守门**：412 → **415**（+3）。`swift build` 11.16s pass + 全量 415/415（R23/R24 既知 flaky tmux 隔离 pass）+ bundle 重建 56.70s。
- **不动的边界**：50+ 处现有 `messages.append/insert(ChatMessage(...))` caller 100% 不动；UI 100% 不动；现有全局共享行为完全保留。纯 additive 改动。
- **降级声明 + Round 29 决策记录**：caller / UI / 行为 100% 不变。无需 Computer Use 真机视觉确认（runtime 等价 + Codable 向后兼容）。按 §7.3 三停止条件：(1) Computer Use 不构成停止，(2) CCB Rubrics 自审 PASS（overall 9.3），(3) 用户未显式 stop — 继续推进 §5.2 余下 2 项。下一轮 R30 候选 ω-sendable 严格化（最复杂，可能暴露 Sendable 违规）。

### 2026-05-04 候选 λ-2 引擎部分落地：migrateLegacyTasksWithoutProductID 幂等 helper（角色继承期轮 28）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 全局安全审计 candidate λ-2 项 — `selectedProductTasks` 用 `|| productID == nil` fallback 让无产品归属 task 在每产品视图都出现，是 critical cross-product 数据泄漏。R28 落地引擎部分（怎么迁移），policy（何时 / 选什么 / 何时清理 fallback）留给 codex。
- **核心设计**：
  - **engine vs policy 分离**：helper 接受 targetProductID + 返回回填数，不绑定调用策略
  - **幂等性**：第二次调用对同一数据集是 no-op（已回填的不再是 nil）
  - **不调 saveSnapshot**：caller 决定事务边界（multi-step 迁移可能要原子提交）
  - **不校验 targetProductID 合法性**：caller 可能用 sentinel UUID 收纳（Inbox 模式）
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：新增 `public func migrateLegacyTasksWithoutProductID(targetProductID: UUID) -> Int` 含完整 docstring；R21 LIMITATION marker 同步从「待 codex 落地」→「R28 引擎部分已落地，剩余 policy 待 codex」；附带修 R27 helper 注释缩进 bug。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：R28 MARK 区 + 4 守门测试（回填正确性 / 幂等性 / 不调 saveSnapshot 源码守门 / docstring 关键词守门）+ R21 既有守门加 `migrateLegacyTasksWithoutProductID` 指针断言。
- **测试守门**：408 → **412**（+4）。`swift build` 12.82s pass + 全量 412/412（R23/R24 既知 flaky tmux 单独失败，多轮验证与 R28 无关）+ bundle 重建 56.86s。
- **不动的边界**：CompanyTask schema / `selectedProductTasks` filter / 现有 caller 100% 不动；helper 暂未被任何 caller 调用 — 等 codex 决定 policy。
- **降级声明 + Round 28 决策记录**：caller 行为 100% 不变（helper 离线工具）。无需 Computer Use 真机视觉确认。按 §7.3 三停止条件：(1) Computer Use 不构成停止，(2) CCB Rubrics 自审 PASS（overall 9.0），(3) 用户未显式 stop — 继续推进 §5.2 余下 3 项。下一轮 R29 候选 λ schema migration（最复杂，需详细 scope report 给用户授权）。

### 2026-05-04 候选 ψ 部分落地：scanLinkedLocalFiles 加 symlink 解析 + 系统路径黑名单（角色继承期轮 27）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 全局安全审计 candidate ψ 项 — `scanLinkedLocalFiles` 用户可写 root 字符串可能（a）经 symlink 逃逸到系统目录，（b）直接被填为 `/usr` 等系统路径污染 artifact 列表。R27 落地 ψ 的安全护栏部分，剩余「显式根白名单」（`~` 子目录或注册根）仍是产品策略层决定。
- **核心设计：分层 canonicalization**：symlink 解析仅用于安全判定；artifact 写入保留原 path 不改用户可见语义。系统路径黑名单 6 个（/System、/private/var/db、/private/etc、/usr、/bin、/sbin），匹配带 trailing-slash 防 `/usrFoo` 误命中。越界写 `.failed` verification + `.risk` event 提升可观测性（不静默）。
- **实施**：
  - `Sources/OPCCompanyCore/CompanyStore.swift`：`scanLinkedLocalFiles` 加双重黑名单判定（rawRoot OR resolvedRoot 命中即拒绝）+ `.failed` verification「本地文件索引被拒绝」+ `.risk` event；新增 `fileprivate static func isSystemReservedPath(_:)` helper；`technicalMaintenanceVerificationTitles` 登记新标题（caller 完整性补全）；R21 LIMITATION marker 文本同步指明 R27 部分落地。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：R27 MARK 区 + 4 守门测试（system path 拒绝 / symlink 越界拒绝 / happy path 维持 / 黑名单源码守门）+ R21 既有守门断言扩展。
- **测试守门**：404 → **408**（+4）。`swift build` 12.56s pass + 全量 408/408（R23/R24 既知 flaky tmux 隔离 0.752s pass）+ bundle 重建 63.68s。
- **不动的边界**：CompanySnapshot / schema / 其他 method / UI / accessor 100% 不动；只 `scanLinkedLocalFiles` 内部加拒绝分支 + 1 helper + 1 verification 分类登记。
- **behavior change 声明**：旧版本 root=/usr 静默扫描 → 污染 artifact；新版本拒绝扫描 + 显式 verification。**有意提升可观测性**，建议 codex 复核后在用户 UI 加配置说明。
- **降级声明 + Round 27 决策记录**：happy path 等价（用户可写目录索引仍工作），越界路径从静默升级为显式拒绝。无需 Computer Use（变化由 contract test 覆盖）。按 §7.3 三停止条件：(1) Computer Use 不构成停止，(2) CCB Rubrics 自审 PASS（overall 9.0），(3) 用户未显式 stop — 继续推进 §5.2 余下 4 项。下一轮 R28 候选 λ-2 数据迁移 helper。

### 2026-05-04 候选 χ-persistence 落地：CompanyPersistence.load() decode failure 路径加 forensic 备份（角色继承期轮 26）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 全局安全审计 candidate χ-persistence 项 — `CompanyPersistence.load()` 原本 `try? Data + try? decode` 双层吞错把「文件不存在」和「decode 失败」合并为「return nil → caller bootstrap」，损坏数据被悄悄覆盖、无 forensic 痕迹。R26 落地最小侵入修复：caller 行为不变（仍然 return nil → bootstrap），但磁盘留 forensic 副本便于事后调查。
- **核心设计：forensic 副本而非阻塞修复**：
  - 备份失败本身静默吞错（应用启动优先于 forensic）
  - 文件名带 ISO8601 fractional seconds 时间戳避免互相覆盖
  - reason sidecar `.reason.txt` 记录 decode 错误详情便于调查
  - happy path 完全不变（成功 decode → snapshot；文件不存在 → nil）
- **实施**：
  - `Sources/OPCCompanyCore/CompanyPersistence.swift` `load()` 重写（双层 do/catch）+ 新增私有 helper `backupCorruptedState(at:payload:reason:)`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift` 新增 R26 MARK 区 + 3 守门测试：corrupt path 全链路 + missing != corrupt 关键差异 + 源码 candidate χ-persistence/R26/backupCorruptedState 指针守门。
- **测试守门**：401 → **404**（+3）。`swift build` 7.72s pass + 全量 404/404（R23/R24 既知 flaky tmux 隔离 0.765s pass）+ bundle 重建 62.54s。
- **不动的边界**：CompanySnapshot Codable 结构 / schema / save() / caller bootstrap 路径 / CompanyStore / UI 100% 不动；仅 load() 内部增加 forensic 备份分支。
- **降级声明 + Round 26 决策记录**：caller 行为对外完全等价（return 值不变），只在 disk 增加 forensic 副本。无需 codex Computer Use 真机视觉确认。按 §7.3 三个停止条件：(1) Computer Use 不构成停止（caller 等价），(2) CCB Rubrics 自审 PASS（overall 8.9），(3) 用户未显式 stop — 继续推进 §5.2 余下 5 项。下一轮 R27 候选 ψ symlink 解析 + 系统路径黑名单。

### 2026-05-04 候选 ω-task 子集落地：CompanyStore.swift 4 处 bare Task 显式 @MainActor 标注（角色继承期轮 25）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：用户 2026-05-03 显式授权「我让你接手codex的职责和工作内容，就是想让你做出和codex一样的效果的。如果你明白了要怎么做，就继续执行下去」，明确许可降级身份按 codex 实际标准（handoff §7.3 三停止条件 + §7.5「大改前小步汇报范围」）执行 §5.2 七项 codex 决定级 followup。同时纠正 engineer_layer_boundaries memory 早期我自写的「3 类 outright 禁止」过于保守误读 — codex 实际标准是「scope report → user authorize → proceed」工作流，不是「等 codex 回来」。R24 「工程师层方向穷尽」结论需要重新解读：是「过去自定义边界内的任务穷尽」，不是「真正的工程师层穷尽」。
- **核心问题**：候选 ω 原描述说「30+ 处 bare Task」，实际 grep 全 `Sources/OPCCompanyCore/` 只有 4 处在 `CompanyStore.swift` + 2 处在 `OperationsSuiteView.swift`。后者已用 `await MainActor.run` 显式 hop，保留不动；前者 4 处属于 `@MainActor` 隔离类的 bare Task，runtime 上自动继承主 actor 上下文（SE-0338），但显式标注能在 (a) 方法日后去隔离化、(b) 闭包逃逸到 nonisolated 上下文、(c) 阅读者无需查类签名 三个场景下保住意图。R25 实施这 4 处显式标注。
- **实施**（4 处单点编辑，runtime 行为不变）：
  - `Sources/OPCCompanyCore/CompanyStore.swift` line 7266 `dispatchTeamLeadReportThroughGateway()`：单行 `Task { await ... }` → 多行 `Task { @MainActor in await ... }`。
  - 同文件 line 7613：`Task {` → `Task { @MainActor in`（命令行流式执行 Task，含内嵌 `Task { @MainActor in` chunk hop）。
  - 同文件 line 7757：`Task {` → `Task { @MainActor in`（聊天回复 Task）。
  - 同文件 line 7800：`Task {` → `Task { @MainActor in`（API chat runner Task）。
- **测试守门**：`swift build` 9.40s pass。`swift test` 全量 401/401 维持（隔离重跑 `persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection` 0.583s 通过，确认 R23/R24 既知 flaky 与 R25 无关）。`scripts/build_app_bundle.sh` 57.81s 通过 → `dist/OPCCompany.app` 重建成功。
- **不动的边界**：`OperationsSuiteView.swift` 2 处 Task 不动（已用 `await MainActor.run` 显式 hop，加 `@MainActor in` 会让现有 hop 显得冗余但不破坏）；测试代码不动；schema/API 不动。
- **engineer_layer_boundaries memory 同步纠错**：将「3 类 outright 禁止（schema migration / test infra convention / API evolution）」改写为「§7.5 scope report → user authorize → proceed 工作流」，对齐 codex 实际标准。Why 段引用用户 2026-05-03 直接授权。
- **降级声明 + Round 25 决策记录**：本轮无产品行为改动 / 无 UI 行为改动 / 无 schema 改动 / 无 API 改动 / 无测试改动；仅 4 处 closure attribute 显式化。runtime 等价（@MainActor 类内 bare Task 本就继承主 actor），无需 codex Computer Use 真机视觉确认。按 §7.3 三个停止条件：(1) Computer Use 不构成停止（runtime 等价），(2) CCB Rubrics 自审 PASS（correctness 9.0 / readability 8.5 / safety 8.0 / consistency 9.0 / scope 9.0），(3) 用户未显式 stop — 继续推进 §5.2 余下 6 项。下一轮 R26 候选 χ-persistence 备份逻辑（CompanyPersistence.load() decode failure 路径加备份-bootstrap）。

### 2026-05-04 §0 brief E 主题分组加 R23 行 + 工程师层任务穷尽收尾标记（角色继承期轮 24）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R23 完成测试 helper 抽取后，docs/CLAUDE_CODE_HANDOFF.md §0 brief E 主题分组只覆盖到 R22；R23 同样属于 E 主题但缺位。同时 R23 完成后工程师层方向基本穷尽，需要给 codex 复核时一个明确的「工程师层穷尽」收尾标记，避免还在找「下一轮做什么」。
- **实施**：纯 docs/CLAUDE_CODE_HANDOFF.md doc 同步 + 本条 §11 entry — last-updated 行 / §0 brief E 主题分组 / §0.1 表头 / §4 detailed record（含工程师层方向穷尽七大类汇总 + §5.2 七项 codex 决定级 followup 列表）。
- **测试守门**：401/401 维持（纯 doc，无测试增减）。
- **工程师层方向穷尽（截至 R24）七大类**：
  1. 老板视图 selectedProductBoss* accessor 体系（任务接力 R8-R9 + 角色继承 R5/6/8/9/10/11）已完成
  2. 员工 desk 信息密度收敛（角色继承 R1-R7）已完成
  3. LIMITATION 标记体系（R12 + R21×2）3 个标记落地，正解依赖 codex schema/数据迁移/产品策略
  4. UI 文案-行为耦合契约 pattern（R13-R16）4 个核心面板全覆盖
  5. 测试 helper DRY（R19/R20/R23）3 个 helper 累计 -189 行；R20 时刻意保留的边界已 R23 收口
  6. 文档/索引维护（R17/R18/R22/R24）brief / §5 / 主题分组持续同步
  7. 全局代码审计（R21）3-agent 并行 → 0 工程师层 critical 漏修 + 4 项 codex policy decision 写入 §5.2
- **§5.2 余下 7 项 codex 决定级 followup**：candidate λ schema / λ-2 数据迁移 / ψ 路径 allowlist / ω Sendable 严格化 / χ-persistence 备份 / extractStructSlice helper 命名复核 / LIMITATION 自洽性条件断言推广评估 — 全部需要 codex CTO 决定级权限，等 codex quota 恢复（sentinel `test -f .claude/codex-back`）接手。
- **不动的边界**：产品代码 / 测试代码 / 测试基础设施 100% 不动；仅 §0 brief / §0.1 / §4 / §11 doc 同步。
- **降级声明 + Round 24 决策记录**：本轮无产品行为改动 / 无 UI 行为改动 / 无 schema 改动 / 无 API 改动 / 无测试改动，无需 codex Computer Use 真机视觉确认。按 §7.3 三个停止条件：(1) Computer Use 不构成停止条件（R12-R24 都不需真机），(2) CCB Rubrics 不构成停止条件（reviewer = codex 已复核（2026-05-05）），(3) 用户未显式 stop — 本助手按用户「continuous autonomous loop」精神不主动停，但工程师层方向穷尽 → 后续轮次只能是更小的 doc 同步 / brief 微调，每轮新增价值递减。

### 2026-05-03 测试 helper loadOPCCompanyCoreSwiftFileURLs 抽取去除 R20 时保留的 3 处目录遍历模式 + silent-failure 升级（角色继承期轮 23）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R20 抽 `loadOPCCompanyCoreSource(_ relativePath:)` helper 时刻意保留 3 处「遍历整个 `Sources/OPCCompanyCore` 目录」的 `sourcesURL` 模式不合并 — 当时理由是「保持 helper 职责单一（单 file load）」。R22 brief 同步后回看，3 处目录遍历模式凑齐、单一职责（目录遍历 vs R20 单 file load）后抽 helper 收益足够。
- **问题诊断 + 附带修复**：
  - 现状：3 处 callsite 各 5-8 行 URL + directory 拼装重复（site 1 = 7 行 / site 2 = 7 行 / site 3 = 8 行 含 `(try? ... ?? [])` silent failure 兜底）。
  - silent failure 隐患：site 3 `coreSourcesMustNotStartInboundHTTPListeners` 用 silent ?? [] — 如果 directory 读不到（测试基础设施 broken / Sources 被删 / 路径上溯 bug），files 会变 [] → 下游 `for file in files where content.contains(api)` 完全跳过 → `#expect(leaks.isEmpty)` 因为 leaks == [] 通过 → forbidden-pattern 守门假阳性通过。site 3 末尾的 `#expect(!files.isEmpty)` 兜底防御能 catch 但是多步 silent → expectation 链路不如直接 throw。
- **核心设计：fileprivate helper + 严格 throw + 两 helper 互相指针**：
  - `loadOPCCompanyCoreSwiftFileURLs() throws -> [URL]`：返回 `Sources/OPCCompanyCore/*.swift` URL list（非递归子目录）；directory 读失败 throw（非 silent return []）。
  - **职责单一不强行通用化**：仅遍历 + 返回 URL list，不 load source（让 caller 决定是否 skip 后再 load — 例如 site 2 跳过 CompanyStore.swift 9684 行）。
  - **R20 docstring 同步更新**：MARK 区从「轮 20 抽取」→「轮 20 抽取 + 轮 23 扩展」；R20 helper 注释末段从「那类测试已用 `sourcesURL` 模式」→「请用 `loadOPCCompanyCoreSwiftFileURLs()`（角色继承期轮 23 抽取）」— 两 helper 互相指针。
- **实施**（3 处 callsite + 1 处 helper 定义 + 1 处 R20 docstring 修订）：
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：R20 helper 下方加 R23 helper + docstring；R20 helper docstring 末段改为指 R23。
  - 3 处 callsite 替换：每处 5-8 行 → 1 行 `try loadOPCCompanyCoreSwiftFileURLs()`。
  - site 3 附带 silent failure 升级：`(try? ...)?.filter { ... } ?? []` → `try ...`；末尾 `#expect(!files.isEmpty)` 保留作防御性额外断言。
  - 0 行业务源代码改动 — 纯测试代码 DRY 重构 + silent-failure 升级。
- **测试守门**：401/401 全过（纯重构无测试增减）。`swift test --filter swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` 0.038s pass（site 1 等价性证明）；已知 flaky tmux 测试并行模式 exit 124，隔离跑 0.751s pass。
- **不动的边界**：
  - 产品代码 100% 不动（仅 Tests/ 内重构）
  - 5-01 红线 1 守住：纯测试代码 DRY 重构 + silent-failure 升级（更严格 = 更安全）
  - 测试基础设施约定 100% 不动 — R20 模式延续到 R23，两 helper 共存职责清晰互相指针
- **降级声明 + Round 23 决策记录**：本轮无产品行为改动 / 无 UI 行为改动 / 无 schema 改动 / 无 API 改动 / 无测试基础设施约定演进，无需 codex Computer Use 真机视觉确认。R19+R20+R23 三轮 helper 抽取累计去除 ~189 行测试代码重复（净 -141 行 helper docstring 计入），R20 当时刻意保留的边界已被 R23 安全收口 — 测试代码 DRY 工程师层方向基本穷尽。§5.2 余下 7 项 codex 决定级 followup（candidate λ / λ-2 / ψ / ω / χ-persistence / extractStructSlice helper 命名复核 / LIMITATION 自洽性条件断言模式）仍是 codex CTO 决定级，等 codex 配额恢复。

### 2026-05-03 §0 onboarding brief 顶部 stale state 同步至 R21 现状（角色继承期轮 22）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R21 完成全局代码审计 + 4 项新 candidate 写入 §5.2 后，docs/CLAUDE_CODE_HANDOFF.md §0 onboarding brief 顶部数字仍是 R17 重写时的 stale state（25 轮 / 16 角色继承轮 / 测试基线 399 / 3 项 codex followup）。codex 配额恢复后第一件事是读 §0 brief，stale 数字会让其需要 cross-check §0.1 表 / §11 / §5.2 才能拼出真实状态 — onboarding 60 秒变 5 分钟。本轮纯 doc-only 同步，沿用 R17/R18 文档维护轮次模式。
- **问题诊断**：
  - §0 brief 顶部说「两期 25 轮」「角色继承期 16 轮 +43」「3 项 codex followup」；实际：30 轮 / 21 角色继承轮 +45 / 7 项 codex followup（含 R21 新增 4 项）。
  - §0 brief 主题分组只覆盖 R1-R17（C 主题只 1 个 LIMITATION，E 主题只 R17）；R18-R21 完全缺位。
  - §0 brief 第 3 步「Computer Use 复核」说「轮 12-16 全是测试守门」；实际 R12-R21 都是，范围应扩到 R12-R21。
- **实施**（仅 docs/CLAUDE_CODE_HANDOFF.md 改动 + 本条 §11 entry）：
  - 顶部 last-updated 行 R21 → R22 + 简要描述。
  - §0 brief 三处替换块 — 顶部 4 件事段 + 接管期成果两句话段 + 角色继承期主题分组段（C 扩展至 3 个 LIMITATION，E 改名「文档/索引/测试 helper 维护 + 全局审计」加 R18-R22 五条）。
  - §0.1 表头加 R22 行；§4 加 R22 detailed record；§4.5 加 candidate ω-engineer-doc 行；§6 加 4 行 R22 命令历史。
- **测试守门**：401/401 全过（纯 doc 改动 — 无测试增减）。`swift test` + `swift build` 跑过确认。
- **不动的边界**：
  - 产品代码 100% 不动 — 0 行业务/产品/Schema/API/Persistence 改动
  - 测试代码 100% 不动 — 0 行测试改动（401/401 基线保持）
  - §0.2/§0.3/§0.4/§0.5/§0.6/§1/§2/§3/§5/§7 100% 不动
  - 5-01 红线 1 守住：纯 doc-only 同步
- **降级声明 + Round 22 决策记录**：本轮无产品行为改动 / 无 UI 行为改动 / 无 schema 改动 / 无 API 改动 / 无测试改动 / 无产品代码改动 / 无测试基础设施约定演进，无需 codex Computer Use 真机视觉确认。本轮兑现 R17/R18 doc 维护轮次模式 — onboarding brief 必须与 §0.1 表 / §11 / §5.2 保持 single source of truth 一致。R21 新增 4 项 codex followup（candidate λ-2 / ψ / ω / χ-persistence）已在 §0 brief 第 4 步显式列出。工程师层后续可执行方向已基本穷尽 — 待 codex quota 恢复（sentinel `test -f .claude/codex-back`）接手 7 项 codex 决定级 followup。

### 2026-05-03 全局代码审计后落地 2 处工程师层防御性 LIMITATION 标记加固（角色继承期轮 21）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：用户指令「先执行你能执行的任务，做完以后再做全局代码审计；所有检查完直接进行修复」。R20 后工程师层 DRY 重构方向已无新增高信号密度目标，转入审计阶段。后台并行启 3 个审计 agent（dead-code / logic-inconsistency / security & bug），按"工程师层 vs codex 决定级"分流结果。
- **审计三方对账**：
  - dead-code：0 actionable findings；codebase 干净（0 TODO/FIXME / 0 dead private funcs / 0 skipped tests / 5 处 medium-confidence 注释经核实皆 fallback 文档）。
  - logic-inconsistency：7 findings → 0 工程师层修复（3 false positives：grep 漏 Tests/ + 注释 scope 误读 + 守门测试已存在；4 项 codex 决定级 policy decision：productAgents fallback / error-handling consistency / accessor 命名约定 / event filter 白名单）。
  - security & bug：5 findings → 2 项工程师层落地 + 3 项 codex 决定级 followup（详见 docs/CLAUDE_CODE_HANDOFF.md §5.2）。
- **核心设计：复用 R12 LIMITATION 标记模式 + R20 helper 守门**：
  - R12 已建立的 LIMITATION 模式：源码上方多行注释 + LIMITATION token + 「正解 = candidate X」指针 + 守门测试名 grep 锚点。
  - 守门测试用 R20 `loadOPCCompanyCoreSource` helper 加载源码 + 多条 `#expect` 断言 token / candidate 指针 / 守门测试名 / R21 加固调用都不被悄悄抹除。
- **实施**（2 处源码加 LIMITATION 注释 + 1 处源码追加 .standardizedFileURL + 2 条守门测试）：
  - `Sources/OPCCompanyCore/CompanyStore.swift:240`：`selectedProductTasks` 上方加 9 行 `LIMITATION-CROSS-PRODUCT-TASKS-NIL-LEAK` 注释，记录 `productID == nil` 任务跨产品视图泄漏（违反 CLAUDE.md 多产品隔离铁律）；简单删除 `|| $0.productID == nil` arm 会让历史 nil 任务从所有产品消失（数据迁移决定级），正解 candidate λ-2 留 codex；守门 `selectedProductTasksCarriesNilLeakLimitationMarker`。
  - `Sources/OPCCompanyCore/CompanyStore.swift:5539`：`scanLinkedLocalFiles` 加 8 行 `LIMITATION-LINKED-LOCAL-FILES-PATH-ALLOWLIST` 注释 + `URL(fileURLWithPath:).expandingTildeInPath` 后追加 `.standardizedFileURL`（折叠 `..` 段，对 well-formed 输入无可观察变化 — OS 在 syscall 时也会做同样折叠）；symlink 解析 + root allowlist 是产品策略级 candidate ψ 留 codex；守门 `scanLinkedLocalFilesCarriesPathAllowlistLimitationMarker`。
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`：在 R12 LIMITATION 守门测试后新增 `MARK: - 安全审计 LIMITATION 标记守门（角色继承期轮 21）` 区 + 2 个守门测试，每个含 3-4 条 `#expect` 断言。
- **测试守门**：399 → **401** 全过（+2 LIMITATION 守门）。`swift test` 全量通过；已知 SourceKit cache lag 9 处假阳性是 R7/R10 既有 issue，与 R21 无关。
- **不动的边界**：
  - 产品行为代码 100% 不动 — `scanLinkedLocalFiles` 的 `.standardizedFileURL` 折叠对 well-formed 输入与原行为一致；`selectedProductTasks` 计算逻辑 100% 不动。
  - Schema 100% 不动（candidate λ / λ-2 留 codex）
  - API 100% 不动（candidate ω 留 codex）
  - Persistence 契约 100% 不动（candidate χ 留 codex）
  - 5-01 红线 1 守住：纯防御性 LIMITATION 标记 + 守门测试 + 路径折叠加固，0 业务行为改动
  - 测试基础设施约定 100% 不动 — 完全复用 R12 LIMITATION 守门模式 + R20 `loadOPCCompanyCoreSource` helper
- **降级声明 + Round 21 决策记录**：本轮无产品行为改动 / 无 UI 行为改动 / 无 schema 改动 / 无 API 改动 / 无 Persistence 契约改动 / 无测试基础设施约定演进，无需 codex Computer Use 真机视觉确认。LIMITATION 标记体系扩张至 3 处（R12 CTO message leak + R21 tasks nil leak + R21 path allowlist），3 处都用 R12 模式 — 「LIMITATION 自洽性条件断言模式」§5.2 第 3 项已凑齐 3 个 LIMITATION 样本，可在 codex 复核时一并评估是否推广 R15 自洽性条件断言到所有 LIMITATION 守门。安全审计另产生 candidate ω/χ-persistence/λ-2/ψ 四项 codex 决定级 followup，写入 §5.2。

### 2026-05-03 测试 helper loadOPCCompanyCoreSource 抽取去除 27 处源码加载代码重复（角色继承期轮 20）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：R19 抽取了 `extractTopLevelStructSlice` helper 解决 4 处切片定位重复后，本助手扫描整个测试文件继续找 DRY 模式，发现 `let url = URL(fileURLWithPath: #filePath) .deletingLastPathComponent() ×3 .appendingPathComponent("Sources/OPCCompanyCore/<file>.swift")` + `let source = try String(contentsOf: url, encoding: .utf8)` 这套 6 行 URL 加载块在源码扫描类测试中重复了 27 次（含 20 处 `url`-named + 2 处 `companyStoreURL` + 1 处 `viewURL` + 1 处 `inspectorURL` 单 file + 1 处 3-URL 多 file 测试 = 27 处）。每处 6 行 × 27 = 162 行重复，是 R19（32 行）的 5 倍。
- **问题诊断**：
  - 现状：源码扫描类测试都要拼"测试文件 → 上溯 3 层 → 项目根 → Sources/OPCCompanyCore/ → 文件名"完整 URL，每处 6 行 boilerplate；多 file 测试（`bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor`）甚至要重复 3 次拼装 = 18 行。
  - 后果：DRY 违规 27×6=162 行；后续要在该模式上加新源码扫描测试时还要继续 copy-paste；URL 拼装逻辑出 bug（如项目根上溯层数变化）时要在 27 处同步修。
- **核心设计：fileprivate `loadOPCCompanyCoreSource(_ relativePath: String) throws -> String`**：
  - 内嵌 `#filePath` 解析为 helper 所在源文件（即 OPCCompanyCoreTests.swift），与所有 caller 相同 — 接口最小化（无需 `file: StaticString = #filePath` 默认参数）。
  - **职责单一不强行通用化**：仅适用于读取单个 `.swift` 源文件；对于需要遍历整个 `Sources/OPCCompanyCore` 目录的测试（如 `swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords`，3 处 `sourcesURL` 模式）不强行合并以保持职责单一。
  - **fileprivate 限定 scope**：放在 R19 helper 上方的新 MARK 区，仅 OPCCompanyCoreTests.swift 内部使用，不暴露到测试目标包外。
- **实施**（27 处 callsite + 1 处 helper 定义）：
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`（R19 helper 上方）：新增 `MARK: - 源码扫描类测试共享 helper（角色继承期轮 20 抽取）` 区 + helper 函数 + 文档注释（适用边界 / 不通用提醒 / 上溯路径解释）。
  - 20 处 `url`-named callsite：通过 5 批量 `replace_all`（按 filename：TerminalHallView/CommandCenterView/InspectorPanel/OperationsSuiteView/SelectionWorkspaceView）每组同时收口，每处 6 行 → 1 行。
  - 2 处 `companyStoreURL` callsite：单独编辑（其中一处含 `// OPCCompanyTests/` `// Tests/` `// OPCCompany/` 路径解释注释；refactor 后该解释由 helper docstring 接收，等价知识保全）。
  - 1 处 `viewURL` callsite + 1 处 `inspectorURL` 单 file callsite：单独编辑。
  - 1 处 3-URL 多 file 测试（`bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor`）：18 行 URL 拼装 → 3 行 helper 调用，DRY 净收益最大单测。
  - 0 行业务源代码改动 — 纯测试代码 DRY 重构。
- **测试守门**：399/399 全过（本轮无测试数量增量，纯重构）。多 file 测试 `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor` 隔离跑 0.012s pass，证明 helper 调用与原内联 URL 拼装行为完全等价。已知 flaky tmux 测试（`persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection`）并行模式 exit 124 timeout，隔离跑 0.751s pass — 与本轮重构无关。
- **不动的边界**：
  - §0/§1/§2/§3/§4/§5/§6/§7 100% 不动
  - 产品代码 100% 不动（仅 Tests/ 内重构）
  - 3 处 `sourcesURL` directory 遍历模式（`swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` 等）100% 不动 — 不合并以保持 helper 职责单一
  - 5-01 红线 1 守住：纯测试代码 DRY 重构，不动产品行为
- **降级声明 + Round 20 决策记录**：本轮无产品代码改动 / 无 UI 行为改动 / 无 schema 改动 / 无测试基础设施约定演进，无需 codex Computer Use 真机视觉确认。重构等价性已通过 399/399 全量测试 + 多 file 测试隔离跑全过证明。本轮承接 R19 工程师层 DRY 重构方向 — R19 节省 16 行（4 sites × 4 行减幅），R20 节省约 135 行（27 sites × 5 行减幅），两轮 helper 抽取累计去除 ~167 行测试代码重复，未来在该 pattern 上加新测试可直接复用。§5.2 余下两项（candidate λ ChatMessage.productID schema 迁移 / LIMITATION 自洽性条件断言模式评估）仍是 codex CTO 决定级，等 codex 配额恢复（sentinel `test -f .claude/codex-back`）接手。

### 2026-05-03 测试 helper extractTopLevelStructSlice 抽取去除 R13/R14/R15/R16 4 处切片代码重复（角色继承期轮 19）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：用户在 R18 停止评估后明确指令「你先执行你能执行的，到时候统一让 codex 来接手验证」— 把"工程师能做 / codex 验证"明确拆分。从 §5.2 三项 codex 决定级 followup 中挑出最贴工程师层、可立即执行、不动产品 schema、不动测试基础设施约定的那条：测试 helper extractTopLevelStructSlice 抽取。
- **问题诊断**：
  - 现状：R13/R14/R15/R16 四个文案-行为耦合契约测试都要扫"目标 struct 起点 → 下一个顶层 struct 起点"切片，每处 8 行同模式代码（startMarker = / guard let startRange / Issue.record / let afterStart / let nextStructRange / let slice = String）。
  - 后果：DRY 违规 4×8 = 32 行重复；后续要在该模式上加新切片测试时还要继续 copy-paste；切片定位逻辑出 bug（比如 `\nstruct ` 终止符要换成更精确的 regex）时要在 4 处同步修。
- **核心设计：fileprivate helper + nil-return 解耦**：
  - `extractTopLevelStructSlice(from:structMarker:failureMessage:) -> String?`：找不到 startMarker 时 `Issue.record(failureMessage)` + return nil；caller 用 `guard let slice = ... else { return }` 提早退出。
  - **职责单一不强行通用化**：仅适用于顶层 `struct X:` 模式；不合并 R10 line 10846 的 `private struct X: View {` 形式（终止符也不同 `private struct ` vs `\nstruct `）— 强行合并会让接口膨胀（增加 markerType 参数）反而模糊语义，违反 contract pattern「测试代码读起来要像规约」原则。
  - **fileprivate 限定 scope**：放在 R13 测试上方 MARK 区，仅 OPCCompanyCoreTests.swift 内部使用，不暴露到测试目标包外，符合「test helper 不污染产品包符号表」最小可见性原则。
- **实施**（4 处 callsite + 1 处 helper 定义）：
  - `Tests/OPCCompanyTests/OPCCompanyCoreTests.swift`（R13 测试上方）：新增 `MARK: - 角色继承期文案-行为耦合契约共享 helper（轮 19 抽取）` 区 + helper 函数 + 文档注释（适用边界、不通用提醒、nil-return 调用约定）。
  - 4 处 callsite：每处 8 行原始切片代码 → 4 行 `guard let slice = extractTopLevelStructSlice(...) else { return }`，节省 4×4 = 16 行；同时把 R13 注释里"切片定位：扫 ... 之间的范围"改为指向共享 helper。
  - 0 行业务源代码改动 — 纯测试代码 DRY 重构。
- **测试守门**：399/399 全过（本轮无测试数量增量，纯重构）。R13/R14/R15/R16 四个契约测试隔离跑 0.002-0.005s 每个全过，证明 helper 行为与原内联代码完全等价。已知 flaky tmux 测试（`persistentTerminalSendInputLineDuringCommandPreservesMarkerDetection`）并行模式 exit 124 timeout，隔离跑 0.743s pass — 与本轮重构无关。
- **不动的边界**：
  - §0/§1/§2/§3/§4/§5/§6/§7 100% 不动
  - 产品代码 100% 不动（仅 Tests/ 内重构）
  - R10 现有 `private struct ... View {` 切片代码（line 10846 / line 11364）100% 不动 — 不合并以保持 helper 职责单一
  - 5-01 红线 1 守住：纯测试代码 DRY 重构，不动产品行为
- **降级声明 + Round 19 决策记录**：本轮无产品代码改动 / 无 UI 行为改动 / 无 schema 改动 / 无测试基础设施约定演进，无需 codex Computer Use 真机视觉确认。重构等价性已通过 4 个契约测试隔离跑全过证明。本轮兑现 R18 末尾承诺「评估是否还有非 doc / 非 contract test 的小幅价值方向」— 找到一条工程师层可执行、风险极低、价值清晰的 DRY 重构。§5.2 余下两项（candidate λ ChatMessage.productID schema 迁移 / LIMITATION 自洽性条件断言模式评估）仍是 codex CTO 决定级，等 codex 配额恢复（sentinel `test -f .claude/codex-back`）接手。

### 2026-05-03 docs/CLAUDE_CODE_HANDOFF.md §5 待 codex 处理清单全面重写（角色继承期轮 18）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 17 重写 §0 onboarding brief 后，发现 §5「待 codex 回来后处理的清单」也是 stale state — 仍说「9 条接管期变更条目」「356 测试基线」「33 条新增守门」「9 条 OPC_COMPANY.md 第 11 节变更条目」，全部停留在任务接力期 R9 完成时刻；同时 codex 决定级 followup（candidate λ / extractStructSlice helper / LIMITATION 自洽性条件断言）只在最近几轮 §4 末尾「等 codex 复核」段提及，没有在 §5 集中显式化 — codex 配额恢复后看 §5 会以为接管期只产生 9 条 followup-pending 条目，遗漏 candidate λ 等结构性 followup。
- **问题诊断**：
  - 现状：§5 4 行项目级 stale state（仅汇总数字 + 通用 reviewer/Computer Use 提醒），缺 codex 决定级 followup 显式化，缺业务影响×复杂度排序，缺角色继承期 R12-R17 的"无 UI 行为/可跳过 Computer Use"明示。
  - 后果：codex 上手 §5 看不到接管期 25 轮真实规模 + 漏掉 candidate λ 等结构性 followup，可能花时间逐轮翻 §4 才能拼出全貌。
- **核心设计：§5 完全重写 + 三栏分类 + 业务影响×复杂度排序**：
  - **5.1 onboarding / 复核类**：Computer Use 真机视觉确认（明示哪些轮次需要、哪些可跳过）+ CCB Peer Review 补做（指向 §0 重点复核 3 条）+ §11 自审声明清理 + reviewer 降级声明
  - **5.2 codex 决定级 followup（结构性 / 跨轮影响）**：3 项按业务影响×复杂度排序详述（candidate λ schema 迁移 / extractStructSlice helper / LIMITATION 自洽性条件断言模式评估）
  - **5.3 接管期成果汇总（25 轮）**：325 → 399 (+74) / ~80 守门测试新增 / 25 §11 条目 / 21 bundle 重建 / 0 回归 0 红线违反
- **实施**（最小侵入 + 知识保全）：
  - `docs/CLAUDE_CODE_HANDOFF.md §5`（line 1456-1468 附近）：完全重写。+~50 行（4 行 → 50 行三栏 + 详述）。
  - `docs/CLAUDE_CODE_HANDOFF.md`「最后更新」行 + §0.1 表格新增轮 18 行 + accumulator 不动（本轮无测试增量）。
  - 0 行业务源代码改动 / 0 行测试改动 —— 纯 docs/CLAUDE_CODE_HANDOFF.md §5 内容重写。
- **测试守门**：本轮 0 测试增量。既有 399/399 守门继续 pass。
- **不动的边界**：
  - §0/§1/§2/§3/§4/§4.5/§6/§7 100% 不动（§0/§4.5 已在 R17 重写）
  - §11 历史 100% 不动 — 仅在顶部追加一条 R18 条目
  - 5-01 红线 1 守住：本轮零代码改动
- **降级声明 + Round 18 决策记录**：本轮无代码 / 无测试 / 无 UI 行为改动，无需 codex Computer Use 真机视觉确认。本轮是 R17 §0 重写后续 — 同是 codex onboarding 改善的逻辑续作，把"§0 主题导航"+"§5 followup 详述"两件事在 R17/R18 拆开做，避免单轮 doc 改动太大不便复核。从 R19 起若 codex 仍未回，本助手会评估是否还有非 doc / 非 contract test 的小幅价值方向，如确实穷尽则汇报用户进入 §7.3 的"无更多明确高优先级可执行项"待 codex 状态。

### 2026-05-03 docs/CLAUDE_CODE_HANDOFF.md §0 onboarding brief 全面重写按主题分组索引（角色继承期轮 17）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：本助手已完成 16 轮接管期工作（任务接力期 R1-R9 + 角色继承期 R1-R16），但 `docs/CLAUDE_CODE_HANDOFF.md §0「给 codex 的快速上手」` 仍停留在 R1-R9 任务接力期 stale 状态，仅提到「9 条 2026-05-02 变更条目」+「356 测试」。codex 配额恢复后第一眼看到的 onboarding brief 是 stale 的，会误以为只有 9 轮要复核，进入 §0.1 表格才发现还有 16 轮 角色继承期。这是低成本高 ROI 的纯 onboarding-experience 改善 — 不动代码，不动测试，只让 codex 的第一 60 秒读到准确累计画面。
- **问题诊断**：
  - 现状：§0 brief 仍说「先做 3 件事」「成果一句话 325 → 356」「最需要重点复核 2 条（轮 7 + 轮 9 任务接力期）」— 全部停留在 R9 完成时刻。
  - 后果：codex 上手第一印象与实际 25 轮工作量不匹配，可能低估接管期复盘工作量；25 轮按时间倒序排在 §0.1 表格 + §4 详细记录里散乱呈现，没有主题分类索引，复核效率低。
  - **本助手不直接做的事**：删除/合并任何具体 §4 详细记录（codex 需要的细节都在）、删除/合并 §0.1 表格行（每行是 atomic 改动单位、reviewer 复核单位）、动 §1-3 红线/§7 角色继承 SOP（codex 设的契约）。
- **核心设计：§0 完全重写 + 主题分组索引 + 3 个 codex 决定级 followup 显式化**：
  - 旧 brief「30 秒看完」改为「60 秒看完」— 反映双期 25 轮规模
  - 新 brief 4 步骤而非 3 步骤 — 第 4 步专门列 codex 决定级 followup
  - 16 轮按 5 主题分组（A 老板 accessor 体系 / B 员工 desk 密度 / C LIMITATION 标记 / D contract pattern / E 文档维护）按业务影响排序
  - 「最需要重点复核」从 2 条扩展到 3 条 + 业务边界 + 复杂度排序理由
  - 「轮 12-16 全是测试守门，无 UI 行为改动，可跳过 Computer Use 复核」明示降低 codex 复核负担
- **实施**（最小侵入 + 知识保全）：
  - `docs/CLAUDE_CODE_HANDOFF.md §0`（line 9-50 附近）：完全重写。+50 行（3 步 → 4 步 + 主题分组索引 + 重点复核扩展）。
  - `docs/CLAUDE_CODE_HANDOFF.md`「最后更新」行 + §0.1 表格新增轮 17 行 + accumulator 不动（本轮无测试增量）。
  - 0 行业务源代码改动 / 0 行测试改动 —— 纯 docs/CLAUDE_CODE_HANDOFF.md 内 §0 内容重写。
- **测试守门**：本轮 0 测试增量。既有 399/399 守门继续 pass。
- **不动的边界**：
  - §4 详细记录（25 条）100% 保留 — codex 复核细节单源真理。
  - §0.1 表格按时间倒序保留 — atomic 改动 PR-style 单位。
  - §1-3（红线 / SOP / 工具）100% 不动。
  - §7（角色继承期 SOP）100% 不动。
  - OPC_COMPANY.md §11 历史 100% 不动 — 本轮只在 §11 顶部追加一条 R17 条目。
  - 5-01 红线 1 守住：本轮零代码改动，零 UI 影响。
- **降级声明 + Round 17 决策记录**：本轮无代码 / 无测试 / 无 UI 行为改动，无需 codex Computer Use 真机视觉确认。本轮是 contract pattern (R13-R16) 收尾后的纯文档维护轮，刻意避开「再做一个 marginal contract test」的递减回报陷阱（轮 16 末尾已明确"contract pattern 收尾，从 R17 起 pivot 到非 contract test 方向"）。pivot 到 docs/onboarding 改善是合理的 80/20 价值方向 — 帮 codex 上手是接管期最终交付物的一部分。

### 2026-05-03 AgentDeskWorkspace「当前产品」UI 承诺-双轴行为耦合契约测试（角色继承期轮 16）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 13/14/15 完成 boss 三件套（BossReportCenter / BossControlPanel / CommandCenterView）契约后，本轮把 contract pattern 镜像到员工侧 — `AgentDeskWorkspace`（员工工作台核心面板）。多条「当前产品」UI 承诺（`未加入当前产品团队，不能执行当前产品任务` / `当前产品下没有分配给该员工的任务` 等）+ 双轴 scoped 数据源（agentTasks/agentQueue 是 `selectedProduct{Tasks,WorkQueue}.filter { $0.ownerID == agent.id }`，product 轴 + agent 轴双重过滤）。完成"老板核心 3 件 + 员工核心 1 件"对称覆盖后，contract pattern 收尾 — 剩余次要面板（BossDecisionCenterSheet / ProfilePanel etc.）UX 体感低，不再扩展。
- **问题诊断**：
  - 现状：accessor 已正确（轮 1-7 改造时确认 selectedProduct + agent 双轴过滤），UI 承诺无对应守门。
  - 比 boss 三件套更严重的失败模式：双轴 scope 任一退化都会导致灾难性泄漏。
    - 去 `selectedProduct` 前缀（直读 `store.tasks.filter`）：员工 desk 显示别的产品的任务
    - 去 `agent.id` 过滤（不带 .filter）：员工 desk 显示别人的任务
    - UX 后果：员工看到不属于自己/不属于当前产品的任务，看似可执行但运行会失败 → 用户对系统信任崩塌
- **核心设计：复用轮 13/14/15 切片+多重断言模式 + 7 断言含双轴反契约**：
  - 在 `SelectionWorkspaceView.swift` 中按 `struct AgentDeskWorkspace:` → 下一个 `struct ` 切片。
  - 7 条断言：2 条 UI 承诺 + 3 条 scoped 行为 + 2 条**双轴反契约**（`store.tasks.filter` / `store.workQueue.filter` 不应直读）。
- **实施**（最小侵入 + 知识保全）：
  - `OPCCompanyCoreTests.swift` 末尾新增 MARK「AgentDeskWorkspace「当前产品」UI 承诺-行为耦合契约（角色继承期轮 16）」+ 1 条测试 `agentDeskWorkspaceCurrentProductUIPromisesStayCoupledToProductAndAgentScopedAccessors`。
  - 0 行业务源代码改动 —— 纯测试加固。
- **测试守门**（7 条断言绑成单条契约）：
  1. UI 承诺 #1：切片含「未加入当前产品团队」（强 product scope claim + agent assignment gating 联动）
  2. UI 承诺 #2：切片含「当前产品下没有分配给该员工的任务」（assignedTasks 空状态文案）
  3. 行为 #1：切片含 `store.selectedProductTasks.filter`（agentTasks 双轴 scoped）
  4. 行为 #2：切片含 `store.selectedProductWorkQueue.filter`（agentQueue 双轴 scoped）
  5. 行为 #3：切片含 `store.isAgentAssignedToSelectedProduct`（运行按钮 + warning 显示双 gating）
  6. 反契约 #1：切片不含 `store.tasks.filter`（防 product 轴退化）
  7. 反契约 #2：切片不含 `store.workQueue.filter`（防 product 轴退化）
- **不动的边界**：
  - 0 view 改动 / 0 store 改动 / 0 现有测试改动 —— 既有 UI 文案 + accessor 都已正确。
  - 切片用纯字符串切分（与轮 13/14/15 同模式）。
  - 5-01 红线 1 守住：本轮零 UI 改动。
- **降级声明 + Contract Pattern 收尾**：本轮无 UI 行为改动，无需 codex Computer Use 真机视觉确认。本轮是 contract pattern 第四个也是最后一个实例（80/20 收益已达成 — 老板 3 件 + 员工 1 件覆盖核心，剩余次要 widget 不值得做）。codex 配额恢复后请：
  1. 4 个实例的切片提取代码 100% 重复，**强烈建议提取通用 helper** `extractStructSlice(in: source, named: "X")` —— 后续任何新增老板/员工核心面板新增时只需 5 行调用；
  2. 评估 LIMITATION 自洽性条件断言模式（轮 15 引入）是否值得作为新 best practice 推广到其他 limitation 标记场景；
  3. 对称完整性确认：boss 3 + employee 1 = 4 实例，其中 employee 端只覆盖 AgentDeskWorkspace。是否值得给 ChannelChat / TerminalHall 加同模式契约 — 倾向"不做"（这些不是核心员工 desk）。

### 2026-05-03 CommandCenterView header 产品名插值-行为耦合契约测试 + LIMITATION 自洽性冗余守门（角色继承期轮 15）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 13/14 落地 BossReportCenter + BossControlPanel 双侧文案-行为契约后，本轮把同模式扩展到第三个目标 — `CommandCenterView`（老板首页主区域，"老板总览"），完成"老板专属面板三个核心实例"的 contract pattern 全覆盖。三个实例足以证明该模式适合长期推广（codex 配额恢复后可考虑提取通用 helper）。
- **问题诊断**：
  - 现状：`CommandCenterView` 是老板首页主区域，header 渲染 `product?.name ?? "当前产品"`（line 130，强 UI 承诺）+ 老板专属定位文案「老板看目标、结果、风险和需要确认的审批」（line 150），核心数据源 `riskEvents` 走 `selectedProductBossRiskEvents`（line 23，轮 9 收口）。但**没有任何测试断言"header 产品名 + 定位文案"与"scoped risk accessor"是耦合的**。
  - 同时 `latestCTOBriefing`（line 617）跨产品读 `messages(for: ctoID)` 是已知 limitation（轮 12 加 LIMITATION 标记 + 守门）。本轮的契约测试需要"自洽地确认" LIMITATION 标记仍在 — 一旦未来同时删 limitation 标记和跨产品调用（看似"清理跨产品 read 同时清理 marker"），轮 12 的单点守门虽然会拦截，但缺少切片维度的冗余守门。
- **核心设计：复用轮 13/14 切片+多重断言模式 + 7 断言绑成单条契约（含 LIMITATION 自洽性条件断言）**：
  - 在 `CommandCenterView.swift` 中按 `struct CommandCenterView:` → 下一个 `struct ` 切片（line 3-649，约 647 行）。
  - 7 条断言：2 条 UI 承诺 + 1 条 scoped accessor + 3 条反契约 + 1 条 **LIMITATION 自洽性条件断言**（如果切片仍含 `messages(for: store.ctoID)`，则切片必须仍含 `LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK` 标记 — 防止后续清理同时删 limitation 标记 + 跨产品调用）。
- **实施**（最小侵入 + 知识保全）：
  - `OPCCompanyCoreTests.swift` 末尾新增 MARK「CommandCenterView header 产品名插值-行为耦合契约（角色继承期轮 15）」+ 1 条测试 `commandCenterViewHeaderProductNameStaysCoupledToScopedRiskAccessor`。
  - 0 行业务源代码改动 —— 纯测试加固。
- **测试守门**（7 条断言绑成单条契约）：
  1. UI 承诺 #1：切片含 `product?.name`（header 产品名插值）
  2. UI 承诺 #2：切片含「老板看目标、结果、风险和需要确认的审批」
  3. 行为：切片含 `selectedProductBossRiskEvents`（轮 9）
  4. 反契约 #1：切片不含 `store.events.filter`
  5. 反契约 #2：切片不含 `store.events.prefix`
  6. 反契约 #3：切片不含 `store.messages(for: store.bossID)`
  7. LIMITATION 自洽性条件断言：切片含 `messages(for: store.ctoID)` ⇒ 切片必须含 `LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK`（轮 12 marker 冗余守门）
- **不动的边界**：
  - 0 view 改动 / 0 store 改动 / 0 现有测试改动 —— 既有 header + accessor + LIMITATION 标记都已正确，本轮纯绑契约。
  - 切片 ~647 行扫描代价可接受（测试运行 0.006s，O(n) 字符串扫描）。
  - 5-01 红线 1 守住：本轮零 UI 改动，无折叠/勾选/快照体感变化。
- **降级声明**：本轮无 UI 行为改动，无需 codex Computer Use 真机视觉确认。codex 配额恢复后请判断：
  1. 三个实例（轮 13/14/15）覆盖了老板专属面板核心；剩余次要老板侧 widget（如 BossDecisionCenterSheet line 760, BossSummaryPill etc.）UX 体感低，是否值得继续做契约 — 倾向"不做，已经达到 80/20 收益"；
  2. 是否值得提取通用 helper `extractStructSlice(in: source, named: "X")` —— 三个实例的切片提取代码 100% 重复，helper 化后第四个目标只需 5 行调用即可；
  3. **LIMITATION 自洽性条件断言模式**值得作为新 best practice 推广：当一个切片内有 limitation 标记时，跨切片维度做冗余守门（防止 limitation 标记和它守的跨产品调用被一起悄悄清理）。这种"双层守门" + "切片内自洽"是降低长期 contract drift 的有效手段。

### 2026-05-03 BossControlPanel header 产品名插值-行为耦合契约测试（角色继承期轮 14）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 13 把 BossReportCenter 文案-行为耦合绑成契约后，自驱寻找同模式的第二个目标。`InspectorPanel.BossControlPanel` (line 304) 是老板首页核心 sidebar：header 直接插值 `store.selectedProduct?.name`（line 387），是比 BossReportCenter 更强的 UI 承诺（产品名作为可见标题文字渲染，不只是文案声明）；正文三个 accessor (`recentRiskCount` / `recentEvents` / `compactRecentReports`) 已在轮 5/8 收口到 `selectedProductBoss*` 系列。但同样**没有任何测试断言"header 产品名插值"与"三个 accessor 行为"是耦合的**。
- **问题诊断**：
  - 现状：accessor 各自有作用域守门（轮 5/8），header 产品名插值无任何测试保护。
  - 耦合断裂会引起更明显的 UX 灾难：header 写「Product A」但内容混入 Product B 的事件，老板视觉一眼能看到落差（比 BossReportCenter 文字声明更刺眼）。
  - 这是轮 13 模式的第二个实例 — 三个目标实例（含轮 13 + 候选 CommandCenterView）足以证明该 contract pattern 适合长期推广。
- **核心设计：复用轮 13 切片+多重断言模式 + 6 断言绑成单条契约**：
  - 在 `InspectorPanel.swift` 中按 `struct BossControlPanel:` → 下一个 `struct ` 切片（与轮 13 同模式，避免文件其他位置含「当前产品」误匹配）。
  - 在切片内同时断言：产品名插值 + 老板专属定位文案 + 风险 accessor + 综合事件 accessor + 两条反契约。
- **实施**（最小侵入 + 知识保全）：
  - `OPCCompanyCoreTests.swift` 末尾新增 MARK「BossControlPanel header 产品名插值-行为耦合契约（角色继承期轮 14）」+ 1 条测试 `bossControlPanelHeaderProductNameStaysCoupledToScopedAccessors`。
  - 0 行业务源代码改动 —— 纯测试加固（既有 header + accessor 都已是正确状态，本轮只把它们绑成契约）。
- **测试守门**（6 条断言绑成单条契约）：
  1. UI 承诺 #1：切片含 `store.selectedProduct?.name`（产品名插值）
  2. UI 承诺 #2：切片含「你只负责下目标、看进度、批准风险」（老板专属定位文案）
  3. 行为 #1：切片含 `selectedProductBossRiskEvents`（风险计数 accessor，轮 8）
  4. 行为 #2：切片含 `selectedProductBossEvents`（综合事件 accessor，轮 5）
  5. 反契约 #1：切片不含 `store.events.prefix`（轮 5 已移除）
  6. 反契约 #2：切片不含 `store.events.filter`
- **不动的边界**：
  - 0 view 改动 / 0 store 改动 / 0 现有测试改动 —— 既有 header + accessor 调用都已正确，本轮纯绑契约。
  - 切片用纯字符串切分（与轮 13 同模式），脆性可接受。
  - 5-01 红线 1 守住：本轮零 UI 改动，无折叠/勾选/快照体感变化。
- **降级声明**：本轮无 UI 行为改动，无需 codex Computer Use 真机视觉确认。codex 配额恢复后请判断：
  1. 三个目标实例（轮 13 BossReportCenter + 轮 14 BossControlPanel + 候选 CommandCenterView）是否足以提取通用 helper `extractStructSlice(in: source, named: "X")` —— 通用化后第三个目标只需 5 行测试调用即可；
  2. 是否值得给老板专属面板/老板侧 widget 加一个「老板侧 UI 文案承诺都被切片守门覆盖」元契约（meta-contract），catch 新增老板面板时漏接守门的回归。

### 2026-05-03 BossReportCenter UI 文案-行为耦合契约测试（角色继承期轮 13）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 12 收尾后 view 端跨产品边界审计真正进入"已知/已修复/已加守门 + 已留 limitation 标记"全覆盖状态。本轮转向"既有契约测试覆盖盲点"扫描 — 发现 BossReportCenter UI 文案 (line 2944) 明示「报告会汇总当前产品...」，轮 6 把 `reportEvents` 收口到 `selectedProductBossEvents`，轮 10 把 `bossMessages` 收口到 `selectedProductBossReportMessages`，但**没有任何测试断言"UI 文案承诺"与"accessor 行为"是耦合的**。任一侧单边修改（UI 文案改成「全部产品」 / accessor 偷偷换回跨产品）都会导致用户看到与文案矛盾的行为，且现有测试不会拦截。
- **问题诊断**：
  - 现状：accessor 各自有作用域守门（轮 6/10 已落），UI 文案没有任何测试保护。
  - 耦合断裂的两个失败模式：(a) 文案改成「全部产品」但 accessor 仍是产品作用域 → UI 谎言（用户以为看到全部，实际只看到一份）；(b) accessor 偷偷换回跨产品但文案仍说「当前产品」→ UI 谎言（用户以为看到当前产品，实际混入其他产品）。
  - 现有测试覆盖：作用域行为契约（轮 10 `selectedProductBossReportMessagesScopesToCurrentProductOnly`）+ 单源码扫描（轮 10 `bossReportCenterBossMessagesUses...`）+ 轮 6 `reportEvents` 来源扫描，但都不检查"UI 文案承诺"侧。
- **核心设计：单条 source-scan 测试 + 切片定位 + 双侧契约**：
  - 在 `OperationsSuiteView.swift` 中按 `struct BossReportCenter:` → 下一个 `struct ` 切片，避免文件其他位置（line 854/1394 等）含「当前产品」误匹配。
  - 在切片内同时断言：UI 文案承诺侧含「当前产品」 + 行为侧含两个 scoped accessor 调用 + 反契约（`store.events.filter` / `store.messages(for: store.bossID)` 不应再出现）。
- **实施**（最小侵入 + 知识保全）：
  - `OPCCompanyCoreTests.swift` 末尾新增 MARK「BossReportCenter UI 文案-行为耦合契约（角色继承期轮 13）」+ 1 条测试 `bossReportCenterUITextStaysCoupledToCurrentProductScopedAccessors`。
  - 0 行业务源代码改动 —— 纯测试加固（既有 UI 文案 + 既有 accessor 调用都已是正确状态，本轮只把它们绑成契约）。
- **测试守门**：
  - `bossReportCenterUITextStaysCoupledToCurrentProductScopedAccessors`（新）：单条扫描 5 个断言 — 1 文案 + 2 accessor + 2 反契约。
- **不动的边界**：
  - 0 view 改动、0 store 改动、0 现有测试改动。
  - 切片用纯字符串切分（无 AST 解析），脆性可接受 —— `struct BossReportCenter:` 重命名时测试会立即提示，是 PR 信号而非工程债。
  - 5-01 红线 1 守住：本轮零 UI 改动，无折叠/勾选/快照体感变化。
- **降级声明**：本轮无 UI 行为改动，无需 codex Computer Use 真机视觉确认。codex 配额恢复后请复核：
  1. 切片+多重断言模式是否值得推广到其他类似"UI 文案承诺-accessor 行为"耦合点（候选：BossControlPanel header「老板总控台 · [产品名] · 你只负责...」+ recentEvents/compactRecentReports；CommandCenterView 命令总控台总览段）；
  2. 是否需要把切片定位提取为通用 helper（如 `extractStructSlice(in: source, named: "BossReportCenter")`）。

### 2026-05-03 跨产品 CTO 消息泄漏（latestCTOBriefing + ownerGoal）落地限制标记 + 测试守门（角色继承期轮 12）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 11 后自驱审计扫描 view 端剩余 `messages(for:)` 调用点（共 5 处，剔除 store/InspectorPanel 后剩 2 处属于「应当按当前产品作用域」却跨产品累加的真实泄漏）—— `CommandCenterView.latestCTOBriefing`（line 617，老板首页命令总控台显示「最新 CTO briefing」）和 `SelectionWorkspaceView.ownerGoal`（line 403，产品总览面板显示「老板目标」）。两处都直接读 `store.messages(for: store.ctoID)`；ctoID 是单一全局 agent，跨产品累加：Product A 的 CTO 回执/老板输入会泄漏到 Product B 的对应面板。
- **问题诊断**：
  - 现状：两处 view-side accessor 都跨产品读 ctoID 流，无作用域过滤。
  - 实际 UX：老板在 Product A 与 CTO 对话 → 切换到 Product B 命令总控台 → 看到 A 的最新 CTO briefing；同模式发生在「老板目标」面板。
  - 桥接退路评估（轮 10 文本 prefix 桥接策略）：**不可行**。轮 10 的 BossReportCenter 桥接成功因为 `generateBossReport()` 是单一可控写入点 + 文本统一以 `"老板报告：\(productName)"` 起头。ctoID 写入有 30+ 处（CompanyStore.swift:186/1283/1664/1685/1712/1833/1884/1892/1898/2487/2488/3352/3370/3747/3852/3928/4101/4222/4278/4291/4319/5163/5194/5242/5266/5619/5967/6015/6175/6231 …），文本格式各异（审计报告/流水线提示/简报/快照/系统通知），retrofit-prefixing 全部 append site 且要处理历史持久化数据，落地代价接近 schema 迁移本身。
  - 正解：candidate λ —— `ChatMessage.productID: UUID?` schema 迁移 + `messages(for:in:)` 重载 + 持久化/序列化/迁移工具。落地范围超出本轮单 view-comment 修改的安全边界，明确**留给 codex 配额恢复后处理**。
- **核心设计：限制标记注释（landmine） + 守门测试，禁止后续清理悄悄抹除**：
  - **view 端**：在两处 accessor 上方各加 8-10 行注释块，统一含三个 grep token：`LIMITATION-CROSS-PRODUCT-CTO-MESSAGE-LEAK`（限制类型唯一标识）、`candidate λ`（指向正解路径）、对应守门测试函数名（注释 → 测试反向跳转锚点）。
  - **测试端**：每处 view 一条 source-scan 测试，断言三个 token 都在源文件里 —— 任何后续「这看起来跨产品但应该没事」的清理都会立即拦截。
- **实施**（最小侵入 + 知识保全）：
  - `CommandCenterView.swift:617-630`：`latestCTOBriefing` 上方加 13 行注释块，含完整 30+ append site 列举 + candidate λ 引用 + 守门测试名。函数体（4 行）100% 不动。
  - `SelectionWorkspaceView.swift:403-416`：`ownerGoal` 上方加 9 行注释块，引用同侧详细说明 + 评估了文本注入桥接退路并说明仍接近 schema 迁移代价 + candidate λ 引用 + 守门测试名。函数体（8 行）100% 不动。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾新增 MARK「跨产品 CTO 消息泄漏限制标记守门（角色继承期轮 12）」）：
  - `latestCTOBriefingCarriesCrossProductLeakLimitationMarker`（新）：scan `CommandCenterView.swift`，断言三个 token 都在源里。
  - `ownerGoalCarriesCrossProductLeakLimitationMarker`（新）：scan `SelectionWorkspaceView.swift`，同模式断言三个 token。
- **不动的边界**：
  - 0 处 store API 改动 / 0 处函数体逻辑改动 —— 纯 view comment + test 两类文件追加。
  - InspectorPanel.swift:112+122 的 `messages(for: store.selectedAgentID)` 不在本轮范围 —— 该面板按 selectedAgentID 索引，是「员工维度全量历史」视图（员工 inspector 直读，类比 R9 处理 store.events 的方式），与「按当前产品过滤」的 latestCTOBriefing/ownerGoal 语义不同。
  - 31 处 ctoID 写入点 100% 保留 —— 本轮不做 retrofit-prefix 桥接（评估代价高于直接走 schema 迁移）。
  - 5-01 红线 1 守住：本轮零 UI 改动（仅注释 + 测试），无折叠/勾选/快照体感变化。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 配额恢复后请在 candidate λ 落地前后用 Computer Use 复核：
  1. **当前状态（落地前）**：Product A CTO chat 输入 `"目标 A"` → 切到 Product B 命令总控台 → `latestCTOBriefing` 文案是否含 A 的内容（确认泄漏可观察）；
  2. **λ 落地后**：同操作 → B 的 `latestCTOBriefing` 应回退到 fallback「技术负责人已接管当前产品...」文案，A 的 briefing 完全不见。

### 2026-05-03 老板视图剔除前缀白名单加固「命令行作业」覆盖后端文件失败类（角色继承期轮 11）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 9 注释清理 + 轮 10 跨产品老板报告流收口后，自驱审计扫描所有 `appendEvent(kind: .risk, ...)` 调用点（共 31 处），按主题对老板视图相关性分类。发现 2 处 `.opc/jobs/` 后端文件操作失败事件 — `命令行作业目录创建失败`（CompanyStore.swift:8166）+ `命令行作业档案写入失败`（CompanyStore.swift:8179）— 当前未在 `bossViewExcludedRiskTitlePrefixes` 白名单中（白名单只有「命令行健康预警：」一条）。这两条事件属于纯后端文件系统失败（mkdir/write 失败），后端继续运行不阻断业务，老板看不懂也无法处理；却会挤占老板首页"最近风险" widget 容量（prefix(5) / prefix(3)）。同时复核业务层「命令行发车被阻止」（CompanyStore.swift:6015）— 老板试图运行命令行任务但前置检查不通过 — 老板需要知道，**不**应进入白名单。
- **问题诊断**：
  - 现状：`bossViewExcludedRiskTitlePrefixes` 单一前缀只覆盖 CLI 健康预警；同类其他后端维护失败漏过。
  - 风险：老板首页"最近风险" widget prefix(5) 容量被技术维护噪音挤占，业务风险信号能见度降低。
  - 设计选择：选择 `命令行作业` 单一前缀（不带冒号）天然覆盖现有 2 条 +「命令行作业XXX失败」未来变体；同时不会误击中 `命令行发车被阻止`（不以「命令行作业」开头）。
- **核心设计：白名单加 1 条前缀 + 编辑指南注释 + 2 条契约测试**：
  - **store 端**：`bossViewExcludedRiskTitlePrefixes` 加 `"命令行作业"`；同时给该静态常量补 6 行「白名单设计原则」注释，明示判定标准（纯后端 vs 老板可决策）+ 例子（命令行作业XXX失败 vs 命令行发车被阻止）。
  - **测试端**：1 条单点契约 + 1 条多事件行为契约。
- **实施**（最小侵入 + 测试加固）：
  - `CompanyStore.swift:307-321`：白名单从 1 条变 2 条（追加 `"命令行作业"`）；注释从原 13 行扩展到 22 行（加「白名单设计原则」段落）。
  - `OPCCompanyCoreTests.swift`：新增 2 条测试 — 单点契约 + 多事件行为契约。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「老板首页风险流过滤维护类事件」MARK 段内）：
  - `bossViewExcludedRiskTitlePrefixesIncludesCommandJobMaintenancePrefix`（@MainActor，新）：单点契约 — `bossViewExcludedRiskTitlePrefixes` 必须含 `"命令行作业"`。
  - `selectedProductBossRiskEventsExcludesCommandJobMaintenanceTitlesButKeepsBossLaunchBlocked`（@MainActor，新）：多事件行为契约 — 写入 3 条事件（2 条命令行作业XXX失败 + 1 条命令行发车被阻止）→ 全量 +3 / 老板视图 +1（仅命令行发车被阻止）。
- **不动的边界**：
  - 31 处 `.risk` 事件写入 100% 保留，无改写、无新增、无重命名。这是纯下游消费的过滤层加固。
  - 「命令行健康预警：」（轮 9 引入的 1 条前缀）100% 保留。
  - 既有 `bossViewExcludedRiskTitlePrefixesIncludesCLIHealthWarning` 单点契约（轮 9）100% 保留 — 与新加的并列。
  - `selectedProductBossEvents` / `selectedProductBossReportMessages`（轮 5/6/10）100% 保留，与 `selectedProductBossRiskEvents` 同模式但是分立的 accessor。
  - 5-01 红线 1 守住：本轮零 UI 改动（store 静态常量 + 注释 + 测试），无 DisclosureGroup / 折叠引入。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 触发命令行作业目录创建失败（删 `.opc/jobs/` 写权限） → 老板首页"最近风险" widget 不应显示该条；员工 inspector「事件」tab 必须能看到该条；
  2. 触发命令行发车被阻止（前置检查失败） → 老板首页"最近风险" widget 必须显示该条。

### 2026-05-03 BossReportCenter「最近老板报告」按当前产品作用域过滤 + 移除失效产品交接快照分支（角色继承期轮 10）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 9 收口注释 + 守门后，自驱审计扫描所有"老板专属面板"是否仍存在跨产品/跨边界数据源。发现 `BossReportCenter.bossMessages`（OperationsSuiteView.swift:2923）读 `store.messages(for: store.bossID)`，boss agent 是跨产品角色，这条消息流是跨产品累加的；同时面板 UI 文案明示「报告会汇总当前产品...」(line 2938)。Product A 生成老板报告后切到 Product B，B 的 BossReportCenter 也会显示 A 的报告，与 UI 文案承诺相悖。同时发现该过滤里有失效分支 `text.contains("产品交接快照")` — `createHandoffSnapshot()` 只写 ctoID 流（line 3340），boss 流从来没这种消息，分支永远不匹配。
- **问题诊断**：
  - 跨产品老板报告污染：boss 是单一跨产品 agent → `messages(for: bossID)` 跨产品累加 → BossReportCenter 没产品作用域过滤 → 切产品后旧产品报告错误显示。
  - 失效过滤分支：`text.contains("产品交接快照")` 在 boss 流永远不匹配（dead branch），属于历史遗留的过度防御。
  - 结构性根因：`ChatMessage` schema 没有 `productID: UUID?` 字段，无法按产品维度按 ID 过滤。
- **核心设计：CompanyStore 加产品作用域 accessor + view 端切换 + 移除 dead branch**：
  - **store 端**：新增 `selectedProductBossReportMessages` accessor — `messages(for: bossID).reversed().filter { $0.text.hasPrefix("老板报告：\(productName)") }`。`generateBossReport()` 写入的报告文本固定以"老板报告：<产品名>\n"开头（line 3294-3321），按此前缀稳定锁定本产品报告。保留原 `.reversed()` 时间倒序语义。
  - **view 端**：`BossReportCenter.bossMessages` 从原 `store.messages(for: store.bossID).reversed().filter { $0.text.contains("老板报告") || $0.text.contains("产品交接快照") }` 改为 `store.selectedProductBossReportMessages`；同时移除失效 `产品交接快照` 分支。
  - **已知限制**：纯文本 prefix 匹配，若用户在生成报告后重命名产品，旧报告匹配会失效。结构性修复需要给 `ChatMessage` 加 `productID: UUID?` schema 字段（codex 决定）；prefix 匹配是兜底方案，避免明显的跨产品污染。
- **实施**（最小侵入 + 测试加固）：
  - `CompanyStore.swift:336+`（紧贴 `selectedProductBossEvents` 之后）：新增 `selectedProductBossReportMessages` 公开 accessor + 16 行注释（说明为什么需要 + 实现方式 + 已知限制）。
  - `OperationsSuiteView.swift:2923-2932`：`bossMessages` 从原 1 行 cross-product chained call 改为 1 行 store accessor 调用 + 8 行注释说明同源契约。
  - `OPCCompanyCoreTests.swift`：新增 3 个测试 — 2 行为契约（产品作用域 + 时间倒序）+ 1 跨文件源码扫描守门。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「BossReportCenter 最近老板报告按当前产品作用域过滤」MARK 段内）：
  - `selectedProductBossReportMessagesScopesToCurrentProductOnly`（@MainActor）：行为契约 — Product A 生成老板报告 → 出现在 A 的 accessor；调用 `addProductWorkspace()` 切到 B → A 的报告不再出现，B 视图只显示当前产品报告。
  - `selectedProductBossReportMessagesIsTimeReversedNewestFirst`（@MainActor）：行为契约 — 多次调用 `generateBossReport()` 后，accessor 必须按 `createdAt` 倒序（最新在前），与原 `BossReportCenter.bossMessages` `.reversed()` 行为一致。
  - `bossReportCenterBossMessagesUsesSelectedProductBossReportMessagesAndDropsCrossProductReadAndDeadHandoffSnapshotBranch`：源码扫描守门 — `OperationsSuiteView.swift` 必须含 `store.selectedProductBossReportMessages` AND 不应再含 `store.messages(for: store.bossID).reversed().filter` 链 AND 不应再含 `text.contains("产品交接快照")` 失效分支。
- **不动的边界**：
  - `generateBossReport()` 写入逻辑（line 3277-3325）100% 保留：仍然双写 bossID + ctoID 两条流，技术负责人对话仍能看到完整老板报告。
  - `createHandoffSnapshot()` 写入 ctoID 流（line 3340）100% 保留：CTO 对话还是收得到产品交接快照，只是不再被 BossReportCenter 误抓。
  - `messages(for: bossID)` 公开 API 100% 保留：CommandCenterView (line 618) / SelectionWorkspaceView (line 404) 等其他读 boss 消息的地方继续用，不强制改造（它们的语义是"看 boss 整个对话流"，不是"看当前产品报告"）。
  - 5-01 红线 1 守住：本轮零 UI 改动（数据源迁移），无 DisclosureGroup / 折叠引入。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. Product A 选中 → 点击「生成老板报告」→ 右栏「最近老板报告」应显示该报告；
  2. 切到 Product B → 右栏应仅显示 B 的老板报告（如有），A 的报告必须不可见；
  3. 同一产品多次生成报告 → 右栏最多 3 条，按时间倒序（最新在前）。
- **结构性 follow-up（留给 codex）**：考虑给 `ChatMessage` 加 `productID: UUID?` schema 字段 + 持久化迁移，把所有"哪条消息属于哪个产品"的关系从文本匹配升级到结构化关联。本轮 prefix 匹配只是兜底，schema 升级后可以优雅删除。

### 2026-05-03 清理轮 8 已失实注释 + 跨 6 view 文件 `selectedProductRiskEvents` token 缺位守门（角色继承期轮 9）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 8 把所有老板视图 risk 流迁到 `selectedProductBossRiskEvents` 之后，自驱审计扫描全代码库 `selectedProductRiskEvents` 出现位置，发现 2 处注释（`CompanyStore.swift` `bossViewExcludedRiskTitlePrefixes` 头注释 + `CommandCenterView.swift` `riskEvents` 内联注释）仍宣称"技术负责人 InspectorPanel / OperationsSuiteView 仍读全量 selectedProductRiskEvents"。这两条注释在轮 8 后已经失实，可能误导未来 PR 错误新增 `store.selectedProductRiskEvents` 调用回退轮 5/6/8 收敛。同时观察到轮 8 跨文件守门 `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor` 只覆盖 3 个文件且只检查 `store.` 前缀调用，注释里 token 引用绕过守门。本轮：注释清理 + 更严的 6 view 文件 token 缺位扫描。
- **问题诊断**：
  - `CompanyStore.swift` `bossViewExcludedRiskTitlePrefixes` 头注释（line 296-303）：与轮 8 实际状态相悖。**真正的技术维护「全量事件流」入口是 `EventLogView`（员工 inspector「事件」tab）直读 `store.events`**（不是 `selectedProductRiskEvents`），而后者在所有 view 文件里已无消费者（仅 `CompanyStore.swift` 派生 + 内部团队负责人手机汇报报告文本计数行 ~7204/7230/7463 仍在用）。
  - `CommandCenterView.swift` `riskEvents` 内联注释（line 18-20）：同上失实。
  - 轮 8 守门覆盖广度不足：`bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor` 只扫 3 文件 `store.selectedProductRiskEvents` 字面量，注释 token 引用（如本轮发现的两条）绕过。
- **核心设计：2 处注释修订 + 1 个跨 6 view 文件 token 缺位守门**：
  - 注释端：`CompanyStore.swift` 头注释明示当前消费方（`EventLogView` 直读 `store.events`）+ 守门测试名 + 内部报告文本计数行号；`CommandCenterView.swift` 内联注释不再出现 `selectedProductRiskEvents` token（避免 token 缺位守门误报）。
  - 测试端：扫描所有 6 个 view 文件（`CommandCenterView.swift` / `ContentView.swift` / `InspectorPanel.swift` / `OperationsSuiteView.swift` / `SelectionWorkspaceView.swift` / `TerminalHallView.swift`），断言每个都不含字符串 `selectedProductRiskEvents`（不论是 `store.` 调用还是注释 token 引用）。`CompanyStore.swift` 显式排除（声明 + 派生 + 报告文本计数）。
- **实施**（最小侵入 + 测试加固）：
  - `CompanyStore.swift:296-308`：8 行注释 → 12 行注释，明示当前消费方 + 守门测试名 + 内部报告文本计数行号。
  - `CommandCenterView.swift:17-23`：4 行注释 → 6 行注释，去掉失实的"InspectorPanel / OperationsSuiteView 仍读全量"断言 + 改为 EventLogView 直读 `store.events` 描述 + 不再出现 `selectedProductRiskEvents` 裸 token。
  - `OPCCompanyCoreTests.swift`：新增 `selectedProductRiskEventsHasNoUIConsumerAfterBossViewMigration`（19 行）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「老板首页风险流过滤维护类事件」MARK 段内，紧贴 `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor` 之后）：
  - `selectedProductRiskEventsHasNoUIConsumerAfterBossViewMigration`：跨 6 view 文件 token 缺位扫描，CompanyStore.swift 显式排除。比轮 8 更严：覆盖 6 个 view 文件（vs 轮 8 的 3 个）+ 检查 token 缺位（含注释，vs 轮 8 只检查 `store.` 前缀调用）。
- **不动的边界**：
  - `EventLogView`（员工 inspector「事件」tab，`ForEach(store.events)`）100% 保留。
  - 所有老板专属视图（轮 5/6/8 收口的 4 处）100% 保留过滤 accessor。
  - `CompanyStore.swift` 内 3 处团队负责人手机汇报 / 外部状态查询报告文本里的 `selectedProductRiskEvents.count`（line ~7204/7230/7463）100% 保留 — 这些走团队负责人 / 外部通信通道，应看到全量风险（含维护类）。
  - 5-01 红线 1 守住：本轮零 UI 改动，纯注释 + 测试。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。本轮零 UI 改动，无需真机复核；但建议 codex 回来后顺便复核轮 5/6/8 的 4 处老板视图视觉一致（仅业务风险显示，命令行健康预警等维护类不出现）。

### 2026-05-03 RiskApprovalCenter + recentRiskCount 接入老板视图过滤 + 修正轮 9 契约测试（角色继承期轮 8）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：轮 8 自驱审计发现轮 9 老板视图风险流过滤主线漏掉了 2 处老板专属面板，且既有契约测试 `technicalMaintenanceViewsStillReadFullRiskEvents`（轮 9 引入）的检查目标本身有问题。本轮一并收口 + 修正。
- **问题诊断**：
  - 全代码库 `selectedProductRiskEvents`（全量）剩 2 处 view-side 调用（轮 9 / 轮 5 / 轮 6 后），表面看是"技术维护视图"但实际全在老板侧：
    1. `OperationsSuiteView.RiskApprovalCenter.riskEvents` (line 2706) — 老板审批中心右侧"风险事件" widget。
    2. `InspectorPanel.BossControlPanel.recentRiskCount` (line 320) — 老板首页 stat tile"近期风险" 计数。
  - 轮 9 既有契约测试 `technicalMaintenanceViewsStillReadFullRiskEvents`：grep `selectedProductRiskEvents` 在 InspectorPanel + OperationsSuiteView 必须存在，假设这两个文件含技术维护视图。**此前提错误** — 这两处的 selectedProductRiskEvents 全在老板侧。真正的技术维护"全量事件"入口是 EventLogView (员工 inspector "事件" tab)，它读 `store.events`（不是 selectedProductRiskEvents）。
  - 后果：维护类前缀事件（命令行健康预警 等）会污染老板审批面板和老板首页 stat tile，与轮 9 主线意图相悖。
- **核心设计：2 处老板视图调用收敛 + 1 个契约测试拆分修正**：
  - view 端：`RiskApprovalCenter.riskEvents` + `BossControlPanel.recentRiskCount` 都从 `store.selectedProductRiskEvents` → `store.selectedProductBossRiskEvents`。
  - test 端：删除"技术维护视图必须读全量 selectedProductRiskEvents" 的错误前提，拆为：
    1. `technicalMaintenanceEventLogViewRetainsFullEventFeed`：守 EventLogView 必须用 `ForEach(store.events)` — 真正的技术维护诊断入口。
    2. `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor`：3 个老板视图（CommandCenter + InspectorPanel + OperationsSuite）正反向断言 — 必须有 `selectedProductBossRiskEvents` AND 不应有 `store.selectedProductRiskEvents`。
- **实施**（最小侵入 + 测试结构重构）：
  - `OperationsSuiteView.RiskApprovalCenter.riskEvents`：1 行替换 + 4 行注释说明同源契约。
  - `InspectorPanel.BossControlPanel.recentRiskCount`：1 行替换 + 3 行注释说明同口径。
  - `OPCCompanyCoreTests.swift`：1 个修订（重命名 + 重写 EventLogView 检查）+ 3 个新增测试（1 个跨 3 文件源码扫描守门 + 2 个行为契约）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「老板首页风险流过滤维护类事件」MARK 段内修订 + 新增）：
  - `technicalMaintenanceEventLogViewRetainsFullEventFeed`（修订自轮 9 既有）：守 EventLogView 必须 `ForEach(store.events)`（真正的技术维护视图）。
  - `bossFacingViewsAcrossPanelsUseFilteredBossRiskAccessor`：跨 3 文件源码扫描 — CommandCenter / InspectorPanel / OperationsSuite 必须含 `selectedProductBossRiskEvents` 且不能含 `store.selectedProductRiskEvents`。把轮 5/6/8 收敛后的 4 处老板视图统一守门，防止未来回退。
  - `riskApprovalCenterRiskEventsExcludeMaintenancePrefixes`（@MainActor）：行为契约 — 命令行健康预警事件必须不出现在 RiskApprovalCenter；业务风险事件正常入。
  - `bossControlPanelRecentRiskCountReflectsFilteredBossRiskEvents`（@MainActor）：行为契约 — 全量风险流 +2 时（含 1 维护前缀），过滤后 +1；BossControlPanel.recentRiskCount stat tile 必须用过滤后值（避免给老板看虚高数字）。
- **不动的边界**：
  - `EventLogView`（员工 inspector "事件" tab，line 957 `ForEach(store.events)`）100% 保留 — 技术负责人能看到全量事件做诊断。
  - `BossControlPanel.recentEvents` / `compactRecentReports`（轮 5 已用 `selectedProductBossEvents`）+ `CommandCenterView.riskEvents`（轮 9 已用 `selectedProductBossRiskEvents`）+ `BossReportCenter.reportEvents`（轮 6 已用 `selectedProductBossEvents`）100% 保留。
  - `RiskApprovalCenter` 的左栏「审批请求」/「待老板处理」+ 右栏「风险事件」section header / `prefix(8)` 容量 / `EventSignalRow` 视觉 100% 保留。
  - 5-01 红线 1 守住：所有维护类事件在员工 inspector EventLogView 100% 可见，老板视图只是过滤特定前缀的 densification（不是隐藏数据，技术诊断入口仍然存在）。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 写入一条「命令行健康预警：xxx」事件 → 老板首页 stat tile「近期风险 N」应不计入这条；
  2. 同上事件 → 老板审批中心右栏「风险事件」section 应不显示此条；
  3. 但员工 inspector「事件」tab 必须能看到此条；
  4. 写入业务风险（如「审批被驳回」）→ 老板侧三个 widget（首页 stat / 审批中心右栏 / 命令中心 risk widget）都要显示。

### 2026-05-03 员工工作台「我的协作收件箱」overflow footer 对齐三面板（角色继承期轮 7）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：完成员工工作台 5 个列表面板的 overflow 一致性收尾。轮 2 (`reviewQueuePanel`) / 轮 4 (`assignedTasks` + `queuePanel`) 三个面板已经统一 prefix(3) + 共享 `AgentDeskOverflowFooter` 模式；剩 `inboxPanel` 还在 prefix(6) **裸截断**（没有 footer 提示溢出条数）。当用户消息超过 6 条时，看不到"还有 N 条未展开"信息，与三面板模式不一致。
- **问题诊断**：
  - 收件箱裸 `prefix(6)` — 用户看到 6 条以为没有更多了，错过待处理协作消息会拖慢 review/handoff 流程。
  - 但 inbox 与 review/assigned/workQueue 三面板的根本差异：收件箱是核心协作功能，过度收敛（如降到 3）会损害"看到最近收到的消息"的本能；因此 limit 应保留 6（不与三面板的 3 同口径），只补 footer。
- **核心设计：limit 差异化 + 共享 footer 视图**：
  - store 端新增 `agentDeskInboxDefaultDisplayLimit = 6` 常量（注释说明"差异化 limit 是有意"）+ `agentDeskInboxOverflow() -> AgentDeskListOverflow?` accessor（与轮 4 同模式但对应 inbox 数据源 `selectedAgentRecentProductMessages`）。
  - view 端 `inboxBody` 把 `prefix(6)` 改为 `prefix(CompanyStore.agentDeskInboxDefaultDisplayLimit)` + `if let overflow = store.agentDeskInboxOverflow() { AgentDeskOverflowFooter(summary: overflow.summary) }`。
  - 复用轮 4 的 `AgentDeskOverflowFooter` 共享视图组件（不新增视图类型）。
  - 复用轮 4 的 `AgentDeskListOverflow` 通用 struct 类型。
- **实施**（最小侵入 + 复用模式）：
  - `CompanyStore` 新增 `agentDeskInboxDefaultDisplayLimit` 常量 + `agentDeskInboxOverflow()` 公共方法（无 agentID 参数，因为 `selectedAgentRecentProductMessages` 已按 selectedAgentID 隐式过滤）。
  - `inboxBody` 替换 prefix 字面量 + 加 footer 调用（紧贴 ForEach 内部）。
  - `selectedAgentRecentProductMessages` / `AgentMessageRow` / `agentDisplayName` / `inboxTaskTitle` / `shouldOfferAcknowledgement` / 「标记已读」/「打开协作消息总览」按钮 0 改动。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「员工工作台『我的协作收件箱』overflow footer 与三面板对齐」MARK 段）：
  - `agentDeskInboxDefaultDisplayLimitIsSixToPreserveCollaborationUX`：常量必须 = 6 且严格 > assignedTasks 的 3（防止有人误改成 3 损害协作 UX）。
  - `agentDeskInboxOverflowReturnsNilAtOrBelowLimitAndNonNilWhenExceeds`：边界测试 — 总数 == limit (6) 时 nil；总数 = limit + 2 时 hidden=2 + summary 含「2 条」。
  - `agentDeskInboxOverflowReturnsNilForBossOrAgentWithoutSession`：边界测试 — 选中不存在的 agent 时 selectedAgentRecentProductMessages 为空，overflow 返回 nil。
  - `inboxPanelInSelectionWorkspaceUsesInboxLimitConstantAndOverflowFooter`：源码扫描 — SelectionWorkspaceView 必须用 `CompanyStore.agentDeskInboxDefaultDisplayLimit` + `store.agentDeskInboxOverflow()`，反向禁止 `selectedAgentRecentProductMessages.prefix(6)` 硬编码字面量。
- **不动的边界**：
  - 「标记我的消息已读」/「打开协作消息总览」按钮 + 顶部「待确认 N」chip + EmptyCommandLine 占位文案 100% 保留。
  - `AgentMessageRow` 视觉、acknowledge 回调、taskTitle 解析 100% 保留。
  - `inboxBody` 的两个 if/else 分支（员工不在团队 / 还没收消息）100% 保留 — 这两个空状态路径不走 ForEach，没有 overflow。
  - 5-01 红线 1 守住：所有消息在「协作消息总览」`AgentMessageCenterSheet` 中 100% 可见，inbox 只是默认展开"前 6 条 + 摘要"的 densification（不是隐藏数据）。
  - 与三面板（review/assigned/workQueue）limit 差异（6 vs 3）有意保留，由专门契约测试 `agentDeskInboxDefaultDisplayLimitIsSixToPreserveCollaborationUX` 守门。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 选有 7+ 协作消息的员工 → inboxPanel 默认显示前 6 条 + 底部「还有 N 条协作消息未展开...」footer；
  2. footer 视觉与 review/assigned/queuePanel footer 完全一致（同 ellipsis.circle / 同字号 / 同背景）；
  3. 处理掉前几条消息 → 下一条自动浮现，footer 数量 -1；
  4. 收件箱 ≤ 6 条时 footer 消失（与三面板 ≤ 3 时同行为）；
  5. 「打开协作消息总览」点击后弹出的 sheet 中所有消息（含 footer 提示的隐藏部分）100% 可见。

### 2026-05-03 BossReportCenter「报告事件」收敛到产品作用域 + 老板视图过滤（角色继承期轮 6）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：完成轮 5 选定的候选 δ 拆分中的 η 部分。`OperationsSuiteView.BossReportCenter.reportEvents` 是老板专属"老板报告中心"面板，UI 文案明示「报告会汇总当前产品...」，但底层 `store.events.filter { ... }` 是**跨产品**的全局事件流 — UI 框架与数据源不一致。
- **问题诊断**：
  - `reportEvents` 内容选择规则（标题含「报告」/「快照」或 `kind == .artifactCreated`）合理，是面板专有业务逻辑保留在视图层。
  - 数据源 `store.events` 跨产品 — 用户在产品 A 工作台看 BossReportCenter 时会看到产品 B / 全局的"报告"事件，与"汇总当前产品"承诺不符。
  - 维护类前缀（命令行健康预警 + 任何未来登记前缀）在老板报告中心也应过滤 — 若未来有"命令行健康预警：xxx 报告异常"类标题恰好命中"报告"关键词，会污染列表。
- **核心设计：复用轮 5 的 selectedProductBossEvents accessor（产品作用域 + 共享老板视图前缀白名单）**：
  - 把 `store.events.filter { ... }` 替换为 `store.selectedProductBossEvents.filter { ... }`，保留视图层的内容选择规则不变。
  - 一行替换 + 一段注释说明意图，业务逻辑、UI 视觉、prefix(6) 容量、`bossMessages` 右侧栏 100% 不动。
  - 复用轮 5 的 accessor 意味着两个老板专属面板（BossControlPanel 侧栏综合事件流 + BossReportCenter 报告事件）现在共享同一份"产品作用域 + 维护前缀过滤"逻辑 — 加新维护前缀时两处同步生效。
- **实施**（最小侵入 + 复用轮 5）：
  - `OperationsSuiteView.BossReportCenter.reportEvents`：`store.events.filter { ... }` → `store.selectedProductBossEvents.filter { ... }`，加 3 行注释说明 UI 文案契约。
  - `CompanyStore` 0 改动 — 完全复用轮 5 的 `selectedProductBossEvents` accessor。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「BossReportCenter『报告事件』迁移到 selectedProductBossEvents」MARK 段）：
  - `bossReportCenterReportEventsAreScopedToSelectedProductOnly`：边界测试 — 同产品 + 报告标题入；跨产品 + 报告标题被过滤。
  - `bossReportCenterReportEventsExcludeMaintenancePrefixesEvenIfTitleContainsReport`：防御性测试 — "命令行健康预警：xxx 报告异常"类维护前缀事件即便标题含"报告"也必须被过滤；正常老板报告事件不受影响。
  - `bossReportCenterUsesSelectedProductBossEventsAndDropsRawStoreEventsFilter`：源码扫描 — OperationsSuiteView.swift 必须含 `store.selectedProductBossEvents.filter`，反向禁止 `store.events.filter` 重新出现。
- **不动的边界**：
  - `bossMessages`（line 2920，`store.messages(for: store.bossID).reversed().filter { ... }`）保留 — 这是按 bossID 过滤的消息流，本身就是按收件人作用域，不存在跨产品污染。
  - 内容选择规则（"报告" / "快照" / artifactCreated）100% 保留在视图层 — 这是面板专有业务，不进 store。
  - "生成老板报告" / "生成项目交接快照" / "生成健康体检" 三个按钮 + `prefix(6)` 容量 + `EmptyCommandLine` 占位文案 + 右侧"最近老板报告"栏 100% 保留。
  - `EventLogView`（员工 inspector tab，`InspectorPanel.swift` line 957 `store.events`）100% 保留全量 — 设计意图技术维护视图保留全量。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 多产品场景下，选老板进 OperationsSuite 「报告中心」 → 「报告事件」section 只显示当前产品的报告/快照/产物事件；
  2. 切产品 → 「报告事件」内容跟随刷新；
  3. 在某员工写一条「命令行健康预警：xxx 报告异常」事件 → 报告中心不应出现该条；
  4. 「生成老板报告」按钮触发后 → 新报告事件应在「报告事件」section 顶部出现。

### 2026-05-03 老板侧栏「近期汇报」/「最新消息」事件源迁移到产品作用域 + 老板视图过滤（角色继承期轮 5）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：完成轮 9（任务接力期）老板首页风险流过滤维护类事件主线的最后一片 — `BossControlPanel` 侧栏的 `recentEvents`（「近期汇报」prefix 5）/ `compactRecentReports`（「最新消息」prefix 3）两处仍在读 `store.events.prefix(N)`，**跨产品 + 含维护类**，与老板总控台 header「老板总控台 · [产品名] · 你只负责下目标、看进度、批准风险」明确产品级 + 老板专属定位不符。
- **问题诊断**：
  - 老板侧栏综合事件流（不只是风险）当前读全局 `store.events`，混入其他产品事件 + 命令行健康预警等技术维护类细节。
  - 轮 9 已经把 `CommandCenterView` 的 `riskEvents` 改为 `selectedProductBossRiskEvents`，但只覆盖了 risk kind；侧栏「近期汇报」面板综合显示所有 kind（message / artifactCreated / statusChanged 等），需要平行的 `selectedProductBossEvents` accessor。
  - `EventLogView`（员工 inspector tab，技术维护视图）+ `OperationsSuiteView.BossReportCenter`（cross-product 内容过滤，可能有意全局）本轮**不动**。
- **核心设计：与 selectedProductBossRiskEvents 平行的综合事件流 accessor + 共享前缀白名单**：
  - store 端新增 `selectedProductBossEvents` accessor，以 `selectedProductEvents`（产品作用域）为基底，复用 `bossViewExcludedRiskTitlePrefixes` 白名单过滤前缀；保留所有 kind（不只是 risk）。
  - view 端 `BossControlPanel.recentEvents`/`compactRecentReports` 两处 `store.events.prefix(N)` → `store.selectedProductBossEvents.prefix(N)`，UI 视觉/排版/section header 0 改动。
- **实施**（拆分双轨 + 共享白名单）：
  - `CompanyStore` 新增 `selectedProductBossEvents` accessor（紧贴 `selectedProductBossRiskEvents`），加详细注释说明与 RiskEvents 区别（保留所有 kind）+ 当前消费方清单。
  - `bossViewExcludedRiskTitlePrefixes` 白名单 0 改动 — 两个 accessor 共享同一份；新增维护前缀只需登记一次，两个老板视图同步生效。
  - `InspectorPanel.BossControlPanel.recentEvents` 第 576 行：`store.events.prefix(5)` → `store.selectedProductBossEvents.prefix(5)`。
  - `InspectorPanel.BossControlPanel.compactRecentReports` 第 608 行：`store.events.prefix(3)` → `store.selectedProductBossEvents.prefix(3)`。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「BossControlPanel 侧栏综合事件流迁移到 selectedProductBossEvents」MARK 段）：
  - `selectedProductBossEventsIsScopedToSelectedProductAndExcludesMaintenancePrefixes`：3 条事件（同产品业务 / 同产品维护前缀 / 跨产品）→ 老板视图只入 1 条业务，前缀和跨产品两条都被过滤。
  - `selectedProductBossEventsKeepsAllKindsNotJustRisk`：4 种非 risk kind（message / statusChanged / taskCreated / artifactCreated）必须全保留 — 与 RiskEvents 区别守门。
  - `selectedProductBossEventsAndSelectedProductBossRiskEventsShareMaintenancePrefixWhitelist`：契约测试 — 两个 accessor 必须同时过滤 `bossViewExcludedRiskTitlePrefixes` 全部前缀（防止未来有人只在一处加前缀，造成两个视图出现"半过滤"漂移）。
  - `bossControlPanelInInspectorPanelUsesSelectedProductBossEventsAndDropsRawStoreEventsPrefix`：源码扫描 — InspectorPanel.swift 必须含 `store.selectedProductBossEvents.prefix(5)` + `store.selectedProductBossEvents.prefix(3)`，反向禁止 `store.events.prefix(5)` / `store.events.prefix(3)`。
- **不动的边界**：
  - `EventLogView`（员工 inspector tab，line 957 `store.events`）100% 保留全量，技术负责人能看到维护类事件诊断。
  - `OperationsSuiteView.BossReportCenter.reportEvents`（line 2925，含「报告」/「快照」字符串过滤的 cross-product 全局事件）保持不动 — 报告中心可能有意全局，需要 codex 决定。
  - `BossControlPanel.recentRiskCount`（line 320）继续读 `selectedProductRiskEvents.count` 全量（统计场景，不是显示风险事件）。
  - 轮 9 既有的 `CommandCenterView.riskEvents = selectedProductBossRiskEvents` 0 改动。
  - section header「近期汇报」/「最新消息」文案、容量 prefix(5)/prefix(3)、卡片视觉 100% 保留。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 选老板进 BossControlPanel（任意产品）→ 「近期汇报」section 只显示当前产品事件，且无「命令行健康预警：」前缀的卡片；
  2. 切换 mainWorkspace 到 `commandCenter` 或 `productDetail`（compact 模式）→ 「最新消息」section 同上；
  3. 切产品 → 「近期汇报」内容应跟随产品切换刷新（验证产品作用域生效）；
  4. 在某员工写一条「命令行健康预警：xxx」事件 → 老板侧栏不应出现，但员工 inspector「事件」tab（EventLogView）必须仍可见。

### 2026-05-03 员工工作台「负责的任务」/「员工工作队列」prefix 收敛 + 通用溢出 footer（角色继承期轮 4）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：承接轮 2「我的待审任务」prefix 收敛主线，把员工工作台另两个 `prefix(8)` 列表 — `assignedTasks`（员工负责的任务，每张 task card ~70-90pt）与 `queuePanel`（员工工作队列，每张 ~70-90pt）也收敛为 `prefix(3)` + 共享溢出 footer。三个面板（reviewQueue / assignedTasks / queuePanel）现在统一行为：超过 3 项就只展开前 3 张 + 底部一行 muted footer 提示剩余数量与处理后自动浮现策略。
- **问题诊断**：在 task 较多的产品（如 5 任务上方）打开工作台时，单个员工身上 `assignedTasks` 8 张 + `queuePanel` 8 张 = 16 张任务卡，加 `terminalSummary`(~120pt) + `profilePanel` chip 行(~60pt) + `commandPanel` 输入区(~140pt) + `reviewQueuePanel`（reviewer 角色额外 3 张 + footer），整张工作台总高度可达 1600-1800pt，远超首屏（典型 900-1100pt）。轮 2 只解决了 reviewer 一支，剩两支 `prefix(8)` 仍在恶化首屏密度。
- **核心设计：通用化 overflow 类型 + 共享 footer 视图**：
  - store 端把轮 2 的 `AgentDeskReviewQueueOverflow` 通用化重命名为 `AgentDeskListOverflow`（{hiddenCount, summary} 双字段不变，只换名字 — 三个 accessor 复用同一类型，未来若新增第 4 个列表也直接复用）。
  - 新增 `agentDeskAssignedTasksDefaultDisplayLimit = 3` / `agentDeskWorkQueueDefaultDisplayLimit = 3`（与 `agentDeskReviewQueueDefaultDisplayLimit` 三常量并排，方便后续统一调整）。
  - 新增 `agentDeskAssignedTasksOverflow(forAgentID:)` / `agentDeskWorkQueueOverflow(forAgentID:)` accessor，与轮 2 同模式：列表长度超过 limit 才返回非 nil（hidden = total - limit）。
  - view 端把轮 2 内联在 `reviewQueuePanel` 的 9 行 footer HStack 提取为 `private struct AgentDeskOverflowFooter: View { let summary: String; ... }` 单一可复用视图，三个面板（reviewQueue / assignedTasks / queuePanel）调用同一组件，DRY。
- **实施**（拆分双轨 + 复用模式）：
  - `CompanyStore`：rename `AgentDeskReviewQueueOverflow` → `AgentDeskListOverflow`（3 处全局替换）；新增 2 常量 + 2 accessor，紧贴轮 2 `agentDeskReviewQueueOverflow()`。
  - `Task` 业务字段、`agent.permissions`、`runtimeSession`、`commandHistory` 0 改动。
  - `AgentDeskWorkspace.assignedTasks`：`agentTasks.prefix(8)` → `agentTasks.prefix(CompanyStore.agentDeskAssignedTasksDefaultDisplayLimit)` + `if let overflow = store.agentDeskAssignedTasksOverflow(forAgentID: agent?.id) { AgentDeskOverflowFooter(summary: overflow.summary) }`。
  - `AgentDeskWorkspace.queuePanel`：`agentQueue.prefix(8)` → `agentQueue.prefix(CompanyStore.agentDeskWorkQueueDefaultDisplayLimit)` + 同 footer。
  - `AgentDeskWorkspace.reviewQueuePanel`：内联 footer HStack 替换为 `AgentDeskOverflowFooter(summary: overflow.summary)`，行为不变。
  - 新增 `private struct AgentDeskOverflowFooter`（紧凑单行 muted 提示，ellipsis.circle icon + 11pt medium muted text + surfaceRaised 0.32 背景 + 8pt corner，与轮 2 内联版完全等价的视觉）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「员工工作台『负责的任务』/『工作队列』prefix 收敛」MARK 段）：
  - `agentDeskAssignedTasksAndWorkQueueLimitsAreThreeAndReducedFromOriginalEight`：双常量必须 = 3 且严格 < 8（防止有人直接撤销改回 8）。
  - `agentDeskAssignedTasksOverflowReturnsNilWhenAtOrBelowLimitAndNonNilWhenExceeds`：边界测试 — 0/1/2/3 项时 nil；4 项时 hidden=1 + summary 含「1 项」。
  - `agentDeskWorkQueueOverflowReturnsNilWhenAtOrBelowLimitAndNonNilWhenExceeds`：同上。
  - `agentDeskAssignedTasksAndQueuePanelInSelectionWorkspaceUseLimitConstantAndOverflowFooter`：源码扫描必须用新常量 + AgentDeskOverflowFooter 调用 + 反向禁止 `prefix(8)` 在 assignedTasks/queuePanel 段重新出现。
- **不动的边界**：
  - 任务卡视觉、TaskSignalRow、Approve / Reject 按钮 0 改动。
  - 「分派给我的任务」/「员工工作队列」section header 文案与排序逻辑 100% 保留。
  - reviewer 待审任务的轮 2 收敛行为 100% 保留（只是底层视图组件统一了，行为不变）。
  - 5-01 红线 1 守住：所有任务在「协作消息总览」/「任务总览」/产品工作台主列表中仍 100% 可见，工作台只是改为"前 3 张 + 摘要" densification，不是隐藏数据。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 选有 5+ 任务的产品 → 任意员工进工作台 → assignedTasks 区只显示前 3 张任务卡 + 底部「还有 N 项分配任务未展开...」footer；
  2. 同员工的 queuePanel 区同上；
  3. 三个面板（reviewQueue / assignedTasks / queuePanel）的 footer 视觉应完全一致（同 ellipsis.circle + 同字号 + 同背景）；
  4. 处理掉前 3 张任务后下一张应自动浮现（footer 数量 -1，归零时 footer 消失）；
  5. 整张工作台首屏密度对比改造前应明显改善（典型场景从 1600-1800pt 收敛到 ~900-1100pt 内）。

### 2026-05-03 员工工作台「模型和权限」面板 chip 化收敛（角色继承期轮 3）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：候选 C 拆解的 C 项 — 把员工工作台 `profilePanel`（"模型和权限"）默认展示的 6 行 ProfileMiniRow（每行 ~32pt + spacing 12pt = ~44pt × 6 = ~264pt）收敛为 wrap chip 行（~28pt × 1-2 行 = 28-56pt），节省 ~200pt。**不引入 DisclosureGroup 折叠**（所有 6 个字段仍默认可见，只是更紧凑），守 5-01 红线 1。
- **核心设计：data-driven chip stream + 视图层 LazyVGrid**：
  - store 端把"哪些字段进 chip 列表"集中：4 项核心 chip 始终展示（后端 / 命令行工具 / 模型 / 推理强度）+ 2 项会话 chip 仅在 runtimeSession 存在时追加（会话 / 保活）。
  - view 端 LazyVGrid 自适应排列（minimum 140pt），窄屏自动多行，宽屏单行；每个 chip = 紧凑 Capsule 含 label（10pt heavy muted）+ value（10pt mono ink）。
  - 错误 banner / 预热-重开按钮 / 权限 FlowLayout 100% 保留（这些原本就是必要的"可操作"控件，不是技术细节展示）。
- **实施**（拆分双轨 + 复用模式）：
  - `CompanyStore` 新增公共 `AgentDeskProfileChip` struct（label / value / Identifiable id = label）+ `agentDeskProfileChips(forAgentID:) -> [AgentDeskProfileChip]` accessor，紧贴轮 2 `agentDeskReviewQueueOverflow()`。
  - `agent.backend` / `runtimeSession(for:)` / `agentDeskWorkspace` 业务字段 0 改动。
  - `AgentDeskWorkspace.profilePanel` 6 个 `ProfileMiniRow` 调用 → 1 个 `LazyVGrid + ForEach + AgentDeskProfileChipView`；新增私有 `AgentDeskProfileChipView` 紧凑 Capsule chip 视图。
  - `ProfileMiniRow` struct 保留（未来如有"详情面板"场景仍可复用，删除影响小但暂留）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「员工工作台『模型和权限』面板 chip 化收敛」MARK 段）：
  - `agentDeskProfileChipsReturnFourCoreFieldsForAnyAgentEvenWithoutSession`：任何员工（即便无 session）都必须返回 4 项核心 chip；nil agentID → 空数组。
  - `agentDeskProfileChipsAppendSessionFieldsOnlyWhenRuntimeSessionExists`：无 runtimeSession 时不能含「会话」「保活」chip；预热建立 session 后必须追加。
  - `agentDeskProfileChipValuesAreNonEmptyAndShortEnoughForCapsule`：所有 chip 的 label / value 非空（避免 capsule 内显示空白）。
  - `agentDeskProfilePanelInSelectionWorkspaceUsesChipAccessorAndDropsProfileMiniRowStack`：源码扫描必须用新 accessor + AgentDeskProfileChipView + 反向禁止 6 个 `ProfileMiniRow(label: "...")` 硬编码调用。
- **不动的边界**：
  - 错误 banner（`session.lastError` 非空时）100% 保留视觉（红色 10% 透明背景）。
  - 「预热团队」/「重开」2 按钮 + 触发的 `prewarmSelectedProductAgentSessions` / `restartAgentSession` 业务方法 0 改动。
  - 权限 FlowLayout（`agent.permissions.map(\.title).sorted()`）100% 保留。
  - 区块顺序：SectionHeader → chip grid → error banner → 2 按钮 → permissions FlowLayout，与改造前一致。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 默认产品任意员工卡进工作台 → profilePanel 顶部应显示 4 个 chip 横排（后端 / 命令行工具 / 模型 / 推理强度），窄屏自动 2×2 换行；
  2. 触发预热产生 session 后 → 追加 2 个 chip（会话 / 保活），共 6 chip；
  3. chip capsule 视觉：浅 surfaceRaised 背景、label muted 灰、value mono ink、单行 truncationMode middle；
  4. session.lastError 出现时仍渲染红色 banner（不被 chip 收敛）；
  5. 整张 panel 比改造前明显紧凑（节省 ~200pt 垂直空间）。

### 2026-05-03 员工工作台「我的待审任务」prefix 收敛 + 溢出提示（角色继承期轮 2）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：承接同日轮 1 的员工工作台默认可见信息密度优化主线，把 `reviewQueuePanel`（仅对 reviewer 角色出现的"我的待审任务"）默认展开 `prefix(8)` 收敛为 `prefix(3)` + 溢出 footer 提示。reviewer 待审任务超过 3 项时只展开前 3 张卡（避免垂直无止境拥挤），底部加单行紧凑 footer 显示「还有 N 项待审任务未展开。处理完上方任务后下一项会自动浮现，或在协作消息总览查看完整队列。」
- **问题诊断**：原 `prefix(8)` 在 reviewer 任务积压时会展开 8 张任务卡，每张约 80pt（TaskSignalRow + 2 个按钮），共约 640pt；加文本框 + section header + commandPanel padding 后整张面板可达 800pt+，把工作台下方 `assignedTasks` / `terminalSummary` / `queuePanel` / `profilePanel` 都挤到首屏外。
- **核心设计：可调常量 + 信息式溢出提示**：
  - 不引入 sheet 全队列展开（避免拉入次生作用域）；reviewer 处理完上方 3 项后下一项自动浮现，「协作消息总览」是既存的全队列兜底入口。
  - 不引入 `DisclosureGroup` 折叠（守 5-01 红线 1）；溢出 footer 是纯信息提示，不可点击展开。
  - 上限做成 `public static let` 常量（`agentDeskReviewQueueDefaultDisplayLimit = 3`），方便未来调参 + 测试断言"必须 < 8"防止退化。
- **实施**（拆分双轨）：
  - `CompanyStore` 新增 `public static let agentDeskReviewQueueDefaultDisplayLimit: Int = 3`、公共 `AgentDeskReviewQueueOverflow` struct（`hiddenCount: Int`、`summary: String`）、`agentDeskReviewQueueOverflow() -> AgentDeskReviewQueueOverflow?` accessor，紧贴 `selectedAgentReviewQueue`。
  - `selectedAgentReviewQueue` / `completeReviewByOwner` / `rejectReviewByOwner` 等业务 API 0 字节改动。
  - `AgentDeskWorkspace.reviewQueuePanel` 把硬编码 `prefix(8)` 替换为 `prefix(CompanyStore.agentDeskReviewQueueDefaultDisplayLimit)`；ForEach 之后条件渲染 footer（`ellipsis.circle` icon + `overflow.summary`，2 行 lineLimit，更轻的 surfaceRaised 背景）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「员工工作台『我的待审任务』prefix 收敛 + overflow 提示」MARK 段）：
  - `agentDeskReviewQueueDefaultDisplayLimitIsThreeAndReducedFromOriginalEight`：上限 == 3 + 必须 < 8（双向锁，防止退化回 prefix(8)）。
  - `agentDeskReviewQueueOverflowReturnsNilWhenQueueAtOrBelowLimit`：队列 ≤ limit 时 overflow 必须 nil（含队列 = 0 和队列 = limit 两种边界）。
  - `agentDeskReviewQueueOverflowExposesHiddenCountAndChineseSummaryWhenQueueExceedsLimit`：队列 = 7 时 hiddenCount = 4、summary 含具体数字 + 「待审」、反向禁用「折叠 / DisclosureGroup」措辞。
  - `agentDeskReviewQueuePanelInSelectionWorkspaceUsesLimitConstantAndOverflowAccessor`：源码扫描——必须用 `CompanyStore.agentDeskReviewQueueDefaultDisplayLimit` 常量 + 必须调用 `store.agentDeskReviewQueueOverflow()` + 反向禁止再含 `selectedAgentReviewQueue.prefix(8)`。
- **不动的边界**：
  - `selectedAgentReviewQueue` 数据源 0 改动；reviewer 角色门禁 / canReview 逻辑不变。
  - 「N 项」chip（`Text("\(store.selectedAgentReviewQueue.count) 项")`）继续显示完整队列长度（让 reviewer 始终知道总量）。
  - 共享文本框 + 完成审查 / 打回返工按钮位置不变。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. reviewer 角色注入 7 条 needsReview 任务后，工作台只展开前 3 张卡 + 底部一行「还有 4 项待审任务未展开...」提示；
  2. footer chip 视觉比上方任务卡明显更轻（surfaceRaised 0.32 透明度 vs panel 0.72）；
  3. 顶部「N 项」chip 仍显示完整 7（不被 prefix 影响）；
  4. reviewer 完成 1 项后队列下降到 6，footer 提示更新为「还有 3 项」（自动响应）；
  5. 队列 ≤ 3 时 footer 完全消失（不留空白行）。

### 2026-05-03 员工工作台「发起员工交接」面板空状态收敛（角色继承期轮 1 ）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：把员工工作台 (`AgentDeskWorkspace`) 默认可见的次大噪音源 — `handoffComposer` 面板在 3 种"无法交接"场景（老板视角 / 员工未加入产品团队 / 当前产品没有可接收对端）下原本各自渲染一条 `EmptyCommandLine` 撑满整张 commandPanel（约 95-100pt 垂直空间）— 收敛为单行紧凑提示（约 42pt），节省 ~55pt × 出现频次。
- **问题诊断**：handoff §0.3 / §4.5 候选 C「员工工作台 `AgentDeskWorkspace` 信息密度优化」长期搁置（"改动面大 + 单 turn 难做完"）。本轮先调研 638 行 `AgentDeskWorkspace`（SelectionWorkspaceView.swift:1289-1926），识别 6 个默认可见信息密度问题（详见 §4.5 表），按 ROI 优先级落地最高的 A 项（handoffComposer 空状态）。其它 5 项写入候选下一轮。
- **核心设计：拆分双轨 + view 视图层 enum 决策**：
  - `CompanyStore` 新增公共 `AgentDeskHandoffComposerState` enum（`.expanded` / `.collapsed(reason: String)`）+ `agentDeskHandoffComposerState() -> AgentDeskHandoffComposerState` accessor，把 4 种业务分支（含未选中员工兜底）集中到 store 层。
  - `selectedAgentHandoffRecipients` / `selectedAgentHandoffTaskCandidates` / `postSelectedAgentHandoff` 等既有业务 API 100% 保留，sheet 等其它消费方不受影响。
  - `AgentDeskWorkspace.handoffComposer` 改为 switch 分发到 `handoffComposerCollapsedRow(reason:)`（紧凑单行 HStack）或 `handoffComposerExpanded`（保留原 4 输入 + 按钮表单）；既有 `commandPanel()` 视觉风格在两个分支中均保留，确保与邻近 `inboxPanel` / `reviewQueuePanel` 视觉一致。
  - 不引入新 `DisclosureGroup`（这是"内容驱动的紧凑"不是"折叠隐藏"，5-01 红线 1 不触）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「员工工作台『发起员工交接』面板空状态收敛」MARK 段）：
  - `agentDeskHandoffComposerStateExpandsForEngineerInTeamWithRecipients`：默认产品工程师有 ≥ 1 个对端 → state 必须 `.expanded`。
  - `agentDeskHandoffComposerStateCollapsesForBossSelectionWithReason`：选中老板 → `.collapsed`，原因含「老板」+「交接」+ 长度 < 80 字（紧凑约束）。
  - `agentDeskHandoffComposerStateCollapsesWhenAgentNotInProductTeamWithReason`：员工未加入新产品团队 → `.collapsed`，原因含员工名 +「产品」（让老板识别哪个员工）。
  - `agentDeskHandoffComposerStateCollapsesWhenNoOtherRecipientsInTeam`：员工已加入但团队里只有自己 → `.collapsed`，原因含「可接收交接的员工」或「邀请」。
  - `agentDeskHandoffComposerInSelectionWorkspaceUsesAccessorAndCollapsesEmptyState`：源码扫描——必须用新 accessor + 必须有 `handoffComposerCollapsedRow` / `handoffComposerExpanded` 双分支 + 反向禁止再硬编码原 3 个 EmptyCommandLine 撑满 panel。
- **不动的边界**：
  - `selectedAgentHandoffRecipients` / `selectedAgentHandoffTaskCandidates` / `postSelectedAgentHandoff` 业务 API 0 字节改动。
  - `AgentMessageCenterSheet`（点击"查看全部"按钮打开的 sheet）独立路径未触动。
  - 非 handoffComposer 区段（header / inboxPanel / reviewQueuePanel / assignedTasks / terminalSummary / queuePanel / profilePanel）100% 保留原渲染。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 选中老板 / 选中未加入团队员工 / 切到只有自己的产品 → handoffComposer 是否如预期收敛为 ~42pt 单行（含 icon + 标题 + chip + 原因）；
  2. 选中默认产品工程师 → handoffComposer 是否仍是完整 4 输入 + 发送按钮表单；
  3. 单行原因在窄屏（< 480pt）下是否能 lineLimit(2) 不溢出；
  4. 视觉与邻近 `inboxPanel` / `reviewQueuePanel` commandPanel 风格是否仍一致（border / background / shadow）。

### 2026-05-02 老板首页风险流过滤维护类事件（修复轮 7 引出的污染风险）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：修复轮 7「CLI 健康状态变化事件流审计」自评 §6 列出的"老板首页『最近风险』被维护事件污染"风险。当前 `selectedProductRiskEvents` 被老板总控台 (`CommandCenterView`) 与技术维护视图 (`InspectorPanel` / `OperationsSuiteView`) 同时消费，轮 7 加入的「命令行健康预警：」事件会挤占老板首页 prefix(5) / prefix(3) 容量。
- **拆分双轨改造**（沿用 codex「维护类 VR/AR 隔离」模式）：
  - `CompanyStore` 新增公共白名单 `bossViewExcludedRiskTitlePrefixes: [String]` 和 accessor `selectedProductBossRiskEvents`。
  - 当前白名单仅含「命令行健康预警：」（轮 7 引入的标题前缀）；未来加入新的技术维护类 .risk 事件标题需同步登记到此处。
  - 既有 `selectedProductRiskEvents` 100% 保留，技术负责人视图（InspectorPanel.swift:320 / OperationsSuiteView.swift:2706）继续读全量。
  - `CommandCenterView`（老板总控台）改读新的 `selectedProductBossRiskEvents`。
- **不动的边界**：
  - `terminalHallOverviewSummaryText()` / `terminalHallOverviewMetrics()` / `terminalHallOverviewNextStepText()` 这 3 处技术负责人视图的「最近风险」继续读全量 `selectedProductRiskEvents`（既有契约不变）。
  - 维护类 VR / AR 的隔离机制（`technicalMaintenanceVerificationTitles` / `technicalMaintenanceArtifactTitlePrefixes`）100% 保留。
  - CompanyEvent 数据源不变，只是老板视图加一层过滤。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「老板首页风险流过滤维护类事件」MARK 段）：
  - `selectedProductBossRiskEventsExcludesMaintenancePrefixesButKeepsBusinessRisks`：注入 1 维护事件 + 1 业务事件 → 全量 +2、老板视图 +1，且老板视图新增的是业务风险。
  - `bossViewExcludedRiskTitlePrefixesIncludesCLIHealthWarning`：契约断言「命令行健康预警：」必须在白名单中（任何 PR 想拿掉这条剔除必须先动这个测试）。
  - `bossCommandCenterUsesFilteredRiskAccessorInsteadOfFullRiskList`：源码扫描 CommandCenterView 必须用 `selectedProductBossRiskEvents`，**不能**再含 `selectedProductRiskEvents`。
  - `technicalMaintenanceViewsStillReadFullRiskEvents`：源码扫描 InspectorPanel / OperationsSuiteView 必须继续读全量 `selectedProductRiskEvents`（确保过滤只发生在老板视图）。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请复核：
  1. 老板首页「风险」widget 计数是否如预期不再包含 CLI 健康预警事件；
  2. 老板首页「最近事件」prefix(3) 是否仍能展示真实业务风险（不被维护事件占满）；
  3. 技术负责人 InspectorPanel / 检查器仍能完整看到 CLI 健康预警事件用于诊断；
  4. 未来加入的"维护类 .risk 事件"是否需要补充到 `bossViewExcludedRiskTitlePrefixes` 白名单。

### 2026-05-02 终端大厅员工卡按钮收敛 + 卡片整体可点击选中

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：终端大厅默认可见 UI 优化主线的扫尾轮（轮 1/2/3/4/5 已完成顶部紧凑 + 自适应 + 健康徽章）。本轮收敛底部按钮区视觉密度 + 加卡片整体可点击兜底，进一步降低用户必须找按钮的成本。
- **改动**（`TerminalHallView.swift` 657-695 + 707-720）：
  - 「选中」按钮从 `Label("选中", systemImage: "person.crop.circle")` 简化为 icon-only `Image(systemName: "person.crop.circle")`，节省底部按钮宽度约 30-40pt。
  - 保留 `.help("选中员工")` hover tooltip + `.accessibilityLabel("选中员工")` + `.accessibilityHint(...)` —— **Computer Use 寻址完整保留**，与 codex 5-01 「icon-only 按钮必须暴露中文 a11y label」准则对齐（`terminalHallAndCommunicationIconOnlyButtonsExposeChineseAccessibilityLabel` 守门）。
  - 卡片整体加 `.contentShape(RoundedRectangle(cornerRadius: 8))` + `.onTapGesture { store.selectAgent(agent.id) }` 兜底选中。SwiftUI 中内部 Button 的 tap 高优先级，不会被父 onTapGesture 抢走（预检/运行/清空日志按钮行为完全保留）。
  - 加 `.accessibilityAction(named: "选中员工")` Computer Use 显式动作入口（即便 Computer Use 不点 icon 按钮，也能通过 accessibility action 触发）。
- **不动的边界**：
  - 「预检」「运行」「清空日志」3 个按钮保持原样（运行按钮仍是 borderedProminent 强调主操作；清空仍是 borderless icon 弱操作）。
  - 卡片选中视觉效果（CompanyTheme.selected 背景色 + selectedStroke 边框）100% 保留。
  - `store.selectAgent(_:)` 行为不变。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅员工卡按钮收敛」MARK 段）：
  - `terminalAgentCardSelectButtonIsIconOnlyAndCardIsTappableAsFallback`：源码扫描——
    - 「选中」按钮**不能**再含 `Label("选中", systemImage: "person.crop.circle")` 字面量（必须简化）；
    - 必须含 `Image(systemName: "person.crop.circle")` icon-only 形式；
    - 必须保留 `.accessibilityLabel("选中员工")` + `.help("选中员工")`；
    - `TerminalAgentCard` body 内必须有 `.contentShape(RoundedRectangle(cornerRadius: 8))` + `.onTapGesture` + `.accessibilityAction(named: "选中员工")`。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 员工卡底部按钮区视觉宽度比改造前明显减少（icon-only "选中" + Label "预检"/"运行" + icon "清空"）；
  2. 点击卡片任意空白区（avatar 旁、backend 摘要旁、终端日志区外）应触发员工选中（高亮变化）；
  3. 点击「预检」「运行」「清空日志」「选中」按钮本身应触发各自动作（不应被卡片 onTapGesture 抢走）；
  4. 鼠标悬浮 person.crop.circle icon 应显示 hover tooltip「选中员工」；
  5. Computer Use 通过 accessibility tree 应能找到「选中员工」按钮 + 「选中员工」accessibility action。

### 2026-05-02 CLI 健康状态变化事件流审计（推进 codex 增强方案"审计"长期项）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：推进 codex 多 Agent 增强方案长期项「**真实模型链路的生产级容错、审计和可视化**」中的"**审计**"部分。当前 `recordCLIInteractionObservationIfNeeded` 在 phase 变化时只写中文摘要到 `terminalLogs[agent.id]`，技术负责人和老板想回查"过去一段时间出现过几次授权异常 / 忙碌 / 临时异常"必须解析文本日志。本轮在已有 phase 去重逻辑里追加结构化 `CompanyEvent`，让事件流（已被多个面板消费）能反映 CLI 健康状态变化历史。
- **关键设计：只升级到 attention 状态时写事件**：
  - 写事件的 phase：`.busy` / `.authenticationBlocked` / `.transientFailure`（与轮 4 健康徽章口径一致，但不含 `.awaitingResponse`，因后者属于常规等待，不是预警）。
  - 不写事件的 phase：`.unknown` / `.ready` / `.completedTurn` / `.awaitingResponse`。
  - 复用既有 `previousPhase != observation.phase` 去重逻辑：同一 attention 状态反复观察不会反复写事件。
  - 从 attention 状态恢复到 ready/completedTurn 也不写"恢复"事件，避免老板看到"恢复"也算成预警噪音。
- **实施**：
  - `CompanyStore.recordCLIInteractionObservationIfNeeded`（CompanyStore.swift:9278 附近）在既有 terminalLogs 写入分支末尾追加：
    ```swift
    if isCLIAttentionPhaseForAuditEvent(observation.phase) {
        appendEvent(kind: .risk,
                    title: "命令行健康预警：\(agent.displayName)",
                    detail: "\(observation.reasonTitle) · 建议：\(recoveryAction.title)。\(operatorHint ?? "")",
                    agentID: agent.id)
    }
    ```
  - 新增私有 helper `isCLIAttentionPhaseForAuditEvent(_:)` 集中定义"哪些 phase 进事件流"的契约；与轮 4 `terminalAgentCardHealthBadge` 的可视化口径**一致但更收敛**（不含 .awaitingResponse）。
- **不动的边界**：
  - `recordPersistentTerminalREPLObservation`（CompanyStore.swift:8429）单轮 REPL 同步路径**不**做同样改造：那条路径 phase 变化更频繁（每轮 REPL 都跑），加事件会噪音；只覆盖主流的 `recordCLIInteractionObservationIfNeeded`。
  - `terminalLogs` 中文摘要继续写（既有审计来源不变）。
  - 既有 `appendEvent` API、events @Published 数组、风险流过滤逻辑 100% 保留。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「CLI 健康状态变化事件流审计」MARK 段）：
  - `cliInteractionPhaseUpgradeToAttentionWritesStructuredRiskEvent`：升级到 attention phase 后 events 中正好新增 1 条 `.risk` 事件，标题前缀「命令行健康预警：」+ 含员工名、detail 含中文 attention 描述、agentID 正确。
  - `cliInteractionPhaseRepeatObservationDoesNotWriteDuplicateEvents`：同一 attention phase 反复观察 3 次只写 1 条事件（依赖 phase 去重）。
  - `cliInteractionPhaseReadyOrCompletedDoesNotWriteHealthEvent`：ready / completedTurn 不写健康预警事件（避免噪音）。
  - `cliInteractionPhaseTransitionFromAttentionToReadyDoesNotWriteEvent`：从 attention 恢复到 ready 不写新事件（避免给老板"恢复"也算成预警噪音）。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请复核：
  1. 老板首页"最近风险"统计是否会因为 CLI 健康预警进入而失真（建议加监控）；
  2. `isCLIAttentionPhaseForAuditEvent` 与 `terminalAgentCardHealthBadge` 口径不一致（前者不含 .awaitingResponse），是否需要统一；
  3. 同一员工短时间内反复在 .busy ↔ .ready 之间切换是否会写多条事件（理论上每次升级都写一次，可能噪音）。如果有问题可加最短间隔守门。

### 2026-05-02 通信网关入站 HTTP 服务前置守门（推进 codex 增强方案长期项）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：推进 codex 多 Agent 增强方案长期项「**真正暴露公网/局域网入站 HTTP 服务仍必须默认关闭，并在 HMAC、白名单、nonce 和端口策略全部就绪后再打开**」。本轮**不**实施 HTTP 入站服务（代码上禁止），而是加 4 条防御性守门测试，确保任何未来 PR 不能意外引入入站 HTTP listener、不能改默认通道开启入站、不能放开入站三联条件。
- **调研结论**：当前 `Sources/OPCCompanyCore` 中**不**含任何 HTTP/socket 服务监听代码（grep 无 `NWListener` / `HTTPServer` / `Vapor` / `NIOHTTP1` / `Hummingbird` / `URLSessionStreamTask`）。通信网关入站只通过 `CommunicationInboundVerifier` 接受测试夹具与本地指挥台模拟入站，外部签名通道走结构化 JSON + HMAC 校验，不真起 HTTP 服务。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「通信网关入站 HTTP 服务前置守门」MARK 段）：
  - `communicationChannelDefaultsToDisabledAndCommandsOff`：新创建的 `CommunicationChannelConfig` 必须 `isEnabled = false` + `commandsEnabled = false`（外发汇报 `reportsEnabled` 默认 true 仍允许，因为低风险方向）。
  - `communicationChannelKindOnlyTelegramBotAndLocalSupportInbound`：只有 `.telegramBot` / `.localOnly` 两种通道类型 `supportsInboundCommand == true`；其它（飞书/企业微信/钉钉/邮件）必须 false——攻击面契约。
  - `sourceCodeContainsNoBoundHTTPListenerOrSocketServer`：扫描 `Sources/OPCCompanyCore` 全部 .swift 文件，禁止出现 `NWListener` / `URLSessionStreamTask` / `import NIOHTTP1` / `import Vapor` / `HTTPServer(` / `Hummingbird` 等任何启动 HTTP/socket listener 的 API。
  - `communicationChannelEnablingInboundRequiresAllThreeSwitchesOn`：要让通道真正接受入站指令，必须三条同时满足：`kind.supportsInboundCommand` + `isEnabled` + `commandsEnabled`；任一缺失或 webhook 类应被拒绝。
- **未来如何打开入站 HTTP 服务的正确流程**（写在测试 doc-comment 里）：
  1. 在 `OPC_COMPANY.md` 第 10 节同步规则；
  2. 写完 HMAC / 白名单 / nonce / 端口策略测试；
  3. 加显式 admin enable 开关（不能默认开启）；
  4. 才能放开本守门测试中的 `bannedAPIs` 列表。
- **不动的边界**：`CommunicationChannelConfig` / `CommunicationChannelKind` / `CommunicationInboundVerifier` 等既有 store 端 API 与字段 100% 保留；不修改任何业务逻辑。
- **降级声明**：本轮纯防御性测试，无业务代码改动，无需 codex Computer Use 真机复核；codex 回来后请正常审阅 4 条新测试，确认没有过度限制未来扩展空间。

### 2026-05-02 终端大厅总览「健康预警」chip 联动（产品级聚合预警）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：把同日轮 4 的「员工卡 CLI 健康徽章」（单卡视角）升级为产品级聚合预警，让技术负责人在终端大厅顶部总览一眼看到当前产品里有多少员工处于 attention 状态（busy / authBlocked / transientFailure / awaitingResponse），无需逐张卡片扫描。
- **核心设计：条件追加而非默认显示**：
  - 默认场景（无 attention 员工）→ 总览仍是 5 个固定 chip（团队 / 运行中 / 待审批 / 阻塞/失败 / 最近风险），与轮 2 既有契约 100% 兼容。
  - 一旦当前产品有 ≥ 1 个员工进入 attention 状态 → 总览 chip 行末尾追加第 6 个「健康预警 N」danger 红色 chip，N = attention 员工数。
  - 这样默认窄屏卡片不被挤压；只有真出风险时第 6 chip 才浮现，符合「老板视角优先 + 默认不打扰」准则。
- **实施**（沿用拆分双轨 + 复用模式）：
  - `CompanyStore` 新增 `terminalHallOverviewAttentionAgentCount() -> Int`：复用轮 4 `terminalAgentCardHealthBadge(for:)` 数据源；遍历 `selectedProductAgents`，统计 badge != nil 的员工数。徽章 nil 的员工（OK / unknown / API/local）不计入。
  - `terminalHallOverviewMetrics()` 末尾条件追加：`if attentionCount > 0 { metrics.append(...健康预警...) }`。
  - view 端 `TerminalHallOverviewSummary` **零改动**：已经用 `ForEach(store.terminalHallOverviewMetrics(), id: \.title)` 遍历，自动适应 5 或 6 个 chip。
- **数据流闭环**：
  - 轮 4 单卡 `terminalAgentCardHealthBadge(for:)` ← 同时被 view 端单卡渲染 + 轮 5 总览聚合 accessor 调用。
  - 一处数据源，两处视图消费，不重复实现状态判定逻辑。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅总览健康预警 chip 联动」MARK 段）：
  - `terminalHallOverviewAttentionAgentCountReturnsZeroByDefault`：默认 bootstrap 后 count = 0；总览 metrics 仍 5 个；不含「健康预警」。
  - `terminalHallOverviewAppendsAttentionChipWhenAnyAgentNeedsAttention`：注入 2 个员工 attention 状态后，count = 2、metrics 升至 6 个、新 chip kind = .danger、必须追加在末尾（不能挤前面 5 个固定 chip 顺序）。
  - `terminalHallOverviewAttentionDoesNotCountOkOrApiAgents`：所有员工注入 ready phase（OK 状态）后 count 仍 = 0；metrics 仍 5 个。
- **既有测试自动通过**（双轨保留生效）：轮 2 `terminalHallOverviewMetricsReturnsFiveOrderedChinesetMetricsWithKindMappedByValue` 断言「正好 5 个 metric」在默认 bootstrap 场景下仍成立（默认无 attention）。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 默认产品总览 chip 行**只有 5 个 chip**（无健康预警）；
  2. 手动触发 1 个员工进入 .busy 状态后，总览第 6 chip「健康预警 1」浮现，红色 danger；
  3. 触发第 2 个员工 .authBlocked 后，第 6 chip 升级为「健康预警 2」；
  4. 第 6 chip 出现/消失/数字变化时，前 5 个 chip 顺序与配色不被影响；
  5. 窄屏卡片（< 480pt）下 6 个 chip 是否换行（如果出现挤压可考虑给 chip 行加 `LazyHStack` 或 wrap layout）。

### 2026-05-02 终端大厅员工卡 CLI 健康状态徽章可视化

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：推进 codex 多 Agent 增强方案「**真实模型链路的生产级容错、审计和可视化**」长期项里的「可视化」部分。把 `CLIInteractionPhase` 的状态观察结果（可继续交互/等待回复/本轮结束/忙碌/授权异常/临时异常）做成员工卡顶部一个紧凑徽章 chip，让技术负责人不用展开「运行前预检」DisclosureGroup 就能默认看到员工健康状态。
- **问题诊断**：`CompanyStore.cliRecoveryAdvice(for:)` 已经有完整的恢复建议数据源（phase / action / hint / canManualRetry），但当前只在「员工恢复建议」长文本面板里使用；终端大厅员工卡顶部默认不展示这些信号。技术负责人想知道某个员工是否在忙碌 / 授权异常时，必须打开预检面板或维护抽屉。
- **核心设计：默认不显示徽章原则**：
  - 员工不是命令行后端 / 没有运行会话 / phase = `.unknown` / `.ready` / `.completedTurn` → 徽章 accessor 返回 nil，卡片不渲染。
  - 只有 4 种"需要技术负责人注意"的状态浮现徽章：
    - `.awaitingResponse` → info 蓝徽章「等待回复」
    - `.busy` → warning 黄徽章「忙碌中」
    - `.authenticationBlocked` → danger 红徽章「授权异常」
    - `.transientFailure` → danger 红徽章「临时异常」
  - 这一策略让默认场景下徽章不打扰；只有真出事时才浮现，符合「老板视角优先 + 员工像人不像接口」准则。
- **拆分双轨改造**（沿用同日轮 1/2/3 模式）：
  - `CompanyStore` 新增 `terminalAgentCardHealthBadge(for: UUID) -> TerminalAgentCardHealthBadge?` accessor 与公共 `TerminalAgentCardHealthBadge` 类型（含 `Severity` 枚举 `.info` / `.warning` / `.danger`、`title` / `detail` 字段）。
  - 既有 `cliRecoveryAdvice(for:)` / `cliRecoveryAdvicesForSelectedProduct()` / `cliRecoveryAdviceSummaryText()` 完全保留，「员工恢复建议」长文本面板继续使用（双轨）。
- **`TerminalAgentCard` 顶部第 1 行新增渲染分支**（`TerminalHallView.swift:511-532`）：
  - 在 `visibleBackendSummary` 之后、Spacer 之前条件渲染 `TerminalAgentCardHealthBadgeChip`（accessor 返回 nil 时根本不进入此分支）。
  - 新增 `TerminalAgentCardHealthBadgeChip` 私有 view 组件：10pt heavy mono 字、padding 6/2、Capsule 背景、按 severity 映射 `CompanyTheme.blue/.warning/.red` 颜色。
  - `.help(badge.detail ?? badge.title)` 提供 hover tooltip（含中文 action.title 与 operatorHint）。
  - `.accessibilityLabel("命令行健康状态：\(badge.title)")` —— **避免裸 `CLI` 字面量**（既有 `swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` 守门只允许 `Codex CLI` / `Claude Code CLI` / `Gemini CLI` 品牌组合）。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅员工卡 CLI 健康徽章可视化」MARK 段）：
  - `terminalAgentCardHealthBadgeReturnsNilForOkOrUnobservedStates`：bootstrap 后无 session → nil；强制注入 `.unknown` / `.ready` / `.completedTurn` → 仍 nil。
  - `terminalAgentCardHealthBadgeMapsAttentionStatesToCorrectSeverityAndChinese`：4 种 attention phase 必须映射到正确中文标题 + 正确严重度；标题 ≤ 4 字（保证卡顶第 1 行不挤压）。
  - `terminalAgentCardHealthBadgeOmitsBadgeForApiAndLocalBackends`：API 后端即便强行注入 `.busy` phase 也必须返回 nil（API 没有 CLI 长期会话，不应误显示）。
  - `terminalAgentCardViewRendersHealthBadgeChipWhenAccessorReturnsNonNil`：源码扫描 view 必须含 `store.terminalAgentCardHealthBadge(for: agent.id)` 调用 + `TerminalAgentCardHealthBadgeChip(badge:` 渲染 + 组件定义；DisclosureGroup 数量仍 ≤ 2（徽章必须默认可见，不允许折叠）。
- **不动的边界**：
  - `cliRecoveryAdvice` / `runtimeSessions` / `AgentRuntimeSession` 既有 API 与字段 100% 保留。
  - 不修改 `CLIInteractionStateMachine.observe` / `recoveryAction` 状态机逻辑。
  - 不引入新 `DisclosureGroup`；不改既有员工卡其它结构。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 默认产品 5 个员工卡顶部第 1 行**不应该**有任何徽章（所有员工 phase=.unknown / nil）；
  2. 在维护区手动触发一个员工进入 `.busy` 状态后，该卡片顶部第 1 行 backend chip 后面应该浮现一个黄色「忙碌中」短徽章；
  3. 鼠标悬浮徽章 hover 应显示中文 tooltip（含「等待当前任务」+ operatorHint）；
  4. `.authenticationBlocked` 状态下徽章为红色「授权异常」；`.transientFailure` 为红色「临时异常」；`.awaitingResponse` 为蓝色「等待回复」；
  5. 徽章不会挤压 backend chip（最窄 340pt 卡片下仍能看到 backend 摘要前几个字 + 徽章 + info icon）；
  6. 徽章变化时不应有视觉抖动（无显式动画，依赖 SwiftUI 默认过渡）。

### 2026-05-02 终端大厅员工卡终端日志区按状态自适应高度（不折叠）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：承接同日「员工卡顶部紧凑摘要」与「顶部概览结构化指标 chip」改造，把员工卡终端日志 ScrollView 的硬编码 `frame(height: 248)` 改为按运行状态自适应：员工"准备中"（不在运行 + `terminalLogs[id]` 为空）→ 80pt 紧凑高度 + 中文等待提示；运行中或有任何日志输出 → 180pt（比原 248pt 减少 27%）。
- **问题诊断**：默认产品 bootstrap 后 5 个员工，光"空终端"就吃掉 5 × 248 = 1240pt 垂直空间。员工还没被派任务时展示一个巨大空黑框，违背 5.3 节"员工像人不像接口"原则（没在干活的员工不应展示一个巨大空终端给用户暗示"在等输出"）。
- **关键边界**：这是「内容驱动的高度适配」，**不是** DisclosureGroup 折叠：高度变化由 SwiftUI `.animation(.easeOut(duration: 0.2))` 平滑过渡；占位文字、清空按钮、运行按钮等控件全部保留可见；不会触动 5-01「摘要工作台替代默认折叠」准则（无 `DisclosureGroup` 新增）。
- **拆分双轨改造**（沿用同日轮 1 / 轮 2 模式）：
  - `CompanyStore` 新增视觉层 accessor：
    - `terminalAgentCardLogHeight(for: UUID) -> CGFloat`：按 isIdle 返回 idle 80pt 或 active 180pt。
    - `terminalAgentCardLogPlaceholder(for: UUID) -> String`：idle 时返回「等待派发任务，运行后此处显示终端输出。」；非 idle 退回原 fallback「暂无终端输出。」。
    - `terminalAgentCardIsIdle(agentID: UUID) -> Bool`：判定 = `!isRunning && terminalLogs 原始空`。
    - `terminalAgentCardLogIdleHeight` / `terminalAgentCardLogActiveHeight` 两个 `public static let CGFloat` 常量（80 / 180），便于测试断言与 codex 后续调参。
  - `visibleTerminalLog(for:)` 函数 + 「暂无终端输出。」fallback 字符串保持不变（兼容既有 `visibleTerminalLogCollapsesConsecutiveDuplicateOPCSessionWarmupBlocks` / `visibleTerminalLogHidesLegacyCommandPathsAndRawFlags` 等多条守门）。
- **`TerminalAgentCard` ScrollView 新结构**（`TerminalHallView.swift` 614-636）：
  - `Text(...)` 内容按 isIdle 切换：idle → 占位文字（muted 灰）；其它 → 原 logText（ink）。
  - `.frame(height: store.terminalAgentCardLogHeight(for: agent.id))` 替换 `.frame(height: 248)`。
  - `.animation(.easeOut(duration: 0.2), value: store.terminalAgentCardIsIdle(agentID: agent.id))` 让高度变化平滑过渡，避免运行任务时卡片"跳一下"。
  - 清空按钮 `.disabled(logText == "暂无终端输出。")` 判定保持不变（idle 时 logText 仍是 fallback，原判定继续等价于"无内容")。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅员工卡终端日志区按状态自适应高度」MARK 段）：
  - `terminalAgentCardLogHeightShrinksWhenIdleAndExpandsWhenActive`：bootstrap 后 idle → idle 高度；注入日志 → active 高度；清空日志 → 重新 idle 高度；占位文字含「等待派发任务」/「运行后此处显示终端输出」。
  - `terminalAgentCardLogHeightConstantsAreReducedFromOriginal248`：active ≤ 200（比原 248 减 ≥ 19%）；idle * 2 ≤ active（明显紧凑差异）；active ≥ 120 给真实输出留空间；idle ≥ 60 给占位留空间。
  - `terminalAgentCardViewUsesAdaptiveLogHeightInsteadOfHardcoded248`：源码扫描必须用 3 个新 accessor + **不能**再含 `.frame(height: 248)` 字面量。
- **不动的边界**：
  - `visibleTerminalLog(for:)` 函数行为完全不变；多个既有终端日志守门测试 100% 保留绿。
  - 不引入新 `DisclosureGroup`（同日轮 1 测试已锁阈值 ≤ 2）。
  - 清空按钮、运行按钮、选中按钮、预检按钮全部保留；只是日志区高度变化。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 默认产品 5 个员工的终端日志区是否都是 80pt 紧凑高度（垂直滚动距离明显缩短）；
  2. 中文占位文字「等待派发任务，运行后此处显示终端输出。」是否清晰可读；
  3. 点击任意员工的「运行」按钮后，该卡片日志区是否平滑过渡（≈ 0.2s 动画）扩展到 180pt；
  4. 运行结束后日志保留时高度是否仍维持 180pt（不会缩回去），切换其它产品再切回是否仍保留运行状态判定；
  5. 整体卡片堆叠高度是否比改造前明显紧凑（5 个员工节省 5 × 168 = 840pt 垂直空间）。

### 2026-05-02 终端大厅顶部「运行状态」概览改为结构化指标 chip + next-step

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：承接同日「员工卡顶部紧凑摘要」与 5-01「摘要工作台替代默认折叠」准则，把终端大厅顶部 `TerminalHallOverviewSummary` 默认可见的 4 行纯文本概览重构为「标题 + 产品名 / 5 个 MetricChip / next-step 单行」3 行结构化布局，与下方 3 张 SummaryCard 信息架构对齐。
- **问题诊断**：原 `Text(store.terminalHallOverviewSummaryText())` 直接渲染 4 行 monospace 文本，存在以下缺陷：
  - 第 1 行「终端大厅运行状态：<产品名>」与卡头 `Text("终端大厅运行状态")` 重复；
  - 第 2 行 5 个指标用 `·` 拼接的纯文本，无颜色编码，与下方 SummaryCard 的 `MetricChip` 视觉风格割裂；
  - 第 4 行「提示：下方摘要工作台默认可见架构体检 / 通信网关 / 本地稳定性…」已经过时（5-01 SummaryCard 落地后用户可直接看到，无需文字提示）；
  - 视觉信息密度低，占用屏幕空间却无法快速扫描风险状态。
- **拆分双轨改造**（沿用同日员工卡同模式）：
  - `CompanyStore` 新增视觉层结构化 accessor：
    - `TerminalHallOverviewMetric` 类型（含 `Kind` 枚举 `.neutral` / `.ok` / `.warning` / `.danger`）；放在 `EmployeeDraft` 旁同文件 9311 行附近的轻量 helper 类型区。
    - `terminalHallOverviewMetrics() -> [TerminalHallOverviewMetric]`：返回固定顺序 5 个指标（团队 / 运行中 / 待审批 / 阻塞/失败 / 最近风险），kind 按值是否非零分桶（值=0 → neutral；值>0 按语义升档）。
    - `terminalHallOverviewNextStepText() -> String`：返回单行中文 next-step（优先级链路：待审批 > 阻塞/失败 > 最近风险 > 无运行 > 默认保持运行）。
  - `terminalHallOverviewSummaryText()` 4 行字符串**完全保留**，继续供聊天/复制/审计兜底使用，并仍由既有测试 `terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure` 守门「摘要工作台 / 查看详情」中文方向 token。
- **`TerminalHallOverviewSummary` view 新结构**（`TerminalHallView.swift` 104-152）：
  - 第 1 行 HStack：标题「终端大厅运行状态」（12pt heavy ink）+ 右对齐产品名（11pt medium muted，单行截断）。
  - 第 2 行 HStack：5 个 `MetricChip`（颜色按 kind 映射：neutral=blue / ok=green / warning=warning / danger=red）+ Spacer。
  - 第 3 行 Text：`terminalHallOverviewNextStepText()` 单行（10.5pt medium muted）。
  - `accessibilityElement(children: .contain)` 让容器组保留各 chip a11y 节点。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅顶部概览结构化指标」MARK 段）：
  - `terminalHallOverviewMetricsReturnsFiveOrderedChinesetMetricsWithKindMappedByValue`：5 个标题 / 顺序 / 全中文 / kind 按值是否非零分桶（值=0 一律 neutral，值>0 必须升档）；反向锁不允许 `backend` / `rawValue` / `Agent` / `CTO` 出现在 title。
  - `terminalHallOverviewNextStepTextReflectsHighestPriorityCondition`：必须以「下一步：」开头；默认空运行场景应落到「选择员工运行任务」分支；反向锁不允许底层参数 / 英文角色词。
  - `terminalHallOverviewSummaryViewUsesStructuredMetricsInsteadOfPlainTextBlock`：源码扫描必须含 `terminalHallOverviewMetrics()` / `terminalHallOverviewNextStepText()` 调用，**不能再含** `terminalHallOverviewSummaryText()` view 调用（该字符串只保留给聊天/复制/审计），且 `TerminalHallOverviewSummary` 区块内必须出现 `MetricChip(` 调用。
- **不动的边界**：
  - `terminalHallOverviewSummaryText()` 4 行字符串和 `terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure` 守门 100% 保留。
  - 不引入新 `DisclosureGroup` 默认折叠任何模块（同日员工卡守门已锁阈值 ≤ 2）。
  - 不修改 `selectedProductDeliveryArtifacts` / `selectedProductMaintenanceArtifacts` 等 accessor。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认。codex 回来后请用 Computer Use 复核：
  1. 概览顶部第 1 行「终端大厅运行状态」与右上角产品名是否一行显示；
  2. 第 2 行 5 个 chip 是否横排、颜色是否按指标语义（运行中 chip 为绿、阻塞/最近风险 chip 为红等）；
  3. 第 3 行 next-step 单行中文是否清晰可读；
  4. 概览整体高度比改造前是否略矮（4 行→3 行 + 行距压缩）；
  5. 与下方 3 张 SummaryCard 的 chip 视觉风格是否完全一致（同 `MetricChip` 组件）。

### 2026-05-02 终端大厅员工卡顶部紧凑摘要（不折叠、不隐藏）

> 本条 reviewer = codex 已复核（2026-05-05：测试基线 420/420，UI 行为项已 Computer Use 抽样复核）。

- **方向**：承接 5-01「摘要工作台替代默认折叠」准则与 codex 上一轮收尾留言（员工卡顶部「运行方式 / 任务注入 / 会话续跑」需在不折叠、不隐藏的前提下改清晰紧凑），重构终端大厅员工卡 `TerminalAgentCard` 顶部摘要区。
- **问题诊断**（codex 留下、本轮接管期复盘验证）：原顶部 4 行多行字符串 `commandPreview = visibleExecutionSummary` 直接渲染并被 `lineLimit(2)` 截断，导致：
  - 第 1 行「运行方式：…」与上方 `visibleBackendSummary` **完全重复**；
  - 第 2 行「任务注入：…」是**静态样板**，每张卡都一样；
    - 第 3 行「任务摘要」与第 4 行「长期会话」高频被截断，会话续跑状态几乎从不可见。
- **拆分双轨改造**（不破坏既有日志/预检/聊天链路）：
  - `CompanyStore` 新增 4 个**视觉层专用**紧凑 accessor，专给 `TerminalAgentCard` 用：
    - `terminalHallCardLongSessionLine(for:) -> String?`：「会话续跑：<品牌名> · <接续结论>」，固定 2 段；默认可见行不展示协议名、画像、监控或异常信号；后端无 CLI 交互画像（API / local）时返回 `nil`，卡片整行隐去。
    - `terminalHallCardLongSessionDetail(for:) -> String?`：「会话续跑详情：<品牌名> · <接续结论> · <产品层说明>」，给 `.help()` tooltip 与 a11y hint 用；默认可访问性详情同样不展示协议名、画像、监控或异常信号。
    - `terminalHallCardTaskDigestLine(prompt:) -> String`：「本轮任务：<前 60 字>…」；空 prompt 退化为「本轮任务：使用默认提示词。」；多行 prompt 压成单行。
    - `terminalHallCardInjectionHint() -> String`：静态文案「自动注入：角色档案 · 记忆 · 技能 · 产品工作区。」给 info icon tooltip 用。
  - `commandPreview` / `visibleExecutionSummary` 多行字符串**保持原样**，继续供运行前预检、终端日志、聊天会话日志（`appendAgentSession` / `terminalCommandSummary`）复用，避免冲击 7+ 条既有守门测试。
- **`TerminalAgentCard` 顶部新结构**（`TerminalHallView.swift` 503-545）：
  - 第 1 行：`visibleBackendSummary`（保留，等宽 11pt）+ 右侧 `info.circle` SF Symbol（`.help()` 显示注入说明 tooltip，`.accessibilityLabel("任务注入说明")`）。
  - 第 2 行：会话续跑摘要（等宽 10pt，muted；仅当 accessor 非 nil 时渲染；`lineLimit(1)` + `truncationMode(.tail)`；`.help()` 给产品层详情）。
  - 第 3 行：本轮任务摘要（系统字体 10.5pt，italic muted；`lineLimit(2)`，但内容已在 store 端截到 60 字 + 省略号，正常情况下单行就够）。
  - 旧的 `lineLimit(2)` 多行截断块**整体删除**；卡片顶部不再调用 `store.commandPreview(`。
- **测试守门**（`OPCCompanyCoreTests.swift` 末尾「终端大厅员工卡顶部紧凑摘要」MARK 段）：
  - `terminalHallCardLongSessionLineCompactsProtocolSummaryButHidesDetails`：会话续跑摘要必须是「品牌名 + 接续结论」2 段、含品牌名（Codex / Claude / Gemini 任一）、默认行和 Help 详情都不含「长期会话 / 执行协议 / 协议 / 画像 / 监控 / 授权异常 / 临时异常」和 `model_reasoning_effort` / `--skip-git-repo-check` / `rawValue` / `backendSignature`；Help 详情仍保持中文并补充产品层接续说明。
  - `terminalHallCardLongSessionLineIsNilForBackendsWithoutInteractionProfile`：API / local 后端 accessor 必须返回 nil，卡片不渲染空字符串行。
  - `terminalHallCardTaskDigestLineHandlesEmptyShortAndLongPrompts`：空 prompt → 默认文案；短 prompt → 原样；多行 → 压成单行；70 字中文 → 截到 60 字 + 「…」（共 61 grapheme）。
  - `terminalHallCardInjectionHintMentionsAllInjectionDimensions`：tooltip 必须含「自动注入 / 角色档案 / 记忆 / 技能 / 产品工作区」全部 5 个关键词；不含 `CTO` / `Agent 编队` 等禁词。
  - `terminalHallAgentCardTopUsesCompactAccessorsInsteadOfTruncatedCommandPreview`：源码扫描 `TerminalHallView.swift` 必须含 5 个新 accessor 调用（`visibleBackendSummary` 保留 + 4 个新 `terminalHallCard*`），且**必须不再含** `store.commandPreview(`，并阻止新增第 3 处 `DisclosureGroup`（防止结构被偷偷折叠）。
- **不动的边界**（继承 codex SOP）：
  - 不修改 `terminalLogs` 原始存储；可见层减噪与卡片渲染完全解耦。
  - 不进入老板/交付视图过滤逻辑；本改动只影响终端大厅员工卡视觉层，不改变 `selectedProductDeliveryArtifacts` / `selectedProductMaintenanceArtifacts` 任何 accessor。
  - 不引入新的可见英文角色词或后端参数文案；`info.circle` SF Symbol 名不在 `swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` 扫描范围内（该测试只覆盖 Text/Label/Button/Toggle/Picker/Section 等字符串字面量与 `.help()`/`.accessibilityLabel/Hint`，已为新增中文 helper 文本就位）。
- **降级声明**：本轮无 codex Computer Use 真机视觉确认，亦无 CCB `[CODE REVIEW REQUEST]` 双模型互审。所有验证依赖 `swift test --no-parallel` 全量通过 + `scripts/build_app_bundle.sh` 重建可启动 bundle。codex 回来后请用 Computer Use 复核以下控件：
  1. 员工卡顶部第 1 行 backend chip + 右上角 info icon hover 是否显示完整中文 tooltip。
  2. 第 2 行「会话续跑：Codex · 可按产品接续」是否展示且不被截断。
  3. 第 3 行「本轮任务：…」斜体 muted 风格是否符合产品调性。
  4. 当 prompt 为空时第 3 行是否回退为「本轮任务：使用默认提示词。」。
  5. API / 本地后端员工卡是否正确隐去第 2 行（无会话续跑能力）。

### 2026-05-01 终端大厅默认信息架构修正：摘要工作台（替代默认折叠）

- **方向修正**：上一轮把架构体检 / 通信网关 / 本地稳定性三大模块默认包进 `DisclosureGroup` 折叠隐藏的方案是**开发视角的减噪**，不符合产品级运维工作台体验。本轮统一回退该方向：终端大厅默认即「**摘要化工作台**」，模块入口与状态默认可见，长报告 / 完整配置面板按需通过二级 sheet 详情打开，不再用「默认折叠」隐藏功能入口。
- 新增三张默认可见摘要卡片，每张统一信息架构（标题 + 状态 capsule + 2-3 个核心指标 chip + 1 行最近摘要 + 主要操作按钮 + 「查看详情」）：
  - `OPCAdvancedMaintenanceArchitectureSummaryCard` — 多员工架构体检与闭环：完成度 + 已闭合 / 待加强 / 未闭合 / 检查项分布 + 最近闭环目标摘要 + [运行体检] [闭环演练] [查看详情]。
  - `OPCAdvancedMaintenanceGatewaySummaryCard` — 通信网关与手机指令：通道总数 / 启用 / 可入站 / 通信日志计数 + 最近通信方向与标题 + [生成手机汇报] [测试通道] [查看详情]。
  - `OPCAdvancedMaintenanceLocalSummaryCard` — 本地稳定性与命令行运维：维护审计 N/100 + 维护产物 N/500 + 阈值压力提示 + 最近维护标题 + [运行隔离体检] [命令行预检] [查看详情]。
- 新增 3 个详情触发 anchor：`OPCAdvancedMaintenanceArchitectureDetailTrigger` / `...GatewayDetailTrigger` / `...LocalDetailTrigger`。点击对应「查看详情」按钮，通过 `.sheet(item:)` 打开二级面板渲染完整 `MultiAgentArchitectureAuditCenter` / `CommunicationGatewayCommandCenter` / `LocalMaintenanceCenter`，所有原有功能、按钮、a11y 锚点全部保留在二级面板内（含维护审计中心、维护产物档案、运行证据分类巡检、维护数据增长巡检、真实终端自动循环等深层入口）。
- 删除旧的 3 个 `Disclosure` enum case 与 3 个 `@State Bool = false` 默认折叠状态（`showsArchitectureAudit` / `showsCommunicationGateway` / `showsLocalMaintenance`），重命名为 `SummaryCard` 系列；`runbookKeyPaths` 双向锁同步替换。
- `terminalHallOverviewSummaryText()` 文案修正：删除「高级维护...默认收起」/「点击下方『高级维护』区域展开。」等折叠时代措辞，改为「下方摘要工作台默认可见架构体检 / 通信网关 / 本地稳定性的状态、核心指标与主要操作；点击「查看详情」按需打开完整面板。」。
- 测试改写：
  - `terminalHallOverviewSummaryStaysChineseAndKeepsAdvancedMaintenanceCollapsed` → `terminalHallOverviewSummaryReflectsSummaryWorkbenchInsteadOfCollapsedDisclosure`，锁定提示中包含「摘要工作台」/「查看详情」，反向禁止「默认收起」/「折叠」/「展开」等旧方向 token。
  - `terminalHallViewKeepsAdvancedMaintenanceBlocksInsideDisclosureGroupsByDefault` → `terminalHallShowsSummaryWorkbenchInsteadOfCollapsedDisclosure`，从源码层面双向断言：(1) 旧的 3 个折叠 `@State` 名字与 3 个 `Disclosure` enum case 必须删除；(2) 3 张摘要卡片结构、6 个新 enum case、3 处「查看详情」按钮、`.sheet(item: $presentedDetail)` 路由必须存在；(3) 主视图 ScrollView 不再内联渲染完整 `MultiAgentArchitectureAuditCenter` / `CommunicationGatewayCommandCenter` / `LocalMaintenanceCenter`，这些只能在二级 `TerminalHallDetailSheet` 内部渲染。
- `RUNBOOK.md` 同步更新「终端大厅维护区关键控件」清单：移除 3 条 disclosure 条目，改为 3 张摘要卡片 + 3 个详情触发按钮，并把「先点 disclosure 展开」描述改为「先点对应卡片『查看详情』打开二级 sheet 面板」。

### 2026-05-01 持久化目录测试隔离（不污染真实 App 状态）

- `CompanyPersistence` 新增 `resolveSupportDirectory(environment:temporaryDirectory:processIdentifier:processName:bundlePath:arguments:)`：按优先级解析持久化根目录——(1) 环境变量 `OPC_COMPANY_SUPPORT_DIR` 显式覆盖；(2) 检测到 XCTest / swift-testing / SwiftPM `swift test` 进程 → `<TemporaryDirectory>/OPCCompanyTests-<pid>`；(3) 真实运行 → `~/Library/Application Support/OPCCompany`。结果由 `static let resolvedSupportDirectory` 一次性缓存到进程级。
- 测试进程检测信号（`isLikelyTestProcess`）综合：env（`XCTestConfigurationFilePath` / `XCTestSessionIdentifier` / `XCTEST_HOST_BUNDLE_PATH`）、processName（`xctest` / `PackageTests` / `swift-testing` / `swiftpm-testing-helper` / `testing-helper`）、bundlePath（`.xctest` 结尾或包含 `.xctest/`）、arguments（含 `.xctest` 路径或 `--testing-library`）。任一命中即视为测试进程。这层冗余保证 Xcode XCTest（注入 env）和命令行 `swift test`（不注入 env，但进程名是 `swiftpm-testing-helper`，arguments 含 `.xctest`）都能被识别。
- `stateURL` / `historyIndexURL` / `agentWorkspacesURL` / 安全检查点目录全部继承 `supportDirectory`，自动随测试隔离。
- 新增三条测试：
  - `companyPersistenceSupportDirectoryRedirectsAwayFromRealApplicationSupportInTestProcess`：当前 `swift test` 进程的 `supportDirectory` 必须不等于真实 `~/Library/Application Support/OPCCompany`，必须落在 `OPCCompanyTests-<pid>` 临时目录。
  - `companyPersistenceBootstrapDoesNotWriteToRealApplicationSupport`：触发 `CompanyStore.bootstrap` + `saveSnapshot`，断言 `company-state.json` 写到隔离目录、真实 Application Support state 修改时间不变。
  - `companyPersistenceResolveSupportDirectoryHonorsEnvironmentAndXCTestDetection`：用 helper 注入参数验证 4 类决策分支（env 覆盖 / Xcode XCTest / SwiftPM swift-testing / 进程名 / arguments / 真实运行 / 空覆盖回退）。
- **测试运行边界**：测试运行必须使用隔离持久化目录，不得污染真实 App 状态。CI / 自定义沙盒可通过 `OPC_COMPANY_SUPPORT_DIR=/path` 显式指定根目录。当前已被测试污染的本地真实状态文件（如出现）需用户确认后人工清理；产品代码不主动删除真实状态。

### 2026-05-01 终端大厅默认信息密度收敛 + 高级维护折叠区（**历史方案，已被上方「摘要工作台」方向取代**）

> **已被取代**：该条目记录的「3 大维护模块默认包进 `DisclosureGroup` 折叠隐藏」是开发视角减噪方案，**不**再代表当前产品方向。当前方向见上方 `2026-05-01 终端大厅默认信息架构修正：摘要工作台（替代默认折叠）` 条目——3 张摘要卡片默认可见、长报告通过 `.sheet(item:)` 二级面板按需打开。本条目保留作为历史决策追溯，不要再据此实施任何修改；任何复活默认折叠的 PR 会被 `terminalHallShowsSummaryWorkbenchInsteadOfCollapsedDisclosure` 测试当场拦截。

- 终端大厅顶部新增「**终端大厅运行状态**」简洁概览卡片（`OPCTerminalHallOverviewSummary`）：默认可见，含团队/运行中/待审批/阻塞/最近风险计数 + 中文下一步建议；不暴露 backend / CLI / identifier 等内部字段。
- 把开发/验证期长期默认展开的 3 大维护块全部包进 `DisclosureGroup`，**默认收起**：
  - `OPCAdvancedMaintenanceArchitectureDisclosure` — 多员工架构体检与闭环
  - `OPCAdvancedMaintenanceGatewayDisclosure` — 通信网关与手机指令
  - `OPCAdvancedMaintenanceLocalDisclosure` — 本地稳定性与命令行运维（包含维护审计中心、维护产物档案、运行证据分类巡检、维护数据增长巡检、真实终端自动循环等技术负责人专用入口）
- 「终端大厅维护细节属于技术负责人高级区」是产品边界：默认主屏只展示运行状态、员工终端卡片、3 个折叠入口；维护功能全部保留（不删除任何按钮/数据源/a11y identifier），点击 disclosure 展开后即可使用。
- `RUNBOOK.md` Computer Use 路径同步：维护类 anchor（`OPCMaintenanceAuditCenter` / `OPCMaintenanceArtifactCenter` / `OPCEvidenceClassificationAudit*` / `OPCMaintenanceDataPressure*` / `OPCTerminalAutoInteractionLoopPanel` 等）必须先点击 `OPCAdvancedMaintenanceLocalDisclosure` 展开后再下钻。
- 新增 4 个 `OPCUIAutomationIdentifier` case 同步登记到 `runbookKeyPaths` 双向锁；新增测试 `terminalHallOverviewSummaryStaysChineseAndKeepsAdvancedMaintenanceCollapsed`（概览简洁中文、行数 ≤ 6、不含内部词）+ `terminalHallViewKeepsAdvancedMaintenanceBlocksInsideDisclosureGroupsByDefault`（源码守门：3 个 `@State` 默认 false、3 个中文 disclosure label 存在、3 个原维护块仍存在，未删除任何功能）。
- 终端大厅可见概览文案使用纯中文产品话术（如「点击下方『高级维护』区域展开。」），不出现 `DisclosureGroup` / `VStack` / `HStack` / `ScrollView` / `ForEach` / `LazyVGrid` 等 SwiftUI 开发组件名；测试 `terminalHallOverviewSummaryStaysChineseAndKeepsAdvancedMaintenanceCollapsed` 加入相应禁词断言锁住边界。

### 2026-05-01 superset accessor 直读源码守门

- 新增测试 `unfilteredEvidenceAccessorsAreNotReadOutsideCompanyStore`：扫描 `Sources/OPCCompanyCore/*.swift`（除 `CompanyStore.swift` 自身定义入口），禁止任何 UI 或 helper 文件直接读取未过滤的 `selectedProductArtifacts` / `selectedProductVerifications` / `selectedProductRecentArtifacts` / `selectedProductRecentVerifications`。
- 老板/交付侧 view 必须使用 `selectedProductDeliveryArtifacts` / `selectedProductDeliveryVerifications` / `Recent...Delivery...`；技术维护侧 view 必须使用 `selectedProductMaintenanceArtifacts` / `selectedProductMaintenanceVerifications` / `Recent...Maintenance...`。
- 守门用 word boundary 判断：`selectedProductDeliveryArtifacts` / `selectedProductMaintenanceArtifacts` 等合法 accessor 后跟字母数字会被跳过，不误报。
- 当前扫描结果零泄漏；本守门把当前合规状态固化为编译期 + swift test 双重锁，未来 PR 一加 superset 直读会立刻在测试里失败并给出文件:行号:代码片段。

### 2026-05-01 SwiftUI inline 文案扫描覆盖 7 类 API + fuzzy 内部词

- `swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords` 扩展扫描入口：从 `Text` / `Label` 扩展到 `Button` / `Toggle` / `Picker` / `SectionHeader(title:)` / `.navigationTitle` / `.help` / `.accessibilityLabel` / `.accessibilityHint`，覆盖 SwiftUI 默认可见文案的 7 类 API。
- 禁词列表分两层：(a) 精确禁词（`AI 控制` / `Agent 编队` / `COMMAND LINK` / `CTO 办公室` / 内部 enum / CLI 参数 / `OPCUIAutomationIdentifier` / `OPCTerminalAutoLoop` / `OPCEvidenceClassification` 等 a11y identifier 前缀）；(b) fuzzy 禁词（裸 `backend` / `identifier` / `a11y` / `CLI`），其中 `Codex CLI` / `Claude Code CLI` / `Gemini CLI` 品牌组合白名单放行。
- 扫描器加 `\(...)` 字符串插值剥离预处理：`Text("工具 \(opcBackendCommandDisplayName(agent.backend.command))")` 这类 Swift 插值代码段不会被误报为含 `backend`——用户可见的是清洗后函数返回值，而不是字面量里的属性名。
- sanity check 升级：覆盖更多 API 后字面量数从原 50 提到 100；同时强制至少抓到 1 条 `SectionHeader(title:)` 字面量；保留品牌名（Codex/Claude Code/Gemini/OpenAI）反向锁。
- 当前扫描结果：本次扩展扫描清零，无任何泄漏；既有 SwiftUI inline 文案在新覆盖面下仍合规。

### 2026-05-01 维护证据隔离守门 + SwiftUI inline 文案扫描

- 新增测试 `maintenanceEvidenceIsolatedFromAllBossAndDeliveryDataSources`：把 5 类典型维护证据一次性插入产品（VR：`运行证据分类巡检` / `维护数据增长巡检`；AR 前缀：`本地文件索引：` / `命令行作业档案：` / `闭环审计报告：`），断言它们都**不**进入 4 个老板/交付数据 accessor（`selectedProductDeliveryVerifications` / `selectedProductRecentDeliveryVerifications` / `selectedProductDeliveryArtifacts` / `selectedProductRecentDeliveryArtifacts`），覆盖老板首页 widget、产品详情交付 metric tile、产品详情交付摘要 prefix(3)、交付验收中心 prefix(20)、运营套件验收抽屉 prefix(6) 五个 UI surface；同时锁定维护中心 accessor 与 prefix(8) 切片可见。
- 新增测试 `swiftUIInlineCopyDoesNotContainLegacyEnglishRoleWords`：扫描 `Sources/OPCCompanyCore/*.swift` 里所有 `Text("...")` / `Label("...", ...)` 字面量，强制 SwiftUI inline 文案不含 `AI 控制` / `Agent 编队` / `COMMAND LINK` / `CTO 办公室` / `OPC AI` / `AI 通信` / `AI 智能` / `Codex CTO` / `rawValue` / `subscriptionCLI` / `persistentProtocol` / `model_reasoning_effort` / `--skip-git-repo-check` / `--no-stream` / `--dangerously-allow` 等旧词或 CLI 参数；同时正向 sanity 检查至少一处保留 Codex / Claude Code / Gemini / OpenAI 品牌词。任何泄漏都会让 swift test 失败并显式列出文件、词汇、字面量。
- 这两条守门和既有 `defaultVisibleTextHidesRawCommandFlagsAndEnglishRoleWords` / `defaultVisibleInterfaceCopyUsesChineseRoleTermsAndKeepsBrandsAvailable` / `maintenanceCenterCopyKeepsChineseAndAvoidsLegacyEnglishRoleWords` 形成多层文案/数据隔离防御：默认可见集合 + 维护中心 store 文本 + SwiftUI inline 字面量 + 老板/交付 5 个 surface 数据源——每一层都有失败信息直接给开发者修复线索。

### 2026-05-01 运行证据分类巡检覆盖半角冒号边界

- `selectedProductUnclassifiedArtifactRecords` 扩展边界：除了原有「全角「：」结构化前缀」识别，新增「半角「: 」（冒号 + 空格）+ 前缀不含 `/` `\` 路径标记」识别——保守接受真实的英文/中英文混合标签（如 `未登记类别: 示例` / `version: 1.2.0`）。
- 严格保留动态证据安全：URL（`https://...` / `opc://...`，无空格）、Windows / Unix 路径（`/var/log/...` / `C:\\...`）、时间戳（`2026-05-01T10:30:00` / `10:30:00`，冒号后无空格）、普通动态文件名（`data.csv` / `client_brief.md` / `AGENTS.md`）一律不报告。`/usr/bin/foo: bar` 这类含 `: ` 但前缀已有 `/` 路径标记的极端边界也按动态证据保留。
- `evidenceClassificationAuditText()` 在告警段加一行中文识别规则说明：`标题含全角「：」或半角「: 」（冒号 + 空格，前缀不含 / \ 路径标记）视为结构化前缀；URL、文件路径、时间戳和普通动态文件名不会被巡检报告。`
- 测试 `evidenceClassificationAuditCoversHalfWidthColonButSparesPathsAndTimestamps` 锁定：5 条半角结构化标题被报告、11 条动态/路径/URL/时间戳标题不被报告、维护和交付分类好的样例不被报告、巡检自身只进维护视图、巡检不删除任何数据。

### 2026-05-01 Claude Code busy 测试夹具 + busy 不打断正常任务

- 新增 `cliInteractionStateMachineRecognizesClaudeCodeBusyVariantsAndRecoveryWaits` 锁定 Claude Code 协议画像识别 4 条英文 busy 样例（`busy` / `overloaded` / `rate limit` / `already running`）+ 5 条中文 busy 样例（`服务繁忙` / `已在运行` / `过载` / `速率限制` / `请稍后重试`）；同时锁定 5 条非诊断行（普通中文提示词 / 路径 / 代码片段 / 文档名）不会被误判。
- 锁定 `recoveryAction(for: .busy) == .waitForCurrentTask`，标题「等待当前任务」，操作建议「上一轮任务尚未结束，请等待完成后再发起新任务。」——这是 OPC 产品边界：busy 状态由 OPC 让用户等待当前任务自然完成，不自动重开、不允许手动重试入口触发。
- 新增 `cliRecoveryManualRetryRefusesBusyAndDoesNotInterruptRunningTasks` 端到端验证：员工处于 busy 状态、正在运行任务时，调用 `manualRetryTransientForAgent` 会被中文拒绝（不在「临时异常」范围内），`runningAgentIDs` 与会话 phase 保持不变——确保受控手动重试入口不会误把正常忙任务打断。

### 2026-05-01 维护数据增长巡检（不删除/不裁剪）

- `CompanyStore` 新增 `maintenanceDataPressureText()` 中文预览与 `runMaintenanceDataPressureAuditForSelectedProduct()` 巡检入口；阈值常量 `maintenanceVerificationGrowthAdvisoryThreshold = 100` / `maintenanceArtifactGrowthAdvisoryThreshold = 500`。
- 巡检结果状态：维护类 VR/AR 任一达到或超过阈值 → 「有警告」；否则「通过」。预览同时给出最近维护记录/产物时间戳和"不删除任何数据、不裁剪主快照"说明，并在超阈值时建议运行历史索引/归档（仍按归档 RFC 走旁路）。
- 新标题「维护数据增长巡检」加入 `technicalMaintenanceVerificationTitles`：巡检结果只进维护审计中心，老板/交付视图过滤。
- 终端大厅维护区在「运行证据分类巡检」之后加「运行维护数据增长巡检」按钮 + 中文预览卡片，附 a11y identifier `OPCMaintenanceDataPressureAuditButton` / `OPCMaintenanceDataPressurePreview`。
- 测试 `maintenanceDataPressureAuditEmptyStateIsChineseAndPasses` / `maintenanceDataPressureAuditFlagsWarningWhenAboveThreshold` / `maintenanceDataPressureAuditFlagsWarningWhenArtifactsAboveThreshold` 锁定空态、VR 阈值、AR 阈值三种场景；同时验证巡检不删除已有维护数据、不进交付视图。

### 2026-05-01 运行证据分类巡检

- `CompanyStore` 新增 `selectedProductUnclassifiedVerificationRecords` / `selectedProductUnclassifiedArtifactRecords` accessor 与 `evidenceClassificationAuditText()` / `runEvidenceClassificationAuditForSelectedProduct()` 巡检入口。
- VR 未分类规则：标题既不在 `technicalMaintenanceVerificationTitles`、也不在 `deliveryVerificationTitleExactMatches`/`Prefixes`。AR 未分类规则更保守：仅当标题含 `：`（全角冒号，结构化前缀标志）且不命中维护或交付的精确/前缀清单时才报告——动态文件名（`AGENTS.md`/`client_brief.md` 等）继续按默认交付通过，避免误伤真实交付证据。
- 新标题「运行证据分类巡检」加入 `technicalMaintenanceVerificationTitles`：巡检结果（无未分类时状态「通过」，有未分类时状态「有警告」）只进维护审计中心；老板/交付视图过滤；不删除/不修改任何已有证据，不写老板聊天/员工协作消息/作业档案。
- 终端大厅维护区在「命令行作业幽灵巡检」之后加入「运行证据分类巡检」按钮 + 中文预览卡片，附 accessibility identifier `OPCEvidenceClassificationAuditButton` / `OPCEvidenceClassificationAuditPreview`。

### 2026-05-01 本地文件索引产物归类为维护

- `scanLinkedLocalFiles()` 创建的 `ArtifactRecord` 标题改为 `本地文件索引：<文件名>`，自动命中 `technicalMaintenanceArtifactTitlePrefixes` 维护分类。
- 这些索引产物现在只出现在终端大厅维护区的「维护产物档案」中心；老板总控台「最近交付与验收」widget、产品详情交付物 metric tile + 交付摘要、交付验收中心交付物 prefix(20)、运营套件「自动化引擎」产物记录都通过 `selectedProductDeliveryArtifacts` 自动过滤掉。
- 真实交付（验收产物 / 验收报告 / 售前方案 / 项目扫描发现的规则与文档）继续可见。
- 测试 `scanLinkedLocalFilesRoutesArtifactsToMaintenanceAndKeepsDeliveryClean` 端到端验证：临时目录下创建 4 个真实文件、运行 `scanLinkedLocalFiles`，断言扫描产物全部进维护视图，老板/交付视图与既有验收产物保留不变。
- 旧售前方案工厂入口已在后续死代码清理中移除；本地文件索引的维护/交付隔离规则仍保留，后续任何交付生成能力都必须继续通过 `selectedProductDeliveryArtifacts` 与维护侧索引隔离。

### 2026-05-01 维护产物与交付产物边界 + 维护产物档案中心

- `ArtifactRecord` 增加产物分类二选一登记：`technicalMaintenanceArtifactTitleExactMatches`（精确：`安全检查点`）+ `technicalMaintenanceArtifactTitlePrefixes`（前缀：`闭环审计报告：` / `命令行作业档案：` / `本地文件索引：`）；`deliveryArtifactTitleExactMatches` 当前为空，真实交付字面量通过 `deliveryArtifactTitlePrefixes`（前缀：`验收产物：` / `验收报告：`）登记。动态文件名（项目扫描候选 / 本地文件索引文件名）默认按交付接受。
- 新增 `selectedProductDeliveryArtifacts` / `selectedProductRecentDeliveryArtifacts` 与 `selectedProductMaintenanceArtifacts` / `selectedProductRecentMaintenanceArtifacts`。
- 老板/交付视图（老板总控台「最近交付与验收」widget、产品详情交付物 metric tile + 交付摘要 prefix(3)、交付验收中心交付物 prefix(20)、运营套件验收抽屉 / 多员工架构体检"交付证据库"项）**全部**改用 delivery accessor，运维产物（安全检查点 / 命令行作业档案 / 闭环审计报告 / 本地文件索引）不再泄漏到老板视图。
- 终端大厅维护区在「技术维护审计中心」之下新增「维护产物档案」区块，使用 `selectedProductRecentMaintenanceArtifacts`，同时给 Computer Use 暴露 `OPCMaintenanceArtifactCenter` / `OPCMaintenanceArtifactRow` accessibility identifier。
- 测试 `technicalMaintenanceArtifactsAreHiddenFromBossAndDeliveryViews` 锁定老板/交付视图与维护视图边界；`artifactRecordTitleLiteralsAreClassifiedInCompanyStore` 源码扫描守门强制每条 `ArtifactRecord` 字面量 title 显式分类（用负向 lookahead 阻断跨越其他 record/event 构造器的误抓）。

### 2026-05-01 终端大厅维护区可访问性 + Computer Use 验证路径

- 真实终端自动交互循环面板和技术维护审计中心区块加上稳定的 SwiftUI accessibility identifier / label / hint：`OPCTerminalAutoInteractionLoopPanel`、`OPCTerminalAutoLoopTaskContextField`、`OPCTerminalAutoLoopMaxTurnsStepper`、`OPCTerminalAutoLoopStartButton`、`OPCTerminalAutoLoopReportSummary`、`OPCMaintenanceAuditCenter`、`OPCMaintenanceAuditRow`，零视觉副作用，便于 Computer Use 自动化在 a11y tree 上定位。
- 验证路径写入 `docs/RUNBOOK.md`：UI 验证只在 MacBook 内置屏执行，外接显示器**不作为目标屏**（SwiftUI a11y tree 与 SF Symbol 渲染密度会随外接屏 DPI 漂移）。
- 测试 `realTerminalAutoLoopRejectionRoutesAuditToMaintenanceOnlyAndKeepsBossViewsEmpty` 锁定数据 accessor 等价边界：preflight 拒绝后老板总控台 widget / 产品详情交付区 / 交付验收中心 / 运营套件验收抽屉的数据切片均不含审计；技术维护审计中心 prefix(8)、`selectedProductLatestTerminalAutoLoopReadinessAudit`、架构体检摘要均能查到中文「有警告」记录。

### 2026-05-01 中文诊断短语识别 + 真实终端自动循环停止审计

- `CLIInteractionProfile` 的 `authenticationIssueSignals` / `busySignals` / `transientIssueSignals` 在 codex / claude / gemini 三个画像里加上中文诊断短语：未授权 / 请登录 / 请重新登录 / 授权失败 / 授权异常 / 登录失败、服务繁忙 / 已忙碌 / 已在运行 / 速率限制 / 配额已用尽 / 请稍后重试（claude 还包含 `过载`）、请求超时 / 连接超时 / 网络异常 / 网络错误 / 连接失败 / 临时不可用。
- `diagnosticPrefixes` 同步加上中文行首前缀（错误：/ 致命：/ 警告：/ 异常：/ 严重错误：/ 未授权 / 请登录 等），保持"诊断行必须以前缀开头"的现有守门；普通中文用户提示词回显（不以诊断前缀开头）仍然不会被命中。
- 中文短语命中走"substring 命中 + 前后字符不能是 `/\\-_.` 路径标记"二段判定（`linePhraseHitAvoidingPathContext`）：彩色路径 `/var/log/临时异常.log` / `/etc/codex/未授权.json` / `/opt/codex/服务繁忙-fixture.txt` 仍不会被误判；ASCII 单词 / 多词原有匹配规则保持不变，避免回退。
- `runTerminalAutoInteractionLoopForSelectedAgent` 真实终端路径下，循环结束时如果 stopReason ∈ {授权异常 / 命令行仍在忙碌 / 临时异常 / 等待超时}，会同步写一条结构化 `VerificationRecord("真实终端自动循环停止审计")`（状态「有警告」），并向员工终端日志追加 `[OPC 自动循环停止审计]` 区块；正文使用中文 stopReason.title + operatorHint，不暴露 `rawValue` / 内部 enum 名 / 后端签名。
- 新增标题 `真实终端自动循环停止审计` 同步登记到 `technicalMaintenanceVerificationTitles` 集合：源码扫描守门测试、维护审计中心 accessor、老板/交付视图过滤都自动获得新条目；技术负责人维护视图通过 `selectedProductLatestTerminalAutoLoopStopAudit` 直接读取，老板总控台、产品详情交付区、交付验收中心均不展示。

### 2026-05-01 技术维护审计中心接入终端大厅维护区

- 终端大厅维护区（`LocalMaintenanceCenter`）右侧预览栏新增「技术维护审计中心」区块：聚合当前产品所有运维巡检/恢复/审计/真实终端工作区类 `VerificationRecord`，按时间倒序展示标题、状态、详情摘要。
- `CompanyStore` 新增 `selectedProductMaintenanceVerifications` 与 `selectedProductRecentMaintenanceVerifications` accessor，复用既有 `isTechnicalMaintenanceVerification` 分类，不复制判断逻辑。
- 维护记录归属边界：技术维护审计中心**仅在**技术负责人维护视图展示；老板总控台、产品详情交付区、交付验收中心、运营套件验收抽屉继续通过 `selectedProductDeliveryVerifications` / `selectedProductRecentDeliveryVerifications` 的 allow-list 过滤掉所有维护记录，只展示真实交付/验收证据。
- 区块文案使用中文产品话术；维护记录的 `rawValue` / 内部 enum 名 / 后端签名 / 完整命令参数继续不展示。

### 2026-05-01 真实终端自动循环就绪审计接入产品级验证记录

- 真实终端自动交互循环 preflight 现在除了写终端日志 `[OPC 自动循环就绪审计]` 和报告 `summaryText`，还会同步写一条结构化 `VerificationRecord("真实终端自动循环就绪审计")` 到当前产品：preflight 通过时状态为「通过」，preflight 拒绝时状态为「有警告」。
- 验证记录正文使用中文产品话术：包含「员工：<显示名>（<角色中文>）」、`就绪校验：…`、必要时附加`拒绝说明：…`，并明确标注「不进入老板总控台或交付验收中心、不创建命令行作业档案、不写老板聊天」；正文不含 `rawValue` / `subscriptionCLI` / `persistentProtocol` / `--skip-git-repo-check` / `model_reasoning_effort` / `opcGenerated` / 内部 enum 名 / ANSI 序列。
- `multiAgentArchitectureAuditText()` 末尾新增「最近真实终端自动循环就绪审计：<状态> · <就绪校验摘要>」一行；`CompanyStore.selectedProductLatestTerminalAutoLoopReadinessAudit` 与 `selectedProductTerminalAutoLoopReadinessAuditSummary()` 暴露给技术负责人维护视图。
- 老板总控台与交付验收中心会过滤该维护记录，不展示标题、详情或计数；详细 detail、`[OPC 自动循环就绪审计]` 终端日志和架构体检摘要都属于技术负责人/终端大厅可见区域。
- 老板/交付视图统一读取 `selectedProductDeliveryVerifications` / `selectedProductRecentDeliveryVerifications`：真实终端工作区、终端日志刷新、持久终端巡检、命令行链路预检、产品隔离体检、运行会话巡检、异常恢复、历史索引/归档、安全检查点等技术维护记录会被过滤；老板验收通过、自动验收检查、产物扫描等真实交付证据仍保留。

### 2026-05-01 命令行诊断信号识别 ANSI / 控制符容错

- 授权异常、忙碌、临时异常三类诊断信号判定（`CLIInteractionProfile.containsAuthenticationIssue` / `containsBusySignal` / `containsTransientIssue`）现在共用 `normalizedForPromptMatching(_:)`：在 `isDiagnosticLine` 前缀闸 + `lineContainsAnyDiagnosticSignal` 单词闸之前先剥离 ANSI / OSC、模拟 CR / BS 光标，让真实终端里被颜色或 spinner 包裹的 `error: not authenticated` / `warning: rate limit` / `fatal: ... busy` / `error: 429` / `error: network timeout` 仍能被识别。
- 守门未放松：诊断行必须以 `error:` / `warning:` / `not authenticated` / `please login` / `rate limit` 等列入清单的前缀开头；单词信号（`timeout` / `network` / `429` / `busy` 等）必须按 token 整词匹配且 token 不能含 `/\-_.` 等路径/标识符标记。彩色路径 `\u{1B}[36m/var/log/timeout-429-busy.log\u{1B}[0m`、彩色标识符 `NetworkTimeout429BusyProbe`、OSC 包裹的中文提示词回显仍然不会被误判。
- 状态优先级保持：observe 仍按授权异常 → 临时异常 → 忙碌 → 完成 → 就绪的顺序判定；`error: 429 rate limit` 这种同行混入仍优先报临时异常，符合既有调度行为。
- 该识别增强属于技术负责人维护侧的命令行容错；老板总控台不展示底层 ANSI / `rawValue` / 完整命令参数，恢复建议、自动循环就绪审计与终端日志的中文产品话术保持不变。

### 2026-05-01 REPL prompt 识别 ANSI / 控制符容错

- `CLIInteractionProfile` 新增静态 `normalizedForPromptMatching(_:)`：在 prompt 静态识别前按"行 + 光标"模拟终端：剥离 ESC CSI（颜色、光标控制等无可见副作用的序列）、OSC（终端 title / 超链接）控制序列，识别 `CSI K` / `ESC[0K` 清光标到行尾、`ESC[1K` 把行首到光标位置改成空格、`ESC[2K` 清整行；CR 只把当前行光标重置到列 0，**不擦掉尾部**；BS 只把光标左移一位，shell 标准擦字 `\b \b` 才会用空格覆盖；丢弃 BEL 等其他 C0 控制字节和 DEL；保留中文、`\t` 和 `\n`。
- `containsREPLReadySignal` 与 `endsWithReplReadyPrompt` 都改为先规范化再判定：带颜色或 OSC title 包装的 `codex>` / `claude>` / `gemini>` 行可以正确识别；CR 之后必须有 `CSI K` 类清行控制符或后续字符把残留尾部覆盖完，prompt 才算就绪；裸 `processing...\rcodex>` 因尾部 `sing...` 仍然可见会被拒绝，避免被假就绪误发。
- 真实终端席位 preflight、单轮手动 REPL 发送和增量观察共用同一规范化输入；规范化只服务 prompt 静态识别，不影响轮询期增量解析或 `__OPC_JOB_EXIT_<id>__` 退出协议。
- 该识别增强属于技术负责人维护侧的命令行容错，不进入老板总控台、不暴露底层 ANSI / `rawValue` / 完整命令参数。

### 2026-05-01 最近 REPL prompt 严格识别与自动循环就绪审计

- 命令行交互画像新增 `endsWithReplReadyPrompt(_:)`：要求终端最近一非空行去掉首尾空白后整行命中 `codex>` / `claude>` / `gemini>` 才算就绪；旧的「任意一行命中」语义保留为 `containsREPLReadySignal`，仅供观察增量输出阶段使用。
- 真实终端自动交互循环和单轮手动 REPL 的发送前预检都改用最近一行判断：tmux scrollback 里残留的旧 prompt 不再把当前还在「正在处理…」的席位误判为可继续交互，会以中文「最近一行不是 \(协议名) 的专用就绪提示」拒绝并终止本次发送。
- `TerminalAutoInteractionLoopReport` 增加 `terminalReadinessAudit` 中文审计字段，并在 `summaryText` 里输出「就绪校验：最近一行已确认 / 未确认」一行；同步把审计追加到 `terminalLogs` 下的 `[OPC 自动循环就绪审计]` 区块，老板总控台不展示。
- 拒绝路径仍不消耗循环轮次、不写老板聊天、不写员工协作消息、不创建命令行作业档案；审计行也不暴露底层参数、`rawValue` 或后端签名字段。

### 2026-05-01 默认可见界面减噪锁定

- 终端大厅员工卡片的来源摘要和命令预览以中文展示工具、模型、思考强度和执行方式；不直接暴露完整命令数组、`model_reasoning_effort`、`--skip-git-repo-check` 等运行参数，详细命令仅保留在运维详情和 `.opc/jobs/` 作业档案。
- 订阅制命令行的默认可见交互文案使用「持续交互」「命令行工具」「就绪提示」「命令行工具可用」等产品词；不要在老板侧、员工卡片或默认维护入口显示「执行协议」「长期会话协议」「协议可用」等实现命名。底层 `CLIInteractionProfile`、就绪信号和运行档案仍可在维护逻辑中保留实现概念。
- 运行证据分类巡检的默认可见文案使用「验证记录」「产物档案」「技术维护或交付验收分类清单」；不要向维护详情、按钮 Help 或巡检正文暴露 `VerificationRecord` / `ArtifactRecord` / `CompanyStore.*` 分类常量名。
- 旧数据迁移和维护清理的默认可见说明使用「旧任务」「没有产品归属」「等待归属确认」「当前产品」等产品词；不要向维护详情或巡检结果暴露 `productID`、`selectedProductTasks`、`legacy fallback`、`fallback` 等实现名。
- 技术维护详情的默认可见巡检结论也要用产品层词汇：产品隔离说「产品归属」，会话文件说「员工会话日志档案」，终端依赖说「终端工具」，角色称呼说「技术负责人」；不要把 `productID`、`sessions.jsonl`、`tmux` 或 `CTO` 这类实现词作为结论文本直接展示。
- 老板/技术负责人/员工角色显示名继续避免「Codex CTO」等中英文混排，所有可见角色称呼使用「老板」「技术负责人」「员工」。
- 新增测试锁定终端大厅默认卡片可见文本不含命令底层参数和英文角色词，但仍可显示 Codex / Claude Code / Gemini 等品牌名，避免之后回归。

### 2026-05-01 持久执行、通信网关和历史索引增强

- 本地历史索引作为主快照的旁路查询层落地，不在每次保存时同步全量重建；终端大厅维护区提供「历史索引巡检」入口。
- 真实终端席位执行增加未完成 OPC 任务守门：发现同一 tmux 席位还有未闭合 marker 时拒绝覆盖发送；命令超时后会先普通中断、再强中断，仍未闭合时关闭未响应席位。
- Codex / Claude Code / Gemini 的长期会话协议画像落地并补齐首轮回退：统一保存协议形态、会话模式、会话编号字段、可配置编号格式、就绪/本轮结束/忙碌/授权异常/临时异常信号和建议超时；状态观察器可识别可继续交互、等待回复、本轮结束、忙碌、授权异常和临时异常，并在员工任务结束后写入运行会话档案和终端日志中文摘要；运行前预检只向用户展示中文摘要，不暴露底层参数；持久终端会话已经支持单行字面量输入基础件，续跑失败连续出现后会清理当前产品旧会话，避免过期会话死循环。
- 通信网关增加出站调度器：支持 LOCAL、HTTP POST、一次重试和 webhook 地址脱敏错误；UI 区分「生成手机汇报」和「发送到就绪通道」。
- 移动端入站指令增加通道守门：必须启用、允许指令、支持入站且配置就绪；本地指挥台可用于无外网验证。
- 外部入站动作白名单落地：签名入口只接受结构化 JSON，当前允许查询当前产品状态和提交普通指令任务；非 JSON、非白名单动作和外部审批动作会被拒绝并写入通信日志。
- 入站安全基础件增加 HMAC-SHA256 签名、时间戳窗口和 nonce 重放校验测试；公网/局域网 HTTP 入站服务仍默认关闭。

### 2026-04-30 多 Agent 架构升级方案完成态

- 多 Agent 架构升级方案的主链路已经从“规划中”更新为“已闭合”：结构化消息总线、显式任务图、技术负责人调度闭环、交付证据库、验收门禁和老板视图减噪均具备 Store 层能力、UI 入口和测试覆盖。
- 终端大厅「运行闭环演练」可在当前产品上生成完整证据链；真实终端工作区已启动且闭环演练完成后 `selectedProductArchitectureCompletionScore` 达到 100%，七个架构体检项全部通过。
- 当前产品未运行演练时，体检显示未闭合/待加强代表缺少该产品的闭环证据，不代表架构代码能力缺失。
- 仍列为长期项的是完整交互式 REPL 状态机和外部入站 HTTP 服务；历史归档迁移已具备“复制到本地归档表但不裁剪主快照”的安全第一版。

### 2026-04-30 架构体检闭环证据收紧

- 「多员工架构体检」里的「交付证据库」和「验收门禁」不再只看当前产品是否存在任意产物、验收或门禁；现在必须检查最近闭环追踪里的关联产物、验收记录和门禁记录。
- 产品里散落的无关报告或验收只能让模块进入「待加强」，不能冒充从技术负责人拆解、员工执行、审查门禁到老板验收的完整闭环。测试新增无关证据场景，确认只有闭环关联证据能让模块通过。

### 2026-04-30 审查员个人审查队列

- 员工工作台新增「我的待审任务」面板，仅审查员或具备 review 技能的员工可见；队列只显示当前产品、当前员工本人负责、状态为「待审查」的任务。
- 审查员可以直接「完成审查」或「打回返工」：动作会更新任务状态、写入员工协作消息、刷新验收门禁并追加中文事件，不写老板首页消息、不触发模型任务。
- 审查反馈消息新增结构化结果字段：通过写入「审查通过」，打回写入「审查打回」；旧消息没有该字段时保持兼容，不再要求后续巡检或闭环追踪解析消息标题。
- 技术负责人闭环里的审查任务被打回时，会自动把同目标执行任务重新放回执行员工队列，并在派发消息里带上打回原因；只重排队，不启动模型任务、不创建作业档案、不通知老板首页。
- 执行员工工作台会把自己的返工队列单独计数，并在队列卡片里显示中文「返工」标签和打回原因；该信息留在员工执行视图，不进入老板总控台。
- 技术负责人后台「多员工架构体检」新增「返工追踪」摘要，按当前产品显示返工队列数量、任务、状态、执行员工和原因，帮助技术负责人跟踪返工闭环。
- 执行员工完成返工工作项后，系统会重新打开同目标审查任务并写入「返工后复审」协作消息和待审查门禁；审查员个人待审面板会显示「返工后复审」中文标签，避免返工完成后卡在技术负责人后台。
- 审查员对技术负责人闭环审查任务签字通过后，系统会自动提交对应老板审批到老板决策中心，并写入技术负责人推进消息；重复复审不会重复创建同一老板审批。
- 老板批准技术负责人闭环的最终审批后，系统会把同目标的技术负责人拆解、员工执行、审查验收和「老板审批：目标」任务组自动收束为完成，并写入验收报告、老板验收通过记录和验收完成消息；普通风险审批仍保持批准后继续运行。
- 老板驳回技术负责人闭环的最终审批后，系统只对同目标闭环触发返工回流：老板审批任务退出风险列表并等待返工后再次提交，把员工执行任务重新放回执行员工返工队列，并把审查任务退回待后续复审；返工完成、审查员复审通过后可以再次提交新的老板审批。普通风险审批仍保持驳回后阻塞。
- 最终审批的批准/驳回回流使用审批记录自己的产品归属写入任务、队列、消息和事件；老板在另一个产品页签处理旧审批时，也不会把返工队列写到当前选中的产品。
- 该能力属于员工执行视图，继续由技术负责人汇总后向老板展示结果、风险、审批和交付，保持老板总控台减噪边界。
- 测试覆盖本人/他人、状态、跨产品、消息回传、验收门禁和不启动运行任务等守门条件。

### 2026-04-30 普通界面后台词中文化

- 可见角色称呼进一步统一：界面标题、按钮、事件、任务图、消息主题、角色包和默认员工名里的 `CTO` 改成「技术负责人」，并增加旧持久化状态迁移，把旧的 `Codex CTO` 显示名转换为「Codex 技术负责人」。
- 多员工闭环的数据前缀同步改为「技术负责人拆解 / 技术负责人调度」，测试同步覆盖闭环任务图、消息链、发车台计划、命令行预检和自动调度，确保多员工架构升级仍按同一方案闭合。
- 项目导入、通信网关、员工档案和命令行错误里的普通后台词统一改成中文产品话术：例如「智能工具」「接口地址」「聊天标识」「网络回调通道」「命令行工具」「技术负责人」。
- 员工简报、自动压缩记忆和聊天日志不再把 `TaskStatus.rawValue`、`MessageAuthor.rawValue`、`[chat exit]`、`[api chat exit]` 这类英文内部值显示给老板/员工，改用中文状态、作者和退出码标签。
- 保留 Codex、Claude Code、Gemini、OpenAI 等具体产品/模型品牌名；新增测试锁定导入报告、通信网关日志、员工记忆和技术负责人简报不再显示 `AI 工具`、`Endpoint`、`Chat ID`、`Webhook/Bot`、`user`、`running` 等普通英文后台词。

### 2026-04-30 运行巡检可见文案中文化

- 运行会话健康巡检的说明文本不再向界面暴露 `runningAgentIDs`、`.opc/jobs`、`agent 消息总线` 这类内部实现名，统一改成「正在运行的员工列表」「作业档案」「员工协作消息」。
- 补测试锁定该报告的中文产品词，避免内部变量名重新出现在终端大厅、验证记录或技术负责人后台。

### 2026-04-30 运维预检可见文案中文化

- 终端大厅、运行前预检、命令行链路压测预检和发车计划不再直接展示底层命令参数、提示词占位符和调试开关，改为「运行摘要」「运行清单」和「任务注入」等中文产品话术。
- 运行会话健康巡检不再在报告里显示 `busy`、`lastError`、`backendSignature` 或后端签名字串，改为「异常占用」「最近错误」「后端配置匹配/不匹配」。
- 命令行作业幽灵巡检不再把完整内部作业编号显示在可见报告里，改用「作业 1 / 作业 2」这类短中文编号；真实作业 ID 仍保留在磁盘档案中供运维回查。
- 命令行与工作区隔离体检不再在预览里展示 `sessions.jsonl`、`.opc/worktrees`、元数据目录或 `source` 目录，改为「员工工作区已创建」「会话日志已创建」「独立执行区/主工作目录」等中文摘要。
- 真实终端工作区预览不再显示 tmux 路径、会话名、窗口名或内部终端标识，改为「终端工具已就绪」「已连接席位」「员工终端席位」等中文摘要。
- 本地维护区采用「默认中文摘要 + 折叠运维详情」分轨；普通截图和复制默认只包含中文摘要，路径、会话名、窗口名等排障字段只放在「展开运维详情」内。
- 员工工作台里的运行状态摘要会把英文退出标记和底层错误字段转成中文摘要，命令行工具只展示工具名，不展示完整参数。
- 命令行任务、员工聊天和聊天修正的终端日志不再回显完整底层命令数组或提示词参数，统一显示「运行方式」「执行位置」「任务摘要」；异常占用恢复报告也不再显示 `busy`、`timedOut`、`lastUsedAt` 等内部状态名。
- 安全检查点列表默认只显示中文时间和「本机检查点已保存」，不再展示 `Library/Application Support` 下的内部存档路径。
- 老板/员工/检查器等普通视图统一用工具名和「默认模型」展示后端配置，完整命令字串只保留在可编辑配置输入框和运维档案里。
- 保留 Codex、Claude Code、Gemini、OpenAI、模型名和必要路径等用户配置名；底层参数仍由系统生成并用于真实运行，只是不作为普通可见文案展示。
- 测试覆盖：命令行链路压测、运行前预检、发车计划、命令行任务终端日志、异常占用恢复、安全检查点列表和运行会话巡检不再泄漏 `OPC_PROMPT`、`model_reasoning_effort`、`--skip-git-repo-check`、`busy`、`timedOut`、`lastUsedAt`、`lastError`、`backendSignature`。

### 2026-04-30 可见日期中文化修正

- 终端大厅和本地维护区的「最近安全检查点」列表改用统一 `Date.opcDateTimeText`，通信日志行的时间改用 `Date.opcShortTimeText`，避免出现 `4/30/2026`、英文月份或 AM/PM 这类中英文混排日期。
- 员工记忆自动压缩摘要同步改用同一日期格式，保持员工工作台和日志可见文本的中文数字日期一致。
- 测试覆盖安全检查点列表的日期稳定性：包含 `2026/04/30` 风格前缀，不包含美式日期和 AM/PM。

### 2026-04-30 员工收件箱单条消息确认

- `CompanyStore` 新增 `acknowledgeSelectedAgentMessage(_ messageID: UUID) -> Bool`：仅当消息属于当前产品、`toAgentID == selectedAgentID` 且仍为待确认时才执行单条确认；其他情况返回 false 且不修改状态。出站消息、其他员工消息、跨产品消息都会被拒绝。
- 确认成功时会写入 `acknowledgedAt`，并向事件流追加中文标题「员工协作收件箱已确认一条」+ 主题片段；不向老板首页写消息，不触发模型任务，不创建作业档案。
- `AgentMessageRow` 增加可选 `onAcknowledge` 闭包参数：员工工作台「我的协作收件箱」、员工消息中心 (`AgentMessageCenterSheet(scope: .agent)`) 在入站待确认消息上显示中文按钮「确认这条」；产品级 `scope: .product`、产品详情「员工协作链路」、流程图「消息流 / 协作链路」保持只读，不替别人确认。
- 与员工交接巡检联动：单条确认会让 `runEmployeeHandoffAuditForSelectedProduct` 把对应交接从待确认计数移走，警告 / 失败状态在所有 pending 都被确认后回到通过。批量「标记我的消息已读」按钮保留。
- 测试覆盖：单条确认只作用于当前员工当前产品入站；出站和他人消息被拒；跨产品被拒；员工交接巡检在确认前为警告、确认后为通过；中文事件标题稳定。

### 2026-04-30 员工工作台快捷发起员工交接

- `CompanyStore` 新增 `selectedAgentHandoffRecipients`、`selectedAgentHandoffTaskCandidates`、`postSelectedAgentHandoff(toAgentID:taskID:subject:body:)`：当前选中员工维度筛选可交接接收人（同产品团队、非老板、非自己）、可关联任务（自己负责的当前产品任务，按状态优先级排序），并通过 `postEmployeeHandoff` 落地，保留同产品守门和老板/跨团队保护；空主题/正文时由消息总线兜底文案补全。
- `AgentDeskWorkspace` 新增中文「发起员工交接」面板，紧贴「我的协作收件箱」之下：下拉菜单选交接对象、下拉菜单选关联任务（含「无关联任务」）、输入框填主题与正文、按钮发送；老板/未加入团队/无可接收人时分别给中文空状态。发送成功后清空输入并提示「已写入员工协作消息总线，待对方在收件箱确认」。**不进老板总控台**；不触发模型任务、不创建作业档案。
- 与员工交接巡检联动：手动发起的员工交接和闭环演练自动写入的员工交接走同一条 `agentMessages` 总线，`runEmployeeHandoffAuditForSelectedProduct` 会一并统计待确认/超时。
- 测试覆盖：候选接收人不含老板/自己/外部成员；快捷交接生成 `employeeHandoff` 待确认消息（带任务 / 无任务）；非本人负责的任务、老板视角和跨产品都被拒绝；空主题/正文时使用中文兜底文案。

### 2026-04-30 员工交接待确认巡检

- `CompanyStore` 新增 `employeeHandoffAuditText(staleAfter:)` 与 `runEmployeeHandoffAuditForSelectedProduct(staleAfter:)`：默认阈值 180 秒（最低 60 秒），按当前产品维度统计员工交接消息总数、待确认数、已确认数、超时待确认数，并列出每条交接的状态、收发员工、主题和等待时间。
- 巡检结果写入 `VerificationRecord("员工交接待确认巡检")`、技术负责人系统消息和事件流。无超时且无待确认时标记为通过；存在超时待确认时标记为失败并额外写一条「员工交接超时待确认」风险事件；只有待确认而没超时时标记为警告。
- 巡检纯只读，不修改交接状态、不创建作业档案、不触发模型任务。员工想清除待确认仍需自行在「我的协作收件箱」里点击「标记我的消息已读」。
- 入口位于 `LocalMaintenanceCenter` 的技术负责人/运维后台区域：新增中文按钮「运行员工交接巡检」和始终可见的中文「员工交接巡检预览」卡片，**不进入老板总控台**。
- 测试覆盖：空状态通过；闭环演练后待确认交接被巡检看到、确认后从警告转为通过；超时交接产生失败结果和风险事件，再次确认全部交接后通过且不会重复写超时风险事件；跨产品隔离。

### 2026-04-30 跨员工显式交接消息

- `AgentMessageKind` 增加 `employeeHandoff`，用于「界面设计师 → 工程师」和「工程师 → 审查员」这类员工到员工的显式交接。
- `CompanyStore` 新增 `postEmployeeHandoff(productID:fromAgentID:toAgentID:taskID:subject:body:)`：仅允许同一产品团队的非老板员工之间发送，跨产品 / 跨产品任务 / 老板 / 非团队成员或自交接会被拒绝并写入风险事件，**不写老板首页消息、不创建 `.opc/jobs/` 作业档案、不触发模型任务**。
- 闭环演练 `runMultiAgentArchitectureClosureDrill` 在工程完成后会写入一条「工程师 → 审查员」的 `employeeHandoff`，作为闭环证据链一环；闭环追踪通过 `closureTraceMessages` 自动包含交接证据。
- `AgentMessageDisplay` 增加中文标题「员工交接」、`person.2.wave.2.fill` 图标、`CompanyTheme.blue` 配色，员工工作台「我的协作收件箱」和产品详情「员工协作链路」自动显示该类型。
- 测试覆盖：合法同产品员工交接的发送人、接收人、任务、正文正确；老板/自交接/跨团队均被拒绝；闭环演练后消息种类含 `employeeHandoff`；跨产品不串台。

### 2026-04-30 闭环演练复盘摘要

- `CompanyStore` 新增 `selectedProductClosureDrillSummaryText()`，按当前产品聚合最近一次多员工闭环追踪的目标、闭环状态、完成度、任务、协作消息、审批、审查门禁、产物、验收等关键计数，并根据闭环状态给出「下一步」建议。
- 没有闭环记录时输出统一的空状态文案，提示在技术负责人后台运行「运行闭环演练」。
- 技术负责人和运维后台「多员工架构体检」面板新增 `ClosureDrillSummaryCard` 区块展示这段摘要，**不进入老板总控台**，且不暴露后端、命令行、模型等运维细节，符合 § 7 老板视图减噪。
- 文案全中文（中文括号「」），保持与 OPC_COMPANY § 7 一致。
- 测试覆盖：无闭环时输出"暂无记录"且包含"运行闭环演练"提示；闭环演练后摘要包含目标、100%、任务/协作消息/审批/审查门禁/产物/验收/下一步关键字段；跨产品不串台。

### 2026-04-30 运行会话健康巡检

- `CompanyStore` 新增 `runtimeSessionHealthAuditText(staleAfter:)` 和 `runRuntimeSessionHealthAuditForSelectedProduct(staleAfter:)`，纯只读诊断当前产品可执行员工：运行会话是否存在、状态/能力/后端配置是否与当前员工档案一致、订阅制命令行工具是否可解析、接口三件套是否齐全、运行占用是否超过 180 秒、累计失败次数和最近错误。
- 报告写入 `VerificationRecord("运行会话健康巡检")`、CTO `ChatMessage` 和事件流；有命令缺失/后端漂移/缺会话/异常占用/最近失败任一发生时 status `.warning`，全部健康时 `.passed`。
- 巡检不会改正在运行的员工列表、不动员工状态、不写员工协作消息、不创建作业档案、不触发模型任务。异常占用仅在报告里高亮"提示，本次不恢复"，恢复仍由"恢复异常占用员工会话"按钮负责。
- `AgentRuntimeSession` 记录 `productID`，运行会话健康巡检会提示"产品漂移"；切换产品后同一员工的旧产品会话不会被静默复用，异常占用恢复也不会误恢复其他产品的同员工会话。
- 入口位于 `LocalMaintenanceCenter`（CTO/运维层），不进老板总控台。
- 测试覆盖：健康团队 passed；命令缺失/后端漂移 warning；异常占用仅提示，不动运行列表、运行会话和员工状态；不污染消息总线和作业档案。

### 2026-04-30 命令行作业幽灵巡检

- `CompanyStore` 新增 `jobArchiveStaleAuditText(staleAfter:)` 和 `runJobArchiveStaleAuditForSelectedProduct(staleAfter:)`，只扫描当前产品根目录 `.opc/jobs/*/status.json`。
- 巡检会识别仍为运行中、更新时间超过阈值、但对应员工没有真实运行占用的旧作业档案，把它们写回为已中断，并记录原状态、中断时间和中断原因。
- 报告写入 `VerificationRecord("命令行作业幽灵巡检")` 和运维事件；不会启动模型任务、不会写老板聊天、不会新增员工协作消息，也不会创建新的 `.opc/jobs/`。
- 入口位于 `LocalMaintenanceCenter`（CTO/运维层），包含中文按钮和预览卡片，不进入老板总控台。
- 测试覆盖：幽灵运行作业被中断；仍有真实运行占用的作业不被打断；未超过阈值的运行作业不被打断；巡检不污染老板聊天和员工消息总线。

### 2026-04-30 异常占用员工会话恢复

- `CompanyStore` 新增 `recoverStaleRuntimeSessionsForSelectedProduct(staleAfter:)`，默认阈值 180 秒（最低 60 秒）。仅处理"正在运行列表内 + 员工运行会话占用中 + 最近使用时间超过阈值"三条同时成立的员工运行会话，正常运行任务不会被打断。
- 恢复动作：从正在运行列表移除该员工、把员工运行会话置为超时、失败计数 +1、写入最近错误、向员工终端日志追加运维恢复条目、追加风险事件、写入 `VerificationRecord("异常占用会话恢复")` 和 CTO 报告。
- 不触发模型任务、不写 `agentMessages` 总线、不写 `.opc/jobs/` 作业档案——下一次任务仍必须从 OPC 运行入口手动发起，保留预检、作业档案和验收链路。
- 入口位于 `LocalMaintenanceCenter`（CTO/运维层），不进老板总控台。
- 测试覆盖：最近运行占用不被打断；异常占用被恢复且不影响非运行员工；不会跨产品误清；恢复路径不污染员工协作消息。

### 2026-04-30 多 Agent 架构第五阶段：交付验收中心

- 新增 `DeliveryAcceptanceCenterSheet`，把可验收任务、自动验收记录、交付物记录集中到完整弹层；老板总控台和产品详情页继续只展示最近摘要和入口。
- `CompanyStore` 新增 `selectedProductRecentArtifacts` / `selectedProductRecentVerifications` / `selectedProductAcceptanceTasks`，统一当前产品隔离、倒序展示和验收候选筛选。
- 产品详情的“交付物与验收”和老板总控台的“最近交付与验收”改为显示最近记录，并提供“打开交付验收中心”入口，避免主界面堆积完整历史。
- 验收动作接入协作闭环：`requestCTOReview` 写入 `reviewRequested` 消息；`generateAcceptanceReport` 写入报告产物和 `reviewCompleted` 消息；`acceptTask` 写入老板验收记录、任务产物索引和 `acceptanceCompleted` 消息。
- 新增轻量 `ReviewGateRecord` / `ReviewGateStatus`，把送审、自动验收、报告产物和老板验收串成独立门禁记录；快照 schema 升级到 13，删除产品/清理运行数据时同步清理门禁。
- 交付验收中心新增 `ReviewGate 验收门禁` 区块，老板和 CTO 可以看到每个待验收任务的门禁状态、摘要和更新时间。
- 新增 `MultiAgentArchitectureCheck` / `ArchitectureCheckStatus` 和 CTO 高级控制台“多 Agent 架构体检”面板，按升级方案检查结构化消息总线、显式任务图、技术负责人调度闭环、交付证据库、验收门禁和老板视图减噪的闭合状态，并可生成 CTO 架构体检报告。
- CTO 后台新增“运行闭环演练”，用真实 Store 状态流转一次性跑通 CTO 目标、任务派发、员工回传、审查、老板审批、产物报告、自动验收和老板验收，用于验证多 Agent 主链路。
- 新增 `MultiAgentClosureTrace` / `MultiAgentClosureTraceStep` 派生追踪视图和“查看闭环详情”后台弹层，从任务、消息、审批、ReviewGate、产物、验收记录还原每次 CTO 闭环的证据链。
- 新增 `MultiAgentTaskGraphNode` / `MultiAgentTaskGraphEdge` 派生任务图，把闭环任务串成“CTO 派发 -> 员工回传 -> 审查结论 -> 老板决策回流”的显式边证据。
- 多 Agent 架构体检的显式任务图项改为检查任务图节点和边数量，不再只按技术负责人任务数量判断。
- 闭环详情新增下钻分组，可展开查看具体任务、消息、审批、ReviewGate、产物和验收记录标题与摘要；下钻 helper 统一由 `CompanyStore` 提供，避免 UI 重复筛选。
- 闭环详情新增“生成审计报告”，把单次闭环证据链写入 CTO 对话并登记为报告产物，便于后续复盘和交付审查。
- 闭环审计报告按 `opc://closure-traces/...` 路径和报告标题保持幂等；报告已存在时后台按钮显示“审计报告已生成”并禁用，避免同一闭环重复创建报告产物。
- 终端大厅系统维护区新增“命令行与工作区隔离体检”，检查可执行员工的独立员工工作区、会话日志、运行会话，并为代码/测试员工创建 `.opc/worktrees/.../source` 独立源码执行区；有代码仓库的产品使用独立代码仓库工作区，非代码仓库但能识别为项目根目录的产品使用源码快照隔离，不能安全识别时只登记目录并继续使用主工作目录。
- 命令行真实运行链路新增 `.opc/jobs/<job-id>/` 作业档案：运行前写入 `brief.md`、`agent-task.md`、`status.json`、`transcript.log` 占位和 `artifacts/` 目录，命令结束后回填运行记录与退出状态，并作为“命令行作业档案”产物进入交付证据库，供 CTO/审查追踪，不直接暴露到老板首页。
- CTO 后台新增“真实终端工作区”：为当前产品团队创建可复用 tmux 会话和每个可执行员工的独立终端窗口，窗口只写入身份和执行目录提示，不自动执行模型任务；具体任务仍必须从 OPC 运行入口发起，以保留预检、作业档案、消息总线和验收记录；后台可手动刷新真实终端日志，把 pane 内容回收到员工终端日志、CTO 报告和验证记录。
- 测试覆盖：交付验收中心文案稳定性、交付物/验收记录当前产品隔离、按时间倒序、可验收任务筛选、ReviewGate 状态流转、持久化和产品删除清理。

### 2026-04-30 多 Agent 架构第四阶段：完整协作消息中心

- 新增 `AgentMessageFilter`（全部、待确认、已读、失败）和 Store 过滤 helper：`selectedProductAgentMessages(filter:)` / `selectedAgentProductMessages(filter:)`，完整列表仍基于当前产品隔离和时间倒序。
- 产品详情、流程图、员工工作台保留最近 6 条摘要，并新增"查看全部"入口打开 `AgentMessageCenterSheet`；完整历史进入弹层，不再堆到主界面。
- 员工消息中心支持筛选和"标记我的消息已读"，并在员工未加入当前产品团队时显示明确提示，不展示误导性空列表。
- 测试覆盖：产品维度状态筛选、员工维度相关消息筛选和倒序、待确认筛选、文案常量和筛选标题稳定性。

### 2026-04-30 老板决策中心

- 新增 `BossDecisionCenterSheet`，把待审批请求、风险/阻塞任务、已处理审批集中到一个老板弹层里，主界面继续只显示摘要。
- `CompanyStore` 增加 `selectedProductPendingApprovals` / `selectedProductResolvedApprovals` / `selectedProductRiskTasks` / `bossDecisionCount`，老板总控台和右侧老板面板统一使用这些 helper，减少重复筛选逻辑。
- 已处理审批使用只读 `BossApprovalDecidedRow` 展示，不再出现批准/驳回按钮；待审批和风险任务继续复用现有批准/驳回组件。
- 测试覆盖：当前产品隔离、审批决策后从待审批进入已处理、任务状态变化、已处理审批按最近决策排序、决策中心文案稳定性。

### 2026-04-30 多 Agent 架构第三阶段：员工收件箱

- `CompanyStore` 增加 `selectedAgentProductMessages`（当前产品、与 selectedAgent 收发相关）/ `selectedAgentPendingMessages`（仅入站待确认）/ `acknowledgeSelectedAgentMessages()`（仅 ack 当前员工收到的 pending）。发送出去的 pending 不算"我待确认"，跨员工/跨产品互不影响。
- 员工工作台（`AgentDeskWorkspace`）新增"我的协作收件箱"面板，紧贴 header 下方，展示最近 6 条相关消息，含"标记我的消息已读"按钮、"待确认 N"徽标和空状态文案；非团队成员显示明确的未加入团队提示。
- 产品协作链路和员工收件箱统一使用 `selectedProductRecentAgentMessages` / `selectedAgentRecentProductMessages`，按 `createdAt` 倒序展示最新消息，避免旧消息占住前 6 条。
- 修复 `startCTOSupervisorGoal` 中 reviewer/engineer 角色解析的优先级：先按 `firstAgentID(for:)` 走显式角色匹配，再回退到技能推荐。原来当 `successCriteria` 含"目标"等关键词时会被 `planning` 技能优先匹配到 CTO，导致 reviewer 任务被错误派发回 CTO。
- 测试覆盖：收件箱只返回当前产品且与 selectedAgent 相关、最近消息倒序、ack 仅作用于入站、其他员工/其他产品 pending 不被影响、入口文案 helper 验证。

### 2026-04-30 多 Agent 架构第二阶段：协作链路可见化

- `CompanyStore` 增加 `selectedProductPendingAgentMessages` / `acknowledgeSelectedProductAgentMessages()`，按当前产品维度过滤和 ack，跨产品消息互不干扰。
- 产品详情页（`ProductDetailWorkspace`）新增轻量"Agent 协作链路"面板：展示最近 6 条消息、类型、发送者→接收者、关联任务、状态，含"推进 CTO 循环""全部标记已读"按钮和空状态文案；老板总控台保持不动。
- 协作链路为空时提供"启动协作目标"入口，直接基于当前产品目标或阶段里程碑创建 CTO 多 Agent 协作链路，避免只展示空状态。
- 任务流程图（`WorkflowMapView`）新增"消息流 / 协作链路"区块，按时间线展示老板→CTO→员工→审查→老板审批的最近消息，不改原有流程节点和任务看板大结构。
- 引入 `AgentMessageRow` / `AgentMessageDisplay` 用于统一消息行渲染（图标/颜色/文案）。
- 测试覆盖：`startCTOSupervisorGoal` 后 pending 消息 > 0 且 ack 后归零、ack 只影响当前产品、视图入口（`AgentMessageDisplay`）暴露文案和图标。

### 2026-04-30 多 Agent 架构第一阶段

- `CompanyStore` 接入 `agentMessages` 消息总线：CTO 派发任务、员工回传完成、审批请求/裁定、CTO 调度循环都会写入结构化消息。
- 新增 `startCTOSupervisorGoal(goal:)` / `advanceCTOSupervisorLoop()` 闭环：自动创建 CTO 拆解、员工执行、审查验收、老板审批四个任务并通过消息总线派发。
- 跨团队收发消息会被拒绝并写入风险事件，老板和 CTO 享有跨产品调度豁免。
- `CompanySnapshot` 持久化保留 `agentMessages`，旧快照通过 `decodeIfPresent` 兼容。
- 删除产品或清理当前产品运行数据时同步清理对应 `agentMessages`，避免已删除产品的协作消息残留。
- 测试覆盖：`startCTOSupervisorGoal` 创建任务/工作队列/消息、非团队员工无法收到产品消息、`completeWorkItem` 给 CTO 回传、审批链路可追踪、消息持久化。

### 2026-04-30

- 建立 OPC 公司产品总纲。
- 明确老板、CTO、员工三层职责。
- 明确老板总控台应以结果、风险、审批和交付为核心。
- 明确多 Agent 架构方向：CTO Supervisor + TaskGraph + MessageBus + ArtifactStore + ReviewGate。
- 明确员工聊天不能硬编码人格，必须走真实模型链路或明确降级提示。
- 明确普通聊天和工作任务默认使用同一个员工模型配置，不隐式降级。
- 启动多 Agent 架构第一阶段升级：结构化 Agent 消息总线、CTO 调度入口、员工回传和审查闭环。

### 2026-04-30 老板决策中心

- 新增老板决策中心弹窗，集中处理当前产品的待审批请求、风险/阻塞任务和已处理审批记录。
- 老板总览和右侧老板面板提供统一入口，避免审批能力散落在多个区域。
- `CompanyEvent` 新增产品归属，新增事件自动绑定当前产品，避免多产品风险事件串台。
- 老板“待我处理”只展示真正需要老板处理的审批/阻塞项，不再把普通风险日志混作待决策事项。
- 测试覆盖：决策中心文案、当前产品审批隔离、风险任务隔离、风险事件隔离、审批处理后进入已处理列表并更新计数。

### 2026-04-29 至 2026-04-30

- 增强员工聊天链路，避免展示原始 CLI 日志。
- 增加运行时会话状态、预热和重开基础能力。
- 调整老板总控台，减少后台操作暴露。
- 统一深色视觉方向，推进像素小人和公司场景。
- 增加多产品工作区、员工档案、角色包、记忆和技能的基础结构。

## 12. 后续路线

### P0：把“像公司一样工作”的闭环做实

- 结构化消息总线：员工之间、员工到 CTO、CTO 到老板的消息全部结构化。
- 显式任务图：每个目标生成任务图、依赖、分支、验收节点。
- 技术负责人调度循环：持续检查任务、分配员工、收结果、发审查、给老板汇报。
- 验收门禁：代码、方案、交付物进入审查和老板审批。
- 老板视图减噪：老板首页只保留结果、决策和风险。

### P1：把执行能力做实

- Codex / Claude / Gemini 常驻会话驱动。
- tmux 或 PTY 真实多终端工作区。
- 每个产品独立工作目录和可选 git worktree。
- 产物库和验收记录。
- 导入已有项目并接管上下文。

### P2：把组织能力做实

- 团队模板：软件产品团队、售前方案团队、研究团队、内容团队。
- 团队负责人机制：每个产品一个负责人，向 CTO 汇报。
- 员工绩效和可靠性记录。
- 技能市场和角色包导入导出。

### P3：把远程协作做实

- 通信网关。
- 手机汇报。
- 远程审批。
- 定时日报/周报。

## 13. 维护规则

以后每轮开发必须检查：

- 是否改变了产品定位。
- 是否改变了老板、CTO、员工职责。
- 是否增加了新模块或删除了旧模块。
- 是否引入新的权限风险。
- 是否改变了 UI 信息架构。
- 是否需要更新变更记录。

如果答案是“是”，必须更新本文件。

相关细分文档：

- `docs/PRODUCT_SPEC.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/AGENT_ROLES.md`
- `docs/CLI_ORCHESTRATION.md`
- `docs/MULTI_PRODUCT_WORKSPACES.md`
- `docs/MULTI_AGENT_ARCHITECTURE.md`
- `docs/COMMUNICATION_GATEWAY_SECURITY.md`
- `docs/HISTORY_ARCHIVE_RFC.md`
- `docs/GITHUB_RESEARCH.md`
- `docs/TERMINAL_HALL_DESIGN.md`
- `docs/RUNBOOK.md`
