# 09 - App Invitations with CloudKit (setup & administration)

Familoq is invite-only. App Invitations live in the **public database** of Familoq's own iCloud container (`iCloud.com.carolandmartin.familoq`). There is no server of our own and no extra account - only your Apple Developer account. **No family or financial data is ever stored here.**

## How it works

| Record type | Record name | Who may create | Who may read | Purpose |
|---|---|---|---|---|
| `FQInvitation` | SHA-256 of the code | Admin | signed-in iCloud users, **by exact name only** | the invitation (status, expiry) |
| `FQRedemption` | `redeemed-` + hash | signed-in iCloud users | its creator, Admin | proves a code was used - a record name can exist **only once**, so a code works once |
| `FQRevocation` | `revoked-` + user ID | Admin | signed-in iCloud users | locks a person out |
| `FQInvitationLog` | `log-` + hash | Admin | Admin | your list: hint, note, expiry |
| `FQInvitationRequest` | random | signed-in iCloud users | its creator, Admin | "Request an Invitation" messages |

- The code itself is never stored - only its SHA-256 fingerprint. Nobody can list invitations except you.
- A person is identified by their **iCloud account** (no extra login). Reinstall or new iPhone with the same Apple ID → access is restored automatically.
- The app re-checks once a day whether the account was revoked; offline it keeps working.
- You (the administrator) need **no code**: the FamiloqAdmin role activates you and shows *Family → Administration*.

---

## One-time setup

Browser only. About 30 minutes. Steps A-C on developer.apple.com, D-F in the CloudKit Console, G on your iPhone.

### A. Create the iCloud container
developer.apple.com → *Certificates, IDs & Profiles* → **Identifiers** → **+** → **iCloud Containers** → Continue
- Description: `Familoq`
- Identifier: `iCloud.com.carolandmartin.familoq` → Continue → Register

### B. Enable iCloud on the App ID
*Identifiers* → `com.carolandmartin.familoq` → tick **iCloud** → choose **Include CloudKit support** → click **Edit** next to iCloud → tick `iCloud.com.carolandmartin.familoq` → Continue → **Save** (confirm the warning about profiles).

### C. Regenerate the provisioning profile
*Profiles* → **Familoq AppStore** → **Edit** → **Save** → **Download**, then in PowerShell:
```powershell
cd $HOME\familoq-signing
Remove-Item *.mobileprovision -ErrorAction SilentlyContinue
Move-Item $HOME\Downloads\*.mobileprovision .
Select-String -Path (Get-ChildItem *.mobileprovision)[0].FullName -Pattern "icloud-container-identifiers" -Quiet   # must print True
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Get-ChildItem *.mobileprovision)[0].FullName)) | Set-Clipboard
```
GitHub → *Settings → Secrets and variables → Actions* → `IOS_PROVISIONING_PROFILE_BASE64` → **Update** → paste.

### D. Create the record types (CloudKit Console, **Development**)
Open **https://icloud.developer.apple.com** → **CloudKit Database** → container `iCloud.com.carolandmartin.familoq` → environment **Development** (top).

*Schema* → **Record Types** → **+** for each type, then **+ Add Field** for its fields → **Save**:

| Record type | Fields (name · type) |
|---|---|
| `FQInvitation` | `status` · String, `expiresAt` · Date/Time |
| `FQRedemption` | `redeemedAt` · Date/Time |
| `FQRevocation` | `revokedAt` · Date/Time |
| `FQInvitationLog` | `codeHash` · String, `hint` · String, `note` · String, `expiresAt` · Date/Time |
| `FQInvitationRequest` | `name` · String, `contact` · String, `message` · String, `handled` · Int(64) |

Names are case-sensitive - type them exactly.

### E. Indexes
*Schema* → **Indexes** → pick the record type → **+ Add Basic Index**:

| Record type | Field | Index type |
|---|---|---|
| `FQRedemption` | `recordName` | Queryable |
| `FQRedemption` | `createdUserRecordName` (the "created by" system field) | Queryable |
| `FQRevocation` | `recordName` | Queryable |
| `FQInvitationLog` | `recordName` | Queryable |
| `FQInvitationRequest` | `recordName` | Queryable |

Do **not** add a queryable index to `FQInvitation` - that is what keeps invitations unlistable.

### F. Security roles (who may do what)
*Schema* → **Security Roles**:
1. **+** → create a role named `FamiloqAdmin`.
2. Set the permissions per record type exactly like this (untick everything not listed - in particular **World must have nothing** on these types):

| Record type | World | Authenticated | Creator | FamiloqAdmin |
|---|---|---|---|---|
| `FQInvitation` | - | Read | Read, Write | Create, Read, Write |
| `FQRedemption` | - | Create | Read | Read, Write |
| `FQRevocation` | - | Read | - | Create, Read, Write |
| `FQInvitationLog` | - | - | - | Create, Read, Write |
| `FQInvitationRequest` | - | Create | Read | Read, Write |

(In the Console these roles are named `_world` = anyone, `_icloud` = any signed-in iCloud user ("Authenticated" above), `_creator` = whoever created that record. Leave the built-in `Users` type unchanged.)

3. **Deploy to Production**: *Schema* → **Deploy Schema Changes…** → Deploy. TestFlight and App Store builds use the **Production** environment - without this step nothing works.

### G. Make yourself administrator
1. Install the new Familoq build from TestFlight and open it once (so iCloud knows your account in Production). On the first screen tap **About Familoq** - copy **Your iCloud user ID** (starts with `_`).
2. CloudKit Console → environment **Production** → *Data* → **Records** → database **Public** → **Fetch Records** (by record name) → record type **Users** → paste your iCloud user ID → Fetch.
   (CloudKit does not allow a custom index on `Users`, so use *Fetch*, not *Query*.)
3. In the record → section **Security Roles** → tick **FamiloqAdmin** (the role may be saved immediately; reopen the record to check).
4. Back in Familoq: **Already activated? Restore access** → **Continue**. You are in - with your existing data - and *Family → Administration* appears.

---

## Daily use (on your iPhone)

*Family* → **Administration**:
- **New App Invitations**: choose number of codes, validity, a note (e.g. "John & Sarah") → **Create** → share each code with the share button. Codes are shown only once.
- **Invitations**: open / used / expired / revoked. Swipe an open one → **Revoke**.
- **Activated accounts**: swipe → **Revoke** (that iPhone locks at its next daily check; their data is not deleted) or **Restore**.
- **Invitation requests**: messages from the *Request an Invitation* screen; swipe → **Done**.

Everything is also visible in the CloudKit Console (Production → Records) as a backup.

## What a friend does
1. Installs Familoq from TestFlight (later the App Store).
2. Is signed in to iCloud on the iPhone (Settings → their name).
3. **Enter Invitation Code** → types the code → **Activate Familoq**.
4. **Create our family** (or join one - completes with the Phase 4 update).

## Security notes
- One-time use is enforced by iCloud itself: a second redemption record with the same name is rejected.
- Only the FamiloqAdmin role can create invitations and revocations; a revoked person cannot remove their revocation.
- The gate controls who may *use* the app. Family data is protected separately: it stays on the devices and, from Phase 4, in each family's private iCloud zone shared only with its members.
- Cost: included in the Apple Developer Program; the public database quota is far above what invitation records need.
