# Senior Technical Audit & Engineering Improvement Report (`AUDIT_REPORT.md`)

**Project:** MATLAB Digital Vocal Pitch Correction Workstation (AutoTune)  
**Environment:** MATLAB R2026b (Base MATLAB only — zero external toolbox dependencies)  
**Auditor & Lead Improvement Engineer:** Argon  

---

## 1. Executive Summary

An independent line-by-line mathematical, algorithmic, and architectural audit was conducted across the entire vocal pitch correction codebase (`src/`, `tests/`, `demo/`). The audit identified **five critical DSP defects** and **four major UI/UX and workflow deficiencies** that explained why early recordings suffered from noise amplification, pitch-estimation bias, wavering pitch bleed-through, syllable-boundary chirps, and vocal roughness.

All identified defects have been resolved while preserving the modular Base-MATLAB architecture established in `PROJECT_PLAN.md` and `TECHNICAL_DECISIONS.md`. The verification suite was expanded from 31 to **38 automated unit and integration tests** (`test_m0_basics` through `test_m8_audit_dsp`), achieving a **100% pass rate (38/38 passed, 0 failed)**.

---

## 2. Confirmed Issues Identified During Audit

### Priority 1 — Audio Preprocessing & Noise Conditioning Defects

| ID | Component | Confirmed Defect | Technical Impact |
| :--- | :--- | :--- | :--- |
| **A1** | `src/pc_preprocess.m` | **Absence of stationary background noise reduction:** The original preprocessor only performed mono averaging, mean subtraction, and peak scaling. | Room hiss, laptop fan noise, and microphone pre-amp noise were amplified right alongside the voice and fed directly into YIN and TD-PSOLA. |
| **A2** | `src/pc_preprocess.m` | **Absence of vocal bandpass conditioning:** No high-pass filter or low-pass filter was present before pitch detection. | Low-frequency microphone stand rumble, AC hum trends, and plosives ($< 55\text{ Hz}$) corrupted YIN autocorrelation lags, while high-frequency hiss ($> 10\text{ kHz}$) degraded grain splicing. |
| **A3** | `src/pc_preprocess.m` | **Flawed silence vs. low-amplitude threshold:** A hard threshold `rawPeak < 0.005` zeroed out legitimate quiet vocal takes (e.g., `-54 dBFS`, `peak = 0.002`), whereas earlier versions without a gate boosted 16-bit ADC idle quantization noise (`1 LSB = 3.05e-5`) by $>30,000\times$. | Quiet singers were muted completely, or idle 16-bit microphones exploded into full-scale white noise. |

### Priority 2 — Pitch Detection & Correction Engine Defects

| ID | Component | Confirmed Defect | Technical Impact |
| :--- | :--- | :--- | :--- |
| **B1** | `src/pc_yin.m` | **Biased difference function & inverted parabolic interpolation sign:** (1) The FFT difference function used `E0 = cumSq(W + 1)` instead of `E_head = cumSq(W - taus + 1)` and omitted the $1/(W-\tau)$ window-overlap normalization, tilting $d(\tau)$ upward with lag $\tau$. (2) In Step 5, `denom = 2 * (2 * y2 - y1 - y3)` had the **opposite sign** of the second derivative $y_1 - 2y_2 + y_3 > 0$, causing the fractional lag refinement $\delta$ to step in the **wrong direction** from the integer lag! | Systematic $+7.87\text{ cent}$ pitch estimation error on pure tones (220, 440, 880 Hz), cascading into a $14\text{ cent}$ pitch-shift error in TD-PSOLA resynthesis. |
| **B2** | `src/pc_correction_contour.m` | **High-pass pitch wobble leak during retune smoothing:** The original contour smoother applied the first-order IIR filter to `rawShift = strength * (midiTarget - midiDet)` and added it to `midiDet`. Mathematically, $y = x + H_{\text{LP}}(T - x) = H_{\text{LP}}(T) + (1 - H_{\text{LP}})(x)$, acting as a high-pass filter on `midiDet`. Furthermore, there was no hysteresis at scale midpoints. | Whenever `retuneMs > 0`, vocal vibrato and pitch jitter passed straight through unattenuated, and singers hovering near a scale boundary caused rapid 5 ms note-chatter. |
| **B3** | `src/pc_psola.m` | **Voiced/unvoiced transition chirps & formant-induced pitch-mark random walk:** (1) Unvoiced frames were assigned dummy period `Pu = 441` (100 Hz) and `ratio = 1.0`, and linearly interpolated into voiced frames—creating pitch sweeps at every consonant-vowel boundary. (2) Analysis pitch marks `ta` searched `max(x)` on the unfiltered multi-harmonic signal within $\pm 25\% P$, jumping between secondary formant ripples. (3) WOLA divided by `w_sum` down to `1e-9` at grain edges, and ran periodic windowing over unvoiced consonants. | Audible boundary chirps, cycle-to-cycle phase jitter ("gargling") on formant-rich vocals, and comb-filtered sibilants/consonants. |

