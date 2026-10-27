import Foundation

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
    var completed: Bool { aiStatus == "completed" }
}
