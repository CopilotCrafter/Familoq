# Changelog

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
