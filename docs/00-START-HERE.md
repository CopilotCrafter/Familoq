# 00 - Start here: what to create, in order

Everything below is done from **Windows** and your **iPhone**. No Mac.
Time: about 2 hours of your time, plus Apple's enrollment processing (often same day, sometimes up to 48 h).

Legend: 🆓 free · 💶 costs money · ⏱ waiting time

---

## A. On your Windows PC (🆓, ~20 min)

1. **Git for Windows** - https://git-scm.com/download/win
   Includes *Git Bash* and *OpenSSL*, which you need later to create the signing certificate.
   ```powershell
   winget install --id Git.Git -e
   ```
2. **Visual Studio Code** - https://code.visualstudio.com
   ```powershell
   winget install --id Microsoft.VisualStudioCode -e
   ```
   Open the repo folder; VS Code offers the recommended extensions (Swift, YAML, GitHub Actions, GitLens).
3. **GitHub CLI** (optional, lets you watch builds from the terminal)
   ```powershell
   winget install --id GitHub.cli -e
   gh auth login
   ```
4. *(Optional)* **Swift for Windows** - lets you run the business-logic tests locally in seconds instead of waiting for CI:
   ```powershell
   winget install --id Swift.Toolchain -e     # then, in Packages\FamiloqKit:  swift test
   ```
   The iOS app itself can only be compiled on macOS - that is what the cloud runner does.

## B. On GitHub (🆓, ~10 min)

1. Create a GitHub account if needed (you can reuse an existing one).
2. Create a **new private repository** named `familoq` - *no* README/.gitignore (the project already has them).
3. Push this project:
   ```powershell
   cd C:\dev\familoq                    # wherever you unzipped the project
   git init -b main                     # skip if the folder already contains .git
   git add -A
   git commit -m "Phase 1: Familoq budget module and CI"
   git remote add origin https://github.com/<you>/familoq.git
   git push -u origin main
   ```
4. Open **Actions** in the repo. The **Build** workflow starts automatically.
   - `Core logic tests (Linux)` - ~2-4 min
   - `iOS build & app tests (macOS)` - ~8-15 min
5. Run **Actions -> Test -> Run workflow** once. Download the `familoq-screenshots-and-coverage` artifact to see the app running on a simulated iPhone.

> Private vs public repo: see *GitHub Actions minutes* in [01-no-mac-strategy.md](01-no-mac-strategy.md). Start private.

## C. Apple account (💶 99 USD/year + ⏱)

Details and screenshots-free click paths: [02-apple-account-and-signing.md](02-apple-account-and-signing.md).

1. **Apple Account with two-factor authentication** - your normal Apple ID from the iPhone works. It must use your **legal name**.
2. **Enroll in the Apple Developer Program** as an *Individual* - easiest in the **Apple Developer app** on your iPhone (Account -> Enroll). Pay the annual fee. ⏱ Wait for the confirmation email.
3. On **developer.apple.com -> Certificates, IDs & Profiles** (web browser on Windows):
   1. **Identifiers -> +** -> App IDs -> App -> Bundle ID **explicit**: `com.carolandmartin.familoq`
      (If you choose another ID, change `FQ_BUNDLE_ID` in `Config/App.xcconfig`.)
   2. **Certificates -> +** -> *Apple Distribution* -> upload a CSR you create in Git Bash (commands in doc 02).
   3. **Profiles -> +** -> *App Store Connect* -> select the App ID and the certificate -> name it `Familoq AppStore` -> download.
4. On **appstoreconnect.apple.com**:
   1. **Apps -> + -> New App**: platform iOS, name **Familoq** (must be unique on the App Store - if taken, e.g. "Familoq - Family Space"), primary language, bundle ID, SKU `familoq`.
   2. **Users and Access -> Integrations -> App Store Connect API -> Team Keys -> +**: name `GitHub CI`, access **App Manager**. Download the `.p8` file (**only downloadable once**). Note the *Key ID* and *Issuer ID*.
5. On the iPhone: install **TestFlight** from the App Store.

## D. Connect Apple and GitHub (🆓, ~15 min)

In GitHub: **Settings -> Secrets and variables -> Actions -> New repository secret**. Create these 8 secrets (how to get each value: doc 02, section 7):

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | 10-character Team ID (developer.apple.com -> Membership) |
| `IOS_DIST_CERT_P12_BASE64` | your `.p12` file as base64 |
| `IOS_DIST_CERT_PASSWORD` | the password you gave the `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | the `.mobileprovision` file as base64 |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_PRIVATE_KEY` | full text of `AuthKey_XXXXXX.p8` (including BEGIN/END lines) |
| `KEYCHAIN_PASSWORD` | any long random string |

Then **delete the local copies** of the `.p12`, `.key` and `.p8` files, or move them into a password manager. They must never be committed (`.gitignore` blocks them anyway).

## E. First build on your iPhone (⏱ ~30-60 min total)

1. GitHub -> **Actions -> Release to TestFlight -> Run workflow** (leave version empty).
2. When it is green, App Store Connect -> your app -> **TestFlight**. The build shows *Processing* (5-30 min).
3. TestFlight -> **Internal Testing -> +** create group "Family", add yourself (your Apple ID must be a user in App Store Connect - the account holder already is).
4. On the iPhone, open **TestFlight** -> Familoq -> **Install**.

Internal testers (up to 100 App Store Connect users) need **no Apple review**. Friends outside your account are *external testers* and need a one-time Beta App Review per version - see doc 02.

## F. What "done" looks like for Phase 1

- [ ] Build workflow green on `main`
- [ ] Test workflow green, screenshots downloaded
- [ ] Release workflow green, build installed via TestFlight
- [ ] On the phone: add a quick expense, a detailed expense in USD, set a monthly budget, see Safe to spend

When all four are ticked, Phase 2 (receipt scanning) starts.
