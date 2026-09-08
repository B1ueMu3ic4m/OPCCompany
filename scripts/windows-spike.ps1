# windows-spike.ps1 — M1 Windows compile experiment (see docs/WINDOWS_PORT_RFC.md)
# Runs on a Windows machine (local or GitHub Actions runner).
# Produces spike-full-log.txt and spike-core-log.txt + an error census summary.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root "Package.swift"))) { $root = $PSScriptRoot }
Set-Location $root

Write-Host "=== Swift version ==="
swift --version

# --- stdlib presence + hello-world probe (run #19: 'unable to load standard
# library' persisted under vcvars — check whether the stdlib is even on disk) ---
$tc = Split-Path (Split-Path (Get-Command swift.exe).Source)  # ...\usr
Write-Host "toolchain usr: $tc"
Write-Host "=== lib/swift contents ==="
Get-ChildItem "$tc\lib\swift" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Host "=== hello-world probe ==="
Set-Content "$env:RUNNER_TEMP\hw.swift" 'print("hello")'
& swiftc "$env:RUNNER_TEMP\hw.swift" -o "$env:RUNNER_TEMP\hw.exe" 2>&1 | ForEach-Object { Write-Host "  $_" }
if (Test-Path "$env:RUNNER_TEMP\hw.exe") { Write-Host "  hw.exe BUILT ok"; & "$env:RUNNER_TEMP\hw.exe" } else { Write-Host "  hw.exe FAILED" }

# ---------- Step 1: full core target build (expected to fail on UI imports) ----------
Write-Host "`n=== [1/2] Full OPCCompanyCore build ==="
swift build --target OPCCompanyCore 2>&1 | Tee-Object -FilePath spike-full-log.txt

# ---------- Step 2: logic-only package ----------
Write-Host "`n=== [2/2] Logic-only build ==="
$logic = @(
  'Models.swift','CompanyStore.swift','CompanyPersistence.swift','KeychainStore.swift','ObservationCompat.swift','AgentMessageDisplay.swift','StringExtras.swift',
  'SecretStore.swift','AppStrings.swift','AppStringsTables.swift','AppStringsReverse.swift',
  'AppStringsGenerated.swift','AppLanguage.swift','L10nEnvironment.swift','L10nBundleOverride.swift',
  'DisplayFormatting.swift','CLIAgentRunner.swift','CLIAutoInteractionLoopGate.swift',
  'CLIAutoInteractionLoopExecutor.swift','CompanyHistorySQLiteIndex.swift','ProjectImportScanner.swift',
  'CommunicationGatewayRequest.swift','CommunicationInboundVerifier.swift','CommunicationGatewayDispatcher.swift',
  'CompanyStore+Runtime.swift','CompanyStore+Tasks.swift','CompanyStore+Comms.swift',
  'CompanyStore+Maintenance.swift','CompanyStore+Reports.swift','CompanyStore+Workspace.swift',
  'CompanyStore+Agents.swift','CompanyStore+Persistence.swift'
)
$core = Join-Path $root "spike-core"
Remove-Item -Recurse -Force $core -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$core\Sources\OPCCompanyCore" | Out-Null
foreach ($f in $logic) {
  $src = Join-Path $root "Sources\OPCCompanyCore\$f"
  if (Test-Path $src) { Copy-Item $src "$core\Sources\OPCCompanyCore\" }
}
# Vendored CSQLite (spike #2: Windows has no system SQLite3 module; the logic
# files fall back to `import CSQLite` there). Copy the amalgamation in and
# link it unconditionally — this package only ever builds on Windows.
New-Item -ItemType Directory -Force -Path "$core\Sources\CSQLite" | Out-Null
Copy-Item "Sources\CSQLite\sqlite3.c" "$core\Sources\CSQLite\"
Copy-Item "Sources\CSQLite\include" "$core\Sources\CSQLite\include" -Recurse
@'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OPCCompanyCore",
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
    targets: [
        .target(name: "CSQLite", path: "Sources/CSQLite", publicHeadersPath: "include"),
        .target(name: "OPCCompanyCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .target(name: "CSQLite")],
            path: "Sources/OPCCompanyCore")]
)
'@ | Set-Content "$core\Package.swift"

Push-Location $core
swift build 2>&1 | Tee-Object -FilePath (Join-Path $root "spike-core-log.txt")
Pop-Location

# ---------- Error census ----------
Write-Host "`n=== Error census ==="
$log = ""
if (Test-Path spike-core-log.txt) { $log += (Get-Content spike-core-log.txt -Raw) }
if (Test-Path spike-full-log.txt)  { $log += "`n" + (Get-Content spike-full-log.txt -Raw) }
$patterns = @{
  "missing-module-SwiftUI"   = "no such module 'SwiftUI'"
  "missing-module-Combine"   = "no such module 'Combine'"
  "missing-module-SpriteKit" = "no such module 'SpriteKit'"
  "missing-module-AppKit"    = "no such module 'AppKit'"
  "missing-module-Security"  = "no such module 'Security'"
  "missing-module-CryptoKit" = "no such module 'CryptoKit'"
  "missing-module-SQLite3"   = "no such module 'SQLite3'"
  "missing-module-ObjC"      = "no such module 'ObjectiveC'"
  "cannot-find-type"         = "cannot find type|cannot find '[A-Z]"
  "unsupported-api"          = "is unavailable|unavailable in macOS|not supported on this platform"
  "linker-error"             = "linker command failed|LNK[0-9]+"
  "other-error"              = "error:"
}
$census = [ordered]@{}
foreach ($k in $patterns.Keys) {
  $census[$k] = ([regex]::Matches($log, $patterns[$k])).Count
}
$census["total-error-lines"] = ([regex]::Matches($log, "error:")).Count
$census.GetEnumerator() | ForEach-Object { Write-Host ("{0,-26} {1}" -f $_.Key, $_.Value) }
$census | ConvertTo-Json | Set-Content spike-census.json
Write-Host "`nArtifacts: spike-full-log.txt spike-core-log.txt spike-census.json"
# Honest step status: succeed if the build COMPLETED (the port milestone), or
# if the census reached real module errors (data for the next shim round).
# Fail only when neither holds — everything still stdlib-load failure = env
# problem, not data.
$buildOk = $log -match "Build complete"
$realModules = ($census["missing-module-SwiftUI"] + $census["missing-module-Combine"] + $census["missing-module-SpriteKit"] + $census["missing-module-AppKit"] + $census["missing-module-Security"] + $census["missing-module-CryptoKit"] + $census["missing-module-SQLite3"] + $census["cannot-find-type"])
if ($buildOk) {
  Write-Host "SPIKE MILESTONE: logic package BUILT on Windows (errors: $($census['total-error-lines']))"
} elseif ($realModules -eq 0) {
  Write-Host "NO REAL MODULE CENSUS — build never reached compilation (env problem). Failing step."
  exit 1
}
