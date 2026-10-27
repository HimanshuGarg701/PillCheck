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
    private let samples = [("metformin", "Metformin", "Read a label"), ("glucophage", "Glucophage", "Find a duplicate ingredient"), ("cimetidine", "Cimetidine", "See a reference interaction")]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Start with a label.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Use a synthetic label. Review every field before it joins your schedule.").foregroundStyle(.secondary)
                    Text("Try a sample label").font(.title2.bold())
                    ForEach(samples, id: \.0) { sample in
                        Button {
                            guard let url = Bundle.main.url(forResource: sample.0, withExtension: "png"), let data = try? Data(contentsOf: url) else { error = "This sample image could not be opened."; return }
                            imageData = data
                            Task { await readImage(data) }
                        } label: {
                            HStack(spacing: 16) {
                                Image(uiImage: UIImage(named: sample.0 + ".png") ?? UIImage()).resizable().scaledToFit().frame(width: 88, height: 72).background(.white)
                                VStack(alignment: .leading, spacing: 5) { Text(sample.1).font(.headline); Text(sample.2).font(.subheadline).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "chevron.right")
                            }.card()
                        }.buttonStyle(.plain).disabled(busy).accessibilityLabel("Scan sample \(sample.1)")
                    }
                    if busy { HStack { ProgressView(); Text("Muse Spark 1.3 is reading the label…") }.font(.subheadline).card(Theme.sage) }
                    if let error { WarningBox(text: error + " No medicine has been added. Your selected image and text are retained.") }
                    if let imageData, let image = UIImage(data: imageData) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose a label photo", systemImage: "photo") }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy)
                    Button { files = true } label: { Label("Import an image file", systemImage: "doc") }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { Task { await openCamera() } } label: { Label("Photograph a label", systemImage: "camera") }.buttonStyle(PrimaryButtonStyle(secondary: true))
                    }
                    if let cameraPermissionMessage { WarningBox(text: cameraPermissionMessage) }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or paste label text").font(.headline)
                        TextEditor(text: $labelText).frame(minHeight: 120).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Label text")
                        Button("Read text with Meta") { Task { await readText() } }.buttonStyle(PrimaryButtonStyle(secondary: true)).disabled(busy || labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.card()
                    Button("Enter medicine manually") { draft = MedicineDraft(startDate: store.now) }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    Text("Only the selected label is sent to Meta for extraction. The API key stays on the server.").font(.footnote).foregroundStyle(.secondary)
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
                    field("Medicine name", text: $draft.name).accessibilityIdentifier("medicine-name")
                    if !draft.name.isEmpty {
                        let known = ["Metformin", "Glucophage", "Cimetidine", "Amlodipine", "Atorvastatin", "Warfarin", "Insulin"].filter { $0.localizedCaseInsensitiveContains(draft.name) }
                        ForEach(known, id: \.self) { name in
                            Button("Use \(name)") { draft.name = name; draft.ingredient = name == "Glucophage" ? "metformin" : name.lowercased() }
                        }
                    }
                    field("Active ingredient", text: $draft.ingredient)
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
                    Toggle("I checked every field against the synthetic prescription", isOn: $reviewed)
                    if let error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
                    Text("Medicine names are checked with U.S. reference services. Medicine details and reference excerpts go to Meta; your name and dose history are not sent.").font(.footnote).foregroundStyle(.secondary)
                    Button { Task { await check() } } label: {
                        if checkingAI { HStack { ProgressView().tint(.white); Text("Checking references & AI…") } }
                        else { Label("Check with AI & references", systemImage: "sparkles") }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!reviewed || checkingAI)
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
