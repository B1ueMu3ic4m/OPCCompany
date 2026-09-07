# Windows 移植 Spike 手册（M1）

> 目的：用 2-3 天在 Windows 台式机上实测「Swift 核心层能否在 Windows 编译」，
> 以数据裁决移植路线（A: Swift 核心复用 / B: Flutter 全量移植）。
> 本手册假设你已让 Hermes 准备好一切，你只需要复制粘贴命令并把输出发回来。

## 前置：你需要准备什么

- 一台 Windows 10/11 x64 机器（你的 32GB + 3060Ti 台式机完全够）
- 约 10GB 磁盘空间
- 全程不需要写任何代码

## 第 1 步：安装工具链（约 20 分钟）

1. 打开 PowerShell（开始菜单搜 `powershell`，右键以管理员身份运行）
2. 安装 Git：
   ```powershell
   winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
   ```
3. 安装 Swift for Windows（官方 toolchain）：
   ```powershell
   winget install --id Swift.OpenSource -e --accept-source-agreements --accept-package-agreements
   ```
   > 如果 winget 里搜不到，去 https://www.swift.org/download/#windows 下载最新
   > 6.x 的 `.exe` 安装器，双击安装（勾选 "Add to PATH"）。
4. 安装 Visual Studio Build Tools（Swift 在 Windows 需要 MSVC 工具集）：
   ```powershell
   winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
5. **关闭 PowerShell，重新打开一个普通 PowerShell**（让 PATH 生效），验证：
   ```powershell
   swift --version
   git --version
   ```
   两条都有版本号 = 成功。

## 第 2 步：拉代码并尝试编译核心层（约 10 分钟）

```powershell
cd $HOME
git clone https://github.com/B1ueMu3ic4m/OPCCompany.git opc-spike
cd opc-spike
swift build --target OPCCompanyCore 2>&1 | Tee-Object -FilePath spike-log.txt
```

**不管成功失败，都不要自己修**——把 `spike-log.txt` 发回来（或把报错贴给 Hermes），
这就是 spike 要采集的数据。

预期会撞到的墙（提前知道，不慌）：
- `import SwiftUI` / `import Combine` 找不到 → 正常，SwiftUI 没有 Windows 版，
  核心层里混着 13 个 SwiftUI 文件（视图层），它们本来就不该参与 spike 编译
- `import SQLite3` / `import Security` / `import AppKit` → 平台 API 缺口，逐个记录
- `NSColor`、`Process()` 行为差异 → 记录

## 第 3 步：纯净核心编译（关键实验，约 30 分钟）

上面一步会因视图文件失败，这是预期。真正的实验是：**只编译纯逻辑文件**。
把下面这段存成 `spike-filter.ps1` 运行（它生成一个只含逻辑文件的临时包）：

```powershell
# spike-filter.ps1 —— 在 opc-spike 目录下运行
$logic = @(
  'Models.swift','CompanyStore.swift','CompanyPersistence.swift','KeychainStore.swift',
  'SecretStore.swift','AppStrings.swift','AppStringsTables.swift','AppStringsReverse.swift',
  'AppStringsGenerated.swift','AppLanguage.swift','L10nEnvironment.swift','L10nBundleOverride.swift',
  'DisplayFormatting.swift','CLIAgentRunner.swift','CLIAutoInteractionLoopGate.swift',
  'CLIAutoInteractionLoopExecutor.swift','CompanyHistorySQLiteIndex.swift','ProjectImportScanner.swift',
  'CommunicationGatewayRequest.swift','CommunicationInboundVerifier.swift','CommunicationGatewayDispatcher.swift',
  'CompanyStore+Runtime.swift','CompanyStore+Tasks.swift','CompanyStore+Comms.swift',
  'CompanyStore+Maintenance.swift','CompanyStore+Reports.swift','CompanyStore+Workspace.swift',
  'CompanyStore+Agents.swift','CompanyStore+Persistence.swift'
)
New-Item -ItemType Directory -Force -Path spike-core\Sources\OPCCompanyCore | Out-Null
foreach ($f in $logic) { Copy-Item "Sources\OPCCompanyCore\$f" spike-core\Sources\OPCCompanyCore\ -ErrorAction SilentlyContinue }
@'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OPCCompanyCore",
    platforms: [.macOS(.v14)],
    targets: [.target(name: "OPCCompanyCore", path: "Sources/OPCCompanyCore",
        linkerSettings: [.linkedLibrary("sqlite3")])]
)
'@ | Set-Content spike-core\Package.swift
cd spike-core
swift build 2>&1 | Tee-Object -FilePath ..\spike-core-log.txt
```

> 注意：`CompanyStore.swift` 等文件 `import SwiftUI`（用了 ObservableObject/@Published），
> 这一步大概率仍会失败——**失败本身就是数据**：它告诉我们"逻辑/UI 解耦还差多少"，
> 这正是 M0 抽象层要逐个消灭的东西。把日志发回来即可。

## 第 4 步：采集环境信息（1 分钟）

```powershell
swift --version
systeminfo | Select-String "OS Name","OS Version"
```

## 交付物（全部发回给 Hermes）

1. `spike-log.txt`（第 2 步）
2. `spike-core-log.txt`（第 3 步）
3. 第 4 步两条命令的输出

收到后我会产出《Windows 编译报告》并裁决路线 A/B。
