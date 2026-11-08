import Foundation
import Security

/// Names one sign-in: a server, a user on it and the tenant the token is bound to.
/// Tokens of servers before 0.2, or of a sign-in not yet confirmed by `/me`,
/// have no user or tenant.
public struct TokenKey: Hashable, Sendable {
    public let server: String
    public let user: UUID?
    public let tenant: UUID?

    public init(server: String, user: UUID? = nil, tenant: UUID? = nil) {
        self.server = server
        self.user = user
        self.tenant = tenant
    }

    private static let separator: Character = "|"
    private static let none = "-"

    /// The Keychain account: `server|user|tenant`, with `-` for what is unknown.
    public var account: String {
        let user = user?.uuidString.lowercased() ?? Self.none
        let tenant = tenant?.uuidString.lowercased() ?? Self.none
        return "\(server)\(Self.separator)\(user)\(Self.separator)\(tenant)"
    }

    /// Reads an account back. The server may hold any character, so the IDs
    /// are taken from the end.
    public init?(account: String) {
        let parts = account.split(separator: Self.separator, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let server = parts.dropLast(2).joined(separator: String(Self.separator))
        let user = String(parts[parts.count - 2])
        let tenant = String(parts[parts.count - 1])
        guard !server.isEmpty else { return nil }
        func id(_ text: String) -> UUID?? {
            if text == Self.none { return .some(nil) }
            return UUID(uuidString: text).map { .some($0) }
        }
        guard let user = id(user), let tenant = id(tenant) else { return nil }
        self.init(server: server, user: user, tenant: tenant)
    }

    /// Whether both keys belong to the same person on the same server.
    public func sameUser(as other: TokenKey) -> Bool {
        server == other.server && user != nil && user == other.user
    }
}

/// Keeps device tokens, one per server, user and tenant, so that switching
/// back to a tenant reuses its token rather than adding a device each time.
public protocol TokenStore: Sendable {
    func load(_ key: TokenKey) -> String?
    func save(_ token: String, for key: TokenKey)
    func clear(_ key: TokenKey)
    /// Every key with a stored token.
    func keys() -> [TokenKey]
    /// The single token that builds before multi-user servers kept.
    func loadLegacy() -> String?
    func clearLegacy()
}

extension TokenStore {
    public func loadLegacy() -> String? { nil }
    public func clearLegacy() {}
}

/// Stores the tokens in the Keychain, for this device only.
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "tools.lighthouse.app"
    static let legacyAccount = "device-token"
    private let service: String

    /// A build under another bundle identifier, such as one for a test server,
    /// passes its own service so that it keeps a sign-in of its own.
    public init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func load(account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func load(_ key: TokenKey) -> String? { load(account: key.account) }

    public func save(_ token: String, for key: TokenKey) {
        let item = query(key.account)
        let data = Data(token.utf8)
        let status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var added = item
        added[kSecValueData as String] = data
        added[kSecAttrLabel as String] = "Lighthouse"
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(added as CFDictionary, nil)
    }

    public func clear(_ key: TokenKey) {
        SecItemDelete(query(key.account) as CFDictionary)
    }

    public func keys() -> [TokenKey] {
        let request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let items = result as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                account != Self.legacyAccount
            else { return nil }
            return TokenKey(account: account)
        }
    }

    public func loadLegacy() -> String? { load(account: Self.legacyAccount) }

    public func clearLegacy() {
        SecItemDelete(query(Self.legacyAccount) as CFDictionary)
    }
}
