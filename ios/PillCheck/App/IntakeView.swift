import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MedicineDraft: Identifiable, Equatable {
    var id = UUID()
    var original: Medication?
    var name = ""
    var ingredient = ""
    var strength = ""
    var quantity = ""
    var unit = ""
    var frequency = ""
    var times = ""
    var instructions = ""
    var riskClass = ""
    var highRisk = false
    var startDate = Date()
    var source = "manual-reviewed"
    var explanation = ""
    var uncertain: [String] = []
    init(startDate: Date = Date()) { self.startDate = startDate }
    init(medicine: Medication, now: Date) {
        original = medicine
        name = medicine.name; ingredient = medicine.ingredient
        strength = String(medicine.strengthMg); quantity = String(medicine.doseQuantity)
        unit = medicine.doseUnit; frequency = medicine.frequency
        times = medicine.times.joined(separator: ", "); instructions = medicine.instructions
        riskClass = medicine.riskClass; highRisk = MedicationEngine.isHighRisk(medicine)
        startDate = now; source = "manual-reviewed"
    }
    init(scan: ScanResult, now: Date) {
        name = scan.name ?? ""; ingredient = scan.ingredient ?? ""
        strength = scan.strengthMg.map(String.init(describing:)) ?? ""
        quantity = scan.doseQuantity.map(String.init(describing:)) ?? ""
        unit = scan.doseUnit ?? ""; frequency = scan.frequency ?? ""
        times = scan.times.joined(separator: ", "); instructions = scan.instructions ?? ""
        startDate = now; source = "meta-reviewed"
        explanation = scan.explanation; uncertain = scan.uncertainFields
    }
    func medication() throws -> Medication {
        guard let mg = Double(strength.replacingOccurrences(of: ",", with: ".")), let count = Double(quantity.replacingOccurrences(of: ",", with: ".")) else { throw PillCheckError("Confirm the strength and quantity as numbers.") }
        return try MedicationEngine.validate(Medication(id: original?.id ?? id.uuidString, name: name, ingredient: ingredient, strengthMg: mg, doseQuantity: count, doseUnit: unit, frequency: frequency, times: times.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, instructions: instructions, riskClass: riskClass, startDate: startDate, highRisk: highRisk, source: source))
    }
}

