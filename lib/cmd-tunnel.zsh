#!/usr/bin/env zsh
# Tunnel state commands — up, down, list, status, clear.
#
# up/down route through wg-quick when a /etc/wireguard/<name>.conf exists,
# falling back to manual cache markers (under VPNII_CACHE_DIR) for VPN
# clients that aren't wg-quick (Passepartout, IKEv2, etc.).

# Returns 0 if the config's [Peer] AllowedIPs covers the default route
# (0.0.0.0/0 or ::/0). Used by _cmd_up to detect "two full-tunnels at
# once" conflicts where both want to own the default route.
_is_full_tunnel() {
  local conf="$1"
  [[ -r "$conf" ]] || return 1
  # Find AllowedIPs lines, then check for 0.0.0.0/0 or ::/0 with a
  # non-digit boundary on each side — otherwise "10.0.0.0/0" (literal
  # typo) would match as a suffix.
  grep -E '^[[:space:]]*AllowedIPs[[:space:]]*=' "$conf" 2>/dev/null \
    | grep -qE '(^|[^0-9])(0\.0\.0\.0/0|::/0)([^0-9]|$)'
}

_cmd_up() {
  local name=""
  if (( $# == 0 )); then
    if [[ -d /etc/wireguard && ! -r /etc/wireguard ]]; then
      _die "/etc/wireguard isn't readable as $USER  (run: sudo chown $USER /etc/wireguard)"
    fi
    local configs=( /etc/wireguard/*.conf(N.) )
    local -a names=()
    local c
    for c in "${configs[@]}"; do names+=("${c:t:r}"); done
    if (( ${#names} == 0 )); then
      _die "no wg-quick configs in /etc/wireguard  (run: vpnii setup)"
    fi
    _pick_one "Available tunnels" "${names[@]}" || _die "aborted"
    name="$REPLY"
  else
    [[ $# -ge 1 ]] || _die "up takes a tunnel name"
    name="$1"; shift
  fi

  # Tailscale branch: name matches the configured TS label or the literal
  # "tailscale". Extra args (e.g. profile) get forwarded.
  if [[ "$name" == "$VPNII_TS_NAME" || "$name" == "tailscale" ]]; then
    _cmd_tailscale_up "$@"
    return
  fi
  (( $# == 0 )) || _die "up takes at most one tunnel name (extra args only valid for tailscale)"

  _validate_name "$name"
  local conf="/etc/wireguard/${name}.conf"

  # If a wg-quick config exists, this is a wg-quick tunnel — bring it up.
  if [[ -f "$conf" ]]; then
    if [[ -f "${VPNII_WG_DIR}/${name}.name" ]]; then
      _info "$name is already up"
      return 0
    fi

    # Full-tunnel conflict check: if this config covers the default route
    # AND another tunnel covering it is already up, two routes will fight
    # and the user usually didn't intend it. Warn + confirm.
    if _is_full_tunnel "$conf"; then
      local f other other_conf
      local -a conflicts=()
      for f in "${VPNII_WG_DIR}"/*.name(N.); do
        other="${f:t:r}"
        [[ "$other" == "$name" ]] && continue
        other_conf="/etc/wireguard/${other}.conf"
        _is_full_tunnel "$other_conf" && conflicts+=("$other")
      done
      if (( ${#conflicts} > 0 )); then
        _warn "another full-tunnel is up: ${(j:, :)conflicts}"
        _info "two tunnels with 0.0.0.0/0 will fight over the default route"
        _ask "Bring up $name anyway?" || _die "aborted"
      fi
    fi

    command -v wg-quick &>/dev/null || _die "wg-quick not found  (install with: brew install wireguard-tools)"
    _info "sudo wg-quick up $name"
    sudo wg-quick up "$name"
    printf '\n'
    _ok "tunnel up: $name"
    return
  fi

  # Otherwise: manual cache state for non-wg-quick VPN clients.
  mkdir -p "$VPNII_CACHE_DIR"
  touch "${VPNII_CACHE_DIR}/${name}"
  _ok "marked active in cache: $name"
}

_cmd_down() {
  local name=""
  if (( $# == 0 )); then
    local -a active=( ${(f)"$(vpnii_active_tunnels 2>/dev/null)"} )
    # Tailscale isn't in vpnii_active_tunnels (it's a separate indicator),
    # but it should be a pickable down-target when up.
    if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]] && _vpnii_tailscale_active; then
      active+=("$VPNII_TS_NAME")
    fi
    if (( ${#active} == 0 )); then
      _info "no active tunnels"
      return 0
    fi
    _pick_one "Active tunnels" "${active[@]}" || _die "aborted"
    name="$REPLY"
  else
    [[ $# -eq 1 ]] || _die "down takes at most one tunnel name"
    name="$1"
  fi

  # Tailscale branch.
  if [[ "$name" == "$VPNII_TS_NAME" || "$name" == "tailscale" ]]; then
    _cmd_tailscale_down
    return
  fi

  _validate_name "$name"
  local cache_file="${VPNII_CACHE_DIR}/${name}"
  local wg_marker="${VPNII_WG_DIR}/${name}.name"
  local conf="/etc/wireguard/${name}.conf"

  # If wg-quick manages it (active or known config), tear it down via wg-quick.
  if [[ -f "$wg_marker" || -f "$conf" ]]; then
    command -v wg-quick &>/dev/null || _die "wg-quick not found  (install with: brew install wireguard-tools)"
    _info "sudo wg-quick down $name"
    sudo wg-quick down "$name"
    printf '\n'
    _ok "tunnel down: $name"
    return
  fi

  # Manual cache: remove if present, otherwise idempotent no-op.
  if [[ -f "$cache_file" ]]; then
    rm -f "$cache_file"
    _ok "cleared cache: $name"
  fi
}

_cmd_list() {
  vpnii_active_tunnels || true
}

_cmd_status() {
  _vpnii_collect_tunnels
  local -a parts=()
  if (( ${#reply} > 0 )); then
    parts+=("$VPNII_SYM_VPN ${(j:, :)reply}")
  fi
  if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]]; then
    if _vpnii_tailscale_active; then
      parts+=("$VPNII_TS_SYM_ACTIVE $VPNII_TS_NAME")
    else
      parts+=("$VPNII_TS_SYM_INACTIVE off")
    fi
  fi
  if (( ${#parts} == 0 )); then
    printf 'no active tunnels\n'
  else
    printf '%s\n' "${(j:  :)parts}"
  fi
}

_cmd_clear() {
  if [[ -d "$VPNII_CACHE_DIR" ]]; then
    rm -f "${VPNII_CACHE_DIR}/"*(N.)
    # Older versions wrote .vpnii-bak files containing full config values
    # under backups/ — wipe any leftover so private keys don't linger.
    rm -rf "${VPNII_CACHE_DIR}/backups"
  fi
}
