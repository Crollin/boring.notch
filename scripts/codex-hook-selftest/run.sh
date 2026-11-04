#!/bin/sh
# Selftest de scripts/codex-hook.sh (mode BN_DRY, sans socket).
cd "$(dirname "$0")" || exit 1
HOOK=../codex-hook.sh
python3 - "$HOOK" <<'PY' || exit 1
import json, subprocess, os, sys
hook = sys.argv[1]
def run(inp):
    r = subprocess.run(["sh", hook], input=inp, capture_output=True, text=True, env={**os.environ, "BN_DRY": "1"})
    assert r.returncode == 0, r.returncode
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
pre = run(open("pre.json").read())
assert len(pre) == 1, pre
p = pre[0]["payload"]
assert p["hook_event_name"] == "PreToolUse" and p["tool_use_id"] and p["tool_name"] == "Bash", p
assert p["tool_input"]["command"] == "rtk ls -la", p
assert not any(l.get("kind") == "statusline" for l in pre), pre
post = run(open("post.json").read())
assert len(post) == 1 and post[0]["payload"]["hook_event_name"] == "PostToolUse", post
patch = run(open("patch.json").read())
assert len(patch) == 1, patch
q = patch[0]["payload"]
assert q["tool_name"] == "Edit" and q["tool_input"]["file_path"] == "src/a.swift", q
assert run("pas du json") == []
for bad in ("[1]", "null", "5", '"x"'):
    assert run(bad) == [], bad
nt = json.load(open("pre.json")); nt.pop("transcript_path")
assert not any(l.get("kind") == "statusline" for l in run(json.dumps(nt)))
PY
echo OK
