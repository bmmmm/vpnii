#!/usr/bin/env zsh
# vpnii dns — toggle macOS DNS resolver between presets.
#
# Two privileged ops happen here:
#  1. `networksetup -setdnsservers` writes via macOS Authorization
#     framework — triggers a GUI auth prompt when run without admin
#     context. No `sudo` prefix needed in front of `vpnii dns`.
#  2. `killall -HUP mDNSResponder` flushes the DNS cache — needs root.
#     Called via `sudo` (tries non-interactive first, falls back to
#     prompted sudo). User has TouchID for sudo configured if available.
#
# Modes:
#   home       192.168.189.4 + 1.1.1.1 fallback (Pi-hole IPv4-only).
#              Locks out FritzBox-IPv6-DNS bypass that would otherwise
#              skip Pi-hole adblock for AAAA queries.
#   public     1.1.1.1 + 1.0.0.1 — for foreign LANs / mobile when the
#              local DHCP-pushed nameserver is unreachable.
#   dhcp       clear override → DHCP-pushed nameservers (adaptive to
#              the current network).
#   show       display current state (override + effective resolver).
#   services   list all networksetup services (debug).
#
# Active service is auto-detected via the default route. Override with:
#   VPNII_DNS_SERVICE="USB 10/100/1000 LAN" vpnii dns home

