import SwiftUI
import OPCCompanyCore

@main
struct OPCCompanyApp: App {
    @StateObject private var store = CompanyStore.bootstrap()
    @StateObject private var l10n = L10nEnvironment.shared

    private var lang: AppLanguage { l10n.language }
    private var resolved: AppLanguage { lang.resolving() }

    init() {
        L10nBundleOverride.install()
        L10nBundleOverride.select(L10nEnvironment.shared.language)
        AppStrings.sessionLanguage = L10nEnvironment.shared.language.resolving()
    }

    var body: some Scene {
        WindowGroup("app.name.full".tr(lang)) {
            ContentView()
                .environmentObject(store)
                .environment(\.appLanguage, resolved)
                // Force a full view-tree rebuild on language change so every
                // Text() re-resolves through the swizzled bundle lookup.
                .id(resolved)
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
                    let r = newValue.resolving()
                    L10nBundleOverride.select(newValue)
                    AppStrings.sessionLanguage = r
                }
            }
        }
    }
}
