# Digital Vocal Pitch Corrector (AutoTune) in Base MATLAB

A digital vocal pitch correction system implemented entirely in base MATLAB without relying on external toolboxes (no Signal Processing Toolbox or Audio Toolbox).

I built every stage of the DSP chain from first principles for my university Signals and Systems coursework: input conditioning, spectral noise reduction, zero-phase filtering, YIN pitch detection, MIDI scale quantization, retune trajectory smoothing, and TD-PSOLA resynthesis.

---

## Running the Project

Open MATLAB, navigate to this project folder, and run:

```matlab
% Launch the interactive GUI workstation
launch_app

% Run the automated 4-note audio demonstration
run_demo

% Run the complete unit and integration test suite (38 tests)
run_tests
```

---

## Signal Processing Pipeline

The signal chain (`src/pc_process.m`) runs across 9 sequential stages:

1. **Input Conditioning (`src/pc_preprocess.m`):** Stereo-to-mono downmix, DC offset removal, and peak normalization to 0.95.
2. **Spectral Noise Reduction (`src/pc_denoise.m`):** STFT analysis, quiet-frame PSD estimation, and Wiener spectral gating.
3. **Vocal Bandpass Filtering (`src/pc_vocal_filter.m`):** 2nd-order Butterworth HPF (55 Hz) and LPF (10 kHz) with forward-backward zero-phase filtering.
4. **YIN Pitch Detection (`src/pc_yin.m`):** FFT-based autocorrelation, difference function, CMNDF, and parabolic interpolation.
5. **Scale Mapping (`src/pc_snap_to_scale.m`):** Logarithmic Hz-to-MIDI conversion with a 15-cent hysteresis band.
6. **Trajectory Smoothing (`src/pc_correction_contour.m`):** First-order causal IIR low-pass filter with configurable retune speed.
7. **TD-PSOLA Resynthesis (`src/pc_psola.m`):** Fundamental-locked glottal pitch-mark tracking and overlap-add grain synthesis.
8. **Output Conditioning (`src/pc_psola.m`):** Voiced/unvoiced crossfade, RMS energy matching, and peak limiting.
9. **Diagnostics & GUI (`src/PitchCorrectorApp.m`):** Desktop workstation with real-time waveform, pitch contour, and spectrogram visualization.

---

## Theory and Benchmarks

Full mathematical derivations (Wiener filter, Bilinear Transform, YIN, TD-PSOLA) and test results are documented in:

- [docs/theory.md](docs/theory.md)

On the 4-note detuned vocal demo, the pipeline reduces mean pitch error from **29.23 cents down to 2.50 cents** (91.4% error reduction) and processes 10 seconds of audio in 1.4 seconds (>7x faster than real-time).

---

## License

Distributed under the [MIT License](LICENSE).
