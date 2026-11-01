function [x, info] = pc_preprocess(xIn, fs)
% PC_PREPROCESS Preprocess input audio for vocal pitch correction.
%   [x, info] = pc_preprocess(xIn, fs)
%   - Converts input to double column vector.
%   - Stereo/multichannel to mono: mean across channels.
%   - Errors if fs < 8000 or numel(xIn) < round(0.1*fs).
%   - Removes DC: subtracts mean.
%   - If max(abs(x)) < 1e-6:
%       returns zeros, info.silent = true, info.gain = 1.0.
%   - Otherwise:
%       info.silent = false, info.gain = 0.95 / max(abs(x)), x = x * info.gain.

if nargin < 2 || ~isnumeric(fs) || ~isscalar(fs) || fs < 8000
    error('pc_preprocess:invalidFs', 'Sample rate fs must be a numeric scalar >= 8000 Hz.');
end

if isempty(xIn) || numel(xIn) < round(0.1 * fs)
    error('pc_preprocess:tooShort', 'Input signal too short (< 0.1 s).');
end

x = double(xIn);

% Stereo / multichannel to mono, preserving column format
if isvector(x)
    x = x(:);
else
    x = mean(x, 2);
end

% Remove DC offset
x = x - mean(x);

% Silence and noise-floor threshold
% Signals with peak < 0.005 (-46 dBFS) are treated as silence to avoid
% multiplying ADC noise floor/dither by thousands of times.
silenceThreshold = 0.005;

peak = max(abs(x));
if peak < silenceThreshold
    x = zeros(size(x));
    info.silent = true;
    info.gain = 1.0;
else
    info.silent = false;
    % Cap normalization gain to 20x (+26 dB) to prevent noise explosion
    info.gain = min(20.0, 0.95 / peak);
    x = x * info.gain;
end
end
