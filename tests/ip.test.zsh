# Tests for `vpnii ip`. PATH-stubs `dig` to control which resolver replies.

stubdir=$(mktemp -d)
VPNII="${VPNII_HOME}/bin/vpnii"

# dig stub controlled via env vars. We match on the query HOST (stable across
# the v4/v6 resolver-IP split the real command does) rather than the resolver
# address:
#   STUB_FAIL=myip.opendns.com,whoami.cloudflare   (these queries fail, exit 9)
#   STUB_REPLY_OPENDNS=1.2.3.4    (plain — A/AAAA shape)
#   STUB_REPLY_CLOUDFLARE=5.6.7.8 (will be quoted — TXT shape)
#   STUB_REPLY_GOOGLE=9.10.11.12  (will be quoted — TXT shape)
make_dig_stub() {
  cat >"${stubdir}/dig" <<'EOF'
#!/bin/sh
# The query host is the last bare arg (qtype precedes it; flags + @server skipped).
host=""
for arg in "$@"; do
  case "$arg" in
    @*|+*|-*) ;;
    *) host="$arg" ;;
  esac
done
case ",$STUB_FAIL," in
  *",${host},"*) exit 9 ;;
esac
case "$host" in
  myip.opendns.com)        echo "${STUB_REPLY_OPENDNS:-1.2.3.4}" ;;
  whoami.cloudflare)       echo "\"${STUB_REPLY_CLOUDFLARE:-5.6.7.8}\"" ;;
  o-o.myaddr.l.google.com) echo "\"${STUB_REPLY_GOOGLE:-9.10.11.12}\"" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${stubdir}/dig"
}

make_dig_stub
export PATH="${stubdir}:${PATH}"

# 1. First resolver replies → that's what we see.
output=$(STUB_REPLY_OPENDNS="93.184.216.34" "$VPNII" ip 2>&1)
assert_eq "$?" "0" "first source ok: exits 0"
assert_contains "$output" "93.184.216.34" "first source: IP printed"
assert_contains "$output" "via OpenDNS" "first source: source attribution"

# 2. First fails → fall back to Cloudflare; quotes from TXT are stripped.
output=$(STUB_FAIL="myip.opendns.com" STUB_REPLY_CLOUDFLARE="93.184.216.34" "$VPNII" ip 2>&1)
assert_eq "$?" "0" "fallback ok: exits 0"
assert_contains "$output" "93.184.216.34" "fallback: IP from cloudflare"
assert_contains "$output" "via Cloudflare" "fallback: cloudflare attribution"
# Make sure we didn't print the literal quotes from the TXT record.
[[ "$output" != *'"93.184.216.34"'* ]] && {
  (( PASS++ )); printf '  \033[0;32m✓\033[0m fallback: TXT quotes stripped\n'
} || {
  (( FAIL++ )); FAILED_TESTS+=("fallback: TXT quotes stripped")
  printf '  \033[0;31m✗\033[0m fallback: TXT quotes stripped (output: %s)\n' "$output"
}

# 3. First two fail → fall back to Google.
output=$(STUB_FAIL="myip.opendns.com,whoami.cloudflare" STUB_REPLY_GOOGLE="203.0.113.42" "$VPNII" ip 2>&1)
assert_eq "$?" "0" "third fallback: exits 0"
assert_contains "$output" "203.0.113.42" "third fallback: google IP"
assert_contains "$output" "via Google" "third fallback: google attribution"

# 4. All fail → die with hint.
output=$(STUB_FAIL="myip.opendns.com,whoami.cloudflare,o-o.myaddr.l.google.com" "$VPNII" ip 2>&1)
exit_code=$?
assert_eq "$exit_code" "1" "all fail: exits 1"
assert_contains "$output" "couldn't reach" "all fail: clear error"

# 5. -6 flag is accepted.
output=$(STUB_REPLY_OPENDNS="2001:db8::1" "$VPNII" ip -6 2>&1)
assert_eq "$?" "0" "-6 flag: accepted"
assert_contains "$output" "2001:db8::1" "-6 flag: v6 IP returned"

# 6. Unknown flag → die.
output=$("$VPNII" ip --bogus 2>&1) || true
assert_contains "$output" "unknown ip flag" "unknown flag: error"

rm -rf "$stubdir"