struct SampleMedicineLabel: Identifiable {
    let id: String
    let name: String
    let ingredient: String
    let strength: String
    let times: String
    let instructions: String
    static let all = [
        SampleMedicineLabel(id: "metformin", name: "Metformin", ingredient: "Metformin hydrochloride", strength: "500 mg", times: "08:00 and 18:00", instructions: "Take with meals."),
        SampleMedicineLabel(id: "glucophage", name: "Glucophage", ingredient: "Metformin hydrochloride", strength: "500 mg", times: "08:00 and 18:00", instructions: "Take with meals."),
        SampleMedicineLabel(id: "cimetidine", name: "Cimetidine", ingredient: "Cimetidine", strength: "200 mg", times: "12:00", instructions: "")
    ]
    @MainActor var image: UIImage? {
        let renderer = ImageRenderer(content: SampleLabelCard(label: self))
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct SampleLabelCard: View {
    let label: SampleMedicineLabel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PillCheck").font(.system(size: 24, weight: .bold))
                Spacer()
                Text("SAMPLE LABEL").font(.system(size: 12, weight: .semibold)).tracking(1)
            }.foregroundStyle(.white).padding(24).background(Theme.green)
            VStack(alignment: .leading, spacing: 16) {
                Text("Alex Morgan").font(.system(size: 15)).foregroundStyle(.secondary)
                Text(label.name).font(.system(size: 36, weight: .bold))
                Text("\(label.ingredient) · \(label.strength)").font(.system(size: 19))
                Divider()
                Text("Take 1 tablet at \(label.times).").font(.system(size: 23, weight: .semibold))
                if !label.instructions.isEmpty { Text(label.instructions).font(.system(size: 18)) }
                Spacer(minLength: 0)
                Text("Sample medicine details for exploring label scanning.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width: 600, height: 400).foregroundStyle(Theme.ink).background(.white)
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .medium)
    }
}

struct IntakeView: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var files = false
    @State private var camera = false
    @State private var cameraPermissionMessage: String?
    @State private var labelText = ""
    @State private var imageData: Data?
    @State private var busy = false
    @State private var error: String?
    @State private var draft: MedicineDraft?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Start with a label.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Scan a label or enter your medicine details. Review every field before saving.").foregroundStyle(.secondary)
                    if busy { HStack { ProgressView(); Text("Muse Spark 1.3 is reading the label…") }.font(.subheadline).card(Theme.sage) }
                    if let error { WarningBox(text: error + " No medicine has been added. Your selected image and text are retained.") }
                    if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose a label photo", systemImage: "photo") }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy)
                    Button { files = true } label: { Label("Import an image file", systemImage: "doc") }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { Task { await openCamera() } } label: { Label("Photograph a label", systemImage: "camera") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                    }
                    if let cameraPermissionMessage { WarningBox(text: cameraPermissionMessage) }
                    Button("Enter medicine manually") { draft = MedicineDraft(startDate: store.now) }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or paste label text").font(.headline)
                        TextEditor(text: $labelText).frame(minHeight: 120).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Label text")
                        Button("Read label text") { Task { await readText() } }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy || labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.card()
                    DisclosureGroup("Try a sample label") {
                        VStack(spacing: 14) {
                            ForEach(SampleMedicineLabel.all) { sample in
                                Button {
                                    guard let data = sample.image?.pngData() else { error = "This sample label could not be opened."; return }
                                    imageData = data
                                    Task { await readImage(data) }
                                } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: "doc.text.viewfinder").font(.title2).foregroundStyle(Theme.green)
                                        VStack(alignment: .leading, spacing: 5) { Text(sample.name).font(.headline); Text(sample.ingredient).font(.subheadline).foregroundStyle(.secondary) }
                                        Spacer(); Image(systemName: "chevron.right")
                                    }.padding(.vertical, 10)
                                }.buttonStyle(.plain).disabled(busy).accessibilityLabel("Scan sample \(sample.name)")
                            }
                        }.padding(.top, 10)
                    }.card()
                    Text("The selected label is sent securely to Meta to read the medicine details. You review the results before saving.").font(.footnote).foregroundStyle(.secondary)
                    DisclaimerView()
                }.padding(20)
            }.background(Theme.cream).navigationTitle("Add medicine").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .sheet(item: $draft) { draft in MedicineEditor(draft: draft, onSaved: { dismiss() }) }
                .sheet(isPresented: $camera) { CameraPicker { data in if let data { imageData = data; Task { await readImage(data) } } } }
                .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 20_000_000 else { throw PillCheckError("Choose an image under 20 MB.") }
                        let data = try Data(contentsOf: url); imageData = data
                        Task { await readImage(data) }
                    } catch { self.error = error.localizedDescription }
                }
                .onChange(of: photo) { _, item in
                    Task { do { if let data = try await item?.loadTransferable(type: Data.self) { imageData = data; await readImage(data) } } catch { self.error = error.localizedDescription } }
                }
        }
    }
    private func readImage(_ data: Data) async {
        busy = true; error = nil
        defer { busy = false }
        do { draft = MedicineDraft(scan: try await store.meta.scan(image: data), now: store.now); store.modelStatus = "Muse Spark 1.3 · live" }
        catch { self.error = error.localizedDescription }
    }
    private func readText() async {
        busy = true; error = nil
        defer { busy = false }
        do { draft = MedicineDraft(scan: try await store.meta.scan(text: labelText), now: store.now); store.modelStatus = "Muse Spark 1.3 · live" }
        catch { self.error = error.localizedDescription }
    }
    private func openCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        if granted { camera = true }
        else { cameraPermissionMessage = "Camera access is off. You can still choose a photo, import a file, or scan a sample label." }
    }
}

