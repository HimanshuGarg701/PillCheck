import XCTest
@testable import PillCheckCore

final class SafetyTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func time(_ value: String) -> Date { PillTime.at(day, value)! }

    func testDuplicateIncludesSaltAliasAndCombinedDailyAmount() {
        let state = SeedData.make(now: day)
        var candidate = state.medications[0]
        candidate.id = "brand"; candidate.name = "Glucophage"; candidate.ingredient = "Metformin hydrochloride"
        let flags = MedicationEngine.risks(for: candidate, in: state, now: day)
        XCTAssertEqual(flags.first?.combinedMg, 2000)
        XCTAssertFalse(flags.first!.explanation.contains("safe to mix"))
        var mutable = state
        XCTAssertThrowsError(try MedicationEngine.save(candidate, replacing: nil, acknowledged: false, state: &mutable, now: day))
        XCTAssertEqual(state, mutable)
    }
    func testHighRiskCannotBeTurnedOffByCheckbox() throws {
        var med = SeedData.medicines(now: day)[0]
        med.name = "Warfarin"; med.highRisk = false
        XCTAssertTrue(try MedicationEngine.validate(med).highRisk)
        XCTAssertFalse(MedicationEngine.replanEligible(med))
    }
    func testConfirmationIsAtomicAndCannotDoubleRecord() throws {
        var state = SeedData.make(now: day)
        let morning = state.doses.filter { PillTime.sameDay($0.scheduledAt, day) && $0.scheduledAt == time("08:00") }
        try MedicationEngine.confirm(morning.map(\.id), state: &state, at: time("10:00"), method: "voice")
        let saved = state
        XCTAssertThrowsError(try MedicationEngine.confirm(morning.map(\.id), state: &state, at: time("10:05"), method: "button"))
        XCTAssertEqual(saved, state)
        XCTAssertEqual(state.doses.first { $0.id == morning[0].id }?.confirmedAt, time("10:00"))
        XCTAssertEqual(state.doses.first { $0.id == morning[0].id }?.status, .takenLate)
        XCTAssertEqual(state.doses.first { $0.id == morning[0].id }?.method, "voice")
    }
    func testReplanPreservesQuantitiesAndRejectsInvalidSpacing() throws {
        var state = SeedData.make(now: day)
        let med = state.medications[0]
        let first = state.doses.first { $0.medicationId == med.id && $0.scheduledAt == time("08:00") }!
        try MedicationEngine.confirm([first.id], state: &state, at: time("10:00"), method: "button")
        let confirmed = state.doses.first { $0.id == first.id }!
        let future = state.doses.first { $0.medicationId == med.id && $0.scheduledAt == time("18:00") }!
        let before = state
        for (quantity, newTime) in [(2.0, "20:00"), (1.0, "18:00")] {
            let bad = ReplanProposal(changes: [.init(doseId: future.id, newTime: time(newTime), doseQuantity: quantity)], explanation: "Fictional schedule adjustment.")
            XCTAssertThrowsError(try MedicationEngine.apply(bad, medication: med, confirmed: confirmed, state: &state))
            XCTAssertEqual(before, state)
        }
        let good = ReplanProposal(changes: [.init(doseId: future.id, newTime: time("20:00"), doseQuantity: 1)], explanation: "The evening event shifts later in this fictional example.", source: "meta")
        try MedicationEngine.apply(good, medication: med, confirmed: confirmed, state: &state)
        XCTAssertEqual(state.doses.first { $0.id == future.id }?.scheduledAt, time("20:00"))
        XCTAssertEqual(state.changes.first?.oldTime, time("18:00"))
        XCTAssertEqual(state.medications, before.medications)
    }
    func testRegimenUpdatePreservesEarlierDosesAndDoesNotBackfillNewPastTimes() throws {
        var state = SeedData.make(now: day)
        let original = state.medications[1]
        let oldDoses = state.doses.filter { $0.medicationId == original.id && $0.scheduledAt < time("10:00") }
        var updated = original
        updated.times = ["07:00", "18:00"]; updated.startDate = PillTime.day(day)
        try MedicationEngine.save(updated, replacing: original.id, acknowledged: true, state: &state, now: time("10:00"))
        MedicationEngine.catchUp(&state, now: time("10:00"))
        XCTAssertEqual(state.medications.first { $0.id == original.id }?.status, .stopped)
        let new = state.medications.last!
        XCTAssertFalse(state.doses.contains { $0.medicationId == new.id && $0.scheduledAt < time("10:00") })
        for dose in oldDoses where dose.status != .pending { XCTAssertEqual(state.doses.first { $0.id == dose.id }, dose) }
        XCTAssertEqual(state.doses.filter { $0.medicationId == new.id }.count, 1)
    }
    func testRecentlyStoppedInteractionAndClassConcern() {
        var state = SeedData.make(now: day)
        state.medications[0].status = .stopped; state.medications[0].endDate = PillTime.addingDays(-1, to: day)
        state.problems = ["antihistamine"]
        let candidate = Medication(name: "Cimetidine", ingredient: "cimetidine", strengthMg: 200, doseQuantity: 1, doseUnit: "tablet", frequency: "Once daily", times: ["12:00"], riskClass: "antihistamine", startDate: day)
        let flags = MedicationEngine.risks(for: candidate, in: state, now: day)
        XCTAssertTrue(flags.contains { $0.kind == "interaction" && $0.sourceURL != nil })
        XCTAssertTrue(flags.contains { $0.kind == "history" })
    }
    func testRolloverPreservesHistoryAndGeneratesUniqueEvents() {
        var state = SeedData.make(now: day)
        let complete = state.doses.filter { $0.status.isTaken }
        let tomorrow = PillTime.addingDays(1, to: time("10:00"))
        MedicationEngine.catchUp(&state, now: tomorrow)
        MedicationEngine.catchUp(&state, now: tomorrow)
        XCTAssertEqual(Set(state.doses.map(\.id)).count, state.doses.count)
        for dose in complete { XCTAssertEqual(state.doses.first { $0.id == dose.id }, dose) }
    }
    func testNotificationCadenceBoundedQueueAndConfirmationCancellation() throws {
        var state = SeedData.make(now: day)
        state.remindersEnabled = true
        let plan = ReminderPlanner.plan(state: state, now: time("07:59"))
        XCTAssertEqual(plan.requests.count, 60)
        XCTAssertTrue(plan.truncated)
        let morning = plan.requests.filter { $0.scheduledAt == time("08:00") }
        XCTAssertEqual(morning.map { Int($0.fireAt.timeIntervalSince(time("08:00")) / 60) }, [0, 15, 45, 75, 105])
        XCTAssertTrue(morning.allSatisfy { $0.doseIDs.count == 2 })
        try MedicationEngine.confirm(morning[0].doseIDs, state: &state, at: time("08:01"), method: "button")
        XCTAssertFalse(ReminderPlanner.plan(state: state, now: time("08:01")).requests.contains { $0.scheduledAt == time("08:00") })
        state.practiceClockEnabled = true
        XCTAssertTrue(ReminderPlanner.plan(state: state, now: time("08:01")).requests.isEmpty)
    }
    func testPersistenceRoundTripUsesUTCAndPreservesAudit() throws {
        let state = SeedData.make(now: day)
        let data = try PillTime.encoder().encode(state)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Z\""))
        XCTAssertEqual(try PillTime.decoder().decode(PillCheckState.self, from: data), state)
    }
}
