import Foundation

/// A bounded adult label-ceiling screen, never a personalized dose recommendation.
/// Keep unknown products, formulations and units unassessed rather than guessing.
struct MedicationDoseCheck: Codable, Equatable {
    let dailyMg: Double
    let adultMaximumDailyMg: Double
    let sourceURL: String
    var isHigh: Bool { dailyMg > adultMaximumDailyMg }
    var message: String {
        "The entered \(PillTime.number(dailyMg)) mg/day exceeds this medicine’s adult label maximum of \(PillTime.number(adultMaximumDailyMg)) mg/day. Confirm the dose with your pharmacist."
    }
    static func assess(_ medicine: Medication) -> Self? {
        guard MedicationEngine.canonical(medicine.ingredient) == "metformin",
              medicine.doseUnit.lowercased() == "tablet", !medicine.isLiquid,
              medicine.dailyMg.isFinite, medicine.dailyMg > 0 else { return nil }
        let maximum: Double
        switch IngredientIdentification.nameKey(medicine.name) {
        case "glucophage" where [500.0, 850, 1000].contains(medicine.strengthMg): maximum = 2550
        case "glucophage xr" where [500.0, 750].contains(medicine.strengthMg): maximum = 2000
        default: return nil
        }
        // FDA prescribing information, May 2018, §§2.1 and 3; reviewed 2026-11-04.
        // Other brands (including other metformin ER products) cannot inherit these ceilings.
        return Self(dailyMg: medicine.dailyMg, adultMaximumDailyMg: maximum,
            sourceURL: "https://www.accessdata.fda.gov/drugsatfda_docs/label/2018/020357s034,021202s018lbl.pdf")
    }
}
