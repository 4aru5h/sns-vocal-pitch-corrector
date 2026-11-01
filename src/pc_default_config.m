function cfg = pc_default_config()
%PC_DEFAULT_CONFIG Return master DSP configuration struct.
%   cfg = PC_DEFAULT_CONFIG() returns a struct containing all default
%   parameters for preprocessing, noise reduction, vocal conditioning,
%   YIN pitch detection, scale mapping, and TD-PSOLA pitch correction.

    cfg = struct();
    cfg.fs                    = 44100;
    cfg.key                   = 'C';
    cfg.scale                 = 'major';
    cfg.strength              = 1.0;        % [0, 1]
    cfg.retuneMs              = 0;          % [0, 200] ms
    cfg.maxShiftSemis         = 12.0;       % max pitch shift in semitones

    % Preprocessing, Noise Reduction & Vocal Conditioning
    cfg.denoiseEnable         = true;       % Stationary spectral noise reduction
    cfg.denoiseStrength       = 1.0;        % [0, 2] oversubtraction strength
    cfg.vocalFilterEnable     = true;       % Zero-phase Butterworth HPF + LPF
    cfg.highPassHz            = 55;         % Sub-vocal rumble cutoff (Hz)
    cfg.lowPassHz             = 10000;      % High-frequency hiss cutoff (Hz)
    cfg.silencePeakThreshold  = 1e-4;       % Digital silence / idle ADC gate (-80 dBFS)

    % YIN Pitch Detector parameters (both nested and flat for compatibility)
    cfg.f0Min                 = 80;         % Hz (~E2)
    cfg.f0Max                 = 1000;       % Hz (~B5)
    cfg.yinThreshold          = 0.15;       % CMNDF dip threshold
    cfg.yinFrameMs            = 40;         % analysis window (ms)
    cfg.yinHopMs              = 5;          % hop size (ms)
    cfg.voicedRmsGate         = 0.015;      % relative to signal RMS
    cfg.voicedMaxAperiodicity = 0.45;       % reject frames with d'(tau) > this
    cfg.medianFilterFrames    = 5;          % post-YIN median smoothing (odd)

    cfg.yin = struct( ...
        'fmin',                  cfg.f0Min, ...
        'fmax',                  cfg.f0Max, ...
        'threshold',             cfg.yinThreshold, ...
        'frameMs',               cfg.yinFrameMs, ...
        'hopMs',                 cfg.yinHopMs, ...
        'rmsGate',               cfg.voicedRmsGate, ...
        'maxAperiodicity',       cfg.voicedMaxAperiodicity, ...
        'medianFilterFrames',    cfg.medianFilterFrames);

    % Scale Mapping & Contour Smoothing
    cfg.hysteresisSemis       = 0.15;       % 15-cent deadband to prevent note chatter

    % TD-PSOLA Resynthesis parameters
    cfg.maxPitchRatio         = 2.0;        % clamp synthesis ratio
    cfg.minPitchRatio         = 0.5;
    cfg.unvoicedPeriodMs      = 10;         % 100 Hz default mark spacing
    cfg.psola = struct( ...
        'refineMarks',           true, ...
        'maxPitchRatio',         cfg.maxPitchRatio, ...
        'minPitchRatio',         cfg.minPitchRatio, ...
        'unvoicedPeriodMs',      cfg.unvoicedPeriodMs);
end
