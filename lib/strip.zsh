#!/usr/bin/env zsh
# vpnii hook stripping — removes vpnii(-state) state-management snippets from
# PostUp/PreDown lines in a wg-quick config. Three legacy patterns survive in
# the wild:
#   1. old claudii: && mkdir -p .../.cache/claudii && echo "X" > .../claudii/vpnii
#   2. su -c form:  && su -c 'vpnii(-state) ...' - $SUDO_USER
#   3. sudo form:   && sudo -u $SUDO_USER /path/vpnii(-state) up <name>
#
# `_strip_to_file <src> <dst>` reads <src>, strips known patterns from
# PostUp/PreDown lines, writes the result to <dst>. Source is untouched.
# All other lines pass through verbatim.
#
# Implemented with `sed -E`. `|` is the s-delimiter so paths don't need to
# escape `/`. Word-boundaries are split across two passes per "vpnii"
# suffix: one for EOL (`/vpnii$`), one for a non-word char after vpnii
# (captured via `(...)` and put back via `\1`). The previous `[[:>:]]`
# form is BSD-only and made GNU sed bail with "Invalid character class
# name", and `($|X)` alternation inside a `s|...|...|` block confused BSD
# sed's delimiter scan ("parentheses not balanced"). Embedded single
# quotes use the standard `'\''` shell-escape so the patterns can match
# `su -c 'vpnii ...'`.

_strip_to_file() {
  sed -E '
/^PostUp[[:space:]]*=/{
  s|[[:space:]]*&&[[:space:]]*mkdir[[:space:]]+-p[[:space:]]+[^[:space:]]*\.cache[^[:space:]]*[[:space:]]*&&[[:space:]]*echo[[:space:]]+"[^"]*"[[:space:]]*>[[:space:]]*[^[:space:]]*/vpnii$||g
  s|[[:space:]]*&&[[:space:]]*mkdir[[:space:]]+-p[[:space:]]+[^[:space:]]*\.cache[^[:space:]]*[[:space:]]*&&[[:space:]]*echo[[:space:]]+"[^"]*"[[:space:]]*>[[:space:]]*[^[:space:]]*/vpnii([^[:alnum:]_-])|\1|g
  s|[[:space:]]*&&[[:space:]]*su[[:space:]]+-c[[:space:]]+'\''vpnii(-state)?[^'\'']*'\''[[:space:]]+-[[:space:]]+[^[:space:]]+||g
  s|[[:space:]]*&&[[:space:]]*sudo[[:space:]]+-u[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]*vpnii(-state)?[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+||g
}
/^PreDown[[:space:]]*=/{
  s|[[:space:]]+[^[:space:]]+/\.cache[^[:space:]]*/vpnii$||g
  s|[[:space:]]+[^[:space:]]+/\.cache[^[:space:]]*/vpnii([^[:alnum:]_-])|\1|g
  s|su[[:space:]]+-c[[:space:]]+'\''vpnii(-state)?[^'\'']*'\''[[:space:]]+-[[:space:]]+[^[:space:]]+||g
  s|[[:space:]]*&&[[:space:]]*sudo[[:space:]]+-u[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]*vpnii(-state)?[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+||g
}
' "$1" > "$2"
}
