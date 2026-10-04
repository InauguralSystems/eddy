#!/usr/bin/env bash
# eddy milestone-2 gate: multi-key list-append transactions graded by Elle.
#   correct store obeys snapshot isolation for every interleaving;
#   the DST surfaces the dirty-read (intermediate-read) anomaly by sweeping
#   seeds; the anomaly replays byte-for-byte with only the pinned-argv N record.
# EIGS=<eigenscript>, JAVA=<java>, ELLE_JAR=<elle-cli standalone jar> override
# the binaries (CI sets all three inside the devcontainer).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
EIG="${EIGS:-eigenscript}"
JAVA="${JAVA:-java}"
JAR="${ELLE_JAR:?set ELLE_JAR to the elle-cli standalone jar}"
DST="$HERE/src/txn_dst.eigs"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
source "$HERE/test/replay_check.sh" || exit 1

# grade SEED MODE -> "true" | "false" (Elle's list-append verdict)
grade() {
  "$EIG" "$DST" "$1" "$2" > "$TMP" 2>/dev/null
  "$JAVA" -jar "$JAR" -m list-append -f json "$TMP" 2>/dev/null | grep -oE 'true|false' | tail -1
}

# 1. the correct store obeys snapshot isolation for every interleaving
cbad=""
for s in 1 2 3; do
  [ "$(grade "$s" correct)" = "true" ] || { cbad="$s"; break; }
done
[ -z "$cbad" ] && ok "correct store is snapshot-isolation valid (Elle) across seeds 1..3" \
              || no "correct store rejected by Elle at seed $cbad"

# 2. the DST surfaces the dirty-read anomaly (a reader observing another txn's
#    intermediate state) by sweeping seeds
found=""
for s in 1 2 3 4 5 6; do
  [ "$(grade "$s" dirty)" = "false" ] && { found="$s"; break; }
done
[ -n "$found" ] && ok "DST surfaces the dirty-read anomaly (seed $found -> Elle rejects)" \
                || no "no seed in 1..6 exposed the dirty-read anomaly"

# 3. Check execution, exact outputs and the pinned-argv population separately.
if [ -n "$found" ]; then
  check_replay "$found" dirty
  finish_replay
fi

echo "eddy milestone-2: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
