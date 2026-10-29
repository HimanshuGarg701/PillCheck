import Foundation

struct MedicineDraft: Identifiable, Equatable {
    var id = UUID()
    var original: Medication?
    var name = ""
    var ingredient = ""
    var isLiquid = false
    var strength = ""
    var pillDose = ""
    var liquidStrength = ""
    var liquidAmount = ""
    var frequency = ""
    var times = ""
    var instructions = ""
    var riskClass = ""
    var startDate = Date()
    var source = "manual-reviewed"
    var explanation = ""
    var uncertain: [String] = []

    init(startDate: Date = Date()) { self.startDate = startDate }
    init(medicine: Medication, now: Date) {
        original = medicine
        name = medicine.name; ingredient = medicine.ingredient
        isLiquid = medicine.isLiquid
        if isLiquid {
            liquidStrength = "\(medicine.strengthMg) mg / \(medicine.strengthVolumeMl ?? 1) mL"
            liquidAmount = String(medicine.doseQuantity)
        } else {
            strength = String(medicine.strengthMg)
            pillDose = "\(medicine.doseQuantity) \(medicine.doseUnit)"
        }
        frequency = medicine.frequency
        times = medicine.times.joined(separator: ", "); instructions = medicine.instructions
        riskClass = medicine.riskClass
        startDate = now; source = "manual-reviewed"
    }
    init(scan: ScanResult, now: Date) {
        name = scan.name ?? ""; ingredient = scan.ingredient ?? ""
        isLiquid = Medication.isLiquidUnit(scan.doseUnit ?? "") || scan.strengthVolumeMl != nil
        if isLiquid {
            if let mg = scan.strengthMg, let ml = scan.strengthVolumeMl {
                liquidStrength = "\(mg) mg / \(ml) mL"
            }
            // A concentration does not establish a prescribed dose volume.
            if Medication.isLiquidUnit(scan.doseUnit ?? "") {
                liquidAmount = scan.doseQuantity.map(String.init(describing:)) ?? ""
            }
        } else {
            strength = scan.strengthMg.map(String.init(describing:)) ?? ""
            if let count = scan.doseQuantity, let unit = scan.doseUnit {
                pillDose = "\(count) \(unit)"
            }
        }
        frequency = scan.frequency ?? ""
        times = scan.times.joined(separator: ", "); instructions = scan.instructions ?? ""
        startDate = now; source = "meta-reviewed"
        explanation = scan.explanation; uncertain = scan.uncertainFields
    }
    func medication() throws -> Medication {
        let mg: Double
        let volume: Double?
        let amount: Double
        let unit: String
        if isLiquid {
            let concentration = try DoseEntry.liquidStrength(liquidStrength)
            mg = concentration.mg; volume = concentration.ml
            guard let ml = DoseEntry.positiveNumber(liquidAmount) else { throw PillCheckError("Enter the prescribed amount in mL.") }
            amount = ml; unit = "mL"
        } else {
            guard let value = DoseEntry.positiveNumber(strength) else { throw PillCheckError("Confirm the strength in mg.") }
            mg = value; volume = nil
            let dose = try DoseEntry.pill(pillDose)
            amount = dose.amount; unit = dose.unit
        }
        return try MedicationEngine.validate(Medication(id: original?.id ?? id.uuidString, name: name, ingredient: ingredient, strengthMg: mg, doseQuantity: amount, doseUnit: unit, frequency: frequency, times: times.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, instructions: instructions, riskClass: riskClass, startDate: startDate, highRisk: original?.highRisk ?? false, source: source, strengthVolumeMl: volume))
    }
}

enum DoseEntry {
    static func positiveNumber(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^(?:\d+(?:\.\d+)?|\.\d+)$"#, options: .regularExpression) != nil,
              let number = Double(value), number.isFinite, number > 0 else { return nil }
        return number
    }
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
    static func pill(_ text: String) throws -> (amount: Double, unit: String) {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = normalized.first, let value = [Character("½"): "0.5", Character("¼"): "0.25", Character("¾"): "0.75"][first] {
            normalized = value + normalized.dropFirst()
        }
        guard let parts = captures(#"^((?:\d+(?:[.,]\d+)?|[.,]\d+)(?:\s*/\s*\d+)?)\s*(tablets?|capsules?|pills?|caplets?|softgels?|lozenges?)$"#, in: normalized) else {
            throw PillCheckError("Enter the full dose, for example 1 tablet or 2 capsules.")
        }
        let fraction = parts[0].split(separator: "/").map(String.init)
        guard let numerator = positiveNumber(fraction[0]) else { throw PillCheckError("Confirm the pill dose on your prescription.") }
        let amount: Double
        if fraction.count == 2 {
            guard let denominator = positiveNumber(fraction[1]) else { throw PillCheckError("Confirm the pill dose on your prescription.") }
            amount = numerator / denominator
        } else { amount = numerator }
        let unit = parts[1].lowercased()
        return (amount, unit.hasSuffix("s") ? String(unit.dropLast()) : unit)
    }
    static func liquidStrength(_ text: String) throws -> (mg: Double, ml: Double) {
        guard let parts = captures(#"^\s*((?:\d+(?:[.,]\d+)?|[.,]\d+))\s*mg\s*/\s*((?:\d+(?:[.,]\d+)?|[.,]\d+))\s*ml\s*$"#, in: text),
              let mg = positiveNumber(parts[0]), let ml = positiveNumber(parts[1]) else {
            throw PillCheckError("Copy the bottle strength with its volume, for example 250 mg / 5 mL.")
        }
        return (mg, ml)
    }
}
