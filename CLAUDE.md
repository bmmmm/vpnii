# vpnii

VPN status indicator for the zsh RPROMPT plus a small CLI over wg-quick and
Tailscale. Zero dependencies, pure system-state detection (no daemon, no
WireGuard config changes), and it works with the Mac App Store Tailscale build
whose CLI is sandboxed off from the daemon.

## Identity

This repo follows the Claude push convention. Commits authored as
`bmmmm <hi@brtsz.de>`, pushed to Forgejo (`forgejo.example.com/your-org/vpnii`) via
HTTPS-with-token. Per-repo setup: `./scripts/setup-claude-identity.sh`.
See `~/ops/runbooks/identity-setup.md`.

## Conventions

- Cross-repo notes, runbooks, audits: `~/ops/`
- Per-repo intent (current focus, blockers, next): `~/ops/projects/vpnii.md`

## Build / Test

- Test suite: `./tests/run.zsh` (pure zsh, no deps; stubs every system binary,
  and flags any test file that crashes or has a syntax error)
- Syntax check: `zsh -n bin/vpnii lib/*.zsh`
- Run the CLI directly: `bin/vpnii <command>` — see `bin/vpnii help`
- Install / uninstall: `./install.sh` / `./uninstall.sh`
- CI runs the suite + `shellcheck scripts/*.sh` + a TODO/FIXME marker gate
  (`.forgejo/workflows/ci.yml`)
