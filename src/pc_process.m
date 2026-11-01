function res = pc_process(xIn, fs, cfg)
%PC_PROCESS Top-level end-to-end vocal pitch correction pipeline.
%   res = PC_PROCESS(xIn, fs, cfg) executes the complete processing pipeline:
%     1. Input Validation & Audio Conditioning
%     2. Stationary Spectral Noise Reduction
%     3. Vocal Bandpass Conditioning
%     4. YIN Fundamental Frequency Detection
%     5. Musical Scale Mapping & Hysteresis Contour Calculation
%     6. TD-PSOLA Pitch Correction & Output Smoothing

    arguments
        xIn {mustBeNumeric, mustBeReal}
        fs (1,1) double {mustBePositive, mustBeFinite}
        cfg struct = pc_default_config()
    end

    cfg.fs = fs;

    % Stages 1-3: Input Validation, Conditioning, Noise Reduction & Vocal Filter
    [x, info] = pc_preprocess(xIn, fs, cfg);

    if info.silent
        H = round(cfg.yinHopMs * 1e-3 * fs);
        W = round(cfg.yinFrameMs * 1e-3 * fs);
        yin = struct('f0', NaN(0,1), 'voiced', false(0,1), ...
                     'aperiodicity', ones(0,1), 'rms', zeros(0,1), ...
                     't', zeros(0,1), 'tFrames', zeros(0,1), ...
                     'hopSamples', H, 'frameSamples', W);
        contour  = pc_correction_contour(yin, cfg);
        y        = x;
        pitchOut = yin;
    else
        % Stage 4: Pitch Detection (YIN)
        yin = pc_yin(x, fs, cfg);

        % Stage 5: Musical Note Mapping & Pitch Correction Contour
        contour = pc_correction_contour(yin, cfg);

        % Stage 6: Time-Domain PSOLA Resynthesis & Output Smoothing
        y = pc_psola(x, fs, yin, contour, cfg);

        % Stage 7: Output Pitch Verification (YIN on resynthesized signal)
        pitchOut = pc_yin(y, fs, cfg);
    end

    tSamples = (0:size(x, 1)-1)' / fs;

    % Compute summary telemetry metrics for UI & diagnostics
    metrics = compute_summary_metrics(yin, pitchOut, contour, info, cfg);

    res = struct( ...
        'xRaw',     info.xRaw, ...
        'x',        x, ...
        'y',        y, ...
        'fs',       fs, ...
        'cfg',      cfg, ...
        'info',     info, ...
        'yin',      yin, ...
        'pitch',    yin, ...
        'pitchOut', pitchOut, ...
        'contour',  contour, ...
        'metrics',  metrics, ...
        'tSamples', tSamples);
end

function m = compute_summary_metrics(yin, pitchOut, contour, info, cfg)
    m = struct( ...
        'voicedRatio',     0, ...
        'medianF0In',      NaN, ...
        'medianF0Target',  NaN, ...
        'medianF0Out',     NaN, ...
        'detectedNote',    '--', ...
        'targetNote',      '--', ...
        'meanAbsCentsIn',  NaN, ...
        'meanAbsCentsOut', NaN, ...
        'snrImproveDb',    info.snrImproveDb, ...
        'noiseFloorDb',    info.noiseFloorDb);

    if isempty(yin.f0) || ~any(contour.voiced)
        return;
    end

    v = contour.voiced;
    m.voicedRatio     = mean(double(v));
    m.medianF0In      = median(yin.f0(v), 'omitnan');
    m.medianF0Target  = median(contour.f0Target(v), 'omitnan');
    m.meanAbsCentsIn  = mean(abs(contour.centsIn(v)), 'omitnan');

    if ~isempty(pitchOut.f0) && any(pitchOut.voiced)
        vOut = pitchOut.voiced;
        m.medianF0Out = median(pitchOut.f0(vOut), 'omitnan');
        outContour = pc_correction_contour(pitchOut, cfg);
        m.meanAbsCentsOut = mean(abs(outContour.centsIn(vOut)), 'omitnan');
    else
        m.medianF0Out     = median(contour.f0Corr(v), 'omitnan');
        m.meanAbsCentsOut = mean(abs(contour.centsOut(v)), 'omitnan');
    end

    if isfinite(m.medianF0In) && m.medianF0In > 0
        midiIn = round(pc_hz2midi(m.medianF0In));
        namesIn = pc_midi2name(midiIn);
        m.detectedNote = char(namesIn(1));
    end
    if isfinite(m.medianF0Target) && m.medianF0Target > 0
        midiTgt = round(pc_hz2midi(m.medianF0Target));
        namesTgt = pc_midi2name(midiTgt);
        m.targetNote = char(namesTgt(1));
    end
end
