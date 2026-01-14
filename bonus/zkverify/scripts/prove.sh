#!/usr/bin/env bash
set -euo pipefail

CIRCUIT=circuits/matmul_2x2.circom
OUT_DIR=build
PTAU=${PTAU:-powersOfTau28_hez_final_10.ptau}

mkdir -p "$OUT_DIR"

circom "$CIRCUIT" --r1cs --wasm --sym -o "$OUT_DIR"

snarkjs groth16 setup "$OUT_DIR"/matmul_2x2.r1cs "$PTAU" "$OUT_DIR"/matmul_2x2_0000.zkey
snarkjs zkey contribute "$OUT_DIR"/matmul_2x2_0000.zkey "$OUT_DIR"/matmul_2x2_final.zkey --name="1st Contributor" -v
snarkjs zkey export verificationkey "$OUT_DIR"/matmul_2x2_final.zkey "$OUT_DIR"/verification_key.json

cat > "$OUT_DIR"/input.json <<'JSON'
{
  "a00": 1,
  "a01": 2,
  "a10": 3,
  "a11": 4,
  "b00": 5,
  "b01": 6,
  "b10": 7,
  "b11": 8
}
JSON

node "$OUT_DIR"/matmul_2x2_js/generate_witness.js "$OUT_DIR"/matmul_2x2_js/matmul_2x2.wasm "$OUT_DIR"/input.json "$OUT_DIR"/witness.wtns

snarkjs groth16 prove "$OUT_DIR"/matmul_2x2_final.zkey "$OUT_DIR"/witness.wtns "$OUT_DIR"/proof.json "$OUT_DIR"/public.json
snarkjs groth16 verify "$OUT_DIR"/verification_key.json "$OUT_DIR"/public.json "$OUT_DIR"/proof.json
