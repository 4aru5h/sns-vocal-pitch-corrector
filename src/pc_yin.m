function p = pc_yin(x, fs, cfg)
% PC_YIN YIN fundamental frequency (f0) estimator.
%   p = pc_yin(x, fs, cfg) estimates the fundamental frequency contour of
%   monophonic audio signal x using the YIN algorithm (de Cheveigné &
%   Kawahara, 2002) with cumulative mean normalized difference function (CMNDF)
%   computed in O(N log N) via FFT cross-correlation.
%
%   Output struct p contains matching column vectors:
%       p.t             - Frame center timestamps in seconds.
%       p.f0            - Fundamental frequency in Hz (NaN if unvoiced).
%       p.aperiodicity  - CMNDF value d' at the chosen dip tau*.
%       p.confidence    - Voicing confidence [0, 1] = max(0, min(1, 1 - d')).
%       p.voiced        - Logical flag (true if voiced, false if unvoiced).
%       p.rmsDb         - Frame RMS energy in dB relative to 1.0 full scale.

x = double(x(:));
N = numel(x);

if nargin < 3 || isempty(cfg)
    cfg = pc_default_config();
end

% Default parameter values
fmin = 70;
fmax = 1000;
winSec = 0.025;
hopSec = 0.005;
threshold = 0.15;
voicedMaxAperiodicity = 0.25;
silenceDb = -45;
medianFrames = 5;

if isfield(cfg, 'yin')
    if isfield(cfg.yin, 'fmin'), fmin = cfg.yin.fmin; end
    if isfield(cfg.yin, 'fmax'), fmax = cfg.yin.fmax; end
    if isfield(cfg.yin, 'winSec'), winSec = cfg.yin.winSec; end
    if isfield(cfg.yin, 'hopSec'), hopSec = cfg.yin.hopSec; end
    if isfield(cfg.yin, 'threshold'), threshold = cfg.yin.threshold; end
    if isfield(cfg.yin, 'voicedMaxAperiodicity'), voicedMaxAperiodicity = cfg.yin.voicedMaxAperiodicity; end
    if isfield(cfg.yin, 'silenceDb'), silenceDb = cfg.yin.silenceDb; end
    if isfield(cfg.yin, 'medianFrames'), medianFrames = cfg.yin.medianFrames; end
end

W = round(winSec * fs);
tau_min = max(1, floor(fs / fmax));
tau_max = ceil(fs / fmin);
hop = round(hopSec * fs);

% Compute one extra lag to safely evaluate parabolic interpolation at tau_max
tau_max_calc = tau_max + 1;
L = W + tau_max_calc;

% Frame centers and timestamps
frameCenters = (1 : hop : N)';
numFrames = numel(frameCenters);
t = (frameCenters - 1) / fs;

% Preallocate result arrays
f0 = nan(numFrames, 1);
aperiodicity = ones(numFrames, 1);
confidence = zeros(numFrames, 1);
voiced = false(numFrames, 1);
rmsDb = -240 * ones(numFrames, 1);

if numFrames == 0
    p.t = t;
    p.f0 = f0;
    p.aperiodicity = aperiodicity;
    p.confidence = confidence;
    p.voiced = voiced;
    p.rmsDb = rmsDb;
    return;
end

% Zero-pad signal symmetrically so frame centers align with original samples
pad_left = floor(W / 2);
pad_right = L + hop;
x_pad = [zeros(pad_left, 1); x; zeros(pad_right, 1)];

% FFT size for cross-correlation: length(u_rev) + length(frame) - 1 = W + L - 1
N_fft = 2^nextpow2(W + L);
tau_indices = (1 : tau_max_calc)';

for k = 1:numFrames
    idx_start = frameCenters(k);
    frame = x_pad(idx_start : idx_start + L - 1);
    u = frame(1 : W);
    
    % Step 1: Energy terms via cumsum
    cumSq = [0; cumsum(frame.^2)];
    E_u = cumSq(W + 1);
    frame_rms = sqrt(E_u / W);
    currRmsDb = 20 * log10(max(frame_rms, 1e-12));
    rmsDb(k) = currRmsDb;
    
    % Energy gate check
    if currRmsDb <= silenceDb
        continue;
    end
    
    % FFT cross-correlation r_{u,v}(tau) = sum_{j=1}^W u(j)*frame(j+tau)
    u_rev = u(W : -1 : 1);
    U = fft(u_rev, N_fft);
    V = fft(frame, N_fft);
    corr = real(ifft(U .* V));
    r = corr(W + (0 : tau_max_calc));
    
    % Energy of delayed window: E_v(tau) = sum_{m=1+tau}^{W+tau} frame(m)^2
    E_v = cumSq(W + 1 + (0 : tau_max_calc)) - cumSq(1 + (0 : tau_max_calc));
    
    % Difference function d(tau) = E_u + E_v(tau) - 2*r(tau)
    d = max(0, E_u + E_v - 2 * r);
    d(1) = 0;
    
    % Step 2: Cumulative Mean Normalized Difference Function (CMNDF)
    cum_d = cumsum(d(2 : end));
    d_prime = ones(tau_max_calc + 1, 1);
    nz = (cum_d > 0);
    d_prime(1 + find(nz)) = (d(1 + find(nz)) .* tau_indices(nz)) ./ cum_d(nz);
    
    % Step 3: Absolute threshold search in [tau_min, tau_max]
    found = false;
    tau_star = tau_min;
    for t_lag = tau_min : tau_max
        if d_prime(t_lag + 1) < threshold
            tau_star = t_lag;
            % Descend to local minimum
            while (tau_star < tau_max) && (d_prime(tau_star + 2) < d_prime(tau_star + 1))
                tau_star = tau_star + 1;
            end
            found = true;
            break;
        end
    end
    
    if ~found
        % Global minimum in [tau_min, tau_max]
        range_idx = (tau_min : tau_max) + 1;
        [~, min_rel_idx] = min(d_prime(range_idx));
        tau_star = tau_min + min_rel_idx - 1;
    end
    
    % Step 4: Parabolic interpolation around tau_star
    y1 = d_prime(tau_star);       % at lag tau_star - 1
    y2 = d_prime(tau_star + 1);   % at lag tau_star
    y3 = d_prime(tau_star + 2);   % at lag tau_star + 1
    
    denom = 2 * (y1 - 2 * y2 + y3);
    if abs(denom) > 1e-12
        delta = (y1 - y3) / denom;
        if abs(delta) > 1
            delta = 0;
        end
    else
        delta = 0;
    end
    
    tau_fine = tau_star + delta;
    d_fine = max(0, y2 - 0.25 * (y1 - y3) * delta);
    
    % Step 5: Frequency, aperiodicity, confidence, voicing decision
    aperiodicity(k) = d_fine;
    confidence(k) = max(0, min(1, 1 - d_fine));
    
    isVoiced = (d_fine < voicedMaxAperiodicity) && (currRmsDb > silenceDb);
    if isVoiced
        f0(k) = fs / tau_fine;
        voiced(k) = true;
    end
end

% Step 6: Post-processing over contiguous voiced runs
isVoicedRun = ~isnan(f0);
d_run = diff([false; isVoicedRun; false]);
run_starts = find(d_run == 1);
run_ends = find(d_run == -1) - 1;

for r = 1:numel(run_starts)
    idx = run_starts(r) : run_ends(r);
    run_len = numel(idx);
    if run_len < 3
        % Drop runs shorter than 3 frames
        f0(idx) = NaN;
        voiced(idx) = false;
    else
        % movmedian over voiced run
        w_med = min(medianFrames, run_len);
        f0(idx) = movmedian(f0(idx), w_med);
    end
end

p.t = t;
p.f0 = f0;
p.aperiodicity = aperiodicity;
p.confidence = confidence;
p.voiced = voiced;
p.rmsDb = rmsDb;
end
