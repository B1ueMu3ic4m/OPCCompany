import SwiftUI
import SpriteKit

struct CompanySceneHost: View {
    @EnvironmentObject private var store: CompanyStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(OPCVisibleInterfaceCopy.companySceneTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(CompanyTheme.ink)
                    Text(OPCVisibleInterfaceCopy.companySceneSubtitle)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CompanyTheme.secondaryInk.opacity(0.78))
                }
                Spacer()
                if let selected = store.selectedAgent {
                    Label(selected.displayName, systemImage: "scope")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompanyTheme.selected)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(CompanyTheme.secondaryPanel.opacity(0.42), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(CompanyTheme.selectedStroke.opacity(0.20), lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(
                CompanyTheme.workspace
                    .overlay(
                        LinearGradient(
                            colors: [
                                CompanyTheme.blue.opacity(0.035),
                                .clear,
                                CompanyTheme.selected.opacity(0.020)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )

            GeometryReader { proxy in
                ZStack {
                    SpriteView(scene: makeScene(size: proxy.size))
                        .ignoresSafeArea()
                    OfficeOverlay(size: proxy.size)
                }
            }
        }
    }

    private func makeScene(size: CGSize) -> SKScene {
        let scene = OfficeScene()
        scene.employeeCount = store.agents.filter { $0.seat.room == "employee-hall" }.count
        scene.size = size
        scene.scaleMode = .resizeFill
        scene.backgroundColor = NSColor(CompanyTheme.officeFloor)
        return scene
    }
}

final class OfficeScene: SKScene {
    var employeeCount = 0

    override func didMove(to view: SKView) {
        buildScene()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        buildScene()
    }

    private func buildScene() {
        removeAllChildren()
        guard size.width > 10, size.height > 10 else { return }

        let zones = NeuralFloorLayout.zones(for: size)
        addNeuralAtmosphere()
        addMainFloor(zones.mainFloor)
        addFloorDataTracks(zones: zones)
        addSchedulerTable(in: zones.core)
        addExecutiveOffice(
            rect: zones.ctoDeck,
            title: "技术负责人办公室".L(),
            fill: NSColor(CompanyTheme.officeCTO),
            border: NSColor(CompanyTheme.officeCTOBorder),
            accent: NSColor(CompanyTheme.blue),
            side: .left
        )
        addExecutiveOffice(
            rect: zones.bossDeck,
            title: "老板办公室".L(),
            fill: NSColor(CompanyTheme.officeBoss),
            border: NSColor(CompanyTheme.officeBossBorder),
            accent: NSColor(CompanyTheme.selected),
            side: .right
        )
        addEmployeeOffice(in: zones.agentPods, employeeCount: employeeCount)
    }

    private enum OfficeSide {
        case left
        case right
    }

    private func addNeuralAtmosphere() {
        let bandCount = max(9, Int(size.height / 56))
        for index in 0..<bandCount {
            let progress = CGFloat(index) / CGFloat(max(bandCount - 1, 1))
            let rect = CGRect(
                x: 0,
                y: size.height * progress,
                width: size.width,
                height: size.height / CGFloat(bandCount) + 2
            )
            let node = SKShapeNode(rect: rect)
            node.fillColor = NSColor(
                red: 0.020 + 0.007 * Double(progress),
                green: 0.026 + 0.010 * Double(1 - progress),
                blue: 0.030 + 0.010 * Double(1 - abs(progress - 0.45)),
                alpha: 1
            )
            node.strokeColor = .clear
            node.zPosition = -10
            addChild(node)
        }

        let gridPath = CGMutablePath()
        let spacing: CGFloat = 44
        var x: CGFloat = 0
        while x <= size.width {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }

        let grid = SKShapeNode(path: gridPath)
        grid.strokeColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.008)
        grid.lineWidth = 0.55
        grid.zPosition = -8
        addChild(grid)

        addDotMatrix()
        addVignette()
    }

    private func addDotMatrix() {
        let dotSize: CGFloat = 1.2
        let spacing: CGFloat = 34
        var row = 0
        var y: CGFloat = 8
        while y <= size.height {
            var column = 0
            var x: CGFloat = 10
            while x <= size.width {
                if (row * 13 + column * 17).isMultiple(of: 4) {
                    let dot = SKShapeNode(rect: CGRect(x: x, y: y, width: dotSize, height: dotSize))
                    dot.fillColor = NSColor.white.withAlphaComponent(0.007)
                    dot.strokeColor = .clear
                    dot.zPosition = -6
                    addChild(dot)
                }
                x += spacing
                column += 1
            }
            y += spacing
            row += 1
        }
    }

    private func addVignette() {
        let edgeDepth = min(size.width, size.height) * 0.16
        let overlays: [(CGRect, CGFloat)] = [
            (CGRect(x: 0, y: 0, width: size.width, height: edgeDepth), 0.16),
            (CGRect(x: 0, y: size.height - edgeDepth, width: size.width, height: edgeDepth), 0.18),
            (CGRect(x: 0, y: 0, width: edgeDepth, height: size.height), 0.14),
            (CGRect(x: size.width - edgeDepth, y: 0, width: edgeDepth, height: size.height), 0.14)
        ]

        for (rect, alpha) in overlays {
            let node = SKShapeNode(rect: rect)
            node.fillColor = NSColor.black.withAlphaComponent(alpha)
            node.strokeColor = .clear
            node.zPosition = -4
            addChild(node)
        }
    }

    private func addMainFloor(_ rect: CGRect) {
        let shadow = SKShapeNode(rect: rect.insetBy(dx: -16, dy: -18), cornerRadius: 12)
        shadow.fillColor = NSColor.black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        shadow.zPosition = -3.6
        addChild(shadow)

        let base = SKShapeNode(rect: rect, cornerRadius: 9)
        base.fillColor = sceneColor(0x0D1516)
        base.strokeColor = NSColor.white.withAlphaComponent(0.085)
        base.lineWidth = 0.7
        base.zPosition = -3.2
        addChild(base)

        let inner = SKShapeNode(rect: rect.insetBy(dx: 1.2, dy: 1.2), cornerRadius: 8)
        inner.fillColor = .clear
        inner.strokeColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.032)
        inner.lineWidth = 0.55
        inner.zPosition = -3.0
        addChild(inner)

        let bayPath = CGMutablePath()
        let baySpacing: CGFloat = 72
        var x = rect.minX + baySpacing
        while x < rect.maxX - baySpacing / 2 {
            bayPath.move(to: CGPoint(x: x, y: rect.minY + 18))
            bayPath.addLine(to: CGPoint(x: x, y: rect.maxY - 18))
            x += baySpacing
        }
        let bayLines = SKShapeNode(path: bayPath)
        bayLines.strokeColor = NSColor.white.withAlphaComponent(0.018)
        bayLines.lineWidth = 0.45
        bayLines.zPosition = -2.8
        addChild(bayLines)
    }

    private func addSchedulerTable(in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.31

        let floorGlow = SKShapeNode(ellipseIn: CGRect(
            x: center.x - radius * 1.55,
            y: center.y - radius * 0.58,
            width: radius * 3.10,
            height: radius * 1.16
        ))
        floorGlow.fillColor = NSColor(CompanyTheme.accent).withAlphaComponent(0.030)
        floorGlow.strokeColor = NSColor.clear
        floorGlow.zPosition = -1.4
        addChild(floorGlow)

        let base = SKShapeNode(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        base.fillColor = sceneColor(0x151F2A, 0.92)
        base.strokeColor = NSColor.white.withAlphaComponent(0.10)
        base.lineWidth = 0.7
        base.zPosition = -0.2
        addChild(base)

        for index in 0..<3 {
            let ringRadius = radius * (0.48 + CGFloat(index) * 0.20)
            let ring = SKShapeNode(ellipseIn: CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ))
            ring.fillColor = NSColor.clear
            let ringColor = index == 1 ? NSColor(CompanyTheme.selected) : NSColor(CompanyTheme.accent)
            ring.strokeColor = ringColor.withAlphaComponent(index == 0 ? 0.17 : 0.12)
            ring.lineWidth = index == 0 ? 0.9 : 0.7
            ring.zPosition = 0.1
            addChild(ring)
        }

        let core = SKShapeNode(ellipseIn: CGRect(x: center.x - radius * 0.28, y: center.y - radius * 0.28, width: radius * 0.56, height: radius * 0.56))
        core.fillColor = NSColor(CompanyTheme.officeCore).withAlphaComponent(0.86)
        core.strokeColor = NSColor(CompanyTheme.selected).withAlphaComponent(0.20)
        core.lineWidth = 0.7
        core.zPosition = 0.5
        addChild(core)

        let nucleus = SKShapeNode(ellipseIn: CGRect(x: center.x - radius * 0.11, y: center.y - radius * 0.11, width: radius * 0.22, height: radius * 0.22))
        nucleus.fillColor = NSColor(CompanyTheme.selected).withAlphaComponent(0.18)
        nucleus.strokeColor = NSColor(CompanyTheme.accent).withAlphaComponent(0.22)
        nucleus.lineWidth = 0.55
        nucleus.zPosition = 0.8
        addChild(nucleus)

        let title = SKLabelNode(text: "智能调度".L())
        title.fontName = "AvenirNext-DemiBold"
        title.fontSize = 10.5
        title.fontColor = NSColor(CompanyTheme.secondaryInk).withAlphaComponent(0.70)
        title.position = CGPoint(x: center.x, y: center.y - radius * 0.58)
        title.zPosition = 1.0
        addChild(title)
    }

    private func addFloorDataTracks(zones: NeuralFloorZones) {
        let core = CGPoint(x: zones.core.midX, y: zones.core.midY)
        addEmbeddedTrack(from: core, to: CGPoint(x: zones.ctoDeck.midX, y: zones.ctoDeck.minY + 4), color: NSColor(CompanyTheme.blue))
        addEmbeddedTrack(from: core, to: CGPoint(x: zones.bossDeck.midX, y: zones.bossDeck.minY + 4), color: NSColor(CompanyTheme.selected))
        addEmbeddedTrack(from: core, to: CGPoint(x: zones.agentPods.midX, y: zones.agentPods.maxY - 8), color: NSColor(CompanyTheme.accent))
        addEmbeddedTrack(from: CGPoint(x: core.x, y: core.y - zones.core.height * 0.16), to: CGPoint(x: zones.agentPods.minX + zones.agentPods.width * 0.18, y: zones.agentPods.maxY - 18), color: NSColor(CompanyTheme.blue))
    }

    private func addEmbeddedTrack(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let bendY = (start.y + end.y) / 2
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: bendY))
        path.addLine(to: CGPoint(x: end.x, y: bendY))
        path.addLine(to: end)

        let trench = SKShapeNode(path: path)
        trench.strokeColor = NSColor.black.withAlphaComponent(0.18)
        trench.lineWidth = 2.2
        trench.zPosition = -2.2
        addChild(trench)

        let line = SKShapeNode(path: path)
        line.strokeColor = color.withAlphaComponent(0.14)
        line.lineWidth = 0.9
        line.zPosition = -2.0
        addChild(line)
    }

    private func addExecutiveOffice(rect: CGRect, title: String, fill: NSColor, border: NSColor, accent: NSColor, side: OfficeSide) {
        let ambient = SKShapeNode(rect: rect.insetBy(dx: -8, dy: -10), cornerRadius: 8)
        ambient.fillColor = NSColor.black.withAlphaComponent(0.12)
        ambient.strokeColor = .clear
        ambient.zPosition = -1.2
        addChild(ambient)

        let floorPlane = SKShapeNode(rect: CGRect(
            x: rect.minX + 10,
            y: rect.minY + 8,
            width: rect.width - 20,
            height: rect.height * 0.58
        ), cornerRadius: 5)
        floorPlane.fillColor = fill.withAlphaComponent(0.24)
        floorPlane.strokeColor = border.withAlphaComponent(0.24)
        floorPlane.lineWidth = 0.55
        floorPlane.zPosition = -0.8
        addChild(floorPlane)

        let backWall = SKShapeNode(rect: CGRect(
            x: rect.minX + 8,
            y: rect.maxY - rect.height * 0.34,
            width: rect.width - 16,
            height: rect.height * 0.27
        ), cornerRadius: 5)
        backWall.fillColor = fill.withAlphaComponent(0.22)
        backWall.strokeColor = border.withAlphaComponent(0.30)
        backWall.lineWidth = 0.55
        backWall.zPosition = -0.7
        addChild(backWall)

        let sideWallX = side == .left ? rect.minX + 8 : rect.maxX - 26
        let sideWall = SKShapeNode(rect: CGRect(
            x: sideWallX,
            y: rect.minY + 9,
            width: 18,
            height: rect.height - 18
        ), cornerRadius: 4)
        sideWall.fillColor = border.withAlphaComponent(0.18)
        sideWall.strokeColor = border.withAlphaComponent(0.26)
        sideWall.lineWidth = 0.5
        sideWall.zPosition = -0.6
        addChild(sideWall)

        let ceilingLinePath = CGMutablePath()
        ceilingLinePath.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 9))
        ceilingLinePath.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.maxY - 9))
        ceilingLinePath.move(to: CGPoint(x: side == .left ? rect.minX + 10 : rect.maxX - 10, y: rect.minY + 10))
        ceilingLinePath.addLine(to: CGPoint(x: side == .left ? rect.minX + 10 : rect.maxX - 10, y: rect.maxY - 10))
        let glassEdges = SKShapeNode(path: ceilingLinePath)
        glassEdges.strokeColor = NSColor.white.withAlphaComponent(0.16)
        glassEdges.lineWidth = 0.5
        glassEdges.zPosition = 0.1
        addChild(glassEdges)

        let header = SKShapeNode(rect: CGRect(x: rect.minX + 24, y: rect.maxY - 29, width: rect.width - 48, height: 1.2), cornerRadius: 0.6)
        header.fillColor = accent.withAlphaComponent(0.28)
        header.strokeColor = .clear
        header.zPosition = 0.2
        addChild(header)

        let locatorX = side == .left ? rect.minX + 13 : rect.maxX - 15
        let accentBar = SKShapeNode(rect: CGRect(x: locatorX, y: rect.minY + 20, width: 1.4, height: rect.height - 56), cornerRadius: 0.7)
        accentBar.fillColor = accent.withAlphaComponent(0.24)
        accentBar.strokeColor = .clear
        accentBar.zPosition = 1
        addChild(accentBar)

        let label = SKLabelNode(text: title)
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 12
        label.fontColor = NSColor(CompanyTheme.ink).withAlphaComponent(0.80)
        label.horizontalAlignmentMode = side == .left ? .left : .right
        label.position = CGPoint(
            x: side == .left ? rect.minX + 28 : rect.maxX - 28,
            y: rect.maxY - 23
        )
        label.zPosition = 2
        addChild(label)

        let boardWidth = rect.width * 0.32
        let boardRect = CGRect(
            x: side == .left ? rect.maxX - boardWidth - 30 : rect.minX + 30,
            y: rect.maxY - rect.height * 0.56,
            width: boardWidth,
            height: max(28, rect.height * 0.24)
        )
        let board = SKShapeNode(rect: boardRect, cornerRadius: 4)
        board.fillColor = NSColor(CompanyTheme.officeCore).withAlphaComponent(0.62)
        board.strokeColor = border.withAlphaComponent(0.30)
        board.lineWidth = 0.55
        board.zPosition = 1
        addChild(board)

        for index in 0..<3 {
            let lineWidth = boardRect.width * (0.70 - CGFloat(index) * 0.12)
            let line = SKShapeNode(rect: CGRect(
                x: boardRect.minX + 10,
                y: boardRect.maxY - 12 - CGFloat(index) * 9,
                width: lineWidth,
                height: 2
            ), cornerRadius: 1)
            line.fillColor = index == 0 ? accent.withAlphaComponent(0.38) : NSColor(CompanyTheme.secondaryInk).withAlphaComponent(0.18)
            line.strokeColor = .clear
            line.zPosition = 2
            addChild(line)
        }

        let deskRect = CGRect(
            x: rect.midX - rect.width * 0.26,
            y: rect.minY + rect.height * 0.21,
            width: rect.width * 0.52,
            height: rect.height * 0.20
        )
        let seatShadow = SKShapeNode(ellipseIn: CGRect(x: rect.midX - 38, y: deskRect.minY - 21, width: 76, height: 24))
        seatShadow.fillColor = NSColor.black.withAlphaComponent(0.22)
        seatShadow.strokeColor = .clear
        seatShadow.zPosition = 0.8
        addChild(seatShadow)

        let chairBack = SKShapeNode(rect: CGRect(x: rect.midX - 22, y: deskRect.maxY - 2, width: 44, height: 28), cornerRadius: 6)
        chairBack.fillColor = fill.withAlphaComponent(0.74)
        chairBack.strokeColor = border.withAlphaComponent(0.35)
        chairBack.lineWidth = 0.55
        chairBack.zPosition = 1
        addChild(chairBack)

        let desk = SKShapeNode(rect: deskRect, cornerRadius: 6)
        desk.fillColor = NSColor(CompanyTheme.floatingPanel).withAlphaComponent(0.70)
        desk.strokeColor = border.withAlphaComponent(0.34)
        desk.lineWidth = 0.6
        desk.zPosition = 2
        addChild(desk)

        let deskEdge = SKShapeNode(rect: CGRect(x: deskRect.minX, y: deskRect.maxY - 4, width: deskRect.width, height: 4), cornerRadius: 2)
        deskEdge.fillColor = accent.withAlphaComponent(0.16)
        deskEdge.strokeColor = .clear
        deskEdge.zPosition = 3
        addChild(deskEdge)

        let monitorRect = CGRect(x: rect.midX - 20, y: deskRect.maxY + 5, width: 40, height: 24)
        let monitor = SKShapeNode(rect: monitorRect, cornerRadius: 3)
        monitor.fillColor = NSColor(CompanyTheme.background).withAlphaComponent(0.84)
        monitor.strokeColor = accent.withAlphaComponent(0.26)
        monitor.lineWidth = 0.6
        monitor.zPosition = 3
        addChild(monitor)

        let monitorLine = SKShapeNode(rect: CGRect(x: monitorRect.minX + 8, y: monitorRect.midY, width: monitorRect.width - 16, height: 2), cornerRadius: 1)
        monitorLine.fillColor = accent.withAlphaComponent(0.34)
        monitorLine.strokeColor = .clear
        monitorLine.zPosition = 4
        addChild(monitorLine)

        let keyboard = SKShapeNode(rect: CGRect(x: rect.midX - 26, y: deskRect.maxY - 12, width: 52, height: 5), cornerRadius: 2)
        keyboard.fillColor = NSColor.black.withAlphaComponent(0.30)
        keyboard.strokeColor = .clear
        keyboard.zPosition = 3
        addChild(keyboard)
    }

    private func addEmployeeOffice(in rect: CGRect, employeeCount: Int) {
        let shadow = SKShapeNode(rect: rect.insetBy(dx: -10, dy: -12), cornerRadius: 12)
        shadow.fillColor = NSColor.black.withAlphaComponent(0.20)
        shadow.strokeColor = .clear
        shadow.zPosition = -1.35
        addChild(shadow)

        let base = SKShapeNode(rect: rect, cornerRadius: 7)
        base.fillColor = sceneColor(0x0D1415, 0.42)
        base.strokeColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.13)
        base.lineWidth = 0.85
        base.zPosition = -1.1
        addChild(base)

        let innerFrame = SKShapeNode(rect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 6)
        innerFrame.fillColor = .clear
        innerFrame.strokeColor = NSColor.white.withAlphaComponent(0.055)
        innerFrame.lineWidth = 0.55
        innerFrame.zPosition = -1.0
        addChild(innerFrame)

        let title = SKLabelNode(text: "员工办公区".L())
        title.fontName = "AvenirNext-DemiBold"
        title.fontSize = 10.5
        title.fontColor = NSColor(CompanyTheme.secondaryInk).withAlphaComponent(0.72)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: rect.minX + 14, y: rect.maxY - 18)
        title.zPosition = 2
        addChild(title)

        let centerAisle = SKShapeNode(rect: CGRect(
            x: rect.minX + rect.width * 0.07,
            y: rect.midY - 7,
            width: rect.width * 0.86,
            height: 14
        ), cornerRadius: 7)
        centerAisle.fillColor = sceneColor(0x11191A, 0.50)
        centerAisle.strokeColor = .clear
        centerAisle.zPosition = -0.8
        addChild(centerAisle)

        let aisleLight = SKShapeNode(rect: CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.midY - 0.5,
            width: rect.width * 0.84,
            height: 1
        ), cornerRadius: 0.5)
        aisleLight.fillColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.065)
        aisleLight.strokeColor = NSColor.clear
        aisleLight.zPosition = -0.6
        addChild(aisleLight)

        let dimensions = NeuralFloorLayout.employeeHallGridDimensions(for: employeeCount)
        let footprint = NeuralFloorLayout.employeeHallFootprint(for: employeeCount, in: rect)
        var occupiedSeats: Set<Int> = []
        for index in 0..<employeeCount {
            let seat = NeuralFloorLayout.employeeHallSeat(index: index, count: employeeCount)
            occupiedSeats.insert(seat.row * 100 + seat.column)
        }

        for row in 0..<dimensions.rows {
            let rowPoint = NeuralFloorLayout.employeeHallStationSpritePoint(
                row: row,
                column: max(0, dimensions.columns / 2),
                dimensions: dimensions,
                in: rect
            )
            let islandRect = CGRect(
                x: rect.minX + rect.width * 0.055,
                y: rowPoint.y - footprint.height * 0.34,
                width: rect.width * 0.89,
                height: max(36, footprint.height * 0.50)
            )
            let island = SKShapeNode(rect: islandRect, cornerRadius: 6)
            island.fillColor = sceneColor(0x101819, row.isMultiple(of: 2) ? 0.38 : 0.30)
            island.strokeColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.050)
            island.lineWidth = 0.55
            island.zPosition = -0.7
            addChild(island)

            let islandTrace = SKShapeNode(rect: CGRect(
                x: islandRect.minX + 12,
                y: islandRect.maxY - 5,
                width: islandRect.width - 24,
                height: 1
            ), cornerRadius: 0.5)
            islandTrace.fillColor = NSColor(CompanyTheme.accent).withAlphaComponent(0.075)
            islandTrace.strokeColor = .clear
            islandTrace.zPosition = -0.4
            addChild(islandTrace)
        }

        for row in 0..<dimensions.rows {
            for column in 0..<dimensions.columns {
                let isOccupied = occupiedSeats.contains(row * 100 + column)
                let point = NeuralFloorLayout.employeeHallStationSpritePoint(
                    row: row,
                    column: column,
                    dimensions: dimensions,
                    in: rect
                )
                addEmployeeStation(at: point, footprint: footprint, isOccupied: isOccupied)
            }
        }

        if employeeCount == 0 {
            let empty = SKLabelNode(text: "等待新增员工".L())
            empty.fontName = "AvenirNext-DemiBold"
            empty.fontSize = 10.5
            empty.fontColor = NSColor(CompanyTheme.muted).withAlphaComponent(0.44)
            empty.position = CGPoint(x: rect.midX, y: rect.minY + 22)
            empty.zPosition = 2
            addChild(empty)
        }
    }

    private func addEmployeeStation(at point: CGPoint, footprint: CGSize, isOccupied: Bool) {
        let alpha: CGFloat = isOccupied ? 1.0 : 0.58
        let stationRect = CGRect(
            x: point.x - footprint.width * 0.42,
            y: point.y - footprint.height * 0.30,
            width: footprint.width * 0.84,
            height: footprint.height * 0.50
        )

        let shadow = SKShapeNode(ellipseIn: CGRect(
            x: stationRect.minX + stationRect.width * 0.18,
            y: stationRect.minY - 5,
            width: stationRect.width * 0.64,
            height: max(10, stationRect.height * 0.20)
        ))
        shadow.fillColor = NSColor.black.withAlphaComponent(isOccupied ? 0.20 : 0.14)
        shadow.strokeColor = .clear
        shadow.zPosition = 0
        addChild(shadow)

        let base = SKShapeNode(rect: stationRect, cornerRadius: 4)
        base.fillColor = sceneColor(0x111820, isOccupied ? 0.40 : 0.28)
        base.strokeColor = NSColor.white.withAlphaComponent(isOccupied ? 0.045 : 0.040)
        base.lineWidth = 0.45
        base.zPosition = 0.1
        addChild(base)

        let deskRect = CGRect(
            x: stationRect.minX + stationRect.width * 0.14,
            y: stationRect.minY + stationRect.height * 0.50,
            width: stationRect.width * 0.72,
            height: max(8, stationRect.height * 0.13)
        )
        let desk = SKShapeNode(rect: deskRect, cornerRadius: 2.5)
        desk.fillColor = sceneColor(0x273441, 0.48 * alpha)
        desk.strokeColor = NSColor(CompanyTheme.blue).withAlphaComponent(0.055 * alpha)
        desk.lineWidth = 0.45
        desk.zPosition = 0.6
        addChild(desk)

        let chair = SKShapeNode(rect: CGRect(
            x: stationRect.midX - stationRect.width * 0.12,
            y: deskRect.minY - stationRect.height * 0.20,
            width: stationRect.width * 0.24,
            height: stationRect.height * 0.20
        ), cornerRadius: 3)
        chair.fillColor = sceneColor(0x17212A, 0.62 * alpha)
        chair.strokeColor = .clear
        chair.zPosition = 0.5
        addChild(chair)

        let monitorRect = CGRect(
            x: stationRect.midX - stationRect.width * 0.10,
            y: deskRect.maxY + 3,
            width: stationRect.width * 0.20,
            height: stationRect.height * 0.14
        )
        let monitor = SKShapeNode(rect: monitorRect, cornerRadius: 2)
        monitor.fillColor = NSColor(CompanyTheme.background).withAlphaComponent(0.70 * alpha)
        monitor.strokeColor = NSColor(CompanyTheme.accent).withAlphaComponent(0.12 * alpha)
        monitor.lineWidth = 0.45
        monitor.zPosition = 0.8
        addChild(monitor)

        let signal = SKShapeNode(rect: CGRect(
            x: monitorRect.minX + monitorRect.width * 0.18,
            y: monitorRect.midY - 0.5,
            width: monitorRect.width * 0.64,
            height: 1
        ), cornerRadius: 0.5)
        signal.fillColor = NSColor(CompanyTheme.accent).withAlphaComponent(isOccupied ? 0.28 : 0.10)
        signal.strokeColor = .clear
        signal.zPosition = 0.9
        addChild(signal)
    }

    private func addOrthogonalDataLinks(zones: NeuralFloorZones) {
        let core = CGPoint(x: zones.core.midX, y: zones.core.midY)
        addRightAngleLink(from: CGPoint(x: zones.ctoDeck.midX, y: zones.ctoDeck.minY + 18), to: core, color: NSColor(CompanyTheme.blue))
        addRightAngleLink(from: CGPoint(x: zones.bossDeck.midX, y: zones.bossDeck.minY + 18), to: core, color: NSColor(CompanyTheme.selected))
        addRightAngleLink(from: CGPoint(x: zones.agentPods.midX, y: zones.agentPods.maxY - 18), to: core, color: NSColor(CompanyTheme.officeStaffBorder))
    }

    private func addRightAngleLink(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let midY = (start.y + end.y) / 2
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: midY))
        path.addLine(to: CGPoint(x: end.x, y: midY))
        path.addLine(to: end)

        let line = SKShapeNode(path: path)
        line.strokeColor = color.withAlphaComponent(0.11)
        line.lineWidth = 0.8
        line.zPosition = -0.5
        addChild(line)
    }

    private func rectNode(name: String, rect: CGRect, color: NSColor) -> SKShapeNode {
        let node = SKShapeNode(rect: rect)
        node.name = name
        node.fillColor = color
        node.strokeColor = .clear
        return node
    }
}

