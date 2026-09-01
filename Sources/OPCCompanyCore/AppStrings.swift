import Foundation

/// Central bilingual string table with a registry of per-module tables.
/// Keys are stable identifiers; lookups fall back zh -> en -> key so a missing
/// entry degrades gracefully.
///
/// Conventions:
/// - View layer: `@Environment(\.appLanguage)` + `"key".tr(lang)`.
/// - Store/generated layer: `AppStrings.tr(key, AppStrings.sessionLanguage)`.
/// - `zh` table entries MUST be byte-identical to the original Chinese copy so
///   Chinese-mode output (and the existing test suite) never changes.
public enum AppStrings {

    /// Language used for store-generated strings (briefs, log markers, summaries).
    /// Deterministic under XCTest (forced Chinese) so the 444-test suite stays green.
    /// Mutations happen on the main thread (menu action); enum reads are benign.
    nonisolated(unsafe) public static var sessionLanguage: AppLanguage = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return .simplifiedChinese }
        if let forced = env["OPC_FORCE_LANGUAGE"], let lang = AppLanguage(rawValue: forced) {
            return lang
        }
        if let raw = UserDefaults.standard.string(forKey: "opc.appLanguage.v1"),
           let lang = AppLanguage(rawValue: raw) {
            return lang.resolving()
        }
        return .simplifiedChinese
    }()

    /// Module tables registered for lookup (core first, later tables win per key
    /// only if earlier tables miss the key).
    static var tables: [(zh: [String: String], en: [String: String])] {
        [core, StringsTableV1.tables, StringsTableV2.tables, StringsTableV3.tables, StringsTableStore.tables]
    }

    /// Resolve a key for the given language. `.system` resolves via locale.
    public static func tr(_ key: String, _ language: AppLanguage) -> String {
        let effective = language.resolving()
        switch effective {
        case .english:
            for table in tables where table.en[key] != nil { return table.en[key]! }
            for table in tables where table.zh[key] != nil { return table.zh[key]! }
            return key
        case .simplifiedChinese:
            for table in tables where table.zh[key] != nil { return table.zh[key]! }
            for table in tables where table.en[key] != nil { return table.en[key]! }
            return key
        case .system:
            return key
        }
    }

    /// Formatted variant using %@ / %ld templates.
    public static func tr(_ key: String, _ language: AppLanguage, _ args: CVarArg...) -> String {
        String(format: tr(key, language), arguments: args)
    }

    // MARK: - Core table (app shell + add-employee sheet)

    static let core: (zh: [String: String], en: [String: String]) = (
        [
            // App shell
            "app.name": "OPC 公司",
            "app.name.full": "OPC 公司 / OPC Company",
            "menu.newEmployee": "新增员工",
            "menu.sendCTOBrief": "发送 CTO 状态简报",
            "menu.language": "界面语言 / Language",
            "menu.file": "文件",
            "menu.help": "帮助",

            // Add Employee sheet
            "addEmployee.title": "新增智能员工",
            "addEmployee.subtitle": "创建一个由订阅制命令行、接口模型或本地占位来源驱动的新角色。",
            "a11y.closePanel": "关闭添加员工面板",
            "a11y.closePanel.hint": "关闭弹窗，放弃当前未保存的员工配置。",
            "section.identity": "身份",
            "section.modelSource": "模型来源",
            "section.appearance": "外观",
            "section.permissions": "权限",
            "field.displayName": "显示名称",
            "field.title": "职位名称",
            "field.role": "角色",
            "field.source": "来源",
            "field.endpoint": "接口地址，例如 https://api.openai.com/v1",
            "field.apiKey": "接口密钥",
            "field.model": "模型，例如 gpt-5.5、deepseek-chat",
            "field.modelGeneric": "模型",
            "field.reasoningEffort": "推理强度",
            "field.command": "命令",
            "field.placeholderID": "占位标识",
            "field.ethnicity": "人种/外观",
            "field.gender": "性别",
            "field.clothing": "服装",
            "hint.apiKey": "接口密钥会作为运行环境变量传给接口运行器，不会显示在终端运行摘要里。",
            "hint.cli": "订阅制命令行员工可以创建，但要真正运行，本机必须已经安装对应命令行工具，并且你已经在终端完成登录授权。",
            "hint.local": "本地占位适合老板、人类角色或暂不执行终端任务的角色。",
            "error.endpointRequired": "接口模式必须填写接口地址。",
            "error.apiKeyRequired": "接口模式必须填写接口密钥。",
            "error.modelRequired": "接口模式必须填写模型名称。",
            "error.commandRequired": "订阅制命令行模式必须填写命令，例如 codex、claude、gemini。",
            "common.cancel": "取消",
            "button.addEmployee": "新增员工",
        ],
        [
            // App shell
            "app.name": "OPC Company",
            "app.name.full": "OPC Company",
            "menu.newEmployee": "Add Employee",
            "menu.sendCTOBrief": "Send CTO Status Brief",
            "menu.language": "界面语言 / Language",
            "menu.file": "File",
            "menu.help": "Help",

            // Add Employee sheet
            "addEmployee.title": "New AI Employee",
            "addEmployee.subtitle": "Create a new role driven by subscription CLIs, API models, or a local placeholder.",
            "a11y.closePanel": "Close add-employee panel",
            "a11y.closePanel.hint": "Close the dialog and discard the unsaved employee configuration.",
            "section.identity": "Identity",
            "section.modelSource": "Model Source",
            "section.appearance": "Appearance",
            "section.permissions": "Permissions",
            "field.displayName": "Display Name",
            "field.title": "Job Title",
            "field.role": "Role",
            "field.source": "Source",
            "field.endpoint": "Endpoint, e.g. https://api.openai.com/v1",
            "field.apiKey": "API Key",
            "field.model": "Model, e.g. gpt-5.5, deepseek-chat",
            "field.modelGeneric": "Model",
            "field.reasoningEffort": "Reasoning Effort",
            "field.command": "Command",
            "field.placeholderID": "Placeholder ID",
            "field.ethnicity": "Ethnicity & Look",
            "field.gender": "Gender",
            "field.clothing": "Clothing",
            "hint.apiKey": "The API key is passed to the API runner as an environment variable and is never shown in terminal summaries.",
            "hint.cli": "CLI employees can be created, but to actually run, the CLI must be installed locally and you must be logged in from your terminal.",
            "hint.local": "Local placeholders suit the boss, human roles, or roles that do not run terminal tasks yet.",
            "error.endpointRequired": "API mode requires an endpoint.",
            "error.apiKeyRequired": "API mode requires an API key.",
            "error.modelRequired": "API mode requires a model name.",
            "error.commandRequired": "CLI mode requires a command, e.g. codex, claude, gemini.",
            "common.cancel": "Cancel",
            "button.addEmployee": "Add Employee",
        ]
    )
}

extension String {
    /// Convenience lookup: `"key".tr(lang)`.
    public func tr(_ language: AppLanguage) -> String {
        AppStrings.tr(self, language)
    }
}
