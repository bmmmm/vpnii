#!/usr/bin/env zsh
# vpnii setup — adaptive: maintenance on existing /etc/wireguard configs,
# or first-time wizard when the dir is empty.
#
# Maintenance does two things per config: chown to the user (sudo-free
# future edits) and strip stale vpnii(-state) PostUp/PreDown hooks.
# The wizard lives in lib/cmd-wizard.zsh.

_cmd_setup() {
  while (( $# > 0 )); do
    case "$1" in
      -y|--yes) _VPNII_ASSUME_YES=1; shift ;;
      --) shift; break ;;
      -*) _die "unknown setup flag: $1  (try -y/--yes)" ;;
      *)  break ;;
    esac
  done

  # Explicit configs given → maintenance on those, no auto-detection.
  if (( $# > 0 )); then
    _setup_maintenance "$@"
    return
  fi

  # No args → adaptive: maintenance if /etc/wireguard has configs, wizard if empty.
  local configs=()
  if [[ -d /etc/wireguard ]]; then
    configs=( /etc/wireguard/*.conf(N.) )
  fi
  if (( ${#configs} == 0 )); then
    _setup_wizard
  else
    _setup_maintenance "${configs[@]}"
  fi
}

_setup_maintenance() {
  # Make sure the directory itself is user-owned so glob/listing works
  # without sudo. This is a one-time fix for installs that pre-date the
  # dir-chown in _cmd_install.
  if [[ -d /etc/wireguard ]]; then
    local dir_owner
    dir_owner=$(_file_owner /etc/wireguard)
    if [[ "$dir_owner" != "$USER" ]]; then
      _warn "/etc/wireguard owned by $dir_owner — sudo needed to list"
      if _ask "Take ownership of the directory? (sudo chown $USER /etc/wireguard)"; then
        sudo chown "$USER" /etc/wireguard
        _ok "now owned by $USER"
      fi
    fi
  fi

  printf 'vpnii setup — %d config(s) to check\n' "$#"
  local conf
  for conf in "$@"; do
    if [[ ! -e "$conf" ]]; then
      _warn "$conf not found, skipping"
      continue
    fi
    _setup_one "$conf"
  done
  printf '\n'
}

_setup_one() {
  local conf="$1"
  local name="${conf:t:r}"
  printf '\n\033[1m%s\033[0m  (%s)\n' "$name" "$conf"

  # 1. Ownership — let the user own the file so future edits and cleanups
  # don't need sudo. Skipped if already owned.
  local owner
  owner=$(_file_owner "$conf")
  if [[ "$owner" == "$USER" ]]; then
    _ok "owned by $USER"
  else
    _warn "owned by $owner — sudo needed for read/write"
    if _ask "Take ownership? (sudo chown ${USER}:staff $conf)"; then
      sudo chown "${USER}:staff" "$conf"
      _ok "now owned by $USER"
    else
      _info "leaving ownership as-is — further steps may need sudo"
    fi
  fi

  # 2. Stale hooks — only check if we can read the file.
  if [[ ! -r "$conf" ]]; then
    _err "not readable — skipping hook check"
    return
  fi
  if grep -qE "vpnii(-state)?" "$conf" 2>/dev/null; then
    _warn "stale vpnii hooks found in PostUp/PreDown"
    if _ask "Strip them?"; then
      _strip_hooks "$conf"
    fi
  else
    _ok "no stale vpnii hooks"
  fi
}

# Strips hooks in-place via a $TMPDIR scratch file. No disk backup is
# retained — config values (PrivateKey, Endpoint, …) never leave
# /etc/wireguard. The strip is deterministic and transactional: if
# _strip_to_file fails (set -e aborts), the original is untouched.
_strip_hooks() {
  local conf="$1"
  if [[ ! -w "$conf" ]]; then
    _err "not writable — cannot strip"
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)
  _strip_to_file "$conf" "$tmpfile"
  cp "$tmpfile" "$conf"
  rm -f "$tmpfile"
  _ok "stripped (no backup retained)"
}
