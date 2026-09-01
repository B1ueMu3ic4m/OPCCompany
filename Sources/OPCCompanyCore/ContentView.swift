import SwiftUI
import SpriteKit
import AppKit

public struct ContentView: View {
    @EnvironmentObject private var store: CompanyStore

    public init() {}

    public var body: some View {
        ZStack {
            AppShellBackdrop()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                AgentRosterView()
                    .frame(width: 300)

                AppShellDivider()

                MainWorkspaceView()
                    .frame(minWidth: 640)

                AppShellDivider()

                InspectorPanel()
                    .frame(width: 392)
            }
        }
        .sheet(isPresented: $store.isAddingEmployee) {
            AddEmployeeSheet()
                .environmentObject(store)
                .frame(width: 520, height: 620)
        }
    }
}

struct MainWorkspaceView: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        ZStack {
            MainWorkspaceBackdrop()

            VStack(spacing: 0) {
                WorkspaceNavigationBar()

                ShellHairline()

                switch store.mainWorkspace {
                case .commandCenter:
                    CommandCenterView()
                case .productDetail:
                    ProductDetailWorkspace()
                case .agentDesk:
                    AgentDeskWorkspace()
                case .office:
                    CompanySceneHost()
                case .workflow:
                    WorkflowMapView()
                case .terminalHall:
                    TerminalHallView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await Task.yield()
            store.startRuntimeSupervisorIfNeeded()
        }
    }
}

struct WorkspaceNavigationBar: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        HStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(MainWorkspace.workNavigationCases) { workspace in
                        WorkspaceToolbarButton(
                            title: workspace.title,
                            systemImage: icon(for: workspace),
                            isSelected: store.mainWorkspace == workspace
                        ) {
                            store.mainWorkspace = workspace
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            CompanySceneToolbarButton()

            if store.mainWorkspace == .terminalHall {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.runningAgentIDs.isEmpty ? CompanyTheme.muted : CompanyTheme.accent)
                        .frame(width: 7, height: 7)
                        .shadow(color: store.runningAgentIDs.isEmpty ? .clear : CompanyTheme.accent.opacity(0.36), radius: 4)
                    Text("\(store.runningAgentIDs.count)" + " 运行中".L())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.runningAgentIDs.isEmpty ? CompanyTheme.muted : CompanyTheme.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(CompanyTheme.secondaryPanel.opacity(0.54), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CompanyTheme.border.opacity(0.36), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CompanyTheme.panel
                .overlay(
                    LinearGradient(
                        colors: [
                                CompanyTheme.selected.opacity(0.020),
                                .clear,
                                CompanyTheme.blue.opacity(0.012)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(CompanyTheme.ink.opacity(0.055))
                            .frame(height: 0.5)
                    }
                )
        )
    }

    private func icon(for workspace: MainWorkspace) -> String {
        switch workspace {
        case .commandCenter: "speedometer"
        case .productDetail: "folder.fill"
        case .agentDesk: "person.crop.rectangle.stack.fill"
        case .office: "building.2.fill"
        case .workflow: "point.3.connected.trianglepath.dotted"
        case .terminalHall: "terminal.fill"
        }
    }
}

struct CompanySceneToolbarButton: View {
    @EnvironmentObject private var store: CompanyStore

    private var isSelected: Bool {
        store.mainWorkspace == .office
    }

