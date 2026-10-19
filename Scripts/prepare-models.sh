#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -resolvePackageDependencies -scheme EchoVoiceApp -derivedDataPath .xcbuild \
    -skipMacroValidation -skipPackagePluginValidation
python3 Scripts/patch-models.py .xcbuild/SourcePackages/checkouts/mlx-audio-swift
