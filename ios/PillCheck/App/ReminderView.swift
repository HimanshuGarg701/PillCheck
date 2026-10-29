import SwiftUI

struct ReminderView: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.dismiss) private var dismiss
    let selection: ReminderSelection
    @State private var index = 0
    @State private var spoken = ""
    @State private var busy = false
    @State private var error: String?
    @State private var skipping = false
    @State private var reason = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if selection.isPreview {
                        Text("Notification preview · Done will not change your history.")
                            .font(.subheadline.weight(.medium)).multilineTextAlignment(.center).card(Theme.sage)
                    }
                    if let dose = currentDose, let med = store.medicine(dose.medicationId) {
                        Text("MEDICINE \(index + 1) OF \(selection.doseIDs.count)").font(.subheadline.weight(.semibold)).tracking(1).foregroundStyle(Theme.green)
                        Image(systemName: med.isLiquid ? "drop.fill" : "pills").font(.system(size: 56)).foregroundStyle(Theme.green).frame(width: 110, height: 110).background(Theme.sage, in: RoundedRectangle(cornerRadius: 30)).accessibilityHidden(true)
                        Text(med.name).font(.system(.largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                        Text("\(med.strengthText)").font(.title2).foregroundStyle(.secondary)
                        Text("Recorded dose: \(med.doseText)").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened)).font(.headline)
                        Text(med.instructions).multilineTextAlignment(.center)
                        if store.now.timeIntervalSince(dose.scheduledAt) > 30 * 60 {
                            WarningBox(text: MedicationEngine.isHighRisk(med) ? PillCheckCopy.pharmacist : "This dose is late. Do not double a dose. Confirm timing with your pharmacist; record only what has already happened.")
                        }
                        if !spoken.isEmpty { Text(spoken).font(.title3).multilineTextAlignment(.center).card(Theme.sage).accessibilityIdentifier("spoken-reminder") }
                        if let error { WarningBox(text: error) }
                        Button { Task { await read(med) } } label: {
                            if busy { HStack { ProgressView().tint(.white); Text("Preparing reminder…") } }
                            else { Label("Speak reminder", systemImage: "speaker.wave.2.fill") }
                        }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy)
                        if index < selection.doseIDs.count - 1 {
                            Button { next() } label: { Label("Next medicine", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button { finish(method: "button") } label: { Label(selection.isPreview ? "Done — finish preview" : selection.doseIDs.count == 1 ? "Done — already taken" : "Done — all already taken", systemImage: "checkmark") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirm-dose")
                        }
                        VoiceControl(speech: store.speech, language: store.state.language) { command in
                            if command == "next" { next() }
                            else if index == selection.doseIDs.count - 1 { finish(method: "voice") }
                            else { error = "Review each card with Next. Say Done on the final card to confirm the whole group." }
                        }
                        if !selection.isPreview {
                            Button("Record this dose as skipped") { store.speech.stop(); skipping = true }.frame(minHeight: 56)
                            Text("Done on the last card records all \(selection.doseIDs.count) medicine\(selection.doseIDs.count == 1 ? "" : "s") at the actual confirmation time\(store.state.practiceClockEnabled ? " shown in the reminder preview" : "").").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        DisclaimerView()
                    } else {
                        ContentUnavailableView("This dose is already recorded", systemImage: "checkmark.circle", description: Text("Your history is preserved."))
                    }
                }.padding(24)
            }.background(Theme.cream).navigationTitle("Your check-in").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onDisappear { store.speech.stop() }
                .alert("Record skipped dose", isPresented: $skipping) {
                    TextField("Reason (optional)", text: $reason)
                    Button("Cancel", role: .cancel) {}
                    Button("Record skipped") {
                        guard let dose = currentDose else { return }
                        do { try store.confirm([dose.id], method: "button", skipped: true, reason: reason) }
                        catch { self.error = error.localizedDescription }
                    }
                } message: { Text("This only records what happened. Ask your pharmacist for missed-dose advice.") }
        }
    }
    private var currentDose: DoseEvent? {
        guard selection.doseIDs.indices.contains(index) else { return nil }
        return store.state.doses.first { $0.id == selection.doseIDs[index] && $0.status.canRecord }
    }
    private func next() { guard index < selection.doseIDs.count - 1 else { return }; store.speech.stop(); index += 1; spoken = ""; error = nil }
    private func finish(method: String) {
        guard store.isShowingReminder(selection.id) else { return }
        if selection.isPreview {
            store.speech.stop()
            store.activeReminder = nil
            store.notice = "Notification preview completed. Your medication history is unchanged."
            return
        }
        do { try store.confirm(selection.doseIDs, method: method) }
        catch { self.error = error.localizedDescription }
    }
    private func read(_ med: Medication) async {
        busy = true; error = nil
        defer { busy = false }
        if let dose = currentDose, MedicationEngine.isHighRisk(med), store.now.timeIntervalSince(dose.scheduledAt) > 30 * 60 {
            spoken = PillCheckCopy.pharmacist(language: store.state.language)
            store.speech.speak(spoken, language: store.state.language)
            return
        }
        do {
            let text = try await store.spoken(med)
            guard store.isShowingReminder(selection.id), currentDose?.medicationId == med.id else { return }
            spoken = text
            store.speech.speak(spoken, language: store.state.language)
        }
        catch { self.error = "The model reminder is unavailable. Your recorded dose remains visible above. " + error.localizedDescription }
    }
}

