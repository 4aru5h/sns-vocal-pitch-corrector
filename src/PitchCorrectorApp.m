classdef PitchCorrectorApp < handle
%PITCHCORRECTORAPP Simple, intuitive desktop interface for vocal Auto-Tune.
%   app = PITCHCORRECTORAPP() launches the clean dark-themed vocal Auto-Tune
%   application. Supports PitchCorrectorApp('Visible', 'off') for headless
%   automated testing.

    properties (Access = public)
        fig
        axWave
        axPitch
        axSpec

        % Step 1: Audio Input
        btnLoad
        btnSynthDemo
        ddInputDevice
        edtRecDur
        btnRecord

        % Step 2: Auto-Tune Controls
        ddKey
        ddScale
        sldStrength
        lblStrengthVal
        sldRetune
        lblRetuneVal
        btnPresetHard
        btnPresetNatural
        chkDenoise
        btnProcess

        % Step 3: Listen & Save
        btnPlayOrig
        btnPlayCorr
        btnStop
        btnReset
        btnExport

        % Readout Labels
        lblNoteIn
        lblNoteTarget
        lblCentsMetric
        lblStatus

        % Legacy / Programmatic compatibility handles (kept valid for tests)
        sldDenoise
        lblDenoiseVal
        chkVocalFilter
        btnPreprocess
        btnPlayClean
        ddWaveMode
        ddSpecMode
        lblF0Out
        lblDenoiseMetric
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

            app.runPreprocessingOnly(false);

            set(app.btnPlayOrig,  'Enable', 'on');
            set(app.btnPlayClean, 'Enable', 'on');
            set(app.btnPlayCorr,  'Enable', 'off');
            set(app.btnExport,    'Enable', 'off');

            pc_plot_waveform(app.axWave, (0:numel(app.xClean)-1)'/app.fs, ...
                             app.xRaw, app.xClean, 'cleaned');
            cla(app.axPitch, 'reset');
            app.styleEmptyAxes(app.axPitch, 'Pitch Contour (Click AUTO-TUNE AUDIO to Process)');
            cla(app.axSpec, 'reset');
            app.styleEmptyAxes(app.axSpec, 'Frequency Spectrum');

            app.setStatus(sprintf('Loaded %.2f s audio (%d Hz). Click AUTO-TUNE AUDIO or Play Original.', ...
                          size(x, 1) / fs, fs));
        end

        function preprocessAudio(app)
            % Programmatic hook to run preprocessing
            app.runPreprocessingOnly(true);
        end

        function process(app)
            % Execute Auto-Tune pipeline and update plots
            if isempty(app.xIn)
                app.setStatus('Load a WAV file, click Demo Vocal, or record your mic first.');
                return;
            end

            app.setStatus('Applying Auto-Tune pitch correction...');
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
                    app.setStatus('Input audio is silent. Please record louder or check your microphone.');
                else
                    m = app.res.metrics;
                    app.setStatus(sprintf('Auto-Tune Ready  |  Key: %s %s  |  Strength: %.0f%%  |  Retune: %.0f ms  |  %s -> %s', ...
                        cfg.key, upper(cfg.scale), cfg.strength*100, cfg.retuneMs, ...
                        m.detectedNote, m.targetNote));
                end
            catch ME
                app.setStatus(['Error: ', ME.message]);
            end
        end

        function resetDefaults(app)
            % Restore default Hard Auto-Tune settings
            app.onStopAudio();
            set(app.chkDenoise,     'Value', 0);
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
            set(app.ddSpecMode,     'Value', 4);

            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Reset to default Hard Auto-Tune settings (Key: C Major, Strength: 100%, Retune: 0 ms).');
            end
        end

        function res = getResult(app)
            res = app.res;
        end
    end

    methods (Access = private)
        function buildUI(app, vis)
            % Clean, Minimal Dark Palette
            bgMain     = [0.07, 0.08, 0.10];
            bgPanel    = [0.10, 0.11, 0.14];
            bgCard     = [0.13, 0.15, 0.19];
            bgControl  = [0.18, 0.20, 0.26];
            borderCol  = [0.22, 0.25, 0.32];
            txtPrimary = [0.94, 0.96, 0.99];
            txtMuted   = [0.64, 0.69, 0.77];
            accBlue    = [0.18, 0.55, 0.96];
            accEmerald = [0.12, 0.72, 0.48];
            accCrimson = [0.82, 0.24, 0.30];

            app.fig = figure('Name', 'Vocal Auto-Tune', ...
                             'NumberTitle', 'off', ...
                             'MenuBar', 'none', ...
                             'ToolBar', 'none', ...
                             'Color', bgMain, ...
                             'Position', [80, 70, 1180, 740], ...
                             'Visible', vis, ...
                             'CloseRequestFcn', @(~,~) app.onClose());

            % Left Sidebar (3 Simple Steps)
            pnlLeft = uipanel('Parent', app.fig, ...
                              'Units', 'normalized', ...
                              'Position', [0.015, 0.06, 0.27, 0.92], ...
                              'BackgroundColor', bgPanel, ...
                              'ForegroundColor', txtPrimary, ...
                              'HighlightColor', borderCol, ...
                              'BorderType', 'line', ...
                              'Title', '');

            uicontrol('Parent', pnlLeft, 'Style', 'text', ...
                      'String', 'VOCAL AUTO-TUNE', ...
                      'Units', 'normalized', 'Position', [0.06, 0.94, 0.88, 0.04], ...
                      'BackgroundColor', bgPanel, 'ForegroundColor', txtPrimary, ...
                      'FontName', 'Segoe UI', 'FontSize', 13, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left');

            % =================================================================
            % STEP 1: AUDIO INPUT
            % =================================================================
            pnlInput = uipanel('Parent', pnlLeft, ...
                               'Title', ' 1. AUDIO INPUT ', ...
                               'Units', 'normalized', ...
                               'Position', [0.05, 0.71, 0.90, 0.22], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.55, 0.80, 1.00], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold');

            app.btnLoad = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                    'String', 'Load WAV', ...
                                    'Units', 'normalized', 'Position', [0.05, 0.58, 0.43, 0.34], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                    'Callback', @(~,~) app.onLoadAudio());

            app.btnSynthDemo = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                         'String', 'Demo Vocal', ...
                                         'Units', 'normalized', 'Position', [0.52, 0.58, 0.43, 0.34], ...
                                         'BackgroundColor', bgControl, 'ForegroundColor', [0.55, 0.84, 1.00], ...
                                         'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                         'Callback', @(~,~) app.onLoadSynthDemo());

            [devNames, devIds] = app.getAudioInputDevices();
            app.inputDeviceIds = devIds;
            app.ddInputDevice = uicontrol('Parent', pnlInput, 'Style', 'popupmenu', ...
                                          'String', devNames, ...
                                          'Units', 'normalized', 'Position', [0.05, 0.31, 0.90, 0.20], ...
                                          'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                          'FontName', 'Segoe UI', 'FontSize', 8.5);

            uicontrol('Parent', pnlInput, 'Style', 'text', 'String', 'Sec:', ...
                      'Units', 'normalized', 'Position', [0.05, 0.05, 0.14, 0.20], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 9, 'HorizontalAlignment', 'left');

            app.edtRecDur = uicontrol('Parent', pnlInput, 'Style', 'edit', ...
                                      'String', '4', ...
                                      'Units', 'normalized', 'Position', [0.20, 0.06, 0.22, 0.22], ...
                                      'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                      'FontName', 'Segoe UI', 'FontSize', 9.5);

            app.btnRecord = uicontrol('Parent', pnlInput, 'Style', 'pushbutton', ...
                                      'String', 'Record Mic', ...
                                      'Units', 'normalized', 'Position', [0.46, 0.05, 0.49, 0.24], ...
                                      'BackgroundColor', accCrimson, 'ForegroundColor', [1, 1, 1], ...
                                      'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                      'Callback', @(~,~) app.onRecordAudio());

            % =================================================================
            % STEP 2: AUTO-TUNE SETTINGS
            % =================================================================
            pnlPitch = uipanel('Parent', pnlLeft, ...
                               'Title', ' 2. AUTO-TUNE SETTINGS ', ...
                               'Units', 'normalized', ...
                               'Position', [0.05, 0.26, 0.90, 0.43], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.55, 0.80, 1.00], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold');

            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Key:', ...
                      'Units', 'normalized', 'Position', [0.05, 0.84, 0.15, 0.10], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 9.5, 'HorizontalAlignment', 'left');

            keys = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'};
            app.ddKey = uicontrol('Parent', pnlPitch, 'Style', 'popupmenu', ...
                                  'String', keys, 'Value', 1, ...
                                  'Units', 'normalized', 'Position', [0.20, 0.85, 0.25, 0.11], ...
                                  'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                  'FontName', 'Segoe UI', 'FontSize', 9.5, ...
                                  'Callback', @(~,~) app.onAutoTuneParamChanged());

            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Scale:', ...
                      'Units', 'normalized', 'Position', [0.49, 0.84, 0.16, 0.10], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 9.5, 'HorizontalAlignment', 'left');

            scales = {'major', 'minor', 'chromatic'};
            app.ddScale = uicontrol('Parent', pnlPitch, 'Style', 'popupmenu', ...
                                    'String', scales, 'Value', 1, ...
                                    'Units', 'normalized', 'Position', [0.66, 0.85, 0.29, 0.11], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 9.5, ...
                                    'Callback', @(~,~) app.onAutoTuneParamChanged());

            % Mode Quick Buttons
            app.btnPresetHard = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                          'String', 'Hard Auto-Tune', ...
                                          'Units', 'normalized', 'Position', [0.05, 0.69, 0.43, 0.12], ...
                                          'BackgroundColor', [0.88, 0.56, 0.14], 'ForegroundColor', [0.07, 0.08, 0.10], ...
                                          'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                          'Callback', @(~,~) app.onPresetHard());

            app.btnPresetNatural = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                             'String', 'Natural Tune', ...
                                             'Units', 'normalized', 'Position', [0.52, 0.69, 0.43, 0.12], ...
                                             'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                             'FontName', 'Segoe UI', 'FontSize', 9, ...
                                             'Callback', @(~,~) app.onPresetNatural());

            % Strength Slider
            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Correction Strength:', ...
                      'Units', 'normalized', 'Position', [0.05, 0.54, 0.60, 0.09], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 9, 'HorizontalAlignment', 'left');

            app.lblStrengthVal = uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', '100%', ...
                                           'Units', 'normalized', 'Position', [0.70, 0.54, 0.25, 0.09], ...
                                           'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                           'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                           'HorizontalAlignment', 'right');

            app.sldStrength = uicontrol('Parent', pnlPitch, 'Style', 'slider', ...
                                        'Min', 0, 'Max', 100, 'Value', 100, ...
                                        'Units', 'normalized', 'Position', [0.05, 0.45, 0.90, 0.08], ...
                                        'BackgroundColor', bgControl, ...
                                        'Callback', @(~,~) app.onStrengthSlider());

            % Retune Speed Slider
            uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', 'Retune Speed (0 = Instant Snap):', ...
                      'Units', 'normalized', 'Position', [0.05, 0.33, 0.68, 0.09], ...
                      'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                      'FontName', 'Segoe UI', 'FontSize', 9, 'HorizontalAlignment', 'left');

            app.lblRetuneVal = uicontrol('Parent', pnlPitch, 'Style', 'text', 'String', '0 ms', ...
                                         'Units', 'normalized', 'Position', [0.73, 0.33, 0.22, 0.09], ...
                                         'BackgroundColor', bgCard, 'ForegroundColor', txtPrimary, ...
                                         'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                         'HorizontalAlignment', 'right');

            app.sldRetune = uicontrol('Parent', pnlPitch, 'Style', 'slider', ...
                                      'Min', 0, 'Max', 200, 'Value', 0, ...
                                      'Units', 'normalized', 'Position', [0.05, 0.24, 0.90, 0.08], ...
                                      'BackgroundColor', bgControl, ...
                                      'Callback', @(~,~) app.onRetuneSlider());

            % Simple Optional Noise Reduction Toggle (Off by default for pure vocal tone)
            app.chkDenoise = uicontrol('Parent', pnlPitch, 'Style', 'checkbox', ...
                                       'String', 'Reduce Background Noise', ...
                                       'Value', 0, ...
                                       'Units', 'normalized', 'Position', [0.05, 0.14, 0.90, 0.08], ...
                                       'BackgroundColor', bgCard, 'ForegroundColor', txtMuted, ...
                                       'FontName', 'Segoe UI', 'FontSize', 8.5, ...
                                       'Callback', @(~,~) app.onAutoTuneParamChanged());

            app.btnProcess = uicontrol('Parent', pnlPitch, 'Style', 'pushbutton', ...
                                       'String', 'AUTO-TUNE AUDIO', ...
                                       'Units', 'normalized', 'Position', [0.05, 0.02, 0.90, 0.11], ...
                                       'BackgroundColor', accBlue, 'ForegroundColor', [1, 1, 1], ...
                                       'FontName', 'Segoe UI', 'FontSize', 10, 'FontWeight', 'bold', ...
                                       'Callback', @(~,~) app.process());

            % =================================================================
            % STEP 3: LISTEN & SAVE
            % =================================================================
            pnlTrans = uipanel('Parent', pnlLeft, ...
                               'Title', ' 3. LISTEN & SAVE ', ...
                               'Units', 'normalized', ...
                               'Position', [0.05, 0.02, 0.90, 0.22], ...
                               'BackgroundColor', bgCard, ...
                               'ForegroundColor', [0.55, 0.80, 1.00], ...
                               'HighlightColor', borderCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold');

            app.btnPlayOrig = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                        'String', 'Play Original', 'Enable', 'off', ...
                                        'Units', 'normalized', 'Position', [0.05, 0.50, 0.43, 0.40], ...
                                        'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                        'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                        'Callback', @(~,~) app.onPlayAudio('original'));

            app.btnPlayCorr = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                        'String', 'Play Auto-Tuned', 'Enable', 'off', ...
                                        'Units', 'normalized', 'Position', [0.52, 0.50, 0.43, 0.40], ...
                                        'BackgroundColor', accEmerald, 'ForegroundColor', [0.05, 0.07, 0.07], ...
                                        'FontName', 'Segoe UI', 'FontSize', 9.5, 'FontWeight', 'bold', ...
                                        'Callback', @(~,~) app.onPlayAudio('corrected'));

            app.btnStop = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                    'String', 'Stop', ...
                                    'Units', 'normalized', 'Position', [0.05, 0.08, 0.26, 0.30], ...
                                    'BackgroundColor', bgControl, 'ForegroundColor', txtPrimary, ...
                                    'FontName', 'Segoe UI', 'FontSize', 9, ...
                                    'Callback', @(~,~) app.onStopAudio());

            app.btnReset = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                     'String', 'Reset', ...
                                     'Units', 'normalized', 'Position', [0.34, 0.08, 0.24, 0.30], ...
                                     'BackgroundColor', bgControl, 'ForegroundColor', txtMuted, ...
                                     'FontName', 'Segoe UI', 'FontSize', 9, ...
                                     'Callback', @(~,~) app.resetDefaults());

            app.btnExport = uicontrol('Parent', pnlTrans, 'Style', 'pushbutton', ...
                                      'String', 'Save WAV...', 'Enable', 'off', ...
                                      'Units', 'normalized', 'Position', [0.61, 0.08, 0.34, 0.30], ...
                                      'BackgroundColor', accBlue, 'ForegroundColor', [1, 1, 1], ...
                                      'FontName', 'Segoe UI', 'FontSize', 9, 'FontWeight', 'bold', ...
                                      'Callback', @(~,~) app.onExportAudio());

            % Hidden compatibility controls for programmatic tests
            app.sldDenoise       = uicontrol('Parent', pnlLeft, 'Style', 'slider', 'Min', 0, 'Max', 150, 'Value', 100, 'Visible', 'off');
            app.lblDenoiseVal    = uicontrol('Parent', pnlLeft, 'Style', 'text', 'String', '100%', 'Visible', 'off');
            app.chkVocalFilter   = uicontrol('Parent', pnlLeft, 'Style', 'checkbox', 'String', 'Vocal Filter', 'Value', 1, 'Visible', 'off');
            app.btnPreprocess    = uicontrol('Parent', pnlLeft, 'Style', 'pushbutton', 'String', 'Preprocess', 'Visible', 'off');
            app.btnPlayClean     = uicontrol('Parent', pnlLeft, 'Style', 'pushbutton', 'String', 'Play Cleaned', 'Visible', 'off');
            app.ddWaveMode       = uicontrol('Parent', pnlLeft, 'Style', 'popupmenu', 'String', {'Cleaned vs Corrected', 'Original vs Cleaned', 'Original vs Corrected'}, 'Value', 1, 'Visible', 'off');
            app.ddSpecMode       = uicontrol('Parent', pnlLeft, 'Style', 'popupmenu', 'String', {'Corrected Spectrogram', 'Cleaned Spectrogram', 'Original Spectrogram', 'Harmonic Spectrum Overlay'}, 'Value', 4, 'Visible', 'off');
            app.lblF0Out         = uicontrol('Parent', pnlLeft, 'Style', 'text', 'String', '--', 'Visible', 'off');
            app.lblDenoiseMetric = uicontrol('Parent', pnlLeft, 'Style', 'text', 'String', 'Ready', 'Visible', 'off');

            % =================================================================
            % RIGHT AREA: 3 CLEAN READOUT CARDS + 3 PLOTS (PITCH ON TOP)
            % =================================================================
            pnlTelemetry = uipanel('Parent', app.fig, ...
                                   'Units', 'normalized', ...
                                   'Position', [0.30, 0.90, 0.685, 0.08], ...
                                   'BackgroundColor', bgPanel, ...
                                   'HighlightColor', borderCol, ...
                                   'BorderType', 'line');

            app.lblNoteIn      = app.createMetricCard(pnlTelemetry, [0.015, 0.10, 0.31, 0.80], 'INPUT NOTE / PITCH', '--', [0.42, 0.72, 1.00]);
            app.lblNoteTarget  = app.createMetricCard(pnlTelemetry, [0.345, 0.10, 0.31, 0.80], 'AUTO-TUNED NOTE', '--', [0.16, 0.88, 0.56]);
            app.lblCentsMetric = app.createMetricCard(pnlTelemetry, [0.675, 0.10, 0.31, 0.80], 'PITCH ERROR (BEFORE -> AFTER)', '--', txtPrimary);

            % 3 Diagnostic Axes (Pitch Contour on top as primary visual feedback)
            app.axPitch = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.345, 0.57, 0.625, 0.28]);
            app.axWave  = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.345, 0.31, 0.625, 0.19]);
            app.axSpec  = axes('Parent', app.fig, 'Units', 'normalized', 'Position', [0.345, 0.09, 0.625, 0.16]);

            app.styleEmptyAxes(app.axPitch, 'Auto-Tune Pitch Map (Input Pitch vs Stepped Auto-Tuned Output)');
            app.styleEmptyAxes(app.axWave,  'Audio Waveform');
            app.styleEmptyAxes(app.axSpec,  'Harmonic Frequency Spectrum');

            % Bottom Status Bar
            app.lblStatus = uicontrol('Parent', app.fig, 'Style', 'text', ...
                                      'String', 'Ready. Click Demo Vocal, Load WAV, or Record Mic to start.', ...
                                      'Units', 'normalized', 'Position', [0.015, 0.01, 0.97, 0.035], ...
                                      'BackgroundColor', [0.09, 0.10, 0.13], ...
                                      'ForegroundColor', [0.80, 0.85, 0.92], ...
                                      'FontName', 'Segoe UI', 'FontSize', 9.5, ...
                                      'HorizontalAlignment', 'left');
        end

        function lblVal = createMetricCard(~, parent, pos, titleStr, initVal, valCol)
            card = uipanel('Parent', parent, 'Units', 'normalized', 'Position', pos, ...
                           'BackgroundColor', [0.13, 0.15, 0.19], ...
                           'HighlightColor', [0.22, 0.25, 0.32], 'BorderType', 'line');
            uicontrol('Parent', card, 'Style', 'text', 'String', titleStr, ...
                      'Units', 'normalized', 'Position', [0.05, 0.56, 0.90, 0.36], ...
                      'BackgroundColor', [0.13, 0.15, 0.19], 'ForegroundColor', [0.60, 0.66, 0.74], ...
                      'FontName', 'Segoe UI', 'FontSize', 8, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left');
            lblVal = uicontrol('Parent', card, 'Style', 'text', 'String', initVal, ...
                               'Units', 'normalized', 'Position', [0.05, 0.08, 0.90, 0.48], ...
                               'BackgroundColor', [0.13, 0.15, 0.19], 'ForegroundColor', valCol, ...
                               'FontName', 'Segoe UI', 'FontSize', 11, 'FontWeight', 'bold', ...
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
                return;
            end

            cfg = app.buildConfigFromUI();
            [xCln, info] = pc_preprocess(app.xIn, app.fs, cfg);
            app.xRaw   = info.xRaw;
            app.xClean = xCln;

            if updatePlots
                t = (0:numel(app.xClean)-1)' / app.fs;
                pc_plot_waveform(app.axWave, t, app.xRaw, app.xClean, 'cleaned');
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

            % 1. Pitch Contour Axes (Top Hero Plot)
            pc_plot_pitch(app.axPitch, app.res);

            % 2. Waveform Axes
            pc_plot_waveform(app.axWave, app.res, 'corrected');

            % 3. Harmonic Spectrum Overlay Axes
            pc_plot_spectrum(app.axSpec, app.res, 'spectrum');
        end

        function updateTelemetryReadouts(app)
            if isempty(app.res) || app.res.info.silent
                set(app.lblNoteIn,      'String', 'Silent');
                set(app.lblNoteTarget,  'String', '--');
                set(app.lblCentsMetric, 'String', '--');
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

            if isfinite(m.meanAbsCentsIn) && isfinite(m.meanAbsCentsOut)
                set(app.lblCentsMetric, 'String', sprintf('%.1f cents  ->  %.1f cents', m.meanAbsCentsIn, m.meanAbsCentsOut));
            else
                set(app.lblCentsMetric, 'String', '--');
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
            % Generate an expressive 6-note vocal melody with pitch scoops,
            % glides, and vibrato that snaps into unmistakable Auto-Tune steps
            fsDemo = 44100;
            N = round(2.7 * fsDemo);
            t = (0:N-1)' / fsDemo;
            notesMidi = [60.25, 62.30, 64.25, 67.35, 64.30, 60.25]; % C4 - D4 - E4 - G4 - E4 - C4
            numNotes  = numel(notesMidi);
            segLen    = floor(N / numNotes);

            midiTrack = zeros(N, 1);
            for k = 1:numNotes
                idx = (k-1)*segLen + 1 : min(N, k*segLen);
                nSeg = numel(idx);
                tLocal = (0:nSeg-1)' / fsDemo;
                targetM = notesMidi(k);
                if k == 1
                    prevM = targetM - 1.2;
                else
                    prevM = notesMidi(k-1);
                end
                glideEnv = exp(-tLocal / 0.040);
                vibSemis = 0.22 * sin(2 * pi * 5.5 * t(idx));
                midiTrack(idx) = targetM - (targetM - prevM) * glideEnv + vibSemis;
            end
            f0Track = pc_midi2hz(midiTrack);
            xDemo = pc_synth_voice(fsDemo, f0Track);
            app.loadAudio(xDemo, fsDemo);
            app.process();
        end

        function onRecordAudio(app)
            dur = str2double(get(app.edtRecDur, 'String'));
            if isnan(dur) || dur < 0.5 || dur > 60
                dur = 4;
                set(app.edtRecDur, 'String', '4');
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
                app.setStatus(sprintf('Recording from microphone for %.1f seconds... Sing a melody now.', dur));
                drawnow;

                recordblocking(recObj, dur);
                xRec = getaudiodata(recObj, 'double');

                set(app.btnRecord, 'Enable', 'on', 'String', 'Record Mic');

                rawPeak = max(abs(xRec - mean(xRec)));
                if rawPeak < 1e-4
                    app.setStatus('Microphone signal is silent. Check Windows mic permissions or select another input device.');
                    return;
                end

                app.loadAudio(xRec, app.fs);
                app.process();
            catch ME
                set(app.btnRecord, 'Enable', 'on', 'String', 'Record Mic');
                app.setStatus(['Recording Error: ', ME.message]);
            end
        end

        function onAutoTuneParamChanged(app)
            if ~isempty(app.xIn)
                app.process();
            end
        end

        function onStrengthSlider(app)
            val = round(get(app.sldStrength, 'Value'));
            set(app.lblStrengthVal, 'String', sprintf('%d%%', val));
            if ~isempty(app.xIn)
                app.process();
            end
        end

        function onRetuneSlider(app)
            val = round(get(app.sldRetune, 'Value'));
            set(app.lblRetuneVal, 'String', sprintf('%d ms', val));
            if ~isempty(app.xIn)
                app.process();
            end
        end

        function onPresetHard(app)
            set(app.sldStrength,    'Value', 100);
            set(app.lblStrengthVal, 'String', '100%');
            set(app.sldRetune,      'Value', 0);
            set(app.lblRetuneVal,   'String', '0 ms');
            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Hard Auto-Tune mode selected (100% strength, 0 ms instant snap).');
            end
        end

        function onPresetNatural(app)
            set(app.sldStrength,    'Value', 80);
            set(app.lblStrengthVal, 'String', '80%');
            set(app.sldRetune,      'Value', 35);
            set(app.lblRetuneVal,   'String', '35 ms');
            if ~isempty(app.xIn)
                app.process();
            else
                app.setStatus('Natural Tune mode selected (80% strength, 35 ms smooth retune).');
            end
        end

        function onPlayAudio(app, whichSig)
            app.onStopAudio();

            switch whichSig
                case 'original'
                    if isempty(app.xRaw), return; end
                    sig = app.xRaw;
                    label = 'Original Audio';
                case 'cleaned'
                    if isempty(app.xClean), return; end
                    sig = app.xClean;
                    label = 'Cleaned Audio';
                case 'corrected'
                    if isempty(app.res) || isempty(app.res.y), return; end
                    sig = app.res.y;
                    label = 'Auto-Tuned Audio';
                otherwise
                    return;
            end

            pk = max(abs(sig));
            if pk > 0
                sigPlay = 0.92 * (sig / pk);
            else
                sigPlay = sig;
            end

            try
                app.player = audioplayer(sigPlay, app.fs);
                play(app.player);
                app.setStatus(sprintf('Playing %s (%.2f s)...', label, numel(sigPlay) / app.fs));
            catch ME
                app.setStatus(['Playback Error: ', ME.message]);
            end
        end

        function onStopAudio(app)
            if ~isempty(app.player)
                try
                    if isplaying(app.player)
                        stop(app.player);
                    end
                catch
                end
            end
        end

        function onExportAudio(app)
            if isempty(app.res) || isempty(app.res.y)
                app.setStatus('Process audio first before saving.');
                return;
            end

            [file, path] = uiputfile({'*.wav', 'WAV Audio File (*.wav)'}, ...
                                     'Save Auto-Tuned Audio', 'autotuned_vocal.wav');
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);

            try
                audiowrite(fullPath, app.res.y, app.fs);
                app.setStatus(['Saved Auto-Tuned WAV to: ', fullPath]);
            catch ME
                app.setStatus(['Export Error: ', ME.message]);
            end
        end

        function [names, ids] = getAudioInputDevices(~)
            names = {'Default Microphone'};
            ids   = -1;
            try
                info = audiodevinfo;
                if isfield(info, 'input') && ~isempty(info.input)
                    nDevs = numel(info.input);
                    names = cell(1, nDevs);
                    ids   = zeros(1, nDevs);
                    for k = 1:nDevs
                        rawName = info.input(k).Name;
                        rawName = char(rawName);
                        rawName(double(rawName) > 127) = [];
                        names{k} = strtrim(rawName);
                        ids(k)   = info.input(k).ID;
                    end
                end
            catch
            end
        end

        function setStatus(app, msg)
            if ~isempty(app.lblStatus) && isvalid(app.lblStatus)
                set(app.lblStatus, 'String', msg);
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
