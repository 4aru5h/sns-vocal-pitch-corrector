classdef PitchCorrectorApp < handle
%PITCHCORRECTORAPP Desktop studio interface for digital vocal pitch correction.
%   app = PITCHCORRECTORAPP() launches the dark-themed vocal pitch correction
%   workstation. Supports PitchCorrectorApp('Visible', 'off') for headless
%   automated testing.

    properties (Access = public)
        fig
        axWave
        axPitch
        axSpec

        % Section 1: Audio Input & Capture
        btnLoad
        btnSynthDemo
        ddInputDevice
        edtRecDur
        btnRecord

        % Section 2: Preprocessing & Noise Reduction
        chkDenoise
        sldDenoise
        lblDenoiseVal
        chkVocalFilter
        btnPreprocess

        % Section 3: Pitch Correction Parameters
        ddKey
        ddScale
        sldStrength
        lblStrengthVal
        sldRetune
        lblRetuneVal
        btnPresetHard
        btnPresetNatural
        btnProcess

        % Section 4: View Mode & Transport / Export
        ddWaveMode
        ddSpecMode
        btnPlayOrig
        btnPlayClean
        btnPlayCorr
        btnStop
        btnReset
        btnExport

        % Readout Telemetry Labels
        lblNoteIn
        lblNoteTarget
        lblF0Out
        lblCentsMetric
        lblDenoiseMetric
        lblStatus
    end

    properties (Access = private)
        xIn = []
        xRaw = []
        xClean = []
        fs = 44100
        res = []
        player = []
        inputDeviceIds = []
    end

    methods (Access = public)
        function app = PitchCorrectorApp(varargin)
            vis = 'on';
            for k = 1:2:numel(varargin)
                if strcmpi(varargin{k}, 'Visible')
                    vis = varargin{k+1};
                end
            end

            app.buildUI(vis);
        end

        function loadAudio(app, x, fs)
            % Programmatic hook to load an audio signal directly
            app.xIn = double(x);
            app.fs  = double(fs);
            app.res = [];

            % Run initial preprocessing so Original & Cleaned previews are ready
            app.runPreprocessingOnly(false);

            set(app.btnPlayOrig,  'Enable', 'on');
            set(app.btnPlayClean, 'Enable', 'on');
            set(app.btnPlayCorr,  'Enable', 'off');
            set(app.btnExport,    'Enable', 'off');

            pc_plot_waveform(app.axWave, (0:numel(app.xClean)-1)'/app.fs, ...
                             app.xRaw, app.xClean, 'cleaned');
            cla(app.axPitch, 'reset');
            app.styleEmptyAxes(app.axPitch, 'Pitch Contour Tracking — Ready to Process');
            cla(app.axSpec, 'reset');
            app.styleEmptyAxes(app.axSpec, 'Spectral Analysis — Ready to Process');

            app.setStatus(sprintf('Loaded audio: %.2f s at %d Hz. Ready for preprocessing or pitch correction.', ...
                          size(x, 1) / fs, fs));
        end

        function preprocessAudio(app)
            % Programmatic hook to run preprocessing and update Original vs Cleaned view
            app.runPreprocessingOnly(true);
        end

        function process(app)
            % Programmatic hook to execute full preprocessing + pitch correction pipeline
            if isempty(app.xIn)
                app.setStatus('No audio loaded. Import a WAV file, record mic audio, or load the Synth Demo first.');
                return;
            end

            app.setStatus('Processing pipeline: Conditioning -> Denoising -> YIN Pitch Tracking -> TD-PSOLA...');
            drawnow limitrate;

            try
                cfg = app.buildConfigFromUI();
                app.res    = pc_process(app.xIn, app.fs, cfg);
                app.xRaw   = app.res.xRaw;
                app.xClean = app.res.x;

                app.refreshVisualizations();
                app.updateTelemetryReadouts();

                set(app.btnPlayOrig,  'Enable', 'on');
                set(app.btnPlayClean, 'Enable', 'on');
                set(app.btnPlayCorr,  'Enable', 'on');
                set(app.btnExport,    'Enable', 'on');

                if app.res.info.silent
                    app.setStatus('Warning: Input signal is below the digital silence threshold (-80 dBFS).');
                else
                    m = app.res.metrics;
                    app.setStatus(sprintf(['Completed | Key: %s %s | Strength: %.0f%% | Retune: %.0f ms | ', ...
                        'Detected: %s (%.1f Hz) -> Target: %s (%.1f Hz) | Pitch Error: %.1f -> %.1f cents'], ...
                        cfg.key, upper(cfg.scale), cfg.strength*100, cfg.retuneMs, ...
                        m.detectedNote, m.medianF0In, m.targetNote, m.medianF0Target, ...
                        m.meanAbsCentsIn, m.meanAbsCentsOut));
                end
            catch ME
                app.setStatus(['Processing Error: ', ME.message]);
            end
        end

        function resetDefaults(app)
            % Programmatic hook to restore default studio parameters
            app.onStopAudio();
            set(app.chkDenoise,     'Value', 1);
            set(app.sldDenoise,     'Value', 100);
            set(app.lblDenoiseVal,  'String', '100%');
            set(app.chkVocalFilter, 'Value', 1);
            set(app.ddKey,          'Value', 1); % C
            set(app.ddScale,        'Value', 1); % major
            set(app.sldStrength,    'Value', 100);
            set(app.lblStrengthVal, 'String', '100%');
            set(app.sldRetune,      'Value', 0);
            set(app.lblRetuneVal,   'String', '0 ms');
            set(app.ddWaveMode,     'Value', 1);
            set(app.ddSpecMode,     'Value', 1);

            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Controls reset to factory studio defaults.');
            end
        end

        function res = getResult(app)
            res = app.res;
        end
    end

    methods (Access = private)
        function buildUI(app, vis)
            % Studio Color Palette
            bgMain     = [0.07, 0.08, 0.10];
            bgPanel    = [0.10, 0.11, 0.14];
            bgCard     = [0.12, 0.14, 0.18];
            bgControl  = [0.16, 0.18, 0.23];
            borderCol  = [0.20, 0.23, 0.29];
            txtPrimary = [0.92, 0.94, 0.98];
            txtMuted   = [0.62, 0.67, 0.75];
            accBlue    = [0.16, 0.52, 0.92];
            accEmerald = [0.12, 0.68, 0.46];
            accAmber   = [0.85, 0.54, 0.12];
            accCrimson = [0.78, 0.22, 0.28];

            app.fig = figure('Name', 'SNS Vocal Pitch Corrector — Studio DSP Workstation', ...
                             'NumberTitle', 'off', ...
                             'MenuBar', 'none', ...
                             'ToolBar', 'none', ...
                             'Color', bgMain, ...
                             'Position', [60, 60, 1280, 800], ...
                             'Visible', vis, ...
                             'CloseRequestFcn', @(~,~) app.onClose());

            % Left Sidebar Panel (Controls)
            pnlLeft = uipanel('Parent', app.fig, ...
                              'Units', 'normalized', ...
                              'Position', [0.01, 0.05, 0.26, 0.93], ...
                              'BackgroundColor', bgPanel, ...
                              'ForegroundColor', txtPrimary, ...
                              'HighlightColor', borderCol, ...
                              'BorderType', 'line', ...
                              'Title', '');

            % Header Banner inside Left Panel
            uicontrol('Parent', pnlLeft, 'Style', 'text', ...
                      'String', 'VOCAL PITCH WORKSTATION', ...
                      'Units', 'normalized', 'Position', [0.05, 0.955, 0.90, 0.032], ...
                      'BackgroundColor', bgPanel, 'ForegroundColor', txtPrimary, ...
                      'FontName', 'Segoe UI', 'FontSize', 11, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left');
            uicontrol('Parent', pnlLeft, 'Style', 'text', ...
                      'String', 'YIN f0 Estimator  |  Spectral Denoise  |  TD-PSOLA', ...
                      'Units', 'normalized', 'Position', [0.05, 0.932, 0.90, 0.022], ...
                      'BackgroundColor', bgPanel, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8, ...
                      'HorizontalAlignment', 'left');

            % =================================================================
            % SECTION 1: AUDIO INPUT & CAPTURE
            % =================================================================
            pnlInput = uipanel('Parent', pnlLeft, ...
                               'Title', ' 1. AUDIO INPUT & CAPTURE ', ...
                               'Units', 'normalized', ...
                               'Position', [0.04, 0.745, 0.92, 0.18], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.45, 0.74, 0.98], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold');

            app.btnLoad = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                    'String', 'Import WAV...', ...
                                    'Units', 'normalized', 'Position', [0.04, 0.62, 0.44, 0.31], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                    'Callback', @(~,~) app.onLoadAudio());

            app.btnSynthDemo = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                         'String', 'Load Demo Vocal', ...
                                         'Units', 'normalized', 'Position', [0.52, 0.62, 0.44, 0.31], ...
                                         'BackgroundColor', bgControl, 'ForegroundColor', [0.55, 0.82, 0.98], ...
                                         'FontName', 'Segoe UI', 'FontSize', 9, ...
                                         'Callback', @(~,~) app.onLoadSynthDemo());

            uicontrol('Parent', pnlInput, 'Style', 'text', 'String', 'Mic Input:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.33, 0.24, 0.20], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8, 'HorizontalAlignment', 'left');

            [devNames, devIds] = app.getAudioInputDevices();
            app.inputDeviceIds = devIds;
            app.ddInputDevice = uicontrol('Parent', pnlInput, 'Style', 'popupmenu', ...
                                          'String', devNames, ...
                                          'Units', 'normalized', 'Position', [0.28, 0.34, 0.68, 0.22], ...
                                          'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                          'FontName', 'Segoe UI', 'FontSize', 8);

            uicontrol('Parent', pnlInput, 'Style', 'text', 'String', 'Length (s):', ...
                      'Units', 'normalized', 'Position', [0.04, 0.05, 0.24, 0.22], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8, 'HorizontalAlignment', 'left');

            app.edtRecDur = uicontrol('Parent', pnlInput, 'Style', 'edit', ...
                                      'String', '5', ...
                                      'Units', 'normalized', 'Position', [0.28, 0.06, 0.20, 0.23], ...
                                      'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                      'FontName', 'Segoe UI', 'FontSize', 9);

            app.btnRecord = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                      'String', 'Record Mic', ...
                                      'Units', 'normalized', 'Position', [0.52, 0.05, 0.44, 0.25], ...
                                      'BackgroundColor', accCrimson, 'ForegroundColor', [1, 1, 1], ...
                                      'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                      'Callback', @(~,~) app.onRecordAudio());

            % =================================================================
            % SECTION 2: PREPROCESSING & NOISE REDUCTION
            % =================================================================
            pnlPre = uipanel('Parent', pnlLeft, ...
                             'Title', ' 2. PREPROCESSING & NOISE REDUCTION ', ...
                             'Units', 'normalized', ...
                             'Position', [0.04, 0.545, 0.92, 0.185], ...
                             'BackgroundColor', bgCard, ...
                             'ForegroundColor', [0.45, 0.74, 0.98], ...
                             'HighlightColor', borderCol, ...
                             'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold');

            app.chkDenoise = uicontrol('Parent', pnlPre, 'Style', 'checkbox', ...
                                       'String', 'Spectral Noise Reduction (Wiener Gate)', ...
                                       'Value', 1, ...
                                       'Units', 'normalized', 'Position', [0.04, 0.74, 0.92, 0.20], ...
                                       'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                       'FontName', 'Segoe UI', 'FontSize', 8.5, ...
                                       'Callback', @(~,~) app.onPreprocessParamChanged());

            uicontrol('Parent', pnlPre, 'Style', 'text', 'String', 'Denoise Strength:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.50, 0.42, 0.18], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8, 'HorizontalAlignment', 'left');

            app.lblDenoiseVal = uicontrol('Parent', pnlPre, 'Style', 'text', 'String', '100%', ...
                                          'Units', 'normalized', 'Position', [0.76, 0.50, 0.20, 0.18], ...
                                          'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                          'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', ...
                                          'HorizontalAlignment', 'right');

            app.sldDenoise = uicontrol('Parent', pnlPre, 'Style', 'slider', ...
                                       'Min', 0, 'Max', 150, 'Value', 100, ...
                                       'Units', 'normalized', 'Position', [0.44, 0.51, 0.32, 0.18], ...
                                       'BackgroundColor', bgControl, ...
                                       'Callback', @(~,~) app.onDenoiseSlider());

            app.chkVocalFilter = uicontrol('Parent', pnlPre, 'Style', 'checkbox', ...
                                           'String', 'Vocal Conditioning Filter (55 Hz - 10 kHz)', ...
                                           'Value', 1, ...
                                           'Units', 'normalized', 'Position', [0.04, 0.28, 0.92, 0.20], ...
                                           'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                           'FontName', 'Segoe UI', 'FontSize', 8.5, ...
                                           'Callback', @(~,~) app.onPreprocessParamChanged());

            app.btnPreprocess = uicontrol('Parent', pnlPre, 'Style', 'pushbutton', ...
                                          'String', 'Update & Preview Cleaned Audio', ...
                                          'Units', 'normalized', 'Position', [0.04, 0.04, 0.92, 0.22], ...
                                          'BackgroundColor', bgControl, 'ForegroundColor', [0.45, 0.82, 0.98], ...
                                          'FontName', 'Segoe UI', 'FontSize', 8.5, 'FontWeight', 'bold', ...
                                          'Callback', @(~,~) app.runPreprocessingOnly(true));

            % =================================================================
            % SECTION 3: PITCH CORRECTION ENGINE
            % =================================================================
            pnlPitch = uipanel('Parent', pnlLeft, ...
                               'Title', ' 3. PITCH CORRECTION ENGINE ', ...
                               'Units', 'normalized', ...
                               'Position', [0.04, 0.235, 0.92, 0.295], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.45, 0.74, 0.98], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold');

            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Musical Key:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.81, 0.30, 0.13], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8.5, 'HorizontalAlignment', 'left');

            keys = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'};
            app.ddKey = uicontrol('Parent', pnlPitch, 'Style', 'popupmenu', ...
                                  'String', keys, 'Value', 1, ...
                                  'Units', 'normalized', 'Position', [0.34, 0.82, 0.22, 0.14], ...
                                  'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                  'FontName', 'Segoe UI', 'FontSize', 8.5);

            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Scale:', ...
                      'Units', 'normalized', 'Position', [0.58, 0.81, 0.14, 0.13], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8.5, 'HorizontalAlignment', 'left');

            scales = {'major', 'minor', 'chromatic'};
            app.ddScale = uicontrol('Parent', pnlPitch, 'Style', 'popupmenu', ...
                                    'String', scales, 'Value', 1, ...
                                    'Units', 'normalized', 'Position', [0.72, 0.82, 0.24, 0.14], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 8.5);

            % Correction Strength Slider
            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Correction Strength:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.64, 0.55, 0.12], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8.5, 'HorizontalAlignment', 'left');

            app.lblStrengthVal = uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', '100%', ...
                                           'Units', 'normalized', 'Position', [0.74, 0.64, 0.22, 0.12], ...
                                           'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                           'FontName', 'Segoe UI', 'FontSize', 8.5, 'FontWeight', 'bold', ...
                                           'HorizontalAlignment', 'right');

            app.sldStrength = uicontrol('Parent', pnlPitch, 'Style', 'slider', ...
                                        'Min', 0, 'Max', 100, 'Value', 100, ...
                                        'Units', 'normalized', 'Position', [0.04, 0.53, 0.92, 0.10], ...
                                        'BackgroundColor', bgControl, ...
                                        'Callback', @(~,~) app.onStrengthSlider());

            % Retune Speed Slider
            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Retune Speed (ms):', ...
                      'Units', 'normalized', 'Position', [0.04, 0.39, 0.55, 0.12], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 8.5, 'HorizontalAlignment', 'left');

            app.lblRetuneVal = uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', '0 ms', ...
                                         'Units', 'normalized', 'Position', [0.74, 0.39, 0.22, 0.12], ...
                                         'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                         'FontName', 'Segoe UI', 'FontSize', 8.5, 'FontWeight', 'bold', ...
                                         'HorizontalAlignment', 'right');

            app.sldRetune = uicontrol('Parent', pnlPitch, 'Style', 'slider', ...
                                      'Min', 0, 'Max', 200, 'Value', 0, ...
                                      'Units', 'normalized', 'Position', [0.04, 0.28, 0.92, 0.10], ...
                                      'BackgroundColor', bgControl, ...
                                      'Callback', @(~,~) app.onRetuneSlider());

            % Presets (Zero emojis)
            app.btnPresetHard = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                          'String', 'Preset: Hard Quantize', ...
                                          'Units', 'normalized', 'Position', [0.04, 0.15, 0.45, 0.11], ...
                                          'BackgroundColor', accAmber, 'ForegroundColor', [0.08, 0.08, 0.10], ...
                                          'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', ...
                                          'Callback', @(~,~) app.onPresetHard());

            app.btnPresetNatural = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                             'String', 'Preset: Natural Studio', ...
                                             'Units', 'normalized', 'Position', [0.51, 0.15, 0.45, 0.11], ...
                                             'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                             'FontName', 'Segoe UI', 'FontSize', 8, ...
                                             'Callback', @(~,~) app.onPresetNatural());

            app.btnProcess = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                       'String', 'APPLY PITCH CORRECTION', ...
                                       'Units', 'normalized', 'Position', [0.04, 0.02, 0.92, 0.12], ...
                                       'BackgroundColor', accBlue, 'ForegroundColor', [1, 1, 1], ...
                                       'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                       'Callback', @(~,~) app.process());

            % =================================================================
            % SECTION 4: TRANSPORT, COMPARISON & EXPORT
            % =================================================================
            pnlTrans = uipanel('Parent', pnlLeft, ...
                               'Title', ' 4. MONITOR, COMPARE & EXPORT ', ...
                               'Units', 'normalized', ...
                               'Position', [0.04, 0.015, 0.92, 0.205], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.45, 0.74, 0.98], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold');

            app.btnPlayOrig = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                        'String', 'Play Original', 'Enable', 'off', ...
                                        'Units', 'normalized', 'Position', [0.04, 0.67, 0.29, 0.26], ...
                                        'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                        'FontName', 'Segoe UI', 'FontSize', 8, ...
                                        'Callback', @(~,~) app.onPlayAudio('original'));

            app.btnPlayClean = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                         'String', 'Play Cleaned', 'Enable', 'off', ...
                                         'Units', 'normalized', 'Position', [0.355, 0.67, 0.29, 0.26], ...
                                         'BackgroundColor', bgControl, 'ForegroundColor', [0.45, 0.82, 0.98], ...
                                         'FontName', 'Segoe UI', 'FontSize', 8, ...
                                         'Callback', @(~,~) app.onPlayAudio('cleaned'));

            app.btnPlayCorr = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                        'String', 'Play Corrected', 'Enable', 'off', ...
                                        'Units', 'normalized', 'Position', [0.67, 0.67, 0.29, 0.26], ...
                                        'BackgroundColor', accEmerald, 'ForegroundColor', [0.06, 0.08, 0.08], ...
                                        'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', ...
                                        'Callback', @(~,~) app.onPlayAudio('corrected'));

            % View Mode Selectors
            uicontrol('Parent', pnlTrans, 'Style', 'text', 'String', 'Wave View:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.37, 0.24, 0.20], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 7.5, 'HorizontalAlignment', 'left');

            app.ddWaveMode = uicontrol('Parent', pnlTrans, 'Style', 'popupmenu', ...
                                       'String', {'Cleaned vs Corrected', 'Original vs Cleaned', 'Original vs Corrected'}, ...
                                       'Value', 1, ...
                                       'Units', 'normalized', 'Position', [0.27, 0.39, 0.69, 0.22], ...
                                       'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                       'FontName', 'Segoe UI', 'FontSize', 7.5, ...
                                       'Callback', @(~,~) app.refreshVisualizations());

            uicontrol('Parent', pnlTrans, 'Style', 'text', 'String', 'Spec View:', ...
                      'Units', 'normalized', 'Position', [0.04, 0.18, 0.24, 0.18], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 7.5, 'HorizontalAlignment', 'left');

            app.ddSpecMode = uicontrol('Parent', pnlTrans, 'Style', 'popupmenu', ...
                                       'String', {'Corrected Spectrogram', 'Cleaned Spectrogram', 'Original Spectrogram', 'Harmonic Spectrum Overlay'}, ...
                                       'Value', 1, ...
                                       'Units', 'normalized', 'Position', [0.27, 0.19, 0.69, 0.20], ...
                                       'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                       'FontName', 'Segoe UI', 'FontSize', 7.5, ...
                                       'Callback', @(~,~) app.refreshVisualizations());

            % Bottom row: Stop | Reset | Export WAV
            app.btnStop = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                    'String', 'Stop Audio', ...
                                    'Units', 'normalized', 'Position', [0.04, 0.01, 0.28, 0.16], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 8, ...
                                    'Callback', @(~,~) app.onStopAudio());

            app.btnReset = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                     'String', 'Reset', ...
                                     'Units', 'normalized', 'Position', [0.35, 0.01, 0.24, 0.16], ...
                                     'BackgroundColor', bgControl, 'ForegroundColor', txtMuted, ...
                                     'FontName', 'Segoe UI', 'FontSize', 8, ...
                                     'Callback', @(~,~) app.resetDefaults());

            app.btnExport = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                      'String', 'Export WAV...', 'Enable', 'off', ...
                                      'Units', 'normalized', 'Position', [0.62, 0.01, 0.34, 0.16], ...
                                      'BackgroundColor', accBlue, 'ForegroundColor', [1, 1, 1], ...
                                      'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', ...
                                      'Callback', @(~,~) app.onExportAudio());

            % =================================================================
            % RIGHT AREA: TELEMETRY HEADER STRIP + 3 DIAGNOSTIC AXES
            % =================================================================
            pnlTelemetry = uipanel('Parent', app.fig, ...
                                   'Units', 'normalized', ...
                                   'Position', [0.28, 0.90, 0.71, 0.08], ...
                                   'BackgroundColor', bgPanel, ...
                                   'HighlightColor', borderCol, ...
                                   'BorderType', 'line');

            app.lblNoteIn      = app.createMetricCard(pnlTelemetry, [0.01, 0.08, 0.18, 0.84], 'DETECTED NOTE / F0', '--', [0.38, 0.68, 0.98]);
            app.lblNoteTarget  = app.createMetricCard(pnlTelemetry, [0.20, 0.08, 0.18, 0.84], 'SCALE TARGET NOTE', '--', [0.96, 0.66, 0.16]);
            app.lblF0Out       = app.createMetricCard(pnlTelemetry, [0.39, 0.08, 0.18, 0.84], 'CORRECTED OUTPUT F0', '--', [0.16, 0.86, 0.56]);
            app.lblCentsMetric = app.createMetricCard(pnlTelemetry, [0.58, 0.08, 0.20, 0.84], 'MEAN CENTS ERROR (IN -> OUT)', '--', txtPrimary);
            app.lblDenoiseMetric = app.createMetricCard(pnlTelemetry, [0.79, 0.08, 0.20, 0.84], 'PREPROCESS / DENOISE', 'Ready', [0.45, 0.82, 0.98]);

            % 3 Diagnostic Axes
            app.axWave  = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.33, 0.64, 0.64, 0.22]);
            app.axPitch = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.33, 0.36, 0.64, 0.22]);
            app.axSpec  = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.33, 0.08, 0.64, 0.22]);

            app.styleEmptyAxes(app.axWave,  'Time-Domain Waveform — Load or Record Audio to Begin');
            app.styleEmptyAxes(app.axPitch, 'Pitch Contour Tracking — Detected f0, Scale Target & Corrected f0');
            app.styleEmptyAxes(app.axSpec,  'Spectral Analysis — STFT Spectrogram & Harmonic Magnitude Spectrum');

            % Bottom Status Bar
            app.lblStatus = uicontrol('Parent', app.fig, 'Style', 'text', ...
                                      'String', 'Ready. Import a WAV file, click Load Demo Vocal, or record from your microphone.', ...
                                      'Units', 'normalized', 'Position', [0.01, 0.008, 0.98, 0.032], ...
                                      'BackgroundColor', [0.09, 0.10, 0.13], ...
                                      'ForegroundColor', [0.78, 0.83, 0.90], ...
                                      'FontName', 'Segoe UI', 'FontSize', 9, ...
                                      'HorizontalAlignment', 'left');
        end

        function lblVal = createMetricCard(~, parent, pos, titleStr, initVal, valCol)
            card = uipanel('Parent', parent, 'Units', 'normalized', 'Position', pos, ...
                           'BackgroundColor', [0.12, 0.14, 0.18], ...
                           'HighlightColor', [0.20, 0.23, 0.29], 'BorderType', 'line');
            uicontrol('Parent', card, 'Style', 'text', 'String', titleStr, ...
                      'Units', 'normalized', 'Position', [0.06, 0.58, 0.88, 0.34], ...
                      'BackgroundColor', [0.12, 0.14, 0.18], 'ForegroundColor', [0.58, 0.64, 0.72], ...
                      'FontName', 'Segoe UI', 'FontSize', 7.5, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left');
            lblVal = uicontrol('Parent', card, 'Style', 'text', 'String', initVal, ...
                               'Units', 'normalized', 'Position', [0.06, 0.08, 0.88, 0.48], ...
                               'BackgroundColor', [0.12, 0.14, 0.18], 'ForegroundColor', valCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 10.5, 'FontWeight', 'bold', ...
                               'HorizontalAlignment', 'left');
        end

        function styleEmptyAxes(~, ax, ttl)
            set(ax, 'Color', [0.08, 0.09, 0.12], ...
                    'XColor', [0.68, 0.73, 0.80], ...
                    'YColor', [0.68, 0.73, 0.80], ...
                    'GridColor', [0.22, 0.25, 0.32], ...
                    'GridAlpha', 0.45, ...
                    'Box', 'on', ...
                    'FontName', 'Segoe UI', 'FontSize', 9);
            grid(ax, 'on');
            title(ax, ttl, 'Color', [0.90, 0.93, 0.97], 'FontWeight', 'bold', 'FontSize', 10);
        end

        function cfg = buildConfigFromUI(app)
            cfg = pc_default_config();
            keys   = get(app.ddKey, 'String');
            scales = get(app.ddScale, 'String');
            cfg.key      = keys{get(app.ddKey, 'Value')};
            cfg.scale    = scales{get(app.ddScale, 'Value')};
            cfg.strength = get(app.sldStrength, 'Value') / 100.0;
            cfg.retuneMs = get(app.sldRetune, 'Value');

            cfg.denoiseEnable     = logical(get(app.chkDenoise, 'Value'));
            cfg.denoiseStrength   = get(app.sldDenoise, 'Value') / 100.0;
            cfg.vocalFilterEnable = logical(get(app.chkVocalFilter, 'Value'));
        end

        function runPreprocessingOnly(app, updatePlots)
            if isempty(app.xIn)
                if updatePlots
                    app.setStatus('Load or record audio first before running preprocessing.');
                end
                return;
            end

            cfg = app.buildConfigFromUI();
            [xCln, info] = pc_preprocess(app.xIn, app.fs, cfg);
            app.xRaw   = info.xRaw;
            app.xClean = xCln;

            if info.denoiseApplied
                set(app.lblDenoiseMetric, 'String', sprintf('+%.1f dB SNR (Active)', info.snrImproveDb));
            elseif cfg.vocalFilterEnable
                set(app.lblDenoiseMetric, 'String', 'Vocal Filter Active');
            else
                set(app.lblDenoiseMetric, 'String', 'Bypassed (Raw)');
            end

            if updatePlots
                t = (0:numel(app.xClean)-1)' / app.fs;
                pc_plot_waveform(app.axWave, t, app.xRaw, app.xClean, 'cleaned');
                app.setStatus('Preprocessing updated. Displaying Original Input vs Cleaned Audio.');
            end
        end

        function refreshVisualizations(app)
            if isempty(app.res)
                if ~isempty(app.xClean)
                    t = (0:numel(app.xClean)-1)' / app.fs;
                    pc_plot_waveform(app.axWave, t, app.xRaw, app.xClean, 'cleaned');
                end
                return;
            end

            % 1. Waveform Axes
            waveIdx = get(app.ddWaveMode, 'Value');
            if waveIdx == 2
                pc_plot_waveform(app.axWave, app.res, 'cleaned');
            elseif waveIdx == 3
                pc_plot_waveform(app.axWave, app.res, 'raw_vs_corrected');
            else
                pc_plot_waveform(app.axWave, app.res, 'corrected');
            end

            % 2. Pitch Contour Axes
            pc_plot_pitch(app.axPitch, app.res);

            % 3. Spectral Analysis Axes
            specIdx = get(app.ddSpecMode, 'Value');
            switch specIdx
                case 1
                    pc_plot_spectrum(app.axSpec, app.res, 'corrected');
                case 2
                    pc_plot_spectrum(app.axSpec, app.res, 'cleaned');
                case 3
                    pc_plot_spectrum(app.axSpec, app.res, 'original');
                case 4
                    pc_plot_spectrum(app.axSpec, app.res, 'spectrum');
            end
        end

        function updateTelemetryReadouts(app)
            if isempty(app.res) || app.res.info.silent
                set(app.lblNoteIn,        'String', 'Silent');
                set(app.lblNoteTarget,    'String', '--');
                set(app.lblF0Out,         'String', '--');
                set(app.lblCentsMetric,   'String', '--');
                set(app.lblDenoiseMetric, 'String', 'Silent Input');
                return;
            end

            m = app.res.metrics;
            if isfinite(m.medianF0In)
                set(app.lblNoteIn, 'String', sprintf('%s  (%.1f Hz)', m.detectedNote, m.medianF0In));
            else
                set(app.lblNoteIn, 'String', 'Unvoiced');
            end

            if isfinite(m.medianF0Target)
                set(app.lblNoteTarget, 'String', sprintf('%s  (%.1f Hz)', m.targetNote, m.medianF0Target));
            else
                set(app.lblNoteTarget, 'String', '--');
            end

            if isfinite(m.medianF0Out)
                set(app.lblF0Out, 'String', sprintf('%.1f Hz', m.medianF0Out));
            else
                set(app.lblF0Out, 'String', '--');
            end

            if isfinite(m.meanAbsCentsIn) && isfinite(m.meanAbsCentsOut)
                set(app.lblCentsMetric, 'String', sprintf('%.1f ct  ->  %.1f ct', m.meanAbsCentsIn, m.meanAbsCentsOut));
            else
                set(app.lblCentsMetric, 'String', '--');
            end

            if app.res.info.denoiseApplied
                set(app.lblDenoiseMetric, 'String', sprintf('+%.1f dB SNR Gain', app.res.info.snrImproveDb));
            elseif app.res.info.vocalFilterApplied
                set(app.lblDenoiseMetric, 'String', 'Clean + Vocal HPF');
            else
                set(app.lblDenoiseMetric, 'String', 'Clean Input');
            end
        end

        function onLoadAudio(app)
            [file, path] = uigetfile({'*.wav;*.WAV', 'WAV Audio Files (*.wav)'}, 'Select Input Audio');
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            try
                [x, fsRead] = audioread(fullPath);
                app.loadAudio(x, fsRead);
                app.process();
            catch ME
                app.setStatus(['Error loading WAV file: ', ME.message]);
            end
        end

        function onLoadSynthDemo(app)
            % Generate a 2.4-second detuned 4-note C-major vocal phrase with mild room noise
            fsDemo = 44100;
            N = round(2.4 * fsDemo);
            t = (0:N-1)' / fsDemo;
            notesMidi = [60.35, 64.40, 67.30, 72.35]; % Detuned C4 - E4 - G4 - C5
            f0Track = zeros(N, 1);
            segLen = floor(N / 4);
            for k = 1:4
                idx = (k-1)*segLen + 1 : min(N, k*segLen);
                fBase = pc_midi2hz(notesMidi(k));
                vib = 18 * sin(2 * pi * 5.2 * t(idx));
                f0Track(idx) = fBase * (2 .^ (vib / 1200));
            end
            rng(7);
            xDemo = pc_synth_voice(fsDemo, f0Track) + 0.015 * randn(N, 1);
            app.loadAudio(xDemo, fsDemo);
            app.process();
        end

        function onRecordAudio(app)
            dur = str2double(get(app.edtRecDur, 'String'));
            if isnan(dur) || dur < 0.5 || dur > 60
                dur = 5;
                set(app.edtRecDur, 'String', '5');
            end

            try
                devIdx = get(app.ddInputDevice, 'Value');
                if ~isempty(app.inputDeviceIds) && devIdx <= numel(app.inputDeviceIds)
                    devId = app.inputDeviceIds(devIdx);
                    recObj = audiorecorder(app.fs, 16, 1, devId);
                else
                    recObj = audiorecorder(app.fs, 16, 1);
                end

                set(app.btnRecord, 'Enable', 'off', 'String', 'Recording...');
                app.setStatus(sprintf('Recording from microphone for %.1f seconds... Speak or sing clearly.', dur));
                drawnow;

                recordblocking(recObj, dur);
                xRec = getaudiodata(recObj, 'double');

                set(app.btnRecord, 'Enable', 'on', 'String', 'Record Mic');

                rawPeak = max(abs(xRec - mean(xRec)));
                if rawPeak < 1e-4
                    app.setStatus('Microphone signal is silent (peak < -80 dBFS). Check Windows microphone permissions or select another input device.');
                    return;
                end

                app.loadAudio(xRec, app.fs);
                app.process();
            catch ME
                set(app.btnRecord, 'Enable', 'on', 'String', 'Record Mic');
                app.setStatus(['Recording Error: ', ME.message]);
            end
        end

        function onDenoiseSlider(app)
            val = round(get(app.sldDenoise, 'Value'));
            set(app.lblDenoiseVal, 'String', sprintf('%d%%', val));
        end

        function onPreprocessParamChanged(app)
            if ~isempty(app.xIn)
                app.runPreprocessingOnly(false);
            end
        end

        function onStrengthSlider(app)
            val = round(get(app.sldStrength, 'Value'));
            set(app.lblStrengthVal, 'String', sprintf('%d%%', val));
        end

        function onRetuneSlider(app)
            val = round(get(app.sldRetune, 'Value'));
            set(app.lblRetuneVal, 'String', sprintf('%d ms', val));
        end

        function onPresetHard(app)
            set(app.sldStrength, 'Value', 100);
            set(app.lblStrengthVal, 'String', '100%');
            set(app.sldRetune, 'Value', 0);
            set(app.lblRetuneVal, 'String', '0 ms');
            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Preset loaded: Hard Quantize (100% Strength, 0 ms Retune Speed).');
            end
        end

        function onPresetNatural(app)
            set(app.sldStrength, 'Value', 85);
            set(app.lblStrengthVal, 'String', '85%');
            set(app.sldRetune, 'Value', 35);
            set(app.lblRetuneVal, 'String', '35 ms');
            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Preset loaded: Natural Studio (85% Strength, 35 ms Retune Speed).');
            end
        end

        function onPlayAudio(app, whichSig)
            app.onStopAudio();
            sig = [];
            switch lower(whichSig)
                case 'original'
                    if ~isempty(app.xRaw)
                        sig = app.xRaw;
                    elseif ~isempty(app.xIn)
                        sig = app.xIn;
                    end
                    label = 'Original Input';
                case 'cleaned'
                    sig = app.xClean;
                    label = 'Cleaned (Preprocessed) Audio';
                case 'corrected'
                    if ~isempty(app.res)
                        sig = app.res.y;
                    end
                    label = 'Pitch-Corrected Output';
            end

            if isempty(sig)
                app.setStatus('Requested audio buffer is empty.');
                return;
            end

            try
                app.player = audioplayer(sig, app.fs);
                play(app.player);
                app.setStatus(sprintf('Playing %s (%.2f s at %d Hz)...', label, numel(sig)/app.fs, app.fs));
            catch ME
                app.setStatus(['Audio Playback Error: ', ME.message]);
            end
        end

        function onStopAudio(app)
            if ~isempty(app.player) && isvalid(app.player)
                try
                    stop(app.player);
                catch
                end
            end
        end

        function onExportAudio(app)
            if isempty(app.res) || isempty(app.res.y)
                app.setStatus('No processed output available to export.');
                return;
            end
            [file, path] = uiputfile('corrected_vocal.wav', 'Export Corrected WAV');
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            try
                audiowrite(fullPath, app.res.y, app.fs);
                app.setStatus(['Exported pitch-corrected audio to: ', fullPath]);
            catch ME
                app.setStatus(['Export Error: ', ME.message]);
            end
        end

        function [names, ids] = getAudioInputDevices(~)
            names = {'Default Microphone'};
            ids   = -1;
            try
                devInfo = audiodevinfo;
                if isfield(devInfo, 'input') && ~isempty(devInfo.input)
                    nDev = numel(devInfo.input);
                    names = cell(1, nDev);
                    ids   = zeros(1, nDev);
                    for k = 1:nDev
                        names{k} = devInfo.input(k).Name;
                        ids(k)   = devInfo.input(k).ID;
                    end
                end
            catch
            end
        end

        function setStatus(app, msg)
            if ~isempty(app.lblStatus) && isvalid(app.lblStatus)
                set(app.lblStatus, 'String', ['  ', msg]);
            end
        end

        function onClose(app)
            app.onStopAudio();
            if ~isempty(app.fig) && isvalid(app.fig)
                delete(app.fig);
            end
        end
    end
end
