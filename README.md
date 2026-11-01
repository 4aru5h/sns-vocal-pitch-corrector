# MATLAB Digital Vocal Pitch Correction Workstation (AutoTune)

A complete, self-contained digital vocal pitch correction (AutoTune) workstation written in **100% Base MATLAB** (zero external toolbox dependencies). The system combines **Stationary Spectral Noise Reduction**, **Zero-Phase Butterworth Vocal Conditioning**, the **YIN Fundamental Frequency ($f_0$) Estimator**, **Hysteresis Scale Quantization**, and **Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA)** resynthesis inside a dark-themed desktop studio GUI.

---

## Key Features

- **End-to-End Vocal Preprocessing Pipeline:**
  - Stereo-to-mono downmix, DC offset removal, and intelligent silence vs. low-amplitude vocal detection (`-80 dBFS` idle ADC gate with automatic normalization for quiet takes).
  - **Decision-Directed Wiener Spectral Denoising (`pc_denoise.m`):** Estimates stationary background noise from quiet frames and inter-harmonic spectral valleys with time-frequency smoothing to suppress room hiss without musical noise or harmonic damage.
  - **Zero-Phase Butterworth Vocal Conditioning (`pc_vocal_filter.m`):** Forward-backward 2nd-order Butterworth high-pass filter ($55\text{ Hz}$) and low-pass filter ($10\text{ kHz}$) removing sub-bass mic rumble/plosives and ultrasonic hiss with zero phase distortion.
- **High-Precision YIN Pitch Tracker (`pc_yin.m`):**
  - $O(W \log W)$ FFT-accelerated unbiased difference function, cumulative mean normalization (CMNDF), subharmonic octave-error protection, parabolic lag refinement ($< 0.1\text{ cent}$ pure-tone error), and contiguous voiced-run median filtering.
- **Scale Quantization & Retune Trajectory Smoothing (`pc_correction_contour.m`):**
  - Supports all 12 chromatic keys (`C` through `B`) and `major`, `minor`, and `chromatic` scales.
  - Includes a $15\text{-cent}$ hysteresis deadband to prevent note-chatter at scale midpoints and target-locked exponential retune smoothing (`0 ms` hard T-Pain quantize to `200 ms` natural glide).
- **Artifact-Free TD-PSOLA Resynthesis (`pc_psola.m`):**
  - Places analysis pitch marks on a zero-phase fundamental-isolated reference signal (`x_f0`) to prevent formant-ripple phase jitter while extracting full-bandwidth Hann grains from the conditioned vocal.
  - Nearest-neighbor voiced boundary extension and $10\text{ ms}$ voiced/unvoiced crossfading eliminate syllable-boundary chirps and preserve crisp unvoiced consonants.
- **Dark Studio Desktop Workstation (`PitchCorrectorApp.m`):**
  - Complete 10-step workflow: Import WAV / Load Demo Vocal / Record Mic $\to$ Adjust Denoise & Vocal Filter $\to$ Preview Original & Cleaned Audio $\to$ Select Key, Scale, Strength & Retune Speed $\to$ Apply Pitch Correction $\to$ Compare Waveforms, Pitch Contours & Spectrograms $\to$ Export WAV.

---

## Quick Start

Open MATLAB in the repository root (`c:\Users\iamaa\Desktop\sns`) and run:

```matlab
% 1. Launch the interactive Dark Studio GUI Workstation
launch_app

% 2. Run the automated end-to-end demonstration (exports WAVs & PNG to demo/out/)
run_demo

% 3. Run the complete 38-test verification suite (M0 through M8)
run_tests
```

---

## Repository Structure

```text
sns/
├── launch_app.m                 % Launches PitchCorrectorApp studio GUI
├── run_demo.m                   % Runs demo/demo_autotune.m
├── run_tests.m                  % Executes all 38 automated tests in tests/
├── AUDIT_REPORT.md              % Senior technical audit & improvement report
├── PROJECT_PLAN.md              % Master architectural specification
├── TECHNICAL_DECISIONS.md       % Settled DSP & GUI engineering decisions
├── IMPLEMENTATION_STATUS.md     % Milestone completion & verification status
├── src/
│   ├── pc_default_config.m      % Master configuration struct
│   ├── pc_hann.m                % Base-MATLAB symmetric Hann window
│   ├── pc_synth_voice.m         % Formant-enveloped harmonic test voice synthesizer
│   ├── pc_hz2midi.m             % Frequency (Hz) to fractional MIDI converter
│   ├── pc_midi2hz.m             % Fractional MIDI to frequency (Hz) converter
│   ├── pc_midi2name.m           % MIDI note number to scientific pitch name
│   ├── pc_scale_pcs.m           % Musical key & scale pitch-class generator
│   ├── pc_snap_to_scale.m       % Nearest-note scale quantizer
│   ├── pc_vocal_filter.m        % Zero-phase Butterworth HPF (55 Hz) & LPF (10 kHz)
│   ├── pc_denoise.m             % Stationary noise estimator & soft Wiener spectral gate
│   ├── pc_preprocess.m          % Conditioning, denoise, vocal filter & normalization
│   ├── pc_yin.m                 % FFT-accelerated YIN f0 pitch detector
│   ├── pc_correction_contour.m  % Hysteresis scale mapper & retune trajectory smoother
│   ├── pc_psola.m               % Fundamental-locked TD-PSOLA pitch resynthesizer
│   ├── pc_process.m             % End-to-end processing pipeline & telemetry generator
│   ├── pc_stft.m                % Base-MATLAB Short-Time Fourier Transform
│   ├── pc_plot_waveform.m       % Dark-theme waveform comparison renderer
│   ├── pc_plot_pitch.m          % Dark-theme pitch contour & scale grid renderer
│   ├── pc_plot_spectrum.m       % Dark-theme spectrogram & harmonic spectrum renderer
│   └── PitchCorrectorApp.m      % Dark-theme desktop studio GUI application
├── tests/
│   ├── test_m0_basics.m         % Windowing, synth voice, config tests
│   ├── test_m1_music.m          % Music theory & scale snapping tests
│   ├── test_m2_yin.m            % Preprocessing & YIN pitch tracking accuracy tests
│   ├── test_m3_contour.m        % Retune smoothing, onset reset & clamping tests
│   ├── test_m4_psola.m          % TD-PSOLA identity & semitone shifting tests
│   ├── test_m5_pipeline.m       % End-to-end vocal pitch correction & WAV I/O tests
│   ├── test_m6_plots.m          % STFT & headless visualization tests
│   ├── test_m7_gui.m            % Headless GUI smoke test
│   └── test_m8_audit_dsp.m      % Audit verification: multi-SNR denoise, filters, sample rates, hysteresis & UI
└── demo/
    ├── demo_autotune.m          % Automated 4-note vocal phrase demo script
    └── out/                     % Generated original.wav, cleaned.wav, corrected.wav, autotune_demo.png
```
