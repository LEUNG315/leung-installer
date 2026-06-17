#!/usr/bin/env python3
import json
import os
from pathlib import Path


def clone_data(data):
    return json.loads(json.dumps(data))


def expand_path(path_s: str) -> Path:
    return Path(path_s).expanduser()


def atomic_write_text(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(content, encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
