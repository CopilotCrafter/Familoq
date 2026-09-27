# 06 - Security test plan

Principle: **unauthorised users never receive family financial data** - enforced by Apple's servers (CloudKit permissions and sharing), not only hidden in the UI.

| # | Scenario | Expected result | Phase | Test |
|---|---|---|---|---|
| 1 | User without App Invitation | Only invitation / request / about screens; no data access | 3 ✅ | app `testWithoutInvitationTheAppIsLocked` |
| 2 | Expired App Invitation | Rejected with "expired" | 3 ✅ | app `testUnknownExpiredAndRevokedInvitationsStayLocked` |
| 3 | Used App Invitation | Rejected ("already used"), unless same Apple ID re-installs | 3 ✅ | app `testUsedInvitationCannotBeUsedByAnotherPerson`; CloudKit unique record names |
| 4 | Revoked App Invitation | Rejected; revoked accounts locked on next check | 3 ✅ | app `testUnknownExpiredAndRevokedInvitationsStayLocked`, `testRevokedAccountIsSignedOutOnDailyCheck` |
| 5 | Valid App Invitation | Account activated; can create or join a family | 3 ✅ | app `testValidInvitationActivates`, `testNewUserHasNoFamilyUntilCreated` |
| 6 | Valid Family Invitation | Joins exactly that family; sees its data | 4 | Manual with 2 Apple IDs (doc 10); `testJoinedFamilyWithoutMyMemberNeedsName` |
| 7 | Withdrawn / forwarded Family Invitation | Cannot join: the share only admits the Apple Account the owner added | 4 | Manual (doc 10 test 7); share is never public (`publicPermission = .none`) |
| 8 | User tries another Family ID | No data returned (repository filter + CloudKit has no access) | 1 ✅ / 4 | `testRepositoryIsolatesFamilies`, `testRepositoryRefusesForeignFamilyInsert`, `AccessPolicy` tests; CloudKit manual with 2 Apple IDs |
| 9 | Removed family member | Share participant removed; access ends at Apple; local copy deleted on next sync | 4 ✅ | `testRemovedMemberSeesNothing`, `testDeletingOneFamilyKeepsTheOther`; manual (doc 10 test 5) |
| 10 | Offline synchronisation | Entries saved locally, synced later, nothing lost | 4 ✅ | CKSyncEngine queue; `testLocalEditChangesOnlyThatFingerprint`, `testEveryRecordRoundTripsThroughAnotherDevice`; manual (doc 10 test 2) |
| 11 | Reinstall and restore | Same Apple ID -> entitlement + family data restored | 4 ✅ | app `testReinstallRestoresAutomatically`; manual (doc 10 test 6) |
| 12 | Device replacement | Same as 11 on a second device | 4 ✅ | as 11 |

Additional checks:
- Invitations cannot be listed (no queryable index) and are fetched only by the SHA-256 of the exact code; only FamiloqAdmin creates invitations and revocations (CloudKit security roles, doc 09).
- A different iCloud account on the same iPhone needs its own invitation (`testDifferentICloudAccountNeedsOwnInvitation`).
- Owner-only actions enforced for members (`testOwnerPermissionsVsMember`).
- Invitation code typos rejected before any network call (`testSingleTypoIsDetected`).
- Members can edit only their own expenses; owners manage budgets/categories/settings (`testEditRules`).
- Member limit of 6 enforced (`testMemberLimit`), invited people count towards it.
- Members cannot change owner-only records through iCloud either: the owner's iPhone reverts family, category, subcategory, budget and role changes made by others (`SyncCoordinator.isChangeAllowed`).
- Family data never goes to the public database; each family is its own zone (`testDeletingOneFamilyKeepsTheOther`).
- No secrets in the repository (`.gitignore` + review before each release).
- Release workflow deletes keychain, keys and profiles on the runner in an `always()` step.
