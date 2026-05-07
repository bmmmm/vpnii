# Tests for vpnii peers — stubs `wg` to feed deterministic dump output.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

# wg stub: prints a fake `wg show <name> dump`. First line is interface
# (4 fields tab-separated), peer lines have 8 fields.
make_wg_stub() {
  local mode="$1"
  case "$mode" in
    two-peers)
      cat >"${stubdir}/wg" <<EOF
#!/bin/sh
now=\$(date +%s)
hs1=\$((now - 120))   # 2m ago
# peer with handshake
printf 'IFACE_PRIV\tIFACE_PUB\t51820\toff\n'
printf 'AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK=\toff\t1.2.3.4:51820\t10.0.0.0/24\t%s\t1024\t2048\t25\n' "\$hs1"
printf 'XXXXYYYYZZZZ1111222233334444555566667777888=\toff\t(none)\t192.168.0.0/24\t0\t0\t0\t0\n'
EOF
      ;;
    sudo-needed)
      cat >"${stubdir}/wg" <<'EOF'
#!/bin/sh
echo "Unable to access interface: Operation not permitted" >&2
exit 1
EOF
      ;;
  esac
  chmod +x "${stubdir}/wg"
}

export PATH="${stubdir}:${PATH}"
VPNII="${VPNII_HOME}/bin/vpnii"

# 1. Active tunnel + two peers → table renders.
touch "${VPNII_WG_DIR}/HomeLab.name"
make_wg_stub two-peers
output=$("$VPNII" peers HomeLab 2>&1)
assert_eq "$?" "0" "two peers: exits 0"
assert_contains "$output" "HomeLab peers" "two peers: header"
assert_contains "$output" "AAAA…JKKK=" "two peers: pubkey snipped (first 4 + last 5)"
assert_contains "$output" "2m 0s ago" "two peers: handshake age formatted"
assert_contains "$output" "1.2.3.4:51820" "two peers: endpoint"
assert_contains "$output" "never" "two peers: never-handshake shown"
assert_contains "$output" "—" "two peers: missing endpoint shown as dash"

# 2. wg show needs sudo → friendly error.
make_wg_stub sudo-needed
output=$("$VPNII" peers HomeLab 2>&1) || true
assert_contains "$output" "sudo needed" "sudo-needed: hint shown"
assert_contains "$output" "sudo wg show" "sudo-needed: copy-paste command"

# 3. Tunnel not active → die.
rm "${VPNII_WG_DIR}/HomeLab.name"
output=$("$VPNII" peers HomeLab 2>&1) || true
assert_contains "$output" "not active" "inactive: error message"

# 4. Missing argument → usage.
output=$("$VPNII" peers 2>&1) || true
assert_contains "$output" "usage:" "no arg: shows usage"

# 5. Invalid name → reject.
output=$("$VPNII" peers "../foo" 2>&1) || true
assert_contains "$output" "invalid tunnel name" "path traversal rejected"

rm -rf "$stubdir" "$tmpdir"
