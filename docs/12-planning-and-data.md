# 12 - Planning, insights and your data (0.4.0)

## Recurring & planned expenses
*Dashboard → Upcoming → Recurring & planned*

| Kind | Example | What Familoq does |
|---|---|---|
| Recurring | Rent €950 every month from 1 Oct | On each due date an expense is added automatically (category, member, payment as entered). |
| Planned | Car service €300 on 12 Nov | On that date it becomes an expense; until then it is reserved. |

- **Safe to spend** keeps back everything still due this month (plus what savings goals still need), so the daily amount is realistic. Tap Safe to spend to see the breakdown.
- Booking happens when Familoq opens or comes to the foreground. Missed dates are caught up (at most 12 per item).
- Both iPhones of a family may book the same date - it is the same expense (fixed ID from item + date), never a duplicate.
- Changing the first date or the frequency starts the booking afresh from the new date. Pause with *Active* off.
- Foreign-currency items are booked in their currency and converted with the rate of the due date.

## Savings goals
*Dashboard → Savings goals*
- Target amount (base currency), optional deadline, symbol.
- With a deadline Familoq shows *€X per month for N months*; the monthly amount minus what was already saved this month is reserved in Safe to spend (switch off per goal).
- *Add money* / *Take out* keep a history (who, when, note). Goals sync to the whole family.

## Search & filters
*Dashboard → Recent expenses → See all*
- Search: every word must match merchant, note or category (umlauts ignored); a number like `12,50` finds that amount.
- Filters: period (incl. custom), categories, members, amount range, entered as (manual / quick / receipt / recurring), only other currencies. The filtered total is shown on top.

## Reports
Periods: today, week, month, previous month, **this year, last 12 months, custom range**. New sections: **12-month trend** (current period highlighted, average of complete months), **by member**, **budget vs actual** (monthly category budgets).

## Export & backup
*Family → Export & backup*
- **CSV**: one row per expense (date, time, merchant, category, subcategory, amount, currency, amount in base currency, rate, rate date, member, payment, note, entered as, receipt). With a German iPhone the file uses `;` and decimal commas, so German Excel opens it directly.
- **Backup**: one JSON file with everything of the family (optionally with receipt photos). Save it to Files / iCloud Drive / OneDrive.
- **Restore** (owner): adds the backup's records to the current family; existing records are replaced by the backup's version; records of other families are never touched; the family's name and currency stay.

## German
The app follows the iPhone language (Settings → General → Language & Region, or Settings → Familoq → Language). When the owner uses Familoq in German, built-in category names are renamed once (only names nobody changed); the new names sync to the family.
