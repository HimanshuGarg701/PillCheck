import Foundation

enum PillCheckCopy {
    // Present older system labels consistently without rewriting saved history.
    static func recordText(_ value: String) -> String {
        value.replacingOccurrences(of: "Fictional profile and synthetic records only.", with: "Sample medicines and history added.")
            .replacingOccurrences(of: "Fictional late-dose example", with: "Sample late check-in")
            .replacingOccurrences(of: "Synthetic duplicate-entry test completed", with: "Sample duplicate check completed")
    }
    static let disclaimer = "Informational only, not medical advice. Confirm with your doctor or pharmacist."
    static let pharmacist = "This medicine needs your pharmacist’s advice. Call your pharmacist before taking it."
    static func pharmacist(language: String) -> String {
        switch language {
        case "es-ES": "Este medicamento necesita el consejo de su farmacéutico. Llame a su farmacéutico antes de tomarlo."
        case "hi-IN": "इस दवा के लिए आपको अपने फ़ार्मासिस्ट की सलाह चाहिए। इसे लेने से पहले अपने फ़ार्मासिस्ट को फ़ोन करें।"
        default: pharmacist
        }
    }
}

enum MedicineStatus: String, Codable { case active, stopped }
enum DoseStatus: String, Codable, CaseIterable {
    case pending, takenOnTime = "taken_on_time", takenLate = "taken_late", skipped, missed, cancelled
    var title: String {
        switch self {
        case .pending: "Upcoming"
        case .takenOnTime: "Taken on time"
        case .takenLate: "Taken late"
        case .skipped: "Skipped"
        case .missed: "Missed"
        case .cancelled: "Regimen updated"
        }
    }
    var isTaken: Bool { self == .takenOnTime || self == .takenLate }
    var canRecord: Bool { self == .pending || self == .missed }
}

struct Medication: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var ingredient: String
    var strengthMg: Double
    var doseQuantity: Double
    var doseUnit: String
    var frequency: String
    var times: [String]
    var instructions: String = ""
    var riskClass: String = ""
    var startDate: Date
    var endDate: Date? = nil
    var status: MedicineStatus = .active
    var highRisk: Bool = false
    var demo: Bool = true
    var minSpacingHours: Double? = nil
    var source: String = "manual-reviewed"
    var archiveReason: String? = nil
    var dailyMg: Double { strengthMg * doseQuantity * Double(times.count) }
}

struct DoseEvent: Identifiable, Codable, Equatable {
    var id: String
    var medicationId: String
    var scheduledAt: Date
    var originalScheduledAt: Date
    var status: DoseStatus = .pending
    var confirmedAt: Date? = nil
    var method: String? = nil
    var reason: String? = nil
    var replanReason: String? = nil
    var isSampleEntry: Bool { method == "sample" || method == "synthetic-seed" }
    var methodTitle: String {
        if isSampleEntry { return "Sample entry" }
        switch method {
        case "button": return "Button"
        case "voice": return "Voice"
        case "notification": return "Notification"
        default: return method ?? "Not recorded"
        }
    }
}

struct ScheduleChange: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var doseId: String
    var medicationId: String
    var oldTime: Date
    var newTime: Date
    var reason: String
    var at: Date
}

struct RiskFlag: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var kind: String
    var title: String
    var explanation: String
    var medications: [String] = []
    var combinedMg: Double? = nil
    var sourceURL: String? = nil
    var at: Date = Date()
    var acknowledgedAt: Date? = nil
}

struct AuditEntry: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var type: String
    var at: Date
    var reason: String
    var source: String? = nil
}

struct PillCheckState: Codable, Equatable {
    var version = 1
    var patient = "Alex Morgan"
    var patientDisplayName: String { patient == "Alex Morgan (fictional)" ? "Alex Morgan" : patient }
    var medications: [Medication]
    var doses: [DoseEvent]
    var changes: [ScheduleChange] = []
    var flags: [RiskFlag] = []
    var audit: [AuditEntry] = []
    var problems: [String] = []
    var language = "en-US"
    var reminderWindowMinutes = 120
    var remindersEnabled = false
    var practiceClockEnabled = false
    var practiceTime: Date
    var lastGeneratedDay: Date
    var spokenCache: [String: String] = [:]
    var medicationReviews: [MedicationAIReview]? = nil
}

struct ScanResult: Codable {
    var name: String?
    var ingredient: String?
    var strengthMg: Double?
    var doseQuantity: Double?
    var doseUnit: String?
    var frequency: String?
    var times: [String]
    var instructions: String?
    var uncertainFields: [String]
    var explanation: String
    var model: String?
    var source: String?
}

struct ReplanProposal: Codable {
    struct Change: Codable {
        var doseId: String
        var newTime: Date
        var doseQuantity: Double
    }
    var changes: [Change]
    var explanation: String
    var source: String?
    var model: String?
}

struct PillCheckError: LocalizedError, Equatable {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum PillTime {
    static func day(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }
    static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func at(_ date: Date, _ time: String) -> Date? {
        guard time.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }
    static func addingDays(_ number: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: number, to: date)!
    }
    static func sameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: value) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: value) { return date }
            throw PillCheckError("A saved timestamp could not be read.")
        }
        return decoder
    }
}
