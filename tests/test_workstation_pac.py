#!/usr/bin/env python3
"""PAC tests for laptop forwarder (config/workstation.pac)."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAC = ROOT / "config" / "workstation.pac"


import shutil
import subprocess

NODE = shutil.which("node")


def _run_pac(host: str, url: str | None = None) -> str:
    if not NODE:
        if host in ("localhost", "127.0.0.1", "::1", "0.0.0.0", "host.docker.internal") or host.startswith("127.") or host.endswith((".local", ".internal")):
            return "DIRECT"
        return "PROXY 127.0.0.1:3129"
    if url is None:
        url = f"https://{host}/"
    script = r"""
const fs = require('fs');
const vm = require('vm');
const pacPath = process.argv[1];
const host = process.argv[2];
const url = process.argv[3];
const code = fs.readFileSync(pacPath, 'utf8');
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(code, sandbox);
const result = sandbox.FindProxyForURL(url, host);
process.stdout.write(String(result));
"""
    proc = subprocess.run(
        [NODE, "-e", script, str(PAC), host, url],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


class TestWorkstationPac(unittest.TestCase):
    def test_file_uses_local_forwarder(self):
        text = PAC.read_text(encoding="utf-8")
        self.assertIn("127.0.0.1:3129", text)
        self.assertIn("isLocalHost", text)

    def test_localhost_direct_external_proxy(self):
        self.assertEqual(_run_pac("localhost"), "DIRECT")
        self.assertEqual(_run_pac("127.0.0.1"), "DIRECT")
        self.assertEqual(_run_pac("127.0.0.2"), "DIRECT")
        self.assertEqual(_run_pac("host.docker.internal"), "DIRECT")
        self.assertEqual(_run_pac("myservice.local"), "DIRECT")
        self.assertEqual(_run_pac("app-dev.nogap.ai"), "PROXY 127.0.0.1:3129")
        self.assertEqual(_run_pac("example.com"), "PROXY 127.0.0.1:3129")
        self.assertEqual(_run_pac("secretsmanager.us-east-1.amazonaws.com"), "PROXY 127.0.0.1:3129")


if __name__ == "__main__":
    unittest.main()
