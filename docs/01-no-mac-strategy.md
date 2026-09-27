# 01 - The no-Mac strategy

*Checked against published pricing/docs on 27 September 2026. Prices change - re-check the linked pages before relying on them.*

## Verdict

**Developing Familoq from Windows is practical.** Everything that truly needs macOS - compiling for iOS, running the simulator, code signing, uploading to App Store Connect - runs on GitHub-hosted macOS runners. Your iPhone runs the real app through TestFlight.

| Step | Where it runs | Needs a Mac? |
|---|---|---|
| Write Swift, YAML, docs | Windows (VS Code) | No |
| Business-logic tests (`FamiloqKit`) | GitHub Linux runner (or Swift for Windows) | No |
| Generate Xcode project | macOS runner (XcodeGen from `project.yml`) | Cloud |
| Compile app, run app tests on iOS Simulator | macOS runner | Cloud |
| Screenshots of the app | macOS runner (simulator) | Cloud |
| Signing certificate & CSR | Windows (OpenSSL in Git Bash) + Apple website | No |
| Archive, sign, upload | macOS runner | Cloud |
| Install & test | iPhone (TestFlight) | No |
| App Store listing & submission | App Store Connect website | No |

### What you give up without a Mac, and the mitigation

| Missing | Mitigation in this project |
|---|---|
| Xcode editor, SwiftUI live previews | VS Code + small commits; CI screenshots of every tab |
| Interactive simulator | Test workflow screenshots; TestFlight on the real iPhone |
| Step-debugger, Instruments | Unit tests for logic (fast on Linux); TestFlight crash reports & screenshots feedback |
| Instant compile errors | Linux job fails fast for logic; the macOS job summary lists all compiler errors |
| Fixing signing interactively | Manual signing with files you create on Windows - fully scripted |

If you ever need an interactive Mac for an hour (rare, e.g. an unusual crash), hourly cloud-Mac rentals exist. They are **not required** for this project, so no provider is prescribed.

## Why the project is structured this way

- **XcodeGen (`project.yml`)** instead of a committed `.xcodeproj`: the Xcode project file is huge, machine-written and impossible to edit safely by hand. `project.yml` is 100 lines of readable YAML you edit on Windows; the runner generates the project each time.
- **`FamiloqKit` Swift package** holds all money, currency, budget, categorisation and access logic with **only Foundation** as dependency. It compiles and tests on Linux (cheap, fast) - most bugs are caught before a single macOS minute is used.
- **No third-party runtime dependencies.** Only Apple frameworks. XcodeGen is a build-time tool on the runner.

## Cloud macOS options (verified)

### 1. GitHub Actions - **chosen**

- macOS runners: `macos-14`, `macos-15`, `macos-26` (Apple Silicon); the `macos-26` image ships **Xcode 26.0.1 - 26.6** (default 26.6) with iOS 26.x simulators.
- **Public repositories:** standard GitHub-hosted runners are **free and unlimited**.
- **Private repositories:** GitHub Free includes **2,000 minutes/month** and 500 MB artifact storage. Standard macOS runners bill at **$0.062/minute** beyond the allowance (Linux 2-core: $0.006). GitHub historically counted each macOS minute as **10** included minutes (≈200 macOS minutes/month); the current docs no longer print the multiplier - check *Settings -> Billing -> Usage* after your first runs. GitHub cut hosted-runner prices by up to 39 % from 1 January 2026.
- Estimated usage per run: Linux core tests 2-4 min · macOS build + tests 8-15 min · Test workflow with screenshots 15-25 min · Release 15-25 min.

**Recommendation:** keep the repo **private**, set a spending limit of **$0** in GitHub billing (so nothing can be charged), and watch usage for a month. If you run out:
- make the repo **public** (it contains no secrets and no financial data - but your code becomes visible), or
- run the macOS part on Codemagic (below), or
- run the macOS job only on `main`/PRs: in `build.yml` add `if: github.ref == 'refs/heads/main' || github.event_name == 'pull_request'` to the `ios` job - feature-branch pushes then only run the Linux tests.

### 2. Codemagic - **backup**

- Personal accounts: **500 free macOS M2 build minutes/month**, reset on the 1st; pay-as-you-go $0.095/min (M2) after that.
- Works with the same repo; the build commands in our workflows (`scripts/ci/*.sh`, `xcodebuild …`) transfer 1:1 into a `codemagic.yaml`.

### 3. Xcode Cloud - **backup, included with the Apple fee**

- **25 compute hours/month included** with the Apple Developer Program; extra tiers from $49.99/month.
- App Store Connect's web dashboard can edit workflows and start builds. The initial connection of a repository has traditionally been done from Xcode, so treat this as a fallback, not the primary path.

### Why not a rented Mac as the main path
Hourly/monthly cloud Macs cost money continuously and must be maintained. CI runners are ephemeral, reproducible and free or nearly free at this project's size.

## The project survives free-tier changes

- All build logic is in plain shell/`xcodebuild` commands (`scripts/ci/`), not in a vendor-specific plugin.
- Signing uses standard Apple files (certificate `.p12`, provisioning profile, App Store Connect API key) that any CI can use.
- Business logic is testable on any OS.

## Unavoidable costs

| Cost | Amount | Why |
|---|---|---|
| Apple Developer Program | **99 USD per membership year**, charged in local currency (shown at enrollment) | Required for TestFlight, App Store, distribution signing, CloudKit containers |

Not free and not avoidable if you want the App Store: that fee. Everything else in this setup can stay at €0 for a small invite-only community.

## Sources
- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [GitHub Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [2026 pricing changes for GitHub Actions](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)
- [macOS 26 runner image (Xcode versions)](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Codemagic pricing](https://docs.codemagic.io/billing/pricing/)
- [Xcode Cloud](https://developer.apple.com/xcode-cloud/)
- [Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/)
- [Apple SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/)
