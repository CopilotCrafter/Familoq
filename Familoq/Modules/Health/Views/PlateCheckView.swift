import SwiftUI
import SwiftData
import PhotosUI
import Vision
import UIKit
import FamiloqCore
import FamiloqHealth

/// Health → Plate check: photo of a plate → what is on it (suggested on the
/// iPhone, corrected by you) → plate balance score and tips for the family's
/// health conditions.
struct PlateCheckView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var logs: [PlateLog]
    @Query private var people: [HealthPerson]
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var draft: PlateDraft?
    @State private var working = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _logs = Query(filter: #Predicate<PlateLog> { $0.familyID == fid }, sort: \PlateLog.date, order: .reverse)
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
    }

    var body: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let week = logs.filter { $0.date >= weekAgo }
        List {
            Section {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take a photo of the plate", systemImage: "camera")
                    }
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a photo", systemImage: "photo")
                }
                Button {
                    draft = PlateDraft(image: nil, parts: [:])
                } label: {
                    Label("Without a photo", systemImage: "square.grid.2x2")
                }
                if working { ProgressView() }
            } footer: {
                Text("The photo is looked at on this iPhone only. It suggests what is on the plate - you correct the amounts. Grams or calories cannot be measured reliably from a photo, so Familoq only rates the balance.")
            }

            if !week.isEmpty {
                Section("Last 7 days") {
                    let average = week.map(\.score).reduce(0, +) / week.count
                    LabeledContent("Average plate") {
                        Text("\(average)").font(.headline).foregroundStyle(Self.color(average))
                    }
                }
            }

            Section {
                ForEach(logs.prefix(30)) { log in
                    HStack {
                        if let data = log.thumbnail, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "fork.knife.circle").font(.largeTitle).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: log.date.formatted(date: .abbreviated, time: .shortened))
                            Text(verbatim: log.parts.sorted { $0.value > $1.value }.prefix(3)
                                .map { String(localized: String.LocalizationValue($0.key.title)) }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(log.score)").font(.headline).foregroundStyle(Self.color(log.score))
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            context.delete(log)
                            try? context.save()
                        }
                    }
                }
            } header: {
                if !logs.isEmpty { Text("Saved plates") }
            }
        }
        .navigationTitle("Plate check")
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await analyse(image) } }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $draft) { draft in
            PlateEditSheet(family: family, draft: draft, people: people)
        }
    }

    static func color(_ score: Int) -> Color {
        score >= 70 ? .green : (score >= 45 ? .orange : .red)
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        await analyse(image)
        photo = nil
    }

    private func analyse(_ original: UIImage) async {
        working = true
        defer { working = false }
        let image = ReceiptOCRService.downscaled(original, maxDimension: 1200)
        let labels = await Self.classify(image)
        var parts: [PlatePart: Double] = [:]
        for (label, confidence) in labels {
            guard let part = PlatePart.guess(label: label) else { continue }
            parts[part, default: 0] += confidence
        }
        // Turn confidences into rough portions (0-5).
        let maxValue = parts.values.max() ?? 1
        var portions: [PlatePart: Double] = [:]
        for (part, value) in parts {
            portions[part] = max(1, (value / maxValue * 4).rounded())
        }
        draft = PlateDraft(image: image, parts: portions)
    }

    /// Apple's on-device image classifier (food labels like "salad", "rice", "pizza").
    static func classify(_ image: UIImage) async -> [(String, Double)] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil else { return [(String, Double)]() }
            return (request.results ?? [])
                .filter { $0.confidence > 0.08 }
                .prefix(25)
                .map { ($0.identifier, Double($0.confidence)) }
        }.value
    }
}

struct PlateDraft: Identifiable {
    let id = UUID()
    let image: UIImage?
    var parts: [PlatePart: Double]
}

/// Correct the parts, see the score, save.
private struct PlateEditSheet: View {
    let family: Family
    let draft: PlateDraft
    let people: [HealthPerson]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var parts: [PlatePart: Double]
    @State private var personID: UUID?
    @State private var isPrivate = false

