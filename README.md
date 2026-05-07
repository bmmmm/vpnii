# vpnii

VPN status indicator for zsh + a small CLI on top of WireGuard and Tailscale.
Two indicators in your RPROMPT — active wg/cache tunnels (`⬡`) and Tailscale
(`⬢` / dim `⊖`):

```
~  ⬡ HomeLab  ⬢ ts             # wg tunnel + tailscale active
~  ⬢ ts                        # only tailscale up
~  ⊖ off                       # tailscale not connected (dim)
```

**Zero dependencies.** No background processes, no polling, no WireGuard
config changes. Detection is pure system-state — files in `/var/run` and
the CGNAT-IP check from `ifconfig`. Works on macOS App Store Tailscale
where the official CLI fails (sandbox can't reach the daemon).

---

- [How it works](#how-it-works)
- [Install](#install) · [Uninstall](#uninstall)
- [CLI cheat sheet](#cli-cheat-sheet) · [Recipes](#recipes)
- [Configuration](#configuration)
- [Diagnostics](#diagnostics) · [Troubleshooting](#troubleshooting)
- [Files & layout](#files--layout)
- [Tests](#tests) · [Roadmap](#roadmap)

---

## How it works

Detection is pull-based — runs once per zsh prompt redraw, no daemon.

| Indicator | Source | Notes |
|-----------|--------|-------|
| `⬡ <name>` | `/var/run/wireguard/<name>.name` | wg-quick on macOS, automatic |
| `⬡ <name>` | `~/.cache/vpnii/<name>` | manual marker (Passepartout, scripts) |
| `⬢ ts` | CGNAT IP `100.64.0.0/10` on any interface | works for App Store Tailscale too |
| `⊖ off` | (no CGNAT IP) | dim — tells you tailscale is *off*, not just hidden |

The Tailscale account name (`bma`, `you@example.com`, …) is read from the
macsys plist or the OSS CLI's status JSON, but kept out of the prompt so
the indicator stays a stable width. Run `vpnii diag` to see it.

## Install

```zsh
git clone ssh://git@git.home:2222/your-org/vpnii.git ~/path/to/vpnii
cd ~/path/to/vpnii
./install.sh
```

Open a new shell. If `/etc/wireguard` already has configs, the installer
offers an interactive `vpnii setup` (one-time `sudo chown` per config so
maintenance stays sudo-free thereafter). Decline freely; runtime never
needs sudo regardless.

**oh-my-zsh:** clone into `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/vpnii`
and add `vpnii` to `plugins=()`.

**Standalone:** `source /path/to/vpnii/vpnii.plugin.zsh`.

## Uninstall

```zsh
./uninstall.sh
```

Removes the `~/.zshrc` line + PATH entry, clears the state cache.
WireGuard configs are left untouched.

## CLI cheat sheet

```
vpnii up [<tunnel> [<profile>]]   bring up (wg-quick / cache / tailscale)
vpnii down [<tunnel>]             bring down (auto-pick from active)
vpnii toggle <tunnel>             flip state
vpnii reconnect <tunnel>          down + up (fixes stale handshake / DERP)

vpnii list                        active wg tunnels — one per line
vpnii status                      "⬡ HomeLab  ⬢ ts" / "⊖ off"
vpnii statusline                  fixed-width status (cc-statusline / tmux)
vpnii where                       what each tunnel routes + default route
vpnii peers <tunnel>              per-peer table (handshake, endpoint, bytes)
vpnii ip [-4 | -6]                external IP via DNS
vpnii diag                        full status (handshake age, ts account)

vpnii setup [-y] [<conf>...]      adaptive: maintenance / first-time wizard
vpnii install [-y] [-n NAME] <conf>   land a clean wg config in /etc/wireguard
vpnii export  [-y] <conf> [<dir>]     extract a clean copy (strips legacy hooks)
vpnii edit <tunnel>               open in $EDITOR
vpnii verify <conf>               pre-flight (sections, key shapes, hooks)
vpnii rename <old> <new>          rename config + cache marker
```

`vpnii help` for the same. Tab completion (`vpnii up <TAB>`) ships with the
plugin.

`up` and `down` adapt: with a `/etc/wireguard/<name>.conf` they call
`sudo wg-quick`; without, they manage `~/.cache/vpnii/<name>` markers
for non-wg-quick clients. Bringing up a `0.0.0.0/0` tunnel while another
one is already active prompts before clobbering the default route.

The Mac App Store Tailscale build sandboxes its CLI off from the daemon,
so `vpnii up tailscale` / `down` exit with a hint pointing to the menu
bar app. Detection (`⬢ ts`) keeps working regardless.

## Recipes

**Quick "is my VPN actually carrying my traffic?":**
```zsh
vpnii where        # are routes set up correctly?
vpnii ip           # what IP does the world see?
```

**Stale tunnel — handshake older than 10 minutes?**
```zsh
vpnii diag         # spot the red handshake line
vpnii reconnect HomeLab
```

**Got a config from someone, want to vet it before installing?**
```zsh
vpnii verify ~/Downloads/work-vpn.conf
vpnii install ~/Downloads/work-vpn.conf
```

**Switch between Tailscale tailnets:**
```zsh
vpnii up ts work          # auto-prompts if profile name ambiguous
vpnii up ts personal
```

**Embed in cc-statusline / tmux without jitter:**
```zsh
vpnii statusline           # 21-char stable-width (defaults)
```

## Configuration

Set before sourcing. Common knobs:

| Variable | Default | What |
|----------|---------|------|
| `VPNII_ENABLED` | `1` | `0` disables the indicator entirely |
| `VPNII_TS_ENABLED` | `1` | `0` hides only the Tailscale slot |
| `VPNII_TS_NAME` | `ts` | label in the prompt + the name `vpnii up`/`down` accepts |
| `VPNII_SYM_VPN` | `⬡` | wg / cache indicator |
| `VPNII_TS_SYM_ACTIVE` | `⬢` | tailscale-up indicator |
| `VPNII_TS_SYM_INACTIVE` | `⊖` | tailscale-off indicator |

Less-used: `VPNII_WG_DIR`, `VPNII_CACHE_DIR`, `VPNII_CLR_ACTIVE`,
`VPNII_CLR_RESET`, `VPNII_TS_CLR_INACTIVE`, `VPNII_STATUSLINE_WG_W`,
`VPNII_STATUSLINE_TS_W`. See `lib/vpnii.zsh` for the full set with defaults.

## Diagnostics

`vpnii diag` reports active tunnels (with handshake age, color-coded —
green <3m, yellow 3-10m, red >10m / unavailable), Tailscale state +
account, binary paths, shell integration, and config-hook hygiene.

`vpnii where` complements it with what each tunnel actually routes:

```
$ vpnii where
HomeLab     → 192.168.189.0/24, 0.0.0.0/0  (full-tunnel)
ts          → 100.64.0.0/10                (mesh)

default v4  → 192.168.189.1 via en0  (direct, no VPN)
```

Tags: `full-tunnel` (config covers `0.0.0.0/0` or `::/0`), `split`
(selective prefixes), `mesh` (tailscale CGNAT). Default-route line is
tagged `likely VPN-routed` when it exits via a `utun`.

## Public API

```zsh
vpnii_active_tunnels    # prints active tunnel names; exit 1 if none
```

```zsh
if vpnii_active_tunnels &>/dev/null; then echo "VPN is up"; fi
```

## Troubleshooting

**Indicator doesn't appear after `wg-quick up`** — check
`/var/run/wireguard/` has a `<name>.name` file. If yes, `vpnii diag`
flags any shell-integration issue.

**Indicator stays after `wg-quick down`** — wg-quick should remove the
`.name` file. If a stale `~/.cache/vpnii/` marker remains: `vpnii clear`.

**`vpnii up tailscale` fails with "CLI failed to start"** — Mac App Store
build, expected. Toggle via the menu bar app. Detection still works.

**`vpnii peers` says "sudo needed?"** — `wg show <name>` reads a
root-owned socket on macOS. Run the printed `sudo wg show …` once or
configure password-less sudo for that command.

## Files & layout

| Path | Purpose |
|------|---------|
| `vpnii.plugin.zsh` | oh-my-zsh entry point |
| `lib/vpnii.zsh` | Detection + precmd hook + public API |
| `lib/ui.zsh` · `lib/strip.zsh` | Primitives + sed-based hook stripper |
| `lib/cmd-*.zsh` | Per-subcommand modules |
| `lib/_vpnii` | Zsh autoload tab completion |
| `bin/vpnii` | Dispatcher |
| `tests/` | Pure-zsh test harness |
| `install.sh` / `uninstall.sh` | `~/.zshrc` source line + PATH entry |

## Tests

```zsh
./tests/run.zsh
```

Pure zsh, no deps. ~140 assertions across 12 files cover strip, detection,
tailscale CLI, handshake parsing, CLI smoke, ip, where, statusline,
toggle, peers, conflict detection, config verify.

## Roadmap

- [ ] macOS menu bar indicator (SwiftBar/xbar plugin)
- [ ] Homebrew tap
