# Amadeus Hack - TTNN MatMul Solver

This repo targets the hard-track uPoW MatMul using Tenstorrent TT-metal/TTNN.
Simulator flows have been removed; the main entrypoints run on TT hardware.

## Quick start (testnet)

```bash
./install.sh
./run_riscv_validate.sh
```

This generates the seed via RPC, runs the TTNN matmul once, and validates via
`/api/upow/validate`. `solution.bin` is reconstructed from the `solution_hex`
line printed by the TTNN runner.
`install.sh` stores keys in `.env`, which is loaded automatically by the scripts.

## Miner-style output

```bash
./run_miner_testnet.sh
```

Override target/rate settings:

```bash
TARGET_BITS=20 PRINT_EVERY=1 MAX_ITERS=1000 ./run_miner_testnet.sh
```

By default, `HASH_ALGO=blake3` is used for the bits display. You can switch to
SHA256 with `HASH_ALGO=sha256`.

## Seed generation

If you want to generate the seed manually:

```bash
cd hard/matmul/scripts
npm install
node build_seed.mjs --generate --rpc https://testnet.ama.one --out ../seed.bin
```

Then run with:

```bash
SEED_HEX=... ./run_riscv_validate.sh
```

## Submit on-chain (testnet)

```bash
AMA_SEED_BASE58=... SUBMIT=1 ./run_riscv_validate.sh
```

The submit step builds a `submit_sol` transaction against the `Epoch` contract
and calls `/api/tx/submit_and_wait`.

## Device selection

Use `TT_DEVICE_ID` to select a board index:

```bash
TT_DEVICE_ID=0 ./run_riscv_validate.sh
```

## Hard Hack requirements (from developer_onboarding.pdf)

- Target: Tenstorrent hardware (Blackhole p150a in hard track).
- Workloads: MatMul (fixed sizes/precision) and AMA microbench tasks.
- Output: execution metrics + correctness hash.
- Submission bundle: raw metrics, output hash, benchmark metadata, plus source/binary.
