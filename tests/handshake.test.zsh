# Tests for handshake-age helpers. _vpnii_handshake_age parses
# `wg show <name> latest-handshakes`; we stub wg via PATH.

stubdir=$(mktemp -d)

make_wg_stub() {
  local mode="$1"
  case "$mode" in
    silent)
      cat >"${stubdir}/wg" <<'EOF'
#!/bin/sh
exit 0
EOF
      ;;
    one-peer-fresh)
      # Latest handshake = 30 seconds ago.
      cat >"${stubdir}/wg" <<EOF
#!/bin/sh
ts=\$((\$(date +%s) - 30))
printf 'abc123peerkey\t%s\n' "\$ts"
EOF
      ;;
    multi-peer-pick-max)
      # Two peers; the older is at 1h ago, the latest at 2m ago.
      cat >"${stubdir}/wg" <<EOF
#!/bin/sh
old=\$((\$(date +%s) - 3600))
new=\$((\$(date +%s) - 120))
printf 'oldpeer\t%s\n' "\$old"
printf 'newpeer\t%s\n' "\$new"
EOF
      ;;
    never-handshaked)
      # All zeros — wg-quick reports 0 for peers that haven't handshaked.
      cat >"${stubdir}/wg" <<'EOF'
#!/bin/sh
printf 'peer1\t0\n'
printf 'peer2\t0\n'
EOF
      ;;
    permission-denied)
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
source "${VPNII_HOME}/lib/vpnii.zsh"

# 1. Fresh handshake → age in seconds, close to 30.
make_wg_stub one-peer-fresh
age=$(_vpnii_handshake_age homelab)
assert_eq "$?" "0" "fresh: function exits 0"
# allow 0..2s drift between wg stub run and date call
if (( age >= 28 && age <= 32 )); then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m fresh: age ~30s (got %ss)\n' "$age"
else
  (( FAIL++ )); FAILED_TESTS+=("fresh: age ~30s")
  printf '  \033[0;31m✗\033[0m fresh: age ~30s (got %ss)\n' "$age"
fi

# 2. Multi-peer: pick max timestamp (= newest = smallest age, ~120s).
make_wg_stub multi-peer-pick-max
age=$(_vpnii_handshake_age homelab)
if (( age >= 118 && age <= 122 )); then
  (( PASS++ )); printf '  \033[0;32m✓\033[0m multi-peer: picks max ts (got %ss)\n' "$age"
else
  (( FAIL++ )); FAILED_TESTS+=("multi-peer: picks max ts")
  printf '  \033[0;31m✗\033[0m multi-peer: picks max ts (got %ss)\n' "$age"
fi

# 3. Never handshaked → return 1 (not "0 seconds ago").
make_wg_stub never-handshaked
_vpnii_handshake_age homelab >/dev/null
assert_eq "$?" "1" "never-handshaked: returns 1, not 0"

# 4. Permission denied → return 1, no output.
make_wg_stub permission-denied
out=$(_vpnii_handshake_age homelab 2>/dev/null)
assert_eq "$?" "1" "permission denied: returns 1"
assert_eq "$out" "" "permission denied: no output on stdout"

# 5. wg silent / no peers (empty stdout) → return 1.
make_wg_stub silent
_vpnii_handshake_age homelab >/dev/null
assert_eq "$?" "1" "silent wg: returns 1"

# Format helper: spot-check three buckets.
assert_eq "$(_vpnii_format_age 5)"     "5s"        "format: 5 seconds"
assert_eq "$(_vpnii_format_age 90)"    "1m 30s"    "format: 90 seconds"
assert_eq "$(_vpnii_format_age 3725)"  "1h 2m"     "format: 3725 seconds"

rm -rf "$stubdir"
