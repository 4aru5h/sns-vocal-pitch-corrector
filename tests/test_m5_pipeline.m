function tests = test_m5_pipeline
tests = functiontests(localfunctions);
end

function testVocalCorrectionReduction(testCase)
fs = 44100;
N = fs; % 1 s
t = (0 : N - 1)' / fs;

% Synth at 220 * 2^(-0.4/12) with 5.5 Hz +-20 cent vibrato
f_base = 220 * 2^(-0.4 / 12);
vibratoCents = 20 * sin(2 * pi * 5.5 * t);
f0_inst = f_base * 2.^(vibratoCents / 1200);

x = pc_synth_voice(fs, f0_inst);

cfg = pc_default_config();
cfg.scale = 'chromatic';
cfg.strength = 1.0;
cfg.retuneMs = 0;

res = pc_process(x, fs, cfg);

testCase.verifyEqual(numel(res.y), numel(res.x));

% Input cents deviation re: nearest scale note (PROJECT_PLAN §3.2)
inContour = res.contour;
inDev = abs(inContour.centsDev(res.pitch.voiced));
validIn = inDev(~isnan(inDev));
testCase.verifyGreaterThan(numel(validIn), 0);
meanInputDev = mean(validIn);

% Output cents deviation re: nearest scale note on re-synthesized output
outContour = pc_correction_contour(res.pitchOut, cfg);
outDev = abs(outContour.centsDev(res.pitchOut.voiced));
validOut = outDev(~isnan(outDev));
testCase.verifyGreaterThan(numel(validOut), 0);
meanOutputDev = mean(validOut);

% Mean |cents deviation| reduced >= 70%
reduction = (meanInputDev - meanOutputDev) / meanInputDev;
testCase.verifyGreaterThanOrEqual(reduction, 0.70, ...
    sprintf('Cents deviation reduction is %.2f%% (expected >= 70%%)', reduction * 100));
end

function testZeroStrengthIdentity(testCase)
fs = 44100;
N = fs;
x = pc_synth_voice(fs, 220 * ones(N, 1));

cfg = pc_default_config();
cfg.strength = 0;

res = pc_process(x, fs, cfg);

err = res.x - res.y;
snr = 20 * log10(norm(res.x) / norm(err));
testCase.verifyGreaterThanOrEqual(snr, 60.0, ...
    sprintf('Strength 0 SNR is %.2f dB (expected >= 60 dB)', snr));
end

function testAudioReadWriteRoundTrip(testCase)
fs = 44100;
N = fs;
x = pc_synth_voice(fs, 220 * ones(N, 1));
cfg = pc_default_config();

res = pc_process(x, fs, cfg);

tempWav = fullfile(tempdir, 'sns_test_roundtrip.wav');
audiowrite(tempWav, res.y, fs);
[y_read, fs_read] = audioread(tempWav);

testCase.verifyEqual(fs_read, fs);
testCase.verifyEqual(numel(y_read), numel(res.y));
testCase.verifyEqual(y_read, res.y, 'AbsTol', 1e-4);

if exist(tempWav, 'file')
    delete(tempWav);
end
end

function testSilentInput(testCase)
fs = 44100;
x_silent = zeros(fs, 1);
cfg = pc_default_config();

res = pc_process(x_silent, fs, cfg);

testCase.verifyTrue(res.info.silent);
testCase.verifyEqual(max(abs(res.y)), 0);
testCase.verifyEqual(numel(res.y), numel(x_silent));
end
