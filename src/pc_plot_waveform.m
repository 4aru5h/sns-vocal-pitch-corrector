function pc_plot_waveform(ax, varargin)
%PC_PLOT_WAVEFORM Plot time-domain waveforms on dark studio axes.
%   Supports both:
%     PC_PLOT_WAVEFORM(ax, res)
%     PC_PLOT_WAVEFORM(ax, res, modeStr)
%     PC_PLOT_WAVEFORM(ax, t, x, y)
%     PC_PLOT_WAVEFORM(ax, t, x, y, modeStr)

    if isempty(varargin)
        error('pc_plot_waveform:notEnoughInputs', 'Not enough input arguments.');
    end

    modeStr = 'corrected';
    if isstruct(varargin{1})
        res = varargin{1};
        t = res.tSamples;
        if numel(varargin) >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
            modeStr = char(varargin{2});
        end
        if strcmpi(modeStr, 'cleaned') && isfield(res, 'xRaw') && ~isempty(res.xRaw)
            x = res.xRaw;
            y = res.x;
        elseif strcmpi(modeStr, 'raw_vs_corrected') && isfield(res, 'xRaw') && ~isempty(res.xRaw)
            x = res.xRaw;
            y = res.y;
        else
            x = res.x;
            y = res.y;
        end
    else
        t = varargin{1}(:);
        x = varargin{2}(:);
        y = varargin{3}(:);
        if numel(varargin) >= 4
            modeStr = char(varargin{4});
        end
    end

    cla(ax, 'reset');
    hold(ax, 'on');

    switch lower(modeStr)
        case 'cleaned'
            lblA = 'Original Input';
            lblB = 'Cleaned (Preprocessed)';
            colA = [0.52, 0.57, 0.65];
            colB = [0.22, 0.74, 0.97];
            ttl  = 'Time-Domain Waveform — Original vs Cleaned';
        case 'raw_vs_corrected'
            lblA = 'Original Raw Input';
            lblB = 'Pitch-Corrected Output';
            colA = [0.52, 0.57, 0.65];
            colB = [0.16, 0.84, 0.55];
            ttl  = 'Time-Domain Waveform — Original Raw vs Corrected Output';
        otherwise
            lblA = 'Preprocessed Input';
            lblB = 'Pitch-Corrected Output';
            colA = [0.45, 0.52, 0.62];
            colB = [0.16, 0.84, 0.55];
            ttl  = 'Time-Domain Waveform — Cleaned Input vs Corrected Output';
    end

    plot(ax, t, x, 'Color', colA, 'LineWidth', 0.9, 'DisplayName', lblA);
    plot(ax, t, y, 'Color', colB, 'LineWidth', 1.0, 'DisplayName', lblB);

    hold(ax, 'off');
    style_dark_axes(ax);
    xlabel(ax, 'Time (s)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
    ylabel(ax, 'Amplitude', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
    title(ax, ttl, 'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);

    lgd = legend(ax, 'Location', 'northeast');
    set(lgd, 'Color', [0.12, 0.14, 0.18], 'TextColor', [0.86, 0.89, 0.94], ...
             'EdgeColor', [0.24, 0.27, 0.34], 'FontSize', 8);

    ylim(ax, [-1.05, 1.05]);
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
