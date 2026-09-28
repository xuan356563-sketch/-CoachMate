from __future__ import annotations

import re
import tomllib
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = BACKEND_ROOT / "requirements.lock"
DOCKERFILE_PATH = BACKEND_ROOT / "Dockerfile"


def _normalize(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def _dependency_name(requirement: str) -> str:
    matched = re.match(r"[A-Za-z0-9_.-]+", requirement)
    assert matched is not None, f"无法识别依赖声明：{requirement}"
    return _normalize(matched.group())


def test_runtime_direct_dependencies_are_pinned_with_hashes() -> None:
    project = tomllib.loads(
        (BACKEND_ROOT / "pyproject.toml").read_text(encoding="utf-8"),
    )
    direct = {
        _dependency_name(item)
        for item in project["project"]["dependencies"]
    }
    lock_text = LOCK_PATH.read_text(encoding="utf-8")
    pinned = {
        _normalize(match.group(1))
        for match in re.finditer(r"(?m)^([A-Za-z0-9_.-]+)==[^\s\\]+", lock_text)
    }

    assert direct <= pinned
    assert "--hash=sha256:" in lock_text
    for block in re.split(r"(?m)(?=^[A-Za-z0-9_.-]+==)", lock_text)[1:]:
        assert "--hash=sha256:" in block.split("\n    # via", 1)[0]


def test_docker_uses_digest_and_hash_locked_install() -> None:
    dockerfile = DOCKERFILE_PATH.read_text(encoding="utf-8")

    assert re.search(
        r"(?m)^FROM python:3\.13-slim@sha256:[0-9a-f]{64}$",
        dockerfile,
    )
    assert (
        "pip install --no-cache-dir --require-hashes -r requirements.lock"
        in dockerfile
    )
    assert "pip install --no-cache-dir ." not in dockerfile
