#!/usr/bin/env zsh
# vpnii core — detection helpers + precmd hook + public API
#
# Detection (in order):
#   1. /var/run/wireguard/<name>.name  — wg-quick on macOS, zero config, zero elevation
#   2. $VPNII_CACHE_DIR/<name>         — manual state files (Passepartout, other VPN tools)

: "${VPNII_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"
: "${VPNII_WG_DIR:=/var/run/wireguard}"
: "${VPNII_SYM_VPN:=⬡}"
(( ${+VPNII_CLR_ACTIVE} )) || VPNII_CLR_ACTIVE='%F{green}'
(( ${+VPNII_CLR_RESET} ))  || VPNII_CLR_RESET='%f'

# Populates `reply` (zsh convention) with active tunnel names, deduplicated.
# wg-quick names take precedence over cache entries with the same name.
function _vpnii_collect_tunnels {
  local f name
  local -A seen
  reply=()
  for f in "${VPNII_WG_DIR}"/*.name(N.); do
    name="${f:t:r}"
    (( ${+seen[$name]} )) && continue
    seen[$name]=1
    reply+=("$name")
  done
  for f in "${VPNII_CACHE_DIR}"/*(N.); do
    name="${f:t}"
    (( ${+seen[$name]} )) && continue
    seen[$name]=1
    reply+=("$name")
  done
}

# Public API: print active tunnel names, one per line; exit 1 if none.
function vpnii_active_tunnels {
  local -a reply
  _vpnii_collect_tunnels
  (( ${#reply} )) || return 1
  printf '%s\n' "${reply[@]}"
}

function _vpnii_precmd {
  [[ "${VPNII_ENABLED:-1}" == "0" ]] && return
  # Capture user's RPROMPT once on first run, so subsequent calls can rebuild
  # from the original instead of accumulating duplicates.
  (( ${+_vpnii_orig_rprompt} )) || typeset -g _vpnii_orig_rprompt="${RPROMPT:-}"
  local -a reply
  _vpnii_collect_tunnels
  RPROMPT="${_vpnii_orig_rprompt}"
  (( ${#reply} )) || return
  RPROMPT="${RPROMPT:+${RPROMPT} }${VPNII_CLR_ACTIVE}${VPNII_SYM_VPN} ${(j:, :)reply}${VPNII_CLR_RESET}"
}

# Register hook only in interactive shells, so this file can be safely
# sourced from CLI scripts (vpnii-state, vpnii-diag) without side effects.
if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
  add-zsh-hook    precmd _vpnii_precmd
fi
