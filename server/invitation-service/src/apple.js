// Verifies "Sign in with Apple" identity tokens (RS256 JWTs signed by Apple).
// https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api/verifying_a_user

import { base64urlDecode, sha256Hex } from "./crypto.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

let cachedKeys = null;
let cachedAt = 0;

async function appleKeys(fetchKeys) {
  if (fetchKeys) return fetchKeys();
  if (cachedKeys && Date.now() - cachedAt < 6 * 3600 * 1000) return cachedKeys;
  const res = await fetch(APPLE_KEYS_URL);
  if (!res.ok) throw new AppleTokenError("apple_keys_unavailable");
  cachedKeys = (await res.json()).keys;
  cachedAt = Date.now();
  return cachedKeys;
}

export class AppleTokenError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

/**
 * @param {string} token      identity token from ASAuthorizationAppleIDCredential
 * @param {object} options
 *   audiences:  allowed bundle IDs
 *   rawNonce:   nonce the app generated; its SHA-256 (hex) must equal the token's nonce claim
 *   fetchKeys:  optional override (tests)
 *   now:        seconds (tests)
 * @returns {Promise<{sub: string, email?: string}>}
 */
export async function verifyAppleIdentityToken(token, { audiences, rawNonce, fetchKeys, now } = {}) {
  const parts = String(token ?? "").split(".");
  if (parts.length !== 3) throw new AppleTokenError("invalid_token");
  let header, payload;
  try {
    header = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(base64urlDecode(parts[1])));
  } catch {
    throw new AppleTokenError("invalid_token");
  }
  if (header.alg !== "RS256") throw new AppleTokenError("invalid_token");

  const keys = await appleKeys(fetchKeys);
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new AppleTokenError("unknown_key");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64urlDecode(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`)
  );
  if (!valid) throw new AppleTokenError("invalid_signature");

  const nowSeconds = now ?? Math.floor(Date.now() / 1000);
  if (payload.iss !== APPLE_ISSUER) throw new AppleTokenError("invalid_issuer");
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.some((a) => audiences.includes(a))) throw new AppleTokenError("invalid_audience");
  if (typeof payload.exp !== "number" || payload.exp < nowSeconds) throw new AppleTokenError("token_expired");
  if (payload.nonce) {
    if (!rawNonce || (await sha256Hex(rawNonce)) !== payload.nonce) throw new AppleTokenError("invalid_nonce");
  }
  if (!payload.sub) throw new AppleTokenError("invalid_token");
  return { sub: payload.sub, email: payload.email };
}
