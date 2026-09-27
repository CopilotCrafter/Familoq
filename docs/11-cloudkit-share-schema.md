# 11 - One-time: make family invitations work (cloudkit.share schema)

## Why

When you invite someone, Familoq saves an iCloud **share** (`CKShare`). Shares use a system record type called `cloudkit.share`. CloudKit creates it **only when a share is first saved in the Development environment**, and it cannot be created by hand in the CloudKit Console. TestFlight and App Store builds always use **Production**, so without this one-time step inviting fails with

> Error saving record … Cannot create new type cloudkit.share in production schema

The fix: save one test share in **Development** once, then deploy the schema to Production. Done once for the lifetime of the app.

## Option 1 (recommended): browser + PowerShell, Apple services only - ~10 minutes

No iPhone, no extra apps. A small script talks to Apple's CloudKit Web Services (`api.apple-cloudkit.com`) as you.

### 1. API token (CloudKit Console)
https://icloud.developer.apple.com → **CloudKit Database** → container `iCloud.com.carolandmartin.familoq` → left menu **Tokens & Keys** (older console: *API Access*) → **API Tokens** → **+**
- Name: `schema`
- Sign-In Callback: **URL Redirect** → `http://localhost`
- Allowed Origins: **Any domain**
- **Save** → copy the token (a long hex string).

### 2. Run the script (Windows PowerShell)
Download `docs/scripts/cloudkit-share-schema.ps1` from GitHub (open the file → *Download raw file*) into `Downloads`, then:
```powershell
cd $HOME\Downloads
powershell -ExecutionPolicy Bypass -File .\cloudkit-share-schema.ps1
```
1. Paste the API token.
2. The browser opens Apple's sign-in → sign in with **your** Apple Account (tick *Keep me signed in* is fine).
3. The browser then shows "localhost refused to connect" - expected. Copy the **whole address** from the address bar (it contains `ckWebAuthToken=`) and paste it into PowerShell.
4. You should see four green `OK` lines.

### 3. Deploy
CloudKit Console → **Development** → *Schema* → *Record Types*: `cloudkit.share` is listed → **Deploy Schema Changes…** → **Deploy**.

### 4. Tidy up and invite
Delete the `schema` API token (Tokens & Keys → token → Delete). In Familoq: *Family → Members → Invite* again.

## Option 2: special Ad Hoc app build (needs your iPhone's UDID and a tool to install an .ipa)

Use only if Option 1 does not work.

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
