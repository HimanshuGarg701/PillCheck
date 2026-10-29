import SwiftUI

@main
struct PillCheckApp: App {
    @StateObject private var store = PillStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Theme.green)
                .preferredColorScheme(.light)
        }
    }
}

enum Theme {
    static let green = Color(red: 0.20, green: 0.36, blue: 0.28)
    static let ink = Color(red: 0.15, green: 0.22, blue: 0.18)
    static let cream = Color(red: 0.97, green: 0.975, blue: 0.95)
    static let sage = Color(red: 0.90, green: 0.94, blue: 0.86)
    static let amber = Color(red: 0.48, green: 0.33, blue: 0.12)
    static let peach = Color(red: 0.96, green: 0.89, blue: 0.81)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(secondary ? Theme.green : .white)
            .background(secondary ? Theme.sage : Theme.green, in: RoundedRectangle(cornerRadius: 17))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}
extension View {
    func deferReminderCards(while presented: Bool) -> some View {
        modifier(ReminderDeferral(isPresented: presented))
    }
    func card(_ color: Color = .white) -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 24))
    }
}
private struct ReminderDeferral: ViewModifier {
    @EnvironmentObject private var store: PillStore
    @State private var id = UUID()
    let isPresented: Bool
    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, value in store.deferReminderCards(value, for: id) }
    }
}
struct DisclaimerView: View {
    var body: some View {
        Label(PillCheckCopy.disclaimer, systemImage: "checkmark.shield")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(PillCheckCopy.disclaimer)
    }
}
struct WarningBox: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Theme.amber).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RootView: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.scenePhase) private var phase
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if let error = store.loadError {
                VStack(spacing: 24) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("Your records need attention").font(.title2.bold())
                    Text(error)
                    ShareLink("Export original records", item: store.fileURL)
                }.padding(28)
            } else {
                TabView {
                    TodayView().tabItem { Label("Today", systemImage: "sun.max") }
                    MedicinesView().tabItem { Label("Medicines", systemImage: "pills") }
                    HistoryView().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    PreferencesView().tabItem { Label("Preferences", systemImage: "slider.horizontal.3") }
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .sheet(item: $store.activeReminder, onDismiss: { store.resumeReminderCards() }) { selection in ReminderView(selection: selection).environmentObject(store) }
        .alert("PillCheck", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onReceive(ticker) { _ in store.refresh() }
        .onChange(of: phase, initial: true) { _, value in
            if value == .active { store.becameActive() }
            else if value == .background { store.enteredBackground() }
        }
        .onChange(of: store.error) { _, value in if value == nil { store.resumeReminderCards() } }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: PillStore
    @State private var adding = false
    @State private var showReplan = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(.secondary)
                    Text("One day at a time.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("A clear plan for your medicines.\nA little more peace of mind.").foregroundStyle(.secondary)
                    if let notice = store.notice {
                        HStack(alignment: .top) { Label(notice, systemImage: "checkmark.circle.fill"); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message") }.font(.subheadline).card(Theme.sage)
                    }
                    nextCard
                    HStack {
                        Text("Today’s schedule").font(.title2.bold())
                        Spacer()
                        Text("\(store.today.filter { $0.status.isTaken }.count) / \(store.today.count) taken").font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(store.today) { dose in
                            if let med = store.medicine(dose.medicationId) {
                                DoseRow(dose: dose, medication: med) { store.openReminder(ids: [dose.id]) }
                                if dose.id != store.today.last?.id { Divider().padding(.leading, 58) }
                            }
                        }
                    }.card()
                    if store.lateDoseID != nil {
                        Button { showReplan = true } label: { Label("Review the late-dose record", systemImage: "clock.badge.exclamationmark") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                    }
                    let risks = MedicationEngine.activeRisks(store.state, now: store.now)
                    if !risks.isEmpty { ForEach(risks) { RiskFlagView(flag: $0) } }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Manage your medicines").font(.headline)
                        Button { adding = true } label: { Label("Add a medicine", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                        Button { store.openReminder() } label: { Label("Open reminder cards", systemImage: "speaker.wave.2") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                        if store.state.practiceClockEnabled { Text("Reminder preview: \(store.now.formatted(date: .omitted, time: .shortened)). Notifications are paused. End the preview in Preferences.").font(.footnote).foregroundStyle(.secondary) }
                    }.card()
                    DisclaimerView()
                    Text(store.modelStatus).font(.caption).foregroundStyle(Theme.green)
                }.padding(20)
            }.background(Theme.cream)
                .navigationTitle("PillCheck").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add medicine") } }
                .sheet(isPresented: $adding) { IntakeView() }
                .sheet(isPresented: $showReplan) { if let id = store.lateDoseID { ReplanView(doseID: id) } }
                .deferReminderCards(while: adding || showReplan)
        }
    }
    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let first = store.nextGroup.first {
                Label(first.scheduledAt.formatted(date: .omitted, time: .shortened), systemImage: "sun.max").font(.headline)
                Text(first.scheduledAt < store.now ? "A moment to check in." : "Your next check-in.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("\(store.nextGroup.count) medicine\(store.nextGroup.count == 1 ? "" : "s") on this part of your recorded schedule.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) { ForEach(store.nextGroup) { dose in if let med = store.medicine(dose.medicationId) { Label(med.name, systemImage: "pills").font(.subheadline) } } }.fixedSize(horizontal: false, vertical: true)
                Button { store.openReminder() } label: { Label("Review medicines", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
            } else {
                Image(systemName: "checkmark.circle").font(.largeTitle)
                Text("Your day is recorded.").font(.title2.bold())
                Text("Every check-in keeps your history clear.").foregroundStyle(.secondary)
            }
        }.card(Theme.sage)
    }
}

struct DoseRow: View {
    let dose: DoseEvent
    let medication: Medication
    let review: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: dose.status.isTaken ? "checkmark.circle.fill" : medication.isLiquid ? "drop.fill" : "pills").font(.title2).foregroundStyle(Theme.green).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(medication.name).font(.headline)
                    Text("\(medication.strengthText) · \(medication.doseText)").font(.subheadline).foregroundStyle(.secondary)
                    Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened)).font(.subheadline.weight(.semibold))
                    if dose.replanReason != nil { Text("Adjusted from \(dose.originalScheduledAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.green) }
                }
                Spacer(minLength: 0)
            }
            if dose.status.canRecord {
                Button(dose.status == .missed ? "Review missed record" : "Review") { review() }.buttonStyle(PrimaryButtonStyle(secondary: true))
            } else { Text(dose.status.title).font(.subheadline.weight(.medium)).foregroundStyle(dose.status.isTaken ? Theme.green : Theme.amber).padding(.leading, 46) }
        }.padding(.vertical, 14)
    }
}

struct RiskFlagView: View {
    let flag: RiskFlag
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(flag.title, systemImage: "exclamationmark.triangle").font(.headline)
            Text(flag.explanation).font(.subheadline)
            if let total = flag.combinedMg { Text("Combined daily ingredient: \(PillTime.number(total)) mg").font(.headline) }
            if let source = flag.sourceURL, let url = URL(string: source) { Link("Reference: DailyMed prescribing information", destination: url).font(.footnote) }
        }.foregroundStyle(Theme.amber).card(Color.yellow.opacity(0.09))
    }
}
