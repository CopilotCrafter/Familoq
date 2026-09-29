import XCTest
import FamiloqCore
import FamiloqBudget
@testable import FamiloqHealth

final class CatalogueTests: XCTestCase {
    func testEveryLineParses() {
        XCTAssertEqual(DishCatalogue.all.count, DishCatalogueData.lines.count, "a catalogue line has a typo")
        XCTAssertGreaterThanOrEqual(DishCatalogue.all.count, 200)
        XCTAssertEqual(Set(DishCatalogue.all.map(\.id)).count, DishCatalogue.all.count, "duplicate dish IDs")
        for dish in DishCatalogue.all {
            XCTAssertFalse(dish.proteins.isEmpty, dish.name)
            XCTAssertGreaterThanOrEqual(dish.ingredients.count, 3, dish.name)
            XCTAssertGreaterThan(dish.minutes, 0, dish.name)
            for region in dish.regions {
                XCTAssertTrue(dish.cuisine.regions.contains { $0.code == region }, "\(dish.name): unknown region \(region)")
            }
        }
    }

    func testEveryCuisineHasDishes() {
        for cuisine in Cuisine.allCases {
            XCTAssertGreaterThanOrEqual(DishCatalogue.dishes(for: cuisine).count, 5, cuisine.rawValue)
        }
    }

    func testSeasonMonthsWrap() {
        XCTAssertEqual(DishCatalogue.months("11-2"), [11, 12, 1, 2])
        XCTAssertEqual(DishCatalogue.months("4-6"), [4, 5, 6])
        XCTAssertEqual(DishCatalogue.months(""), [])
    }

    func testDishTraits() {
        let spaetzle = DishCatalogue.all.first { $0.name == "Käsespätzle" }!
        XCTAssertTrue(spaetzle.isVegetarian)
        XCTAssertFalse(spaetzle.isVegan)
        XCTAssertTrue(spaetzle.containsEgg)
        let rajma = DishCatalogue.all.first { $0.name == "Rajma Chawal" }!
        XCTAssertTrue(rajma.isVegan)
        XCTAssertTrue(rajma.hasLegumes)
        XCTAssertNotNil(DishCatalogue.match(title: "rajma chawal"))
    }

    func testCarbEstimate() {
        // 300 g rice (78 g carbs / 100 g) + 2 cans beans (~72 g) for 4.
        let carbs = CarbEstimate.perPortion(ingredients: ["2 Dosen Kidneybohnen", "2 Zwiebeln", "300 g Reis"], servings: 4)
        XCTAssertNotNil(carbs)
        XCTAssertTrue((65...80).contains(carbs!), "\(carbs!)")
        XCTAssertNil(CarbEstimate.perPortion(ingredients: ["2 Zwiebeln", "Salz"], servings: 4))
    }
}

final class CuisineTests: XCTestCase {
    func testAllocationFollowsRank() {
        let prefs = [CuisinePreference(cuisine: .german), CuisinePreference(cuisine: .indian),
                     CuisinePreference(cuisine: .italian), CuisinePreference(cuisine: .thai)]
        let a = CuisinePreference.allocation(prefs, days: 7)
        XCTAssertEqual(a[.german], 3)
        XCTAssertEqual(a[.indian], 2)
        XCTAssertEqual(a[.italian], 1)
        XCTAssertEqual(a[.thai], 1)
        XCTAssertEqual(a.values.reduce(0, +), 7)
    }

    func testSequenceSpreadsCuisines() {
        let prefs = [CuisinePreference(cuisine: .german), CuisinePreference(cuisine: .indian), CuisinePreference(cuisine: .italian)]
        let seq = CuisinePreference.sequence(prefs, days: 7)
        XCTAssertEqual(seq.count, 7)
        for i in 1..<seq.count { XCTAssertNotEqual(seq[i], seq[i - 1], "\(seq)") }
    }

