import Foundation

public struct CommunicationDispatchResult: Equatable, Sendable {
    public var succeeded: Bool
    public var httpStatus: Int?
    public var attempts: Int
    public var error: String?

    public init(succeeded: Bool, httpStatus: Int?, attempts: Int, error: String? = nil) {
        self.succeeded = succeeded
        self.httpStatus = httpStatus
        self.attempts = attempts
        self.error = error
    }
}

public enum CommunicationGatewayDispatcher {
    public static func dispatch(_ preview: CommunicationDispatchPreview, session: URLSession = .shared, retryBudget: Int = 1) async -> CommunicationDispatchResult {
        if preview.method == "LOCAL" {
            return CommunicationDispatchResult(succeeded: true, httpStatus: nil, attempts: 0)
        }

        guard let url = URL(string: preview.endpoint), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return CommunicationDispatchResult(succeeded: false, httpStatus: nil, attempts: 0, error: "接口地址无效：\(redactedEndpoint(preview.endpoint))")
        }

        let maxAttempts = max(1, retryBudget + 1)
        var lastStatus: Int?
        var lastError: String?

        for attempt in 1...maxAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = preview.method
            request.timeoutInterval = 10
            request.httpBody = Data(preview.body.utf8)
            for (key, value) in preview.headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            do {
                let (_, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode
                lastStatus = status
                if let status, (200..<300).contains(status) {
                    return CommunicationDispatchResult(succeeded: true, httpStatus: status, attempts: attempt)
                }
                lastError = "HTTP \(status.map(String.init) ?? "未知状态")：\(redactedEndpoint(preview.endpoint))"
            } catch {
                lastError = "\(error.localizedDescription)：\(redactedEndpoint(preview.endpoint))"
            }
        }

        return CommunicationDispatchResult(succeeded: false, httpStatus: lastStatus, attempts: maxAttempts, error: lastError)
    }

    public static func redactedEndpoint(_ endpoint: String) -> String {
        guard var components = URLComponents(string: endpoint), components.host != nil else {
            return "无效地址"
        }
        components.path = "/***"
        components.query = nil
        components.fragment = nil
        return components.string ?? "已隐藏接口地址"
    }
}
