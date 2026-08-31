import SwiftUI

struct AddEmployeeSheet: View {
    @EnvironmentObject private var store: CompanyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新增智能员工")
                        .font(.system(size: 24, weight: .heavy, design: .serif))
                        .foregroundStyle(CompanyTheme.ink)
                    Text("创建一个由订阅制命令行、接口模型或本地占位来源驱动的新角色。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CompanyTheme.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭添加员工面板")
                .accessibilityHint("关闭弹窗，放弃当前未保存的员工配置。")
            }
            .padding(20)
            .background(CompanyTheme.panel)

            Divider().overlay(CompanyTheme.line)

            Form {
                Section("身份") {
                    TextField("显示名称", text: $store.draftEmployee.displayName)
                    TextField("职位名称", text: $store.draftEmployee.title)
                    Picker("角色", selection: $store.draftEmployee.role) {
                        ForEach(AgentRole.allCases.filter { $0 != .boss }) { role in
                            Text(role.title).tag(role)
                        }
                    }
                }

                Section("模型来源") {
                    Picker("来源", selection: $store.draftEmployee.backendType) {
                        ForEach(BackendType.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .onChange(of: store.draftEmployee.backendType) { _, newValue in
                        applyBackendDefaults(newValue)
                    }

                    if store.draftEmployee.backendType == .api {
                        TextField("接口地址，例如 https://api.openai.com/v1", text: $store.draftEmployee.endpoint)
                        SecureField("接口密钥", text: $store.draftEmployee.apiKey)
                        TextField("模型，例如 gpt-5.5、deepseek-chat", text: $store.draftEmployee.model)
                        Picker("推理强度", selection: $store.draftEmployee.reasoningEffort) {
                            ForEach(ReasoningEffort.allCases) { effort in
                                Text(effort.title).tag(effort)
                            }
                        }
                        Text("接口密钥会作为运行环境变量传给接口运行器，不会显示在终端运行摘要里。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                    } else if store.draftEmployee.backendType == .subscriptionCLI {
                        TextField("命令", text: $store.draftEmployee.command)
                        TextField("模型", text: $store.draftEmployee.model)
                        Picker("推理强度", selection: $store.draftEmployee.reasoningEffort) {
                            ForEach(ReasoningEffort.allCases) { effort in
                                Text(effort.title).tag(effort)
                            }
                        }
                        Text("订阅制命令行员工可以创建，但要真正运行，本机必须已经安装对应命令行工具，并且你已经在终端完成登录授权。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                    } else {
                        TextField("占位标识", text: $store.draftEmployee.model)
                        Text("本地占位适合老板、人类角色或暂不执行终端任务的角色。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CompanyTheme.muted)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CompanyTheme.red)
                    }
                }

                Section("外观") {
                    Picker("人种/外观", selection: $store.draftEmployee.ethnicity) {
                        ForEach(EthnicityPresentation.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("性别", selection: $store.draftEmployee.gender) {
                        ForEach(GenderPresentation.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("服装", selection: $store.draftEmployee.clothing) {
                        ForEach(ClothingStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                Section("权限") {
                    ForEach(AgentPermission.allCases) { permission in
                        Toggle(permission.title, isOn: Binding(
                            get: { store.draftEmployee.permissions.contains(permission) },
                            set: { enabled in
                                if enabled {
                                    store.draftEmployee.permissions.insert(permission)
                                } else {
                                    store.draftEmployee.permissions.remove(permission)
                                }
                            }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(CompanyTheme.background)

            Divider().overlay(CompanyTheme.line)

            HStack {
                Button("取消") {
                    dismiss()
                }
                Spacer()
                Button {
                    store.addEmployee(from: store.draftEmployee)
                    dismiss()
                } label: {
                    Label("新增员工", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(validationMessage != nil)
                .buttonStyle(.borderedProminent)
                .tint(CompanyTheme.accent)
            }
            .padding(16)
            .background(CompanyTheme.panel)
        }
        .background(CompanyTheme.background)
    }

    private var validationMessage: String? {
        let draft = store.draftEmployee
        switch draft.backendType {
        case .api:
            if draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "接口模式必须填写接口地址。"
            }
            if draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "接口模式必须填写接口密钥。"
            }
            if draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "接口模式必须填写模型名称。"
            }
        case .subscriptionCLI:
            if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "订阅制命令行模式必须填写命令，例如 codex、claude、gemini。"
            }
        case .local:
            break
        }
        return nil
    }

    private func applyBackendDefaults(_ backend: BackendType) {
        switch backend {
        case .api:
            store.draftEmployee.command = "api-agent"
            if store.draftEmployee.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.draftEmployee.model == "sonnet"
                || store.draftEmployee.model == "gemini-cli"
                || store.draftEmployee.model == "local" {
                store.draftEmployee.model = "gpt-5.5"
            }
            store.draftEmployee.permissions.insert(.useNetwork)
        case .subscriptionCLI:
            if store.draftEmployee.command == "api-agent" || store.draftEmployee.command.isEmpty {
                store.draftEmployee.command = "claude"
            }
            if store.draftEmployee.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.draftEmployee.model == "gpt-5.5"
                || store.draftEmployee.model == "local" {
                store.draftEmployee.model = "sonnet"
            }
        case .local:
            store.draftEmployee.command = "local"
            if store.draftEmployee.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || store.draftEmployee.model == "sonnet"
                || store.draftEmployee.model == "gpt-5.5"
                || store.draftEmployee.model == "gemini-cli" {
                store.draftEmployee.model = "local"
            }
        }
    }
}
