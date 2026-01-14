# Amadeus Hack - Quick Run

This repo contains the hard-track MatMul solver and helper scripts. The judges can run the multi-run benchmark from the repo root.

## Quick benchmark (x86_64, multi-run)

```bash
./benchmark.sh --runs 5
```

Alias:

```bash
./benchmark_x86.sh --runs 5
```

The script will:
- Generate a uPoW seed (requires Node 18+ and internet), or use an existing seed file.
- Build the `matmul` binary.
- Run the uPoW matmul multiple times.
- Print average and stddev for `elapsed_ms` and `gflops`.

## If Node 18+ is NOT available on the instance

Generate the seed hex on your local machine, then pass it to the benchmark:

```bash
cd hard/matmul/scripts
npm install
node build_seed.mjs --generate --rpc https://nodes.amadeus.bot --out ../seed.bin
```

Copy the `seed_hex=...` value and run:

```bash
SEED_HEX=... ./benchmark.sh --runs 5
```

## RISC-V version

Requires a RISC-V toolchain and a runner (e.g., `qemu-riscv64` or a Tensix simulator).

```bash
./benchmark_riscv.sh --runs 5
```

The RISC-V script defaults to `TT_BAREMETAL=1` to avoid dynamic memory and file I/O
when running inside the Tensix simulator. To compile the full host-style binary:

```bash
TT_BAREMETAL=0 ./benchmark_riscv.sh --runs 5
```

Use a custom runner:

```bash
RISCV_RUNNER=/path/to/runner RISCV_RUNNER_ARGS="--flag value" ./benchmark_riscv.sh --runs 5
```

By default, the RISC-V script runs with `--no-output` to avoid filesystem calls in bare-metal
environments. To write `solution.bin`, pass:

```bash
./benchmark_riscv.sh --runs 5 --write-output
```

Note: the bare-metal build embeds the seed at compile time (via `TT_SEED_HEX`)
and can also read `SEED_HEX` from the environment if program arguments are not
forwarded by the simulator.

To set the CPU frequency for cycle-based timing (default 1 GHz):

```bash
TT_CPU_HZ=1500000000 ./benchmark_riscv.sh --runs 1
```

If the simulator supports `rdcycle`, enable it explicitly:

```bash
TT_USE_RDCYCLE=1 ./benchmark_riscv.sh --runs 1
```

If you see `Illegal instruction`, keep `TT_USE_RDCYCLE=0`. In this mode the
binary reports `elapsed_cycles` (may be zero) and the script falls back to host
wall-clock timing for `elapsed_ms/gflops`.

## RISC-V diagnostics

Generate a full simulator diagnostic bundle (profile + trace):

```bash
./testing.sh
```

## Useful options (all scripts)

- Use a different RPC:
  ```bash
  RPC_URL=https://testnet.ama.one ./benchmark.sh --runs 5
  ```
- Skip rebuild if already compiled:
  ```bash
  ./benchmark.sh --runs 5 --no-build
  ```
- Use an existing seed file:
  ```bash
  ./benchmark.sh --runs 5 --seed-bin hard/matmul/seed.bin
  ```
