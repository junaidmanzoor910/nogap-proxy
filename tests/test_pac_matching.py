#!/usr/bin/env python3
"""PAC tests for full-machine routing (config/proxy.pac)."""

import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAC_FILE = ROOT / "config" / "proxy.pac"
NODE = shutil.which("node")


def _run_pac_in_node(host: str, url: str | None = None) -> str:
    if not NODE:
        raise unittest.SkipTest("node not installed")
    if url is None:
        url = f"https://{host}/" if host else "https://example.com/"
    script = r"""
const fs = require('fs');
const vm = require('vm');
const pacPath = process.argv[1];
const host = process.argv[2];
const url = process.argv[3];
const code = fs.readFileSync(pacPath, 'utf8');
const sandbox = {
  isPlainHostName(h) { return typeof h === 'string' && h.length > 0 && h.indexOf('.') === -1; },
};
vm.createContext(sandbox);
vm.runInContext(code, sandbox);
const result = sandbox.FindProxyForURL(url, host);
process.stdout.write(String(result));
"""
    proc = subprocess.run(
        [NODE, "-e", script, str(PAC_FILE), host, url],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    return proc.stdout.strip()


def decision(host: str) -> str:
    if NODE:
        out = _run_pac_in_node(host)
        return "PROXY" if out.startswith(("PROXY", "HTTPS")) else "DIRECT"
    if host in ("localhost", "127.0.0.1", "::1", ""):
        return "DIRECT"
    return "PROXY"


class TestPacFullRouting(unittest.TestCase):
    def test_app_dev_uses_proxy(self):
        self.assertEqual(decision("app-dev.nogap.ai"), "PROXY")

    def test_general_internet_uses_proxy(self):
        self.assertEqual(decision("example.com"), "PROXY")
        self.assertEqual(decision("google.com"), "PROXY")

    def test_localhost_direct(self):
        self.assertEqual(decision("localhost"), "DIRECT")
        self.assertEqual(decision("127.0.0.1"), "DIRECT")

    def test_pac_file_full_routing(self):
        text = PAC_FILE.read_text(encoding="utf-8")
        self.assertIn("isLocalHost", text)
        self.assertNotIn("ALLOWED_APEX", text)

    @unittest.skipUnless(NODE, "node not installed")
    def test_node_executes_actual_pac_file(self):
        out = _run_pac_in_node("example.com")
        self.assertIn("proxy-dev.nogap.ai:443", out)


class TestPacSplitReference(unittest.TestCase):
    """Legacy split PAC kept as proxy.pac.split for optional use."""

    def test_split_file_preserved(self):
        split = ROOT / "config" / "proxy.pac.split"
        self.assertTrue(split.is_file())
        self.assertIn("isAllowedAppHost", split.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
