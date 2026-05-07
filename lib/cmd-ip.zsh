#!/usr/bin/env zsh
# vpnii ip — fetch the current external IP via DNS. Useful sanity check
# after bringing a tunnel up: "is my traffic actually going through it?"
#
# Implementation: well-known public DNS resolvers expose a "tell me your
# IP" record. Single UDP packet per query, no TLS, no HTTP. `dig` ships
# with macOS in /usr/bin (BIND tools). Three resolvers in fallback order
# so no single operator has to be available.

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

  command -v dig &>/dev/null || _die "dig not found  (BIND tools ship with macOS — PATH issue?)"

  local rectype="A"
  (( family == 6 )) && rectype="AAAA"

  # Each entry: resolver:hostname:qtype. OpenDNS returns plain A/AAAA;
  # Cloudflare and Google return the IP wrapped in a TXT record (quoted).
  # We strip quotes and whitespace uniformly so callers don't care.
  local -a sources=(
    "resolver1.opendns.com:myip.opendns.com:${rectype}"
    "1.1.1.1:whoami.cloudflare:TXT"
    "ns1.google.com:o-o.myaddr.l.google.com:TXT"
  )

  # `|| ip=""` swallows non-zero from dig + pipefail propagation under
  # `set -euo pipefail` — otherwise a failing first source aborts the
  # whole script before we can try the next one.
  local entry resolver host qtype ip
  for entry in "${sources[@]}"; do
    IFS=: read -r resolver host qtype <<<"$entry"
    ip=$(dig "+short" "+time=3" "+tries=1" "-${family}" "$qtype" "$host" "@${resolver}" 2>/dev/null \
      | tr -d '"\r\n ' | head -1) || ip=""
    if [[ -n "$ip" ]]; then
      printf '%s  (via %s)\n' "$ip" "$resolver"
      return 0
    fi
  done

  _die "couldn't reach any DNS source  (network down? IPv${family} blocked?)"
}
