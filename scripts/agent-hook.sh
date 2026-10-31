#!/bin/sh
# Hook d'agent -> Boring Notch. Usage : agent-hook.sh <claude|codex|cursor>
# Transmet aussi l'app du terminal (pour rouvrir la conversation au clic).
# Échoue en silence si l'app est fermée (l'agent n'est jamais bloqué).
SOCK="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
[ -S "$SOCK" ] || { cat >/dev/null; exit 0; }
{ printf '{"source":"%s","app":"%s","payload":' "$1" "$__CFBundleIdentifier"; tr -d '\n'; printf '}'; } | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
