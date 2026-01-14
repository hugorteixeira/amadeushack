# Execution Plan (Jan 8-15)

This plan targets completion of the Hard Track + bonuses, plus Soft Track deliverables, as fast as possible.

## Hard Track (MatMul) - Step-by-step

1. **Access and onboarding**
   - Request API key and hardware access.
   - Pull workload spec: matrix sizes, precision, input/output format.

2. **Baseline solver**
   - Implement input parser for official spec.
   - Produce correctness hash and metrics (latency/throughput).
   - Submit a first valid score quickly.

3. **Optimization loop**
   - Profile baseline to find hotspots.
   - Add tiling/packing and tune block sizes for SRAM (1.5MB/core).
   - Add RVV vectorization if available.
   - Add thread scheduling/affinity and avoid false sharing.
   - Re-benchmark and lock the best configuration.

4. **Submission packaging**
   - Record compiler flags, block sizes, and hardware info.
   - Export metrics to JSON and submit via API.

## Bonus 1 (Arweave Provenance) - Step-by-step

1. Capture output artifacts (results JSON + output binary).
2. Compute SHA-256 hashes and create provenance JSON.
3. Upload to Arweave using Turbo SDK or AR.IO API.
4. Store TX ID + hash references in final submission.

## Bonus 2 (zkVerify Proof) - Step-by-step

1. Build a minimal proof demo (2x2 or hash-commitment circuit).
2. Generate proof and verify locally.
3. Integrate zkVerify SDK/bridge for submission.
4. Provide proof artifacts + short verifier demo.

## Soft Track (Ideathon) - Step-by-step

1. Define problem + target users + value.
2. Architecture diagram with agent roles and data flow.
3. Prototype mockups and usage flow.
4. Clearly state what works now vs future features.
5. Add how Amadeus is used (uPoW, WASM, state proofs, agent identity, oracles, swarm).

## Timeline (Night of Jan 8 to Jan 15)

- **Jan 8 (Night)**: Read docs, set goals, prepare repo structure, baseline solver stub.
- **Jan 9**: Access hardware/simulator, integrate official input/output, submit first valid result.
- **Jan 10**: Optimize blocking, vectorization, threading; iterate on benchmarks.
- **Jan 11**: Run on hardware, tune parameters, finalize best score.
- **Jan 12**: Implement Arweave provenance pipeline and upload test.
- **Jan 13**: Implement zk proof demo and verification flow.
- **Jan 14**: Finalize soft track deck, diagram, and prototype; record demo notes.
- **Jan 15**: Final benchmarking, package submission, upload all deliverables.

## Risks and mitigations

- **Unknown input format**: implement adapter layer and keep compute core separate.
- **Hardware access delays**: test on simulator, keep configs versioned.
- **Proof complexity**: start with hash commitment circuit and scale later.
