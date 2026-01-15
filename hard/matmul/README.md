# Hard Track - MatMul Baseline

This folder provides a minimal C++ baseline and a tiny harness to measure matmul performance and generate an output hash. Adapt the input/output format to match the official workload spec once released.

## Build

```bash
make
```

Enable OpenMP (if available):

```bash
OPENMP=1 make
```

Cross-compile example (adjust for your toolchain):

```bash
make CXX=riscv64-unknown-linux-gnu-g++ CXXFLAGS="-O3 -std=c++17 -march=rv64gcv -mabi=lp64d"
```

## Run

```bash
./matmul --m 512 --n 512 --k 512 --algo blocked --block 64 --output out.bin
python3 scripts/hash_output.py --input out.bin
```

## uPoW MatMul mode (Amadeus validator format)

Based on the `BIC.Sol` and `sol_freivalds` implementation:

- Seed size: 240 bytes (epoch + segment VR hash + keys + nonce).
- A: 16 x 50240 (u8)
- B: 50240 x 16 (i8)
- C: 16 x 16 (i32) -> 1024 bytes
- Solution = seed || C (1264 bytes)

Run with a binary seed file:

```bash
./matmul --upow --seed-path seed.bin --output solution.bin
```

Or with a hex string:

```bash
./matmul --upow --seed-hex deadbeef... --output solution.bin
```

## Generate seed via RPC (no node required)

This uses the public RPC to fetch `epoch` and `segment_vr_hash`, then builds the 240-byte seed locally.
Requires Node.js 18+ for `fetch`.

```bash
cd hard/matmul/scripts
npm install
node build_seed.mjs --generate --rpc https://nodes.amadeus.bot --out ../seed.bin
```

If you already have a Base58 seed:

```bash
node build_seed.mjs --seed-base58 <SEED_BASE58> --rpc https://nodes.amadeus.bot --out ../seed.bin
```

## One-shot validation (repo root)

Run the end-to-end RISC-V flow (seed + matmul + validate) from the repo root:

```bash
bash run_riscv_validate.sh
```

Override defaults if needed:

```bash
RPC_URL=https://testnet.ama.one VALIDATE_URL=https://testnet.ama.one/api/upow/validate bash run_riscv_validate.sh
```

Submit on-chain (requires wallet seed, not API key):

```bash
AMA_SEED_BASE58=... SUBMIT=1 bash run_riscv_validate.sh
```

## Benchmark sweep

```bash
python3 scripts/benchmark.py --m 512 --n 512 --k 512 --blocks 32,64,128 --runs 3 --output results.json
```

## Input/Output format (current stub)

- Input binary (optional): 3 int32 header (m, n, k), then A (m*k float32), then B (k*n float32).
- Output binary: same header followed by C (m*n float32).

Replace this with the official format once provided by the hackathon API.

## Next optimization steps

- Tune block sizes so tiles fit in SRAM (1.5 MB per core) and align to cache lines.
- Add packing for A/B tiles to improve locality.
- Add vectorized micro-kernel (RVV if available).
- Add threading strategy that matches core topology and avoids false sharing.
- Measure with official workload runner and lock the best configuration.
