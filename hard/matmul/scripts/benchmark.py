#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import struct
import subprocess
import tempfile
from typing import List


def parse_blocks(value: str) -> List[int]:
    return [int(v.strip()) for v in value.split(",") if v.strip()]


def hash_output(path: str) -> str:
    with open(path, "rb") as f:
        header = f.read(12)
        data = f.read()
    h = hashlib.sha256()
    h.update(header)
    h.update(data)
    return h.hexdigest()


def run_one(matmul_path: str, m: int, n: int, k: int, algo: str, block: int) -> dict:
    with tempfile.NamedTemporaryFile(prefix="matmul_out_", delete=False) as tmp:
        out_path = tmp.name
    cmd = [matmul_path, "--m", str(m), "--n", str(n), "--k", str(k), "--algo", algo]
    if algo == "blocked":
        cmd += ["--block", str(block)]
    cmd += ["--output", out_path]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    try:
        metrics = json.loads(proc.stdout.strip())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Failed to parse JSON output: {proc.stdout}") from exc
    metrics["output_hash"] = hash_output(out_path)
    os.unlink(out_path)
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matmul", default="./matmul")
    parser.add_argument("--m", type=int, default=256)
    parser.add_argument("--n", type=int, default=256)
    parser.add_argument("--k", type=int, default=256)
    parser.add_argument("--algo", default="blocked")
    parser.add_argument("--blocks", default="32,64,128")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--output", default="results.json")
    args = parser.parse_args()

    blocks = parse_blocks(args.blocks)
    results = []
    for block in blocks:
        for _ in range(args.runs):
            results.append(run_one(args.matmul, args.m, args.n, args.k, args.algo, block))

    payload = {
        "m": args.m,
        "n": args.n,
        "k": args.k,
        "algo": args.algo,
        "blocks": blocks,
        "runs": args.runs,
        "results": results,
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
