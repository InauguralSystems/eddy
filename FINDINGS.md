# FINDINGS — eddy's gap ledger

Every language/runtime observation from running `eddy` as a forcing function.
Gaps are filed upstream (InauguralSystems/EigenScript), never worked around
in-repo. Convention: `F-EDDY-NN` for findings, `OBS-N` for measurements.

## Milestone 1 (single-register linearizability, Porcupine oracle)

**Headline: no EigenScript defect surfaced.** The #408 cooperative task layer
held up under a real external adversary, not just the upstream suite's toy
programs:
- the correct (atomic) store was **linearizable for all 12 seeds** graded by
  Porcupine;
- the planted torn-write bug was **reliably caught** as non-linearizable;
- every run — including the caught violation — **replayed byte-for-byte** under
  `EIGS_REPLAY` with **zero tape `N` records**.
That is the concurrency-determinism moat validated on an oracle-graded workload:
a found anomaly is perfectly reproducible from a single integer seed.

### OBS-1 — `task_sched_seed` reaches anomaly-exposing interleavings
Sweeping seeds 1..12, the torn-write violation surfaced at seeds **2, 4, 5**
(the correct store was OK at every seed). So the seeded scheduler explores
schedules that expose a real concurrency bug at a healthy rate (~25–40% here) —
encouraging for the transactional phase, where the open question is whether the
per-operation yield granularity is fine enough to expose subtler isolation
anomalies. Not a gap; a baseline measurement to watch as the workload deepens.

### F-EDDY-01 — RESOLVED IN FLIGHT: JSON emission is a builtin, not boilerplate
First instinct was to hand-build the history JSON by string concatenation.
EigenScript already ships `json_encode` / `json_decode` / `json_build` and
`lib/json.eigs`; `src/dst.eigs` was refactored to `print of (json_encode of
events)`. No upstream gap — recorded so the ledger reflects that the language
covered this cleanly.

### F-EDDY-02 — TOOLCHAIN (not a language gap): the oracle needs Go
The external checker (Porcupine) is a Go program, and Go is not on the 4GB dev
box; it is provided in the devcontainer/CI (pinned Go tarball). Local
`test/run.sh` therefore needs `go` on PATH (`GO=` overridable). This is inherent
to importing an external, independently-authored oracle — the alternative
(re-implementing linearizability checking in EigenScript) would be self-grading
and is explicitly rejected. Recorded for the next local dev.

## Anticipated (later milestones — NOT yet exercised)

- **Cooperative mutual exclusion across yield points has no stdlib primitive.**
  Milestone 1 needs none (single-register ops are atomic), but a real lock
  manager / MVCC / SSI for the transactional phase will. Expect this to force a
  `lib/sync` and connect to `lib/supervise.eigs` (which EigenScript #408 already
  names as blocked on the task layer). This is the expected big harvest.
- **Transactional oracle swap.** The history is emitted in a shape a
  Jepsen-op-map mapper can consume, so the checker can move Porcupine → Elle
  (`elle-cli`) without rewriting the DST when multi-key transactions land.
