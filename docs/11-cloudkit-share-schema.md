# 11 - One-time: make family invitations work (cloudkit.share schema)

## Why

When you invite someone, Familoq saves an iCloud **share** (`CKShare`). Shares use a system record type called `cloudkit.share`. CloudKit creates it **only when a share is first saved in the Development environment**, and it cannot be created by hand in the CloudKit Console. TestFlight and App Store builds always use **Production**, so without this one-time step inviting fails with

> Error saving record … Cannot create new type cloudkit.share in production schema

The fix: run a special Familoq build that talks to **Development** once, then deploy the schema to Production. About 30 minutes, from Windows, done once for the lifetime of the app.

## Steps

### A. Your iPhone's UDID (Windows)
1. Install **iMazing** (https://imazing.com, the free version is enough).
2. Connect the iPhone by USB, unlock it and tap **Trust**.
3. In iMazing select the iPhone → click the device name / *Device info* → copy the **UDID** (40 or 25 characters).

### B. Register the iPhone (developer.apple.com)
*Certificates, IDs & Profiles* → **Devices** → **+** → Platform *iOS*, name `Martin iPhone`, paste the UDID → **Continue** → **Register**.

### C. Ad Hoc provisioning profile
*Profiles* → **+** → under *Distribution* choose **Ad Hoc** → Continue
- App ID: `com.carolandmartin.familoq` → Continue
- Certificate: your **Apple Distribution** certificate (the same one as for TestFlight) → Continue
- Devices: tick your iPhone → Continue
- Name: `Familoq AdHoc` → **Generate** → **Download**

### D. GitHub secret (PowerShell)
```powershell
$p = Get-ChildItem $HOME\Downloads\*.mobileprovision | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$p.Name   # should be Familoq_AdHoc.mobileprovision
[Convert]::ToBase64String([IO.File]::ReadAllBytes($p.FullName)) | Set-Clipboard
```
GitHub → repository → *Settings → Secrets and variables → Actions* → **New repository secret** → name `IOS_ADHOC_PROFILE_BASE64` → paste → **Add secret**.

### E. Build the special app
GitHub → **Actions** → **CloudKit schema build (one-time, Ad Hoc)** → **Run workflow** (branch `main`). Takes ~10-15 minutes. When it is green, open the run and download **Familoq-CloudKit-schema-AdHoc** (a .zip) → unzip → `Familoq.ipa`.

### F. Install it with iMazing
iMazing → your iPhone → **Manage Apps** → tab **Device** → button **Install .IPA** (bottom) → choose `Familoq.ipa`.
It replaces the TestFlight version for a moment; your data stays on the iPhone. (If iMazing refuses, delete Familoq from the iPhone first - your family comes back from iCloud when you reinstall from TestFlight.)

### G. Prepare the schema
Open Familoq on the iPhone → it shows only **CloudKit schema** → tap **Prepare iCloud schema**. All lines should show ✓.

### H. Deploy (CloudKit Console)
https://icloud.developer.apple.com → CloudKit Database → container `iCloud.com.carolandmartin.familoq` → **Development** → *Schema* → *Record Types*: `cloudkit.share` is now listed → **Deploy Schema Changes…** → **Deploy**.

### I. Back to normal
Open the **TestFlight** app → Familoq → **Install**. Invite Carol again (*Family → Members → Invite*).

You never need this build again, and nobody else has to do it - Carol only installs from TestFlight.
