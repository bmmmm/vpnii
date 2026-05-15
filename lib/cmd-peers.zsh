#!/usr/bin/env zsh
# vpnii peers — readable peer list per tunnel.
#
# wg-quick: parses `wg show <name> dump` (8 tab-separated fields per peer:
#   pubkey, preshared, endpoint, allowed-ips, last-handshake-unix, rx, tx, ka).
#   The first dump line is the interface — we skip it.
#
# tailscale: passes through `tailscale status` for now. The CLI output is
#   already a peer table; reformatting would just hide upstream changes.

# Human-readable bytes. zsh integer division loses precision for the
# fractional cases; we use float arithmetic and printf %.1f.
_human_bytes() {
  local b="$1"
  if (( b < 1024 ));            then printf '%dB'    "$b"
  elif (( b < 1048576 ));       then printf '%.1fKB' "$((b / 1024.0))"
  elif (( b < 1073741824 ));    then printf '%.1fMB' "$((b / 1048576.0))"
  else                               printf '%.2fGB' "$((b / 1073741824.0))"
  fi
}

_cmd_peers() {
  [[ $# -eq 1 ]] || _die "usage: vpnii peers <tunnel>"
  local name="$1"

  # Tailscale: pass through the CLI's table. Sandboxed App Store build
  # can't reach the daemon, so we surface that explicitly.
  if _is_tailscale_name "$name"; then
    _require_tailscale_cli
    tailscale status 2>&1
    return
  fi

  _validate_name "$name"
  if [[ ! -f "${VPNII_WG_DIR}/${name}.name" ]]; then
    _die "$name is not active"
  fi

  _require_wg

  # `wg show <name> dump` may need sudo on macOS — the runtime socket is
  # often root-owned. We try without first; if it fails, surface a hint
  # rather than silently re-running with sudo.
  local dump
  dump=$(wg show "$name" dump 2>/dev/null) || {
    _err "wg show $name failed  (sudo needed?)"
    printf '      try: sudo wg show %s dump\n' "$name"
    exit 1
  }
  if [[ -z "$dump" ]]; then
    _info "no peers configured on $name"
    return 0
  fi

  printf '\033[1m%s peers:\033[0m\n' "$name"
  printf '  %-12s  %-15s  %-24s  %-9s  %-9s\n' "pubkey" "handshake" "endpoint" "↑ tx" "↓ rx"

  local now first=1 pub psk endpoint allowed hs rx tx ka
  now=$(date +%s)
  while IFS=$'\t' read -r pub psk endpoint allowed hs rx tx ka; do
    # First line of `wg show dump` is the interface (private/public/listen/fwmark).
    if (( first )); then first=0; continue; fi
    [[ -z "$pub" ]] && continue

    local pubsnip="${pub[1,4]}…${pub[-5,-1]}"
    local hs_str
    if [[ -z "$hs" || "$hs" == "0" ]]; then
      hs_str="never"
    else
      hs_str="$(_vpnii_format_age $((now - hs))) ago"
    fi
    [[ -z "$endpoint" || "$endpoint" == "(none)" ]] && endpoint="—"

    printf '  %-12s  %-15s  %-24s  %-9s  %-9s\n' \
      "$pubsnip" "$hs_str" "$endpoint" \
      "$(_human_bytes "${tx:-0}")" "$(_human_bytes "${rx:-0}")"
  done <<< "$dump"
}