struct VoiceControl: View {
    @ObservedObject var speech: SpeechService
    let language: String
    let command: (String) -> Void
    var body: some View {
        VStack(spacing: 10) {
            Button { Task { await speech.listen(language: language, onCommand: command) } } label: {
                Label(speech.listening ? "Listening… say Done or Next" : speech.preparing ? "Preparing microphone…" : "Confirm by voice", systemImage: speech.listening ? "waveform" : "mic")
            }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(speech.listening || speech.preparing)
            if !speech.transcript.isEmpty { Text(speech.transcript).font(.subheadline).foregroundStyle(.secondary) }
            if let message = speech.message { WarningBox(text: message) }
        }
    }
}

struct ReplanView: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.dismiss) private var dismiss
    let doseID: String
    @State private var result: ReplanProposal?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let dose = store.state.doses.first(where: { $0.id == doseID }), let med = store.medicine(dose.medicationId) {
                        Text("A timing change, explained.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("\(med.name) was recorded at \(dose.confirmedAt?.formatted(date: .omitted, time: .shortened) ?? "—"), after its \(dose.originalScheduledAt.formatted(date: .omitted, time: .shortened)) time.")
                        if MedicationEngine.isHighRisk(med) {
                            WarningBox(text: PillCheckCopy.pharmacist)
                            Button("Read pharmacist guidance") { store.speech.speak(PillCheckCopy.pharmacist(language: store.state.language), language: store.state.language) }.buttonStyle(PrimaryButtonStyle())
                        } else if !MedicationEngine.replanEligible(med) {
                            WarningBox(text: "This medicine needs a pharmacist-approved timing plan. No remaining doses or quantities have changed.")
                        } else if let result {
                            Label("Timing review complete", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                            ForEach(result.changes, id: \.doseId) { change in
                                if let saved = store.state.changes.last(where: { $0.doseId == change.doseId }) {
                                    HStack { Text(saved.oldTime.formatted(date: .omitted, time: .shortened)).strikethrough().foregroundStyle(.secondary); Image(systemName: "arrow.right"); Text(saved.newTime.formatted(date: .omitted, time: .shortened)).bold() }.font(.title2).card(Theme.sage)
                                }
                            }
                            Text(result.explanation).font(.title3)
                            Text("Quantity remains \(med.doseText). The explanation and earlier time are saved in history.").foregroundStyle(.secondary)
                            Button("Read explanation aloud") { store.speech.speak(result.explanation, language: store.state.language) }.buttonStyle(PrimaryButtonStyle())
                        } else {
                            WarningBox(text: "This sample uses a 10-hour interval to preview timing changes. It is not a clinical dosing rule. Confirm schedule changes with your pharmacist.")
                            Button {
                                Task { do { result = try await store.replan(doseID) } catch { self.error = error.localizedDescription } }
                            } label: {
                                if store.isWorking { HStack { ProgressView().tint(.white); Text("Preparing timing proposal…") } }
                                else { Text("Ask Meta for a timing plan") }
                            }.buttonStyle(PrimaryButtonStyle()).disabled(store.isWorking)
                        }
                        if let error { WarningBox(text: error + " Your confirmation is saved. No other times changed.") }
                    }
                    DisclaimerView()
                }.padding(24)
            }.background(Theme.cream).navigationTitle("Late-dose review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onDisappear { store.speech.stop() }
        }
    }
}
