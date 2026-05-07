# Tests for vpnii up/down tailscale. PATH-stubs the `tailscale` binary so
# we can exercise both the OK path and the App Store sandbox-broken path.

stubdir=$(mktemp -d)
tmpdir=$(mktemp -d)

# Always return a fake CGNAT IP so _vpnii_tailscale_active is true.
cat >"${stubdir}/ifconfig" <<'EOF'
#!/bin/sh
echo "utun9: flags=8051"
echo "	inet 100.64.0.3 netmask 0xffffffff"
EOF
chmod +x "${stubdir}/ifconfig"

# Stub builder for `tailscale`. mode=ok → echos a profile list and accepts
# any command; mode=sandboxed → mimics the App Store failure (exit 0 plus
# the marker error string we have to grep for).
make_tailscale_stub() {
  local mode="$1"
  case "$mode" in
    ok)
      cat >"${stubdir}/tailscale" <<'EOF'
#!/bin/sh
case "$1" in
  status) echo '{"BackendState":"Running"}' ;;
  switch)
    if [ "$2" = "--list" ]; then
      printf 'ID    Name        Tailnet     Account\n'
      printf 'aaaa  bma         headscale   bma\n'
      printf 'bbbb  appleid     tailscale   user (current)\n'
      exit 0
    fi
    echo "switched to $2"
    ;;
  up) echo "tailscale up" ;;
  down) echo "tailscale down" ;;
esac
EOF
      ;;
    sandboxed)
      cat >"${stubdir}/tailscale" <<'EOF'
#!/bin/sh
echo "The Tailscale CLI failed to start: Failed to load preferences."
exit 0
EOF
      ;;
    single-profile)
      cat >"${stubdir}/tailscale" <<'EOF'
#!/bin/sh
case "$1" in
  status) echo '{"BackendState":"Running"}' ;;
  switch)
    [ "$2" = "--list" ] && { printf 'ID    Name\n'; printf 'aaaa  default (current)\n'; exit 0; }
    echo "switched"
    ;;
  up|down) echo "tailscale $1" ;;
esac
EOF
      ;;
  esac
  chmod +x "${stubdir}/tailscale"
}

export PATH="${stubdir}:${PATH}"
export VPNII_WG_DIR="${tmpdir}/wg"
export VPNII_CACHE_DIR="${tmpdir}/cache"
mkdir -p "$VPNII_WG_DIR" "$VPNII_CACHE_DIR"
VPNII="${VPNII_HOME}/bin/vpnii"

# 1. Sandboxed CLI (App Store): vpnii up tailscale dies with the marker.
make_tailscale_stub sandboxed
output=$("$VPNII" up tailscale 2>&1)
exit_code=$?
assert_eq "$exit_code" "1" "sandboxed: vpnii up tailscale exits 1"
assert_contains "$output" "Mac App Store" "sandboxed: hint mentions App Store"

output=$("$VPNII" down tailscale 2>&1)
exit_code=$?
assert_eq "$exit_code" "1" "sandboxed: vpnii down tailscale exits 1"

# 2. Single-profile CLI: up/down work without prompting.
make_tailscale_stub single-profile
output=$("$VPNII" up tailscale 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "single-profile up: exits 0"
assert_contains "$output" "tailscale up" "single-profile up: invoked"

output=$("$VPNII" down tailscale 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "single-profile down: exits 0"
assert_contains "$output" "tailscale down" "single-profile down: invoked"

# 3. Multi-profile CLI: explicit profile arg switches before up.
make_tailscale_stub ok
output=$("$VPNII" up tailscale bma 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "multi-profile up bma: exits 0"
assert_contains "$output" "switched to bma" "multi-profile: switch invoked with chosen name"
assert_contains "$output" "tailscale up" "multi-profile: up invoked after switch"

# 4. VPNII_TS_NAME alias also works (default 'ts' hits the same branch).
output=$("$VPNII" up ts bma 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "VPNII_TS_NAME alias 'ts' routes to TS"

# 5. Down picks tailscale from active list when only TS is up.
# (vpnii down with no arg + only TS active → auto-pick tailscale.)
make_tailscale_stub single-profile
output=$("$VPNII" down 2>&1)
exit_code=$?
assert_eq "$exit_code" "0" "auto-pick down with only TS active: exits 0"
assert_contains "$output" "tailscale down" "auto-pick: routes to TS"

rm -rf "$stubdir" "$tmpdir"
