function y = pc_vocal_filter(x, fs, cfg)
%PC_VOCAL_FILTER Zero-phase Butterworth high-pass and low-pass vocal conditioning.
%   y = PC_VOCAL_FILTER(x, fs, cfg) removes sub-vocal rumble/plosives below
%   highPassHz (default 55 Hz) and ultrasonic/hiss components above
%   lowPassHz (default 10000 Hz) using analytical bilinear-transform 2nd-order
%   Butterworth sections applied forward-backward (zero phase, Base MATLAB).

    arguments
        x (:,1) double {mustBeReal, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        cfg struct = struct()
    end

    if ~isfield(cfg, 'highPassHz'), cfg.highPassHz = 55; end
    if ~isfield(cfg, 'lowPassHz'),  cfg.lowPassHz  = 10000; end
    if ~isfield(cfg, 'enableHighPass'), cfg.enableHighPass = true; end
    if ~isfield(cfg, 'enableLowPass'),  cfg.enableLowPass  = true; end

    N = numel(x);
    if N < 16
        y = x;
        return;
    end

    y = x;
    nyq = 0.5 * fs;

    % 1. High-pass filter (removes rumble, mic stand thumps, DC drift < 55 Hz)
    if cfg.enableHighPass && cfg.highPassHz > 5 && cfg.highPassHz < 0.85 * nyq
        [bHP, aHP] = butter2_highpass(cfg.highPassHz, fs);
        padLen = min(floor((N - 1) / 2), max(64, ceil(2.5 * fs / cfg.highPassHz)));
        y = zero_phase_iir(y, bHP, aHP, padLen);
    end

    % 2. Low-pass filter (removes high-frequency hiss while keeping harmonics <= 10 kHz)
    lpCutoff = min(cfg.lowPassHz, 0.88 * nyq);
    if cfg.enableLowPass && lpCutoff > 1500 && lpCutoff < 0.92 * nyq
        [bLP, aLP] = butter2_lowpass(lpCutoff, fs);
        padLen = min(floor((N - 1) / 2), max(32, ceil(4.0 * fs / lpCutoff)));
        y = zero_phase_iir(y, bLP, aLP, padLen);
    end
end

function [b, a] = butter2_highpass(fc, fs)
    K = tan(pi * fc / fs);
    K2 = K * K;
    sqrt2K = sqrt(2) * K;
    normFactor = 1.0 / (1.0 + sqrt2K + K2);
    b0 = normFactor;
    b1 = -2.0 * b0;
    b2 = b0;
    a1 = 2.0 * (K2 - 1.0) * normFactor;
    a2 = (1.0 - sqrt2K + K2) * normFactor;
    b = [b0, b1, b2];
    a = [1.0, a1, a2];
end

function [b, a] = butter2_lowpass(fc, fs)
    K = tan(pi * fc / fs);
    K2 = K * K;
    sqrt2K = sqrt(2) * K;
    normFactor = 1.0 / (1.0 + sqrt2K + K2);
    b0 = K2 * normFactor;
    b1 = 2.0 * b0;
    b2 = b0;
    a1 = 2.0 * (K2 - 1.0) * normFactor;
    a2 = (1.0 - sqrt2K + K2) * normFactor;
    b = [b0, b1, b2];
    a = [1.0, a1, a2];
end

function y = zero_phase_iir(x, b, a, padLen)
    if padLen < 1
        y = filter(b, a, x);
        return;
    end
    % Odd-symmetric reflection padding to minimize boundary transients
    pre  = 2 * x(1) - x(padLen + 1 : -1 : 2);
    post = 2 * x(end) - x(end - 1 : -1 : end - padLen);
    xPad = [pre; x; post];

    % Forward-backward pass (zero phase distortion)
    yPad = filter(b, a, xPad);
    yPad = flipud(filter(b, a, flipud(yPad)));

    y = yPad(padLen + 1 : padLen + numel(x));
end