struct NeuralFloorZones {
    let mainFloor: CGRect
    let ctoDeck: CGRect
    let bossDeck: CGRect
    let agentPods: CGRect
    let core: CGRect
}

enum NeuralFloorLayout {
    static let employeeRigHeight: CGFloat = PixelWorkstationLayout.rigHeight(isExecutive: false)

    static func zones(for size: CGSize) -> NeuralFloorZones {
        let floor = CGRect(
            x: size.width * 0.06,
            y: size.height * 0.09,
            width: size.width * 0.88,
            height: size.height * 0.82
        )
        let deckWidth = max(190, floor.width * 0.25)
        let deckHeight = min(max(110, floor.height * 0.22), floor.height * 0.25)
        let deckTopInset = floor.height * 0.07
        let deckSideInset = floor.width * 0.055
        let deckY = floor.maxY - deckTopInset - deckHeight
        let employeeHeight = floor.height * 0.55
        let employeeZone = CGRect(
            x: floor.minX + floor.width * 0.055,
            y: floor.minY + floor.height * 0.065,
            width: floor.width * 0.89,
            height: employeeHeight
        )
        let coreSide = min(floor.width * 0.17, floor.height * 0.17)
        let coreMidY = employeeZone.maxY + max(36, (deckY - employeeZone.maxY) * 0.48)
        return NeuralFloorZones(
            mainFloor: floor,
            ctoDeck: CGRect(x: floor.minX + deckSideInset, y: deckY, width: deckWidth, height: deckHeight),
            bossDeck: CGRect(x: floor.maxX - deckSideInset - deckWidth, y: deckY, width: deckWidth, height: deckHeight),
            agentPods: employeeZone,
            core: CGRect(
                x: floor.midX - coreSide / 2,
                y: coreMidY - coreSide / 2,
                width: coreSide,
                height: coreSide
            )
        )
    }

