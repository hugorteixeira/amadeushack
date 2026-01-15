# Hard Track - Challenge B (Merkle Proofs)

This folder contains a minimal RISC-V-friendly Merkle proof generator and verifier.
It uses BLAKE3 and is designed to run in the RISC-V simulator (bare-metal).

## Build (native)

```bash
make
```

## RISC-V build + run (manual)

Cross-compile by setting your toolchain (and optional compile-time parameters):

```bash
CC=riscv64-unknown-linux-gnu-gcc CXX=riscv64-unknown-linux-gnu-g++ \
CFLAGS="-O3 -std=c11 -DMERKLE_LEAVES=1024 -DMERKLE_PROOFS=32 -DMERKLE_ITERS=4" \
CXXFLAGS="-O3 -std=c++17 -DMERKLE_LEAVES=1024 -DMERKLE_PROOFS=32 -DMERKLE_ITERS=4" \
make
```

Run with your RISC-V runner (example):

```bash
riscv-tt-elf-run --environment user --memory-size 256m merkle
```

Use `-DMERKLE_PROGRESS=1` to print `iter=...` to stderr, and `-DMERKLE_SEED_HEX=...`
to override the default seed.
