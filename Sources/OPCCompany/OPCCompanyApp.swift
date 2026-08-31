import SwiftUI
import OPCCompanyCore

@main
struct OPCCompanyApp: App {
    @StateObject private var store = CompanyStore.bootstrap()
    @StateObject private var l10n = L10nEnvironment.shared

    private var lang: AppLanguage { l10n.language }

    var body: some Scene {
        WindowGroup("app.name.full".tr(lang)) {
            ContentView()
                .environmentObject(store)
                .environment(\.appLanguage, lang.resolving())
                .environment(\.locale, Locale(identifier: lang.resolving() == .english ? "en" : "zh-Hans"))
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("menu.newEmployee".tr(lang)) {
                    store.isAddingEmployee = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("menu.sendCTOBrief".tr(lang)) {
                    store.sendSystemBriefToCTO()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }

            CommandMenu("menu.language".tr(lang)) {
                Picker("menu.language".tr(lang), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: l10n.language) { _, newValue in
                    AppStrings.sessionLanguage = newValue.resolving()
                }
            }
        }
    }
}
