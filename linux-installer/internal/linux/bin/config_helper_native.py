#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path

from config_helper_shared import atomic_write_text

TEMPLATES_DIR = Path(__file__).resolve().parents[3] / "templates"


def load_template_text(*parts: str) -> str:
    return (TEMPLATES_DIR.joinpath(*parts)).read_text(encoding="utf-8")


def load_template_json(*parts: str):
    return json.loads(load_template_text(*parts))


def read_json_if_exists(path: Path, fallback):
    if not path.exists():
        return fallback
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return fallback


def toml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def parse_toml_model_value(path_s: str) -> str:
    path = Path(path_s)
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r'^model\s*=\s*"((?:\\.|[^"])*)"', line)
        if m:
            return m.group(1).replace('\\"', '"').replace('\\\\', '\\')
    return ""


def cli_native_path(cli_entry, cli: str, kind: str, home_dir: str) -> str:
    rel = cli_entry(cli).get("native_paths", {}).get(kind, "")
    if not rel:
        return ""
    return str(Path(home_dir).expanduser() / rel)


def render_claude(cli_entry, path_s: str, key: str, url: str, model: str):
    entry = cli_entry("claude")
    payload = load_template_json(*entry["templates"]["primary"].split("/"))
    env = payload.setdefault("env", {})
    env["ANTHROPIC_BASE_URL"] = url
    if "ANTHROPIC_AUTH_TOKEN" in env:
        env["ANTHROPIC_AUTH_TOKEN"] = key
    else:
        env["ANTHROPIC_API_KEY"] = key
    Path(path_s).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def render_codex(cli_entry, path_s: str, key: str, url: str, model: str):
    entry = cli_entry("codex")
    content = load_template_text(*entry["templates"]["primary"].split("/"))
    content = re.sub(r'^model\s*=\s*".*?"\s*$', f'model = "{toml_escape(model)}"', content, flags=re.M)
    content = re.sub(r'^\s*base_url\s*=\s*".*?"\s*$', f'base_url = "{toml_escape(url)}"', content, flags=re.M)
    Path(path_s).write_text(content, encoding="utf-8")


def render_codex_auth(cli_entry, path_s: str, key: str):
    entry = cli_entry("codex")
    payload = load_template_json(*entry["templates"]["secondary"].split("/"))
    payload["OPENAI_API_KEY"] = key
    Path(path_s).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def render_gemini_settings(cli_entry, path_s: str, model: str):
    entry = cli_entry("gemini")
    payload = load_template_json(*entry["templates"]["primary"].split("/"))
    payload.setdefault("model", {})["name"] = model
    Path(path_s).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def render_gemini_env(cli_entry, path_s: str, key: str, url: str, model: str):
    entry = cli_entry("gemini")
    content = load_template_text(*entry["templates"]["secondary"].split("/"))
    content = re.sub(r'^GEMINI_API_KEY=.*$', f'GEMINI_API_KEY={key}', content, flags=re.M)
    content = re.sub(r'^GOOGLE_GEMINI_BASE_URL=.*$', f'GOOGLE_GEMINI_BASE_URL={url}', content, flags=re.M)
    content = re.sub(r'^GEMINI_MODEL=.*$', f'GEMINI_MODEL={model}', content, flags=re.M)
    Path(path_s).write_text(content, encoding="utf-8")


def write_native_config(cli_entry, cli: str, home_dir: str, key: str, url: str, model: str):
    primary = cli_native_path(cli_entry, cli, "primary", home_dir)
    secondary = cli_native_path(cli_entry, cli, "secondary", home_dir)
    if not primary:
        raise SystemExit(f"missing primary native path for cli: {cli}")

    primary_path = Path(primary)
    primary_path.parent.mkdir(parents=True, exist_ok=True)
    if secondary:
        Path(secondary).parent.mkdir(parents=True, exist_ok=True)

    if cli == "claude":
        render_claude(cli_entry, primary, key, url, model)
        os.chmod(primary, 0o600)
        return
    if cli == "codex":
        render_codex(cli_entry, primary, key, url, model)
        render_codex_auth(cli_entry, secondary, key)
        os.chmod(primary, 0o600)
        os.chmod(secondary, 0o600)
        return
    if cli == "gemini":
        render_gemini_settings(cli_entry, primary, model)
        render_gemini_env(cli_entry, secondary, key, url, model)
        os.chmod(primary, 0o600)
        os.chmod(secondary, 0o600)
        return
    raise SystemExit(f"unsupported cli for native config write: {cli}")


def extract_claude_key_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    env = data.get("env", {}) if isinstance(data, dict) else {}
    return env.get("ANTHROPIC_API_KEY", "") or env.get("ANTHROPIC_AUTH_TOKEN", "")


