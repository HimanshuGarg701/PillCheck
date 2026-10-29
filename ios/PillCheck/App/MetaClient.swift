import Foundation
import UIKit

struct MetaClient {
    // The credential remains in Vercel. This public URL contains no secret.
    let transport = AITransport()

    private func post<T: Decodable>(_ body: [String: Any], as type: T.Type) async throws -> T {
        try await transport.post(body, as: type)
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
}
