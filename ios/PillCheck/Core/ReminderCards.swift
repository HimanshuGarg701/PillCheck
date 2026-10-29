import Foundation

struct ReminderCardRequest: Equatable {
    var doseIDs: [String]
    var isPreview = false
}

/// Keeps notification requests until the app can present them, and prevents a
/// dismissed due card from reopening on every foreground timer tick.
struct ReminderCardQueue {
    var isForeground = false
    private var shownDoseIDs = Set<String>()
    private var requested: [ReminderCardRequest] = []

    mutating func enterBackground() {
        isForeground = false
        shownDoseIDs.removeAll()
    }
    mutating func enqueue(_ request: ReminderCardRequest) {
        guard !request.doseIDs.isEmpty, !requested.contains(request) else { return }
        requested.append(request)
    }
    mutating func didPresent(_ ids: [String]) { shownDoseIDs.formUnion(ids) }

    mutating func next(state: PillCheckState, now: Date, canPresent: Bool) -> ReminderCardRequest? {
        guard isForeground, canPresent else { return nil }
        let enabled = Set(state.medications.filter(\.isScheduleEnabled).map(\.id))
        while !requested.isEmpty {
            var request = requested.removeFirst()
            var unique = Set<String>()
            request.doseIDs = request.doseIDs.filter { id in
                unique.insert(id).inserted && state.doses.contains {
                    $0.id == id && enabled.contains($0.medicationId) && $0.status.canRecord && (request.isPreview || $0.scheduledAt <= now)
                }
            }
            if !request.doseIDs.isEmpty {
                if !request.isPreview { didPresent(request.doseIDs) }
                return request
            }
        }
        let due = state.doses.filter {
            enabled.contains($0.medicationId) && $0.status == .pending && $0.scheduledAt <= now &&
            $0.scheduledAt.addingTimeInterval(Double(state.reminderWindowMinutes) * 60) > now &&
            !shownDoseIDs.contains($0.id)
        }.sorted { $0.scheduledAt < $1.scheduledAt }
        guard let first = due.first else { return nil }
        let ids = due.filter { $0.scheduledAt == first.scheduledAt }.map(\.id).sorted()
        didPresent(ids)
        return ReminderCardRequest(doseIDs: ids)
    }
}

enum VoiceConfirmationCommand: String {
    case done, next

    static func parse(_ transcript: String, isFinal: Bool) -> Self? {
        guard isFinal else { return nil }
        let words = transcript.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if ["done", "listo", "हो गया"].contains(words) { return .done }
        if ["next", "siguiente", "अगला"].contains(words) { return .next }
        return nil
    }
}
