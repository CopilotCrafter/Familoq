# 08 - Automatic delivery: TestFlight and App Store

```
git push (main) ─▶ Build ✅ ─▶ Release ─▶ TestFlight ─▶ your iPhone (auto-update in TestFlight)

git tag v1.2.0 && git push --tags
               ─▶ Release ─▶ upload ─▶ wait for Apple processing ─▶ submit v1.2.0 for review
                                                                  ─▶ Apple review (~24 h)
                                                                  ─▶ live (auto or one click)
```

## What is automatic

| Trigger | Result | Switch |
|---|---|---|
| Push/merge to `main` and the Build workflow is green | New TestFlight build (only the tested commit is released) | variable `AUTO_TESTFLIGHT` (`false` = off) |
| Push a tag `vX.Y.Z` | Build X.Y.Z -> TestFlight -> **submitted for App Store review** | variable `APP_STORE_SUBMISSIONS` must be `true` |
| Apple approves | Goes live immediately | variable `APP_STORE_AUTO_RELEASE` = `true` (otherwise click *Release* in App Store Connect) |
| Manual | Actions -> *Release (TestFlight / App Store)* -> Run workflow (tick *submit for review* if wanted) | - |

Variables: GitHub -> *Settings -> Secrets and variables -> Actions -> Variables*.

Until the 8 Apple secrets exist, automatic runs are **skipped with a notice**, not failed - so the pipeline is already live and starts delivering the moment you add them.

## What can never be automatic
- **Apple's review** of every App Store version. No tool or API can skip it.
- **The first App Store listing**, done once in App Store Connect (web): description, keywords, support & privacy-policy URL, screenshots, App Privacy answers, age rating, price (free), category (Finance), and *App Review Information* with a **demo invitation code**. After that, every submission reuses it.
- **Only one version in review at a time.** A new tag while one is in review fails the submission step (the TestFlight upload still succeeds).

## Why App Store submissions start switched OFF
`APP_STORE_SUBMISSIONS` is off by default so a stray tag cannot send an unfinished app to Apple. Phase 1 has **no invitation gate yet** - on the App Store anybody could use it, which breaks the invite-only rule, and a review rejection is likely. Recommended moment to switch it on: after Phase 3 (invitations) and the Phase 6 checks.

## Releasing a version (when enabled)
```powershell
git switch main; git pull
git tag v1.0.0
git push origin v1.0.0
```
The version must be higher than the last App Store version. Build numbers are automatic.

## Minute budget (private repo)
Every push to `main` = Build (~6 min macOS) + Release (~15-25 min macOS). Work on branches and merge to `main` when a change is worth installing, or set `AUTO_TESTFLIGHT=false` and release manually. Details: [01-no-mac-strategy.md](01-no-mac-strategy.md).

## Tools
- TestFlight uploads: Apple's own `altool` / `xcodebuild` (scripts/ci/upload-testflight.sh).
- App Store submission: [fastlane](https://fastlane.tools) (`fastlane/Fastfile`) on the runner only - it waits for Apple's processing and submits via the App Store Connect API key. Nothing is installed on Windows.
