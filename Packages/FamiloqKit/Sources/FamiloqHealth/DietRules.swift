import Foundation
import FamiloqCore
import FamiloqBudget

/// Lifestyle and chronic conditions that shape meal suggestions. Based on
/// common dietary guidance (e.g. DASH for blood pressure); not medical advice.
public enum HealthCondition: String, CaseIterable, Codable, Sendable, Identifiable {
    case highBloodPressure, diabetesType2, diabetesType1, highCholesterol, highTriglycerides, heartDisease
    case hypothyroidism, hyperthyroidism, gout, fattyLiver, weightGoal
    case coeliac, lactoseIntolerance, ibs, reflux, ironDeficiency, osteoporosis, pregnancy, kidneyDisease

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highBloodPressure: return "High blood pressure"
        case .diabetesType2: return "Type 2 diabetes / prediabetes"
        case .diabetesType1: return "Type 1 diabetes"
        case .highCholesterol: return "High cholesterol"
        case .highTriglycerides: return "High triglycerides"
        case .heartDisease: return "Heart disease"
        case .hypothyroidism: return "Underactive thyroid / Hashimoto's"
        case .hyperthyroidism: return "Overactive thyroid"
        case .gout: return "Gout / high uric acid"
        case .fattyLiver: return "Fatty liver"
        case .weightGoal: return "Losing weight"
        case .coeliac: return "Coeliac disease (gluten-free)"
        case .lactoseIntolerance: return "Lactose intolerance"
        case .ibs: return "Irritable bowel (IBS)"
        case .reflux: return "Heartburn / reflux"
        case .ironDeficiency: return "Iron deficiency"
        case .osteoporosis: return "Osteoporosis"
        case .pregnancy: return "Pregnancy"
        case .kidneyDisease: return "Kidney disease"
        }
    }

    public var icon: String {
        switch self {
        case .highBloodPressure, .heartDisease: return "heart.fill"
        case .diabetesType1, .diabetesType2: return "drop.fill"
        case .highCholesterol, .highTriglycerides, .fattyLiver: return "waveform.path.ecg"
        case .hypothyroidism, .hyperthyroidism: return "bolt.heart.fill"
        case .gout: return "figure.walk"
        case .weightGoal: return "scalemass.fill"
        case .coeliac, .lactoseIntolerance, .ibs, .reflux: return "fork.knife"
        case .ironDeficiency: return "bolt.fill"
        case .osteoporosis: return "figure.stand"
        case .pregnancy: return "figure.and.child.holdinghands"
        case .kidneyDisease: return "cross.case.fill"
        }
    }

    /// Food rules need a doctor or dietitian (Familoq only lowers salt).
    public var needsProfessionalPlan: Bool { self == .kidneyDisease || self == .diabetesType1 }

    /// Shows a rough carbohydrate count per portion.
    public var showsCarbs: Bool { self == .diabetesType2 || self == .diabetesType1 }

    /// What the menu leans towards.
    public var guidance: String {
        switch self {
        case .highBloodPressure: return "More vegetables, pulses and low-fat dairy; less salt, sausage, cured meat, pickles and ready meals."
        case .diabetesType2: return "Wholegrain, fibre, protein with every meal and smaller portions of white rice, pasta and bread; hardly any sugar or sweet drinks."
        case .diabetesType1: return "Balanced meals; the carb counts are rough estimates and not for insulin dosing - follow your diabetes team."
        case .highCholesterol: return "Oats, pulses, nuts, fish and olive or rapeseed oil; less butter, ghee, cream, fatty meat, sausage and fried food."
        case .highTriglycerides: return "Less sugar, white flour and alcohol; fish twice a week, more vegetables and pulses."
        case .heartDisease: return "Low salt and low saturated fat: vegetables, pulses, fish, wholegrain and plant oils."
        case .hypothyroidism: return "A normal balanced diet with iodised salt, fish and dairy; selenium from fish and eggs. Gluten-free only with coeliac disease. Take the tablet 30-60 minutes before breakfast, away from coffee, soy, calcium and high-fibre foods."
        case .hyperthyroidism: return "Balanced meals; iodine-rich seaweed is left out."
        case .gout: return "Dairy, vegetables and pulses are fine; less offal, red meat, shellfish, beer and sweet drinks."
        case .fattyLiver: return "Like diabetes: wholegrain, vegetables and fish; no alcohol, little sugar and fried food."
        case .weightGoal: return "Half the plate vegetables, enough protein, smaller carb portions; fewer fried and sweet dishes."
        case .coeliac: return "Strictly gluten-free: dishes with wheat, rye, barley or spelt are never suggested. Check labels - the catalogue is a guide."
        case .lactoseIntolerance: return "Dishes with milk, cream or yoghurt come less often; lactose-free products work as swaps. Hard cheese is usually fine."
        case .ibs: return "Fewer beans, wheat and very spicy or fried dishes (a rough low-FODMAP guide - a dietitian can tailor it)."
        case .reflux: return "Fewer very spicy, fatty and fried dishes and less alcohol; smaller evening portions."
        case .ironDeficiency: return "Pulses, green vegetables, meat or fish; vitamin C with the meal and tea or coffee not right with it."
        case .osteoporosis: return "Dairy or calcium-rich foods, fish for vitamin D, green vegetables."
        case .pregnancy: return "Folate, iron and calcium; no raw fish or meat, no liver, no alcohol; heat eggs and fish well, no raw-milk soft cheese."
        case .kidneyDisease: return "Familoq only lowers salt. Potassium, phosphate and protein limits depend on the stage - ask your nephrologist or dietitian."
        }
    }

    /// Short tip per dish for this person (when the dish needs a tweak).
    public func tip(for dish: Dish) -> String? {
        switch self {
        case .highBloodPressure, .heartDisease, .kidneyDisease:
            if dish.has(.highSalt) || dish.has(.processedMeat) { return "Less salt: salt at the table, not in the pot; small portion of sausage or ham." }
        case .diabetesType2, .diabetesType1:
            if dish.base.isRefined || dish.has(.highSugar) { return "Half portion of rice, pasta or bread; extra salad or vegetables." }
            if dish.has(.sweet) { return "Small portion; add a salad or yoghurt." }
        case .highCholesterol, .highTriglycerides:
            if dish.has(.highSatFat) || dish.has(.fried) { return "Use oil instead of butter, ghee or cream; small portion." }
        case .gout:
            if dish.has(.purine) || dish.has(.offal) || dish.proteins.contains(.shellfish) || dish.hasRedMeat { return "Small portion of meat or seafood; more vegetables." }
        case .fattyLiver, .weightGoal:
            if dish.has(.fried) || dish.has(.highSatFat) || dish.has(.sweet) { return "Smaller portion, half the plate vegetables." }
            if dish.base.isRefined { return "Smaller carb portion, extra vegetables." }
        case .lactoseIntolerance:
            if dish.has(.dairy) { return "Use lactose-free milk, cream or yoghurt." }
        case .reflux:
            if dish.spiceLevel >= 2 || dish.has(.fried) { return "Mild portion (chilli at the table); no late big meal." }
        case .ironDeficiency:
            if dish.hasLegumes || dish.has(.vegetableRich) { return "Add lemon, peppers or fruit (vitamin C) for better iron uptake." }
        case .hypothyroidism:
            if dish.has(.soy) { return "Soy is fine, but not within 4 hours of the thyroid tablet." }
        case .pregnancy:
            if dish.hasFish || dish.containsEgg { return "Cook fish and eggs through." }
        case .coeliac, .hyperthyroidism, .osteoporosis, .ibs:
            break
        }
        return nil
    }

    /// Food groups the Healthy basket watches for this condition.
    public var basketWatch: [FoodGroup] {
        switch self {
        case .highBloodPressure, .heartDisease, .kidneyDisease: return [.processedMeat, .readyMeals, .sweetsSnacks, .alcohol]
        case .diabetesType1, .diabetesType2, .weightGoal: return [.sugaryDrinks, .sweetsSnacks, .readyMeals]
        case .highCholesterol: return [.processedMeat, .readyMeals, .sweetsSnacks]
        case .highTriglycerides, .fattyLiver: return [.sugaryDrinks, .sweetsSnacks, .alcohol]
        case .gout: return [.alcohol, .sugaryDrinks, .processedMeat]
        case .reflux: return [.alcohol, .readyMeals]
        case .pregnancy: return [.alcohol]
        case .hypothyroidism, .hyperthyroidism, .coeliac, .lactoseIntolerance, .ibs, .ironDeficiency, .osteoporosis: return []
        }
    }
}

