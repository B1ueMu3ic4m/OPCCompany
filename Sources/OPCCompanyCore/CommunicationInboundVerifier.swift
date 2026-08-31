import CryptoKit
import Foundation

public enum CommunicationInboundVerificationResult: Equatable, Sendable {
    case accepted
    case missingField(String)
    case staleTimestamp
    case replayedNonce
    case invalidSignature
}

public enum CommunicationInboundAction: String, Codable, CaseIterable, Sendable {
    case queryStatus = "query_status"
    case submitInstruction = "submit_instruction"
    case approvalDecision = "approval_decision"

    public var title: String {
        switch self {
        case .queryStatus: "查询当前产品状态"
        case .submitInstruction: "提交普通指令任务"
        case .approvalDecision: "处理特定审批"
        }
    }
}

public enum CommunicationInboundCommandParseResult: Equatable, Sendable {
    case accepted(CommunicationInboundCommand)
    case invalidJSON
    case missingField(String)
    case unsupportedAction(String)
    case emptyInstruction
    case approvalActionDisabled
}

public struct CommunicationInboundCommand: Equatable, Sendable {
    public var action: CommunicationInboundAction
    public var text: String

    public init(action: CommunicationInboundAction, text: String) {
        self.action = action
        self.text = text
    }
}

public enum CommunicationInboundCommandParser {
    public static func parse(_ body: String) -> CommunicationInboundCommandParseResult {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return .invalidJSON
        }
        guard let actionText = stringValue(dictionary["action"]), !actionText.isEmpty else {
            return .missingField("action")
        }
        guard let action = CommunicationInboundAction(rawValue: actionText) else {
            return .unsupportedAction(actionText)
        }

        switch action {
        case .queryStatus:
            return .accepted(CommunicationInboundCommand(action: action, text: "查询当前产品状态"))
        case .submitInstruction:
            let text = stringValue(dictionary["text"]) ?? stringValue(dictionary["instruction"]) ?? stringValue(dictionary["command"]) ?? ""
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return .emptyInstruction }
            return .accepted(CommunicationInboundCommand(action: action, text: clean))
        case .approvalDecision:
            return .approvalActionDisabled
        }
    }

    public static func parseFailureTitle(_ result: CommunicationInboundCommandParseResult) -> String {
        switch result {
        case .accepted:
            "已通过"
        case .invalidJSON:
            "请求体必须是 JSON"
        case .missingField(let field):
            "缺少 \(field)"
        case .unsupportedAction(let action):
            "动作不在白名单：\(action)"
        case .emptyInstruction:
            "普通指令内容为空"
        case .approvalActionDisabled:
            "外部审批动作暂未开放"
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }
}

public enum CommunicationInboundVerifier {
    public static func signature(body: String, timestamp: String, nonce: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let payload = Data("\(timestamp).\(nonce).\(body)".utf8)
        let code = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(
        body: String,
        timestamp: String?,
        nonce: String?,
        signature providedSignature: String?,
        secret: String,
        now: Date = Date(),
        usedNonces: inout Set<String>,
        allowedSkewSeconds: TimeInterval = 300
    ) -> CommunicationInboundVerificationResult {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingField("secret")
        }
        guard let timestamp, !timestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingField("timestamp")
        }
        guard let nonce, !nonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingField("nonce")
        }
        guard let providedSignature, !providedSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .missingField("signature")
        }
        guard let timestampDate = ISO8601DateFormatter().date(from: timestamp),
              abs(now.timeIntervalSince(timestampDate)) <= allowedSkewSeconds
        else {
            return .staleTimestamp
        }
        guard !usedNonces.contains(nonce) else {
            return .replayedNonce
        }

        let expected = signature(body: body, timestamp: timestamp, nonce: nonce, secret: secret)
        guard constantTimeEqual(expected, providedSignature.lowercased()) else {
            return .invalidSignature
        }

        usedNonces.insert(nonce)
        if usedNonces.count > 1_000 {
            usedNonces = Set(usedNonces.suffix(1_000))
        }
        return .accepted
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}
