import SwiftUI
import OPCCompanyCore

@main
struct OPCCompanyApp: App {
    @StateObject private var store = CompanyStore.bootstrap()

    var body: some Scene {
        WindowGroup("OPC 公司") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新增员工") {
                    store.isAddingEmployee = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("发送 CTO 状态简报") {
                    store.sendSystemBriefToCTO()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