    var body: some View {
        Button {
            store.mainWorkspace = .office
        } label: {
            Label("公司场景".L(), systemImage: "building.2.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CompanyTheme.selectedDeep)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    LinearGradient(
                        colors: [
                            CompanyTheme.selected,
                            CompanyTheme.selectedStroke
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CompanyTheme.ink.opacity(isSelected ? 0.34 : 0.16), lineWidth: 0.8)
                )
                .shadow(color: CompanyTheme.selectionGlow.opacity(isSelected ? 0.34 : 0.18), radius: isSelected ? 12 : 8, y: 4)
        }
        .buttonStyle(.plain)
        .help("打开公司场景".L())
    }
}

enum CompanyTheme {
    static let background = hex(0x06080B)
    static let selected = hex(0xD8C79A)
    static let selectedDeep = hex(0x211F18)
    static let selectedStroke = hex(0xBAAA7A)
    static let selectionGlow = hex(0xD2C18E)
    static let surface = hex(0x121821)
    static let surfaceRaised = hex(0x18202A)
    static let surfaceSunken = hex(0x070A0E)
    static let inputSurface = hex(0x070A0E)
    static let inputBorder = hex(0x2A3440)
    static let rosterSurface = hex(0x0A0907)
    static let rosterItem = hex(0x11151C)
    static let rosterItemSelected = hex(0x17150F)
    static let inspectorSurface = hex(0x09080D)
    static let inspectorPanel = hex(0x11131B)
    static let chatUserBubble = hex(0x2B2215)
    static let chatAgentBubble = hex(0x121A25)
    static let chatSystemBubble = hex(0x0E1A1E)
    static let officeBoss = hex(0x211821)
    static let officeBossBorder = hex(0x7D526D)
    static let officeCTO = hex(0x14212A)
    static let officeCTOBorder = hex(0x3F7186)
    static let officeStaff = hex(0x111820)
    static let officeStaffBorder = hex(0x2F4350)
    static let officeCore = hex(0x111722)
    static let workspace = hex(0x0A0F14)
    static let workspaceAbyss = hex(0x06080B)
    static let workspaceTint = hex(0x0D1516)
    static let sidebarWarm = hex(0x100D07)
    static let inspectorViolet = hex(0x100B15)
    static let sidebar = rosterSurface
    static let inspector = inspectorSurface
    static let panel = surface
    static let secondaryPanel = surfaceRaised
    static let panelRaised = hex(0x202632)
    static let floatingPanel = hex(0x262D3A)
    static let border = hex(0x2A3440)
    static let officeFloor = hex(0x0A0F14)
    static let ink = hex(0xEEF2F6)
    static let secondaryInk = hex(0xB7C0CC)
    static let muted = hex(0x7A8492)
    static let accent = hex(0x5F8FE8)
    static let blue = hex(0x63C7D4)
    static let green = hex(0x5CCB8A)
    static let warning = hex(0xD49A4A)
    static let purple = hex(0xA78BFA)
    static let red = hex(0xE06C75)
    static let terminalBackground = hex(0x0B0D10)
    static let terminalInk = hex(0xEEF2F6)
    static let line = border.opacity(0.72)

    private static func hex(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

struct AppShellBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.020, green: 0.021, blue: 0.024),
                    CompanyTheme.background,
                    Color(red: 0.006, green: 0.007, blue: 0.008)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let grid: CGFloat = 54
                ZStack {
                    Path { path in
                        var x: CGFloat = 0
                        while x <= proxy.size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                            x += grid
                        }

                        var y: CGFloat = 0
                        while y <= proxy.size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            y += grid
                        }
                    }
                    .stroke(CompanyTheme.ink.opacity(0.003), lineWidth: 0.5)

                    Path { path in
                        let dot: CGFloat = 1.2
                        let spacing: CGFloat = 28
                        var y: CGFloat = 12
                        var row = 0
                        while y <= proxy.size.height {
                            var x: CGFloat = 10
                            var column = 0
                            while x <= proxy.size.width {
                                if (row * 7 + column * 11).isMultiple(of: 5) {
                                    path.addRect(CGRect(x: x, y: y, width: dot, height: dot))
                                }
                                x += spacing
                                column += 1
                            }
                            y += spacing
                            row += 1
                        }
                    }
                    .fill(CompanyTheme.ink.opacity(0.003))
                }
            }
        }
    }
}

struct MainWorkspaceBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CompanyTheme.workspaceTint.opacity(0.62),
                    CompanyTheme.workspace,
                    CompanyTheme.workspaceAbyss
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    CompanyTheme.blue.opacity(0.032),
                    CompanyTheme.workspaceTint.opacity(0.014),
                    .clear
                ],
                center: UnitPoint(x: 0.44, y: 0.34),
                startRadius: 60,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    CompanyTheme.selected.opacity(0.018),
                    .clear
                ],
                center: UnitPoint(x: 0.78, y: 0.18),
                startRadius: 80,
                endRadius: 760
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.22),
                    .clear,
                    .black.opacity(0.30)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct AppShellDivider: View {
    var body: some View {
        Rectangle()
            .fill(CompanyTheme.line)
            .frame(width: 0.5)
    }
}

