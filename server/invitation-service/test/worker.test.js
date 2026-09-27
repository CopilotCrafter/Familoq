import { test, describe, before } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import * as codes from "../src/codes.js";
import { base64url, sha256Hex, signToken } from "../src/crypto.js";
import { createD1 } from "./d1-shim.js";

// ---- Fake Apple: our own RSA key pair signs identity tokens -------------------
let appleKeyPair;
let appleJWK;
const BUNDLE = "com.carolandmartin.familoq";

async function appleToken({ sub = "apple-user-1", aud = BUNDLE, iss = "https://appleid.apple.com", expIn = 600, nonce, kid = "test-kid", signWith } = {}) {
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", kid })));
  const payload = { iss, aud, sub, iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + expIn };
  if (nonce) payload.nonce = await sha256Hex(nonce);
  const body = base64url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", (signWith ?? appleKeyPair).privateKey, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${base64url(sig)}`;
}

before(async () => {
  appleKeyPair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"]
  );
  const jwk = await crypto.subtle.exportKey("jwk", appleKeyPair.publicKey);
  appleJWK = { kty: "RSA", kid: "test-kid", n: jwk.n, e: jwk.e, alg: "RS256", use: "sig" };
});

// ---- Helpers ------------------------------------------------------------------
const ADMIN = "admin-token-for-tests-1234567890";
function makeEnv() {
  return {
    DB: createD1(),
    TOKEN_SECRET: "token-secret-for-tests-1234567890",
    ADMIN_TOKEN: ADMIN,
    APPLE_AUDIENCE: BUNDLE,
    TOKEN_TTL_DAYS: "90",
    __appleKeys: [appleJWK]
  };
}

let ipCounter = 0;
async function call(env, method, path, body, headers = {}) {
  const req = new Request(`https://api.test${path}`, {
    method,
    headers: { "content-type": "application/json", "cf-connecting-ip": headers.ip ?? `10.0.0.${++ipCounter % 250}`, ...headers },
    body: body ? JSON.stringify(body) : undefined
  });
  const res = await worker.fetch(req, env);
  return { status: res.status, body: await res.json().catch(() => null) };
}

const adminHeaders = { authorization: `Bearer ${ADMIN}` };

async function createCode(env, { days = 14, note = "test" } = {}) {
  const r = await call(env, "POST", "/v1/admin/invitations", { count: 1, expiresInDays: days, note }, adminHeaders);
  assert.equal(r.status, 201);
  return r.body.codes[0];
}

// ---- Code format ----------------------------------------------------------------
describe("invitation code format", () => {
  test("generated codes are well formed and formatted", () => {
    for (let i = 0; i < 500; i++) {
      const c = codes.generate();
      assert.match(c, /^[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/);
      assert.ok(codes.isWellFormed(c));
    }
  });

  test("every single-character typo is detected", () => {
    const code = [...codes.normalize(codes.generate())];
    for (let p = 0; p < code.length; p++) {
      for (const r of codes.ALPHABET) {
        if (r === code[p]) continue;
        const typo = [...code];
        typo[p] = r;
        assert.equal(codes.isWellFormed(typo.join("")), false);
      }
    }
  });

  test("matches the Swift implementation (shared test vector)", () => {
    // Same vector is asserted in FamiloqCoreTests.testCheckCharacterMatchesServer
    assert.equal(codes.checkCharacter("MBF7K92X4QP"), "7");
    assert.ok(codes.isWellFormed("MBF7-K92X-4QP7"));
  });
});

// ---- Security scenarios -------------------------------------------------------------
describe("App Invitation redemption", () => {
  test("1. without a valid code there is no account", async () => {
    const env = makeEnv();
    const r = await call(env, "POST", "/v1/invitations/redeem", { code: "AAAA-AAAA-AAAA", identityToken: await appleToken() });
    assert.equal(r.status, 400);
    assert.equal(r.body.error, "invalid_code");
    const users = env.DB.raw.prepare("SELECT COUNT(*) AS n FROM users").get();
    assert.equal(users.n, 0);
  });

  test("well-formed but unknown code is rejected", async () => {
    const env = makeEnv();
    const r = await call(env, "POST", "/v1/invitations/redeem", { code: codes.generate(), identityToken: await appleToken() });
    assert.equal(r.status, 404);
    assert.equal(r.body.error, "invalid_code");
  });

  test("5. valid invitation activates the Apple ID and returns a session", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    const r = await call(env, "POST", "/v1/invitations/redeem", { code: code.toLowerCase().replace(/-/g, " "), identityToken: await appleToken({ nonce: "n1" }), nonce: "n1" });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.status, "active");
    assert.ok(r.body.token);
    assert.equal(r.body.alreadyActivated, false);
  });

  test("3. a used invitation cannot be used by someone else", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "martin" }) });
    const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "stranger" }) });
    assert.equal(r.status, 409);
    assert.equal(r.body.error, "used");
  });

  test("same Apple ID can redeem again (reinstall) without consuming anything", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "martin" }) });
    const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "martin" }) });
    assert.equal(r.status, 200);
    assert.equal(r.body.alreadyActivated, true);
  });

  test("2. expired invitation is rejected", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    env.DB.raw.prepare("UPDATE invitations SET expires_at = ?").run(Math.floor(Date.now() / 1000) - 10);
    const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken() });
    assert.equal(r.status, 410);
    assert.equal(r.body.error, "expired");
  });

  test("4. revoked invitation is rejected", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    const list = await call(env, "GET", "/v1/admin/invitations", null, adminHeaders);
    await call(env, "POST", `/v1/admin/invitations/${list.body.invitations[0].id}/revoke`, null, adminHeaders);
    const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken() });
    assert.equal(r.status, 410);
    assert.equal(r.body.error, "revoked");
  });

  test("forged / wrong Apple tokens are rejected", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    const otherKeys = await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
    const cases = [
      await appleToken({ signWith: otherKeys }),            // wrong signature
      await appleToken({ aud: "com.evil.app" }),            // other app
      await appleToken({ iss: "https://evil.example" }),    // wrong issuer
      await appleToken({ expIn: -10 }),                     // expired
      "not-a-jwt"
    ];
    for (const identityToken of cases) {
      const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken });
      assert.equal(r.status, 401);
    }
    // Nonce mismatch
    const r = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ nonce: "right" }), nonce: "wrong" });
    assert.equal(r.status, 401);
    // Code still usable afterwards
    const ok = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken() });
    assert.equal(ok.status, 200);
  });

  test("brute force is rate limited", async () => {
    const env = makeEnv();
    let last;
    for (let i = 0; i < 22; i++) {
      last = await call(env, "POST", "/v1/invitations/redeem", { code: "AAAA-AAAA-AAAA", identityToken: "x" }, { ip: "1.2.3.4" });
    }
    assert.equal(last.status, 429);
  });
});