### Priority 3 — UI/UX & Functional Workflow Deficiencies

| ID | Component | Confirmed Defect | Technical Impact |
| :--- | :--- | :--- | :--- |
| **C1** | `src/PitchCorrectorApp.m` | **Emoji usage & generic light styling:** Contained the `'⚡'` emoji in the preset button and used default light-gray MATLAB figure styling with garish button colors. | Violated strict professional studio UI standards and no-emoji constraints. |
| **C2** | `src/PitchCorrectorApp.m` | **Incomplete 10-step audio workflow:** Lacked preprocessing/denoise controls, lacked a "Play Cleaned" preview button, lacked Original-vs-Cleaned waveform comparison, lacked real-time musical note/Hz telemetry cards, and lacked a Reset button. | Users could not inspect, preview, or tune noise reduction prior to pitch correction. |

---

## 3. Engineering Corrections Implemented

### 3.1 Audio Preprocessing Pipeline (`pc_preprocess.m`, `pc_denoise.m`, `pc_vocal_filter.m`)
The pipeline now strictly enforces the architecture:
`Audio Input -> Input Validation -> Audio Conditioning -> Noise Reduction -> Vocal Preprocessing -> Pitch Detection -> Musical Note Mapping -> Pitch Correction -> Output Smoothing -> Playback and Export`

1. **Input Validation & Conditioning (`src/pc_preprocess.m`):**
   - Validates finite real samples, sampling rate $f_s \ge 8000\text{ Hz}$, and duration $\ge 0.1\text{ s}$.
   - Downmixes stereo/multi-channel inputs (`mean(x, 2)`), removes DC offset, and separates 16-bit ADC idle noise (`rawPeak < 1e-4`, `-80 dBFS`) from legitimate low-amplitude vocals (`rawPeak >= 1e-4`), recovering quiet vocals cleanly up to $500\times$ gain while keeping idle mics completely silent.
   - Preserves `info.xRaw` (conditioned raw reference) alongside `x` (cleaned & vocal-filtered signal) for A/B/C comparison.
2. **Stationary Noise Reduction (`src/pc_denoise.m`):**
   - Computes a 75%-overlap COLA-compliant Hann STFT (`~32 ms` frames).
   - Combines **quiet-frame detection** (when natural vocal pauses exist) with **inter-harmonic spectral valley quantiles** (30th percentile across vocal-band bins when the input is a continuous tone/vowel without pauses) so sustained vocal harmonics are never mistaken for noise.
   - Automatically bypasses spectral gating when estimated broadband SNR $> 40\text{ dB}$, guaranteeing zero distortion on studio-clean or synthetic test signals.
   - Applies a **decision-directed soft Wiener spectral gain** ($\alpha_{\text{dd}} = 0.90$) with 3-bin frequency smoothing `[0.25, 0.50, 0.25]`, 3-frame temporal smoothing `[0.20, 0.60, 0.20]`, and a soft spectral floor (`-14 dB` to `-26 dB`) to eliminate musical noise.
