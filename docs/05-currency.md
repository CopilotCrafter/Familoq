# 05 - Currency: base currency and conversion

## Base currency
- Every family has **one base currency**. Default: **EUR**.
- The owner can change it: *Family -> Base currency*. It applies to the whole family (all members see the same totals).
- Budgets, dashboard totals, safe-to-spend and reports are always in the base currency.

## Foreign-currency expenses
An expense keeps **both** values:

| Field | Example |
|---|---|
| Original amount & currency | 25.00 USD (as on the receipt) |
| Base amount & currency | 21.36 EUR |
| Rate, rate date, source, status | 0.8543 · 2026-09-25 · ECB reference rate (Frankfurter) · converted |

### Which rate
- The **ECB euro reference rate for the expense's date** - the receipt date (Phase 2) or the date & time entered.
- The ECB publishes one rate per business day at about 16:00 CET. **There is no free intraday or time-of-day average rate**; the daily reference rate is the standard, neutral choice and is what most statements and tax guidance use. The time is kept on the expense for your records.
- Weekend or public holiday -> the previous business day's rate (official behaviour).
- Expense dated **today** before publication -> converted with yesterday's rate and marked **estimated**; refreshed automatically once the day's rate exists.
- Future-dated expenses (planned) -> latest rate, estimated.
- Cross rates (e.g. USD expense, GBP base) are supported - the API computes them from ECB data.
- ~30 currencies are covered (USD, GBP, CHF, INR, PLN, CZK, HUF, SEK, NOK, DKK, JPY, CNY, TRY, AUD, CAD, …). For others (e.g. AED) the app asks for a **manual rate**.

### Manual rate
Toggle *Enter exchange rate manually* and type the rate from your bank/card statement (1 USD = 0.92 EUR). Manual rates are **never overwritten**.

### Offline
The expense is saved immediately. If no rate can be fetched:
1. use the newest cached rate for the pair -> status **estimated**, included in totals;
2. if nothing is cached -> status **pending**, *not* included in totals; the dashboard shows "N expenses waiting for an exchange rate".
Pending/estimated expenses are retried whenever the app becomes active or you pull to refresh.

### Changing the base currency
- Requires internet (nothing changes if offline).
- **Budgets** are converted with today's rate and rounded to whole units.
- **Every expense** is re-converted with the rate of **its own date**.
- Expenses already in the new currency need no rate. Manual rates were given against the old base, so those expenses are re-fetched.

## Privacy
Rate requests contain only two currency codes and a date, e.g. `GET https://api.frankfurter.dev/v1/2026-09-25?base=USD&symbols=EUR`. No amounts, merchants, names or device identifiers. Final rates are cached on the device so each day/pair is fetched once. Fallback endpoint: `api.frankfurter.app`.

## Where it is implemented
- `Packages/FamiloqKit/Sources/FamiloqCore/Currency/` - converter, status rules, Frankfurter client (tested on Linux)
- `Familoq/Modules/Budget/Services/ExchangeRateService.swift` - caching, offline fallback, refresh
- `Familoq/Modules/Budget/Services/BaseCurrencyService.swift` - base currency change
- Tests: `CurrencyConversionTests`, `CurrencyConversionFlowTests`
