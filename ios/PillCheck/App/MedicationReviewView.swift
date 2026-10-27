import SwiftUI

struct MedicationReviewContent: View {
    let review: MedicationAIReview
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(review.completed ? "Reviewed with Muse Spark 1.3" : "AI review incomplete", systemImage: review.completed ? "sparkles" : "exclamationmark.triangle")
                .font(.headline).foregroundStyle(review.completed ? Theme.green : Theme.amber)
            Text(review.summary).font(.title3)
            if !review.completed, let problem = review.warnings.last { WarningBox(text: problem) }
            Text("Checked \(review.createdAt.formatted(date: .abbreviated, time: .shortened)). This is a snapshot of the supplied list.").font(.footnote).foregroundStyle(.secondary)
            Text("Ingredients behind the brands").font(.title2.bold())
            ForEach(review.identities) { identity in
                VStack(alignment: .leading, spacing: 8) {
                    Text(identity.name).font(.headline)
                    Text(identity.status == "matched" ? identity.ingredients.joined(separator: " + ") : "Ingredient identity not resolved in the U.S. reference.")
                    if !identity.preciseIngredients.isEmpty { Text("Salt / precise ingredient: " + identity.preciseIngredients.joined(separator: " + ")).font(.subheadline).foregroundStyle(.secondary) }
                    if let source = identity.sourceURL, let url = URL(string: source) { Link("NLM RxNorm source", destination: url).font(.footnote) }
                }.card(Theme.sage)
            }
            Text("Compared with your list").font(.title2.bold())
            if review.pairs.isEmpty { Text("No other active or recently stopped medicines were supplied. This does not establish safety.").foregroundStyle(.secondary) }
            ForEach(review.pairs) { pair in
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(review.candidateName) + \(pair.medicationName)").font(.headline)
                    if pair.status == "stopped" { Text("Recently stopped medicine").font(.caption).foregroundStyle(Theme.amber) }
                    Label(pair.ingredientTitle, systemImage: "pills")
                    if !pair.overlapIngredients.isEmpty { Text("Shared: " + pair.overlapIngredients.joined(separator: ", ")).bold() }
                    if !pair.duplicateBasis.isEmpty { Text(pair.duplicateBasis).font(.subheadline) }
                    Label(pair.interactionTitle, systemImage: "exclamationmark.shield")
                    Text(pair.explanation).font(.subheadline)
                    if let minutes = pair.spacingMinutes { Text("Label-supported separation: at least \(minutes / 60) hours. Spacing does not establish overall safety.").font(.subheadline.weight(.semibold)) }
                    ForEach(Array(pair.evidence.enumerated()), id: \.offset) { _, evidence in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("“\(evidence.quote)”").font(.footnote).italic()
                            if let source = review.sources.first(where: { $0.id == evidence.sourceId }), let url = URL(string: source.url) { Link(source.title, destination: url).font(.footnote) }
                        }
                    }
                }.card(Theme.peach)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("Schedule review", systemImage: "clock").font(.title2.bold())
                ForEach(review.timing.conflicts, id: \.self) { WarningBox(text: $0) }
                Text(review.timing.explanation)
                if !review.timing.proposedTimes.isEmpty {
                    Text("Draft for pharmacist review").font(.headline)
                    Text("\(review.candidateName): \(review.timing.proposedTimes.joined(separator: " · "))").font(.title2.bold())
                    Text("Other medicine times and every dose amount stay unchanged. Meal instructions and the complete regimen still need pharmacist confirmation. This draft has not changed your schedule.").font(.subheadline)
                    ShareLink(item: shareText) { Label("Share timing draft for review", systemImage: "square.and.arrow.up") }.frame(minHeight: 56)
                } else { Text("No timing change has been applied.").font(.subheadline.weight(.semibold)) }
            }.card(Theme.sage)
            DisclosureGroup("Reference coverage & limits") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(review.warnings, id: \.self) { Text($0).font(.subheadline) }
                    ForEach(review.sources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            if let url = URL(string: source.url) { Link(source.title, destination: url) }
                            Text(source.note).font(.footnote).foregroundStyle(.secondary)
                            if source.truncated { Text("Only an excerpt was reviewed.").font(.footnote).foregroundStyle(Theme.amber) }
                        }
                    }
                }.padding(.top, 12)
            }
            DisclaimerView()
        }
    }
    private var shareText: String {
        "PillCheck — draft for pharmacist review\n\(review.candidateName): \(review.timing.proposedTimes.joined(separator: ", "))\n\(review.timing.explanation)\nDose amounts and other medicine times unchanged. Not applied to the schedule.\n\(review.sources.map { $0.title + ": " + $0.url }.joined(separator: "\n"))\n\(PillCheckCopy.disclaimer)"
    }
}

struct MedicationAIReviewView: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.dismiss) private var dismiss
    let medication: Medication
    @State private var review: MedicationAIReview?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("\(medication.name), with your other medicines.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Check possible interactions, shared active ingredients under different brands, and label-supported spacing. Includes active and recently stopped records.")
                    Text("Medicine names go to U.S. reference services. The reviewed medicine details and reference excerpts go to Meta. Your name and dose history are not sent.").font(.footnote).foregroundStyle(.secondary)
                    Button {
                        busy = true; error = nil; review = nil
                        Task {
                            do { review = try await store.meta.review(candidate: medication, medications: store.otherMedicines(for: medication)) }
                            catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: {
                        if busy { HStack { ProgressView().tint(.white); Text("Checking references & AI…") } }
                        else { Label(review == nil ? "Check with AI" : "Run a fresh review", systemImage: "sparkles") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    if let error { WarningBox(text: error + " This is an incomplete check, not a safety result.") }
                    if let review { MedicationReviewContent(review: review) }
                    else if !busy { DisclaimerView() }
                }.padding(20)
            }.background(Theme.cream).navigationTitle("AI medication review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
