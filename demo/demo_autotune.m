% DEMO_AUTOTUNE End-to-end demonstration of vocal pitch correction.
%   Synthesises an expressive, detuned vocal phrase, processes it through
%   the pc_process pipeline, saves before/after WAVs to demo/out/, and
%   exports a high-resolution comparison figure.

fprintf('=== Vocal AutoTune Pitch Correction Demonstration ===\n');

% Set up paths
repoDir = fileparts(fileparts(mfilename('fullpath')));
srcDir = fullfile(repoDir, 'src');
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir, 'dir'), mkdir(outDir); end
addpath(srcDir);

% 1. Synthesise a musical phrase with intentional detuning & vibrato
fs = 44100;
noteDurs = [0.6, 0.6, 0.6, 0.8]; % seconds per note
% Nominal targets in C major: C4 (60), E4 (64), G4 (67), A4 (69)
targets = [60, 64, 67, 69];
% Deliberate vocal pitch offsets in semitones (flat/sharp singing)
offsets = [-0.35, +0.25, -0.40, +0.15];

f0_full = [];
for k = 1:numel(targets)
    nSamples = round(noteDurs(k) * fs);
    t_note = (0 : nSamples - 1)' / fs;
    f_center = pc_midi2hz(targets(k) + offsets(k));
    % 5.5 Hz vibrato with 18-cent depth
    vibrato = 18 * sin(2 * pi * 5.5 * t_note);
    f_track = f_center * 2.^(vibrato / 1200);
    f0_full = [f0_full; f_track]; %#ok<AGROW>
end

fprintf('Synthesising test vocal phrase (%.1f s at %d Hz)...\n', numel(f0_full)/fs, fs);
xIn = pc_synth_voice(fs, f0_full);

% 2. Configure AutoTune processing pipeline
cfg = pc_default_config();
cfg.key = 'C';
cfg.scale = 'major';
cfg.strength = 1.0;     % 100% pitch correction
cfg.retuneMs = 25;      % Fast retune speed

fprintf('Running pc_process (Key: %s %s, Strength: %.0f%%, Retune: %d ms)...\n', ...
    cfg.key, cfg.scale, cfg.strength * 100, round(cfg.retuneMs));
res = pc_process(xIn, fs, cfg);

% 3. Save WAV files
origWavPath = fullfile(outDir, 'original.wav');
corrWavPath = fullfile(outDir, 'corrected.wav');
audiowrite(origWavPath, res.x, fs);
audiowrite(corrWavPath, res.y, fs);
fprintf('Saved audio:\n  - %s\n  - %s\n', origWavPath, corrWavPath);

% 4. Render and export figures
fig = figure('Name', 'AutoTune Demo Comparison', ...
             'Position', [100, 100, 1100, 800], ...
             'Visible', 'off');

ax1 = subplot(3, 1, 1, 'Parent', fig);
pc_plot_waveform(ax1, res);

ax2 = subplot(3, 1, 2, 'Parent', fig);
pc_plot_pitch(ax2, res);

ax3 = subplot(3, 1, 3, 'Parent', fig);
pc_plot_spectrum(ax3, res, 'corrected');

pngPath = fullfile(outDir, 'autotune_demo.png');
try
    exportgraphics(fig, pngPath, 'Resolution', 200);
catch
    saveas(fig, pngPath);
end
delete(fig);
fprintf('Saved visualisation plot to:\n  - %s\n', pngPath);

fprintf('Demonstration finished successfully!\n');
