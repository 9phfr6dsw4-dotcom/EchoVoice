#!/usr/bin/env python3
"""Regenerate synthetic Qwen golden data with its published librosa magnitude frontend.

Requires numpy, scipy, librosa. No voice recordings or model weights are used.
Reference: QwenLM/Qwen3-TTS qwen_tts/core/models/modeling_qwen3_tts.py
mel_spectrogram and extract_speaker_embedding (24 kHz, Slaney, periodic Hann).
"""
import json
from pathlib import Path
import librosa
import numpy as np
from scipy.signal.windows import hann

samples = np.array([((i * 37) % 101 - 50) / 100 + ((i * 13) % 17 - 8) / 64 for i in range(4096)], dtype=np.float32)
padded = np.pad(samples, (384, 384), mode='reflect')
frames = np.lib.stride_tricks.sliding_window_view(padded, 1024)[::256]
spectrum = np.fft.rfft(frames * hann(1024, sym=False).astype(np.float32))
magnitude = np.sqrt(spectrum.real**2 + spectrum.imag**2 + 1e-9)
filters = librosa.filters.mel(sr=24000, n_fft=1024, n_mels=128, fmin=0, fmax=12000)
expected = np.log(np.maximum(magnitude @ filters.T, 1e-5)).astype(np.float32)
assert expected.shape == (16, 128)
fixture = Path(__file__).resolve().parents[1] / 'Tests/EchoVoiceModelTests/Fixtures/qwen-speaker-features.json'
fixture.parent.mkdir(parents=True, exist_ok=True)
fixture.write_text(json.dumps({'samples': samples.tolist(), 'features': expected.tolist()}, separators=(',', ':')) + '\n')
print(f'Generated {expected.shape} Qwen reference features from a synthetic signal.')
