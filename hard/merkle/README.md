# Hard Track - Challenge B (Merkle Proofs)

This folder contains a minimal RISC-V-friendly Merkle proof generator and verifier.
It uses BLAKE3 and is designed to run in the RISC-V simulator (bare-metal).

## Build (native)

```bash
make
```

## RISC-V build + run

Use the repo-level script:

```bash
./benchmark_riscv_merkle.sh --runs 1
```

## Parameters

You can customize the tree size and proof count via env vars:

```bash
MERKLE_LEAVES=1024 MERKLE_PROOFS=32 MERKLE_ITERS=4 ./benchmark_riscv_merkle.sh --runs 1
```

To show progress (prints `iter=...` to stderr):

```bash
MERKLE_PROGRESS=1 ./benchmark_riscv_merkle.sh --runs 1
```
