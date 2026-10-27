import Foundation
import Combine

struct ReminderSelection: Identifiable {
    let id = UUID()
    let doseIDs: [String]
}

@MainActor
final class PillStore: ObservableObject {
    @Published private(set) var state: PillCheckState
    @Published var loadError: String?
    @Published var error: String?
    @Published var notice: String?
    @Published var activeReminder: ReminderSelection?
    @Published var lateDoseID: String?
    @Published var modelStatus = "Muse Spark 1.3"
    @Published var isWorking = false
    let notifications = LocalReminders()
    let speech = SpeechService()
    let meta = MetaClient()
    let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("PillCheck", isDirectory: true)
        fileURL = directory.appendingPathComponent("records.json")
        state = SeedData.make()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let decoded = try PillTime.decoder().decode(PillCheckState.self, from: Data(contentsOf: fileURL))
                guard decoded.version == 1 else { throw PillCheckError("These records use a newer format. They have not been overwritten.") }
                state = decoded
            } else { try write(state) }
        } catch { loadError = "Your saved records could not be opened. The original file is preserved. \(error.localizedDescription)" }
        notifications.openDoses = { [weak self] ids in
            guard let self else { return }
            self.refresh()
            let available = ids.filter { id in self.state.doses.contains { $0.id == id && $0.status.canRecord } }
            if !available.isEmpty { self.activeReminder = ReminderSelection(doseIDs: available) }
        }
    }
    var now: Date { state.practiceClockEnabled ? state.practiceTime : Date() }
    var today: [DoseEvent] {
        state.doses.filter { PillTime.sameDay($0.scheduledAt, now) && $0.status != .cancelled }.sorted { $0.scheduledAt < $1.scheduledAt }
    }
    var nextGroup: [DoseEvent] {
        let pending = today.filter { $0.status.canRecord }
        guard let first = pending.first else { return [] }
        return pending.filter { $0.scheduledAt == first.scheduledAt }
    }
    func medicine(_ id: String) -> Medication? { state.medications.first { $0.id == id } }
    private func write(_ state: PillCheckState) throws {
        try PillTime.encoder().encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func change(_ operation: (inout PillCheckState) throws -> Void) throws {
        guard loadError == nil else { throw PillCheckError("Saved records need attention before making changes.") }
        var updated = state
        try operation(&updated)
        try write(updated)
        state = updated
        Task { await notifications.reconcile(updated) }
    }
    func refresh() {
        guard loadError == nil else { return }
        do {
            let at = now
            try change { MedicationEngine.catchUp(&$0, now: at) }
        } catch { self.error = error.localizedDescription }
        Task { await notifications.refreshPermission() }
    }
    func openReminder(ids: [String]? = nil) {
        let ids = ids ?? nextGroup.map(\.id)
        guard !ids.isEmpty else { notice = "There are no unconfirmed medicines in this group."; return }
        activeReminder = ReminderSelection(doseIDs: ids)
    }
    func confirm(_ ids: [String], method: String, skipped: Bool = false, reason: String = "") throws {
        let at = now
        try change { try MedicationEngine.confirm(ids, state: &$0, at: at, method: method, skipped: skipped, reason: reason) }
        speech.stop()
        activeReminder = nil
        if !skipped {
            lateDoseID = ids.first { id in state.doses.contains { $0.id == id && $0.status == .takenLate } }
        }
        notice = skipped ? "Skipped dose recorded." : "Confirmation saved at \(at.formatted(date: .omitted, time: .shortened))."
    }
    func save(_ medication: Medication, replacing id: String?, acknowledged: Bool) throws {
        let at = now
        try change { try MedicationEngine.save(medication, replacing: id, acknowledged: acknowledged, state: &$0, now: at) }
    }
    func archive(_ id: String, reason: String) throws {
        let at = now
        try change { try MedicationEngine.archive(id, state: &$0, now: at, reason: reason) }
    }
    func spoken(_ med: Medication) async throws -> String {
        let key = "\(med.name)|\(med.doseQuantity)|\(med.doseUnit)|\(state.language)"
        if let cached = state.spokenCache[key] { return cached }
        let text = try await meta.reminder(medication: med, language: state.language)
        try change { $0.spokenCache[key] = text }
        modelStatus = "Muse Spark 1.3 · live"
        return text
    }
    func replan(_ id: String) async throws -> ReplanProposal {
        guard let dose = state.doses.first(where: { $0.id == id }), let med = medicine(dose.medicationId), let at = dose.confirmedAt else { throw PillCheckError("Record the already-taken dose first.") }
        guard !MedicationEngine.isHighRisk(med) else { throw PillCheckError(PillCheckCopy.pharmacist) }
        guard MedicationEngine.replanEligible(med) else { throw PillCheckError("A pharmacist-approved timing plan is required for this medicine.") }
        let future = state.doses.filter { $0.medicationId == med.id && $0.status == .pending && PillTime.sameDay($0.scheduledAt, at) }.sorted { $0.scheduledAt < $1.scheduledAt }
        isWorking = true
        defer { isWorking = false }
        do {
            let proposal = try await meta.replan(medication: med, dose: dose, future: future, language: state.language)
            try change { try MedicationEngine.apply(proposal, medication: med, confirmed: dose, state: &$0) }
            modelStatus = "Muse Spark 1.3 · live"
            return proposal
        } catch {
            try? change { $0.audit.append(AuditEntry(type: "replan_not_applied", at: Date(), reason: error.localizedDescription)) }
            throw error
        }
    }
    func startLateExample() throws {
        let day = PillTime.day(now)
        guard let dose = today.first(where: { $0.medicationId == "med-metformin" && $0.originalScheduledAt == PillTime.at(day, "08:00") && $0.status.canRecord }) else {
            if let dose = today.first(where: { $0.medicationId == "med-metformin" && $0.status == .takenLate }) { lateDoseID = dose.id; return }
            throw PillCheckError("The morning example is already recorded. Its history will not be reset.")
        }
        let at = PillTime.at(day, "10:00")!
        try change {
            $0.practiceClockEnabled = true
            $0.practiceTime = at
            $0.remindersEnabled = false
            try MedicationEngine.confirm([dose.id], state: &$0, at: at, method: "button", reason: "Fictional late-dose example")
        }
        lateDoseID = dose.id
    }
    func setPractice(_ enabled: Bool) throws {
        try change {
            $0.practiceClockEnabled = enabled
            if enabled {
                $0.practiceTime = PillTime.at(Date(), "08:00")!
                $0.remindersEnabled = false
            }
        }
        refresh()
    }
    func setReminders(_ enabled: Bool) async {
        do {
            if enabled {
                guard !state.practiceClockEnabled else { throw PillCheckError("Switch off the practice clock before scheduling real iPhone reminders.") }
                guard try await notifications.requestPermission() else { throw PillCheckError("Notifications were not allowed. You can change this in iPhone Settings.") }
            }
            try change { $0.remindersEnabled = enabled }
        } catch { self.error = error.localizedDescription }
    }
}
