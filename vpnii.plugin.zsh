#!/usr/bin/env zsh
# vpnii — VPN status indicator for zsh RPROMPT
#
# oh-my-zsh plugin:  clone to $ZSH_CUSTOM/plugins/vpnii, add "vpnii" to plugins=()
# Standalone:        source this file from ~/.zshrc
#
# Configuration (set before sourcing):
#   VPNII_CACHE_DIR    state file directory  (default: ~/.cache/vpnii)
#   VPNII_SYM_VPN      indicator symbol      (default: ⬡)
#   VPNII_CLR_ACTIVE   zsh prompt color      (default: %F{green})
#   VPNII_CLR_RESET    zsh prompt reset      (default: %f)
#   VPNII_ENABLED      set to "0" to disable (default: enabled)

export VPNII_HOME="${VPNII_HOME:-${0:A:h}}"
source "${VPNII_HOME}/lib/vpnii.zsh"
