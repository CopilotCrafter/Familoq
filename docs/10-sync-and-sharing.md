# 10 - iCloud sync & shared families (Phase 4)

Since 0.3.0 every family is stored in iCloud and shared with its members. Familoq still has **no server of its own**: the data lives in the family owner's iCloud, and members see it through Apple's iCloud sharing.

## How it works

```
 Martin's iPhone (owner)                    Carol's iPhone (member)
 ┌──────────────────────┐                   ┌──────────────────────┐
 │ SwiftData (offline)  │                   │ SwiftData (offline)  │
 │   ▲   SyncCoordinator│                   │ SyncCoordinator  ▲   │
 └───┼────────┬─────────┘                   └─────────┬────────┼───┘
     │        │ private database                      │ shared database
     │        ▼                                        ▼        │
     │   iCloud (Martin's account) ─ zone "family-<id>" ◄───────┘
     │        └── CKShare: Martin (owner), Carol (invited, read/write)
```

- **One zone per family** in the owner's *private* database. Other families on the same iPhone (e.g. your own test family) live in their own zones. Nothing is mixed.
- **Members** reach the zone through their *shared* database - only after the owner invited their Apple Account and they opened the link.
- **One record type** for everything: `FQFamilyItem` with `kind` (e.g. `expense`), `payload` (the fields as JSON), `modifiedAt`, `asset` (receipt photo). Record names are `kind-UUID`.
- **Offline first**: everything is saved on the iPhone immediately. Changes are uploaded within ~15 s when online, and remembered (CKSyncEngine queue) when offline.
- **Receiving changes**: when the app opens, comes to the foreground, on pull-to-refresh (Family tab) and every minute while open. (No push notifications, so no extra Apple capability is needed.)
- **Conflicts**: last writer wins, per record.
- **Owner-only settings** (family name, base currency, categories, budgets, roles) are enforced on the owner's iPhone: a change made by someone else is reverted to the owner's version.
- **Reinstall / new iPhone** with the same Apple Account: the family comes back from iCloud. The app waits for it before offering "Create your family".

## One-time setup: the record type (CloudKit Console, ~5 minutes)

Browser only. Same container as the App Invitations (docs/09).

1. Open **https://icloud.developer.apple.com** → **CloudKit Database** → container `iCloud.com.carolandmartin.familoq`.
2. Environment (top): **Development**.
3. *Schema* → **Record Types** → **+** → name `FQFamilyItem` → **Save**. Then **+ Add Field** four times:

   | Field name | Type |
   |---|---|
   | `kind` | String |
   | `payload` | String |
   | `modifiedAt` | Date/Time |
   | `asset` | Asset |

   → **Save**. Names are case-sensitive.
4. No indexes and no security roles are needed (private and shared databases are protected by iCloud itself; roles only apply to the public database).
5. *Schema* → **Deploy Schema Changes…** → **Deploy** (to Production). TestFlight uses Production - **without this step sync shows "iCloud rejected the data"**.

That's all. No new certificates or profiles: the iCloud capability from docs/09 already covers private and shared databases.

## Inviting a family member

Owner (e.g. Martin):
1. *Family* → **Members** → **Invite to family**.
2. Type the **e-mail address or phone number of the person's Apple Account** (the one signed in to iCloud on their iPhone) → **Invite to family**.
3. Tap **Send the link to …** and send it (Messages, WhatsApp, Mail).
4. Under **Invitations** the person shows as *Invited*, later *Joined*. Swipe → **Withdraw** / **Remove** at any time.

Member (e.g. Carol):
1. Familoq installed from TestFlight and activated with her own App Invitation (docs/09).
2. Opens the link on her iPhone → Familoq opens → *Joining the family…*
3. Enters her name → sees the family's dashboard, categories and budgets.

Only people the owner added can open the link - forwarding it to someone else does not work. The family limit (6) counts invited people too.

If Carol already created her own family earlier, she now has two: *Family* → **Your families** switches between them; *Family* → **Leave / Delete this family** removes one.

## Removing, leaving, deleting

| Action | Who | Effect |
|---|---|---|
| Swipe member → **Remove** | owner | person loses access immediately; the family disappears from their iPhone at their next sync; their past expenses stay in the family |
| **Leave this family** | member | family removed from their iPhone; owner sees them as inactive |
| **Delete this family** | owner | zone deleted in iCloud: gone for every member and all devices |

## What to test (two iPhones)

| # | Test | Expected |
|---|---|---|
| 1 | Martin adds an expense | appears on Carol's iPhone within ~1 minute (or after pull-to-refresh on the Family tab) |
| 2 | Carol adds an expense offline, then goes online | uploaded, visible to Martin |
| 3 | Both edit the same expense offline | after sync both show the later edit |
| 4 | Carol opens budgets / family name | read-only for members (also enforced on Martin's iPhone) |
| 5 | Martin removes Carol | the family disappears from Carol's iPhone |
| 6 | Delete & reinstall Familoq on Martin's iPhone | access restored, family and expenses come back from iCloud |
| 7 | Forward the invitation link to a third Apple Account | "Could not join" |
| 8 | Receipt photo on Martin's iPhone | visible in the expense on Carol's iPhone |

Status and problems: *Family* → **iCloud** row (Up to date · time / Offline / message).

## Costs

- No Familoq server, no extra subscription. CloudKit is included in the Apple Developer Program.
- Family data counts against the **owner's iCloud storage** (receipt photos ≈ 100-300 KB each; the free 5 GB is plenty for years of receipts).
- Members' iCloud storage is not used for the shared family.

## Code map

| File | Purpose |
|---|---|
| `Packages/FamiloqKit/Sources/FamiloqCore/Sync/` | record names, zones, payload encoding, fingerprints, diff, last-writer-wins (Linux-tested) |
| `Familoq/Core/Sync/SyncCoordinator.swift` | CKSyncEngine (private + shared), upload/download, conflicts, owner rules |
| `Familoq/Core/Sync/FamilySharing.swift` | invite, withdraw/remove, accept |
| `Familoq/Core/Sync/SyncableRecord.swift` | which models sync and how (core) |
| `Familoq/Modules/Budget/Sync/BudgetSync.swift` | Budget module records |
| `Familoq/App/AppDelegate.swift` | receives tapped invitation links |
