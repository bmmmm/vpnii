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

Open a new shell — that's it. No WireGuard config changes, no sudo required.

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

## Other VPN tools (Passepartout, manual)

For VPN clients that don't use wg-quick, manage state manually:

```zsh
vpnii-state up <tunnel>    # mark tunnel active
vpnii-state down <tunnel>  # mark tunnel inactive
```

Or hook into your VPN client's connect/disconnect events.

## `vpnii-state` CLI

```
vpnii-state up <tunnel>    mark tunnel active (writes ~/.cache/vpnii/<tunnel>)
vpnii-state down <tunnel>  mark tunnel inactive (removes the cache file)
vpnii-state list           list active tunnels from all sources, one per line
vpnii-state status         "⬡ HomeLab, work" — same sources as the prompt
vpnii-state clear          remove all manual state files (wg-quick tunnels are unaffected)
```

`vpnii-state` only manages the manual cache directory — wg-quick tunnels are
read-only from its perspective:

- `up <name>` is a no-op (with a notice) if `<name>` is already up via wg-quick.
- `down <name>` fails with a hint when `<name>` is wg-quick-managed; the correct
  command is `sudo wg-quick down <name>`.
- `down <name>` on an inactive tunnel exits 0 with an info message (idempotent).

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
vpnii-diag
```

Output sections:

| Section | What it checks |
|---------|----------------|
| Active tunnels | currently up — from `*.name` files and the cache dir |
| Detection sources | both source directories exist and are readable |
| WireGuard binaries | `wg`, `wg-quick` resolvable in PATH |
| vpnii-state | binary present and on PATH (or symlinked to `/usr/local/bin`) |
| Shell integration | plugin sourced from `~/.zshrc` |
| WireGuard configs | flags stale `vpnii-state` hooks in `/etc/wireguard/*.conf` |

## Troubleshooting

**Indicator doesn't appear after `wg-quick up`**

Check that `/var/run/wireguard/` contains a `<name>.name` file:
```zsh
ls /var/run/wireguard/
```
If it does, run `vpnii-diag` to check shell integration.

**Indicator doesn't clear after `wg-quick down`**

The `.name` file should be removed by wg-quick automatically.
If a stale state file remains in `~/.cache/vpnii/`, clear it:
```zsh
vpnii-state clear
```

**Migrating from an earlier vpnii version (PostUp/PreDown hooks)**

If your WireGuard config has leftover `vpnii-state` calls in PostUp/PreDown,
they're harmless but can be cleaned up:
```zsh
sudo /path/to/vpnii/bin/vpnii-wg-setup --clean /etc/wireguard/<name>.conf
```
This strips the `vpnii-state` calls while leaving all other PostUp/PreDown
content (DNS entries, etc.) intact.

## Files & directories

| Path | Purpose |
|------|---------|
| `vpnii.plugin.zsh` | oh-my-zsh entry point — sources `lib/vpnii.zsh` |
| `lib/vpnii.zsh` | Detection logic, `_vpnii_precmd` hook, public `vpnii_active_tunnels` API |
| `bin/vpnii-state` | Manual state CLI for non-wg-quick VPN tools |
| `bin/vpnii-diag` | Self-check — sources, binaries, shell integration, stale hooks |
| `bin/vpnii-wg-setup` | Migration helper — strips legacy `vpnii-state` hooks from `*.conf` |
| `install.sh` / `uninstall.sh` | Adds/removes the source line in `~/.zshrc` and the PATH entry |
| `/var/run/wireguard/<name>.name` | wg-quick's tunnel marker (read-only, system-managed) |
| `~/.cache/vpnii/<name>` | Manual state file — one empty file per active tunnel |

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Tailscale support
- [ ] Homebrew tap
