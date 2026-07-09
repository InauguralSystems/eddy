#!/usr/bin/env bash
# eddy milestone-2 gate: multi-key list-append transactions graded by Elle.
#   correct store obeys snapshot isolation for every interleaving;
#   the DST surfaces the dirty-read (intermediate-read) anomaly by sweeping
#   seeds; the anomaly replays byte-for-byte, zero tape N records.
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

# 3. the found anomaly reproduces byte-for-byte from its seed, zero tape N
if [ -n "$found" ]; then
  A=$("$EIG" "$DST" "$found" dirty 2>/dev/null)
  B=$("$EIG" "$DST" "$found" dirty 2>/dev/null)
  TAPE="$(mktemp)"; EIGS_TRACE="$TAPE" "$EIG" "$DST" "$found" dirty >/dev/null 2>&1
  R=$(EIGS_REPLAY="$TAPE" "$EIG" "$DST" "$found" dirty 2>/dev/null)
  N=$(grep -c '^N ' "$TAPE" 2>/dev/null); rm -f "$TAPE"
  if [ "$A" = "$B" ] && [ "$A" = "$R" ] && [ "$N" -eq 0 ]; then
    ok "anomaly reproduces byte-for-byte from seed $found (2-run + EIGS_REPLAY identical, $N tape N records)"
  else
    no "anomaly not reproducible (2-run/replay diverged or N=$N != 0)"
  fi
fi

echo "eddy milestone-2: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
