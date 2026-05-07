#!/usr/bin/env zsh
# vpnii core — detection helpers + precmd hook + public API
#
# Two indicators in the prompt:
#   1. VPN tunnel indicator — wg-quick (.name files) and cache files
#   2. Tailscale indicator  — always-visible state (active+account / off)
#
# Detection sources for the VPN indicator:
#   * /var/run/wireguard/<name>.name  wg-quick on macOS, zero config, zero elevation
#   * $VPNII_CACHE_DIR/<name>         manual state files (Passepartout, etc.)
#
# Detection sources for tailscale:
#   * CGNAT IP (100.64/10) on any interface — active/inactive (works for OSS
#     CLI and App Store builds; the App Store CLI can't reach the daemon
#     socket, but ifconfig always sees the tunnel address)
#   * Account name from the Tailscale macsys/macos plist's cached profile,
#     or `tailscale status --json` if the CLI is reachable

: "${VPNII_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/vpnii}"
: "${VPNII_WG_DIR:=/var/run/wireguard}"
: "${VPNII_SYM_VPN:=⬡}"
: "${VPNII_TS_ENABLED:=1}"
: "${VPNII_TS_NAME:=tailscale}"
: "${VPNII_TS_SYM_ACTIVE:=⊕}"
: "${VPNII_TS_SYM_INACTIVE:=⊖}"
(( ${+VPNII_CLR_ACTIVE} ))      || VPNII_CLR_ACTIVE='%F{green}'
(( ${+VPNII_CLR_RESET} ))       || VPNII_CLR_RESET='%f'
(( ${+VPNII_TS_CLR_INACTIVE} )) || VPNII_TS_CLR_INACTIVE='%F{8}'

# Returns 0 if any local interface holds an IP in the Tailscale CGNAT range
# (100.64.0.0/10 → second octet 64..127).
function _vpnii_tailscale_active {
  ifconfig 2>/dev/null | grep -qE 'inet 100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'
}

# Echoes the Tailscale account display name, or nothing if it can't be
# determined. Cached for the lifetime of the shell once a non-empty value
# is found — accounts rarely change mid-session, and the plist parse costs
# ~20ms which adds up across prompt redraws.
typeset -g _vpnii_ts_account_cache=""
function _vpnii_tailscale_account {
  if [[ -n "$_vpnii_ts_account_cache" ]]; then
    print -- "$_vpnii_ts_account_cache"
    return 0
  fi

  # Source 1: macOS App Store / DMG plist. The cached current profile is
  # stored as a binary <data> blob containing JSON with UserProfile.DisplayName.
  # Convert to XML, extract the <data> block, base64-decode, regex out the name.
  local plist account=""
  for plist in \
    "$HOME/Library/Preferences/io.tailscale.ipn.macsys.plist" \
    "$HOME/Library/Preferences/io.tailscale.ipn.macos.plist"
  do
    [[ -r "$plist" ]] || continue
    local tmp
    tmp=$(mktemp) || continue
    if plutil -convert xml1 -o "$tmp" "$plist" 2>/dev/null; then
      account=$(awk '
        /<key>com\.tailscale\.cached\.currentProfile<\/key>/{f=1; next}
        f && /<data>/{f=2; next}
        f==2 && /<\/data>/{exit}
        f==2{print}
      ' "$tmp" | tr -d ' \t\n' | base64 -D 2>/dev/null \
        | grep -oE '"DisplayName":"[^"]*"' | head -1 \
        | sed -E 's/.*:"([^"]*)".*/\1/')
    fi
    rm -f "$tmp"
    [[ -n "$account" ]] && break
  done

  # Source 2: OSS CLI status JSON. Only works when the daemon socket is
  # reachable, which excludes the App Store build (it's sandboxed off).
  if [[ -z "$account" ]] && command -v tailscale &>/dev/null; then
    account=$(tailscale status --json 2>/dev/null \
      | grep -oE '"LoginName":"[^"]*"' | head -1 \
      | sed -E 's/.*:"([^"]*)".*/\1/')
  fi

  if [[ -n "$account" ]]; then
    _vpnii_ts_account_cache="$account"
    print -- "$account"
    return 0
  fi
  return 1
}

# Populates `reply` (zsh convention) with active tunnel names from wg-quick
# and the cache dir. Tailscale is rendered separately (always-visible state),
# not bundled into this list.
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
# Tailscale is excluded — use _vpnii_tailscale_active for that.
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

  local -a parts=()

  # VPN indicator: only when at least one wg-quick/cache tunnel is up.
  if (( ${#reply} > 0 )); then
    parts+=("${VPNII_CLR_ACTIVE}${VPNII_SYM_VPN} ${(j:, :)reply}${VPNII_CLR_RESET}")
  fi

  # Tailscale indicator: always rendered when enabled — active shows the
  # account (falls back to VPNII_TS_NAME if account isn't extractable),
  # inactive shows a dim "off" so the user can tell the difference between
  # "TS is down" and "vpnii forgot about TS".
  if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]]; then
    if _vpnii_tailscale_active; then
      local account
      account=$(_vpnii_tailscale_account 2>/dev/null) || account=""
      [[ -z "$account" ]] && account="$VPNII_TS_NAME"
      parts+=("${VPNII_CLR_ACTIVE}${VPNII_TS_SYM_ACTIVE} ${account}${VPNII_CLR_RESET}")
    else
      parts+=("${VPNII_TS_CLR_INACTIVE}${VPNII_TS_SYM_INACTIVE} off${VPNII_CLR_RESET}")
    fi
  fi

  RPROMPT="${_vpnii_orig_rprompt}"
  if (( ${#parts} > 0 )); then
    RPROMPT="${RPROMPT:+${RPROMPT} }${(j:  :)parts}"
  fi
}

# Register hook only in interactive shells, so this file can be safely
# sourced from the `vpnii` CLI without side effects.
if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _vpnii_precmd 2>/dev/null
  add-zsh-hook    precmd _vpnii_precmd
fi
