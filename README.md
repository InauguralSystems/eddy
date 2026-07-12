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
  BSD-3, pure Go) via the ~90-line harness in [`oracle/check.go`](oracle/check.go).
- **Milestone 2:** multi-key **list-append transactions** under snapshot
  isolation, graded by [Elle](https://github.com/jepsen-io/elle) (Adya-anomaly
  detection) via the [`elle-cli`](https://github.com/ligurio/elle-cli)
  standalone uberjar, over a Jepsen op-map JSON history.

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

## Layout

| Path | What |
|------|------|
| `src/dst.eigs` | M1: single-register store (correct + torn) + cooperative-task DST; emits a Porcupine JSON history |
| `src/txn_dst.eigs` | M2: multi-key list-append transactions (correct SI + dirty) + DST; emits a Jepsen op-map JSON history |
| `oracle/check.go` | M1's external Porcupine linearizability oracle (`OK`/`ILLEGAL`) |
| `test/run.sh` | M1 gate: builds the oracle, sweeps seeds, asserts determinism + replay |
| `test/run_txn.sh` | M2 gate: grades correct/dirty with Elle (`elle-cli`), asserts the anomaly replays |
| `FINDINGS.md` | The gap ledger — every language/runtime observation, filed upstream not worked around |
| `.devcontainer/` | Pinned EigenScript (`EIGS_REF`) + Go toolchain; the same image CI runs |