struct ShellHairline: View {
    var body: some View {
        Rectangle()
            .fill(CompanyTheme.line)
            .frame(height: 0.5)
    }
}

struct WorkspaceToolbarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                if isSelected {
                    Rectangle()
                        .fill(CompanyTheme.selected.opacity(0.72))
                        .frame(height: 1)
                        .shadow(color: CompanyTheme.selectionGlow.opacity(0.30), radius: 5, y: 1)
                }

                HStack(spacing: 7) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 15)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isSelected {
                    Circle()
                        .fill(CompanyTheme.selected.opacity(0.86))
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 28)
                }
            }
            .foregroundStyle(isSelected ? CompanyTheme.selected : CompanyTheme.secondaryInk)
            .frame(width: 116, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CompanyTheme.selectedDeep.opacity(0.72) : CompanyTheme.surfaceSunken.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? CompanyTheme.selectedStroke.opacity(0.45) : CompanyTheme.border.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.18) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct SectionHeader: View {
    var title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(CompanyTheme.muted)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CompanyTheme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CompanyTheme.secondaryPanel.opacity(0.70), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(CompanyTheme.border.opacity(0.72), lineWidth: 0.7)
                    )
            }
        }
    }
}

struct AgentRosterView: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("OPC 公司".L())
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(CompanyTheme.ink)
                Text("公司办公室与工作区".L())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CompanyTheme.accent)
            }
            .padding(.top, 20)

            HStack {
                Text("产品工作区".L())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(CompanyTheme.muted)
                Spacer()
                Button {
                    importExistingProject()
                } label: {
                    Label("导入".L(), systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CompanyTheme.blue)
                Button {
                    store.addProductWorkspace()
                } label: {
                    Label("新增".L(), systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CompanyTheme.accent)
            }

            ProductWorkspaceList()

            SectionHeader(title: "员工".L(), actionTitle: "新增".L()) {
                store.isAddingEmployee = true
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.agents) { agent in
                        AgentRosterRow(agent: agent, isSelected: agent.id == store.selectedAgentID)
                            .onTapGesture {
                                store.selectAgent(agent.id)
                            }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .background(
            CompanyTheme.sidebar
                .overlay(
                    LinearGradient(
                        colors: [
                            CompanyTheme.sidebarWarm.opacity(0.42),
                            CompanyTheme.rosterSurface,
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [
                            CompanyTheme.selected.opacity(0.060),
                            .clear
                        ],
                        center: UnitPoint(x: 0.08, y: 0.08),
                        startRadius: 18,
                        endRadius: 310
                    )
                )
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            .clear,
                            CompanyTheme.selected.opacity(0.085),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 1)
                }
        )
    }

    private func importExistingProject() {
        let panel = NSOpenPanel()
        panel.title = "导入现有产品项目".L()
        panel.message = "选择已经在开发的项目根目录。OPC 会读取本地规则、记忆和项目文件线索。".L()
        panel.prompt = "导入项目".L()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            store.importProductWorkspace(from: url)
        }
    }
}

struct CompanySceneEntryButton: View {
    @EnvironmentObject private var store: CompanyStore

    private var isSelected: Bool {
        store.mainWorkspace == .office
    }

