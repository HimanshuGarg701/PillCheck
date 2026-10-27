import SwiftUI
import UserNotifications

struct PreferencesView: View {
    @EnvironmentObject private var store: PillStore
    @State private var problems = ""
    @State private var checking = false
    @State private var connection: String?
    @State private var shareRecords = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DemoBadge()
                    Text("A little help, your way.").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Synthetic records only. Your medication history is stored on this iPhone and survives app restarts.").foregroundStyle(.secondary)
                }
                Section("Voice & language") {
                    Picker("Spoken language", selection: Binding(get: { store.state.language }, set: { value in update { $0.language = value } })) {
                        Text("English").tag("en-US")
                        Text("Español").tag("es-ES")
                        Text("हिन्दी").tag("hi-IN")
                    }
                    Text("Meta writes reminder text in this language. iOS reads it aloud. Previously generated text is cached for offline playback. Voice confirmation uses on-device recognition when supported.").font(.footnote).foregroundStyle(.secondary)
                }
                NotificationSettings(store: store, reminders: store.notifications)
                Section("Practice clock") {
                    Toggle("Use practice time", isOn: Binding(get: { store.state.practiceClockEnabled }, set: { value in do { try store.setPractice(value) } catch { store.error = error.localizedDescription } }))
                    if store.state.practiceClockEnabled {
                        DatePicker("Practice time", selection: Binding(get: { store.state.practiceTime }, set: { value in update { $0.practiceTime = value }; store.refresh() }), displayedComponents: .hourAndMinute)
                    }
                    Text("Practice time is for the fictional examples. Enabling it switches off real notifications. Saved confirmations are retained when you return to the real clock.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recorded class concerns") {
                    TextField("e.g. statin, anticoagulant", text: $problems)
                    Button("Save class concerns") {
                        update { $0.problems = problems.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }; $0.audit.append(AuditEntry(type: "class_concerns_updated", at: Date(), reason: "Recorded medication-class concerns updated.")) }
                        store.notice = "Medication-class concerns saved."
                    }
                    Text("This records a known problem with a medicine class. It is not a diagnosis or allergy assessment.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Meta Model API") {
                    LabeledContent("Approved model", value: "Muse Spark 1.3")
                    Button {
                        checking = true
                        Task { do { connection = try await store.meta.checkConnection(); store.modelStatus = "Muse Spark 1.3 · live" } catch { connection = error.localizedDescription }; checking = false }
                    } label: { HStack { Text("Check live connection"); if checking { Spacer(); ProgressView() } } }.disabled(checking)
                    if let connection { Text(connection).font(.footnote).textSelection(.enabled) }
                    Text("Label parsing, reminder text, and fictional timing proposals use the live model. Persistent provider errors are shown without fabricated results. The credential stays on the server.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your records") {
                    Button { shareRecords = true } label: { Label("Export all records (JSON)", systemImage: "square.and.arrow.up") }
                    Text("There is no delete-history control. Earlier regimens, confirmations, and audit entries are retained. Keep an export before uninstalling the app or replacing this iPhone.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { DisclaimerView() }
            }.scrollContentBackground(.hidden).background(Theme.cream).navigationTitle("Preferences").navigationBarTitleDisplayMode(.inline)
                .onAppear { problems = store.state.problems.joined(separator: ", ") }
                .sheet(isPresented: $shareRecords) { ShareSheet(items: [store.fileURL]) }
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
                    Task { do { try await reminders.sendTest(); testMessage = "Test scheduled. Leave the app to check delivery in 10 seconds." } catch { testMessage = error.localizedDescription } }
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
