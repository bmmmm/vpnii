# Tests for uninstall.sh. Points ZDOTDIR + XDG_CACHE_HOME at a scratch dir so
# the real ~/.zshrc and cache are never touched. Verifies the portable line
# delete removes exactly the vpnii lines (comment, source, PATH — including the
# em-dash comment) and leaves unrelated lines intact.

tmpdir=$(mktemp -d)
UNINSTALL="${VPNII_HOME}/uninstall.sh"

# A .zshrc with vpnii's lines surrounded by unrelated user content. VPNII_HOME
# is expanded (uninstall.sh derives the same value from its own path); $PATH is
# kept literal. The comment carries the em-dash exactly as install.sh writes it.
fake_zshrc="${tmpdir}/.zshrc"
cat > "$fake_zshrc" <<EOF
# user prompt setup
export FOO=bar

# vpnii — VPN status indicator
source "${VPNII_HOME}/vpnii.plugin.zsh"
export PATH="${VPNII_HOME}/bin:\$PATH"

alias ll='ls -la'
EOF

# A stale cache marker that uninstall should wipe.
mkdir -p "${tmpdir}/cache/vpnii"
touch "${tmpdir}/cache/vpnii/HomeLab"

output=$(ZDOTDIR="$tmpdir" XDG_CACHE_HOME="${tmpdir}/cache" "$UNINSTALL" 2>&1)
exit_code=$?
remaining=$(cat "$fake_zshrc")

assert_eq "$exit_code" "0" "uninstall: exits 0"
assert_contains "$output" "removed source line" "uninstall: reports source removal"
assert_contains "$output" "removed PATH entry" "uninstall: reports PATH removal"

# vpnii lines gone — including the em-dash comment (portable sed must match it).
if [[ "$remaining" != *"vpnii.plugin.zsh"* ]]; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m uninstall: source line removed\n'
else
  (( FAIL++ )); FAILED_TESTS+=("uninstall: source line removed")
  printf '  \033[0;31m✗\033[0m uninstall: source line removed\n'
fi
if [[ "$remaining" != *"# vpnii — VPN status indicator"* ]]; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m uninstall: em-dash comment removed\n'
else
  (( FAIL++ )); FAILED_TESTS+=("uninstall: em-dash comment removed")
  printf '  \033[0;31m✗\033[0m uninstall: em-dash comment removed\n'
fi
if [[ "$remaining" != *"${VPNII_HOME}/bin"* ]]; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m uninstall: PATH entry removed\n'
else
  (( FAIL++ )); FAILED_TESTS+=("uninstall: PATH entry removed")
  printf '  \033[0;31m✗\033[0m uninstall: PATH entry removed\n'
fi

# Unrelated lines survive — the delete is surgical, not a blanket wipe.
assert_contains "$remaining" "export FOO=bar" "uninstall: unrelated export preserved"
assert_contains "$remaining" "alias ll='ls -la'" "uninstall: unrelated alias preserved"

# Cache marker wiped.
if [[ ! -e "${tmpdir}/cache/vpnii/HomeLab" ]]; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m uninstall: stale cache marker cleared\n'
else
  (( FAIL++ )); FAILED_TESTS+=("uninstall: stale cache marker cleared")
  printf '  \033[0;31m✗\033[0m uninstall: stale cache marker cleared\n'
fi

# Idempotent: a second run finds nothing to do and still exits 0.
output=$(ZDOTDIR="$tmpdir" XDG_CACHE_HOME="${tmpdir}/cache" "$UNINSTALL" 2>&1)
assert_eq "$?" "0" "uninstall: second run idempotent (exits 0)"
assert_contains "$output" "already removed" "uninstall: second run notes nothing to do"

rm -rf "$tmpdir"
