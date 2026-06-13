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

  # Resolvers are addressed by IP, not hostname, so this still works when the
  # system resolver is broken — which is exactly when you reach for `vpnii ip`
  # (sanity check right after a tunnel comes up or down). v4 and v6 transports
  # need a resolver address of the matching family, so the set is picked per
  # `family`. Fields are space-separated because v6 literals contain colons:
  #   <resolver-ip> <query-host> <qtype> <label>
  # OpenDNS answers with a plain A/AAAA; Cloudflare and Google wrap the IP in
  # a quoted TXT record — quotes/whitespace are stripped uniformly below.
  local -a sources
  if (( family == 6 )); then
    sources=(
      "2620:119:35::35 myip.opendns.com AAAA OpenDNS"
      "2606:4700:4700::1111 whoami.cloudflare TXT Cloudflare"
      "2001:4860:4802:32::a o-o.myaddr.l.google.com TXT Google"
    )
  else
    sources=(
      "208.67.222.222 myip.opendns.com A OpenDNS"
      "1.1.1.1 whoami.cloudflare TXT Cloudflare"
      "216.239.32.10 o-o.myaddr.l.google.com TXT Google"
    )
  fi

  # `|| ip=""` swallows non-zero from dig + pipefail propagation under
  # `set -euo pipefail` — otherwise a failing first source aborts the
  # whole script before we can try the next one.
  local entry resolver host qtype label ip
  for entry in "${sources[@]}"; do
    local -a parts=(${=entry})
    resolver="${parts[1]}" host="${parts[2]}" qtype="${parts[3]}" label="${parts[4]}"
    ip=$(dig "+short" "+time=3" "+tries=1" "-${family}" "$qtype" "$host" "@${resolver}" 2>/dev/null \
      | tr -d '"\r\n ') || ip=""
    if [[ -n "$ip" ]]; then
      printf '%s  (via %s)\n' "$ip" "$label"
      return 0
    fi
  done

  _die "couldn't reach any DNS source  (network down? IPv${family} blocked?)"
}
