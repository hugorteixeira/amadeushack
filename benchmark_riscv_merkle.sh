#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "bash is required to run this script." >&2
  exit 1
fi
set -euo pipefail

RUNS=${RUNS:-3}
NO_BUILD=${NO_BUILD:-0}
RISCV_CC=${RISCV_CC:-}
RISCV_CXX=${RISCV_CXX:-}
RISCV_RUNNER=${RISCV_RUNNER:-}
RISCV_RUNNER_ARGS=${RISCV_RUNNER_ARGS:-}

MERKLE_LEAVES=${MERKLE_LEAVES:-1024}
MERKLE_PROOFS=${MERKLE_PROOFS:-16}
MERKLE_ITERS=${MERKLE_ITERS:-1}
MERKLE_PROGRESS=${MERKLE_PROGRESS:-0}
MERKLE_SEED_HEX=${MERKLE_SEED_HEX:-}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MERKLE_DIR="${ROOT_DIR}/hard/merkle"
BUILD_DIR="${MERKLE_DIR}/build_riscv"
BIN="${BUILD_DIR}/merkle_riscv"

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

if [[ -z "${MERKLE_SEED_HEX}" ]]; then
  SEED_BIN="${ROOT_DIR}/hard/matmul/seed.bin"
  if [[ -f "${SEED_BIN}" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      MERKLE_SEED_HEX=$(python3 - <<'PY'
from pathlib import Path
seed = Path("/amadeushack/hard/matmul/seed.bin").read_bytes()
print(seed[:32].hex())
PY
)
    elif command -v xxd >/dev/null 2>&1; then
      MERKLE_SEED_HEX=$(xxd -p -l 32 "${SEED_BIN}" | tr -d '\n')
    fi
  fi
fi

if [[ -z "${MERKLE_SEED_HEX}" ]]; then
  MERKLE_SEED_HEX="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
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
  CFLAGS="-O3 -std=c11 ${COMMON_DEFS} -I${ROOT_DIR}/hard/matmul/third_party/blake3"
  CXXFLAGS="-O3 -std=c++17 ${COMMON_DEFS} -I${ROOT_DIR}/hard/matmul/third_party/blake3"

  CONFIG_HEADER="${BUILD_DIR}/merkle_config.h"
  printf '#define MERKLE_LEAVES %s\n#define MERKLE_PROOFS %s\n#define MERKLE_ITERS %s\n#define MERKLE_PROGRESS %s\n#define MERKLE_SEED_HEX "%s"\n' \
    "${MERKLE_LEAVES}" "${MERKLE_PROOFS}" "${MERKLE_ITERS}" "${MERKLE_PROGRESS}" "${MERKLE_SEED_HEX}" > "${CONFIG_HEADER}"
  CXXFLAGS="${CXXFLAGS} -include ${CONFIG_HEADER}"

  "${RISCV_CC}" ${CFLAGS} -c "${ROOT_DIR}/hard/matmul/third_party/blake3/blake3.c" -o "${BUILD_DIR}/third_party/blake3/blake3.o"
  "${RISCV_CC}" ${CFLAGS} -c "${ROOT_DIR}/hard/matmul/third_party/blake3/blake3_dispatch.c" -o "${BUILD_DIR}/third_party/blake3/blake3_dispatch.o"
  "${RISCV_CC}" ${CFLAGS} -c "${ROOT_DIR}/hard/matmul/third_party/blake3/blake3_portable.c" -o "${BUILD_DIR}/third_party/blake3/blake3_portable.o"
  "${RISCV_CXX}" ${CXXFLAGS} -c "${MERKLE_DIR}/src/merkle.cpp" -o "${BUILD_DIR}/src/merkle.o"
  "${RISCV_CXX}" ${CXXFLAGS} -o "${BIN}" \
    "${BUILD_DIR}/src/merkle.o" \
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
  RISCV_RUNNER_ARGS="--environment user --memory-size 256m"
fi

IFS=' ' read -r -a runner_args <<< "${RISCV_RUNNER_ARGS}"

ELAPSED_FILE=$(mktemp)
PPS_FILE=$(mktemp)
trap 'rm -f "${ELAPSED_FILE}" "${PPS_FILE}"' EXIT
ELAPSED_VALUES=""
PPS_VALUES=""
expected_total=$((MERKLE_PROOFS * MERKLE_ITERS))

for i in $(seq 1 "${RUNS}"); do
  start_ns=$(now_ns)
  if ! output=$("${RISCV_RUNNER}" "${runner_args[@]}" "${BIN}" 2>&1); then
    echo "${output}" >&2
    echo "Runner failed." >&2
    exit 1
  fi
  end_ns=$(now_ns)

  host_elapsed_ms=$(awk -v s="${start_ns}" -v e="${end_ns}" 'BEGIN{printf "%.6f", (e-s)/1000000.0}')
  total_proofs=$(echo "${output}" | sed -n 's/.*"total_proofs":\([0-9]*\).*/\1/p')
  if [[ -z "${total_proofs}" || "${total_proofs}" == "0" ]]; then
    total_proofs="${expected_total}"
  fi
  proofs_per_sec=$(awk -v tp="${total_proofs}" -v ms="${host_elapsed_ms}" 'BEGIN{if(ms==0){printf "0.000000"} else {printf "%.6f", tp/(ms/1000.0)}}')

  echo "${output}"
  echo "${host_elapsed_ms}" >> "${ELAPSED_FILE}"
  echo "${proofs_per_sec}" >> "${PPS_FILE}"
  ELAPSED_VALUES+="${host_elapsed_ms}"$'\n'
  PPS_VALUES+="${proofs_per_sec}"$'\n'
  echo "run=${i} elapsed_ms=${host_elapsed_ms} proofs_per_sec=${proofs_per_sec} total_proofs=${total_proofs} expected_total=${expected_total}"
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
  else
    awk 'NR==1{min=max=$1} {sum+=$1; sumsq+=$1*$1; if($1<min)min=$1; if($1>max)max=$1} END{mean=sum/NR; var=sumsq/NR-mean*mean; if(var<0)var=0; printf "avg=%.4f std=%.4f min=%.4f max=%.4f", mean, sqrt(var), min, max}'
  fi
}

if [[ -n "${ELAPSED_VALUES}" ]]; then
  echo "elapsed_ms: $(printf "%s" "${ELAPSED_VALUES}" | stats)"
else
  echo "elapsed_ms: $(stats < "${ELAPSED_FILE}")"
fi
if [[ -n "${PPS_VALUES}" ]]; then
  echo "proofs_per_sec: $(printf "%s" "${PPS_VALUES}" | stats)"
else
  echo "proofs_per_sec: $(stats < "${PPS_FILE}")"
fi
