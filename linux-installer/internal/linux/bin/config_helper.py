#!/usr/bin/env python3
import json
import sys
from pathlib import Path

from config_helper_auth import (
    build_default_auth,
    ensure_auth,
    get_auth_field,
    get_auth_key,
    set_auth_field,
    set_auth_key,
)
from config_helper_config import (
    build_default_config,
    cluster_check,
    ensure_config,
    load_config,
    upsert_config_key,
)
from config_helper_native import (
    extract_claude_key_value,
    extract_claude_model_value,
    extract_claude_url_value,
    extract_codex_key_value,
    extract_codex_model_value,
    extract_codex_url_value,
    extract_gemini_key_value,
    extract_gemini_model_value,
    extract_gemini_url_value,
    render_claude,
    render_codex,
    render_codex_auth,
    render_gemini_env,
    render_gemini_settings,
    update_actual_key,
    update_actual_url,
    write_native_config,
)

DEFAULT_REGISTRY_PATH = Path(__file__).resolve().parents[1] / "manifests" / "cli-registry.json"


def load_registry(path: Path | None = None):
    registry_path = path or DEFAULT_REGISTRY_PATH
    data = json.loads(Path(registry_path).read_text(encoding="utf-8"))
    items = data.get("clis", [])
    result = {}
    for item in items:
        result[item["id"]] = item
    return result


CLI_REGISTRY = load_registry()


def cli_entry(cli: str):
    try:
        return CLI_REGISTRY[cli]
    except KeyError as exc:
        raise KeyError(f"unknown cli: {cli}") from exc


def registry_list(path_s: str | None = None):
    registry = load_registry(Path(path_s)) if path_s else CLI_REGISTRY
    for cli in registry:
        print(cli)


def registry_get(path_s: str | None, cli: str, field: str):
    registry = load_registry(Path(path_s)) if path_s else CLI_REGISTRY
    entry = registry[cli]
    value = entry
    for part in field.split("."):
        if isinstance(value, dict):
            value = value.get(part, "")
        else:
            value = ""
            break
    if isinstance(value, bool):
        print("1" if value else "0")
    else:
        print(value)


DEFAULT_CONFIG = build_default_config(CLI_REGISTRY, cli_entry)
DEFAULT_AUTH = build_default_auth(CLI_REGISTRY, cli_entry)


def provider_key(cli: str) -> str:
    return cli_entry(cli)["provider_key"]


def print_value(value):
    print(value if value is not None else "")


def build_command_table():
    return {
        "registry-list": lambda argv: registry_list(argv[2] if len(argv) > 2 else None),
        "registry-get": lambda argv: registry_get(argv[2], argv[3], argv[4]),
        "ensure-config": lambda argv: ensure_config(argv[2], DEFAULT_CONFIG, CLI_REGISTRY, cli_entry),
        "ensure-auth": lambda argv: ensure_auth(argv[2], DEFAULT_AUTH),
        "get-provider-url": lambda argv: print_value(load_config(Path(argv[2]).expanduser(), DEFAULT_CONFIG).get("providers", {}).get(provider_key(argv[3]), "")),
        "get-auth-key": lambda argv: get_auth_key(argv[2], argv[3], DEFAULT_AUTH),
        "get-auth-field": lambda argv: get_auth_field(argv[2], argv[3], argv[4], DEFAULT_AUTH),
        "set-auth-key": lambda argv: set_auth_key(argv[2], argv[3], argv[4], DEFAULT_AUTH, cli_entry),
        "set-auth-field": lambda argv: set_auth_field(argv[2], argv[3], argv[4], argv[5], DEFAULT_AUTH, cli_entry),
        "set-provider-url": lambda argv: upsert_config_key(Path(argv[2]).expanduser(), "providers", provider_key(argv[3]), argv[4], DEFAULT_CONFIG, CLI_REGISTRY, cli_entry),
        "get-model": lambda argv: print_value(load_config(Path(argv[2]).expanduser(), DEFAULT_CONFIG)["models"].get(argv[3], DEFAULT_CONFIG["models"][argv[3]])),
        "set-model": lambda argv: upsert_config_key(Path(argv[2]).expanduser(), "models", argv[3], argv[4], DEFAULT_CONFIG, CLI_REGISTRY, cli_entry),
        "render-claude": lambda argv: render_claude(cli_entry, argv[2], argv[3], argv[4], argv[5]),
        "render-codex": lambda argv: render_codex(cli_entry, argv[2], argv[3], argv[4], argv[5]),
        "render-codex-auth": lambda argv: render_codex_auth(cli_entry, argv[2], argv[3]),
        "render-gemini-settings": lambda argv: render_gemini_settings(cli_entry, argv[2], argv[3]),
        "render-gemini-env": lambda argv: render_gemini_env(cli_entry, argv[2], argv[3], argv[4], argv[5]),
        "write-native-config": lambda argv: write_native_config(cli_entry, argv[2], argv[3], argv[4], argv[5], argv[6]),
        "update-actual-key": lambda argv: update_actual_key(cli_entry, argv[2], argv[3], argv[4]),
        "update-actual-url": lambda argv: update_actual_url(cli_entry, argv[2], argv[3], argv[4]),
        "extract-claude-key": lambda argv: print_value(extract_claude_key_value(argv[2])),
        "extract-claude-url": lambda argv: print_value(extract_claude_url_value(argv[2])),
        "extract-claude-model": lambda argv: print_value(extract_claude_model_value(argv[2])),
        "extract-codex-key": lambda argv: print_value(extract_codex_key_value(argv[2])),
        "extract-codex-url": lambda argv: print_value(extract_codex_url_value(argv[2])),
        "extract-codex-model": lambda argv: print_value(extract_codex_model_value(argv[2])),
        "extract-gemini-key": lambda argv: print_value(extract_gemini_key_value(argv[2])),
        "extract-gemini-url": lambda argv: print_value(extract_gemini_url_value(argv[2])),
        "extract-gemini-model": lambda argv: print_value(extract_gemini_model_value(argv[2])),
        "cluster-check": lambda argv: cluster_check(argv[2], DEFAULT_CONFIG),
    }


def main(argv):
    if len(argv) < 2:
        raise SystemExit("usage: config_helper.py <command> ...")
    cmd = argv[1]
    handler = build_command_table().get(cmd)
    if handler is None:
        raise SystemExit(f"unknown command: {cmd}")
    handler(argv)


if __name__ == "__main__":
    main(sys.argv)
