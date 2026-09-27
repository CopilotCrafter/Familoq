// Familoq invitation service - Cloudflare Worker + D1.
//
// Level 1 of Familoq's access model: an App Invitation code lets one Apple ID
// use Familoq. Family data NEVER passes through this service.
//
// Public endpoints (used by the iOS app)
//   GET  /health
//   POST /v1/invitations/redeem     {code, identityToken, nonce}  -> {status, token, expiresAt}
//   POST /v1/session/apple          {identityToken, nonce}        -> restore on reinstall / new device
//   POST /v1/session/refresh        Authorization: Bearer <token> -> {status, token}
//   POST /v1/invitation-requests    {name, contact, message}
//
// Admin (Authorization: Bearer <ADMIN_TOKEN>)
//   GET  /admin                                  simple admin page
//   GET  /v1/admin/invitations
//   POST /v1/admin/invitations                   {count, expiresInDays, note}
//   POST /v1/admin/invitations/:id/revoke
//   GET  /v1/admin/users
//   POST /v1/admin/users/:id/revoke | /restore
//   GET  /v1/admin/requests
//   POST /v1/admin/requests/:id/done

import * as codes from "./codes.js";
import { sha256Hex, hmacHex, signToken, verifyToken } from "./crypto.js";
import { verifyAppleIdentityToken, AppleTokenError } from "./apple.js";
import { adminPage } from "./admin.js";

const DAY = 86400;

const json = (body, status = 200, extraHeaders = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extraHeaders }
  });

const fail = (status, error, message) => json({ error, message }, status);

const now = () => Math.floor(Date.now() / 1000);

async function readJSON(request) {
  try {
    const text = await request.text();
    if (text.length > 10_000) return null;
    return JSON.parse(text || "{}");
  } catch {
    return null;
  }
}

function clientKey(request) {
  return request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for") || "unknown";
}

async function rateLimited(env, kind, request, limit, windowSeconds) {
  const keyHash = await sha256Hex(`${kind}:${clientKey(request)}`);
  const since = now() - windowSeconds;
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM rate_events WHERE kind = ? AND key_hash = ? AND created_at > ?")
    .bind(kind, keyHash, since).first();
  return { limited: (row?.n ?? 0) >= limit, keyHash };
}

async function recordRateEvent(env, kind, keyHash) {
  await env.DB.prepare("INSERT INTO rate_events (kind, key_hash, created_at) VALUES (?, ?, ?)").bind(kind, keyHash, now()).run();
}

function audiences(env) {
  return String(env.APPLE_AUDIENCE || "").split(",").map((s) => s.trim()).filter(Boolean);
}

async function appleSubject(env, body) {
  const result = await verifyAppleIdentityToken(body.identityToken, {
    audiences: audiences(env),
    rawNonce: body.nonce,
    fetchKeys: env.__appleKeys ? async () => env.__appleKeys : undefined
  });
  return hmacHex(env.TOKEN_SECRET, `apple:${result.sub}`);
}

async function issueToken(env, user) {
  const ttlDays = Number(env.TOKEN_TTL_DAYS || 90);
  const exp = now() + ttlDays * DAY;
  const token = await signToken(env.TOKEN_SECRET, { sub: user.id, iat: now(), exp, v: 1 });
  await env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(now(), user.id).run();
  return { status: "active", token, expiresAt: exp };
}

// MARK: Public handlers

