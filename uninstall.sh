#!/usr/bin/env zsh
# vpnii uninstall — removes vpnii from ~/.zshrc and PATH

set -euo pipefail

VPNII_HOME="${0:A:h}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ZSHRC_REAL="${ZSHRC:A}"
VPNII_LINK="/usr/local/bin/vpnii"
LEGACY_LINK="/usr/local/bin/vpnii-state"
VPNII_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vpnii"

_green()  { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m→ %s\033[0m\n' "$*"; }
_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

# Portable in-place line delete. BSD sed wants `-i ''`, GNU sed rejects the
# empty arg — so route through a temp file + copy-back, which behaves the same
# on both and preserves the target's inode and permissions. Args after the
# file are passed straight to sed (e.g. one or more `-e <expr>`).
_sed_delete() {
  local file="$1"; shift
  local tmp
  tmp=$(mktemp)
  if ! sed "$@" "$file" > "$tmp"; then
    rm -f "$tmp"
    _yellow "sed failed on $file — left unchanged"
    return 1
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

_bold "vpnii uninstaller"
printf '\n'

# 1. Remove source line + comment from .zshrc
if grep -qF "vpnii.plugin.zsh" "$ZSHRC_REAL" 2>/dev/null; then
  _sed_delete "$ZSHRC_REAL" \
    -e '/^# vpnii — VPN status indicator$/d' \
    -e '/^source.*vpnii\.plugin\.zsh/d'
  _green "removed source line from $ZSHRC"
else
  _yellow "source line not found in $ZSHRC (already removed?)"
fi

# 2. Remove PATH line from .zshrc
if grep -qF "${VPNII_HOME}/bin" "$ZSHRC_REAL" 2>/dev/null; then
  _sed_delete "$ZSHRC_REAL" -e "\|${VPNII_HOME}/bin|d"
  _green "removed PATH entry from $ZSHRC"
else
  _yellow "PATH entry not found in $ZSHRC (already removed?)"
fi

# 3. Remove symlinks pointing at this install
for link in "$VPNII_LINK" "$LEGACY_LINK"; do
  if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "${VPNII_HOME}/bin/"* ]]; then
    rm -f "$link"
    _green "removed $link"
  fi
done

# 4. Clear state cache
if [[ -d "$VPNII_CACHE_DIR" ]]; then
  rm -f "${VPNII_CACHE_DIR}/"*(N.)
  _green "cleared state cache: $VPNII_CACHE_DIR"
fi

printf '\n'
_green "Done. Open a new shell or: source $ZSHRC"
printf '\nNote: WireGuard configs are unchanged.\n'
printf 'To clean stale vpnii hooks: %s/bin/vpnii setup /etc/wireguard/<name>.conf\n' "$VPNII_HOME"
