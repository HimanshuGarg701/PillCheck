import Foundation

struct ConsultationConcern: Identifiable, Codable, Equatable {
    struct Medicine: Codable, Equatable {
        var id: String
        let name: String
    }
    let medicines: [Medicine]
    let title: String
    let detail: String
    let reviewedAt: Date
    let reviewID: String?
    let sources: [MedicationAIReview.Source]
    let evidence: [MedicationAIReview.Evidence]

    // A fresh check or checking the same pair in reverse must not create a
    // second pending follow-up. Length prefixes avoid ambiguous joined IDs.
    var id: String { Set(medicines.map(\.id)).sorted().map { "\($0.count):\($0)" }.joined() }
    var medicineNames: String { medicines.map(\.name).joined(separator: " + ") }

    func replacingMedicine(_ id: String, with saved: Medication) -> Self {
        Self(medicines: medicines.map { $0.id == id ? Medicine(id: saved.id, name: saved.name) : $0 },
             title: title, detail: detail, reviewedAt: reviewedAt, reviewID: reviewID, sources: sources, evidence: evidence)
    }

    static func from(flag: RiskFlag, medications: [Medication], candidate: Medication? = nil) -> Self? {
        let ids = Set(flag.medications + (candidate.map { [$0.id] } ?? []))
        let records = (candidate.map { [$0] } ?? []) + medications.filter { $0.id != candidate?.id }
        let medicines = records.filter { ids.contains($0.id) }.map { Medicine(id: $0.id, name: $0.name) }
        guard !medicines.isEmpty else { return nil }
        let sources = flag.sourceURL.map { [MedicationAIReview.Source(id: "offline-reference", title: "Prescribing information", url: $0, truncated: false, note: "Reference for the recorded concern.")] } ?? []
        return Self(medicines: medicines, title: flag.title, detail: flag.explanation, reviewedAt: flag.at, reviewID: nil, sources: sources, evidence: [])
    }
}

extension MedicationAIReview {
    var consultationConcerns: [ConsultationConcern] { pairs.compactMap { consultationConcern(for: $0) } + (doseConsultationConcern.map { [$0] } ?? []) }

    var doseConsultationConcern: ConsultationConcern? {
        let otherIDs = Set(pairs.map(\.medicationId))
        guard let message = doseConcernMessage,
              let candidateID = savedMedicationID ?? identities.first(where: { !otherIDs.contains($0.medicationId) })?.medicationId else { return nil }
        let evidence = doseAssessment?.evidence ?? []
        var references = sources.filter { source in evidence.contains { $0.sourceId == source.id } }
        if doseAssessment == nil, let dose = doseCheck {
            references = [.init(id: "dose-label", title: "Saved dose reference", url: dose.sourceURL, truncated: false, note: "Reference retained from this historical review.")]
        }
        return ConsultationConcern(medicines: [.init(id: candidateID, name: candidateName)], title: "Dose may be too high",
            detail: message, reviewedAt: createdAt, reviewID: id, sources: references, evidence: evidence)
    }

    func consultationConcern(for pair: Pair) -> ConsultationConcern? {
        let needsReview = pair.ingredientFinding != "different_ingredients"
            || pair.interactionFinding != "not_identified_in_references" || pair.spacingMinutes != nil
        let otherIDs = Set(pairs.map(\.medicationId))
        guard needsReview, let candidateID = savedMedicationID ?? identities.first(where: { !otherIDs.contains($0.medicationId) })?.medicationId else { return nil }
        let reason: String
        if pair.ingredientFinding == "possible_duplicate" { reason = pair.ingredientTitle }
        else if pair.interactionFinding == "potential_interaction" { reason = pair.interactionTitle }
        else if pair.spacingMinutes != nil { reason = "Medication timing needs review" }
        else if pair.ingredientFinding != "different_ingredients" { reason = pair.ingredientTitle }
        else { reason = pair.interactionTitle }
        var details = [pair.ingredientTitle, pair.interactionTitle, pair.explanation]
        if !pair.overlapIngredients.isEmpty { details.append("Shared ingredients: " + pair.overlapIngredients.joined(separator: ", ")) }
        if pair.status == "stopped" { details.append("Includes a recently stopped medicine.") }
        if let minutes = pair.spacingMinutes { details.append("Ask about the label-supported separation of \(minutes) minutes. Spacing does not establish overall safety.") }
        // Preserve the review's reference qualifications with the saved concern.
        return ConsultationConcern(medicines: [.init(id: candidateID, name: candidateName), .init(id: pair.medicationId, name: pair.medicationName)],
            title: reason, detail: details.joined(separator: "\n"), reviewedAt: createdAt, reviewID: id, sources: sources, evidence: pair.evidence)
    }
}

struct ConsultationReminder: Identifiable, Codable, Equatable {
    enum Status: String, Codable { case pending, completed, removed }
    let id: String
    let concern: ConsultationConcern
    let createdAt: Date
    var status: Status = .pending
    var completedAt: Date?
}

enum ConsultationReminderEngine {
    static func pending(for concern: ConsultationConcern, in state: PillCheckState) -> ConsultationReminder? {
        state.consultationReminders?.first { $0.concern.id == concern.id && $0.status == .pending }
    }

    static func setSelected(_ selected: Bool, concern: ConsultationConcern, state: inout PillCheckState, at: Date) throws {
        guard !concern.medicines.isEmpty, concern.medicines.allSatisfy({ reference in state.medications.contains { $0.id == reference.id } }) else {
            throw PillCheckError("Save the medication record before adding its doctor reminder.")
        }
        if let pending = pending(for: concern, in: state) {
            if !selected { try setStatus(.removed, id: pending.id, state: &state, at: at) }
        } else if selected {
            let reminder = ConsultationReminder(id: UUID().uuidString, concern: concern, createdAt: at)
            state.consultationReminders = (state.consultationReminders ?? []) + [reminder]
            state.audit.append(AuditEntry(type: "consultation_reminder_added", at: at, reason: "Consult with doctor: \(concern.medicineNames). \(concern.title)"))
        }
    }

    static func setStatus(_ status: ConsultationReminder.Status, id: String, state: inout PillCheckState, at: Date) throws {
        guard let index = state.consultationReminders?.firstIndex(where: { $0.id == id }), let reminder = state.consultationReminders?[index] else {
            throw PillCheckError("This doctor reminder could not be found.")
        }
        guard reminder.status != status else { return }
        if status == .pending, pending(for: reminder.concern, in: state) != nil {
            throw PillCheckError("A pending doctor reminder already exists for these medicines.")
        }
        state.consultationReminders?[index].status = status
        state.consultationReminders?[index].completedAt = status == .completed ? at : nil
        state.audit.append(AuditEntry(type: "consultation_reminder_\(status.rawValue)", at: at,
            reason: "Consult with doctor: \(reminder.concern.medicineNames). Follow-up marked \(status.rawValue). Medication warnings and schedules are unchanged."))
    }
}
