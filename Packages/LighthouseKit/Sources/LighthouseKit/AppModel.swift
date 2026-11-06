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
    public private(set) var serverAddress: String

    private let store: TokenStore
    private let defaults: UserDefaults
    private let session: URLSession
    private let deviceName: String
    private let deviceKind: String
    private var token: String?
    private var errorCameFromRefresh = false
    private static let addressKey = "server-address"

    public init(
        store: TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard,
        session: URLSession = .shared, deviceName: String, deviceKind: String
    ) {
        self.store = store
        self.defaults = defaults
        self.session = session
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        serverAddress = defaults.string(forKey: Self.addressKey) ?? ""
        token = store.load()
        phase = token != nil && !serverAddress.isEmpty ? .ready : .signedOut
    }

    /// Model costs of today across all providers.
    public var spentToday: Double { costsToday.map(\.costEur).reduce(0, +) }

    /// Host of the current server, for status lines.
    public var serverHost: String {
        (try? Client.serverURL(from: serverAddress))?.host() ?? serverAddress
    }

    /// Whether the last refresh reached the server.
    public var isConnected: Bool { !errorCameFromRefresh }

    /// Sessions that wait for their owner.
    public var waitingSessions: [Session] { sessions.filter { $0.status == "waiting" } }

    /// Requests that need a decision.
    public var pendingCount: Int { approvals.count + permissions.count }

    /// A client for the current server, for views that load their own data.
    public var client: Client? {
        guard let url = try? Client.serverURL(from: serverAddress) else { return nil }
        return Client(baseURL: url, token: token, session: session)
    }

    public func signIn(address: String, password: String) async {
        lastError = nil
        do {
            let url = try Client.serverURL(from: address)
            let client = Client(baseURL: url, token: nil, session: session)
            let issued = try await client.login(
                password: password, device: deviceName, kind: deviceKind)
            store.save(issued.token)
            token = issued.token
            serverAddress = url.absoluteString
            defaults.set(serverAddress, forKey: Self.addressKey)
            phase = .ready
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func signOut() async {
        try? await client?.logout()
        finishSignOut()
    }

    private func finishSignOut() {
        store.clear()
        token = nil
        approvals = []
        permissions = []
        sessions = []
        nodes = []
        runs = []
        agents = []
        phase = .signedOut
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
            lastError = nil
            errorCameFromRefresh = false
        } catch ClientError.unauthorized {
            finishSignOut()
        } catch {
            lastError = error.localizedDescription
            errorCameFromRefresh = false
        }
    }

    /// Loads everything. A failure keeps what is already shown, and a success
    /// only clears errors of earlier refreshes, not of a refused decision.
    public func refresh() async {
        guard phase == .ready, let client else { return }
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
            self.approvals = try await approvals
            self.permissions = try await permissions
            self.sessions = try await sessions
            self.nodes = try await nodes
            self.runs = try await runs
            self.agents = try await agents
            let today = Date.now.formatted(.iso8601.year().month().day())
            costsToday = try await costs.filter { $0.day == today }
            ownerName = try await me.name
            self.connectors = try await connectors
            if errorCameFromRefresh {
                lastError = nil
                errorCameFromRefresh = false
            }
        } catch ClientError.unauthorized {
            finishSignOut()
        } catch {
            lastError = error.localizedDescription
            errorCameFromRefresh = true
        }
    }

    /// Refreshes until the surrounding task ends.
    public func keepFresh(every seconds: Int = 10) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(seconds))
        }
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
