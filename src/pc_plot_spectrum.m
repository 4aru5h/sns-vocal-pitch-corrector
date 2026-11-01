function pc_plot_spectrum(ax, res, whichSignal)
% PC_PLOT_SPECTRUM Plot STFT spectrogram of original or corrected audio.
%   pc_plot_spectrum(ax, res, whichSignal) renders an STFT spectrogram
%   in dB into the target axes ax using pc_stft.
%
%   whichSignal: 'corrected' (default) or 'original'.

if nargin < 2 || isempty(res) || isempty(ax)
    return;
end

if nargin < 3 || isempty(whichSignal)
    whichSignal = 'corrected';
end

cla(ax);

if strcmpi(whichSignal, 'original')
    sig = res.x;
    labelStr = 'Original';
else
    sig = res.y;
    labelStr = 'Corrected';
end

fs = res.fs;
N = 1024;
hop = 256;

[S, f, t] = pc_stft(sig, fs, N, hop);
S_db = 20 * log10(max(S, 1e-6));

imagesc(ax, t, f, S_db);
axis(ax, 'xy');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Frequency (Hz)');
title(ax, sprintf('Spectrogram (%s)', labelStr));
colormap(ax, 'parula');
colorbar(ax);
end
