import SwiftUI
import SwiftData
import FamiloqCore
import FamiloqHealth

// Edit sheets for the Health space. Each keeps its own copy and writes on Save.

struct CheckupEditTarget: Identifiable {
    let id = UUID()
    let checkup: Checkup?
    let personID: UUID
    var kind: CheckupKind = .dentist
}

struct CheckupForm: View {
    let family: Family
    let person: HealthPerson
    let target: CheckupEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CheckupKind
    @State private var title: String
    @State private var hasLast: Bool
    @State private var lastDate: Date
    @State private var months: Int
    @State private var hasAppointment: Bool
    @State private var appointment: Date
    @State private var doneExams: Set<String>
    @State private var note: String
    @State private var remind: Bool

    init(family: Family, person: HealthPerson, target: CheckupEditTarget) {
        self.family = family
        self.person = person
        self.target = target
        let c = target.checkup
        let kind = c?.kind ?? target.kind
        _kind = State(initialValue: kind)
        _title = State(initialValue: c?.title ?? "")
        _hasLast = State(initialValue: c?.lastDate != nil)
        _lastDate = State(initialValue: c?.lastDate ?? Date())
        _months = State(initialValue: c?.intervalMonths ?? kind.defaultMonths)
        _hasAppointment = State(initialValue: c?.appointment != nil)
        _appointment = State(initialValue: c?.appointment ?? (Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()))
        _doneExams = State(initialValue: c?.doneExams ?? [])
        _note = State(initialValue: c?.note ?? "")
        _remind = State(initialValue: c?.remind ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(LocalizedStringKey(kind.title), systemImage: kind.icon)
                    if kind == .custom {
                        TextField("What, e.g. Orthodontist", text: $title)
                    }
                }
                if kind == .childExam {
                    Section {
                        ForEach(ChildExam.all, id: \.name) { exam in
                            Toggle(isOn: Binding(get: { doneExams.contains(exam.name) }, set: { on in
                                if on { doneExams.insert(exam.name) } else { doneExams.remove(exam.name) }
                            })) {
                                VStack(alignment: .leading) {
                                    Text(verbatim: exam.name)
                                    Text(verbatim: ageText(exam)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Done (yellow booklet)")
                    } footer: {
                        if person.birthDate == nil { Text("Add the birth date in the profile to get the dates.") }
                    }
                } else {
                    Section {
                        Toggle("Last check-up known", isOn: $hasLast.animation())
                        if hasLast {
                            DatePicker("Last one", selection: $lastDate, in: ...Date(), displayedComponents: [.date])
                        }
                        Stepper(value: $months, in: 1...120) { Text("Every \(months) months") }
                    } footer: {
                        Text("Typical interval: \(kind.defaultMonths) months.")
                    }
                }
                Section {
                    Toggle("Appointment booked", isOn: $hasAppointment.animation())
                    if hasAppointment {
                        DatePicker("Appointment", selection: $appointment)
                    }
                    Toggle("Remind me", isOn: $remind)
                    TextField("Note (doctor, what to bring)", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("Reminder 14 days before it is due and on the day; for an appointment, the day before.")
                }
                if hasAppointment, target.checkup != nil {
                    Section {
                        Button("Mark as done today") {
                            hasLast = true
                            lastDate = Date()
                            hasAppointment = false
                        }
                    }
                }
                if let checkup = target.checkup {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(checkup)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: person.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func ageText(_ exam: ChildExam) -> String {
        guard let birth = person.birthDate,
              let from = Calendar.current.date(byAdding: .month, value: exam.fromMonths, to: birth),
              let to = Calendar.current.date(byAdding: .month, value: exam.toMonths, to: birth) else { return "" }
        return from.formatted(date: .abbreviated, time: .omitted) + " – " + to.formatted(date: .abbreviated, time: .omitted)
    }

    private func save() {
        let checkup: Checkup
        if let existing = target.checkup {
            checkup = existing
        } else {
            checkup = Checkup(familyID: family.id, personID: person.id, kind: kind)
            checkup.isPrivate = person.isPrivate
            context.insert(checkup)
        }
        checkup.kind = kind
        checkup.title = title.trimmingCharacters(in: .whitespaces)
        checkup.lastDate = hasLast ? lastDate : nil
        checkup.intervalMonths = months
        checkup.appointment = hasAppointment ? appointment : nil
        checkup.doneExams = doneExams
        checkup.note = note
        checkup.remind = remind
        checkup.updatedAt = Date()
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }
}

struct VaccinationEditTarget: Identifiable {
    let id = UUID()
    let vaccination: Vaccination?
    let personID: UUID
}

struct VaccinationForm: View {
    let family: Family
    let person: HealthPerson
    let target: VaccinationEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var trips: [Trip]
    @State private var kind: VaccineKind
    @State private var title: String
    @State private var date: Date
    @State private var months: Int
    @State private var hasNext: Bool
    @State private var nextDue: Date
    @State private var batch: String
    @State private var note: String
    @State private var tripID: UUID?

    init(family: Family, person: HealthPerson, target: VaccinationEditTarget) {
        self.family = family
        self.person = person
        self.target = target
        let fid = family.id
        _trips = Query(filter: #Predicate<Trip> { $0.familyID == fid }, sort: \Trip.startDate, order: .reverse)
        let v = target.vaccination
        let kind = v?.kind ?? .tetanusDiphtheriaPertussis
        _kind = State(initialValue: kind)
        _title = State(initialValue: v?.title ?? "")
        _date = State(initialValue: v?.date ?? Date())
        _months = State(initialValue: v?.boosterMonths ?? kind.defaultBoosterMonths)
        _hasNext = State(initialValue: v?.nextDue != nil)
        _nextDue = State(initialValue: v?.nextDue ?? (Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()))
        _batch = State(initialValue: v?.batch ?? "")
        _note = State(initialValue: v?.note ?? "")
        _tripID = State(initialValue: v?.tripID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Vaccine", selection: $kind) {
                        ForEach(VaccineKind.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    .onChange(of: kind) { _, value in months = value.defaultBoosterMonths }
                    if kind == .custom {
                        TextField("Vaccine name", text: $title)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    TextField("Batch number (optional)", text: $batch)
                }
                Section {
                    Stepper(value: $months, in: 0...240, step: 6) {
                        Text(months == 0 ? LocalizedStringKey("No routine booster") : LocalizedStringKey("Booster after \(months) months"))
                    }
                    Toggle("Next dose on a set date", isOn: $hasNext.animation())
                    if hasNext {
                        DatePicker("Next dose", selection: $nextDue, displayedComponents: [.date])
                    }
                } footer: {
                    Text(kind == .flu ? LocalizedStringKey("Flu: reminder each October.") : LocalizedStringKey("For a series (e.g. 2nd or 3rd dose) set the date of the next dose."))
                }
                if kind.isTravel || tripID != nil {
                    Section {
                        Picker("For the trip", selection: $tripID) {
                            Text("None").tag(UUID?.none)
                            ForEach(trips) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if let vaccination = target.vaccination {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(vaccination)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: person.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let vaccination: Vaccination
        if let existing = target.vaccination {
            vaccination = existing
        } else {
            vaccination = Vaccination(familyID: family.id, personID: person.id, kind: kind, date: date)
            vaccination.isPrivate = person.isPrivate
            context.insert(vaccination)
        }
        vaccination.kind = kind
        vaccination.title = title.trimmingCharacters(in: .whitespaces)
        vaccination.date = date
        vaccination.boosterMonths = months
        vaccination.nextDue = hasNext ? nextDue : nil
        vaccination.batch = batch
        vaccination.note = note
        vaccination.tripID = tripID
        vaccination.updatedAt = Date()
        try? context.save()
        Task { await PlannerNotifications.reschedule(context: context) }
        dismiss()
    }
}

struct MedicationEditTarget: Identifiable {
    let id = UUID()
    let medication: Medication?
    let personID: UUID
}

struct MedicationForm: View {
    let family: Family
    let person: HealthPerson
    let target: MedicationEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var dose: String
    @State private var times: [Date]
    @State private var perDay: Double
    @State private var stock: Double
    @State private var remindDoses: Bool
    @State private var remindRefill: Bool
    @State private var isActive: Bool
    @State private var isPrivate: Bool
    @State private var note: String

    init(family: Family, person: HealthPerson, target: MedicationEditTarget) {
        self.family = family
        self.person = person
        self.target = target
        let m = target.medication
        _name = State(initialValue: m?.name ?? "")
        _dose = State(initialValue: m?.dose ?? "")
        let calendar = Calendar.current
        let existing = m?.times.compactMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: Date()) } ?? []
        _times = State(initialValue: m == nil ? [calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()] : existing)
        _perDay = State(initialValue: m?.perDay ?? 1)
        _stock = State(initialValue: m.map { $0.remaining(calendar: calendar) } ?? 0)
        _remindDoses = State(initialValue: m?.remindDoses ?? true)
        _remindRefill = State(initialValue: m?.remindRefill ?? true)
        _isActive = State(initialValue: m?.isActive ?? true)
        _isPrivate = State(initialValue: m?.isPrivate ?? true)
        _note = State(initialValue: m?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. L-Thyroxin 75", text: $name)
                    TextField("Dose, e.g. 1 tablet", text: $dose)
                }
                Section {
                    Toggle("Remind me to take it", isOn: $remindDoses)
                    if remindDoses {
                        ForEach(times.indices, id: \.self) { index in
                            DatePicker("Time \(index + 1)", selection: Binding(
                                get: { index < times.count ? times[index] : Date() },
                                set: { if index < times.count { times[index] = $0 } }), displayedComponents: [.hourAndMinute])
                        }
                        HStack {
                            if times.count < 6 {
                                Button("Add a time") {
                                    times.append(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date())
                                }
                                .buttonStyle(.borderless)
                            }
                            Spacer()
                            if times.count > 1 {
                                Button("Remove last", role: .destructive) { times.removeLast() }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                } footer: {
                    Text("Every day at these times, on the iPhones that get this person's reminders.")
                }
                Section {
                    Stepper(value: $stock, in: 0...1000, step: 1) { Text("Left now: \(Int(stock))") }
                    Stepper(value: $perDay, in: 0.5...12, step: 0.5) { Text("Per day: \(perDay.formatted(.number.precision(.fractionLength(0...1))))") }
                    Toggle("Remind me before it runs out", isOn: $remindRefill)
                    if stock > 0, perDay > 0 {
                        let days = Int(stock / perDay)
                        Text("Lasts about \(days) days.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Pack")
                } footer: {
                    Text("A reminder 7 days before the pack is empty, so there is time for a prescription. Update \"Left now\" when you open a new pack.")
                }
                Section {
                    Toggle("Taking it at the moment", isOn: $isActive)
                    Toggle(isOn: $isPrivate) { Label("Only on this iPhone", systemImage: "lock") }
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    Text("Medications are private by default. Share one if a partner should remind a child or parent.")
                }
                if let medication = target.medication {
                    Section {
                        Button("Delete", role: .destructive) {
                            context.delete(medication)
                            try? context.save()
                            Task { await PlannerNotifications.reschedule(context: context) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: person.name))
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
        let medication: Medication
        if let existing = target.medication {
            medication = existing
        } else {
            medication = Medication(familyID: family.id, personID: person.id, name: "")
            context.insert(medication)
        }
        let calendar = Calendar.current
        medication.name = name.trimmingCharacters(in: .whitespaces)
        medication.dose = dose.trimmingCharacters(in: .whitespaces)
        medication.times = times.map { (hour: calendar.component(.hour, from: $0), minute: calendar.component(.minute, from: $0)) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        medication.perDay = perDay
        medication.stock = stock
        medication.stockDate = calendar.startOfDay(for: Date())
        medication.remindDoses = remindDoses
        medication.remindRefill = remindRefill
        medication.isActive = isActive
        medication.isPrivate = isPrivate || person.isPrivate
        medication.note = note
        medication.updatedAt = Date()
        try? context.save()
        Task {
            _ = await PlannerNotifications.requestPermissionIfNeeded()
            await PlannerNotifications.reschedule(context: context)
        }
        dismiss()
    }
}

struct MeasurementEditTarget: Identifiable {
    let id = UUID()
    let personID: UUID
    let type: MeasurementType
}

struct MeasurementForm: View {
    let family: Family
    let person: HealthPerson
    let target: MeasurementEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var value2 = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isPrivate = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(target.type.hasSecondValue ? LocalizedStringKey("Systolic, e.g. 128") : LocalizedStringKey("Value"), text: $value).keyboardType(.decimalPad)
                        if target.type.hasSecondValue {
                            Text(verbatim: "/")
                            TextField("Diastolic, e.g. 82", text: $value2).keyboardType(.numberPad)
                        }
                        Text(verbatim: target.type.unit).foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                    TextField("Note (e.g. after sport, fasting)", text: $note)
                    Toggle(isOn: $isPrivate) { Label("Only on this iPhone", systemImage: "lock") }
                } header: {
                    Text(LocalizedStringKey(target.type.title))
                }
            }
            .navigationTitle(Text(verbatim: person.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(number(value) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func save() {
        guard let first = number(value) else { return }
        let m = HealthMeasurement(familyID: family.id, personID: person.id, type: target.type, value: first, date: date)
        m.value2 = number(value2) ?? 0
        m.note = note
        m.isPrivate = isPrivate || person.isPrivate
        context.insert(m)
        try? context.save()
        dismiss()
    }
}
