#!/usr/bin/env zsh
# Tailscale up/down — drives the `tailscale` CLI. Multi-profile picker
# when more than one is configured. The Mac App Store build sandboxes
# its CLI off from the daemon, so all CLI calls fail with "The Tailscale
# CLI failed to start: Failed to load preferences" — but exit 0 anyway,
# so we have to grep stderr to know.

# Runs `tailscale "$@"`, mirrors output, and returns non-zero if the
# sandbox-failure marker is in the output OR the underlying call exits
# non-zero. This is the only reliable way to detect a broken CLI on the
# App Store build.
_tailscale_invoke() {
  local out rc=0
  out=$(tailscale "$@" 2>&1) || rc=$?
  [[ -n "$out" ]] && printf '%s\n' "$out"
  if [[ "$out" == *"Tailscale CLI failed"* ]]; then
    return 1
  fi
  return $rc
}

_tailscale_cli_works() {
  command -v tailscale &>/dev/null || return 1
  local out
  out=$(tailscale status --json 2>&1)
  [[ "$out" != *"Tailscale CLI failed"* ]]
}

_tailscale_sandboxed_die() {
  _err "tailscale CLI can't reach the daemon"
  printf '      The Mac App Store build sandboxes its CLI off — toggle\n'
  printf '      tailscale via the menu bar app instead. Or install the\n'
  printf '      OSS build (brew install tailscale) for CLI control.\n'
  exit 1
}

# Lists configured profiles, one per line: "<id> <name> ..." (the raw
# table row from `tailscale switch --list`, header stripped, trailing
# "(current)" trimmed). Empty result means single-profile setup.
_tailscale_list_profiles() {
  tailscale switch --list 2>/dev/null \
    | awk 'NR>1 && NF>=2 {sub(/[[:space:]]*\(current\)$/, "", $0); print}'
}

_cmd_tailscale_up() {
  local profile="${1:-}"
  if ! _tailscale_cli_works; then
    _tailscale_sandboxed_die
  fi

  # Multi-profile setup: pick one if not specified.
  local -a profiles=( ${(f)"$(_tailscale_list_profiles)"} )
  if (( ${#profiles} > 1 )); then
    if [[ -z "$profile" ]]; then
      local -a names=()
      local p
      for p in "${profiles[@]}"; do
        # Each row is whitespace-separated; second column is the name.
        names+=("${${(z)p}[2]}")
      done
      _pick_one "Tailscale profiles" "${names[@]}" || _die "aborted"
      profile="$REPLY"
    fi
    _info "tailscale switch $profile"
    _tailscale_invoke switch "$profile" \
      || _die "tailscale switch failed (see CLI output above; try: vpnii diag)"
  elif [[ -n "$profile" ]]; then
    _warn "only one profile configured — ignoring '$profile'"
  fi

  _info "tailscale up"
  _tailscale_invoke up \
    || _die "tailscale up failed (see CLI output above; try: vpnii diag)"
  printf '\n'
  _ok "tailscale up"
}

_cmd_tailscale_down() {
  if ! _tailscale_cli_works; then
    _tailscale_sandboxed_die
  fi
  _info "tailscale down"
  _tailscale_invoke down \
    || _die "tailscale down failed (see CLI output above; try: vpnii diag)"
  printf '\n'
  _ok "tailscale down"
}
