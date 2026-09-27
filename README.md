# Familoq

**Your family's private space.** Familoq starts as an invite-only family budgeting app for iPhone and is designed to grow into a shared family space: budget today; travel, health, plans, reminders and events later.

Built with Swift, SwiftUI and SwiftData - and developed **entirely without a Mac**:

```
Windows PC ──push──▶ GitHub ──▶ GitHub Actions (cloud macOS) ──▶ build · test · sign ──▶ TestFlight ──▶ iPhone
```

| | |
|---|---|
| **Status** | Phases 1-3 of 6 - budgeting, receipt scanning, invite-only access |
| **Platform** | iOS 17+ (iPhone) |
| **Base currency** | EUR by default, switchable per family; foreign expenses converted with the ECB rate of the receipt/entry date |
| **Privacy** | No ads, no tracking, no analytics, no third-party SDKs |

## Start here

1. **[docs/00-START-HERE.md](docs/00-START-HERE.md)** - exact checklist of what to create on Windows, GitHub and Apple.
2. [docs/01-no-mac-strategy.md](docs/01-no-mac-strategy.md) - why this works, what it costs, alternatives.
3. [docs/02-apple-account-and-signing.md](docs/02-apple-account-and-signing.md) - Apple ID, Developer Program, App Store Connect, bundle ID, certificates, provisioning, TestFlight, production - all from Windows.
4. [docs/03-github-ci-cd.md](docs/03-github-ci-cd.md) - repository layout, workflows, secrets, daily loop, minute budget.
5. [docs/04-families-invitations-cloudkit.md](docs/04-families-invitations-cloudkit.md) - invite-only access, family isolation, CloudKit design (Phases 3-4).
6. [docs/05-currency.md](docs/05-currency.md) - base currency and conversion rules.
7. [docs/06-security-test-plan.md](docs/06-security-test-plan.md) - the 12 security scenarios and where each is tested.
8. [docs/07-roadmap.md](docs/07-roadmap.md) - phases, and how new spaces plug in.
9. [docs/08-automatic-delivery.md](docs/08-automatic-delivery.md) - push to `main` -> TestFlight; tag `vX.Y.Z` -> App Store review.
10. [docs/09-invitations-cloudkit.md](docs/09-invitations-cloudkit.md) - App Invitations in CloudKit: setup and administration.

## Costs at a glance

| Item | Cost | Needed for |
|---|---|---|
| Windows PC, VS Code, Git | Free | Writing code |
| GitHub repository | Free | Source code |
| GitHub Actions - public repo | Free (standard runners) | Builds & tests |
| GitHub Actions - private repo | Free allowance, then pay per minute (macOS is the expensive part) | Builds & tests |
| XcodeGen, Frankfurter exchange-rate API | Free | Project generation, currency rates |
| **Apple Developer Program** | **99 USD/year** (charged in local currency) - **unavoidable** | TestFlight, App Store, signing, CloudKit |
| iCloud / CloudKit (Phase 4) | Included with Apple's developer program; users' data counts against their iCloud storage | Sync & restore |
| Mac | **Not required** | - |

Details and current numbers: [docs/01-no-mac-strategy.md](docs/01-no-mac-strategy.md).

## Repository layout

