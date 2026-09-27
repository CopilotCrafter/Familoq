# 09 - Invitation service (App Invitations)

Familoq is invite-only. The **invitation service** decides who may use the app (Level 1). It is a small Cloudflare Worker with a D1 (SQLite) database, deployed automatically by GitHub Actions. Family data **never** passes through it - it stores only hashed invitation codes, hashed Apple IDs, statuses and dates.

```
iPhone ── Sign in with Apple ──▶ Apple identity token
iPhone ── code + token ──▶ familoq-api.carolandmartin.com  (Cloudflare Worker)
                              verifies Apple's signature, audience, expiry, nonce
                              redeems the code atomically (only once, not expired, not revoked)
                              returns a session token (90 days, refreshed daily)
```

## One-time setup (≈15 min, all in the browser)

### 1. Cloudflare API token
dash.cloudflare.com → **My Profile → API Tokens → Create Token** → template **Edit Cloudflare Workers** → *Use template*:
- **Add permission**: *Account* → **D1** → **Edit**
- *Account Resources*: your account
- *Zone Resources*: *Specific zone* → `carolandmartin.com` (needed for the custom domain)
- Continue → Create → copy the token (shown once).

### 2. Account ID
dash.cloudflare.com → *Workers & Pages* → the **Account ID** is shown on the right side of the overview (or in the URL after `dash.cloudflare.com/`).

### 3. Two random secrets (PowerShell)
```powershell
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 40 | ForEach-Object {[char]$_})   # FAMILOQ_ADMIN_TOKEN - save it in your password manager
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 48 | ForEach-Object {[char]$_})   # FAMILOQ_TOKEN_SECRET - never change it later
```

### 4. GitHub secrets and variable
GitHub → Familoq → *Settings → Secrets and variables → Actions*:

| Type | Name | Value |
|---|---|---|
| Secret | `CLOUDFLARE_API_TOKEN` | token from step 1 |
| Secret | `CLOUDFLARE_ACCOUNT_ID` | ID from step 2 |
| Secret | `FAMILOQ_ADMIN_TOKEN` | first random string |
| Secret | `FAMILOQ_TOKEN_SECRET` | second random string |
| **Variable** | `FAMILOQ_API_DOMAIN` | `familoq-api.carolandmartin.com` |

The app is built with `https://familoq-api.carolandmartin.com` (`FQ_INVITE_SERVICE_URL` in `Config/App.xcconfig`). If you choose another domain, change both.

### 5. Deploy
Merging to `main` deploys automatically (workflow **Invitation service**), or run it manually from the Actions tab. The first run creates the D1 database, applies the schema, deploys the Worker, attaches the domain and sets the two secrets. The run summary shows the API and admin URLs.

## Daily use - the admin page
Open **https://familoq-api.carolandmartin.com/admin** (phone or PC) → paste `FAMILOQ_ADMIN_TOKEN` → Unlock.

- **Create codes**: count, validity (days), note (e.g. "John & Sarah") → the codes are shown **once** - copy and send them. Only a hash is stored.
- **Invitations**: status (active / used / expired / revoked), revoke unused codes.
- **Activated accounts**: revoke or restore access. A revoked account is signed out on its next daily check.
- **Invitation requests**: messages sent from the app's *Request an Invitation* screen.

## Security properties (tested in `server/invitation-service/test/worker.test.js`)
- Apple identity tokens verified with Apple's public keys (signature, issuer, audience = bundle ID, expiry, nonce).
- A code works **once**; redemption is atomic; expired/revoked codes are rejected.
- Codes stored only as SHA-256 hashes; Apple IDs only as HMAC.
- Failed attempts and invitation requests are rate-limited per IP.
- Admin endpoints require the admin token (constant-time comparison).
- Reinstall / new device: the same Apple ID signs in again - no new code needed.

## Costs
Cloudflare's **free plan** covers Workers and D1 at this scale (a small invite-only community). No card is needed.

## If the service is down
Activated users keep using Familoq normally (offline-first). Only new activations and the daily check wait until it is back.
