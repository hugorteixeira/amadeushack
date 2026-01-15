# Amadeus Hack - RISC-V MatMul Solver

This repo is focused on the hard-track RISC-V MatMul solver. The main entrypoint
for judges is the RISC-V benchmark script in the repo root.

## RISC-V quick start (primary)

```bash
./benchmark_riscv.sh --runs 1
```

This builds a RISC-V binary (bare-metal by default) and runs the uPoW MatMul
inside the Tensix simulator / RISC-V runner. The output includes:

- The RISC-V program JSON (from the simulator).
- `run=... elapsed_ms=... gflops=... host_elapsed_ms=...`

Note: some simulators do not expose cycle counters. In that case, the script
falls back to host wall-clock timing (`host_elapsed_ms`) for `elapsed_ms/gflops`.

## Seed generation

If the instance does not have Node 18+, generate the seed on your local machine
and pass it as `SEED_HEX`:

```bash
cd hard/matmul/scripts
npm install
node build_seed.mjs --generate --rpc https://nodes.amadeus.bot --out ../seed.bin
```

Then run on the instance:

```bash
SEED_HEX=... ./benchmark_riscv.sh --runs 1
```

You can also use an existing seed file:

```bash
./benchmark_riscv.sh --runs 1 --seed-bin hard/matmul/seed.bin
```

## Testnet validation (one-shot)

Generate a seed, run the RISC-V solver once, and validate via the testnet
`/api/upow/validate` endpoint:

```bash
bash run_riscv_validate.sh
```

This uses the bare-metal RISC-V build and reconstructs `solution.bin` from the
`solution_hex` line printed by the solver.

Override defaults if needed:

```bash
RPC_URL=https://testnet.ama.one VALIDATE_URL=https://testnet.ama.one/api/upow/validate bash run_riscv_validate.sh
```

## RISC-V tuning and options

- Bare-metal build (default, avoids file I/O):
  ```bash
  TT_BAREMETAL=1 ./benchmark_riscv.sh --runs 1
  ```
- Full host-style binary (if your runner supports syscalls):
  ```bash
  TT_BAREMETAL=0 ./benchmark_riscv.sh --runs 1
  ```
- Progress output (prints `row=1..16` on stderr):
  ```bash
  TT_PROGRESS=1 ./benchmark_riscv.sh --runs 1
  ```
- If `rdcycle` is supported by your simulator:
  ```bash
  TT_USE_RDCYCLE=1 ./benchmark_riscv.sh --runs 1
  ```
- CPU frequency for cycle-based timing (default 1 GHz):
  ```bash
  TT_CPU_HZ=1500000000 ./benchmark_riscv.sh --runs 1
  ```
- Write `solution.bin`:
  ```bash
  ./benchmark_riscv.sh --runs 1 --write-output
  ```
- Custom runner:
  ```bash
  RISCV_RUNNER=/path/to/runner RISCV_RUNNER_ARGS="--flag value" ./benchmark_riscv.sh --runs 1
  ```

## Challenge B (Merkle proofs)

Sources live in `hard/merkle`. Build with `make` (or set `CC`/`CXX` for RISC-V)
and run with your RISC-V runner.

## Hard Hack requirements (from developer_onboarding.pdf)

- Target: RISC-V TensTorrent-class hardware or GPU-based simulation (exact specs TBD).
- Workloads: MatMul (fixed sizes/precision) and AMA microbench tasks (conv/attention/etc).
- Output: execution metrics + correctness hash.
- Submission bundle: raw metrics, output hash, benchmark metadata (compiler flags/libs),
  plus source or compiled binary. Docker optional but recommended.
- Constraints: time/memory limits; caching allowed but inputs must be unmodified.
- Scoring: latency primary, then throughput/correctness (tie-breaks by latency, memory, timestamp).
