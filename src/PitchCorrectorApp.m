function app = PitchCorrectorApp(varargin)
% PITCHCORRECTORAPP Programmatic uifigure GUI for vocal pitch correction.
%   app = PitchCorrectorApp() launches the pitch correction application.
%   app = PitchCorrectorApp('Visible', 'off') launches headlessly for testing.
%
%   Returned struct exposes handles and methods for testing:
%       app.fig          - UIFigure handle
%       app.axWave       - Waveform UIAxes handle
%       app.axPitch      - Pitch contour UIAxes handle
%       app.axSpec       - Spectrogram UIAxes handle
%       app.loadAudio    - Function: app.loadAudio(x, fs)
%       app.process      - Function: app.process()
%       app.getResult    - Function: res = app.getResult()

p_vis = 'on';
for idx = 1:2:numel(varargin)
    if strcmpi(varargin{idx}, 'Visible')
        p_vis = varargin{idx+1};
    end
end

fig = uifigure('Name', 'AutoTune Vocal Pitch Corrector (SNS)', ...
               'Position', [100, 100, 1200, 750], ...
               'Visible', p_vis);

% State variables
audioData.xIn = [];
audioData.fs = 44100;
audioData.res = [];
audioData.player = [];
audioData.recorder = [];

% Main 2-row layout: Top Controls, Bottom Visualizations
mainGrid = uigridlayout(fig, [2, 1]);
mainGrid.RowHeight = {160, '1x'};
mainGrid.Padding = [10, 10, 10, 10];

% Controls Panel
ctrlPanel = uipanel(mainGrid, 'Title', 'Control Panel', 'FontWeight', 'bold');
ctrlGrid = uigridlayout(ctrlPanel, [3, 6]);
ctrlGrid.RowHeight = {35, 35, 35};
ctrlGrid.ColumnWidth = {'1x', '1x', '1x', '1.2x', '1.2x', '1.2x'};

% Row 1 Controls: Load, Record, Duration, Key, Scale, Process
btnLoad = uibutton(ctrlGrid, 'Text', 'Load WAV...', 'ButtonPushedFcn', @onLoadWav);
btnRecord = uibutton(ctrlGrid, 'Text', 'Record Mic', 'ButtonPushedFcn', @onRecord);

durPanel = uipanel(ctrlGrid, 'BorderType', 'none');
durGrid = uigridlayout(durPanel, [1, 2]);
durGrid.Padding = [0 0 0 0];
uilabel(durGrid, 'Text', 'Dur (s):', 'HorizontalAlignment', 'right');
numDuration = uieditfield(durGrid, 'numeric', 'Value', 3, 'Limits', [0.5, 30]);

dropKey = uidropdown(ctrlGrid, 'Items', {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}, 'Value', 'C');
dropScale = uidropdown(ctrlGrid, 'Items', {'chromatic', 'major', 'minor'}, 'Value', 'chromatic');
btnProcess = uibutton(ctrlGrid, 'Text', 'Process Pitch', 'FontWeight', 'bold', 'BackgroundColor', [0.15 0.65 0.25], 'FontColor', 'w', 'ButtonPushedFcn', @onProcess);

% Row 2 Controls: Sliders and Labels
lblStrength = uilabel(ctrlGrid, 'Text', 'Strength: 100%', 'HorizontalAlignment', 'right');
sldStrength = uislider(ctrlGrid, 'Limits', [0, 100], 'Value', 100, 'ValueChangedFcn', @(s,e) set(lblStrength, 'Text', sprintf('Strength: %d%%', round(s.Value))));

lblRetune = uilabel(ctrlGrid, 'Text', 'Retune: 50 ms', 'HorizontalAlignment', 'right');
sldRetune = uislider(ctrlGrid, 'Limits', [0, 400], 'Value', 50, 'ValueChangedFcn', @(s,e) set(lblRetune, 'Text', sprintf('Retune: %d ms', round(s.Value))));

dropSpec = uidropdown(ctrlGrid, 'Items', {'corrected', 'original'}, 'Value', 'corrected', 'ValueChangedFcn', @onSpecToggle);
btnExport = uibutton(ctrlGrid, 'Text', 'Export WAV...', 'ButtonPushedFcn', @onExportWav);

% Row 3 Controls: Playback & Status
btnPlayOrig = uibutton(ctrlGrid, 'Text', 'Play Original', 'ButtonPushedFcn', @onPlayOrig);
btnPlayCorr = uibutton(ctrlGrid, 'Text', 'Play Corrected', 'ButtonPushedFcn', @onPlayCorr);
btnStop = uibutton(ctrlGrid, 'Text', 'Stop Audio', 'ButtonPushedFcn', @onStopAudio);

lblStatus = uilabel(ctrlGrid, 'Text', 'Status: Ready. Load a WAV file or record to begin.', 'FontWeight', 'bold');
lblStatus.Layout.Column = [4, 6];

