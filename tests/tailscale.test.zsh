# Tests for tailscale detection — stubs ifconfig via PATH so the test
# matrix doesn't depend on the host's actual network state.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

make_ifconfig_stub() {
  local content="$1"
  cat >"${stubdir}/ifconfig" <<EOF
#!/bin/sh
cat <<'STUBDATA'
${content}
STUBDATA
EOF
  chmod +x "${stubdir}/ifconfig"
}

# Source after stubbing PATH so subsequent ifconfig calls hit the stub.
export PATH="${stubdir}:${PATH}"
source "${VPNII_HOME}/lib/vpnii.zsh"

# 1. No tailscale IP → not detected.
make_ifconfig_stub "lo0: flags=8049
	inet 127.0.0.1 netmask 0xff000000
en0: flags=8863
	inet 192.168.1.42 netmask 0xffffff00"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "" "no tailnet IP: empty reply"

# 2. CGNAT IP present → detected with default name.
make_ifconfig_stub "utun9: flags=8051
	inet 100.64.0.3 --> 100.64.0.3 netmask 0xffffffff"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "tailscale" "100.64.0.3: detected as 'tailscale'"

# 3. Edge of CGNAT range — 100.127.x.x (upper bound).
make_ifconfig_stub "utun9: flags=8051
	inet 100.127.255.254 netmask 0xffffffff"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "tailscale" "100.127.x.x: still in CGNAT range"

# 4. Just outside CGNAT — 100.63.x.x and 100.128.x.x must NOT trigger.
make_ifconfig_stub "utun9: flags=8051
	inet 100.63.0.1 netmask 0xffffffff"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "" "100.63.x.x: outside CGNAT, ignored"

make_ifconfig_stub "utun9: flags=8051
	inet 100.128.0.1 netmask 0xffffffff"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "" "100.128.x.x: outside CGNAT, ignored"

# 5. Disable knob — VPNII_TS_ENABLED=0 suppresses detection even when active.
make_ifconfig_stub "utun9: flags=8051
	inet 100.64.0.3 netmask 0xffffffff"
VPNII_TS_ENABLED=0
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "" "VPNII_TS_ENABLED=0: detection disabled"
VPNII_TS_ENABLED=1

# 6. Custom name via VPNII_TS_NAME.
VPNII_TS_NAME="ts"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "ts" "VPNII_TS_NAME=ts: custom label used"
VPNII_TS_NAME="tailscale"

# 7. Coexistence with wg-quick tunnel — both appear.
touch "${VPNII_WG_DIR}/homelab.name"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "homelab tailscale" "wg+ts: both listed, wg first"

# 8. Dedup: cache file already named "tailscale" → don't double up.
rm "${VPNII_WG_DIR}/homelab.name"
touch "${VPNII_CACHE_DIR}/tailscale"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${#reply}" "1" "dedup: tailscale in both cache and detection → 1"
assert_eq "${reply[*]}" "tailscale" "dedup: name preserved"

rm -rf "$stubdir" "$tmpdir"
