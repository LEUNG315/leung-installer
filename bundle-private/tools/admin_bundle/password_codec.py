#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import hmac
import secrets

SUPPORTED_CLIS = ("claude", "codex", "gemini", "opencode")


def encode_password(password: str, iterations: int = 200_000) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), iterations)
    return f"pbkdf2_sha256${iterations}${salt}${digest.hex()}"


def verify_password(stored_hash: str, password: str) -> bool:
    try:
        algorithm, iterations_s, salt, expected_hex = stored_hash.split("$", 3)
        iterations = int(iterations_s)
    except ValueError:
        return False
    if algorithm != "pbkdf2_sha256":
        return False
    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), iterations).hex()
    return hmac.compare_digest(actual, expected_hex)
