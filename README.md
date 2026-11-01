# Digital Vocal Pitch Correction (AutoTune) in Base MATLAB
## Complete Signals & Systems Theoretical & Engineering Guide for Project Report

---

## 1. Project Overview & Objective

The objective of this project is to design and implement a complete, studio-grade **Digital Vocal Pitch Correction System (AutoTune)** in **100% Base MATLAB** without relying on external commercial toolboxes (such as the Signal Processing Toolbox or Audio Toolbox).

Instead of calling black-box functions, every single stage of the digital signal processing (DSP) chain—window generation, Short-Time Fourier Transform (STFT), spectral noise estimation, Wiener spectral gating, bilinear-transform Butterworth IIR filtering, zero-phase forward-backward filtering, FFT-accelerated autocorrelation, YIN fundamental frequency ($f_0$) tracking, first-order IIR trajectory smoothing, and Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA) resynthesis—is derived and implemented from first principles of **Signals and Systems**.

---

## 2. End-to-End Signal Processing Architecture

The system processes a raw vocal signal $x_{\text{in}}[n]$ sampled at frequency $f_s$ (typically $44.1\text{ kHz}$) through a 9-stage sequential pipeline orchestrated by `src/pc_process.m`:

```text
Raw Audio Input x_in[n]
   │
   ▼
[Stage 1] Input Validation & Conditioning (src/pc_preprocess.m)
   │  • Stereo-to-mono downmix, DC removal, silence gate, peak normalization
   ▼
[Stage 2] Stationary Noise Reduction (src/pc_denoise.m)
   │  • STFT analysis -> Noise PSD estimation -> Decision-Directed Wiener Spectral Gate -> WOLA IFFT
   ▼
[Stage 3] Zero-Phase Vocal Conditioning Filter (src/pc_vocal_filter.m)
   │  • 2nd-order Butterworth HPF (55 Hz) + LPF (10 kHz) via Bilinear Transform + Forward-Backward pass
   ▼
[Stage 4] YIN Fundamental Frequency (f0) Detection (src/pc_yin.m)
   │  • FFT Wiener-Khinchin Autocorrelation -> Unbiased Difference Function -> CMNDF -> Parabolic Fit
   ▼
[Stage 5] Musical Scale Mapping & Hysteresis (src/pc_hz2midi.m, src/pc_snap_to_scale.m)
   │  • Logarithmic Hz-to-MIDI mapping -> Pitch-class quantization -> 15-cent hysteresis deadband
   ▼
[Stage 6] Retune Speed Trajectory Smoothing (src/pc_correction_contour.m)
   │  • First-order causal IIR low-pass filter on target MIDI trajectory with time constant tau = retuneMs
   ▼
[Stage 7] Time-Domain PSOLA Pitch Resynthesis (src/pc_psola.m)
   │  • Fundamental-isolated glottal peak picking -> Hann grain extraction -> Pitch-shifted Overlap-Add
   ▼
[Stage 8] Output Smoothing & Consonant Preservation (src/pc_psola.m)
   │  • 10 ms moving-average voiced/unvoiced crossfade + RMS energy matching + peak limiter
   ▼
[Stage 9] Diagnostic Visualization, Playback & WAV Export (src/PitchCorrectorApp.m)
```

---

## 3. Core "Signals and Systems" Concepts Used & Mathematical Derivations

This section maps every module in the codebase to the exact theoretical concepts from a university **Signals and Systems** / **Digital Signal Processing** course.

---

### Concept 1: Discrete-Time Signals, Energy, Power & DC Component (`src/pc_preprocess.m`)

1. **Multi-Channel to Monophonic Downmixing:**
   A stereo recording is a two-channel discrete-time signal $\mathbf{x}[n] = [x_L[n],\, x_R[n]]$. It is converted to a monophonic signal via linear superposition:
   $$x_{\text{mono}}[n] = \frac{1}{2}\bigl(x_L[n] + x_R[n]\bigr)$$

