#!/usr/bin/env zsh
# vpnii install — copies a clean wg config into /etc/wireguard/<name>.conf
# and chowns it to the current user, so further edits/cleanups never need
# sudo. Rejects configs containing vpnii hooks — those should be cleaned
# via `vpnii setup` first, since `install` is meant to land already-clean
# configs.

_cmd_install() {
  local name=""
  while (( $# > 0 )); do
    case "$1" in
      -y|--yes)  _VPNII_ASSUME_YES=1; shift ;;
      -n|--name) [[ $# -ge 2 ]] || _die "-n/--name needs a value"; name="$2"; shift 2 ;;
      --) shift; break ;;
      -*) _die "unknown install flag: $1  (try -y/--yes or -n NAME)" ;;
      *)  break ;;
    esac
  done
  [[ $# -eq 1 ]] || _die "usage: vpnii install [-y] [-n NAME] <wireguard-config.conf>"
  local source="$1"

  [[ -f "$source" ]] || _die "not found: $source"
  [[ -r "$source" ]] || _die "not readable: $source"

  _require_wg_quick

  if _vpnii_has_hooks "$source"; then
    _die "$source contains vpnii hooks — clean first: vpnii setup $source"
  fi

  # If -n wasn't given, derive name from source filename. Reject paths,
  # leading dots, and empty names regardless of source.
  [[ -z "$name" ]] && name="${source:t:r}"
  [[ -n "$name" ]] || _die "tunnel name empty"
  [[ "$name" == */* || "$name" == .* ]] && _die "invalid tunnel name: $name"

  local target="/etc/wireguard/${name}.conf"

  printf 'vpnii install: %s\n' "$source"
  _info "tunnel name: $name"
  _info "target: $target"
  _ok "wg-quick: $(command -v wg-quick)"
  _ok "source clean (no vpnii hooks)"

  if [[ -e "$target" ]]; then
    _warn "target already exists: $target"
    if ! _ask "Overwrite?"; then
      _info "aborted — nothing changed"
      return 1
    fi
  fi

  # Single sudo handles dir creation (if needed) + cp + chown + chmod under
  # one `set -e` shell. -p preserves the source mode (0600). The bundle also
  # chowns the *directory* to the user so future ops (listing, vpnii up
  # without args, manual edits) don't need sudo.
  _info "sudo: install + chown to ${USER}:staff"
  sudo sh -s "$source" "$target" "${USER}:staff" <<'SUDO_BLOCK'
set -e
src="$1"; dst="$2"; owner="$3"
parent="$(dirname "$dst")"
if [ ! -d "$parent" ]; then
  mkdir -p "$parent"
fi
chown "$owner" "$parent"
chmod 700 "$parent"
cp -p "$src" "$dst"
chown "$owner" "$dst"
chmod 600 "$dst"
SUDO_BLOCK

  printf '\n'
  _ok "installed at $target (owned by $USER, mode 0600)"

  if _ask "Bring up now? (sudo wg-quick up $name)"; then
    printf '\n'
    _info "sudo wg-quick up $name"
    sudo wg-quick up "$name"
  else
    printf 'Later: sudo wg-quick up %s  (or vpnii up %s)\n' "$name" "$name"
  fi
}
