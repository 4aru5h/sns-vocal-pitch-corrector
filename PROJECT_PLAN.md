# PROJECT_PLAN — Vocal Pitch Correction (AutoTune-style) in MATLAB

**Deadline:** tomorrow (2026-11-02). **Target:** MATLAB R2026b, base MATLAB only (no Signal Processing / Audio Toolbox installed).
**Principle:** genuine pitch correction = estimate f0 → choose target note → *resynthesize the waveform at a new pitch with duration preserved*. Relabelling FFT peaks or resampling the whole clip (which changes duration) does **not** qualify.

## 1. Architecture

```
WAV / mic ─► pc_preprocess ─► pc_yin ─► pc_correction_contour ─► pc_psola ─► playback / WAV export
                                 │            │  (pc_hz2midi, pc_scale_pcs,       │
                                 │            │   pc_snap_to_scale)               │
                                 └────────────┴──────► pc_plot_* ◄────────────────┘
                     pc_process (orchestrator, pure, no GUI)  ◄── PitchCorrectorApp (uifigure GUI)
```

Layout: `src/` (all functions), `tests/` (matlab.unittest function-based tests), `demo/` (demo script + generated WAVs). Flat function files, prefix `pc_`. No classdef except none required. All signals are **column vectors, double, mono**.

## 2. Module specifications

