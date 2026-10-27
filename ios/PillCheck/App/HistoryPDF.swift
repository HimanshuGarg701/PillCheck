import UIKit

enum HistoryPDF {
    @MainActor static func export(state: PillCheckState, from: Date, to: Date, medicationID: String?) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PillCheck-history-\(PillTime.key(from))-\(PillTime.key(to)).pdf")
        let doses = state.doses.filter {
            PillTime.day($0.scheduledAt) >= PillTime.day(from) && PillTime.day($0.scheduledAt) <= PillTime.day(to) && (medicationID == nil || $0.medicationId == medicationID)
        }.sorted { $0.scheduledAt > $1.scheduledAt }
        try renderer.writePDF(to: file) { context in
            var y: CGFloat = 45
            var number = 0
            func newPage() {
                context.beginPage(); number += 1; y = 45
                ("PillCheck · medication history    |    Page \(number)" as NSString).draw(at: CGPoint(x: 42, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
                (PillCheckCopy.disclaimer as NSString).draw(in: CGRect(x: 42, y: 749, width: 528, height: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
            }
            func text(_ value: String, size: CGFloat = 11, bold: Bool = false, gap: CGFloat = 8) {
                let attributes: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]
                let height = (value as NSString).boundingRect(with: CGSize(width: 528, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height.rounded(.up)
                if y + height > 724 { newPage() }
                (value as NSString).draw(in: CGRect(x: 42, y: y, width: 528, height: height + 2), withAttributes: attributes)
                y += height + gap
            }
            newPage()
            text("Medication history", size: 24, bold: true)
            text(state.patientDisplayName, size: 15, bold: true)
            text("Generated \(Date().formatted(date: .complete, time: .shortened))")
            text("Period: \(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted)).")
            if doses.contains(where: { $0.isSampleEntry }) { text("Includes sample history. Sample entries are identified in the dose record.") }
            text("Medicines and earlier regimens", size: 17, bold: true)
            for med in state.medications {
                if y > 620 { newPage() }
                text("\(med.name) · \(PillTime.number(med.strengthMg)) mg", size: 14, bold: true)
                text("Ingredient: \(med.ingredient). Recorded dose: \(PillTime.number(med.doseQuantity)) \(med.doseUnit). \(med.frequency), at \(med.times.joined(separator: ", ")).")
                text("Started \(med.startDate.formatted(date: .abbreviated, time: .omitted)) · \(med.endDate.map { "Ended " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "Ongoing")")
            }
            text("Daily dose record", size: 17, bold: true)
            for dose in doses {
                if y > 640 { newPage() }
                let med = state.medications.first { $0.id == dose.medicationId }
                text("\(dose.scheduledAt.formatted(date: .abbreviated, time: .shortened)) · \(med?.name ?? "Archived medicine")", bold: true)
                text("\(dose.status.title). \(med.map { PillTime.number($0.doseQuantity) + " " + $0.doseUnit } ?? "") · Confirmed: \(dose.confirmedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not recorded") · Method: \(dose.methodTitle)")
                if let reason = dose.replanReason ?? dose.reason, !reason.isEmpty { text(PillCheckCopy.recordText(reason)) }
            }
            if !state.changes.isEmpty {
                text("Recorded timing changes", size: 17, bold: true)
                for change in state.changes {
                    text("\(change.oldTime.formatted()) → \(change.newTime.formatted()): \(PillCheckCopy.recordText(change.reason))")
                }
            }
        }
        return file
    }
}
