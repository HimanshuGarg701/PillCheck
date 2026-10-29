import XCTest
@testable import PillCheckCore

private final class ReviewURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.respond!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class AITransportTests: XCTestCase {
    func client() -> AITransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewURLProtocol.self]
        return AITransport(session: URLSession(configuration: config), endpoint: URL(string: "https://pillcheck.test/api/ai")!)
    }
    func testValidReviewDecodesThroughTransport() async throws {
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        ReviewURLProtocol.respond = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 60)
            return (200, data)
        }
        let review = try await client().post(["task": "review"], as: MedicationAIReview.self)
        XCTAssertFalse(review.completed)
        XCTAssertFalse(review.identities.isEmpty)
    }
    func testMalformedOrIncompleteResponseIsRecoverable() async {
        for text in ["<html>server error</html>", "{}", "{\"id\":null}"] {
            ReviewURLProtocol.respond = { _ in (200, Data(text.utf8)) }
            do {
                _ = try await client().post(["task": "review"], as: MedicationAIReview.self)
                XCTFail("Invalid review must not render")
            } catch { XCTAssertEqual(error.localizedDescription, "The AI response could not be read. Please run the check again.") }
        }
    }
    func testHTTPFailuresOfferRetryWithoutExposingProviderDetails() async {
        for status in [429, 502, 504] {
            ReviewURLProtocol.respond = { _ in (status, Data("{\"error\":\"model routing detail\"}".utf8)) }
            do {
                _ = try await client().post(["task": "review"], as: MedicationAIReview.self)
                XCTFail("Failed response must not be a review")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("routing"))
                XCTAssertTrue(error.localizedDescription.contains(status == 429 ? "wait a minute" : "try again"))
            }
        }
    }
    func testTimeoutAndOfflineErrorsExplainHowToRetry() async {
        for (code, message) in [(URLError.timedOut, "took too long"), (.notConnectedToInternet, "internet connection"), (.networkConnectionLost, "Reconnect")] {
            ReviewURLProtocol.respond = { _ in throw URLError(code) }
            do {
                _ = try await client().post(["task": "review"], as: MedicationAIReview.self)
                XCTFail("Network failure must not be a review")
            } catch { XCTAssertTrue(error.localizedDescription.contains(message)) }
        }
    }
    func testCancellationIsNotShownAsAReviewFailure() async {
        ReviewURLProtocol.respond = { _ in throw URLError(.cancelled) }
        do {
            _ = try await client().post(["task": "review"], as: MedicationAIReview.self)
            XCTFail("Cancelled request must not produce a review")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
