#!/bin/sh
# Forfait d'une IA -> Boring Notch, quel que soit le client (terminal, T3 Code, SDK). Usage : agent-usage.sh <claude|codex>
# Mêmes sources que T3 Code, sans appel au modèle :
#   claude : requête de contrôle `get_usage` du CLI (hooks coupés, aucune session enregistrée) ;
#   codex  : `account/rateLimits/read` de `codex app-server` (aucun fil ouvert).
# Lancé en arrière-plan par agent-hook.sh / codex-hook.sh ; au plus une fois toutes les 3 min par IA.
# --force : ignore la limite. BN_DRY=1 : affiche au lieu d'envoyer. --parse <source> <fichier> : convertit une réponse enregistrée (auto-test).
exec /usr/bin/python3 -c '
import json, os, shutil, socket, subprocess, sys, threading, time
from datetime import datetime

SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
THROTTLE = 180

def claude_limits(resp):
    rl = (resp or {}).get("rate_limits") or {}
    out = {}
    for k in ("five_hour", "seven_day"):
        w = rl.get(k) or {}
        if not isinstance(w.get("utilization"), (int, float)): continue
        try: reset = datetime.fromisoformat(w["resets_at"]).timestamp()
        except Exception: reset = None
        out[k] = {"used_percentage": w["utilization"], "resets_at": reset}
    return out

def codex_limits(result):
    snap = ((result or {}).get("rateLimitsByLimitId") or {}).get("codex") or (result or {}).get("rateLimits") or {}
    out = {}
    # primary / secondary sont des positions : on range par durée (5 h, 7 j) ; offre mensuelle ignorée.
    for w in (snap.get("primary"), snap.get("secondary")):
        if not w or not isinstance(w.get("usedPercent"), (int, float)): continue
        mins = w.get("windowDurationMins")
        key = "five_hour" if mins == 300 else "seven_day" if mins == 10080 else None
        if key: out[key] = {"used_percentage": w["usedPercent"], "resets_at": w.get("resetsAt")}
    return out

def envelope(source, limits):
    return {"source": source, "kind": "usage", "payload": {"rate_limits": limits}} if limits else None

PROBES = {
    "claude": (["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                "--no-session-persistence", "--settings", "{\"disableAllHooks\":true}"],
               [{"type": "control_request", "request_id": "i", "request": {"subtype": "initialize"}},
                {"type": "control_request", "request_id": "u", "request": {"subtype": "get_usage"}}],
               lambda d: d.get("type") == "control_response" and (d.get("response") or {}).get("request_id") == "u",
               lambda d: claude_limits(d["response"].get("response"))),
    "codex": (["app-server"],
              [{"method": "initialize", "id": 1, "params": {"clientInfo": {"name": "boring-notch", "title": "Boring Notch", "version": "1"}}},
               {"method": "initialized"},
               {"method": "account/rateLimits/read", "id": 2}],
              lambda d: d.get("id") == 2,
              lambda d: codex_limits(d.get("result"))),
}

def probe(source):
    args, lines, match, parse = PROBES[source]
    exe = shutil.which(source) or os.path.expanduser("~/.local/bin/" + source)
    if not os.access(exe, os.X_OK): return None
    p = subprocess.Popen([exe] + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    guard = threading.Timer(20, p.kill); guard.daemon = True; guard.start()   # jamais plus de 20 s
    try:
        p.stdin.write("".join(json.dumps(l) + "\n" for l in lines)); p.stdin.flush()
        for line in p.stdout:
            try: d = json.loads(line)
            except ValueError: continue
            if match(d): return envelope(source, parse(d))
    except Exception:
        return None
    finally:
        p.kill()

a = sys.argv[1:]
if a[:1] == ["--parse"]:
    src, d = a[1], json.load(open(a[2]))
    print(json.dumps(envelope(src, PROBES[src][3](d)), sort_keys=True)); sys.exit(0)
force = "--force" in a
src = next((x for x in a if x in PROBES), None)
if not src or not os.path.exists(SOCK): sys.exit(0)
stamp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "bn-usage-" + src + ".stamp")
try:
    if not force and time.time() - os.path.getmtime(stamp) < THROTTLE: sys.exit(0)
except OSError:
    pass
open(stamp, "w").close()
env = probe(src)
if env and os.environ.get("BN_DRY"):
    print(json.dumps(env)); sys.exit(0)
if env:
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(SOCK); s.sendall(json.dumps(env).encode()); s.close()
    except Exception:
        pass
' "$@"
