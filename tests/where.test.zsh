# Tests for vpnii where. Stubs netstat (default route) and creates fake
# wg-quick configs in /etc/wireguard via VPNII_WG_CONF_DIR override...
# actually the path /etc/wireguard is hardcoded. We only test the parts
# we can: tailscale-on path and the default-route formatting.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

# Stub netstat to return a fixed default-route line.
cat >"${stubdir}/netstat" <<'EOF'
#!/bin/sh
case "$STUB_DEFAULT_VIA" in
  utun)  echo "Routing tables"; echo ""; echo "Internet:"; echo "default            100.64.0.1         UGScg                utun9 Expire" ;;
  en0)   echo "Routing tables"; echo ""; echo "Internet:"; echo "default            192.168.1.1        UGScg                  en0 Expire" ;;
  none)  echo "Routing tables"; echo ""; echo "Internet:" ;;
  *)     echo "Routing tables"; echo ""; echo "Internet:"; echo "default            192.168.1.1        UGScg                  en0 Expire" ;;
esac
EOF
chmod +x "${stubdir}/netstat"

# Stub ifconfig so _vpnii_tailscale_active can be controlled.
cat >"${stubdir}/ifconfig" <<'EOF'
#!/bin/sh
case "$STUB_TS" in
  on)  echo "utun9: flags=8051"; echo "	inet 100.64.0.3 netmask 0xffffffff" ;;
  off) echo "lo0: flags=8049"; echo "	inet 127.0.0.1" ;;
esac
EOF
chmod +x "${stubdir}/ifconfig"

export PATH="${stubdir}:${PATH}"
VPNII="${VPNII_HOME}/bin/vpnii"

# 1. No tunnels at all → "no active tunnels" + default route line.
output=$(STUB_DEFAULT_VIA=en0 STUB_TS=off VPNII_TS_ENABLED=0 "$VPNII" where 2>&1)
assert_contains "$output" "no active tunnels" "empty: states no active"
assert_contains "$output" "default v4" "empty: still shows default route"
assert_contains "$output" "192.168.1.1" "empty: shows gateway"
assert_contains "$output" "via en0" "empty: shows interface"
assert_contains "$output" "(direct, no VPN)" "empty: tags as direct"

# 2. Default route via utun (likely VPN-routed) → tags accordingly.
output=$(STUB_DEFAULT_VIA=utun "$VPNII" where 2>&1)
assert_contains "$output" "via utun9" "utun route: shows utun"
assert_contains "$output" "likely VPN-routed" "utun route: tagged as VPN"

# 3. Tailscale active → mesh entry shown.
output=$(STUB_DEFAULT_VIA=en0 STUB_TS=on VPNII_TS_ENABLED=1 "$VPNII" where 2>&1)
assert_contains "$output" "ts" "TS on: tailscale entry"
assert_contains "$output" "100.64.0.0/10" "TS on: shows CGNAT range"
assert_contains "$output" "(mesh)" "TS on: tagged mesh"

# 4. Cache marker present → listed as cache marker.
touch "${VPNII_CACHE_DIR}/passepartout"
output=$(STUB_DEFAULT_VIA=en0 "$VPNII" where 2>&1)
assert_contains "$output" "passepartout" "cache: name shown"
assert_contains "$output" "external client" "cache: tagged as managed externally"

rm -rf "$stubdir" "$tmpdir"