/// Allergies and intolerances that are never suggested.
public enum FoodAllergen: String, CaseIterable, Codable, Sendable, Identifiable {
    case gluten, lactose, nuts, egg, fish, shellfish, soy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gluten: return "Gluten"
        case .lactose: return "Milk / lactose"
        case .nuts: return "Nuts & peanuts"
        case .egg: return "Egg"
        case .fish: return "Fish"
        case .shellfish: return "Shellfish"
        case .soy: return "Soy"
        }
    }

    public func isIn(_ dish: Dish) -> Bool {
        switch self {
        case .gluten: return dish.has(.gluten)
        case .lactose: return dish.has(.dairy)
        case .nuts: return dish.has(.nuts)
        case .egg: return dish.containsEgg
        case .fish: return dish.hasFish
        case .shellfish: return dish.proteins.contains(.shellfish)
        case .soy: return dish.has(.soy)
        }
    }
}

/// The people's health settings that apply to the family table.
public struct DietPerson: Sendable {
    public var name: String
    public var conditions: Set<HealthCondition>
    public var allergens: Set<FoodAllergen>

    public init(name: String, conditions: Set<HealthCondition>, allergens: Set<FoodAllergen>) {
        self.name = name
        self.conditions = conditions
        self.allergens = allergens
    }
}

