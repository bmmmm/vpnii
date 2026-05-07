#!/usr/bin/env zsh
# UI primitives — printing helpers, interactive prompts, name validation,
# small utilities used across all command modules.

_die()   { printf 'vpnii: %s\n' "$*" >&2; exit 1; }
_info()  { printf '  → %s\n' "$*"; }
_ok()    { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
_warn()  { printf '  \033[0;33m⚠\033[0m %s\n' "$*"; }
_err()   { printf '  \033[0;31m✗\033[0m %s\n' "$*"; }
_hdr()   { printf '\n\033[1m%s\033[0m\n' "$*"; }
# Phase header for multi-step flows: subtle dim rule + bold title.
_phase() { printf '\n\033[2m──\033[0m \033[1m%s\033[0m\n' "$*"; }

# stat is BSD on macOS, GNU on Linux — different flags for the same field.
# Falls back to '?' so callers can still compare the result safely.
_file_owner() {
  stat -f '%Su' "$1" 2>/dev/null || stat -c '%U' "$1" 2>/dev/null || echo '?'
}

# Tunnel names are used as path components (state files, .conf names).
# Reject path separators and leading dots so a stray "../etc/passwd" or
# ".hidden" can't redirect cache writes or .conf installs.
_validate_name() {
  if [[ -z "$1" || "$1" == */* || "$1" == .* ]]; then
    _die "invalid tunnel name: $1"
  fi
}

# Picks a tunnel name from a candidate list. With one candidate, returns it
# silently. With several, prints a numbered list and prompts; user can type
# the index or a literal name. Result is left in REPLY for the caller.
_pick_one() {
  local label="$1"; shift
  local -a candidates=("$@")
  if (( ${#candidates} == 0 )); then
    REPLY=""
    return 1
  fi
  if (( ${#candidates} == 1 )); then
    REPLY="${candidates[1]}"
    return 0
  fi
  printf '%s:\n' "$label"
  local i=1 c
  for c in "${candidates[@]}"; do
    printf '  [%d] %s\n' "$i" "$c"
    (( i++ ))
  done
  printf '\n  → Pick a number or type a name: '
  local pick
  read -r pick || { REPLY=""; return 1; }
  if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#candidates} )); then
    REPLY="${candidates[$pick]}"
  else
    REPLY="$pick"
  fi
  return 0
}

typeset -g _VPNII_ASSUME_YES=0

# Interactive yes/no prompt. Defaults to yes (Enter); non-interactive (closed
# stdin) returns no unless --yes was passed, so unattended runs don't make
# destructive guesses by accident.
_ask() {
  local prompt="$1" answer
  if (( _VPNII_ASSUME_YES )); then
    printf '  → %s [Y/n] yes (--yes)\n' "$prompt"
    return 0
  fi
  printf '  → %s [Y/n] ' "$prompt"
  if ! read -r answer; then
    printf 'no (no tty — pass --yes to auto-accept)\n' >&2
    return 1
  fi
  [[ "${answer:l}" != "n" ]]
}
