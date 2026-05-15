#!/usr/bin/env zsh
# First-time wizard for `vpnii setup` when /etc/wireguard is empty.
# Three paths — most users arrive at vpnii already holding a config:
#   1) _wizard_import   path to a config file on disk
#   2) _wizard_paste    paste config content inline (clipboard via $TMPDIR
#                       scratch with mode 0600 from the first byte)
#   3) _wizard_generate fresh keypair + skeleton (assist path)
#
# All three paths funnel into _cmd_install which lands the config at
# /etc/wireguard/<name>.conf with proper ownership.

_setup_wizard() {
  printf '\033[1mvpnii setup — first-time wizard\033[0m\n'
  printf '\033[2m(no configs in /etc/wireguard)\033[0m\n'

  _phase "Dependencies"
  _require_wg_quick
  _require_wg
  _ok "wg-quick: $(command -v wg-quick)"
  _ok "wg:       $(command -v wg)"

  # Two-source check for already-running tunnels: .name files (wg-quick's
  # convention, no sudo needed) plus `wg show interfaces` (catches raw wg
  # setups that bypass wg-quick; needs sudo on macOS, silent fail otherwise).
  _phase "Active tunnels"
  local active=( ${(f)"$(vpnii_active_tunnels 2>/dev/null)"} )
  local wg_ifs
  wg_ifs=$(wg show interfaces 2>/dev/null) || wg_ifs=""
  if [[ -n "$wg_ifs" ]]; then
    local iface
    for iface in ${(s: :)wg_ifs}; do
      (( ${active[(I)$iface]} )) || active+=("$iface")
    done
  fi
  if (( ${#active} > 0 )); then
    _warn "wg is already running — active tunnel(s):"
    local t
    for t in "${active[@]}"; do printf '      %s\n' "$t"; done
    printf '\n'
    if ! _ask "Continue with setup anyway?"; then
      _info "aborted — tear the tunnel down first if you want a clean slate"
      return 0
    fi
  else
    _ok "no active tunnels (checked .name files and wg show)"
  fi

  # If WireGuard.app is installed, give a hint on how to extract its tunnels —
  # those are stored in Keychain + NetworkExtension, not as .conf files, but
  # the app has an "Export Tunnels" feature that produces a .zip we can use.
  if [[ -d /Applications/WireGuard.app || -d "$HOME/Applications/WireGuard.app" ]]; then
    _phase "WireGuard.app detected"
    _info "To reuse a tunnel from the app:"
    printf '      Open the app → Settings → "Export Tunnels" → save the .zip,\n'
    printf '      unzip it, then choose [1] below. The export contains private\n'
    printf '      keys — delete the unzipped files after install.\n'
  fi

  _phase "Setup mode"
  printf 'What do you have?\n'
  printf '  [1] A path to a wg config file (most common — provider, admin, backup)\n'
  printf '  [2] The config content to paste in (clipboard never hits a tmpfile)\n'
  printf '  [3] Nothing yet — generate a fresh keypair and skeleton\n\n'
  printf '  → Choice [1]: '

  local choice
  read -r choice || _die "aborted"
  : "${choice:=1}"

  case "$choice" in
    1) _wizard_import ;;
    2) _wizard_paste ;;
    3) _wizard_generate ;;
    *) _die "invalid choice: $choice  (expected 1, 2 or 3)" ;;
  esac
}

