// Small crypto helpers built on WebCrypto (available in Cloudflare Workers and Node 20+).

const enc = new TextEncoder();

export function base64url(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (const x of b) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlDecode(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function hex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(text) {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(text)));
}

async function hmacKey(secret) {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function hmacHex(secret, text) {
  const key = await hmacKey(secret);
  return hex(await crypto.subtle.sign("HMAC", key, enc.encode(text)));
}

/** Compact HS256 JWT used as the Familoq session token. */
export async function signToken(secret, payload) {
  const header = base64url(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = base64url(enc.encode(JSON.stringify(payload)));
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${header}.${body}`));
  return `${header}.${body}.${base64url(sig)}`;
}

/** Returns the payload if the signature is valid and the token is not expired, else null. */
export async function verifyToken(secret, token, nowSeconds = Math.floor(Date.now() / 1000)) {
  const parts = String(token ?? "").split(".");
  if (parts.length !== 3) return null;
  const [header, body, sig] = parts;
  try {
    const key = await hmacKey(secret);
    const ok = await crypto.subtle.verify("HMAC", key, base64urlDecode(sig), enc.encode(`${header}.${body}`));
    if (!ok) return null;
    const payload = JSON.parse(new TextDecoder().decode(base64urlDecode(body)));
    if (typeof payload.exp !== "number" || payload.exp < nowSeconds) return null;
    return payload;
  } catch {
    return null;
  }
}
