function y = pc_psola(x, fs, p, ratio, cfg)
% PC_PSOLA Time-Domain Pitch-Synchronous Overlap-Add (TD-PSOLA).
%   y = pc_psola(x, fs, p, ratio, cfg) performs pitch shifting on audio
%   signal x while preserving duration using TD-PSOLA.
%
%   x:      Monophonic input audio signal (column vector).
%   fs:     Sampling frequency in Hz.
%   p:      YIN tracking struct with fields t, f0, voiced.
%   ratio:  Resynthesis pitch-shift ratio (scalar, per-frame, or per-sample).
%   cfg:    Configuration struct with psola and yin parameters.
%
%   Output y has exactly the same length as x, with window-sum normalisation
%   ensuring ratio==1 is an exact identity.

x = double(x(:));
N = numel(x);

if N == 0
    y = zeros(0, 1);
    return;
end

if nargin < 5 || isempty(cfg)
    cfg = pc_default_config();
end

% Extract parameters
unvoicedPeriodSec = 0.01;
refineMarks = true;
fmin = 70;
fmax = 1000;

if isfield(cfg, 'psola')
    if isfield(cfg.psola, 'unvoicedPeriodSec'), unvoicedPeriodSec = cfg.psola.unvoicedPeriodSec; end
    if isfield(cfg.psola, 'refineMarks'), refineMarks = cfg.psola.refineMarks; end
end
if isfield(cfg, 'yin')
    if isfield(cfg.yin, 'fmin'), fmin = cfg.yin.fmin; end
    if isfield(cfg.yin, 'fmax'), fmax = cfg.yin.fmax; end
end

Pu = round(unvoicedPeriodSec * fs);
Pmin = max(2, floor(fs / fmax));
Pmax = ceil(fs / fmin);

t_samples = (0 : N - 1)' / fs;

% Extract frame data from p
if isempty(p) || ~isfield(p, 't') || isempty(p.t)
    t_frames = [0; (N - 1) / fs];
    P_frames = [Pu; Pu];
    is_voiced_frame = [false; false];
else
    t_frames = p.t(:);
    N_frames = numel(t_frames);
    P_frames = Pu * ones(N_frames, 1);
    
    if isfield(p, 'voiced')
        is_voiced_frame = p.voiced(:) & ~isnan(p.f0(:)) & (p.f0(:) > 0);
    else
        is_voiced_frame = ~isnan(p.f0(:)) & (p.f0(:) > 0);
    end
    P_frames(is_voiced_frame) = fs ./ p.f0(is_voiced_frame);
end

% Process ratio
N_frames = numel(t_frames);
if isscalar(ratio)
    ratio_frames = ratio * ones(N_frames, 1);
elseif numel(ratio) == N_frames
    ratio_frames = ratio(:);
elseif numel(ratio) == N
    ratio_frames = [];
else
    ratio_frames = ones(N_frames, 1);
end

if ~isempty(ratio_frames)
    ratio_frames(~is_voiced_frame) = 1.0;
end

% Interpolate period and ratio to sample rate
if N_frames >= 2
    P_samples = interp1(t_frames, P_frames, t_samples, 'linear', 'extrap');
    is_voiced_samples = interp1(t_frames, double(is_voiced_frame), t_samples, 'nearest', 'extrap') > 0.5;
    if isempty(ratio_frames)
        ratio_samples = ratio(:);
    else
        ratio_samples = interp1(t_frames, ratio_frames, t_samples, 'linear', 'extrap');
    end
else
    P_samples = P_frames(1) * ones(N, 1);
    is_voiced_samples = is_voiced_frame(1) * ones(N, 1);
    if isempty(ratio_frames)
        ratio_samples = ratio(:);
    else
        ratio_samples = ratio_frames(1) * ones(N, 1);
    end
end

% Clamp period and ratio
P_samples = max(Pmin, min(Pmax, round(P_samples)));
ratio_samples = max(0.25, min(4.0, ratio_samples));

% Step 2: Analysis pitch marks ta
% Extend marks past N to ensure grains completely cover the signal boundaries
ta = [];
curr_ta = 1;
while curr_ta <= N + Pmax
    lookup_idx = min(N, max(1, curr_ta));
    P_curr = P_samples(lookup_idx);
    refined_ta = curr_ta;
    
    if refineMarks && is_voiced_samples(lookup_idx) && (curr_ta <= N)
        w_radius = round(0.25 * P_curr);
        win_min = max(1, curr_ta - w_radius);
        win_max = min(N, curr_ta + w_radius);
        if ~isempty(ta)
            win_min = max(win_min, ta(end) + 1);
        end
        if win_max >= win_min
            [~, max_rel] = max(x(win_min : win_max));
            refined_ta = win_min + max_rel - 1;
        end
    end
    
    ta(end + 1, 1) = refined_ta;
    curr_ta = refined_ta + P_curr;
end

% Step 3: Synthesis pitch marks ts
isIdentity = all(abs(ratio_samples - 1.0) < 1e-6);
if isIdentity
    ts = ta;
else
    ts = [];
    curr_ts = ta(1);
    while curr_ts <= N + Pmax
        ts_idx = round(curr_ts);
        ts(end + 1, 1) = ts_idx;
        lookup_idx = min(N, max(1, ts_idx));
        P_step = P_samples(lookup_idx) / ratio_samples(lookup_idx);
        curr_ts = curr_ts + P_step;
    end
end

% Step 4, 5, 6: Grain extraction, overlap-add, and window-sum normalisation
pad_left = 2 * Pmax + 100;
pad_right = 4 * Pmax + 100;
x_pad = [zeros(pad_left, 1); x; zeros(pad_right, 1)];

acc = zeros(N, 1);
wsum = zeros(N, 1);

for j = 1:numel(ts)
    ts_j = ts(j);
    
    % Find nearest analysis mark
    [~, k_near] = min(abs(ta - ts_j));
    ta_k = ta(k_near);
    lookup_k = min(N, max(1, ta_k));
    Pk = P_samples(lookup_k);
    
    % Hann window for grain of length 2*Pk + 1
    w = pc_hann(2 * Pk + 1);
    
    % Extract grain centered at ta_k
    grain_x = x_pad(ta_k + pad_left - Pk : ta_k + pad_left + Pk);
    grain = grain_x .* w;
    
    % Destination overlap in output buffer
    dst_start = max(1, ts_j - Pk);
    dst_end = min(N, ts_j + Pk);
    
    if dst_end >= dst_start
        g_start = 1 + (dst_start - (ts_j - Pk));
        g_end = (2 * Pk + 1) - ((ts_j + Pk) - dst_end);
        
        acc(dst_start : dst_end) = acc(dst_start : dst_end) + grain(g_start : g_end);
        wsum(dst_start : dst_end) = wsum(dst_start : dst_end) + w(g_start : g_end);
    end
end

% Normalise by summed window; fall back to x for any unreached boundary samples
valid_w = (wsum > 1e-3);
y = x;
y(valid_w) = acc(valid_w) ./ max(wsum(valid_w), 1e-3);

% Peak normalisation if clipping occurred (not applied for identity)
if ~isIdentity
    peak = max(abs(y));
    if peak > 1.0
        y = y * (0.99 / peak);
    end
end

y = y(:);
end
