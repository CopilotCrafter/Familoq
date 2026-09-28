# 07 - Roadmap

Familoq = the family's shared space. Each **space** is a module on a shared core.

```
                ┌──────────────── Familoq app ────────────────┐
 Spaces:        │ Budget │ Shopping │ Reminders │ Events │ Travel │ Health
                ├──────────────────────────────────────────────┤
 Shared core:   │ invitations · families · members · roles     │
                │ family-scoped storage · CloudKit family zone │
                │ currency & rates · calendar · privacy        │
                └──────────────────────────────────────────────┘
```

## Budget space - phases

| Phase | Scope | Status |
|---|---|---|
| **1** | SwiftUI project, XcodeGen, CI/CD, SwiftData, categories & subcategories, manual & quick expenses, multi-currency (EUR base), dashboard, budgets, warnings, safe-to-spend, basic reports | **done** (TestFlight 0.1.0) |
| **2** | Receipt scanning (VisionKit document camera + photo import), on-device OCR (Vision), receipt parsing (merchant, date & time, total, currency, VAT, items, discounts, quantities), item-level grocery categorisation, confirmation screen, "categorise entire receipt", receipt storage | **done** (0.2.0) |
| **3** | Invitation gate, App Invitations in the CloudKit public database, in-app Administration, iCloud identity, restore/revoke, family creation, owner/member permissions | **done** (0.2.0) |
| **4** | CloudKit family zones + CKSyncEngine, offline queue, last-writer-wins, restore after reinstall, family invitations by Apple Account (CKShare), join / leave / remove / delete, family switcher; receipts from any country (currency detection, asks when unclear) | **done** (0.3.0) - see docs/10 |
| **5** | Recurring & planned expenses (booked automatically, reserved in Safe to spend), savings goals, search & filters, reports (year, 12 months, custom range, trend, per member, budget vs actual), CSV export, family backup & restore, German language | **done** (0.4.0) - see docs/12 |
| **Planner** | Shopping list (receipt tick-off), family reminders, family calendar, local notifications, background refresh | **done** (0.5.0) - see docs/13 |
| 6 | TestFlight external beta, security test run, accessibility, performance, error handling, App Store submission | |

Each phase follows: implement -> build -> test -> fix -> commit -> explain -> how to test from Windows/iPhone.

## Adding a new space later (e.g. Travel)

1. `Packages/FamiloqKit/Sources/FamiloqTravel/` - pure logic, tests in `Tests/FamiloqTravelTests/`; add the target to `Package.swift`.
2. `Familoq/Modules/Travel/` - SwiftData models (with `familyID`), views, services.
3. `enum TravelModule: FamiloqModule` - declares models and default seed data.
4. Register it in `FamiloqModules.enabled` and flip `FamiloqSpace.travel.isAvailable`.
5. Navigation: when a second space ships, the tab bar becomes *Home · Budget · Spaces · Family* (decided then; today's five budget tabs stay unchanged until there is something to switch to).

Spaces reuse invitations, family membership, sharing and sync - nothing is rebuilt per space. A trip's expenses can later be booked into the Budget space in the trip's currency, using the same conversion engine.
