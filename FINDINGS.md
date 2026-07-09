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

## Milestone 2 (multi-key list-append transactions, Elle oracle)

**Again no EigenScript defect surfaced.** The store correctly implements
snapshot isolation over 3 list-valued keys — Elle validated it across seeds —
the planted dirty-read (intermediate-read / G1b) bug was caught, and the anomaly
replayed byte-for-byte with zero tape `N` records. The Elle bridge works: the
DST emits a Jepsen op-map JSON array that `elle-cli -m list-append` grades
directly, so the checker swapped Porcupine → Elle **without rewriting the DST**,
exactly as the format decision intended.

### OBS-2 — `task_sched_seed` reaches intermediate-read schedules readily
Sweeping dirty over seeds 1..6, Elle rejected seeds 1, 3, 4 (a reader catching
another txn mid-append). The seeded scheduler finds isolation-anomaly-exposing
interleavings at a healthy rate at this scale.

### F-EDDY-03 — the load-bearing finding: "atomic section via cooperative non-yield"
The correct store's commit is atomic **purely because its commit loop contains
no `task_yield`** — under cooperative single-thread scheduling, any region that
does not yield is indivisible, so mutual exclusion is free without a lock.
Powerful, but a **footgun**: nothing in the language *marks* a region as
must-not-yield, so an accidental `task_yield` (or a yielding builtin) inside a
commit would silently break atomicity and only show up as a rare seed-dependent
anomaly. **Filed upstream: InauguralSystems/EigenScript#488** — a `lib/sync` with a
`critical`/`atomic` helper plus a debug-mode assertion that a delimited region
issued no scheduler yield.
This is the concrete, grounded form of the anticipated `lib/sync` gap — surfaced
by SI, not yet by a blocking lock (append-only writes commute, so milestone 2
needs no lock manager).

### F-EDDY-04 — TOOLCHAIN: the transactional oracle costs a JVM
Elle is delivered as `elle-cli`, a standalone uberjar needing a JRE (~180 MB +
37 MB jar) — heavier than milestone 1's pure-Go Porcupine. Justified: Elle is
the **sound, near-linear, black-box** transactional-isolation oracle (Adya
G0/G1/G2 via cycle detection), and re-implementing it in EigenScript would be
self-grading. Lives in the devcontainer/CI; local `test/run_txn.sh` needs
`JAVA` + `ELLE_JAR`.

## Anticipated (milestone 3 — NOT yet exercised)

- **A blocking cooperative lock IS forced by serializable rw-registers.** Once
  the workload has read-write conflicts (not conflict-free appends), an SSI/2PL
  store needs real lock acquisition across yield points and transaction aborts —
  the point where a `lib/sync` blocking primitive (built on mailboxes or a
  spin-yield flag) becomes unavoidable, connecting to `lib/supervise.eigs`.
- **Elle consistency-model ladder.** `elle-cli -c` can target read-committed →
  snapshot-isolation → serializable → strict-serializable; milestone 3 tightens
  the target and ports PostgreSQL SSI as the reference protocol.
