#!/usr/bin/env zsh
# vpnii statusline — fixed-width output for cc-statusline / tmux / sketchybar.
#
# Two slots:
#   - VPN (wg-quick + cache):  empty when no tunnel up
#   - Tailscale:               always rendered when VPNII_TS_ENABLED=1
#
# Each slot padded to a configurable column width so the surrounding
# statusline doesn't jitter when state changes. Long tunnel names
# truncated with horizontal ellipsis.
#
# Width knobs (defaults sized for typical wg name + "⬢ ts"):
#   VPNII_STATUSLINE_WG_W  default 14
#   VPNII_STATUSLINE_TS_W  default 5

_cmd_statusline() {
  local wg_w="${VPNII_STATUSLINE_WG_W:-14}"
  local ts_w="${VPNII_STATUSLINE_TS_W:-5}"

  local wg_text="" ts_text=""

  local -a reply
  _vpnii_collect_tunnels
  if (( ${#reply} > 0 )); then
    wg_text="${VPNII_SYM_VPN} ${(j:, :)reply}"
  fi

  if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]]; then
    if _vpnii_tailscale_active; then
      ts_text="${VPNII_TS_SYM_ACTIVE} ${VPNII_TS_NAME}"
    else
      ts_text="${VPNII_TS_SYM_INACTIVE} off"
    fi
  fi

  # Truncate overlong text with `…`. ${#var} in zsh is char count, which
  # matches column count for the single-cell unicode symbols we use.
  if (( ${#wg_text} > wg_w )); then
    wg_text="${wg_text[1,wg_w-1]}…"
  fi
  if (( ${#ts_text} > ts_w )); then
    ts_text="${ts_text[1,ts_w-1]}…"
  fi

  # Right-pad each slot. printf %*s counts bytes, but spaces are 1 byte
  # = 1 column, so the math holds.
  local wg_pad=$(( wg_w - ${#wg_text} ))
  local ts_pad=$(( ts_w - ${#ts_text} ))
  (( wg_pad < 0 )) && wg_pad=0
  (( ts_pad < 0 )) && ts_pad=0

  printf '%s%*s  %s%*s\n' "$wg_text" "$wg_pad" "" "$ts_text" "$ts_pad" ""
}
