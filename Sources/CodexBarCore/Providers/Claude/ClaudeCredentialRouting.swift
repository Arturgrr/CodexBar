import Foundation

public enum ClaudeCredentialRouting: Sendable, Equatable {
    case none
    case oauth(accessToken: String)
    case webCookie(header: String)
    case adminAPIKey(String)
    /// A Claude Code profile directory (`claude-profile:~/.claude-work`). Usage comes from that profile's own
    /// `claude` login; CodexBar never reads its credentials.
    case configDirectory(String)

    public static let configDirectoryTokenPrefix = "claude-profile:"
    /// Set by the selected profile account's environment so strategy resolution can route it to that
    /// profile's own CLI without seeing the token. The value records whether `CLAUDE_CONFIG_DIR` was set.
    public static let profileAccountEnvironmentKey = "CODEXBAR_CLAUDE_PROFILE_ACCOUNT"
    public static let defaultProfileAccountMarker = "default"
    public static let customProfileAccountMarker = "custom"

    public static func resolve(tokenAccountToken: String?, manualCookieHeader: String?) -> Self {
        if let tokenAccountToken,
           let route = self.resolvePrimaryCredential(tokenAccountToken)
        {
            return route
        }

        guard let manualCookieHeader = self.normalizedWebCookie(manualCookieHeader) else {
            return .none
        }
        return .webCookie(header: manualCookieHeader)
    }

    public var oauthAccessToken: String? {
        guard case let .oauth(accessToken) = self else { return nil }
        return accessToken
    }

    public var manualCookieHeader: String? {
        guard case let .webCookie(header) = self else { return nil }
        return header
    }

    public var isOAuth: Bool {
        if case .oauth = self { return true }
        return false
    }

    public var adminAPIKey: String? {
        guard case let .adminAPIKey(key) = self else { return nil }
        return key
    }

    public var configDirectory: String? {
        guard case let .configDirectory(directory) = self else { return nil }
        return directory
    }

    private static func resolvePrimaryCredential(_ raw: String) -> Self? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(self.configDirectoryTokenPrefix) {
            // A profile token never falls through to cookie routing, even when its directory is missing.
            return self.normalizedConfigDirectory(raw).map { .configDirectory($0) }
        }
        if let adminKey = self.normalizedAdminAPIKey(raw) {
            return .adminAPIKey(adminKey)
        }
        if let accessToken = self.normalizedOAuthToken(raw) {
            return .oauth(accessToken: accessToken)
        }
        if let cookieHeader = self.normalizedWebCookie(raw) {
            return .webCookie(header: cookieHeader)
        }
        return nil
    }

    private static func normalizedOAuthToken(_ raw: String?) -> String? {
        guard let trimmed = self.cleaned(raw) else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("cookie:") || trimmed.contains("=") {
            return nil
        }
        if lower.hasPrefix("bearer ") {
            let bearerTrimmed = trimmed.dropFirst("bearer ".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bearerTrimmed.isEmpty else { return nil }
            let lowerBearerTrimmed = bearerTrimmed.lowercased()
            return lowerBearerTrimmed.hasPrefix("sk-ant-oat") ? bearerTrimmed : nil
        }
        return lower.hasPrefix("sk-ant-oat") ? trimmed : nil
    }

    private static func normalizedAdminAPIKey(_ raw: String?) -> String? {
        guard let trimmed = self.cleaned(raw) else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("cookie:") || trimmed.contains("=") {
            return nil
        }
        if lower.hasPrefix("bearer ") {
            let bearerTrimmed = trimmed.dropFirst("bearer ".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bearerTrimmed.isEmpty else { return nil }
            return bearerTrimmed.lowercased().hasPrefix("sk-ant-admin") ? bearerTrimmed : nil
        }
        return lower.hasPrefix("sk-ant-admin") ? trimmed : nil
    }

    private static func normalizedConfigDirectory(_ raw: String?) -> String? {
        guard let trimmed = self.cleaned(raw),
              trimmed.lowercased().hasPrefix(self.configDirectoryTokenPrefix)
        else { return nil }
        let directory = trimmed.dropFirst(self.configDirectoryTokenPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return directory.isEmpty ? nil : directory
    }

    private static func normalizedWebCookie(_ raw: String?) -> String? {
        guard let normalized = CookieHeaderNormalizer.normalize(raw) else { return nil }
        if normalized.contains("=") {
            return normalized
        }
        return "sessionKey=\(normalized)"
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