    init(family: Family, draft: PlateDraft, people: [HealthPerson]) {
        self.family = family
        self.draft = draft
        self.people = people
        _parts = State(initialValue: draft.parts)
        _personID = State(initialValue: people.first?.id)
    }

    private var conditions: Set<HealthCondition> {
        if let personID, let person = people.first(where: { $0.id == personID }) { return person.conditions }
        return people.reduce(into: Set<HealthCondition>()) { $0.formUnion($1.conditions) }
    }

    var body: some View {
        let result = PlateScore.evaluate(parts, conditions: conditions)
        NavigationStack {
            Form {
                if let image = draft.image {
                    Section {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                    }
                }
                Section {
                    HStack {
                        Text("\(result.score)")
                            .font(.system(size: 44, weight: .bold)).monospacedDigit()
                            .foregroundStyle(PlateCheckView.color(result.score))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.notes, id: \.self) { note in
                                Text(LocalizedStringKey(Self.text(note))).font(.caption)
                            }
                        }
                    }
                    ForEach(Array(result.concerns.enumerated()), id: \.offset) { _, concern in
                        Label {
                            Text("\(String(localized: String.LocalizationValue(concern.1.title))): watch this for \(String(localized: String.LocalizationValue(concern.0.title)).lowercased()).")
                        } icon: {
                            Image(systemName: "heart.text.square").foregroundStyle(.pink)
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Plate balance")
                } footer: {
                    Text("Compared with the healthy plate: half vegetables, a quarter protein, a quarter (wholegrain) carbohydrates.")
                }
                Section {
                    ForEach(PlatePart.allCases) { part in
                        Stepper(value: Binding(get: { parts[part] ?? 0 }, set: { parts[part] = $0 }), in: 0...5) {
                            HStack {
                                Image(systemName: part.icon).foregroundStyle(part.isLessHealthy ? Color.orange : Color.green).frame(width: 22)
                                Text(LocalizedStringKey(part.title))
                                Spacer()
                                Text(verbatim: String(repeating: "●", count: Int(parts[part] ?? 0)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("On the plate (0-5 portions)")
                }
                Section {
                    Picker("Whose plate", selection: $personID) {
                        Text("Family").tag(UUID?.none)
                        ForEach(people) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    Toggle(isOn: $isPrivate) { Label("Only on this iPhone", systemImage: "lock") }
                }
            }
            .navigationTitle("Plate check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(score: result.score) }.disabled(parts.values.reduce(0, +) == 0)
                }
            }
        }
    }

    static func text(_ note: PlateScore.Note) -> String {
        switch note {
        case .moreVegetables: return "Add vegetables or salad - ideally half the plate."
        case .addProtein: return "Add some protein: pulses, fish, eggs, chicken or tofu."
        case .bigCarbPortion: return "Big portion of rice, pasta, bread or potatoes."
        case .chooseWholegrain: return "Wholegrain instead of white keeps you full longer."
        case .lessFried: return "Fried food - better less often."
        case .lessProcessed: return "Sausage or ham - salty and processed."
        case .lessCreamy: return "Creamy or cheesy sauce - a lighter one is better for the heart."
        case .sweetExtras: return "Sweet extras - fine now and then."
        case .great: return "Great plate - well balanced!"
        }
    }

    private func save(score: Int) {
        let log = PlateLog(familyID: family.id, date: Date())
        log.parts = parts
        log.score = score
        log.personID = personID
        log.isPrivate = isPrivate || (people.first { $0.id == personID }?.isPrivate ?? false)
        if let image = draft.image {
            log.thumbnail = ReceiptOCRService.downscaled(image, maxDimension: 240).jpegData(compressionQuality: 0.6)
        }
        context.insert(log)
        try? context.save()
        dismiss()
    }
}

/// Camera (UIImagePickerController) for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
