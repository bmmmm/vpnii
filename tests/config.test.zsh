# Tests for vpnii edit / verify / rename.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
configdir=$(mktemp -d)   # used as fake "/etc/wireguard" — but cmd-config
                         # hardcodes /etc/wireguard. We can only fully test
                         # `verify` (operates on arbitrary path) here.
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
export VPNII_TS_ENABLED=0
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"

VPNII="${VPNII_HOME}/bin/vpnii"

# Valid wg keys are exactly 44 chars: 43 base64 + '='. These are
# fake but shape-correct.
VALID_PRIV='AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK='
VALID_PUB1='LLLLMMMMNNNNOOOOPPPPQQQQRRRRSSSSTTTTUUUUVVV='
VALID_PUB2='WWWWXXXXYYYYZZZZ1111222233334444555566667o9='

# 1. Clean valid config → 0 issues.
clean_conf="${configdir}/clean.conf"
cat >"$clean_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV
Address    = 10.0.0.2/24

[Peer]
PublicKey  = $VALID_PUB1
Endpoint   = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0
EOF
output=$("$VPNII" verify "$clean_conf" 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "verify clean: exits 0"
assert_contains "$output" "ready to install" "verify clean: 'ready' message"
assert_contains "$output" "PrivateKey shape valid" "verify clean: pk valid"

# 2. Missing [Peer] section → fails.
broken_conf="${configdir}/broken.conf"
cat >"$broken_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV
EOF
output=$("$VPNII" verify "$broken_conf" 2>&1); exit_code=$?
assert_eq "$exit_code" "1" "verify broken: exits 1"
assert_contains "$output" "[Peer] section missing" "verify broken: peer section flagged"
assert_contains "$output" "no PublicKey lines" "verify broken: no pubkey flagged"

# 3. Malformed PrivateKey → fails.
malformed_conf="${configdir}/malformed.conf"
cat >"$malformed_conf" <<EOF
[Interface]
PrivateKey = not-a-real-key

[Peer]
PublicKey = $VALID_PUB1
AllowedIPs = 0.0.0.0/0
EOF
output=$("$VPNII" verify "$malformed_conf" 2>&1) || true
assert_contains "$output" "PrivateKey doesn't look like" "verify malformed: pk shape flagged"

# 4. Has vpnii hooks → fails.
hooked_conf="${configdir}/hooked.conf"
cat >"$hooked_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV
PostUp = something && sudo -u bma /path/vpnii up x

[Peer]
PublicKey = $VALID_PUB1
AllowedIPs = 0.0.0.0/0
EOF
output=$("$VPNII" verify "$hooked_conf" 2>&1) || true
assert_contains "$output" "vpnii(-state) hooks found" "verify hooked: hooks flagged"
assert_contains "$output" "vpnii setup" "verify hooked: cleanup hint"

# 5. Missing AllowedIPs → warning, not error (exits 0).
no_allowed_conf="${configdir}/no-allowed.conf"
cat >"$no_allowed_conf" <<EOF
[Interface]
PrivateKey = $VALID_PRIV

[Peer]
PublicKey = $VALID_PUB1
Endpoint = 1.2.3.4:51820
EOF
output=$("$VPNII" verify "$no_allowed_conf" 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "verify warning-only: exits 0"
assert_contains "$output" "no AllowedIPs" "verify warning-only: AllowedIPs warned"

# 6. verify on missing file → die.
output=$("$VPNII" verify /no/such/file 2>&1) || true
assert_contains "$output" "not found" "verify missing: error"

# 7. rename: invalid name → reject.
output=$("$VPNII" rename "../etc/passwd" newname 2>&1) || true
assert_contains "$output" "invalid tunnel name" "rename: rejects path traversal"

# 8. rename: same name → reject.
output=$("$VPNII" rename foo foo 2>&1) || true
assert_contains "$output" "same name" "rename: rejects identical names"

# 9. rename: usage when wrong arg count.
output=$("$VPNII" rename onlyone 2>&1) || true
assert_contains "$output" "usage:" "rename: usage on missing arg"

# 10. edit: missing file → clear error.
output=$("$VPNII" edit nonexistent-tunnel-name 2>&1) || true
assert_contains "$output" "config not found" "edit: error on missing"

# 11. edit: usage.
output=$("$VPNII" edit 2>&1) || true
assert_contains "$output" "usage:" "edit: usage on missing arg"

rm -rf "$stubdir" "$tmpdir" "$configdir"
