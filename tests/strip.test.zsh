# Tests for _strip_to_file — pins behavior so the python→sed swap stays
# semantically identical. Each fixture has an .in.conf input and a
# .expected.conf golden output.

source "${VPNII_HOME}/lib/strip.zsh"

run_strip() {
  local fixture="$1"
  local input="${VPNII_HOME}/tests/fixtures/${fixture}.in.conf"
  local expected="${VPNII_HOME}/tests/fixtures/${fixture}.expected.conf"
  local actual
  actual=$(mktemp)
  _strip_to_file "$input" "$actual"
  assert_file_eq "$actual" "$expected" "${fixture}: matches golden"
  rm -f "$actual"
}

run_strip clean
run_strip foreign-hooks
run_strip claudii-legacy
run_strip su-form
run_strip sudo-form
run_strip sudo-state

# Idempotency — running strip twice produces the same output.
input="${VPNII_HOME}/tests/fixtures/sudo-form.in.conf"
once=$(mktemp); twice=$(mktemp)
_strip_to_file "$input" "$once"
_strip_to_file "$once" "$twice"
assert_file_eq "$twice" "$once" "idempotent: strip(strip(x)) == strip(x)"
rm -f "$once" "$twice"

# Foreign hooks (iptables, no vpnii reference) are preserved verbatim.
input="${VPNII_HOME}/tests/fixtures/foreign-hooks.in.conf"
out=$(mktemp)
_strip_to_file "$input" "$out"
assert_file_eq "$out" "$input" "foreign hooks untouched"
rm -f "$out"
