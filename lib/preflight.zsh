#!/usr/bin/env zsh
# Preflight checks — "is the binary available and usable?" guards that
# every command would otherwise duplicate. Each `_require_*` either
# returns silently (precondition met) or `_die`s with an actionable
# install hint.
#
# Why centralise: the install hint will eventually need updating (Linux
# package names, OSS-tailscale path, etc.) and a single source of truth
# is cheaper than chasing five identical lines.

_require_wg_quick() {
  command -v wg-quick &>/dev/null \
    || _die "wg-quick not found  (install with: brew install wireguard-tools)"
}

_require_wg() {
  command -v wg &>/dev/null \
    || _die "wg not found  (install with: brew install wireguard-tools)"
}

# Tailscale on the Mac App Store sandboxes its CLI off from the daemon —
# `tailscale status --json` exits 0 but emits a "Tailscale CLI failed to
# start" marker on stderr. Detect that, and surface the App-Store-vs-OSS
# guidance so users don't waste time wondering why nothing happens.
_tailscale_cli_works() {
  command -v tailscale &>/dev/null || return 1
  local out
  out=$(tailscale status --json 2>&1)
  [[ "$out" != *"Tailscale CLI failed"* ]]
}

_tailscale_sandboxed_die() {
  _err "tailscale CLI can't reach the daemon"
  printf '      The Mac App Store build sandboxes its CLI off — toggle\n'
  printf '      tailscale via the menu bar app instead. Or install the\n'
  printf '      OSS build (brew install tailscale) for CLI control.\n'
  exit 1
}

_require_tailscale_cli() {
  _tailscale_cli_works && return 0
  _tailscale_sandboxed_die
}
