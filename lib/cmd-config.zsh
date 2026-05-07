#!/usr/bin/env zsh
# Config-management ergonomics: edit, verify, rename.
#
# All three operate on /etc/wireguard/<name>.conf and assume the file is
# user-owned (run `vpnii setup` first if not — that's the one-time sudo).

# `vpnii edit <name>` — open the config in $EDITOR. Refuses if the file
# isn't writable, with a hint to take ownership first.
_cmd_edit() {
  [[ $# -eq 1 ]] || _die "usage: vpnii edit <tunnel>"
  local name="$1"
  _validate_name "$name"
  local conf="/etc/wireguard/${name}.conf"
  [[ -f "$conf" ]] || _die "config not found: $conf  (run: vpnii setup)"
  [[ -w "$conf" ]] || _die "config not writable as $USER  (run: vpnii setup $conf)"
  exec "${EDITOR:-vi}" "$conf"
}

# `vpnii verify <conf>` — pre-flight a wg config before install. Catches
# malformed key shapes, missing sections, and leftover vpnii hooks early
# instead of letting wg-quick fail at runtime with a less-friendly error.
_cmd_verify() {
  [[ $# -eq 1 ]] || _die "usage: vpnii verify <wireguard-config.conf>"
  local conf="$1"
  [[ -f "$conf" ]] || _die "not found: $conf"
  [[ -r "$conf" ]] || _die "not readable: $conf"

  printf 'vpnii verify: %s\n' "$conf"

  local issues=0 warnings=0

  # Required sections.
  if grep -qE '^\[Interface\]' "$conf"; then
    _ok "[Interface] section present"
  else
    _err "[Interface] section missing"
    issues=$(( issues + 1 ))
  fi
  if grep -qE '^\[Peer\]' "$conf"; then
    _ok "[Peer] section present"
  else
    _err "[Peer] section missing"
    issues=$(( issues + 1 ))
  fi

  # PrivateKey: exactly one in [Interface], 44-char base64.
  local pk_count pk
  pk_count=$(grep -cE '^[[:space:]]*PrivateKey[[:space:]]*=' "$conf")
  if (( pk_count == 0 )); then
    _err "PrivateKey missing"; issues=$(( issues + 1 ))
  elif (( pk_count > 1 )); then
    _err "$pk_count PrivateKey lines (should be exactly 1)"; issues=$(( issues + 1 ))
  else
    pk=$(grep -E '^[[:space:]]*PrivateKey[[:space:]]*=' "$conf" | sed -E 's/^[[:space:]]*PrivateKey[[:space:]]*=[[:space:]]*//' | head -1)
    if [[ "$pk" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
      _ok "PrivateKey shape valid (44-char base64)"
    else
      _err "PrivateKey doesn't look like a wg key (expected 44 chars base64)"; issues=$(( issues + 1 ))
    fi
  fi

  # PublicKey: at least one, each 44-char base64.
  local pub_count=0 bad_pubs=0 line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pub_count=$(( pub_count + 1 ))
    [[ "$line" =~ ^[A-Za-z0-9+/]{43}=$ ]] || bad_pubs=$(( bad_pubs + 1 ))
  done < <(grep -E '^[[:space:]]*PublicKey[[:space:]]*=' "$conf" | sed -E 's/^[[:space:]]*PublicKey[[:space:]]*=[[:space:]]*//')
  if (( pub_count == 0 )); then
    _err "no PublicKey lines (need at least one peer)"; issues=$(( issues + 1 ))
  elif (( bad_pubs > 0 )); then
    _err "$bad_pubs of $pub_count PublicKey line(s) malformed"; issues=$(( issues + 1 ))
  else
    _ok "$pub_count PublicKey line(s), all base64-shaped"
  fi

  # AllowedIPs: optional but warn if missing.
  if grep -qE '^[[:space:]]*AllowedIPs[[:space:]]*=' "$conf"; then
    _ok "AllowedIPs present"
  else
    _warn "no AllowedIPs — wg-quick won't route any traffic through this peer"
    warnings=$(( warnings + 1 ))
  fi

  # Endpoint: warn if missing on any peer (not strictly required but unusual).
  if ! grep -qE '^[[:space:]]*Endpoint[[:space:]]*=' "$conf"; then
    _warn "no Endpoint — peer must initiate the handshake (you'll be passive only)"
    warnings=$(( warnings + 1 ))
  fi

  # vpnii hooks left over from older versions / claudii.
  if grep -qE 'vpnii(-state)?' "$conf"; then
    _err "vpnii(-state) hooks found — clean with: vpnii setup $conf"; issues=$(( issues + 1 ))
  else
    _ok "no leftover vpnii hooks"
  fi

  printf '\n'
  if (( issues > 0 )); then
    _err "$issues issue(s), $warnings warning(s) — install will likely fail"
    return 1
  elif (( warnings > 0 )); then
    _warn "$warnings warning(s) — install possible but review first"
    return 0
  else
    _ok "config looks ready to install"
    return 0
  fi
}

# `vpnii rename <old> <new>` — rename the config file and the cache marker
# in one step. Refuses when <old> is currently up — a live tunnel and a
# renamed config is a recipe for "wg-quick down homelab" failing with
# "no such file or directory".
_cmd_rename() {
  [[ $# -eq 2 ]] || _die "usage: vpnii rename <old> <new>"
  local old="$1" new="$2"
  _validate_name "$old"
  _validate_name "$new"
  [[ "$old" == "$new" ]] && _die "old and new are the same name"

  if [[ -f "${VPNII_WG_DIR}/${old}.name" ]]; then
    _die "$old is currently up — bring it down first: vpnii down $old"
  fi

  local old_conf="/etc/wireguard/${old}.conf"
  local new_conf="/etc/wireguard/${new}.conf"
  [[ -f "$old_conf" ]] || _die "no config at $old_conf"
  [[ -e "$new_conf" ]] && _die "$new_conf already exists"

  if [[ ! -w "$old_conf" || ! -w "$(dirname "$old_conf")" ]]; then
    _die "config or its directory not writable as $USER  (run: vpnii setup)"
  fi
  mv "$old_conf" "$new_conf" || _die "rename failed"
  _ok "renamed $old → $new  ($new_conf)"

  if [[ -f "${VPNII_CACHE_DIR}/${old}" ]]; then
    mv "${VPNII_CACHE_DIR}/${old}" "${VPNII_CACHE_DIR}/${new}"
    _ok "moved cache marker"
  fi
}