    static func overlayPoint(in rect: CGRect, x: CGFloat, y: CGFloat, canvasHeight: CGFloat) -> CGPoint {
        let spritePoint = CGPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
        return CGPoint(x: spritePoint.x, y: canvasHeight - spritePoint.y)
    }

    static func employeeHallAvatarScale(for count: Int) -> CGFloat {
        switch count {
        case 0...15:
            return 1
        case 16...24:
            return 0.86
        default:
            return 0.78
        }
    }

    static func employeeHallAvatarScale(for count: Int, in rect: CGRect) -> CGFloat {
        guard count > 0 else { return 1 }

        let dimensions = employeeHallGridDimensions(for: count)
        let maxColumns = max(dimensions.columns, 1)
        let rows = max(dimensions.rows, 1)
        let gap = employeeHallGridGap(for: count)
        let baseScale = employeeHallAvatarScale(for: count)
        let rigWidth = PixelWorkstationLayout.rigWidth(isExecutive: false)
        let rigHeight = PixelWorkstationLayout.rigHeight(isExecutive: false)
        let widthFit = (rect.width - CGFloat(maxColumns - 1) * gap) / (CGFloat(maxColumns) * rigWidth)
        let heightFit = (rect.height - CGFloat(rows - 1) * gap) / (CGFloat(rows) * rigHeight)

        return max(0.46, min(baseScale, widthFit, heightFit))
    }

