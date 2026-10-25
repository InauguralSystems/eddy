#!/usr/bin/env bash
# eddy explorer gate (issue #6). Go-free: everything here runs with just
# the pinned EigenScript — the Porcupine/Elle oracles stay in the other
# gates. EIGS=<eigenscript> overrides the binary.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
EIG="${EIGS:-eigenscript}"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. Pure-reader + sink-purity oracle in one diff: the explorer's --dump
#    runs the SAME dst_run with the schedule sink ON and prints only the
#    history; it must byte-match the CLI (sink OFF). Divergence means the
#    explorer is not reading THE run, or the sink perturbed it.
pure=1
for m in correct torn; do
  for s in 2 7; do
    a=$("$EIG" src/dst.eigs "$s" "$m" 2>/dev/null)
    b=$("$EIG" explorer_main.eigs "$s" "$m" --dump 2>/dev/null)
    [ -n "$a" ] && [ "$a" = "$b" ] || { no "explorer history diverged from the CLI (seed $s $m)"; pure=0; }
  done
done
[ "$pure" -eq 1 ] && ok "explorer --dump byte-identical to src/dst.eigs (sink is a pure reader)"

# 2. The schedule record stream is deterministic (same seed, two fresh
#    processes) and non-empty.
sa=$("$EIG" explorer_main.eigs 2 torn --dump-sched 2>/dev/null)
sb=$("$EIG" explorer_main.eigs 2 torn --dump-sched 2>/dev/null)
if [ -n "$sa" ] && [ "$sa" = "$sb" ]; then
  ok "schedule records deterministic ($(printf '%s\n' "$sa" | wc -l) records)"
else
  no "schedule records diverged across two runs (or empty)"
fi

# 3. Tape accounting on the explorer path: one argv N record (#471) plus
#    only the two tape v7 module-source kinds, same boundary as the CLI.
TAPE="$(mktemp)"
EIGS_TRACE="$TAPE" "$EIG" explorer_main.eigs 2 torn --dump >/dev/null 2>&1
N=$(grep -c '^N ' "$TAPE" 2>/dev/null)
N_ARGS=$(grep -Ec '^N ([0-9]+ )?args=' "$TAPE" 2>/dev/null)
N_SOURCE=$(grep -Ec '^N ([0-9]+ )?load_file_source(_chunk)?=' "$TAPE" 2>/dev/null)
rm -f "$TAPE"
if [ "${N_ARGS:-0}" -eq 1 ] && [ "${N:-0}" -eq "$((N_ARGS + N_SOURCE))" ]; then
  ok "explorer tape N-records=$N (args=$N_ARGS source=$N_SOURCE)"
else
  no "explorer tape carries N=$N args=$N_ARGS source=$N_SOURCE (args=1 plus module source only expected)"
fi

# 4. The UI itself, driven headlessly through dispatch (gfx stubbed).
out=$("$EIG" test/test_explorer_ui.eigs 2>&1)
if printf '%s\n' "$out" | grep "explorer ui: all passed" >/dev/null; then
  ok "explorer UI (headless dispatch)"
else
  no "explorer UI (headless dispatch)"
  printf '%s\n' "$out" | grep -E "FAIL|error" | head -5
fi

echo "eddy explorer gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
