# Tests for vpnii dns. PATH-stubs route / networksetup / dig / scutil /
# sudo / killall so we never touch the live macOS DNS state.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
calls="${tmpdir}/calls.log"
: > "$calls"

# Stubs that record their invocation to $calls so we can assert on them.
cat >"${stubdir}/route" <<EOF
#!/bin/sh
echo "ROUTE \$*" >> "$calls"
# Mode is set via /tmp file: 'ok' returns en0, 'noroute' returns nothing.
mode=\$(cat "${tmpdir}/route_mode" 2>/dev/null || echo ok)
if [ "\$mode" = "noroute" ]; then
  exit 1
fi
echo "   interface: en0"
EOF

cat >"${stubdir}/networksetup" <<EOF
#!/bin/sh
echo "NETWORKSETUP \$*" >> "$calls"
case "\$1" in
  -listallhardwareports)
    cat <<'PORTS'
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: aa:bb:cc:dd:ee:ff

Hardware Port: USB 10/100/1000 LAN
Device: en7
Ethernet Address: 11:22:33:44:55:66
PORTS
    ;;
  -getdnsservers)
    mode=\$(cat "${tmpdir}/dns_mode" 2>/dev/null || echo override)
    if [ "\$mode" = "dhcp" ]; then
      echo "There aren't any DNS Servers set on Wi-Fi."
    else
      echo "192.168.189.4"
      echo "1.1.1.1"
    fi
    ;;
  -setdnsservers)
    : # no-op, just record the call above
    ;;
  -listnetworkserviceorder)
    cat <<'ORDER'
(1) Wi-Fi
(Hardware Port: Wi-Fi, Device: en0)

(2) USB 10/100/1000 LAN
(Hardware Port: USB 10/100/1000 LAN, Device: en7)
ORDER
    ;;
esac
EOF

cat >"${stubdir}/dig" <<'EOF'
#!/bin/sh
# Last positional after flags is the domain; second-to-last with @ prefix is server.
domain=""
server="system"
for a in "$@"; do
  case "$a" in
    @*) server="${a#@}" ;;
    +*|-*) ;;
    *) domain="$a" ;;
  esac
done
mode=$(cat "DIG_MODE_FILE" 2>/dev/null || echo blocked)
case "$mode" in
  blocked)    echo "0.0.0.0" ;;          # both resolvers block
  bypass)
    if [ "$server" = "system" ]; then echo "1.2.3.4"; else echo "0.0.0.0"; fi ;;
  unreach)
    # Pi-hole unreachable: real dig exits 9 (no reply) for the @pihole query,
    # while the system resolver still answers. The non-zero exit is the whole
    # point — it must not abort `vpnii dns home` under `set -euo pipefail`.
    if [ "$server" = "system" ]; then echo "5.6.7.8"; else exit 9; fi ;;
esac
EOF
sed -i.bak "s|DIG_MODE_FILE|${tmpdir}/dig_mode|" "${stubdir}/dig" && rm -f "${stubdir}/dig.bak"

cat >"${stubdir}/scutil" <<'EOF'
#!/bin/sh
cat <<'OUT'
resolver #1
  nameserver[0] : 192.168.189.4
  search domain[0] : home
resolver #2
  nameserver[0] : 1.1.1.1
OUT
EOF

cat >"${stubdir}/sudo" <<'EOF'
#!/bin/sh
# Recognise -n; either way succeed.
[ "$1" = "-n" ] && shift
exec "$@"
EOF