    static func employeeHallStatusClearance(for count: Int, in rect: CGRect) -> CGFloat {
        employeeRigHeight * employeeHallAvatarScale(for: count, in: rect) * 0.30
    }

    static func employeeHallFootprint(for count: Int, in rect: CGRect) -> CGSize {
        let scale = employeeHallAvatarScale(for: count, in: rect)
        return CGSize(
            width: PixelWorkstationLayout.rigWidth(isExecutive: false) * scale,
            height: PixelWorkstationLayout.rigHeight(isExecutive: false) * scale
        )
    }

    static func employeeHallGridPoint(index: Int, count: Int, in rect: CGRect, canvasHeight: CGFloat) -> CGPoint {
        let spritePoint = employeeHallGridSpritePoint(index: index, count: count, in: rect)
        return CGPoint(x: spritePoint.x, y: canvasHeight - spritePoint.y)
    }

    static func employeeHallGridSpritePoint(index: Int, count: Int, in rect: CGRect) -> CGPoint {
        guard count > 0 else {
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        let dimensions = employeeHallGridDimensions(for: count)
        let seat = employeeHallSeat(index: index, count: count)
        return employeeHallStationSpritePoint(row: seat.row, column: seat.column, dimensions: dimensions, in: rect)
    }

    static func employeeHallSeat(index: Int, count: Int) -> (row: Int, column: Int) {
        let dimensions = employeeHallGridDimensions(for: count)
        let rows = dimensions.rows
        let columns = dimensions.columns
        let row = min(index / columns, rows - 1)
        let column = index % columns
        return (row, column)
    }

    static func employeeHallStationSpritePoint(
        row: Int,
        column: Int,
        dimensions: (rows: Int, columns: Int),
        in rect: CGRect
    ) -> CGPoint {
        let rows = max(dimensions.rows, 1)
        let columns = max(dimensions.columns, 1)
        let footprint = employeeHallFootprint(forGridRows: rows, columns: columns, in: rect)
        let gap = employeeHallGridGap(forColumns: columns)
        let totalWidth = CGFloat(columns) * footprint.width + CGFloat(max(columns - 1, 0)) * gap
        let totalHeight = CGFloat(rows) * footprint.height + CGFloat(max(rows - 1, 0)) * gap
        let x = rect.midX - totalWidth / 2 + footprint.width / 2 + CGFloat(column) * (footprint.width + gap)
        let y = rect.midY + totalHeight / 2 - footprint.height / 2 - CGFloat(row) * (footprint.height + gap)

        return CGPoint(
            x: min(max(x, rect.minX + footprint.width / 2), rect.maxX - footprint.width / 2),
            y: min(max(y, rect.minY + footprint.height / 2), rect.maxY - footprint.height / 2)
        )
    }

    static func employeeHallGridDimensions(for count: Int) -> (rows: Int, columns: Int) {
        let visibleCount = max(count, 0)

        let rows: Int
        switch visibleCount {
        case 0...4:
            rows = 1
        case 5...8:
            rows = 2
        case 9...18:
            rows = 3
        default:
            rows = 4
        }
        let visibleSlots = max(visibleCount + 1, rows * 4)
        let columns = Int(ceil(Double(visibleSlots) / Double(rows)))

        return (rows, columns)
    }

    private static func employeeHallGridGap(for count: Int) -> CGFloat {
        let dimensions = employeeHallGridDimensions(for: count)
        return employeeHallGridGap(forColumns: dimensions.columns)
    }

    private static func employeeHallGridGap(forColumns columns: Int) -> CGFloat {
        columns > 8 ? 8 : 14
    }

    private static func employeeHallFootprint(forGridRows rows: Int, columns: Int, in rect: CGRect) -> CGSize {
        let scale = min(
            employeeHallAvatarScale(for: max(rows * columns, 1), in: rect),
            1
        )
        return CGSize(
            width: PixelWorkstationLayout.rigWidth(isExecutive: false) * scale,
            height: PixelWorkstationLayout.rigHeight(isExecutive: false) * scale
        )
    }

    private static func orderedIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let center = CGFloat(count - 1) / 2
        return Array(0..<count).sorted { first, second in
            let firstDistance = abs(CGFloat(first) - center)
            let secondDistance = abs(CGFloat(second) - center)
            if firstDistance == secondDistance {
                return first < second
            }
            return firstDistance < secondDistance
        }
    }
}

