#!/usr/bin/env zsh
# vpnii where — show what each active tunnel actually routes, plus the
# system default route. Answers the "is my traffic actually going through
# the tunnel?" question that vpnii status / list / diag don't address.
#
# wg-quick tunnels: AllowedIPs from the config file (all peers concatenated).
# Tailscale:        hardcoded 100.64.0.0/10 (CGNAT mesh).
# Default route:    netstat -rn — `route get` would need raw-socket perms,
#                   netstat just reads /var/run/route entries.

_cmd_where() {
  local found=0 f name conf allowed tag

  # 1. Active wg-quick tunnels — read their AllowedIPs from /etc/wireguard.
  for f in "${VPNII_WG_DIR}"/*.name(N.); do
    name="${f:t:r}"
    conf="/etc/wireguard/${name}.conf"
    if [[ ! -r "$conf" ]]; then
      printf '%-12s → (config not readable; run: vpnii setup)\n' "$name"
      found=1
      continue
    fi
    # Concatenate AllowedIPs from every [Peer] section.
    allowed=$(grep -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "$conf" \
      | sed -E 's/^[[:space:]]*AllowedIPs[[:space:]]*=[[:space:]]*//' \
      | tr ',' '\n' | sed 's/[[:space:]]*//g' | sort -u \
      | paste -sd ', ' -)
    if [[ "$allowed" == *"0.0.0.0/0"* || "$allowed" == *"::/0"* ]]; then
      tag="full-tunnel"
    elif [[ -z "$allowed" ]]; then
      tag="no AllowedIPs found"
    else
      tag="split"
    fi
    printf '%-12s → %s  (%s)\n' "$name" "$allowed" "$tag"
    found=1
  done

  # 2. Cache-only tunnels (Passepartout, etc.) — we don't know what they
  # route, just acknowledge their existence.
  if [[ -d "$VPNII_CACHE_DIR" ]]; then
    for f in "${VPNII_CACHE_DIR}"/*(N.); do
      name="${f:t}"
      printf '%-12s → (cache marker; routes managed by external client)\n' "$name"
      found=1
    done
  fi

  # 3. Tailscale — CGNAT range only when an exit node isn't in use, but
  # we don't probe for that here (would need OSS CLI; App Store is sandboxed).
  if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]] && _vpnii_tailscale_active; then
    printf '%-12s → 100.64.0.0/10  (mesh)\n' "$VPNII_TS_NAME"
    found=1
  fi

  # 4. System default route. netstat -rn is read-only and works without
  # the raw-socket privilege that `route get` needs.
  printf '\n'
  local def_line gw iface
  def_line=$(netstat -rn -f inet 2>/dev/null | awk '$1 == "default" { print; exit }')
  if [[ -n "$def_line" ]]; then
    # Split the netstat row in zsh; columns are: dest gw flags ifr (BSD).
    local -a fields=(${=def_line})
    gw="${fields[2]}"
    iface="${fields[4]}"
    # If default goes via utun while a 0.0.0.0/0 wg is up, that's the VPN
    # carrying it. Otherwise default is direct (either no VPN or split-only).
    if [[ "$iface" == utun* ]]; then
      printf '%-12s → %s via %s  (likely VPN-routed)\n' "default v4" "$gw" "$iface"
    else
      printf '%-12s → %s via %s  (direct, no VPN)\n' "default v4" "$gw" "$iface"
    fi
  else
    _warn "couldn't read default route from netstat"
  fi

  (( found )) || _info "no active tunnels"
}
