#if canImport(SwiftUI)
// Whole-file UI gate (windows.yml lesson — PR #92 re-proved it: the gate
// must come BEFORE `import SwiftUI`). Demo studio: the pixel-employee rig
// as a PURE function of (agent, status, date), so marketing frames can be
// rendered offscreen (GIF via `swift run OPCDemoGif`) without
// screen-recording permission and without a running app. This is the same
// composition AgentDeskView builds around TimelineView — duplicated
// deliberately (AgentDeskView's frames come from a live clock that
// offscreen rendering can't drive). If the desk layout changes there,
// change it here.

import SwiftUI

public enum OPCDemoStudio {

    /// Mirror of AgentDeskView.statusColor — keep in lockstep.
    static func statusColor(for status: AgentStatus) -> Color {
        switch status {
        case .idle: CompanyTheme.muted
        case .thinking, .talking, .typing: CompanyTheme.blue
        case .coding, .reviewing: CompanyTheme.accent
        case .blocked, .failed: CompanyTheme.red
        case .waitingApproval: CompanyTheme.warning
        case .done: CompanyTheme.green
        }
    }

    /// One workstation for one agent at one instant — the desk unit of
    /// AgentDeskView with the clock lifted into a parameter.
    @MainActor
    static func deskRig(agent: CompanyAgent, status: AgentStatus, date: Date, isSelected: Bool = false) -> some View {
        let isExecutive = agent.role == .boss || agent.role == .cto
        let rigWidth = PixelWorkstationLayout.rigWidth(isExecutive: isExecutive)
        let spriteSide = PixelWorkstationLayout.spriteSide(isExecutive: isExecutive)
        let rigHeight = PixelWorkstationLayout.rigHeight(isExecutive: isExecutive)
        let characterFrame = PixelAnimation.characterFrame(for: date, status: status, salt: agent.id.hashValue)
        let selectionFrame = PixelAnimation.selectionFrame(for: date, salt: agent.id.hashValue / 5)
        let statusFrame = PixelAnimation.statusFrame(for: date, status: status, salt: agent.id.hashValue / 11)
        let statusPhase = statusFrame.isMultiple(of: 2)

        return VStack(spacing: PixelWorkstationLayout.verticalGap) {
            PixelStatusHeader(
                status: status, color: statusColor(for: status),
                showsLabel: true, phase: statusPhase
            )
            // The shipping waitingApproval bubble wears a click-affordance
            // ring (WaitingApprovalRigHeader) and — when several requests
            // stack up — a count badge. Mirror both; the "2" here is demo
            // data (the gallery has no store), the SHAPE is the app's.
            .overlay {
                if status == .waitingApproval {
                    PixelStatusCapsule(color: statusColor(for: status), phase: statusPhase)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(CompanyTheme.ink.opacity(statusPhase ? 0.55 : 0.2), lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            Text("2")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(CompanyTheme.ink)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(CompanyTheme.warning, in: RoundedRectangle(cornerRadius: 2))
                                .offset(x: 5, y: -5)
                        }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: rigWidth, height: PixelWorkstationLayout.statusSafeZoneHeight)
            .zIndex(20)

            PixelWorkstationSprite(
                agent: agent,
                statusColor: statusColor(for: status),
                characterFrame: characterFrame,
                selectionFrame: selectionFrame,
                statusFrame: statusFrame,
                isSelected: isSelected
            )
            .frame(width: spriteSide, height: spriteSide)
            .zIndex(1)

            Text(agent.displayName)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(CompanyTheme.ink)
                .lineLimit(1)
                .frame(width: rigWidth, height: PixelWorkstationLayout.nameHeight)
        }
        .frame(width: rigWidth, height: rigHeight)
    }

    /// Canvas size for the GIF renderer (opc-demo-gif): 5 columns × 142pt
    /// rigs + spacing + padding; 2 rows of full-height rigs.
    public static let galleryWidth: CGFloat = 800
    public static let galleryHeight: CGFloat = 452

    /// A labelled grid of rigs — the GIF canvas: every company state the
    /// pixels can express, alive on one dark background.
    @MainActor
    public static func statusGallery(date: Date) -> some View {
        let roster: [(CompanyAgent, AgentStatus)] = AgentStatus.allCases.map { status in
            let agent = demoAgent(
                for: status,
                name: galleryName(for: status),
                ethnicity: galleryEthnicity(index: AgentStatus.allCases.firstIndex(of: status) ?? 0)
            )
            return (agent, status)
        }
        let columns = 5
        return ZStack {
            CompanyTheme.background
            VStack(spacing: 14) {
                ForEach(0..<((roster.count + columns - 1) / columns), id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row * columns..<min((row + 1) * columns, roster.count), id: \.self) { i in
                            deskRig(agent: roster[i].0, status: roster[i].1, date: date)
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: galleryWidth, height: galleryHeight)
    }

    static func demoAgent(for status: AgentStatus, name: String, ethnicity: EthnicityPresentation) -> CompanyAgent {
        CompanyAgent(
            displayName: name,
            title: status.title,
            role: .codeEngineer,
            backend: AgentBackend(type: .subscriptionCLI, command: "claude", model: "sonnet"),
            ethnicity: ethnicity,
            gender: [.woman, .man, .man, .woman, .man, .man][(AgentStatus.allCases.firstIndex(of: status) ?? 0) % 6],
            clothing: .smartCasual,
            status: status,
            permissions: [.readFiles, .editFiles, .runTests],
            seat: OfficeSeat(x: 0.5, y: 0.5, room: "employee-hall")
        )
    }

    static func galleryName(for status: AgentStatus) -> String {
        // Employee NAMES, not status labels — the bubble above already
        // carries the status (status.title). Mirrors the shipping app
        // where the desk label is the person, and gives the gallery the
        // multilingual crew flavor the real roster has.
        switch status {
        case .idle: "阿豪"
        case .thinking: "Nina"
        case .talking: "Raj"
        case .typing: "小雅"
        case .coding: "Leo"
        case .reviewing: "Aisha"
        case .blocked: "大伟"
        case .waitingApproval: "Maria"
        case .done: "Kenji"
        case .failed: "Zoe"
        }
    }

    static func galleryEthnicity(index: Int) -> EthnicityPresentation {
        let cycle: [EthnicityPresentation] = [.chinese, .white, .black, .southAsian, .latino]
        return cycle[index % cycle.count]
    }
}

#endif
