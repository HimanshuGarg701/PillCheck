import Foundation
import UserNotifications

@MainActor
final class LocalReminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var permission: UNAuthorizationStatus = .notDetermined
    @Published var scheduledCount = 0
    @Published var coveredThrough: Date?
    @Published var schedulingError: String?
    var openDoses: (([String]) -> Void)?
    private var generation = 0
    private var work: Task<Void, Never>?
    private var queuedRevision = 0
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let review = UNNotificationAction(identifier: "REVIEW", title: "Review medicines", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: "DOSE", actions: [review], intentIdentifiers: [])])
    }
    func refreshPermission() async {
        permission = await center.notificationSettings().authorizationStatus
        scheduledCount = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("pc.dose.") }.count
    }
    func requestPermission() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshPermission()
        return granted
    }
    func reconcile(_ state: PillCheckState) async {
        queuedRevision += 1
        let queued = queuedRevision
        let previous = work
        let job = Task { @MainActor in
            await previous?.value
            await self.synchronize(state)
        }
        work = job
        await job.value
        if queued == queuedRevision { work = nil }
    }
    private func synchronize(_ state: PillCheckState) async {
        generation += 1
        let revision = generation
        let plan = ReminderPlanner.plan(state: state, now: Date())
        let existing = await center.pendingNotificationRequests()
        guard revision == generation else { return }
        let wanted = Set(plan.requests.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("pc.") && $0.identifier != "pc.test" && !wanted.contains($0.identifier) }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        guard revision == generation else { return }
        let completedIDs = Set(state.doses.filter { !$0.status.canRecord }.map(\.id))
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            let doseIDs = $0.request.content.userInfo["doseIDs"] as? [String] ?? []
            return !doseIDs.isEmpty && doseIDs.allSatisfy { completedIDs.contains($0) }
        }.map { $0.request.identifier })
        guard state.remindersEnabled, !state.practiceClockEnabled else {
            scheduledCount = 0; coveredThrough = nil
            return
        }
        do {
            for item in plan.requests {
                guard revision == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = "PillCheck · your recorded schedule"
                content.body = item.repeatIndex == 0 ? "\(item.doseIDs.count) medicine\(item.doseIDs.count == 1 ? "" : "s") to review. Open PillCheck to check in." : "A scheduled check-in is still unconfirmed. Open PillCheck to review. Do not double a dose."
                content.sound = .default
                content.categoryIdentifier = "DOSE"
                content.threadIdentifier = "pillcheck-reminders"
                content.userInfo = ["doseIDs": item.doseIDs]
                let date = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
                try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)))
                if revision != generation {
                    // A newer sync may have removed this request while add() was suspended.
                    center.removePendingNotificationRequests(withIdentifiers: [item.id])
                    return
                }
            }
            // This generic recurring alert survives queue exhaustion without pretending to be a dose reminder.
            if plan.truncated {
                let content = UNMutableNotificationContent()
                content.title = "Keep PillCheck reminders ready"
                content.body = "Open PillCheck to extend the scheduled reminders and review your record."
                content.sound = .default
                let date = DateComponents(hour: 19, minute: 0)
                try await center.add(UNNotificationRequest(identifier: "pc.refresh", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
            }
            guard revision == generation else { return }
            coveredThrough = plan.coveredThrough
            scheduledCount = plan.requests.count
            schedulingError = nil
        } catch { schedulingError = error.localizedDescription }
    }
    func sendTest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "PillCheck test reminder"
        content.body = "Your iPhone delivered this local reminder. No internet or open app is needed after scheduling."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "pc.test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let ids = response.notification.request.content.userInfo["doseIDs"] as? [String] ?? []
        Task { @MainActor in self.openDoses?(ids); completionHandler() }
    }
}
