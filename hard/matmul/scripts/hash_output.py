#!/usr/bin/env python3
import argparse
import hashlib
import struct


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Path to output binary")
    args = parser.parse_args()

    with open(args.input, "rb") as f:
        header = f.read(12)
        if len(header) != 12:
            raise SystemExit("Output file too small")
        m, n, k = struct.unpack("<iii", header)
        data = f.read()

    h = hashlib.sha256()
    h.update(header)
    h.update(data)
    print(h.hexdigest())


if __name__ == "__main__":
    main()
