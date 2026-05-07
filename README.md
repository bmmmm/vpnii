# vpnii

VPN status indicator for zsh. Shows active WireGuard tunnels in your RPROMPT.

```
~  ⬡ HomeLab
```

Zero dependencies. No background processes. No polling. No config changes to WireGuard.

## How it works

vpnii detects active tunnels from system state — no hooks, no elevated privileges needed:

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

That's it. No WireGuard config changes required.

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
| `VPNII_ENABLED` | `1` | Set to `0` to disable the hook |

## Public API

```zsh
vpnii_active_tunnels    # prints active tunnel names, one per line; exit 1 if none
```

```zsh
if vpnii_active_tunnels &>/dev/null; then
  echo "VPN is up"
fi
```

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Tailscale support
- [ ] Homebrew tap