    var body: some View {
        Button {
            store.mainWorkspace = .office
        } label: {
            ZStack(alignment: .leading) {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(isSelected ? CompanyTheme.selected : CompanyTheme.blue.opacity(0.34))
                        .frame(width: 2, height: 46)
                        .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.28) : .clear, radius: 5)

                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? CompanyTheme.selectedDeep.opacity(0.58) : CompanyTheme.secondaryPanel.opacity(0.72))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(CompanyTheme.ink.opacity(isSelected ? 0.06 : 0.035), lineWidth: 0.5)
                            )
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(isSelected ? CompanyTheme.selected : CompanyTheme.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OPC 公司办公室".L())
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(CompanyTheme.ink)
                        Text("公司总览".L())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? CompanyTheme.selected : CompanyTheme.secondaryInk)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "smallcircle.filled.circle" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? CompanyTheme.selected : CompanyTheme.muted)
                }
                .padding(.horizontal, 11)
            }
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? CompanyTheme.rosterItemSelected.opacity(0.94) : CompanyTheme.rosterItem)
                    .overlay(
                        LinearGradient(
                            colors: [
                                isSelected ? CompanyTheme.selected.opacity(0.11) : CompanyTheme.ink.opacity(0.018),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CompanyTheme.selectedStroke.opacity(0.48) : CompanyTheme.border.opacity(0.34), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.18) : .black.opacity(0.14), radius: isSelected ? 12 : 8, y: 5)
        }
        .buttonStyle(.plain)
        .help("打开公司场景总览".L())
    }
}

struct ProductWorkspaceList: View {
    @EnvironmentObject private var store: CompanyStore
    @State private var pendingDeletion: ProductDeletionRequest?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.products) { product in
                ProductWorkspaceRow(product: product, isSelected: product.id == store.selectedProductID)
                    .onTapGesture {
                        store.selectProduct(product.id)
                    }
                    .contextMenu {
                        Button("删除产品".L(), role: .destructive) {
                            pendingDeletion = ProductDeletionRequest(product: product)
                        }
                        .disabled(store.products.count <= 1)
                    }
            }
        }
        .confirmationDialog(
            "确认删除产品".L(),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { newValue in if !newValue { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { request in
            Button("永久删除「" + "\(request.productName)" + "」".L(), role: .destructive) {
                store.deleteProduct(request.productID)
                pendingDeletion = nil
            }
            Button("取消".L(), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { request in
            Text("将永久移除「".L() + "\(request.productName)" + "」及其全部任务、审批、记忆与交付物，操作无法撤销。".L())
        }
    }
}

struct ProductWorkspaceRow: View {
    @EnvironmentObject private var store: CompanyStore
    let product: ProductWorkspace
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(isSelected ? CompanyTheme.selected : statusColor.opacity(0.42))
                .frame(width: 2, height: 36)
                .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.24) : .clear, radius: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CompanyTheme.selectedDeep.opacity(0.58) : CompanyTheme.panel.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? CompanyTheme.selectedStroke.opacity(0.22) : CompanyTheme.border.opacity(0.40), lineWidth: 0.5)
                    )
                Text(product.shortName.prefix(3).uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? CompanyTheme.selected : CompanyTheme.blue)
            }
            .frame(width: 36, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CompanyTheme.ink)
                    .lineLimit(1)
                Text(product.stage.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CompanyTheme.secondaryInk)
                    .lineLimit(1)
                Text(teamLine)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? CompanyTheme.selected.opacity(0.86) : CompanyTheme.muted)
                    .lineLimit(1)
                if let report = product.importReport {
                    Text(importLine(for: report))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(CompanyTheme.muted.opacity(0.78))
                        .lineLimit(1)
                }
            }

            Spacer()

            StatusPill(text: product.status.title, color: statusColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? CompanyTheme.rosterItemSelected.opacity(0.92) : CompanyTheme.rosterItem)
                .overlay(
                    LinearGradient(
                        colors: [
                            isSelected ? CompanyTheme.selected.opacity(0.10) : CompanyTheme.ink.opacity(0.014),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? CompanyTheme.selectedStroke.opacity(0.46) : CompanyTheme.border.opacity(0.34), lineWidth: 0.5)
        )
        .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.16) : .clear, radius: 10, y: 4)
    }

    private var statusColor: Color {
        switch product.status {
        case .active: CompanyTheme.accent
        case .paused: CompanyTheme.muted
        case .archived: CompanyTheme.red.opacity(0.75)
        }
    }

    private var teamLine: String {
        let count = product.assignedAgentIDs.count
        let lead = product.teamLeadAgentID.flatMap { id in
            store.agents.first { $0.id == id }?.displayName
        } ?? "未设负责人".L()
        return "团队 ".L() + "\(count)" + " 人 · ".L() + "\(lead)"
    }

    private func importLine(for report: ProjectImportReport) -> String {
        let tools = report.detectedTools.isEmpty ? "本地项目".L() : report.detectedTools.joined(separator: "+")
        return "\(tools) · \(URL(fileURLWithPath: report.rootDirectory).lastPathComponent)"
    }
}

