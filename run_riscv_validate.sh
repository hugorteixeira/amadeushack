#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${ROOT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  . "${ENV_FILE}"
  set +a
fi

RUNS=${RUNS:-1}
RPC_URL=${RPC_URL:-https://testnet.ama.one}
VALIDATE_URL=${VALIDATE_URL:-${RPC_URL}/api/upow/validate}
SEED_HEX=${SEED_HEX:-}
SEED_BIN=${SEED_BIN:-}
SEED_BASE58=${SEED_BASE58:-${AMA_SEED_BASE58:-}}
NO_BUILD=${NO_BUILD:-0}
RISCV_RUNNER=${RISCV_RUNNER:-}
RISCV_RUNNER_ARGS=${RISCV_RUNNER_ARGS:-}
SUBMIT=${SUBMIT:-0}
MINER=${MINER:-0}
TARGET_BITS=${TARGET_BITS:-0}
MAX_ITERS=${MAX_ITERS:-0}
PRINT_EVERY=${PRINT_EVERY:-1}
HASH_ALGO=${HASH_ALGO:-blake3}
NONCE_START=${NONCE_START:-}
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
SCRIPT_DIR="${MATMUL_DIR}/scripts"
BUILD_DIR="${MATMUL_DIR}/build_riscv"
SOLUTION_OUT="${BUILD_DIR}/solution.bin"
SOLUTION_HEX=""
FOUND=0
SEED_PREFIX_HEX=""
NONCE_HI_HEX=""
NONCE_VAL=0

if [[ -z "${SEED_BIN}" ]]; then
  SEED_BIN="${MATMUL_DIR}/seed.bin"
fi

log() {
  echo ">> $*"
}

now_ns() {
  local val=""
  if command -v python3 >/dev/null 2>&1; then
    val=$(python3 - <<'PY'
import time
print(time.time_ns())
PY
)
  elif command -v python >/dev/null 2>&1; then
    val=$(python - <<'PY'
import time
print(int(time.time() * 1_000_000_000))
PY
)
  elif command -v perl >/dev/null 2>&1; then
    val=$(perl -MTime::HiRes -e 'printf "%.0f", Time::HiRes::time()*1e9')
  elif [[ -r /proc/uptime ]]; then
    val=$(awk '{printf "%.0f", $1*1000000000}' /proc/uptime)
  elif command -v date >/dev/null 2>&1; then
    val=$(date +%s%N 2>/dev/null | tr -cd '0-9')
  fi
  if [[ -z "${val}" ]]; then
    echo 0
  else
    echo "${val}"
  fi
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
  if [[ -n "${SEED_BASE58}" ]]; then
    node build_seed.mjs --seed-base58 "${SEED_BASE58}" --rpc "${RPC_URL}" --out "${SEED_BIN}"
  else
    node build_seed.mjs --generate --rpc "${RPC_URL}" --out "${SEED_BIN}"
  fi
}

load_seed_hex() {
  if [[ -n "${SEED_HEX}" ]]; then
    return 0
  fi
  if [[ ! -f "${SEED_BIN}" ]]; then
    echo "Missing seed file: ${SEED_BIN}" >&2
    exit 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    SEED_HEX=$(python3 - "${SEED_BIN}" <<'PY'
import sys
from pathlib import Path
print(Path(sys.argv[1]).read_bytes().hex())
PY
)
  elif command -v xxd >/dev/null 2>&1; then
    SEED_HEX=$(xxd -p -c 100000 "${SEED_BIN}" | tr -d '\n')
  elif command -v hexdump >/dev/null 2>&1; then
    SEED_HEX=$(hexdump -v -e '1/1 "%02x"' "${SEED_BIN}")
  elif command -v od >/dev/null 2>&1; then
    SEED_HEX=$(od -An -tx1 -v "${SEED_BIN}" | tr -d ' \n')
  else
    echo "Failed to read seed hex (install python3/xxd/hexdump/od)." >&2
    exit 1
  fi
}

init_nonce_state() {
  load_seed_hex
  if [[ ${#SEED_HEX} -ne 480 ]]; then
    echo "Seed hex length ${#SEED_HEX} is invalid (expected 480)." >&2
    exit 1
  fi
  SEED_PREFIX_HEX="${SEED_HEX:0:456}"
  NONCE_HI_HEX="${SEED_HEX:456:8}"
  local nonce_low_hex="${SEED_HEX:464:16}"
  if [[ -n "${NONCE_START}" ]]; then
    NONCE_VAL="${NONCE_START}"
  else
    NONCE_VAL=$(NONCE_LOW_HEX="${nonce_low_hex}" python3 - <<'PY'
import os
nonce_hex = os.environ.get("NONCE_LOW_HEX", "")
nonce = int.from_bytes(bytes.fromhex(nonce_hex), "little")
print(nonce)
PY
)
  fi
}

build_seed_hex_for_nonce() {
  local nonce_hex
  nonce_hex=$(NONCE_VAL="${NONCE_VAL}" python3 - <<'PY'
import os
nonce = int(os.environ.get("NONCE_VAL", "0"))
print(nonce.to_bytes(8, "little").hex())
PY
)
  echo "${SEED_PREFIX_HEX}${NONCE_HI_HEX}${nonce_hex}"
}

hash_bits() {
  local sol_hex="$1"
  if [[ "${HASH_ALGO}" == "blake3" && -n "${sol_hex}" ]] && command -v node >/dev/null 2>&1; then
    local bits
    bits=$(
      cd "${SCRIPT_DIR}" && SOLUTION_HEX="${sol_hex}" node --input-type=module - <<'NODE'
import { blake3 } from '@noble/hashes/blake3'
const hex = process.env.SOLUTION_HEX || ''
const bytes = Buffer.from(hex, 'hex')
const digest = blake3(bytes)
let bits = 0
for (const b of digest) {
  if (b === 0) {
    bits += 8
  } else {
    let lead = 0
    for (let mask = 0x80; mask > 0; mask >>= 1) {
      if (b & mask) break
      lead += 1
    }
    bits += lead
    break
  }
}
console.log(bits)
NODE
    ) || bits=""
    if [[ -n "${bits}" ]]; then
      echo "${bits}"
      return 0
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    SOLUTION_HEX="${sol_hex}" python3 - <<'PY'
import os, hashlib
hex_str = os.environ.get("SOLUTION_HEX", "")
data = bytes.fromhex(hex_str)
h = hashlib.sha256(data).digest()
bits = 0
for b in h:
    if b == 0:
        bits += 8
        continue
    bits += 8 - b.bit_length()
    break
print(bits)
PY
  else
    echo 0
  fi
}

run_riscv() {
  local seed_hex_override="${1:-}"
  local -a args
  args=(--runs "${RUNS}")
  if [[ "${NO_BUILD}" == "1" ]]; then
    args+=(--no-build)
  fi
  if [[ -n "${seed_hex_override}" ]]; then
    args+=(--seed-hex "${seed_hex_override}")
  elif [[ -n "${SEED_HEX}" ]]; then
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
  if [[ "${MINER}" == "1" && "${TARGET_BITS}" != "0" && "${FOUND}" != "1" ]]; then
    log "Skipping validation (no solution met TARGET_BITS)."
    return 0
  fi
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

submit_solution() {
  if [[ "${SUBMIT}" != "1" ]]; then
    return 0
  fi
  if [[ "${MINER}" == "1" && "${TARGET_BITS}" != "0" && "${FOUND}" != "1" ]]; then
    log "Skipping submit (no solution met TARGET_BITS)."
    return 0
  fi
  if [[ -z "${SEED_BASE58}" ]]; then
    echo "SUBMIT=1 requires SEED_BASE58 or AMA_SEED_BASE58 for signing." >&2
    exit 1
  fi
  need_cmd node
  local submit_script="${SCRIPT_DIR}/submit_upow.mjs"
  if [[ ! -f "${submit_script}" ]]; then
    echo "Missing submit script: ${submit_script}" >&2
    exit 1
  fi
  log "Submitting solution via /api/tx/submit_and_wait..."
  AMA_SEED_BASE58="${SEED_BASE58}" RPC_URL="${RPC_URL}" SOLUTION_BIN="${SOLUTION_OUT}" \
    node "${submit_script}"
}

ensure_seed
if [[ "${MINER}" == "1" ]]; then
  init_nonce_state
  attempts=0
  best_bits=0
  start_ns=$(now_ns)
  while true; do
    attempts=$((attempts + 1))
    seed_hex_iter=$(build_seed_hex_for_nonce)
    RUNS=1 run_riscv "${seed_hex_iter}"
    bits=$(hash_bits "${SOLUTION_HEX}")
    if [[ -z "${bits}" ]]; then
      bits=0
    fi
    if [[ "${bits}" -gt "${best_bits}" ]]; then
      best_bits="${bits}"
    fi
    now_ns_val=$(now_ns)
    elapsed_sec=$(awk -v s="${start_ns}" -v e="${now_ns_val}" 'BEGIN{printf "%.3f", (e-s)/1000000000.0}')
    rate=$(awk -v n="${attempts}" -v s="${elapsed_sec}" 'BEGIN{if(s==0){printf "0.000"} else {printf "%.3f", n/s}}')
    if (( attempts % PRINT_EVERY == 0 )); then
      echo "hashes=${attempts} rate_h/s=${rate} best=${best_bits} bits=${bits} nonce=${NONCE_VAL}"
    fi
    if [[ "${TARGET_BITS}" != "0" && "${bits}" -ge "${TARGET_BITS}" ]]; then
      FOUND=1
      echo "FOUND! nonce=${NONCE_VAL} bits=${bits} rate_avg_h/s=${rate}"
      break
    fi
    if [[ "${MAX_ITERS}" != "0" && "${attempts}" -ge "${MAX_ITERS}" ]]; then
      break
    fi
    NONCE_VAL=$((NONCE_VAL + 1))
  done
  validate_solution
  submit_solution
else
  run_riscv
  validate_solution
  submit_solution
fi
