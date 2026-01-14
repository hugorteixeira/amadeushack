#!/usr/bin/env python3
import argparse
import json
import urllib.request
import urllib.error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--auth-header", default="Authorization")
    parser.add_argument("--auth-prefix", default="Bearer ")
    args = parser.parse_args()

    with open(args.results, "r", encoding="utf-8") as f:
        payload = json.load(f)

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(args.endpoint, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    auth_value = f"{args.auth_prefix}{args.api_key}" if args.auth_prefix else args.api_key
    req.add_header(args.auth_header, auth_value)

    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            print(body)
    except urllib.error.HTTPError as exc:
        print(exc.read().decode("utf-8"))
        raise


if __name__ == "__main__":
    main()