2. **Zero-Frequency (DC Offset) Removal:**
   From Fourier analysis, the $k = 0$ DFT bin (DC component) of a finite-length signal of $N$ samples is its time-average:
   $$\mu_x = \frac{1}{N} \sum_{n=0}^{N-1} x[n]$$
   Hardware analog-to-digital converters (ADCs) often introduce a constant voltage bias $\mu_x \neq 0$, which causes clicks at window boundaries and corrupts low-frequency autocorrelation. Subtracting $\mu_x$ forces the signal to be zero-mean ($X[0] = 0$).

3. **Signal Power, RMS, and Decibel (dBFS) Scaling:**
   The root-mean-square (RMS) amplitude measures the square root of the average discrete-time signal power:
   $$x_{\text{RMS}} = \sqrt{\frac{1}{N}\sum_{n=0}^{N-1} |x[n]|^2}$$
   To prevent digital clipping ($|x[n]| > 1.0$) while maximizing dynamic range, the signal is normalized to a peak amplitude of $0.95$ ($-0.45\text{ dBFS}$). If the raw peak is below $10^{-4}$ ($-80\text{ dBFS}$, corresponding to $1\text{–}2\text{ LSB}$ of 16-bit quantization noise $1/32768 \approx 3.05 \times 10^{-5}$), the signal is classified as digital silence and gated to zero so quantization noise is never amplified.

---

### Concept 2: Windowing, Short-Time Fourier Transform (STFT) & COLA Reconstruction (`src/pc_hann.m`, `src/pc_stft.m`, `src/pc_denoise.m`)

1. **Non-Stationary Signals & Time-Frequency Localization:**
   Human speech and singing are **non-stationary** signals—their frequency content changes over time as notes and vowels change. A single global Discrete Fourier Transform (DFT) loses all time information. However, vocal signals are **quasi-stationary** over short intervals ($10\text{–}40\text{ ms}$).

2. **Symmetric Hann Window (`src/pc_hann.m`):**
   Multiplying a signal by a rectangular window in the time domain corresponds to periodic convolution with a Dirichlet (sinc-like) kernel in the frequency domain, causing severe **spectral leakage** ($-13\text{ dB}$ sidelobes). We instead use a raised-cosine **Hann window** of length $M$:
   $$w[n] = 0.5 \left(1 - \cos\left(\frac{2\pi n}{M - 1}\right)\right), \quad n = 0, 1, \dots, M-1$$
   which suppresses spectral sidelobes to $-31.5\text{ dB}$ with a rapid $-18\text{ dB/octave}$ roll-off.

3. **Forward STFT (`src/pc_stft.m`):**
   With window length $M$ and hop size $R$ (in samples), the $m$-th frame is extracted, windowed, and transformed via the $N_{\text{fft}}$-point Fast Fourier Transform (FFT):
   $$X[k, m] = \sum_{n=0}^{M-1} x[n + mR]\, w[n]\, e^{-j \frac{2\pi}{N_{\text{fft}}} k n}, \quad k = 0, 1, \dots, \frac{N_{\text{fft}}}{2}$$
   Because $x[n]$ is real-valued, its spectrum exhibits **conjugate symmetry** ($X[N_{\text{fft}} - k] = X^*[k]$), so only the first $N_{\text{fft}}/2 + 1$ non-negative frequency bins are stored.

4. **Weighted Overlap-Add (WOLA) & the COLA Condition (`src/pc_denoise.m`):**
   After modifying the short-time spectrum to $\hat{X}[k, m] = G[k, m]\, X[k, m]$, each frame is inverted back to the time domain via the Inverse FFT (`ifft`) and multiplied by a synthesis window $w[n]$. Perfect reconstruction is achieved via Weighted Overlap-Add:
   $$\hat{x}[n] = \frac{\sum_{m} \hat{x}_m[n - mR]\, w[n - mR]}{\sum_{m} w^2[n - mR]}$$
   With $75\%$ overlap ($R = M/4$), the denominator $\sum_m w^2[n - mR]$ is strictly positive and constant across the signal interior (the **Constant Overlap-Add / COLA property**).

