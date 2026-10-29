import Foundation

struct AITransport {
    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = URL(string: "https://pillcheck-zeta.vercel.app/api/ai")!) {
        self.session = session
        self.endpoint = endpoint
    }

    func post<T: Decodable>(_ body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw PillCheckError("The AI service could not be reached. Please try again.") }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 429 { throw PillCheckError("Please wait a minute before trying another AI check.") }
                if (400..<500).contains(http.statusCode), let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let message = error["error"] as? String {
                    throw PillCheckError(String(message.prefix(500)))
                }
                throw PillCheckError("The AI service is temporarily unavailable. Please try again.")
            }
            do { return try PillTime.decoder().decode(type, from: data) }
            catch { throw PillCheckError("The AI response could not be read. Please run the check again.") }
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw PillCheckError("The AI check took too long. Please try again.")
            case .notConnectedToInternet, .networkConnectionLost:
                throw PillCheckError("An internet connection is needed for this check. Reconnect and try again.")
            default: throw PillCheckError("The AI service could not be reached. Please try again.")
            }
        }
    }
}
