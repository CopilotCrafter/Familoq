# 03 - GitHub repository and CI/CD

## Pipeline

```
push / PR ─▶ build.yml ─┬─ core-tests (Linux, swift:6.1 container)
                        │     swift test in Packages/FamiloqKit
                        └─ ios (macos-26)  [runs only if core-tests pass]
                              XcodeGen -> xcodebuild test on iPhone simulator
                              step summary lists compiler errors
                              logs + .xcresult uploaded on failure

manual / PR to main ─▶ test.yml
                              core tests + app tests with code coverage
                              screenshots of all 5 tabs (light) + dashboard (dark)
                              artifact: familoq-screenshots-and-coverage

manual / tag v* ─▶ release.yml
                              decode secrets -> temporary keychain
                              write Config/Signing.generated.xcconfig
                              archive -> export .ipa -> upload to TestFlight
                              artifact: Familoq-ipa-build-N
                              always: delete keychain, keys, profiles
```

## What each automated test covers

| Area (spec §29) | Where |
|---|---|
| Budget calculations & warnings (75/90/100 %) | `FamiloqBudgetTests/BudgetTests` |
| Safe-to-spend (incl. spec example €27.20/day) | `FamiloqBudgetTests/BudgetTests` |
| Merchant categorisation, user rules | `FamiloqBudgetTests/CategorizationTests`, `FamiloqTests/CategorizationFlowTests` |
| Grocery subcategories (item level, German receipts) | `FamiloqBudgetTests/CategorizationTests` |
| Invitations (code format, typo detection) | `FamiloqCoreTests/FamilyAndInvitationTests` |
| Family isolation (policy + repository) | `FamiloqCoreTests/FamilyAndInvitationTests`, `FamiloqTests/PersistenceTests` |
| Currency conversion, offline, base-currency change | `FamiloqCoreTests/CurrencyConversionTests`, `FamiloqTests/CurrencyConversionFlowTests` |
| Import/export | Phase 5 |
| Recurring expenses | Phase 5 |

## Branching (simple)
- `main` - always releasable. Protect it: *Settings -> Branches -> Add rule* -> require status checks **Core logic tests (Linux)** and **iOS build & app tests (macOS)**.
- Feature work: `git switch -c phase2-receipts`, push, open a pull request, merge when green.

## Versioning
- `MARKETING_VERSION` (what users see) lives in `Config/App.xcconfig`, or pass it when running the release workflow, or push a tag `v0.2.0`.
- Build number = GitHub run number (+ optional repository variable `BUILD_NUMBER_OFFSET`). Always increasing, as App Store Connect requires.

## Repository variables (optional)
*Settings -> Secrets and variables -> Actions -> Variables*

| Variable | Purpose |
|---|---|
| `XCODE_VERSION` | Pin an Xcode, e.g. `26.6`. Empty = runner default. |
| `BUILD_NUMBER_OFFSET` | Add to the run number, e.g. if you ever uploaded builds from elsewhere. |

## Secrets policy
- Never commit certificates, keys, profiles or passwords. `.gitignore` blocks `*.p12 *.p8 *.key *.cer *.mobileprovision` and the generated signing xcconfig.
- Workflows run with `permissions: contents: read`.
- Secrets are only used in `release.yml`, which runs on manual dispatch or tags - never on pull requests from forks.
- Optional hardening: create an **Environment** `testflight` with yourself as required reviewer and move the secrets there; add `environment: testflight` to the release job.

## Daily loop from Windows

```powershell
git switch -c my-change
# edit in VS Code
git commit -am "Explain what changed"
git push -u origin my-change
gh run watch                     # or watch the Actions tab
gh pr create --fill              # merge when green
```

Reading a failed build without a Mac:
1. Open the failed run -> the **Summary** shows the compiler errors (file:line: error).
2. Download `ios-build-logs` for the full log.
3. Fix in VS Code, push again.

## Line endings
`.gitattributes` forces LF for all text files. This matters on Windows: CRLF shell scripts and xcconfig files break on the macOS runner.

## Minute budget (private repo)
See [01-no-mac-strategy.md](01-no-mac-strategy.md#1-github-actions---chosen). Docs-only commits (`docs/**`, `*.md`) skip the build; a new push cancels the previous run of the same branch.