describe("sessions", () => {
  test("11/12. reinstall or new device: Sign in with Apple restores access", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "carol" }) });
    const r = await call(env, "POST", "/v1/session/apple", { identityToken: await appleToken({ sub: "carol" }) });
    assert.equal(r.status, 200);
    assert.ok(r.body.token);
  });

  test("restore without activation asks for a code", async () => {
    const env = makeEnv();
    const r = await call(env, "POST", "/v1/session/apple", { identityToken: await appleToken({ sub: "nobody" }) });
    assert.equal(r.status, 404);
    assert.equal(r.body.error, "not_activated");
  });

  test("refresh works, and a revoked account is locked out", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    const red = await call(env, "POST", "/v1/invitations/redeem", { code, identityToken: await appleToken({ sub: "john" }) });
    const ok = await call(env, "POST", "/v1/session/refresh", null, { authorization: `Bearer ${red.body.token}` });
    assert.equal(ok.status, 200);

    const users = await call(env, "GET", "/v1/admin/users", null, adminHeaders);
    await call(env, "POST", `/v1/admin/users/${users.body.users[0].id}/revoke`, null, adminHeaders);

    const blocked = await call(env, "POST", "/v1/session/refresh", null, { authorization: `Bearer ${red.body.token}` });
    assert.equal(blocked.status, 403);
    assert.equal(blocked.body.error, "account_revoked");
    const restore = await call(env, "POST", "/v1/session/apple", { identityToken: await appleToken({ sub: "john" }) });
    assert.equal(restore.status, 403);
  });

  test("tampered or expired session tokens are rejected", async () => {
    const env = makeEnv();
    const forged = await signToken("some-other-secret-1234567890", { sub: "x", exp: Math.floor(Date.now() / 1000) + 100 });
    assert.equal((await call(env, "POST", "/v1/session/refresh", null, { authorization: `Bearer ${forged}` })).status, 401);
    const expired = await signToken(env.TOKEN_SECRET, { sub: "x", exp: 1 });
    assert.equal((await call(env, "POST", "/v1/session/refresh", null, { authorization: `Bearer ${expired}` })).status, 401);
  });
});

describe("admin & requests", () => {
  test("admin endpoints require the admin token", async () => {
    const env = makeEnv();
    assert.equal((await call(env, "GET", "/v1/admin/invitations")).status, 401);
    assert.equal((await call(env, "GET", "/v1/admin/invitations", null, { authorization: "Bearer wrong-token-xxxxxxxxxxxx" })).status, 401);
    assert.equal((await call(env, "GET", "/v1/admin/invitations", null, adminHeaders)).status, 200);
  });

  test("codes are stored only as hashes", async () => {
    const env = makeEnv();
    const code = await createCode(env);
    const row = env.DB.raw.prepare("SELECT * FROM invitations").get();
    assert.notEqual(row.code_hash, codes.normalize(code));
    assert.equal(row.code_hash, await sha256Hex(codes.normalize(code)));
    assert.equal(row.hint, codes.normalize(code).slice(-4));
  });

  test("invitation requests are stored and rate limited", async () => {
    const env = makeEnv();
    const body = { name: "Anna", contact: "anna@example.com", message: "Hi!" };
    for (let i = 0; i < 3; i++) assert.equal((await call(env, "POST", "/v1/invitation-requests", body, { ip: "9.9.9.9" })).status, 201);
    assert.equal((await call(env, "POST", "/v1/invitation-requests", body, { ip: "9.9.9.9" })).status, 429);
    assert.equal((await call(env, "POST", "/v1/invitation-requests", { name: "", contact: "" })).status, 400);
    const list = await call(env, "GET", "/v1/admin/requests", null, adminHeaders);
    assert.equal(list.body.requests.length, 3);
  });

  test("health and admin page", async () => {
    const env = makeEnv();
    assert.equal((await call(env, "GET", "/health")).status, 200);
    const res = await worker.fetch(new Request("https://api.test/admin"), env);
    assert.equal(res.status, 200);
    assert.match(await res.text(), /Familoq invitations/);
  });
});
