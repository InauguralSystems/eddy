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
  `EIGS_REPLAY` with **zero tape `N` records** (as of EigenScript v0.29.0/#471
  the tape also pins CLI argv, so the boundary is exactly one `N args` record;
  the gates assert that set exactly).
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
replayed byte-for-byte with zero task-layer tape `N` records (v0.29.0 adds the
pinned-argv record, see above). The Elle bridge works: the
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
issued no scheduler yield. *(Resolved: #488 shipped in v0.29.0 as `lib/sync`
locks + `must_not_yield`; milestone 3 is their first adversarial exercise —
see F-EDDY-05.)*
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

## Milestone 3 (serializable rw-registers, Elle `rw-register -c serializable`)

**Again no EigenScript defect — and the anticipated `lib/sync` gap arrived
PRE-FILLED.** The blocking-lock forcing predicted below (and by F-EDDY-03) was
real: the SSI store's begin-snapshot and commit apply are both multi-step
sections that *yield mid-section*, so serializability genuinely needs mutual
exclusion across yield points. But upstream had already closed the loop —
**#488 shipped in v0.29.0** as `lib/sync` (`lock_new` / `lock_acquire` /
`lock_release` / `with_lock`) plus the `must_not_yield` builtin — so instead of
hand-rolling a spin-yield mutex and filing the proposal, milestone 3 became the
primitives' **first adversarial consumer**. Both held (see F-EDDY-05). The
store is simplified PostgreSQL SSI (Cahill SIGMOD'08): begin snapshots +
buffered writes + first-committer-wins, commit-time rw-antidependency flags
(`inc`/`outc` per txn, SIREAD lists per register), abort the pivot of a
dangerous structure — an active pivot is doomed in place, a committed pivot
aborts the discovering txn. Elle graded the correct store **serializable at
every seed swept**, with the validation demonstrably load-bearing (pivot
aborts fired at 7 of 12 seeds).

### OBS-3 — seed numbers, and what it took to REACH the anomalies
- `si` (honest snapshot isolation, no rw validation): **write skew caught as
  G2-item at seeds 1, 2, 3, 6, 9, 10, 11** of 1..12 — both txns read both
  contended registers as `[null, null]`, each writes one, both commit; a pure
  rw-antidependency cycle. High hit rate: SI's signature anomaly is easy for
  the seeded scheduler to reach.
- `nolock` (same SSI, lock ablated — the F-EDDY-03 footgun made real):
  **snapshot tear caught at seed 6** (first catch in 1..12): a reader's
  begin-snapshot straddled the writer's yielding commit apply and observed
  register 4's new value without register 3's (`r3=null, r4=401`).
- `correct`: **true at all 12 seeds swept** (gate asserts 1..8), aborts at 7.
- **The tear was NOT reachable in the first workload shape** — 40 seeds, zero
  catches. Two structural reasons, both DST-construction lessons: (1) with one
  txn per task, every begin-snapshot clusters at run start and every commit at
  run end, so a uniform seeded scheduler never phase-skews them enough to
  straddle; the fix was a process that runs **multiple sequential txns** (the
  reader runs three, so its later begins land while the writer's commit is in
  flight) plus a snapshot loop that yields per register. (2) SSI's
  conservative committed-pivot rule **masked the planted fault**: while the
  multi-register writer also had a read, cross-traffic set its `outc`, and the
  torn reader's own validation then self-aborted before emitting the torn
  history — the planted-fault variant only became gateable once the writer was
  blind (no reads). Echoes OBS-1's open question about yield granularity: the
  seeded scheduler explores well *within* the phase structure the workload
  gives it, but the workload must be shaped so anomalous phase overlaps exist.

### F-EDDY-05 — `lib/sync` + `must_not_yield` validated under a real adversary
The predicted `lib/sync` blocking primitive (F-EDDY-03, upstream #488) shipped
in v0.29.0 and milestone 3 leaned on it for correctness, not decoration: the
lock is held **across yield points** through a yielding begin-snapshot and a
yielding multi-step commit apply, under contention from three other tasks, at
every seed — and the `nolock` ablation proves Elle sees the difference (seed
6). `must_not_yield` wraps the SSI validation as an executable
must-not-suspend assertion, exactly the #488 debug-mode use case. Two
observations, neither a gap: (1) `lock_acquire`'s own test-and-claim is atomic
*by the cooperative non-yield property* — the F-EDDY-03 footgun is now fenced
inside one audited, upstream-owned helper instead of being re-rolled in every
consumer, which is the right resolution; (2) `must_not_yield` takes a
zero-argument fn, and passing context in used a nested `define` closing over
the txn's locals — closures cover the ergonomic need cleanly (resolved in
flight, nothing to file).

## Anticipated (milestone 4+ — NOT yet exercised)

- **Strict serializability / real-time edges.** Milestone 3 grades
  `-c serializable`; the histories carry `index` order, so tightening to
  `strict-serializable` (and `-c` ladder experiments per seed) is the next
  rung.
- **Mailbox-based coordination.** The lock is a shared-memory flag; a
  transaction-manager-as-task protocol over `task_send`/`task_recv` would
  exercise the mailbox surface the proposal named and none of M1–M3 touch.

## Interleaving explorer (issue #6, fleet UI ladder rung 4)

### F-EDDY-06 — GAP: no runtime introspection of scheduler decisions
The explorer's "who ran when" lanes are DERIVED from app-level records —
op invoke/ok pairs on the logical clock plus explicit marks at each
`task_yield` call site (`dst_sched_mark`). That covers this workload
because eddy owns every yield site, but it is not the scheduler's own
story: the runtime's seeded ready-queue pick (which task resumed, in what
order, at which yield) is invisible to `.eigs` code, so true run SEGMENTS
(resume → yield) cannot be drawn — only op intervals and yield points. A
consumer that loads third-party task code (or wants to visualize
`task_sleep`/virtual-time scheduling, as liferaft would) cannot
instrument every site by hand. Filed upstream as EigenScript#846 — a
gated `task_sched_trace` (off by default, like the observer/trace flags)
that records {tick, resumed-task, cause} without perturbing the pick
sequence. Until then the derived view is honest: the sink is a pure
reader (gated — `--dump` byte-matches the CLI with the sink on), it just
sees less than the scheduler knows.
