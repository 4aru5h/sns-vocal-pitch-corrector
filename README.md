# Vocal Pitch Correction (AutoTune) in Base MATLAB

A monophonic vocal pitch correction system (AutoTune-style) implemented from scratch in **Base MATLAB R2026b**. Built without relying on the Signal Processing Toolbox or Audio Toolbox.

---

## 1. Overview & Architecture

The system resynthesizes waveforms at new target pitches while strictly preserving audio duration:

```
Audio / Mic ──► pc_preprocess ──► pc_yin ──► pc_correction_contour ──► pc_psola ──► Output WAV / Playback
                                     │               │                     │
                                     │        (Scale Snapping)             │
                                     ▼               ▼                     ▼
                               pc_plot_waveform  pc_plot_pitch      pc_plot_spectrum
                                     ▲               ▲                     ▲
                                     └───────────────┴─────────────────────┘
                                           PitchCorrectorApp (uifigure)
```

### Core Architecture Principles
1. **Base MATLAB Only:** Uses built-in primitives (`fft`, `ifft`, `interp1`, `movmedian`, `cumsum`, `audioread`, `audiowrite`, `audiorecorder`, `audioplayer`, `uifigure`).
2. **Time-Domain Resynthesis (TD-PSOLA):** Time-scale factor is strictly 1.0; pitch marks are interpolated per sample, preserving formant structure and phoneme duration.
3. **Window-Sum Normalisation:** Overlap-add is normalised by the running sum of the synthesis windows, mathematically guaranteeing that a ratio of 1.0 produces an exact identity ($> 60\text{ dB}$ SNR) and eliminating loudness variations.
4. **Fast $O(N \log N)$ YIN Pitch Tracking:** Cross-correlation computed via FFTs and cumulative energy vectors, enabling 10 seconds of 44.1 kHz audio to be tracked in under 2 seconds.

---

## 2. Module Specifications

| Module | Purpose |
|---|---|
| `pc_default_config.m` | Central parameter repository (frequencies, thresholds, hop size, retune speeds). |
| `pc_hann.m` | Symmetric Hann window generator (column vector). |
| `pc_synth_voice.m` | Harmonic voice synthesizer for unit tests and ground-truth validation. |
| `pc_preprocess.m` | Converts input to mono column vector, removes DC bias, peak-normalises to 0.95. |
| `pc_hz2midi.m` / `pc_midi2hz.m` | Continuous frequency to fractional MIDI note conversions and inverse. |
| `pc_midi2name.m` | Maps MIDI numbers to scientific pitch notation (`C4`, `A4`, `C#5`, etc.). |
| `pc_scale_pcs.m` | Generates sorted pitch-class sets for 12 keys (chromatic, major, natural minor). |
| `pc_snap_to_scale.m` | Snaps fractional MIDI notes to the nearest scale pitch class (tie-lower rule). |
| `pc_yin.m` | High-accuracy YIN f0 tracker with CMNDF, parabolic interpolation, and median filtering. |
| `pc_correction_contour.m` | Calculates target notes, cents deviation, and one-pole smoothed pitch shift. |
| `pc_psola.m` | Time-Domain Pitch-Synchronous Overlap-Add pitch-shifting resynthesizer. |
| `pc_process.m` | Orchestrator executing the complete pipeline and verification tracker. |
| `pc_stft.m` | One-sided magnitude Short-Time Fourier Transform. |
| `pc_plot_*.m` | Visualisation renderers (waveform comparison, pitch tracks, spectrogram). |
| `PitchCorrectorApp.m` | Programmatic UIFigure application with live recording, processing, and playback. |

---

## 3. Mathematical Principles & Algorithms

### 3.1 YIN Fundamental Frequency Tracking
For each frame with integration window $W = \text{round}(winSec \cdot fs)$ and maximum lag $\tau_{\max} = \text{ceil}(fs / f_{\min})$:
1. **Difference Function:**
   $$d(\tau) = \sum_{j=1}^W (x_j - x_{j+\tau})^2 = E_u + E_v(\tau) - 2 r_{u,v}(\tau)$$
   Computed in $O(N \log N)$ time using FFT cross-correlation and cumulative energy of squared frame samples.
2. **Cumulative Mean Normalized Difference Function (CMNDF):**
   $$d'(0) = 1, \quad d'(\tau) = \frac{d(\tau) \cdot \tau}{\sum_{k=1}^\tau d(k)}$$
