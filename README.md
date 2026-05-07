# vpnii

VPN status indicator for zsh. Two indicators in your RPROMPT — active tunnels
(wg-quick / cache) and Tailscale (always visible, with account name when up).

```
~  ⬡ HomeLab  ⊕ bma            # wg tunnel + tailscale active as bma
~  ⊕ bma                       # only tailscale, signed in as bma
~  ⊖ off                       # tailscale not connected (dim)
```

Zero dependencies. No background processes. No polling. No WireGuard config changes needed.

## How it works

vpnii detects state from the system — no hooks, no elevated privileges:

**VPN tunnel indicator** (`⬡`, shown only when something is up):

| Source | When used |
|--------|-----------|
| `/var/run/wireguard/<name>.name` | wg-quick on macOS (automatic) |
| `~/.cache/vpnii/<name>` | Passepartout, other VPN tools, manual use |

**Tailscale indicator** (`⊕` active / `⊖ off` dim, always visible):

| Signal | What it tells |
|--------|---------------|
| CGNAT IP `100.64.0.0/10` on any interface | active vs. inactive |
| `~/Library/Preferences/io.tailscale.ipn.macsys.plist` (or `…macos.plist`) | account name (App Store / DMG build) |
| `tailscale status --json` | account name (OSS CLI fallback) |

The IP check works for the Mac App Store build too — `tailscale status` fails
there because the CLI is sandboxed off from the daemon, but `ifconfig` always
sees the tunnel address. The plist source covers the same gap for the account
name. Disable the whole tailscale indicator with `VPNII_TS_ENABLED=0`.

## Install

```zsh
git clone ssh://git@git.home:2222/your-org/vpnii.git ~/path/to/vpnii
cd ~/path/to/vpnii
./install.sh
```

Open a new shell — that's it. If `/etc/wireguard` already contains configs,
`install.sh` offers an interactive `vpnii setup` (one-time `sudo chown` per
config so future maintenance stays sudo-free). Decline freely; runtime never
needs sudo either way.

### oh-my-zsh

```zsh
git clone ssh://git@git.home:2222/your-org/vpnii.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/vpnii"
```

Add `vpnii` to your `plugins=()` in `~/.zshrc`.

### Standalone

```zsh
source /path/to/vpnii/vpnii.plugin.zsh
```

## Uninstall

```zsh
cd ~/path/to/vpnii
./uninstall.sh
```

Removes the source line and PATH entry from `~/.zshrc`, clears the state cache.
WireGuard configs are left unchanged.

## `vpnii` CLI

A single command with subcommands:

```
vpnii up [<tunnel>]     bring tunnel up   (auto-pick if only one config, list if many)
vpnii down [<tunnel>]   bring tunnel down (auto-pick from active, list if many)
vpnii list              list active tunnels (all sources, one per line)
vpnii status            human-readable: "⬡ HomeLab" or "no active tunnels"
vpnii clear             remove all manual state files (wg-quick unaffected)
vpnii diag              show full vpnii status
vpnii setup [-y] [<conf>...]      adaptive: maintenance for existing configs, wizard for empty
vpnii export [-y] <conf> [<dir>]  read a wg config, strip hooks, write a clean copy (default cwd)
vpnii install [-y] [-n NAME] <conf>   copy a clean wg config into /etc/wireguard, owned by you
```

`up` and `down` adapt based on how the tunnel is managed:

- `/etc/wireguard/<name>.conf` exists → `vpnii up <name>` runs
  `sudo wg-quick up <name>`. `vpnii down <name>` does the corresponding
  `sudo wg-quick down`.
- No wg-quick config → `up`/`down` only manipulate `~/.cache/vpnii/<name>`,
  used by non-wg-quick VPN clients (Passepartout, manual scripts).
- Both commands accept no argument: `up` picks from configs in
  `/etc/wireguard`, `down` picks from currently-active tunnels. If only
  one matches, it's auto-selected; otherwise a numbered list is shown.
- `down` on an unknown tunnel is a silent no-op (idempotent).

