# TECHNICAL_DECISIONS

| ID | Decision | Justification | Status |
|---|---|---|---|
| TD-01 | Implement f0 estimation and pitch shifting from scratch; no `pitch()`/`shiftPitch()`. | Must demonstrate DSP understanding in a Signals & Systems viva. Also forced: Audio and Signal Processing Toolboxes are **not installed** (verified in `R2026b\toolbox`). | Agreed |
| TD-02 | Base MATLAB only; write own `pc_hann`, `pc_stft`. Use `fft`, `interp1`, `movmedian`, `audioread/audiowrite/audiorecorder/audioplayer`, `uifigure`. | No toolboxes available; avoids hidden dependencies. | Agreed |
| TD-03 | Offline processing (load WAV or record a clip, then process). No real-time streaming. | Due tomorrow; real-time streaming adds latency/buffering risk with no gain in DSP correctness. | Agreed |
| TD-04 | YIN with CMNDF; aperiodicity d′(τ*) is the confidence measure (confidence = 1−d′); voiced = low d′ AND above energy gate. | Fewer octave errors than raw autocorrelation; gives a principled confidence value for free. | Agreed |
| TD-05 | TD-PSOLA with f0-derived pitch marks (refined to local maxima), not glottal-closure detection. | Handles a ratio that changes every frame, preserves duration, keeps voice character roughly intact. A phase vocoder + resample approach is awkward with time-varying ratios and sounds phasey. GCI detection is too much work for a 1-day timeline. | Agreed |
| TD-06 | Overlap-add normalised by the summed window. | Makes ratio=1 an exact identity, which gives a hard test; removes loudness change when grains overlap more. | Architect |
| TD-07 | Retune speed = one-pole smoothing of the correction **offset**, reset at each voiced-run onset; strength scales the offset. | Simple, testable (63 % step response at τ), and preserves natural vibrato that is faster than τ. | Architect |
| TD-08 | Scales: chromatic + major + natural minor, all 12 keys. Snap tie → lower note. | Covers the demo; deterministic tie rule allows exact tests. | Agreed |
| TD-09 | GUI: programmatic `uifigure` in a plain `.m` file; GUI holds state only, DSP lives in `pc_process`. | Diffable and reviewable; DSP stays testable without a GUI. `.mlapp` is binary, and GUIDE is deprecated. | Agreed |
| TD-10 | Verification against synthetic harmonic signals with known f0 (`pc_synth_voice`) using matlab.unittest. | Gives ground truth; no toolbox reference implementation is available. | Architect |
| TD-11 | Demo/target machine = this machine (R2026b). | Stated by the user; no back-compatibility work. | Agreed |
