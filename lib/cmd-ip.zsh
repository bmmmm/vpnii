#!/usr/bin/env zsh
# vpnii ip — fetch the current external IP. Useful sanity check after
# bringing a tunnel up: "is my traffic actually going through it?"
# curl ships with macOS, no new dependency.

_cmd_ip() {
  local family=4
  while (( $# > 0 )); do
    case "$1" in
      -4) family=4; shift ;;
      -6) family=6; shift ;;
      -h|--help)
        printf 'usage: vpnii ip [-4 | -6]\n  -4    IPv4 (default)\n  -6    IPv6\n'
        return 0
        ;;
      *) _die "unknown ip flag: $1  (try -4 or -6)" ;;
    esac
  done

  command -v curl &>/dev/null || _die "curl not found  (it ships with macOS — PATH issue?)"

  # Multi-source fallback. Each one is plain-text IP only, no JSON parsing
  # needed. Same set covers v4 and v6.
  local -a sources=(
    "ifconfig.io"
    "icanhazip.com"
    "api.ipify.org"
  )

  # `|| ip=""` swallows non-zero from curl + the pipefail propagation
  # under `set -euo pipefail` — otherwise a failing first source aborts
  # the whole script before we can try the next one.
  local src ip
  for src in "${sources[@]}"; do
    ip=$(curl "-${family}" -sS --max-time 5 "https://${src}" 2>/dev/null | tr -d ' \r\n') || ip=""
    if [[ -n "$ip" ]]; then
      printf '%s  (via %s)\n' "$ip" "$src"
      return 0
    fi
  done

  _die "couldn't reach any IP source  (network down? IPv${family} blocked?)"
}