struct AgentRosterRow: View {
    let agent: CompanyAgent
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(isSelected ? CompanyTheme.selected : statusColor.opacity(0.42))
                .frame(width: 2, height: 42)
                .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.28) : .clear, radius: 5)
            CharacterBadge(agent: agent, size: 44, isSelected: isSelected)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CompanyTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    StatusPill(text: agent.status.title, color: statusColor)
                }
                Text(agent.title)
                    .font(.system(size: 12))
                    .foregroundStyle(CompanyTheme.secondaryInk)
                    .lineLimit(1)
                Text(opcBackendCompactDisplay(type: agent.backend.type, command: agent.backend.command, model: agent.backend.model))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(CompanyTheme.muted.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? CompanyTheme.rosterItemSelected.opacity(0.94) : CompanyTheme.rosterItem)
                .overlay(
                    LinearGradient(
                        colors: [
                            isSelected ? CompanyTheme.selected.opacity(0.12) : CompanyTheme.ink.opacity(0.014),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? CompanyTheme.selectedStroke.opacity(0.48) : CompanyTheme.border.opacity(0.34), lineWidth: 0.5)
        )
        .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.18) : .clear, radius: 11, y: 4)
    }

    private var statusColor: Color {
        switch agent.status {
        case .idle: CompanyTheme.muted
        case .thinking, .talking, .typing: CompanyTheme.blue
        case .coding, .reviewing: CompanyTheme.accent
        case .blocked, .failed: CompanyTheme.red
        case .waitingApproval: CompanyTheme.warning
        case .done: CompanyTheme.green
        }
    }
}

enum PixelAnimation {
    static func frame(for date: Date, status: AgentStatus, salt: Int = 0) -> Int {
        characterFrame(for: date, status: status, salt: salt)
    }

    static func characterFrame(for date: Date, status: AgentStatus, salt: Int = 0) -> Int {
        frame(for: date, interval: characterInterval(for: status), salt: salt, frameCount: 8)
    }

    static func selectionFrame(for date: Date, salt: Int = 0) -> Int {
        frame(for: date, interval: 1.85 / 3.0, salt: salt, frameCount: 3)
    }

    static func statusFrame(for date: Date, status: AgentStatus, salt: Int = 0) -> Int {
        frame(for: date, interval: statusInterval(for: status), salt: salt, frameCount: 8)
    }

    private static func characterInterval(for status: AgentStatus) -> TimeInterval {
        switch status {
        case .idle:
            return 1.35
        case .thinking, .talking:
            return 0.58
        case .typing, .coding:
            return 0.34
        case .reviewing:
            return 0.50
        case .waitingApproval:
            return 0.72
        case .blocked, .failed:
            return 0.90
        case .done:
            return 1.10
        }
    }

    private static func statusInterval(for status: AgentStatus) -> TimeInterval {
        switch status {
        case .idle:
            return 2.40
        case .thinking, .talking:
            return 0.72
        case .typing, .coding:
            return 0.42
        case .reviewing:
            return 0.64
        case .waitingApproval:
            return 0.90
        case .blocked, .failed:
            return 0.58
        case .done:
            return 2.00
        }
    }

    private static func frame(for date: Date, interval: TimeInterval, salt: Int, frameCount: Int) -> Int {
        let rawFrame = Int(date.timeIntervalSinceReferenceDate / interval)
        return (rawFrame + abs(salt % frameCount)) % frameCount
    }
}

struct CharacterBadge: View {
    let agent: CompanyAgent
    let size: CGFloat
    var isSelected = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let characterFrame = PixelAnimation.characterFrame(for: timeline.date, status: agent.status, salt: agent.id.hashValue)
            let statusFrame = PixelAnimation.statusFrame(for: timeline.date, status: agent.status, salt: agent.id.hashValue / 7)

