# 06 - Security test plan

Principle: **unauthorised users never receive family financial data** - enforced by Apple's servers (CloudKit permissions and sharing), not only hidden in the UI.

| # | Scenario | Expected result | Phase | Test |
|---|---|---|---|---|
| 1 | User without App Invitation | Only invitation / request / about screens; no data access | 3 ✅ | app `testWithoutInvitationTheAppIsLocked` |
| 2 | Expired App Invitation | Rejected with "expired" | 3 ✅ | app `testUnknownExpiredAndRevokedInvitationsStayLocked` |
| 3 | Used App Invitation | Rejected ("already used"), unless same Apple ID re-installs | 3 ✅ | app `testUsedInvitationCannotBeUsedByAnotherPerson`; CloudKit unique record names |
| 4 | Revoked App Invitation | Rejected; revoked accounts locked on next check | 3 ✅ | app `testUnknownExpiredAndRevokedInvitationsStayLocked`, `testRevokedAccountIsSignedOutOnDailyCheck` |
| 5 | Valid App Invitation | Account activated; can create or join a family | 3 ✅ | app `testValidInvitationActivates`, `testNewUserHasNoFamilyUntilCreated` |
| 6 | Valid Family Invitation | Joins exactly that family; sees its data | 3/4 | Manual with 2 Apple IDs |
| 7 | Expired Family Invitation | Cannot join | 3 ✅ | `testExpiredFamilyInvitation`, `testFamilyInvitationExpiry` |
| 8 | User tries another Family ID | No data returned (repository filter + CloudKit has no access) | 1 ✅ / 4 | `testRepositoryIsolatesFamilies`, `testRepositoryRefusesForeignFamilyInsert`, `AccessPolicy` tests; CloudKit manual with 2 Apple IDs |
| 9 | Removed family member | Share removed; access ends; local copy deleted | 1 ✅ (policy) / 4 | `testRemovedMemberSeesNothing`; manual |
| 10 | Offline synchronisation | Entries saved locally, synced later, nothing lost | 1 ✅ (currency) / 4 | `testOfflineWithoutCache…`, `testOfflineUsesNewestCachedRate…`; sync tests in Phase 4 |
| 11 | Reinstall and restore | Same Apple ID -> entitlement + family data restored | 3 ✅ access / 4 data | app `testReinstallRestoresAutomatically`; data restore with Phase 4 |
| 12 | Device replacement | Same as 11 on a second device | 3 ✅ access / 4 data | as 11 |

Additional checks:
- Invitations cannot be listed (no queryable index) and are fetched only by the SHA-256 of the exact code; only FamiloqAdmin creates invitations and revocations (CloudKit security roles, doc 09).
- A different iCloud account on the same iPhone needs its own invitation (`testDifferentICloudAccountNeedsOwnInvitation`).
- Owner-only actions enforced for members (`testOwnerPermissionsVsMember`).
- Invitation code typos rejected before any network call (`testSingleTypoIsDetected`).
- Members can edit only their own expenses; owners manage budgets/categories/settings (`testEditRules`).
- Member limit of 6 enforced (`testMemberLimit`).
- No secrets in the repository (`.gitignore` + review before each release).
- Release workflow deletes keychain, keys and profiles on the runner in an `always()` step.
