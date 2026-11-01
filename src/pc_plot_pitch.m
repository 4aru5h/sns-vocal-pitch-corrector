function pc_plot_pitch(ax, res)
% PC_PLOT_PITCH Plot detected, target, and output pitch contours.
%   pc_plot_pitch(ax, res) plots pitch contours in fractional MIDI note
%   numbers with scientific pitch note-name y-ticks into axes ax.

if nargin < 2 || isempty(res) || isempty(ax)
    return;
end

cla(ax);

t_in = res.pitch.t;
midi_det = res.contour.midiDet;
midi_target = res.contour.midiTarget;

t_out = res.pitchOut.t;
midi_out = pc_hz2midi(res.pitchOut.f0);
if isfield(res.pitchOut, 'voiced')
    midi_out(~res.pitchOut.voiced) = NaN;
end

plot(ax, t_in, midi_det, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.2, 'DisplayName', 'Detected f0');
hold(ax, 'on');
plot(ax, t_in, midi_target, '--', 'Color', [0.2 0.7 0.2], 'LineWidth', 1.5, 'DisplayName', 'Target Note');
plot(ax, t_out, midi_out, 'Color', [0.0 0.45 0.85], 'LineWidth', 1.5, 'DisplayName', 'Corrected f0');
hold(ax, 'off');

% Configure note name y-ticks
all_midi = [midi_det(~isnan(midi_det)); midi_target(~isnan(midi_target)); midi_out(~isnan(midi_out))];
if ~isempty(all_midi)
    min_m = floor(min(all_midi));
    max_m = ceil(max(all_midi));
    tick_m = min_m : max_m;
    if numel(tick_m) > 20
        tick_m = min_m : 2 : max_m;
    end
    tick_names = pc_midi2name(tick_m);
    ax.YTick = tick_m;
    ax.YTickLabel = cellstr(tick_names);
    ylim(ax, [min_m - 0.5, max_m + 0.5]);
end

xlabel(ax, 'Time (s)');
ylabel(ax, 'Pitch (Note / MIDI)');
title(ax, 'Pitch Tracking & Correction');
legend(ax, 'show', 'Location', 'northeast');
grid(ax, 'on');
end
