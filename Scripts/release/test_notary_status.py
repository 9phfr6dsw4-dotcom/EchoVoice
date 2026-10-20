#!/usr/bin/env python3
"""Tests for notary_status.py. Run with: python3 -I Scripts/release/test_notary_status.py"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import notary_status as ns  # noqa: E402


def _b64url_decode(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _raw_to_der(raw):
    def integer(value):
        value = value.lstrip(b"\x00") or b"\x00"
        if value[0] & 0x80:
            value = b"\x00" + value
        return b"\x02" + bytes([len(value)]) + value
    body = integer(raw[:32]) + integer(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


class NotaryStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.key_path = os.path.join(cls.directory.name, "test-key.p8")
        cls.public_path = os.path.join(cls.directory.name, "test-key.pub")
        # A throwaway P-256 key in the same PKCS#8 PEM form as an App Store Connect .p8 file.
        subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", cls.key_path],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "pkey", "-in", cls.key_path, "-pubout", "-out", cls.public_path],
                       check=True, capture_output=True)
        with open(cls.key_path, "rb") as handle:
            cls.key = handle.read()

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_der_signature_becomes_64_bytes_and_back(self):
        raw = bytes(range(1, 33)) + bytes([0x80] + list(range(2, 33)))
        self.assertEqual(ns.der_to_raw_signature(_raw_to_der(raw)), raw)

    def test_short_integers_are_padded(self):
        raw = b"\x00" * 31 + b"\x05" + b"\x00" * 2 + bytes(range(30))
        self.assertEqual(ns.der_to_raw_signature(_raw_to_der(raw)), raw)

    def test_rejects_non_der(self):
        with self.assertRaises(ns.NotaryError):
            ns.der_to_raw_signature(b"\x01" * 70)

    def test_token_has_apple_claims_and_a_valid_es256_signature(self):
        token = ns.make_token(self.key, "ABC123DEFG", "11111111-2222-3333-4444-555555555555", now=1_800_000_000)
        header_text, payload_text, signature_text = token.split(".")
        self.assertEqual(json.loads(_b64url_decode(header_text)), {"alg": "ES256", "kid": "ABC123DEFG", "typ": "JWT"})
        payload = json.loads(_b64url_decode(payload_text))
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["iss"], "11111111-2222-3333-4444-555555555555")
        self.assertEqual(payload["exp"] - payload["iat"], ns.TOKEN_LIFETIME)
        self.assertLessEqual(ns.TOKEN_LIFETIME, 20 * 60)
        raw = _b64url_decode(signature_text)
        self.assertEqual(len(raw), 64)
        signature_path = os.path.join(self.directory.name, "token.sig")
        with open(signature_path, "wb") as handle:
            handle.write(_raw_to_der(raw))
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", self.public_path, "-signature", signature_path],
            input=f"{header_text}.{payload_text}".encode(), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_bad_key_fails_without_printing_it(self):
        with self.assertRaises(ns.NotaryError) as context:
            ns.make_token(b"not a key", "KEY", "ISSUER")
        self.assertNotIn("not a key", str(context.exception))

    def test_status_meanings(self):
        self.assertTrue(ns.interpret("Accepted"))
        self.assertFalse(ns.interpret("In Progress"))
        for refused in ("Invalid", "Rejected", "Something new"):
            with self.assertRaises(ns.NotaryError):
                ns.interpret(refused)

    def test_submission_id_must_be_a_uuid(self):
        with self.assertRaises(ns.NotaryError):
            ns.wait("../../other", timeout=1, interval=1)

    def test_wait_accepts_only_after_apple_finishes(self):
        submission = "11111111-2222-3333-4444-555555555555"
        replies = [{"data": {"attributes": {"status": status}}} for status in ("In Progress", "Accepted")]
        with patch.object(ns, "_credentials", return_value=(b"fixture", "key", "issuer")), \
                patch.object(ns, "make_token", return_value="fixture-token"), \
                patch.object(ns, "_get", side_effect=replies) as get, \
                patch.object(ns.time, "sleep") as sleep:
            ns.wait(submission, timeout=180, interval=60)
        self.assertEqual(get.call_count, 2)
        self.assertTrue(all(call.args[0] == f"{ns.API}/{submission}" for call in get.call_args_list))
        sleep.assert_called_once_with(60)

    def test_rejection_reads_log_and_fails(self):
        with patch.object(ns, "_credentials", return_value=(b"fixture", "key", "issuer")), \
                patch.object(ns, "make_token", return_value="fixture-token"), \
                patch.object(ns, "_get", return_value={"data": {"attributes": {"status": "Invalid"}}}), \
                patch.object(ns, "_print_log") as log, \
                self.assertRaises(ns.NotaryError):
            ns.wait("11111111-2222-3333-4444-555555555555", timeout=180, interval=60)
        log.assert_called_once()

    def test_in_progress_times_out_instead_of_releasing(self):
        with patch.object(ns, "_credentials", return_value=(b"fixture", "key", "issuer")), \
                patch.object(ns, "make_token", return_value="fixture-token"), \
                patch.object(ns, "_get", return_value={"data": {"attributes": {"status": "In Progress"}}}), \
                patch.object(ns.time, "monotonic", side_effect=[0, 10800]), \
                patch.object(ns.time, "sleep") as sleep, \
                self.assertRaisesRegex(ns.NotaryError, "180 minutes"):
            ns.wait("11111111-2222-3333-4444-555555555555", timeout=10800, interval=60)
        sleep.assert_not_called()

    def test_invalid_credentials_fail_without_retrying_or_logging_the_token(self):
        error = urllib.error.HTTPError(ns.API, 401, "Unauthorized", {}, None)
        with patch.object(ns, "_credentials", return_value=(b"fixture", "key", "issuer")), \
                patch.object(ns, "make_token", return_value="fixture-token"), \
                patch.object(ns, "_get", side_effect=error), \
                patch.object(ns.time, "sleep") as sleep, \
                self.assertRaisesRegex(ns.NotaryError, "HTTP 401") as context:
            ns.wait("11111111-2222-3333-4444-555555555555", timeout=180, interval=60)
        self.assertNotIn("fixture-token", str(context.exception))
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
