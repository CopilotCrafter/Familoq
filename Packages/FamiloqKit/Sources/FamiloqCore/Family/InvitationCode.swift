import Foundation

/// Format of App Invitation codes, e.g. `MBF7-K92X-4QPL`.
///
/// * 12 characters from a 32-symbol alphabet without look-alikes (no 0/O, 1/I)
/// * 11 random characters (~55 bits) + 1 Luhn mod 32 check character, so
///   typos are detected on the device before any network call.
///
/// IMPORTANT: a well-formed code is NOT a valid invitation. Whether a code
/// exists, is unused, unexpired and not revoked is decided server-side in
/// Phase 3 (see docs/04-families-invitations-cloudkit.md).
public enum InvitationCode {
    public static let alphabet: [Character] = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    public static let length = 12

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public static func generate<R: RandomNumberGenerator>(using generator: inout R) -> String {
        var chars: [Character] = []
        for _ in 0..<(length - 1) {
            let index = Int(generator.next() % UInt64(alphabet.count))
            chars.append(alphabet[index])
        }
        chars.append(checkCharacter(for: chars))
        return format(String(chars))
    }

    /// Uppercases and strips spaces/dashes: "mbf7 k92x-4qpl" -> "MBF7K92X4QPL".
    public static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { !$0.isWhitespace && $0 != "-" })
    }

    /// "MBF7K92X4QPL" -> "MBF7-K92X-4QPL"
    public static func format(_ input: String) -> String {
        let n = Array(normalize(input))
        var out = ""
        for (i, c) in n.enumerated() {
            if i > 0 && i % 4 == 0 { out.append("-") }
            out.append(c)
        }
        return out
    }

    /// Checks length, alphabet and check character (catches single typos).
    public static func isWellFormed(_ input: String) -> Bool {
        let chars = Array(normalize(input))
        guard chars.count == length, chars.allSatisfy({ alphabet.contains($0) }) else { return false }
        return luhnSum(chars, startFactor: 1) % alphabet.count == 0
    }

    static func checkCharacter(for payload: [Character]) -> Character {
        let n = alphabet.count
        let sum = luhnSum(payload, startFactor: 2)
        let check = (n - (sum % n)) % n
        return alphabet[check]
    }

    /// Luhn mod N, processing from the right.
    private static func luhnSum(_ chars: [Character], startFactor: Int) -> Int {
        let n = alphabet.count
        var factor = startFactor
        var sum = 0
        for c in chars.reversed() {
            let code = alphabet.firstIndex(of: c) ?? 0
            var addend = factor * code
            factor = factor == 2 ? 1 : 2
            addend = addend / n + addend % n
            sum += addend
        }
        return sum
    }
}
