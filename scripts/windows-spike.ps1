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
  'Models.swift','CompanyStore.swift','CompanyPersistence.swift','KeychainStore.swift','ObservationCompat.swift','AgentMessageDisplay.swift','StringExtras.swift','DPAPISecretStore.swift',
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
New-Item -ItemType Directory -Force -Path "$core\Sources\spikeprobe" | Out-Null
# DPAPI runtime probe (issue #11): compiling the headers proves nothing —
# protect→ciphertext-on-disk→unprotect→delete must actually RUN on Windows.
Set-Content "$core\Sources\spikeprobe\main.swift" @'
import Foundation
import OPCCompanyCore

let account = UUID().uuidString
let store = OPCDPAPISecretStore()
let secret = "OPC-DPAPI-PROBE-NOT-A-REAL-KEY"
let save = store.saveSecret(secret, account: account)
print("probe-save:\(save.isSuccess)")
print("probe-load-match:\(store.loadSecret(account: account) == secret)")
let blob = CompanyPersistence.supportDirectory
    .appendingPathComponent("secrets").appendingPathComponent(account + ".blob")
if let raw = try? Data(contentsOf: blob) {
    print("probe-ciphertext-on-disk:\(!raw.contains(Data(secret.utf8)))")
} else {
    print("probe-blob-missing:false")
}
store.deleteSecret(account: account)
let gone = store.loadSecret(account: account)
print("probe-delete:\(gone.isEmpty)")
'@
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
# DPAPI header shim (issue #11): per-user CryptProtectData secret store.
New-Item -ItemType Directory -Force -Path "$core\Sources\CWinDPAPI" | Out-Null
Copy-Item "Sources\CWinDPAPI\dpapi_shim.c" "$core\Sources\CWinDPAPI\"
Copy-Item "Sources\CWinDPAPI\include" "$core\Sources\CWinDPAPI\include" -Recurse
@'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OPCCompanyCore",
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
    targets: [
        .target(name: "CSQLite", path: "Sources/CSQLite", publicHeadersPath: "include"),
        .target(name: "CWinDPAPI", path: "Sources/CWinDPAPI", publicHeadersPath: "include"),
        .target(name: "OPCCompanyCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .target(name: "CSQLite"),
                .target(name: "CWinDPAPI")],
            path: "Sources/OPCCompanyCore",
            linkerSettings: [.linkedLibrary("crypt32")]),
        .executableTarget(name: "spikeprobe",
            dependencies: [.target(name: "OPCCompanyCore")],
            path: "Sources/spikeprobe",
            linkerSettings: [.linkedLibrary("crypt32")])]
)
'@ | Set-Content "$core\Package.swift"

Push-Location $core
swift build 2>&1 | Tee-Object -FilePath (Join-Path $root "spike-core-log.txt")
# Probe run: isolated support dir via the app's own documented override hook.
$env:OPC_COMPANY_SUPPORT_DIR = Join-Path $root "probe-support"
swift run spikeprobe 2>&1 | Tee-Object -FilePath (Join-Path $root "spike-probe-log.txt")
Remove-Item Env:OPC_COMPANY_SUPPORT_DIR
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
Write-Host "`nArtifacts: spike-full-log.txt spike-core-log.txt spike-probe-log.txt spike-census.json"
# Honest step status. Spike #7 lesson: the old gate could be satisfied by
# FULL-package noise (UI files are supposed to fail — M3 scope) while the
# CORE logic package or the DPAPI probe was broken. Separate the signals:
#   coreErrors  = error: lines from the logic-only build
#   probeOk     = all four DPAPI runtime lines green on real Windows
#   MILESTONE   = coreErrors == 0 AND probeOk  → print + exit 0
#   otherwise   = real core data present → exit 0 (next shim round gets it)
#                 but a silent env failure (no data at all) → exit 1
$coreLog = ""
if (Test-Path spike-core-log.txt) { $coreLog += (Get-Content spike-core-log.txt -Raw) }
$coreErrorCount = ([regex]::Matches($coreLog, "error:")).Count
$census["core-error-lines"] = $coreErrorCount
$probeLog = ""
if (Test-Path spike-probe-log.txt) { $probeLog += (Get-Content spike-probe-log.txt -Raw) }
$probeLines = @{ "probe-save" = $false; "probe-load-match" = $false;
                 "probe-ciphertext-on-disk" = $false; "probe-delete" = $false }
foreach ($pl in $probeLines.Keys) {
  $probeLines[$pl] = ($probeLog -match ($pl + ":True"))
}
$probeOk = -not ($probeLines.Values -contains $false)
Write-Host "DPAPI probe all-green: $probeOk (core errors: $coreErrorCount)"
$census | ConvertTo-Json | Set-Content spike-census.json
if ($coreErrorCount -eq 0 -and $probeOk) {
  Write-Host "SPIKE MILESTONE: logic package builds CLEAN on Windows + DPAPI runtime verified"
  exit 0
}
$realModules = ($census["missing-module-SwiftUI"] + $census["missing-module-Combine"] + $census["missing-module-SpriteKit"] + $census["missing-module-AppKit"] + $census["missing-module-Security"] + $census["missing-module-CryptoKit"] + $census["missing-module-SQLite3"] + $census["cannot-find-type"])
if ($coreErrorCount -gt 0 -or $realModules -gt 0) {
  Write-Host "milestone NOT met, but real core/census data collected for the next round"
  exit 0
}
Write-Host "NO REAL DATA — build never reached compilation (env problem). Failing step."
exit 1
