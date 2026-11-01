# Technical Decisions (`TECHNICAL_DECISIONS.md`)

This document records the authoritative architectural and DSP engineering decisions for the MATLAB Digital Vocal Pitch Correction project, including refinements introduced during the Senior Technical Audit.

---

## TD-1: Zero External Toolbox Dependency (Base MATLAB Only)
- **Decision:** All DSP, spectral analysis, filtering, synthesis, and GUI functionality must execute in Base MATLAB without Signal Processing Toolbox or Audio Toolbox.
- **Implementation:**
  - Symmetric Hann window implemented analytically in `src/pc_hann.m`.
  - STFT implemented via `fft` in `src/pc_stft.m` and `src/pc_denoise.m`.
  - Zero-phase 2nd-order Butterworth high-pass and low-pass filters implemented via analytical bilinear transform and odd-symmetric reflection-padded forward-backward `filter()` in `src/pc_vocal_filter.m`.

## TD-2: Multi-Stage Audio Preprocessing Before Pitch Detection
- **Decision:** Input audio must be conditioned, denoised, and vocal-filtered *prior* to YIN pitch estimation and TD-PSOLA resynthesis, while preserving `info.xRaw` for Original vs. Cleaned comparison.
- **Implementation (`src/pc_preprocess.m`, `src/pc_denoise.m`, `src/pc_vocal_filter.m`):**
  1. **Validation & Conditioning:** Enforces $f_s \ge 8000\text{ Hz}$ and duration $\ge 0.1\text{ s}$, downmixes stereo to mono, removes DC offset, and gates 16-bit ADC idle noise (`rawPeak < 1e-4`, `-80 dBFS`) while normalizing quiet vocal recordings (`rawPeak >= 1e-4`).
  2. **Stationary Noise Reduction (`pc_denoise.m`):** Uses a 75%-overlap Hann STFT (`~32 ms`), estimates noise PSD from quiet frames (when pauses exist) or 30th-percentile inter-harmonic valleys (when continuous), and applies decision-directed soft Wiener gating ($\alpha_{\text{dd}} = 0.90$) with 3-bin frequency smoothing and 3-frame temporal smoothing. Automatically bypasses when estimated broadband $\text{SNR} > 40\text{ dB}$.
  3. **Vocal Bandpass Conditioning (`pc_vocal_filter.m`):** Zero-phase forward-backward Butterworth high-pass ($55\text{ Hz}$) and low-pass ($10\text{ kHz}$) filters remove sub-bass rumble/plosives and high-frequency hiss without phase distortion or harmonic loss.

## TD-3: Unbiased FFT-Accelerated YIN Pitch Detection
- **Decision:** Use the 6-step YIN estimator (`src/pc_yin.m`) with $40\text{ ms}$ window, $5\text{ ms}$ hop, $f_0 \in [80, 1000]\text{ Hz}$, threshold $0.15$, and aperiodicity gate $0.45$.
- **Audit Refinement:** Normalize the FFT difference function by the exact overlap count $(W - \tau)$ to remove window-shrinkage lag bias, verify subharmonic dips at $2\tau$ to prevent 2nd-harmonic lock, and refine lags via parabolic interpolation on $\bar{d}(\tau)$ with positive curvature denominator $2(y_1 - 2y_2 + y_3)$.

## TD-4: Scale-Boundary Hysteresis & Target-Locked Retune Smoothing
- **Decision:** Map voiced $f_0$ frames to MIDI, quantize to the active scale (`major`, `minor`, `chromatic`), and smooth pitch transitions using `retuneMs`.
- **Audit Refinement (`src/pc_correction_contour.m`):**
  - Apply a $15\text{-cent}$ (`0.15` semitone) hysteresis deadband across contiguous voiced frames to prevent rapid note chatter near scale midpoints.
  - Smooth the target pitch trajectory $p_{\text{smooth}}[i] = \beta p_{\text{smooth}}[i-1] + (1 - \beta) \text{midiTarget}[i]$ initialized at $\text{midiDet}[i_0]$ at each voiced onset ($\beta = e^{-\Delta t / \tau}$). This achieves the exact exponential step response while locking sustained vocal notes flat against vibrato/jitter.

## TD-5: Fundamental-Locked TD-PSOLA Resynthesis
- **Decision:** Use Time-Domain Pitch-Synchronous Overlap-Add (`src/pc_psola.m`) with $2P$ Hann grains to shift vocal pitch while preserving vocal formants and exact duration.
- **Audit Refinement:**
  - Extend voiced period and pitch-ratio contours across unvoiced gaps using nearest-neighbor extrapolation prior to sample interpolation to prevent consonant-vowel boundary chirps.
  - Isolate the fundamental cycle via zero-phase low-pass filtering ($f_c = 1.38 \max f_0$) for jitter-free glottal peak picking (`ta`), while extracting full-bandwidth grains from `x`.
  - Floor WOLA window normalization at `0.15` and crossfade unvoiced consonants over $10\text{ ms}$ to preserve natural sibilance.

## TD-6: Dark Studio Desktop UI Architecture
- **Decision:** Build `src/PitchCorrectorApp.m` using classic `figure`/`uipanel`/`uicontrol`/`axes` for fast headless testing (`Visible='off'`) and universal MATLAB compatibility, styled with a dark studio palette (`#12141A` / `#1F242E`) and zero emojis.
