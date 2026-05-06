#!/usr/bin/env zsh
# vpnii install — adds vpnii to ~/.zshrc and optionally puts vpnii-state on PATH

set -euo pipefail

VPNII_HOME="${0:A:h}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE="source \"${VPNII_HOME}/vpnii.plugin.zsh\""
BIN_TARGET="/usr/local/bin/vpnii-state"
BIN_SOURCE="${VPNII_HOME}/bin/vpnii-state"

_green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
_bold() { printf '\033[1m%s\033[0m\n' "$*"; }

_bold "vpnii installer"
printf '\n'

# 1. Add source line to .zshrc
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
  _green "✓ already in $ZSHRC"
else
  printf '\n# vpnii — VPN status indicator\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  _green "✓ added to $ZSHRC"
fi

# 2. Link vpnii-state to PATH
if [[ -w "/usr/local/bin" ]]; then
  ln -sf "$BIN_SOURCE" "$BIN_TARGET"
  _green "✓ vpnii-state linked to $BIN_TARGET"
else
  PATH_LINE="export PATH=\"${VPNII_HOME}/bin:\$PATH\""
  if ! grep -qF "$PATH_LINE" "$ZSHRC" 2>/dev/null; then
    printf '%s\n' "$PATH_LINE" >> "$ZSHRC"
  fi
  _yellow "→ /usr/local/bin not writable — added ${VPNII_HOME}/bin to PATH in $ZSHRC"
fi

# 3. Create cache dir
VPNII_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/vpnii"
mkdir -p "$VPNII_CACHE_DIR"
_green "✓ cache dir: $VPNII_CACHE_DIR"

# 4. Print wg-quick snippet
printf '\n'
_bold "wg-quick integration"
printf 'Add these lines to your WireGuard interface config ([Interface] section):\n\n'
printf '  PostUp  = su -c '"'"'vpnii-state up %%i'"'"' - %s\n' "$USER"
printf '  PreDown = su -c '"'"'vpnii-state down %%i'"'"' - %s\n' "$USER"
printf '\n'
printf '%%i is replaced by wg-quick with the interface name (e.g. HomeLab).\n'
printf 'Running via su ensures state files are owned by your user, not root.\n'
printf '\n'
_green "Done. Open a new shell or: source $ZSHRC"