            Canvas { context, canvasSize in
                let unit = min(canvasSize.width, canvasSize.height) / 48
                for rect in pixelRects(characterFrame: characterFrame, statusFrame: statusFrame) {
                    context.fill(
                        Path(CGRect(
                            x: rect.x * unit,
                            y: rect.y * unit,
                            width: rect.width * unit,
                            height: rect.height * unit
                        ).integral),
                        with: .color(rect.color)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.34) : statusColor.opacity(agent.status == .idle ? 0.10 : 0.32), radius: isSelected ? 10 : 8)
    }

    private func pixelRects(characterFrame: Int, statusFrame: Int) -> [PixelRect] {
        let palette = PixelCharacterPalette(agent: agent, accent: statusColor)
        let accent = statusColor
        let frameColor = isSelected ? CompanyTheme.selected : accent
        let bob = headOffset(frame: characterFrame)
        let blinkHeight = blinkHeight(frame: characterFrame)
        let armLift = armOffset(frame: characterFrame)

        var rects: [PixelRect] = [
            PixelRect(6, 43, 32, 3, Color.black.opacity(0.34)),
            PixelRect(7, 37, 30, 6, isSelected ? CompanyTheme.selectedDeep.opacity(0.18) : CompanyTheme.panel.opacity(0.08)),
            PixelRect(8, 41, 28, 1, frameColor.opacity(isSelected ? 0.28 : 0.10)),

            PixelRect(20, 33, 4, 9, Palette.leg),
            PixelRect(28, 33, 4, 9, Palette.leg),
            PixelRect(18, 24, 17, 13, Palette.outline),
            PixelRect(19, 25, 15, 12, palette.clothing),
            PixelRect(25, 25, 3, 10, palette.clothingLight.opacity(0.82)),
            PixelRect(18, 31 + armLift, 4, 3, palette.clothingDark),
            PixelRect(16, 32 + armLift, 3, 3, palette.skinShadow),
            PixelRect(33, 31 - armLift, 4, 3, palette.clothingDark),
            PixelRect(37, 32 - armLift, 3, 3, palette.skinShadow),

            PixelRect(19, 11 + bob, 17, 14, Palette.outline),
            PixelRect(20, 12 + bob, 15, 13, palette.skin),
            PixelRect(19, 10 + bob, 17, 5, palette.hair),
            PixelRect(18, 14 + bob, 3, 5, palette.hair),
            PixelRect(34, 14 + bob, 3, 5, palette.hair),
            PixelRect(23, 18 + bob, 2, blinkHeight, Palette.eye),
            PixelRect(30, 18 + bob, 2, blinkHeight, Palette.eye),
            PixelRect(25, 22 + bob, mouthWidth(frame: characterFrame), 1, Palette.mouth),

            PixelRect(36, 3, 9, 9, Palette.outline),
            PixelRect(37, 4, 7, 7, frameColor.opacity(statusPointOpacity(frame: statusFrame)))
        ]

        rects.append(contentsOf: statusBadgePixels(frame: statusFrame))
        return rects
    }

    private var statusColor: Color {
        switch agent.status {
        case .idle: CompanyTheme.muted
        case .thinking, .talking, .typing: CompanyTheme.blue
        case .coding, .reviewing: CompanyTheme.accent
        case .blocked, .failed: CompanyTheme.red
        case .waitingApproval: CompanyTheme.warning
        case .done: CompanyTheme.green
        }
    }