cat >"${stubdir}/killall" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod +x "${stubdir}"/*

export PATH="${stubdir}:${PATH}"
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
VPNII="${VPNII_HOME}/bin/vpnii"

# --- service detection ---

# 1. dns show: detection picks Wi-Fi from default route + hardware port pairing.
echo blocked > "${tmpdir}/dig_mode"
echo override > "${tmpdir}/dns_mode"
echo ok > "${tmpdir}/route_mode"
output=$("$VPNII" dns show 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "dns show: exits 0"
assert_contains "$output" "Active service: Wi-Fi" "dns show: detected Wi-Fi from en0"
assert_contains "$output" "Manual override:" "dns show: shows override block"

# 2. dns show with VPNII_DNS_SERVICE: skips detection, uses override.
output=$(VPNII_DNS_SERVICE="USB 10/100/1000 LAN" "$VPNII" dns show 2>&1)
assert_contains "$output" "Active service: USB 10/100/1000 LAN" "dns show: env override honored"

# 3. dns show with no default route: actionable error.
echo noroute > "${tmpdir}/route_mode"
output=$("$VPNII" dns show 2>&1) || true
assert_contains "$output" "no default route" "dns show: no-route error visible"
assert_contains "$output" "VPNII_DNS_SERVICE" "dns show: error hints env override"
echo ok > "${tmpdir}/route_mode"

# 4. dns show DHCP-default branch.
echo dhcp > "${tmpdir}/dns_mode"
output=$("$VPNII" dns show 2>&1)
assert_contains "$output" "DHCP-default" "dns show: DHCP-default detected"
echo override > "${tmpdir}/dns_mode"

# --- mode application ---

# 5. dns home: applies pihole + 1.1.1.1, runs adblock test.
: > "$calls"
output=$("$VPNII" dns home 2>&1)
assert_contains "$output" "Setting home DNS" "dns home: header"
calls_content=$(cat "$calls")
assert_contains "$calls_content" "NETWORKSETUP -setdnsservers Wi-Fi 192.168.189.4 1.1.1.1" \
  "dns home: networksetup invoked with default Pi-hole IP"
assert_contains "$output" "Adblock active" "dns home: adblock probe (blocked mode)"

# 6. dns home honors VPNII_DNS_PIHOLE.
: > "$calls"
output=$(VPNII_DNS_PIHOLE=10.0.0.53 "$VPNII" dns home 2>&1)
calls_content=$(cat "$calls")
assert_contains "$calls_content" "NETWORKSETUP -setdnsservers Wi-Fi 10.0.0.53 1.1.1.1" \
  "dns home: VPNII_DNS_PIHOLE override applied"

# 7. dns public.
: > "$calls"
output=$("$VPNII" dns public 2>&1)
calls_content=$(cat "$calls")
assert_contains "$calls_content" "NETWORKSETUP -setdnsservers Wi-Fi 1.1.1.1 1.0.0.1" \
  "dns public: 1.1.1.1 + 1.0.0.1"

# 8. dns dhcp: clears override.
: > "$calls"
output=$("$VPNII" dns dhcp 2>&1)
calls_content=$(cat "$calls")
assert_contains "$calls_content" "NETWORKSETUP -setdnsservers Wi-Fi empty" \
  "dns dhcp: clears via 'empty'"

# 9. dns services: prints all networksetup services.
output=$("$VPNII" dns services 2>&1)
assert_contains "$output" "Wi-Fi" "dns services: lists Wi-Fi"
assert_contains "$output" "USB 10/100/1000 LAN" "dns services: lists USB"

# --- adblock probe matrix ---

# 10. Bypass mode: Pi-hole filters but system DNS doesn't.
echo bypass > "${tmpdir}/dig_mode"
output=$("$VPNII" dns home 2>&1)
assert_contains "$output" "macOS bypasses it" "adblock: bypass detected"
echo blocked > "${tmpdir}/dig_mode"

# 11. Pi-hole unreachable: real dig exits non-zero for the @pihole probe.
# That must NOT abort `dns home` under set -e — otherwise the "unreachable"
# branch is dead code and the cache flush never runs. The exit-0 assertion
# is the actual regression guard.
echo unreach > "${tmpdir}/dig_mode"
output=$("$VPNII" dns home 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "adblock unreachable: command completes (no set -e abort)"
assert_contains "$output" "Pi-hole" "adblock: unreachable warns"
assert_contains "$output" "unreachable" "adblock: unreachable named"

# --- usage ---

# 12. Unknown mode → actionable error.
output=$("$VPNII" dns frobnicate 2>&1) || true
assert_contains "$output" "unknown dns mode" "dns: rejects unknown mode"

rm -rf "$stubdir" "$tmpdir"
