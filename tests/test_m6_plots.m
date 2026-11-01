function tests = test_m6_plots
tests = functiontests(localfunctions);
end

function testStftAccuracy(testCase)
fs = 44100;
N = 1024;
hop = 256;
t = (0 : fs - 1)' / fs;
x = sin(2 * pi * 440 * t);

[S, f, t_stft] = pc_stft(x, fs, N, hop);

testCase.verifyEqual(size(S, 1), floor(N / 2) + 1);
testCase.verifyEqual(numel(f), floor(N / 2) + 1);

% Verify column matches abs(fft(frame .* w)) within 1e-10 relative error
w = pc_hann(N);
frame1 = x(1 : N) .* w;
expectedCol1 = abs(fft(frame1, N));
expectedCol1 = expectedCol1(1 : floor(N / 2) + 1);

relErr = norm(S(:, 1) - expectedCol1) / norm(expectedCol1);
testCase.verifyLessThan(relErr, 1e-10);
end

function testPlotFunctionsHeadless(testCase)
fs = 44100;
N = fs;
x = pc_synth_voice(fs, 220 * ones(N, 1));
cfg = pc_default_config();
res = pc_process(x, fs, cfg);

% Create invisible figure for batch rendering
fig = figure('Visible', 'off');
c1 = onCleanup(@() delete(fig));

ax1 = subplot(3, 1, 1, 'Parent', fig);
pc_plot_waveform(ax1, res);
testCase.verifyNotEmpty(ax1.Children);

ax2 = subplot(3, 1, 2, 'Parent', fig);
pc_plot_pitch(ax2, res);
testCase.verifyNotEmpty(ax2.Children);

ax3 = subplot(3, 1, 3, 'Parent', fig);
pc_plot_spectrum(ax3, res, 'corrected');
testCase.verifyNotEmpty(ax3.Children);

% Also test 'original' spectrogram
pc_plot_spectrum(ax3, res, 'original');
testCase.verifyNotEmpty(ax3.Children);
end
