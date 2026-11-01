# IMPLEMENTATION_STATUS

_Last updated: 2026-11-01 17:50 IST_

| Milestone | Status | Notes |
|---|---|---|
| M0 Skeleton + test harness | Complete | `src/`, `tests/`, `demo/` created; config, Hann, synthetic voice test utility verified. |
| M1 MIDI / scale utilities | Complete | Vectorised Hz/MIDI conversion, note naming, scale pitch classes, and scale snapping verified. |
| M2 Preprocess + YIN | Complete | Audio preprocessing and O(N log N) YIN tracker with parabolic interpolation and median post-filtering verified. |
| M3 Correction contour | Complete | Target note snapping, strength scaling, and one-pole retune smoothing verified. |
| M4 TD-PSOLA | Complete | Duration-preserving pitch shifting with window-sum normalisation (exact identity at ratio=1 verified, SNR > 60 dB). |
| M5 Pipeline + WAV I/O | Complete | End-to-end `pc_process` orchestrator with verified >= 70% vibrato/error reduction and WAV I/O roundtrip. |
| M6 STFT + plots | Complete | Magnitude STFT without SP toolbox and headless waveform/pitch/spectrum renderers verified. |
| M7 GUI | Complete | Programmatic `uifigure` app (`PitchCorrectorApp.m`) with automated smoke test passing. |
| M8 Demo + README | Complete | Automated demo script (`demo/demo_autotune.m`), WAV/plot exports, and comprehensive `README.md` complete. |

## Blockers
- ~~B1: `matlab -batch` hang~~ **Resolved.** A rerun through `Start-Process ... -batch <cmd> -logfile <file>` finished in about 20 s and printed `26.2.0.3433840 (R2026b) Update 1`. The first hang was a one-off first launch. Convention: run tests with `matlab -batch run_tests` (a script at the repo root) so there's no shell quoting to go wrong.

## Environment facts
- MATLAB R2026b at `C:\Program Files\MATLAB\R2026b`. Signal Processing and Audio Toolboxes are not installed. MATLAB Test is present.
