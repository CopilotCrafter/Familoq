// App Invitation codes - the SAME format as FamiloqCore/Family/InvitationCode.swift:
// 12 characters from a 32-symbol alphabet (no 0/O/1/I), grouped XXXX-XXXX-XXXX,
// last character = Luhn mod 32 check character (catches every single typo).

export const ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
export const LENGTH = 12;
const N = ALPHABET.length;

export function normalize(input) {
  return String(input ?? "").toUpperCase().replace(/[\s-]/g, "");
}

export function format(input) {
  const n = normalize(input);
  return n.match(/.{1,4}/g)?.join("-") ?? "";
}

function luhnSum(chars, startFactor) {
  let factor = startFactor;
  let sum = 0;
  for (let i = chars.length - 1; i >= 0; i--) {
    const code = Math.max(ALPHABET.indexOf(chars[i]), 0);
    let addend = factor * code;
    factor = factor === 2 ? 1 : 2;
    addend = Math.floor(addend / N) + (addend % N);
    sum += addend;
  }
  return sum;
}

export function checkCharacter(payload) {
  const sum = luhnSum([...payload], 2);
  return ALPHABET[(N - (sum % N)) % N];
}

export function isWellFormed(input) {
  const chars = [...normalize(input)];
  if (chars.length !== LENGTH) return false;
  if (!chars.every((c) => ALPHABET.includes(c))) return false;
  return luhnSum(chars, 1) % N === 0;
}

export function generate() {
  const bytes = new Uint8Array(LENGTH - 1);
  crypto.getRandomValues(bytes);
  const payload = [...bytes].map((b) => ALPHABET[b % N]).join(""); // 256 % 32 == 0 -> unbiased
  return format(payload + checkCharacter(payload));
}