private func sceneColor(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

struct OfficeOverlay: View {
    @EnvironmentObject private var store: CompanyStore
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(nonHallAgents) { agent in
                AgentDeskView(agent: agent, isSelected: agent.id == store.selectedAgentID)
                    .position(position(for: agent))
                    .onTapGesture {
                        store.focusAgent(agent.id)
                    }
            }

            ForEach(Array(employeeHallAgents.enumerated()), id: \.element.id) { index, agent in
                AgentDeskView(agent: agent, isSelected: agent.id == store.selectedAgentID)
                    .scaleEffect(employeeHallScale)
                    .position(employeeHallPosition(index: index))
                    .onTapGesture {
                        store.focusAgent(agent.id)
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            ForEach(emptyEmployeeHallSeatIndices, id: \.self) { index in
                EmptyEmployeeSeatHotspot(size: emptySeatHotspotSize)
                    .position(employeeHallPosition(index: index))
                    .onTapGesture {
                        store.isAddingEmployee = true
                    }
                    .help("新增员工".L())
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var employeeHallAgents: [CompanyAgent] {
        store.agents.filter { $0.seat.room == "employee-hall" }
    }

    private var nonHallAgents: [CompanyAgent] {
        store.agents.filter { $0.seat.room != "employee-hall" }
    }

    private func position(for agent: CompanyAgent) -> CGPoint {
        let zones = NeuralFloorLayout.zones(for: size)
        switch agent.seat.room {
        case "cto-office":
            return NeuralFloorLayout.overlayPoint(in: zones.ctoDeck, x: 0.50, y: 0.36, canvasHeight: size.height)
        case "boss-office":
            return NeuralFloorLayout.overlayPoint(in: zones.bossDeck, x: 0.50, y: 0.36, canvasHeight: size.height)
        case "employee-hall":
            return NeuralFloorLayout.overlayPoint(in: zones.agentPods, x: agent.seat.x, y: agent.seat.y, canvasHeight: size.height)
        default:
            return CGPoint(x: size.width * agent.seat.x, y: size.height * (1 - agent.seat.y))
        }
    }

    private func employeeHallPosition(index: Int) -> CGPoint {
        let zones = NeuralFloorLayout.zones(for: size)
        return NeuralFloorLayout.employeeHallGridPoint(
            index: index,
            count: employeeHallAgents.count,
            in: zones.agentPods,
            canvasHeight: size.height
        )
    }

    private var employeeHallScale: CGFloat {
        let zones = NeuralFloorLayout.zones(for: size)
        return NeuralFloorLayout.employeeHallAvatarScale(for: employeeHallAgents.count, in: zones.agentPods)
    }

    private var emptyEmployeeHallSeatIndices: [Int] {
        let count = employeeHallAgents.count
        let dimensions = NeuralFloorLayout.employeeHallGridDimensions(for: count)
        let capacity = max(0, dimensions.rows * dimensions.columns)
        guard capacity > count else { return [] }
        return Array(count..<capacity)
    }

    private var emptySeatHotspotSize: CGSize {
        let zones = NeuralFloorLayout.zones(for: size)
        let footprint = NeuralFloorLayout.employeeHallFootprint(for: employeeHallAgents.count, in: zones.agentPods)
        return CGSize(width: footprint.width * 0.86, height: footprint.height * 0.62)
    }
}

struct EmptyEmployeeSeatHotspot: View {
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(CompanyTheme.surfaceRaised.opacity(0.001))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CompanyTheme.blue.opacity(0.001), lineWidth: 1)
            )
            .frame(width: size.width, height: size.height)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct AgentDeskView: View {
    let agent: CompanyAgent
    let isSelected: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let characterFrame = PixelAnimation.characterFrame(for: timeline.date, status: agent.status, salt: agent.id.hashValue)
            let selectionFrame = PixelAnimation.selectionFrame(for: timeline.date, salt: agent.id.hashValue / 5)
            let statusFrame = PixelAnimation.statusFrame(for: timeline.date, status: agent.status, salt: agent.id.hashValue / 11)
            let statusPhase = statusFrame.isMultiple(of: 2)

            VStack(spacing: PixelWorkstationLayout.verticalGap) {
                PixelStatusHeader(status: agent.status, color: statusColor, showsLabel: showsStatusBubble, phase: statusPhase)
                    .frame(width: rigWidth, height: PixelWorkstationLayout.statusSafeZoneHeight)
                    .zIndex(20)

                PixelWorkstationSprite(
                    agent: agent,
                    statusColor: statusColor,
                    characterFrame: characterFrame,
                    selectionFrame: selectionFrame,
                    statusFrame: statusFrame,
                    isSelected: isSelected
                )
                    .frame(width: spriteSide, height: spriteSide)
                    .zIndex(1)

                Text(agent.displayName)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? CompanyTheme.selected.opacity(0.96) : CompanyTheme.ink)
                    .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.18) : .black.opacity(0.42), radius: isSelected ? 4 : 2, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: rigWidth, height: PixelWorkstationLayout.nameHeight)
            }
            .frame(width: rigWidth, height: agentRigHeight)
            .offset(y: isSelected ? -4 : 0)
            .animation(.easeOut(duration: 0.18), value: isSelected)
        }
        .contentShape(Rectangle())
    }

    private var isExecutive: Bool {
        agent.role == .boss || agent.role == .cto
    }

    private var rigWidth: CGFloat {
        PixelWorkstationLayout.rigWidth(isExecutive: isExecutive)
    }

    private var spriteSide: CGFloat {
        PixelWorkstationLayout.spriteSide(isExecutive: isExecutive)
    }

    static func rigHeight(isExecutive: Bool) -> CGFloat {
        PixelWorkstationLayout.rigHeight(isExecutive: isExecutive)
    }

    private var agentRigHeight: CGFloat {
        Self.rigHeight(isExecutive: isExecutive)
    }

    private var showsStatusBubble: Bool {
        switch agent.status {
        case .idle:
            return isSelected
        case .thinking, .talking, .typing, .coding, .reviewing, .blocked, .waitingApproval, .done, .failed:
            return true
        }
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

enum PixelWorkstationLayout {
    static let statusSafeZoneHeight: CGFloat = 46
    static let nameHeight: CGFloat = 18
    static let verticalGap: CGFloat = 3

    static func rigWidth(isExecutive: Bool) -> CGFloat {
        isExecutive ? 164 : 142
    }

    static func spriteSide(isExecutive: Bool) -> CGFloat {
        isExecutive ? 144 : 124
    }

    static func rigHeight(isExecutive: Bool) -> CGFloat {
        statusSafeZoneHeight + spriteSide(isExecutive: isExecutive) + nameHeight + verticalGap * 2
    }
}

struct PixelStatusHeader: View {
    let status: AgentStatus
    let color: Color
    let showsLabel: Bool
    let phase: Bool

    var body: some View {
        ZStack {
            ActivityMarks(status: status, color: color, phase: phase)
                .frame(height: 24)
                .offset(y: showsLabel ? -9 : 1)

            if showsLabel {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                    Text(status.title)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(CompanyTheme.ink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    PixelStatusCapsule(color: color, phase: phase)
                )
                .offset(y: 12)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PixelStatusCapsule: View {
    let color: Color
    let phase: Bool

    var body: some View {
        Rectangle()
            .fill(CompanyTheme.panel.opacity(0.94))
            .overlay(
                Rectangle()
                    .stroke(color.opacity(phase ? 0.56 : 0.34), lineWidth: 1)
            )
            .shadow(color: color.opacity(phase ? 0.14 : 0.06), radius: 5)
    }
}

struct PixelWorkstationSprite: View {
    let agent: CompanyAgent
    let statusColor: Color
    let characterFrame: Int
    let selectionFrame: Int
    let statusFrame: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            ActivityPulseView(isSelected: isSelected, frame: selectionFrame)
                .padding(8)

            Canvas { context, size in
                let unit = min(size.width, size.height) / 64
                for rect in pixelRects {
                    let path = Path(CGRect(
                        x: rect.x * unit,
                        y: rect.y * unit,
                        width: rect.width * unit,
                        height: rect.height * unit
                    ).integral)
                    context.fill(path, with: .color(rect.color))
                }
            }
            .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.16) : .black.opacity(0.30), radius: isSelected ? 11 : 8, y: 7)
        }
    }

    private var pixelRects: [PixelRect] {
        var rects: [PixelRect] = []
        rects.append(contentsOf: environmentPixels)
        rects.append(contentsOf: chairPixels)
        rects.append(contentsOf: bodyPixels)
        rects.append(contentsOf: deskPixels)
        rects.append(contentsOf: monitorPixels)
        rects.append(contentsOf: keyboardPixels)
        rects.append(contentsOf: statusAccentPixels)
        return rects
    }

    private var environmentPixels: [PixelRect] {
        let frameColor = isSelected ? CompanyTheme.selected : statusColor
        let baseColor = isSelected ? CompanyTheme.selectedDeep : CompanyTheme.panel
        return [
            PixelRect(8, 58, 48, 3, Color.black.opacity(0.30)),
            PixelRect(8, 51, 48, 7, baseColor.opacity(isSelected ? 0.22 : 0.12)),
            PixelRect(11, 55, 42, 1, frameColor.opacity(isSelected ? 0.28 : 0.12)),
            PixelRect(13, 57, 38, 1, frameColor.opacity(agent.status == .idle ? 0.07 : 0.18))
        ]
    }

    private var chairPixels: [PixelRect] {
        [
            PixelRect(22, 27, 21, 21, Palette.outline),
            PixelRect(23, 28, 19, 19, Palette.chairBack),
            PixelRect(18, 44, 29, 5, Palette.outline),
            PixelRect(19, 44, 27, 4, Palette.chairSeat),
            PixelRect(30, 48, 5, 8, Palette.outline)
        ]
    }

    private var bodyPixels: [PixelRect] {
        let headYOffset = headOffset
        let leftArm = leftArmPixels
        let rightArm = rightArmPixels
        return [
            PixelRect(27, 45, 4, 8, Palette.leg),
            PixelRect(35, 45, 4, 8, Palette.leg),
            PixelRect(22, 29, 22, 18, Palette.outline),
            PixelRect(23, 30, 20, 17, palette.clothing),
            PixelRect(31, 31, 4, 14, palette.clothingLight.opacity(0.84)),
            PixelRect(24, 13 + headYOffset, 18, 16, Palette.outline),
            PixelRect(25, 14 + headYOffset, 16, 15, palette.skin),
            PixelRect(24, 12 + headYOffset, 18, 6, palette.hair),
            PixelRect(23, 17 + headYOffset, 3, 6, palette.hair),
            PixelRect(40, 17 + headYOffset, 3, 6, palette.hair),
            PixelRect(29, 21 + headYOffset, 2, blinkHeight, Palette.eye),
            PixelRect(36, 21 + headYOffset, 2, blinkHeight, Palette.eye),
            PixelRect(31, 26 + headYOffset, mouthWidth, 1, Palette.mouth)
        ] + leftArm + rightArm
    }

    private var deskPixels: [PixelRect] {
        [
            PixelRect(10, 43, 44, 3, Palette.deskEdge),
            PixelRect(9, 46, 46, 10, Palette.outline),
            PixelRect(10, 46, 44, 8, Palette.desk),
            PixelRect(10, 54, 44, 2, Palette.deskDark),
            PixelRect(12, 56, 7, 2, Palette.deskLeg),
            PixelRect(45, 56, 7, 2, Palette.deskLeg)
        ]
    }

    private var monitorPixels: [PixelRect] {
        var rects: [PixelRect] = [
            PixelRect(20, 31, 25, 14, Palette.monitorFrame),
            PixelRect(21, 32, 23, 12, Palette.monitorBase),
            PixelRect(31, 45, 4, 3, Palette.monitorFrame),
            PixelRect(27, 48, 12, 2, Palette.monitorFrame)
        ]

        switch agent.status {
        case .typing, .coding:
            let scroll = CGFloat(statusFrame % 4)
            rects.append(PixelRect(24, 34, 12 + scroll, 1, statusColor.opacity(0.92)))
            rects.append(PixelRect(24, 37, 6 + CGFloat((statusFrame + 2) % 9), 1, Color.white.opacity(0.72)))
            rects.append(PixelRect(24, 40, 16 - scroll * 2, 1, statusColor.opacity(0.72)))
            rects.append(PixelRect(41, 34 + CGFloat(statusFrame % 6), 1, 7, statusColor.opacity(0.85)))
        case .reviewing:
            rects.append(PixelRect(24, 34, 13, 1, Color.white.opacity(0.68)))
            rects.append(PixelRect(24, 37, 10, 1, statusFrame.isMultiple(of: 2) ? CompanyTheme.green : CompanyTheme.red))
            rects.append(PixelRect(38, 36, 3, 3, statusFrame.isMultiple(of: 2) ? CompanyTheme.green : CompanyTheme.red))
            rects.append(PixelRect(24, 40, 15, 1, Color.white.opacity(0.35)))
        case .blocked, .failed:
            rects.append(PixelRect(23, 34, 19, 2, CompanyTheme.red.opacity(statusFrame.isMultiple(of: 2) ? 0.95 : 0.38)))
            rects.append(PixelRect(29, 37, 7, 5, CompanyTheme.red.opacity(statusFrame.isMultiple(of: 2) ? 0.75 : 0.28)))
            rects.append(PixelRect(33, 34, 1, 8, CompanyTheme.background.opacity(0.62)))
        case .waitingApproval:
            rects.append(PixelRect(29, 34, 3, 8, CompanyTheme.warning.opacity(0.75)))
            rects.append(PixelRect(36, 34, 3, 8, CompanyTheme.warning.opacity(statusFrame.isMultiple(of: 2) ? 0.92 : 0.44)))
        case .done:
            rects.append(PixelRect(27, 38, 4, 3, CompanyTheme.green))
            rects.append(PixelRect(31, 40, 4, 3, CompanyTheme.green))
            rects.append(PixelRect(35, 34, 7, 4, CompanyTheme.green.opacity(statusFrame.isMultiple(of: 2) ? 0.94 : 0.52)))
        case .thinking, .talking:
            rects.append(PixelRect(24, 36, 7 + CGFloat(statusFrame % 6), 1, statusColor.opacity(0.70)))
            rects.append(PixelRect(26, 39, 14 - CGFloat(statusFrame % 5), 1, Color.white.opacity(0.38)))
        case .idle:
            rects.append(PixelRect(28, 38, 10, 1, Color.white.opacity(idleMonitorAlpha)))
        }
        return rects
    }

    private var keyboardPixels: [PixelRect] {
        var rects = [
            PixelRect(24, 49, 17, 3, Color.black.opacity(0.42))
        ]
        for index in 0..<7 {
            let active = agent.status == .typing || agent.status == .coding
            let isLit = statusFrame % 3 == index % 3
            rects.append(PixelRect(25 + CGFloat(index * 2), 50, 1, 1, active && isLit ? statusColor.opacity(0.92) : Color.white.opacity(0.18)))
        }
        return rects
    }

    private var statusAccentPixels: [PixelRect] {
        switch agent.status {
        case .thinking, .talking:
            return [
                PixelRect(47, 18 + CGFloat(statusFrame % 3), 2, 2, statusColor.opacity(0.92)),
                PixelRect(51, 15 + CGFloat((statusFrame + 1) % 4), 2, 2, statusColor.opacity(0.70)),
                PixelRect(55, 19 + CGFloat((statusFrame + 2) % 3), 2, 2, statusColor.opacity(0.50))
            ]
        case .coding, .typing:
            return [
                PixelRect(48, 28, 2, CGFloat(5 + statusFrame % 7), statusColor.opacity(0.72)),
                PixelRect(52, 26, 2, CGFloat(4 + (statusFrame + 2) % 8), statusColor.opacity(0.58)),
                PixelRect(56, 30, 2, CGFloat(5 + (statusFrame + 4) % 7), statusColor.opacity(0.62))
            ]
        case .reviewing:
            return [
                PixelRect(48, 22, 7, 1, CompanyTheme.warning.opacity(statusFrame.isMultiple(of: 2) ? 0.82 : 0.36)),
                PixelRect(51, 23, 1, 7, CompanyTheme.warning.opacity(statusFrame.isMultiple(of: 2) ? 0.78 : 0.34))
            ]
        case .blocked, .failed:
            return [
                PixelRect(50, 16, 5, 9, CompanyTheme.red.opacity(statusFrame.isMultiple(of: 2) ? 0.95 : 0.42)),
                PixelRect(52, 27, 2, 2, CompanyTheme.red.opacity(statusFrame.isMultiple(of: 2) ? 0.95 : 0.42)),
                PixelRect(46, 33, 13, 2, CompanyTheme.red.opacity(statusFrame.isMultiple(of: 2) ? 0.65 : 0.18))
            ]
        case .waitingApproval:
            return [
                PixelRect(12, 20 + CGFloat(statusFrame % 2) * -2, 3, 11, CompanyTheme.warning.opacity(0.72)),
                PixelRect(12, 18 + CGFloat(statusFrame % 2) * -2, 8, 3, CompanyTheme.warning.opacity(0.70))
            ]
        case .done:
            return [
                PixelRect(48, 23, 4, 4, CompanyTheme.green.opacity(0.92)),
                PixelRect(52, 26, 4, 4, CompanyTheme.green.opacity(0.92)),
                PixelRect(56, 18, 3, 9, CompanyTheme.green.opacity(statusFrame.isMultiple(of: 2) ? 0.90 : 0.46))
            ]
        case .idle:
            return [
                PixelRect(51, 18, 4, 4, statusColor.opacity(idleStatusPointOpacity))
            ]
        }
    }

    private var leftArmPixels: [PixelRect] {
        switch agent.status {
        case .typing, .coding:
            return [
                PixelRect(17, characterFrame.isMultiple(of: 2) ? 35 : 33, 7, 3, palette.clothingDark),
                PixelRect(15, characterFrame.isMultiple(of: 2) ? 36 : 34, 5, 3, palette.skinShadow)
            ]
        case .thinking:
            return [
                PixelRect(18, characterFrame.isMultiple(of: 2) ? 25 : 26, 5, 10, palette.clothingDark),
                PixelRect(20, characterFrame.isMultiple(of: 2) ? 23 : 24, 5, 3, palette.skinShadow)
            ]
        case .waitingApproval:
            return [
                PixelRect(17, characterFrame.isMultiple(of: 2) ? 16 : 19, 5, 14, palette.clothingDark),
                PixelRect(15, characterFrame.isMultiple(of: 2) ? 13 : 16, 6, 4, palette.skinShadow)
            ]
        default:
            return [
                PixelRect(17, 33, 7, 10, palette.clothingDark),
                PixelRect(15, 40, 6, 3, palette.skinShadow)
            ]
        }
    }

    private var rightArmPixels: [PixelRect] {
        switch agent.status {
        case .typing, .coding:
            return [
                PixelRect(42, characterFrame.isMultiple(of: 2) ? 33 : 35, 7, 3, palette.clothingDark),
                PixelRect(48, characterFrame.isMultiple(of: 2) ? 34 : 36, 5, 3, palette.skinShadow)
            ]
        case .reviewing:
            return [
                PixelRect(42, characterFrame.isMultiple(of: 2) ? 33 : 31, 9, 3, palette.clothingDark),
                PixelRect(50, characterFrame.isMultiple(of: 2) ? 33 : 31, 5, 3, palette.skinShadow)
            ]
        default:
            return [
                PixelRect(42, 33, 7, 10, palette.clothingDark),
                PixelRect(47, 40, 6, 3, palette.skinShadow)
            ]
        }
    }

    private var headOffset: CGFloat {
        switch agent.status {
        case .idle: characterFrame.isMultiple(of: 2) ? 0 : -1
        case .thinking: characterFrame.isMultiple(of: 2) ? -1 : 1
        case .blocked, .failed: characterFrame.isMultiple(of: 2) ? 2 : 0
        case .done: characterFrame.isMultiple(of: 2) ? -1 : 0
        default: 0
        }
    }

    private var blinkHeight: CGFloat {
        switch agent.status {
        case .idle, .thinking:
            return characterFrame % 4 == 1 ? 1 : 2
        default:
            return 2
        }
    }

    private var mouthWidth: CGFloat {
        switch agent.status {
        case .done: 6
        case .blocked, .failed: characterFrame.isMultiple(of: 2) ? 5 : 3
        default: 3
        }
    }

    private var idleMonitorAlpha: Double {
        statusFrame.isMultiple(of: 2) ? 0.14 : 0.24
    }

    private var idleStatusPointOpacity: Double {
        statusFrame.isMultiple(of: 2) ? 0.28 : 0.42
    }

    private var palette: PixelCharacterPalette {
        PixelCharacterPalette(agent: agent, accent: statusColor)
    }
}

struct PixelRect {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let color: Color

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
    }
}

