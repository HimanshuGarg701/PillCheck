import SwiftUI
import UserNotifications

struct PreferencesView: View {
    @EnvironmentObject private var store: PillStore
    @State private var problems = ""
    @State private var shareRecords = false
    @State private var lateIntro = false
    @State private var showReplan = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A little help, your way.").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Your medication history is stored on this iPhone and is available offline.").foregroundStyle(.secondary)
                }
                Section("Voice & language") {
                    Picker("Spoken language", selection: Binding(get: { store.state.language }, set: { value in update { $0.language = value } })) {
                        Text("English").tag("en-US")
                        Text("Español").tag("es-ES")
                        Text("हिन्दी").tag("hi-IN")
                    }
                    Text("Hear reminders in your preferred language. Previously generated reminders are available for offline playback. Voice confirmation uses on-device recognition when supported.").font(.footnote).foregroundStyle(.secondary)
                }
                NotificationSettings(store: store, reminders: store.notifications)
                Section {
                  DisclosureGroup("Sample medicines & previews") {
                    Text("PillCheck includes sample medicines and 30 days of sample history to help you explore the app.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Preview reminders at another time", isOn: Binding(get: { store.state.practiceClockEnabled }, set: { value in do { try store.setPractice(value) } catch { store.error = error.localizedDescription } }))
                    if store.state.practiceClockEnabled {
                        DatePicker("Preview time", selection: Binding(get: { store.state.practiceTime }, set: { value in update { $0.practiceTime = value }; store.refresh() }), displayedComponents: .hourAndMinute)
                    }
                    Button("Preview a late check-in") { lateIntro = true }
                    Text("Previews pause notifications and use the selected time for check-ins. Saved check-ins remain in history when you end the preview.").font(.footnote).foregroundStyle(.secondary)
                  }
                }
                Section("Recorded class concerns") {
                    TextField("e.g. statin, anticoagulant", text: $problems)
                    Button("Save class concerns") {
                        update { $0.problems = problems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }; $0.audit.append(AuditEntry(type: "class_concerns_updated", at: Date(), reason: "Recorded medication-class concerns updated.")) }
                        store.notice = "Medication-class concerns saved."
                    }
                    Text("This records a known problem with a medicine class. It is not a diagnosis or allergy assessment.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("AI assistance") {
                    Text("AI helps read labels, review ingredients and interactions, and explain timing. These checks require an internet connection. Review findings with your pharmacist before changing your prescription.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your records") {
                    Button { shareRecords = true } label: { Label("Export all records (JSON)", systemImage: "square.and.arrow.up") }
                    Text("There is no delete-history control. Earlier regimens, confirmations, and audit entries are retained. Keep an export before uninstalling the app or replacing this iPhone.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { DisclaimerView() }
            }.scrollContentBackground(.hidden).background(Theme.cream).navigationTitle("Preferences").navigationBarTitleDisplayMode(.inline)
                .onAppear { problems = store.state.problems.joined(separator: ", ") }
                .sheet(isPresented: $shareRecords) { ShareSheet(items: [store.fileURL]) }
                .sheet(isPresented: $showReplan) { if let id = store.lateDoseID { ReplanView(doseID: id) } }
                .deferReminderCards(while: shareRecords || showReplan || lateIntro)
                .confirmationDialog("Preview a 10 AM check-in?", isPresented: $lateIntro, titleVisibility: .visible) {
                    Button("Record sample check-in") {
                        do { try store.startLateExample(); showReplan = true } catch { store.error = error.localizedDescription }
                    }
                } message: { Text("This records the sample 8 AM metformin dose as taken at 10 AM and pauses notifications. The check-in remains in history after the preview ends.") }
        }
    }
    private func update(_ change: (inout PillCheckState) -> Void) { do { try store.change(change) } catch { store.error = error.localizedDescription } }
}

struct NotificationSettings: View {
    @ObservedObject var store: PillStore
    @ObservedObject var reminders: LocalReminders
    @State private var testMessage: String?
    var body: some View {
        Section("iPhone reminders") {
            Toggle("Enable local notifications", isOn: Binding(get: { store.state.remindersEnabled }, set: { value in Task { await store.setReminders(value) } })).disabled(store.state.practiceClockEnabled)
            Picker("Unconfirmed reminder window", selection: Binding(get: { store.state.reminderWindowMinutes }, set: { value in do { try store.change { $0.reminderWindowMinutes = value } } catch { store.error = error.localizedDescription } })) {
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
                Text("4 hours").tag(240)
            }
            Text("Reminders repeat at the dose time, after 15 minutes, then every 30 minutes until confirmed or the window ends. The iPhone schedules them locally, including while the app is closed or offline.").font(.footnote).foregroundStyle(.secondary)
            if store.state.remindersEnabled {
                LabeledContent("Queued alerts", value: "\(reminders.scheduledCount)")
                if let coverage = reminders.coveredThrough { Text("Queued through \(coverage.formatted(date: .abbreviated, time: .shortened)). Open PillCheck regularly to extend this queue.").font(.footnote) }
                Text("iOS has a finite pending-alert queue. This app queues up to 60 dose alerts, plus a daily prompt to reopen it. Sound and presentation depend on your notification and Focus settings.").font(.footnote).foregroundStyle(.secondary)
                Button("Send a test notification in 10 seconds") {
                    Task {
                        do {
                            let ids = store.nextGroup.map(\.id)
                            try await reminders.sendTest(doseIDs: ids)
                            testMessage = ids.isEmpty ? "Test scheduled. Leave the app to check delivery in 10 seconds." : "Test scheduled. Leave the app, then tap the notification to preview your cards. Done in this preview leaves your history unchanged."
                        } catch { testMessage = error.localizedDescription }
                    }
                }.frame(minHeight: 56)
            }
            if reminders.permission == .denied {
                Text("Notification permission is off.").foregroundStyle(Theme.amber)
                Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            if let testMessage { Text(testMessage).font(.footnote) }
            if let error = reminders.schedulingError { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }
}
