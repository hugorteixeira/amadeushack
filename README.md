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

## RISC-V diagnostics

Generate a full simulator diagnostic bundle (profile + trace):

```bash
./testing.sh
```

## x86_64 reference (optional)

The x86_64 path is a secondary reference only:

```bash
./benchmark.sh --runs 5
```

Alias:

```bash
./benchmark_x86.sh --runs 5
```
