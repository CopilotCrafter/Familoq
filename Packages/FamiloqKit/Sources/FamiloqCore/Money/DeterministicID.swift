import Foundation

/// A UUID derived from text: the same text gives the same UUID on every
/// iPhone. Used so two family members' iPhones booking the same recurring
/// expense create ONE record (same ID) instead of two.
public enum DeterministicID {
    public static func uuid(_ text: String) -> UUID {
        let data = Array(text.utf8)
        let a = fnv(data, seed: 0xcbf29ce484222325)
        let b = fnv(data, seed: 0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xff)
            bytes[8 + i] = UInt8((b >> (8 * UInt64(i))) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // version 5 style
        bytes[8] = (bytes[8] & 0x3f) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func fnv(_ data: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
