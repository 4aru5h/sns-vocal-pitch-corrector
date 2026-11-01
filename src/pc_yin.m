function yin = pc_yin(x, fs, cfg)
%PC_YIN Fundamental frequency (f0) estimator using the YIN algorithm.
%   yin = PC_YIN(x, fs, cfg) implements the 6-step YIN pitch tracking
%   algorithm (de Cheveigne & Kawahara, 2002) using unbiased mean-square
%   difference functions, cumulative mean normalization, harmonic-dip
%   verification, parabolic refinement on d(tau), and median smoothing.

    arguments
        x (:,1) double {mustBeReal, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        cfg struct = pc_default_config()
    end

    % Resolve parameters from nested cfg.yin or flat cfg fields
    f0Min = get_yin_param(cfg, 'f0Min', 'fmin', 80);
    f0Max = get_yin_param(cfg, 'f0Max', 'fmax', 1000);
    yinThreshold = get_yin_param(cfg, 'yinThreshold', 'threshold', 0.15);
    frameMs = get_yin_param(cfg, 'yinFrameMs', 'frameMs', 40);
    hopMs   = get_yin_param(cfg, 'yinHopMs', 'hopMs', 5);
    rmsGate = get_yin_param(cfg, 'voicedRmsGate', 'rmsGate', 0.015);
    maxAper = get_yin_param(cfg, 'voicedMaxAperiodicity', 'maxAperiodicity', 0.45);
    medFrames = get_yin_param(cfg, 'medianFilterFrames', 'medianFilterFrames', 5);

    W = max(32, round(frameMs * 1e-3 * fs));
    H = max(8,  round(hopMs * 1e-3 * fs));
    tauMin = max(2, floor(fs / f0Max));
    tauMax = min(W - 3, ceil(fs / f0Min));

    N = size(x, 1);
    if N < W || tauMax <= tauMin
        yin = struct('f0', NaN(0,1), 'voiced', false(0,1), ...
                     'aperiodicity', ones(0,1), 'rms', zeros(0,1), ...
                     't', zeros(0,1), 'tFrames', zeros(0,1), ...
                     'hopSamples', H, 'frameSamples', W);
        return;
    end

    numFrames = floor((N - W) / H) + 1;

    f0           = NaN(numFrames, 1);
    voiced       = false(numFrames, 1);
    aperiodicity = ones(numFrames, 1);
    rmsVal       = zeros(numFrames, 1);
    tFrames      = ((0:numFrames-1)' * H + W/2) / fs;

    globalRms = sqrt(mean(x.^2));
    if globalRms < 1e-9
        yin = struct('f0', f0, 'voiced', voiced, ...
                     'aperiodicity', aperiodicity, 'rms', rmsVal, ...
                     't', tFrames, 'tFrames', tFrames, ...
                     'hopSamples', H, 'frameSamples', W);
        return;
    end

    Nfft = 2^nextpow2(2 * W);
    taus = (1:tauMax)';
    overlapCounts = max(1, W - taus);

    for m = 1:numFrames
        idx = (m - 1) * H + (1:W);
        frame = x(idx);

        rmsVal(m) = sqrt(mean(frame.^2));
        if rmsVal(m) < rmsGate * globalRms
            continue;
        end

        % Step 1 & 2: Unbiased Mean-Square Difference Function d(tau) via FFT
        % Normalizing by (W - tau) eliminates window-shrinkage lag bias.
        X = fft(frame, Nfft);
        r = real(ifft(abs(X).^2));
        r = r(1:tauMax+1);

        frameSq = frame.^2;
        cumSq = [0; cumsum(frameSq)];

        E_head = cumSq(W - taus + 1);
        E_tail = cumSq(W + 1) - cumSq(taus + 1);
        d = max(0, (E_head + E_tail - 2 * r(2:tauMax+1)) ./ overlapCounts);

        % Step 3: Cumulative Mean Normalized Difference Function d'(tau)
        cumD = cumsum(d);
        d_prime_lags = d ./ (cumD ./ taus);
        d_prime_lags(isnan(d_prime_lags) | isinf(d_prime_lags)) = 1;
        d_prime = [1; d_prime_lags]; % index k corresponds to lag tau = k - 1
        d_full  = [0; d];            % unnormalized unbiased d(tau) for parabolic fit

        % Step 4: Absolute Threshold Search in [tauMin, tauMax]
        idxMin = tauMin + 1;
        idxMax = tauMax + 1;

        tau_idx = -1;
        t = idxMin;
        while t <= idxMax
            if d_prime(t) < yinThreshold
                while (t + 1 <= idxMax) && (d_prime(t + 1) < d_prime(t))
                    t = t + 1;
                end
                tau_idx = t;
                break;
            end
            t = t + 1;
        end

        if tau_idx == -1
            [minVal, relIdx] = min(d_prime(idxMin:idxMax));
            tau_idx = idxMin + relIdx - 1;
            min_d_prime = minVal;
        else
            min_d_prime = d_prime(tau_idx);
        end

        % Subharmonic / 2nd-harmonic octave-up guard
        tauLag = tau_idx - 1;
        doubleLagMin = round(1.92 * tauLag) + 1;
        doubleLagMax = min(idxMax, round(2.08 * tauLag) + 1);
        if min_d_prime > 0.06 && doubleLagMin <= doubleLagMax
            [subMinVal, subRelIdx] = min(d_prime(doubleLagMin:doubleLagMax));
            if subMinVal < 0.45 * min_d_prime
                tau_idx = doubleLagMin + subRelIdx - 1;
                min_d_prime = subMinVal;
            end
        end

        aperiodicity(m) = max(0, min(1, min_d_prime));

        if aperiodicity(m) >= maxAper
            continue;
        end

        % Step 5: Parabolic Interpolation on d_full(tau) around tau_idx
        % (de Cheveigne & Kawahara 2002 Sec II.E: refine on d(tau) to avoid
        % cumulative mean normalization slope bias)
        if tau_idx > 2 && tau_idx < length(d_full)
            y1 = d_full(tau_idx - 1);
            y2 = d_full(tau_idx);
            y3 = d_full(tau_idx + 1);
            denom = 2 * (y1 - 2 * y2 + y3);
            if abs(denom) > 1e-12
                delta = max(-0.5, min(0.5, (y1 - y3) / denom));
            else
                delta = 0;
            end
        else
            delta = 0;
        end

        tau_est = (tau_idx - 1) + delta;
        f0_est  = fs / tau_est;

        if f0_est >= f0Min && f0_est <= f0Max
            f0(m) = f0_est;
            voiced(m) = true;
        end
    end

    % Step 6: Post-processing median filter over contiguous voiced segments
    if medFrames > 1
        d_start = find(diff([false; voiced; false]) == 1);
        d_end   = find(diff([false; voiced; false]) == -1) - 1;

        for k = 1:length(d_start)
            seg_idx = d_start(k):d_end(k);
            if numel(seg_idx) >= 3
                f0(seg_idx) = movmedian(f0(seg_idx), medFrames);
            end
        end
    end

    yin = struct( ...
        'f0',           f0, ...
        'voiced',       voiced, ...
        'aperiodicity', aperiodicity, ...
        'rms',          rmsVal, ...
        't',            tFrames, ...
        'tFrames',      tFrames, ...
        'hopSamples',   H, ...
        'frameSamples', W);
end

function val = get_yin_param(cfg, flatName, nestedName, defaultVal)
    if isfield(cfg, flatName)
        val = cfg.(flatName);
    elseif isfield(cfg, 'yin') && isstruct(cfg.yin) && isfield(cfg.yin, nestedName)
        val = cfg.yin.(nestedName);
    else
        val = defaultVal;
    end
end
