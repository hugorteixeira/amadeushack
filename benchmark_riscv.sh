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
RISCV_CC=${RISCV_CC:-}
RISCV_CXX=${RISCV_CXX:-}
RISCV_RUNNER=${RISCV_RUNNER:-}
RISCV_RUNNER_ARGS=${RISCV_RUNNER_ARGS:-}
NO_OUTPUT=${NO_OUTPUT:-1}
TT_BAREMETAL=${TT_BAREMETAL:-1}
TT_CPU_HZ=${TT_CPU_HZ:-1000000000}
TT_USE_RDCYCLE=${TT_USE_RDCYCLE:-0}

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
    --write-output)
      NO_OUTPUT=0
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
    fi
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

if [[ -z "${SEED_HEX}" ]]; then
  echo "Failed to derive SEED_HEX from ${SEED_BIN}. Install python3/xxd/hexdump or set SEED_HEX." >&2
  exit 1
fi

if [[ "${NO_BUILD}" != "1" ]]; then
  if [[ -z "${RISCV_CC}" && -x /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-gcc ]]; then
    RISCV_CC=/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-gcc
  fi
  if [[ -z "${RISCV_CXX}" && -x /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-g++ ]]; then
    RISCV_CXX=/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-g++
  fi
  if [[ -z "${RISCV_CC}" ]]; then
    RISCV_CC=riscv64-unknown-linux-gnu-gcc
  fi
  if [[ -z "${RISCV_CXX}" ]]; then
    RISCV_CXX=riscv64-unknown-linux-gnu-g++
  fi

  mkdir -p "${BUILD_DIR}/third_party/blake3" "${BUILD_DIR}/src"
  COMMON_DEFS="-DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512"
  if [[ "${TT_BAREMETAL}" == "1" ]]; then
    COMMON_DEFS+=" -DTT_BAREMETAL"
  fi
  RISCV_CFLAGS="${RISCV_CFLAGS:--O3 -std=c11 ${COMMON_DEFS} -I${MATMUL_DIR}/third_party/blake3}"
  RISCV_CXXFLAGS="${RISCV_CXXFLAGS:--O3 -std=c++17 ${COMMON_DEFS} -I${MATMUL_DIR}/third_party/blake3}"
  if [[ "${TT_BAREMETAL}" == "1" ]]; then
    SEED_HEADER="${BUILD_DIR}/seed_hex.h"
    printf '#define TT_SEED_HEX "%s"\n#define TT_CPU_HZ %s\n#define TT_USE_RDCYCLE %s\n' \
      "${SEED_HEX}" "${TT_CPU_HZ}" "${TT_USE_RDCYCLE}" > "${SEED_HEADER}"
    RISCV_CXXFLAGS="${RISCV_CXXFLAGS} -include ${SEED_HEADER}"
  fi

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
  if [[ -x /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run ]]; then
    RISCV_RUNNER="/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run"
  elif command -v qemu-riscv64 >/dev/null 2>&1; then
    RISCV_RUNNER="qemu-riscv64"
  else
    echo "RISCV_RUNNER not set and no runner found." >&2
    exit 1
  fi
fi

if [[ -z "${RISCV_RUNNER_ARGS}" && "${RISCV_RUNNER}" == "/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run" ]]; then
  if [[ "${TT_USE_RDCYCLE}" == "1" ]]; then
    RISCV_RUNNER_ARGS="--environment operating --memory-size 256m"
  else
    RISCV_RUNNER_ARGS="--environment user --memory-size 256m"
  fi
fi

IFS=' ' read -r -a runner_args <<< "${RISCV_RUNNER_ARGS}"
if [[ "${TT_BAREMETAL}" == "1" && "${RISCV_RUNNER}" == "/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run" ]]; then
  runner_args+=(--env-set "SEED_HEX=${SEED_HEX}")
fi

ELAPSED_FILE=$(mktemp)
GFLOPS_FILE=$(mktemp)
trap 'rm -f "${ELAPSED_FILE}" "${GFLOPS_FILE}"' EXIT

