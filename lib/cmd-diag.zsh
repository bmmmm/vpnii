#!/usr/bin/env zsh
# vpnii diag — reports detection sources, binaries, shell integration, and
# config hygiene. Pure read-only; never touches state.

_cmd_diag() {
  local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
  printf '\033[1mvpnii diag\033[0m\n'

  _hdr "Active tunnels"
  local found=0 f
  for f in "${VPNII_WG_DIR}"/*.name(N.); do
    local tname="${f:t:r}"
    _ok "wg-quick: ${tname}  (${f})"
    # Handshake age — green <3m, yellow 3-10m, red >10m or unavailable.
    # When wg show needs sudo (tunnel sock owned by root), we skip with
    # a quiet hint rather than spam every diag run.
    local age
    if age=$(_vpnii_handshake_age "$tname"); then
      local pretty
      pretty=$(_vpnii_format_age "$age")
      if   (( age < 180  )); then _ok   "      handshake: $pretty ago"
      elif (( age < 600  )); then _warn "      handshake: $pretty ago  (stale-ish)"
      else                        _err  "      handshake: $pretty ago  (likely dead)"
      fi
    else
      printf '      handshake: unavailable  (sudo wg show %s for details)\n' "$tname"
    fi
    found=1
  done
  if [[ -d "$VPNII_CACHE_DIR" ]]; then
    for f in "${VPNII_CACHE_DIR}"/*(N.); do
      _ok "state file: ${f:t}  (${f})"
      found=1
    done
  fi
  (( found )) || printf '  no active tunnels\n'

  if [[ "$VPNII_TS_ENABLED" == "1" ]]; then
    _hdr "Tailscale"
    if _vpnii_tailscale_active; then
      local ts_ip ts_account
      ts_ip=$(_vpnii_tailscale_ip)
      ts_account=$(_vpnii_tailscale_account 2>/dev/null) || ts_account=""
      _ok "active: ${ts_ip:-CGNAT IP}"
      if [[ -n "$ts_account" ]]; then
        _ok "account: $ts_account"
      else
        _warn "account: unknown  (no readable plist, no reachable CLI)"
      fi
    else
      _info "inactive  (no IP in 100.64.0.0/10)"
    fi
  fi

  _hdr "Detection sources"
  if [[ -d "$VPNII_WG_DIR" ]]; then
    _ok "wg-quick dir: $VPNII_WG_DIR"
  else
    _warn "wg-quick dir not found: $VPNII_WG_DIR  (wg-quick not installed?)"
  fi
  if [[ -d "$VPNII_CACHE_DIR" ]]; then
    local cache_files=( "$VPNII_CACHE_DIR"/*(N.) )
    _ok "state dir: $VPNII_CACHE_DIR  (${#cache_files} file(s))"
  else
    _warn "state dir missing: $VPNII_CACHE_DIR  (run install.sh)"
  fi

  _hdr "WireGuard binaries"
  if command -v wg-quick &>/dev/null; then
    _ok "wg-quick: $(command -v wg-quick)"
  else
    _warn "wg-quick not in PATH  (install with: brew install wireguard-tools)"
  fi
  if command -v wg &>/dev/null; then
    _ok "wg: $(command -v wg)"
  else
    _warn "wg not in PATH  (install with: brew install wireguard-tools)"
  fi

  _hdr "vpnii"
  local bin="${VPNII_HOME}/bin/vpnii"
  if [[ -x "$bin" ]]; then
    _ok "binary: $bin"
  else
    _err "binary not found: $bin"
  fi
  if [[ -L "/usr/local/bin/vpnii" ]]; then
    _ok "/usr/local/bin/vpnii → $(readlink /usr/local/bin/vpnii)"
  elif command -v vpnii &>/dev/null; then
    _ok "in PATH: $(command -v vpnii)"
  else
    _warn "not in PATH  (add ${VPNII_HOME}/bin to PATH)"
  fi
  local stale_backups=( "${VPNII_CACHE_DIR}/backups"/*(N.) )
  if (( ${#stale_backups} > 0 )); then
    _warn "stale backups (${#stale_backups}) in ${VPNII_CACHE_DIR}/backups — contain config values"
    printf '      → vpnii clear  (wipes them)\n'
  fi

  _hdr "Shell integration"
  local zshrc_real="${zshrc:A}"
  if grep -qF "vpnii.plugin.zsh" "$zshrc_real" 2>/dev/null; then
    _ok "sourced in $zshrc"
  else
    _err "not sourced in $zshrc  (run install.sh)"
  fi

  _hdr "WireGuard configs"
  local wg_dir="/etc/wireguard"
  if [[ ! -d "$wg_dir" ]]; then
    printf '  no configs in %s\n' "$wg_dir"
  else
    local any=0 conf
    for conf in "$wg_dir"/*.conf(N.); do
      any=1
      if grep -qE "vpnii(-state)?" "$conf" 2>/dev/null; then
        _warn "${conf:t}: has stale vpnii hooks (harmless, but can be cleaned)"
        printf '      → vpnii setup %s\n' "$conf"
      else
        _ok "${conf:t}: clean"
      fi
    done
    (( any )) || printf '  no .conf files found\n'
  fi

  printf '\n'
}
