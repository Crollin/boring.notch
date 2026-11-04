#!/bin/sh
# Selftest de scripts/agent-usage.sh : conversion des réponses get_usage (Claude) et account/rateLimits/read (Codex).
cd "$(dirname "$0")" || exit 1
U=../agent-usage.sh
c=$(sh $U --parse claude claude.json)
[ "$c" = '{"kind": "usage", "payload": {"rate_limits": {"five_hour": {"resets_at": 1793800200.032592, "used_percentage": 34}, "seven_day": {"resets_at": 1793916000.0, "used_percentage": 59}}}, "source": "claude"}' ] || { echo "FAIL claude: $c"; exit 1; }
x=$(sh $U --parse codex codex.json)
[ "$x" = '{"kind": "usage", "payload": {"rate_limits": {"five_hour": {"resets_at": 1793800565, "used_percentage": 6}, "seven_day": {"resets_at": 1794046511, "used_percentage": 15}}}, "source": "codex"}' ] || { echo "FAIL codex: $x"; exit 1; }
[ "$(echo '{"id":2,"result":{}}' > /tmp/bn-empty.json; sh $U --parse codex /tmp/bn-empty.json)" = "null" ] || { echo "FAIL vide"; exit 1; }
echo OK
