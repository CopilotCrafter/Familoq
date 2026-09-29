import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqHealth

/// Health tab: the family's health profiles (they shape the meal plan),
/// what is coming up, and the health organiser.
struct HealthView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        NavigationStack {
            if let family = session.family {
                HealthHome(family: family)
            } else {
                ContentUnavailableView("No family yet", systemImage: "heart.circle")
            }
        }
    }
}

private struct HealthHome: View {
    let family: Family
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var people: [HealthPerson]
    @Query private var medications: [Medication]
    @Query private var checkups: [Checkup]
    @Query private var vaccinations: [Vaccination]
    @State private var editingPerson: PersonEditTarget?
    @State private var agenda: [HealthAgenda.Item] = []

    init(family: Family) {
        self.family = family
        let fid = family.id
        _people = Query(filter: #Predicate<HealthPerson> { $0.familyID == fid }, sort: \HealthPerson.sortOrder)
        _medications = Query(filter: #Predicate<Medication> { $0.familyID == fid && $0.isActive == true })
        _checkups = Query(filter: #Predicate<Checkup> { $0.familyID == fid })
        _vaccinations = Query(filter: #Predicate<Vaccination> { $0.familyID == fid })
    }

    var body: some View {
        List {
            Section {
                ForEach(people) { person in
                    NavigationLink {
                        LazyView(PersonHealthView(family: family, personID: person.id))
                    } label: {
                        PersonRow(person: person)
                    }
                }
                if let me = session.currentMember, !people.contains(where: { $0.memberID == me.id }) {
                    Button {
                        HealthService.ensureMe(family: family, member: me, context: context)
                    } label: {
                        Label("Add my health profile", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Button {
                    editingPerson = PersonEditTarget(person: nil)
                } label: {
                    Label("Add a person (child, relative)", systemImage: "person.badge.plus")
                }
            } header: {
                Text("People")
            } footer: {
                Text("Health conditions and allergies shape the meal suggestions (Planner → Meals). A person marked \"Only on this iPhone\" is not shared with the family.")
            }

            Section("Coming up") {
                let soon = agenda.filter { $0.date < (Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()) }
                if soon.isEmpty {
                    Text("Nothing due in the next 3 months. Add check-ups and vaccinations in each person.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(soon.prefix(8)) { item in
                    HStack {
                        Image(systemName: item.icon).foregroundStyle(.pink).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.title + " · " + item.personName)
                            Text(verbatim: item.date.formatted(date: .abbreviated, time: item.kind == .appointment ? .shortened : .omitted))
                                .font(.caption)
                                .foregroundStyle(item.date < Date() ? Color.red : Color.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink { LazyView(MedicationsView(family: family)) } label: {
                    Label("Medications (\(medications.count))", systemImage: "pills")
                }
                NavigationLink { LazyView(MeasurementsView(family: family)) } label: {
                    Label("Measurements", systemImage: "chart.xyaxis.line")
                }
                NavigationLink { LazyView(PlateCheckView(family: family)) } label: {
                    Label("Plate check (photo)", systemImage: "camera.macro")
                }
                NavigationLink { LazyView(HealthCostsView(family: family)) } label: {
                    Label("Health costs & tax", systemImage: "eurosign.circle")
                }
                NavigationLink { LazyView(ClaimsView(family: family)) } label: {
                    Label("Insurance refunds", systemImage: "arrow.uturn.backward.circle")
                }
                NavigationLink { LazyView(HealthContactsView(family: family)) } label: {
                    Label("Doctors & contacts", systemImage: "phone")
                }
                NavigationLink { LazyView(EmergencyCardsView(family: family)) } label: {
                    Label("Emergency cards", systemImage: "staroflife")
                }
            } header: {
                Text("Organiser")
            } footer: {
                Text("Familoq gives general guidance from common dietary recommendations - it is not medical advice. For kidney disease, type 1 diabetes, pregnancy or allergies, follow your doctor or dietitian.")
            }
        }
        .navigationTitle("Health")
        .sheet(item: $editingPerson) { target in
            PersonForm(family: family, target: target)
        }
        .task(id: "\(people.count)-\(checkups.count)-\(vaccinations.count)-\(medications.count)") {
            agenda = HealthAgenda.items(familyIDs: [family.id], context: context)
        }
    }
}

private struct PersonRow: View {
    let person: HealthPerson

    var body: some View {
        HStack {
            Image(systemName: person.memberID == nil ? "person.crop.circle" : "person.crop.circle.fill")
                .font(.title2).foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: person.name).font(.body.weight(.medium))
                    if person.isPrivate { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                let summary = person.conditions.map { String(localized: String.LocalizationValue($0.title)) }.sorted()
                    + person.allergens.map { String(localized: String.LocalizationValue($0.title)) }.sorted()
                Text(verbatim: summary.isEmpty ? String(localized: "No conditions or allergies") : summary.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct PersonEditTarget: Identifiable {
    let id = UUID()
    let person: HealthPerson?
}

/// New or existing health person. Own copy; writes on Save.
struct PersonForm: View {
    let family: Family
    let target: PersonEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [FamilyMember]
    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var conditions: Set<HealthCondition>
    @State private var allergens: Set<FoodAllergen>
    @State private var bloodType: String
    @State private var emergencyName: String
    @State private var emergencyPhone: String
    @State private var notes: String
    @State private var remindMembers: Set<UUID>
    @State private var isPrivate: Bool
    @State private var confirmDelete = false

    init(family: Family, target: PersonEditTarget) {
        self.family = family
        self.target = target
        let fid = family.id
        _members = Query(filter: #Predicate<FamilyMember> { $0.familyID == fid && $0.isActive == true }, sort: \FamilyMember.joinedAt)
        let p = target.person
        _name = State(initialValue: p?.name ?? "")
        _hasBirthDate = State(initialValue: p?.birthDate != nil)
        _birthDate = State(initialValue: p?.birthDate ?? (Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()))
        _conditions = State(initialValue: p?.conditions ?? [])
        _allergens = State(initialValue: p?.allergens ?? [])
        _bloodType = State(initialValue: p?.bloodType ?? "")
        _emergencyName = State(initialValue: p?.emergencyName ?? "")
        _emergencyPhone = State(initialValue: p?.emergencyPhone ?? "")
        _notes = State(initialValue: p?.notes ?? "")
        _remindMembers = State(initialValue: p?.remindMembers ?? [])
        _isPrivate = State(initialValue: p?.isPrivate ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("Birth date", isOn: $hasBirthDate.animation())
                    if hasBirthDate {
                        DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: [.date])
                    }
                } footer: {
                    Text("The birth date is used for children's check-ups (U3-U11, J1).")
                }

                Section {
                    ForEach(HealthCondition.allCases) { condition in
                        Toggle(isOn: Binding(get: { conditions.contains(condition) }, set: { on in
                            if on { conditions.insert(condition) } else { conditions.remove(condition) }
                        })) {
                            Label(LocalizedStringKey(condition.title), systemImage: condition.icon)
                        }
                    }
                } header: {
                    Text("Health conditions")
                } footer: {
                    Text("Used for the meal plan only: dishes that fit come more often, strict ones (coeliac disease, pregnancy) are never suggested, and the meal shows a tip for this person.")
                }

                Section {
                    ForEach(FoodAllergen.allCases) { allergen in
                        Toggle(LocalizedStringKey(allergen.title), isOn: Binding(get: { allergens.contains(allergen) }, set: { on in
                            if on { allergens.insert(allergen) } else { allergens.remove(allergen) }
                        }))
                    }
                } header: {
                    Text("Allergies & intolerances")
                } footer: {
                    Text("Dishes with these are never suggested. The catalogue is a guide - always check labels.")
                }

                Section("Emergency card") {
                    Picker("Blood type", selection: $bloodType) {
                        Text("Unknown").tag("")
                        ForEach(["0+", "0-", "A+", "A-", "B+", "B-", "AB+", "AB-"], id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    TextField("Emergency contact", text: $emergencyName)
                    TextField("Their phone", text: $emergencyPhone).keyboardType(.phonePad)
                    TextField("Notes (e.g. implants, important information)", text: $notes, axis: .vertical).lineLimit(1...5)
                }

                Section {
                    ForEach(members) { member in
                        Toggle(isOn: Binding(get: { remindMembers.contains(member.id) }, set: { on in
                            if on { remindMembers.insert(member.id) } else { remindMembers.remove(member.id) }
                        })) {
                            Text(verbatim: member.displayName)
                        }
                    }
                } header: {
                    Text("Reminders go to")
                } footer: {
                    Text("None chosen: the person themselves (if they use Familoq), otherwise everyone.")
                }

                Section {
                    Toggle(isOn: $isPrivate) {
                        Label("Only on this iPhone", systemImage: "lock")
                    }
                } footer: {
                    Text("Not shared with the family: this person and their check-ups, vaccinations, medications and measurements stay on this iPhone (and in your backup). Meal plans made on other iPhones then don't know them.")
                }

                if let person = target.person, person.memberID == nil {
                    Section {
                        Button("Delete person", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(target.person == nil ? LocalizedStringKey("New person") : LocalizedStringKey("Health profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this person and all their health records?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let person = target.person { HealthService.delete(person, context: context) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let person: HealthPerson
        if let existing = target.person {
            person = existing
        } else {
            person = HealthPerson(familyID: family.id, name: "")
            let fid = family.id
            let count = (try? context.fetchCount(FetchDescriptor<HealthPerson>(predicate: #Predicate { $0.familyID == fid }))) ?? 0
            person.sortOrder = count + 1
            context.insert(person)
        }
        person.name = name.trimmingCharacters(in: .whitespaces)
        person.birthDate = hasBirthDate ? birthDate : nil
        person.conditions = conditions
        person.allergens = allergens
        person.bloodType = bloodType
        person.emergencyName = emergencyName.trimmingCharacters(in: .whitespaces)
        person.emergencyPhone = emergencyPhone.trimmingCharacters(in: .whitespaces)
        person.notes = notes
        person.remindMembers = remindMembers
        person.updatedAt = Date()
        if person.isPrivate != isPrivate {
            HealthService.setPrivate(person, isPrivate, context: context)
        }
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }
}

/// One person: conditions with what they mean, check-ups, vaccinations,
/// medications and latest measurements.
struct PersonHealthView: View {
    let family: Family
    let personID: UUID
    @Environment(\.modelContext) private var context
    @Query private var persons: [HealthPerson]
    @Query private var checkups: [Checkup]
    @Query private var vaccinations: [Vaccination]
    @Query private var medications: [Medication]
    @Query private var measurements: [HealthMeasurement]
    @State private var editingPerson: PersonEditTarget?
    @State private var editingCheckup: CheckupEditTarget?
    @State private var editingVaccination: VaccinationEditTarget?
    @State private var editingMedication: MedicationEditTarget?
    @State private var addingMeasurement: MeasurementEditTarget?

    init(family: Family, personID: UUID) {
        self.family = family
        self.personID = personID
        let pid = personID
        _persons = Query(filter: #Predicate<HealthPerson> { $0.id == pid })
        _checkups = Query(filter: #Predicate<Checkup> { $0.personID == pid }, sort: \Checkup.createdAt)
        _vaccinations = Query(filter: #Predicate<Vaccination> { $0.personID == pid }, sort: \Vaccination.date, order: .reverse)
        _medications = Query(filter: #Predicate<Medication> { $0.personID == pid }, sort: \Medication.name)
        _measurements = Query(filter: #Predicate<HealthMeasurement> { $0.personID == pid }, sort: \HealthMeasurement.date, order: .reverse)
    }

    var body: some View {
        if let person = persons.first {
            content(person)
        } else {
            ContentUnavailableView("Removed", systemImage: "person.slash")
        }
    }

    private func content(_ person: HealthPerson) -> some View {
        let calendar = FamiloqCalendar.make()
        let suggested = MeasurementType.suggested(for: person.conditions)
        return List {
            Section {
                if person.conditions.isEmpty && person.allergens.isEmpty {
                    Text("No conditions or allergies. Tap Edit to add them - the meal plan then takes them into account.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(person.conditions.sorted { $0.rawValue < $1.rawValue }) { condition in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(LocalizedStringKey(condition.title), systemImage: condition.icon).font(.headline)
                        Text(LocalizedStringKey(condition.guidance)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !person.allergens.isEmpty {
                    Label {
                        Text(verbatim: person.allergens.map { String(localized: String.LocalizationValue($0.title)) }.sorted().joined(separator: ", "))
                    } icon: {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(.red)
                    }
                }
            } header: {
                Text("For the meal plan")
            }

            Section {
                ForEach(checkups) { checkup in
                    Button {
                        editingCheckup = CheckupEditTarget(checkup: checkup, personID: person.id)
                    } label: {
                        CheckupRow(checkup: checkup, person: person, calendar: calendar)
                    }
                }
                Menu {
                    ForEach(CheckupKind.allCases) { kind in
                        Button {
                            editingCheckup = CheckupEditTarget(checkup: nil, personID: person.id, kind: kind)
                        } label: {
                            Label(LocalizedStringKey(kind.title), systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("Add check-up", systemImage: "plus")
                }
            } header: {
                Text("Check-ups")
            }

            Section {
                ForEach(vaccinations) { vaccination in
                    Button {
                        editingVaccination = VaccinationEditTarget(vaccination: vaccination, personID: person.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: vaccination.displayTitle).foregroundStyle(.primary)
                                Text(verbatim: vaccination.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let due = vaccination.due(calendar: calendar) {
                                Text("next \(due.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption).foregroundStyle(due < Date() ? Color.red : Color.secondary)
                            }
                        }
                    }
                }
                Button {
                    editingVaccination = VaccinationEditTarget(vaccination: nil, personID: person.id)
                } label: {
                    Label("Add vaccination", systemImage: "plus")
                }
            } header: {
                Text("Vaccinations")
            } footer: {
                Text("Enter each vaccination from the vaccination card (Impfpass). Boosters use the usual STIKO intervals; change them if your doctor says otherwise.")
            }

            Section {
                ForEach(medications) { medication in
                    Button {
                        editingMedication = MedicationEditTarget(medication: medication, personID: person.id)
                    } label: {
                        MedicationRow(medication: medication, calendar: calendar)
                    }
                }
                Button {
                    editingMedication = MedicationEditTarget(medication: nil, personID: person.id)
                } label: {
                    Label("Add medication", systemImage: "plus")
                }
            } header: {
                Text("Medications")
            }

            Section {
                let types = Array(Set(measurements.map(\.type))).sorted { $0.rawValue < $1.rawValue }
                ForEach(types) { type in
                    if let latest = measurements.first(where: { $0.type == type }) {
                        NavigationLink {
                            LazyView(MeasurementChartView(family: family, personID: person.id, type: type))
                        } label: {
                            LabeledContent {
                                Text(verbatim: latest.text).monospacedDigit()
                            } label: {
                                Label(LocalizedStringKey(type.title), systemImage: type.icon)
                            }
                        }
                    }
                }
                Menu {
                    ForEach(suggested + MeasurementType.allCases.filter { !suggested.contains($0) }) { type in
                        Button(LocalizedStringKey(type.title)) {
                            addingMeasurement = MeasurementEditTarget(personID: person.id, type: type)
                        }
                    }
                } label: {
                    Label("Add measurement", systemImage: "plus")
                }
            } header: {
                Text("Measurements")
            }
        }
        .navigationTitle(person.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editingPerson = PersonEditTarget(person: person) }
            }
        }
        .sheet(item: $editingPerson) { target in PersonForm(family: family, target: target) }
        .sheet(item: $editingCheckup) { target in CheckupForm(family: family, person: person, target: target) }
        .sheet(item: $editingVaccination) { target in VaccinationForm(family: family, person: person, target: target) }
        .sheet(item: $editingMedication) { target in MedicationForm(family: family, person: person, target: target) }
        .sheet(item: $addingMeasurement) { target in MeasurementForm(family: family, person: person, target: target) }
    }
}

private struct CheckupRow: View {
    let checkup: Checkup
    let person: HealthPerson
    let calendar: Calendar

    var body: some View {
        HStack {
            Image(systemName: checkup.kind.icon).foregroundStyle(.pink).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: checkup.displayTitle).foregroundStyle(.primary)
                Text(verbatim: status).font(.caption).foregroundStyle(isOverdue ? Color.red : Color.secondary)
            }
        }
    }

    private var nextDate: Date? {
        if let appointment = checkup.appointment { return appointment }
        if checkup.kind == .childExam, let birth = person.birthDate {
            return ChildExam.next(birthDate: birth, done: checkup.doneExams, now: Date(), calendar: calendar)?.from
        }
        return checkup.lastDate.flatMap { HealthDue.next(after: $0, months: checkup.intervalMonths, calendar: calendar) }
    }

    private var isOverdue: Bool { (nextDate ?? .distantFuture) < calendar.startOfDay(for: Date()) }

    private var status: String {
        if let appointment = checkup.appointment {
            return String(localized: "Appointment \(appointment.formatted(date: .abbreviated, time: .shortened))")
        }
        if checkup.kind == .childExam {
            guard let birth = person.birthDate else { return String(localized: "Add the birth date in the profile") }
            guard let next = ChildExam.next(birthDate: birth, done: checkup.doneExams, now: Date(), calendar: calendar) else {
                return String(localized: "All children's check-ups done")
            }
            return String(localized: "\(next.exam.name): \(next.from.formatted(date: .abbreviated, time: .omitted)) – \(next.to.formatted(date: .abbreviated, time: .omitted))")
        }
        guard let next = nextDate else { return String(localized: "When was the last one? Tap to add it.") }
        return String(localized: "Next around \(next.formatted(.dateTime.month(.wide).year()))")
    }
}

private struct MedicationRow: View {
    let medication: Medication
    let calendar: Calendar

    var body: some View {
        HStack {
            Image(systemName: "pills.fill").foregroundStyle(medication.isActive ? Color.pink : Color.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: medication.dose.isEmpty ? medication.name : "\(medication.name) · \(medication.dose)").foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if !medication.timesRaw.isEmpty {
                        Label(medication.timesRaw.replacingOccurrences(of: ",", with: ", "), systemImage: "bell").labelStyle(.titleAndIcon)
                    }
                    if let runOut = medication.runOut(calendar: calendar) {
                        Text("lasts until \(runOut.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(runOut < (calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()) ? Color.orange : Color.secondary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
