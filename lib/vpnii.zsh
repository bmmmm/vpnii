#!/usr/bin/env zsh
# vpnii core — precmd hook + public API
#
# State protocol (presence-based):
#   Active tunnel:   $VPNII_CACHE_DIR/<TunnelName>  exists
#   Inactive tunnel: file absent
#   Multiple tunnels: multiple files, one per tunnel

: "${VPNII_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"
: "${VPNII_SYM_VPN:=⬡}"
: "${VPNII_CLR_ACTIVE:=%F{green}}"
: "${VPNII_CLR_RESET:=%f}"

# vpnii_active_tunnels — print active tunnel names, one per line
# Returns 1 if no tunnels active
function vpnii_active_tunnels {
  [[ -d "$VPNII_CACHE_DIR" ]] || return 1
  local found=0 f
  for f in "$VPNII_CACHE_DIR"/*(N); do
    [[ -f "$f" ]] || continue
    printf '%s\n' "${f:t}"
    found=1
  done
  (( found ))
}

function _vpnii_precmd {
  [[ "${VPNII_ENABLED:-1}" == "0" ]] && return
  local tunnels=() f
  [[ -d "$VPNII_CACHE_DIR" ]] || return
  for f in "$VPNII_CACHE_DIR"/*(N); do
    [[ -f "$f" ]] && tunnels+=("${f:t}")
  done
  (( ${#tunnels} == 0 )) && return
  local label="${(j:, :)tunnels}"
  RPROMPT="${RPROMPT:+${RPROMPT} }${VPNII_CLR_ACTIVE}${VPNII_SYM_VPN} ${label}${VPNII_CLR_RESET}"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
