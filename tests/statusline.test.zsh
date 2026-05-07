# Tests for vpnii statusline — stable-width output.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

cat >"${stubdir}/ifconfig" <<'EOF'
#!/bin/sh
case "$STUB_TS" in
  on)  echo "utun9: flags=8051"; echo "	inet 100.64.0.3 netmask 0xffffffff" ;;
  off) echo "lo0:"; echo "	inet 127.0.0.1" ;;
esac
EOF
chmod +x "${stubdir}/ifconfig"

export PATH="${stubdir}:${PATH}"
VPNII="${VPNII_HOME}/bin/vpnii"

# Helper: run statusline, strip the trailing newline so length is comparable.
sl() {
  local out
  out=$("$@" 2>/dev/null | head -1)
  printf '%s' "$out"
}

# 1. Default widths: nothing up + TS off → padded slots, total fixed length.
out=$(STUB_TS=off VPNII_TS_ENABLED=1 sl "$VPNII" statusline)
# wg_w(14) + 2-space-separator + ts_w(5) = 21 chars total
assert_eq "${#out}" "21" "default off-state: width 21"
# Last 5 chars are TS slot — should be "⊖ off" exactly (5 cells)
assert_contains "$out" "⊖ off" "off-state: shows ⊖ off"

# 2. Tailscale on → "⬢ ts" in TS slot.
out=$(STUB_TS=on VPNII_TS_ENABLED=1 sl "$VPNII" statusline)
assert_eq "${#out}" "21" "ts-on: same width 21"
assert_contains "$out" "⬢ ts" "ts-on: shows ⬢ ts"

# 3. WG up + TS on → both slots filled.
touch "${VPNII_WG_DIR}/HomeLab.name"
out=$(STUB_TS=on VPNII_TS_ENABLED=1 sl "$VPNII" statusline)
assert_contains "$out" "⬡ HomeLab" "wg+ts: wg slot has tunnel"
assert_contains "$out" "⬢ ts" "wg+ts: ts slot active"

# 4. Long WG name → truncated with ellipsis.
rm "${VPNII_WG_DIR}/HomeLab.name"
touch "${VPNII_WG_DIR}/very-long-tunnel-name.name"
out=$(STUB_TS=off VPNII_TS_ENABLED=1 sl "$VPNII" statusline)
# Default wg_w=14 — the text "⬡ very-long-tunnel-name" is way longer.
# Should land at exactly wg_w=14 chars in the wg slot.
assert_contains "$out" "…" "long name: ellipsis present"

# 5. Custom widths via env vars.
rm "${VPNII_WG_DIR}/very-long-tunnel-name.name"
out=$(STUB_TS=off VPNII_TS_ENABLED=1 \
      VPNII_STATUSLINE_WG_W=8 VPNII_STATUSLINE_TS_W=8 \
      sl "$VPNII" statusline)
# 8 + 2-sep + 8 = 18
assert_eq "${#out}" "18" "custom widths: respected (8+2+8=18)"

# 6. TS disabled → ts slot still padded but empty (so wg-only setups don't
# get phantom indicator). Default total width should still be 21.
out=$(STUB_TS=off VPNII_TS_ENABLED=0 sl "$VPNII" statusline)
assert_eq "${#out}" "21" "TS disabled: slot padded, total width unchanged"
[[ "$out" == *"off"* ]] && {
  (( FAIL++ )); FAILED_TESTS+=("TS disabled: must NOT show off")
  printf '  \033[0;31m✗\033[0m TS disabled: must NOT show off (got: %q)\n' "$out"
} || {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m TS disabled: ⊖ off suppressed\n'
}

rm -rf "$stubdir" "$tmpdir"
