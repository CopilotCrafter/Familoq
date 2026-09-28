# Changelog

## 0.5.3 - Healthy basket

### Added
- Reports → Healthy basket: a 0-100 score for how balanced the food shopping of a period is (whole family or one person), compared with the previous period and over the last 6 months.
- What was bought by food group (vegetables, fruit, wholegrain, dairy, fish, … and sweets, soft drinks, alcohol, sausage, ready meals highlighted in orange).
- Nutrients (protein, fibre, vitamins & minerals, calcium, omega-3) estimated from the food groups, with ideas that can be put on the shopping list with one tap.
- "Better less often": the biggest less healthy purchases with a swap idea; optional tips from Apple Intelligence.
- Honest note: estimated from what was bought and its price, not medical or nutrition advice.

## 0.5.2 - Better receipt filing

### Added
- Familoq learns: change an item's category on the check screen and the same item is filed that way on the next receipt, for the whole family (green seal icon). Learned items: Family → Merchant rules.
- Apple Intelligence (iOS 26+, on the iPhone) files receipt items the built-in keywords don't know (sparkles icon).
- Edit a saved receipt: Scan → receipt → Edit (items, amounts, categories, total); its expenses are updated.

### Fixed
- Photos taken at an angle: prices no longer slip to the next item (the tilt of the text lines is measured and removed).
- More German receipt words: Blätterteig, Pudd., Direktsaft (not grapes), Knotenbeutel, Landmilch, Ministeaks, Teebeutel, …
- "2,672 kg x 1,99 EUR/kg" lines are read as the weight of the item above.

## 0.5.1 - Deeper reports

### Added
- Reports per person: choose a person at the top, or tap a person under "By member" - every section then shows only their spending.
- Top subcategories across all categories (e.g. Meat & Poultry, Vegetables, Fuel) with the change against the previous period; tap for the expenses behind it. Category drill-down shows the change per subcategory.
- Biggest changes (largest increases and decreases) and top shops.
- Insights: built-in summary lines, plus "Explain with Apple Intelligence" (iOS 26+, on-device, nothing leaves the iPhone) in the app's language.

## 0.5.0 - Planner

### Added
- Planner tab with a shared shopping list (amounts like "2x Milk", supermarket sections, Buy again, several lists), family reminders (due date/time, repeats, for whom, overdue/today/upcoming) and a family calendar (month view, all-day and multi-day events, birthdays, repeats, participants, alerts).
- Scanning a receipt ticks the bought items off the shopping list.
- Local notifications for reminders, events and bills due tomorrow (Family → Notifications); background refresh so alerts also arrive when Familoq is closed. No new certificate or capability needed.
- Dashboard "Today" section; Reports now open from the dashboard's chart button.
- After updating, Planner entries made on another iPhone before the update are fetched once.


## 0.4.1

### Added
- Member rights: the owner taps a member (Family → Members) and allows budgets, categories & merchant rules, family name & base currency, or editing everyone's expenses. Enforced on the owner's iPhone during sync, so a member cannot give themselves rights.
- Change your name: tap your own name in Members; "Use iCloud name" takes the name of your Apple Account (known once the family is shared - no extra permission). An old placeholder name "Me" is replaced automatically.

### Fixed
- Family → Categories crashed on iOS 27 (screens are now built only when opened; the category editor keeps its own state and saves when you leave it).

## 0.4.0 - Phase 5

### Added
- Recurring expenses (weekly, every 2 weeks, monthly, quarterly, yearly) and planned one-offs: booked automatically on the due date for the whole family (no duplicates across iPhones), upcoming dates reserved in Safe to spend, "Upcoming (30 days)" on the dashboard.
- Savings goals with target, deadline, monthly amount needed, add/take out money, history; optional reservation in Safe to spend.
- Expense search (every word, amounts like "12,50") and filters: period, categories, members, amount range, how it was entered, other currencies; filtered total.
- Reports: this year, last 12 months, custom range; 12-month trend chart with average; spending per member; budget vs actual.
- Export & backup: CSV for Excel/Numbers (German Excel format when the iPhone uses a decimal comma), full family backup file (optionally with receipt photos), restore into the family (other families untouched).
- German language: whole app follows the iPhone's language; built-in category names are renamed to German by the family's owner.

### Fixed (0.3.x builds)
- Receipt check screen froze on iOS 27 (screen now owns its data and opens full screen).

## 0.3.0 - Phase 4

### Added
- iCloud sync with CKSyncEngine: every family in its own CloudKit zone, offline queue, last writer wins, restore after reinstall / on a new iPhone.
- Shared families: invite by Apple Account e-mail or phone (link works only for that person), join by link, choose your name, withdraw invitations, remove members, leave or delete a family, switch between families.
- Owner-only settings enforced on the owner's iPhone for changes arriving from iCloud.
- Receipts from any country: currency detection (ISO codes, symbols, phone prefixes, web addresses, tax names), "Which currency is this receipt in?" when unclear, whole-amount currencies (JPY, KRW, HUF …), year-first dates, multilingual totals, automatic OCR language detection.

### Changed
- Family invitation codes replaced by iCloud family invitations.
- CloudKit setup: one extra record type `FQFamilyItem` (docs/10).

## 0.2.0 - Phases 2 and 3

### Added
- Receipt scanning: VisionKit camera, photo import, on-device Vision OCR, receipt parser (merchant, date & time, total, currency, VAT, items, discounts, quantities), review screen, item-level or whole-receipt categorisation, receipt storage linked to expenses.
- Invite-only access: onboarding (invitation code, request, restore), App Invitations in the CloudKit public database (one-time use, expiry, revocation), iCloud account as identity, daily check.
- In-app Administration (FamiloqAdmin role): create codes, revoke codes and accounts, invitation requests.
- Family setup (create family), owner/member permission checks, family invitation codes.
- CI: compiler errors and failed tests shown as annotations; onboarding screenshot.

## 0.1.0 - Phase 1 (2026-09-27)

### Added
- Familoq app shell: 5 tabs (Dashboard, Add, Scan, Reports, Family), module architecture (`FamiloqSpace`, `FamiloqModule`) with Budget as the first space.
- Local offline-first SwiftData store; all records carry `familyID`; family-scoped `FamilyRepository`.
- Default categories (14) and grocery subcategories (18); owner can rename, add, archive.
- Quick and detailed expense entry, optional receipt photo, recent combinations.
- Merchant rules (built-in + "Always categorize this merchant this way?").
- Multi-currency: EUR default base, switchable; ECB rate of the expense date via Frankfurter; offline estimate/pending; manual rate.
- Budgets (daily/weekly/monthly × family/category/subcategory), 75/90/100 % warnings, safe-to-spend with explanation.
- Reports: category breakdown, subcategory drill-down, previous-period comparison.
- FamiloqKit package (FamiloqCore, FamiloqBudget) with Linux-runnable tests; grocery item classifier; invitation code format.
- XcodeGen project, GitHub Actions: build, test (+ screenshots), release to TestFlight.
- Documentation for the no-Mac workflow, Apple setup, CI/CD, CloudKit design, currency, security tests.
