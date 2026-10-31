#!/bin/sh
# Hook Codex -> Boring Notch : événement de session + limites d'usage du forfait.
# Les limites ne sont pas dans le payload du hook : on les lit dans le dernier
# événement token_count du transcript. Échoue en silence si l'app est fermée.
exec /usr/bin/python3 -c '
import json, os, socket, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def send(obj):
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(1)
        s.connect(SOCK); s.sendall(json.dumps(obj).encode()); s.close()
    except Exception:
        pass

app = os.environ.get("__CFBundleIdentifier", "")
send({"source": "codex", "app": app, "payload": p})

# Dernier token_count du transcript -> rate_limits (primary = 5 h, secondary = 7 j).
try:
    last = None
    for line in open(p["transcript_path"]):
        if "token_count" in line:
            last = line
    rl = json.loads(last)["payload"]["rate_limits"]
    def win(w):
        return {"used_percentage": w["used_percent"], "resets_at": w["resets_at"]} if w else None
    send({"source": "codex", "kind": "statusline", "payload": {"rate_limits": {
        "five_hour": win(rl.get("primary")), "seven_day": win(rl.get("secondary"))}}})
except Exception:
    pass
'