% Visualisation Grid: 3 Axes
visGrid = uigridlayout(mainGrid, [1, 3]);
visGrid.ColumnWidth = {'1x', '1x', '1x'};
visGrid.Padding = [5, 5, 5, 5];

axWave = uiaxes(visGrid);
title(axWave, 'Waveform (Original vs Corrected)');

axPitch = uiaxes(visGrid);
title(axPitch, 'Pitch Contours');

axSpec = uiaxes(visGrid);
title(axSpec, 'Spectrogram');

% Callback Implementations
    function onLoadWav(~, ~)
        try
            [file, path] = uigetfile({'*.wav', 'WAV Audio Files (*.wav)'}, 'Select Input WAV');
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            [audioData.xIn, audioData.fs] = audioread(fullPath);
            lblStatus.Text = sprintf('Status: Loaded "%s" (%d samples, %d Hz).', file, numel(audioData.xIn), audioData.fs);
        catch ME
            uialert(fig, ME.message, 'File Load Error');
        end
    end

    function onRecord(~, ~)
        try
            dur = numDuration.Value;
            lblStatus.Text = sprintf('Status: Recording for %.1f s...', dur);
            drawnow;
            rec = audiorecorder(44100, 16, 1);
            recordblocking(rec, dur);
            audioData.xIn = getaudiodata(rec);
            audioData.fs = 44100;
            lblStatus.Text = sprintf('Status: Recorded %.1f s at 44.1 kHz.', dur);
        catch ME
            uialert(fig, ME.message, 'Recording Error');
        end
    end

    function onProcess(~, ~)
        try
            if isempty(audioData.xIn)
                uialert(fig, 'No audio loaded. Load a WAV file or record first.', 'No Audio');
                return;
            end
            lblStatus.Text = 'Status: Processing vocal correction...';
            drawnow;
            
            cfg = pc_default_config();
            cfg.key = dropKey.Value;
            cfg.scale = dropScale.Value;
            cfg.strength = sldStrength.Value / 100;
            cfg.retuneMs = sldRetune.Value;
            
            audioData.res = pc_process(audioData.xIn, audioData.fs, cfg);
            
            pc_plot_waveform(axWave, audioData.res);
            pc_plot_pitch(axPitch, audioData.res);
            pc_plot_spectrum(axSpec, audioData.res, dropSpec.Value);
            
            lblStatus.Text = sprintf('Status: Complete! Key %s %s, Strength %.0f%%, Retune %d ms.', ...
                cfg.key, cfg.scale, cfg.strength * 100, round(cfg.retuneMs));
        catch ME
            uialert(fig, ME.message, 'Processing Error');
        end
    end

    function onSpecToggle(~, ~)
        if ~isempty(audioData.res)
            pc_plot_spectrum(axSpec, audioData.res, dropSpec.Value);
        end
    end

    function onPlayOrig(~, ~)
        try
            if isempty(audioData.xIn)
                return;
            end
            onStopAudio();
            audioData.player = audioplayer(audioData.xIn, audioData.fs);
            play(audioData.player);
            lblStatus.Text = 'Status: Playing original audio...';
        catch ME
            uialert(fig, ME.message, 'Playback Error');
        end
    end

    function onPlayCorr(~, ~)
        try
            if isempty(audioData.res) || isempty(audioData.res.y)
                uialert(fig, 'Process audio before playing corrected output.', 'Not Processed');
                return;
            end
            onStopAudio();
            audioData.player = audioplayer(audioData.res.y, audioData.res.fs);
            play(audioData.player);
            lblStatus.Text = 'Status: Playing pitch-corrected audio...';
        catch ME
            uialert(fig, ME.message, 'Playback Error');
        end
    end

    function onStopAudio(~, ~)
        if ~isempty(audioData.player) && isplaying(audioData.player)
            stop(audioData.player);
        end
        lblStatus.Text = 'Status: Audio stopped.';
    end

    function onExportWav(~, ~)
        try
            if isempty(audioData.res) || isempty(audioData.res.y)
                uialert(fig, 'No corrected audio to export. Process audio first.', 'Export Error');
                return;
            end
            [file, path] = uiputfile('*.wav', 'Save Corrected WAV', 'corrected_vocal.wav');
            if isequal(file, 0), return; end
            audiowrite(fullfile(path, file), audioData.res.y, audioData.res.fs);
            lblStatus.Text = sprintf('Status: Exported "%s".', file);
        catch ME
            uialert(fig, ME.message, 'Export Error');
        end
    end

% Programmatic testing interface
app.fig = fig;
app.axWave = axWave;
app.axPitch = axPitch;
app.axSpec = axSpec;
app.statusLabel = lblStatus;

app.loadAudio = @loadAudioData;
    function loadAudioData(x, fs)
        audioData.xIn = x;
        audioData.fs = fs;
        lblStatus.Text = sprintf('Status: Audio loaded (%d samples, %d Hz).', numel(x), fs);
    end

app.process = @() onProcess([], []);
app.getResult = @getCurrentResult;
    function r = getCurrentResult()
        r = audioData.res;
    end
end
