import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.unreadableResponse }
        return (data, http)
    }
}

/// Fetches the 5-hour and weekly usage, refreshing the OAuth token when needed.
/// An actor, so only one refresh is ever in flight.
public actor UsageService {
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let store: any CredentialStore
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    /// Refreshed credentials that couldn't be written back yet, and the refresh token they replaced.
    private var unsaved: (credentials: StoredCredentials, replaced: String?)?

    public init(
        store: any CredentialStore = KeychainCredentialStore(),
        transport: any HTTPTransport = URLSession(configuration: .ephemeral),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var credentials = try await currentCredentials()
        if credentials.needsRefresh(now: now()), credentials.refreshToken != nil {
            credentials = try await refresh(credentials, force: false)
        }
        do {
            return try await requestUsage(accessToken: credentials.accessToken)
        } catch UsageError.unauthorized {
            guard credentials.refreshToken != nil else { throw UsageError.signedOut }
            let renewed = try await refresh(credentials, force: true)
            do {
                return try await requestUsage(accessToken: renewed.accessToken)
            } catch UsageError.unauthorized {
                throw UsageError.signedOut
            }
        }
    }

    // MARK: Credentials

    private func currentCredentials() async throws -> StoredCredentials {
        guard let data = try await store.read(), let stored = StoredCredentials(json: data) else {
            throw UsageError.signedOut
        }
        if let pending = unsaved {
            if stored.refreshToken == pending.replaced {
                // Keychain still holds the token we rotated away from; retry the write.
                if (try? await store.write(pending.credentials.json)) != nil { unsaved = nil }
                return pending.credentials
            }
            unsaved = nil
        }
        return stored
    }

    private func refresh(_ credentials: StoredCredentials, force: Bool) async throws -> StoredCredentials {
        var credentials = credentials
        // Claude Code may have refreshed already; its rotated token is the only valid one.
        let latest = try await currentCredentials()
        if latest.refreshToken != credentials.refreshToken {
            if !latest.needsRefresh(now: now()) { return latest }
            credentials = latest
        }
        guard let refreshToken = credentials.refreshToken else { throw UsageError.signedOut }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LastCall/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ])

        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200..<300: break
        case 400, 401, 403: throw UsageError.signedOut
        case 429: throw UsageError.rateLimited(retryAfter: Self.retryAfter(response))
        default: throw UsageError.server(status: response.statusCode)
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = body["access_token"] as? String, !access.isEmpty
        else { throw UsageError.unreadableResponse }
        let lifetime = (body["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let expiresAtMs = (now().timeIntervalSince1970 + lifetime) * 1000
        guard let renewed = credentials.replacingTokens(
            accessToken: access,
            refreshToken: body["refresh_token"] as? String,
            expiresAtMs: expiresAtMs
        ) else { throw UsageError.unreadableResponse }

        do {
            try await store.write(renewed.json)
            unsaved = nil
        } catch {
            unsaved = (renewed, credentials.refreshToken)
        }
        return renewed
    }

    // MARK: Usage

    private func requestUsage(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LastCall/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200..<300:
            do { return try UsageSnapshot.decode(from: data, fetchedAt: now()) } catch { throw UsageError.unreadableResponse }
        case 401: throw UsageError.unauthorized
        case 429: throw UsageError.rateLimited(retryAfter: Self.retryAfter(response))
        default: throw UsageError.server(status: response.statusCode)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.network
        }
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    }
}
