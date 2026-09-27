import Foundation
import Security

/// Where the activation is kept on the device.
protocol AccountStorage {
    func load() -> StoredAccount?
    func save(_ account: StoredAccount) throws
    func delete()
}

/// What Familoq remembers about the person using this iPhone (never financial data).
struct StoredAccount: Codable, Equatable {
    /// CloudKit user record name of the iCloud account (stable per app and Apple ID).
    var userRecordName: String
    var isAdmin: Bool
    var activatedAt: Date
    var lastCheckedAt: Date
}

/// Keychain-backed storage (this device only).
struct KeychainAccountStorage: AccountStorage {
    private let service = "com.carolandmartin.familoq.access"
    private let key = "current"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func load() -> StoredAccount? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredAccount.self, from: data)
    }

    func save(_ account: StoredAccount) throws {
        let data = try JSONEncoder().encode(account)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory storage for tests and CI screenshots.
final class InMemoryAccountStorage: AccountStorage {
    var account: StoredAccount?
    init(_ account: StoredAccount? = nil) { self.account = account }
    func load() -> StoredAccount? { account }
    func save(_ account: StoredAccount) throws { self.account = account }
    func delete() { account = nil }
}
