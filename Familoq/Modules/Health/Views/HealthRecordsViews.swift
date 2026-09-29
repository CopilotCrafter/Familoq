import SwiftUI
import SwiftData
import Charts
import UIKit
import FamiloqCore
import FamiloqHealth

// MARK: - Medications

struct MedicationsView: View {
    let family: Family
    @Query private var people: [HealthPerson]
    @Query private var medications: [Medication]
    @State private var editing: MedicationEditTarget?
    @State private var showInactive = false

    init(family: Family) {
        self.family = family
        let fid = family.id
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _medications = Query(filter: #Predicate<Medication> { $0.familyID == fid }, sort: \Medication.name)
    }

    var body: some View {
        let calendar = FamiloqCalendar.make()
        List {
            ForEach(people) { person in
                let meds = medications.filter { $0.personID == person.id && ($0.isActive || showInactive) }
                Section {
                    ForEach(meds) { med in
                        Button {
                            editing = MedicationEditTarget(medication: med, personID: person.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: med.dose.isEmpty ? med.name : "\(med.name) · \(med.dose)").foregroundStyle(med.isActive ? Color.primary : Color.secondary)
                                HStack(spacing: 8) {
                                    if med.remindDoses && !med.timesRaw.isEmpty {
                                        Label(med.timesRaw.replacingOccurrences(of: ",", with: ", "), systemImage: "bell")
                                    }
                                    if let runOut = med.runOut(calendar: calendar) {
                                        Text("until \(runOut.formatted(date: .abbreviated, time: .omitted))")
                                    }
                                    if med.isPrivate { Image(systemName: "lock.fill") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        editing = MedicationEditTarget(medication: nil, personID: person.id)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                } header: {
                    Text(verbatim: person.name)
                }
            }
            Section {
                Toggle("Show stopped medications", isOn: $showInactive)
            }
        }
        .navigationTitle("Medications")
        .sheet(item: $editing) { target in
            if let person = people.first(where: { $0.id == target.personID }) {
                MedicationForm(family: family, person: person, target: target)
            }
        }
    }
}

// MARK: - Measurements

struct MeasurementsView: View {
    let family: Family
    @Query private var people: [HealthPerson]
    @Query private var measurements: [HealthMeasurement]
    @Query private var medications: [Medication]
    @State private var adding: MeasurementEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _measurements = Query(filter: #Predicate<HealthMeasurement> { $0.familyID == fid }, sort: \HealthMeasurement.date, order: .reverse)
        _medications = Query(filter: #Predicate<Medication> { $0.familyID == fid && $0.isActive == true })
    }

    var body: some View {
        List {
            ForEach(people) { person in
                let own = measurements.filter { $0.personID == person.id }
                let types = Array(Set(own.map(\.type))).sorted { $0.rawValue < $1.rawValue }
                Section {
                    ForEach(types) { type in
                        if let latest = own.first(where: { $0.type == type }) {
                            NavigationLink {
                                LazyView(MeasurementChartView(family: family, personID: person.id, type: type))
                            } label: {
                                LabeledContent {
                                    VStack(alignment: .trailing) {
                                        Text(verbatim: latest.text).monospacedDigit()
                                        Text(verbatim: latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                } label: {
                                    Label(LocalizedStringKey(type.title), systemImage: type.icon)
                                }
                            }
                        }
                    }
                    Menu {
                        let suggested = MeasurementType.suggested(for: person.conditions)
                        ForEach(suggested + MeasurementType.allCases.filter { !suggested.contains($0) }) { type in
                            Button(LocalizedStringKey(type.title)) { adding = MeasurementEditTarget(personID: person.id, type: type) }
                        }
                    } label: {
                        Label("Add measurement", systemImage: "plus")
                    }
                    if !own.isEmpty, let url = HealthReport.pdf(person: person, measurements: own,
                                                                 medications: medications.filter { $0.personID == person.id }) {
                        ShareLink(item: url) {
                            Label("Report for the doctor (PDF)", systemImage: "doc.richtext")
                        }
                    }
                } header: {
                    Text(verbatim: person.name)
                }
            }
        }
        .navigationTitle("Measurements")
        .sheet(item: $adding) { target in
            if let person = people.first(where: { $0.id == target.personID }) {
                MeasurementForm(family: family, person: person, target: target)
            }
        }
    }
}

struct MeasurementChartView: View {
    let family: Family
    let personID: UUID
    let type: MeasurementType
    @Environment(\.modelContext) private var context
    @Query private var values: [HealthMeasurement]
    @Query private var persons: [HealthPerson]
    @State private var adding: MeasurementEditTarget?

    init(family: Family, personID: UUID, type: MeasurementType) {
        self.family = family
        self.personID = personID
        self.type = type
        let pid = personID
        let raw = type.rawValue
        _values = Query(filter: #Predicate<HealthMeasurement> { $0.personID == pid && $0.typeRaw == raw }, sort: \HealthMeasurement.date)
        _persons = Query(filter: #Predicate<HealthPerson> { $0.id == pid })
    }

    var body: some View {
        List {
            if values.count >= 2 {
                Section {
                    Chart {
                        ForEach(values) { m in
                            LineMark(x: .value("Date", m.date), y: .value("Value", m.value), series: .value("Series", "1"))
                                .foregroundStyle(Color.pink)
                            PointMark(x: .value("Date", m.date), y: .value("Value", m.value)).foregroundStyle(Color.pink)
                            if type.hasSecondValue {
                                LineMark(x: .value("Date", m.date), y: .value("Value", m.value2), series: .value("Series", "2"))
                                    .foregroundStyle(Color.blue)
                                PointMark(x: .value("Date", m.date), y: .value("Value", m.value2)).foregroundStyle(Color.blue)
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
            Section {
                ForEach(values.reversed()) { m in
                    LabeledContent {
                        Text(verbatim: m.text).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: m.date.formatted(date: .abbreviated, time: .shortened))
                            if !m.note.isEmpty { Text(verbatim: m.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            context.delete(m)
                            try? context.save()
                        }
                    }
                }
            }
        }
        .navigationTitle(LocalizedStringKey(type.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = MeasurementEditTarget(personID: personID, type: type) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $adding) { target in
            if let person = persons.first {
                MeasurementForm(family: family, person: person, target: target)
            }
        }
    }
}

/// Simple PDF for the doctor: medications and measurements of the last 6 months.
enum HealthReport {
    static func pdf(person: HealthPerson, measurements: [HealthMeasurement], medications: [Medication]) -> URL? {
        let since = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        var lines: [(String, UIFont)] = []
        let title = UIFont.boldSystemFont(ofSize: 18)
        let heading = UIFont.boldSystemFont(ofSize: 13)
        let body = UIFont.systemFont(ofSize: 11)
        lines.append((person.name, title))
        var info: [String] = []
        if let birth = person.birthDate { info.append(String(localized: "Born \(birth.formatted(date: .long, time: .omitted))")) }
        info.append(String(localized: "Created \(Date().formatted(date: .long, time: .omitted)) with Familoq"))
        lines.append((info.joined(separator: " · "), body))
        if !person.conditions.isEmpty {
            lines.append(("", body))
            lines.append((String(localized: "Conditions"), heading))
            lines.append((person.conditions.map { String(localized: String.LocalizationValue($0.title)) }.sorted().joined(separator: ", "), body))
        }
        if !medications.isEmpty {
            lines.append(("", body))
            lines.append((String(localized: "Medications"), heading))
            for med in medications {
                lines.append(("• " + [med.name, med.dose, med.timesRaw.replacingOccurrences(of: ",", with: ", ")].filter { !$0.isEmpty }.joined(separator: " · "), body))
            }
        }
        let recent = measurements.filter { $0.date >= since }
        for type in MeasurementType.allCases {
            let values = recent.filter { $0.type == type }.sorted { $0.date < $1.date }
            guard !values.isEmpty else { continue }
            lines.append(("", body))
            let average = values.map(\.value).reduce(0, +) / Double(values.count)
            var header = String(localized: String.LocalizationValue(type.title)) + " (\(type.unit))"
            if type.hasSecondValue {
                let average2 = values.map(\.value2).reduce(0, +) / Double(values.count)
                header += " – Ø \(Int(average.rounded()))/\(Int(average2.rounded()))"
            } else {
                header += " – Ø " + average.formatted(.number.precision(.fractionLength(type.decimals)))
            }
            lines.append((header, heading))
            for m in values {
                var line = m.date.formatted(date: .numeric, time: .shortened) + "   " + m.text
                if !m.note.isEmpty { line += "   (" + m.note + ")" }
                lines.append((line, body))
            }
        }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 40
            for (text, font) in lines {
                let height = font.lineHeight + 4
                if y + height > page.height - 40 {
                    context.beginPage()
                    y = 40
                }
                (text as NSString).draw(in: CGRect(x: 40, y: y, width: page.width - 80, height: height),
                                        withAttributes: [.font: font])
                y += height
            }
        }
        let safeName = person.name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Familoq-\(safeName.isEmpty ? "Health" : safeName).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Health costs

struct HealthCostsView: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @Query private var categories: [ExpenseCategory]
    @Query private var expenses: [Expense]
    @Query private var people: [HealthPerson]
    @Query private var claims: [InsuranceClaim]
    @State private var year = Calendar.current.component(.year, from: Date())

    init(family: Family) {
        self.family = family
        let fid = family.id
        _categories = Query(filter: #Predicate<ExpenseCategory> { $0.familyID == fid })
        _expenses = Query(filter: #Predicate<Expense> { $0.familyID == fid }, sort: \Expense.date, order: .reverse)
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _claims = Query(filter: #Predicate<InsuranceClaim> { $0.familyID == fid })
    }

    private var healthCategoryIDs: Set<UUID> { Set(categories.filter { $0.systemKey == "health" }.map(\.id)) }

    private func personID(for expense: Expense) -> UUID? {
        if let id = expense.healthPersonID { return id }
        return people.first { $0.memberID != nil && $0.memberID == expense.memberID }?.id
    }

    var body: some View {
        let calendar = Calendar.current
        let healthIDs = healthCategoryIDs
        let inYear = expenses.filter { expense in
            guard calendar.component(.year, from: expense.date) == year else { return false }
            if expense.isTaxRelevant { return true }
            guard let categoryID = expense.categoryID else { return false }
            return healthIDs.contains(categoryID)
        }
        let currentYear = calendar.component(.year, from: Date())
        let base = family.baseCurrencyCode
        let total = inYear.compactMap(\.baseAmount).reduce(0, +)
        let taxTotal = inYear.filter(\.isTaxRelevant).compactMap(\.baseAmount).reduce(0, +)
        let refunded = claims.filter { $0.refundedOn.map { calendar.component(.year, from: $0) == year } ?? false }.map(\.refunded).reduce(0, +)
        List {
            Section {
                Picker("Year", selection: $year) {
                    ForEach((currentYear - 4)...currentYear, id: \.self) { Text(verbatim: String($0)).tag($0) }
                }
                LabeledContent("Health costs") { Text(total.currency(base)).monospacedDigit() }
                LabeledContent("Refunded by insurance") { Text(refunded.currency(base)).monospacedDigit() }
                LabeledContent("Tax-relevant") { Text(taxTotal.currency(base)).monospacedDigit().fontWeight(.semibold) }
                if taxTotal > 0 {
                    ShareLink(item: taxSummary(inYear.filter(\.isTaxRelevant), base: base)) {
                        Label("Share list for the tax return", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text("Expenses in the Health category (plus any marked tax-relevant). Mark doctor's bills, medicines on prescription, glasses, dentures or therapies you pay yourself as tax-relevant - they may count as außergewöhnliche Belastungen. Not tax advice.")
            }

            ForEach(peopleSections(inYear), id: \.id) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        HStack {
                            Button {
                                expense.isTaxRelevant.toggle()
                                expense.updatedAt = Date()
                                try? context.save()
                            } label: {
                                Image(systemName: expense.isTaxRelevant ? "checkmark.seal.fill" : "seal")
                                    .foregroundStyle(expense.isTaxRelevant ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: expense.merchant)
                                Text(verbatim: expense.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                ForEach(people) { person in
                                    Button(person.name) {
                                        expense.healthPersonID = person.id
                                        expense.updatedAt = Date()
                                        try? context.save()
                                    }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle")
                            }
                            Text((expense.baseAmount ?? expense.amount).currency(base)).monospacedDigit()
                        }
                    }
                } header: {
                    Text(verbatim: section.name + " · " + section.total.currency(base))
                }
            }
        }
        .navigationTitle("Health costs & tax")
    }

    struct PersonSection {
        let id: String
        let name: String
        let expenses: [Expense]
        let total: Decimal
    }

    private func peopleSections(_ list: [Expense]) -> [PersonSection] {
        let grouped = Dictionary(grouping: list) { personID(for: $0) }
        var result: [PersonSection] = []
        for person in people {
            if let items = grouped[person.id], !items.isEmpty {
                result.append(PersonSection(id: person.id.uuidString, name: person.name, expenses: items,
                                            total: items.compactMap(\.baseAmount).reduce(0, +)))
            }
        }
        if let items = grouped[UUID?.none], !items.isEmpty {
            result.append(PersonSection(id: "none", name: String(localized: "Not assigned"), expenses: items,
                                        total: items.compactMap(\.baseAmount).reduce(0, +)))
        }
        return result
    }

    private func taxSummary(_ list: [Expense], base: String) -> String {
        var lines = [String(localized: "Health costs \(String(year)) (außergewöhnliche Belastungen)"), ""]
        for expense in list.sorted(by: { $0.date < $1.date }) {
            let who = personID(for: expense).flatMap { id in people.first { $0.id == id }?.name } ?? ""
            lines.append("\(expense.date.formatted(date: .numeric, time: .omitted))  \(expense.merchant)  \(who)  \((expense.baseAmount ?? expense.amount).currency(base))")
        }
        lines.append("")
        lines.append(String(localized: "Total: \(list.compactMap(\.baseAmount).reduce(0, +).currency(base))"))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Insurance refunds

struct ClaimsView: View {
    let family: Family
    @Query private var claims: [InsuranceClaim]
    @Query private var people: [HealthPerson]
    @State private var editing: ClaimEditTarget?

    init(family: Family) {
        self.family = family
        let fid = family.id
        _claims = Query(filter: #Predicate<InsuranceClaim> { $0.familyID == fid }, sort: \InsuranceClaim.createdAt, order: .reverse)
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
    }

    var body: some View {
        let base = family.baseCurrencyCode
        let open = claims.map(\.open).reduce(0, +)
        List {
            Section {
                LabeledContent("Still expected back") { Text(open.currency(base)).monospacedDigit().fontWeight(.semibold) }
                Button {
                    editing = ClaimEditTarget(claim: nil)
                } label: {
                    Label("Add a bill to claim", systemImage: "plus")
                }
            } footer: {
                Text("For private or supplementary insurance: note each bill, when it was sent in and what came back.")
            }
            ForEach([ClaimStatus.toSubmit, .submitted, .refunded], id: \.self) { status in
                let items = claims.filter { $0.status == status }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { claim in
                            Button {
                                editing = ClaimEditTarget(claim: claim)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: claim.title).foregroundStyle(.primary)
                                        Text(verbatim: [claim.personID.flatMap { id in people.first { $0.id == id }?.name } ?? "", claim.insurer]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(claim.amount.currency(claim.currencyCode)).monospacedDigit().foregroundStyle(.primary)
                                        if status == .refunded {
                                            Text(claim.refunded.currency(claim.currencyCode)).font(.caption).foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(Self.title(status))
                    }
                }
            }
        }
        .navigationTitle("Insurance refunds")
        .sheet(item: $editing) { target in
            ClaimForm(family: family, target: target, people: people)
        }
    }

    static func title(_ status: ClaimStatus) -> LocalizedStringKey {
        switch status {
        case .toSubmit: return "To send in"
        case .submitted: return "Sent in - waiting"
        case .refunded: return "Refunded"
        }
    }
}

struct ClaimEditTarget: Identifiable {
    let id = UUID()
    let claim: InsuranceClaim?
}

private struct ClaimForm: View {
    let family: Family
    let target: ClaimEditTarget
    let people: [HealthPerson]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var insurer: String
    @State private var personID: UUID?
    @State private var amountText: String
    @State private var submitted: Bool
    @State private var submittedOn: Date
    @State private var isRefunded: Bool
    @State private var refundedText: String
    @State private var refundedOn: Date
    @State private var note: String

    init(family: Family, target: ClaimEditTarget, people: [HealthPerson]) {
        self.family = family
        self.target = target
        self.people = people
        let c = target.claim
        _title = State(initialValue: c?.title ?? "")
        _insurer = State(initialValue: c?.insurer ?? "")
        _personID = State(initialValue: c?.personID ?? people.first?.id)
        _amountText = State(initialValue: c.map { "\($0.amount)" } ?? "")
        _submitted = State(initialValue: c?.submittedOn != nil)
        _submittedOn = State(initialValue: c?.submittedOn ?? Date())
        _isRefunded = State(initialValue: c?.refundedOn != nil)
        _refundedText = State(initialValue: c.map { $0.refunded > 0 ? "\($0.refunded)" : "" } ?? "")
        _refundedOn = State(initialValue: c?.refundedOn ?? Date())
        _note = State(initialValue: c?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bill, e.g. Dentist invoice March", text: $title)
                    Picker("For", selection: $personID) {
                        Text("Nobody").tag(UUID?.none)
                        ForEach(people) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    TextField("Insurance", text: $insurer)
                    TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                }
                Section {
                    Toggle("Sent in", isOn: $submitted.animation())
                    if submitted { DatePicker("On", selection: $submittedOn, displayedComponents: [.date]) }
                    Toggle("Refunded", isOn: $isRefunded.animation())
                    if isRefunded {
                        TextField("Refunded amount", text: $refundedText).keyboardType(.decimalPad)
                        DatePicker("On", selection: $refundedOn, displayedComponents: [.date])
                    }
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if let claim = target.claim {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(claim)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let claim: InsuranceClaim
        if let existing = target.claim {
            claim = existing
        } else {
            claim = InsuranceClaim(familyID: family.id, title: "")
            claim.currencyCode = family.baseCurrencyCode
            context.insert(claim)
        }
        claim.title = title.trimmingCharacters(in: .whitespaces)
        claim.insurer = insurer.trimmingCharacters(in: .whitespaces)
        claim.personID = personID
        claim.amount = DecimalParser.parse(amountText) ?? 0
        claim.submittedOn = submitted ? submittedOn : nil
        claim.refundedOn = isRefunded ? refundedOn : nil
        claim.refunded = isRefunded ? (DecimalParser.parse(refundedText) ?? claim.amount) : 0
        claim.note = note
        claim.isPrivate = people.first { $0.id == personID }?.isPrivate ?? false
        claim.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

// MARK: - Doctors & contacts

struct HealthContactsView: View {
    let family: Family
    @Query private var contacts: [HealthContact]
    @Query private var people: [HealthPerson]
    @State private var editing: ContactEditTarget?
    @Environment(\.openURL) private var openURL

    init(family: Family) {
        self.family = family
        let fid = family.id
        _contacts = Query(filter: #Predicate<HealthContact> { $0.familyID == fid }, sort: \HealthContact.name)
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
    }

    var body: some View {
        List {
            Section {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: contact.name).font(.body.weight(.medium))
                                Text(verbatim: contact.specialty).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editing = ContactEditTarget(contact: contact) } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless)
                        }
                        HStack(spacing: 16) {
                            if let url = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }), !contact.phone.isEmpty {
                                Button { openURL(url) } label: { Label(contact.phone, systemImage: "phone.fill") }.buttonStyle(.borderless)
                            }
                            if !contact.address.isEmpty,
                               let url = URL(string: "maps://?q=" + (contact.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                                Button { openURL(url) } label: { Image(systemName: "map.fill") }.buttonStyle(.borderless)
                            }
                        }
                        .font(.caption)
                    }
                }
                Button {
                    editing = ContactEditTarget(contact: nil)
                } label: {
                    Label("Add doctor or pharmacy", systemImage: "plus")
                }
            }

            Section {
                Button { openURL(URL(string: "tel:112")!) } label: { Label("112 – Emergency (ambulance, fire)", systemImage: "staroflife.fill") }
                Button { openURL(URL(string: "tel:116117")!) } label: { Label("116 117 – On-call doctor (evenings, weekends)", systemImage: "cross.case.fill") }
                Link(destination: URL(string: "https://www.aponet.de/apotheke/notdienstsuche")!) {
                    Label("Pharmacy on emergency duty near you", systemImage: "cross.vial.fill")
                }
            } header: {
                Text("Germany")
            } footer: {
                Text("The pharmacy search opens aponet.de in Safari.")
            }
        }
        .navigationTitle("Doctors & contacts")
        .sheet(item: $editing) { target in
            ContactForm(family: family, target: target, people: people)
        }
    }
}

struct ContactEditTarget: Identifiable {
    let id = UUID()
    let contact: HealthContact?
}

private struct ContactForm: View {
    let family: Family
    let target: ContactEditTarget
    let people: [HealthPerson]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var specialty: String
    @State private var phone: String
    @State private var address: String
    @State private var note: String
    @State private var personIDs: Set<UUID>

    static let specialties = ["Family doctor", "Dentist", "Paediatrician", "Gynaecologist", "Eye doctor", "ENT doctor",
                              "Dermatologist", "Cardiologist", "Diabetologist", "Endocrinologist", "Orthopaedist",
                              "Physiotherapy", "Pharmacy", "Hospital", "Other"]

    init(family: Family, target: ContactEditTarget, people: [HealthPerson]) {
        self.family = family
        self.target = target
        self.people = people
        let c = target.contact
        _name = State(initialValue: c?.name ?? "")
        _specialty = State(initialValue: c?.specialty ?? String(localized: "Family doctor"))
        _phone = State(initialValue: c?.phone ?? "")
        _address = State(initialValue: c?.address ?? "")
        _note = State(initialValue: c?.note ?? "")
        _personIDs = State(initialValue: c?.personIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Dr. Müller", text: $name)
                    Picker("Type", selection: $specialty) {
                        ForEach(Self.specialties, id: \.self) { key in
                            Text(LocalizedStringKey(key)).tag(String(localized: String.LocalizationValue(key)))
                        }
                        if !Self.specialties.map({ String(localized: String.LocalizationValue($0)) }).contains(specialty) {
                            Text(verbatim: specialty).tag(specialty)
                        }
                    }
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Address", text: $address, axis: .vertical).lineLimit(1...3)
                    TextField("Note (opening hours, patient number)", text: $note, axis: .vertical).lineLimit(1...4)
                }
                Section("For") {
                    ForEach(people) { person in
                        Toggle(person.name, isOn: Binding(get: { personIDs.contains(person.id) }, set: { on in
                            if on { personIDs.insert(person.id) } else { personIDs.remove(person.id) }
                        }))
                    }
                }
                if let contact = target.contact {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(contact)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let contact: HealthContact
        if let existing = target.contact {
            contact = existing
        } else {
            contact = HealthContact(familyID: family.id, name: "")
            context.insert(contact)
        }
        contact.name = name.trimmingCharacters(in: .whitespaces)
        contact.specialty = specialty
        contact.phone = phone.trimmingCharacters(in: .whitespaces)
        contact.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.note = note
        contact.personIDs = personIDs
        contact.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

// MARK: - Emergency cards

/// Per person: allergies, conditions, medications, blood type, contacts.
/// Always asks for Face ID / the passcode first.
struct EmergencyCardsView: View {
    let family: Family
    @Query private var people: [HealthPerson]
    @Query private var medications: [Medication]
    @Query private var contacts: [HealthContact]
    @State private var unlocked = false
    @Environment(\.openURL) private var openURL

    init(family: Family) {
        self.family = family
        let fid = family.id
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _medications = Query(filter: #Predicate<Medication> { $0.familyID == fid && $0.isActive == true })
        _contacts = Query(filter: #Predicate<HealthContact> { $0.familyID == fid })
    }

    var body: some View {
        Group {
            if unlocked || !AppLock.shared.canUse {
                List {
                    ForEach(people) { person in
                        card(person)
                    }
                    Section {
                        Button {
                            if let url = URL(string: "x-apple-health://") { openURL(url) }
                        } label: {
                            Label("Open the Health app for Medical ID", systemImage: "heart.text.square")
                        }
                    } footer: {
                        Text("Medical ID in Apple's Health app can show allergies, medications and contacts on the lock screen for rescuers - set it up there for each iPhone owner.")
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Button {
                        Task { await unlock() }
                    } label: {
                        Label("Unlock with \(AppLock.shared.biometryName)", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Emergency cards")
        .task { await unlock() }
    }

    private func unlock() async {
        guard !unlocked else { return }
        unlocked = await AppLock.shared.authenticate(reason: String(localized: "Show the emergency cards"))
    }

    private func card(_ person: HealthPerson) -> some View {
        let meds = medications.filter { $0.personID == person.id }
        let doctors = contacts.filter { $0.personIDs.contains(person.id) }
        return Section {
            if let age = person.age() { LabeledContent("Age", value: "\(age)") }
            if !person.bloodType.isEmpty { LabeledContent("Blood type", value: person.bloodType) }
            if !person.allergens.isEmpty {
                LabeledContent("Allergies") {
                    Text(verbatim: person.allergens.map { String(localized: String.LocalizationValue($0.title)) }.sorted().joined(separator: ", "))
                        .foregroundStyle(.red)
                }
            }
            if !person.conditions.isEmpty {
                LabeledContent("Conditions") {
                    Text(verbatim: person.conditions.map { String(localized: String.LocalizationValue($0.title)) }.sorted().joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                }
            }
            ForEach(meds) { med in
                LabeledContent("Medication") { Text(verbatim: [med.name, med.dose].filter { !$0.isEmpty }.joined(separator: " · ")) }
            }
            if !person.emergencyName.isEmpty {
                Button {
                    if let url = URL(string: "tel:" + person.emergencyPhone.filter { $0.isNumber || $0 == "+" }) { openURL(url) }
                } label: {
                    LabeledContent("Emergency contact") { Text(verbatim: person.emergencyName + " " + person.emergencyPhone) }
                }
            }
            ForEach(doctors) { doctor in
                LabeledContent(doctor.specialty) { Text(verbatim: doctor.name + " " + doctor.phone) }
            }
            if !person.notes.isEmpty { Text(verbatim: person.notes).font(.caption) }
        } header: {
            Text(verbatim: person.name)
        }
    }
}