struct PixelCharacterPalette {
    let skin: Color
    let skinShadow: Color
    let hair: Color
    let clothing: Color
    let clothingDark: Color
    let clothingLight: Color

    init(agent: CompanyAgent, accent: Color) {
        switch agent.ethnicity {
        case .chinese:
            skin = Color(red: 0.90, green: 0.67, blue: 0.46)
            skinShadow = Color(red: 0.62, green: 0.39, blue: 0.24)
        case .white:
            skin = Color(red: 0.94, green: 0.76, blue: 0.57)
            skinShadow = Color(red: 0.68, green: 0.47, blue: 0.31)
        case .black:
            skin = Color(red: 0.34, green: 0.20, blue: 0.13)
            skinShadow = Color(red: 0.20, green: 0.12, blue: 0.08)
        case .southAsian:
            skin = Color(red: 0.62, green: 0.38, blue: 0.23)
            skinShadow = Color(red: 0.38, green: 0.23, blue: 0.14)
        case .middleEastern:
            skin = Color(red: 0.72, green: 0.47, blue: 0.29)
            skinShadow = Color(red: 0.45, green: 0.28, blue: 0.17)
        case .latino:
            skin = Color(red: 0.76, green: 0.50, blue: 0.32)
            skinShadow = Color(red: 0.48, green: 0.30, blue: 0.18)
        case .custom:
            skin = Color(red: 0.80, green: 0.61, blue: 0.43)
            skinShadow = Color(red: 0.52, green: 0.36, blue: 0.23)
        }

        hair = agent.ethnicity == .white ? Color(red: 0.45, green: 0.32, blue: 0.18) : Color(red: 0.055, green: 0.041, blue: 0.035)

        switch agent.clothing {
        case .businessSuit:
            clothing = Color(red: 0.10, green: 0.17, blue: 0.25)
            clothingDark = Color(red: 0.05, green: 0.08, blue: 0.12)
            clothingLight = accent.opacity(0.62)
        case .smartCasual:
            clothing = Color(red: 0.23, green: 0.40, blue: 0.43)
            clothingDark = Color(red: 0.12, green: 0.23, blue: 0.26)
            clothingLight = Color(red: 0.42, green: 0.68, blue: 0.70)
        case .hoodie:
            clothing = Color(red: 0.31, green: 0.27, blue: 0.50)
            clothingDark = Color(red: 0.15, green: 0.13, blue: 0.26)
            clothingLight = Color(red: 0.48, green: 0.42, blue: 0.76)
        case .designerBlack:
            clothing = Color(red: 0.035, green: 0.040, blue: 0.050)
            clothingDark = Color(red: 0.015, green: 0.018, blue: 0.024)
            clothingLight = Color(red: 0.36, green: 0.24, blue: 0.42)
        case .labCoat:
            clothing = Color(red: 0.76, green: 0.80, blue: 0.78)
            clothingDark = Color(red: 0.42, green: 0.48, blue: 0.50)
            clothingLight = Color(red: 0.90, green: 0.94, blue: 0.92)
        case .custom:
            clothing = accent.opacity(0.88)
            clothingDark = accent.opacity(0.42)
            clothingLight = Color.white.opacity(0.60)
        }
    }
}

