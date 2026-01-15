#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${ROOT_DIR}/.env"

echo ">> Installing Node deps (hard/matmul/scripts)..."
if command -v npm >/dev/null 2>&1; then
  (cd "${ROOT_DIR}/hard/matmul/scripts" && npm install)
else
  echo ">> npm not found; skipping Node deps install."
fi

echo ">> Installing Python deps (hard/matmul/scripts/requirements.txt)..."
if command -v python3 >/dev/null 2>&1; then
  python3 -m pip install --user -r "${ROOT_DIR}/hard/matmul/scripts/requirements.txt" || \
    echo ">> pip failed; install requirements manually."
else
  echo ">> python3 not found; skipping Python deps install."
fi

echo ">> Ensuring scripts are executable..."
chmod +x \
  "${ROOT_DIR}/run_riscv_validate.sh" \
  "${ROOT_DIR}/run_miner_testnet.sh" \
  "${ROOT_DIR}/hard/matmul/scripts/ttnn_upow.py"

existing_seed=""
existing_api_key=""
existing_rpc_url="https://testnet.ama.one"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  . "${ENV_FILE}"
  set +a
  existing_seed="${AMA_SEED_BASE58:-}"
  existing_api_key="${AMA_API_KEY:-}"
  existing_rpc_url="${RPC_URL:-${existing_rpc_url}}"
fi

echo ">> Configure keys (press Enter to keep current / skip)."
read -r -s -p "AMA_SEED_BASE58 (BLS seed, optional): " seed_input
echo
read -r -s -p "AMA_API_KEY (optional): " api_input
echo
read -r -p "RPC_URL [${existing_rpc_url}]: " rpc_input

seed_value="${seed_input:-${existing_seed}}"
api_value="${api_input:-${existing_api_key}}"
rpc_value="${rpc_input:-${existing_rpc_url}}"

umask 077
{
  echo "# Created by install.sh"
  if [[ -n "${seed_value}" ]]; then
    echo "AMA_SEED_BASE58=\"${seed_value}\""
  fi
  if [[ -n "${api_value}" ]]; then
    echo "AMA_API_KEY=\"${api_value}\""
  fi
  echo "RPC_URL=\"${rpc_value}\""
} > "${ENV_FILE}"

echo ">> Wrote ${ENV_FILE} (chmod 600)."
