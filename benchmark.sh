#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "bash is required to run this script." >&2
  exit 1
fi
set -euo pipefail

RUNS=${RUNS:-5}
RPC_URL=${RPC_URL:-https://nodes.amadeus.bot}
SEED_HEX=${SEED_HEX:-}
SEED_BIN=${SEED_BIN:-}
NO_BUILD=${NO_BUILD:-0}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
SCRIPT_DIR="${MATMUL_DIR}/scripts"

if [[ -z "${SEED_BIN}" ]]; then
  SEED_BIN="${MATMUL_DIR}/seed.bin"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      RUNS="$2"
      shift 2
      ;;
    --rpc)
      RPC_URL="$2"
      shift 2
      ;;
    --seed-hex)
      SEED_HEX="$2"
      shift 2
      ;;
    --seed-bin)
      SEED_BIN="$2"
      shift 2
      ;;
    --no-build)
      NO_BUILD=1
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${SEED_HEX}" ]]; then
  if [[ -f "${SEED_BIN}" ]]; then
    echo "Using seed file: ${SEED_BIN}"
  else
    if ! command -v node >/dev/null 2>&1; then
      echo "Node.js not found. Provide SEED_HEX or SEED_BIN." >&2
      exit 1
    fi

    NODE_VERSION=$(node -v | tr -d 'v')
    NODE_MAJOR=${NODE_VERSION%%.*}
    if [[ "${NODE_MAJOR}" -lt 18 ]]; then
      echo "Node.js ${NODE_VERSION} is too old. Install Node 18+ or provide SEED_HEX/SEED_BIN." >&2
      exit 1
    fi

    cd "${SCRIPT_DIR}"
    if [[ ! -d node_modules ]]; then
      npm install
    fi

    seed_output=$(node build_seed.mjs --generate --rpc "${RPC_URL}" --out "${SEED_BIN}")
    echo "${seed_output}"
    SEED_HEX=$(echo "${seed_output}" | grep -m1 "^seed_hex=" | cut -d= -f2-)
    if [[ -z "${SEED_HEX}" ]]; then
      echo "seed_hex not found in build_seed output" >&2
      exit 1
    fi
  fi
fi

if [[ "${NO_BUILD}" != "1" ]]; then
  make -C "${MATMUL_DIR}"
fi

ELAPSED_FILE=$(mktemp)
GFLOPS_FILE=$(mktemp)
trap 'rm -f "${ELAPSED_FILE}" "${GFLOPS_FILE}"' EXIT

for i in $(seq 1 "${RUNS}"); do
  if [[ -n "${SEED_HEX}" ]]; then
    output=$("${MATMUL_DIR}/matmul" --upow --seed-hex "${SEED_HEX}" --output "${MATMUL_DIR}/solution.bin")
  else
    output=$("${MATMUL_DIR}/matmul" --upow --seed-path "${SEED_BIN}" --output "${MATMUL_DIR}/solution.bin")
  fi

  echo "${output}"
  elapsed=$(echo "${output}" | sed -n 's/.*"elapsed_ms":\([0-9.]*\).*/\1/p')
  gflops=$(echo "${output}" | sed -n 's/.*"gflops":\([0-9.]*\).*/\1/p')
  if [[ -z "${elapsed}" || -z "${gflops}" ]]; then
    echo "Failed to parse benchmark output" >&2
    exit 1
  fi
  echo "${elapsed}" >> "${ELAPSED_FILE}"
  echo "${gflops}" >> "${GFLOPS_FILE}"
  echo "run=${i} elapsed_ms=${elapsed} gflops=${gflops}"
done

stats() {
  awk 'NR==1{min=max=$1} {sum+=$1; sumsq+=$1*$1; if($1<min)min=$1; if($1>max)max=$1} END{mean=sum/NR; var=sumsq/NR-mean*mean; if(var<0)var=0; printf "avg=%.4f std=%.4f min=%.4f max=%.4f", mean, sqrt(var), min, max}'
}

echo "elapsed_ms: $(stats < "${ELAPSED_FILE}")"
echo "gflops: $(stats < "${GFLOPS_FILE}")"
