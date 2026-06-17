#!/usr/bin/env python3
import os
import re
from pathlib import Path

from config_helper_shared import atomic_write_text, clone_data, expand_path

SECTION_RE = re.compile(r"^\[(?P<section>[^\]]+)]\s*$")
KEY_RE = re.compile(r"^(?P<key>[A-Za-z0-9_]+)\s*=\s*(?P<value>.+?)\s*$")
ASSIGNMENT_RE = re.compile(r"^(?P<indent>\s*)(?P<key>[A-Za-z0-9_]+)(?P<sep>\s*=\s*)(?P<rest>.*)$")
DEFAULT_CLUSTER_GUARD = {
    "enabled": True,
    "mode": "blocklisted_only",
    "blocked_env_keys": [
        "SLURM_JOB_ID",
        "PBS_JOBID",
        "LSB_JOBID",
        "COBALT_JOBID",
        "AWS_BATCH_JOB_ID",
        "KUBERNETES_SERVICE_HOST",
    ],
    "blocked_env_values": [],
    "blocked_hostname_patterns": [],
    "blocked_cgroup_patterns": ["kubepods"],
}


def toml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render_scalar(value) -> str:
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, list):
        return "[%s]" % ", ".join(f'"{toml_escape(str(item))}"' for item in value)
    return f'"{toml_escape(str(value))}"'


def split_value_comment(raw: str):
    in_string = False
    escaped = False
    for index, char in enumerate(raw):
        if escaped:
            escaped = False
            continue
        if in_string and char == "\\":
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if char == "#" and not in_string:
            value = raw[:index].rstrip()
            return value, raw[len(value):]
    return raw.rstrip(), ""


def parse_array(value: str):
    value = value.strip()
    if value == "[]":
        return []
    inner = value.strip()[1:-1].strip()
    if not inner:
        return []
    parts = re.findall(r'"((?:\\.|[^"])*)"', inner)
    return [p.replace('\\"', '"').replace('\\\\', '\\') for p in parts]


def parse_scalar(value: str):
    value, _ = split_value_comment(value)
    value = value.strip()
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1].replace('\\"', '"').replace('\\\\', '\\')
    if value in {"true", "false"}:
        return value == "true"
    if value.startswith("[") and value.endswith("]"):
        return parse_array(value)
    return value


def build_default_config(cli_registry: dict, cli_entry):
    return {
        "providers": {
            **{cli_entry(cli)["provider_key"]: "" for cli in cli_registry},
        },
        "models": {
            **{cli: cli_entry(cli)["default_model"] for cli in cli_registry},
        },
        "cluster_guard": dict(DEFAULT_CLUSTER_GUARD),
    }


def load_config(path: Path, default_config: dict):
    data = clone_data(default_config)
    if not path.exists():
        return data
    current = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        sec = SECTION_RE.match(line)
        if sec:
            current = sec.group("section")
            data.setdefault(current, {})
            continue
        m = KEY_RE.match(line)
        if m and current:
            data.setdefault(current, {})[m.group("key")] = parse_scalar(m.group("value"))
    return data


def write_config(path: Path, data: dict, cli_registry: dict, cli_entry, default_config: dict):
    provider_lines = [
        f'{cli_entry(cli)["provider_key"]} = {render_scalar(data["providers"].get(cli_entry(cli)["provider_key"], ""))}'
        for cli in cli_registry
    ]
    model_lines = [
        f'{cli} = {render_scalar(data["models"].get(cli, default_config["models"][cli]))}'
        for cli in cli_registry
    ]
    lines = [
        "[providers]",
        *provider_lines,
        "",
        "[models]",
        *model_lines,
        "",
        "[cluster_guard]",
        f'enabled = {render_scalar(bool(data["cluster_guard"].get("enabled", True)))}',
        f'mode = {render_scalar(data["cluster_guard"].get("mode", "blocklisted_only"))}',
        f'blocked_env_keys = {render_scalar(data["cluster_guard"].get("blocked_env_keys", []))}',
        f'blocked_env_values = {render_scalar(data["cluster_guard"].get("blocked_env_values", []))}',
        f'blocked_hostname_patterns = {render_scalar(data["cluster_guard"].get("blocked_hostname_patterns", []))}',
        f'blocked_cgroup_patterns = {render_scalar(data["cluster_guard"].get("blocked_cgroup_patterns", []))}',
        "",
    ]
    atomic_write_text(path, "\n".join(lines))


def upsert_config_key(path: Path, section: str, key: str, value, default_config: dict, cli_registry: dict, cli_entry):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        data = clone_data(default_config)
        data.setdefault(section, {})[key] = value
        write_config(path, data, cli_registry, cli_entry, default_config)
        return

    lines = path.read_text(encoding="utf-8").splitlines()
    target_key_index = None
    target_section_start = None
    target_section_end = len(lines)
    current_section = None

    for index, line in enumerate(lines):
        stripped = line.strip()
        sec = SECTION_RE.match(stripped)
        if sec:
            section_name = sec.group("section").strip()
            if current_section == section and target_section_end == len(lines):
                target_section_end = index
            current_section = section_name
            if section_name == section and target_section_start is None:
                target_section_start = index
            continue
        if current_section != section:
            continue
        assignment = ASSIGNMENT_RE.match(line)
        if assignment and assignment.group("key") == key:
            target_key_index = index

    rendered = render_scalar(value)
    if target_key_index is not None:
        assignment = ASSIGNMENT_RE.match(lines[target_key_index])
        _, comment = split_value_comment(assignment.group("rest"))
        lines[target_key_index] = f'{assignment.group("indent")}{key}{assignment.group("sep")}{rendered}{comment}'
    elif target_section_start is not None:
        insert_at = target_section_end
        while insert_at > target_section_start + 1 and not lines[insert_at - 1].strip():
            insert_at -= 1
        lines.insert(insert_at, f"{key} = {rendered}")
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([f"[{section}]", f"{key} = {rendered}"])

    atomic_write_text(path, "\n".join(lines) + "\n")


def ensure_config(path_s: str, default_config: dict, cli_registry: dict, cli_entry):
    path = expand_path(path_s)
    if not path.exists():
        write_config(path, default_config, cli_registry, cli_entry, default_config)


def cluster_check(path_s: str, default_config: dict):
    cfg = load_config(expand_path(path_s), default_config)
    guard = cfg.get("cluster_guard", {})
    if not guard.get("enabled", True):
        print("ALLOW")
        return
    blocked_values = set(guard.get("blocked_env_values", []))
    for key in guard.get("blocked_env_keys", []):
        val = os.environ.get(key)
        if val and (not blocked_values or val in blocked_values):
            print(f"BLOCK:env:{key}={val}")
            return
    hostname = os.uname().nodename
    for pattern in guard.get("blocked_hostname_patterns", []):
        regex = "^" + re.escape(pattern).replace("\\*", ".*") + "$"
        if re.match(regex, hostname):
            print(f"BLOCK:hostname:{hostname}")
            return
    try:
        cgroup = Path("/proc/1/cgroup").read_text(encoding="utf-8", errors="ignore")
    except Exception:
        cgroup = ""
    for pattern in guard.get("blocked_cgroup_patterns", []):
        if pattern and pattern in cgroup:
            print(f"BLOCK:cgroup:{pattern}")
            return
    print("ALLOW")