---

### Concept 3: Power Spectral Density (PSD) & Wiener Spectral Gating (`src/pc_denoise.m`)

1. **Additive Noise Model:**
   In a real room recording, the microphone captures the clean voice $s[n]$ corrupted by stationary additive background noise $v[n]$ (fan noise, room hiss, pre-amp thermal noise):
   $$x[n] = s[n] + v[n] \xrightarrow{\text{STFT}} X[k, m] = S[k, m] + V[k, m]$$

2. **Noise PSD Estimation ($\hat{P}_v[k]$):**
   - When the recording contains vocal pauses (quiet frames where frame power drops below $25\%$ of peak vocal power), the noise power spectral density $\hat{P}_v[k]$ is estimated by averaging $|X[k, m]|^2$ across the lowest-energy $20\%$ of frames.
   - When the singer sings a continuous sustained note with no pauses, $\hat{P}_v[k]$ is estimated from the **inter-harmonic spectral valleys** (the 30th percentile of $|X[k,m]|^2$ across frequency bins), preventing the filter from mistaking sustained vocal harmonics for stationary noise.
   - If the estimated broadband Signal-to-Noise Ratio (SNR) exceeds $40\text{ dB}$, the denoiser automatically bypasses gating so studio-clean signals suffer zero modification.

3. **Decision-Directed Wiener Filter (Ephraim-Malah Estimator):**
   For each frequency bin $k$ and frame $m$, the *a posteriori* SNR is $\gamma[k, m] = |X[k, m]|^2 / (\beta \hat{P}_v[k])$, where $\beta = 1 + 1.6 \cdot \text{strength}$ is the oversubtraction factor. The *a priori* SNR $\xi[k, m]$ is tracked smoothly across frames:
   $$\xi[k, m] = \alpha_{\text{dd}}\, G^2[k, m-1]\, \gamma[k, m-1] + (1 - \alpha_{\text{dd}}) \max\bigl(\gamma[k, m] - 1,\, 0\bigr), \quad \alpha_{\text{dd}} = 0.90$$
   The optimal minimum mean-square error (MMSE) **Wiener spectral gain** is:
   $$G[k, m] = \max\left(G_{\text{floor}},\, \frac{\xi[k, m]}{\xi[k, m] + 1}\right)$$
   To prevent isolated random tonal spikes ("musical noise"), $G[k, m]$ is convolved across frequency with a 3-tap smoothing kernel $[0.25,\, 0.50,\, 0.25]$ and across time with $[0.20,\, 0.60,\, 0.20]$.

---

### Concept 4: Continuous-to-Discrete IIR Filter Design via Bilinear Transform & Zero-Phase Filtering (`src/pc_vocal_filter.m`)

1. **Continuous-Time Butterworth Prototype & Bilinear Transform:**
   Human vocal fundamentals lie above $80\text{ Hz}$ ($\approx \text{E2}$), and perceptually critical vocal harmonics lie below $10\text{ kHz}$. Sub-bass energy below $55\text{ Hz}$ consists of microphone stand rumble, air-conditioning hum, and breath plosives, while energy above $10\text{ kHz}$ is predominantly hiss.
   We design 2nd-order Butterworth Infinite Impulse Response (IIR) high-pass ($f_c = 55\text{ Hz}$) and low-pass ($f_c = 10\text{ kHz}$) filters directly in Base MATLAB using the **Bilinear Transform** with frequency pre-warping:
   $$s = \frac{2}{T_s}\frac{1 - z^{-1}}{1 + z^{-1}}, \quad K = \tan\left(\frac{\pi f_c}{f_s}\right)$$
   Mapping the continuous-time 2nd-order Butterworth transfer function $H(s) = \frac{1}{(s/\omega_c)^2 + \sqrt{2}(s/\omega_c) + 1}$ into the $z$-domain yields the causal LTI difference equation:
   $$y[n] + a_1 y[n-1] + a_2 y[n-2] = b_0 x[n] + b_1 x[n-1] + b_2 x[n-2]$$
   with transfer function:
   $$H(z) = \frac{b_0 + b_1 z^{-1} + b_2 z^{-2}}{1 + a_1 z^{-1} + a_2 z^{-2}}$$
   where for the low-pass filter:
   $$\text{norm} = \frac{1}{1 + \sqrt{2}K + K^2}, \quad b_0 = K^2\,\text{norm}, \quad b_1 = 2b_0, \quad b_2 = b_0$$
   $$a_1 = 2(K^2 - 1)\,\text{norm}, \quad a_2 = (1 - \sqrt{2}K + K^2)\,\text{norm}$$
   (and for the high-pass filter, $b_0 = \text{norm},\, b_1 = -2\text{norm},\, b_2 = \text{norm}$ with identical poles $a_1, a_2$).

