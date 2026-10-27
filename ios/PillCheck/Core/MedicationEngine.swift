import Foundation

enum MedicationEngine {
    static let interactionSource = "https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=f19ad89c-8dbe-4806-8068-f63aa895488d&type=display"
    static func canonical(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(hydrochloride|hcl)$"#, with: "", options: .regularExpression)
    }
    static func isHighRisk(_ m: Medication) -> Bool {
        m.highRisk || "\(m.name) \(m.ingredient) \(m.riskClass)".range(
            of: "insulin|warfarin|apixaban|rivaroxaban|dabigatran|edoxaban|heparin|enoxaparin|clopidogrel|carbidopa|levodopa|ropinirole|pramipexole|levetiracetam|phenytoin|carbamazepine|valpro|lamotrigine|tacrolimus|cyclosporine|mycophenolate|sirolimus|anticoagulant|antiplatelet|parkinson|seizure|transplant|blood thinner",
            options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func validate(_ input: Medication) throws -> Medication {
        var m = input
        for (title, value) in [("medicine name", m.name), ("active ingredient", m.ingredient), ("dose unit", m.doseUnit), ("frequency", m.frequency)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 100 else { throw PillCheckError("Confirm the \(title).") }
        }
        guard m.strengthMg.isFinite, m.strengthMg > 0, m.strengthMg <= 100_000 else { throw PillCheckError("Confirm the strength in mg.") }
        guard m.doseQuantity.isFinite, m.doseQuantity > 0, m.doseQuantity <= 100 else { throw PillCheckError("Confirm the quantity per dose.") }
        guard !m.times.isEmpty, m.times.count <= 8, Set(m.times).count == m.times.count,
              m.times.allSatisfy({ PillTime.at(m.startDate, $0) != nil }) else { throw PillCheckError("Enter distinct times in 24-hour format, for example 08:00, 18:00.") }
        m.name = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
        m.ingredient = canonical(m.ingredient)
        m.times.sort()
        m.highRisk = isHighRisk(m)
        return m
    }
    static func schedule(_ med: Medication, on date: Date) -> [DoseEvent] {
        guard med.status == .active, PillTime.day(date) >= PillTime.day(med.startDate),
              med.endDate.map({ PillTime.day(date) <= PillTime.day($0) }) ?? true else { return [] }
        return med.times.compactMap { time in
            guard let at = PillTime.at(date, time), at >= med.startDate else { return nil }
            return DoseEvent(id: "\(med.id):\(PillTime.key(date)):\(time)", medicationId: med.id, scheduledAt: at, originalScheduledAt: at)
        }
    }
    static func risks(for candidate: Medication, in state: PillCheckState, now: Date) -> [RiskFlag] {
        let others = state.medications.filter { $0.id != candidate.id }
        let duplicates = others.filter { $0.status == .active && canonical($0.ingredient) == canonical(candidate.ingredient) }
        var flags: [RiskFlag] = []
        if !duplicates.isEmpty {
            flags.append(RiskFlag(kind: "duplicate", title: "Same ingredient, different label", explanation: "This has the same active ingredient as \(duplicates.map(\.name).joined(separator: ", ")). Taking both can double your daily dose. Check with your doctor before starting this.", medications: duplicates.map(\.id), combinedMg: candidate.dailyMg + duplicates.reduce(0) { $0 + $1.dailyMg }, at: now))
        }
        for other in others {
            let recentlyStopped = other.status == .stopped && other.endDate.map { $0 <= now && now.timeIntervalSince($0) <= 30 * 86400 } == true
            guard other.status == .active || recentlyStopped else { continue }
            if Set([canonical(candidate.ingredient), canonical(other.ingredient)]) == Set(["metformin", "cimetidine"]) {
                flags.append(RiskFlag(kind: "interaction", title: "\(candidate.name) + \(other.name)", explanation: "\(recentlyStopped ? "Recently stopped medicine: " : "")Cimetidine can reduce metformin clearance and increase its exposure. Check with your doctor or pharmacist before taking these together.", medications: [other.id], sourceURL: interactionSource, at: now))
            }
        }
        if !candidate.riskClass.isEmpty && state.problems.map(canonical).contains(canonical(candidate.riskClass)) {
            flags.append(RiskFlag(kind: "history", title: "Recorded medication-class concern", explanation: "A problem with this medicine class is recorded in your history. Tell your doctor about this before you start it.", at: now))
        }
        return flags
    }
    static func activeRisks(_ state: PillCheckState, now: Date) -> [RiskFlag] {
        var seen = Set<String>()
        return state.medications.filter { $0.status == .active }.flatMap { med in
            risks(for: med, in: state, now: now).filter { flag in
                let key = ([med.id] + flag.medications).sorted().joined(separator: ":") + flag.kind
                return seen.insert(key).inserted
            }
        }
    }
    static func confirm(_ ids: [String], state: inout PillCheckState, at: Date, method: String, skipped: Bool = false, reason: String = "") throws {
        guard !ids.isEmpty, Set(ids).count == ids.count, ["button", "voice", "notification"].contains(method) else { throw PillCheckError("Choose a dose to record.") }
        for id in ids {
            guard let dose = state.doses.first(where: { $0.id == id }), dose.status.canRecord else { throw PillCheckError("A dose in this group is already recorded. No duplicate confirmation was saved.") }
            guard at >= dose.scheduledAt.addingTimeInterval(-24 * 3600) else { throw PillCheckError("Check the confirmation date.") }
        }
        for id in ids {
            let i = state.doses.firstIndex { $0.id == id }!
            state.doses[i].status = skipped ? .skipped : (at.timeIntervalSince(state.doses[i].scheduledAt) > 30 * 60 ? .takenLate : .takenOnTime)
            state.doses[i].confirmedAt = at
            state.doses[i].method = method
            state.doses[i].reason = reason
            state.audit.append(AuditEntry(type: "dose_recorded", at: at, reason: "\(id): \(state.doses[i].status.title), \(method). \(reason)"))
        }
    }
    static func catchUp(_ state: inout PillCheckState, now: Date) {
        let today = PillTime.day(now)
        let known = Set(state.doses.map(\.id))
        var day = PillTime.day(state.lastGeneratedDay)
        // Reject corrupt far-future state without modifying the original records.
        guard today >= day else { return }
        while day <= today {
            for med in state.medications {
                state.doses.append(contentsOf: schedule(med, on: day).filter { !known.contains($0.id) })
            }
            day = PillTime.addingDays(1, to: day)
        }
        state.lastGeneratedDay = today
        for i in state.doses.indices where state.doses[i].status == .pending {
            if now.timeIntervalSince(state.doses[i].scheduledAt) >= Double(state.reminderWindowMinutes) * 60 {
                state.doses[i].status = .missed
                state.audit.append(AuditEntry(type: "reminder_window_elapsed", at: now, reason: "\(state.doses[i].id): unconfirmed after the reminder window."))
            }
        }
    }
    static func save(_ candidate: Medication, replacing oldID: String?, acknowledged: Bool, state: inout PillCheckState, now: Date) throws {
        var med = try validate(candidate)
        guard PillTime.day(med.startDate) >= PillTime.day(now) else { throw PillCheckError("New regimens must start today or later. Past records stay unchanged.") }
        if oldID != nil && !PillTime.sameDay(med.startDate, now) { throw PillCheckError("Regimen updates take effect today. Add a separate record for a future start date.") }
        let flags = risks(for: med, in: state, now: now)
        guard flags.isEmpty || acknowledged else { throw PillCheckError("Read and acknowledge the risk flags before saving.") }
        if PillTime.sameDay(med.startDate, now) { med.startDate = now }
        if let oldID {
            guard let oldIndex = state.medications.firstIndex(where: { $0.id == oldID && $0.status == .active }) else { throw PillCheckError("The earlier regimen is no longer active.") }
            state.medications[oldIndex].status = .stopped
            state.medications[oldIndex].endDate = now
            state.medications[oldIndex].archiveReason = "Regimen updated"
            for i in state.doses.indices where state.doses[i].medicationId == oldID && state.doses[i].status == .pending && state.doses[i].scheduledAt >= now {
                state.doses[i].status = .cancelled
                state.doses[i].reason = "Superseded by a reviewed regimen"
            }
            med.id = UUID().uuidString
            med.minSpacingHours = nil
        }
        state.medications.append(med)
        state.doses.append(contentsOf: schedule(med, on: now).filter { $0.scheduledAt >= now })
        state.flags.append(contentsOf: flags.map { var f = $0; f.acknowledgedAt = now; return f })
        state.audit.append(AuditEntry(type: oldID == nil ? "medicine_added" : "regimen_updated", at: now, reason: "\(med.name): reviewed \(PillTime.number(med.doseQuantity)) \(med.doseUnit), \(med.times.joined(separator: ", ")). \(flags.count) flags acknowledged.", source: med.source))
    }
    static func archive(_ id: String, state: inout PillCheckState, now: Date, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let i = state.medications.firstIndex(where: { $0.id == id && $0.status == .active }) else { throw PillCheckError("Enter a reason for archiving this recorded regimen.") }
        state.medications[i].status = .stopped
        state.medications[i].endDate = now
        state.medications[i].archiveReason = reason
        for j in state.doses.indices where state.doses[j].medicationId == id && state.doses[j].status == .pending && state.doses[j].scheduledAt >= now {
            state.doses[j].status = .cancelled
            state.doses[j].reason = "Recorded prescription already discontinued"
        }
        state.audit.append(AuditEntry(type: "medicine_archived", at: now, reason: "\(state.medications[i].name): \(reason)"))
    }
    static func replanEligible(_ med: Medication) -> Bool {
        !isHighRisk(med) && med.demo && med.id == "med-metformin" && canonical(med.ingredient) == "metformin" && med.strengthMg == 500 && med.doseQuantity == 1 && med.minSpacingHours == 10
    }
    static func apply(_ proposal: ReplanProposal, medication: Medication, confirmed: DoseEvent, state: inout PillCheckState) throws {
        guard !isHighRisk(medication) else { throw PillCheckError(PillCheckCopy.pharmacist) }
        guard replanEligible(medication), let confirmedAt = confirmed.confirmedAt, confirmed.status.isTaken else { throw PillCheckError("A pharmacist-approved timing plan is required for this medicine.") }
        let future = state.doses.filter { $0.medicationId == medication.id && $0.status == .pending && PillTime.sameDay($0.scheduledAt, confirmedAt) }.sorted { $0.scheduledAt < $1.scheduledAt }
        guard !future.isEmpty, proposal.changes.count == future.count, !proposal.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, proposal.explanation.count <= 600,
              proposal.explanation.range(of: #"double|increase|decrease|\btake\b|\bstop\b|safe to|\bskip\b|resume tomorrow"#, options: [.regularExpression, .caseInsensitive]) == nil else { throw PillCheckError("The proposed plan needs pharmacist review. No times changed.") }
        var previous = confirmedAt
        var seen = Set<String>()
        var changes: [ScheduleChange] = []
        for (offset, change) in proposal.changes.enumerated() {
            let original = future[offset]
            guard change.doseId == original.id, seen.insert(change.doseId).inserted, change.doseQuantity == medication.doseQuantity,
                  PillTime.sameDay(change.newTime, confirmedAt), change.newTime >= original.scheduledAt,
                  change.newTime.timeIntervalSince(previous) >= 10 * 3600 else { throw PillCheckError("The proposal changed a dose or broke the fictional spacing rule. No times changed.") }
            changes.append(ScheduleChange(doseId: change.doseId, medicationId: medication.id, oldTime: original.scheduledAt, newTime: change.newTime, reason: proposal.explanation, at: confirmedAt))
            previous = change.newTime
        }
        for change in changes {
            let i = state.doses.firstIndex { $0.id == change.doseId }!
            state.doses[i].scheduledAt = change.newTime
            state.doses[i].replanReason = change.reason
        }
        state.changes.append(contentsOf: changes)
        state.audit.append(AuditEntry(type: "replan", at: confirmedAt, reason: proposal.explanation, source: proposal.source))
    }
}

enum SeedData {
    static func medicines(now: Date) -> [Medication] {
        let start = PillTime.addingDays(-30, to: PillTime.day(now))
        return [
            Medication(id: "med-metformin", name: "Metformin", ingredient: "metformin", strengthMg: 500, doseQuantity: 1, doseUnit: "tablet", frequency: "Twice daily", times: ["08:00", "18:00"], instructions: "With meals", startDate: start, minSpacingHours: 10, source: "synthetic-seed"),
            Medication(id: "med-amlodipine", name: "Amlodipine", ingredient: "amlodipine", strengthMg: 5, doseQuantity: 1, doseUnit: "tablet", frequency: "Once daily", times: ["08:00"], instructions: "Follow the recorded prescription", startDate: start, source: "synthetic-seed"),
            Medication(id: "med-atorvastatin", name: "Atorvastatin", ingredient: "atorvastatin", strengthMg: 20, doseQuantity: 1, doseUnit: "tablet", frequency: "Once daily", times: ["20:00"], instructions: "Follow the recorded prescription", startDate: start, source: "synthetic-seed")
        ]
    }
    static func make(now: Date = Date()) -> PillCheckState {
        let meds = medicines(now: now)
        var doses: [DoseEvent] = []
        for offset in -30...0 {
            for med in meds {
                for var dose in MedicationEngine.schedule(med, on: PillTime.addingDays(offset, to: now)) {
                    if offset < 0 {
                        let n = doses.count
                        dose.status = n % 19 == 0 ? .missed : n % 17 == 0 ? .skipped : n % 13 == 0 ? .takenLate : .takenOnTime
                        dose.confirmedAt = dose.status == .missed ? nil : dose.scheduledAt.addingTimeInterval(dose.status == .takenLate ? 4200 : 120)
                        dose.method = "synthetic-seed"
                    }
                    doses.append(dose)
                }
            }
        }
        return PillCheckState(medications: meds, doses: doses, audit: [AuditEntry(type: "demo_created", at: now, reason: "Fictional profile and synthetic records only.")], practiceTime: PillTime.at(now, "08:00")!, lastGeneratedDay: PillTime.day(now))
    }
}
