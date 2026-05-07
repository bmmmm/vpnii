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
vpnii-state up <tunnel>    mark tunnel active
vpnii-state down <tunnel>  mark tunnel inactive
vpnii-state list           list active tunnels (one per line)
vpnii-state status         human-readable: "⬡ HomeLab" or "no active tunnels"
vpnii-state clear          remove all state files
```

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

Shows active tunnels, detection sources, binary/PATH status, and flags any
stale WireGuard config hooks left over from earlier vpnii versions.

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

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Tailscale support
- [ ] Homebrew tap
