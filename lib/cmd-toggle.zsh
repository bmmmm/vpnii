#!/usr/bin/env zsh
# vpnii toggle / reconnect — convenience wrappers that flip an existing
# tunnel's state. Both delegate to the regular up/down handlers, so wg-quick,
# cache markers, and tailscale all behave the same way.

# `vpnii toggle <name>`: if active, take it down; otherwise bring it up.
# Active means: a wg-quick .name marker exists, a cache file exists, or
# (for the tailscale name) an interface holds a CGNAT IP.
_cmd_toggle() {
  [[ $# -eq 1 ]] || _die "usage: vpnii toggle <name>"
  local name="$1"

  # Tailscale special-case — use the live IP check, not file markers.
  if [[ "$name" == "$VPNII_TS_NAME" || "$name" == "tailscale" ]]; then
    if _vpnii_tailscale_active; then
      _cmd_tailscale_down
    else
      _cmd_tailscale_up
    fi
    return
  fi

  _validate_name "$name"
  if [[ -f "${VPNII_WG_DIR}/${name}.name" || -f "${VPNII_CACHE_DIR}/${name}" ]]; then
    _cmd_down "$name"
  else
    _cmd_up "$name"
  fi
}

# `vpnii reconnect <name>`: down + up at once. Useful when a tunnel goes
# stale (no recent handshake, DERP relay change for tailscale, etc.).
_cmd_reconnect() {
  [[ $# -eq 1 ]] || _die "usage: vpnii reconnect <name>"
  local name="$1"
  _validate_name "$name"

  _info "reconnect: down then up"
  _cmd_down "$name" || true
  printf '\n'
  _cmd_up "$name"
}
