import Foundation

/// Platform-neutral display metadata for employee collaboration messages.
///
/// Extracted from the SwiftUI file (spike #5 census: `CompanyStore+Reports`
/// needs these titles in generated reports, which are pure logic — reports
/// must render on Windows without SwiftUI). SF Symbol names are plain
/// strings and ride along harmlessly; the Color-returning functions stayed
/// as a UI-layer extension in SelectionWorkspaceView.swift.
enum AgentMessageDisplay {
    static func title(for kind: AgentMessageKind) -> String {
        switch kind {
        case .ctoGoalStarted: "技术负责人启动目标".L()
        case .taskDispatched: "任务派发".L()
        case .workCompleted: "员工回传".L()
        case .reviewRequested: "请求审查".L()
        case .reviewCompleted: "审查反馈".L()
        case .acceptanceCompleted: "验收通过".L()
        case .approvalRequested: "审批请求".L()
        case .approvalDecided: "审批结果".L()
        case .ctoLoopProgressed: "技术负责人循环推进".L()
        case .employeeHandoff: "员工交接".L()
        }
    }
    static func icon(for kind: AgentMessageKind) -> String {
        switch kind {
        case .ctoGoalStarted: "flag.fill"
        case .taskDispatched: "paperplane.fill"
        case .workCompleted: "checkmark.seal.fill"
        case .reviewRequested: "magnifyingglass"
        case .reviewCompleted: "shield.lefthalf.filled"
        case .acceptanceCompleted: "checkmark.seal.fill"
        case .approvalRequested: "hand.raised.fill"
        case .approvalDecided: "signature"
        case .ctoLoopProgressed: "arrow.triangle.2.circlepath"
        case .employeeHandoff: "person.2.wave.2.fill"
        }
    }
    static func statusTitle(for status: AgentMessageStatus) -> String {
        switch status {
        case .pending: "待确认".L()
        case .acknowledged: "已读".L()
        case .failed: "失败".L()
        }
    }
}
