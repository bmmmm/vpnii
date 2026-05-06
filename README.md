# vpnii

VPN status indicator for zsh. Shows active WireGuard tunnels in your RPROMPT.

```
~  ⬡ HomeLab
```

Zero dependencies. No background processes. No polling. Works via wg-quick lifecycle hooks.

## How it works

vpnii reads **state files** — one file per active tunnel:

```
~/.cache/vpnii/HomeLab    ← HomeLab tunnel is active
~/.cache/vpnii/Work       ← Work tunnel is also active
```

File exists = tunnel active. File gone = tunnel down. A `precmd` hook reads these files before each prompt and updates `RPROMPT`.

## Install

```zsh
git clone ssh://git@git.home:2222/your-org/vpnii.git ~/path/to/vpnii
cd ~/path/to/vpnii
./install.sh
```

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

## wg-quick integration

Add to your WireGuard interface config (`/etc/wireguard/HomeLab.conf`):

```ini
[Interface]
# ...

PostUp  = sudo -u $SUDO_USER vpnii-state up %i
PreDown = sudo -u $SUDO_USER vpnii-state down %i
```

`%i` is replaced by wg-quick with the interface name.

> **Why `sudo -u $SUDO_USER`?**
> wg-quick runs as root. Without this, state files are owned by root and your
> shell cannot delete them — the indicator stays active after the tunnel goes down.
> `sudo -u` from a root context needs no password. `$SUDO_USER` is set by sudo
> to the user who ran `sudo wg-quick up` — no hardcoded username needed.
> macOS `su` has no `-c` flag (BSD su), so `sudo -u` is the correct approach.

## `vpnii-state` CLI

```
vpnii-state up <tunnel>    mark tunnel active
vpnii-state down <tunnel>  mark tunnel inactive
vpnii-state list           list active tunnels (one per line)
vpnii-state status         human-readable: "⬡ HomeLab" or "no active tunnels"
vpnii-state clear          remove all active tunnels
```

## Configuration

Set these before sourcing vpnii:

| Variable | Default | Description |
|----------|---------|-------------|
| `VPNII_CACHE_DIR` | `~/.cache/vpnii` | State file directory |
| `VPNII_SYM_VPN` | `⬡` | Indicator symbol |
| `VPNII_CLR_ACTIVE` | `%F{green}` | zsh prompt color |
| `VPNII_CLR_RESET` | `%f` | zsh prompt reset |
| `VPNII_ENABLED` | `1` | Set to `0` to disable the hook |

Example:

```zsh
VPNII_SYM_VPN="🔒"
VPNII_CLR_ACTIVE="%F{cyan}"
source /path/to/vpnii/vpnii.plugin.zsh
```

## Public API

```zsh
vpnii_active_tunnels    # prints active tunnel names, one per line; exit 1 if none
```

Useful for scripting:

```zsh
if vpnii_active_tunnels &>/dev/null; then
  echo "VPN is up"
fi
```

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Tailscale event hook support
- [ ] Homebrew tap