3. **Zero-Phase Vocal Bandpass Conditioning (`src/pc_vocal_filter.m`):**
   - Synthesizes analytical bilinear-transform 2nd-order Butterworth high-pass ($f_c = 55\text{ Hz}$) and low-pass ($f_c = 10\text{ kHz}$) IIR sections in Base MATLAB.
   - Applies odd-symmetric reflection padding and forward-backward filtering (`filter` + `flipud`) for **zero phase distortion**, attenuating 20 Hz sub-bass rumble by $> 30\text{ dB}$ and 14 kHz hiss by $> 12\text{ dB}$ while keeping the 80–1000 Hz vocal fundamental band flat within $< 0.1\text{ dB}$.

### 3.2 Pitch Detection & Correction Engine (`pc_yin.m`, `pc_correction_contour.m`, `pc_psola.m`)
1. **Unbiased YIN Estimator (`src/pc_yin.m`):**
   - Fixed the exact mean-square difference function:
     $$\bar{d}(\tau) = \frac{1}{W - \tau} \left( \sum_{j=1}^{W-\tau} x_j^2 + \sum_{k=\tau+1}^{W} x_k^2 - 2 r(\tau) \right)$$
   - Fixed the Step 5 parabolic interpolation denominator to `denom = 2 * (y1 - 2 * y2 + y3)` on $\bar{d}(\tau)$ with $\delta \in [-0.5, 0.5]$, reducing pure-tone pitch estimation error from $7.87\text{ cents}$ to **$< 0.05\text{ cents}$**.
   - Added a subharmonic ($2\tau_0$) dip check to prevent 2nd-harmonic octave-up lock on bright formants.
2. **Hysteresis & Target-Locked Retune Contour (`src/pc_correction_contour.m`):**
   - Added scale-boundary hysteresis (`cfg.hysteresisSemis = 0.15`, 15 cents) within contiguous voiced runs to eliminate note chatter when hovering near scale midpoints.
   - Replaced raw-shift smoothing with target-trajectory smoothing $p_{\text{smooth}}[i] = \beta p_{\text{smooth}}[i-1] + (1 - \beta) \text{midiTarget}[i]$ initialized at $p_{\text{smooth}}[i_0 - 1] = \text{midiDet}[i_0]$ at each voiced onset ($\beta = e^{-\Delta t / \tau}$). This preserves the exact analytical step response $(1 - e^{-k \Delta t/\tau})$ while locking sustained vocal notes flat against vibrato/drift.
3. **Artifact-Free TD-PSOLA Resynthesis (`src/pc_psola.m`):**
   - **Boundary Chirp Elimination:** Fills unvoiced frame periods and pitch ratios from nearest voiced frames (`'nearest', 'extrap'`) prior to sample-level linear interpolation.
   - **Fundamental-Isolated Peak Locking:** Computes a zero-phase low-pass filtered fundamental signal `x_f0` ($f_c = 1.38 \max f_0$) solely for analysis pitch-mark (`ta`) peak picking within $\pm 0.20 P$, eliminating multi-formant peak jumping while still extracting full-bandwidth grains from `x`.
   - **Bounded WOLA & Unvoiced Crossfading:** Bounds WOLA window normalization at `max(w_sum, 0.15)` and applies a smooth 10 ms moving-average crossfade to pass unvoiced consonants through unaltered.

### 3.3 Dark Studio UI/UX Overhaul (`src/PitchCorrectorApp.m`, `src/pc_plot_*.m`)
- Redesigned `PitchCorrectorApp.m` into a dark studio workstation (`#12141A` / `#1F242E` palette) with **zero emojis** anywhere in the codebase (verified by automated ASCII inspection in `test_m8_audit_dsp`).
- Implemented the complete 10-step workflow across 4 structured control sections:
  1. **Audio Input & Capture:** Import WAV, Load Demo Vocal, Microphone Device selector, Recording duration, Record Mic.
  2. **Preprocessing & Noise Reduction:** Spectral Noise Reduction toggle, Denoise Strength slider (`0%–150%`), Vocal Conditioning Filter toggle (`55 Hz – 10 kHz`), and `Update & Preview Cleaned Audio` button.
  3. **Pitch Correction Engine:** Musical Key (`C` through `B`), Scale (`major`, `minor`, `chromatic`), Correction Strength (`0%–100%`), Retune Speed (`0–200 ms`), `Preset: Hard Quantize`, `Preset: Natural Studio`, and `APPLY PITCH CORRECTION`.
  4. **Monitor, Compare & Export:** `Play Original`, `Play Cleaned`, `Play Corrected`, Waveform View selector (`Cleaned vs Corrected`, `Original vs Cleaned`, `Original vs Corrected`), Spectral View selector (`Corrected Spectrogram`, `Cleaned Spectrogram`, `Original Spectrogram`, `Harmonic Spectrum Overlay`), `Stop Audio`, `Reset`, and `Export WAV`.