/// Everything that decides which dishes fit the family.
public struct DietProfile: Sendable {
    public var people: [DietPerson]
    /// Words never wanted ("Schwein", "Pilze", "Koriander").
    public var avoidWords: [String]
    public var maxSpice: Int
    public var kidFriendly: Bool

    public init(people: [DietPerson] = [], avoidWords: [String] = [], maxSpice: Int = 3, kidFriendly: Bool = false) {
        self.people = people
        self.avoidWords = avoidWords
        self.maxSpice = maxSpice
        self.kidFriendly = kidFriendly
    }

    public var conditions: Set<HealthCondition> { people.reduce(into: []) { $0.formUnion($1.conditions) } }
    public var allergens: Set<FoodAllergen> { people.reduce(into: []) { $0.formUnion($1.allergens) } }

    /// Strict rules: allergies, coeliac disease, pregnancy food safety, avoid list, spice.
    public func allows(_ dish: Dish) -> Bool {
        let conditions = self.conditions
        if allergens.contains(where: { $0.isIn(dish) }) { return false }
        if conditions.contains(.coeliac) && dish.has(.gluten) { return false }
        if conditions.contains(.pregnancy) && (dish.has(.raw) || dish.has(.offal) || dish.has(.alcohol)) { return false }
        if conditions.contains(.hyperthyroidism) && dish.has(.seaweed) { return false }
        if dish.spiceLevel > maxSpice { return false }
        if !avoidWords.isEmpty {
            let text = TextNormalizer.normalize(([dish.name, dish.englishDescription, dish.germanDescription] + dish.ingredients).joined(separator: " "),
                                                germanTransliteration: true)
            for word in avoidWords {
                let key = TextNormalizer.normalize(word, germanTransliteration: true).trimmingCharacters(in: .whitespaces)
                if key.count >= 3 && text.contains(key) { return false }
            }
            // Common meat words also match the protein tags.
            let lowered = avoidWords.map { TextNormalizer.normalize($0, germanTransliteration: true) }
            if dish.proteins.contains(.pork) && lowered.contains(where: { ["schwein", "pork", "schweinefleisch"].contains($0) }) { return false }
        }
        return true
    }

    /// Soft rules: positive = fits well, negative = better less often.
    public func fit(_ dish: Dish) -> Double {
        var score = 0.0
        for condition in conditions {
            score += Self.fit(dish, condition)
        }
        if kidFriendly && dish.has(.kidFriendly) { score += 0.2 }
        return score
    }

