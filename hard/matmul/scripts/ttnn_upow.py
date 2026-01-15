#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
from blake3 import blake3


K_DIM = 50240
M_DIM = 16
N_DIM = 16
SEED_SIZE = 240
TILE = 32


def die(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def load_seed(seed_hex, seed_bin):
    seed_hex = seed_hex or os.environ.get("SEED_HEX")
    if seed_hex:
        data = bytes.fromhex(seed_hex.strip())
    else:
        seed_path = seed_bin or os.environ.get("SEED_BIN")
        if not seed_path:
            die("Missing seed. Provide --seed-hex, --seed-bin, or SEED_HEX/SEED_BIN.")
        data = Path(seed_path).read_bytes()
    if len(data) != SEED_SIZE:
        die(f"Seed size mismatch. Expected {SEED_SIZE} bytes, got {len(data)}.")
    return data


def pad_to(value: int, multiple: int) -> int:
    return ((value + multiple - 1) // multiple) * multiple


def get_ttnn_dtype(ttnn, names) -> object:
    for name in names:
        dtype = getattr(ttnn, name, None)
        if dtype is not None:
            return dtype
    return None


def find_ttnn_paths():
    paths = []
    bases = [Path.home(), Path("/")]
    skip = {"proc", "sys", "dev", "run", "tmp"}
    for base in bases:
        if not base.exists():
            continue
        base_depth = len(base.parts)
        for root, dirs, files in os.walk(base):
            rel_depth = len(Path(root).parts) - base_depth
            if rel_depth > 5:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in skip]
            if "ttnn" in dirs:
                candidate = Path(root) / "ttnn" / "__init__.py"
                if candidate.is_file():
                    paths.append(candidate.parent.parent)
    return paths


def import_ttnn():
    try:
        import ttnn
        return ttnn
    except Exception:
        pass
    for path in find_ttnn_paths():
        if str(path) not in sys.path:
            sys.path.insert(0, str(path))
    try:
        import ttnn
        return ttnn
    except Exception as exc:
        raise RuntimeError(f"Failed to import ttnn after searching: {exc}") from exc


def open_device(ttnn, device_id: int):
    if hasattr(ttnn, "open_device"):
        return ttnn.open_device(device_id)
    if hasattr(ttnn, "create_device"):
        return ttnn.create_device(device_id)
    raise RuntimeError("TTNN device open API not found.")


def close_device(ttnn, device):
    if hasattr(ttnn, "close_device"):
        ttnn.close_device(device)
    elif hasattr(device, "close"):
        device.close()


def run_matmul_ttnn(a_pad: np.ndarray, b_pad: np.ndarray, device_id: int):
    try:
        import torch
        ttnn = import_ttnn()
    except Exception as exc:
        raise RuntimeError(f"Failed to import ttnn/torch: {exc}") from exc

    a_dtype = get_ttnn_dtype(ttnn, ["uint8", "uint8_t"])
    b_dtype = get_ttnn_dtype(ttnn, ["int8", "int8_t"])
    out_dtype = get_ttnn_dtype(ttnn, ["int32", "int32_t"])
    if b_dtype is None or out_dtype is None:
        raise RuntimeError("TTNN int8/int32 dtypes are required.")

    layout = getattr(ttnn, "TILE_LAYOUT", None)
    if layout is None:
        layout = getattr(ttnn, "ROW_MAJOR_LAYOUT", None)
    if layout is None:
        raise RuntimeError("TTNN layout constant not found.")

    device = open_device(ttnn, device_id)
    used_signed_a = False
    try:
        a_torch = torch.from_numpy(a_pad)
        b_torch = torch.from_numpy(b_pad)

        if a_dtype is None:
            a_signed = a_torch.to(torch.int16) - 128
            a_torch = a_signed.to(torch.int8)
            a_dtype = b_dtype
            used_signed_a = True

        a_tt = ttnn.from_torch(a_torch, device=device, dtype=a_dtype, layout=layout)
        b_tt = ttnn.from_torch(b_torch, device=device, dtype=b_dtype, layout=layout)

        try:
            c_tt = ttnn.matmul(a_tt, b_tt, dtype=out_dtype)
        except TypeError:
            c_tt = ttnn.matmul(a_tt, b_tt, output_dtype=out_dtype)

        if hasattr(ttnn, "synchronize"):
            ttnn.synchronize(device)

        c_torch = ttnn.to_torch(c_tt)
    finally:
        close_device(ttnn, device)

    return c_torch, used_signed_a


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed-hex")
    parser.add_argument("--seed-bin")
    parser.add_argument("--output")
    parser.add_argument("--print-solution", action="store_true")
    parser.add_argument("--device", type=int, default=int(os.environ.get("TT_DEVICE_ID", "0")))
    args = parser.parse_args()

    seed = load_seed(args.seed_hex, args.seed_bin)
    ab = blake3(seed).digest(2 * M_DIM * K_DIM)
    a_bytes = ab[: M_DIM * K_DIM]
    b_bytes = ab[M_DIM * K_DIM :]

    a_np = np.frombuffer(a_bytes, dtype=np.uint8).reshape(M_DIM, K_DIM)
    b_np = np.frombuffer(b_bytes, dtype=np.int8).reshape(K_DIM, N_DIM)

    m_pad = pad_to(M_DIM, TILE)
    n_pad = pad_to(N_DIM, TILE)
    a_pad = np.zeros((m_pad, K_DIM), dtype=np.uint8)
    b_pad = np.zeros((K_DIM, n_pad), dtype=np.int8)
    a_pad[:M_DIM, :K_DIM] = a_np
    b_pad[:K_DIM, :N_DIM] = b_np

    start = time.time()
    c_torch, used_signed_a = run_matmul_ttnn(a_pad, b_pad, args.device)
    elapsed_ms = (time.time() - start) * 1000.0

    c_np = c_torch[:M_DIM, :N_DIM].cpu().numpy().astype(np.int32, copy=False)
    if used_signed_a:
        b_sum = b_np.astype(np.int32).sum(axis=0)
        c_np = c_np + (128 * b_sum)[None, :]

    solution = seed + c_np.astype("<i4", copy=False).tobytes()
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_bytes(solution)

    metrics = {"mode": "ttnn_upow", "elapsed_ms": round(elapsed_ms, 6)}
    print(json.dumps(metrics))
    if args.print_solution:
        print(f"solution_hex={solution.hex()}")


if __name__ == "__main__":
    main()