2. **Zero-Phase Forward-Backward Filtering (Time-Reversal Property of the Z-Transform):**
   A single causal IIR pass $H(z)$ introduces non-linear **phase distortion** $\angle H(e^{j\omega})$, which shifts the relative phase of vocal harmonics and distorts glottal pulse peaks in the time domain.
   From Signals and Systems, time-reversing a signal corresponds to replacing $z$ with $z^{-1}$ in the $Z$-transform ($x[-n] \leftrightarrow X(z^{-1})$). By filtering the signal forward with `filter(b, a, x)`, reversing the output in time (`flipud`), filtering again, and reversing back, the effective system transfer function is:
   $$H_{\text{eff}}(e^{j\omega}) = H(e^{j\omega})\, H(e^{-j\omega}) = \bigl|H(e^{j\omega})\bigr|^2$$
   Notice that $\bigl|H(e^{j\omega})\bigr|^2$ is **purely real and non-negative** for all $\omega$! Thus:
   - The phase response is **identically zero** ($\angle H_{\text{eff}}(e^{j\omega}) = 0$) across all frequencies—glottal pulse peaks do not shift by even a fraction of a sample.
   - The effective filter order doubles from 2nd-order to 4th-order ($-24\text{ dB/octave}$ roll-off).
   - Odd-symmetric reflection padding is applied at both ends before filtering to eliminate startup/ending transient ringing.

---

### Concept 5: Autocorrelation, Wiener-Khinchin Theorem & the YIN Pitch Estimator (`src/pc_yin.m`)

1. **Periodicity in the Time Domain:**
   A voiced vocal segment with fundamental frequency $f_0$ is periodic with fundamental period $T_0 = 1/f_0$ seconds, or discrete lag $\tau_0 = f_s / f_0$ samples:
   $$x[n + \tau_0] \approx x[n]$$

2. **Unbiased Mean-Square Difference Function $\bar{d}(\tau)$:**
   To find $\tau_0$ within an analysis frame of $W$ samples ($40\text{ ms}$), YIN (de Cheveigné & Kawahara, 2002) measures the average squared difference between the signal and its delayed version at lag $\tau$:
   $$\bar{d}(\tau) = \frac{1}{W - \tau} \sum_{j=0}^{W - 1 - \tau} \bigl(x[j] - x[j + \tau]\bigr)^2$$
   Expanding the square gives three terms:
   $$\sum_{j=0}^{W-1-\tau} (x[j] - x[j+\tau])^2 = \underbrace{\sum_{j=0}^{W-1-\tau} x^2[j]}_{E_{\text{head}}(\tau)} + \underbrace{\sum_{k=\tau}^{W-1} x^2[k]}_{E_{\text{tail}}(\tau)} - 2 \underbrace{\sum_{j=0}^{W-1-\tau} x[j]\,x[j+\tau]}_{r(\tau)}$$

