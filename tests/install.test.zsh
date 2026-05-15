# Tests for vpnii install. cmd-install hardcodes /etc/wireguard as the
# target; we stub `sudo` to absorb its heredoc-script and `wg-quick` so
# nothing actually writes to /etc/wireguard. Coverage focuses on flag
# parsing, pre-flight rejections, and that sudo gets the right args.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)
calls="${tmpdir}/calls.log"
: > "$calls"

cat >"${stubdir}/sudo" <<EOF
#!/bin/sh
[ "\$1" = "-n" ] && shift
echo "SUDO \$*" >> "$calls"
# When the real install would pipe a heredoc to 'sh -s', drain stdin so
# the parent doesn't block. Otherwise (e.g. 'sudo wg-quick up name')
# there's nothing to read; cat on an empty pipe returns immediately.
cat >/dev/null 2>&1 || true
EOF

cat >"${stubdir}/wg-quick" <<'EOF'
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

VALID_PRIV='AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK='
VALID_PUB='LLLLMMMMNNNNOOOOPPPPQQQQRRRRSSSSTTTTUUUUVVV='

# Build a clean config.
clean_conf="${tmpdir}/clean.conf"
cat >"$clean_conf" <<EOF2
[Interface]
PrivateKey = $VALID_PRIV

[Peer]
PublicKey = $VALID_PUB
AllowedIPs = 0.0.0.0/0
EOF2

hooked_conf="${tmpdir}/hooked.conf"
cat >"$hooked_conf" <<EOF2
[Interface]
PrivateKey = $VALID_PRIV
PostUp = vpnii up x

[Peer]
PublicKey = $VALID_PUB
AllowedIPs = 0.0.0.0/0
EOF2

# 1. Missing source → die.
output=$("$VPNII" install /no/such/path.conf 2>&1) || true
assert_contains "$output" "not found" "install missing: error"

# 2. Source contains vpnii hooks → reject with cleanup hint.
output=$("$VPNII" install "$hooked_conf" 2>&1) || true
assert_contains "$output" "vpnii hooks" "install hooked: rejects"
assert_contains "$output" "vpnii setup" "install hooked: hint to run setup"

# 3. Unknown flag → die with usage hint.
output=$("$VPNII" install --bogus "$clean_conf" 2>&1) || true
assert_contains "$output" "unknown install flag" "install: rejects unknown flag"

# 4. Missing positional after flags → usage error.
output=$("$VPNII" install -y 2>&1) || true
assert_contains "$output" "usage:" "install -y alone: usage error"

# 5. -n requires a value.
output=$("$VPNII" install -n 2>&1) || true
assert_contains "$output" "-n/--name needs a value" "install -n empty: clear error"

# 6. Happy path with -y: name derived from filename, sudo invoked.
: > "$calls"
output=$("$VPNII" install -y "$clean_conf" 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "install -y clean: exits 0"
assert_contains "$output" "tunnel name: clean" "install: derived name from filename"
assert_contains "$output" "/etc/wireguard/clean.conf" "install: target path computed"
assert_contains "$output" "installed at /etc/wireguard/clean.conf" "install: success message"
calls_content=$(cat "$calls")
assert_contains "$calls_content" "SUDO sh -s ${tmpdir}/clean.conf /etc/wireguard/clean.conf" \
  "install: sudo received correct args"

# 7. -n NAME overrides derived name.
: > "$calls"
output=$("$VPNII" install -y -n custom-vpn "$clean_conf" 2>&1)
assert_contains "$output" "tunnel name: custom-vpn" "install -n: name override applied"
assert_contains "$output" "/etc/wireguard/custom-vpn.conf" "install -n: target uses override"

# 8. -n with invalid name (path traversal) → reject.
output=$("$VPNII" install -y -n "../bad" "$clean_conf" 2>&1) || true
assert_contains "$output" "invalid tunnel name" "install -n bad: rejects path traversal"

rm -rf "$stubdir" "$tmpdir"
