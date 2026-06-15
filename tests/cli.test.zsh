# CLI smoke tests — invoke bin/vpnii in isolation with fake state dirs to
# avoid touching the real ~/.cache/vpnii or /var/run/wireguard.

tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0  # suppress ambient tailscale; covered separately
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

VPNII="${VPNII_HOME}/bin/vpnii"

# Explicit `vpnii help` is intentional input — exits 0, prints banner.
output=$("$VPNII" help 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "help: exits 0 when invoked explicitly"
assert_contains "$output" "usage: vpnii" "help: prints usage banner"
assert_contains "$output" "up [<tunnel>" "help: lists up command"

# Bare `vpnii` (no args) is a usage error — exits 1.
"$VPNII" >/dev/null 2>&1
exit_code=$?
assert_eq "$exit_code" "1" "no-arg: exits 1 (usage error)"

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

# up with a brand-new name (no .conf, no existing marker) must confirm before
# creating a cache marker — a typo otherwise spawns a phantom "active" tunnel
# (issue #3). </dev/null forces _ask's no-tty path → returns no → aborts.
output=$("$VPNII" up zz-typo-nonexistent </dev/null 2>&1) || true
assert_contains "$output" "no wg-quick config" "up new name: warns there is no config"
if [[ ! -e "${VPNII_CACHE_DIR}/zz-typo-nonexistent" ]]; then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m up new name: no phantom marker created\n'
else
  (( FAIL++ )); FAILED_TESTS+=("up new name: no phantom marker created")
  printf '  \033[0;31m✗\033[0m up new name: no phantom marker created\n'
fi

# Re-marking an EXISTING cache tunnel stays silent (Passepartout flow intact).
touch "${VPNII_CACHE_DIR}/known-ext"
output=$("$VPNII" up known-ext </dev/null 2>&1)
assert_contains "$output" "marked active in cache: known-ext" "up existing marker: silent re-mark"

rm -rf "$tmpdir"
