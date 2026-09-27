# 04 - Invite-only access, family isolation and CloudKit

Design for Phases 3 and 4, and the constraints Phase 1 already respects.

## Two invitation levels (never mixed up)

| | App Invitation (Level 1) | Family Invitation (Level 2) |
|---|---|---|
| Grants | Permission to **use Familoq at all** | Permission to **join one family** |
| Issued by | You (Familoq administrator) | A family **owner** |
| Example | `MBF7-K92X-4QPL` | share link / code from Martin to Carol |
| Checked by | Invitation service (server-side) | CloudKit sharing (Apple's servers) |
| Stored | Code hash, status, expiry, redeemed-by | CloudKit share on the family's zone |

### Onboarding screens (Phase 3)
```
Familoq
Your family's private space
[ Enter Invitation Code ]
[ Request an Invitation ]
  About Familoq
```
No "Sign up", "Create account" or "Continue as guest". Without a redeemed App Invitation the app shows only these screens.

## Level 1 - App Invitations

Implemented with the **CloudKit public database** - no own server. Details, record types, permissions and the full setup: **[09-invitations-cloudkit.md](09-invitations-cloudkit.md)**.

- Identity = the person's iCloud account (no extra login).
- A code works once: the redemption record name is derived from the code, and CloudKit allows each record name only once.
- Only the FamiloqAdmin role can create invitations and revocations; you manage them in *Family → Administration*.

### Important security property
Even if someone bypassed the Level-1 gate with a modified app, they would get an **empty app**: family data is only reachable through CloudKit shares (Level 2), which Apple's servers enforce. Level 1 controls *who may use the app*; Level 2 protects *the money data*.

## Level 2 - Families in CloudKit

```
Martin's private database                         Carol's shared database
└── zone "family-<UUID>"  (Martin's family) ─share─▶ same zone (read/write)
    ├── Family, FamilyMember
    ├── Expense, ExpenseCategory, ExpenseSubcategory
    ├── Budget, MerchantRule
    └── (later) Trip, HealthRecord, Plan, Reminder, Event ...

John's private database
└── zone "family-<UUID2>" (John's family) ─share─▶ Sarah
```

- **One custom record zone per family**, owned by the family owner, shared with a **zone-wide `CKShare`**. Every Familoq space (budget now, travel/health/… later) lives in the same family zone - one share covers the whole family space.
- Apple's servers only return zones that are **owned by** or **shared with** the signed-in iCloud user. Family A cannot fetch Family B's zone - there is no API for it. This is the hard isolation boundary.
- Inside the app, every record also carries `familyID` and all reads go through `FamilyRepository` (defence in depth; tested in `PersistenceTests.testRepositoryIsolatesFamilies`).
- Joining: owner creates a Family Invitation -> Familoq sends the share link (Messages/Mail) -> the member (who must already have a redeemed App Invitation) accepts -> the zone appears in their shared database.
- Expiry: the app stores a `FamilyInvitation` record (expiry, max uses) in the zone and the owner can stop sharing at any time.
- Inviting: the owner adds the person's Apple Account (e-mail/phone) as a private participant - the link only works for that person.
- Removing a member: owner removes the share participant -> Apple revokes access immediately; the app deletes the local copy on next sync.
- Member limit (6, configurable): enforced when adding participants (`FamilyLimits`).

### Consequences to know
- Every member needs an **iCloud account** on their iPhone.
- The family's data (including receipt images) counts against the **owner's iCloud storage**. Receipts are stored compressed.
- **Public database is never used for family data.**

## Sync engine (built in Phase 4 - details and setup in doc 10)

- SwiftData's built-in CloudKit sync supports only the **private** database - it cannot sync **shared** zones (`CKShare`). Familoq therefore keeps **SwiftData as the local, offline-first store** and uses **`CKSyncEngine`** (iOS 17+) to sync each family zone (owner: private DB; members: shared DB).
- All records are sent as one generic record type `FQFamilyItem` (kind, payload JSON, modifiedAt, asset), so the CloudKit schema never changes when a model or a new space is added.
- Last writer wins per record; owner-only settings are enforced on the owner's iPhone.
- Offline: changes are saved locally first and queued; nothing is lost if sync fails.
- Restore / new device / reinstall: same Apple Account -> the family zone is downloaded again.
- No push notifications (no `aps-environment`): the app fetches on launch, foreground, pull-to-refresh and every minute while open.
- Setup: create `FQFamilyItem` in the CloudKit Console and deploy - see **docs/10-sync-and-sharing.md**.

## Phase 1 data model (all records carry `familyID`)

| Record | Module | Key fields |
|---|---|---|
| Family | Core | name, baseCurrencyCode (EUR default), maxMembers (6) |
| FamilyMember | Core | displayName, role (owner/member), isActive |
| ExpenseCategory / ExpenseSubcategory | Budget | systemKey, name, icon, color, archived |
| Expense | Budget | original amount + currency, base amount + currency, rate/date/source/status, merchant, date & time, category IDs, member, payment method, note, optional receipt |
| Budget | Budget | period, scope, category/subcategory ID, amount |
| MerchantRuleRecord | Budget | pattern, category IDs, user-defined flag |
| ExchangeRateCacheEntry | Budget | public ECB rates (no personal data) |
