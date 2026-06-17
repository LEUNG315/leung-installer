#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from datetime import datetime, timezone
from pathlib import Path

from bundle_crypto import seal_payload
from open_cli_bundle import open_cli_bundle as open_cli_bundle_record
from password_codec import SUPPORTED_CLIS, verify_password

THIS_DIR = Path(__file__).resolve().parent
CLI_REGISTRY_PATH = THIS_DIR / "cli-registry.json"
DEFAULT_KEY_PATTERNS = {
    "claude": [r"sk-[A-Za-z0-9][A-Za-z0-9._-]{5,}"],
    "codex": [r"sk-[A-Za-z0-9][A-Za-z0-9._-]{5,}"],
    "gemini": [r"AIza[0-9A-Za-z_-]{20,}", r"gemini-[A-Za-z0-9][A-Za-z0-9._-]{5,}"],
    "opencode": [r"sk-[A-Za-z0-9][A-Za-z0-9._-]{5,}"],
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing required json file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid json in {path}: {exc}") from exc


def dump_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def update_output_root_index(output_dir: Path, month: str) -> None:
    root = output_dir.parent
    months = []
    seen = set()
    for item in sorted(root.iterdir(), reverse=True):
        if not item.is_dir():
            continue
        name = item.name.strip()
        if re.fullmatch(r"\d{4}-\d{2}", name) and name not in seen:
            seen.add(name)
            months.append(name)
    if month not in seen:
        months.insert(0, month)
    dump_json(root / "index.json", {"version": 1, "latest_month": month, "months": months})


def parse_month(value: str) -> str:
    if not re.fullmatch(r"\d{4}-\d{2}", value):
        raise argparse.ArgumentTypeError("month must be in YYYY-MM format")
    return value


def load_cli_registry() -> dict[str, dict]:
    data = load_json(CLI_REGISTRY_PATH)
    result = {}
    for item in data.get("clis", []):
        cli = str(item.get("id", "")).strip()
        if cli:
            result[cli] = item
    return result


def load_users_config(path: Path) -> tuple[dict, list[dict], dict[str, dict]]:
    data = load_json(path)
    records = data.get("users")
    if records is None:
        records = data.get("passwords")
    if not isinstance(records, list):
        raise SystemExit(f"users config must contain a users/passwords list: {path}")
    cli_defaults = data.get("cli_defaults", {})
    if cli_defaults is None:
        cli_defaults = {}
    if not isinstance(cli_defaults, dict):
        raise SystemExit(f"cli_defaults must be an object: {path}")
    return data, records, cli_defaults


def normalize_allowed_clis(record: dict, cli_defaults: dict[str, dict]) -> list[str]:
    allowed = record.get("allowed_clis")
    if allowed is None:
        return list(cli_defaults.keys()) or list(SUPPORTED_CLIS)
    if not isinstance(allowed, list):
        raise SystemExit(f"allowed_clis must be a list for user {record.get('name', '')}")
    result = []
    for item in allowed:
        cli = str(item).strip()
        if not cli:
            continue
        if cli not in SUPPORTED_CLIS:
            raise SystemExit(f"unsupported cli in allowed_clis for user {record.get('name', '')}: {cli}")
        if cli not in result:
            result.append(cli)
    return result


def resolve_password(record: dict) -> str:
    raw_password = str(record.get("password", "")) if record.get("password") is not None else ""
    if not raw_password:
        raise SystemExit(f"user {record.get('name', '')} is missing required password in users.json")
    password_hash = str(record.get("password_hash", "")).strip()
    if password_hash and not verify_password(password_hash, raw_password):
        raise SystemExit(f"password does not match password_hash for user {record.get('name', '')}")
    return raw_password


def normalize_users(records: list[dict], cli_defaults: dict[str, dict]) -> list[dict]:
    normalized = []
    seen_names = set()
    for raw in records:
        if not isinstance(raw, dict):
            raise SystemExit("each user record must be a JSON object")
        name = str(raw.get("name", "")).strip()
        if not name:
            raise SystemExit("user name cannot be empty")
        if name in seen_names:
            raise SystemExit(f"duplicate user name in users config: {name}")
        seen_names.add(name)
        record = dict(raw)
        record["name"] = name
        record["_allowed_clis"] = normalize_allowed_clis(record, cli_defaults)
        record["_resolved_password"] = resolve_password(record)
        normalized.append(record)
    return normalized


def determine_target_clis(users: list[dict], cli_defaults: dict[str, dict], requested: list[str]) -> list[str]:
    if requested:
        targets = []
        for item in requested:
            cli = str(item).strip()
            if cli not in SUPPORTED_CLIS:
                raise SystemExit(f"unsupported cli: {cli}")
            if cli not in targets:
                targets.append(cli)
        return targets
    targets = []
    seen = set()
    for user in users:
        for cli in user.get("_allowed_clis", []):
            if cli not in seen:
                seen.add(cli)
                targets.append(cli)
    for cli in cli_defaults.keys():
        if cli not in SUPPORTED_CLIS:
            raise SystemExit(f"unsupported cli in cli_defaults: {cli}")
        if cli not in seen:
            seen.add(cli)
            targets.append(cli)
    if not targets:
        raise SystemExit("no target cli selected; add allowed_clis or pass --cli")
    return targets


def cli_config_for(cli: str, cli_defaults: dict[str, dict]) -> dict:
    value = cli_defaults.get(cli, {})
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise SystemExit(f"cli_defaults.{cli} must be a JSON object")
    return value


def key_patterns_for(cli: str, cli_defaults: dict[str, dict]) -> list[str]:
    config = cli_config_for(cli, cli_defaults)
    patterns = config.get("key_patterns") or DEFAULT_KEY_PATTERNS.get(cli, [])
    if isinstance(patterns, str):
        patterns = [patterns]
    if not isinstance(patterns, list) or not patterns:
        raise SystemExit(f"no key extraction patterns configured for cli: {cli}")
    result = []
    for item in patterns:
        pattern = str(item).strip()
        if pattern:
            result.append(pattern)
    if not result:
        raise SystemExit(f"no usable key extraction patterns configured for cli: {cli}")
    return result


def extract_keys_from_markdown(text: str, patterns: list[str]) -> list[str]:
    found = []
    seen = set()
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            token = match.group(0).strip()
            if token and token not in seen:
                seen.add(token)
                found.append(token)
    return found


def effective_users_for_cli(users: list[dict], cli: str) -> list[dict]:
    eligible = []
    for user in users:
        if cli not in user.get("_allowed_clis", []):
            continue
        status = str(user.get("status", "")).strip().lower()
        if status in {"revoked", "disabled"}:
            continue
        eligible.append(user)
    return eligible


def ensure_unique_passwords(users: list[dict], cli: str) -> None:
    by_password = {}
    duplicates = []
    for user in users:
        password = user["_resolved_password"]
        if password in by_password:
            duplicates.append((by_password[password], user["name"]))
        else:
            by_password[password] = user["name"]
    if duplicates:
        rendered = ", ".join(f"{first}/{second}" for first, second in duplicates)
        raise SystemExit(f"duplicate effective passwords not allowed within {cli} bundle: {rendered}")


def cli_rng(seed: str, month: str, cli: str):
    if seed:
        return random.Random(f"{seed}:{month}:{cli}")
    return random.SystemRandom()


def resolve_payload_fields(user: dict, cli: str, month: str, cli_defaults: dict[str, dict], cli_registry: dict[str, dict]) -> dict:
    defaults = cli_config_for(cli, cli_defaults)
    user_overrides = user.get("cli_overrides", {})
    if user_overrides is None:
        user_overrides = {}
    if not isinstance(user_overrides, dict):
        raise SystemExit(f"cli_overrides must be an object for user {user['name']}")
    cli_override = user_overrides.get(cli, {})
    if cli_override is None:
        cli_override = {}
    if not isinstance(cli_override, dict):
        raise SystemExit(f"cli_overrides.{cli} must be an object for user {user['name']}")
    base_url = str(cli_override.get("base_url") or defaults.get("base_url") or "").strip()
    if not base_url:
        raise SystemExit(f"missing base_url for cli {cli}; set cli_defaults.{cli}.base_url or cli_overrides.{cli}.base_url")
    model = str(cli_override.get("model") or defaults.get("model") or cli_registry.get(cli, {}).get("default_model", "")).strip()
    if not model:
        raise SystemExit(f"missing model for cli {cli}")
    credential_name = str(cli_override.get("credential_name") or f"{user['name']}-{cli}-{month}").strip()
    return {
        "credential_name": credential_name,
        "user_name": user["name"],
        "cli": cli,
        "base_url": base_url,
        "model": model,
        "bundle_month": month,
    }


def verify_bundle_for_cli(bundle_path: Path, cli: str, month: str, eligible_users: list[dict]) -> str:
    bundle = load_json(bundle_path)
    if int(bundle.get("record_count", 0)) != len(eligible_users):
        raise SystemExit(f"bundle record_count mismatch for {cli}: expected {len(eligible_users)} got {bundle.get('record_count', 0)}")
    if str(bundle.get("month", "")).strip() != month:
        raise SystemExit(f"bundle month mismatch for {cli}: expected {month} got {bundle.get('month', '')}")
    seen_users = set()
    seen_keys = set()
    for user in eligible_users:
        payload = open_cli_bundle_record(user["_resolved_password"], bundle)
        if payload.get("cli") != cli:
            raise SystemExit(f"bundle verification failed: cli mismatch for user {user['name']}")
        if payload.get("user_name") != user["name"]:
            raise SystemExit(f"bundle verification failed: expected user {user['name']}, got {payload.get('user_name', '')}")
        if payload.get("bundle_month") != month:
            raise SystemExit(f"bundle verification failed: month mismatch for user {user['name']}")
        api_key = str(payload.get("api_key", "")).strip()
        if not api_key:
            raise SystemExit(f"bundle verification failed: empty api_key for user {user['name']}")
        seen_users.add(user["name"])
        seen_keys.add(api_key)
    if len(seen_users) != len(eligible_users):
        raise SystemExit(f"bundle verification failed: some users could not be verified for {cli}")
    if len(seen_keys) != len(eligible_users):
        raise SystemExit(f"bundle verification failed: duplicate api_key assignment detected for {cli}")
    return f"bundle={bundle_path} cli={cli} users={len(eligible_users)} unique_keys={len(seen_keys)}"


def build_bundle_for_cli(*, cli: str, month: str, input_root: Path, output_dir: Path, users: list[dict], cli_defaults: dict[str, dict], cli_registry: dict[str, dict], seed: str) -> dict | None:
    eligible = effective_users_for_cli(users, cli)
    if not eligible:
        print(f"SKIP {cli}: no eligible users")
        return None
    ensure_unique_passwords(eligible, cli)
    markdown_path = input_root / f"{cli}_apikey.md"
    if not markdown_path.exists():
        raise SystemExit(f"missing markdown key file for {cli}: {markdown_path}")
    patterns = key_patterns_for(cli, cli_defaults)
    keys = extract_keys_from_markdown(markdown_path.read_text(encoding="utf-8"), patterns)
    if not keys:
        raise SystemExit(f"no valid keys found in markdown file for {cli}: {markdown_path}")
    if len(keys) < len(eligible):
        raise SystemExit(f"insufficient keys for {cli}: eligible_users={len(eligible)} available_keys={len(keys)} source={markdown_path}")
    rng = cli_rng(seed, month, cli)
    shuffled_keys = list(keys)
    shuffled_users = list(eligible)
    rng.shuffle(shuffled_keys)
    rng.shuffle(shuffled_users)
    sealed_records = []
    for user, api_key in zip(shuffled_users, shuffled_keys):
        payload = resolve_payload_fields(user, cli, month, cli_defaults, cli_registry)
        payload["api_key"] = api_key
        sealed_records.append(seal_payload(user["_resolved_password"], payload))
    rng.shuffle(sealed_records)
    bundle_filename = f"{cli}.bundle.json"
    bundle = {"version": 1, "cli": cli, "month": month, "generated_at": utc_now_iso(), "record_count": len(sealed_records), "records": sealed_records}
    out_path = output_dir / bundle_filename
    dump_json(out_path, bundle)
    bundle_sha256 = sha256_file(out_path)
    print(f"BUILT {out_path} records={len(sealed_records)} source_keys={len(keys)}")
    return {
        "cli": cli,
        "file": bundle_filename,
        "sha256": bundle_sha256,
        "record_count": len(sealed_records),
        "source_markdown": markdown_path.name,
        "available_key_count": len(keys),
        "used_key_count": len(sealed_records),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build monthly per-CLI encrypted bundles from *_apikey.md files")
    parser.add_argument("--input-root", required=True, help="directory containing *_apikey.md files and users.json")
    parser.add_argument("--users-file", default="", help="optional users json path; defaults to <input-root>/users.json")
    parser.add_argument("--output-dir", required=True, help="output directory for bundle files")
    parser.add_argument("--month", required=True, type=parse_month, help="bundle month in YYYY-MM format")
    parser.add_argument("--cli", action="append", default=[], help="build only one CLI; may be passed multiple times")
    parser.add_argument("--seed", default="", help="optional deterministic seed for tests/reproducible builds")
    parser.add_argument("--verify", action="store_true", help="read back every produced bundle using each eligible password")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    input_root = Path(args.input_root).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    users_path = Path(args.users_file).expanduser().resolve() if args.users_file else input_root / "users.json"
    cli_registry = load_cli_registry()
    _config, raw_users, cli_defaults = load_users_config(users_path)
    users = normalize_users(raw_users, cli_defaults)
    targets = determine_target_clis(users, cli_defaults, args.cli)
    manifest_entries = []
    for cli in targets:
        result = build_bundle_for_cli(cli=cli, month=args.month, input_root=input_root, output_dir=output_dir, users=users, cli_defaults=cli_defaults, cli_registry=cli_registry, seed=args.seed)
        if result is not None:
            manifest_entries.append(result)
            if args.verify:
                eligible = effective_users_for_cli(users, cli)
                summary = verify_bundle_for_cli(output_dir / result["file"], cli, args.month, eligible)
                print(f"VERIFY {summary}")
    if not manifest_entries:
        raise SystemExit("no bundles were produced")
    manifest_path = output_dir / "manifest.json"
    dump_json(manifest_path, {"version": 1, "month": args.month, "generated_at": utc_now_iso(), "bundle_count": len(manifest_entries), "bundles": manifest_entries})
    print(f"WROTE {manifest_path}")
    update_output_root_index(output_dir, args.month)
    print(f"WROTE {output_dir.parent / 'index.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
