#!/bin/sh
# Hook d'agent -> Boring Notch. Usage : agent-hook.sh <claude|codex|cursor>
# Transmet aussi l'app du terminal (pour rouvrir la conversation au clic).
# Échoue en silence si l'app est fermée (l'agent n'est jamais bloqué).
SOCK="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
[ -S "$SOCK" ] || { cat >/dev/null; exit 0; }
IN=$(cat)
# À la fin d'un tour (Stop), on joint la fin du dernier message de l'agent : sert à repérer « il attend ma réponse ».
case "$IN" in *'"Stop"'*) IN=$(printf %s "$IN" | /usr/bin/python3 -c '
import json, sys
p = json.load(sys.stdin)
m = p.get("last_assistant_message")
if not m:
    try:
        for line in open(p["transcript_path"]):
            d = json.loads(line)
            if d.get("type") == "assistant":
                t = "".join(c.get("text", "") for c in d["message"]["content"] if isinstance(c, dict) and c.get("type") == "text")
                if t.strip(): m = t
    except Exception:
        pass
if isinstance(m, str): p["last_message"] = m[-400:]
print(json.dumps(p))
' 2>/dev/null || printf %s "$IN");; esac
{ printf '{"source":"%s","app":"%s","payload":' "$1" "$__CFBundleIdentifier"; printf %s "$IN" | tr -d '\n'; printf '}'; } | nc -U -w 1 "$SOCK" >/dev/null 2>&1
exit 0
