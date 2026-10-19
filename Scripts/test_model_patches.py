#!/usr/bin/env python3
"""Check idempotence and fail-closed behavior against the resolved pinned checkout."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('model_patches', ROOT / 'patch-models.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)
SOURCE = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else ROOT.parent / '.xcbuild/SourcePackages/checkouts/mlx-audio-swift'

class PatchSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name) / 'dependency'
        subprocess.run(['git', 'clone', '--quiet', '--shared', '--no-hardlinks', str(SOURCE), str(self.checkout)], check=True, capture_output=True)
        self.model = self.checkout / 'Sources/MLXAudioTTS/Models/Qwen3TTS/Qwen3TTS.swift'

    def testRepeatIsIdenticalAndSharedDSPIsUntouched(self):
        dsp = self.checkout / 'Sources/MLXAudioCore/DSP.swift'
        original = dsp.read_bytes()
        patcher.patch(self.checkout)
        first = self.model.read_bytes()
        patcher.patch(self.checkout)
        self.assertEqual(self.model.read_bytes(), first)
        self.assertEqual(dsp.read_bytes(), original)

    def testUnexpectedSourceStopsBeforeAnyEdits(self):
        self.model.write_text(self.model.read_text() + '\n// unexpected edit\n')
        original = self.model.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'Unexpected local edits'):
            patcher.patch(self.checkout)
        self.assertEqual(self.model.read_bytes(), original)
        self.assertFalse((self.model.parent / 'EchoVoiceQwenSpeakerFeatures.swift').exists())

    def testDifferentRevisionIsRejected(self):
        subprocess.run(['git', '-C', str(self.checkout), 'checkout', '--quiet', 'HEAD^'], check=True)
        original = self.model.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'revision changed'):
            patcher.patch(self.checkout)
        self.assertEqual(self.model.read_bytes(), original)

if __name__ == '__main__':
    unittest.main()
