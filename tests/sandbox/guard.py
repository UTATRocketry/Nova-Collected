"""Sandbox guard: refuse to run a test that could reach the live station.

The ops PC runs the prod and dev stacks against one shared Mosquitto on port
1883, so a test that publishes to nova/command there can move real valves.
Every fixture that starts a broker, backend or frontend calls assert_sandbox()
first. Stdlib only; a copy of this check lives in each code repo's
integration conftest.py (see TESTING-PLAN.md section 2.2).
"""

from __future__ import annotations

import ipaddress
import os
import re
from pathlib import Path
from typing import Iterable, Mapping, Optional

LOOPBACK_NAMES = {"localhost", "127.0.0.1", "::1"}

# Broker, prod/dev backend, frontend and console ports from
# ops/nova.settings.example.ps1.
PROTECTED_PORTS = frozenset({1883, 8000, 8001, 3000, 3001, 8080, 8081})

DEFAULT_STATION_ROOT = r"C:\Nova"

# NOVA_* variables that name a place a test must not touch. A value is
# unsafe when it is a path under the station root, or (for the *_HOST and
# *_PORT names) when it points at the broker or a protected port.
_PORT_RE = re.compile(r"\b[A-Za-z]*Port\s*=\s*(\d+)")
_ROOT_RE = re.compile(r"\b(?:Root|ConfigRoot|DataRoot|ArchiveDir|StateDir)\s*=\s*'([^']+)'")


class SandboxViolation(AssertionError):
    """Raised when a test setup could reach the live station."""


def _norm(path: object) -> str:
    """Normalise a path for comparison: absolute, lower-case, forward slashes.

    Windows station paths (C:\\Nova) are compared the same way on Linux, so the
    guard still rejects them when a Linux CI job is handed one.
    """
    text = str(path).replace("\\", "/")
    if not re.match(r"^[A-Za-z]:/", text):
        text = os.path.abspath(text).replace("\\", "/")
    text = re.sub(r"/+", "/", text).rstrip("/")
    return text.lower()


def _is_under(path: str, root: str) -> bool:
    return path == root or path.startswith(root + "/")


def is_loopback(host: str) -> bool:
    host = host.strip().strip("[]").lower()
    if host in LOOPBACK_NAMES:
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def station_settings_ports(settings_file: Optional[Path]) -> set:
    """Ports named in ops/nova.settings.ps1 (best effort; {} if absent)."""
    if not settings_file or not settings_file.is_file():
        return set()
    return {int(p) for p in _PORT_RE.findall(settings_file.read_text(errors="replace"))}


def station_settings_roots(settings_file: Optional[Path]) -> set:
    if not settings_file or not settings_file.is_file():
        return set()
    return set(_ROOT_RE.findall(settings_file.read_text(errors="replace")))


def default_settings_file() -> Path:
    return Path(__file__).resolve().parents[2] / "ops" / "nova.settings.ps1"


def assert_sandbox(
    broker_host: str,
    broker_port: int,
    http_ports: Iterable[int] = (),
    paths: Iterable[object] = (),
    *,
    env: Optional[Mapping[str, str]] = None,
    settings_file: Optional[Path] = None,
    station_roots: Iterable[str] = (),
    protected_dirs: Iterable[object] = (),
) -> None:
    """Raise SandboxViolation unless every argument stays inside a sandbox.

    broker_host / broker_port  the private Mosquitto the test will use
    http_ports                 ports the test will bind (backend, frontend...)
    paths                      every directory the test will read or write
    env                        process environment to check (default os.environ)
    settings_file              ops/nova.settings.ps1, for station-specific
                               ports and roots (default: the repo's copy)
    station_roots              extra station roots to refuse
    protected_dirs             a repo's own config/ and data/ directories
    """
    env = os.environ if env is None else env
    if settings_file is None:
        settings_file = default_settings_file()

    problems = []

    protected = set(PROTECTED_PORTS) | station_settings_ports(settings_file)

    if not is_loopback(str(broker_host)):
        problems.append(f"broker host {broker_host!r} is not loopback")
    ports = [("broker", broker_port)] + [("http", p) for p in http_ports]
    for kind, port in ports:
        if not isinstance(port, int) or isinstance(port, bool) or not 0 < port < 65536:
            problems.append(f"{kind} port {port!r} is not a valid port")
        elif port in protected:
            problems.append(f"{kind} port {port} is a station port")

    roots = {_norm(r) for r in station_roots}
    roots.add(_norm(DEFAULT_STATION_ROOT))
    roots |= {_norm(r) for r in station_settings_roots(settings_file)}
    protected_paths = {_norm(d) for d in protected_dirs}

    for p in paths:
        n = _norm(p)
        for root in roots:
            if _is_under(n, root):
                problems.append(f"path {p} is under the station root {root}")
        for d in protected_paths:
            if _is_under(n, d):
                problems.append(f"path {p} is inside protected directory {d}")

    for name, value in env.items():
        if not name.startswith("NOVA_") or not value:
            continue
        n = _norm(value)
        if any(_is_under(n, r) for r in roots):
            problems.append(f"{name} points at the station ({value})")
        elif name.endswith("_PORT") and value.isdigit() and int(value) in protected:
            problems.append(f"{name}={value} is a station port")
        elif name.endswith("_HOST") and not is_loopback(value):
            problems.append(f"{name}={value} is not loopback")

    if problems:
        raise SandboxViolation("not a sandbox: " + "; ".join(problems))
