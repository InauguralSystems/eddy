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

- **Milestone 1 (this):** single-register linearizability, graded by
  [Porcupine](https://github.com/anishathalye/porcupine) (Wing-Gong check,
  BSD-3, pure Go) via the ~90-line harness in [`oracle/check.go`](oracle/check.go).
- **Later:** multi-key transactions graded by [Elle](https://github.com/jepsen-io/elle)
  (Adya-anomaly detection) via `elle-cli`, reusing the same history format.

## The determinism contract

- The whole run is reproducible from **one integer seed**. Same seed ⇒
  byte-identical history ⇒ the checker returns the same verdict.
- The interleaving comes entirely from `task_sched_seed`; client op scripts are
  fixed, so the scheduler is the only variable.
- Histories record **zero tape `N` records** (the task layer is deterministic by
  construction), so `EIGS_TRACE`/`EIGS_REPLAY` reproduces any run — including a
  found violation — byte-for-byte.

## Milestone 1 — what it proves

A single register with three cooperative-task clients under a seeded schedule:

- `correct` store (atomic get/put) is **linearizable for every seed**.
- `torn` store (a non-atomic write, `reg:=0; yield; reg:=v`, visible to a
  concurrent reader) is **caught as non-linearizable** — the DST finds an
  exposing interleaving by sweeping seeds, and the violation replays
  byte-for-byte from its seed.

```sh
# one run: store -> JSON history -> external oracle verdict
eigenscript src/dst.eigs 2 torn | oracle/check     # -> ILLEGAL
eigenscript src/dst.eigs 2 correct | oracle/check  # -> OK

# the full gate (builds the oracle, sweeps seeds, checks determinism)
EIGS=eigenscript GO=go bash test/run.sh
```

## Layout

| Path | What |
|------|------|
| `src/dst.eigs` | The store (correct + torn variants) and the cooperative-task DST driver; emits a JSON history |
| `oracle/check.go` | The external Porcupine linearizability oracle (reads the history, prints `OK`/`ILLEGAL`) |
| `test/run.sh` | The milestone gate: builds the oracle, sweeps seeds, asserts determinism + replay |
| `FINDINGS.md` | The gap ledger — every language/runtime observation, filed upstream not worked around |
| `.devcontainer/` | Pinned EigenScript (`EIGS_REF`) + Go toolchain; the same image CI runs |
