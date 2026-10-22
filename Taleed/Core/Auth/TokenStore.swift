import Foundation
import Security

/// Keeps the session token between launches. Never log the token.
protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func delete()
}

/// Stores the token in the Keychain, readable after the first unlock and never synced or backed up
/// to another device.
struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "session_token"

    init(service: String = Bundle.main.bundleIdentifier ?? "app.taleed.mobile") {
        self.service = service
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query = baseQuery.merging(attributes) { _, new in new }
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
