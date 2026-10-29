import SwiftUI

@main
struct PillCheckApp: App {
    @StateObject private var store = PillStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.18, green: 0.34, blue: 0.85)
    static let accentSoft = Color(red: 0.92, green: 0.95, blue: 1)
    static let ink = Color(red: 0.09, green: 0.14, blue: 0.23)
    static let muted = Color(red: 0.36, green: 0.41, blue: 0.49)
    static let background = Color(red: 0.96, green: 0.97, blue: 0.985)
    static let surface = Color.white
    static let border = Color(red: 0.87, green: 0.90, blue: 0.94)
    static let navy = Color(red: 0.08, green: 0.16, blue: 0.30)
    static let onNavy = Color(red: 0.77, green: 0.84, blue: 0.96)
    static let success = Color(red: 0.04, green: 0.43, blue: 0.33)
    static let successSoft = Color(red: 0.90, green: 0.96, blue: 0.93)
    static let amber = Color(red: 0.53, green: 0.29, blue: 0.06)
    static let warningSoft = Color(red: 1, green: 0.96, blue: 0.89)
    static let danger = Color(red: 0.71, green: 0.18, blue: 0.21)
    static let pageTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var secondary = false
    var inverted = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(inverted ? Theme.navy : secondary ? Theme.accent : .white)
            .background(inverted ? Theme.surface : secondary ? Theme.surface : Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(secondary && !inverted ? Theme.border : .clear, lineWidth: 1) }
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

struct StatusBadge: View {
    enum Tone {
        case positive, warning, informational, neutral
        var foreground: Color {
            switch self {
            case .positive: Theme.success
            case .warning: Theme.amber
            case .informational: Theme.accent
            case .neutral: Theme.muted
            }
        }
        var background: Color {
            switch self {
            case .positive: Theme.successSoft
            case .warning: Theme.warningSoft
            case .informational: Theme.accentSoft
            case .neutral: Theme.background
            }
        }
    }
    let text: String
    var tone: Tone = .positive
    var body: some View {
        Text(text).font(.system(.caption, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tone.background, in: Capsule())
    }
}

struct MedicineIcon: View {
    var liquid = false
    var completed = false
    var body: some View {
        Image(systemName: completed ? "checkmark" : liquid ? "drop.fill" : "pills.fill")
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(completed ? Theme.success : Theme.accent)
            .frame(width: 44, height: 44)
            .background(completed ? Theme.successSoft : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}
extension View {
    func deferReminderCards(while presented: Bool) -> some View {
        modifier(ReminderDeferral(isPresented: presented))
    }
    func card(_ color: Color = Theme.surface) -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border.opacity(0.65), lineWidth: 1) }
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
            .font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
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
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today").font(Theme.pageTitle).tracking(-0.6)
                        Text(store.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if let notice = store.notice {
                        HStack(alignment: .top) { Label(notice, systemImage: "checkmark.circle.fill"); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message") }.font(.subheadline).foregroundStyle(Theme.success).card(Theme.successSoft)
                    }
                    nextCard
                    VStack(spacing: 12) {
                        HStack {
                            Text("Today’s schedule").font(Theme.sectionTitle)
                            Spacer()
                            Text("\(store.today.filter { $0.status.isTaken }.count) of \(store.today.count) taken").font(.system(.subheadline, weight: .medium)).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        ProgressView(value: Double(store.today.filter { $0.status.isTaken }.count), total: Double(max(1, store.today.count)))
                            .tint(Theme.accent).accessibilityLabel("Today's recorded doses")
                    }
                    VStack(spacing: 0) {
                        ForEach(store.today) { dose in
                            if let med = store.medicine(dose.medicationId) {
                                DoseRow(dose: dose, medication: med) { store.openReminder(ids: [dose.id]) }
                                if dose.id != store.today.last?.id { Divider().overlay(Theme.border).padding(.leading, 56) }
                            }
                        }
                    }.card()
                    if store.lateDoseID != nil {
                        Button { showReplan = true } label: { Label("Review the late-dose record", systemImage: "clock.badge.exclamationmark") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                    }
                    let risks = MedicationEngine.activeRisks(store.state, now: store.now)
                    if !risks.isEmpty { ForEach(risks) { RiskFlagView(flag: $0) } }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Manage your medicines").font(Theme.sectionTitle)
                        Button { adding = true } label: { Label("Add a medicine", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                        Button { store.openReminder() } label: { Label("Open reminder cards", systemImage: "speaker.wave.2") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                        if store.state.practiceClockEnabled { Text("Reminder preview: \(store.now.formatted(date: .omitted, time: .shortened)). Notifications are paused. End the preview in Preferences.").font(.footnote).foregroundStyle(Theme.muted) }
                    }.card()
                    DisclaimerView()
                }.padding(20)
            }.background(Theme.background)
                .navigationTitle("PillCheck").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add medicine") } }
                .sheet(isPresented: $adding) { IntakeView() }
                .sheet(isPresented: $showReplan) { if let id = store.lateDoseID { ReplanView(doseID: id) } }
                .deferReminderCards(while: adding || showReplan)
        }
    }
    private var nextCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let first = store.nextGroup.first {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(first.scheduledAt < store.now ? "AWAITING CHECK-IN" : "NEXT CHECK-IN")
                            .font(.system(.caption, weight: .semibold)).tracking(1.3).foregroundStyle(Theme.onNavy)
                        Text(first.scheduledAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(.largeTitle, weight: .semibold)).tracking(-0.8).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "clock").font(.title3).foregroundStyle(Theme.onNavy)
                        .frame(width: 40, height: 40).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.nextGroup) { dose in
                        if let med = store.medicine(dose.medicationId) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: med.isLiquid ? "drop.fill" : "pills.fill").foregroundStyle(Theme.onNavy).padding(.top, 3).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(med.name).font(.headline)
                                    Text("\(med.strengthText) · \(med.doseText)").font(.subheadline).foregroundStyle(Theme.onNavy)
                                }
                            }
                        }
                    }
                }.fixedSize(horizontal: false, vertical: true)
                Button { store.openReminder() } label: { HStack { Text("Review medicines"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(PrimaryButtonStyle(inverted: true))
            } else {
                Image(systemName: "checkmark.circle").font(.largeTitle)
                Text("Your day is recorded.").font(Theme.sectionTitle)
                Text("Every check-in keeps your history clear.").foregroundStyle(Theme.onNavy)
            }
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.navy, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct DoseRow: View {
    let dose: DoseEvent
    let medication: Medication
    let review: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MedicineIcon(liquid: medication.isLiquid, completed: dose.status.isTaken)
                VStack(alignment: .leading, spacing: 5) {
                    Text(medication.name).font(.headline)
                    Text("\(medication.strengthText) · \(medication.doseText)").font(.subheadline).foregroundStyle(Theme.muted)
                    Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened)).font(.system(.subheadline, weight: .medium)).monospacedDigit()
                    if dose.replanReason != nil { Text("Adjusted from \(dose.originalScheduledAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Theme.accent) }
                }
                Spacer(minLength: 0)
            }
            if dose.status.canRecord {
                Button(dose.status == .missed ? "Review missed record" : "Review") { review() }.buttonStyle(PrimaryButtonStyle(secondary: true))
            } else { StatusBadge(text: dose.status.title, tone: dose.status.isTaken ? .positive : .warning).padding(.leading, 56) }
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
        }.foregroundStyle(Theme.amber).card(Theme.warningSoft)
    }
}
