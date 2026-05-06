#!/usr/bin/env zsh
# vpnii — VPN status indicator for zsh RPROMPT
# oh-my-zsh plugin entry point. Source directly for standalone use.
#
# State file: written by wg-quick PostUp/PreDown (or bin/vpnii-state)
# No sudo, no network calls, no external dependencies.

export VPNII_HOME="${VPNII_HOME:-${0:A:h}}"
export VPNII_CACHE_DIR="${VPNII_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"

source "${VPNII_HOME}/lib/visual.zsh"
source "${VPNII_HOME}/lib/vpnii.zsh"
