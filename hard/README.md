# Hard Track - Execution Guide (Challenge A)

Goal: deliver the fastest correct MatMul solver on the Tenstorrent Blackhole p150a environment using TT-metal/TTNN. Primary score is latency; throughput and correctness are also scored.

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
4. Run on the provided TT hardware instance and measure.
5. Produce JSON metrics and output hash.
6. Submit results via provided API.

If no hackathon endpoint is available, you can still generate the uPoW seed
from the public RPC and run locally. See `hard/matmul/README.md`.

## Baseline in this repo

- `hard/matmul/`: TTNN uPoW MatMul runner.
- `hard/submit/submit_results.py`: placeholder submission helper.
- `hard/merkle/`: Challenge B baseline (not wired to TTNN in this repo).

## Optimization checklist

- Keep A/B tiles aligned with TTNN tile sizes (pad M/N).
- Use device-local memory configs for matmul inputs/outputs.
- Avoid host-device copies inside the nonce loop when possible.
- Pin device selection (`TT_DEVICE_ID`) and reuse device handles.

## Validation

- Verify output hash against reference.
- Record compiler flags, block sizes, and environment details for submission.
