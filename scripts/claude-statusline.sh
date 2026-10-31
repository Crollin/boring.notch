#!/bin/sh
# Status line Claude Code -> Boring Notch (limites d'usage du forfait + présence de la session).
# Claude Code envoie son état en JSON sur stdin ; on le transmet au notch et on
# garde une copie dans /tmp pour inspection. N'affiche rien dans le terminal.
SOCK="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
IN=$(cat)
printf '%s' "$IN" > /tmp/bn-statusline.json
[ -S "$SOCK" ] && { printf '{"source":"claude","kind":"statusline","app":"%s","payload":%s}' "$__CFBundleIdentifier" "$(printf '%s' "$IN" | tr -d '\n')" | nc -U -w 1 "$SOCK" >/dev/null 2>&1; }
exit 0
