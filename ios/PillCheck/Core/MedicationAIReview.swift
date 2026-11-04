import Foundation

struct IngredientIdentification: Codable, Equatable {
    static func nameKey(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
    let name: String
    let matchedName: String
    let status: String
    let ingredients: [String]
    let sourceURL: String?
    let source: String
    let aiStatus: String
    let model: String?
    let message: String
    var matched: Bool { status == "matched" && !ingredients.isEmpty }
}

struct MedicationAIReview: Identifiable, Codable, Equatable {
    struct Identity: Identifiable, Codable, Equatable {
        var id: String { medicationId }
        let medicationId: String
        let name: String
        let status: String
        let ingredients: [String]
        let ingredientIds: [String]
        let preciseIngredients: [String]
        let sourceURL: String?
    }
    struct Source: Identifiable, Codable, Equatable {
        let id: String
        let title: String
        let url: String
        let truncated: Bool
        let note: String
    }
    struct Evidence: Codable, Equatable { let sourceId: String; let quote: String }
    struct Pair: Identifiable, Codable, Equatable {
        var id: String { medicationId }
        let medicationId: String
        let medicationName: String
        let status: String
        let ingredientFinding: String
        let overlapIngredients: [String]
        let duplicateBasis: String
        let interactionFinding: String
        let spacingMinutes: Int?
        let spacingSourceId: String?
        let explanation: String
        let evidence: [Evidence]
        var hasRisk: Bool { ingredientFinding == "possible_duplicate" || interactionFinding == "potential_interaction" || spacingMinutes != nil }
        var needsMoreInformation: Bool { ingredientFinding == "uncertain" || interactionFinding == "uncertain" }
        var conciseMessage: String {
            var messages: [String] = []
            if ingredientFinding == "possible_duplicate" { messages.append("May contain the same active ingredient as \(medicationName).") }
            if interactionFinding == "potential_interaction" { messages.append("May not go well with \(medicationName).") }
            if let minutes = spacingMinutes { messages.append("Ask your pharmacist about separating them by at least \(PillTime.number(Double(minutes) / 60)) hours.") }
            if messages.isEmpty { messages.append("Couldn’t fully check against \(medicationName).") }
            return messages.joined(separator: " ")
        }
        var ingredientTitle: String {
            switch ingredientFinding {
            case "possible_duplicate": "Possible same ingredient / different brand"
            case "different_ingredients": "Different ingredients identified"
            default: "Ingredient identity needs review"
            }
        }
        var interactionTitle: String {
            switch interactionFinding {
            case "potential_interaction": "Potential interaction"
            case "not_identified_in_references": "No interaction identified in the retrieved excerpts"
            default: "Interaction check is incomplete"
            }
        }
    }
    struct Timing: Codable, Equatable {
        let status: String
        let explanation: String
        let proposedTimes: [String]
        let conflicts: [String]
    }
    let id: String
    let createdAt: Date
    let candidateName: String
    let aiStatus: String
    let summary: String
    let identities: [Identity]
    let sources: [Source]
    let pairs: [Pair]
    let warnings: [String]
    let timing: Timing
    let source: String
    let model: String
    let requestId: String?
    // Associates an intake snapshot with the regimen actually saved after an edit.
    var savedMedicationID: String? = nil
    var doseCheck: MedicationDoseCheck? = nil
    var doseAssessment: MedicationDoseAssessment? = nil
    var hasDoseConcern: Bool { doseAssessment?.isHigh ?? (doseCheck?.isHigh == true) }
    var doseConcernMessage: String? { hasDoseConcern ? (doseAssessment?.message ?? doseCheck?.message) : nil }
    var completed: Bool { aiStatus == "completed" }
    var alertPairs: [Pair] { pairs.filter(\.hasRisk) }
    var incompletePairs: [Pair] { pairs.filter { !$0.hasRisk && $0.needsMoreInformation } }
    var requiresAcknowledgment: Bool { !alertPairs.isEmpty || hasDoseConcern }
}
