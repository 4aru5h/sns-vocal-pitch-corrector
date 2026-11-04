% DEMO_AUTOTUNE End-to-end demonstration of vocal pitch correction.
%   Synthesises an expressive vocal melody with pitch scoops, glides, and
%   vibrato, processes it through the pc_process Auto-Tune pipeline (YIN pitch
%   detection, scale quantization, and glottal-locked TD-PSOLA resynthesis),
%   saves original/cleaned/corrected WAVs to demo/out/, and exports a
%   high-resolution comparison figure.

fprintf('=== Vocal Auto-Tune Pitch Correction Demonstration ===\n');

% Set up paths
repoDir = fileparts(fileparts(mfilename('fullpath')));
srcDir = fullfile(repoDir, 'src');
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir, 'dir'), mkdir(outDir); end
addpath(srcDir);

% 1. Synthesise an expressive 6-note vocal melody with pitch scoops, slides & vibrato
fs = 44100;
N = round(2.7 * fs);
t = (0:N-1)' / fs;

% 6-note C-major vocal run: C4 -> D4 -> E4 -> G4 -> E4 -> C4
% With intentional flat/sharp vocal offsets and smooth pitch glides between notes
notesMidi = [59.65, 62.30, 63.70, 67.35, 64.30, 60.25];
numNotes  = numel(notesMidi);
segLen    = floor(N / numNotes);

midiTrack = zeros(N, 1);
for k = 1:numNotes
    idx = (k-1)*segLen + 1 : min(N, k*segLen);
    nSeg = numel(idx);
    tLocal = (0:nSeg-1)' / fs;
    targetM = notesMidi(k);
    if k == 1
        prevM = targetM - 1.2; % Initial vocal scoop up into first note
    else
        prevM = notesMidi(k-1);
    end
    % Smooth vocal glide (portamento) over first 90 ms of each note + 5.5 Hz vibrato
    glideEnv = exp(-tLocal / 0.040);
    vibratoSemis = 0.22 * sin(2 * pi * 5.5 * t(idx));
    midiTrack(idx) = targetM - (targetM - prevM) * glideEnv + vibratoSemis;
end
f0_full = pc_midi2hz(midiTrack);

fprintf('Synthesising expressive vocal phrase (%.1f s at %d Hz)...\n', N/fs, fs);
rng(42);
xIn = pc_synth_voice(fs, f0_full);

% 2. Configure Hard Auto-Tune processing pipeline (0 ms retune speed, 100% strength)
cfg = pc_default_config();
cfg.key = 'C';
cfg.scale = 'major';
cfg.strength = 1.0;     % 100% pitch correction
cfg.retuneMs = 0;       % 0 ms hard Auto-Tune snap
cfg.denoiseEnable = false;

fprintf('Running pc_process (Key: %s %s, Strength: %.0f%%, Retune: %d ms)...\n', ...
    cfg.key, cfg.scale, cfg.strength * 100, round(cfg.retuneMs));
res = pc_process(xIn, fs, cfg);

fprintf('Metrics: Input Pitch Error = %.2f cents -> Auto-Tuned Output Error = %.2f cents\n', ...
    res.metrics.meanAbsCentsIn, res.metrics.meanAbsCentsOut);

% 3. Save WAV files (Original Raw, Cleaned Preprocessed, and Pitch-Corrected)
origWavPath  = fullfile(outDir, 'original.wav');
cleanWavPath = fullfile(outDir, 'cleaned.wav');
corrWavPath  = fullfile(outDir, 'corrected.wav');
audiowrite(origWavPath,  res.xRaw, fs);
audiowrite(cleanWavPath, res.x,    fs);
audiowrite(corrWavPath,  res.y,    fs);
fprintf('Saved audio:\n  - %s\n  - %s\n  - %s\n', origWavPath, cleanWavPath, corrWavPath);

% 4. Render and export dark-studio diagnostic figure
fig = figure('Name', 'AutoTune Demo Comparison', ...
             'Color', [0.07, 0.08, 0.10], ...
             'InvertHardcopy', 'off', ...
             'Position', [100, 100, 1150, 820], ...
             'Visible', 'off');

ax1 = subplot(3, 1, 1, 'Parent', fig);
pc_plot_pitch(ax1, res);

ax2 = subplot(3, 1, 2, 'Parent', fig);
pc_plot_waveform(ax2, res, 'corrected');

ax3 = subplot(3, 1, 3, 'Parent', fig);
pc_plot_spectrum(ax3, res, 'corrected');

pngPath = fullfile(outDir, 'autotune_demo.png');
try
    exportgraphics(fig, pngPath, 'Resolution', 200, 'BackgroundColor', [0.07, 0.08, 0.10]);
catch
    saveas(fig, pngPath);
end
delete(fig);
fprintf('Saved visualisation plot to:\n  - %s\n', pngPath);

fprintf('Demonstration finished successfully!\n');
