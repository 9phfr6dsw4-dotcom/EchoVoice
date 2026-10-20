#!/usr/bin/env python3
"""Waits for Apple's notary service to finish a submission, from a cheap Linux CI job.

The macOS job only uploads the Developer ID-signed app (Scripts/notarize.sh) and records the
submission ID. This tool asks Apple's Notary API for that submission's status until it is
Accepted, and fails on Invalid, Rejected or a timeout. It signs the API token (ES256) with the
App Store Connect key through OpenSSL; the key is kept in a private temporary file only while
OpenSSL runs, and no key, token or ID secret is ever printed.

Run: python3 -I Scripts/release/notary_status.py wait --submission <id>
Reads NOTARY_API_KEY_P8_BASE64, NOTARY_API_KEY_ID and NOTARY_API_ISSUER_ID from the environment.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://appstoreconnect.apple.com/notary/v2/submissions"
SUBMISSION_ID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
TOKEN_LIFETIME = 15 * 60  # Apple allows at most 20 minutes.


class NotaryError(Exception):
    pass


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_length(data, index):
    length = data[index]
    index += 1
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[index:index + count], "big")
        index += count
    return length, index


def der_to_raw_signature(der):
    """Turns OpenSSL's DER ECDSA signature into the 64-byte r||s form JWTs use (RFC 7518)."""
    if len(der) < 8 or der[0] != 0x30:
        raise NotaryError("Unexpected ECDSA signature format.")
    _, index = _der_length(der, 1)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise NotaryError("Unexpected ECDSA signature format.")
        length, index = _der_length(der, index + 1)
        value = der[index:index + length].lstrip(b"\x00")
        if len(value) > 32:
            raise NotaryError("Unexpected ECDSA signature size.")
        parts.append(value.rjust(32, b"\x00"))
        index += length
    return parts[0] + parts[1]


def make_token(key_pem, key_id, issuer_id, now=None, openssl="openssl"):
    now = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + TOKEN_LIFETIME, "aud": "appstoreconnect-v1"}
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    )
    with tempfile.TemporaryDirectory() as directory:
        key_path = os.path.join(directory, "key.p8")
        fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(key_pem)
        result = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", key_path, "-binary"],
            input=signing_input.encode(),
            capture_output=True,
        )
    if result.returncode != 0:
        # OpenSSL's messages never contain key material.
        raise NotaryError("OpenSSL could not sign the notary token: " + result.stderr.decode(errors="replace").strip())
    return signing_input + "." + _b64url(der_to_raw_signature(result.stdout))


def interpret(status):
    """Returns True when finished and accepted, False while in progress; raises when refused."""
    if status == "Accepted":
        return True
    if status == "In Progress":
        return False
    raise NotaryError(f"Apple's notary service answered {status!r}.")


def _get(url, token=None):
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def _credentials():
    values = {}
    for name in ("NOTARY_API_KEY_P8_BASE64", "NOTARY_API_KEY_ID", "NOTARY_API_ISSUER_ID"):
        value = os.environ.get(name, "").strip()
        if not value:
            raise NotaryError(f"The {name} secret is missing.")
        values[name] = value
    try:
        key = base64.b64decode(values["NOTARY_API_KEY_P8_BASE64"], validate=False)
    except ValueError as error:
        raise NotaryError("NOTARY_API_KEY_P8_BASE64 is not base64.") from error
    return key, values["NOTARY_API_KEY_ID"], values["NOTARY_API_ISSUER_ID"]


def _print_log(submission, token):
    try:
        data = _get(f"{API}/{submission}/logs", token)
        log_url = data["data"]["attributes"]["developerLogUrl"]
        log = _get(log_url)
    except (urllib.error.URLError, KeyError, ValueError):
        print("Apple's notarization log could not be read.", file=sys.stderr)
        return
    issues = log.get("issues") or []
    print(f"Apple's notarization log lists {len(issues)} issue(s):", file=sys.stderr)
    for issue in issues:
        print(f"- {issue.get('path', '?')}: {issue.get('message', '?')}", file=sys.stderr)


def wait(submission, timeout, interval):
    if not SUBMISSION_ID.match(submission):
        raise NotaryError("The notarization submission ID is not a UUID.")
    key, key_id, issuer_id = _credentials()
    deadline = time.monotonic() + timeout
    failures = 0
    while True:
        token = make_token(key, key_id, issuer_id)
        try:
            data = _get(f"{API}/{submission}", token)
            status = data["data"]["attributes"]["status"]
            failures = 0
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise NotaryError(f"Apple refused the notary API key (HTTP {error.code}).") from error
            failures += 1
            status = None
            print(f"Apple's Notary API answered HTTP {error.code}; trying again.")
        except (urllib.error.URLError, KeyError, ValueError, TimeoutError):
            failures += 1
            status = None
            print("Apple's Notary API could not be read; trying again.")
        if failures >= 10:
            raise NotaryError("Apple's Notary API failed 10 times in a row.")
        if status is not None:
            try:
                if interpret(status):
                    print(f"Notarization {submission}: Accepted.")
                    return
            except NotaryError:
                _print_log(submission, token)
                raise
            print(f"Notarization {submission}: {status}.")
        if time.monotonic() + interval > deadline:
            raise NotaryError(f"Apple had not finished notarization {submission} within {timeout // 60} minutes.")
        time.sleep(interval)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    waiting = commands.add_parser("wait", help="wait until a submission is accepted")
    waiting.add_argument("--submission", required=True)
    waiting.add_argument("--timeout", type=int, default=3 * 60 * 60, help="seconds (default 3 hours)")
    waiting.add_argument("--interval", type=int, default=60, help="seconds between checks")
    args = parser.parse_args(argv)
    try:
        wait(args.submission, args.timeout, args.interval)
    except NotaryError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
