import CodexBarCore
import Foundation

/// One account of a multi-account provider, as rendered by its own menu bar item.
struct AccountStatusItemEntry {
    let provider: UsageProvider
    /// Same identifier format as `MergedOverviewRow.accountID`, so menus can reuse the Overview card models.
    let accountID: String
    let label: String
    /// One-character label drawn next to the provider icon so identical provider icons stay distinguishable;
    /// empty when the account is the provider's only visible item.
    var badge: String
    /// Usage that may drive the menu bar icon; last-known source usage is excluded because the icon shows no age.
    let snapshot: UsageSnapshot?
    let error: String?

    var key: String {
        SettingsStore.accountStatusItemKey(provider: self.provider, accountID: self.accountID)
    }

    static func badge(for label: String, ordinal: Int, hidePersonalInfo: Bool) -> String {
        guard !hidePersonalInfo,
              let initial = label.trimmingCharacters(in: .whitespacesAndNewlines).first
        else { return "\(ordinal)" }
        return String(initial).uppercased()
    }
}

extension UsageStore {
    /// Every account the provider's active multi-account source exposes, using the Overview source precedence
    /// (claude-swap, then managed Codex accounts, then token accounts). Fewer than two accounts returns none.
    func accountStatusItemCandidates(for provider: UsageProvider) -> [AccountStatusItemEntry] {
        let hidePersonalInfo = self.settings.hidePersonalInfo
        func entry(_ index: Int, id: String, label: String, snapshot: UsageSnapshot?, error: String?)
            -> AccountStatusItemEntry
        {
            AccountStatusItemEntry(
                provider: provider,
                accountID: id,
                label: hidePersonalInfo ? "\(L("Account")) \(index + 1)" : label,
                badge: AccountStatusItemEntry.badge(for: label, ordinal: index + 1, hidePersonalInfo: hidePersonalInfo),
                snapshot: snapshot,
                error: error)
        }

        if ClaudeSwapMenuPrecedence.prefersClaudeSwap(
            provider: provider,
            accountCount: self.claudeSwapAccountSnapshots.count,
            showSingleAccount: self.settings.claudeSwapShowSingleAccount)
        {
            let accounts = self.claudeSwapAccountSnapshots
            guard accounts.count > 1 else { return [] }
            return accounts.enumerated().map { index, account in
                entry(
                    index,
                    id: account.id.source + ":" + account.id.opaqueID,
                    label: account.displayLabel,
                    snapshot: account.usesLastKnownUsage ? nil : account.snapshot,
                    error: account.error)
            }
        }
        // Provider-specific by design: managed Codex accounts use the cached visible-account inventory.
        if provider == .codex,
           let projection = self.settings.codexVisibleAccountProjectionForMenuDisplay,
           projection.visibleAccounts.count > 1
        {
            let labels = CodexAccountSwitcherLabeling.labels(for: projection.visibleAccounts, hidePersonalInfo: false)
            return projection.visibleAccounts.enumerated().map { index, account in
                let record = self.codexAccountSnapshots.first {
                    $0.id == account.id && Self.codexPriorSnapshotAccountMatches($0.account, account: account)
                }
                return entry(
                    index,
                    id: account.id,
                    label: labels[account.id] ?? account.menuDisplayName,
                    snapshot: record?.snapshot,
                    error: record?.error)
            }
        }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1, self.settings.effectiveSelectedTokenAccount(for: provider) != nil else { return [] }
        let cached = self.validTokenAccountSnapshots(provider: provider, accounts: accounts)
        return accounts.enumerated().map { index, account in
            let record = cached.first { $0.id == account.id }
            return entry(
                index,
                id: account.id.uuidString,
                label: account.displayName,
                snapshot: record?.snapshot,
                error: record?.error)
        }
    }

    /// The accounts that get their own menu bar item: the candidates the user has not turned off.
    func accountStatusItemEntries(for provider: UsageProvider) -> [AccountStatusItemEntry] {
        guard self.settings.accountStatusItemsEnabled else { return [] }
        var entries = self.accountStatusItemCandidates(for: provider).filter {
            self.settings.isAccountStatusItemEnabled(provider: provider, accountID: $0.accountID)
        }
        // A lone item has no sibling to tell apart from.
        if entries.count == 1 {
            entries[0].badge = ""
        }
        return entries
    }

    /// The card shown by an account item's menu; the same model the Overview renders for that account row.
    func accountStatusItemCardModel(for provider: UsageProvider, accountID: String) -> UsageMenuCardView.Model? {
        self.mergedOverviewAccountRows(for: provider).first { $0.accountID == accountID }?.model
    }
}
