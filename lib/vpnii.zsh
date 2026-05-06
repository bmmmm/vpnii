#!/usr/bin/env zsh
# vpnii core — precmd hook that appends VPN segment to RPROMPT
#
# State file: $VPNII_CACHE_DIR/<tunnel-name>  (presence = active)
# Multiple tunnels supported: one file per active tunnel.
#
# wg-quick PostUp:  mkdir -p "$VPNII_CACHE_DIR" && touch "$VPNII_CACHE_DIR/<name>"
# wg-quick PreDown: rm -f "$VPNII_CACHE_DIR/<name>"

: "${VPNII_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"
: "${VPNII_SYM_VPN:=⬡}"
: "${VPNII_CLR_ACTIVE:=%F{green}}"
: "${VPNII_CLR_RESET:=%f}"

function _vpnii_precmd {
  [[ -d "$VPNII_CACHE_DIR" ]] || return

  local tunnels=()
  local f
  for f in "$VPNII_CACHE_DIR"/*(N); do
    [[ -f "$f" ]] && tunnels+=("${f:t}")
  done
  (( ${#tunnels} == 0 )) && return

  local label="${(j:,:)tunnels}"
  RPROMPT="${RPROMPT:+${RPROMPT} }${VPNII_CLR_ACTIVE}${VPNII_SYM_VPN} ${label}${VPNII_CLR_RESET}"
}

autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
add-zsh-hook    precmd _vpnii_precmd
