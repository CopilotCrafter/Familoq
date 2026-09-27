# 02 - Apple account, signing and distribution (from Windows)

## 1. Apple ID (Apple Account)
- Use your existing Apple ID; **two-factor authentication** must be on (it is on by default on a modern iPhone).
- The first/last name must be your **legal name** - it becomes the seller name shown on the App Store for an individual account.

## 2. Apple Developer Program - 💶 unavoidable
- **99 USD per membership year**, billed in local currency (the exact euro price is shown during enrollment). Auto-renews yearly.
- Enroll as **Individual** (simplest). An *Organization* needs a D-U-N-S number and shows a company as seller - only worth it if you later publish under a company.
- Fastest path: **Apple Developer app** on the iPhone -> Account -> *Enroll now*. Identity is verified with your iPhone.
- Without membership you **cannot** use TestFlight, App Store, distribution certificates or CloudKit production.

## 3. App Store Connect
https://appstoreconnect.apple.com - the website for app records, TestFlight, testers, App Store listing, review submissions. Works in any browser on Windows.

## 4. Bundle identifier
- Chosen: **`com.carolandmartin.familoq`** (reverse of the domain you already own).
- Registered once at developer.apple.com -> *Certificates, IDs & Profiles* -> *Identifiers* -> **+** -> *App IDs* -> *App* -> **Explicit** Bundle ID.
- Capabilities for Phase 1: none extra. Phase 3 adds *iCloud (CloudKit)* for App Invitations (doc 09) - when you add capabilities you must regenerate the provisioning profile (step 6) and update the secret.
- The bundle ID in `Config/App.xcconfig` (`FQ_BUNDLE_ID`) must match exactly. It can never be changed after the app is published.

## 5. Signing certificate - created with OpenSSL on Windows

Apple needs a **Certificate Signing Request (CSR)**. On a Mac you would use Keychain Access; on Windows use **Git Bash** (installed with Git for Windows):

```bash
mkdir -p ~/familoq-signing && cd ~/familoq-signing

# 1. Private key + CSR  (use your Apple ID e-mail and legal name)
openssl genrsa -out familoq_dist.key 2048
openssl req -new -key familoq_dist.key -out familoq_dist.csr \
  -subj "/emailAddress=you@example.com/CN=Your Name/C=DE"
```

2. developer.apple.com -> *Certificates* -> **+** -> **Apple Distribution** -> upload `familoq_dist.csr` -> download `distribution.cer`.

```bash
# 3. Convert Apple's certificate and bundle it with your key into a .p12
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export \
  -inkey familoq_dist.key -in distribution.pem \
  -out familoq_dist.p12 \
  -name "Apple Distribution" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout pass:CHOOSE-A-STRONG-PASSWORD
```

The `-certpbe/-keypbe/-macalg` options produce a `.p12` that the macOS `security` tool imports reliably (OpenSSL 3 defaults can fail with "MAC verification failed").

- An Apple Distribution certificate is valid for **1 year**. When it expires, repeat this section and update the two secrets. Existing App Store versions keep working.
- Keep `familoq_dist.key` / `.p12` in a password manager. Anyone with them can sign apps as you.

## 6. Provisioning profile
developer.apple.com -> *Profiles* -> **+** -> **App Store Connect** (Distribution) -> App ID `com.carolandmartin.familoq` -> select the Apple Distribution certificate -> name **`Familoq AppStore`** -> *Generate* -> download `Familoq_AppStore.mobileprovision`.

Regenerate it when you: renew the certificate, or add capabilities (e.g. iCloud). The release workflow reads the profile's name and UUID automatically and checks that it matches the bundle ID.

Development profiles/devices are **not needed** - you never install directly from a Mac; TestFlight uses the distribution build.

## 7. GitHub secrets - how to produce each value (PowerShell)

```powershell
cd $HOME\familoq-signing
# base64 of the .p12 -> clipboard -> paste into IOS_DIST_CERT_P12_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\familoq_dist.p12")) | Set-Clipboard
# base64 of the profile -> IOS_PROVISIONING_PROFILE_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\Familoq_AppStore.mobileprovision")) | Set-Clipboard
# contents of the API key -> ASC_PRIVATE_KEY
Get-Content .\AuthKey_ABC123XYZ.p8 -Raw | Set-Clipboard
```

- `APPLE_TEAM_ID`: developer.apple.com -> *Account* -> *Membership details* -> Team ID.
- `ASC_KEY_ID` / `ASC_ISSUER_ID`: App Store Connect -> *Users and Access* -> *Integrations* -> *App Store Connect API* -> *Team Keys*. Role **App Manager** is enough for uploads.
- `KEYCHAIN_PASSWORD`: any random string; it only protects a temporary keychain on the runner.

## 8. TestFlight
- After the release workflow uploads a build, Apple processes it (5-30 min).
- **Internal testing**: App Store Connect users of your account (up to 100). No review. This is how you and Carol test: add her as a user in *Users and Access* (role *Customer Support* or *Developer* is enough), then add her to the internal group.
- **External testing** (friends without App Store Connect access, up to 10,000 via e-mail or a public link): the first build of each version needs **Beta App Review** (usually ~1 day). Because Familoq is invite-only, provide a **working demo invitation code** in *Test Information* (from Phase 3).
- TestFlight builds expire after **90 days**.
- Testers can send screenshots + comments and crash reports appear in App Store Connect -> TestFlight -> Crashes/Feedback - your debugging channel without a Mac.

## 9. Production (App Store)
1. App Store Connect -> app -> *App Information*: category **Finance**, content rights, age rating questionnaire.
2. **Privacy**: privacy policy URL (e.g. a page on carolandmartin.com) and *App Privacy* answers. Familoq collects no data for tracking; financial data stays on device / in the user's iCloud.
3. Screenshots: 6.9" iPhone size required - take them from TestFlight on a large iPhone, or from the CI simulator screenshots.
4. **App Review for an invite-only app**: Apple allows apps that require an account/invitation **if** you give reviewers full access. Put a working App Invitation code and instructions in *App Review Information -> Notes*. Keep "Request an Invitation" functional.
5. Distribution options (choose at submission):
   - **Public App Store listing** - anyone can download, only invited people can use it (your requirement).
   - **Unlisted app distribution** - not searchable, only reachable by a direct link; requested from Apple separately. Good fit for a private community.
6. Build requirements (current): uploads must be built with **Xcode 26+ / iOS 26 SDK** (since 28 April 2026) - the `macos-26` runner satisfies this. The app's deployment target is iOS 17.

## 10. Free vs. paid - summary

| Free | Paid (unavoidable) |
|---|---|
| Xcode (on the runner), XcodeGen, Swift | **Apple Developer Program - 99 USD/year** |
| GitHub repo + Actions allowance | |
| TestFlight (included in membership) | |
| App Store Connect, App Review | |
| CloudKit for this app's scale (included) | |
| Frankfurter/ECB exchange rates | |

Apple takes no commission on a **free** app without in-app purchases.
