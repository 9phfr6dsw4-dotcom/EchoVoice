#!/usr/bin/env bash
# Sends a Developer ID-signed EchoVoice zip to Apple's notary service without waiting (no --wait), and
# writes the submission ID to the given file. Apple can take from minutes to hours, so the
# Linux "Wait for Apple notarization" job polls for the answer (Scripts/release/notary_status.py)
# instead of keeping a macOS runner busy; the release refuses anything Apple hasn't accepted.
# Nothing is stapled, so the tested zip is exactly the zip that ships; macOS checks the
# notarization online the first time the app opens.
# Needs NOTARY_KEY_PATH (an App Store Connect API key, .p8), NOTARY_KEY_ID and NOTARY_ISSUER_ID.
set -euo pipefail

ZIP="${1:?usage: notarize.sh <path to EchoVoice.zip> <submission ID file>}"
ID_FILE="${2:?usage: notarize.sh <path to EchoVoice.zip> <submission ID file>}"
for name in NOTARY_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID; do
    if [[ -z "${!name:-}" ]]; then
        printf 'Developer ID builds must be notarized, but %s is not set.\n' "$name" >&2
        exit 1
    fi
done
test -s "$NOTARY_KEY_PATH"
test -s "$ZIP"

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/echovoice-notarize.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

xcrun notarytool submit "$ZIP" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --output-format plist > "$WORK_DIR/result.plist"
SUBMISSION_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$WORK_DIR/result.plist")"
[[ "$SUBMISSION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo "Apple's notary service returned no submission ID." >&2; exit 1; }
printf '%s\n' "$SUBMISSION_ID" > "$ID_FILE"
printf 'Sent to Apple for notarization: submission %s\n' "$SUBMISSION_ID"
