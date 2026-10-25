import AppKit
import CodexBarCore

extension MenuDescriptor {
    enum SubscriptionToggle: Equatable {
        case provider(UsageProvider)
        case account(UsageProvider, accountID: String)
        case accountIcons
    }

    /// Subscriptions submenu: turn providers and, while account icons are on, individual accounts on or off
    /// without opening Settings. Lists enabled providers plus any the user turned off from this submenu.
    static func subscriptionsSection(store: UsageStore, settings: SettingsStore) -> Section? {
        let remembered = Set(settings.menuSubscriptionProviderIDs)
        let providers = settings.orderedFirstPartyProviders().filter { provider in
            settings.isProviderEnabled(provider: provider, metadata: store.metadata(for: provider))
                || remembered.contains(provider.rawValue)
        }
        guard let firstProvider = providers.first else { return nil }

        var items: [SubmenuItem] = [
            SubmenuItem(
                title: L("One icon per account"),
                action: .subscriptionToggle(.accountIcons),
                isChecked: settings.accountStatusItemsEnabled),
        ]
        for provider in providers {
            let metadata = store.metadata(for: provider)
            let isEnabled = settings.isProviderEnabled(provider: provider, metadata: metadata)
            items.append(SubmenuItem(
                title: metadata.displayName,
                action: .subscriptionToggle(.provider(provider)),
                isChecked: isEnabled,
                indentationLevel: 1))
            guard isEnabled else { continue }
            for account in store.accountStatusItemCandidates(for: provider) {
                items.append(SubmenuItem(
                    title: account.label,
                    action: .subscriptionToggle(.account(provider, accountID: account.accountID)),
                    isEnabled: settings.accountStatusItemsEnabled,
                    isChecked: settings.isAccountStatusItemEnabled(provider: provider, accountID: account.accountID),
                    indentationLevel: 2))
            }
        }
        items.append(SubmenuItem(title: L("Providers") + "…", action: .providerSettings(firstProvider)))
        return Section(entries: [
            .submenu(L("Subscriptions"), MenuActionSystemImage.subscriptions.rawValue, items),
        ])
    }
}

extension StatusItemController {
    func subscriptionToggleSelector(for toggle: MenuDescriptor.SubscriptionToggle) -> (Selector, Any?) {
        switch toggle {
        case let .provider(provider):
            (#selector(self.toggleProviderEnabledFromMenu(_:)), provider.rawValue)
        case let .account(provider, accountID):
            (#selector(self.toggleAccountStatusItemFromMenu(_:)), [provider.rawValue, accountID])
        case .accountIcons:
            (#selector(self.toggleAccountStatusItemsFromMenu(_:)), nil)
        }
    }

    @objc func toggleProviderEnabledFromMenu(_ sender: NSMenuItem) {
        guard let rawProvider = sender.representedObject as? String,
              let provider = UsageProvider(rawValue: rawProvider)
        else {
            self.menuLogger.error("Subscription toggle is missing a valid provider")
            return
        }
        let metadata = self.store.metadata(for: provider)
        let isEnabled = self.settings.isProviderEnabled(provider: provider, metadata: metadata)
        // Keep it listed so it can be turned back on from the same submenu.
        self.settings.rememberMenuSubscriptionProvider(provider)
        self.settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: !isEnabled)
    }

    @objc func toggleAccountStatusItemFromMenu(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String],
              values.count == 2,
              let provider = UsageProvider(rawValue: values[0])
        else {
            self.menuLogger.error("Account toggle is missing a valid account")
            return
        }
        let isEnabled = self.settings.isAccountStatusItemEnabled(provider: provider, accountID: values[1])
        self.settings.setAccountStatusItemEnabled(!isEnabled, provider: provider, accountID: values[1])
    }

    @objc func toggleAccountStatusItemsFromMenu(_ sender: NSMenuItem) {
        self.settings.accountStatusItemsEnabled.toggle()
        guard self.settings.accountStatusItemsEnabled else { return }
        // Account items need every account's usage; the selected-account refresh skips the others.
        Task { await self.store.refresh() }
    }
}