async function redeem(request, env) {
  const body = await readJSON(request);
  if (!body) return fail(400, "bad_request", "Invalid JSON body.");

  const { limited, keyHash } = await rateLimited(env, "redeem_fail", request, 20, 3600);
  if (limited) return fail(429, "rate_limited", "Too many attempts. Please wait an hour.");

  const code = codes.normalize(body.code);
  if (!codes.isWellFormed(code)) {
    await recordRateEvent(env, "redeem_fail", keyHash);
    return fail(400, "invalid_code", "This invitation code is not valid. Please check for typos.");
  }

  let subHash;
  try {
    subHash = await appleSubject(env, body);
  } catch (e) {
    return fail(401, "invalid_apple_token", `Sign in with Apple could not be verified (${e instanceof AppleTokenError ? e.code : "error"}).`);
  }

  // Same Apple ID already activated (e.g. reinstall): no code needed.
  const existing = await env.DB.prepare("SELECT * FROM users WHERE apple_sub_hash = ?").bind(subHash).first();
  if (existing) {
    if (existing.status !== "active") return fail(403, "account_revoked", "Access to Familoq has been revoked for this account.");
    return json({ ...(await issueToken(env, existing)), alreadyActivated: true });
  }

  const codeHash = await sha256Hex(code);
  const invitation = await env.DB.prepare("SELECT * FROM invitations WHERE code_hash = ?").bind(codeHash).first();
  if (!invitation) {
    await recordRateEvent(env, "redeem_fail", keyHash);
    return fail(404, "invalid_code", "This invitation code does not exist.");
  }
  if (invitation.status === "revoked") return fail(410, "revoked", "This invitation has been revoked.");
  if (invitation.status === "used") return fail(409, "used", "This invitation has already been used.");
  if (invitation.expires_at <= now()) return fail(410, "expired", "This invitation has expired. Please ask for a new one.");

  const userId = crypto.randomUUID();
  // Atomic: only one person can ever redeem a code.
  const claim = await env.DB.prepare(
    "UPDATE invitations SET status = 'used', redeemed_by = ?, redeemed_at = ? WHERE id = ? AND status = 'active' AND expires_at > ?"
  ).bind(userId, now(), invitation.id, now()).run();
  if ((claim.meta?.changes ?? 0) !== 1) return fail(409, "used", "This invitation has already been used.");

  const user = { id: userId };
  await env.DB.prepare("INSERT INTO users (id, apple_sub_hash, status, invitation_id, created_at) VALUES (?, ?, 'active', ?, ?)")
    .bind(userId, subHash, invitation.id, now()).run();
  return json({ ...(await issueToken(env, user)), alreadyActivated: false });
}

async function restoreWithApple(request, env) {
  const body = await readJSON(request);
  if (!body) return fail(400, "bad_request", "Invalid JSON body.");
  let subHash;
  try {
    subHash = await appleSubject(env, body);
  } catch (e) {
    return fail(401, "invalid_apple_token", `Sign in with Apple could not be verified (${e instanceof AppleTokenError ? e.code : "error"}).`);
  }
  const user = await env.DB.prepare("SELECT * FROM users WHERE apple_sub_hash = ?").bind(subHash).first();
  if (!user) return fail(404, "not_activated", "This Apple ID has not been activated yet. Enter your invitation code.");
  if (user.status !== "active") return fail(403, "account_revoked", "Access to Familoq has been revoked for this account.");
  return json(await issueToken(env, user));
}

async function refresh(request, env) {
  const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  const payload = await verifyToken(env.TOKEN_SECRET, token);
  if (!payload) return fail(401, "invalid_session", "Session expired. Please sign in with Apple again.");
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(payload.sub).first();
  if (!user) return fail(401, "invalid_session", "Unknown account.");
  if (user.status !== "active") return fail(403, "account_revoked", "Access to Familoq has been revoked for this account.");
  return json(await issueToken(env, user));
}

async function requestInvitation(request, env) {
  const body = await readJSON(request);
  if (!body) return fail(400, "bad_request", "Invalid JSON body.");
  const name = String(body.name ?? "").trim().slice(0, 100);
  const contact = String(body.contact ?? "").trim().slice(0, 200);
  const message = String(body.message ?? "").trim().slice(0, 1000);
  if (name.length < 2 || contact.length < 3) return fail(400, "missing_fields", "Please enter your name and how we can reach you.");

  const { limited, keyHash } = await rateLimited(env, "request", request, 3, DAY);
  if (limited) return fail(429, "rate_limited", "You have already sent a request today.");
  await recordRateEvent(env, "request", keyHash);

  await env.DB.prepare("INSERT INTO invitation_requests (id, name, contact, message, created_at) VALUES (?, ?, ?, ?, ?)")
    .bind(crypto.randomUUID(), name, contact, message, now()).run();
  return json({ status: "received" }, 201);
}

// MARK: Admin

