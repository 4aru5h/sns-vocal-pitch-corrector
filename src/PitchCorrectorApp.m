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
               'Position', [100, 80, 1220, 780], ...
               'Visible', p_vis);

% State variables
audioData.xIn = [];
audioData.fs = 44100;
audioData.res = [];
audioData.player = [];
audioData.recorder = [];

% Main 2-row layout: Top Controls, Bottom Visualizations
mainGrid = uigridlayout(fig, [2, 1]);
mainGrid.RowHeight = {190, '1x'};
mainGrid.Padding = [10, 10, 10, 10];

% Controls Panel
ctrlPanel = uipanel(mainGrid, 'Title', 'Control Panel & Audio I/O', 'FontWeight', 'bold');
ctrlGrid = uigridlayout(ctrlPanel, [4, 6]);
ctrlGrid.RowHeight = {32, 32, 32, 28};
ctrlGrid.ColumnWidth = {'1x', '1.2x', '0.8x', '1.2x', '1.2x', '1.2x'};

% Query audio input devices
devNames = {'[Default] Windows Sound Capture'};
devIDs = [-1];
try
    devs = audiodevinfo;
    if isstruct(devs) && isfield(devs, 'input') && ~isempty(devs.input)
        for k = 1:numel(devs.input)
            devNames{end+1} = sprintf('[%d] %s', devs.input(k).ID, devs.input(k).Name);
            devIDs(end+1) = devs.input(k).ID;
        end
    end
catch
    % Fallback to default
end

% Row 1 Controls: Audio Input selection, Load WAV, Record, Duration, Process
btnLoad = uibutton(ctrlGrid, 'Text', 'Load WAV...', 'FontWeight', 'bold', 'ButtonPushedFcn', @onLoadWav);

dropDevice = uidropdown(ctrlGrid, 'Items', devNames, 'Value', devNames{1});
dropDevice.Tooltip = 'Select your microphone input device';

durPanel = uipanel(ctrlGrid, 'BorderType', 'none');
durGrid = uigridlayout(durPanel, [1, 2]);
durGrid.Padding = [0 0 0 0];
uilabel(durGrid, 'Text', 'Dur (s):', 'HorizontalAlignment', 'right');
numDuration = uieditfield(durGrid, 'numeric', 'Value', 3, 'Limits', [0.5, 30]);

btnRecord = uibutton(ctrlGrid, 'Text', 'Record Mic', 'FontWeight', 'bold', ...
                     'BackgroundColor', [0.85 0.25 0.2], 'FontColor', 'w', ...
                     'ButtonPushedFcn', @onRecord);

btnProcess = uibutton(ctrlGrid, 'Text', 'Process Pitch', 'FontWeight', 'bold', ...
                      'BackgroundColor', [0.15 0.65 0.25], 'FontColor', 'w', ...
                      'ButtonPushedFcn', @onProcess);
btnProcess.Layout.Column = [5, 6];

