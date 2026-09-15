import Foundation

// ═══════════════════════════════════════════════════════════════════════
// M0 / issue #9 — the ONE process-launch seam of the portable core.
//
// Before this file, `Process()` was hand-rolled in 5 places across 3 files
// with platform-sensitive details (PATH probing, /dev/null, sandbox-exec,
// SIGTERM→SIGKILL escalation) scattered among them. On Windows, CLI agents
// ship as npm `.cmd` shims which CreateProcess cannot launch directly —
// that translation, plus PATHEXT probing and `NUL`, lives here once.
//
// Sealed by a guard test: no `Process()` construction outside this file
// (Sources/OPCCompanyCore). Behavior on macOS is byte-compatible with the
// previous AgentProcessRunner/CompanyStore helpers — same error strings,
// same drain order, same exit-code conventions (127 spawn-failed,
// 124 timed-out).
//
// Public surface note: `AgentProcessRunner` keeps its API (the GUI layer
// and 29 tests call it) and forwards here.
// ═══════════════════════════════════════════════════════════════════════

// LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-BUFFER（角色继承期轮 30 标记）：
// `@unchecked Sendable` 在此**不是技术债** —— class 用 NSLock 同步 mutable state，
// 是「程序员承诺 thread-safe，编译器看不到 lock 语义」的正确 Sendable 声明模式。
// 添加新字段时**必须**同时把读写都包进 lock.lock()/unlock() 块，否则破坏 Sendable contract。
// 守门测试 `processOutputBufferUncheckedSendableCarriesLockProtectionMarker` 防止此标记被误删。
// 候选 ω-sendable Swift 6 升级路径（codex 决定级）：将 NSLock 替换为 Swift 6 `Mutex<(String, String)>`
// 让 Sendable 自动推断；但 Mutex 需要 macOS 15+ 部署目标，本项目 macOS 14 baseline 暂保持 NSLock。
private final class ProcessOutputBuffer: @unchecked Sendable {
    private var standardOutput = ""
    private var standardError = ""
    private let lock = NSLock()

    func append(_ text: String, isError: Bool) {
        lock.lock()
        if isError {
            standardError.append(text)
        } else {
            standardOutput.append(text)
        }
        lock.unlock()
    }

    func snapshot() -> (output: String, error: String) {
        lock.lock()
        let output = standardOutput
        let error = standardError
        lock.unlock()
        return (output, error)
    }
}

// LIMITATION-UNCHECKED-SENDABLE-LOCK-PROTECTED-FLAG（角色继承期轮 30 标记）：
// 同 ProcessOutputBuffer：用 NSLock 保护单 Bool 标志位，`@unchecked Sendable` 是正确声明。
// 添加新字段（如 timeoutReason / wallClockMs）时必须沿用 lock.lock()/unlock() 模式。
// 守门测试 `processTimeoutStateUncheckedSendableCarriesLockProtectionMarker` 防止此标记被误删。
// 候选 ω-sendable Swift 6 升级路径（codex 决定级）：将 NSLock 替换为 `Mutex<Bool>` 让 Sendable
// 自动推断；macOS 14 baseline 暂保持 NSLock。
private final class ProcessTimeoutState: @unchecked Sendable {
    private var timedOut = false
    private let lock = NSLock()

    var didTimeout: Bool {
        lock.lock()
        let value = timedOut
        lock.unlock()
        return value
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }
}

/// Result of the synchronous helpers (tmux plumbing, git worktree, pgrep).
/// `output` is stdout+stderr joined by "\n" (empty parts dropped) — exactly
/// the shape CompanyStore's old runLocalProcess returned.
struct OPCProcessRunResult: Sendable {
    var exitCode: Int32
    var output: String
}

enum OPCProcessRunner {

    // ── executable resolution ───────────────────────────────────────────

    /// Launchability probe. Windows: extension-carrying batch/exe files are
    /// "executable" even without the POSIX bit — isExecutableFile is not a
    /// reliable probe there, existence is (the extension list gates what we
    /// pick during search).
    static func probeExecutableFile(_ path: String) -> Bool {
        #if os(Windows)
        return FileManager.default.fileExists(atPath: path)
        #else
        return FileManager.default.isExecutableFile(atPath: path)
        #endif
    }

    static func resolveExecutable(_ executable: String) -> String {
        if executable.contains("/") || (executable.contains("\\")) {
            return NSString(string: executable).expandingTildeInPath
        }
        return searchPaths(for: executable).first { probeExecutableFile($0) } ?? executable
    }

