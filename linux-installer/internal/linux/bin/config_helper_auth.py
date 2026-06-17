#!/usr/bin/env python3
import json
import os
from pathlib import Path

from config_helper_shared import clone_data, expand_path


def build_default_auth(cli_registry: dict, cli_entry):
    return {
        "active_profile": "default",
        "profiles": {
            "default": {
                **{cli: dict(cli_entry(cli).get("auth_defaults", {})) for cli in cli_registry},
            }
        },
    }


def write_auth(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(path, 0o600)


def load_auth(path: Path, default_auth: dict):
    if not path.exists():
        return clone_data(default_auth)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        data = clone_data(default_auth)
    data.setdefault("active_profile", "default")
    data.setdefault("profiles", {})
    data["profiles"].setdefault("default", {})
    for cli, defaults in default_auth["profiles"]["default"].items():
        data["profiles"]["default"].setdefault(cli, defaults.copy())
        for key, value in defaults.items():
            data["profiles"]["default"][cli].setdefault(key, value)
    return data


def ensure_auth(path_s: str, default_auth: dict):
    path = expand_path(path_s)
    if not path.exists():
        write_auth(path, default_auth)


def get_auth_key(path_s: str, cli: str, default_auth: dict):
    data = load_auth(expand_path(path_s), default_auth)
    profile = data.get("active_profile", "default")
    print(data.get("profiles", {}).get(profile, {}).get(cli, {}).get("api_key", ""))


def set_auth_key(path_s: str, cli: str, value: str, default_auth: dict, cli_entry):
    path = expand_path(path_s)
    data = load_auth(path, default_auth)
    profile = data.get("active_profile", "default")
    data.setdefault("profiles", {}).setdefault(profile, {}).setdefault(cli, {})
    data["profiles"][profile][cli]["api_key"] = value
    for key, default_value in cli_entry(cli).get("auth_defaults", {}).items():
        data["profiles"][profile][cli].setdefault(key, default_value)
    write_auth(path, data)


def get_auth_field(path_s: str, cli: str, field: str, default_auth: dict):
    data = load_auth(expand_path(path_s), default_auth)
    profile = data.get("active_profile", "default")
    value = data.get("profiles", {}).get(profile, {}).get(cli, {}).get(field, "")
    print(value if value is not None else "")


def set_auth_field(path_s: str, cli: str, field: str, value: str, default_auth: dict, cli_entry):
    path = expand_path(path_s)
    data = load_auth(path, default_auth)
    profile = data.get("active_profile", "default")
    data.setdefault("profiles", {}).setdefault(profile, {}).setdefault(cli, {})
    data["profiles"][profile][cli][field] = value
    for key, default_value in cli_entry(cli).get("auth_defaults", {}).items():
        data["profiles"][profile][cli].setdefault(key, default_value)
    write_auth(path, data)
