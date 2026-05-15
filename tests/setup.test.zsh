# Tests for vpnii setup. The maintenance branch is fully testable with
# explicit config paths (skips the auto-detect /etc/wireguard scan).
# The wizard branch is interactive — out of scope for unit tests.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)

# `sudo` is invoked iff /etc/wireguard isn't owned by $USER and the user
# accepts the chown prompt. With explicit-arg setup + closed stdin we
# never hit it, but stub anyway so a stray invocation can't escape.
cat >"${stubdir}/sudo" <<'EOF'
#!/bin/sh
[ "$1" = "-n" ] && shift
exec "$@"
EOF
chmod +x "${stubdir}/sudo"

export PATH="${stubdir}:${PATH}"
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
VPNII="${VPNII_HOME}/bin/vpnii"

VALID_PRIV='AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK='
VALID_PUB='LLLLMMMMNNNNOOOOPPPPQQQQRRRRSSSSTTTTUUUUVVV='

clean_conf="${tmpdir}/clean.conf"
cat >"$clean_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV

[Peer]
PublicKey = $VALID_PUB
AllowedIPs = 0.0.0.0/0
EOF

hooked_conf="${tmpdir}/hooked.conf"
cat >"$hooked_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV
PostUp = nft -f /etc/nft.rules && sudo -u bma /usr/local/bin/vpnii up hooked
PreDown = nft flush ruleset && sudo -u bma /usr/local/bin/vpnii down hooked

[Peer]
PublicKey = $VALID_PUB
AllowedIPs = 10.0.0.0/24
EOF

# 1. Unknown flag → die.
output=$("$VPNII" setup --bogus 2>&1) || true
assert_contains "$output" "unknown setup flag" "setup: rejects unknown flag"

# 2. Maintenance on a clean config: no-hooks ok message.
output=$("$VPNII" setup "$clean_conf" 2>&1 < /dev/null)
exit_code=$?
assert_eq "$exit_code" "0" "setup clean: exits 0"
assert_contains "$output" "1 config(s) to check" "setup: counts configs"
assert_contains "$output" "no stale vpnii hooks" "setup clean: confirms hooks-free"

# 3. Maintenance on a hooked config without -y (stdin closed): warns + skips strip.
hooked_copy="${tmpdir}/hooked-no-y.conf"
cp "$hooked_conf" "$hooked_copy"
output=$("$VPNII" setup "$hooked_copy" 2>&1 < /dev/null)
assert_contains "$output" "stale vpnii hooks found" "setup hooked no-y: detects hooks"
# The original hook lines should still be intact since user said no.
if grep -qF 'vpnii up hooked' "$hooked_copy"; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m setup no-y: hooks left in place\n'
else
  (( FAIL++ )); FAILED_TESTS+=("setup no-y: hooks left in place")
  printf '  \033[0;31m✗\033[0m setup no-y: hooks left in place\n'
fi

# 4. Maintenance on a hooked config with -y: strips hooks.
hooked_y="${tmpdir}/hooked-y.conf"
cp "$hooked_conf" "$hooked_y"
output=$("$VPNII" setup -y "$hooked_y" 2>&1 < /dev/null)
exit_code=$?
assert_eq "$exit_code" "0" "setup -y hooked: exits 0"
assert_contains "$output" "stripped" "setup -y: confirms strip"
if grep -qE 'vpnii(-state)?' "$hooked_y" 2>/dev/null; then
  (( FAIL++ )); FAILED_TESTS+=("setup -y: hooks actually removed")
  printf '  \033[0;31m✗\033[0m setup -y: hooks actually removed\n'
else
  (( PASS++ )); printf '  \033[0;32m✓\033[0m setup -y: hooks actually removed\n'
fi

# 5. Multiple configs in one call.
output=$("$VPNII" setup "$clean_conf" "$hooked_y" 2>&1 < /dev/null)
assert_contains "$output" "2 config(s) to check" "setup multi: counts both"
assert_contains "$output" "clean" "setup multi: processes clean"

# 6. Missing config → warned, skipped, doesn't fail.
output=$("$VPNII" setup "$clean_conf" /no/such/file.conf 2>&1 < /dev/null)
exit_code=$?
assert_eq "$exit_code" "0" "setup missing-among-others: still exits 0"
assert_contains "$output" "skipping" "setup missing: warns + skips"

rm -rf "$stubdir" "$tmpdir"
