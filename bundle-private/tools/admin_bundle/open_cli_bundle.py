#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys

from bundle_crypto import InvalidBundleFormat, InvalidBundlePassword, load_text, open_sealed


def extract_field(payload, field: str):
    value = payload
    for part in field.split("."):
        if isinstance(value, dict):
            value = value.get(part, "")
        else:
            return ""
    return value


def open_cli_bundle(password: str, bundle: dict) -> dict:
    if not isinstance(bundle, dict):
        raise InvalidBundleFormat("bundle must be a JSON object")
    records = bundle.get("records")
    if not isinstance(records, list):
        raise InvalidBundleFormat("bundle.records must be a list")

    matched = []
    for index, record in enumerate(records):
        try:
            payload = open_sealed(password, record)
        except InvalidBundlePassword:
            continue
        except InvalidBundleFormat as exc:
            raise InvalidBundleFormat(f"invalid record at index {index}: {exc}") from exc
        if not isinstance(payload, dict):
            raise InvalidBundleFormat(f"decrypted record at index {index} is not a JSON object")
        matched.append(payload)

    if not matched:
        raise InvalidBundlePassword("no matching record found for this password")
    if len(matched) > 1:
        raise InvalidBundleFormat("bundle invariant violated: multiple records matched this password")
    return matched[0]


def main() -> int:
    parser = argparse.ArgumentParser(description="Open one monthly CLI bundle and find the unique record for a password")
    parser.add_argument("--source", required=True, help="bundle path or URL")
    parser.add_argument("--password", default="", help="bundle password; if omitted, prompt")
    parser.add_argument("--password-stdin", action="store_true", help="read bundle password from stdin")
    parser.add_argument("--field", default="", help="optional single field to print, e.g. api_key")
    args = parser.parse_args()

    password = args.password
    if args.password_stdin:
        password = sys.stdin.read().rstrip("\n")
    if not password:
        from getpass import getpass
        password = getpass("请输入提取密码: ")
    bundle = json.loads(load_text(args.source))
    payload = open_cli_bundle(password, bundle)
    if args.field:
        value = extract_field(payload, args.field)
        if isinstance(value, (dict, list)):
            print(json.dumps(value, ensure_ascii=False))
        else:
            print(value)
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
