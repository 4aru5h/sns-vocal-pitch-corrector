function [x, info] = pc_preprocess(xIn, fs, cfg)
%PC_PREPROCESS Condition, denoise, and filter input audio before pitch detection.
%   [x, info] = PC_PREPROCESS(xIn, fs, cfg) executes the preprocessing stages:
%     1. Input validation (fs >= 8000 Hz, duration >= 0.1 s, finite real)
%     2. Stereo-to-mono downmix & DC offset removal
%     3. Digital silence & idle ADC noise detection
%     4. Stationary spectral noise reduction (pc_denoise)
%     5. Zero-phase Butterworth vocal conditioning (pc_vocal_filter)
%     6. Final zero-mean enforcement & peak normalization to 0.95 (-0.45 dBFS)

    arguments
        xIn {mustBeNumeric, mustBeReal}
        fs (1,1) double {mustBePositive, mustBeFinite}
        cfg struct = struct()
    end

    if isempty(xIn)
        error('pc_preprocess:emptyInput', 'Input audio array cannot be empty.');
    end
    if any(~isfinite(xIn(:)))
        error('pc_preprocess:nonFiniteInput', 'Input audio contains NaN or Inf values.');
    end
    if fs < 8000
        error('pc_preprocess:invalidFs', 'Sampling rate fs must be at least 8000 Hz (got %.1f Hz).', fs);
    end

    % Populate defaults if cfg fields are omitted
    if ~isfield(cfg, 'denoiseEnable'),        cfg.denoiseEnable        = true;  end
    if ~isfield(cfg, 'denoiseStrength'),      cfg.denoiseStrength      = 1.0;   end
    if ~isfield(cfg, 'vocalFilterEnable'),    cfg.vocalFilterEnable    = true;  end
    if ~isfield(cfg, 'highPassHz'),           cfg.highPassHz           = 55;    end
    if ~isfield(cfg, 'lowPassHz'),            cfg.lowPassHz            = 16000; end
    if ~isfield(cfg, 'silencePeakThreshold'), cfg.silencePeakThreshold = 1e-4;  end

    x = double(xIn);

    % Ensure column orientation (samples along dim 1, channels along dim 2)
    if isrow(x) && size(x, 1) == 1 && size(x, 2) > 1
        x = x(:);
        origChannels = 1;
    else
        origChannels = size(x, 2);
        if origChannels > 1
            x = mean(x, 2);
        end
    end

    numSamples = size(x, 1);
    if numSamples < round(0.1 * fs)
        error('pc_preprocess:tooShort', ...
              'Input audio duration (%.4f s) must be at least 0.1 s.', numSamples / fs);
    end

    % 1. Remove DC offset
    dcOffset = mean(x);
    x = x - dcOffset;

    % 2. Silence & idle ADC quantization noise gate
    rawPeak = max(abs(x));
    if rawPeak < cfg.silencePeakThreshold
        x = zeros(numSamples, 1);
        info = struct( ...
            'fs',                 fs, ...
            'channels',           origChannels, ...
            'dcOffset',           dcOffset, ...
            'rawPeak',            rawPeak, ...
            'gain',               1.0, ...
            'silent',             true, ...
            'duration',           numSamples / fs, ...
            'denoiseApplied',     false, ...
            'vocalFilterApplied', false, ...
            'noiseFloorDb',       -120, ...
            'estimatedSnrDb',     0, ...
            'snrImproveDb',       0, ...
            'xRaw',               x);
        return;
    end

    % 3. Initial conditioning normalization (for consistent Reference Raw playback)
    targetPeak = 0.95;
    initialGain = min(targetPeak / rawPeak, 500.0);
    xRaw = x * initialGain;
    xRaw = enforce_zero_mean_and_peak(xRaw, targetPeak);

    xClean = xRaw;

    % 4. Stationary background noise reduction
    denoiseInfo = struct('applied', false, 'noiseFloorDb', -100, ...
                         'estimatedSnrDb', 100, 'snrImproveDb', 0);
    if cfg.denoiseEnable && cfg.denoiseStrength > 0
        [xClean, denoiseInfo] = pc_denoise(xClean, fs, cfg);
    end

    % 5. Vocal bandpass conditioning (high-pass rumble filter + ultrasonic filter)
    vocalFilterApplied = false;
    if cfg.vocalFilterEnable
        vfCfg = struct('enableHighPass', true, 'enableLowPass', true, ...
                       'highPassHz', cfg.highPassHz, 'lowPassHz', cfg.lowPassHz);
        xClean = pc_vocal_filter(xClean, fs, vfCfg);
        vocalFilterApplied = true;
    end

    % 6. Final zero-mean enforcement and exact 0.95 peak normalization
    cleanPeak = max(abs(xClean - mean(xClean)));
    if cleanPeak < cfg.silencePeakThreshold
        x = zeros(numSamples, 1);
        info = struct( ...
            'fs',                 fs, ...
            'channels',           origChannels, ...
            'dcOffset',           dcOffset, ...
            'rawPeak',            rawPeak, ...
            'gain',               1.0, ...
            'silent',             true, ...
            'duration',           numSamples / fs, ...
            'denoiseApplied',     denoiseInfo.applied, ...
            'vocalFilterApplied', vocalFilterApplied, ...
            'noiseFloorDb',       denoiseInfo.noiseFloorDb, ...
            'estimatedSnrDb',     denoiseInfo.estimatedSnrDb, ...
            'snrImproveDb',       denoiseInfo.snrImproveDb, ...
            'xRaw',               xRaw);
        return;
    end

    x = enforce_zero_mean_and_peak(xClean, targetPeak);
    effectiveGain = targetPeak / rawPeak;

    info = struct( ...
        'fs',                 fs, ...
        'channels',           origChannels, ...
        'dcOffset',           dcOffset, ...
        'rawPeak',            rawPeak, ...
        'gain',               effectiveGain, ...
        'silent',             false, ...
        'duration',           numSamples / fs, ...
        'denoiseApplied',     denoiseInfo.applied, ...
        'vocalFilterApplied', vocalFilterApplied, ...
        'noiseFloorDb',       denoiseInfo.noiseFloorDb, ...
        'estimatedSnrDb',     denoiseInfo.estimatedSnrDb, ...
        'snrImproveDb',       denoiseInfo.snrImproveDb, ...
        'xRaw',               xRaw);
end

function y = enforce_zero_mean_and_peak(x, targetPeak)
    y = x - mean(x);
    pk = max(abs(y));
    if pk > 0
        y = y * (targetPeak / pk);
    end
    % Second pass ensures mean(y) == 0 and max(abs(y)) == targetPeak to < 1e-15
    y = y - mean(y);
    pk2 = max(abs(y));
    if pk2 > 0
        y = y * (targetPeak / pk2);
    end
end
