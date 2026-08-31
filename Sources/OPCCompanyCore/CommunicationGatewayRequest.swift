import Foundation

public struct CommunicationDispatchPreview: Hashable, Sendable {
    public var method: String
    public var endpoint: String
    public var headers: [String: String]
    public var body: String

    public init(method: String, endpoint: String, headers: [String: String], body: String) {
        self.method = method
        self.endpoint = endpoint
        self.headers = headers
        self.body = body
    }
}

public enum CommunicationGatewayRequestBuilder {
    public static func preview(for channel: CommunicationChannelConfig, text: String) -> CommunicationDispatchPreview? {
        let endpoint = channel.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty || channel.kind == .localOnly else { return nil }

        switch channel.kind {
        case .localOnly:
            return CommunicationDispatchPreview(
                method: "LOCAL",
                endpoint: "opc://local-command-bus",
                headers: [:],
                body: text
            )
        case .feishuWebhook:
            return jsonPreview(endpoint: endpoint, body: #"{"msg_type":"text","content":{"text":"\#(escaped(text))"}}"#)
        case .wecomWebhook, .dingtalkWebhook:
            return jsonPreview(endpoint: endpoint, body: #"{"msgtype":"text","text":{"content":"\#(escaped(text))"}}"#)
        case .telegramBot:
            let chatID = channel.chatID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chatID.isEmpty else { return nil }
            return jsonPreview(endpoint: endpoint, body: #"{"chat_id":"\#(escaped(chatID))","text":"\#(escaped(text))"}"#)
        case .emailDigest:
            return jsonPreview(endpoint: endpoint, body: #"{"subject":"OPC 团队负责人汇报","text":"\#(escaped(text))"}"#)
        }
    }

    private static func jsonPreview(endpoint: String, body: String) -> CommunicationDispatchPreview {
        CommunicationDispatchPreview(
            method: "POST",
            endpoint: endpoint,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    private static func escaped(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
        let encoded = String(data: data, encoding: .utf8) ?? #""""#
        return String(encoded.dropFirst().dropLast())
    }
}