3. **$O(W \log W)$ Fast Autocorrelation via the Wiener-Khinchin Theorem:**
   Evaluating $r(\tau)$ directly for all lags $\tau \in [\tau_{\min}, \tau_{\max}]$ takes $O(W^2)$ operations per frame. By the **Wiener-Khinchin / Cross-Correlation Theorem** of the DFT, the linear autocorrelation $r(\tau)$ is the Inverse DFT of the power spectrum $|X[k]|^2$ when the frame is zero-padded to $N_{\text{fft}} \ge 2W$:
   $$r(\tau) = \text{IFFT}\Bigl\{\bigl|\text{FFT}\{x_{\text{pad}}[n]\}\bigr|^2\Bigr\}$$
   Meanwhile, $E_{\text{head}}(\tau)$ and $E_{\text{tail}}(\tau)$ are computed in $O(W)$ time using a prefix sum (`cumsum(x.^2)`). Dividing by $(W - \tau)$ removes window-shrinkage bias.

4. **Cumulative Mean Normalized Difference Function (CMNDF) $d'(\tau)$:**
   In raw autocorrelation or difference functions, $\bar{d}(\tau)$ approaches zero near $\tau = 0$, and strong formants (vocal tract resonances) can create secondary dips that cause octave errors. YIN normalizes each lag by its running cumulative average from lag $1$ to $\tau$:
   $$d'(\tau) = \begin{cases} 1, & \tau = 0 \\ \dfrac{\bar{d}(\tau)}{\frac{1}{\tau} \sum_{j=1}^{\tau} \bar{d}(j)}, & \tau \ge 1 \end{cases}$$
   Selecting the first local minimum of $d'(\tau)$ below threshold $\theta = 0.15$ (plus a subharmonic verification check at $2\tau$) prevents both zero-lag lock and octave errors.

5. **Sub-Sample Parabolic Interpolation:**
   Because $\tau$ is an integer sample index, integer lag quantization limits frequency resolution at high pitches (e.g., at $440\text{ Hz}$ and $f_s = 44100\text{ Hz}$, $\tau_0 = 100.227$ samples; rounding to $100$ causes a $3.9\text{-cent}$ error). Fitting a continuous parabola through $(\tau-1, \bar{d}(\tau-1))$, $(\tau, \bar{d}(\tau))$, and $(\tau+1, \bar{d}(\tau+1))$ yields the fractional vertex offset:
   $$\delta = \frac{\bar{d}(\tau-1) - \bar{d}(\tau+1)}{2\bigl(\bar{d}(\tau-1) - 2\bar{d}(\tau) + \bar{d}(\tau+1)\bigr)} \in [-0.5,\, 0.5]$$
   giving $\hat{f}_0 = \frac{f_s}{\tau + \delta}$ with **$< 0.05\text{-cent}$ accuracy** across the vocal range.

---

### Concept 6: Logarithmic Pitch Perception, Hysteresis & First-Order IIR Trajectory Smoothing (`src/pc_hz2midi.m`, `src/pc_correction_contour.m`)

1. **Logarithmic Frequency-to-MIDI Mapping:**
   Human pitch perception is logarithmic (every octave doubles frequency). In 12-tone Equal Temperament (12-TET) referenced to $\text{A4} = 440\text{ Hz}$ ($\text{MIDI } 69$):
   $$m = 69 + 12 \log_2\left(\frac{f_0}{440}\right), \quad f_0 = 440 \cdot 2^{(m - 69)/12}$$
   One semitone equals $1.0$ MIDI unit $= 100\text{ cents}$.

2. **Scale Quantization with Boundary Hysteresis:**
   Given the pitch-class set $\mathcal{S} \subset \{0, 1, \dots, 11\}$ of the chosen musical key and scale (e.g., C Major $= \{0, 2, 4, 5, 7, 9, 11\}$), each detected pitch $m_{\text{det}}[i]$ is mapped to the nearest allowed MIDI note $m_{\text{target}}[i]$.
   To prevent rapid $5\text{ ms}$ oscillation ("note chatter") when a singer hovers near the midpoint between two scale notes, a **nonlinear deadband hysteresis** ($H = 0.15\text{ semitones} = 15\text{ cents}$) keeps the target locked to the previous note $m_{\text{target}}[i-1]$ unless the new note is closer by more than $15\text{ cents}$.

