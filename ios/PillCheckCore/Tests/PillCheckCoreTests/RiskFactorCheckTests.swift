import XCTest
@testable import PillCheckCore

final class RiskFactorCheckTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func testMedicineCanBeAddedWithoutAIReviewAndHistoryIsPreserved() throws {
        var state = SeedData.make(now: day)
        let history = state.doses
        var draft = MedicineDraft.glucophageSample(startDate: day)
        draft.name = "Recorded medicine"; draft.ingredient = "recorded ingredient"
        let saved = try MedicationEngine.save(draft.medication(), replacing: nil, acknowledged: false, state: &state, now: day)
        XCTAssertTrue(state.medications.contains(saved))
        XCTAssertTrue(state.medicationReviews?.isEmpty ?? true)
        for dose in history { XCTAssertEqual(state.doses.first { $0.id == dose.id }, dose) }
    }
    func testSkippingAIStillRequiresLocalRiskAcknowledgmentAndPreventsExactDuplicates() throws {
        var state = SeedData.make(now: day)
        let candidate = try MedicineDraft.glucophageSample(startDate: day).medication()
        let before = state
        XCTAssertThrowsError(try MedicationEngine.save(candidate, replacing: nil, acknowledged: false, state: &state, now: day))
        XCTAssertEqual(state, before)
        try MedicationEngine.save(candidate, replacing: nil, acknowledged: true, state: &state, now: day)
        let after = state
        var duplicate = candidate; duplicate.id = "another-record"
        XCTAssertThrowsError(try MedicationEngine.save(duplicate, replacing: nil, acknowledged: true, state: &state, now: day))
        XCTAssertEqual(state, after)
    }
    func testDoseCeilingUsesProductFormStrengthAndRecordedDailyAmount() throws {
        var medicine = try MedicineDraft.glucophageSample(startDate: day).medication()
        XCTAssertFalse(try XCTUnwrap(MedicationDoseCheck.assess(medicine)).isHigh)
        medicine.doseQuantity = 3
        let dose = try XCTUnwrap(MedicationDoseCheck.assess(medicine))
        XCTAssertEqual(dose.dailyMg, 3000)
        XCTAssertEqual(dose.adultMaximumDailyMg, 2550)
        XCTAssertTrue(dose.isHigh)
        XCTAssertTrue(MedicationEngine.risks(for: medicine, in: SeedData.make(now: day), now: day).contains { $0.kind == "dose" })
        medicine.name = "Glucophage XR"; medicine.doseQuantity = 2
        XCTAssertFalse(try XCTUnwrap(MedicationDoseCheck.assess(medicine)).isHigh)
        medicine.strengthMg = 750
        XCTAssertTrue(try XCTUnwrap(MedicationDoseCheck.assess(medicine)).isHigh)
        for name in ["Metformin", "Fortamet", "Glumetza", "Unknown"] {
            medicine.name = name
            XCTAssertNil(MedicationDoseCheck.assess(medicine))
        }
        medicine.name = "Glucophage"; medicine.strengthMg = 500
        medicine.doseUnit = "mL"; medicine.strengthVolumeMl = 5
        XCTAssertNil(MedicationDoseCheck.assess(medicine))
        medicine.doseUnit = "tablet"; medicine.strengthVolumeMl = nil; medicine.ingredient = "another ingredient"
        XCTAssertNil(MedicationDoseCheck.assess(medicine))
        medicine.ingredient = "metformin"; medicine.strengthMg = 750
        XCTAssertNil(MedicationDoseCheck.assess(medicine))
    }
    func testConciseFindingsKeepIncompleteChecksSeparateFromRisks() throws {
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        var review = try PillTime.decoder().decode(MedicationAIReview.self, from: Data(contentsOf: url))
        XCTAssertNil(review.doseCheck) // Earlier snapshots still decode.
        let duplicate = try XCTUnwrap(review.pairs.first)
        XCTAssertTrue(duplicate.hasRisk)
        XCTAssertTrue(duplicate.conciseMessage.contains(duplicate.medicationName))
        XCTAssertTrue(review.represents(RiskFlag(kind: "duplicate", title: "Duplicate", explanation: "Shared ingredient", medications: [duplicate.medicationId], at: day)))
        XCTAssertFalse(review.represents(RiskFlag(kind: "interaction", title: "Interaction", explanation: "Known concern", medications: ["unresolved-by-ai"], at: day)))
        XCTAssertFalse(review.represents(RiskFlag(kind: "history", title: "History", explanation: "Recorded concern", at: day)))
        let unknown = MedicationAIReview.Pair(medicationId: "unknown", medicationName: "Other medicine", status: "active", ingredientFinding: "uncertain", overlapIngredients: [], duplicateBasis: "", interactionFinding: "uncertain", spacingMinutes: nil, spacingSourceId: nil, explanation: "Missing references", evidence: [])
        XCTAssertFalse(unknown.hasRisk)
        XCTAssertTrue(unknown.needsMoreInformation)
        XCTAssertEqual(unknown.conciseMessage, "Couldn’t fully check against Other medicine.")
        var medicine = try MedicineDraft.glucophageSample(startDate: day).medication(); medicine.doseQuantity = 3
        review.doseCheck = MedicationDoseCheck.assess(medicine)
        XCTAssertNotNil(review.doseConsultationConcern)
        XCTAssertEqual(try PillTime.decoder().decode(MedicationAIReview.self, from: PillTime.encoder().encode(review)), review)
    }
}
