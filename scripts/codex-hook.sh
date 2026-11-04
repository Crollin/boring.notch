#!/bin/sh
# Hook Codex -> Boring Notch : événement de session + limites d'usage du forfait.
# Les limites ne sont pas dans le payload du hook : on les lit dans le dernier
# événement token_count du transcript. Échoue en silence si l'app est fermée.
exec /usr/bin/python3 -c '
import json, os, re, socket, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(p, dict):
    sys.exit(0)

def send(obj):
    if os.environ.get("BN_DRY"):
        print(json.dumps(obj)); return
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(1)
        s.connect(SOCK); s.sendall(json.dumps(obj).encode()); s.close()
    except Exception:
        pass

def normalize(p):
    # Codex envoie déjà le format Claude (Bash, tool_input.command, tool_use_id).
    # Seul apply_patch (format non observé, d’après la doc Codex) devient Edit.
    # PermissionRequest : non vérifié, relayé tel quel.
    ti = p.get("tool_input")
    if p.get("tool_name") == "apply_patch" and isinstance(ti, dict):
        c = ti.get("command")
        txt = "\n".join(map(str, c)) if isinstance(c, list) else str(c or "")
        m = re.search(r"^\*\*\* (?:Update|Add) File: (.+)$", txt, re.M)
        p = dict(p, tool_name="Edit", tool_input={"file_path": m.group(1).strip() if m else ""})
    elif isinstance(ti, dict) and isinstance(ti.get("command"), list):
        p = dict(p, tool_input=dict(ti, command=" ".join(map(str, ti["command"]))))
    return p

p = normalize(p)
app = os.environ.get("__CFBundleIdentifier", "")
send({"source": "codex", "app": app, "payload": p})

# Limites : seulement hors événements d’outil (pas de lecture du transcript à chaque outil).
if p.get("hook_event_name") not in ("SessionStart", "UserPromptSubmit", "Stop"):
    sys.exit(0)

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
