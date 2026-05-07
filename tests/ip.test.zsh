# Tests for `vpnii ip`. PATH-stubs `curl` to control which source replies.

stubdir=$(mktemp -d)
VPNII="${VPNII_HOME}/bin/vpnii"

# Curl stub controlled via env vars set per test:
#   STUB_FAIL_HOSTS=ifconfig.io,icanhazip.com   → those hosts fail (empty + exit 1)
#   STUB_REPLY_FOR_<host>=<text>                → what to print for that host
make_curl_stub() {
  cat >"${stubdir}/curl" <<'EOF'
#!/bin/sh
url=""
for arg in "$@"; do
  case "$arg" in
    https://*) url="${arg#https://}" ;;
  esac
done
case ",$STUB_FAIL_HOSTS," in
  *",${url},"*) exit 1 ;;
esac
case "$url" in
  ifconfig.io)   echo "${STUB_REPLY_IFCONFIG:-1.2.3.4}" ;;
  icanhazip.com) echo "${STUB_REPLY_ICANHAZIP:-5.6.7.8}" ;;
  api.ipify.org) printf '%s' "${STUB_REPLY_IPIFY:-9.10.11.12}" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${stubdir}/curl"
}

make_curl_stub
export PATH="${stubdir}:${PATH}"

# 1. First source replies → that's what we see.
output=$(STUB_REPLY_IFCONFIG="93.184.216.34" "$VPNII" ip 2>&1)
assert_eq "$?" "0" "first source ok: exits 0"
assert_contains "$output" "93.184.216.34" "first source: IP printed"
assert_contains "$output" "via ifconfig.io" "first source: source attribution"

# 2. First source fails, second succeeds → second is shown.
output=$(STUB_FAIL_HOSTS="ifconfig.io" STUB_REPLY_ICANHAZIP="93.184.216.34" "$VPNII" ip 2>&1)
assert_eq "$?" "0" "fallback ok: exits 0"
assert_contains "$output" "via icanhazip.com" "fallback: second source"

# 3. All fail → die with hint.
output=$(STUB_FAIL_HOSTS="ifconfig.io,icanhazip.com,api.ipify.org" "$VPNII" ip 2>&1)
exit_code=$?
assert_eq "$exit_code" "1" "all fail: exits 1"
assert_contains "$output" "couldn't reach" "all fail: clear error"

# 4. -6 flag is accepted.
output=$(STUB_REPLY_IFCONFIG="2001:db8::1" "$VPNII" ip -6 2>&1)
assert_eq "$?" "0" "-6 flag: accepted"
assert_contains "$output" "2001:db8::1" "-6 flag: v6 IP returned"

# 5. Unknown flag → die.
output=$("$VPNII" ip --bogus 2>&1) || true
assert_contains "$output" "unknown ip flag" "unknown flag: error"

# 6. Trailing whitespace from curl is stripped.
output=$(STUB_REPLY_IFCONFIG="1.2.3.4   " "$VPNII" ip 2>&1)
# Match exactly "1.2.3.4  (via ifconfig.io)" — no trailing space-soup before "(".
assert_contains "$output" "1.2.3.4  (via" "whitespace stripped from IP"

rm -rf "$stubdir"