    func testEncodeDecode() {
        let prefs = [CuisinePreference(cuisine: .german, regions: ["by", "bw"]), CuisinePreference(cuisine: .indian, regions: ["kl"]),
                     CuisinePreference(cuisine: .italian)]
        XCTAssertEqual(CuisinePreference.decode(CuisinePreference.encode(prefs)), prefs)
    }
}

final class DietRulesTests: XCTestCase {
    func testCoeliacAndAllergiesAreStrict() {
        let profile = DietProfile(people: [DietPerson(name: "A", conditions: [.coeliac], allergens: [.nuts])])
        for dish in DishCatalogue.all where profile.allows(dish) {
            XCTAssertFalse(dish.has(.gluten), dish.name)
            XCTAssertFalse(dish.has(.nuts), dish.name)
        }
    }

    func testPregnancyExcludesRawLiverAlcohol() {
        let profile = DietProfile(people: [DietPerson(name: "C", conditions: [.pregnancy], allergens: [])])
        let matjes = DishCatalogue.all.first { $0.name == "Matjes Hausfrauenart" }!
        XCTAssertFalse(profile.allows(matjes))
        let bourguignon = DishCatalogue.all.first { $0.name == "Bœuf bourguignon" }!
        XCTAssertFalse(profile.allows(bourguignon))
    }

    func testAvoidWordsAndSpice() {
        let profile = DietProfile(avoidWords: ["Schwein", "Pilze"], maxSpice: 1)
        let carbonara = DishCatalogue.all.first { $0.name == "Spaghetti carbonara" }!
        XCTAssertFalse(profile.allows(carbonara), "pork tag")
        let laalMaas = DishCatalogue.all.first { $0.name == "Laal Maas" }!
        XCTAssertFalse(profile.allows(laalMaas), "too spicy")
        let rajma = DishCatalogue.all.first { $0.name == "Rajma Chawal" }!
        XCTAssertTrue(profile.allows(rajma))
    }

    func testBloodPressurePrefersLowSalt() {
        let profile = DietProfile(people: [DietPerson(name: "M", conditions: [.highBloodPressure], allergens: [])])
        let currywurst = DishCatalogue.all.first { $0.name == "Currywurst mit Ofenkartoffeln" }!
        let lentils = DishCatalogue.all.first { $0.name == "Linseneintopf" }!
        XCTAssertLessThan(profile.fit(currywurst), profile.fit(lentils))
        XCTAssertFalse(profile.tips(for: currywurst).isEmpty)
    }

    func testDiabetesTipAndCarbs() {
        let profile = DietProfile(people: [DietPerson(name: "M", conditions: [.diabetesType2], allergens: [])])
        let biryani = DishCatalogue.all.first { $0.name == "Hyderabadi Chicken Biryani" }!
        XCTAssertEqual(profile.tips(for: biryani).first?.person, "M")
        XCTAssertNotNil(profile.carbsPerPortion(biryani))
        XCTAssertNil(DietProfile().carbsPerPortion(biryani))
    }
}

