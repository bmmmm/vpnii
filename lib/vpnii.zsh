#!/usr/bin/env zsh
# vpnii core — precmd hook + public API
#
# Detection (in order):
#   1. /var/run/wireguard/<name>.name  — wg-quick on macOS, zero config, zero elevation
#   2. $VPNII_CACHE_DIR/<name>         — manual state files (Passepartout, other VPN tools)

: "${VPNII_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"
: "${VPNII_WG_DIR:=/var/run/wireguard}"
: "${VPNII_SYM_VPN:=⬡}"
(( ${+VPNII_CLR_ACTIVE} )) || VPNII_CLR_ACTIVE='%F{green}'
(( ${+VPNII_CLR_RESET} ))  || VPNII_CLR_RESET='%f'

# vpnii_active_tunnels — print active tunnel names, one per line; exit 1 if none
function vpnii_active_tunnels {
  local f name seen=() found=0
  for f in "${VPNII_WG_DIR}"/*.name(N); do
    [[ -f "$f" ]] || continue
    name="${f:t:r}"
    seen+=("$name")
    printf '%s\n' "$name"
    found=1
  done
  for f in "${VPNII_CACHE_DIR}"/*(N); do
    [[ -f "$f" ]] || continue
    name="${f:t}"
    (( ${seen[(I)$name]} )) || { printf '%s\n' "$name"; found=1; }
  done
  (( found ))
}

function _vpnii_precmd {
  [[ "${VPNII_ENABLED:-1}" == "0" ]] && return
  local tunnels=() seen=() f name
  for f in "${VPNII_WG_DIR}"/*.name(N); do
    [[ -f "$f" ]] || continue
    name="${f:t:r}"
    tunnels+=("$name")
    seen+=("$name")
  done
  for f in "${VPNII_CACHE_DIR}"/*(N); do
    [[ -f "$f" ]] || continue
    name="${f:t}"
    (( ${seen[(I)$name]} )) || tunnels+=("$name")
  done
  (( ${#tunnels} == 0 )) && return
  RPROMPT="${RPROMPT:+${RPROMPT} }${VPNII_CLR_ACTIVE}${VPNII_SYM_VPN} ${(j:, :)tunnels}${VPNII_CLR_RESET}"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
