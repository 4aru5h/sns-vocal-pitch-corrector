function [y, denoiseInfo] = pc_denoise(x, fs, cfg)
%PC_DENOISE Stationary noise estimation and decision-directed soft spectral gating.
%   [y, denoiseInfo] = PC_DENOISE(x, fs, cfg) estimates the stationary
%   background noise PSD using quiet-frame detection (when pauses exist) and
%   inter-harmonic spectral valley quantiles (when the input is continuous),
%   then applies a smooth decision-directed Wiener spectral gain in Base MATLAB.
%
%   Automatically bypasses gating when the estimated SNR exceeds 40 dB so clean
%   studio or synthetic test signals remain mathematically unaltered.

    arguments
        x (:,1) double {mustBeReal, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        cfg struct = struct()
    end

    if ~isfield(cfg, 'denoiseEnable'),   cfg.denoiseEnable   = true; end
    if ~isfield(cfg, 'denoiseStrength'), cfg.denoiseStrength = 1.0;  end

    N = numel(x);
    denoiseInfo = struct('applied', false, 'noiseFloorDb', -100, ...
                         'estimatedSnrDb', 100, 'snrImproveDb', 0);

    if ~cfg.denoiseEnable || cfg.denoiseStrength <= 0 || N < round(0.08 * fs)
        y = x;
        return;
    end

    % STFT parameters: ~32 ms Hann window, 75% overlap (COLA compliant)
    nfft = 2^nextpow2(max(256, round(0.032 * fs)));
    hop  = nfft / 4;
    if N < nfft + 2 * hop
        y = x;
        return;
    end

    win = pc_hann(nfft);

    % Pad signal at boundaries to ensure constant overlap-add weight at edges
    padLen = nfft;
    xPad = [zeros(padLen, 1); x; zeros(padLen, 1)];
    Npad = numel(xPad);

    numFrames = floor((Npad - nfft) / hop) + 1;
    nBins = nfft / 2 + 1;

    % Forward STFT
    S = zeros(nBins, numFrames);
    for m = 1:numFrames
        idx = (m - 1) * hop + (1:nfft);
        frame = xPad(idx) .* win;
        F = fft(frame, nfft);
        S(:, m) = F(1:nBins);
    end

    magSq = abs(S).^2;

    % Estimate noise floor only over interior frames (excluding zero-padding)
    firstInterior = max(1, ceil(padLen / hop) + 1);
    lastInterior  = min(numFrames, floor((padLen + N - nfft) / hop) + 1);
    if lastInterior <= firstInterior + 2
        firstInterior = 1;
        lastInterior  = numFrames;
    end
    interiorMagSq = magSq(:, firstInterior:lastInterior);
    M_int = size(interiorMagSq, 2);

    % Frame power in vocal band (80 Hz to 6000 Hz)
    freqs = (0:nBins-1)' * (fs / nfft);
    vocalBins = (freqs >= 80) & (freqs <= min(6000, 0.45 * fs));
    if ~any(vocalBins), vocalBins = true(nBins, 1); end

    framePow  = mean(interiorMagSq(vocalBins, :), 1);
    sortedPow = sort(framePow, 'ascend');

    sigPowEst = sortedPow(max(1, round(0.88 * M_int)));
    minPowEst = sortedPow(max(1, round(0.15 * M_int)));

    % Inter-harmonic spectral floor (30th percentile across frequency bins)
    % Accurately measures broadband noise even when a tone/vowel has no pauses
    interHarmonicFloor = prctile_col(interiorMagSq(vocalBins, :), 0.30) * 1.45;
    broadbandNoiseBinPow = median(interHarmonicFloor);

    % Check whether the recording contains genuine quiet pause frames
    hasQuietFrames = (minPowEst < 0.25 * sigPowEst);

    if hasQuietFrames
        numNoiseFrames = max(1, round(0.20 * M_int));
        noiseThreshold = sortedPow(numNoiseFrames);
        noiseMask = framePow <= max(noiseThreshold * 1.25, 1e-18);
        noisePsd  = mean(interiorMagSq(:, noiseMask), 2) * 1.15;
        noisePowEst = max(mean(noisePsd(vocalBins)), 1e-20);
    else
        % Continuous signal without pauses: estimate white/smooth noise floor
        % from inter-harmonic valleys so sustained harmonics are never cancelled
        noiseMask = framePow <= sortedPow(max(1, round(0.25 * M_int)));
        noisePsd  = repmat(max(broadbandNoiseBinPow, 1e-20), nBins, 1);
        noisePowEst = max(broadbandNoiseBinPow, 1e-20);
    end

    estSnrDb     = 10 * log10(max(sigPowEst, 1e-20) / noisePowEst);
    noiseFloorDb = 10 * log10(noisePowEst / (nfft^2 / 4));

    denoiseInfo.noiseFloorDb   = noiseFloorDb;
    denoiseInfo.estimatedSnrDb = estSnrDb;

    % Bypass if signal is already studio-clean (SNR > 40 dB)
    if estSnrDb > 40
        y = x;
        return;
    end

    % Decision-directed soft Wiener spectral gating
    strength = min(max(cfg.denoiseStrength, 0), 2.0);
    overSub  = 1.0 + 1.6 * strength;           % Oversubtraction factor beta
    gFloor   = 10^(-(14 + 6 * strength) / 20); % Spectral floor (-14 to -26 dB)
    alphaDD  = 0.90;                           % Decision-directed smoothing

    G = ones(nBins, numFrames);
    G_prev = ones(nBins, 1);
    gamma_prev = ones(nBins, 1);
    scaledNoise = max(overSub * noisePsd, 1e-20);

    for m = 1:numFrames
        gamma = magSq(:, m) ./ scaledNoise;
        xi = alphaDD * (G_prev.^2 .* gamma_prev) + (1 - alphaDD) * max(gamma - 1.0, 0);
        g_curr = xi ./ (xi + 1.0);
        g_curr = max(gFloor, min(1.0, g_curr));

        % 3-bin frequency smoothing [0.25, 0.5, 0.25] to suppress musical noise
        if nBins >= 5
            g_smooth = g_curr;
            g_smooth(2:end-1) = 0.25 * g_curr(1:end-2) + 0.50 * g_curr(2:end-1) + 0.25 * g_curr(3:end);
            g_curr = g_smooth;
        end

        G(:, m) = g_curr;
        G_prev = g_curr;
        gamma_prev = gamma;
    end

    % Mild temporal smoothing across adjacent frames [0.2, 0.6, 0.2]
    if numFrames >= 3
        G_temp = G;
        G_temp(:, 2:end-1) = 0.20 * G(:, 1:end-2) + 0.60 * G(:, 2:end-1) + 0.20 * G(:, 3:end);
        G = G_temp;
    end

    % Apply spectral gain and reconstruct via weighted overlap-add (WOLA)
    S_clean = S .* G;
    yPad = zeros(Npad, 1);
    wSum = zeros(Npad, 1);
    winSq = win.^2;

    for m = 1:numFrames
        posSpec = S_clean(:, m);
        fullSpec = [posSpec; conj(posSpec(end-1:-1:2))];
        frameOut = real(ifft(fullSpec, nfft));
        idx = (m - 1) * hop + (1:nfft);
        yPad(idx) = yPad(idx) + frameOut .* win;
        wSum(idx) = wSum(idx) + winSq;
    end

    validW = wSum > 1e-8;
    yPad(validW) = yPad(validW) ./ wSum(validW);
    y = yPad(padLen + 1 : padLen + N);

    % Compute noise reduction metric on quiet frames
    outQuietPow = mean(abs(S_clean(vocalBins, firstInterior - 1 + find(noiseMask))).^2, 'all');
    inQuietPow  = mean(interiorMagSq(vocalBins, noiseMask), 'all');
    if inQuietPow > 1e-20 && outQuietPow > 1e-20
        denoiseInfo.snrImproveDb = max(0, 10 * log10(inQuietPow / outQuietPow));
    end
    denoiseInfo.applied = true;
end

function q = prctile_col(A, p)
    % Base MATLAB column-wise quantile p in [0, 1]
    B = sort(A, 1, 'ascend');
    nRows = size(B, 1);
    idx = min(nRows, max(1, round(p * nRows)));
    q = B(idx, :);
end
