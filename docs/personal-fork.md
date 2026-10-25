---
summary: "Personal fork workflow (Arturgrr/CodexBar): upstream sync, local install, Claude profile accounts, account icons, and the Subscriptions menu."
read_when:
  - Syncing this fork with steipete/CodexBar
  - Installing the fork build locally
  - Setting up multiple Claude Code accounts
---

# Personal fork

This fork keeps upstream `steipete/CodexBar` untouched on `main` and carries personal changes on `personal`.

## Branches and remotes

| Name | Points to | Rule |
| --- | --- | --- |
| `origin` | `github.com/Arturgrr/CodexBar` | push target |
| `upstream` | `github.com/steipete/CodexBar` | fetch only (push URL is `DISABLED`) |
| `main` | mirror of `upstream/main` | never commit here |
| `personal` | `main` + personal commits | rebased on every sync |

## Sync with upstream

```bash
./Scripts/fork_sync.sh          # fast-forward main, rebase personal, push both
./Scripts/fork_sync.sh --no-push
```

On a rebase conflict the script stops; resolve it, run `git rebase --continue`, then rerun the script.

## Install the fork build

Requires Xcode (the widget extension and SwiftUI macros need it). When `xcode-select` still points at the Command
Line Tools, the script uses `/Applications/Xcode.app` through `DEVELOPER_DIR`.

```bash
brew uninstall --cask codexbar   # once; ~/.config/codexbar is kept
./Scripts/fork_install.sh        # package, replace /Applications/CodexBar.app, relaunch, link the CLI
```

The build is ad-hoc signed, so it has no Sparkle feed and never auto-updates over the fork. Its code signature changes
on every rebuild, so macOS may ask again for Keychain access (browser Safe Storage, Claude Code credentials) after an
update.

## Claude profile accounts

Each Claude Code profile (`CLAUDE_CONFIG_DIR`) can be a Claude token account. In Settings → Providers → Claude, add
one account per profile with a `claude-profile:` token:

| Label | Token |
| --- | --- |
| Personal | `claude-profile:~/.claude` |
| Work | `claude-profile:~/.claude-work` |

- The default `~/.claude` profile keeps the ambient routing (OAuth → CLI), exactly like no account.
- Any other profile is fetched only through its own `claude` CLI with `CLAUDE_CONFIG_DIR` set. Claude Code reads its
  own Keychain item; CodexBar never reads that profile's credentials. Like other background CLI probes, the first
  fetch needs a manual **Refresh**, and background probes run at most every 15 minutes per profile.
- Profile accounts never import browser cookies, so a browser session cannot be attributed to the wrong account.
- Local cost history of a custom profile scans only that profile's `projects` directory.
- Relative paths are rejected; use `~/…` or an absolute path.

## One icon per account

Menu → **Subscriptions → One icon per account**. In split (non-merged) icon mode, a provider with two or more
accounts shows one menu bar item per enabled account instead of its single item. Each item shows that account's usage
with a one-letter badge (the label's initial, or an ordinal when Hide Personal Info is on; omitted when it is the
provider's only visible account), and its menu shows only that account's card. Every account is refreshed while
the option is on.

Account sources follow the Overview precedence: claude-swap/tcr, then managed Codex accounts, then token accounts.

## Subscriptions menu

The **Subscriptions** submenu, above Settings, has checkmarks to:

- turn a provider on or off (same as the Settings toggle);
- turn an individual account's menu bar item on or off (while account icons are on).

Providers turned off from this submenu stay listed there so they can be turned back on. If every account of a
provider is turned off, the provider falls back to its single item.
