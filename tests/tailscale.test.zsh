# Tests for tailscale detection. Stubs ifconfig via PATH so tests don't
# depend on the host's actual network state. _vpnii_tailscale_active is
# a yes/no check on CGNAT IP presence (100.64.0.0/10).

stubdir=$(mktemp -d)

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

export PATH="${stubdir}:${PATH}"
source "${VPNII_HOME}/lib/vpnii.zsh"

# 1. No tailnet IP → inactive.
make_ifconfig_stub "lo0: flags=8049
	inet 127.0.0.1 netmask 0xff000000
en0: flags=8863
	inet 192.168.1.42 netmask 0xffffff00"
_vpnii_tailscale_active && active=1 || active=0
assert_eq "$active" "0" "no tailnet IP: inactive"

# 2. CGNAT lower bound (100.64.x.x) → active.
make_ifconfig_stub "utun9: flags=8051
	inet 100.64.0.3 --> 100.64.0.3 netmask 0xffffffff"
_vpnii_tailscale_active && active=1 || active=0
assert_eq "$active" "1" "100.64.x.x: active"

# 3. CGNAT upper bound (100.127.x.x) → still active.
make_ifconfig_stub "utun9: flags=8051
	inet 100.127.255.254 netmask 0xffffffff"
_vpnii_tailscale_active && active=1 || active=0
assert_eq "$active" "1" "100.127.x.x: active"

# 4. Just outside CGNAT → inactive (100.63 below, 100.128 above).
make_ifconfig_stub "utun9: flags=8051
	inet 100.63.0.1 netmask 0xffffffff"
_vpnii_tailscale_active && active=1 || active=0
assert_eq "$active" "0" "100.63.x.x: outside CGNAT"

make_ifconfig_stub "utun9: flags=8051
	inet 100.128.0.1 netmask 0xffffffff"
_vpnii_tailscale_active && active=1 || active=0
assert_eq "$active" "0" "100.128.x.x: outside CGNAT"

# 5. Account cache returns its stored value across calls.
_vpnii_ts_account_cache="cached-user"
result=$(_vpnii_tailscale_account)
assert_eq "$result" "cached-user" "account cache: returns stored value"
_vpnii_ts_account_cache=""

# _vpnii_collect_tunnels no longer mixes TS in — it stays pure wg-quick + cache.
# This is the contract change we just made; pin it.
tmpdir=$(mktemp -d)
VPNII_WG_DIR="${tmpdir}/wg"
VPNII_CACHE_DIR="${tmpdir}/cache"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
make_ifconfig_stub "utun9: flags=8051
	inet 100.64.0.3 netmask 0xffffffff"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${#reply}" "0" "collect_tunnels excludes TS even when active"

touch "${VPNII_WG_DIR}/homelab.name"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "homelab" "collect_tunnels: only wg-quick tunnel"

rm -rf "$stubdir" "$tmpdir"
