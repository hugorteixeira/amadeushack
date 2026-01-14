#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-https://nodes.amadeus.bot}
SEED_HEX=${SEED_HEX:-}
OUT_DIR=${OUT_DIR:-}
SEED_OUT=${SEED_OUT:-}
SOLUTION_OUT=${SOLUTION_OUT:-}
SKIP_BUILD=${SKIP_BUILD:-0}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="${MATMUL_DIR}"
fi
if [[ -z "${SEED_OUT}" ]]; then
  SEED_OUT="${OUT_DIR}/seed.bin"
fi
if [[ -z "${SOLUTION_OUT}" ]]; then
  SOLUTION_OUT="${OUT_DIR}/solution.bin"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc)
      RPC_URL="$2"
      shift 2
      ;;
    --seed-hex)
      SEED_HEX="$2"
      shift 2
      ;;
    --no-build)
      SKIP_BUILD=1
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

need_node=1
if [[ -n "${SEED_HEX}" ]]; then
  need_node=0
fi

if [[ "${need_node}" == "1" ]]; then
  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js not found. Install Node 18+ or provide SEED_HEX." >&2
    exit 1
  fi

  NODE_VERSION=$(node -v | tr -d 'v')
  NODE_MAJOR=${NODE_VERSION%%.*}
  if [[ "${NODE_MAJOR}" -lt 18 ]]; then
    echo "Node.js ${NODE_VERSION} is too old. Install Node 18+ or provide SEED_HEX." >&2
    exit 1
  fi

  cd "${SCRIPT_DIR}"
  if [[ ! -d node_modules ]]; then
    npm install
  fi

  seed_output=$(node build_seed.mjs --generate --rpc "${RPC_URL}" --out "${SEED_OUT}")
  echo "${seed_output}"
  SEED_HEX=$(echo "${seed_output}" | grep -m1 "^seed_hex=" | cut -d= -f2-)
  if [[ -z "${SEED_HEX}" ]]; then
    echo "seed_hex not found in build_seed output" >&2
    exit 1
  fi
fi

cd "${MATMUL_DIR}"
if [[ "${SKIP_BUILD}" != "1" ]]; then
  make
fi

./matmul --upow --seed-hex "${SEED_HEX}" --output "${SOLUTION_OUT}"
bytes=$(wc -c < "${SOLUTION_OUT}" | tr -d ' ')
echo "solution=${SOLUTION_OUT} (${bytes} bytes)"
