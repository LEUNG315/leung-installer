#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
from pathlib import Path
from urllib.request import urlopen

DEFAULT_PBKDF2_ITERATIONS = 200_000
CIPHER_NAME = "xor-pbkdf2-sha256"


class BundleError(Exception):
    pass


class InvalidBundleFormat(BundleError):
    pass


class InvalidBundlePassword(BundleError):
    pass


def pbkdf2_iterations() -> int:
    raw = str(os.environ.get("LEUNG_BUNDLE_PBKDF2_ITERATIONS", DEFAULT_PBKDF2_ITERATIONS)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise InvalidBundleFormat(f"invalid LEUNG_BUNDLE_PBKDF2_ITERATIONS: {raw}") from exc
    if value <= 0:
        raise InvalidBundleFormat("LEUNG_BUNDLE_PBKDF2_ITERATIONS must be positive")
    return value


def derive_keystream(password: str, salt: bytes, length: int, *, iterations: int | None = None) -> bytes:
    out = bytearray()
    counter = 0
    password_b = password.encode("utf-8")
    rounds = pbkdf2_iterations() if iterations is None else iterations
    while len(out) < length:
        block = hashlib.pbkdf2_hmac("sha256", password_b, salt + counter.to_bytes(4, "big"), rounds)
        out.extend(block)
        counter += 1
    return bytes(out[:length])


def xor_bytes(a: bytes, b: bytes) -> bytes:
    return bytes(x ^ y for x, y in zip(a, b))


def seal_payload(password: str, payload: dict) -> dict:
    plaintext = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    salt = secrets.token_bytes(16)
    stream = derive_keystream(password, salt, len(plaintext))
    ciphertext = xor_bytes(plaintext, stream)
    mac = hashlib.sha256(salt + ciphertext + password.encode("utf-8")).hexdigest()
    return {
        "version": 1,
        "cipher": CIPHER_NAME,
        "salt_b64": base64.b64encode(salt).decode("ascii"),
        "ciphertext_b64": base64.b64encode(ciphertext).decode("ascii"),
        "mac_sha256": mac,
    }


def open_sealed(password: str, sealed: dict) -> dict:
    if not isinstance(sealed, dict):
        raise InvalidBundleFormat("sealed payload must be a JSON object")
    if sealed.get("cipher") != CIPHER_NAME:
        raise InvalidBundleFormat(f"unsupported cipher: {sealed.get('cipher', '')}")
    try:
        salt = base64.b64decode(sealed["salt_b64"])
        ciphertext = base64.b64decode(sealed["ciphertext_b64"])
        expected = sealed["mac_sha256"]
    except KeyError as exc:
        raise InvalidBundleFormat(f"missing required field: {exc.args[0]}") from exc
    except Exception as exc:
        raise InvalidBundleFormat(f"invalid sealed payload encoding: {exc}") from exc

    actual = hashlib.sha256(salt + ciphertext + password.encode("utf-8")).hexdigest()
    if actual != expected:
        raise InvalidBundlePassword("invalid password or corrupted bundle")
    stream = derive_keystream(password, salt, len(ciphertext))
    plaintext = xor_bytes(ciphertext, stream)
    try:
        return json.loads(plaintext.decode("utf-8"))
    except Exception as exc:
        raise InvalidBundleFormat(f"invalid decrypted JSON payload: {exc}") from exc


def load_text(source: str) -> str:
    if source.startswith("http://") or source.startswith("https://"):
        with urlopen(source) as resp:
            return resp.read().decode("utf-8")
    return Path(source).read_text(encoding="utf-8")
