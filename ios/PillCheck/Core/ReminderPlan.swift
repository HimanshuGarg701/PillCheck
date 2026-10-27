import Foundation

struct PlannedReminder: Identifiable, Equatable {
    var id: String
    var doseIDs: [String]
    var fireAt: Date
    var scheduledAt: Date
    var repeatIndex: Int
}
struct ReminderPlan {
    var requests: [PlannedReminder]
    var coveredThrough: Date?
    var truncated: Bool
}
enum ReminderPlanner {
    // Leave room for a test alert and a daily queue-refresh reminder.
    static let maximumPending = 60
    static func plan(state: PillCheckState, now: Date, limit: Int = maximumPending) -> ReminderPlan {
        guard state.remindersEnabled, !state.practiceClockEnabled else { return ReminderPlan(requests: [], coveredThrough: nil, truncated: false) }
        var doses = state.doses
        var ids = Set(doses.map(\.id))
        for offset in 0..<30 {
            for med in state.medications {
                for d in MedicationEngine.schedule(med, on: PillTime.addingDays(offset, to: now)) where ids.insert(d.id).inserted { doses.append(d) }
            }
        }
        let pending = doses.filter { $0.status == .pending && $0.scheduledAt.addingTimeInterval(Double(state.reminderWindowMinutes) * 60) > now }
        let groups = Dictionary(grouping: pending, by: \.scheduledAt)
        var all: [PlannedReminder] = []
        for (at, group) in groups {
            var offsets = [0, 15]
            var minute = 45
            while minute < state.reminderWindowMinutes { offsets.append(minute); minute += 30 }
            for (index, offset) in offsets.enumerated() where offset < state.reminderWindowMinutes {
                let fireAt = at.addingTimeInterval(Double(offset) * 60)
                guard fireAt > now else { continue }
                let doseIDs = group.map(\.id).sorted()
                all.append(PlannedReminder(id: "pc.dose.\(Int(at.timeIntervalSince1970)).\(index)", doseIDs: doseIDs, fireAt: fireAt, scheduledAt: at, repeatIndex: index))
            }
        }
        all.sort { $0.fireAt < $1.fireAt }
        let selected = Array(all.prefix(max(0, limit)))
        // Coverage ends before the first unqueued alert, not at the last scheduled dose.
        return ReminderPlan(requests: selected, coveredThrough: selected.last?.fireAt, truncated: all.count > selected.count)
    }
}
