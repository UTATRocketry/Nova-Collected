"""Unit tests for guard.assert_sandbox: each unsafe case is rejected.

Runs under pytest or `python -m unittest` (stdlib only).
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from guard import SandboxViolation, assert_sandbox, is_loopback  # noqa: E402

NO_ENV = {}


def check(**kw):
    """assert_sandbox with a safe baseline and no host environment."""
    args = dict(
        broker_host="127.0.0.1",
        broker_port=45001,
        http_ports=[45002, 45003],
        paths=[Path(tempfile.gettempdir()) / "nova-test"],
        env=NO_ENV,
        settings_file=Path("does-not-exist.ps1"),
    )
    args.update(kw)
    assert_sandbox(**args)


class SafeCases(unittest.TestCase):
    def test_baseline_passes(self):
        check()

    def test_ipv6_and_localhost_pass(self):
        check(broker_host="::1")
        check(broker_host="localhost")
        check(broker_host="[::1]")

    def test_unrelated_env_ignored(self):
        check(env={"PATH": "C:/Nova/bin", "NOVA_ENV": "dev", "HOME": "/x"})


class UnsafeBroker(unittest.TestCase):
    def test_non_loopback_hosts(self):
        for host in ("192.168.137.1", "10.0.0.5", "0.0.0.0", "nova-server", ""):
            with self.subTest(host=host), self.assertRaises(SandboxViolation):
                check(broker_host=host)

    def test_protected_broker_port(self):
        with self.assertRaises(SandboxViolation):
            check(broker_port=1883)

    def test_invalid_ports(self):
        for port in (0, -1, 70000, "1883", None, True):
            with self.subTest(port=port), self.assertRaises(SandboxViolation):
                check(broker_port=port)


class UnsafeHttpPorts(unittest.TestCase):
    def test_every_station_port(self):
        for port in (1883, 8000, 8001, 3000, 3001, 8080, 8081):
            with self.subTest(port=port), self.assertRaises(SandboxViolation):
                check(http_ports=[45002, port])

    def test_port_from_settings_file(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "nova.settings.ps1"
            f.write_text("BackendPort   = 9123\nPort        = 1883\n")
            with self.assertRaises(SandboxViolation):
                check(http_ports=[9123], settings_file=f)
            check(http_ports=[9124], settings_file=f)


class UnsafePaths(unittest.TestCase):
    def test_station_root(self):
        for p in (r"C:\Nova", r"C:\Nova\config\prod", "c:/nova/data", r"C:\NOVA\dev\backend"):
            with self.subTest(path=p), self.assertRaises(SandboxViolation):
                check(paths=[p])

    def test_lookalike_root_is_fine(self):
        check(paths=[r"C:\Nova-Collected-scratch\x"])

    def test_custom_root_from_settings_file(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "nova.settings.ps1"
            f.write_text("Root = 'D:\\Station'\nDataRoot = 'E:\\rec'\n")
            for p in (r"D:\Station\logs", r"E:\rec\prod"):
                with self.subTest(path=p), self.assertRaises(SandboxViolation):
                    check(paths=[p], settings_file=f)

    def test_extra_station_root(self):
        with self.assertRaises(SandboxViolation):
            check(paths=["/srv/nova/config"], station_roots=["/srv/nova"])

    def test_repo_config_and_data_dirs(self):
        repo = Path(tempfile.gettempdir()) / "fake-repo"
        for sub in ("config", "data", "config/history"):
            with self.subTest(sub=sub), self.assertRaises(SandboxViolation):
                check(paths=[repo / sub], protected_dirs=[repo / "config", repo / "data"])
        check(paths=[repo / "tmp"], protected_dirs=[repo / "config", repo / "data"])


class UnsafeEnv(unittest.TestCase):
    def test_env_path_at_station(self):
        for name in ("NOVA_CONFIG_DIR", "NOVA_CONFIG_HISTORY_DIR", "NOVA_DATA_DIR"):
            with self.subTest(name=name), self.assertRaises(SandboxViolation):
                check(env={name: r"C:\Nova\config"})

    def test_env_station_port_and_remote_host(self):
        with self.assertRaises(SandboxViolation):
            check(env={"NOVA_MQTT_PORT": "1883"})
        with self.assertRaises(SandboxViolation):
            check(env={"NOVA_MQTT_HOST": "192.168.137.1"})
        check(env={"NOVA_MQTT_HOST": "127.0.0.1", "NOVA_MQTT_PORT": "45001"})

    def test_message_lists_every_problem(self):
        with self.assertRaises(SandboxViolation) as cm:
            check(broker_host="10.0.0.1", broker_port=1883)
        self.assertIn("not loopback", str(cm.exception))
        self.assertIn("station port", str(cm.exception))


class Loopback(unittest.TestCase):
    def test_is_loopback(self):
        self.assertTrue(is_loopback("127.0.0.5"))
        self.assertFalse(is_loopback("192.168.1.1"))
        self.assertFalse(is_loopback("example.com"))


if __name__ == "__main__":
    unittest.main()