enum Palette {
    static let outline = Color(red: 0.025, green: 0.034, blue: 0.044)
    static let chairBack = Color(red: 0.090, green: 0.118, blue: 0.140)
    static let chairSeat = Color(red: 0.065, green: 0.086, blue: 0.105)
    static let leg = Color(red: 0.040, green: 0.050, blue: 0.064)
    static let desk = Color(red: 0.105, green: 0.145, blue: 0.170)
    static let deskDark = Color(red: 0.055, green: 0.074, blue: 0.090)
    static let deskEdge = Color(red: 0.190, green: 0.260, blue: 0.290)
    static let deskLeg = Color(red: 0.035, green: 0.047, blue: 0.060)
    static let monitorFrame = Color(red: 0.035, green: 0.047, blue: 0.060)
    static let monitorBase = Color(red: 0.040, green: 0.075, blue: 0.095)
    static let eye = Color(red: 0.030, green: 0.035, blue: 0.040)
    static let mouth = Color(red: 0.095, green: 0.055, blue: 0.047)
}

struct ActivityPulseView: View {
    let isSelected: Bool
    let frame: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Ellipse()
                .fill(CompanyTheme.selected.opacity(selectionOpacity * 0.42))
                .frame(width: 92, height: 24)
                .blur(radius: 0.8)
                .offset(x: 20, y: 4)
                .scaleEffect(selectionScale)
            Ellipse()
                .stroke(CompanyTheme.selected.opacity(selectionOpacity), lineWidth: 0.7)
                .frame(width: 86, height: 20)
                .offset(x: 23, y: 5)
                .scaleEffect(selectionScale)
            Rectangle()
                .fill(CompanyTheme.selected.opacity(0.62))
                .frame(width: 1.2, height: 34)
                .offset(x: 9, y: -22)
        }
        .opacity(isSelected ? 1 : 0)
    }

    private var selectionOpacity: Double {
        switch frame % 3 {
        case 1:
            return 0.28
        default:
            return 0.15
        }
    }

    private var selectionScale: CGFloat {
        switch frame % 3 {
        case 1:
            return 1.018
        default:
            return 0.995
        }
    }
}

struct ActivityMarks: View {
    let status: AgentStatus
    let color: Color
    let phase: Bool

    var body: some View {
        ZStack {
            switch status {
            case .thinking, .talking:
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(color.opacity(markOpacity(for: index)))
                            .frame(width: 6, height: 6)
                            .offset(y: phase ? -CGFloat(index * 2) : CGFloat(index))
                    }
                }
            case .blocked, .failed:
                Image(systemName: status == .blocked ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(phase ? 2 : -2))
                    .shadow(color: color.opacity(0.24), radius: 5)
            case .waitingApproval:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(color)
                    .offset(y: phase ? -2 : 0)
            case .done:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(color)
                    .scaleEffect(1.0)
                    .shadow(color: color.opacity(0.18), radius: 4)
            case .typing, .coding, .reviewing:
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(color.opacity(markOpacity(for: index)))
                            .frame(width: 5, height: markHeight(for: index))
                            .offset(y: phase ? -CGFloat(index) : CGFloat(index))
                    }
                }
            case .idle:
                EmptyView()
            }
        }
        .opacity(isVisible ? 1 : 0)
    }

    private var isVisible: Bool {
        switch status {
        case .thinking, .talking, .typing, .coding, .reviewing, .waitingApproval, .done, .failed, .blocked:
            true
        case .idle:
            false
        }
    }

    private func markHeight(for index: Int) -> CGFloat {
        let base: CGFloat = status == .coding || status == .typing ? 14 : 10
        return phase ? base + CGFloat(index * 3) : base + CGFloat((2 - index) * 3)
    }

    private func markOpacity(for index: Int) -> Double {
        phase ? 0.62 - Double(index) * 0.10 : 0.34 + Double(index) * 0.08
    }
}