final class WeekPlannerTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    func week() -> [WeekPlanner.Day] {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        return (0..<7).map { i in
            WeekPlanner.Day(date: calendar.date(byAdding: .day, value: i, to: monday)!, isWeekend: i >= 5)
        }
    }

    func testPlanIsBalancedAndFollowsCuisines() {
        let request = WeekPlanner.Request(
            days: week(),
            cuisines: [CuisinePreference(cuisine: .german, regions: ["by"]), CuisinePreference(cuisine: .indian, regions: ["kl"]),
                       CuisinePreference(cuisine: .italian), CuisinePreference(cuisine: .thai)],
            profile: DietProfile(people: [DietPerson(name: "M", conditions: [.highBloodPressure, .diabetesType2], allergens: [])]),
            vegetarianDays: 2, month: 10, seed: 42)
        let plan = WeekPlanner.plan(request)
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(Set(plan.map(\.dish.id)).count, 7, "no repeats")
        let counts = Dictionary(grouping: plan, by: \.dish.cuisine).mapValues(\.count)
        XCTAssertEqual(counts[.german], 3)
        XCTAssertEqual(counts[.indian], 2)
        XCTAssertGreaterThanOrEqual(plan.filter { $0.dish.hasFish }.count, 1)
        XCTAssertGreaterThanOrEqual(plan.filter { $0.dish.hasLegumes }.count, 2)
        XCTAssertGreaterThanOrEqual(plan.filter { $0.dish.isVegetarian }.count, 2)
        XCTAssertEqual(plan.filter { $0.dish.has(.processedMeat) }.count, 0, "blood pressure: no sausage")
        // Weekdays stay quick.
        for item in plan.prefix(5) { XCTAssertLessThanOrEqual(item.dish.minutes, 75, item.dish.name) }
        // Same seed, same plan.
        XCTAssertEqual(WeekPlanner.plan(request).map(\.dish.id), plan.map(\.dish.id))
    }

    func testBreakfastAndLunchPlans() {
        let cuisines = [CuisinePreference(cuisine: .german), CuisinePreference(cuisine: .indian, regions: ["kl"])]
        let dinners = WeekPlanner.plan(WeekPlanner.Request(days: week(), cuisines: cuisines, profile: DietProfile(), month: 10, seed: 3))
        XCTAssertTrue(dinners.allSatisfy { !$0.dish.has(.breakfast) })
        let breakfasts = WeekPlanner.plan(WeekPlanner.Request(days: week(), cuisines: cuisines, profile: DietProfile(),
                                                              month: 10, seed: 3, slot: .breakfast))
        XCTAssertEqual(breakfasts.count, 7)
        XCTAssertTrue(breakfasts.allSatisfy { $0.dish.has(.breakfast) }, breakfasts.map(\.dish.name).joined(separator: ", "))
        for item in breakfasts.prefix(5) { XCTAssertLessThanOrEqual(item.dish.minutes, 30, item.dish.name) }
        XCTAssertGreaterThanOrEqual(Set(breakfasts.map(\.dish.id)).count, 5, "varied breakfasts")
        let lunches = WeekPlanner.plan(WeekPlanner.Request(days: week(), cuisines: cuisines, profile: DietProfile(),
                                                           alreadyPlanned: dinners.map(\.dish), month: 10, seed: 3, slot: .lunch))
        XCTAssertEqual(lunches.count, 7)
        XCTAssertTrue(lunches.allSatisfy { !$0.dish.has(.breakfast) })
        XCTAssertTrue(Set(lunches.map(\.dish.id)).isDisjoint(with: dinners.map(\.dish.id)), "lunch is not the same as a dinner")
        for item in lunches.prefix(5) { XCTAssertLessThanOrEqual(item.dish.minutes, 60, item.dish.name) }
    }

    func testOutOfSeasonAvoided() {
        let request = WeekPlanner.Request(days: week(), cuisines: [CuisinePreference(cuisine: .german, regions: ["ni"])],
                                          profile: DietProfile(), month: 12, seed: 1)
        for item in WeekPlanner.plan(request) {
            XCTAssertTrue(item.dish.isInSeason(month: 12), item.dish.name)
        }
    }

    func testRecentAndAlternatives() {
        var request = WeekPlanner.Request(days: Array(week().prefix(1)), cuisines: [CuisinePreference(cuisine: .indian)],
                                          profile: DietProfile(), month: 10, seed: 7)
        let first = WeekPlanner.plan(request).first!.dish
        request.recentDishIDs = [first.id]
        XCTAssertNotEqual(WeekPlanner.plan(request).first!.dish.id, first.id)
        let alternatives = WeekPlanner.alternatives(for: week()[0], request: request, excluding: [first.id])
        XCTAssertEqual(alternatives.count, 6)
        XCTAssertFalse(alternatives.contains { $0.id == first.id })
    }

    func testBalanceScore() {
        let good = ["Linseneintopf", "Lachs mit Ofengemüse", "Rajma Chawal", "Ratatouille", "Minestrone"]
            .compactMap { name in DishCatalogue.all.first { $0.name == name } }.map(MealTraits.init(dish:))
        let poor = ["Currywurst mit Ofenkartoffeln", "Schnitzel mit Kartoffelsalat", "Leberkäs mit Kartoffelsalat", "Rostbratwurst mit Sauerkraut"]
            .compactMap { name in DishCatalogue.all.first { $0.name == name } }.map(MealTraits.init(dish:))
        let a = MealPlanBalance.check(good)!, b = MealPlanBalance.check(poor)!
        XCTAssertGreaterThan(a.score, b.score)
        XCTAssertTrue(b.notes.contains(.noFish))
        XCTAssertNil(MealPlanBalance.check([]))
        let traits = MealTraits(ingredients: ["300 g Lachs", "2 Zucchini", "1 Brokkoli"])
        XCTAssertTrue(traits.fish)
        XCTAssertTrue(traits.vegetableRich)
    }
}