_wizard_import() {
  _phase "Import"

  # If WireGuard.app is installed, scan ~/Downloads for .conf files —
  # the export .zip typically lands there, often inside a nested folder.
  # Only files that look like wg configs ([Interface]+[Peer]+PrivateKey)
  # are kept — pi-hole's setupVars.conf etc. would be a false positive.
  local found=()
  if [[ -d /Applications/WireGuard.app || -d "$HOME/Applications/WireGuard.app" ]]; then
    local candidate
    for candidate in "$HOME/Downloads"/**/*.conf(N.); do
      if grep -q '^\[Interface\]' "$candidate" 2>/dev/null \
        && grep -q '^\[Peer\]' "$candidate" 2>/dev/null \
        && grep -qE '^PrivateKey\s*=' "$candidate" 2>/dev/null; then
        found+=("$candidate")
      fi
    done
  fi

  local default=""
  if (( ${#found} == 1 )); then
    default="${found[1]}"
    _info "found in ~/Downloads: ${default/#$HOME/~}"
  elif (( ${#found} > 1 )); then
    _info "found ${#found} configs in ~/Downloads:"
    local i=1 f
    for f in "${found[@]}"; do
      printf '      [%d] %s\n' "$i" "${f/#$HOME/~}"
      (( i++ ))
    done
  fi

  if [[ -n "$default" ]]; then
    printf '  → Path to config [%s]: ' "${default/#$HOME/~}"
  elif (( ${#found} > 1 )); then
    printf '  → Path, or number from the list above: '
  else
    printf '  → Path to config: '
  fi

  local source
  read -r source || _die "aborted"
  source="${source/#\~/$HOME}"

  # Resolve: empty → default, numeric → list index, else literal path
  if [[ -z "$source" && -n "$default" ]]; then
    source="$default"
  elif [[ "$source" =~ ^[0-9]+$ ]] && (( ${#found} > 0 )); then
    local idx="$source"
    if (( idx >= 1 && idx <= ${#found} )); then
      source="${found[$idx]}"
    else
      _die "invalid index: $idx (expected 1..${#found})"
    fi
  fi

  [[ -n "$source" ]] || _die "path required"
  [[ -f "$source" ]] || _die "not found: $source"
  printf '\n'
  _cmd_install "$source"
}

# Reads pasted content into a $TMPDIR scratch file (mode 0600 via global
# umask 077), then hands it straight to _cmd_install which lands it as
# /etc/wireguard/<name>.conf. The tmpfile is wiped on function exit so
# nothing under the user's home stays behind.
_wizard_paste() {
  _phase "Paste"
  printf '  → Tunnel name (e.g. HomeLab): '
  local name
  read -r name || _die "aborted"
  [[ -n "$name" ]] || _die "tunnel name required"
  [[ "$name" == */* || "$name" == .* ]] && _die "invalid tunnel name: $name"

  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT

  printf '\n'
  printf '  Paste the wg config below. End with a line containing only "EOF",\n'
  printf '  or press Ctrl+D when done:\n\n'

  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" == "EOF" ]] && break
    printf '%s\n' "$line" >> "$tmpfile"
  done

  if ! grep -q '^\[Interface\]' "$tmpfile"; then
    _warn "no [Interface] section found — paste might be incomplete"
  fi
  if grep -qE '^PrivateKey\s*=' "$tmpfile"; then
    _ok "paste captured (PrivateKey present)"
  else
    _warn "no PrivateKey line — wg-quick will refuse this config"
  fi

  printf '\n'
  _cmd_install -n "$name" "$tmpfile"
}

# Builds a wg config from prompts plus a freshly-generated keypair into a
# $TMPDIR scratch file (mode 0600 via global umask 077), prints the public
# key for the user to share, then hands the file to _cmd_install. tmpfile
# is wiped on function exit — config lives only at /etc/wireguard/<name>.conf.
_wizard_generate() {
  _phase "Generate"

  local name address peer_pubkey peer_endpoint peer_allowed dns

  printf '  → Tunnel name (e.g. HomeLab): '
  read -r name || _die "aborted"
  [[ -n "$name" ]] || _die "tunnel name required"
  [[ "$name" == */* || "$name" == .* ]] && _die "invalid tunnel name: $name"

  printf '  → Your VPN address with mask (e.g. 192.168.189.100/24): '
  read -r address || _die "aborted"
  [[ -n "$address" ]] || _die "address required"

  printf '  → Server public key: '
  read -r peer_pubkey || _die "aborted"
  [[ -n "$peer_pubkey" ]] || _die "server public key required"

  printf '  → Server endpoint (host:port): '
  read -r peer_endpoint || _die "aborted"
  [[ -n "$peer_endpoint" ]] || _die "endpoint required"

  printf '  → Allowed IPs [0.0.0.0/0]: '
  read -r peer_allowed || _die "aborted"
  : "${peer_allowed:=0.0.0.0/0}"

  printf '  → DNS (optional, blank to skip): '
  read -r dns || _die "aborted"

  local privkey pubkey
  privkey=$(wg genkey)
  pubkey=$(printf '%s' "$privkey" | wg pubkey)

  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT

  {
    printf '[Interface]\n'
    printf 'PrivateKey = %s\n' "$privkey"
    printf 'Address    = %s\n' "$address"
    [[ -n "$dns" ]] && printf 'DNS        = %s\n' "$dns"
    printf '\n[Peer]\n'
    printf 'PublicKey           = %s\n' "$peer_pubkey"
    printf 'Endpoint            = %s\n' "$peer_endpoint"
    printf 'AllowedIPs          = %s\n' "$peer_allowed"
    printf 'PersistentKeepalive = 25\n'
  } > "$tmpfile"

  printf '\n\033[1mYour public key — paste on the server side:\033[0m\n'
  printf '  %s\n\n' "$pubkey"

  _cmd_install -n "$name" "$tmpfile"
}
