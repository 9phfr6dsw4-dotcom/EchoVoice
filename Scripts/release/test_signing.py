#!/usr/bin/env python3
"""Portable regression checks for the CI signing scripts, using fictional identities."""

import base64
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FINGERPRINT = "A" * 40
CERTIFICATE = "Developer ID Application: Example Person (EXAMPLE123)"


class SigningTests(unittest.TestCase):
    def run_setup(self, name=CERTIFICATE, require=True, certificate=True):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            security = folder / "security"
            security.write_text("""#!/bin/bash
case "$1" in
    find-identity)
        printf '  1) %s "%s"\n' "$TEST_FINGERPRINT" "$TEST_CERTIFICATE"
        printf '  1) %s "%s"\n' "$TEST_FINGERPRINT" "$TEST_CERTIFICATE"
        ;;
    list-keychains) [[ "$*" == *'-s'* ]] || echo '\"/tmp/login.keychain-db\"' ;;
esac
exit 0
""")
            security.chmod(0o755)
            github_env = folder / "github-env"
            github_env.touch()
            # Only synthetic data reaches these scripts; never inherit real signing secrets.
            env = {"PATH": f"{folder}:/usr/bin:/bin", "RUNNER_TEMP": directory,
                   "GITHUB_ENV": str(github_env), "TEST_FINGERPRINT": FINGERPRINT,
                   "TEST_CERTIFICATE": name, "REQUIRE_DEVELOPER_ID": str(require).lower()}
            if certificate:
                env.update(DEVELOPER_ID_P12_BASE64=base64.b64encode(b"fixture").decode(),
                           DEVELOPER_ID_P12_PASSWORD="fixture", NOTARY_API_KEY_P8_BASE64="Zml4dHVyZQ==",
                           NOTARY_API_KEY_ID="EXAMPLE123", NOTARY_API_ISSUER_ID="example-issuer")
            result = subprocess.run(["bash", str(ROOT / "Scripts/ci-signing.sh")],
                                    env=env, capture_output=True, text=True)
            return result, github_env.read_text()

    def test_duplicate_identity_becomes_one_github_env_line_and_name_is_masked(self):
        result, values = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values.count(f"SIGN_IDENTITY={FINGERPRINT}\n"), 1)
        self.assertIn("SIGN_MODE=developer-id\n", values)
        self.assertTrue(all("=" in line for line in values.splitlines()))
        # The GitHub masking command is consumed before rendering logs. No ordinary log line
        # or exported setting may contain the account holder's name.
        self.assertIn(f"::add-mask::{CERTIFICATE}", result.stdout)
        visible = "\n".join(line for line in result.stdout.splitlines() if not line.startswith("::add-mask::"))
        self.assertNotIn(CERTIFICATE, visible + result.stderr + values)

    def test_wrong_certificate_fails_without_logging_its_name(self):
        name = "Other Certificate: Example Person"
        result, values = self.run_setup(name=name)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(name, result.stdout + result.stderr + values)

    def test_required_developer_id_cannot_fall_back_to_adhoc(self):
        result, _ = self.run_setup(certificate=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DEVELOPER_ID_P12_BASE64 is missing", result.stderr)

    def test_fork_without_secrets_can_build_adhoc(self):
        result, values = self.run_setup(certificate=False, require=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values, "SIGN_MODE=adhoc\n")

    def test_main_app_gets_audio_input_and_helpers_keep_their_entitlements(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            app = folder / "EchoVoice.app"
            sparkle = app / "Contents/Frameworks/Sparkle.framework/Versions/B"
            for name in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"):
                (sparkle / name).mkdir(parents=True)
            calls = folder / "calls"
            codesign = folder / "codesign"
            codesign.write_text('#!/bin/bash\nprintf \'%s\\n\' "$*" >> "$TEST_CALLS"\n')
            codesign.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "Scripts/sign-app.sh"), str(app)],
                                    env={"PATH": f"{folder}:/usr/bin:/bin", "SIGN_MODE": "developer-id",
                                         "SIGN_IDENTITY": FINGERPRINT, "TEST_CALLS": str(calls)},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            signing = [line for line in calls.read_text().splitlines() if line.startswith("--force")]
            self.assertEqual(len(signing), 6)
            self.assertTrue(all("--options runtime --timestamp" in line for line in signing))
            self.assertTrue(all("--entitlements" not in line for line in signing[:-1]))
            self.assertIn(f"--entitlements {ROOT}/Resources/EchoVoice.entitlements", signing[-1])
            self.assertIn("--preserve-metadata=entitlements", signing[1])
            with (ROOT / "Resources/EchoVoice.entitlements").open("rb") as handle:
                self.assertEqual(plistlib.load(handle), {"com.apple.security.device.audio-input": True})


if __name__ == "__main__":
    unittest.main()