3. **First-Order Causal IIR Smoothing Filter (Retune Speed):**
   To model the classic "Retune Speed" parameter $\tau_{\text{retune}}$ (in seconds) with frame hop $\Delta t = 5\text{ ms}$, the target pitch trajectory is filtered by a first-order discrete-time low-pass IIR system with pole $\beta = e^{-\Delta t / \tau_{\text{retune}}}$:
   $$p_{\text{smooth}}[i] = \beta\, p_{\text{smooth}}[i-1] + (1 - \beta)\, m_{\text{target}}[i]$$
   initialized at each voiced onset $i_0$ as $p_{\text{smooth}}[i_0 - 1] = m_{\text{det}}[i_0]$.
   - **Step Response Analysis:** For a constant step error $\Delta m = m_{\text{target}} - m_{\text{det}}$, at frame $k$ after onset:
     $$p_{\text{smooth}}[k] - m_{\text{det}} = \bigl(1 - \beta^k\bigr)\Delta m = \left(1 - e^{-k\Delta t / \tau_{\text{retune}}}\right)\Delta m$$
     At $t = k\Delta t = \tau_{\text{retune}}$, the pitch correction reaches exactly $1 - e^{-1} \approx 63.21\%$ of the target shift—matching continuous-time RC low-pass filter theory!
   - When $\tau_{\text{retune}} = 0\text{ ms}$ ($\beta = 0$), $p_{\text{smooth}}[i] = m_{\text{target}}[i]$ instantaneously, producing the iconic hard-stepped "T-Pain / Cher" vocal quantization effect.
   - The required per-frame pitch shift ratio is:
     $$R[i] = 2^{\frac{\text{strength} \cdot (p_{\text{smooth}}[i] - m_{\text{det}}[i])}{12}}$$

---

### Concept 7: Source-Filter Vocal Model & TD-PSOLA Resynthesis (`src/pc_synth_voice.m`, `src/pc_psola.m`)

1. **Why Simple Resampling Fails (The Formant Problem):**
   In Signals and Systems, the time-scaling property of the Fourier Transform states:
   $$x(a t) \xleftrightarrow{\mathcal{F}} \frac{1}{|a|} X\left(\frac{\omega}{a}\right)$$
   If you shift vocal pitch upward by a factor $a > 1$ via simple time-domain resampling, **every frequency in the spectrum scales by $a$**—including the **vocal tract resonances (formants)** $F_1, F_2, F_3$! Scaling formants upward makes a human voice sound like an unnatural "chipmunk."

2. **The Source-Filter Model of Speech Production:**
   A voiced human vocal signal is the convolution of a periodic glottal excitation pulse train $e[n] = \sum_m \delta[n - m P_0]$ (controlled by the vocal cords at fundamental period $P_0 = f_s/f_0$) with the impulse response $h[n]$ of the vocal tract cavity (which shapes the formants):
   $$x[n] = e[n] * h[n] = \sum_{m} h[n - m P_0]$$
   Each pitch period consists of a damped vocal-tract impulse response $h[n]$ centered at a glottal pulse peak $t_a(m)$.

