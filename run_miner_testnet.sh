#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
BIN="${MATMUL_DIR}/build_riscv/matmul_riscv"

RPC_URL=${RPC_URL:-https://testnet.ama.one}
TARGET_BITS=${TARGET_BITS:-20}
PRINT_EVERY=${PRINT_EVERY:-1}
MAX_ITERS=${MAX_ITERS:-0}
HASH_ALGO=${HASH_ALGO:-blake3}
NONCE_START=${NONCE_START:-}
RUNS=${RUNS:-1}
SUBMIT=${SUBMIT:-0}

if [[ ! -f "${BIN}" ]] || ! grep -aq "solution_hex=" "${BIN}"; then
  echo ">> Building RISC-V binary (one-time)..."
  NO_BUILD=0 TT_BAREMETAL=1 RUNS=1 "${ROOT_DIR}/benchmark_riscv.sh" --runs 1
fi

export RPC_URL TARGET_BITS PRINT_EVERY MAX_ITERS HASH_ALGO NONCE_START RUNS SUBMIT
export MINER=1
export NO_BUILD=1

exec "${ROOT_DIR}/run_riscv_validate.sh"
