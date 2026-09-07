# Windows Port Spike Guide (M1)

> Goal: spend 2-3 days on any Windows 10/11 x64 machine measuring **whether the
> Swift core layer compiles on Windows**, so the port route (A: Swift core + FFI
> / B: full Flutter port) is decided by data, not hope.
> No coding required — copy, paste, and send the logs back.

## Prerequisites

- Windows 10/11 x64, ~10 GB free disk
- PowerShell (as administrator for installs)

## Step 1 — Install toolchains (~20 min)

```powershell
winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
winget install --id Swift.OpenSource -e --accept-source-agreements --accept-package-agreements
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

> If `Swift.OpenSource` is not found via winget, grab the latest 6.x installer
> from https://www.swift.org/download/#windows and run it (check "Add to PATH").

Close and reopen PowerShell, then verify:

```powershell
swift --version
git --version
```

## Step 2 — Clone and attempt a full build (~10 min)

```powershell
cd $HOME
git clone https://github.com/B1ueMu3ic4m/OPCCompany.git opc-spike
cd opc-spike
swift build --target OPCCompanyCore 2>&1 | Tee-Object -FilePath spike-log.txt
```

**Do not fix anything** — failures are the data we want. Expect missing-module
errors for `SwiftUI` / `SpriteKit` / `AppKit` / `Security` (Apple-only). Send
`spike-log.txt` back to the maintainers.

## Step 3 — Logic-only compile (the key experiment, ~30 min)

Save as `spike-filter.ps1` inside `opc-spike` and run it. It builds a temporary
package containing only the non-UI core files:

```powershell
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

> Files like `CompanyStore.swift` still `import SwiftUI` (for `ObservableObject`
> / `@Published`), so this step may still fail — **that failure is exactly the
> measurement** of how much core/UI decoupling M0 still owes. Send the log back.

## Step 4 — Environment info (1 min)

```powershell
swift --version
systeminfo | Select-String "OS Name","OS Version"
```

## Deliverables (send all back)

1. `spike-log.txt` (Step 2)
2. `spike-core-log.txt` (Step 3)
3. Output of Step 4

Maintainers will publish a Windows Compile Report and decide the route (see
`WINDOWS_PORT_RFC.md`). Contributors whose spike data is used will be credited
in the release notes.
