# Tests for tunnel detection — _vpnii_collect_tunnels and vpnii_active_tunnels
# read from VPNII_WG_DIR (.name files, wg-quick) and VPNII_CACHE_DIR (manual
# state files). We point them at fake dirs to test in isolation.

tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0  # suppress ambient tailscale; covered separately
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

source "${VPNII_HOME}/lib/vpnii.zsh"

# Empty: no tunnels detected.
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${#reply}" "0" "empty dirs: no tunnels"

# wg-quick only.
touch "${VPNII_WG_DIR}/homelab.name"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "homelab" "wg-quick .name file detected"

# Cache only.
rm "${VPNII_WG_DIR}/homelab.name"
touch "${VPNII_CACHE_DIR}/passepartout"
typeset -a reply=()
_vpnii_collect_tunnels
assert_eq "${reply[*]}" "passepartout" "cache file detected"

# Both sources, deduplicated when names overlap (wg-quick wins).
touch "${VPNII_WG_DIR}/homelab.name"
touch "${VPNII_CACHE_DIR}/homelab"
typeset -a reply=()
_vpnii_collect_tunnels
# reply order: wg-quick first, then cache (deduped). homelab appears once,
# passepartout still listed from cache.
assert_eq "${#reply}" "2" "dedup: 2 unique tunnels (homelab × 2 → 1)"
assert_contains "${reply[*]}" "homelab" "dedup: homelab present"
assert_contains "${reply[*]}" "passepartout" "dedup: passepartout present"

# vpnii_active_tunnels prints names, exits non-zero when empty.
output=$(vpnii_active_tunnels 2>/dev/null)
assert_contains "$output" "homelab" "vpnii_active_tunnels lists homelab"

rm -rf "${VPNII_WG_DIR}"/* "${VPNII_CACHE_DIR}"/*
output=$(vpnii_active_tunnels 2>/dev/null)
exit_code=$?
assert_eq "$exit_code" "1" "vpnii_active_tunnels exits 1 when empty"

rm -rf "$tmpdir"
