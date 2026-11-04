import SwiftUI

struct ConsultationCheckbox: View {
    @Binding var isSelected: Bool
    let medicineNames: String
    var savesWithPrescription = false
    var body: some View {
        Button { isSelected.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title2).foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Consult with doctor").font(.headline).foregroundStyle(Theme.ink)
                    Text(savesWithPrescription ? "Add to Reminders when you save this prescription." : isSelected ? "Added to Reminders" : "Add a follow-up to Reminders.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Consult with doctor about \(medicineNames)")
            .accessibilityValue(isSelected ? "Checked" : "Unchecked")
            .accessibilityHint(isSelected ? "Uncheck to remove the pending follow-up." : "Check to add a doctor follow-up.")
    }
}

struct SavedConsultationCheckbox: View {
    @EnvironmentObject private var store: PillStore
    let concern: ConsultationConcern
    var body: some View {
        ConsultationCheckbox(isSelected: Binding(
            get: { ConsultationReminderEngine.pending(for: concern, in: store.state) != nil },
            set: { selected in
                do { try store.setConsultationSelected(selected, concern: concern) }
                catch { store.error = error.localizedDescription }
            }
        ), medicineNames: concern.medicineNames)
        .accessibilityIdentifier("consultation-\(concern.id)")
    }
}

struct ConsultationRemindersView: View {
    @EnvironmentObject private var store: PillStore
    private var completed: [ConsultationReminder] {
        (store.state.consultationReminders ?? []).filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }
    var body: some View {
        NavigationStack {
            BrandScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("Doctor follow-ups").font(Theme.pageTitle).tracking(-0.6)
                    Text("Questions about your medicines, ready for your next conversation.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    HStack {
                        Text("Pending").font(Theme.sectionTitle)
                        Spacer()
                        StatusBadge(text: "\(store.pendingConsultations.count)", tone: .informational)
                    }
                    if store.pendingConsultations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "checklist").font(.largeTitle).foregroundStyle(Theme.accent)
                            Text("No pending doctor follow-ups").font(Theme.sectionTitle)
                            Text("When reviewing a possible interaction or shared ingredient, check “Consult with doctor” to keep it here.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }.card()
                    }
                    ForEach(store.pendingConsultations) { reminder in reminderCard(reminder) }
                    if !completed.isEmpty {
                        DisclosureGroup("Completed (\(completed.count))") {
                            LazyVStack(spacing: 16) {
                                ForEach(completed) { reminder in reminderCard(reminder) }
                            }.padding(.top, 14)
                        }.font(.headline)
                    }
                    Text("Completing a follow-up records that you consulted your doctor. It does not clear a medication warning or change your schedule.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }.padding(20)
            }.navigationTitle("Reminders").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reminderCard(_ reminder: ConsultationReminder) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Consult with doctor", systemImage: "stethoscope").font(Theme.sectionTitle)
            Text(reminder.concern.medicineNames).font(.headline)
            Text(reminder.concern.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.amber)
            Text(reminder.concern.detail.components(separatedBy: "\n").filter { $0 != reminder.concern.title }.joined(separator: "\n")).font(.subheadline)
            Text("Review from \(reminder.concern.reviewedAt.formatted(date: .abbreviated, time: .shortened)). Saved details may differ from your current prescription.")
                .font(.footnote).foregroundStyle(Theme.muted)
            if !reminder.concern.detail.contains("Includes a recently stopped medicine."), reminder.concern.medicines.contains(where: { store.medicine($0.id)?.status == .stopped }) {
                Text("Includes an earlier or stopped regimen.").font(.footnote).foregroundStyle(Theme.amber)
            }
            if !reminder.concern.sources.isEmpty {
                DisclosureGroup("Review references") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(reminder.concern.sources) { source in
                            VStack(alignment: .leading, spacing: 6) {
                                if let url = URL(string: source.url), url.scheme == "https" { Link(source.title, destination: url) }
                                ForEach(Array(reminder.concern.evidence.filter { $0.sourceId == source.id }.enumerated()), id: \.offset) { _, evidence in
                                    Text("“\(evidence.quote)”").italic()
                                }
                                Text(source.note).foregroundStyle(Theme.muted)
                                if source.truncated { Text("Only an excerpt was reviewed.").foregroundStyle(Theme.amber) }
                            }
                        }
                    }.font(.footnote).padding(.top, 10)
                }.font(.subheadline)
            }
            if let completedAt = reminder.completedAt {
                Label("Consulted \(completedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(Theme.success)
            }
            Button {
                do { try store.setConsultationStatus(reminder.status == .completed ? .pending : .completed, id: reminder.id) }
                catch { store.error = error.localizedDescription }
            } label: {
                Label(reminder.status == .completed ? "Mark as pending" : "Mark consulted", systemImage: reminder.status == .completed ? "arrow.uturn.backward" : "checkmark")
            }.buttonStyle(PrimaryButtonStyle(secondary: reminder.status == .completed))
        }.card()
    }
}
