#!/usr/bin/env zsh
# vpnii export — reads a wg config (typically from /etc/wireguard, user-
# readable when owned), strips vpnii hooks, writes the clean version into
# a destination dir. No sudo needed. Useful for: extract a clean copy you
# can edit and reinstall via `vpnii install`.

_cmd_export() {
  while (( $# > 0 )); do
    case "$1" in
      -y|--yes) _VPNII_ASSUME_YES=1; shift ;;
      --) shift; break ;;
      -*) _die "unknown export flag: $1  (try -y/--yes)" ;;
      *)  break ;;
    esac
  done
  if (( $# < 1 || $# > 2 )); then
    _die "usage: vpnii export [-y] <wireguard-config.conf> [<dest-dir>]"
  fi

  local source="$1"
  local dest_dir="${2:-$PWD}"

  [[ -f "$source" ]] || _die "not found: $source"
  [[ -r "$source" ]] || _die "not readable: $source (the file is not yours — run 'vpnii setup' first to take ownership)"

  local name="${source:t:r}"
  local target="${dest_dir}/${name}.conf"

  printf 'vpnii export: %s\n' "$source"
  _info "tunnel name: $name"
  _info "target: $target"

  if [[ ! -d "$dest_dir" ]]; then
    mkdir -p "$dest_dir"
    chmod 700 "$dest_dir"
    _ok "created $dest_dir (mode 0700)"
  fi

  if [[ -e "$target" ]]; then
    _warn "target already exists: $target"
    if ! _ask "Overwrite?"; then
      _info "aborted — nothing changed"
      return 1
    fi
  fi

  _strip_to_file "$source" "$target"
  chmod 600 "$target"

  if grep -qE "vpnii(-state)?" "$target" 2>/dev/null; then
    _warn "still contains vpnii references — manual review needed at $target"
  else
    _ok "exported clean to $target (mode 0600)"
  fi

  printf '\nNext steps:\n'
  printf '  edit if needed: %s\n' "$target"
  printf '  install:        vpnii install %s\n' "$target"
}
