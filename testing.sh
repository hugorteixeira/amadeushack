#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "bash is required to run this script." >&2
  exit 1
fi
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER=${RISCV_RUNNER:-/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-run}
BIN=${RISCV_BIN:-${ROOT_DIR}/hard/matmul/build_riscv/matmul_riscv}
ARCH=${RISCV_ARCH:-riscv:rv32}
MODEL=${RISCV_MODEL:-RV32IMAC}
ENV_MODE=${RISCV_ENV:-user}
MEM_SIZE=${RISCV_MEM:-256m}

OUT_DIR=${OUT_DIR:-${ROOT_DIR}/riscv_diag_$(date +%Y%m%d_%H%M%S)}
mkdir -p "${OUT_DIR}"

run_cmd() {
  local name=$1
  shift
  local file="${OUT_DIR}/${name}.txt"
  echo "== ${name} ==" | tee "${file}"
  "$@" 2>&1 | tee -a "${file}"
}

run_cmd_allow_fail() {
  local name=$1
  shift
  local file="${OUT_DIR}/${name}.txt"
  echo "== ${name} ==" | tee "${file}"
  set +e
  "$@" 2>&1 | tee -a "${file}"
  local code=${PIPESTATUS[0]}
  set -e
  echo "[exit=${code}]" | tee -a "${file}"
  return 0
}

echo "Output dir: ${OUT_DIR}"
echo "Runner: ${RUNNER}"
echo "Binary: ${BIN}"
echo "Arch/Model: ${ARCH} / ${MODEL}"
echo "Env/Memory: ${ENV_MODE} / ${MEM_SIZE}"
echo

if [[ ! -x "${RUNNER}" ]]; then
  echo "Runner not found: ${RUNNER}" >&2
  exit 1
fi

if [[ ! -f "${BIN}" ]]; then
  echo "RISC-V binary not found. Building via ./benchmark_riscv.sh --runs 1" >&2
  set +e
  "${ROOT_DIR}/benchmark_riscv.sh" --runs 1
  set -e
fi
if [[ ! -f "${BIN}" ]]; then
  echo "Failed to build RISC-V binary: ${BIN}" >&2
  exit 1
fi

run_cmd version "${RUNNER}" --version
run_cmd_allow_fail info_model "${RUNNER}" --info-model
run_cmd_allow_fail info_arch "${RUNNER}" --info-architecture
run_cmd_allow_fail info_hw "${RUNNER}" --info-hw
run_cmd_allow_fail hw_list "${RUNNER}" --hw-list

run_cmd_allow_fail opt_ls "ls" -lah /opt
run_cmd_allow_fail opt_tt_find "find" /opt -maxdepth 4 -type f \( -iname "*tt*" -o -iname "*tensix*" -o -iname "*blackhole*" -o -iname "*ttnn*" -o -iname "*ttmetal*" \)

run_cmd file file "${BIN}"
run_cmd readelf /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-readelf -h "${BIN}"
run_cmd objdump /opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-objdump -f "${BIN}"

run_cmd_allow_fail run_baseline "${RUNNER}" --architecture "${ARCH}" --model "${MODEL}" \
  --environment "${ENV_MODE}" --memory-size "${MEM_SIZE}" "${BIN}"

PROFILE_FILE="${OUT_DIR}/tt_profile.txt"
run_cmd_allow_fail run_profile "${RUNNER}" --architecture "${ARCH}" --model "${MODEL}" \
  --environment "${ENV_MODE}" --memory-size "${MEM_SIZE}" \
  --profile=on --profile-core=on --profile-model=on --profile-pc=on --profile-pc-frequency 1 \
  --profile-file "${PROFILE_FILE}" "${BIN}"

if [[ -f "${PROFILE_FILE}" ]]; then
  run_cmd profile_head "head" -n 120 "${PROFILE_FILE}"
  run_cmd_allow_fail profile_grep "grep" -nE "cycle|instr|time|model|core|pc" "${PROFILE_FILE}"
fi

TRACE_FILE="${OUT_DIR}/tt_trace.txt"
run_cmd_allow_fail run_trace "${RUNNER}" --architecture "${ARCH}" --model "${MODEL}" \
  --environment "${ENV_MODE}" --memory-size "${MEM_SIZE}" \
  --trace-model=on --trace-file "${TRACE_FILE}" "${BIN}"

if [[ -f "${TRACE_FILE}" ]]; then
  run_cmd trace_tail "tail" -n 80 "${TRACE_FILE}"
fi

echo
echo "Diagnostics complete. Logs saved under: ${OUT_DIR}"
