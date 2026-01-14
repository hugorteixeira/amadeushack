#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-https://nodes.amadeus.bot}
OUT_DIR=${OUT_DIR:-..}
SEED_OUT=${SEED_OUT:-${OUT_DIR}/seed.bin}
SOLUTION_OUT=${SOLUTION_OUT:-${OUT_DIR}/solution.bin}
VALIDATE_URL=${VALIDATE_URL:-}
SKIP_SEED=${SKIP_SEED:-0}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ "${SKIP_SEED}" == "0" ]]; then
  cd "${SCRIPT_DIR}"

  if [[ ! -f package.json ]]; then
    echo "Missing package.json in ${SCRIPT_DIR}" >&2
    exit 1
  fi

  if [[ ! -d node_modules ]]; then
    npm install
  fi

  node build_seed.mjs --generate --rpc "${RPC_URL}" --out "${SEED_OUT}"
else
  if [[ ! -f "${SEED_OUT}" ]]; then
    echo "Missing seed file: ${SEED_OUT}" >&2
    exit 1
  fi
fi

cd "${MATMUL_DIR}"
make
./matmul --upow --seed-path "${SEED_OUT}" --output "${SOLUTION_OUT}"

bytes=$(wc -c < "${SOLUTION_OUT}" | tr -d ' ')
echo "solution=${SOLUTION_OUT} (${bytes} bytes)"

echo "Tip: validate on a local testnet node via /api/upow/validate"
if [[ -n "${VALIDATE_URL}" ]]; then
  curl --data-binary @"${SOLUTION_OUT}" "${VALIDATE_URL}"
fi
