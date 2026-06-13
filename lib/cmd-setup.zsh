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
  if _vpnii_has_hooks "$conf"; then
    _warn "stale vpnii hooks found in PostUp/PreDown"
    if _ask "Strip them?"; then
      _strip_hooks "$conf"
    fi
  else
    _ok "no stale vpnii hooks"
  fi
}

# Strips hooks in-place, atomically. The cleaned copy is written to a scratch
# file in the SAME directory, then rename()d over the original — a same-fs
# rename is atomic, so a crash mid-strip leaves either the old file or the new
# one intact, never a truncated config. No disk backup is retained: config
# values (PrivateKey, Endpoint, …) never leave the config's own directory.
_strip_hooks() {
  local conf="$1"
  if [[ ! -w "$conf" ]]; then
    _err "not writable — cannot strip"
    return 1
  fi

  # Prefer an atomic same-dir scratch + rename: a crash can't truncate the
  # config that way. If the directory isn't writable — e.g. a user-owned file
  # still sitting in a root-owned /etc/wireguard — fall back to a $TMPDIR
  # scratch + copy. That's non-atomic but matches the pre-atomic behavior,
  # which only required the file (not its directory) to be writable. umask 077
  # keeps either scratch at 0600; the dotfile name stays out of `*.conf` globs.
  local dir tmpfile atomic=1
  dir="${conf:h}"
  tmpfile=$(mktemp "${dir}/.vpnii-strip.XXXXXX" 2>/dev/null) || {
    atomic=0
    tmpfile=$(mktemp) || { _err "cannot create a scratch file"; return 1; }
  }
  # Clean up the scratch if the strip itself fails, so a failure never leaves
  # a .vpnii-strip.* file behind next to the config.
  _strip_to_file "$conf" "$tmpfile" || {
    rm -f "$tmpfile"; _err "strip failed — config left untouched"; return 1
  }
  chmod 600 "$tmpfile"
  if (( atomic )); then
    mv -f "$tmpfile" "$conf"
  else
    cp "$tmpfile" "$conf"
    rm -f "$tmpfile"
  fi
  _ok "stripped (no backup retained)"
}
