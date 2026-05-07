#!/usr/bin/env zsh
# vpnii install — adds vpnii to ~/.zshrc and puts the `vpnii` CLI on PATH

set -euo pipefail

VPNII_HOME="${0:A:h}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE="source \"${VPNII_HOME}/vpnii.plugin.zsh\""
BIN_TARGET="/usr/local/bin/vpnii"
BIN_SOURCE="${VPNII_HOME}/bin/vpnii"
LEGACY_LINK="/usr/local/bin/vpnii-state"

_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

_bold "vpnii installer"
printf '\n'

# 1. Add source line to .zshrc
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
  _green "✓ already in $ZSHRC"
else
  printf '\n# vpnii — VPN status indicator\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  _green "✓ added to $ZSHRC"
fi

# 2. Link `vpnii` to PATH
if [[ -w "/usr/local/bin" ]]; then
  ln -sf "$BIN_SOURCE" "$BIN_TARGET"
  _green "✓ vpnii linked to $BIN_TARGET"
  # Drop legacy vpnii-state symlink if present (the in-repo shim still works
  # via absolute path for legacy wireguard hooks; PATH access goes through `vpnii`).
  if [[ -L "$LEGACY_LINK" ]]; then
    rm -f "$LEGACY_LINK"
    _yellow "→ removed legacy symlink $LEGACY_LINK (use 'vpnii' instead of 'vpnii-state')"
  fi
else
  PATH_LINE="export PATH=\"${VPNII_HOME}/bin:\$PATH\""
  if ! grep -qF "$PATH_LINE" "$ZSHRC" 2>/dev/null; then
    printf '%s\n' "$PATH_LINE" >> "$ZSHRC"
  fi
  _yellow "→ /usr/local/bin not writable — added ${VPNII_HOME}/bin to PATH in $ZSHRC"
fi

printf '\n'
_green "Done. Open a new shell or: source $ZSHRC"

# 3. Interactive wireguard config setup — chown to current user + strip
# stale hooks. Skipped silently if no configs exist or stdin isn't a tty.
configs=( /etc/wireguard/*.conf(N.) )
if (( ${#configs} > 0 )) && [[ -t 0 ]]; then
  printf '\n'
  _bold "WireGuard configs"
  printf 'Found %d config(s) in /etc/wireguard.\n' "${#configs}"
  printf 'vpnii setup takes ownership (so you can edit without sudo) and strips\n'
  printf 'any legacy vpnii hooks left over from older installs.\n\n'
  printf 'Run interactive setup now? [Y/n] '
  read -r answer
  if [[ "${answer:l}" != "n" ]]; then
    "$BIN_SOURCE" setup
  fi
fi

printf '\n'
printf 'wg-quick tunnels are detected automatically — no config changes needed.\n'
printf 'For other VPN tools: vpnii up <name> / vpnii down <name>\n'
