# 06 - Security test plan

Principle: **unauthorised users never receive family financial data** - enforced server-side (CloudKit sharing, invitation service), not only hidden in the UI.

| # | Scenario | Expected result | Phase | Test |
|---|---|---|---|---|
| 1 | User without App Invitation | Only invitation / request / about screens; no data access | 3 | UI test + manual |
| 2 | Expired App Invitation | Rejected with "expired" | 3 | Worker unit test + app test with stubbed service |
| 3 | Used App Invitation | Rejected ("already used"), unless same Apple ID re-installs | 3 | Worker test (atomic redemption) |
| 4 | Revoked App Invitation | Rejected; revoked accounts locked on next check | 3 | Worker test |
| 5 | Valid App Invitation | Account activated; can create or join a family | 3 | Worker + app flow test |
| 6 | Valid Family Invitation | Joins exactly that family; sees its data | 3/4 | Manual with 2 Apple IDs |
| 7 | Expired Family Invitation | Cannot join | 3 | App test |
| 8 | User tries another Family ID | No data returned (repository filter + CloudKit has no access) | 1 ✅ / 4 | `testRepositoryIsolatesFamilies`, `testRepositoryRefusesForeignFamilyInsert`, `AccessPolicy` tests; CloudKit manual with 2 Apple IDs |
| 9 | Removed family member | Share removed; access ends; local copy deleted | 1 ✅ (policy) / 4 | `testRemovedMemberSeesNothing`; manual |
| 10 | Offline synchronisation | Entries saved locally, synced later, nothing lost | 1 ✅ (currency) / 4 | `testOfflineWithoutCache…`, `testOfflineUsesNewestCachedRate…`; sync tests in Phase 4 |
| 11 | Reinstall and restore | Same Apple ID -> entitlement + family data restored | 4 | Manual on iPhone |
| 12 | Device replacement | Same as 11 on a second device | 4 | Manual |

Additional checks:
- Invitation code typos rejected before any network call (`testSingleTypoIsDetected`).
- Members can edit only their own expenses; owners manage budgets/categories/settings (`testEditRules`).
- Member limit of 6 enforced (`testMemberLimit`).
- No secrets in the repository (`.gitignore` + review before each release).
- Release workflow deletes keychain, keys and profiles on the runner in an `always()` step.