# Detect networksetup service name for the interface that holds the
# default route. Pairs Hardware-Port name with Device name from
# `networksetup -listallhardwareports`. Returns non-zero on failure so
# callers can `_die` themselves — `_die` from inside command-substitution
# only exits the subshell, leaving the caller with an empty value.
_dns_detect_service() {
  local iface svc
  iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
  if [[ -z "$iface" ]]; then
    printf 'no default route — not connected to any network\n' >&2
    return 1
  fi
  svc=$(networksetup -listallhardwareports 2>/dev/null | awk -v ifc="$iface" '
    /^Hardware Port:/ { name=$0; sub(/^Hardware Port: /, "", name) }
    /^Device:/        { if ($2 == ifc) { print name; exit } }
  ')
  if [[ -z "$svc" ]]; then
    printf 'no networksetup service for interface %s\n' "$iface" >&2
    return 1
  fi
  printf '%s' "$svc"
}

# Caller-friendly: returns the service to use (env override or detected),
# or exits the script if neither is available.
_dns_resolve_service() {
  if [[ -n "${VPNII_DNS_SERVICE:-}" ]]; then
    printf '%s' "$VPNII_DNS_SERVICE"
    return 0
  fi
  _dns_detect_service
}

_dns_show() {
  local svc; svc=$(_dns_resolve_service) || _die "service detection failed"
  _hdr "Active service: $svc"
  local override
  override=$(networksetup -getdnsservers "$svc" 2>&1 || true)
  if [[ "$override" == *"There aren't any DNS Servers"* ]]; then
    _ok "DHCP-default (no manual override)"
  else
    _info "Manual override:"
    printf '%s\n' "$override" | sed 's/^/      /'
  fi
  printf '\n'
  _info "Effective resolver (scutil resolver #1):"
  scutil --dns | awk '
    /^resolver #1/ { in_block=1; next }
    /^resolver #/  { in_block=0 }
    /^$/           { in_block=0 }
    in_block && /nameserver|search domain/ {
      sub(/^[[:space:]]+/, "      "); print
    }
  '
}

_dns_set() {
  local svc="$1"; shift
  _info "networksetup -setdnsservers '$svc' $*"
  networksetup -setdnsservers "$svc" "$@" || _die "networksetup failed"
  _ok "Override applied"
}

# Flush mDNSResponder. Tries non-interactive sudo first (TouchID / cached
# password / NOPASSWD); falls back to interactive sudo so the user gets
# the standard prompt. If that also fails (no TTY, denied), emit a hint.
_dns_flush_cache() {
  if sudo -n killall -HUP mDNSResponder 2>/dev/null; then
    _ok "mDNSResponder flushed (sudo passwordless)"
  elif sudo killall -HUP mDNSResponder; then
    _ok "mDNSResponder flushed"
  else
    _warn "Could not flush — run manually: sudo killall -HUP mDNSResponder"
  fi
}

# Compare-test: probe a few well-known trackers via Pi-hole directly AND
# via the system resolver, then report whether (a) Pi-hole filters and
# (b) macOS actually routes through Pi-hole vs. some bypass (Private
# Relay, browser DoH, MDM profile).
#
# Note: doubleclick.net is intentionally NOT in the probe list — Hagezi
# `pro` and similar Google-friendly adlists allow it through. Use
# trackers that virtually every adlist blocks.
_dns_test_adblock() {
  local pihole_ip="${VPNII_DNS_PIHOLE:-192.168.189.4}"
  local -a probes=(criteo.com outbrain.com taboola.com)
  local total=${#probes}

  local hits_direct=0 unreach_direct=0
  local hits_system=0 disagrees=0
  local first_direct first_system

  local d direct system
  for d in "${probes[@]}"; do
    direct=$(dig +short +time=2 +tries=1 "$d" "@${pihole_ip}" 2>/dev/null | head -1)
    system=$(dig +short +time=2 +tries=1 "$d" 2>/dev/null | head -1)
    if [[ "$direct" == "0.0.0.0" ]]; then
      (( hits_direct++ ))
    elif [[ -z "$direct" ]]; then
      (( unreach_direct++ ))
    fi
    [[ "$system" == "0.0.0.0" ]] && (( hits_system++ ))
    [[ "$direct" != "$system" ]] && (( disagrees++ ))
    [[ -z "$first_direct" ]] && { first_direct="$direct"; first_system="$system"; }
  done

  printf '      probes: %s\n' "${probes[*]}"
  if (( unreach_direct == total )); then
    _warn "Pi-hole (${pihole_ip}) unreachable — outside home LAN, or Pi-hole down?"
  elif (( hits_direct == total && hits_system == total )); then
    _ok "Adblock active — Pi-hole filters & macOS uses Pi-hole ($total/$total blocked)"
  elif (( hits_direct == total )) && (( hits_system < total )); then
    _warn "Pi-hole filters, but macOS bypasses it ($hits_system/$total via system DNS)"
    printf '      first probe → direct: %s   system: %s\n' \
      "${first_direct:-<empty>}" "${first_system:-<empty>}"
    printf '      check: iCloud Private Relay, browser DoH, MDM/Profile\n'
  elif (( hits_direct < total )); then
    _warn "Pi-hole reachable but only filters $hits_direct/$total — adlist coverage?"
    _info "Check on Pi-hole host: docker exec pihole pihole -q <domain>"
  else
    _warn "Mixed: direct $hits_direct/$total, system $hits_system/$total, $disagrees disagree"
  fi
}

_dns_usage() {
  cat <<'EOF'
usage: vpnii dns <mode>

modes:
  show       display current DNS state (override + effective resolver)
  home       Pi-hole 192.168.189.4 + 1.1.1.1 fallback  (IPv4-only)
  public     1.1.1.1 + 1.0.0.1  (foreign LAN / mobile)
  dhcp       clear override → DHCP-pushed nameservers
  services   list all networksetup services (debug)

env:
  VPNII_DNS_SERVICE     override auto-detected service
                        (e.g. "USB 10/100/1000 LAN" instead of Wi-Fi)

note: no `sudo` prefix needed. networksetup triggers a GUI auth prompt
(once per session if your account lacks admin context). DNS cache flush
runs `sudo killall -HUP mDNSResponder` automatically — TouchID / cached
sudo / NOPASSWD will skip the prompt; otherwise you get the standard
sudo password prompt once.
EOF
}

_cmd_dns() {
  local sub="${1:-show}"; (( $# > 0 )) && shift
  case "$sub" in
    show)
      _dns_show
      ;;
    home)
      local svc; svc=$(_dns_resolve_service) || _die "service detection failed"
      _hdr "Setting home DNS (Pi-hole + 1.1.1.1, IPv4-only)"
      _info "Locks out FritzBox-IPv6 bypass that skips adblock"
      _dns_set "$svc" 192.168.189.4 1.1.1.1
      printf '\n'
      _dns_show
      printf '\n'
      _hdr "Adblock test"
      _dns_test_adblock
      _dns_flush_cache
      ;;
    public)
      local svc; svc=$(_dns_resolve_service) || _die "service detection failed"
      _hdr "Setting public DNS (1.1.1.1 + 1.0.0.1)"
      _dns_set "$svc" 1.1.1.1 1.0.0.1
      printf '\n'
      _dns_show
      _dns_flush_cache
      ;;
    dhcp)
      local svc; svc=$(_dns_resolve_service) || _die "service detection failed"
      _hdr "Clearing DNS override on $svc → DHCP-default"
      _dns_set "$svc" empty
      printf '\n'
      _dns_show
      _dns_flush_cache
      ;;
    services)
      _hdr "All networksetup services (in service-order)"
      networksetup -listnetworkserviceorder | awk '
        /^\([0-9]+\)/ { svc=$0; next }
        /^\(Hardware/ { print svc; print "  " $0; print "" }
      '
      ;;
    -h|--help|help)
      _dns_usage
      ;;
    *) _die "unknown dns mode: $sub  (try: show|home|public|dhcp|services)" ;;
  esac
}