- Added a 5-card **Telemetry Readout Header** displaying `DETECTED NOTE / F0`, `SCALE TARGET NOTE`, `CORRECTED OUTPUT F0`, `MEAN CENTS ERROR (IN -> OUT)`, and `PREPROCESS / DENOISE` status.

---

## 4. Verification & Empirical Test Results

All 38 automated tests across 8 test suites were executed via `matlab -batch "run_tests"`:

| Test Suite | Tests | Status | Key Verified Metrics |
| :--- | :---: | :---: | :--- |
| `test_m0_basics` | 3 | **PASS** | `pc_hann` COLA symmetry, `pc_synth_voice`, `pc_default_config` schema |
| `test_m1_music` | 6 | **PASS** | `pc_hz2midi`, `pc_midi2hz`, `pc_midi2name`, `pc_scale_pcs`, `pc_snap_to_scale` |
| `test_m2_yin` | 6 | **PASS** | 100/220/440/880 Hz error $< 0.1\text{ ct}$, linear chirp $< 15\text{ ct}$, 0% octave errors, 10s audio in $1.4\text{ s}$ |
| `test_m3_contour` | 6 | **PASS** | Zero strength, hard snap, exact $1 - e^{-1}$ step response, onset reset, clamping |
| `test_m4_psola` | 3 | **PASS** | Identity SNR $> 100\text{ dB}$, $\pm 1, \pm 3$ semitone shifts within $< 4\text{ ct}$, unvoiced gap stability |
| `test_m5_pipeline` | 4 | **PASS** | End-to-end vibrato & detune reduction $> 80\%$, WAV round-trip, silent input safety |
| `test_m6_plots` | 2 | **PASS** | `pc_stft` FFT accuracy $< 10^{-12}$, headless rendering of all plot modes |
| `test_m7_gui` | 1 | **PASS** | Headless `PitchCorrectorApp` instantiation, audio load, processing, axes population |
| `test_m8_audit_dsp` | 7 | **PASS** | Multi-SNR noise reduction ($8, 15, 22\text{ dB}$), rumble ($>20\text{ dB}$) & hiss ($>10\text{ dB}$) rejection, low-amplitude (`-54 dBFS`) recovery, 16-bit idle noise rejection, multi-sample-rate (`16, 22.05, 44.1, 48 kHz`), multi-note hysteresis, zero-emoji UI audit |

---

## 5. Remaining Limitations & Operational Notes

1. **Monophonic Source Assumption:** Both YIN and TD-PSOLA are designed for monophonic solo vocals. Polyphonic inputs (chords, backing tracks mixed with vocals, or multiple simultaneous singers) will not track a single fundamental cleanly.
2. **Extreme Pitch Shifts ($> \pm 6\text{ semitones}$):** While `pc_psola` supports pitch ratios in $[0.5, 2.0]$ ($\pm 1\text{ octave}$) and locks analysis marks to the fundamental, standard TD-PSOLA scales the pitch period without independent spectral envelope warping; shifts within $\pm 3\text{ semitones}$ (typical vocal correction) preserve natural vocal timbre best.
3. **Non-Stationary Impulsive Noise:** `pc_denoise` targets stationary background noise (room hiss, fan noise, pre-amp floor) and `pc_vocal_filter` removes sub-55 Hz thumps/rumble, but mid-band non-stationary transients (e.g., door slams or loud clicks overlapping vowel formants) are not removed.
