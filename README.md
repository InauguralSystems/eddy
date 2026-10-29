# eddy

A **deterministic simulation tester (DST) for concurrency control**, written in
[EigenScript](https://github.com/InauguralSystems/EigenScript). Transactions
(here, clients of a store) are **cooperative tasks** (EigenScript #408); the
seeded scheduler explores interleavings; every run's history is graded by an
**external** linearizability/isolation checker. A seed that produces a rejected
history is a perfectly reproducible anomaly.

This is **not** a production datastore. It is a forcing function: a real,
non-trivial concurrent program that stresses EigenScript's cooperative task
layer (`task_spawn`/`task_yield`/`task_join`, `task_sched_seed`, virtual time)
along an axis nothing else in the ecosystem exercises, and surfaces gaps
upstream (see [`FINDINGS.md`](FINDINGS.md)).

## Why the checker is external

The store must not grade itself. `eddy` emits a history file and hands it to an
independent checker built from published theory:

- **Milestone 1:** single-register linearizability, graded by
  [Porcupine](https://github.com/anishathalye/porcupine) (Wing-Gong check,
  MIT, pure Go) via the ~90-line harness in [`oracle/check.go`](oracle/check.go).
- **Milestone 2:** multi-key **list-append transactions** under snapshot
  isolation, graded by [Elle](https://github.com/jepsen-io/elle) (Adya-anomaly
  detection) via the [`elle-cli`](https://github.com/ligurio/elle-cli)
  standalone uberjar, over a Jepsen op-map JSON history.
- **Milestone 3:** **read-write registers** under **serializability** — the
  workload where snapshot isolation admits write skew — graded by Elle's
  `rw-register` model with the `serializable` consistency target.

## The determinism contract

- The whole run is reproducible from **one integer seed**. Same seed ⇒
  byte-identical history ⇒ the checker returns the same verdict.
- The interleaving comes entirely from `task_sched_seed`; client op scripts are
  fixed, so the scheduler is the only variable.
- The only tape `N` record is the **pinned CLI argv** (the declared
  nondeterminism boundary since EigenScript v0.29.0, #471); the task layer
  itself contributes none, so `EIGS_TRACE`/`EIGS_REPLAY` reproduces any run —
  including a found violation — byte-for-byte.

## Milestone 1 — what it proves

A single register with three cooperative-task clients under a seeded schedule:

- `correct` store (atomic get/put) is **linearizable for every seed**.
- `torn` store (a non-atomic write, `reg:=0; yield; reg:=v`, visible to a
  concurrent reader) is **caught as non-linearizable** — the DST finds an
  exposing interleaving by sweeping seeds, and the violation replays
  byte-for-byte from its seed.

```sh
# milestone 1 — single register, Porcupine:
eigenscript src/dst.eigs 2 torn | oracle/check     # -> ILLEGAL
eigenscript src/dst.eigs 2 correct | oracle/check  # -> OK
EIGS=eigenscript GO=go bash test/run.sh            # the gate

# milestone 2 — multi-key transactions, Elle:
eigenscript src/txn_dst.eigs 1 dirty > h.json
java -jar "$ELLE_JAR" -m list-append -f json h.json   # -> false (anomaly)
EIGS=eigenscript JAVA=java ELLE_JAR=... bash test/run_txn.sh  # the gate

# milestone 3 — serializable rw-registers, Elle:
eigenscript src/rw_dst.eigs 1 si > h.json
java -jar "$ELLE_JAR" -m rw-register -c serializable -f json h.json  # -> false (G2-item write skew)
EIGS=eigenscript JAVA=java ELLE_JAR=... bash test/run_rw.sh   # the gate
```

## Milestone 2 — what it proves

Three cooperative-task transactions over 3 list-valued keys, appending
globally-unique values so Elle can recover the version order:

- `correct` store (snapshot isolation: a txn reads the committed prefix as of
  its begin plus its own buffered appends; commit applies the buffer atomically
  — no yield in the commit loop) is **valid under snapshot isolation** for every
  interleaving.
- `dirty` store (appends apply to the live shared list immediately; reads see
  the whole live list) lets a reader observe another txn's **intermediate
  state** — Elle catches it (G1b) — and the anomaly replays byte-for-byte from
  its seed.

## Milestone 3 — what it proves

Read-write registers with overlapping read sets and disjoint write sets — the
classic **write-skew** shape snapshot isolation cannot reject — plus a blind
multi-register writer and a repeating reader, as cooperative-task transactions:

- `correct` store implements **Serializable Snapshot Isolation** (Cahill
  SIGMOD'08 / PostgreSQL SSI, simplified): begin snapshots + buffered writes +
  first-committer-wins, with commit-time **rw-antidependency** tracking that
  aborts the pivot of a dangerous structure. Begin-snapshot and the
  deliberately multi-step commit apply both *yield mid-section*, so their
  atomicity comes from a **real blocking lock** (`lib/sync`, upstream #488) —
  not from the milestone-2 "atomic because it never yields" accident
  (F-EDDY-03); validation runs inside `must_not_yield`. Elle grades it
  **serializable for every seed**, and the aborts demonstrably fire.
- `si` store (same machinery, no rw validation — honest snapshot isolation)
  **admits write skew**: both txns read both contended registers as empty and
  both commit their writes — Elle rejects it as **G2-item**.
- `nolock` store (same SSI, lock ablated) shows the F-EDDY-03 footgun for
  real: a begin-snapshot straddles the yielding commit apply and observes half
  a transaction's writes — Elle rejects the torn read.
- Every anomaly replays byte-for-byte from its seed.

## Layout

| Path | What |
|------|------|
| `src/dst.eigs` | M1 CLI: emits the Porcupine JSON history (machinery in `src/dst_core.eigs`) |
| `src/dst_core.eigs` | M1 core: single-register store (correct + torn) + cooperative-task DST + the explorer's schedule sink |
| `explorer.eigs` + `explorer_main.eigs` | interleaving explorer (#6): timeline lanes + anomaly replay scrubber over a seed's schedule |
| `src/txn_dst.eigs` | M2: multi-key list-append transactions (correct SI + dirty) + DST; emits a Jepsen op-map JSON history |
| `src/rw_dst.eigs` | M3: serializable rw-registers (SSI + `lib/sync` lock, plain SI, lock-ablated) + DST; Jepsen op-map JSON history |
| `oracle/check.go` | M1's external Porcupine linearizability oracle (`OK`/`ILLEGAL`) |
| `test/run.sh` | M1 gate: builds the oracle, sweeps seeds, asserts determinism + replay |
| `test/run_txn.sh` | M2 gate: grades correct/dirty with Elle (`elle-cli`), asserts the anomaly replays |
| `test/run_rw.sh` | M3 gate: correct serializable + aborts firing, si write skew (G2-item), nolock snapshot tear, replay |
| `test/run_ui.sh` | Explorer gate (Go-free): `--dump` byte-matches the CLI (pure-reader + sink purity in one diff), schedule determinism, tape N-records, headless UI dispatch test |
| `FINDINGS.md` | The gap ledger — every language/runtime observation, filed upstream not worked around |
| `.devcontainer/` | Pinned EigenScript (`EIGS_REF`) + Go toolchain; the same image CI runs |
