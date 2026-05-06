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

# 4. Patch WireGuard configs
printf '\n'
_bold "WireGuard integration"

wg_dir="/etc/wireguard"
wg_configs=()
if [[ -d "$wg_dir" ]]; then
  for f in "$wg_dir"/*.conf(N); do
    [[ -f "$f" ]] && wg_configs+=("$f")
  done
fi

if (( ${#wg_configs} == 0 )); then
  printf 'No WireGuard configs found in %s.\n' "$wg_dir"
  printf 'Run manually: sudo %s/bin/vpnii-wg-setup /etc/wireguard/<name>.conf\n' "$VPNII_HOME"
else
  for conf in "${wg_configs[@]}"; do
    name="${conf:t:r}"
    printf 'Found: %s — patch PostUp/PreDown? [y/N] ' "$conf"
    read -r answer
    if [[ "${answer:l}" == "y" ]]; then
      sudo "$VPNII_HOME/bin/vpnii-wg-setup" "$conf" && \
        printf '  Restart to apply: sudo wg-quick down %s && sudo wg-quick up %s\n' "$name" "$name"
    else
      printf '  Skipped. Run manually: sudo %s/bin/vpnii-wg-setup %s\n' "$VPNII_HOME" "$conf"
    fi
  done
fi

printf '\n'
_green "Done. Open a new shell or: source $ZSHRC"
