import XCTest
import FamiloqCore
@testable import FamiloqBudget

final class FoodBalanceTests: XCTestCase {
    let day = Date(timeIntervalSince1970: 1_790_000_000)

    func p(_ name: String, _ amount: String, _ key: String? = nil, _ date: Date? = nil) -> FoodPurchase {
        FoodPurchase(name: name, amount: Decimal(string: amount)!, subcategoryKey: key, date: date ?? day)
    }

    func testGroupsFromNamesAndSubcategories() {
        let cases: [(String, String?, FoodGroup)] = [
            ("Hähn. Minist. XXL", "groceries.meat", .meat),
            ("Salami Classic", "groceries.meat", .processedMeat),
            ("Landmilch 3,8%", "groceries.dairy", .dairy),
            ("Traubendirektsa 1l", "groceries.beverages", .sugaryDrinks),
            ("Pfand", "groceries.beverages", .nonFood),
            ("Nektarinen 1kg", "groceries.fruits", .fruits),
            ("Weintrauben hell", nil, .fruits),
            ("Rotwein trocken", nil, .alcohol),
            ("Schweinefilet", nil, .meat),
            ("Milchschokolade", nil, .sweetsSnacks),
            ("Vollkornbrot", "groceries.bakery", .wholeGrains),
            ("Blätterteig,275g", "groceries.bakery", .grains),
            ("Rote Linsen", nil, .legumesNuts),
            ("Räucherlachs", nil, .fish),
            ("TK Pizza Salami", "groceries.frozen", .processedMeat),
            ("Mineralwasser", nil, .drinks),
            ("Teebeutel Minze", nil, .drinks),
            ("Küchenrolle", nil, .nonFood),
            ("Speisezwiebeln rot", nil, .vegetables),
            ("Brokkoli", "groceries.other", .vegetables)
        ]
        for (name, key, expected) in cases {
            XCTAssertEqual(FoodGroupClassifier.group(name: name, subcategoryKey: key), expected, name)
        }
    }

    func testAldiBasket() {
        let basket = [
            p("Hähn. Minist. XXL", "6.99", "groceries.meat"), p("Hähn. Minist. XXL", "6.99", "groceries.meat"),
            p("Blätterteig,275g", "0.95", "groceries.bakery"), p("Knoblauch fri Stk", "1.29", "groceries.vegetables"),
            p("Blätterteig,275g", "0.95", "groceries.bakery"), p("Speisezwiebeln rot", "1.29", "groceries.vegetables"),
            p("Landmilch 3,8%", "1.19", "groceries.dairy"), p("Pfand", "0.25", "groceries.beverages"),
            p("Traubendirektsa 1l", "1.49", "groceries.beverages"),
            p("High Protein Pudd", "0.59", "groceries.dairy"), p("High Protein Pudd", "0.59", "groceries.dairy"),
            p("High Protein Pudd", "0.59", "groceries.dairy"), p("High Protein Pudd", "0.59", "groceries.dairy"),
            p("Nektarinen 1kg", "1.99", "groceries.fruits"), p("Mandarinen pre los", "5.32", "groceries.fruits"),
            p("Obstknotenbeutel", "0.02", "groceries.household")
        ]
        let report = FoodBalance.report(basket)
        XCTAssertEqual(report.foodTotal, Decimal(string: "30.81"))
        XCTAssertEqual(report.freshVariety, 4)
        XCTAssertEqual(report.level(.omega3), .missing, "no fish, no nuts")
        XCTAssertEqual(report.level(.protein), .good)
        XCTAssertEqual(report.level(.fibre), .low, "no wholegrain or pulses")
        XCTAssertEqual(report.lessHealthyItems.map(\.name), ["Traubendirektsa 1l"])
        let score = try? XCTUnwrap(report.score)
        XCTAssertNotNil(score)
        XCTAssertTrue((40...80).contains(score ?? -1), "score \(score ?? -1)")
    }

    func testSweetsAndSodaLowerTheScore() {
        let healthy = [p("Brokkoli", "2", nil), p("Äpfel", "3", nil), p("Karotten", "1.5", nil), p("Lachs", "5", nil),
                       p("Vollkornbrot", "2.5", nil), p("Joghurt", "1", "groceries.dairy"), p("Eier 10", "2.5", nil), p("Paprika", "2", nil)]
        let junk = healthy + [p("Cola 1,5l", "4", nil), p("Chips Paprika", "6", nil), p("Milchschokolade", "5", nil), p("Salami", "4", nil)]
        let good = FoodBalance.report(healthy)
        let worse = FoodBalance.report(junk)
        XCTAssertGreaterThan(good.score ?? 0, 75)
        XCTAssertLessThan(worse.score ?? 100, good.score ?? 0)
        XCTAssertEqual(worse.lessHealthyItems.first?.name, "Chips Paprika")
        XCTAssertGreaterThan(worse.lessHealthyShare, 0.3)
    }

    func testTooLittleDataHasNoScore() {
        XCTAssertNil(FoodBalance.report([p("Milch", "1.19", "groceries.dairy"), p("Brot", "2", nil)]).score)
    }

    func testMonthlyScores() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
        let aug = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let basket = ["Brokkoli", "Äpfel", "Karotten", "Lachs", "Vollkornbrot", "Paprika"].map { p($0, "4", nil, aug) }
        let months = FoodBalance.monthlyScores(basket, months: 3, endingAt: now, calendar: calendar)
        XCTAssertEqual(months.count, 3)
        XCTAssertNil(months[0].score)
        XCTAssertNotNil(months[1].score)
        XCTAssertNil(months[2].score)
    }
}
