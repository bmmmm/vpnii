# Tests for vpnii toggle / reconnect.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0   # neutralise ambient tailscale; covered separately
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

# Stub `sudo` so wg-quick doesn't actually need root.
cat >"${stubdir}/sudo" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
chmod +x "${stubdir}/sudo"

# Stub `wg-quick` — pretend it always works, no real network.
cat >"${stubdir}/wg-quick" <<EOF
#!/bin/sh
case "\$1" in
  up)   touch "$VPNII_WG_DIR/\$2.name" ;;
  down) rm -f "$VPNII_WG_DIR/\$2.name" ;;
esac
EOF
chmod +x "${stubdir}/wg-quick"

export PATH="${stubdir}:${PATH}"
VPNII="${VPNII_HOME}/bin/vpnii"

# 1. Toggle starting from inactive (cache only — no /etc/wireguard config).
output=$("$VPNII" toggle xx-toggle-test-xx 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "toggle inactive: exits 0"
[[ -f "${VPNII_CACHE_DIR}/xx-toggle-test-xx" ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m toggle inactive: cache marker created\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("toggle inactive: cache marker created")
  printf '  \033[0;31m✗\033[0m toggle inactive: cache marker created\n'
}

# 2. Toggle from active → goes inactive.
output=$("$VPNII" toggle xx-toggle-test-xx 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "toggle active: exits 0"
[[ ! -f "${VPNII_CACHE_DIR}/xx-toggle-test-xx" ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m toggle active: cache marker removed\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("toggle active: cache marker removed")
  printf '  \033[0;31m✗\033[0m toggle active: cache marker removed\n'
}

# 3. Reconnect a cache-only tunnel: down (rm cache), then up (touch cache).
touch "${VPNII_CACHE_DIR}/xx-toggle-test-xx"
output=$("$VPNII" reconnect xx-toggle-test-xx 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "reconnect: exits 0"
[[ -f "${VPNII_CACHE_DIR}/xx-toggle-test-xx" ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m reconnect: cache marker present after\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("reconnect: cache marker present after")
  printf '  \033[0;31m✗\033[0m reconnect: cache marker present after\n'
}

# 4. Toggle without name → usage error.
output=$("$VPNII" toggle 2>&1) || true
assert_contains "$output" "usage:" "toggle no-arg: shows usage"

# 5. Reconnect without name → usage error.
output=$("$VPNII" reconnect 2>&1) || true
assert_contains "$output" "usage:" "reconnect no-arg: shows usage"

# 6. Toggle invalid name (path traversal) → die.
output=$("$VPNII" toggle "../etc/passwd" 2>&1) || true
assert_contains "$output" "invalid tunnel name" "toggle: rejects path traversal"

rm -rf "$stubdir" "$tmpdir"
