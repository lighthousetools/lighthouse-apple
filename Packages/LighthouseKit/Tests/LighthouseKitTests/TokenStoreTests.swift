import Foundation
import Security
import Testing

@testable import LighthouseKit

@Suite struct TokenKeyTests {
    let user = UUID(uuidString: "019a0000-0000-7000-8000-0000000000a1")!
    let tenant = UUID(uuidString: "019a0000-0000-7000-8000-0000000000b1")!

    @Test func accountsRoundTrip() throws {
        let full = TokenKey(server: "https://lighthouse.test", user: user, tenant: tenant)
        #expect(full.account == "https://lighthouse.test|\(user.uuidString.lowercased())|\(tenant.uuidString.lowercased())")
        #expect(TokenKey(account: full.account) == full)
        let bare = TokenKey(server: "http://192.168.1.2:8080")
        #expect(bare.account == "http://192.168.1.2:8080|-|-")
        #expect(TokenKey(account: bare.account) == bare)
    }

    @Test func aServerWithTheSeparatorStaysWhole() {
        let odd = TokenKey(server: "https://a|b.test", user: user, tenant: nil)
        #expect(TokenKey(account: odd.account) == odd)
    }

    @Test func brokenAccountsAreIgnored() {
        #expect(TokenKey(account: "device-token") == nil)
        #expect(TokenKey(account: "|-|-") == nil)
        #expect(TokenKey(account: "https://x|nope|-") == nil)
    }

    @Test func theSameUserNeedsAKnownUserOnTheSameServer() {
        let home = TokenKey(server: "https://a.test", user: user, tenant: tenant)
        let team = TokenKey(server: "https://a.test", user: user, tenant: UUID())
        #expect(home.sameUser(as: team))
        #expect(!home.sameUser(as: TokenKey(server: "https://b.test", user: user, tenant: tenant)))
        #expect(!TokenKey(server: "https://a.test").sameUser(as: TokenKey(server: "https://a.test")))
    }
}

/// Uses the real Keychain under a service of its own, removed afterwards.
/// Skipped where the test process cannot reach a Keychain.
@Suite(.serialized, .enabled(if: KeychainProbe.available)) struct KeychainTokenStoreTests {
    @Test func tokensAreKeptPerUserAndTenant() {
        let service = "tools.lighthouse.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        defer { for key in store.keys() { store.clear(key) } }
        let home = TokenKey(server: "https://lighthouse.test", user: UUID(), tenant: UUID())
        let team = TokenKey(server: "https://lighthouse.test", user: home.user, tenant: UUID())
        store.save("lht_home", for: home)
        store.save("lht_team", for: team)
        #expect(store.load(home) == "lht_home")
        #expect(store.load(team) == "lht_team")
        #expect(Set(store.keys()) == [home, team])
        store.save("lht_home2", for: home)
        #expect(store.load(home) == "lht_home2")
        store.clear(home)
        #expect(store.load(home) == nil)
        #expect(store.keys() == [team])
    }
}

enum KeychainProbe {
    static let available: Bool = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tools.lighthouse.tests.probe",
            kSecAttrAccount as String: "probe",
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data("x".utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }()
}
