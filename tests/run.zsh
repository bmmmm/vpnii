#!/usr/bin/env zsh
# Test runner — sources every *.test.zsh under tests/, reports pass/fail.
# Each test file gets fresh PASS/FAIL/FAILED_TESTS counters via subshell.

set -u

TESTS_DIR="${0:A:h}"
VPNII_HOME="${TESTS_DIR:h}"
export VPNII_HOME

typeset -gi TOTAL_PASS=0 TOTAL_FAIL=0
typeset -ga ALL_FAILED=()

for test_file in "$TESTS_DIR"/*.test.zsh(N); do
  printf '\n\033[1m%s\033[0m\n' "${test_file:t:r}"
  # Run each test file in a subshell with its own counters, capture results.
  result_file=$(mktemp)
  (
    typeset -gi PASS=0 FAIL=0
    typeset -ga FAILED_TESTS=()
    source "$TESTS_DIR/lib/assert.zsh"
    source "$test_file"
    printf '%d %d\n' "$PASS" "$FAIL" > "$result_file"
    for f in "${FAILED_TESTS[@]}"; do printf 'F %s\n' "$f" >> "$result_file"; done
  )
  read -r p f < "$result_file"
  TOTAL_PASS=$(( TOTAL_PASS + p ))
  TOTAL_FAIL=$(( TOTAL_FAIL + f ))
  while IFS= read -r line; do
    [[ "$line" == F\ * ]] && ALL_FAILED+=("${test_file:t:r}: ${line#F }")
  done < "$result_file"
  rm -f "$result_file"
done

printf '\n\033[1m─── Summary ───\033[0m\n'
printf '  passed: %d\n' "$TOTAL_PASS"
if (( TOTAL_FAIL > 0 )); then
  printf '  \033[0;31mfailed: %d\033[0m\n' "$TOTAL_FAIL"
  for f in "${ALL_FAILED[@]}"; do
    printf '    - %s\n' "$f"
  done
  exit 1
fi
printf '  failed: 0\n'
exit 0