3. **Threshold Search & Parabolic Interpolation:**
   Locates the first dip in $[\tau_{\min}, \tau_{\max}]$ falling below $\text{threshold} = 0.15$ and descends to the local minimum $\tau^*$. Parabolic interpolation around $\tau^*$ yields fractional lag $\tau_{\text{fine}}$:
   $$\delta = \frac{d'(\tau^*-1) - d'(\tau^*+1)}{2(d'(\tau^*-1) - 2d'(\tau^*) + d'(\tau^*+1))}, \quad f_0 = \frac{fs}{\tau^* + \delta}$$
4. **Voicing Decision & Median Filtering:**
   Gated by aperiodicity $d'_{\text{fine}} < 0.25$ and RMS $>-45\text{ dBFS}$. Spurious voiced runs of length $< 3$ frames are rejected; valid runs receive a 5-frame moving median filter.

### 3.2 Pitch Correction Contour & Retune Smoothing
For each voiced frame $n$:
1. Detected note: $m[n] = 69 + 12 \log_2(f_0[n] / 440)$.
2. Nearest scale note: $m_T[n] = \text{snap}(m[n], \text{pcs})$.
3. Raw shift: $o[n] = \text{strength} \cdot (m_T[n] - m[n])$, clamped to $\pm \text{maxShiftSemis}$.
4. One-pole retune smoothing on shift offset:
   $$\alpha = 1 - \exp\left(-\frac{T_{\text{hop}}}{\text{retuneMs}/1000}\right), \quad s[n] = s[n-1] + \alpha (o[n] - s[n-1])$$
   Smoothing the offset rather than absolute pitch naturally preserves musical vibrato. The state resets to 0 at voiced-run onsets.
5. Pitch shift ratio: $\text{ratio}[n] = 2^{s[n] / 12}$.

### 3.3 Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA)
1. Pitch period $P(t) = fs / f_0(t)$ and ratio are interpolated to the audio sample grid.
2. Analysis pitch marks $t_a$ are placed pitch-synchronously ($t_a(k+1) = t_a(k) + P(t_a(k))$) and refined to local waveform peaks.
3. Synthesis pitch marks $t_s$ are generated according to the local shift ratio:
   $$t_s(j+1) = t_s(j) + \frac{P(t_s(j))}{\text{ratio}(t_s(j))}$$
4. Hann-windowed grains of length $2P_k + 1$ from the nearest analysis marks are accumulated at each synthesis mark:
   $$y[n] = \frac{\sum_j g_j[n]}{\max\left(\sum_j w_j[n], 10^{-3}\right)}$$

---

## 4. Running the Tests

To run the automated test suite in MATLAB batch mode:
```powershell
Start-Process -FilePath 'C:\Program Files\MATLAB\R2026b\bin\matlab.exe' -ArgumentList '-batch','run_tests','-logfile',"$env:TEMP\sns_tests.log" -WorkingDirectory (Get-Location) -Wait -NoNewWindow; Get-Content "$env:TEMP\sns_tests.log"
```
Or inside an interactive MATLAB session:
```matlab
run_tests
```

### Milestone Coverage:
- `test_m0_basics.m`: Hann window symmetry, harmonic voice synthesizer, default config.
- `test_m1_music.m`: MIDI conversions, note names, scale generation, nearest-note snapping.
- `test_m2_yin.m`: Preprocessing, synthetic tones (100–880 Hz, $<5$ cents error), linear glide, noise/silence rejection, speed benchmark ($< 5\text{ s}$ for 10 s audio).
- `test_m3_contour.m`: Strength scaling, hard snapping, retune step response ($1 - 1/e$ at $\tau$), shift clamping.
- `test_m4_psola.m`: Exact identity ($\ge 60\text{ dB}$ SNR at ratio=1), semitone shifts ($\pm 1$, $\pm 3$), RMS preservation.
- `test_m5_pipeline.m`: End-to-end pipeline, vibrato reduction ($\ge 70\%$), WAV roundtrip, silence.
- `test_m6_plots.m`: STFT numerical accuracy and headless rendering of all plots.
- `test_m7_gui.m`: Automated smoke test of `PitchCorrectorApp`.

---

## 5. Running the Demo & GUI

### Running the Demonstration Script
From MATLAB or PowerShell:
```matlab
addpath('src');
run('demo/demo_autotune.m');
```
This generates:
- `demo/out/original.wav` (deliberately out-of-tune synthetic vocal phrase).
- `demo/out/corrected.wav` (AutoTune-corrected audio).
- `demo/out/autotune_demo.png` (high-resolution waveform, pitch contour, and spectrogram plots).

### Launching the Interactive GUI
In the MATLAB command prompt:
```matlab
addpath('src');
app = PitchCorrectorApp();
```
Features available in the interface:
- **Load WAV:** Load any monophonic vocal recording.
- **Record Mic:** Record directly from your microphone via `audiorecorder` (44.1 kHz).
- **Key & Scale Selectors:** Choose from all 12 musical keys and Chromatic, Major, or Minor scales.
- **Strength Slider:** Adjust correction intensity from 0% (transparent bypass) to 100% (hard tune).
- **Retune Speed Slider:** Adjust correction responsiveness from 0 ms (hard snap) to 400 ms (subtle drift).
- **Interactive Visualizers:** Waveform comparison, pitch tracks with note-name ticks, and magnitude spectrogram.
- **Real-Time Playback & Export:** Audition original vs corrected audio or save to WAV.