3. **Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA):**
   TD-PSOLA shifts the fundamental pitch period from $P_{\text{analysis}}$ to $P_{\text{synthesis}} = P_{\text{analysis}} / R$ **without stretching or compressing the individual impulse response $h[n]$**:
   - **Step 1 (Fundamental-Isolated Glottal Peak Picking):** The signal is zero-phase low-pass filtered at $1.38 \max(f_0)$ to isolate the fundamental wave $x_{f_0}[n]$ (removing higher harmonics so secondary formant peaks cannot cause mark jitter). Analysis pitch marks $t_a(m)$ are locked to local maxima of $x_{f_0}[n]$ spaced by $P_0(t)$.
   - **Step 2 (Synthesis Pitch Marks):** Synthesis marks $t_s(k)$ are placed across the timeline advancing by the modified period $P_{\text{syn}}(t) = P_0(t) / R(t)$.
   - **Step 3 (Hann-Windowed Grain Extraction & WOLA):** For each synthesis mark $t_s(k)$, the closest analysis mark $t_a(m^*)$ is selected. A grain of length $2 P_0 + 1$ centered at $t_a(m^*)$ is extracted from the **full-bandwidth signal $x[n]$**, windowed with a symmetric Hann window $w_m[n]$, and overlap-added centered at $t_s(k)$:
     $$y_{\text{psola}}[n] = \frac{\sum_{k} x\bigl[n - t_s(k) + t_a(m^*_k)\bigr]\, w_k\bigl[n - t_s(k)\bigr]}{\max\Bigl(0.15,\, \sum_{k} w_k\bigl[n - t_s(k)\bigr]\Bigr)}$$
   Because each individual grain $x[n - t_s(k) + t_a(m^*_k)]$ is **never time-stretched**, the spectral envelope $H(e^{j\omega})$ (the formants!) remains completely invariant, while the repetition rate of the grains shifts to the exact new fundamental frequency $R \cdot f_0$ while preserving the exact duration $N$ of the recording!

4. **Voiced/Unvoiced Crossfading:**
   Unvoiced consonants (`/s/`, `/sh/`, `/t/`, `/k/`) are broadband stochastic noise processes rather than periodic impulse trains. A $10\text{ ms}$ moving-average crossfade envelope $v_{\text{env}}[n]$ blends $y_{\text{psola}}[n]$ during voiced vowels with the crisp original signal $x[n]$ during unvoiced consonants:
   $$y[n] = v_{\text{env}}[n]\, y_{\text{psola}}[n] + \bigl(1 - v_{\text{env}}[n]\bigr)\, x[n]$$

---

## 4. Software Engineering & File-by-File Breakdown

The codebase is organized cleanly into modular DSP functions (`src/`), an interactive dark-themed desktop studio workstation (`src/PitchCorrectorApp.m`), an automated demonstration script (`demo/demo_autotune.m`), and an 8-part unit/integration test suite (`tests/`):

| File | Responsibility | Key Signals & Systems Techniques |
| :--- | :--- | :--- |
| `src/pc_default_config.m` | Master configuration struct | Centralizes sampling rate, filter cutoffs, YIN thresholds, hysteresis, and PSOLA limits. |
| `src/pc_hann.m` | Window generator | Symmetric raised-cosine Hann window $w[n] = 0.5(1 - \cos(2\pi n/(M-1)))$. |
| `src/pc_synth_voice.m` | Synthetic vocal generator | Source-filter synthesis: harmonic glottal series shaped by 3 Gaussian vocal formants ($730, 1090, 2440\text{ Hz}$) + unvoiced consonant noise. |
| `src/pc_vocal_filter.m` | Vocal bandpass filter | Bilinear-transform 2nd-order Butterworth HPF ($55\text{ Hz}$) & LPF ($10\text{ kHz}$) with reflection-padded forward-backward zero-phase filtering. |
| `src/pc_denoise.m` | Background noise suppressor | 75%-overlap COLA STFT, quiet-frame & inter-harmonic PSD estimation, decision-directed Wiener spectral gate. |
| `src/pc_preprocess.m` | Input conditioner | Stereo-to-mono downmix, DC removal, $-80\text{ dBFS}$ idle ADC gate, denoising, vocal filtering, and $0.95$ peak normalization. |
| `src/pc_yin.m` | Pitch detector ($f_0$) | Wiener-Khinchin FFT autocorrelation, unbiased mean-square difference, CMNDF, subharmonic guard, parabolic refinement, median filter. |
| `src/pc_hz2midi.m` / `pc_midi2hz.m` | Pitch unit converters | 12-TET logarithmic frequency-to-MIDI transformations ($\text{A4} = 440\text{ Hz} \leftrightarrow 69$). |
| `src/pc_scale_pcs.m` / `pc_snap_to_scale.m` | Scale quantizer | Pitch-class set generation (`major`, `minor`, `chromatic`) and nearest-note Euclidean projection in MIDI space. |
| `src/pc_correction_contour.m` | Contour generator | $15\text{-cent}$ scale boundary hysteresis + first-order causal IIR target trajectory smoothing ($\tau = \text{retuneMs}$). |
| `src/pc_psola.m` | Pitch resynthesizer | Fundamental-locked glottal peak picking, nearest-neighbor boundary extension, Hann grain WOLA, $10\text{ ms}$ unvoiced crossfade. |
| `src/pc_stft.m` | Spectral analyzer | One-sided magnitude Short-Time Fourier Transform for spectrograms. |
| `src/pc_plot_*.m` | Diagnostic visualizers | Dark-studio waveform overlays, pitch contour tracking with musical note gridlines, and STFT spectrograms / harmonic spectra. |
| `src/PitchCorrectorApp.m` | Studio GUI Workstation | Complete 10-step desktop workflow with live telemetry cards, A/B/C audio preview (`Original`, `Cleaned`, `Corrected`), and WAV export. |

