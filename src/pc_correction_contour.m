function contour = pc_correction_contour(yin, cfg)
%PC_CORRECTION_CONTOUR Compute target pitch & smoothed correction contour.
%   contour = PC_CORRECTION_CONTOUR(yin, cfg) maps detected f0 values to the
%   selected musical scale with boundary hysteresis (preventing note chatter)
%   and smooths the target pitch trajectory via a first-order IIR filter
%   controlled by cfg.retuneMs.

    arguments
        yin struct
        cfg struct = pc_default_config()
    end

    numFrames = numel(yin.f0);
    voiced    = logical(yin.voiced(:));
    f0        = yin.f0(:);

    if isfield(yin, 'tFrames')
        tFrames = yin.tFrames(:);
    elseif isfield(yin, 't')
        tFrames = yin.t(:);
    else
        hopMs = 5;
        if isfield(cfg, 'yinHopMs'), hopMs = cfg.yinHopMs; end
        tFrames = (0:numFrames-1)' * (hopMs * 1e-3);
    end

    midiDet    = NaN(numFrames, 1);
    midiTarget = NaN(numFrames, 1);
    midiOut    = NaN(numFrames, 1);
    shiftSemis = zeros(numFrames, 1);
    pitchRatio = ones(numFrames, 1);
    f0Target   = NaN(numFrames, 1);
    f0Corr     = NaN(numFrames, 1);
    centsIn    = NaN(numFrames, 1);
    centsOut   = NaN(numFrames, 1);

    scalePcs = pc_scale_pcs(cfg.key, cfg.scale);
    hyst = 0.0;
    if isfield(cfg, 'hysteresisSemis')
        hyst = max(0, cfg.hysteresisSemis);
    end
    maxShift = 12.0;
    if isfield(cfg, 'maxShiftSemis')
        maxShift = max(0, cfg.maxShiftSemis);
    end
    minRatio = 0.5;
    if isfield(cfg, 'minPitchRatio'), minRatio = cfg.minPitchRatio; end
    maxRatio = 2.0;
    if isfield(cfg, 'maxPitchRatio'), maxRatio = cfg.maxPitchRatio; end

    if any(voiced)
        midiDet(voiced)    = pc_hz2midi(f0(voiced));
        midiTarget(voiced) = pc_snap_to_scale(midiDet(voiced), scalePcs);

        % Apply scale-boundary hysteresis within contiguous voiced runs
        % so hovering near a midpoint between two scale notes does not chatter
        if hyst > 0
            for i = 2:numFrames
                if voiced(i) && voiced(i-1)
                    prevTarget = midiTarget(i-1);
                    currTarget = midiTarget(i);
                    if currTarget ~= prevTarget
                        distPrev = abs(midiDet(i) - prevTarget);
                        distCurr = abs(midiDet(i) - currTarget);
                        if distPrev <= distCurr + hyst
                            midiTarget(i) = prevTarget;
                        end
                    end
                end
            end
        end

        f0Target(voiced) = pc_midi2hz(midiTarget(voiced));
        centsIn(voiced)  = 100 * (midiDet(voiced) - midiTarget(voiced));
    end

    % Determine frame hop dt (seconds)
    if numel(tFrames) >= 2
        dt = median(diff(tFrames));
    elseif isfield(cfg, 'yinHopMs')
        dt = cfg.yinHopMs * 1e-3;
    else
        dt = 0.005;
    end

    if cfg.retuneMs <= 0
        beta = 0; % Instantaneous snap (alpha = 1)
    else
        tau  = cfg.retuneMs * 1e-3;
        beta = exp(-dt / tau);
    end

    p_prev = NaN;
    for i = 1:numFrames
        if voiced(i)
            % Clamp target pitch excursion by maxShiftSemis relative to midiDet
            clampedTarget = midiDet(i) + min(max(midiTarget(i) - midiDet(i), -maxShift), maxShift);

            % Onset of voiced run starts from initial detected pitch midiDet(i)
            % and converges exponentially toward clampedTarget with time constant tau.
            % On frame k of a run with constant target T, p_curr - midiDet = (1 - beta^k)*(T - midiDet),
            % while on sustained vocal notes p_curr locks onto T and cancels vibrato/drift!
            if i == 1 || ~voiced(i-1) || isnan(p_prev)
                p_prev = midiDet(i);
            end
            p_curr = beta * p_prev + (1 - beta) * clampedTarget;
            p_prev = p_curr;

            s_curr = cfg.strength * (p_curr - midiDet(i));
            s_curr = min(max(s_curr, -maxShift), maxShift);
            shiftSemis(i) = s_curr;

            r = 2^(s_curr / 12);
            r = min(max(r, minRatio), maxRatio);
            pitchRatio(i) = r;

            midiOut(i)  = midiDet(i) + s_curr;
            f0Corr(i)   = f0(i) * r;
            centsOut(i) = 100 * (midiOut(i) - midiTarget(i));
        else
            p_prev = NaN;
            shiftSemis(i) = 0;
            pitchRatio(i) = 1.0;
        end
    end

    contour = struct( ...
        'midiDet',    midiDet, ...
        'midiTarget', midiTarget, ...
        'midiOut',    midiOut, ...
        'f0Target',   f0Target, ...
        'f0Corr',     f0Corr, ...
        'shiftSemis', shiftSemis, ...
        'ratio',      pitchRatio, ...
        'pitchRatio', pitchRatio, ...
        'centsDev',   centsIn, ...
        'centsIn',    centsIn, ...
        'centsOut',   centsOut, ...
        'voiced',     voiced, ...
        't',          tFrames, ...
        'tFrames',    tFrames);
end