Names containing `/`, leading `.`, or empty strings are rejected to keep
writes confined to the cache directory.

## Configuration

Set these before sourcing vpnii:

| Variable | Default | Description |
|----------|---------|-------------|
| `VPNII_WG_DIR` | `/var/run/wireguard` | wg-quick socket directory |
| `VPNII_CACHE_DIR` | `~/.cache/vpnii` | Manual state file directory |
| `VPNII_SYM_VPN` | `⬡` | Indicator symbol |
| `VPNII_CLR_ACTIVE` | `%F{green}` | zsh prompt color |
| `VPNII_CLR_RESET` | `%f` | zsh prompt reset |
| `VPNII_ENABLED` | `1` | Set to `0` to disable |
| `VPNII_TS_ENABLED` | `1` | Set to `0` to hide the tailscale indicator entirely |
| `VPNII_TS_NAME` | `tailscale` | Label fallback when account name can't be read |
| `VPNII_TS_SYM_ACTIVE` | `⊕` | Symbol when tailscale is connected |
| `VPNII_TS_SYM_INACTIVE` | `⊖` | Symbol when tailscale is off |
| `VPNII_TS_CLR_INACTIVE` | `%F{8}` | zsh prompt color for the "off" state |

## Public API

```zsh
vpnii_active_tunnels    # prints active tunnel names, one per line; exit 1 if none
```

```zsh
if vpnii_active_tunnels &>/dev/null; then
  echo "VPN is up"
fi
```

## Diagnostics

```zsh
vpnii diag
```

Output sections:

| Section | What it checks |
|---------|----------------|
| Active tunnels | currently up — from `*.name` files and the cache dir |
| Detection sources | both source directories exist and are readable |
| WireGuard binaries | `wg`, `wg-quick` resolvable in PATH |
| vpnii | binary present and on PATH (or symlinked to `/usr/local/bin`) |
| Shell integration | plugin sourced from `~/.zshrc` |
| WireGuard configs | flags stale `vpnii(-state)` hooks in `/etc/wireguard/*.conf` |

## `vpnii setup`

Adaptive: behaves differently depending on whether `/etc/wireguard` already
has configs.

### Maintenance mode

When configs exist, setup brings each one into a sudo-free state:

```zsh
vpnii setup            # scan all configs in /etc/wireguard
vpnii setup <conf>     # one or more specific paths
```

Per config, it offers two operations:

1. **Take ownership** — `sudo chown $USER:staff <conf>`. Only step that
   needs sudo, and only once per config. After this, you can edit and
   clean the file without root. wg-quick continues to work because
   wg-quick itself runs as root and reads the file regardless of owner.
2. **Strip legacy hooks** — removes any `vpnii-state up/down` calls from
   `PostUp`/`PreDown` left over from older versions. The strip is done
   via a `$TMPDIR` scratch file that's deleted right after the copy —
   no disk backup is retained, so config values (PrivateKey, Endpoint,
   …) never leave `/etc/wireguard`. The strip is deterministic and
   transactional; if anything fails before the copy, the original is
   untouched.

Pass `-y` / `--yes` to auto-accept every prompt — useful from non-interactive
contexts (`install.sh`, scripts).

### First-time wizard

When `/etc/wireguard` is empty or missing, `vpnii setup` (no args) starts a
wizard. It first verifies `wg`/`wg-quick` are installed (with a `brew install
wireguard-tools` hint if not), then offers three paths:

1. **Path to a config file** — most common, when you got a `.conf` from a
   VPN provider, a server admin, or a backup. Fed straight into `vpnii install`.
2. **Paste the config inline** — for configs that arrived through email or
   chat. Asked only for a tunnel name, then accepts pasted content until
   `EOF` or Ctrl+D. The paste lands in a `$TMPDIR` scratch file at mode
   `0600` (umask `077` is set globally), is handed straight to `vpnii
   install`, and the tmpfile is wiped on function exit — nothing under
   the user's home stays behind.
