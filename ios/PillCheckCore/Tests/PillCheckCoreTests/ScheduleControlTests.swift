import XCTest
@testable import PillCheckCore

final class ScheduleControlTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func time(_ text: String) -> Date { PillTime.at(day, text)! }

    func testPauseCancelsDueAndFutureRemindersButPreservesCheckInsAndOtherMedicines() throws {
        var state = SeedData.make(now: day)
        state.remindersEnabled = true
        let med = state.medications[0]
        let history = state.doses.filter { $0.status != .pending }
        let otherDoses = state.doses.filter { $0.medicationId != med.id }
        try MedicationEngine.setSchedulePaused(true, for: med.id, state: &state, now: time("08:01"))
        XCTAssertTrue(state.medications[0].isSchedulePaused)
        XCTAssertEqual(state.medications[0].status, .active)
        XCTAssertTrue(state.doses.filter { $0.medicationId == med.id && $0.scheduledAt >= time("08:00") }.allSatisfy { $0.status == .cancelled })
        for dose in history { XCTAssertEqual(state.doses.first { $0.id == dose.id }, dose) }
        XCTAssertEqual(otherDoses, state.doses.filter { $0.medicationId != med.id })
        let plan = ReminderPlanner.plan(state: state, now: time("08:01"))
        XCTAssertFalse(plan.requests.flatMap(\.doseIDs).contains { $0.hasPrefix(med.id + ":") })
        XCTAssertFalse(plan.requests.isEmpty)
        XCTAssertTrue(MedicationEngine.schedule(state.medications[0], on: PillTime.addingDays(1, to: day)).isEmpty)
    }

    func testResumeOnlyFutureDosesAndNoBackfillAfterDaysPausedOrRelaunch() throws {
        var state = SeedData.make(now: day)
        let id = state.medications[0].id
        try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("07:00"))
        state = try PillTime.decoder().decode(PillCheckState.self, from: PillTime.encoder().encode(state))
        let resume = PillTime.addingDays(3, to: time("12:00"))
        try MedicationEngine.setSchedulePaused(false, for: id, state: &state, now: resume)
        MedicationEngine.catchUp(&state, now: resume)
        MedicationEngine.catchUp(&state, now: resume)
        XCTAssertEqual(Set(state.doses.map(\.id)).count, state.doses.count)
        let duringPause = state.doses.filter { $0.medicationId == id && $0.scheduledAt >= time("07:00") && $0.scheduledAt <= resume }
        XCTAssertTrue(duringPause.allSatisfy { $0.status == .cancelled })
        XCTAssertEqual(state.doses.filter { $0.medicationId == id && $0.scheduledAt > resume }.map(\.scheduledAt), [PillTime.addingDays(3, to: time("18:00"))])
        XCTAssertEqual(MedicationEngine.schedule(state.medications[0], on: PillTime.addingDays(4, to: day)).count, 2)
    }

    func testSameDayResumeAndRepeatedPausePreservePastCancellations() throws {
        var state = SeedData.make(now: day)
        let id = state.medications[0].id
        try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("07:00"))
        try MedicationEngine.setSchedulePaused(false, for: id, state: &state, now: time("08:00"))
        MedicationEngine.catchUp(&state, now: time("08:00"))
        XCTAssertEqual(state.doses.first { $0.medicationId == id && $0.scheduledAt == time("08:00") }?.status, .cancelled)
        XCTAssertEqual(state.doses.first { $0.medicationId == id && $0.scheduledAt == time("18:00") }?.status, .pending)
        try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("17:00"))
        try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("17:01"))
        XCTAssertEqual(state.medications[0].schedulePauses?.count, 2)
        try MedicationEngine.setSchedulePaused(false, for: id, state: &state, now: time("19:00"))
        XCTAssertEqual(state.doses.first { $0.medicationId == id && $0.scheduledAt == time("18:00") }?.status, .cancelled)
    }

    func testPausedMedicinesStillTriggerDuplicateAndInteractionChecks() throws {
        var state = SeedData.make(now: day)
        try MedicationEngine.setSchedulePaused(true, for: state.medications[0].id, state: &state, now: time("07:00"))
        var candidate = state.medications[0]; candidate.id = "new-brand"
        XCTAssertTrue(MedicationEngine.risks(for: candidate, in: state, now: time("08:00")).contains { $0.kind == "duplicate" })
        candidate.name = "Cimetidine"; candidate.ingredient = "cimetidine"
        XCTAssertTrue(MedicationEngine.risks(for: candidate, in: state, now: time("08:00")).contains { $0.kind == "interaction" })
    }

    func testStopWorksFromActiveOrPausedAndCannotResumeArchivedRegimen() throws {
        for paused in [false, true] {
            var state = SeedData.make(now: day)
            state.remindersEnabled = true
            let id = state.medications[0].id
            let history = state.doses.filter { $0.status != .pending }
            if paused { try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("07:00")) }
            try MedicationEngine.archive(id, state: &state, now: time("08:01"), reason: "Schedule stopped")
            XCTAssertEqual(state.medications[0].status, .stopped)
            XCTAssertFalse(state.doses.contains { $0.medicationId == id && $0.status == .pending })
            XCTAssertFalse(ReminderPlanner.plan(state: state, now: time("08:01")).requests.flatMap(\.doseIDs).contains { $0.hasPrefix(id + ":") })
            for dose in history { XCTAssertEqual(state.doses.first { $0.id == dose.id }, dose) }
            let stopped = state
            XCTAssertThrowsError(try MedicationEngine.setSchedulePaused(false, for: id, state: &state, now: time("09:00")))
            XCTAssertEqual(state, stopped)
        }
    }

    func testStaleNotificationDoesNotReopenPausedMissedDose() throws {
        var state = SeedData.make(now: day)
        let id = state.medications[0].id
        MedicationEngine.catchUp(&state, now: time("11:00"))
        let missed = state.doses.first { $0.medicationId == id && $0.scheduledAt == time("08:00") }!
        XCTAssertEqual(missed.status, .missed)
        try MedicationEngine.setSchedulePaused(true, for: id, state: &state, now: time("11:00"))
        var queue = ReminderCardQueue(); queue.isForeground = true
        queue.enqueue(ReminderCardRequest(doseIDs: [missed.id]))
        XCTAssertNil(queue.next(state: state, now: time("11:01"), canPresent: true))
        XCTAssertEqual(state.doses.first { $0.id == missed.id }, missed)
    }

    func testUpdatingPausedRecordKeepsSchedulePausedAndRejectsStaleReplan() throws {
        var state = SeedData.make(now: day)
        let med = state.medications[0]
        let morning = state.doses.first { $0.medicationId == med.id && $0.scheduledAt == time("08:00") }!
        try MedicationEngine.confirm([morning.id], state: &state, at: time("10:00"), method: "button")
        let confirmed = state.doses.first { $0.id == morning.id }!
        try MedicationEngine.setSchedulePaused(true, for: med.id, state: &state, now: time("11:00"))
        let before = state
        XCTAssertThrowsError(try MedicationEngine.apply(ReplanProposal(changes: [], explanation: "Old response"), medication: med, confirmed: confirmed, state: &state))
        XCTAssertEqual(before, state)
        var edited = med; edited.startDate = PillTime.day(day)
        try MedicationEngine.save(edited, replacing: med.id, acknowledged: true, state: &state, now: time("12:00"))
        XCTAssertTrue(state.medications.last!.isSchedulePaused)
        XCTAssertTrue(MedicationEngine.schedule(state.medications.last!, on: day).isEmpty)
    }

    func testOlderRecordsWithoutPauseFieldsDecodeUnchanged() throws {
        let state = SeedData.make(now: day)
        let data = try PillTime.encoder().encode(state)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("schedulePauses"))
        let restored = try PillTime.decoder().decode(PillCheckState.self, from: data)
        XCTAssertEqual(restored, state)
        XCTAssertTrue(restored.medications.allSatisfy(\.isScheduleEnabled))
    }
}
