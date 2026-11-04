import Foundation

/// Legacy snapshot format. Kept only to read earlier saved reviews.
/// New dose assessments come from Meta; there is no product-specific dose table.
struct MedicationDoseCheck: Codable, Equatable {
    let dailyMg: Double
    let adultMaximumDailyMg: Double
    let sourceURL: String
    var isHigh: Bool { dailyMg > adultMaximumDailyMg }
    var message: String {
        "The entered \(PillTime.number(dailyMg)) mg/day exceeds this medicine’s adult label maximum of \(PillTime.number(adultMaximumDailyMg)) mg/day. Confirm the dose with your pharmacist."
    }
}

struct MedicationDoseAssessment: Codable, Equatable {
    let finding: String
    let basis: String
    let source: String
    let evidence: [MedicationAIReview.Evidence]
    let message: String
    var isHigh: Bool { finding == "potential_high_dose" }
    var isIncomplete: Bool { finding != "potential_high_dose" && finding != "not_flagged" }
}
