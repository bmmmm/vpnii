# Tests for vpnii diag. Pure read-only command — exercises detection,
# binaries, shell integration, and config-hygiene sections without
# touching system state.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)

# Stub ifconfig — no CGNAT IP by default → tailscale inactive.
cat >"${stubdir}/ifconfig" <<'EOF'
#!/bin/sh
echo "lo0: flags=8049"
echo "  inet 127.0.0.1 netmask 0xff000000"
EOF

# Stub wg-quick + wg so the "binaries" section reports them present.
cat >"${stubdir}/wg-quick" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${stubdir}/wg" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${stubdir}"/*

export PATH="${stubdir}:${PATH}"
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=1   # exercise the TS branch
export VPNII_TS_NAME="ts"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
VPNII="${VPNII_HOME}/bin/vpnii"

# 1. Empty state: no tunnels, all sections render.
output=$("$VPNII" diag 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "diag empty: exits 0"
assert_contains "$output" "Active tunnels" "diag: header Active tunnels"
assert_contains "$output" "no active tunnels" "diag empty: 'no active tunnels' message"
assert_contains "$output" "Tailscale" "diag: header Tailscale"
assert_contains "$output" "inactive" "diag empty TS: marks inactive"
assert_contains "$output" "Detection sources" "diag: header Detection sources"
assert_contains "$output" "WireGuard binaries" "diag: header WG binaries"
assert_contains "$output" "wg-quick: ${stubdir}/wg-quick" "diag: wg-quick path detected"
assert_contains "$output" "WireGuard configs" "diag: header WG configs"

# 2. With cache marker: shows up under Active tunnels.
touch "${VPNII_CACHE_DIR}/HomeLab"
output=$("$VPNII" diag 2>&1)
assert_contains "$output" "state file: HomeLab" "diag: cache marker reported"
rm -f "${VPNII_CACHE_DIR}/HomeLab"

# 3. With wg .name marker: shown as wg-quick: <name>.
touch "${VPNII_WG_DIR}/MyTunnel.name"
output=$("$VPNII" diag 2>&1)
assert_contains "$output" "wg-quick: MyTunnel" "diag: wg-quick tunnel reported"
# No wg show stub → handshake unavailable line.
assert_contains "$output" "handshake: unavailable" "diag: handshake unavailable hint"
rm -f "${VPNII_WG_DIR}/MyTunnel.name"

# 4. Tailscale active: ifconfig stub returns CGNAT IP.
cat >"${stubdir}/ifconfig" <<'EOF'
#!/bin/sh
echo "utun9: flags=8051"
echo "  inet 100.64.0.7 netmask 0xffffffff"
EOF
chmod +x "${stubdir}/ifconfig"
output=$("$VPNII" diag 2>&1)
assert_contains "$output" "active: 100.64.0.7" "diag TS active: shows IP"

# 5. VPNII_TS_ENABLED=0 hides the TS section entirely.
output=$(VPNII_TS_ENABLED=0 "$VPNII" diag 2>&1)
[[ "$output" != *"Tailscale"* ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m diag: TS section hidden when disabled\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("diag: TS section hidden when disabled")
  printf '  \033[0;31m✗\033[0m diag: TS section hidden when disabled\n'
}

# 6. Stale backups: warns + suggests vpnii clear.
mkdir -p "${VPNII_CACHE_DIR}/backups"
touch "${VPNII_CACHE_DIR}/backups/old.bak"
output=$("$VPNII" diag 2>&1)
assert_contains "$output" "stale backups" "diag: stale backups warned"
assert_contains "$output" "vpnii clear" "diag: stale backups → vpnii clear hint"
rm -rf "${VPNII_CACHE_DIR}/backups"

rm -rf "$stubdir" "$tmpdir"