% Row 2 Controls: Musical parameters (Key, Scale, Strength, Retune)
uilabel(ctrlGrid, 'Text', 'Musical Key:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
dropKey = uidropdown(ctrlGrid, 'Items', {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}, 'Value', 'C');

uilabel(ctrlGrid, 'Text', 'Target Scale:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
% Default to major so vocal notes snap to distinct scale intervals rather than chromatic micro-steps
dropScale = uidropdown(ctrlGrid, 'Items', {'major', 'minor', 'pentatonic', 'chromatic'}, 'Value', 'major');

lblStrength = uilabel(ctrlGrid, 'Text', 'Strength: 100%', 'HorizontalAlignment', 'right');
sldStrength = uislider(ctrlGrid, 'Limits', [0, 100], 'Value', 100, ...
    'ValueChangedFcn', @(s,e) set(lblStrength, 'Text', sprintf('Strength: %d%%', round(s.Value))));

% Row 3 Controls: Retune slider (default 0 ms for instant hard snap), Playback, Export
lblRetune = uilabel(ctrlGrid, 'Text', 'Retune: 0 ms (Hard)', 'HorizontalAlignment', 'right');
sldRetune = uislider(ctrlGrid, 'Limits', [0, 400], 'Value', 0, ...
    'ValueChangedFcn', @onRetuneChanged);

btnPlayOrig = uibutton(ctrlGrid, 'Text', 'Play Original', 'FontWeight', 'bold', 'ButtonPushedFcn', @onPlayOrig);
btnPlayCorr = uibutton(ctrlGrid, 'Text', 'Play Corrected', 'FontWeight', 'bold', ...
                       'BackgroundColor', [0.2 0.5 0.8], 'FontColor', 'w', ...
                       'ButtonPushedFcn', @onPlayCorr);
btnStop = uibutton(ctrlGrid, 'Text', 'Stop Audio', 'ButtonPushedFcn', @onStopAudio);

btnExport = uibutton(ctrlGrid, 'Text', 'Export WAV...', 'ButtonPushedFcn', @onExportWav);

% Row 4: Presets, Spectrogram toggle & Status
btnTPain = uibutton(ctrlGrid, 'Text', '⚡ Hard T-Pain Preset', 'FontWeight', 'bold', ...
                    'BackgroundColor', [0.85 0.45 0.1], 'FontColor', 'w', ...
                    'ButtonPushedFcn', @onPresetTPain);

btnNatural = uibutton(ctrlGrid, 'Text', 'Natural Pop Preset', ...
                      'ButtonPushedFcn', @onPresetNatural);

lblStatus = uilabel(ctrlGrid, 'Text', 'Status: Ready. Load a WAV file or click Record Mic to begin.', 'FontWeight', 'bold');
lblStatus.Layout.Column = [3, 5];

dropSpec = uidropdown(ctrlGrid, 'Items', {'corrected', 'original'}, 'Value', 'corrected', ...
                       'Tooltip', 'Spectrogram view toggle', 'ValueChangedFcn', @onSpecToggle);

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

% Helper to get selected device ID
    function devId = getSelectedDeviceId()
        devId = -1;
        selIdx = find(strcmp(dropDevice.Value, devNames), 1);
        if ~isempty(selIdx) && selIdx <= numel(devIDs)
            devId = devIDs(selIdx);
        end
    end

% Callback Implementations
    function onLoadWav(~, ~)
        try
            [file, path] = uigetfile({'*.wav', 'WAV Audio Files (*.wav)'}, 'Select Input WAV');
            if isequal(file, 0), return; end
            fullPath = fullfile(path, file);
            [audioData.xIn, audioData.fs] = audioread(fullPath);
            peakVal = max(abs(audioData.xIn(:)));
            lblStatus.Text = sprintf('Status: Loaded "%s" (%d samples, %d Hz, peak = %.3f).', file, size(audioData.xIn, 1), audioData.fs, peakVal);
            
            % Plot waveform immediately
            cla(axWave);
            t_ax = (0 : size(audioData.xIn, 1) - 1)' / audioData.fs;
            plot(axWave, t_ax, audioData.xIn(:, 1), 'Color', [0.2 0.4 0.8], 'LineWidth', 1.0);
            title(axWave, sprintf('Loaded Audio: %s (Peak = %.3f)', file, peakVal));
            xlabel(axWave, 'Time (s)'); ylabel(axWave, 'Amplitude'); grid(axWave, 'on');
        catch ME
            uialert(fig, ME.message, 'File Load Error');
        end
    end

    function onRecord(~, ~)
        try
            dur = numDuration.Value;
            lblStatus.Text = sprintf('Status: RECORDING NOW (%.1f s)... Please sing / speak into your microphone!', dur);
            lblStatus.FontColor = [0.85 0.15 0.1];
            drawnow;
            
            devId = getSelectedDeviceId();
            if devId >= 0
                rec = audiorecorder(44100, 16, 1, devId);
            else
                rec = audiorecorder(44100, 16, 1);
            end
            
            recordblocking(rec, dur);
            audioData.xIn = getaudiodata(rec);
            audioData.fs = 44100;
            lblStatus.FontColor = [0 0 0];
            
            recPeak = max(abs(audioData.xIn));
            
            % Immediately render waveform on axWave so user gets visual feedback
            cla(axWave);
            t_ax = (0 : numel(audioData.xIn) - 1)' / audioData.fs;
            plot(axWave, t_ax, audioData.xIn, 'Color', [0.2 0.4 0.8], 'LineWidth', 1.0);
            title(axWave, sprintf('Recorded Input Waveform (Peak = %.4f)', recPeak));
            xlabel(axWave, 'Time (s)'); ylabel(axWave, 'Amplitude'); grid(axWave, 'on');
            ylim(axWave, [-max(0.05, recPeak * 1.2), max(0.05, recPeak * 1.2)]);
            
            if recPeak < 0.005
                lblStatus.Text = sprintf('Status: Warning: Input is near silent (Peak = %.5f). Check microphone mute / volume.', recPeak);
                uialert(fig, sprintf(['Your microphone recorded near-silence (Peak = %.6f).\n\n' ...
                    'Common reasons:\n' ...
                    '1. Hardware/Fn mute key: Check if your keyboard microphone mute key (e.g. F4 / Fn+F4) is active.\n' ...
                    '2. Low Windows input volume: Open Windows Sound Settings and increase microphone volume.\n' ...
                    '3. Wrong device: Try picking "Microphone Array" explicitly from the device dropdown.\n\n' ...
                    'You can also load any audio file using "Load WAV..." to test pitch correction immediately.'], ...
                    recPeak), 'Low Microphone Signal', 'Icon', 'warning');
            else
                lblStatus.Text = sprintf('Status: Recorded %.1f s successfully (Peak = %.2f - Good level!). Click "Process Pitch" to tune.', dur, recPeak);
            end
        catch ME
            lblStatus.FontColor = [0 0 0];
            uialert(fig, ME.message, 'Recording Error');
        end
    end

    function onRetuneChanged(s, ~)
        val = round(s.Value);
        if val == 0
            set(lblRetune, 'Text', 'Retune: 0 ms (Hard)');
        else
            set(lblRetune, 'Text', sprintf('Retune: %d ms', val));
        end
    end

    function onPresetTPain(~, ~)
        sldRetune.Value = 0;
        set(lblRetune, 'Text', 'Retune: 0 ms (Hard)');
        sldStrength.Value = 100;
        set(lblStrength, 'Text', 'Strength: 100%');
        if strcmp(dropScale.Value, 'chromatic')
            dropScale.Value = 'major';
        end
        lblStatus.Text = 'Status: Preset loaded: Hard T-Pain (Retune 0ms, Strength 100%, Major Scale). Click "Process Pitch"!';
    end

    function onPresetNatural(~, ~)
        sldRetune.Value = 60;
        set(lblRetune, 'Text', 'Retune: 60 ms');
        sldStrength.Value = 85;
        set(lblStrength, 'Text', 'Strength: 85%');
        lblStatus.Text = 'Status: Preset loaded: Natural Pop (Retune 60ms, Strength 85%). Click "Process Pitch"!';
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
            % Allow full melodic shifts across scale intervals
            cfg.maxShiftSemis = 6.0;
            
            audioData.res = pc_process(audioData.xIn, audioData.fs, cfg);
            
            pc_plot_waveform(axWave, audioData.res);
            pc_plot_pitch(axPitch, audioData.res);
            pc_plot_spectrum(axSpec, audioData.res, dropSpec.Value);
            
            if audioData.res.info.silent
                lblStatus.Text = 'Status: Input is silent or below noise floor. Output is muted.';
                uialert(fig, 'The audio input was detected as silence or below the noise floor (-46 dBFS). Output is muted to avoid amplifying noise.', 'Silent Input', 'Icon', 'info');
            else
                lblStatus.Text = sprintf('Status: Complete! Key %s %s, Strength %.0f%%, Retune %d ms.', ...
                    cfg.key, cfg.scale, cfg.strength * 100, round(cfg.retuneMs));
            end
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
            playSig = audioData.xIn;
            if size(playSig, 2) > 1
                playSig = mean(playSig, 2);
            end
            p = max(abs(playSig));
            if p > 0.0001
                % Boost playback volume so quiet microphone recordings are clearly audible
                playSig = playSig * (0.85 / p);
            end
            audioData.player = audioplayer(playSig, audioData.fs);
            play(audioData.player);
            lblStatus.Text = 'Status: Playing original audio (normalized for clear audibility)...';
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
            if audioData.res.info.silent
                lblStatus.Text = 'Status: Corrected output is silent (input audio was below noise floor).';
                return;
            end
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
