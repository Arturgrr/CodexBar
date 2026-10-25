import CodexBarCore
import Foundation

extension SettingsStore {
    /// Opt-in: a provider with more than one account shows one menu bar item per enabled account
    /// instead of its single provider item. Split (non-merged) icons only.
    var accountStatusItemsEnabled: Bool {
        get { self.defaultsState.accountStatusItemsEnabled }
        set { self.setDefault(\.accountStatusItemsEnabled, newValue, key: "accountStatusItemsEnabled") }
    }

    /// Accounts hidden from the menu bar, keyed by `accountStatusItemKey(provider:accountID:)`.
    var disabledAccountStatusItemKeys: Set<String> {
        get { Set(self.defaultsState.disabledAccountStatusItemKeys) }
        set {
            self.setDefault(\.disabledAccountStatusItemKeys, newValue.sorted(), key: "disabledAccountStatusItemKeys")
        }
    }

    /// Providers toggled from the menu's Subscriptions submenu stay listed there after being turned off,
    /// so they can be turned back on without opening Settings.
    var menuSubscriptionProviderIDs: [String] {
        get { self.defaultsState.menuSubscriptionProviderIDs }
        set { self.setDefault(\.menuSubscriptionProviderIDs, newValue, key: "menuSubscriptionProviderIDs") }
    }

    nonisolated static func accountStatusItemKey(provider: UsageProvider, accountID: String) -> String {
        "\(provider.rawValue)/\(accountID)"
    }

    func isAccountStatusItemEnabled(provider: UsageProvider, accountID: String) -> Bool {
        let key = Self.accountStatusItemKey(provider: provider, accountID: accountID)
        return !self.disabledAccountStatusItemKeys.contains(key)
    }

    func setAccountStatusItemEnabled(_ enabled: Bool, provider: UsageProvider, accountID: String) {
        let key = Self.accountStatusItemKey(provider: provider, accountID: accountID)
        var keys = self.disabledAccountStatusItemKeys
        if enabled {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
        self.disabledAccountStatusItemKeys = keys
    }

    func rememberMenuSubscriptionProvider(_ provider: UsageProvider) {
        guard !self.menuSubscriptionProviderIDs.contains(provider.rawValue) else { return }
        self.menuSubscriptionProviderIDs.append(provider.rawValue)
    }
}
