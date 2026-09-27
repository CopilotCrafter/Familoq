// swift-tools-version:5.9
//
// FamiloqKit - all platform-independent Familoq logic, split per space:
//
//   FamiloqCore    shared by every module: money, currency & exchange rates,
//                  family roles/access rules, invitation codes, text/calendar
//   FamiloqBudget  the Budget space: categories, merchant rules, grocery item
//                  classifier, budgets, warnings, safe-to-spend
//
// Future spaces (FamiloqTravel, FamiloqHealth, FamiloqPlans, ...) become new
// library targets here that depend on FamiloqCore.
//
// Depends ONLY on Foundation, so it builds and tests on:
//   * iOS / macOS (inside the app)
//   * Linux (cheap GitHub Actions runner)
//   * Windows (optional: Swift for Windows toolchain, `swift test`)
//
import PackageDescription

let package = Package(
    name: "FamiloqKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FamiloqCore", targets: ["FamiloqCore"]),
        .library(name: "FamiloqBudget", targets: ["FamiloqBudget"])
    ],
    targets: [
        .target(name: "FamiloqCore"),
        .target(name: "FamiloqBudget", dependencies: ["FamiloqCore"]),
        .testTarget(name: "FamiloqCoreTests", dependencies: ["FamiloqCore"]),
        .testTarget(name: "FamiloqBudgetTests", dependencies: ["FamiloqBudget", "FamiloqCore"])
    ]
)
