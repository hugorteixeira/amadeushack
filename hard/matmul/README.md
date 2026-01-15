# Hard Track - MatMul (TTNN)

This folder provides the TTNN-based uPoW MatMul runner. Simulator and CPU-only
baselines are removed; only TT-metal/TTNN is supported.

## uPoW MatMul spec (Amadeus validator format)

Based on the `BIC.Sol` and `sol_freivalds` implementation:

- Seed size: 240 bytes (epoch + segment VR hash + keys + nonce).
- A: 16 x 50240 (u8)
- B: 50240 x 16 (i8)
- C: 16 x 16 (i32) -> 1024 bytes
- Solution = seed || C (1264 bytes)

The TTNN runner builds `solution = seed || C` and can print `solution_hex` for
the validator pipeline.

## Dependencies

- TT-metal/TTNN installed on the host.
- Python 3.10+ with `blake3` and `numpy` (`pip install -r scripts/requirements.txt`).

## Generate seed via RPC

This uses the public RPC to fetch `epoch` and `segment_vr_hash`, then builds the 240-byte seed locally.
Requires Node.js 18+ for `fetch`.

```bash
cd hard/matmul/scripts
npm install
node build_seed.mjs --generate --rpc https://testnet.ama.one --out ../seed.bin
```

If you already have a Base58 seed:

```bash
node build_seed.mjs --seed-base58 <SEED_BASE58> --rpc https://testnet.ama.one --out ../seed.bin
```

## Run the TTNN solver

```bash
python3 scripts/ttnn_upow.py --seed-bin seed.bin --print-solution --output build_ttnn/solution.bin
```

Select a board with `TT_DEVICE_ID=0` (default 0).

## One-shot validation (repo root)

```bash
./run_riscv_validate.sh
```

Override defaults if needed:

```bash
RPC_URL=https://testnet.ama.one VALIDATE_URL=https://testnet.ama.one/api/upow/validate ./run_riscv_validate.sh
```

Submit on-chain (requires wallet seed, not API key):

```bash
AMA_SEED_BASE58=... SUBMIT=1 ./run_riscv_validate.sh
```

## Miner loop output

```bash
./run_miner_testnet.sh
```
