import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeProfileAccountTests {
    private static let home = "/Users/example"

    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Work",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }

    private static func resolvedEnvironment(
        token: String,
        base: [String: String] = ["HOME": Self.home]) -> [String: String]
    {
        ProviderEnvironmentResolver.resolve(
            base: base,
            provider: .claude,
            config: ProviderConfig(id: .claude),
            selectedAccount: self.account(token: token))
    }

    private static func strategyIDs(env: [String: String], selectedAccount: Bool = true) async -> [String] {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let settings = ProviderSettingsSnapshot.make(claude: .init(
            usageDataSource: .auto,
            webExtrasEnabled: false,
            cookieSource: .off,
            manualCookieHeader: nil))
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            selectedTokenAccountID: selectedAccount ? UUID() : nil)
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)
        return await descriptor.fetchPlan.pipeline.resolveStrategies(context).map(\.id)
    }

    @Test
    func `profile token resolves to config directory before cookie routing`() {
        #expect(ClaudeCredentialRouting.resolve(
            tokenAccountToken: "claude-profile:~/.claude-work",
            manualCookieHeader: nil) == .configDirectory("~/.claude-work"))
        #expect(ClaudeCredentialRouting.resolve(
            tokenAccountToken: "  Claude-Profile: /Users/example/.claude-work ",
            manualCookieHeader: nil) == .configDirectory("/Users/example/.claude-work"))
    }

    @Test
    func `profile token without directory never becomes a session cookie`() {
        #expect(ClaudeCredentialRouting.resolve(
            tokenAccountToken: "claude-profile:  ",
            manualCookieHeader: nil) == .none)
    }

    @Test
    func `profile directories expand home and reject relative paths`() {
        let env = ["HOME": Self.home]
        #expect(ClaudeConfigPaths.expandedProfileDirectory("~/.claude-work", environment: env)
            == "/Users/example/.claude-work")
        #expect(ClaudeConfigPaths.expandedProfileDirectory("/opt/claude/../claude-b/", environment: env)
            == "/opt/claude-b")
        #expect(ClaudeConfigPaths.expandedProfileDirectory(".claude-work", environment: env) == nil)
        #expect(ClaudeConfigPaths.isDefaultConfigRoot("/Users/example/.claude/", environment: env))
        #expect(!ClaudeConfigPaths.isDefaultConfigRoot("/Users/example/.claude-work", environment: env))
    }

    @Test
    func `custom profile account scopes the fetch to its config directory`() {
        let environment = Self.resolvedEnvironment(
            token: "claude-profile:~/.claude-work",
            base: [
                "HOME": Self.home,
                ClaudeConfigPaths.configDirectoryEnvironmentKey: "/Users/example/.claude-other",
                ClaudeConfigPaths.secureStorageDirectoryEnvironmentKey: "/Users/example/.secure",
                ClaudeOAuthCredentialsStore.environmentTokenKey: "ambient-oauth",
            ])

        #expect(environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] == "/Users/example/.claude-work")
        #expect(environment[ClaudeConfigPaths.secureStorageDirectoryEnvironmentKey] == nil)
        #expect(environment[ClaudeOAuthCredentialsStore.environmentTokenKey] == nil)
        #expect(environment[ClaudeCredentialRouting.profileAccountEnvironmentKey]
            == ClaudeCredentialRouting.customProfileAccountMarker)
    }

    @Test
    func `default profile account keeps Claude's unset config directory`() {
        let environment = Self.resolvedEnvironment(
            token: "claude-profile:~/.claude",
            base: ["HOME": Self.home, ClaudeConfigPaths.configDirectoryEnvironmentKey: "/Users/example/.claude-work"])

        #expect(environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] == nil)
        #expect(environment[ClaudeCredentialRouting.profileAccountEnvironmentKey]
            == ClaudeCredentialRouting.defaultProfileAccountMarker)
    }

    @Test
    func `relative profile directory leaves no profile marker`() {
        let environment = Self.resolvedEnvironment(token: "claude-profile:.claude-work")

        #expect(environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] == nil)
        #expect(environment[ClaudeCredentialRouting.profileAccountEnvironmentKey] == nil)
    }

    @Test
    func `session account does not touch the ambient config directory`() {
        let marker = ClaudeCredentialRouting.customProfileAccountMarker
        let environment = Self.resolvedEnvironment(
            token: "sk-ant-session-account",
            base: [
                "HOME": Self.home,
                ClaudeConfigPaths.configDirectoryEnvironmentKey: "/Users/example/.claude-work",
                ClaudeCredentialRouting.profileAccountEnvironmentKey: marker,
            ])

        #expect(environment[ClaudeConfigPaths.configDirectoryEnvironmentKey] == "/Users/example/.claude-work")
        #expect(environment[ClaudeCredentialRouting.profileAccountEnvironmentKey] == nil)
    }

    @Test
    func `custom profile account fetches only through its own CLI`() async {
        let ids = await Self.strategyIDs(env: [
            "HOME": Self.home,
            "CLAUDE_CLI_PATH": "/usr/bin/true",
            ClaudeConfigPaths.configDirectoryEnvironmentKey: "/Users/example/.claude-work",
            ClaudeCredentialRouting.profileAccountEnvironmentKey: ClaudeCredentialRouting.customProfileAccountMarker,
        ])

        #expect(ids == ["claude.cli"])
    }

    @Test
    func `default profile account keeps ambient routing`() async {
        let env = [
            "HOME": Self.home,
            "CLAUDE_CLI_PATH": "/usr/bin/true",
            ClaudeCredentialRouting.profileAccountEnvironmentKey: ClaudeCredentialRouting.defaultProfileAccountMarker,
        ]
        let ambient = await Self.strategyIDs(env: env, selectedAccount: false)

        #expect(await Self.strategyIDs(env: env) == ambient)
        #expect(!ambient.isEmpty)
    }

    @Test
    func `selected account without credentials stays fail closed`() async {
        #expect(await Self.strategyIDs(env: ["HOME": Self.home, "CLAUDE_CLI_PATH": "/usr/bin/true"]).isEmpty)
    }
}