async function isAdmin(request, env) {
  const given = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!env.ADMIN_TOKEN || env.ADMIN_TOKEN.length < 16 || !given) return false;
  // Constant-time comparison of hashes.
  const [a, b] = await Promise.all([sha256Hex(given), sha256Hex(env.ADMIN_TOKEN)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function admin(request, env, path) {
  if (!(await isAdmin(request, env))) return fail(401, "unauthorized", "Admin token required.");
  const method = request.method;

  if (method === "GET" && path === "/v1/admin/invitations") {
    const { results } = await env.DB.prepare(
      "SELECT id, hint, status, note, created_at, expires_at, redeemed_at FROM invitations ORDER BY created_at DESC LIMIT 500"
    ).all();
    return json({ invitations: results.map((r) => ({ ...r, expired: r.status === "active" && r.expires_at <= now() })) });
  }

  if (method === "POST" && path === "/v1/admin/invitations") {
    const body = (await readJSON(request)) ?? {};
    const count = Math.min(Math.max(Number(body.count) || 1, 1), 50);
    const days = Math.min(Math.max(Number(body.expiresInDays) || 14, 1), 365);
    const note = String(body.note ?? "").slice(0, 200);
    const created = [];
    for (let i = 0; i < count; i++) {
      const code = codes.generate();
      const normalized = codes.normalize(code);
      await env.DB.prepare(
        "INSERT INTO invitations (id, code_hash, hint, status, note, created_at, expires_at) VALUES (?, ?, ?, 'active', ?, ?, ?)"
      ).bind(crypto.randomUUID(), await sha256Hex(normalized), normalized.slice(-4), note, now(), now() + days * DAY).run();
      created.push(code);
    }
    // Codes are only returned ONCE - only their hashes are stored.
    return json({ codes: created, expiresInDays: days }, 201);
  }

  let m;
  if (method === "POST" && (m = path.match(/^\/v1\/admin\/invitations\/([\w-]+)\/revoke$/))) {
    const r = await env.DB.prepare("UPDATE invitations SET status = 'revoked' WHERE id = ? AND status = 'active'").bind(m[1]).run();
    return json({ revoked: (r.meta?.changes ?? 0) === 1 });
  }

  if (method === "GET" && path === "/v1/admin/users") {
    const { results } = await env.DB.prepare(
      "SELECT u.id, u.status, u.created_at, u.last_seen_at, i.hint, i.note FROM users u LEFT JOIN invitations i ON i.id = u.invitation_id ORDER BY u.created_at DESC LIMIT 500"
    ).all();
    return json({ users: results });
  }

  if (method === "POST" && (m = path.match(/^\/v1\/admin\/users\/([\w-]+)\/(revoke|restore)$/))) {
    const status = m[2] === "revoke" ? "revoked" : "active";
    const r = await env.DB.prepare("UPDATE users SET status = ? WHERE id = ?").bind(status, m[1]).run();
    return json({ updated: (r.meta?.changes ?? 0) === 1, status });
  }

  if (method === "GET" && path === "/v1/admin/requests") {
    const { results } = await env.DB.prepare(
      "SELECT id, name, contact, message, status, created_at FROM invitation_requests ORDER BY created_at DESC LIMIT 500"
    ).all();
    return json({ requests: results });
  }

  if (method === "POST" && (m = path.match(/^\/v1\/admin\/requests\/([\w-]+)\/done$/))) {
    const r = await env.DB.prepare("UPDATE invitation_requests SET status = 'done' WHERE id = ?").bind(m[1]).run();
    return json({ updated: (r.meta?.changes ?? 0) === 1 });
  }

  return fail(404, "not_found", "Unknown admin endpoint.");
}

// MARK: Router

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    try {
      if (!env.TOKEN_SECRET || env.TOKEN_SECRET.length < 16) {
        return fail(500, "not_configured", "TOKEN_SECRET is not configured.");
      }
      if (request.method === "GET" && path === "/health") return json({ ok: true, service: "familoq-invitations" });
      if (request.method === "GET" && path === "/admin") {
        return new Response(adminPage, {
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "no-store",
            "content-security-policy": "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
            "x-frame-options": "DENY",
            "referrer-policy": "no-referrer"
          }
        });
      }
      if (request.method === "POST" && path === "/v1/invitations/redeem") return await redeem(request, env);
      if (request.method === "POST" && path === "/v1/session/apple") return await restoreWithApple(request, env);
      if (request.method === "POST" && path === "/v1/session/refresh") return await refresh(request, env);
      if (request.method === "POST" && path === "/v1/invitation-requests") return await requestInvitation(request, env);
      if (path.startsWith("/v1/admin/")) return await admin(request, env, path);
      return fail(404, "not_found", "Not found.");
    } catch (e) {
      console.error(e);
      return fail(500, "server_error", "Something went wrong. Please try again.");
    }
  }
};
