import Foundation
import Security

/// Keeps the device token.
public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

/// Stores the token in the Keychain, for this device only.
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "tools.lighthouse.app"
    private let service: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device-token",
        ]
    }

    /// A build under another bundle identifier, such as one for a test server,
    /// passes its own service so that it keeps a sign-in of its own.
    public init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    public func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) {
        clear()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
