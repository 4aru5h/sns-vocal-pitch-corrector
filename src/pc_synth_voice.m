function x = pc_synth_voice(fs, f0)
% PC_SYNTH_VOICE Synthesise harmonic test voice signal from per-sample f0.
%   x = pc_synth_voice(fs, f0) synthesises a harmonic signal with fundamental
%   frequency specified by the per-sample column vector f0 (in Hz).
%   NaN or 0 in f0 indicates silence for that sample.
%   Phase accumulation: phi = 2*pi*cumsum(f0)/fs (with 0 during silence).
%   Harmonics k = 1..K, K = floor(0.45*fs/f0) per sample, amplitude 1/k,
%   masked out where k*f0 > 0.45*fs. Peak normalised to 0.9.
%   Output x is a column vector.

f0 = f0(:);
N = numel(f0);
x = zeros(N, 1);

if N == 0
    return;
end

isSilence = isnan(f0) | (f0 <= 0);
f0_eff = f0;
f0_eff(isSilence) = 0;

phi = 2 * pi * cumsum(f0_eff) / fs;

if any(~isSilence)
    K_per_sample = zeros(N, 1);
    K_per_sample(~isSilence) = floor(0.45 * fs ./ f0(~isSilence));
    K_max = max(K_per_sample);
    
    for k = 1:K_max
        active = (k <= K_per_sample);
        x(active) = x(active) + sin(k * phi(active)) / k;
    end
end

peak = max(abs(x));
if peak > 0
    x = x * (0.9 / peak);
end

x = x(:);
end