3. **Generate fresh** — prompts for tunnel name, VPN address, server's
   public key, endpoint, allowed IPs and optional DNS, runs
   `wg genkey | wg pubkey`, writes the skeleton to a `$TMPDIR` scratch
   file, prints the generated public key (which you share with the
   server side), and installs. Same tmpfile cleanup as paste.

All three paths land the config straight at `/etc/wireguard/<name>.conf`
with `chown user:staff`, mode `0600`. No staging directory under the
user's home is created.

`install.sh` runs `vpnii setup` automatically at the end on a fresh install.

## `vpnii export`

Reads an existing wg config, strips any vpnii hooks, and writes the clean
version into the current directory (or a directory you pass):

```zsh
vpnii export /etc/wireguard/HomeLab.conf            # → ./HomeLab.conf
vpnii export /etc/wireguard/HomeLab.conf ~/configs  # → ~/configs/HomeLab.conf
```

The source must be readable by you (own the file, or `vpnii setup` it
first to take ownership). Source is left untouched. Output gets `0600`
(via global `umask 077`); target dir `0700` if newly created.

Typical workflow when migrating off legacy hooks:

```zsh
vpnii export /etc/wireguard/HomeLab.conf   # extract a clean copy
sudo rm /etc/wireguard/HomeLab.conf        # drop the dirty original
vpnii install ~/wg/HomeLab.conf            # land the clean copy back
```

## `vpnii install`

Lands a clean wg config in `/etc/wireguard/<name>.conf` with the right
ownership in one step:

```zsh
vpnii install ~/wg/HomeLab.conf
```

It checks `wg-quick` is installed (with a `brew install wireguard-tools`
hint if not), refuses configs that still have `vpnii-state` hooks
(`vpnii setup <conf>` cleans those first), creates `/etc/wireguard/` if
needed, then `sudo cp` + `sudo chown $USER:staff` + `sudo chmod 600`.

Pass `-y` to overwrite an existing config without prompting.

After install: `sudo wg-quick up <name>` to bring the tunnel up. vpnii
detects it automatically via `/var/run/wireguard/<name>.name`.

## Troubleshooting

**Indicator doesn't appear after `wg-quick up`**

Check that `/var/run/wireguard/` contains a `<name>.name` file:
```zsh
ls /var/run/wireguard/
```
If it does, run `vpnii diag` to check shell integration.

**Indicator doesn't clear after `wg-quick down`**

The `.name` file should be removed by wg-quick automatically.
If a stale state file remains in `~/.cache/vpnii/`, clear it:
```zsh
vpnii clear
```

## Files & directories

| Path | Purpose |
|------|---------|
| `vpnii.plugin.zsh` | oh-my-zsh entry point — sources `lib/vpnii.zsh` |
| `lib/vpnii.zsh` | Detection logic, `_vpnii_precmd` hook, public `vpnii_active_tunnels` API |
| `lib/ui.zsh` | UI primitives (printing, prompts, name validation) |
| `lib/strip.zsh` | `_strip_to_file` — removes vpnii hooks from PostUp/PreDown lines |
| `lib/cmd-*.zsh` | Per-subcommand modules: tunnel, diag, setup, wizard, install, export |
| `bin/vpnii` | CLI dispatcher — sources lib modules, routes subcommands |
| `tests/run.zsh` | Test runner — pure-zsh, no deps |
| `install.sh` / `uninstall.sh` | Adds/removes the source line in `~/.zshrc` and the PATH entry |
| `/var/run/wireguard/<name>.name` | wg-quick's tunnel marker (read-only, system-managed) |
| `~/.cache/vpnii/<name>` | Manual state file — one empty file per active tunnel |

## Tests

```zsh
./tests/run.zsh
```

Pure-zsh harness, no dependencies. Covers:
- `_strip_to_file` against fixture matrix (clean, foreign hooks, claudii
  legacy, su-c form, sudo-u form, vpnii-state binary)
- Detection dedup (`_vpnii_collect_tunnels`, `vpnii_active_tunnels`)
- CLI smoke paths (help, status, list, clear, name validation)

To run tests automatically before each push, opt into the bundled hook:

```zsh
git config core.hooksPath .githooks
```

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Homebrew tap
