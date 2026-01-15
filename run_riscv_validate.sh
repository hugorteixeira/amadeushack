#!/usr/bin/env bash
set -euo pipefail

RUNS=${RUNS:-1}
RPC_URL=${RPC_URL:-https://testnet.ama.one}
VALIDATE_URL=${VALIDATE_URL:-${RPC_URL}/api/upow/validate}
SEED_HEX=${SEED_HEX:-}
SEED_BIN=${SEED_BIN:-}
NO_BUILD=${NO_BUILD:-0}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
SCRIPT_DIR="${MATMUL_DIR}/scripts"
BUILD_DIR="${MATMUL_DIR}/build_riscv"
SOLUTION_OUT="${BUILD_DIR}/solution.bin"

if [[ -z "${SEED_BIN}" ]]; then
  SEED_BIN="${MATMUL_DIR}/seed.bin"
fi

log() {
  echo ">> $*"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

ensure_seed() {
  if [[ -n "${SEED_HEX}" ]]; then
    return 0
  fi
  if [[ -f "${SEED_BIN}" ]]; then
    log "Using seed file: ${SEED_BIN}"
    return 0
  fi
  need_cmd node
  local node_version
  node_version=$(node -v | tr -d 'v')
  local node_major=${node_version%%.*}
  if [[ "${node_major}" -lt 18 ]]; then
    echo "Node.js ${node_version} is too old. Install Node 18+ or set SEED_HEX." >&2
    exit 1
  fi
  log "Generating seed via RPC: ${RPC_URL}"
  cd "${SCRIPT_DIR}"
  if [[ ! -d node_modules ]]; then
    log "Installing Node deps (requires network)..."
    npm install
  fi
  node build_seed.mjs --generate --rpc "${RPC_URL}" --out "${SEED_BIN}"
}

run_riscv() {
  local -a args
  args=(--runs "${RUNS}" --write-output)
  if [[ "${NO_BUILD}" == "1" ]]; then
    args+=(--no-build)
  fi
  if [[ -n "${SEED_HEX}" ]]; then
    args+=(--seed-hex "${SEED_HEX}")
  else
    args+=(--seed-bin "${SEED_BIN}")
  fi
  log "Running RISC-V benchmark (TT_BAREMETAL=0)..."
  TT_BAREMETAL=0 "${ROOT_DIR}/benchmark_riscv.sh" "${args[@]}"
}

validate_solution() {
  need_cmd curl
  if [[ ! -f "${SOLUTION_OUT}" ]]; then
    echo "Missing solution file: ${SOLUTION_OUT}" >&2
    exit 1
  fi
  local bytes
  bytes=$(wc -c < "${SOLUTION_OUT}" | tr -d ' ')
  log "Validating solution (${bytes} bytes) at ${VALIDATE_URL}"
  curl --data-binary @"${SOLUTION_OUT}" "${VALIDATE_URL}"
  echo
}

ensure_seed
run_riscv
validate_solution
