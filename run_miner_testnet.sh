#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${ROOT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  . "${ENV_FILE}"
  set +a
fi
RPC_URL=${RPC_URL:-https://testnet.ama.one}
TARGET_BITS=${TARGET_BITS:-20}
PRINT_EVERY=${PRINT_EVERY:-1}
MAX_ITERS=${MAX_ITERS:-0}
HASH_ALGO=${HASH_ALGO:-blake3}
NONCE_START=${NONCE_START:-}
SUBMIT=${SUBMIT:-0}
TT_DEVICE_ID=${TT_DEVICE_ID:-}

export RPC_URL TARGET_BITS PRINT_EVERY MAX_ITERS HASH_ALGO NONCE_START SUBMIT TT_DEVICE_ID
export MINER=1

exec "${ROOT_DIR}/run_riscv_validate.sh"
