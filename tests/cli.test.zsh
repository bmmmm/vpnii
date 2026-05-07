# CLI smoke tests — invoke bin/vpnii in isolation with fake state dirs to
# avoid touching the real ~/.cache/vpnii or /var/run/wireguard.

tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

VPNII="${VPNII_HOME}/bin/vpnii"

# `vpnii help` exits 1 (it's the usage path) but prints the banner.
output=$("$VPNII" help 2>&1) || true
assert_contains "$output" "usage: vpnii" "help: prints usage banner"
assert_contains "$output" "up [<tunnel>]" "help: lists up command"

# Unknown command dies with a hint.
output=$("$VPNII" frobnicate 2>&1) || true
assert_contains "$output" "unknown command" "unknown cmd: error message"

# status with empty state.
output=$("$VPNII" status 2>&1)
assert_eq "$output" "no active tunnels" "status: empty state"

# list with empty state — exits 0 (no-tunnels is not an error), no output.
output=$("$VPNII" list 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "list: exits 0 when empty"
assert_eq "$output" "" "list: empty output"

# status with one cache tunnel.
touch "${VPNII_CACHE_DIR}/homelab"
output=$("$VPNII" status 2>&1)
assert_contains "$output" "homelab" "status: shows cache tunnel"

# list with one cache tunnel.
output=$("$VPNII" list 2>&1)
assert_eq "$output" "homelab" "list: prints cache tunnel"

# clear nukes manual cache.
"$VPNII" clear &>/dev/null
output=$("$VPNII" status 2>&1)
assert_eq "$output" "no active tunnels" "clear: cache wiped"

# Invalid tunnel names rejected.
output=$("$VPNII" up "../etc/passwd" 2>&1) || true
assert_contains "$output" "invalid tunnel name" "up: rejects path traversal"

output=$("$VPNII" up ".hidden" 2>&1) || true
assert_contains "$output" "invalid tunnel name" "up: rejects leading dot"

rm -rf "$tmpdir"
