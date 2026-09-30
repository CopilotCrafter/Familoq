# Changelog

## 0.9.0 - Cars and document vault

### Added
- Planner → Cars: every family car with what it really costs - fuel with liters, km and l/100 km (kWh for electric cars), service, repairs, tyres, TÜV, insurance, vehicle tax, parking, tolls and washing. Cost per km, average fuel price, monthly average, a log per car.
- Car costs are normal budget expenses (Transport): add them on the car, in any expense (new "Car" section) or book insurance and vehicle tax as a contract of the car.
- Scanned fuel receipts ask which car (the car you used last is suggested) and take the liters from the receipt; add the km reading for the consumption.
- Reminders: TÜV 30 and 7 days before, service 14 days before, tyre change on 10 October and 10 April. Only the car's drivers get them.
- Planner → Documents: the family document vault - passports, ID cards, driving licences, birth and marriage certificates, insurance policies, car registration, certificates, medical and tax documents. Scan with the camera, choose photos or import PDFs.
- Always opens with Face ID (or the passcode). Shared with the family through iCloud, or "Only on this iPhone" per document.
- Download / Share as PDF and Save to Files for every document.
- Reminders before documents expire (passports and ID cards 90 and 30 days before).
- Dashboard: cars with their monthly cost and next due date, documents that expire soon.

## 0.8.2 - Breakfast & lunch plans, family in Health

### Added
- "Plan my week" also plans breakfast and lunch when they are switched on (Planner → Meals, bottom): about 40 breakfasts from all cuisines (quick on weekdays), lunches that are quick or good for a lunchbox and never the same dish as a dinner.
- Swap and the dish catalogue show breakfasts for breakfast and meals for lunch/dinner.

### Changed
- Health lists every family member automatically; tap one to add their conditions and allergies.

## 0.8.1 - Better receipt reading

### Fixed
- Receipts photographed curled or unevenly (e.g. REWE with a separate price column): when the items don't add up to the total, the prices are paired with the names in order - items, amounts and the total come out right.
- Total found even when the "Summe" line is not read (it is printed several times on the card slip / VAT table).
- Weighed items where the name is on one line and the total on the weight line (Lidl, Kaufland), "2 x 0,79 1,58" lines (EDEKA), fuel litres (Aral), coupons with "PAYBACK", kg amounts like 1,254.
- Shop names like "Bäckerei Mustermann" are recognised.
- Tested with typical receipts of REWE, Lidl, ALDI Süd/Nord, EDEKA, Kaufland, Netto, Penny, dm, Rossmann, Norma, Aral and a bakery - flat, curled and tilted.

## 0.8.0 - Meals by cuisine, Health tab

### Added
- Planner → Meals → Meal settings: rank 3-4 cuisines (German, Indian, Italian, Greek, Turkish, Lebanese, Chinese, Japanese, Korean, Thai, Vietnamese, Mexican, Spanish, French) with 1-2 regions each (German and Indian by state); vegetarian days, weekday cooking time, spice level, kid-friendly, "never suggest" list.
- Built-in dish catalogue (over 200 dishes with ingredients for 4) and "Plan my week": follows the cuisine ranking (about 3/2/1/1), balances fish, pulses and vegetarian days, no repeats from the last 3 weeks, quick on weekdays, seasonal, prefers what is at home and what the family rated well.
- Per meal: swap for another suggestion, thumbs up/down per person, guests (servings scale the shopping list), "Cook double" adds tomorrow's leftovers, lunchbox ideas, tips per person for their health conditions, rough carbs per portion for diabetes.
- Week balance score for the planned meals.
- At home (pantry): items with use-by reminders, add food from recent receipts, "Cook with what's at home"; the shopping list skips what is at home.
- Recipes: steps, import from a website link or a cookbook photo, cooking mode (step by step, screen stays on, timers), steps written by Apple Intelligence.
- New Health tab: a profile per person (members, children, relatives) with health conditions (blood pressure, diabetes, cholesterol, triglycerides, thyroid/Hashimoto's, gout, fatty liver, weight, coeliac, lactose, IBS, reflux, iron, osteoporosis, pregnancy, kidney disease, heart disease) and allergies that shape the meal plan; "Only on this iPhone" per person.
- Check-ups with intervals and appointments, children's U/J exams by age, vaccinations with boosters (STIKO intervals, flu each October, travel vaccines linked to trips), medications with daily reminders and a refill reminder, measurements with charts and a PDF report for the doctor.
- Health costs per person and year with a tax-relevant mark (außergewöhnliche Belastungen) and a shareable list; insurance refunds (to send in / waiting / refunded); doctors & contacts with 112, 116 117 and the pharmacy emergency search; emergency cards behind Face ID.
- Plate check: photo of a plate, foods suggested on the iPhone and corrected by you, plate balance score with notes for the family's conditions.
- Time off: "Sick" type (not taken from the allowance), sick days per person, reminder to send the sick note (AU).
- Healthy basket and meal plan use everyone's health settings.

### Changed
- Family & settings moved to the button at the top left of the Dashboard; the Health tab took its place in the tab bar.

## 0.7.0 - Fixed costs, contracts, meals, travel, Siri, Face ID

### Added
- Dashboard → Fixed costs: what the family pays every month for recurring expenses and contracts (yearly and quarterly payments spread over the months), per category and per year.
- Contracts: term, notice period and renewal; reminders 30/14/7 days before the cancellation deadline and on the day; ready-to-send cancellation letter; optional booking as a recurring expense.
- Warranties: add one from a receipt or by hand; reminder 30 days before it ends.
- Family → Import bank statement: CSV export of any bank; columns guessed and remembered per bank; payments already in Familoq are skipped; no duplicates on re-import.
- Planner → Meals: week plan (dinner, optionally lunch and breakfast), recipes with ingredients, "Put this week's ingredients on the shopping list" (amounts added up), dinner ideas from Apple Intelligence.
- Planner → Travel: trips with budget, expenses in any currency, "Settle up" with friends who don't have the app, packing list, calendar entry and time off.
- Siri & Shortcuts: add to the shopping list, log an expense, spending this month, family reminder (English and German phrases).
- Family → Face ID lock: whole app or only Storage & Backup, lock delay, amounts hidden in the app switcher.
- Planner sections are now chips (Shopping, Meals, Reminders, Calendar, Time off, Travel).

## 0.6.0 - Time off, holidays, storage

### Added
- Calendar: public holidays calculated on the iPhone - country from the App Store account (changeable), optional state (all 16 German states; nationwide holidays when no state is set). Saturday, Sunday and holidays in the same red.
- Planner → Time off: per person vacation, half day, bridge day, company closure, training; yearly allowance with used/left; days per person for any period (weekends and holidays not counted); "Off together" overlaps; coloured bars per person in the month view.
- Family → Storage: space used on this iPhone and in your iCloud, photos by year, largest photos; "Make photos smaller"; "Keep receipt photos" (Forever by default, 2 years, 1 year, 6 months); archive a year as PDF or ZIP; "Keep photo" pin for warranty/tax receipts.
- New receipt photos are stored in grayscale at 1,600 px (about half the size); photos attached to expenses are reduced the same way.
- Healthy basket counts the number of items too and adjusts for typical prices (cheap vegetables count fairly against meat).

### Fixed
- Replacing or removing the photo of an expense is now synced to the other iPhones.

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
