function pc_plot_waveform(ax, res)
% PC_PLOT_WAVEFORM Plot original and pitch-corrected waveforms.
%   pc_plot_waveform(ax, res) renders the original and corrected audio
%   waveforms into the target axes handle ax.

if nargin < 2 || isempty(res) || isempty(ax)
    return;
end

cla(ax);
t = (0 : numel(res.x) - 1)' / res.fs;

plot(ax, t, res.x, 'Color', [0.4 0.4 0.4], 'DisplayName', 'Original');
hold(ax, 'on');
plot(ax, t, res.y, 'Color', [0.0 0.45 0.85], 'LineWidth', 1.0, 'DisplayName', 'Corrected');
hold(ax, 'off');

xlabel(ax, 'Time (s)');
ylabel(ax, 'Amplitude');
title(ax, 'Waveforms (Original vs Corrected)');
legend(ax, 'show', 'Location', 'northeast');
grid(ax, 'on');
end
