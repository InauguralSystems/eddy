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
source "$HERE/test/replay_check.sh" || exit 1

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

# 3. Check execution, exact output and the declared argv observation separately.
# Keep failed runs so a population failure cannot conceal output divergence.
if [ -n "$found" ]; then
  check_replay "$found" torn
  verdict=$("$CHK" <"$REPLAY_EVIDENCE/replay.stdout" 2>"$REPLAY_EVIDENCE/oracle.stderr"); oracle_rc=$?
  # oracle/check.go documents ILLEGAL as the expected anomaly: text plus rc1.
  if [ "$oracle_rc" -eq 1 ] && [ "$verdict" = "ILLEGAL" ]; then
    ok "replayed history retains the externally verified violation"
  else
    no "replayed history oracle failed: rc=$oracle_rc verdict=$verdict"
  fi
  finish_replay
fi

echo "eddy milestone-1: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
