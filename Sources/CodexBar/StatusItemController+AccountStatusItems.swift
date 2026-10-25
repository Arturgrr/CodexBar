import AppKit
import CodexBarCore
import CryptoKit

/// The account an account item's menu is scoped to.
struct AccountStatusItemFocus: Equatable {
    let provider: UsageProvider
    let accountID: String
}

/// Per-account menu bar items, keyed by `AccountStatusItemEntry.key`. They replace their provider's single
/// item while `SettingsStore.accountStatusItemsEnabled` is on and icons are not merged.
struct AccountStatusItemRegistry {
    var items: [String: NSStatusItem] = [:]
    var menus: [String: NSMenu] = [:]
    var menuFocus: [ObjectIdentifier: AccountStatusItemFocus] = [:]
    var renderSignatures: [String: String] = [:]
    /// Keys in menu bar order as of the last reconciliation.
    var orderedKeys: [String] = []

    var allItems: [NSStatusItem] {
        Array(self.items.values)
    }
}

extension StatusItemController {
    /// A stable, non-identifying autosave token: account IDs can contain emails.
    nonisolated static func accountStatusItemToken(accountID: String) -> String {
        SHA256.hash(data: Data(accountID.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Providers whose single item is currently replaced by per-account items.
    func accountStatusItemProviders() -> Set<UsageProvider> {
        guard !self.shouldMergeIcons, self.settings.accountStatusItemsEnabled else { return [] }
        return Set(self.settings.orderedFirstPartyProviders().filter { provider in
            self.isEnabled(provider) && !self.store.accountStatusItemEntries(for: provider).isEmpty
        })
    }

    private func desiredAccountStatusItemEntries(providers: Set<UsageProvider>) -> [AccountStatusItemEntry] {
        self.settings.orderedFirstPartyProviders()
            .filter(providers.contains)
            .flatMap { self.store.accountStatusItemEntries(for: $0) }
    }

    /// True when accounts appeared, disappeared, or were toggled since the items were last reconciled.
    func accountStatusItemLayoutNeedsUpdate() -> Bool {
        let keys = self.desiredAccountStatusItemEntries(providers: self.accountStatusItemProviders()).map(\.key)
        return keys != self.accountStatusItems.orderedKeys
    }

    /// Creates, shows, and attaches menus to the desired account items and removes the rest.
    /// Returns the autosave names that should be visible.
    func reconcileAccountStatusItems(providers: Set<UsageProvider>) -> Set<String> {
        let entries = self.desiredAccountStatusItemEntries(providers: providers)
        let desiredKeys = Set(entries.map(\.key))
        for key in Set(self.accountStatusItems.items.keys).union(self.accountStatusItems.menus.keys)
            where !desiredKeys.contains(key)
        {
            self.removeAccountStatusItem(key: key)
        }
        var visibleAutosaveNames: Set<String> = []
        for entry in entries {
            let item = self.accountStatusItem(for: entry)
            self.setStatusItemVisiblePreservingPlacement(item, true)
            visibleAutosaveNames.insert(item.autosaveName)
            let menu = self.accountStatusItemMenu(for: entry)
            if item.menu !== menu {
                item.menu = menu
            }
        }
        self.accountStatusItems.orderedKeys = entries.map(\.key)
        return visibleAutosaveNames
    }

    func removeAllAccountStatusItems() {
        for key in Set(self.accountStatusItems.items.keys).union(self.accountStatusItems.menus.keys) {
            self.removeAccountStatusItem(key: key)
        }
        self.accountStatusItems.orderedKeys = []
    }

    private func removeAccountStatusItem(key: String) {
        if let menu = self.accountStatusItems.menus.removeValue(forKey: key) {
            let menuID = ObjectIdentifier(menu)
            self.accountStatusItems.menuFocus.removeValue(forKey: menuID)
            self.removeMenuLifecycleState(menuID)
        }
        self.accountStatusItems.renderSignatures.removeValue(forKey: key)
        guard let item = self.accountStatusItems.items.removeValue(forKey: key) else { return }
        item.menu = nil
        self.removeStatusItemPreservingPlacement(item)
    }

    private func accountStatusItem(for entry: AccountStatusItemEntry) -> NSStatusItem {
        if let existing = self.accountStatusItems.items[entry.key] {
            return existing
        }
        return Self.makeStatusItem(
            create: self.statusBar.statusItem(withLength:),
            identity: .account(
                entry.provider.instanceID,
                accountToken: Self.accountStatusItemToken(accountID: entry.accountID)),
            defaults: self.settings.userDefaults,
            legacyDefaultItemIndex: nil,
            onCreated: { item in
                // Register before setup callbacks can re-enter vending (see `lazyStatusItem`).
                self.accountStatusItems.items[entry.key] = item
            })
    }

    private func accountStatusItemMenu(for entry: AccountStatusItemEntry) -> NSMenu {
        if let existing = self.accountStatusItems.menus[entry.key] {
            return existing
        }
        let menu = self.makeMenu(for: entry.provider)
        self.accountStatusItems.menus[entry.key] = menu
        self.accountStatusItems.menuFocus[ObjectIdentifier(menu)] = AccountStatusItemFocus(
            provider: entry.provider,
            accountID: entry.accountID)
        return menu
    }

    /// The account an account item's menu is scoped to, if `menu` belongs to one.
    func accountStatusItemFocus(for menu: NSMenu) -> AccountStatusItemFocus? {
        self.accountStatusItems.menuFocus[ObjectIdentifier(menu)]
    }

    /// Renders the focused account's card in place of the provider's selected-account cards.
    /// Returns false when `menu` is not an account item's menu.
    func addAccountStatusItemCard(to menu: NSMenu, focusMenu: NSMenu, context: MenuCardContext) -> Bool {
        guard let focus = self.accountStatusItemFocus(for: focusMenu) else { return false }
        if let model = self.store.accountStatusItemCardModel(for: focus.provider, accountID: focus.accountID) {
            self.addStackedMenuCards([model], to: menu, context: context)
        } else {
            // Never fall back to the provider card: it belongs to whichever account is selected.
            let item = NSMenuItem(title: L("Unavailable"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        return true
    }

    /// Change signature for the store icon observer, so account usage updates redraw account items.
    func accountStatusItemObservationSignature() -> String {
        self.desiredAccountStatusItemEntries(providers: self.accountStatusItemProviders()).map { entry in
            [
                entry.key,
                entry.badge,
                Self.iconSignatureValue(entry.snapshot?.primary?.usedPercent),
                Self.iconSignatureValue(entry.snapshot?.secondary?.usedPercent),
                entry.error == nil ? "ok" : "error",
            ].joined(separator: ":")
        }.joined(separator: ",")
    }

    func applyAccountStatusItemIcons() {
        guard !self.accountStatusItems.items.isEmpty else { return }
        for entry in self.desiredAccountStatusItemEntries(providers: self.accountStatusItemProviders()) {
            guard let item = self.accountStatusItems.items[entry.key] else { continue }
            self.applyAccountStatusItemIcon(entry, statusItem: item)
        }
    }

    /// A reduced `applyIcon(for:phase:)`: the account's own usage with a short account badge, without
    /// loading animations, which are provider-scoped.
    private func applyAccountStatusItemIcon(_ entry: AccountStatusItemEntry, statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }
        let provider = entry.provider
        let tint = self.providerTintColor(for: provider, button: button)
        let style = self.store.style(for: provider)
        let warningFlash = self.quotaWarningFlashActive(provider: provider)
        button.toolTip = "\(self.store.metadata(for: provider).displayName) · \(entry.label)"
        statusItem.length = NSStatusItem.variableLength

        if self.settings.menuBarShowsBrandIconWithPercent,
           self.applyAccountStatusItemLayout(entry, statusItem: statusItem, button: button, warningFlash: warningFlash)
        {
            // Layouts render outside the signature cache; drop it so a later legacy render is not skipped.
            self.accountStatusItems.renderSignatures[entry.key] = nil
            return
        }

        if self.settings.menuBarShowsBrandIconWithPercent, let brand = self.brandIcon(provider) {
            let title = [entry.badge, self.menuBarDisplayText(for: provider, snapshot: entry.snapshot)]
                .compactMap(\.self)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let signature = [
                "mode=brandPercent",
                "title=\(title)",
                "style=\(String(describing: style))",
                "warningFlash=\(warningFlash ? "1" : "0")",
                "highContrast=\(self.shouldUseHighContrastStatusItemContent ? "1" : "0")",
                "providerTint=\(tint?.description ?? "template")",
            ].joined(separator: "|")
            guard self.accountStatusItems.renderSignatures[entry.key] != signature else { return }
            self.accountStatusItems.renderSignatures[entry.key] = signature
            let image = warningFlash ? Self.quotaWarningFlashImage(base: brand) : brand
            self.setButtonContent(image: image, title: title, tint: tint, for: button)
            return
        }

        let resolved = self.resolvedMenuBarIconPercents(
            provider: provider,
            snapshot: entry.snapshot,
            style: style,
            showUsed: self.settings.usageBarsShowUsed)
        let credits = self.menuBarCreditsRemainingForIcon(provider: provider, snapshot: entry.snapshot)
        let stale = entry.error != nil
        let statusIndicator = self.store.statusIndicator(for: provider)
        let signature = [
            "mode=icon",
            "badge=\(entry.badge)",
            "style=\(String(describing: style))",
            "primary=\(Self.iconSignatureValue(resolved?.primary))",
            "weekly=\(Self.iconSignatureValue(resolved?.secondary))",
            "credits=\(Self.iconSignatureValue(credits))",
            "stale=\(stale ? "1" : "0")",
            "status=\(statusIndicator.rawValue)",
            "warningFlash=\(warningFlash ? "1" : "0")",
            "hideCritters=\(self.settings.menuBarHidesCritters ? "1" : "0")",
            "highContrast=\(self.shouldUseHighContrastStatusItemContent ? "1" : "0")",
            "providerTint=\(tint?.description ?? "template")",
        ].joined(separator: "|")
        guard self.accountStatusItems.renderSignatures[entry.key] != signature else { return }
        self.accountStatusItems.renderSignatures[entry.key] = signature
        let image = IconRenderer.makeIcon(
            primaryRemaining: resolved?.primary,
            weeklyRemaining: resolved?.secondary,
            creditsRemaining: credits,
            stale: stale,
            style: style,
            statusIndicator: statusIndicator,
            hideCritters: self.settings.menuBarHidesCritters,
            quotaLayoutPolicy: .provider(provider, snapshot: entry.snapshot))
        self.setButtonContent(
            image: warningFlash ? Self.quotaWarningFlashImage(base: image) : image,
            title: entry.badge,
            tint: tint,
            for: button)
    }

    /// Renders the provider's menu bar layout (the same windows the provider item shows, e.g. session) with
    /// the account's own usage. Returns false when the layout does not apply and the legacy styles render.
    private func applyAccountStatusItemLayout(
        _ entry: AccountStatusItemEntry,
        statusItem: NSStatusItem,
        button: NSStatusBarButton,
        warningFlash: Bool) -> Bool
    {
        let provider = entry.provider
        let resolution = self.renderedMenuBarLayoutResolution(for: provider)
        guard !resolution.usesLegacyRendering, self.settings.menuBarIconStyle == .iconAndPercent else {
            return false
        }
        let now = Date()
        let data = self.store.menuBarLayoutRenderData(
            provider: provider,
            snapshot: entry.snapshot,
            iconKey: "\(provider.rawValue):\(warningFlash ? "warning" : "normal")",
            accountLabel: entry.badge.isEmpty ? nil : entry.badge,
            costs: self.menuBarLayoutCosts(provider: provider, now: now),
            now: now)
        let icon = self.brandIcon(provider).map { warningFlash ? Self.quotaWarningFlashImage(base: $0) : $0 }
        let rendered = self.menuBarLayoutRenderer.render(
            layout: Self.accountStatusItemLayout(resolution.layout, showsBadge: !entry.badge.isEmpty),
            data: data,
            icon: icon,
            options: self.menuBarLayoutRenderOptions(for: provider, button: button, now: now))
        statusItem.length = Self.applyMenuBarLayoutContent(rendered, for: button, gap: self.settings.menuBarLayoutGap)
        return true
    }

    /// The badge rides in an account-label token right after the icon, unless the layout already has one.
    static func accountStatusItemLayout(_ layout: MenuBarLayout, showsBadge: Bool) -> MenuBarLayout {
        guard showsBadge, var firstLine = layout.lines.first, !firstLine.contains(.accountLabel) else { return layout }
        let index = firstLine.firstIndex(of: .icon).map { $0 + 1 } ?? 0
        firstLine.insert(.accountLabel, at: index)
        return MenuBarLayout(lines: [firstLine] + layout.lines.dropFirst())
    }
}
