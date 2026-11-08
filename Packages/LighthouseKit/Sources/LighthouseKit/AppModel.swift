import Foundation
import Observation

/// The state of the app as a whole, so no view keeps its own sign-in flags.
public enum AppPhase: Equatable, Sendable {
    case loading
    case signedOut
    case ready
}

/// Holds what the apps show and talks to the server.
@MainActor
@Observable
public final class AppModel {
    public private(set) var phase: AppPhase = .loading
    public private(set) var approvals: [Approval] = []
    public private(set) var permissions: [Permission] = []
    public private(set) var sessions: [Session] = []
    public private(set) var nodes: [Node] = []
    public private(set) var runs: [Run] = []
    public private(set) var agents: [Agent] = []
    public private(set) var ownerName: String?
    public private(set) var connectors: [Connector] = []
    public private(set) var costsToday: [DailyCost] = []
    public private(set) var lastError: String?
    /// What waits for the owner, from servers that offer `GET /ready`.
    public private(set) var readyFeed: ReadyFeed?
    public private(set) var alertCounts = AlertCounts()
    /// Unresolved alerts, worst first.
    public private(set) var alerts: [Alert] = []
    /// Whether a refresh has succeeded since sign-in, so that what is already
    /// waiting is not mistaken for something new.
    public private(set) var hasLoaded = false
    /// The organizations, from servers that know them.
    public private(set) var organizations: [Organization] = []
    public private(set) var serverAddress: String
    /// The signed-in user in the current tenant, once `/me` answered.
    public private(set) var me: Me?
    /// The tenants of the user, from servers since 0.2.
    public private(set) var tenants: [Membership] = []
    /// Whether a switch to another tenant is under way.
    public private(set) var switching = false
    /// Grows with every new sign-in or tenant, so live connections start over.
    public private(set) var signInGeneration = 0
    /// The name this device gets in the list of signed-in devices.
    public var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Self.deviceNameKey) }
    }
    public var language: Language {
        didSet {
            Lang.current = language
            defaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    private let store: TokenStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let deviceKind: String
    private var token: String?
    private var key: TokenKey?
    private var errorCameFromRefresh = false
    private static let addressKey = "server-address"
    private static let languageKey = "language"
    private static let tokenKeyKey = "token-key"
    private static let deviceNameKey = "device-name"

    public init(
        store: TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard,
        session: URLSession = .shared, deviceName: String, deviceKind: String
    ) {
        self.store = store
        self.defaults = defaults
        self.session = session
        self.deviceKind = deviceKind
        self.deviceName = defaults.string(forKey: Self.deviceNameKey) ?? deviceName
        serverAddress = defaults.string(forKey: Self.addressKey) ?? ""
        let stored = defaults.string(forKey: Self.languageKey).flatMap(Language.init(rawValue:))
        language = stored ?? .system
        Lang.current = stored ?? .system
        key = defaults.string(forKey: Self.tokenKeyKey).flatMap(TokenKey.init(account:))
        token = key.flatMap(store.load)
        if token == nil { migrateLegacyToken() }
        phase = token != nil && !serverAddress.isEmpty ? .ready : .signedOut
    }

    /// Builds before multi-user servers kept one token. It moves to a key of
    /// its server, and the first `/me` adds the user and tenant.
    private func migrateLegacyToken() {
        guard let legacy = store.loadLegacy(), let url = try? Client.serverURL(from: serverAddress) else { return }
        let migrated = TokenKey(server: url.absoluteString)
        store.save(legacy, for: migrated)
        store.clearLegacy()
        remember(migrated)
        token = legacy
    }

    private func remember(_ key: TokenKey?) {
        self.key = key
        if let key { defaults.set(key.account, forKey: Self.tokenKeyKey) } else {
            defaults.removeObject(forKey: Self.tokenKeyKey)
        }
    }

    /// Model costs of today across all providers.
    public var spentToday: Double { costsToday.map(\.costEur).reduce(0, +) }

    /// Host of the current server, for status lines.
    public var serverHost: String {
        (try? Client.serverURL(from: serverAddress))?.host() ?? serverAddress
    }

    /// The tenant the app works in, from `/me`.
    public var tenantName: String? { me?.tenantName }

    /// The user's role in the current tenant. Nil on servers before 0.2.
    public var role: Role? { me?.role }

    /// Whether the user may change credentials, connections and the budget.
    /// On servers before 0.2 the only person is the owner.
    public var canAdminister: Bool { role?.canAdminister ?? true }

    /// The current tenant among the user's tenants.
    public var currentTenant: Membership? {
        guard let id = me?.tenantId else { return nil }
        return tenants.first { $0.tenantId == id }
    }

    /// Changes whenever the app signs in anew, signs out or switches tenants.
    public var sessionID: String { "\(phase)-\(signInGeneration)" }

    /// Whether the last refresh reached the server.
    public var isConnected: Bool { !errorCameFromRefresh }

    /// Sessions that wait for their owner, unless a request already says why.
    public var waitingSessions: [Session] {
        sessions.filter { session in
            session.status == "waiting" && !permissions.contains { $0.project == session.project }
        }
    }

    /// What waits for the owner: the ready feed, or on older servers the
    /// requests that need a decision.
    public var pendingCount: Int { readyFeed?.total ?? approvals.count + permissions.count }

    /// Unresolved critical alerts.
    public var criticalAlerts: [Alert] { alerts.filter(\.isCritical) }

    /// Whether a server event touches what the apps keep. Events for rules,
    /// memory, automations and the like only matter to the web app.
    public nonisolated static func refreshes(on event: String) -> Bool {
        let relevant: Set<String> = [
            "changed", "ready.changed", "alert.raised", "alerts.changed", "tasks.changed",
            "sessions.changed", "run.waiting", "run.finished", "organizations.changed",
        ]
        return relevant.contains(event)
    }

    /// The token the web app of the Mac window signs in with. It stays in the
    /// Keychain and in memory, never in a file of the web view.
    public var webToken: String? { phase == .ready ? token : nil }

    /// The server as a URL, once one is set.
    public var serverURL: URL? { try? Client.serverURL(from: serverAddress) }

    /// A client for the current server, for views that load their own data.
    public var client: Client? {
        guard let url = try? Client.serverURL(from: serverAddress) else { return nil }
        return Client(baseURL: url, token: token, session: session)
    }

    /// What a server needs for a sign-in, or nil when it cannot be reached.
    public func status(of address: String) async -> AuthStatus? {
        guard let url = try? Client.serverURL(from: address) else { return nil }
        return try? await Client(baseURL: url, token: nil, session: session).authStatus()
    }

    /// Signs in. The email may stay empty while the server has a single user.
    public func signIn(address: String, email: String = "", password: String) async {
        lastError = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let url = try Client.serverURL(from: address)
            let client = Client(baseURL: url, token: nil, session: session)
            let issued = try await client.login(
                email: email, password: password, device: deviceName, kind: deviceKind)
            let key = TokenKey(server: url.absoluteString, user: issued.userId, tenant: issued.tenantId)
            store.save(issued.token, for: key)
            serverAddress = url.absoluteString
            defaults.set(serverAddress, forKey: Self.addressKey)
            begin(token: issued.token, key: key)
            phase = .ready
            await refresh()
        } catch ClientError.server(400, _) where email.isEmpty {
            lastError = tr("This server has several users. Enter your email address.")
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Starts working with a token: what the last one loaded belongs to
    /// another tenant or person, so it goes.
    private func begin(token: String, key: TokenKey) {
        clearData()
        self.token = token
        remember(key)
        signInGeneration += 1
    }

    /// Works in another tenant of the user. A token kept from an earlier
    /// visit is reused while the server still accepts it; otherwise the server
    /// issues one. The token of the tenant left stays for the way back.
    public func switchTenant(to tenant: Membership) async {
        guard phase == .ready, !switching, let key, let client, let url = serverURL,
            tenant.tenantId != me?.tenantId
        else { return }
        switching = true
        defer { switching = false }
        var target = TokenKey(server: key.server, user: key.user ?? me?.userId, tenant: tenant.tenantId)
        do {
            var next: String?
            if target.user != nil, let kept = store.load(target) {
                do {
                    let found = try await Client(baseURL: url, token: kept, session: session).me()
                    if found.tenantId == tenant.tenantId { next = kept }
                } catch ClientError.unauthorized {
                    store.clear(target)
                }
            }
            if next == nil {
                let issued = try await client.switchTenant(to: tenant.tenantId, device: deviceName, kind: deviceKind)
                target = TokenKey(
                    server: key.server, user: issued.userId ?? target.user, tenant: issued.tenantId ?? tenant.tenantId)
                next = issued.token
            }
            guard let next else { return }
            store.save(next, for: target)
            begin(token: next, key: target)
            lastError = nil
            await refresh()
        } catch ClientError.unauthorized {
            finishSignOut(ended: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Takes over a token the web app of the Mac window got by itself, such as
    /// after it switched tenants, once the server confirms it.
    public func adoptWebToken(_ webToken: String) async {
        guard phase == .ready, webToken != token, let url = serverURL else { return }
        guard let found = try? await Client(baseURL: url, token: webToken, session: session).me(),
            phase == .ready, webToken != token
        else { return }
        let key = TokenKey(server: url.absoluteString, user: found.userId, tenant: found.tenantId)
        store.save(webToken, for: key)
        begin(token: webToken, key: key)
        me = found
        await refresh()
    }

    /// Signs out of every tenant of this user on this server, and revokes the tokens.
    public func signOut() async {
        if let key {
            let related = store.keys().filter { $0 == key || $0.sameUser(as: key) }
            let all = related.contains(key) ? related : related + [key]
            for each in all {
                if let stored = each == key ? token : store.load(each), let url = URL(string: each.server) {
                    try? await Client(baseURL: url, token: stored, session: session).logout()
                }
                store.clear(each)
            }
        } else {
            try? await client?.logout()
        }
        finishSignOut()
    }

    /// Ends the sign-in on this device. `ended` tells the person the server
    /// refused the token, so they know why they see the sign-in again.
    private func finishSignOut(ended: Bool = false) {
        if let key { store.clear(key) }
        remember(nil)
        token = nil
        clearData()
        lastError = ended ? tr("Your sign-in has ended. Please sign in again.") : nil
        phase = .signedOut
        signInGeneration += 1
    }

    private func clearData() {
        me = nil
        ownerName = nil
        tenants = []
        approvals = []
        permissions = []
        sessions = []
        nodes = []
        runs = []
        agents = []
        readyFeed = nil
        alertCounts = AlertCounts()
        alerts = []
        hasLoaded = false
        organizations = []
        connectors = []
        costsToday = []
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
            lastError = nil
            errorCameFromRefresh = false
        } catch ClientError.unauthorized {
            finishSignOut(ended: true)
        } catch {
            lastError = error.localizedDescription
            errorCameFromRefresh = false
        }
    }

    /// Loads everything. A failure keeps what is already shown, and a success
    /// only clears errors of earlier refreshes, not of a refused decision.
    public func refresh() async {
        guard phase == .ready, let client else { return }
        let generation = signInGeneration
        do {
            async let approvals = client.approvals()
            async let permissions = client.permissions()
            async let sessions = client.sessions()
            async let nodes = client.nodes()
            async let runs = client.runs()
            async let agents = client.agents()
            async let costs = client.costs(days: 1)
            async let me = client.me()
            async let connectors = client.connectors()
            let loaded = try await (approvals, permissions, sessions, nodes, runs, agents, costs, me, connectors)
            let extras = await loadExtras(client)
            // A sign-out or another tenant came in between: this answer is stale.
            guard generation == signInGeneration else { return }
            self.approvals = loaded.0
            self.permissions = loaded.1
            self.sessions = loaded.2
            self.nodes = loaded.3
            self.runs = loaded.4
            self.agents = loaded.5
            let today = Date.now.formatted(.iso8601.year().month().day())
            costsToday = loaded.6.filter { $0.day == today }
            adopt(loaded.7)
            self.connectors = loaded.8
            readyFeed = extras.feed
            alertCounts = extras.counts ?? readyFeed?.alerts ?? AlertCounts()
            alerts = extras.alerts ?? []
            organizations = extras.organizations ?? []
            tenants = extras.tenants ?? []
            hasLoaded = true
            if errorCameFromRefresh {
                lastError = nil
                errorCameFromRefresh = false
            }
        } catch ClientError.unauthorized {
            guard generation == signInGeneration else { return }
            finishSignOut(ended: true)
        } catch {
            guard generation == signInGeneration else { return }
            lastError = error.localizedDescription
            errorCameFromRefresh = true
        }
    }

    private struct Extras: Sendable {
        var feed: ReadyFeed?
        var counts: AlertCounts?
        var alerts: [Alert]?
        var organizations: [Organization]?
        var tenants: [Membership]?
    }

    /// The ready feed, alerts, organizations and tenants are newer than some
    /// servers, so their absence is no error.
    private nonisolated func loadExtras(_ client: Client) async -> Extras {
        async let feed = try? client.ready()
        async let counts = try? client.alertCounts()
        async let active = try? client.activeAlerts()
        async let organizations = try? client.organizations()
        async let tenants = try? client.tenants()
        return await Extras(
            feed: feed, counts: counts, alerts: active, organizations: organizations, tenants: tenants)
    }

    /// Keeps who is signed in, and files a token stored before its user and
    /// tenant were known under its full key.
    private func adopt(_ found: Me) {
        me = found
        ownerName = found.name
        guard let key, let token, let user = found.userId, let tenant = found.tenantId,
            key.user != user || key.tenant != tenant
        else { return }
        let confirmed = TokenKey(server: key.server, user: user, tenant: tenant)
        store.save(token, for: confirmed)
        store.clear(key)
        remember(confirmed)
    }

    /// Creates a task at the top of the owner's list.
    public func createTask(title: String, notes: String?) async throws {
        guard let client else { throw ClientError.invalidAddress }
        _ = try await client.createTask(title: title, notes: notes)
        await refresh()
    }

    /// Stays current until the surrounding task ends: the server announces
    /// changes, and a lost connection is retried with a growing delay.
    public func keepFresh() async {
        var delay = 1
        while !Task.isCancelled {
            await refresh()
            guard phase == .ready, let client else { return }
            do {
                for try await event in client.changes() {
                    delay = 1
                    if Self.refreshes(on: event.name) { await refresh() }
                }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 30)
        }
    }

    /// Decides all open proposals at once.
    public func decideAll(approve: Bool) async {
        let ids = approvals.map(\.id)
        await perform {
            try await client?.decide(approvals: ids, approve: approve)
            approvals.removeAll()
        }
        await refresh()
    }

    /// A readable name for the agent of a run.
    public func agentName(_ id: String) -> String {
        agents.first { $0.id == id }?.name ?? readableName(id)
    }

    public func decide(_ approval: Approval, approve: Bool) async {
        await perform {
            try await client?.decide(approval: approval.id, approve: approve)
            approvals.removeAll { $0.id == approval.id }
        }
        await refresh()
    }

    public func decide(_ permission: Permission, allow: Bool) async {
        await perform {
            try await client?.decide(permission: permission.id, allow: allow)
            permissions.removeAll { $0.id == permission.id }
        }
        await refresh()
    }

    public func setPaused(_ node: Node, paused: Bool) async {
        await perform { try await client?.setPaused(node: node.id, paused: paused) }
        await refresh()
    }

    public func run(_ agent: Agent) async {
        await perform { try await client?.run(agent: agent.id) }
        await refresh()
    }
}