def extract_claude_url_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    env = data.get("env", {}) if isinstance(data, dict) else {}
    return env.get("ANTHROPIC_BASE_URL", "") or env.get("ANTHROPIC_API_BASE_URL", "") or env.get("ANTHROPIC_API_URL", "")


def extract_claude_model_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("model", "") if isinstance(data, dict) else ""


def extract_codex_key_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("OPENAI_API_KEY", "") or data.get("openai_api_key", "") or data.get("api_key", "")


def extract_codex_url_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    m = re.search(r'^openai_base_url\s*=\s*"(.*)"\s*$', text, re.M)
    if m:
        return m.group(1).replace('\\"', '"')
    provider = re.search(r'^model_provider\s*=\s*"(.*)"\s*$', text, re.M)
    if provider:
        provider_id = re.escape(provider.group(1))
        block = re.search(r'^\[model_providers\.' + provider_id + r'\]\s*$([\s\S]*?)(?=^\[|\Z)', text, re.M)
        if block:
            inner = block.group(1)
            m2 = re.search(r'^\s*base_url\s*=\s*"(.*)"\s*$', inner, re.M)
            if m2:
                return m2.group(1).replace('\\"', '"')
    m3 = re.search(r'^\s*base_url\s*=\s*"(https?://.*)"\s*$', text, re.M)
    return m3.group(1).replace('\\"', '"') if m3 else ""


def extract_codex_model_value(path_s: str):
    return parse_toml_model_value(path_s)


def extract_gemini_key_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    for key in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        m = re.search(rf'^{re.escape(key)}="(.*)"\s*$', text, re.M)
        if m:
            return m.group(1).replace('\\"', '"')
        m2 = re.search(rf'^{re.escape(key)}=([^\n\r#]+?)\s*$', text, re.M)
        if m2:
            return m2.group(1).strip()
    return ""


def extract_gemini_url_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8")
    for key in ("GOOGLE_GEMINI_BASE_URL", "GEMINI_BASE_URL", "OPENAI_BASE_URL"):
        m = re.search(rf'^{re.escape(key)}="(.*)"\s*$', text, re.M)
        if m:
            return m.group(1).replace('\\"', '"')
        m2 = re.search(rf'^{re.escape(key)}=([^\n\r#]+?)\s*$', text, re.M)
        if m2:
            return m2.group(1).strip()
    return ""


def extract_gemini_model_value(path_s: str):
    path = Path(path_s)
    if not path.exists():
        return ""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return ""
    model = data.get("model", "")
    if isinstance(model, dict):
        return model.get("name", "")
    return model


def update_actual_key(cli_entry, cli: str, path_s: str, value: str):
    path = Path(path_s)
    if cli == "claude":
        payload = read_json_if_exists(path, load_template_json(*cli_entry("claude")["templates"]["primary"].split("/")))
        env = payload.setdefault("env", {})
        if "ANTHROPIC_AUTH_TOKEN" in env:
            env["ANTHROPIC_AUTH_TOKEN"] = value
            env.pop("ANTHROPIC_API_KEY", None)
        else:
            env["ANTHROPIC_API_KEY"] = value
            env.pop("ANTHROPIC_AUTH_TOKEN", None)
        atomic_write_text(path, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
        return
    if cli == "codex":
        payload = read_json_if_exists(path, {})
        payload["OPENAI_API_KEY"] = value
        atomic_write_text(path, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
        return
    if cli == "gemini":
        existing_url = extract_gemini_url_value(path_s) or "xxx"
        settings_path = str(path.with_name("settings.json"))
        existing_model = extract_gemini_model_value(settings_path) or cli_entry("gemini")["default_model"]
        render_gemini_env(cli_entry, path_s, value, existing_url, existing_model)
        return
    raise SystemExit(f"unsupported cli for actual key update: {cli}")


def update_actual_url(cli_entry, cli: str, path_s: str, value: str):
    path = Path(path_s)
    if cli == "claude":
        payload = read_json_if_exists(path, load_template_json(*cli_entry("claude")["templates"]["primary"].split("/")))
        payload.setdefault("env", {})["ANTHROPIC_BASE_URL"] = value
        atomic_write_text(path, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
        return
    if cli == "codex":
        current_key = extract_codex_key_value(str(path.with_name("auth.json"))) or "xxx"
        current_model = extract_codex_model_value(path_s) or cli_entry("codex")["default_model"]
        render_codex(cli_entry, path_s, current_key, value, current_model)
        return
    if cli == "gemini":
        current_key = extract_gemini_key_value(path_s) or "xxx"
        settings_path = str(path.with_name("settings.json"))
        current_model = extract_gemini_model_value(settings_path) or cli_entry("gemini")["default_model"]
        render_gemini_env(cli_entry, path_s, current_key, value, current_model)
        return
    raise SystemExit(f"unsupported cli for actual url update: {cli}")
