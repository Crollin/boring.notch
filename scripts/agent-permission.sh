#!/bin/sh
# Hook PermissionRequest bloquant -> Boring Notch. Usage : agent-permission.sh <claude>
# Envoie la demande puis attend la décision (Autoriser/Refuser) cliquée dans le notch et la
# renvoie à l'agent. Sans réponse (app fermée, délai dépassé, réponse donnée dans le terminal) :
# sortie vide = le flux de validation normal continue.
exec /usr/bin/python3 -c '
import json, os, socket, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
try:
    p = json.load(sys.stdin)
    s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(SOCK)
    s.sendall(json.dumps({"source": sys.argv[1], "app": os.environ.get("__CFBundleIdentifier", ""), "wait": True, "payload": p}).encode())
    s.shutdown(socket.SHUT_WR); s.settimeout(100)
    out = b""
    while True:
        c = s.recv(4096)
        if not c: break
        out += c
    if out: sys.stdout.write(out.decode())
except Exception:
    pass
' "$1"