```
Familoq/                          iOS app (SwiftUI + SwiftData)
├── App/                          app entry, session, tab bar
├── Core/                         shared by every space
│   ├── Models/                   Family, FamilyMember
│   ├── Persistence/              ModelContainer, FamilyRepository (family-scoped data access)
│   ├── Family/                   family settings & members
│   ├── Authentication/           invitation gate, CloudKit invitation store, Admin screen
│   ├── Modules/                  FamiloqSpace + FamiloqModule plug-in contract
│   └── Views/                    shared UI components
├── Modules/
│   └── Budget/                   the Budget space
│       ├── Models/               Expense, Budget, categories, merchant rules, rate cache
│       ├── Expenses/             quick & detailed entry, list, currency picker
│       ├── Budget/               dashboard, budgets, safe-to-spend
│       ├── Reports/              category breakdown, drill-down
│       ├── Receipts/             Phase 2: scanning
│       ├── Services/             exchange rates, base currency, categorisation, demo data
│       ├── Persistence/          budget queries (still family-scoped)
│       ├── ViewModels/           spending summaries, budget progress
│       └── Views/                budget components & settings
└── Resources/                    assets, app icon, privacy manifest
FamiloqTests/                     app tests (iOS Simulator)
Packages/FamiloqKit/              pure-Swift logic, tested on Linux too
├── Sources/FamiloqCore/          money, currency, exchange rates, access policy, invitation codes
├── Sources/FamiloqBudget/        categories, merchant rules, grocery classifier, budgets, safe-to-spend
└── Tests/                        FamiloqCoreTests, FamiloqBudgetTests
Config/App.xcconfig               bundle ID, version, signing variables
project.yml                       XcodeGen spec (the .xcodeproj is generated in CI)
scripts/ci/                       CI helper scripts
.github/workflows/                build.yml · test.yml · release.yml
fastlane/Fastfile                 App Store submission (runs on CI only)
docs/                             everything you need to operate the project
```

## Everyday workflow (from Windows)

```powershell
git pull
code .                                    # edit Swift files in VS Code
git add -A
git commit -m "Describe the change"
git push                                  # -> GitHub Actions builds & tests automatically
```

- **Green check** on GitHub = it compiles and all tests pass.
- **Actions -> Test -> Run workflow** = full tests + iPhone simulator **screenshots** you can download.
- **Merge to `main`** = new TestFlight build automatically once Build is green; **tag `vX.Y.Z`** = submitted for App Store review (see doc 08).

## Phase 2 - receipts
- Scan with the VisionKit document camera (multi-page) or import a photo
- On-device OCR (Vision, German + English); nothing leaves the iPhone
- Recognises merchant, date & time, total, currency, VAT, items, discounts, quantities, deposit (Pfand)
- Review screen: correct everything; item-level grocery subcategories or "categorize entire receipt"
- Receipt image + items stored; expenses grouped per subcategory and linked to the receipt
- Foreign receipts converted with the ECB rate of the receipt date

## Phase 3 - invite-only access & families
- First screen: Enter Invitation Code · Request an Invitation · About - no sign-up, no guest mode
- App Invitations stored in the CloudKit public database; one-time use enforced by iCloud (docs 09)
- Identity = the iCloud account; reinstall / new iPhone restores access automatically; revoked accounts are signed out
- In-app Administration for you: create codes, revoke codes or people, read invitation requests
- Create your family (name, your name, base currency); owner/member permissions enforced
- Family invitation codes (7 days, single use); joining completes with iCloud sync in Phase 4

## Phase 1 features

- Local, offline-first SwiftData storage; every record carries a `familyID`
- 14 default categories incl. 18 grocery subcategories; owners can rename/add/archive
- Quick expense (amount + category in seconds, recent combinations remembered)
- Detailed expense (amount, currency, merchant, date & time, category, subcategory, member, payment method, note, optional receipt photo)
- Merchant auto-categorisation (130+ built-in German-market merchant patterns) and "Always categorize this merchant this way?"
- Multi-currency: EUR base by default, switchable; foreign expenses converted automatically with the ECB reference rate of the expense date; offline-safe; manual rate override
- Budgets: daily / weekly / monthly, family / category / subcategory; warnings at 75 / 90 / 100 %
- Dashboard with spent, remaining and **Safe to spend** per day/week, with an explanation of the maths
- Reports: category breakdown, subcategory drill-down, comparison with previous period
- Grocery item classifier (Phase 2 foundation) and invitation-code format (Phase 3 foundation), both tested

## Licence

Private project. All rights reserved.
