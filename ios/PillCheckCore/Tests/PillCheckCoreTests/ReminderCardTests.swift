import XCTest
@testable import PillCheckCore

final class ReminderCardTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_793_145_600)
    func time(_ value: String) -> Date { PillTime.at(day, value)! }

    func testOpeningAppPresentsOnlyDueGroupWithinWindow() {
        var queue = ReminderCardQueue()
        queue.isForeground = true
        let state = SeedData.make(now: day)
        XCTAssertNil(queue.next(state: state, now: time("07:59"), canPresent: true))
        let request = queue.next(state: state, now: time("08:00"), canPresent: true)
        let ids = state.doses.filter { $0.scheduledAt == time("08:00") }.map(\.id).sorted()
        XCTAssertEqual(request, ReminderCardRequest(doseIDs: ids))
        XCTAssertEqual(ids.count, 2)
        // The foreground timer must not reopen a dismissed card.
        XCTAssertNil(queue.next(state: state, now: time("08:01"), canPresent: true))
        queue.enterBackground()
        queue.isForeground = true
        XCTAssertEqual(queue.next(state: state, now: time("08:02"), canPresent: true)?.doseIDs, ids)
        queue.enterBackground()
        queue.isForeground = true
        XCTAssertNil(queue.next(state: state, now: time("10:00"), canPresent: true))
    }

    func testNotificationWaitsForForegroundAndFormDismissal() {
        var queue = ReminderCardQueue()
        let state = SeedData.make(now: day)
        let ids = state.doses.filter { $0.scheduledAt == time("08:00") }.map(\.id).sorted()
        let request = ReminderCardRequest(doseIDs: ids)
        queue.enqueue(request)
        queue.enqueue(request)
        XCTAssertNil(queue.next(state: state, now: time("08:01"), canPresent: true))
        queue.isForeground = true
        XCTAssertNil(queue.next(state: state, now: time("08:01"), canPresent: false))
        XCTAssertEqual(queue.next(state: state, now: time("08:01"), canPresent: true), request)
        XCTAssertNil(queue.next(state: state, now: time("08:01"), canPresent: true))
        // A later explicit notification tap can reopen an unconfirmed group.
        queue.enqueue(request)
        XCTAssertEqual(queue.next(state: state, now: time("08:15"), canPresent: true), request)
    }

    func testStaleNotificationCannotOpenCompletedCancelledOrFutureDose() throws {
        var state = SeedData.make(now: day)
        let ids = state.doses.filter { $0.scheduledAt == time("08:00") }.map(\.id)
        try MedicationEngine.confirm([ids[0]], state: &state, at: time("08:01"), method: "button")
        let second = state.doses.firstIndex { $0.id == ids[1] }!
        state.doses[second].status = .cancelled
        let future = state.doses.first { $0.scheduledAt == time("18:00") }!.id
        var queue = ReminderCardQueue()
        queue.isForeground = true
        queue.enqueue(ReminderCardRequest(doseIDs: ids + [future, "unknown"]))
        XCTAssertNil(queue.next(state: state, now: time("08:01"), canPresent: true))
    }

    func testNotificationRetainsUnconfirmedMembersAndRemovesDuplicateIDs() throws {
        var state = SeedData.make(now: day)
        let ids = state.doses.filter { $0.scheduledAt == time("08:00") }.map(\.id)
        try MedicationEngine.confirm([ids[0]], state: &state, at: time("08:01"), method: "button")
        var queue = ReminderCardQueue()
        queue.isForeground = true
        queue.enqueue(ReminderCardRequest(doseIDs: ids + ids))
        XCTAssertEqual(queue.next(state: state, now: time("08:01"), canPresent: true)?.doseIDs, [ids[1]])
    }

    func testNotificationPreviewDoesNotSuppressActualDueCardOrChangeRecords() {
        let state = SeedData.make(now: day)
        let ids = state.doses.filter { $0.scheduledAt == time("08:00") }.map(\.id).sorted()
        let before = state
        var queue = ReminderCardQueue()
        queue.isForeground = true
        queue.enqueue(ReminderCardRequest(doseIDs: ids, isPreview: true))
        XCTAssertEqual(queue.next(state: state, now: time("07:59"), canPresent: true), ReminderCardRequest(doseIDs: ids, isPreview: true))
        XCTAssertEqual(queue.next(state: state, now: time("08:00"), canPresent: true), ReminderCardRequest(doseIDs: ids))
        XCTAssertEqual(state, before)
    }

    func testVoiceOnlyAcceptsFinalExactSupportedCommands() {
        for command in ["Done", "done.", " LISTO! ", "हो गया"] {
            XCTAssertEqual(VoiceConfirmationCommand.parse(command, isFinal: true), .done)
            XCTAssertNil(VoiceConfirmationCommand.parse(command, isFinal: false))
        }
        for command in ["Next", "siguiente", "अगला"] {
            XCTAssertEqual(VoiceConfirmationCommand.parse(command, isFinal: true), .next)
        }
        for command in ["", "not done", "don't mark done", "almost done", "done next", "done done", "I haven't taken it", "no listo"] {
            XCTAssertNil(VoiceConfirmationCommand.parse(command, isFinal: true))
        }
    }
}
