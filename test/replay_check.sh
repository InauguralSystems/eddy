#!/usr/bin/env bash
# Shared checks for the three milestone wrappers. Uses their EIG/DST and
# ok/no counters; failed evidence is kept until finish_replay reports it.
check_replay() {
  local seed="$1" mode="$2"
  local a_rc b_rc record_rc replay_rc N N_ARGS N_SOURCE
  REPLAY_EVIDENCE=$(mktemp -d "${TMPDIR:-/tmp}/eddy-replay.XXXXXX") || exit 1
  REPLAY_FAILURES_BEFORE=$FAIL
  "$EIG" "$DST" "$seed" "$mode" >"$REPLAY_EVIDENCE/repeat-a.stdout" 2>"$REPLAY_EVIDENCE/repeat-a.stderr"; a_rc=$?
  "$EIG" "$DST" "$seed" "$mode" >"$REPLAY_EVIDENCE/repeat-b.stdout" 2>"$REPLAY_EVIDENCE/repeat-b.stderr"; b_rc=$?
  EIGS_TRACE="$REPLAY_EVIDENCE/trace.tape" "$EIG" "$DST" "$seed" "$mode" >"$REPLAY_EVIDENCE/record.stdout" 2>"$REPLAY_EVIDENCE/record.stderr"; record_rc=$?
  EIGS_REPLAY="$REPLAY_EVIDENCE/trace.tape" "$EIG" "$DST" "$seed" "$mode" >"$REPLAY_EVIDENCE/replay.stdout" 2>"$REPLAY_EVIDENCE/replay.stderr"; replay_rc=$?
  if [ "$a_rc" -eq 0 ] && [ "$b_rc" -eq 0 ] && [ "$record_rc" -eq 0 ] && [ "$replay_rc" -eq 0 ]; then
    ok "repeat, record and replay executions succeed"
  else
    no "execution failed: repeat-a=$a_rc repeat-b=$b_rc record=$record_rc replay=$replay_rc"
  fi
  if cmp -s "$REPLAY_EVIDENCE/repeat-a.stdout" "$REPLAY_EVIDENCE/repeat-b.stdout"; then
    ok "seed $seed repeats byte-for-byte"
  else
    no "repeated outputs differ at seed $seed"
  fi
  if cmp -s "$REPLAY_EVIDENCE/repeat-a.stdout" "$REPLAY_EVIDENCE/record.stdout" && cmp -s "$REPLAY_EVIDENCE/record.stdout" "$REPLAY_EVIDENCE/replay.stdout"; then
    ok "record and replay outputs match the ordinary run byte-for-byte"
  else
    no "record/replay output differs from the ordinary run at seed $seed"
  fi
  # Since runtime v0.29.0 (#471), exactly one argv N record is declared.
  # Tape v7 also records loaded module source with exactly these two kinds;
  # no time/random or other simulation nondeterminism may enter the tape.
  # Tape v4 adds the decimal stream id (v5 adds B associations); older
  # release pins use N args=<value> rather than N <stream_id> args=<value>.
  if [ -f "$REPLAY_EVIDENCE/trace.tape" ]; then
    N=$(grep -c '^N ' "$REPLAY_EVIDENCE/trace.tape")
    N_ARGS=$(grep -Ec '^N ([0-9]+ )?args=' "$REPLAY_EVIDENCE/trace.tape")
    N_SOURCE=$(grep -Ec '^N ([0-9]+ )?load_file_source(_chunk)?=' "$REPLAY_EVIDENCE/trace.tape")
    if [ "$N_ARGS" -eq 1 ] && [ "$N" -eq "$((N_ARGS + N_SOURCE))" ]; then
      ok "tape contains one argv observation plus $N_SOURCE module-source records"
    else
      no "tape observation population differs: expected args=1 plus module source only, got N=$N args=$N_ARGS source=$N_SOURCE"
    fi
  else
    no "record execution produced no tape"
  fi
}

finish_replay() {
  if [ "$FAIL" -eq "$REPLAY_FAILURES_BEFORE" ]; then
    rm -rf "$REPLAY_EVIDENCE"
  else
    echo "  EVIDENCE: $REPLAY_EVIDENCE (stdout, stderr and tape retained)"
  fi
}
