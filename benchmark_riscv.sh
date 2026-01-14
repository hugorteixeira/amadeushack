#!/usr/bin/env bash
set -euo pipefail

RUNS=${RUNS:-5}
RPC_URL=${RPC_URL:-https://nodes.amadeus.bot}
SEED_HEX=${SEED_HEX:-}
SEED_BIN=${SEED_BIN:-}
NO_BUILD=${NO_BUILD:-0}
RISCV_CC=${RISCV_CC:-riscv64-unknown-linux-gnu-gcc}
RISCV_CXX=${RISCV_CXX:-riscv64-unknown-linux-gnu-g++}
RISCV_RUNNER=${RISCV_RUNNER:-}
RISCV_RUNNER_ARGS=${RISCV_RUNNER_ARGS:-}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MATMUL_DIR="${ROOT_DIR}/hard/matmul"
SCRIPT_DIR="${MATMUL_DIR}/scripts"
BUILD_DIR="${MATMUL_DIR}/build_riscv"
BIN="${BUILD_DIR}/matmul_riscv"
SOLUTION_OUT="${BUILD_DIR}/solution.bin"

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
    --runner)
      RISCV_RUNNER="$2"
      shift 2
      ;;
    --runner-args)
      RISCV_RUNNER_ARGS="$2"
      shift 2
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
  mkdir -p "${BUILD_DIR}/third_party/blake3" "${BUILD_DIR}/src"
  COMMON_DEFS="-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512"
  RISCV_CFLAGS="${RISCV_CFLAGS:--O3 -std=c11 ${COMMON_DEFS} -I${MATMUL_DIR}/third_party/blake3}"
  RISCV_CXXFLAGS="${RISCV_CXXFLAGS:--O3 -std=c++17 ${COMMON_DEFS} -I${MATMUL_DIR}/third_party/blake3}"

  "${RISCV_CC}" ${RISCV_CFLAGS} -c "${MATMUL_DIR}/third_party/blake3/blake3.c" -o "${BUILD_DIR}/third_party/blake3/blake3.o"
  "${RISCV_CC}" ${RISCV_CFLAGS} -c "${MATMUL_DIR}/third_party/blake3/blake3_dispatch.c" -o "${BUILD_DIR}/third_party/blake3/blake3_dispatch.o"
  "${RISCV_CC}" ${RISCV_CFLAGS} -c "${MATMUL_DIR}/third_party/blake3/blake3_portable.c" -o "${BUILD_DIR}/third_party/blake3/blake3_portable.o"
  "${RISCV_CXX}" ${RISCV_CXXFLAGS} -c "${MATMUL_DIR}/src/matmul.cpp" -o "${BUILD_DIR}/src/matmul.o"
  "${RISCV_CXX}" ${RISCV_CXXFLAGS} -o "${BIN}" \
    "${BUILD_DIR}/src/matmul.o" \
    "${BUILD_DIR}/third_party/blake3/blake3.o" \
    "${BUILD_DIR}/third_party/blake3/blake3_dispatch.o" \
    "${BUILD_DIR}/third_party/blake3/blake3_portable.o"
fi

if [[ -z "${RISCV_RUNNER}" ]]; then
  if command -v qemu-riscv64 >/dev/null 2>&1; then
    RISCV_RUNNER="qemu-riscv64"
  else
    echo "RISCV_RUNNER not set and qemu-riscv64 not found." >&2
    exit 1
  fi
fi

IFS=' ' read -r -a runner_args <<< "${RISCV_RUNNER_ARGS}"

ELAPSED_FILE=$(mktemp)
GFLOPS_FILE=$(mktemp)
trap 'rm -f "${ELAPSED_FILE}" "${GFLOPS_FILE}"' EXIT

for i in $(seq 1 "${RUNS}"); do
  if [[ -n "${SEED_HEX}" ]]; then
    output=$("${RISCV_RUNNER}" "${runner_args[@]}" "${BIN}" --upow --seed-hex "${SEED_HEX}" --output "${SOLUTION_OUT}")
  else
    output=$("${RISCV_RUNNER}" "${runner_args[@]}" "${BIN}" --upow --seed-path "${SEED_BIN}" --output "${SOLUTION_OUT}")
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
