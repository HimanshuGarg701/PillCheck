import Foundation
import UIKit

struct MetaClient {
    // The credential remains in Vercel. This public URL contains no secret.
    let endpoint = URL(string: "https://pillcheck-zeta.vercel.app/api/ai")!

    private func post<T: Decodable>(_ body: [String: Any], as type: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw PillCheckError(error?["error"] as? String ?? "Meta could not complete the request. Your saved records have not changed.")
        }
        return try PillTime.decoder().decode(type, from: data)
    }
    func scan(image: Data) async throws -> ScanResult {
        guard let uiImage = UIImage(data: image) else { throw PillCheckError("Choose a readable label image.") }
        let size = uiImage.size
        let scale = min(1, 1500 / max(size.width, size.height))
        let resized = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale)).image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82), jpeg.count <= 2_500_000 else { throw PillCheckError("Choose a smaller photo of the label.") }
        return try await post(["task": "scan", "image": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"], as: ScanResult.self)
    }
    func scan(text: String) async throws -> ScanResult {
        try await post(["task": "scan", "text": text], as: ScanResult.self)
    }
    func identify(name: String) async throws -> IngredientIdentification {
        try await post(["task": "identify", "name": name], as: IngredientIdentification.self)
    }
    func reminder(medication: Medication, language: String) async throws -> String {
        struct Result: Decodable { let text: String }
        let result = try await post(["task": "speak", "language": language, "medications": [["name": medication.name, "doseQuantity": medication.doseQuantity, "doseUnit": medication.doseUnit]]], as: Result.self)
        return result.text
    }
    func replan(medication: Medication, dose: DoseEvent, future: [DoseEvent], language: String) async throws -> ReplanProposal {
        func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: PillTime.encoder().encode(value)) }
        return try await post(["task": "replan", "medication": try json(medication), "confirmed": try json(dose), "future": try json(future), "timeZone": TimeZone.current.identifier, "language": language], as: ReplanProposal.self)
    }
    func review(candidate: Medication, medications: [Medication]) async throws -> MedicationAIReview {
        func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: PillTime.encoder().encode(value)) }
        return try await post(["task": "review", "candidate": try json(candidate), "medications": try json(medications)], as: MedicationAIReview.self)
    }
    func checkConnection() async throws -> String {
        struct Result: Decodable { let message: String; let model: String }
        let result = try await post(["task": "connection"], as: Result.self)
        return "\(result.model): \(result.message)"
    }
}
