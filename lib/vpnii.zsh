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
: "${VPNII_TS_NAME:=ts}"
: "${VPNII_TS_SYM_ACTIVE:=⬢}"
: "${VPNII_TS_SYM_INACTIVE:=⊖}"
(( ${+VPNII_CLR_ACTIVE} ))      || VPNII_CLR_ACTIVE='%F{green}'
(( ${+VPNII_CLR_RESET} ))       || VPNII_CLR_RESET='%f'
(( ${+VPNII_TS_CLR_INACTIVE} )) || VPNII_TS_CLR_INACTIVE='%F{8}'

# Returns 0 if a wg config still contains legacy vpnii(-state) PostUp/PreDown
# hooks from older versions. Used by install / setup / export before they
# either strip them or refuse the file. Centralised so the regex stays in
# sync — drift here once shipped a broken `export` that missed the hooks.
function _vpnii_has_hooks {
  grep -qE "vpnii(-state)?" "$1" 2>/dev/null
}

# Echoes the latest-handshake age in seconds for a wg-quick tunnel, or
# returns non-zero if unavailable (tunnel down, sudo needed, no peers
# handshaked yet). `wg show <name> latest-handshakes` outputs one
# "<peer>\t<unix-ts>" line per peer; we pick the max timestamp.
function _vpnii_handshake_age {
  local name="$1" out peer ts latest=0
  out=$(wg show "$name" latest-handshakes 2>/dev/null) || return 1
  [[ -z "$out" ]] && return 1
  while IFS=$'\t' read -r peer ts; do
    [[ -n "$ts" ]] && (( ts > latest )) && latest=$ts
  done <<< "$out"
  (( latest == 0 )) && return 1
  print -- $(( $(date +%s) - latest ))
}

# Formats a duration in seconds as "Xs", "Xm Ys", or "Xh Ym".
function _vpnii_format_age {
  local secs="$1"
  if (( secs < 60 )); then
    print -- "${secs}s"
  elif (( secs < 3600 )); then
    print -- "$((secs/60))m $((secs%60))s"
  else
    print -- "$((secs/3600))h $((secs%3600/60))m"
  fi
}

# CGNAT range used by Tailscale: 100.64.0.0/10 (second octet 64..127).
# Centralised here so detection, diag, and any future caller stay in sync.
typeset -gr _VPNII_CGNAT_RE='inet 100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'

# Returns 0 if any local interface holds an IP in the CGNAT range.
# Hot path — runs once per zsh prompt redraw. Captures ifconfig output once
# and matches in-shell via zsh's =~ to avoid the grep fork.
function _vpnii_tailscale_active {
  local out
  out=$(ifconfig 2>/dev/null)
  [[ "$out" =~ $_VPNII_CGNAT_RE ]]
}

# Echoes the first CGNAT IP found on a local interface (or empty if none).
# Used by `vpnii diag` to surface the actual address; the active-check
# above only needs a yes/no. Single fork (ifconfig), regex extract in zsh.
function _vpnii_tailscale_ip {
  local out
  out=$(ifconfig 2>/dev/null)
  [[ "$out" =~ ${_VPNII_CGNAT_RE}[0-9]+\.[0-9]+ ]] && print -- "${MATCH#inet }"
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
    # EXIT trap inside subshell so an early return / continue still cleans
    # up; the trap fires when the (...) subshell exits.
    account=$(
      trap 'rm -f "$tmp"' EXIT
      plutil -convert xml1 -o "$tmp" "$plist" 2>/dev/null || exit 0
      # The blob has two DisplayName fields (UserProfile and NetworkProfile),
      # in unstable JSON-key order. NetworkProfile.DisplayName is often
      # empty, so we filter to the first non-empty match.
      awk '
        /<key>com\.tailscale\.cached\.currentProfile<\/key>/{f=1; next}
        f && /<data>/{f=2; next}
        f==2 && /<\/data>/{exit}
        f==2{print}
      ' "$tmp" | tr -d ' \t\n' | base64 -D 2>/dev/null \
        | grep -oE '"DisplayName":"[^"]+"' | head -1 \
        | sed -E 's/.*:"([^"]*)".*/\1/'
    )
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

  # Tailscale indicator: always rendered when enabled. Compact label
  # (VPNII_TS_NAME, default "ts") — account name lives in `vpnii diag`,
  # not the prompt, so the indicator stays a stable width regardless of
  # which tailnet/profile is active.
  if [[ "${VPNII_TS_ENABLED:-1}" == "1" ]]; then
    if _vpnii_tailscale_active; then
      parts+=("${VPNII_CLR_ACTIVE}${VPNII_TS_SYM_ACTIVE} ${VPNII_TS_NAME}${VPNII_CLR_RESET}")
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