    static func resolvedExecutablePath(for executable: String) -> String? {
        let resolved = resolveExecutable(executable)
        return probeExecutableFile(resolved) ? resolved : nil
    }

    static func searchPaths(for executable: String) -> [String] {
        #if os(Windows)
        // npm/bun shims land in %APPDATA%\npm etc.; PATHEXT decides which
        // suffixes are actually launchable ("claude" alone is not — the
        // shim is claude.cmd).
        let env = ProcessInfo.processInfo.environment
        var dirs = (env["PATH"] ?? "")
            .split(whereSeparator: { $0 == ";" })
            .map(String.init)
        if let appData = env["APPDATA"] { dirs.append("\(appData)\\npm") }
        if let user = env["USERPROFILE"] { dirs.append("\(user)\\.bun\\bin") }
        let exts = (env["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD")
            .split(whereSeparator: { $0 == ";" || $0 == ":" })
            .map { $0.lowercased() }
        return dirs.flatMap { dir in
            exts.map { ext in "\(dir)\\\(executable)\(ext)" }
        }
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathValues = [
            "\(home)/.npm-global/bin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        return pathValues.map { "\($0)/\(executable)" }
        #endif
    }

    // ── Windows batch-file translation (the #9 crux) ──────────────────

    /// True when a resolved path is a cmd.exe batch script — the shape
    /// every npm-installed CLI agent (claude.cmd, codex.cmd…) ships as on
    /// Windows. CreateProcess refuses these; only cmd /c runs them.
    static func isWindowsBatchScript(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "cmd" || ext == "bat"
    }

    /// CommandLineToArgvW-compatible quoting wrapped in outer quotes: the
    /// standard way to hand one argument through cmd.exe's parser AND the
    /// target's argv parser without double-decoding mangling it.
    /// (Pure string logic — compiled and unit-tested on every platform.)
    static func windowsQuoteArgument(_ argument: String) -> String {
        var out = "\""
        var backslashes = 0
        for ch in argument {
            switch ch {
            case "\\":
                backslashes += 1
            case "\"":
                out += String(repeating: "\\", count: backslashes * 2 + 1)
                out.append("\"")
                backslashes = 0
            default:
                if backslashes > 0 {
                    out += String(repeating: "\\", count: backslashes)
                    backslashes = 0
                }
                out.append(ch)
            }
        }
        if backslashes > 0 {
            // trailing backslashes must double up before the closing quote
            out += String(repeating: "\\", count: backslashes * 2)
        }
        out += "\""
        return out
    }

    /// Wrap a batch launch as `cmd /d /s /c "<target> <quoted args…>"`.
    /// /d disables AutoRun, /s keeps cmd from stripping the outer quotes.
    static func windowsBatchLaunch(scriptPath: String, arguments: [String], environment: [String: String]) -> (executable: String, arguments: [String]) {
        let cmdExe = environment["COMSPEC"] ?? "C:\\Windows\\System32\\cmd.exe"
        var inner = windowsQuoteArgument(scriptPath)
        for arg in arguments {
            inner += " " + windowsQuoteArgument(arg)
        }
        return (cmdExe, ["/d", "/s", "/c", inner])
    }

    // ── environment ───────────────────────────────────────────────────

    static func mergedEnvironment(overrides: [String: String] = [:], isolatedHome: URL? = nil) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var environment = ProcessInfo.processInfo.environment
        #if os(Windows)
        let appPath = environment["PATH"] ?? "C:\\Windows\\System32"
        let sep = ";"
        var extra: [String] = []
        if let appData = environment["APPDATA"] { extra.append("\(appData)\\npm") }
        if let user = environment["USERPROFILE"] { extra.append("\(user)\\.bun\\bin") }
        #else
        let appPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let sep = ":"
        let homeDirs = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = [
            "\(homeDirs)/.npm-global/bin",
            "\(homeDirs)/.local/bin",
            "\(homeDirs)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        #endif
        environment["PATH"] = (extra + [appPath]).joined(separator: sep)
        if let isolatedHome {
            let homePath = isolatedHome.path
            environment["HOME"] = homePath
            environment["XDG_CONFIG_HOME"] = "\(homePath)/.opc/env/config"
            environment["XDG_CACHE_HOME"] = "\(homePath)/.opc/env/cache"
            environment["XDG_DATA_HOME"] = "\(homePath)/.opc/env/data"
        } else {
            environment["HOME"] = home
        }
        for (key, value) in overrides where !value.isEmpty {
            environment[key] = value
        }
        return environment
    }

    // ── async streaming engine (the ex-AgentProcessRunner body) ───────

    static func runStreaming(command: [String], workingDirectory: URL?, environmentOverrides: [String: String] = [:], isolatedHome: URL? = nil, sandboxProfile: String? = nil, timeoutSeconds: TimeInterval? = nil, terminationGraceSeconds: TimeInterval = 2, onOutput: @escaping @Sendable (String) -> Void) async -> CommandExecutionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var launchCommand = command
                if let sandboxProfile {
                    let sandboxExecutable = "/usr/bin/sandbox-exec"
                    guard FileManager.default.isExecutableFile(atPath: sandboxExecutable) else {
                        let error = "严格沙盒不可用：当前系统没有可执行的 sandbox-exec。".L().L()
                        onOutput(error)
                        continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error))
                        return
                    }
                    launchCommand = [sandboxExecutable, "-p", sandboxProfile] + command
                }

