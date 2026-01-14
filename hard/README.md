# Hard Track - Execution Guide (Challenge A)

Goal: deliver the fastest correct MatMul solver on the RISC-V Blackhole p150a environment. Primary score is latency; throughput and correctness are also scored.

## Source requirements (from hackathon docs)

- Workload: MatMul with fixed matrix sizes and required precision (details via API).
- Output: execution metrics + result hash.
- Caching is allowed as long as inputs are not modified.
- Optimized libraries are allowed (BLIS/OpenBLAS/TVM/custom kernels).

## uPoW MatMul spec (from Amadeus node implementation)

- Seed size: 240 bytes (epoch + segment VR hash + keys + nonce).
- A: 16 x 50240 (u8)
- B: 50240 x 16 (i8)
- C: 16 x 16 (i32), 1024 bytes.
- Solution = seed || C (1264 bytes).

## Minimal workflow

1. Request API key on TAIKAI/Discord.
2. Fetch workload spec + input format.
3. Implement parser for official input format.
4. Run locally on simulator or provided instance and measure.
5. Produce JSON metrics and output hash.
6. Submit results via provided API.

If no hackathon endpoint is available, you can still generate the uPoW seed
from the public RPC and run locally. See `hard/matmul/README.md`.

## Baseline in this repo

- `hard/matmul/`: C++ baseline + benchmark harness.
- `hard/submit/submit_results.py`: placeholder submission helper.

## Optimization checklist

- Block/tile sizes fit per-core SRAM (1.5MB) and L1/L2 behavior.
- Pack A/B tiles into contiguous buffers for reuse.
- Vectorize inner loop (RVV if available).
- Use multi-threading across cores; avoid false sharing.
- Pin threads or set affinity if runtime supports it.
- Use `-O3` plus target-specific flags (`-march=rv64gcv`, etc.).

## Validation

- Verify output hash against reference.
- Record compiler flags, block sizes, and environment details for submission.