import AVFoundation
struct CameraPicker: UIViewControllerRepresentable {
    var completion: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.dismiss(); parent.completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct MedicineEditor: View {
    @EnvironmentObject private var store: PillStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: MedicineDraft
    var onSaved: () -> Void = {}
    @State private var reviewed = false
    @State private var acknowledged = false
    @State private var candidate: Medication?
    @State private var flags: [RiskFlag] = []
    @State private var aiReview: MedicationAIReview?
    @State private var checkingAI = false
    @State private var reviewRequest = UUID()
    @State private var reviewedList: [Medication] = []
    @State private var error: String?
    @State private var ingredientForName: String
    @State private var identification: IngredientIdentification?
    @State private var identifying = false
    @State private var ingredientIssue: String?
    @State private var manualIngredient = false
    @State private var ingredientRetry = 0
    @State private var ingredientRequest = UUID()
    init(draft: MedicineDraft, onSaved: @escaping () -> Void = {}) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
        _ingredientForName = State(initialValue: draft.ingredient.isEmpty ? "" : IngredientIdentification.nameKey(draft.name))
    }
    private var enteredName: String { IngredientIdentification.nameKey(draft.name) }
    private var nameBinding: Binding<String> {
        Binding(get: { draft.name }, set: { name in
            let changed = IngredientIdentification.nameKey(name) != enteredName
            draft.name = name
            if changed {
                ingredientRequest = UUID(); identifying = false
                draft.ingredient = ""; ingredientForName = ""; identification = nil
                ingredientIssue = nil; manualIngredient = false
            }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                if draft.source == "meta-reviewed" {
                    Section("Read live by Muse Spark 1.3") {
                        Text(draft.explanation)
                        if !draft.uncertain.isEmpty { WarningBox(text: "Confirm these fields: " + draft.uncertain.joined(separator: ", ")) }
                    }
                }
                Section("Copy the recorded prescription") {
                    field("Medicine name", text: nameBinding).accessibilityIdentifier("medicine-name")
                    Text("Enter the brand or generic name from your label. The name is sent to Meta and U.S. medicine references to identify the ingredient.").font(.footnote).foregroundStyle(.secondary)
                    ingredientDetails
                    field("Strength (mg)", text: $draft.strength).keyboardType(.decimalPad)
                    field("Quantity per dose", text: $draft.quantity).keyboardType(.decimalPad)
                    field("Dose unit (tablet, capsule…)", text: $draft.unit)
                    field("Frequency (e.g. twice daily)", text: $draft.frequency)
                    field("Times (e.g. 08:00, 18:00)", text: $draft.times).keyboardType(.numbersAndPunctuation)
                    DatePicker("Start date", selection: $draft.startDate, in: PillTime.day(store.now)..., displayedComponents: .date)
                    TextField("Label instructions", text: $draft.instructions, axis: .vertical)
                    field("Medication class, if known", text: $draft.riskClass)
                    Toggle("High-risk / specialist timing", isOn: $draft.highRisk)
                    Text("Recognized high-risk medicines are protected even if this switch is off. This form records a prescription; it does not choose a dose.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("I checked every field against my prescription", isOn: $reviewed)
                    if let error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
                    Text("Medicine names are checked with U.S. reference services. Medicine details and reference excerpts go to Meta; your name and dose history are not sent.").font(.footnote).foregroundStyle(.secondary)
                    Button { Task { await check() } } label: {
                        if checkingAI { HStack { ProgressView().tint(.white); Text("Checking references & AI…") } }
                        else { Label("Check with AI & references", systemImage: "sparkles") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!reviewed || checkingAI || identifying || draft.ingredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let aiReview { Section { MedicationReviewContent(review: aiReview) } }
                if candidate != nil && !checkingAI {
                    Section("Before this joins your schedule") {
                        ForEach(flags) { RiskFlagView(flag: $0) }
                        if aiReview?.completed != true { WarningBox(text: "AI review is incomplete. Saving only records the prescription; it does not confirm that this combination is safe.") }
                        Toggle(aiReview?.completed == true ? "I reviewed the findings. I am recording an existing prescription and will confirm interactions and timing with my pharmacist." : "I understand the AI check is incomplete and am only recording an existing prescription.", isOn: $acknowledged)
                        Button("Save recorded prescription") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(!acknowledged)
                        Text("The AI timing draft is for pharmacist review. It never changes the times entered above.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section { DisclaimerView() }
            }.disabled(checkingAI).scrollContentBackground(.hidden).background(Theme.cream)
                .navigationTitle(draft.original == nil ? "Review medicine" : "Update regimen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: draft) { _, _ in clearCheck() }
                .task(id: "\(enteredName)|\(ingredientRetry)") { await identifyIngredient() }
        }
    }
    @ViewBuilder private var ingredientDetails: some View {
        if manualIngredient {
            field("Active ingredient from your label", text: $draft.ingredient)
            Text("For a combination product, include every active ingredient.").font(.footnote).foregroundStyle(.secondary)
        } else if identifying {
            HStack { ProgressView(); Text("Identifying active ingredient…") }.font(.subheadline)
        } else if !draft.ingredient.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Active ingredient", systemImage: "pills").font(.caption).foregroundStyle(.secondary)
                Text(draft.ingredient).font(.headline)
                Text(identification?.message ?? "Check this ingredient against your prescription label.").font(.footnote).foregroundStyle(.secondary)
                if let source = identification?.sourceURL, let url = URL(string: source) { Link("View medicine reference", destination: url).font(.footnote) }
            }.padding(.vertical, 4)
        } else if let ingredientIssue {
            Text(ingredientIssue).font(.subheadline).foregroundStyle(Theme.amber)
        } else {
            Text("The active ingredient will appear here after you enter the medicine name.").font(.subheadline).foregroundStyle(.secondary)
        }
        if !manualIngredient {
            Button(draft.ingredient.isEmpty ? "Enter ingredient manually" : "Correct ingredient") {
                manualIngredient = true; ingredientRequest = UUID(); identifying = false
                identification = nil; ingredientRetry += 1; clearCheck()
            }.font(.subheadline)
        }
        if manualIngredient || ingredientIssue != nil {
            Button("Identify from medicine name") {
                manualIngredient = false; draft.ingredient = ""; ingredientForName = ""
                identification = nil; ingredientIssue = nil; ingredientRetry += 1
            }.font(.subheadline).disabled(enteredName.count < 2)
        }
    }
    private func identifyIngredient() async {
        guard !manualIngredient, enteredName.count >= 2,
              ingredientForName != enteredName || draft.ingredient.isEmpty else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedName = enteredName
        let request = UUID(); ingredientRequest = request
        identifying = true; ingredientIssue = nil
        defer { if ingredientRequest == request { identifying = false } }
        do {
            try await Task.sleep(for: .milliseconds(900))
            try Task.checkCancellation()
            let result = try await store.meta.identify(name: name)
            guard !Task.isCancelled, ingredientRequest == request, enteredName == requestedName, !manualIngredient,
                  IngredientIdentification.nameKey(result.name) == requestedName else { return }
            identification = result
            if result.matched {
                draft.ingredient = result.ingredients.joined(separator: " + ")
                ingredientForName = requestedName
            } else { ingredientIssue = result.message }
        } catch {
            guard !Task.isCancelled, ingredientRequest == request, enteredName == requestedName, !manualIngredient else { return }
            ingredientIssue = "Ingredient lookup could not complete. Retry, or enter the ingredient from your label."
        }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel(label)
        }.padding(.vertical, 4)
    }
    private func clearCheck() {
        reviewRequest = UUID(); checkingAI = false; candidate = nil; flags = []; aiReview = nil; acknowledged = false; reviewed = false
    }
    private func check() async {
        guard !identifying else { return }
        error = nil; candidate = nil; aiReview = nil; acknowledged = false
        let request = UUID(); reviewRequest = request
        do {
            let m = try draft.medication()
            if draft.original == nil && store.state.medications.contains(where: { $0.status == .active && MedicationEngine.canonical($0.name) == MedicationEngine.canonical(m.name) && $0.strengthMg == m.strengthMg && $0.doseQuantity == m.doseQuantity && $0.times == m.times }) {
                error = "This exact medicine and schedule are already recorded. No duplicate was added."
                return
            }
            candidate = m; flags = MedicationEngine.risks(for: m, in: store.state, now: store.now)
            reviewedList = store.state.medications
            checkingAI = true
            defer { if reviewRequest == request { checkingAI = false } }
            let result = try await store.meta.review(candidate: m, medications: store.otherMedicines(for: m))
            guard reviewRequest == request else { return }
            aiReview = result
            if result.completed { store.modelStatus = "Muse Spark 1.3 · live" }
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard let candidate, acknowledged, reviewed, !checkingAI else { return }
        guard reviewedList == store.state.medications else {
            clearCheck(); error = "Your medication list changed. Run the review again before saving."; return
        }
        do { try store.save(candidate, replacing: draft.original?.id, acknowledged: acknowledged, review: aiReview); dismiss(); onSaved() }
        catch { self.error = error.localizedDescription }
    }
}
