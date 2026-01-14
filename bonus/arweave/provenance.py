#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import time
import urllib.request


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True, help="Benchmark results JSON")
    parser.add_argument("--artifact", required=True, help="Output artifact (e.g., out.bin)")
    parser.add_argument("--out", default="provenance.json")
    parser.add_argument("--endpoint", help="Optional upload endpoint (Turbo / Arweave gateway)")
    parser.add_argument("--api-key", help="Optional API key for upload")
    args = parser.parse_args()

    with open(args.results, "r", encoding="utf-8") as f:
        results = json.load(f)

    payload = {
        "run_id": os.urandom(8).hex(),
        "timestamp": int(time.time()),
        "results_hash": sha256_file(args.results),
        "artifact_hash": sha256_file(args.artifact),
        "results": results,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    if args.endpoint:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(args.endpoint, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        if args.api_key:
            req.add_header("Authorization", f"Bearer {args.api_key}")
        with urllib.request.urlopen(req) as resp:
            print(resp.read().decode("utf-8"))
    else:
        print(args.out)


if __name__ == "__main__":
    main()
