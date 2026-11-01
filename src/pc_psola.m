function y = pc_psola(x, fs, yin, ratioOrContour, cfg)
%PC_PSOLA Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA) resynthesis.
%   y = PC_PSOLA(x, fs, yin, ratioOrContour, cfg) shifts the vocal pitch
%   according to ratioOrContour (which may be a contour struct, a scalar
%   pitch ratio, or a per-frame ratio vector) while preserving formants
%   and exact signal duration.

    arguments
        x (:,1) double {mustBeReal, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        yin struct
        ratioOrContour
        cfg struct = pc_default_config()
    end

    N = size(x, 1);
    if N == 0 || isempty(yin.f0)
        y = x;
        return;
    end

    numFrames = numel(yin.f0);
    f0 = yin.f0(:);

    if isfield(yin, 'tFrames')
        t_frames = yin.tFrames(:);
    elseif isfield(yin, 't')
        t_frames = yin.t(:);
    else
        t_frames = ((0:numFrames-1)' * 0.005);
    end

    if isstruct(ratioOrContour)
        voiced = logical(ratioOrContour.voiced(:));
        if isfield(ratioOrContour, 'pitchRatio')
            ratio = ratioOrContour.pitchRatio(:);
        else
            ratio = ratioOrContour.ratio(:);
        end
    elseif isnumeric(ratioOrContour)
        voiced = logical(yin.voiced(:));
        if isscalar(ratioOrContour)
            ratio = repmat(double(ratioOrContour), numFrames, 1);
        else
            ratio = double(ratioOrContour(:));
        end
    else
        error('pc_psola:invalidRatioInput', 'Fourth argument must be a contour struct or numeric ratio.');
    end

    if ~any(voiced)
        y = x;
        return;
    end

    % Identity shortcut: bit-accurate reconstruction when pitchRatio == 1.0
    isIdentity = all(abs(ratio(voiced) - 1.0) < 1e-6);
    if isIdentity
        y = x;
        return;
    end

    f0Min = 80;  if isfield(cfg, 'f0Min'), f0Min = cfg.f0Min; end
    f0Max = 1000; if isfield(cfg, 'f0Max'), f0Max = cfg.f0Max; end
    minRatio = 0.5; if isfield(cfg, 'minPitchRatio'), minRatio = cfg.minPitchRatio; end
    maxRatio = 2.0; if isfield(cfg, 'maxPitchRatio'), maxRatio = cfg.maxPitchRatio; end

    Pmin = max(2, floor(fs / f0Max));
    Pmax = ceil(fs / f0Min);

    t_samples = ((0:N-1)' + 0.5) / fs;

    % Fill unvoiced frames from nearest voiced frame so voiced/unvoiced
    % boundaries do not chirp from dummy unvoiced period or ratio 1.0
    voicedIdx = find(voiced);
    if numFrames == 1 || numel(voicedIdx) == 1
        vIdx = voicedIdx(1);
        P_samples         = repmat(fs / f0(vIdx), N, 1);
        ratio_samples     = repmat(ratio(vIdx), N, 1);
        is_voiced_samples = repmat(voiced(1), N, 1);
    else
        P_voiced_frames     = interp1(t_frames(voicedIdx), fs ./ f0(voicedIdx), t_frames, 'nearest', 'extrap');
        ratio_voiced_frames = interp1(t_frames(voicedIdx), ratio(voicedIdx), t_frames, 'nearest', 'extrap');

        P_samples         = interp1(t_frames, P_voiced_frames, t_samples, 'linear', 'extrap');
        ratio_samples     = interp1(t_frames, ratio_voiced_frames, t_samples, 'linear', 'extrap');
        is_voiced_samples = interp1(t_frames, double(voiced), t_samples, 'nearest', 'extrap') > 0.5;
    end

    P_samples     = min(max(P_samples, Pmin), Pmax);
    ratio_samples = min(max(ratio_samples, minRatio), maxRatio);

    % Fundamental-isolated signal x_f0 for jitter-free glottal peak placement
    maxVoicedF0 = max(f0(voiced));
    f0LpCutoff  = min(0.42 * fs, max(150, 1.38 * maxVoicedF0));
    x_f0 = pc_vocal_filter(x, fs, struct('enableHighPass', false, ...
                                         'enableLowPass', true, ...
                                         'lowPassHz', f0LpCutoff));

    % Step 1: Place Analysis Pitch Marks (ta) locked to fundamental peaks
    maxMarks = ceil(N / max(1, Pmin)) * 2 + 100;
    ta = zeros(maxMarks, 1);
    numTa = 0;

    curr_pos = 1;
    while curr_pos <= N
        idx_curr = min(max(round(curr_pos), 1), N);
        P_curr   = P_samples(idx_curr);

        if is_voiced_samples(idx_curr)
            delta = round(0.20 * P_curr);
            search_min = max(1, idx_curr - delta);
            search_max = min(N, idx_curr + delta);
            [~, max_rel] = max(x_f0(search_min:search_max));
            refined_ta = search_min + max_rel - 1;
        else
            refined_ta = idx_curr;
        end

        if numTa > 0 && refined_ta <= ta(numTa)
            refined_ta = min(N, ta(numTa) + max(1, round(0.5 * P_curr)));
        end

        numTa = numTa + 1;
        ta(numTa) = refined_ta;

        next_pos = refined_ta + P_curr;
        if next_pos <= curr_pos
            curr_pos = curr_pos + max(1, round(P_curr));
        else
            curr_pos = next_pos;
        end
    end
    ta = ta(1:numTa);

    if numTa < 2
        y = x;
        return;
    end

    % Step 2: Place Synthesis Pitch Marks (ts)
    maxSynMarks = ceil(maxMarks * maxRatio) + 100;
    ts = zeros(maxSynMarks, 1);
    numTs = 0;

    curr_ts = ta(1);
    while curr_ts <= N
        numTs = numTs + 1;
        ts(numTs) = curr_ts;

        idx_curr = min(max(round(curr_ts), 1), N);
        P_curr   = P_samples(idx_curr);
        r_curr   = ratio_samples(idx_curr);

        if is_voiced_samples(idx_curr)
            P_syn = P_curr / r_curr;
        else
            P_syn = P_curr;
        end

        curr_ts = curr_ts + max(1, P_syn);
    end
    ts = ts(1:numTs);

    % Step 3: Windowed Overlap-Add (WOLA) using full-bandwidth signal x
    y_psola = zeros(N, 1);
    w_sum   = zeros(N, 1);

    m_idx = 1;
    for k = 1:numTs
        tk = ts(k);

        while (m_idx < numTa) && (abs(ta(m_idx + 1) - tk) <= abs(ta(m_idx) - tk))
            m_idx = m_idx + 1;
        end

        tm  = ta(m_idx);
        P_a = P_samples(min(max(round(tm), 1), N));
        L_half = max(2, round(P_a));

        L_win = 2 * L_half + 1;
        win   = pc_hann(L_win);

        a_idx    = (tm - L_half) : (tm + L_half);
        valid_a  = (a_idx >= 1) & (a_idx <= N);
        grain    = zeros(L_win, 1);
        grain(valid_a) = x(a_idx(valid_a));
        grain    = grain .* win;

        tk_round = round(tk);
        s_idx    = (tk_round - L_half) : (tk_round + L_half);
        valid_s  = (s_idx >= 1) & (s_idx <= N);

        s_valid_indices = s_idx(valid_s);
        y_psola(s_valid_indices) = y_psola(s_valid_indices) + grain(valid_s);
        w_sum(s_valid_indices)   = w_sum(s_valid_indices)   + win(valid_s);
    end

    % Safe WOLA normalization (floor at 0.15 prevents grain-tail division spikes)
    valid_w = w_sum > 1e-6;
    y_psola(valid_w)  = y_psola(valid_w) ./ max(w_sum(valid_w), 0.15);
    y_psola(~valid_w) = x(~valid_w);

    % Match voiced RMS energy to input voiced RMS
    vMask = is_voiced_samples;
    if any(vMask)
        rmsIn  = sqrt(mean(x(vMask).^2));
        rmsOut = sqrt(mean(y_psola(vMask).^2));
        if rmsOut > 1e-8
            y_psola = y_psola * (rmsIn / rmsOut);
        end
    end

    % Step 4: Smooth 10 ms crossfade between pitch-shifted vowels and crisp
    % unvoiced consonants when unvoiced segments are present
    if all(is_voiced_samples)
        y = y_psola;
    else
        fadeLen = max(3, round(0.010 * fs));
        v_env   = movmean(double(is_voiced_samples), fadeLen);
        y       = v_env .* y_psola + (1.0 - v_env) .* x;
    end

    % Step 5: Output smoothing & clipping protection
    peakOut = max(abs(y));
    peakIn  = max(abs(x));
    targetCap = max(0.98, peakIn);
    if peakOut > targetCap && peakOut > 0
        y = y * (targetCap / peakOut);
    end
end