| File | Signature | Responsibility |
|---|---|---|
| `pc_default_config.m` | `cfg = pc_default_config()` | Single source of all parameters (below). |
| `pc_preprocess.m` | `[x, info] = pc_preprocess(xIn, fs)` | Mixdown to mono (mean of channels), to double, remove DC (subtract mean), peak-normalise to 0.95 (`info.gain`). Error if `fs<8000` or `numel<round(0.1*fs)`. Silent input (peak<1e-6) → return zeros, `info.silent=true`. |
| `pc_hann.m` | `w = pc_hann(N)` | Symmetric Hann `0.5-0.5*cos(2πn/(N-1))`, column; `N==1 → 1`. |
| `pc_yin.m` | `p = pc_yin(x, fs, cfg)` | YIN f0 tracker (§3.1). Returns struct: `t` (frame centres, s), `f0` (Hz, NaN if unvoiced), `aperiodicity` (d′ at τ*), `confidence` (=1−d′, clipped [0,1]), `voiced` (logical), `rmsDb`. |
| `pc_hz2midi.m` / `pc_midi2hz.m` | `m = pc_hz2midi(f)` / `f = pc_midi2hz(m)` | `m = 69 + 12·log2(f/440)`; NaN-propagating. |
| `pc_midi2name.m` | `s = pc_midi2name(m)` | Round to nearest; sharps; `60→"C4"`, `69→"A4"`. string array output. |
| `pc_scale_pcs.m` | `pcs = pc_scale_pcs(key, scaleType)` | key ∈ {C,C#,D,…,B}; scaleType ∈ {chromatic, major, minor}. Major intervals [0 2 4 5 7 9 11], natural minor [0 2 3 5 7 8 10], added to key pitch class mod 12. |
| `pc_snap_to_scale.m` | `mT = pc_snap_to_scale(m, pcs)` | Nearest integer MIDI note whose `mod(note,12)∈pcs`; tie → lower note; NaN→NaN. Vectorised. |
| `pc_correction_contour.m` | `c = pc_correction_contour(p, cfg)` | §3.2. Returns `midiDet`, `midiTarget`, `centsDev` (det−target), `shiftSemis` (applied), `ratio`, `midiOut`. |
| `pc_psola.m` | `y = pc_psola(x, fs, p, ratio, cfg)` | §3.3 TD-PSOLA, `numel(y)==numel(x)`. |
| `pc_stft.m` | `[S, f, t] = pc_stft(x, fs, N, hop)` | Magnitude STFT with `pc_hann`; one-sided. Replaces `spectrogram`. |
| `pc_process.m` | `res = pc_process(xIn, fs, cfg)` | Orchestrates preprocess→yin→contour→psola; `res` holds `x, y, fs, pitch, contour, pitchOut` (YIN re-run on `y` for verification), `cfg`. |
| `pc_plot_waveform.m`, `pc_plot_spectrum.m`, `pc_plot_pitch.m` | `pc_plot_*(ax, res)` | Draw into a given axes (works in uifigure and headless). Pitch plot: detected, target, output-measured f0 in MIDI with note-name y-ticks. Spectrum: STFT spectrogram dB of orig/corrected (selectable). |
| `pc_synth_voice.m` (test util) | `x = pc_synth_voice(fs, f0)` | Per-sample f0 vector → phase-accumulated harmonic signal, harmonics up to 0.45·fs with amplitude 1/k. Ground-truth source for tests. |
| `PitchCorrectorApp.m` | `app = PitchCorrectorApp()` | Programmatic `uifigure` GUI (§3.4); returns handle struct with test hooks. |
| `demo/demo_autotune.m` | script | Synth + optional user WAV → process → figures + WAVs in `demo/out/`. |

### Default configuration (`pc_default_config`)
```
cfg.yin.fmin = 70;  cfg.yin.fmax = 1000;      % Hz
cfg.yin.winSec = 0.025; cfg.yin.hopSec = 0.005;
cfg.yin.threshold = 0.15;                     % CMNDF absolute threshold
cfg.yin.voicedMaxAperiodicity = 0.25;         % d' gate
cfg.yin.silenceDb = -45;                      % frame RMS re. full-scale gate
cfg.yin.medianFrames = 5;                     % movmedian over voiced runs
cfg.key = 'C'; cfg.scale = 'chromatic';
cfg.strength = 1.0;                           % 0..1
cfg.retuneMs = 50;                            % 0 = hard snap
cfg.maxShiftSemis = 2;
cfg.psola.unvoicedPeriodSec = 0.01;
cfg.psola.refineMarks = true;
```

## 3. Algorithms

### 3.1 YIN (de Cheveigné & Kawahara, 2002)
Per frame (window `W=round(winSec·fs)`, lag max `τmax=ceil(fs/fmin)`, frame length `W+τmax`, hop `round(hopSec·fs)`, zero-padded ends):
1. Difference `d(τ)=Σ_{j=1}^{W}(x_j−x_{j+τ})²`, computed via FFT cross-correlation + cumulative energy (O(N log N)).
2. CMNDF `d′(0)=1`, `d′(τ)=d(τ)·τ / Σ_{k=1}^{τ}d(k)`.
3. Search `τ∈[floor(fs/fmax), τmax]`: first τ with `d′<threshold`, then descend to the local minimum; if none, global minimum.
4. Parabolic interpolation on `d′` around τ* → fractional τ; `f0=fs/τ`.
5. Voiced iff `d′(τ*) < voicedMaxAperiodicity` AND `rmsDb > silenceDb`. Unvoiced → `f0=NaN`.
6. Post: `movmedian` (base MATLAB) of f0 within each contiguous voiced run (length ≥ 3); drop voiced runs shorter than 3 frames.

### 3.2 Correction contour (strength + retune speed)
Per voiced frame: `m=hz2midi(f0)`, `mT=snap(m,pcs)`, `centsDev=100(m−mT)`.
Raw offset `o[n] = strength·(mT−m)` (semitones), clamped to ±maxShiftSemis.
Retune smoothing (one-pole on the offset): `α = 1−exp(−hop/(retuneMs/1000))` (α=1 if retuneMs=0); `s[n]=s[n−1]+α(o[n]−s[n−1])`; `s` resets to 0 at each voiced-run onset; unvoiced → `s=0`.
`ratio = 2^(s/12)`, `midiOut = m + s`.
*Documented limitation:* smoothing the offset (not the absolute pitch) preserves vibrato faster than the retune time constant — acceptable and matches "natural" retune behaviour.

### 3.3 TD-PSOLA (time-preserving, per-sample ratio)
1. Interpolate frame f0 and ratio to sample rate (`interp1`, linear; unvoiced: period `Pu=round(unvoicedPeriodSec·fs)`, ratio 1).
2. **Analysis marks** `ta`: start at first sample; `ta(k+1)=ta(k)+P(ta(k))`. In voiced regions, if `refineMarks`, move each mark to the max of `x` within ±0.25P of its predicted position (sequential, so spacing stays ≈P).
3. **Synthesis marks** `ts`: `ts(1)=ta(1)`; `ts(j+1)=ts(j)+P(ts(j))/ratio(ts(j))` until end of signal.
4. For each `ts(j)`, choose the analysis mark `k` nearest in time (duration preserved: time-scale factor 1).
5. Grain = `x(ta(k)−P_k : ta(k)+P_k) .* pc_hann(2P_k+1)` (zero-pad at edges), overlap-add centred on `ts(j)`; accumulate the window sum separately.
6. `y = acc ./ max(wsum, 1e−3)` for samples with `wsum>1e−3`, else 0. This normalisation makes `ratio≡1` an **exact identity** and removes the loudness change at ratio≠1.
7. Final: if `max|y|>1`, scale to 0.99 (report in `res`).

### 3.4 GUI (`PitchCorrectorApp`)
Programmatic `uifigure` + `uigridlayout`. Controls: Load WAV, Record (duration field, `audiorecorder` 44.1 kHz mono), Key dropdown, Scale dropdown, Strength slider (0–100 %), Retune slider (0–400 ms), Process, Play Original, Play Corrected, Stop, Export WAV, status label. Axes: waveform (orig vs corrected), pitch contour, spectrogram (orig/corrected toggle). All DSP via `pc_process`; GUI holds state only. Errors → `uialert`, never crash. Returned struct exposes `loadAudio(x,fs)`, `process()`, `fig` for scripted smoke tests.

## 4. Milestones & acceptance criteria
Critical path: M0→M1→M2→M3→M4→M5; M6/M7 after. Each milestone = code + passing tests under `tests/`; run with `runtests('tests')` in `matlab -batch`.

| # | Deliverable | Acceptance criteria (all automated unless marked) |
|---|---|---|
| M0 | Repo skeleton, `pc_default_config`, `pc_hann`, `pc_synth_voice`, `tests/` harness | `runtests('tests')` runs in batch; `pc_hann(5)` = `[0 .5 1 .5 0]'`. |
| M1 | `pc_hz2midi`, `pc_midi2hz`, `pc_midi2name`, `pc_scale_pcs`, `pc_snap_to_scale` | 440→69 exact; 261.6256→60 ±1e-3; round-trip error <1e-9; `C4`, `A4`, `C#5` names; A minor = {9,11,0,2,4,5,7}; C major: 61.4→62, 61.0→60 (tie lower), 64.6→65; chromatic 60.49→60, 60.51→61; NaN passes through. |
| M2 | `pc_preprocess`, `pc_yin` | Synth tones 100/220/440/880 Hz (fs 44.1k, 1 s): median error <5 cents, voiced ≥95 % frames; linear glide 200→400 Hz: median error <15 cents; white noise & silence: voiced ≤5 %; <1 % frames with >600-cent error on harmonic synth; stereo input handled; 10 s clip processed in <5 s. |
| M3 | `pc_correction_contour` | strength 0 → ratio≡1; strength 1, retune 0 → `midiOut==midiTarget` (±1e-9) on voiced frames; retune τ: step response reaches 63 % ±1 hop at τ; unvoiced frames ratio 1; |shift| ≤ maxShiftSemis. |
| M4 | `pc_psola` | ratio≡1 → SNR ≥ 60 dB vs input; `numel(y)==numel(x)` always; constant ratio 2^(±1/12) on 220 Hz synth → YIN of output median within 10 cents of 233.08/207.65 Hz; ratio 2^(±3/12) within 15 cents; output RMS/input RMS ∈ [0.8, 1.25]; no NaN/Inf; works on signal with unvoiced gaps. |
| M5 | `pc_process`, WAV I/O, end-to-end | Synth at 220 Hz·2^(−0.4/12) with 5.5 Hz ±20-cent vibrato, chromatic, strength 1, retune 0 → mean |cents deviation| of output reduced ≥70 % vs input; strength 0 → output ≈ input (SNR ≥ 60 dB); `audiowrite`/`audioread` round-trip; silent file → silent output, no error. |
| M6 | `pc_stft`, `pc_plot_*` | `pc_stft` column matches `abs(fft(frame.*w))` (rel err <1e-10); plot functions render into an invisible figure in batch without error. |
| M7 | `PitchCorrectorApp` | Scripted smoke test: create app, `loadAudio(synth)`, `process()`, all three axes populated, delete fig — no error. **Manual:** load WAV, record 3 s, change key/scale/strength/retune, play, export, all on this machine. |
| M8 | `demo/demo_autotune.m`, README | Generates before/after WAVs + figures in `demo/out/`; README states how to run. |

## 5. Risks & mitigations
| Risk | Mitigation |
|---|---|
| One-day deadline | Strict critical path; GUI minimal; cut list below. |
| No SP/Audio toolbox | Own `pc_hann`, `pc_stft`; `movmedian`, `interp1`, `fft` only. Tests use synthetic ground truth instead of `pitch()`. |
| `matlab -batch` hang observed on first launch | Verify batch works before M0 is accepted (see IMPLEMENTATION_STATUS blocker). |
| YIN octave errors | First-dip threshold rule + median filter; test for >600-cent errors. |
| PSOLA artefacts at voicing boundaries / mark jitter | Window-sum normalisation; ratio→1 in unvoiced; mark refinement constrained to ±0.25P. |
| Real voice: breath, reverb, polyphony | Out of scope: monophonic dry vocal assumed; low-confidence frames pass through uncorrected. |
| GUI cannot be exercised in `-batch` | Smoke test uses invisible figure; final manual checklist on desktop. |
| Clipping after shift | Peak check + rescale before export. |

**Cut list (in order) if time runs out:** spectrogram toggle → recording (keep WAV load) → mark refinement → retune smoothing (keep hard snap). Never cut: YIN, PSOLA, scale snapping, strength, pitch plot, export.

**Out of scope:** real-time streaming, formant shifting, extra scales, MIDI target melodies, polyphonic input.
