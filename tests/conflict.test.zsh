# Tests for _is_full_tunnel — the predicate that drives conflict detection
# when bringing up a wg tunnel. We test the predicate in isolation; the
# wider conflict flow uses _ask + _warn (already tested via cli.test).

source "${VPNII_HOME}/lib/ui.zsh"
source "${VPNII_HOME}/lib/cmd-tunnel.zsh"

tmpdir=$(mktemp -d)

# 1. Plain IPv4 full-tunnel.
cat > "$tmpdir/full-v4.conf" <<EOF
[Peer]
AllowedIPs = 0.0.0.0/0
EOF
_is_full_tunnel "$tmpdir/full-v4.conf"
assert_eq "$?" "0" "AllowedIPs = 0.0.0.0/0 → full-tunnel"

# 2. Plain IPv6 default route.
cat > "$tmpdir/full-v6.conf" <<EOF
[Peer]
AllowedIPs = ::/0
EOF
_is_full_tunnel "$tmpdir/full-v6.conf"
assert_eq "$?" "0" "AllowedIPs = ::/0 → full-tunnel"

# 3. Mixed list with 0.0.0.0/0 in the middle.
cat > "$tmpdir/full-mixed.conf" <<EOF
[Peer]
AllowedIPs = 192.168.1.0/24, 0.0.0.0/0, fd00::/64
EOF
_is_full_tunnel "$tmpdir/full-mixed.conf"
assert_eq "$?" "0" "mixed list including 0.0.0.0/0 → full-tunnel"

# 4. Split-tunnel: specific prefix only.
cat > "$tmpdir/split.conf" <<EOF
[Peer]
AllowedIPs = 192.168.189.0/24
EOF
_is_full_tunnel "$tmpdir/split.conf"
assert_eq "$?" "1" "split: AllowedIPs = single subnet → not full"

# 5. No AllowedIPs at all.
cat > "$tmpdir/no-allowedips.conf" <<EOF
[Peer]
PublicKey = X
Endpoint = 1.2.3.4:51820
EOF
_is_full_tunnel "$tmpdir/no-allowedips.conf"
assert_eq "$?" "1" "no AllowedIPs line → not full"

# 6. Edge case: 10.0.0.0/0 (literal typo, but technically not 0.0.0.0/0).
cat > "$tmpdir/typo.conf" <<EOF
[Peer]
AllowedIPs = 10.0.0.0/0
EOF
_is_full_tunnel "$tmpdir/typo.conf"
assert_eq "$?" "1" "10.0.0.0/0 (typo, not the default route) → not full"

# 7. Non-existent file → returns 1 (not full, defensive). Originally used
# `chmod 000` to test unreadability, but root in CI containers bypasses file
# perms and reads anyway. A path that doesn't exist exercises the same
# defensive branch (`[[ -r "$conf" ]]` is false) without depending on uid.
_is_full_tunnel "$tmpdir/does-not-exist.conf"
assert_eq "$?" "1" "unreadable file → not full (defensive)"

rm -rf "$tmpdir"
