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

_strip_to_file() {
  python3 - "$1" "$2" <<'PYEOF'
import sys, re

src, dst = sys.argv[1:3]

STRIP_POSTUP = re.compile(
    r'\s*&&\s*(?:'
    r'mkdir\s+-p\s+\S*\.cache\S*\s*&&\s*echo\s+"[^"]*"\s*>\s*\S*/vpnii'
    r"|su\s+-c\s+'vpnii(?:-state)?[^']*'\s+-\s+\S+"
    r'|sudo\s+-u\s+\S+\s+\S*vpnii(?:-state)?\s+\S+\s+\S+'
    r')'
)
STRIP_PREDOWN = re.compile(
    r'(?:'
    r'\s+\S+/\.cache\S*/vpnii\b'
    r"|su\s+-c\s+'vpnii(?:-state)?[^']*'\s+-\s+\S+"
    r'|\s*&&\s*sudo\s+-u\s+\S+\s+\S*vpnii(?:-state)?\s+\S+\s+\S+'
    r')'
)

with open(src) as f:
    lines = f.readlines()

out = []
for line in lines:
    if re.match(r'^PostUp\s*=', line):
        out.append(STRIP_POSTUP.sub('', line.rstrip('\n')) + '\n')
    elif re.match(r'^PreDown\s*=', line):
        out.append(STRIP_PREDOWN.sub('', line.rstrip('\n')) + '\n')
    else:
        out.append(line)

with open(dst, 'w') as f:
    f.writelines(out)
PYEOF
}
