# Bonus - zkVerify Proof Demo

Goal: provide a zk proof that a MatMul result is correct and show verification. This folder includes a tiny Circom circuit (2x2) as a minimal demo.

## Build proof (local demo)

Prereqs:
- circom
- snarkjs
- a PTAU file (e.g. `powersOfTau28_hez_final_10.ptau`)

```bash
PTAU=path/to/powersOfTau28_hez_final_10.ptau ./scripts/prove.sh
```

This produces:
- `build/proof.json`
- `build/public.json`
- `build/verification_key.json`

## Hook into zkVerify

Use zkVerify's SDK/bridge to submit the proof and verify on-chain or via their verifier. Replace the 2x2 circuit with the official matmul workload once specs are published.

## Recommended next step

- Extend the circuit to match the official input shape (or hash commitments to scale).
- Prove the hash of the full MatMul output, not the full matrix, to keep constraints small.
