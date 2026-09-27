# 07 - Roadmap

Familoq = the family's shared space. Each **space** is a module on a shared core.

```
                ┌──────────────── Familoq app ────────────────┐
 Spaces:        │ Budget │ Travel │ Health │ Plans │ Reminders │ Events
                ├──────────────────────────────────────────────┤
 Shared core:   │ invitations · families · members · roles     │
                │ family-scoped storage · CloudKit family zone │
                │ currency & rates · calendar · privacy        │
                └──────────────────────────────────────────────┘
```

## Budget space - phases

| Phase | Scope | Status |
|---|---|---|
| **1** | SwiftUI project, XcodeGen, CI/CD, SwiftData, categories & subcategories, manual & quick expenses, multi-currency (EUR base), dashboard, budgets, warnings, safe-to-spend, basic reports | **built - verify via CI** |
| 2 | Receipt scanning (VisionKit document camera), OCR (Vision), receipt parsing (merchant, date & time, total, currency, VAT, items), item-level grocery categorisation (classifier ready), confirmation screen, "categorise entire receipt as Groceries", receipt storage | next |
| 3 | Sign in with Apple, invitation gate, App Invitation service, family creation, family invitations, membership, authorisation | |
| 4 | CloudKit family zones + CKSyncEngine, offline queue, conflict handling, restore | |
| 5 | Recurring & planned expenses (reserved in safe-to-spend), savings goals, full reports (trends, budget vs actual, custom range), search & filters, JSON/CSV export/import | |
| 6 | TestFlight external beta, security test run, accessibility, performance, error handling, App Store submission | |

Each phase follows: implement -> build -> test -> fix -> commit -> explain -> how to test from Windows/iPhone.

## Adding a new space later (e.g. Travel)

1. `Packages/FamiloqKit/Sources/FamiloqTravel/` - pure logic, tests in `Tests/FamiloqTravelTests/`; add the target to `Package.swift`.
2. `Familoq/Modules/Travel/` - SwiftData models (with `familyID`), views, services.
3. `enum TravelModule: FamiloqModule` - declares models and default seed data.
4. Register it in `FamiloqModules.enabled` and flip `FamiloqSpace.travel.isAvailable`.
5. Navigation: when a second space ships, the tab bar becomes *Home · Budget · Spaces · Family* (decided then; today's five budget tabs stay unchanged until there is something to switch to).

Spaces reuse invitations, family membership, sharing and sync - nothing is rebuilt per space. A trip's expenses can later be booked into the Budget space in the trip's currency, using the same conversion engine.
