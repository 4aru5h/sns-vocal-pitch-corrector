function pc_plot_spectrum(ax, varargin)
%PC_PLOT_SPECTRUM Plot spectrogram or overlaid magnitude spectra on dark axes.
%   Supports both:
%     PC_PLOT_SPECTRUM(ax, res, modeStr)
%       where modeStr is 'corrected', 'original', 'cleaned', 'spectrogram', or 'spectrum'
%     PC_PLOT_SPECTRUM(ax, x, y, fs, modeStr)

    if isempty(varargin)
        error('pc_plot_spectrum:notEnoughInputs', 'Not enough input arguments.');
    end

    if isstruct(varargin{1})
        res = varargin{1};
        fs  = res.fs;
        if isfield(res, 'xRaw') && ~isempty(res.xRaw)
            xOrig = res.xRaw;
        else
            xOrig = res.x;
        end
        xClean = res.x;
        yCorr  = res.y;
        modeStr = 'corrected';
        if numel(varargin) >= 2
            modeStr = char(varargin{2});
        end
    else
        xOrig  = varargin{1}(:);
        xClean = xOrig;
        yCorr  = varargin{2}(:);
        fs     = varargin{3};
        modeStr = 'spectrogram';
        if numel(varargin) >= 4
            modeStr = char(varargin{4});
        end
    end

    cla(ax, 'reset');

    switch lower(modeStr)
        case 'original'
            sigPlot = xOrig;
            ttl = 'Original Input Spectrogram (0 - 5000 Hz)';
            isSpectrogram = true;
        case 'cleaned'
            sigPlot = xClean;
            ttl = 'Cleaned (Denoised) Spectrogram (0 - 5000 Hz)';
            isSpectrogram = true;
        case {'corrected', 'spectrogram'}
            sigPlot = yCorr;
            ttl = 'Pitch-Corrected Output Spectrogram (0 - 5000 Hz)';
            isSpectrogram = true;
        case 'spectrum'
            isSpectrogram = false;
        otherwise
            sigPlot = yCorr;
            ttl = 'Pitch-Corrected Output Spectrogram (0 - 5000 Hz)';
            isSpectrogram = true;
    end

    if isSpectrogram
        [S, f, t] = pc_stft(sigPlot, fs, 1024, 256);

        idx = f <= 5000;
        f = f(idx);
        S = S(idx, :);

        if isempty(t) || isempty(f)
            style_dark_axes(ax);
            title(ax, ttl, 'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);
            return;
        end

        maxS = max(S(:));
        if maxS <= 0, maxS = 1; end

        SdB = 20 * log10(S / maxS + 1e-12);
        SdB = max(SdB, -80);

        imagesc(ax, t, f, SdB);
        axis(ax, 'xy');
        colormap(ax, 'parula');
        cb = colorbar(ax);
        cb.Color = [0.75, 0.80, 0.88];
        cb.Label.String = 'Magnitude (dB)';
        cb.Label.Color  = [0.78, 0.82, 0.88];

        style_dark_axes(ax);
        xlabel(ax, 'Time (s)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        ylabel(ax, 'Frequency (Hz)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        title(ax, ttl, 'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);
        ylim(ax, [0, min(5000, fs/2)]);
        if numel(t) > 1
            xlim(ax, [t(1), t(end)]);
        end
    else
        N = size(xClean, 1);
        Nfft = 2^nextpow2(max(N, 2048));
        win = pc_hann(N);

        X = abs(fft(xClean .* win, Nfft));
        Y = abs(fft(yCorr .* win, Nfft));

        numBins = floor(Nfft/2) + 1;
        X = X(1:numBins);
        Y = Y(1:numBins);
        f = (0:numBins-1)' * (fs / Nfft);

        idx = f <= 5000;
        f = f(idx);
        X = X(idx);
        Y = Y(idx);

        ref = max([max(X), max(Y), 1e-12]);
        XdB = max(-90, 20 * log10(X / ref + 1e-12));
        YdB = max(-90, 20 * log10(Y / ref + 1e-12));

        hold(ax, 'on');
        plot(ax, f, XdB, 'Color', [0.38, 0.68, 0.98], 'LineWidth', 1.0, ...
             'DisplayName', 'Cleaned Input');
        plot(ax, f, YdB, 'Color', [0.16, 0.86, 0.56], 'LineWidth', 1.1, ...
             'DisplayName', 'Corrected Output');
        hold(ax, 'off');

        style_dark_axes(ax);
        xlabel(ax, 'Frequency (Hz)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        ylabel(ax, 'Magnitude (dB)', 'Color', [0.78, 0.82, 0.88], 'FontSize', 9);
        title(ax, 'Harmonic Magnitude Spectrum Comparison (0 - 5000 Hz)', ...
              'Color', [0.93, 0.95, 0.98], 'FontWeight', 'bold', 'FontSize', 10);

        lgd = legend(ax, 'Location', 'northeast');
        set(lgd, 'Color', [0.12, 0.14, 0.18], 'TextColor', [0.86, 0.89, 0.94], ...
                 'EdgeColor', [0.24, 0.27, 0.34], 'FontSize', 8);

        xlim(ax, [0, min(5000, fs/2)]);
        ylim(ax, [-85, 5]);
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
