import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct AccountStatusItemsTests {
    private static func usage(_ usedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: usedPercent, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
    }

    /// Two Claude token accounts with cached usage for both; claude-swap rows are cleared so token accounts win.
    private static func withTwoClaudeAccounts(
        _ body: @MainActor (UsageStore, [ProviderTokenAccount]) async throws -> Void) async throws
    {
        try await ClaudeSwapRichUsageFixture.withFixture { fixture in
            let store = fixture.store
            store.claudeSwapAccountSnapshots = []
            store.settings.addTokenAccount(provider: .claude, label: "personal", token: "claude-profile:~/.claude")
            store.settings.addTokenAccount(
                provider: .claude,
                label: "work@example.com",
                token: "claude-profile:~/.claude-work")
            let accounts = store.settings.tokenAccounts(for: .claude)
            store.accountSnapshots[.claude] = accounts.enumerated().map { index, account in
                TokenAccountUsageSnapshot(
                    account: account,
                    snapshot: Self.usage(Double(20 + index * 50)),
                    error: nil,
                    sourceLabel: "fixture",
                    cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
            }
            try await body(store, accounts)
        }
    }

    @Test
    func `account icons default off and persist account toggles`() {
        let defaults = InMemoryUserDefaults()
        let config = testConfigStore(suiteName: "AccountStatusItemsTests")
        let settings = ProviderUsageItemVisibilityTests.settings(defaults: defaults, configStore: config)
        #expect(!settings.accountStatusItemsEnabled)
        #expect(settings.isAccountStatusItemEnabled(provider: .claude, accountID: "a"))

        settings.accountStatusItemsEnabled = true
        settings.setAccountStatusItemEnabled(false, provider: .claude, accountID: "a")
        settings.rememberMenuSubscriptionProvider(.cursor)
        settings.rememberMenuSubscriptionProvider(.cursor)

        let reloaded = ProviderUsageItemVisibilityTests.settings(defaults: defaults, configStore: config)
        #expect(reloaded.accountStatusItemsEnabled)
        #expect(!reloaded.isAccountStatusItemEnabled(provider: .claude, accountID: "a"))
        #expect(reloaded.isAccountStatusItemEnabled(provider: .codex, accountID: "a"))
        #expect(reloaded.menuSubscriptionProviderIDs == ["cursor"])
    }

    @Test
    func `account items use each account's own usage and stable ids`() async throws {
        try await Self.withTwoClaudeAccounts { store, accounts in
            #expect(store.accountStatusItemEntries(for: .claude).isEmpty)

            store.settings.accountStatusItemsEnabled = true
            let entries = store.accountStatusItemEntries(for: .claude)
            #expect(entries.map(\.accountID) == accounts.map(\.id.uuidString))
            #expect(entries.map { $0.snapshot?.primary?.usedPercent } == [20, 70])
            #expect(entries.map(\.badge) == ["P", "W"])

            let workCard = store.accountStatusItemCardModel(for: .claude, accountID: accounts[1].id.uuidString)
            #expect(workCard?.metrics.first?.percent == 70)
            #expect(store.accountStatusItemCardModel(for: .claude, accountID: "missing") == nil)
        }
    }

    @Test
    func `turned off accounts lose their item but stay listed`() async throws {
        try await Self.withTwoClaudeAccounts { store, accounts in
            store.settings.accountStatusItemsEnabled = true
            store.settings.setAccountStatusItemEnabled(false, provider: .claude, accountID: accounts[0].id.uuidString)

            let entries = store.accountStatusItemEntries(for: .claude)
            #expect(entries.map(\.accountID) == [accounts[1].id.uuidString])
            // A lone item has nothing to be told apart from, so it drops its badge.
            #expect(entries.map(\.badge) == [""])
            #expect(store.accountStatusItemCandidates(for: .claude).count == 2)
        }
    }

    @Test
    func `hide personal info replaces account labels with ordinals`() async throws {
        try await Self.withTwoClaudeAccounts { store, _ in
            store.settings.accountStatusItemsEnabled = true
            store.settings.hidePersonalInfo = true
            let entries = store.accountStatusItemEntries(for: .claude)
            #expect(entries.map(\.badge) == ["1", "2"])
            #expect(entries.allSatisfy { !$0.label.contains("work") })
        }
    }

    @Test
    func `account icons fetch every token account even with segmented menus`() async throws {
        try await Self.withTwoClaudeAccounts { store, accounts in
            store.settings.multiAccountMenuLayout = .segmented
            store.settings.accountWidgetsEnabled = false
            #expect(!store.shouldFetchAllTokenAccounts(provider: .claude, accounts: accounts))
            store.settings.accountStatusItemsEnabled = true
            #expect(store.shouldFetchAllTokenAccounts(provider: .claude, accounts: accounts))
        }
    }

    @Test
    func `subscriptions submenu toggles providers and accounts`() async throws {
        try await Self.withTwoClaudeAccounts { store, accounts in
            store.settings.setProviderEnabled(provider: .claude, metadata: store.metadata(for: .claude), enabled: true)
            let section = try #require(MenuDescriptor.subscriptionsSection(store: store, settings: store.settings))
            guard case let .submenu(_, _, items) = try #require(section.entries.first) else {
                Issue.record("Expected a submenu entry")
                return
            }
            #expect(items.first?.action == .subscriptionToggle(.accountIcons))
            #expect(items.first?.isChecked == false)
            let claude = try #require(items.firstIndex { $0.action == .subscriptionToggle(.provider(.claude)) })
            #expect(items[claude].isChecked)
            let accountRows = Array(items[(claude + 1)...].prefix(2))
            let expectedActions = accounts.map {
                MenuDescriptor.MenuAction.subscriptionToggle(.account(.claude, accountID: $0.id.uuidString))
            }
            #expect(accountRows.compactMap(\.action) == expectedActions)
            #expect(accountRows.allSatisfy { $0.indentationLevel == 2 && !$0.isEnabled && $0.isChecked })

            store.settings.accountStatusItemsEnabled = true
            let enabledSection = try #require(MenuDescriptor.subscriptionsSection(
                store: store,
                settings: store.settings))
            guard case let .submenu(_, _, enabledItems) = try #require(enabledSection.entries.first) else { return }
            let accountItemsEnabled = enabledItems.filter { $0.indentationLevel == 2 }.allSatisfy(\.isEnabled)
            #expect(accountItemsEnabled)
        }
    }

    @Test
    func `account item identity hides the account id`() {
        let token = StatusItemController.accountStatusItemToken(accountID: "work@example.com")
        #expect(token.count == 12)
        #expect(token == StatusItemController.accountStatusItemToken(accountID: "work@example.com"))
        #expect(token != StatusItemController.accountStatusItemToken(accountID: "personal@example.com"))
        let identity = StatusItemController.StatusItemIdentity.account(.claude, accountToken: token)
        #expect(identity.autosaveName == "codexbar-claude-account-\(token)")
        #expect(!identity.autosaveName.contains("example"))
    }

    @Test
    func `account items reuse the provider layout with the badge after the icon`() {
        let session = MenuBarLayout(lines: [[.icon, .percent(window: .session)]])
        #expect(StatusItemController.accountStatusItemLayout(session, showsBadge: true).lines
            == [[.icon, .accountLabel, .percent(window: .session)]])
        #expect(StatusItemController.accountStatusItemLayout(session, showsBadge: false) == session)

        let labeled = MenuBarLayout(lines: [[.accountLabel, .icon]])
        #expect(StatusItemController.accountStatusItemLayout(labeled, showsBadge: true) == labeled)
        let iconless = MenuBarLayout(lines: [[.percent(window: .session)]])
        #expect(StatusItemController.accountStatusItemLayout(iconless, showsBadge: true).lines
            == [[.accountLabel, .percent(window: .session)]])
    }

    @Test
    func `account badges use the label's uppercased initial`() {
        #expect(AccountStatusItemEntry.badge(for: "work@example.com", ordinal: 2, hidePersonalInfo: false) == "W")
        #expect(AccountStatusItemEntry.badge(for: " pessoal", ordinal: 1, hidePersonalInfo: false) == "P")
        #expect(AccountStatusItemEntry.badge(for: "  ", ordinal: 3, hidePersonalInfo: false) == "3")
        #expect(AccountStatusItemEntry.badge(for: "work", ordinal: 2, hidePersonalInfo: true) == "2")
    }
}