struct ChairShape: View {
    let status: AgentStatus
    let color: Color
    let phase: Bool

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.115, green: 0.145, blue: 0.170),
                            Color(red: 0.070, green: 0.085, blue: 0.105)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(status == .idle ? 0.10 : phase ? 0.30 : 0.16), lineWidth: 1)
                )
                .frame(width: 62, height: 54)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.060, green: 0.073, blue: 0.088))
                .frame(width: 74, height: 22)
        }
        .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
    }
}

struct DeskShape: View {
    let isSelected: Bool
    let status: AgentStatus
    let color: Color
    let phase: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.140, green: 0.175, blue: 0.200),
                            Color(red: 0.070, green: 0.085, blue: 0.100)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? CompanyTheme.selected : color.opacity(status == .idle ? 0.10 : 0.34), lineWidth: isSelected ? 3 : 1)
                )
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(status == .idle ? 0.08 : phase ? 0.22 : 0.12))
                .frame(height: 18)
                .offset(y: 28)

            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.22))
                    .frame(width: 22, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 34, height: 6)
            }
            .offset(y: -4)
        }
        .shadow(color: isSelected ? CompanyTheme.selectionGlow.opacity(0.18) : .black.opacity(0.32), radius: 13, y: 8)
    }
}

struct SceneCharacterRig: View {
    let agent: CompanyAgent
    let statusColor: Color
    let phase: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                Capsule()
                    .fill(legColor)
                    .frame(width: 10, height: 34)
                    .rotationEffect(.degrees(8))
                Capsule()
                    .fill(legColor)
                    .frame(width: 10, height: 34)
                    .rotationEffect(.degrees(-8))
            }
            .offset(y: 42)

            RoundedRectangle(cornerRadius: 11)
                .fill(clothingColor)
                .frame(width: 42, height: 46)
                .overlay(jacketDetail)
                .offset(y: 18)

            arm(isLeft: true)
                .offset(x: -31, y: armYOffset)
            arm(isLeft: false)
                .offset(x: 31, y: oppositeArmYOffset)

            Ellipse()
                .fill(skinColor)
                .frame(width: 44, height: 48)
                .offset(y: -22 + headYOffset)

            Capsule()
                .fill(hairColor)
                .frame(width: 43, height: 16)
                .offset(y: -45 + headYOffset)

            HStack(spacing: 10) {
                eye
                eye
            }
            .offset(y: -24 + headYOffset)

            Capsule()
                .fill(Color.black.opacity(0.36))
                .frame(width: mouthWidth, height: 3)
                .offset(y: -11 + headYOffset)
        }
    }

    private func arm(isLeft: Bool) -> some View {
        Capsule()
            .fill(clothingColor.opacity(0.96))
            .frame(width: 10, height: armHeight)
            .overlay(
                Capsule()
                    .fill(skinColor)
                    .frame(width: 9, height: 12)
                    .offset(y: armHeight * 0.34)
            )
            .rotationEffect(.degrees(armRotation(isLeft: isLeft)))
    }

    private var jacketDetail: some View {
        VStack(spacing: 0) {
            if agent.clothing == .businessSuit || agent.clothing == .designerBlack {
                Triangle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 16, height: 16)
                Rectangle()
                    .fill(statusColor.opacity(0.72))
                    .frame(width: 4, height: 15)
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 20, height: 4)
                    .offset(y: -6)
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.black.opacity(0.70))
            .frame(width: 4, height: phase && agent.status == .thinking ? 2 : 5)
    }

    private var armHeight: CGFloat {
        switch agent.status {
        case .waitingApproval:
            return phase ? 42 : 34
        case .reviewing:
            return 36
        default:
            return 32
        }
    }

    private var armYOffset: CGFloat {
        switch agent.status {
        case .typing, .coding:
            return phase ? 22 : 15
        case .thinking:
            return phase ? -2 : 4
        case .waitingApproval:
            return phase ? -16 : -9
        case .blocked, .failed:
            return 28
        default:
            return 16
        }
    }

    private var oppositeArmYOffset: CGFloat {
        switch agent.status {
        case .typing, .coding:
            return phase ? 15 : 22
        case .reviewing:
            return phase ? 10 : 18
        case .blocked, .failed:
            return 28
        default:
            return 16
        }
    }

    private func armRotation(isLeft: Bool) -> Double {
        switch agent.status {
        case .typing, .coding:
            return isLeft ? (phase ? 72 : 54) : (phase ? -54 : -72)
        case .thinking:
            return isLeft ? 130 : -35
        case .reviewing:
            return isLeft ? 58 : (phase ? -92 : -74)
        case .waitingApproval:
            return isLeft ? (phase ? -150 : -132) : -30
        case .blocked, .failed:
            return isLeft ? 38 : -38
        case .done:
            return isLeft ? 50 : -50
        default:
            return isLeft ? 38 : -38
        }
    }

    private var headYOffset: CGFloat {
        switch agent.status {
        case .thinking:
            return phase ? -2 : 2
        case .typing, .coding:
            return phase ? 1 : 0
        case .blocked, .failed:
            return 5
        case .done:
            return phase ? -3 : 0
        default:
            return 0
        }
    }

    private var mouthWidth: CGFloat {
        switch agent.status {
        case .blocked, .failed:
            return 11
        case .done:
            return 16
        default:
            return 9
        }
    }

    private var skinColor: Color {
        switch agent.ethnicity {
        case .chinese: Color(red: 0.92, green: 0.70, blue: 0.50)
        case .white: Color(red: 0.95, green: 0.78, blue: 0.62)
        case .black: Color(red: 0.34, green: 0.20, blue: 0.13)
        case .southAsian: Color(red: 0.64, green: 0.39, blue: 0.24)
        case .middleEastern: Color(red: 0.74, green: 0.49, blue: 0.31)
        case .latino: Color(red: 0.78, green: 0.52, blue: 0.34)
        case .custom: Color(red: 0.80, green: 0.62, blue: 0.45)
        }
    }

    private var clothingColor: Color {
        switch agent.clothing {
        case .businessSuit: Color(red: 0.12, green: 0.18, blue: 0.24)
        case .smartCasual: Color(red: 0.27, green: 0.45, blue: 0.48)
        case .hoodie: Color(red: 0.42, green: 0.36, blue: 0.62)
        case .designerBlack: Color(red: 0.04, green: 0.04, blue: 0.04)
        case .labCoat: Color(red: 0.91, green: 0.92, blue: 0.87)
        case .custom: CompanyTheme.accent
        }
    }

    private var legColor: Color {
        Color(red: 0.055, green: 0.066, blue: 0.078)
    }

    private var hairColor: Color {
        switch agent.ethnicity {
        case .white: Color(red: 0.49, green: 0.35, blue: 0.20)
        default: Color(red: 0.08, green: 0.06, blue: 0.05)
        }
    }
}

struct StatusScreenView: View {
    let status: AgentStatus
    let color: Color
    let phase: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.035, green: 0.048, blue: 0.060))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(status == .idle ? 0.16 : phase ? 0.54 : 0.32))
                    .padding(7)
            )
            .overlay(screenContent.padding(8))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(status == .idle ? 0.12 : 0.38), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var screenContent: some View {
        switch status {
        case .typing, .coding:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(lineOpacity(index)))
                        .frame(width: lineWidth(index), height: 3)
                        .offset(x: phase ? CGFloat(index % 2) * 5 : 0)
                }
            }
        case .reviewing:
            VStack(spacing: 4) {
                Label("", systemImage: phase ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(phase ? CompanyTheme.green : CompanyTheme.red)
                Capsule()
                    .fill(Color.white.opacity(0.50))
                    .frame(width: 32, height: 4)
            }
        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(CompanyTheme.red)
                .opacity(phase ? 1 : 0.45)
        case .waitingApproval:
            Image(systemName: "pause.rectangle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.yellow)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(CompanyTheme.green)
                .scaleEffect(phase ? 1.16 : 0.92)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(CompanyTheme.red)
                .opacity(phase ? 1 : 0.55)
        case .thinking, .talking:
            VStack(spacing: 4) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 34, height: 4)
                    .offset(x: phase ? 6 : -4)
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 24, height: 4)
                    .offset(x: phase ? -5 : 5)
            }
        case .idle:
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 24, height: 4)
        }
    }

    private func lineWidth(_ index: Int) -> CGFloat {
        let widths: [CGFloat] = status == .coding ? [38, 30, 42, 25] : [32, 24, 35, 20]
        return widths[index % widths.count]
    }

    private func lineOpacity(_ index: Int) -> Double {
        phase ? 0.86 - Double(index) * 0.12 : 0.42 + Double(index) * 0.10
    }
}

struct KeyboardView: View {
    let status: AgentStatus
    let color: Color
    let phase: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(keyColor(index: index))
                    .frame(width: 6, height: 4)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
    }

    private func keyColor(index: Int) -> Color {
        switch status {
        case .typing, .coding:
            return color.opacity((phase == (index.isMultiple(of: 2))) ? 0.88 : 0.26)
        case .blocked, .failed:
            return CompanyTheme.red.opacity(phase ? 0.80 : 0.32)
        default:
            return Color.white.opacity(0.16)
        }
    }
}

struct SpeechBubble: View {
    let agent: CompanyAgent

    var body: some View {
        Text(agent.status.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }
}
