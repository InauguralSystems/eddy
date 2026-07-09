#!/usr/bin/env bash
# eddy milestone-1 gate. Proves the whole loop:
#   task-native store -> seeded interleaving -> JSON history -> EXTERNAL oracle
#   (Porcupine) -> deterministic byte-for-byte replay of a found violation.
# Exit 0 iff every assertion holds. EIGS=<eigenscript> and GO=<go> override the
# binaries (CI passes EIGS=eigenscript; Go must be on PATH for the oracle build).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
EIG="${EIGS:-eigenscript}"
GO="${GO:-go}"
DST="$HERE/src/dst.eigs"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# 0. build the external oracle (independent Go program; the store never self-grades)
if ! ( cd "$HERE/oracle" && "$GO" build -buildvcs=false -o check . ) 2>&1; then
  echo "  FAIL: oracle (Porcupine harness) failed to build"; exit 1
fi
CHK="$HERE/oracle/check"

# 1. the correct (atomic) store is linearizable for every interleaving
bad=""
for s in $(seq 1 12); do
  v=$("$EIG" "$DST" "$s" correct 2>/dev/null | "$CHK")
  [ "$v" = "OK" ] || { bad="$s($v)"; break; }
done
[ -z "$bad" ] && ok "correct store is linearizable (OK) across seeds 1..12" \
              || no "correct store not linearizable at seed $bad"

# 2. the DST surfaces the torn-write bug: at least one seed -> ILLEGAL
found=""
for s in $(seq 1 12); do
  [ "$("$EIG" "$DST" "$s" torn 2>/dev/null | "$CHK")" = "ILLEGAL" ] && { found="$s"; break; }
done
[ -n "$found" ] && ok "DST surfaces the torn-write violation (seed $found -> ILLEGAL)" \
                || no "no seed in 1..12 exposed the torn-write bug"

# 3. the found violation is deterministic + replays byte-for-byte, zero tape N
#    records — the concurrency-determinism moat on a real, oracle-graded workload
if [ -n "$found" ]; then
  A=$("$EIG" "$DST" "$found" torn 2>/dev/null)
  B=$("$EIG" "$DST" "$found" torn 2>/dev/null)
  TAPE="$(mktemp)"; EIGS_TRACE="$TAPE" "$EIG" "$DST" "$found" torn >/dev/null 2>&1
  R=$(EIGS_REPLAY="$TAPE" "$EIG" "$DST" "$found" torn 2>/dev/null)
  N=$(grep -c '^N ' "$TAPE" 2>/dev/null); rm -f "$TAPE"
  if [ "$A" = "$B" ] && [ "$A" = "$R" ] && [ "$N" -eq 0 ] && [ "$(printf '%s' "$A" | "$CHK")" = "ILLEGAL" ]; then
    ok "violation reproduces byte-for-byte from seed $found (2-run + EIGS_REPLAY identical, $N tape N records)"
  else
    no "violation not reproducible (2-run/replay diverged or N=$N != 0)"
  fi
fi

echo "eddy milestone-1: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
