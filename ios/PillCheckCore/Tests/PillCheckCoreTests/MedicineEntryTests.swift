import XCTest
@testable import PillCheckCore

final class MedicineEntryTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func draft() -> MedicineDraft {
        var value = MedicineDraft(startDate: day)
        value.name = "Sample medicine"; value.ingredient = "sample ingredient"
        value.frequency = "Twice daily"; value.times = "08:00, 18:00"
        return value
    }
    func testNewEntryDefaultsToPillsWithoutAssumingDose() {
        let value = draft()
        XCTAssertFalse(value.isLiquid)
        XCTAssertTrue(value.pillDose.isEmpty)
        XCTAssertThrowsError(try value.medication())
    }
    func testCombinedPillDosePreservesWholeAndFractionalAmounts() throws {
        for (text, amount, unit) in [("2 capsules", 2.0, "capsule"), ("1 tablet", 1, "tablet"), ("0.5 tablet", 0.5, "tablet"), ("1/2 tablet", 0.5, "tablet"), ("½ tablet", 0.5, "tablet")] {
            var value = draft(); value.strength = "100"; value.pillDose = text
            let med = try value.medication()
            XCTAssertEqual(med.doseQuantity, amount)
            XCTAssertEqual(med.doseUnit, unit)
            XCTAssertEqual(med.dailyMg, 100 * amount * 2)
        }
        for text in ["tablet", "0 tablets", "-1 tablet", "1/0 tablet", "1½ tablets", "2 mL", "1 tablet twice daily"] {
            XCTAssertThrowsError(try DoseEntry.pill(text), text)
        }
    }
    func testLiquidConcentrationAndVolumeAreDistinctAndPersist() throws {
        var value = draft(); value.isLiquid = true
        value.liquidStrength = "250 mg / 5 mL"; value.liquidAmount = "7.5"
        let med = try value.medication()
        XCTAssertEqual(med.strengthMg, 250)
        XCTAssertEqual(med.strengthVolumeMl, 5)
        XCTAssertEqual(med.doseQuantity, 7.5)
        XCTAssertEqual(med.doseUnit, "mL")
        XCTAssertEqual(med.dailyMg, 750)
        XCTAssertEqual(med.strengthText, "250 mg / 5 mL")
        XCTAssertEqual(med.doseText, "7.5 mL")
        let restored = try PillTime.decoder().decode(Medication.self, from: PillTime.encoder().encode(med))
        XCTAssertEqual(restored, med)
        XCTAssertEqual(try MedicineDraft(medicine: restored, now: day).medication().dailyMg, 750)
    }
    func testChangingFormDoesNotReusePillAmountAsLiquidVolume() throws {
        var value = draft(); value.strength = "500"; value.pillDose = "2 tablets"
        value.isLiquid = true
        XCTAssertThrowsError(try value.medication())
        value.liquidStrength = "250 mg / 5 mL"; value.liquidAmount = "5"
        XCTAssertEqual(try value.medication().dailyMg, 500)
        value.isLiquid = false
        XCTAssertEqual(try value.medication().doseQuantity, 2)
        XCTAssertEqual(try value.medication().strengthMg, 500)
        XCTAssertNil(try value.medication().strengthVolumeMl)
    }
    func testLiquidValidationRequiresExplicitConcentrationAndPositiveVolume() throws {
        for strength in ["250", "250 mg", "250 mg / 0 mL", "250 mg / -5 mL", "250 mg / 5 tsp"] {
            XCTAssertThrowsError(try DoseEntry.liquidStrength(strength), strength)
        }
        var value = draft(); value.isLiquid = true; value.liquidStrength = "250 mg / 5 mL"
        for amount in ["", "0", "-5", "NaN", "1/0"] {
            value.liquidAmount = amount
            XCTAssertThrowsError(try value.medication(), amount)
        }
        value.liquidStrength = "250 mg / 5 mL"; value.liquidAmount = "5"
        var med = try value.medication()
        med.strengthVolumeMl = Double.leastNonzeroMagnitude
        XCTAssertThrowsError(try MedicationEngine.validate(med))
    }
    func testScanDoesNotInferDoseFromLiquidConcentration() throws {
        var scan = ScanResult(name: "Sample liquid", ingredient: "sample ingredient", strengthMg: 250, doseQuantity: nil, doseUnit: "mL", frequency: "Once daily", times: ["08:00"], instructions: "", uncertainFields: ["doseQuantity"], explanation: "Copy the prescribed amount.", strengthVolumeMl: 5)
        let value = MedicineDraft(scan: scan, now: day)
        XCTAssertTrue(value.isLiquid)
        XCTAssertTrue(value.liquidAmount.isEmpty)
        XCTAssertFalse(value.liquidStrength.isEmpty)
        XCTAssertThrowsError(try value.medication())
        scan.doseQuantity = 2.5
        XCTAssertEqual(try MedicineDraft(scan: scan, now: day).medication().doseQuantity, 2.5)
        scan.strengthVolumeMl = nil
        XCTAssertTrue(MedicineDraft(scan: scan, now: day).liquidStrength.isEmpty)
    }
    func testExistingPillDoseAndHighRiskProtectionSurviveSimplifiedEditor() throws {
        var med = SeedData.medicines(now: day)[0]
        med.doseQuantity = 2
        XCTAssertEqual(try MedicineDraft(medicine: med, now: day).medication().doseQuantity, 2)
        med.highRisk = true
        XCTAssertTrue(try MedicineDraft(medicine: med, now: day).medication().highRisk)
        var value = draft(); value.name = "Warfarin"; value.ingredient = "warfarin"
        value.strength = "1"; value.pillDose = "1 tablet"
        XCTAssertTrue(try value.medication().highRisk)
    }
    func testEarlierRecordsLoadWithoutLiquidStrengthField() throws {
        let med = SeedData.medicines(now: day)[0]
        var json = try JSONSerialization.jsonObject(with: PillTime.encoder().encode(med)) as! [String: Any]
        json.removeValue(forKey: "strengthVolumeMl")
        let restored = try PillTime.decoder().decode(Medication.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, med)
        XCTAssertEqual(restored.dailyMg, 1000)
    }
}