    private func statusBadgePixels(frame: Int) -> [PixelRect] {
        switch agent.status {
        case .thinking, .talking:
            return [
                PixelRect(38, 6 + CGFloat(frame % 3), 1, 1, CompanyTheme.ink.opacity(0.92)),
                PixelRect(40, 5 + CGFloat((frame + 1) % 3), 1, 1, CompanyTheme.ink.opacity(0.82)),
                PixelRect(42, 6 + CGFloat((frame + 2) % 3), 1, 1, CompanyTheme.ink.opacity(0.72))
            ]
        case .typing, .coding:
            let offset = CGFloat(frame % 3)
            return [
                PixelRect(38, 6, 5 + offset, 1, CompanyTheme.background.opacity(0.72)),
                PixelRect(38, 8, 3 + CGFloat((frame + 1) % 4), 1, CompanyTheme.background.opacity(0.64))
            ]
        case .reviewing:
            let ok = frame.isMultiple(of: 2)
            return ok ? [
                PixelRect(38, 8, 2, 2, CompanyTheme.background.opacity(0.78)),
                PixelRect(40, 9, 2, 2, CompanyTheme.background.opacity(0.78)),
                PixelRect(42, 6, 1, 3, CompanyTheme.background.opacity(0.78))
            ] : [
                PixelRect(38, 6, 5, 1, CompanyTheme.background.opacity(0.78)),
                PixelRect(40, 5, 1, 5, CompanyTheme.background.opacity(0.78))
            ]
        case .blocked, .failed:
            return [
                PixelRect(40, 5, 1, 4, CompanyTheme.background.opacity(frame.isMultiple(of: 2) ? 0.90 : 0.38)),
                PixelRect(40, 10, 1, 1, CompanyTheme.background.opacity(frame.isMultiple(of: 2) ? 0.90 : 0.38))
            ]
        case .waitingApproval:
            return [
                PixelRect(38, 5 + CGFloat(frame % 2), 2, 5, CompanyTheme.background.opacity(0.74)),
                PixelRect(42, 5 + CGFloat((frame + 1) % 2), 1, 5, CompanyTheme.background.opacity(0.74))
            ]
        case .done:
            return [
                PixelRect(38, 8, 2, 2, CompanyTheme.background.opacity(0.78)),
                PixelRect(40, 9, 2, 2, CompanyTheme.background.opacity(0.78)),
                PixelRect(42, 6, 1, 3, CompanyTheme.background.opacity(frame.isMultiple(of: 2) ? 0.90 : 0.58))
            ]
        case .idle:
            return [PixelRect(39, 7, 3, 1, CompanyTheme.background.opacity(0.56))]
        }
    }

    private func headOffset(frame: Int) -> CGFloat {
        switch agent.status {
        case .idle:
            return frame.isMultiple(of: 2) ? 0 : -1
        case .thinking:
            return frame.isMultiple(of: 2) ? -1 : 1
        case .coding, .typing:
            return frame % 3 == 0 ? 1 : 0
        case .blocked, .failed:
            return frame.isMultiple(of: 2) ? 2 : 0
        case .done:
            return frame.isMultiple(of: 2) ? -1 : 0
        default:
            return 0
        }
    }

    private func blinkHeight(frame: Int) -> CGFloat {
        switch agent.status {
        case .idle:
            return frame % 4 == 1 ? 1 : 2
        case .thinking:
            return frame % 4 == 1 ? 1 : 2
        default:
            return 2
        }
    }

    private func statusPointOpacity(frame: Int) -> Double {
        if agent.status == .idle {
            return frame.isMultiple(of: 2) ? 0.28 : 0.42
        }
        return 0.96
    }

    private func armOffset(frame: Int) -> CGFloat {
        switch agent.status {
        case .coding, .typing:
            return frame.isMultiple(of: 2) ? -2 : 2
        case .waitingApproval:
            return frame.isMultiple(of: 2) ? -6 : -3
        case .blocked, .failed:
            return frame.isMultiple(of: 2) ? 3 : 0
        default:
            return 0
        }
    }

    private func mouthWidth(frame: Int) -> CGFloat {
        switch agent.status {
        case .done:
            return 5
        case .blocked, .failed:
            return frame.isMultiple(of: 2) ? 5 : 3
        default:
            return 3
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct StatusDot: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(status.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.28), lineWidth: 0.7)
        )
    }

    private var color: Color {
        switch status {
        case .idle: CompanyTheme.muted
        case .thinking, .talking, .typing: CompanyTheme.blue
        case .coding, .reviewing: CompanyTheme.accent
        case .blocked, .failed: CompanyTheme.red
        case .waitingApproval: CompanyTheme.warning
        case .done: CompanyTheme.green
        }
    }
}
