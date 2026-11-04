import XCTest
@testable import PillCheckCore

final class ConsultationReminderTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func review(changes: (inout [String: Any]) -> Void = { _ in }) throws -> MedicationAIReview {
        let url = Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        changes(&json)
        return try PillTime.decoder().decode(MedicationAIReview.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func state() -> PillCheckState {
        var state = SeedData.make(now: day)
        for i in state.medications.indices { state.medications[i].id = state.medications[i].id.replacingOccurrences(of: "med-", with: "") }
        for i in state.doses.indices { state.doses[i].medicationId = state.doses[i].medicationId.replacingOccurrences(of: "med-", with: "") }
        var candidate = state.medications[0]; candidate.id = "candidate"; candidate.name = "Glucophage"
        state.medications.append(candidate)
        return state
    }

    func testLegacyRecordsAndReviewDecodeWithoutConsultationFields() throws {
        let original = state()
        let data = try PillTime.encoder().encode(original)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("consultationReminders"))
        XCTAssertEqual(try PillTime.decoder().decode(PillCheckState.self, from: data), original)
        XCTAssertNil(try review().savedMedicationID)
    }

    func testRepeatAndReverseReviewsDeduplicatePendingWithoutDiscardingSnapshot() throws {
        var state = state()
        let concern = try review().consultationConcerns[0]
        try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day)
        let initial = state
        let reversed = ConsultationConcern(medicines: concern.medicines.reversed(), title: "New review", detail: "New explanation", reviewedAt: day,
                                          reviewID: "fresh-review", sources: [], evidence: [])
        try ConsultationReminderEngine.setSelected(true, concern: reversed, state: &state, at: day.addingTimeInterval(30))
        XCTAssertEqual(state, initial)
        XCTAssertEqual(state.consultationReminders?.count, 1)
        XCTAssertEqual(state.consultationReminders?.first?.concern, concern)
        XCTAssertEqual(try PillTime.decoder().decode(PillCheckState.self, from: PillTime.encoder().encode(state)), state)
    }

    func testCompleteReopenAndUncheckPreserveMedicationAndWarningHistory() throws {
        var state = state()
        state.remindersEnabled = true
        let original = state
        let concern = try review().consultationConcerns[0]
        try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day)
        let id = try XCTUnwrap(state.consultationReminders?.first?.id)
        let completedAt = day.addingTimeInterval(120)
        try ConsultationReminderEngine.setStatus(.completed, id: id, state: &state, at: completedAt)
        state = try PillTime.decoder().decode(PillCheckState.self, from: PillTime.encoder().encode(state))
        XCTAssertEqual(state.consultationReminders?.first?.completedAt, completedAt)
        XCTAssertNil(ConsultationReminderEngine.pending(for: concern, in: state))
        try ConsultationReminderEngine.setStatus(.pending, id: id, state: &state, at: day.addingTimeInterval(180))
        XCTAssertNil(state.consultationReminders?.first?.completedAt)
        try ConsultationReminderEngine.setSelected(false, concern: concern, state: &state, at: day.addingTimeInterval(240))
        XCTAssertEqual(state.consultationReminders?.first?.status, .removed)
        XCTAssertEqual(state.consultationReminders?.count, 1)
        XCTAssertEqual(state.medications, original.medications)
        XCTAssertEqual(state.doses, original.doses)
        XCTAssertEqual(state.flags, original.flags)
        XCTAssertEqual(state.changes, original.changes)
        XCTAssertEqual(state.remindersEnabled, original.remindersEnabled)
        let plan = ReminderPlanner.plan(state: state, now: day)
        let originalPlan = ReminderPlanner.plan(state: original, now: day)
        XCTAssertFalse(plan.requests.isEmpty)
        XCTAssertEqual(plan.requests, originalPlan.requests)
        XCTAssertEqual(plan.coveredThrough, originalPlan.coveredThrough)
        XCTAssertEqual(plan.truncated, originalPlan.truncated)
    }

    func testNewFollowUpAfterCompletionRetainsHistoryAndPreventsDuplicateReopen() throws {
        var state = state()
        let concern = try review().consultationConcerns[0]
        try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day)
        let firstID = state.consultationReminders![0].id
        try ConsultationReminderEngine.setStatus(.completed, id: firstID, state: &state, at: day)
        try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day)
        let before = state
        XCTAssertEqual(state.consultationReminders?.map(\.status), [.completed, .pending])
        XCTAssertThrowsError(try ConsultationReminderEngine.setStatus(.pending, id: firstID, state: &state, at: day))
        XCTAssertEqual(state, before)
    }

    func testUnknownUnsavedMedicationCannotCreateReminder() throws {
        var state = SeedData.make(now: day)
        let before = state
        let concern = try review().consultationConcerns[0]
        XCTAssertThrowsError(try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day))
        XCTAssertThrowsError(try ConsultationReminderEngine.setStatus(.completed, id: "missing", state: &state, at: day))
        XCTAssertEqual(state, before)
    }

    func testEditedRegimenReminderAndSavedReviewUseNewMedicationID() throws {
        var state = state()
        var review = try review()
        let concern = review.consultationConcerns[0]
        var candidate = state.medications.first { $0.id == "candidate" }!
        candidate.startDate = day
        let saved = try MedicationEngine.save(candidate, replacing: candidate.id, acknowledged: true, state: &state, now: day)
        XCTAssertNotEqual(saved.id, candidate.id)
        let linked = concern.replacingMedicine(candidate.id, with: saved)
        try ConsultationReminderEngine.setSelected(true, concern: linked, state: &state, at: day)
        review.savedMedicationID = saved.id
        XCTAssertEqual(review.consultationConcerns[0].id, linked.id)
        XCTAssertNotNil(ConsultationReminderEngine.pending(for: review.consultationConcerns[0], in: state))
        XCTAssertEqual(state.medications.first { $0.id == candidate.id }?.status, .stopped)
        XCTAssertTrue(state.consultationReminders![0].concern.medicines.contains { $0.id == saved.id })
    }

    func testOnlyFlaggedOrIncompletePairsOfferConsultation() throws {
        XCTAssertEqual(try review().consultationConcerns.count, 3)
        let result = try review { json in
            var pairs = json["pairs"] as! [[String: Any]]
            pairs[0]["ingredientFinding"] = "different_ingredients"
            pairs[0]["interactionFinding"] = "not_identified_in_references"
            pairs[1]["ingredientFinding"] = "different_ingredients"
            pairs[1]["interactionFinding"] = "potential_interaction"
            pairs[1]["evidence"] = [["sourceId": "label-metformin", "quote": "Reference quote"]]
            pairs[2]["ingredientFinding"] = "uncertain"
            pairs[2]["interactionFinding"] = "not_identified_in_references"
            json["pairs"] = pairs
        }
        XCTAssertNil(result.consultationConcern(for: result.pairs[0]))
        XCTAssertEqual(result.consultationConcerns.count, 2)
        XCTAssertEqual(result.consultationConcerns[0].title, "Potential interaction")
        XCTAssertEqual(result.consultationConcerns[1].title, "Ingredient identity needs review")
        XCTAssertEqual(result.consultationConcerns[0].evidence.first?.quote, "Reference quote")
        XCTAssertTrue(result.consultationConcerns[0].sources.contains { $0.truncated })
    }

    func testOfflineRiskLinksBothMedicinesAndDeduplicatesReversePair() throws {
        var state = SeedData.make(now: day)
        var other = state.medications[0]; other.id = "cimetidine"; other.name = "Cimetidine"; other.ingredient = "cimetidine"
        state.medications.append(other)
        let flags = MedicationEngine.activeRisks(state, now: day).filter { $0.kind == "interaction" }
        XCTAssertEqual(flags.count, 1)
        let concern = try XCTUnwrap(ConsultationConcern.from(flag: flags[0], medications: state.medications))
        XCTAssertEqual(Set(concern.medicines.map(\.id)), Set(["med-metformin", "cimetidine"]))
        try ConsultationReminderEngine.setSelected(true, concern: concern, state: &state, at: day)
        XCTAssertEqual(state.consultationReminders?.count, 1)
        XCTAssertEqual(state.consultationReminders?.first?.concern.sources.first?.url, flags[0].sourceURL)
    }
}
