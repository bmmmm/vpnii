# vpnii

VPN status indicator for zsh. Shows active WireGuard tunnels in your RPROMPT.

```
~  ⬡ HomeLab
```

Zero dependencies. No background processes. No polling. No WireGuard config changes needed.

## How it works

vpnii detects active tunnels from system state — no hooks, no elevated privileges:

| Source | When used |
|--------|-----------|
| `/var/run/wireguard/<name>.name` | wg-quick on macOS (automatic) |
| `~/.cache/vpnii/<name>` | Passepartout, other VPN tools, manual use |

wg-quick creates and removes the `.name` file automatically when tunnels go up/down.

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
vpnii up <tunnel>       mark tunnel active (manual cache only)
vpnii down <tunnel>     mark tunnel inactive (manual cache only)
vpnii list              list active tunnels (all sources, one per line)
vpnii status            human-readable: "⬡ HomeLab" or "no active tunnels"
vpnii clear             remove all manual state files (wg-quick unaffected)
vpnii diag              show full vpnii status
vpnii setup [-y] [<conf>...]   chown wireguard configs and strip stale hooks (-y skips prompts)
vpnii install [-y] <conf>      copy a clean wg config into /etc/wireguard, owned by you
```

`up`/`down` are only needed for VPN clients that don't use wg-quick
(Passepartout, manual scripts) — wg-quick tunnels are picked up automatically.

The CLI only manages the manual cache directory. wg-quick tunnels are
read-only from its perspective:

- `up <name>` is a no-op (with a notice) if `<name>` is already up via wg-quick.
- `down <name>` warns to stderr if `<name>` is wg-quick-managed; the correct
  command is `sudo wg-quick down <name>`. `down` is always idempotent (exit 0).
- `down <name>` on an inactive tunnel is silent (no-op).

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

Interactive helper that brings each wireguard config into a sudo-free state:

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
   `PostUp`/`PreDown` left over from older versions. A timestamped backup
   is written to `~/.cache/vpnii/backups/` (the parent directory
   `/etc/wireguard/` stays root-owned and write-locked).

Pass `-y` / `--yes` to auto-accept every prompt — useful from non-interactive
contexts (`install.sh`, scripts).

`install.sh` runs `vpnii setup` automatically at the end if `/etc/wireguard`
already contains configs.

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
| `bin/vpnii` | CLI dispatcher — all subcommands |
| `install.sh` / `uninstall.sh` | Adds/removes the source line in `~/.zshrc` and the PATH entry |
| `/var/run/wireguard/<name>.name` | wg-quick's tunnel marker (read-only, system-managed) |
| `~/.cache/vpnii/<name>` | Manual state file — one empty file per active tunnel |

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Tailscale support
- [ ] Homebrew tap
