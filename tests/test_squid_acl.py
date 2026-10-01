#!/usr/bin/env python3
"""Static checks on Squid policy template (no squid binary required)."""

import unittest
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parents[1] / "config" / "squid.conf.template"


class TestSquidAcl(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = TEMPLATE.read_text(encoding="utf-8")
        cls.lines = cls.text.splitlines()

    def test_default_deny_last(self):
        deny_all_idx = max(i for i, l in enumerate(self.lines) if l.strip() == "http_access deny all")
        allow_auth = [i for i, l in enumerate(self.lines) if l.strip() == "http_access allow authenticated"]
        self.assertTrue(allow_auth, "missing allow authenticated")
        self.assertGreater(deny_all_idx, allow_auth[-1])

    def test_maxconn_denies_over_limit_not_under(self):
        self.assertIn("http_access deny max_conn_per_client", self.text)
        self.assertNotIn("http_access deny !max_conn_per_client", self.text)

    def test_connect_port_443_only(self):
        self.assertIn("http_access deny CONNECT !SSL_ports", self.text)
        self.assertIn("acl SSL_ports port 443", self.text)
        self.assertIn("http_access deny !CONNECT", self.text)

    def test_no_destination_allowlist(self):
        self.assertNotIn("allowed_app_domains", self.text)

    def test_auth_before_allow(self):
        unauth = self.text.index("http_access deny !authenticated")
        allow = self.text.index("http_access allow authenticated")
        self.assertLess(unauth, allow)

    def test_no_ssl_bump_directives(self):
        self.assertNotIn("ssl_bump", self.text)

    def test_ip_literal_denies(self):
        self.assertIn("http_access deny dst_ipv4_literal", self.text)

    def test_http_access_ordering_contract(self):
        keys = [
            "http_access deny !authenticated",
            "http_access deny max_conn_per_client",
            "http_access deny !Safe_ports",
            "http_access deny !CONNECT",
            "http_access deny CONNECT !SSL_ports",
            "http_access allow authenticated",
            "http_access deny all",
        ]
        positions = [self.text.index(k) for k in keys]
        self.assertEqual(positions, sorted(positions))


if __name__ == "__main__":
    unittest.main()
