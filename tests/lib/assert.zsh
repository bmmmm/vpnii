#!/usr/bin/env zsh
# Tiny assertion helpers for vpnii tests. Each assertion prints a one-line
# pass/fail and increments PASS/FAIL counters in the parent test runner.

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-equal}"
  if [[ "$actual" == "$expected" ]]; then
    (( PASS++ ))
    printf '  \033[0;32m✓\033[0m %s\n' "$msg"
    return 0
  fi
  (( FAIL++ ))
  FAILED_TESTS+=("$msg")
  printf '  \033[0;31m✗\033[0m %s\n' "$msg"
  printf '      expected: %q\n' "$expected"
  printf '      actual:   %q\n' "$actual"
  return 1
}

assert_file_eq() {
  local actual_file="$1" expected_file="$2" msg="${3:-files match}"
  if diff -q "$actual_file" "$expected_file" &>/dev/null; then
    (( PASS++ ))
    printf '  \033[0;32m✓\033[0m %s\n' "$msg"
    return 0
  fi
  (( FAIL++ ))
  FAILED_TESTS+=("$msg")
  printf '  \033[0;31m✗\033[0m %s\n' "$msg"
  printf '      diff (expected → actual):\n'
  diff "$expected_file" "$actual_file" | sed 's/^/        /'
  return 1
}

assert_exit() {
  local expected="$1"; shift
  local msg="$1"; shift
  local actual=0
  "$@" &>/dev/null || actual=$?
  if (( actual == expected )); then
    (( PASS++ ))
    printf '  \033[0;32m✓\033[0m %s\n' "$msg"
    return 0
  fi
  (( FAIL++ ))
  FAILED_TESTS+=("$msg")
  printf '  \033[0;31m✗\033[0m %s (expected exit %d, got %d)\n' "$msg" "$expected" "$actual"
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains}"
  if [[ "$haystack" == *"$needle"* ]]; then
    (( PASS++ ))
    printf '  \033[0;32m✓\033[0m %s\n' "$msg"
    return 0
  fi
  (( FAIL++ ))
  FAILED_TESTS+=("$msg")
  printf '  \033[0;31m✗\033[0m %s\n' "$msg"
  printf '      needle:   %q\n' "$needle"
  printf '      haystack: %q\n' "$haystack"
  return 1
}
