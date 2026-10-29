import SwiftUI

struct MedicinesView: View {
    @EnvironmentObject private var store: PillStore
    @State private var add = false
    @State private var edit: MedicineDraft?
    @State private var archiving: Medication?
    @State private var archiveReason = ""
    @State private var reviewing: Medication?
    @State private var savedReview: MedicationAIReview?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Everything in one place.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Earlier regimens stay in your history.").foregroundStyle(.secondary)
                    ForEach(store.state.medications.filter { $0.status == .active }) { med in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Image(systemName: med.isLiquid ? "drop.fill" : "pills").font(.title).foregroundStyle(Theme.green); Spacer(); Text(med.isSchedulePaused ? "Schedule paused" : "Schedule active").font(.caption).foregroundStyle(med.isSchedulePaused ? Theme.amber : Theme.green) }
                            Text(med.name).font(.title2.bold())
                            Text("\(med.ingredient) · \(med.strengthText)").foregroundStyle(.secondary)
                            LabeledContent("Recorded dose", value: "\(med.doseText)")
                            LabeledContent("Schedule", value: med.times.joined(separator: " · "))
                            LabeledContent("Daily ingredient", value: "\(PillTime.number(med.dailyMg)) mg")
                            Text(med.instructions).font(.subheadline)
                            if med.isSchedulePaused { Text("Reminders are paused. This medicine stays in interaction checks. Resume to schedule future doses at the recorded times.").font(.subheadline).foregroundStyle(.secondary) }
                            if MedicationEngine.isHighRisk(med) { WarningBox(text: PillCheckCopy.pharmacist) }
                            Button { reviewing = med } label: { Label("AI interactions & timing", systemImage: "sparkles") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                            Button("Update record") { edit = MedicineDraft(medicine: med, now: store.now) }.buttonStyle(PrimaryButtonStyle(secondary: true))
                            Button {
                                do { try store.setSchedulePaused(!med.isSchedulePaused, for: med.id) }
                                catch { store.error = error.localizedDescription }
                            } label: { Label(med.isSchedulePaused ? "Resume schedule" : "Pause schedule", systemImage: med.isSchedulePaused ? "play.circle" : "pause.circle") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                            Button("Stop schedule", role: .destructive) { archiving = med; archiveReason = "" }.frame(minHeight: 44)
                        }.card()
                    }
                    Text("Offline reference checks").font(.title2.bold())
                    let risks = MedicationEngine.activeRisks(store.state, now: store.now)
                    if risks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No known interaction found in this reference set.").font(.headline)
                            Text("The offline reference set covers one curated metformin/cimetidine pair. Use AI interactions & timing above for a review of retrieved U.S. references. No flag does not mean a combination is safe.").font(.subheadline).foregroundStyle(.secondary)
                        }.card()
                    } else { ForEach(risks) { RiskFlagView(flag: $0) } }
                    if let reviews = store.state.medicationReviews, !reviews.isEmpty {
                        Text("Saved AI review snapshots").font(.title2.bold())
                        Text("Historical reviews may no longer match your current list. Run a fresh check after any prescription change.").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(reviews.reversed()) { review in
                            Button { savedReview = review } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(review.candidateName).font(.headline)
                                    Text("\(review.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(review.completed ? "AI reviewed" : "AI incomplete")").font(.subheadline)
                                }.card()
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Earlier regimens & stopped medicines").font(.title2.bold())
                    let archived = store.state.medications.filter { $0.status == .stopped }
                    if archived.isEmpty { Text("Your archived records will appear here. They are never deleted.").foregroundStyle(.secondary) }
                    ForEach(archived) { med in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(med.name) · \(med.strengthText)").font(.headline)
                            Text("\(med.startDate.formatted(date: .abbreviated, time: .omitted)) – \(med.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                            Text(PillCheckCopy.recordText(med.archiveReason ?? "Archived")).foregroundStyle(.secondary)
                        }.card()
                    }
                    DisclaimerView()
                }.padding(20)
            }.background(Theme.cream).navigationTitle("Medicines").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add medicine") } }
                .sheet(isPresented: $add) { IntakeView() }
                .sheet(item: $edit) { draft in MedicineEditor(draft: draft) }
                .sheet(item: $reviewing) { med in MedicationAIReviewView(medication: med) }
                .sheet(item: $savedReview) { review in
                    NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 20) { WarningBox(text: "Historical snapshot. Run a new review for the current medication list."); MedicationReviewContent(review: review) }.padding(20) }.background(Theme.cream).navigationTitle("Saved review").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { savedReview = nil } } } }
                }
                .deferReminderCards(while: add || edit != nil || reviewing != nil || savedReview != nil || archiving != nil)
                .alert("Stop this medication schedule?", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } })) {
                    TextField("Reason (optional)", text: $archiveReason)
                    Button("Cancel", role: .cancel) { archiving = nil }
                    Button("Stop schedule", role: .destructive) {
                        guard let med = archiving else { return }
                        do { try store.archive(med.id, reason: archiveReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Schedule stopped" : archiveReason); archiving = nil } catch { store.error = error.localizedDescription }
                    }
                } message: { Text("Future reminders for \(archiving?.name ?? "this medicine") will stop and the record will move to history. Use Pause for a temporary break. This changes the app schedule; follow your prescriber's instructions about the medicine itself.") }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: PillStore
    @State private var from = PillTime.addingDays(-29, to: Date())
    @State private var to = Date()
    @State private var medicationID = "all"
    @State private var pdf: ExportedFile?
    private var filtered: [DoseEvent] {
        store.state.doses.filter {
            PillTime.day($0.scheduledAt) >= PillTime.day(from) && PillTime.day($0.scheduledAt) <= PillTime.day(to) && (medicationID == "all" || $0.medicationId == medicationID)
        }.sorted { $0.scheduledAt > $1.scheduledAt }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("Your record, over time.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("See your check-ins, prescription changes, and medication history in one place.").foregroundStyle(.secondary)
                    VStack(spacing: 16) {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                        Picker("Medicine", selection: $medicationID) {
                            Text("All medicines & regimens").tag("all")
                            ForEach(store.state.medications) { med in Text("\(med.name)\(med.status == .stopped ? " (earlier regimen)" : "")").tag(med.id) }
                        }
                    }.card()
                    let complete = filtered.filter { $0.status != .pending && $0.status != .cancelled }
                    let taken = complete.filter { $0.status.isTaken }.count
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) { Text("\(complete.isEmpty ? 0 : Int(Double(taken) / Double(complete.count) * 100))%").font(.largeTitle.bold()); Text("Recorded taken").font(.subheadline); Text("\(taken) of \(complete.count) completed records").font(.caption).foregroundStyle(.secondary) }.card(Theme.sage)
                        VStack(alignment: .leading, spacing: 8) { Text("\(complete.filter { $0.status == .missed || $0.status == .skipped }.count)").font(.largeTitle.bold()); Text("Missed or skipped").font(.subheadline); Text("Share concerns with your pharmacist").font(.caption).foregroundStyle(.secondary) }.card(Theme.peach)
                    }
                    Button {
                        do { pdf = ExportedFile(url: try HistoryPDF.export(state: store.state, from: from, to: to, medicationID: medicationID == "all" ? nil : medicationID)) }
                        catch { store.error = error.localizedDescription }
                    } label: { Label("Export history PDF", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("export-pdf")
                    ForEach(filtered) { dose in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(store.medicine(dose.medicationId)?.name ?? "Earlier regimen").font(.headline); Spacer(); Text(dose.status.title).font(.caption.weight(.semibold)).foregroundStyle(dose.status.isTaken ? Theme.green : Theme.amber) }
                            Text(dose.scheduledAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                            if let confirmed = dose.confirmedAt { Text("Confirmed \(confirmed.formatted(date: .omitted, time: .shortened)) · \(dose.methodTitle)").font(.subheadline).foregroundStyle(.secondary) }
                            if let reason = dose.replanReason ?? dose.reason, !reason.isEmpty { Text(PillCheckCopy.recordText(reason)).font(.footnote).foregroundStyle(.secondary) }
                        }.card()
                    }
                    DisclosureGroup("Changes & acknowledgments (\(store.state.audit.count))") {
                        ForEach(store.state.audit.reversed()) { entry in VStack(alignment: .leading, spacing: 6) { Text(entry.at.formatted()).font(.caption).foregroundStyle(.secondary); Text(PillCheckCopy.recordText(entry.reason)).font(.subheadline); Divider() }.padding(.vertical, 8) }
                    }.card()
                    DisclaimerView()
                }.padding(20)
            }.background(Theme.cream).navigationTitle("History").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $pdf) { file in ShareSheet(items: [file.url]) }
                .deferReminderCards(while: pdf != nil)
                .onChange(of: from) { _, new in if to < new { to = new } }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