for i in $(seq 1 "${RUNS}"); do
  cmd=("${RISCV_RUNNER}" "${runner_args[@]}" "${BIN}" --upow)
  if [[ -n "${SEED_HEX}" ]]; then
    if [[ "${NO_OUTPUT}" == "1" ]]; then
      cmd+=(--seed-hex "${SEED_HEX}" --no-output)
    else
      cmd+=(--seed-hex "${SEED_HEX}" --output "${SOLUTION_OUT}")
    fi
  else
    if [[ "${NO_OUTPUT}" == "1" ]]; then
      cmd+=(--seed-path "${SEED_BIN}" --no-output)
    else
      cmd+=(--seed-path "${SEED_BIN}" --output "${SOLUTION_OUT}")
    fi
  fi

  if ! output=$(SEED_HEX="${SEED_HEX}" "${cmd[@]}" 2>&1); then
    echo "${output}" >&2
    echo "Runner failed." >&2
    exit 1
  fi
  echo "${output}"
  elapsed=$(echo "${output}" | sed -n 's/.*"elapsed_ms":\([0-9.]*\).*/\1/p')
  gflops=$(echo "${output}" | sed -n 's/.*"gflops":\([0-9.]*\).*/\1/p')
  if [[ -z "${elapsed}" || -z "${gflops}" ]]; then
    elapsed_cycles=$(echo "${output}" | sed -n 's/.*"elapsed_cycles":\([0-9]*\).*/\1/p')
    if [[ -n "${elapsed_cycles}" ]]; then
      calc=""
      if command -v python3 >/dev/null 2>&1; then
        calc=$(python3 - <<'PY'
import os
cyc = int(os.environ.get("ELAPSED_CYCLES", "0"))
hz = int(os.environ.get("TT_CPU_HZ", "1000000000"))
if cyc == 0:
    ms = 0.0
    g = 0.0
else:
    ms = (cyc * 1000.0) / hz
    g = (2.0 * 16.0 * 16.0 * 50240.0 * hz) / (cyc * 1e9)
print(f"{ms:.6f} {g:.6f}")
PY
ELAPSED_CYCLES="${elapsed_cycles}" TT_CPU_HZ="${TT_CPU_HZ}" ) || true
      elif command -v awk >/dev/null 2>&1; then
        calc=$(awk -v cyc="${elapsed_cycles}" -v hz="${TT_CPU_HZ}" 'BEGIN{
          if (cyc==0) {ms=0; g=0} else {ms=cyc*1000.0/hz; g=(2.0*16.0*16.0*50240.0*hz)/(cyc*1e9)}
          printf "%.6f %.6f", ms, g
        }') || true
      fi
      if [[ -n "${calc}" ]]; then
        elapsed=${calc%% *}
        gflops=${calc##* }
      fi
    fi
  fi
  if [[ -z "${elapsed}" || -z "${gflops}" ]]; then
    if [[ "${TT_BAREMETAL}" == "1" ]]; then
      echo "Warning: failed to parse benchmark output, assuming 0 for bare-metal." >&2
      elapsed=0
      gflops=0
    else
      echo "Failed to parse benchmark output" >&2
      exit 1
    fi
  fi
  echo "${elapsed}" >> "${ELAPSED_FILE}"
  echo "${gflops}" >> "${GFLOPS_FILE}"
  echo "run=${i} elapsed_ms=${elapsed} gflops=${gflops}"
done

stats() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import math, sys
vals = [float(x.strip()) for x in sys.stdin if x.strip()]
if not vals:
    print("avg=0.0000 std=0.0000 min=0.0000 max=0.0000")
    raise SystemExit(0)
mean = sum(vals) / len(vals)
var = sum((v - mean) ** 2 for v in vals) / len(vals)
std = math.sqrt(max(var, 0.0))
print(f"avg={mean:.4f} std={std:.4f} min={min(vals):.4f} max={max(vals):.4f}")
PY
  elif command -v awk >/dev/null 2>&1; then
    awk 'NR==1{min=max=$1} {sum+=$1; sumsq+=$1*$1; if($1<min)min=$1; if($1>max)max=$1} END{mean=sum/NR; var=sumsq/NR-mean*mean; if(var<0)var=0; printf "avg=%.4f std=%.4f min=%.4f max=%.4f", mean, sqrt(var), min, max}'
  else
    echo "avg=0.0000 std=0.0000 min=0.0000 max=0.0000"
  fi
}

echo "elapsed_ms: $(stats < "${ELAPSED_FILE}")"
echo "gflops: $(stats < "${GFLOPS_FILE}")"