    static func fit(_ d: Dish, _ c: HealthCondition) -> Double {
        var s = 0.0
        func avoid(_ flag: DishFlag, _ weight: Double) { if d.has(flag) { s -= weight } }
        let veg = d.has(.vegetableRich) ? 1.0 : 0
        let pulses = d.hasLegumes ? 1.0 : 0
        let fish = d.hasFish ? 1.0 : 0
        let whole = d.base == .wholegrain ? 1.0 : 0
        switch c {
        case .highBloodPressure, .heartDisease:
            avoid(.highSalt, 0.8); avoid(.processedMeat, 0.8); avoid(.highSatFat, c == .heartDisease ? 0.6 : 0.2)
            s += 0.3 * veg + 0.2 * pulses + (c == .heartDisease ? 0.3 * fish : 0)
        case .diabetesType2, .diabetesType1:
            avoid(.highSugar, 0.8); avoid(.sweet, 0.8); avoid(.fried, 0.2)
            if d.base.isRefined { s -= 0.3 }
            s += 0.3 * whole + 0.3 * pulses + 0.2 * veg
        case .highCholesterol:
            avoid(.highSatFat, 0.8); avoid(.processedMeat, 0.6); avoid(.fried, 0.5); avoid(.offal, 0.3)
            s += 0.3 * pulses + 0.3 * fish + 0.2 * whole + 0.2 * veg
        case .highTriglycerides:
            avoid(.highSugar, 0.7); avoid(.sweet, 0.7); avoid(.alcohol, 0.8); avoid(.highSatFat, 0.4)
            if d.base.isRefined { s -= 0.3 }
            s += 0.4 * fish + 0.2 * veg + 0.2 * pulses
        case .hypothyroidism:
            s += 0.2 * fish
        case .hyperthyroidism:
            avoid(.seaweed, 1.0)
        case .gout:
            avoid(.purine, 0.9); avoid(.offal, 0.9); avoid(.alcohol, 0.6); avoid(.highSugar, 0.3)
            if d.proteins.contains(.shellfish) { s -= 0.6 }
            if d.proteins.contains(.redMeat) { s -= 0.4 }
            s += 0.2 * veg
        case .fattyLiver:
            avoid(.alcohol, 0.9); avoid(.highSugar, 0.7); avoid(.sweet, 0.7); avoid(.fried, 0.5); avoid(.highSatFat, 0.4)
            s += 0.2 * veg + 0.2 * pulses + 0.2 * whole + 0.2 * fish
        case .weightGoal:
            avoid(.fried, 0.5); avoid(.highSatFat, 0.5); avoid(.sweet, 0.6); avoid(.highSugar, 0.4)
            s += 0.4 * veg + 0.3 * pulses
        case .coeliac:
            break
        case .lactoseIntolerance:
            avoid(.dairy, 0.9)
        case .ibs:
            if d.highFODMAP { s -= 0.5 }
            avoid(.spicy3, 0.5); avoid(.fried, 0.3)
        case .reflux:
            avoid(.spicy2, 0.4); avoid(.spicy3, 0.9); avoid(.fried, 0.6); avoid(.highSatFat, 0.5); avoid(.alcohol, 0.5)
        case .ironDeficiency:
            s += 0.3 * pulses + 0.2 * veg + (d.proteins.contains(.redMeat) ? 0.2 : 0)
        case .osteoporosis:
            s += (d.has(.dairy) ? 0.3 : 0) + 0.2 * fish + 0.2 * veg
        case .pregnancy:
            s += 0.2 * veg + 0.2 * pulses
        case .kidneyDisease:
            avoid(.highSalt, 0.8); avoid(.processedMeat, 0.6)
        }
        return s
    }

    /// Per-person tweaks for a dish ("Martin: half portion of rice…").
    public func tips(for dish: Dish) -> [(person: String, tip: String)] {
        var result: [(person: String, tip: String)] = []
        for person in people {
            var seen = Set<String>()
            for condition in person.conditions.sorted(by: { $0.rawValue < $1.rawValue }) {
                if let tip = condition.tip(for: dish), !seen.contains(tip) {
                    seen.insert(tip)
                    result.append((person: person.name, tip: tip))
                }
            }
        }
        return result
    }

    /// Rough carbs per portion when someone has diabetes.
    public func carbsPerPortion(_ dish: Dish, servings: Int = 4) -> Int? {
        guard conditions.contains(where: \.showsCarbs) else { return nil }
        return CarbEstimate.perPortion(ingredients: dish.ingredients, servings: servings)
    }
}

/// Healthy basket warnings for the family's conditions.
public enum BasketHealthCheck {
    public struct Warning: Sendable, Identifiable {
        public let condition: HealthCondition
        public let group: FoodGroup
        public let share: Double
        public var id: String { condition.rawValue + group.rawValue }
    }

    static let thresholds: [FoodGroup: Double] = [
        .processedMeat: 0.06, .readyMeals: 0.08, .sweetsSnacks: 0.10, .sugaryDrinks: 0.05, .alcohol: 0.05
    ]

    public static func warnings(_ report: FoodBalanceReport, conditions: Set<HealthCondition>) -> [Warning] {
        var result: [Warning] = []
        var seenGroups = Set<FoodGroup>()
        for condition in conditions.sorted(by: { $0.rawValue < $1.rawValue }) {
            for group in condition.basketWatch {
                let share = report.share(group)
                guard share >= (thresholds[group] ?? 0.1), !seenGroups.contains(group) else { continue }
                seenGroups.insert(group)
                result.append(Warning(condition: condition, group: group, share: share))
            }
        }
        return result.sorted { $0.share > $1.share }
    }
}
