#!/usr/bin/env bash
# eddy milestone-3 gate: serializable read-write registers graded by Elle.
#   correct store (SSI + a real blocking lib/sync lock) is serializable for
#   every interleaving, and its validation demonstrably fires (aborts happen);
#   the si store (snapshot isolation, no rw validation) admits WRITE SKEW at
#   some seed (Elle names it G2-item); the nolock store (same SSI but the lock
#   ablated — the F-EDDY-03 non-yield-atomicity footgun) lets a multi-step
#   commit tear a concurrent snapshot at some seed; the caught anomaly replays
#   byte-for-byte with only the pinned-argv N record.
# EIGS=<eigenscript>, JAVA=<java>, ELLE_JAR=<elle-cli standalone jar> override
# the binaries (CI sets all three inside the devcontainer).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
EIG="${EIGS:-eigenscript}"
JAVA="${JAVA:-java}"
JAR="${ELLE_JAR:?set ELLE_JAR to the elle-cli standalone jar}"
DST="$HERE/src/rw_dst.eigs"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
source "$HERE/test/replay_check.sh" || exit 1

# grade SEED MODE -> "true" | "false" (Elle, rw-register model, serializable
# consistency target). Leaves the history in $TMP for follow-up assertions.
grade() {
  "$EIG" "$DST" "$1" "$2" > "$TMP" 2>/dev/null
  "$JAVA" -jar "$JAR" -m rw-register -c serializable -f json "$TMP" 2>/dev/null | grep -oE 'true|false' | tail -1
}

# 1. the correct store is serializable for every interleaving — and not
#    vacuously: the SSI validation must actually abort something in the sweep
cbad=""; aborts=0
for s in $(seq 1 8); do
  [ "$(grade "$s" correct)" = "true" ] || { cbad="$s"; break; }
  aborts=$((aborts + $(grep -o '"type":"fail"' "$TMP" | wc -l)))
done
[ -z "$cbad" ] && ok "correct store (SSI + lib/sync lock) is serializable (Elle) across seeds 1..8" \
              || no "correct store rejected by Elle at seed $cbad"
[ "$aborts" -ge 1 ] && ok "SSI validation is load-bearing: $aborts pivot abort(s) across the sweep" \
                    || no "no SSI abort fired across seeds 1..8 (validation is vacuous)"

# 2. the DST surfaces WRITE SKEW under plain snapshot isolation: some seed's
#    si history is rejected with the G2-item anomaly (two txns each read both
#    contended registers, each writes one, both commit)
skew=""
for s in $(seq 1 12); do
  if [ "$(grade "$s" si)" = "false" ]; then
    if "$JAVA" -jar "$JAR" -m rw-register -c serializable -f json -v "$TMP" 2>/dev/null | grep -q 'G2-item'; then
      skew="$s"; break
    fi
  fi
done
[ -n "$skew" ] && ok "DST surfaces write skew under SI (seed $skew -> Elle rejects, G2-item)" \
               || no "no seed in 1..12 produced a G2-item write skew under si"

# 3. the lock is load-bearing (the F-EDDY-03 footgun made real): with the lock
#    ablated, some seed lets a begin-snapshot straddle a yielding multi-step
#    commit apply — a torn read Elle rejects
torn=""
for s in $(seq 1 12); do
  [ "$(grade "$s" nolock)" = "false" ] && { torn="$s"; break; }
done
[ -n "$torn" ] && ok "DST surfaces the snapshot tear without the lock (seed $torn -> Elle rejects)" \
               || no "no seed in 1..12 exposed the nolock snapshot tear"

# 4. Check execution, exact outputs and the pinned-argv population separately.
if [ -n "$skew" ]; then
  check_replay "$skew" si
  finish_replay
fi

echo "eddy milestone-3: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
