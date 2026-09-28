# 13 - Planner: shopping list, reminders, calendar (0.5.0)

A new tab **Planner** with three parts. Everything is shared with the family through the same iCloud sync as the budget (no new CloudKit setup: every record is an `FQFamilyItem`). Every member may add, change and tick off.

## Shopping list
- Type `2x Milk`, `500 g Hackfleisch`, `Eier 10` → name + amount. Typing an item that is already on the list only updates the amount.
- Items are grouped by supermarket section (fruit & vegetables first, frozen and household last), using the same on-device classifier as receipts. Change the section via swipe → *Edit*.
- Tap to put an item in the cart; *Clear bought items* hides them. Bought items stay in the history for the **Buy again** chips (removed after a year).
- **Receipt scanning ticks items off**: after saving a receipt, open items that appear on it are marked bought ("Ticked off the shopping list: Milk, Bananas"). Handles plurals (Banane/BANANEN), cut-off receipt words (KARTOFF.) and compounds (VOLLMILCH = milk, but MILCHSCHOKOLADE is not milk).
- Several lists (e.g. Supermarket, Drugstore): list icon (top right) → *Manage lists*. The first list has the same ID on every iPhone, so two people never create two default lists.

## Reminders
- Title, notes, due date (optionally with time), repeat (daily … yearly), for whom (nobody chosen = whole family).
- Sections: Overdue, Today, Tomorrow, Next 7 days, Later, No date. Top-left: everyone's or only mine.
- Ticking off a repeating reminder moves it to its next date (an overdue weekly chore jumps to the coming week).

## Calendar
- Month view with dots (events and reminders), the selected day's agenda and "Coming up" (30 days).
- Types: Event, Appointment, Birthday (all-day, yearly, alert the day before), School, Trip; all-day and multi-day events; repeats; participants; location; notes.
- Changes and deletion apply to the whole series.

## Notifications
- Local notifications, prepared on each iPhone from the synced data: reminders for me or everyone, event alerts for participants, bills (recurring expenses) the evening before they are due.
- *Family → Notifications*: allow notifications, choose the three kinds. The first reminder/event with an alert asks "Allow notifications?".
- **Background refresh**: iOS wakes Familoq now and then (it decides when, typically a few times a day) to fetch family changes and update the alerts. It does not work when the app was force-quit from the app switcher.
- **No extra certificate**: local notifications and background refresh need no Apple capability. *Instant* alerts the moment another member adds something would need Apple Push Notifications (App ID capability + new provisioning profile) - optional, later.

## Dashboard
- New **Today** section: today's events, reminders due, number of open shopping items (tap → Planner).
- **Reports** moved from the tab bar to the chart button on the dashboard (top right).

## Updating with two iPhones
Records created on an iPhone with 0.5.0 are ignored by 0.4.x. When the other iPhone updates, Familoq fetches the Planner records of every family once (`catchUpNewKindsIfNeeded` in SyncCoordinator), so nothing is lost - just update both iPhones.

## Code map
| File | Purpose |
|---|---|
| `Packages/FamiloqKit/Sources/FamiloqPlanner/` | entry parsing, aisles, receipt matching, suggestions, repeat rules, reminder buckets, event occurrences, notification plan (Linux-tested) |
| `Familoq/Modules/Planner/Models/PlannerModels.swift` | ShoppingList, ShoppingItem, FamilyReminder, FamilyEvent |
| `Familoq/Modules/Planner/PlannerModule.swift` | module registration, ShoppingService, ReminderService, demo data |
| `Familoq/Modules/Planner/Sync/PlannerSync.swift` | sync handlers and payloads |
| `Familoq/Modules/Planner/Services/PlannerNotifications.swift` | local notifications, background refresh |
| `Familoq/Modules/Planner/Views/` | Planner tab, shopping, reminders, calendar, Today section, notification settings |

## What to test
| # | Test | Expected |
|---|---|---|
| 1 | Martin adds "2x Milch", Carol opens Planner | item appears (pull-to-refresh on Family tab if impatient) |
| 2 | Scan a receipt with milk on it | milk is ticked off, banner at the top |
| 3 | Reminder for Carol tomorrow 8:00 | only Carol's iPhone alerts at 8:00 |
| 4 | Birthday event | alert 9:00 the day before, repeats next year |
| 5 | Weekly reminder, tick off | moves to next week |
| 6 | Recurring expense due tomorrow | notification 18:00 today |
| 7 | German iPhone | all Planner texts in German |
