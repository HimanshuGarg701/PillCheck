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
    func testSkippingAIDoesNotGenerateRiskFlagsOrAcknowledgmentsAndPreventsExactDuplicates() throws {
        var state = SeedData.make(now: day)
        let candidate = try MedicineDraft.glucophageSample(startDate: day).medication()
        let before = state
        try MedicationEngine.save(candidate, replacing: nil, acknowledged: false, state: &state, now: day)
        XCTAssertEqual(state.flags, before.flags)
        XCTAssertTrue(state.audit.last!.reason.contains("No Risk Factor Check snapshot recorded."))
        XCTAssertFalse(state.audit.last!.reason.contains("acknowledged"))
        let after = state
        var duplicate = candidate; duplicate.id = "another-record"
        XCTAssertThrowsError(try MedicationEngine.save(duplicate, replacing: nil, acknowledged: true, state: &state, now: day))
        XCTAssertEqual(state, after)
    }
    func testOnlyRequestedReviewFindingsRequireAcknowledgment() throws {
        var state = SeedData.make(now: day)
        let candidate = try MedicineDraft.glucophageSample(startDate: day).medication()
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        let review = try PillTime.decoder().decode(MedicationAIReview.self, from: Data(contentsOf: url))
        XCTAssertTrue(review.requiresAcknowledgment)
        let before = state
        XCTAssertThrowsError(try MedicationEngine.save(candidate, replacing: nil, acknowledged: false, review: review, state: &state, now: day))
        XCTAssertEqual(state, before)
        try MedicationEngine.save(candidate, replacing: nil, acknowledged: true, review: review, state: &state, now: day)
        XCTAssertEqual(state.flags, before.flags)
        XCTAssertTrue(state.audit.last!.reason.contains("Risk Factor Check findings acknowledged."))
    }
    func testMoreThanSixPillsRequiresExactQuantityConfirmationWithoutBrandRules() throws {
        var draft = MedicineDraft.glucophageSample(startDate: day)
        for name in ["Glucophage", "Amlodipine", "Another medicine"] {
            draft.name = name
            for amount in [1, 6] {
                draft.pillDose = "\(amount) tablets"
                XCTAssertNil(draft.largePillDose)
                XCTAssertNoThrow(try draft.medicationForSaving(quantityConfirmed: false))
            }
            for amount in [7, 100, 200] {
                draft.pillDose = "\(amount) tablets"
                XCTAssertEqual(draft.largePillDose, "\(amount) tablets")
                XCTAssertThrowsError(try draft.medicationForSaving(quantityConfirmed: false))
                XCTAssertEqual(try draft.medicationForSaving(quantityConfirmed: true).doseQuantity, Double(amount))
                XCTAssertFalse(MedicationEngine.risks(for: try draft.medication(), in: SeedData.make(now: day), now: day).contains { $0.kind == "dose" })
            }
        }
        draft.pillDose = "6.5 capsules"
        XCTAssertEqual(draft.largePillDose, "6.5 capsules")
        draft.isLiquid = true; draft.liquidStrength = "250 mg / 5 mL"; draft.liquidAmount = "100"
        XCTAssertNil(draft.largePillDose)
        XCTAssertNoThrow(try draft.medicationForSaving(quantityConfirmed: false))
    }
    func testHistoricalDoseSnapshotsStillDecode() throws {
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        var review = try PillTime.decoder().decode(MedicationAIReview.self, from: Data(contentsOf: url))
        review.doseCheck = MedicationDoseCheck(dailyMg: 3000, adultMaximumDailyMg: 2550, sourceURL: "https://www.accessdata.fda.gov/")
        let restored = try PillTime.decoder().decode(MedicationAIReview.self, from: PillTime.encoder().encode(review))
        XCTAssertEqual(review, restored)
        XCTAssertTrue(restored.hasDoseConcern)
        XCTAssertNotNil(restored.doseConsultationConcern)
    }
    func testConciseFindingsKeepIncompleteChecksSeparateFromRisks() throws {
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        var review = try PillTime.decoder().decode(MedicationAIReview.self, from: Data(contentsOf: url))
        XCTAssertNil(review.doseCheck) // Earlier snapshots still decode.
        let duplicate = try XCTUnwrap(review.pairs.first)
        XCTAssertTrue(duplicate.hasRisk)
        XCTAssertTrue(duplicate.conciseMessage.contains(duplicate.medicationName))
        let unknown = MedicationAIReview.Pair(medicationId: "unknown", medicationName: "Other medicine", status: "active", ingredientFinding: "uncertain", overlapIngredients: [], duplicateBasis: "", interactionFinding: "uncertain", spacingMinutes: nil, spacingSourceId: nil, explanation: "Missing references", evidence: [])
        XCTAssertFalse(unknown.hasRisk)
        XCTAssertTrue(unknown.needsMoreInformation)
        XCTAssertEqual(unknown.conciseMessage, "Couldn’t fully check against Other medicine.")
        XCTAssertNil(review.doseAssessment)
        review.doseAssessment = MedicationDoseAssessment(finding: "potential_high_dose", basis: "strength_or_daily_total", source: "meta", evidence: [], message: "The entered dose may be too high. Confirm the amount with your pharmacist.")
        XCTAssertTrue(review.hasDoseConcern)
        XCTAssertNotNil(review.doseConsultationConcern)
        XCTAssertTrue(review.doseConsultationConcern!.sources.isEmpty)
        XCTAssertEqual(try PillTime.decoder().decode(MedicationAIReview.self, from: PillTime.encoder().encode(review)), review)
    }
}