                guard let executable = launchCommand.first else {
                    let error = "没有提供命令。".L().L()
                    onOutput(error)
                    continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error))
                    return
                }

                let resolvedExecutable = resolveExecutable(executable)
                guard probeExecutableFile(resolvedExecutable) else {
                    let searched = searchPaths(for: executable).joined(separator: "\n- ")
                    let error = """
                    \("找不到可执行命令：".L())\(executable)

                    \("这通常是因为从 macOS 应用启动时 PATH 不包含你的终端环境。".L())
                    \("已搜索：".L())
                    - \(searched)

                    \("请确认命令行工具已安装并可执行，或在员工模型来源里填完整路径。".L())
                    """
                    onOutput(error)
                    continuation.resume(returning: CommandExecutionResult(
                        exitCode: 127,
                        standardOutput: "",
                        standardError: error
                    ))
                    return
                }

                // Windows: npm-shipped agents resolve to *.cmd shims; CreateProcess
                // cannot exec those, so route them through cmd /c exactly once.
                var launchExecutable = resolvedExecutable
                var launchArguments = Array(launchCommand.dropFirst())
                #if os(Windows)
                if isWindowsBatchScript(resolvedExecutable) {
                    let wrapped = windowsBatchLaunch(
                        scriptPath: resolvedExecutable,
                        arguments: launchArguments,
                        environment: mergedEnvironment(overrides: environmentOverrides, isolatedHome: isolatedHome))
                    launchExecutable = wrapped.executable
                    launchArguments = wrapped.arguments
                }
                #endif

                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchExecutable)
                process.arguments = launchArguments
                process.currentDirectoryURL = workingDirectory
                process.environment = mergedEnvironment(overrides: environmentOverrides, isolatedHome: isolatedHome)

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                #if os(Windows)
                let nullDevice = FileHandle(forReadingAtPath: "NUL")
                #else
                let nullDevice = FileHandle(forReadingAtPath: "/dev/null")
                #endif
                process.standardInput = nullDevice
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let outputBuffer = ProcessOutputBuffer()
                let timeoutState = ProcessTimeoutState()

                let appendOutput: @Sendable (Data, Bool) -> Void = { data, isError in
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                    outputBuffer.append(text, isError: isError)
                    onOutput(text)
                }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    appendOutput(handle.availableData, false)
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    appendOutput(handle.availableData, true)
                }

                do {
                    try process.run()
                    if let timeoutSeconds, timeoutSeconds > 0 {
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                            guard process.isRunning else { return }
                            timeoutState.markTimedOut()
                            let message = "\n命令超时：".L() + "\(Int(timeoutSeconds))" + " 秒内没有返回，OPC 已停止这次调用。\n".L()
                            outputBuffer.append(message, isError: true)
                            onOutput(message)
                            process.terminate()
                            // SIGTERM→SIGKILL 升级：被 `trap '' TERM` 屏蔽或卡在不可中断系统调用的子进程
                            // 不会响应 process.terminate()，waitUntilExit 将永远挂起，导致整个 await
                            // 永不返回。grace 后再用 Darwin kill(pid, SIGKILL) 强制结束，保证调用方
                            // 一定能拿到 124 退出。pid 在 isRunning 为真时取，被 reuse 的概率可忽略。
                            let pid = process.processIdentifier
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(terminationGraceSeconds, 0)) {
                                guard process.isRunning else { return }
                                let killMessage = "\n命令在 SIGTERM 后仍在运行，已升级到 SIGKILL 强制结束。\n".L().L()
                                outputBuffer.append(killMessage, isError: true)
                                onOutput(killMessage)
                                #if canImport(Darwin) || canImport(Glibc)
                                kill(pid, SIGKILL)
                                #else
                                // Windows has no POSIX signals; Foundation's
                                // Process.terminate() there maps to
                                // TerminateProcess — an immediate hard kill
                                // that a child cannot trap, which is exactly
                                // what the SIGKILL escalation means.
                                process.terminate()
                                #endif
                            }
                        }
                    }
                    process.waitUntilExit()
                    // 子进程退出后，内核管道缓冲区可能仍残留 readabilityHandler 还没分发的尾部数据；
                    // 必须先把 handler 清掉避免与我们的同步 drain 抢同一个 fd，再用 readDataToEndOfFile
                    // 把剩余字节读到 EOF。写端已随子进程关闭，readDataToEndOfFile 不会阻塞。
                    // 缓冲区有 NSLock 保护，即使最后一次 handler 派发与我们的 drain 并发也能安全 append。
                    //
                    // 例外：timeout 升级 SIGKILL 的路径下，被 kill 的是直接子进程，但其孤儿孙进程
                    // 可能还持有 stdout/stderr 管道写端的 dup 副本（macOS pipe EOF 语义要所有写端关闭
                    // 才会发出），这会让 readDataToEndOfFile 一直阻塞到孤儿自己退出 —— 直接抹掉
                    // SIGKILL 升级带来的「短界返回」承诺。timeout 已在 SIGTERM 阶段同步写入中文超时
                    // 消息、在 SIGKILL 阶段同步写入升级诊断消息，超时之后的孤儿尾部输出已无价值，
                    // 所以这条路径上跳过 trailing drain，让调用方立刻拿到 124。
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    if !timeoutState.didTimeout {
                        let trailingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        appendOutput(trailingOutput, false)
                        let trailingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        appendOutput(trailingError, true)
                    }
                    let snapshot = outputBuffer.snapshot()
                    let output = snapshot.output
                    let error = snapshot.error
                    let exitCode: Int32 = timeoutState.didTimeout ? 124 : process.terminationStatus
                    continuation.resume(returning: CommandExecutionResult(exitCode: exitCode, standardOutput: output, standardError: error))
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    onOutput(error.localizedDescription)
                    continuation.resume(returning: CommandExecutionResult(exitCode: 127, standardOutput: "", standardError: error.localizedDescription))
                }
            }
        }
    }

    // ── synchronous helpers (tmux plumbing / git / pgrep) ─────────────

    /// Direct-launch wait (executable path taken verbatim — no PATH probing;
    /// callers pass resolved paths). Inherits the ambient environment, as the
    /// old inline Process() blocks did.
    static func runAndWait(executable: String, arguments: [String], workingDirectory: URL) -> OPCProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            return collectedResult(process: process, outputPipe: outputPipe, errorPipe: errorPipe)
        } catch {
            return OPCProcessRunResult(exitCode: 127, output: error.localizedDescription)
        }
    }

    /// runAndWait + stdin text written & closed immediately. (Same
    /// write-then-wait ordering the persistent-terminal REPL plumbing used;
    /// large outputs beyond one pipe buffer still rely on the child
    /// finishing first — unchanged tradeoff, documented by the old code.)
    static func runAndWaitWithStdin(executable: String, arguments: [String], workingDirectory: URL, stdinText: String) -> OPCProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            if let data = stdinText.data(using: .utf8), !data.isEmpty {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return collectedResult(process: process, outputPipe: outputPipe, errorPipe: errorPipe)
        } catch {
            return OPCProcessRunResult(exitCode: 127, output: error.localizedDescription)
        }
    }

    /// Exit status with both output streams silenced; nil when the binary
    /// could not be launched at all (platform lacks it — e.g. pgrep on
    /// Windows, where callers must treat "unavailable" as "no detection").
    static func runQuietly(executable: String, arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return nil
        }
    }

    private static func collectedResult(process: Process, outputPipe: Pipe, errorPipe: Pipe) -> OPCProcessRunResult {
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return OPCProcessRunResult(exitCode: process.terminationStatus, output: [output, error].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}