final class PlateAndScheduleTests: XCTestCase {
    let calendar = Calendar(identifier: .gregorian)

    func testPlateGuess() {
        XCTAssertEqual(PlatePart.guess(label: "french_fries"), .fried)
        XCTAssertEqual(PlatePart.guess(label: "salad"), .vegetables)
        XCTAssertEqual(PlatePart.guess(label: "Bratwurst"), .processedMeat)
        XCTAssertEqual(PlatePart.guess(label: "brown rice"), .wholegrain)
        XCTAssertEqual(PlatePart.guess(label: "rice"), .refinedCarbs)
        XCTAssertEqual(PlatePart.guess(label: "grilled salmon"), .leanProtein)
        XCTAssertNil(PlatePart.guess(label: "table"))
    }

    func testPlateScore() {
        let healthy = PlateScore.evaluate([.vegetables: 5, .leanProtein: 2.5, .wholegrain: 2.5])
        let poor = PlateScore.evaluate([.fried: 4, .processedMeat: 3, .refinedCarbs: 3], conditions: [.highBloodPressure])
        XCTAssertGreaterThanOrEqual(healthy.score, 90)
        XCTAssertLessThan(poor.score, 30)
        XCTAssertTrue(poor.notes.contains(.moreVegetables))
        XCTAssertTrue(poor.concerns.contains { $0.0 == .highBloodPressure && $0.1 == .processedMeat })
        XCTAssertTrue(healthy.notes.contains(.great))
    }

    func testChildExamsAndDue() {
        let birth = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let next = ChildExam.next(birthDate: birth, done: ["U3", "U4", "U5", "U6"], now: now, calendar: calendar)
        XCTAssertEqual(next?.exam.name, "U7")
        let last = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        XCTAssertEqual(HealthDue.next(after: last, months: 6, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        XCTAssertNil(HealthDue.next(after: last, months: 0, calendar: calendar))
    }

    func testRefill() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let runOut = Refill.runOutDate(stock: 30, perDay: 2, from: start, calendar: calendar)
        XCTAssertEqual(runOut, calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        XCTAssertEqual(Refill.remaining(stock: 30, perDay: 2, from: start, now: later, calendar: calendar), 20)
    }

    func testBasketWarnings() {
        let purchases = [
            FoodPurchase(name: "Bratwurst", amount: 12, subcategoryKey: nil, date: Date()),
            FoodPurchase(name: "Salami", amount: 8, subcategoryKey: nil, date: Date()),
            FoodPurchase(name: "Brokkoli", amount: 10, subcategoryKey: nil, date: Date()),
            FoodPurchase(name: "Äpfel", amount: 10, subcategoryKey: nil, date: Date()),
            FoodPurchase(name: "Haferflocken", amount: 10, subcategoryKey: nil, date: Date())
        ]
        let report = FoodBalance.report(purchases)
        let warnings = BasketHealthCheck.warnings(report, conditions: [.highBloodPressure])
        XCTAssertEqual(warnings.first?.group, .processedMeat)
        XCTAssertTrue(BasketHealthCheck.warnings(report, conditions: [.coeliac]).isEmpty)
    }
}
