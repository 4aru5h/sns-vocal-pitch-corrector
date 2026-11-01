function pc_plot_pitch(ax, varargin)
%PC_PLOT_PITCH Render detected, target, and corrected pitch contours.
%   Supports both:
%     PC_PLOT_PITCH(ax, res)
%     PC_PLOT_PITCH(ax, yin, contour, cfg)

    if isempty(varargin)
        error('pc_plot_pitch:notEnoughInputs', 'Not enough input arguments.');
    end

    if isstruct(varargin{1}) && isfield(varargin{1}, 'contour')
        res = varargin{1};
        if isfield(res, 'yin')
            yin = res.yin;
        else
            yin = res.pitch;
        end
        contour = res.contour;
        cfg = res.cfg;
    else
        yin     = varargin{1};
        contour = varargin{2};
        cfg     = varargin{3};
    end

    cla(ax, 'reset');
    hold(ax, 'on');

    if isfield(contour, 'tFrames')
        t = contour.tFrames;
    else
        t = contour.t;
    end
    f0Det  = yin.f0;
    f0Targ = contour.f0Target;
    f0Corr = contour.f0Corr;

    voiced = contour.voiced;
    f0Det(~voiced)  = NaN;
    f0Targ(~voiced) = NaN;
    f0Corr(~voiced) = NaN;

    validF0 = [f0Det(voiced); f0Targ(voiced); f0Corr(voiced)];
    validF0 = validF0(~isnan(validF0) & validF0 > 0);

    if isempty(validF0)
        style_dark_axes(ax);
        title(ax, sprintf('Pitch Tracking Contour (%s %s) — No Voiced Frames', ...
              cfg.key, cfg.scale), 'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);
        xlabel(ax, 'Time (s)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        ylabel(ax, 'Frequency (Hz)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        hold(ax, 'off');
        return;
    end

    minMidi = floor(pc_hz2midi(min(validF0))) - 2;
    maxMidi = ceil(pc_hz2midi(max(validF0))) + 2;
    midiRange = (minMidi:maxMidi)';

    pcs = pc_scale_pcs(cfg.key, cfg.scale);
    inScale = ismember(mod(midiRange, 12), pcs);
    scaleMidis = midiRange(inScale);
    scaleFreqs = pc_midi2hz(scaleMidis);
    scaleNames = pc_midi2name(scaleMidis);

    for k = 1:numel(scaleFreqs)
        yline(ax, scaleFreqs(k), ':', char(scaleNames(k)), ...
              'Color', [0.35, 0.40, 0.50], 'Alpha', 0.55, ...
              'LabelHorizontalAlignment', 'left', ...
              'FontSize', 8, 'HandleVisibility', 'off');
    end

    plot(ax, t, f0Det,  'Color', [0.38, 0.68, 0.98], 'LineWidth', 1.2, ...
         'DisplayName', 'Detected f0');
    plot(ax, t, f0Targ, '--', 'Color', [0.96, 0.66, 0.16], 'LineWidth', 1.3, ...
         'DisplayName', 'Scale Target');
    plot(ax, t, f0Corr, 'Color', [0.16, 0.86, 0.56], 'LineWidth', 1.9, ...
         'DisplayName', 'Corrected f0');

    hold(ax, 'off');
    style_dark_axes(ax);
    xlabel(ax, 'Time (s)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
    ylabel(ax, 'Frequency (Hz)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
    title(ax, sprintf('Pitch Contour Tracking — Key: %s %s', cfg.key, upper(cfg.scale)), ...
          'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);

    lgd = legend(ax, 'Location', 'northeast');
    set(lgd, 'Color', [0.12, 0.14, 0.18], 'TextColor', [0.86, 0.89, 0.94], ...
             'EdgeColor', [0.24, 0.27, 0.34], 'FontSize', 8);

    ylim(ax, [pc_midi2hz(minMidi), pc_midi2hz(maxMidi)]);
    if ~isempty(t) && t(end) > t(1)
        xlim(ax, [t(1), t(end)]);
    end
end

function style_dark_axes(ax)
    set(ax, 'Color', [0.08, 0.09, 0.12], ...
            'XColor', [0.68, 0.73, 0.80], ...
            'YColor', [0.68, 0.73, 0.80], ...
            'GridColor', [0.22, 0.25, 0.32], ...
            'GridAlpha', 0.45, ...
            'Box', 'on', ...
            'FontName', 'Segoe UI', ...
            'FontSize', 9);
    grid(ax, 'on');
end
