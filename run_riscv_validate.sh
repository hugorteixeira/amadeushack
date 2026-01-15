#!/usr/bin/env bash
set -euo pipefail

RUNS=${RUNS:-1}
RPC_URL=${RPC_URL:-https://testnet.ama.one}
VALIDATE_URL=${VALIDATE_URL:-${RPC_URL}/api/upow/validate}
SEED_HEX=${SEED_HEX:-}
SEED_BIN=${SEED_BIN:-}
NO_BUILD=${NO_BUILD:-0}
RISCV_RUNNER=${RISCV_RUNNER:-}
RISCV_RUNNER_ARGS=${RISCV_RUNNER_ARGS:-}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
SCRIPT_DIR="${MATMUL_DIR}/scripts"
BUILD_DIR="${MATMUL_DIR}/build_riscv"
SOLUTION_OUT="${BUILD_DIR}/solution.bin"
SOLUTION_HEX=""

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
  args=(--runs "${RUNS}")
  if [[ "${NO_BUILD}" == "1" ]]; then
    args+=(--no-build)
  fi
  if [[ -n "${SEED_HEX}" ]]; then
    args+=(--seed-hex "${SEED_HEX}")
  else
    args+=(--seed-bin "${SEED_BIN}")
  fi
  log "Running RISC-V benchmark (TT_BAREMETAL=1, TT_PRINT_SOLUTION=1)..."
  local runner_args="${RISCV_RUNNER_ARGS}"
  if [[ -z "${RISCV_RUNNER}" && -x /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run ]]; then
    if [[ -n "${runner_args}" ]]; then
      runner_args+=" "
    fi
    runner_args+="--env-set TT_PRINT_SOLUTION=1"
  elif [[ "${RISCV_RUNNER}" == "/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run" ]]; then
    if [[ -n "${runner_args}" ]]; then
      runner_args+=" "
    fi
    runner_args+="--env-set TT_PRINT_SOLUTION=1"
  fi
  local output_file
  output_file=$(mktemp)
  TT_BAREMETAL=1 TT_PRINT_SOLUTION=1 RISCV_RUNNER="${RISCV_RUNNER}" RISCV_RUNNER_ARGS="${runner_args}" \
    "${ROOT_DIR}/benchmark_riscv.sh" "${args[@]}" 2>&1 | tee "${output_file}"
  SOLUTION_HEX=$(sed -n 's/^solution_hex=//p' "${output_file}" | tail -n 1 | tr -d '\r\n')
  rm -f "${output_file}"
  if [[ -z "${SOLUTION_HEX}" ]]; then
    echo "Failed to capture solution_hex from RISC-V output." >&2
    exit 1
  fi
}

write_solution_bin() {
  if [[ -z "${SOLUTION_HEX}" ]]; then
    echo "Missing solution hex data." >&2
    exit 1
  fi
  if (( ${#SOLUTION_HEX} % 2 != 0 )); then
    echo "Invalid solution hex length: ${#SOLUTION_HEX}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${SOLUTION_OUT}")"
  if command -v python3 >/dev/null 2>&1; then
    SOLUTION_HEX="${SOLUTION_HEX}" SOLUTION_OUT="${SOLUTION_OUT}" python3 - <<'PY'
import os
hex_str = os.environ["SOLUTION_HEX"].strip()
out_path = os.environ["SOLUTION_OUT"]
with open(out_path, "wb") as f:
    f.write(bytes.fromhex(hex_str))
PY
  elif command -v xxd >/dev/null 2>&1; then
    printf "%s" "${SOLUTION_HEX}" | xxd -r -p > "${SOLUTION_OUT}"
  else
    echo "Missing python3 or xxd to build solution.bin" >&2
    exit 1
  fi
}

validate_solution() {
  need_cmd curl
  write_solution_bin
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