---

## 5. Empirical Verification & Benchmark Results

The entire system is verified by **38 automated unit and integration tests** (`run_tests.m` running `tests/test_m0_basics.m` through `tests/test_m8_audit_dsp.m`):

1. **YIN Pitch Estimation Accuracy (`test_m2_yin.m`):**
   - Pure sine waves at $100, 220, 440, 880\text{ Hz}$: median pitch error **$< 0.05\text{ cents}$** (well below the $5\text{-cent}$ threshold) with $100\%$ voiced frame detection.
   - Linear frequency chirp ($200\text{ Hz} \to 400\text{ Hz}$ over $1\text{ s}$): median tracking error $< 8\text{ cents}$.
   - Harmonic-rich synthetic vocals: **$0\%$ gross octave errors**; processes $10\text{ seconds}$ of audio at $44.1\text{ kHz}$ in **$1.4\text{ seconds}$** ($>7\times$ faster than real-time).
2. **Preprocessing, Denoising & Filtering (`test_m8_audit_dsp.m`):**
   - Stationary background noise tested at $8, 15, \text{ and } 22\text{ dB}$ input SNR: achieves **$+4\text{ to } +9\text{ dB}$ SNR improvement** in quiet segments while preserving $< 5\text{-cent}$ YIN pitch tracking accuracy.
   - Zero-phase vocal filter attenuates $20\text{ Hz}$ sub-bass rumble by **$> 30\text{ dB}$** and $14\text{ kHz}$ hiss by **$> 12\text{ dB}$** with **$< 0.05\text{ dB}$** passband ripple at $220\text{ Hz}$.
3. **TD-PSOLA & End-to-End Pitch Correction (`test_m4_psola.m`, `test_m5_pipeline.m`, `demo_autotune.m`):**
   - Identity pitch shift ($R = 1.0$) achieves **$\infty\text{ dB}$ SNR** (bit-exact reconstruction).
   - $\pm 1\text{ and } \pm 3\text{ semitone}$ shifts on multi-formant vocals achieve **$< 3.5\text{ cents}$** output pitch error with exact sample-length preservation (`numel(y) == numel(x)`).
   - On the 4-note detuned & vibrato-modulated vocal phrase in `demo_autotune.m` ($\text{C4 – E4 – G4 – A4}$ with $-35, +25, -40, +20\text{ cent}$ detuning, $18\text{-cent}$ vibrato, and additive room hiss), the pipeline reduces mean pitch error from **$29.23\text{ cents} \to 2.50\text{ cents}$** (**$91.4\%$ error reduction**).
