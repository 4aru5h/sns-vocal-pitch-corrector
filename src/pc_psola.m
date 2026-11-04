function y = pc_psola(x, fs, yin, ratioOrContour, cfg)
%PC_PSOLA Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA) resynthesis.
%   y = PC_PSOLA(x, fs, yin, ratioOrContour, cfg) shifts vocal pitch cleanly
%   according to ratioOrContour while preserving vocal formants, natural
%   timbre, and exact signal duration.
%
%   Key DSP design for crisp, artifact-free Auto-Tune:
%     1. Glottal-peak-locked analysis pitch marks (ta) searching within
%        [0.72*P, 1.28*P] of each cycle on the fundamental-isolated signal
%        so marks lock onto true glottal peaks without 2nd-harmonic jumps.
%     2. Single-cycle bounded Hann grain windowing L_half = round(min(P_a, P_syn))
%        so neighboring input glottal peaks at +-P_a never bleed into the
%        resynthesized signal (eliminating double-pitch / chorus artifacts).
%     3. Sub-sample linear grain interpolation at fractional synthesis marks (ts).
%     4. Period-smoothed overlap normalization and 12 ms consonant crossfade.

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

    f0Min = 80;   if isfield(cfg, 'f0Min'), f0Min = cfg.f0Min; end
    f0Max = 1000; if isfield(cfg, 'f0Max'), f0Max = cfg.f0Max; end
    minRatio = 0.5; if isfield(cfg, 'minPitchRatio'), minRatio = cfg.minPitchRatio; end
    maxRatio = 2.0; if isfield(cfg, 'maxPitchRatio'), maxRatio = cfg.maxPitchRatio; end

    Pmin = max(2, floor(fs / f0Max));
    Pmax = ceil(fs / f0Min);

    t_samples = ((0:N-1)' + 0.5) / fs;

    % Extend voiced period and ratio across unvoiced gaps using nearest
    % voiced neighbors so syllable boundaries never chirp
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

    % Isolate fundamental wave x_f0 so higher harmonics cannot cause
    % pitch-mark jumping
    maxVoicedF0 = prctile_vec(f0(voiced), 0.90);
    f0LpCutoff  = min(0.42 * fs, max(140, 1.45 * maxVoicedF0));
    x_f0 = pc_vocal_filter(x, fs, struct('enableHighPass', true, ...
                                         'highPassHz', 60, ...
                                         'enableLowPass', true, ...
                                         'lowPassHz', f0LpCutoff));

    % Step 1: Glottal-Peak-Locked Analysis Pitch Marks (ta)
    % On the start of each voiced segment, locate the local fundamental peak.
    % On subsequent cycles, search within [ta(end) + 0.72*P, ta(end) + 1.28*P]
    % so marks lock directly onto the true glottal cycle peak (eliminating
    % vibrato/glide residual) while never jumping to a 2nd harmonic (at 0.5*P).
    maxMarks = ceil(N / max(1, Pmin)) * 2 + 100;
    ta = zeros(maxMarks, 1);
    numTa = 0;

    firstSearchLen = min(N, round(1.5 * P_samples(1)));
    [~, firstPeak] = max(x_f0(1:max(1, firstSearchLen)));
    curr_pos = double(firstPeak);
    was_voiced = false;

    while curr_pos <= N
        idx_curr = min(max(round(curr_pos), 1), N);
        P_curr   = P_samples(idx_curr);
        v_curr   = is_voiced_samples(idx_curr);

        if v_curr
            if ~was_voiced || numTa == 0
                % Voiced onset: search +-0.5*P_curr to lock onto first glottal peak
                halfWin = max(1, round(0.50 * P_curr));
                search_min = max(1, idx_curr - halfWin);
                search_max = min(N, idx_curr + halfWin);
            else
                % Continuing voiced run: search [prev_ta + 0.72*P, prev_ta + 1.28*P]
                prev_ta = ta(numTa);
                search_min = max(1, round(prev_ta + 0.72 * P_curr));
                search_max = min(N, round(prev_ta + 1.28 * P_curr));
                if search_min > search_max
                    search_min = idx_curr;
                    search_max = idx_curr;
                end
            end

            [~, max_rel] = max(x_f0(search_min:search_max));
            peak_idx = search_min + max_rel - 1;

            % Parabolic sub-sample peak refinement on x_f0
            if peak_idx > 1 && peak_idx < N
                y1 = x_f0(peak_idx - 1);
                y2 = x_f0(peak_idx);
                y3 = x_f0(peak_idx + 1);
                denom = 2 * (2 * y2 - y1 - y3);
                if denom > 1e-12
                    frac_pk = max(-0.5, min(0.5, (y1 - y3) / denom));
                else
                    frac_pk = 0;
                end
                refined_ta = double(peak_idx) + frac_pk;
            else
                refined_ta = double(peak_idx);
            end
        else
            refined_ta = curr_pos;
        end

        refined_ta = max(1, min(double(N), refined_ta));
        if numTa > 0 && refined_ta <= ta(numTa)
            refined_ta = min(double(N), ta(numTa) + 0.5 * P_curr);
        end

        numTa = numTa + 1;
        ta(numTa) = refined_ta;
        was_voiced = v_curr;

        curr_pos = refined_ta + P_curr;
    end
    ta = ta(1:numTa);

    if numTa < 2
        y = x;
        return;
    end

    % Step 2: Synthesis Pitch Marks (ts) advancing at exact target period P_syn
    maxSynMarks = ceil(maxMarks * maxRatio) + 100;
    ts    = zeros(maxSynMarks, 1);
    PsynA = zeros(maxSynMarks, 1);
    numTs = 0;

    curr_ts = ta(1);
    while curr_ts <= N
        idx_curr = min(max(round(curr_ts), 1), N);
        P_curr   = P_samples(idx_curr);
        r_curr   = ratio_samples(idx_curr);

        if is_voiced_samples(idx_curr)
            P_syn = P_curr / r_curr;
        else
            P_syn = P_curr;
        end
        P_syn = max(2, P_syn);

        numTs = numTs + 1;
        ts(numTs)    = curr_ts;
        PsynA(numTs) = P_syn;

        curr_ts = curr_ts + P_syn;
    end
    ts    = ts(1:numTs);
    PsynA = PsynA(1:numTs);

    % Step 3: Single-Cycle Bounded Sub-Sample Overlap-Add
    % Using L_half = round(min(P_a, P_syn)) ensures each grain contains strictly
    % one glottal peak and decays to zero before neighboring marks.
    y_psola = zeros(N, 1);
    w_sum   = zeros(N, 1);

    m_idx = 1;
    for k = 1:numTs
        tk    = ts(k);
        P_syn = PsynA(k);

        while (m_idx < numTa) && (abs(ta(m_idx + 1) - tk) <= abs(ta(m_idx) - tk))
            m_idx = m_idx + 1;
        end

        tm  = ta(m_idx);
        idx_tm = min(max(round(tm), 1), N);
        P_a = P_samples(idx_tm);
        if m_idx > 1 && m_idx < numTa
            P_local = 0.5 * (ta(m_idx + 1) - ta(m_idx - 1));
            if P_local >= Pmin && P_local <= Pmax
                P_a = P_local;
            end
        end

        % Bound grain half-width by min(P_a, P_syn) when pitching up so old
        % cycle peaks never bleed in, and by max(P_a, P_syn) weighted smoothly
        L_half = max(4, round(min(P_a, P_syn)));

        L_win = 2 * L_half + 1;
        win   = pc_hann(L_win);

        % Sub-sample alignment: shift analysis read positions by (tm - tk_round)
        % so grain lands at exact floating-point synthesis mark tk
        tk_round = round(tk);
        frac_tk  = tk - tk_round;
        exact_center = tm - frac_tk;
        base_center  = floor(exact_center);
        alpha_interp = exact_center - base_center;

        a_idx   = (base_center - L_half) : (base_center + L_half);
        valid_a = (a_idx >= 1) & (a_idx < N);

        grain = zeros(L_win, 1);
        if any(valid_a)
            va = a_idx(valid_a);
            grain(valid_a) = (1.0 - alpha_interp) * x(va) + alpha_interp * x(va + 1);
        end
        grain = grain .* win;

        s_idx   = (tk_round - L_half) : (tk_round + L_half);
        valid_s = (s_idx >= 1) & (s_idx <= N);

        s_valid_indices = s_idx(valid_s);
        y_psola(s_valid_indices) = y_psola(s_valid_indices) + grain(valid_s);
        w_sum(s_valid_indices)   = w_sum(s_valid_indices)   + win(valid_s);
    end

    % Period-smoothed WOLA normalization: prevents intra-cycle amplitude
    % modulation while maintaining constant envelope across pitch shifts
    meanPsyn = round(median(PsynA));
    w_smooth = movmean(w_sum, max(3, meanPsyn));
    valid_w  = w_smooth > 0.10;
    y_psola(valid_w)  = y_psola(valid_w) ./ w_smooth(valid_w);
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

    % Step 4: Smooth 12 ms crossfade between pitch-corrected vowels and
    % crisp unvoiced consonants
    if all(is_voiced_samples)
        y = y_psola;
    else
        fadeLen = max(3, round(0.012 * fs));
        v_env   = movmean(double(is_voiced_samples), fadeLen);
        y       = v_env .* y_psola + (1.0 - v_env) .* x;
    end

    % Step 5: Output peak protection
    peakOut = max(abs(y));
    peakIn  = max(abs(x));
    targetCap = max(0.98, peakIn);
    if peakOut > targetCap && peakOut > 0
        y = y * (targetCap / peakOut);
    end
end

function q = prctile_vec(v, p)
    v = sort(v(:), 'ascend');
    if isempty(v)
        q = 220;
        return;
    end
    idx = min(numel(v), max(1, round(p * numel(v))));
    q = v(idx);
end
