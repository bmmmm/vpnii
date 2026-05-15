# Tests for vpnii export. No sudo, no /etc/wireguard collision — export
# reads any path and writes to the given dest dir (default $PWD).

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
export PATH="${stubdir}:${PATH}"
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
VPNII="${VPNII_HOME}/bin/vpnii"

VALID_PRIV='AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK='
VALID_PUB='LLLLMMMMNNNNOOOOPPPPQQQQRRRRSSSSTTTTUUUUVVV='

# Source with vpnii hooks — exporting should strip them. _strip_to_file
# matches the canonical "<wg-quick cmd> && <vpnii hook>" form (see
# tests/fixtures/sudo-form.in.conf for the production shape).
hooked_src="${tmpdir}/HomeLab.conf"
cat >"$hooked_src" <<EOF
[Interface]
PrivateKey = $VALID_PRIV
PostUp = nft -f /etc/nft.rules && sudo -u bma /usr/local/bin/vpnii up HomeLab
PreDown = nft flush ruleset && sudo -u bma /usr/local/bin/vpnii down HomeLab
Address = 10.0.0.2/24

[Peer]
PublicKey = $VALID_PUB
Endpoint = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0
EOF

clean_src="${tmpdir}/Already-Clean.conf"
cat >"$clean_src" <<EOF
[Interface]
PrivateKey = $VALID_PRIV

[Peer]
PublicKey = $VALID_PUB
AllowedIPs = 10.0.0.0/24
EOF

# 1. Missing source → die.
output=$("$VPNII" export /no/such/file.conf 2>&1) || true
assert_contains "$output" "not found" "export missing: error"

# 2. Unknown flag → die.
output=$("$VPNII" export --bogus "$clean_src" 2>&1) || true
assert_contains "$output" "unknown export flag" "export: rejects unknown flag"

# 3. Too many args → usage error.
output=$("$VPNII" export "$clean_src" "$tmpdir" extra 2>&1) || true
assert_contains "$output" "usage:" "export: too many args"

# 4. Happy path: hooked source → clean target.
out_dir="${tmpdir}/out"
output=$("$VPNII" export "$hooked_src" "$out_dir" 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "export hooked: exits 0"
target="${out_dir}/HomeLab.conf"
[[ -f "$target" ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m export: target file exists\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("export: target file exists")
  printf '  \033[0;31m✗\033[0m export: target file exists\n'
}
# Verify hooks are stripped.
if grep -qE 'vpnii(-state)?' "$target" 2>/dev/null; then
  (( FAIL++ )); FAILED_TESTS+=("export: hooks stripped")
  printf '  \033[0;31m✗\033[0m export: hooks stripped\n'
else
  (( PASS++ )); printf '  \033[0;32m✓\033[0m export: hooks stripped\n'
fi
# Verify content preserved.
assert_contains "$(cat "$target")" "PrivateKey = $VALID_PRIV" "export: PrivateKey preserved"
assert_contains "$(cat "$target")" "Endpoint = 1.2.3.4:51820" "export: Endpoint preserved"

# 5. Mode is 0600. stat is BSD on macOS, GNU on Linux — try both. GNU first
# because BSD stat fails cleanly on -c, while GNU stat reinterprets BSD's -f
# as --file-system and "succeeds" with verbose filesystem info.
mode=$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target" 2>/dev/null)
assert_eq "$mode" "600" "export: target mode is 0600"

# 6. Dest dir auto-created.
new_out="${tmpdir}/created-by-export"
output=$("$VPNII" export "$clean_src" "$new_out" 2>&1)
[[ -d "$new_out" ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m export: created missing dest dir\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("export: created missing dest dir")
  printf '  \033[0;31m✗\033[0m export: created missing dest dir\n'
}

# 7. Overwrite without -y: aborts (no tty for _ask, returns no).
output=$("$VPNII" export "$clean_src" "$out_dir" 2>&1 < /dev/null) || true
# Already-Clean.conf doesn't exist in out_dir yet (different name from earlier run),
# so this writes a new file — not an overwrite. Use the existing HomeLab target.
output=$("$VPNII" export "$hooked_src" "$out_dir" 2>&1 < /dev/null) || true
assert_contains "$output" "already exists" "export overwrite-no-tty: warns about existing"

# 8. Overwrite with -y: proceeds.
output=$("$VPNII" export -y "$hooked_src" "$out_dir" 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "export -y overwrite: exits 0"

rm -rf "$stubdir" "$tmpdir"
