import Foundation

/// Claude Code's OAuth credentials as stored in the Keychain. The original JSON is
/// kept so that writing back preserves keys this app doesn't know about.
public struct StoredCredentials: Sendable, Equatable {
    public let json: Data
    public let accessToken: String
    public let refreshToken: String?
    /// Milliseconds since the epoch; may be 0 or missing.
    public let expiresAtMs: Double?

    public init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        let access = (oauth["accessToken"] as? String) ?? ""
        let refresh = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !access.isEmpty || refresh != nil else { return nil }
        self.json = json
        self.accessToken = access
        self.refreshToken = refresh
        self.expiresAtMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue
    }

    public func needsRefresh(now: Date) -> Bool {
        accessToken.isEmpty || TokenPolicy.needsRefresh(expiresAtMs: expiresAtMs, now: now)
    }

    /// The same JSON with new token values; every other key is untouched.
    public func replacingTokens(accessToken: String, refreshToken: String?, expiresAtMs: Double) -> StoredCredentials? {
        guard var root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        oauth["accessToken"] = accessToken
        if let refreshToken { oauth["refreshToken"] = refreshToken }
        oauth["expiresAt"] = Int64(expiresAtMs)
        root["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes]) else { return nil }
        return StoredCredentials(json: data)
    }
}

public enum TokenPolicy {
    /// A token this close to expiring (or already expired) is refreshed first.
    public static let refreshMargin: TimeInterval = 5 * 60

    /// `expiresAtMs` is milliseconds since the epoch. Missing and 0 mean unknown, which refreshes.
    public static func needsRefresh(expiresAtMs: Double?, now: Date) -> Bool {
        guard let expiresAtMs, expiresAtMs > 0 else { return true }
        return Date(timeIntervalSince1970: expiresAtMs / 1000).timeIntervalSince(now) <= refreshMargin
    }
}

public protocol CredentialStore: Sendable {
    /// The raw JSON, or nil when no item exists.
    func read() async throws -> Data?
    func write(_ json: Data) async throws
}

/// Reads and writes the “Claude Code-credentials” generic password through
/// /usr/bin/security. `security` created the item, so it can read it without a prompt.
public struct KeychainCredentialStore: CredentialStore {
    public static let service = "Claude Code-credentials"
    private let account: String

    public init(account: String = NSUserName()) {
        self.account = account
    }

    public func read() async throws -> Data? {
        let (status, output) = try await Self.run(["find-generic-password", "-s", Self.service, "-a", account, "-w"])
        if status == 44 { return nil }  // errSecItemNotFound
        guard status == 0 else { throw UsageError.keychain }
        var text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("{"), let decoded = Self.hexDecoded(text) { text = decoded }
        return Data(text.utf8)
    }

    public func write(_ json: Data) async throws {
        let text = String(decoding: json, as: UTF8.self)
        let (status, _) = try await Self.run(["add-generic-password", "-U", "-s", Self.service, "-a", account, "-w", text])
        guard status == 0 else { throw UsageError.keychain }
    }

    /// `security -w` prints a hex string for values it considers binary.
    static func hexDecoded(_ hex: String) -> String? {
        guard hex.count.isMultiple(of: 2), !hex.isEmpty else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    @concurrent
    private static func run(_ arguments: [String]) async throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageError.keychain }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
