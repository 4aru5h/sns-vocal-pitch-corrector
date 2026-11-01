function tests = test_m2_yin
tests = functiontests(localfunctions);
end

function testPreprocess(testCase)
fs = 44100;
N = fs;
t = (0:N-1)' / fs;
tone = sin(2 * pi * 440 * t);

% Stereo input handling
toneStereo = [tone, tone * 0.8];
[xMono, info] = pc_preprocess(toneStereo, fs);
testCase.verifyTrue(iscolumn(xMono));
testCase.verifyEqual(size(xMono), [N, 1]);
testCase.verifyFalse(info.silent);
testCase.verifyEqual(max(abs(xMono)), 0.95, 'AbsTol', 1e-12);

% Mono row vector input handling
toneRow = tone';
[xFromRow, ~] = pc_preprocess(toneRow, fs);
testCase.verifyTrue(iscolumn(xFromRow));
testCase.verifyEqual(size(xFromRow), [N, 1]);

% DC removal check
toneWithDC = tone + 2.5;
[xNoDC, ~] = pc_preprocess(toneWithDC, fs);
testCase.verifyEqual(mean(xNoDC), 0, 'AbsTol', 1e-12);

% Silence handling
xSilent = zeros(N, 1);
[xOutSilent, infoSilent] = pc_preprocess(xSilent, fs);
testCase.verifyTrue(infoSilent.silent);
testCase.verifyEqual(infoSilent.gain, 1.0);
testCase.verifyEqual(max(abs(xOutSilent)), 0);

% Errors on invalid inputs
testCase.verifyError(@() pc_preprocess(tone, 4000), ?MException); % fs < 8000
testCase.verifyError(@() pc_preprocess(tone(1:100), fs), ?MException); % < 0.1 s
end

function testSyntheticTones(testCase)
fs = 44100;
N = fs;
t = (0:N-1)' / fs;
cfg = pc_default_config();

testFreqs = [100, 220, 440, 880];

for k = 1:numel(testFreqs)
    f_true = testFreqs(k);
    x = sin(2 * pi * f_true * t);
    p = pc_yin(x, fs, cfg);
    
    % Voiced fraction >= 95%
    voicedFraction = sum(p.voiced) / numel(p.voiced);
    testCase.verifyGreaterThanOrEqual(voicedFraction, 0.95, ...
        sprintf('Voiced fraction for %d Hz tone below 95%%: %.2f', f_true, voicedFraction));
    
    % Median f0 error < 5 cents
    f0_median = median(p.f0, 'omitnan');
    centsErr = 1200 * abs(log2(f0_median / f_true));
    testCase.verifyLessThan(centsErr, 5.0, ...
        sprintf('Median f0 error for %d Hz tone exceeds 5 cents: %.2f', f_true, centsErr));
end
end

function testLinearGlide(testCase)
fs = 44100;
N = fs;
t = (0:N-1)' / fs;
cfg = pc_default_config();

% 200 Hz -> 400 Hz linear chirp over 1 s
% phi(t) = 2*pi*(200*t + 0.5*200*t^2)
phi = 2 * pi * (200 * t + 100 * t.^2);
x = sin(phi);

p = pc_yin(x, fs, cfg);

% Instantaneous true frequency at frame center timestamps
f_true = 200 + 200 * p.t(p.voiced);
f0_est = p.f0(p.voiced);

centsErr = 1200 * abs(log2(f0_est ./ f_true));
medianErr = median(centsErr);

testCase.verifyLessThan(medianErr, 15.0, ...
    sprintf('Linear glide median cents error exceeds 15 cents: %.2f', medianErr));
end

function testWhiteNoiseAndSilence(testCase)
fs = 44100;
N = fs;
cfg = pc_default_config();

% White noise: voiced frames <= 5%
rng(42);
xNoise = randn(N, 1);
xNoise = xNoise / max(abs(xNoise)) * 0.95;
pNoise = pc_yin(xNoise, fs, cfg);

noiseVoicedFraction = sum(pNoise.voiced) / numel(pNoise.voiced);
testCase.verifyLessThanOrEqual(noiseVoicedFraction, 0.05, ...
    sprintf('Noise voiced fraction exceeds 5%%: %.2f', noiseVoicedFraction));

% Silence: voiced frames <= 5% (should be 0%)
xSilence = zeros(N, 1);
pSilence = pc_yin(xSilence, fs, cfg);

silenceVoicedFraction = sum(pSilence.voiced) / numel(pSilence.voiced);
testCase.verifyLessThanOrEqual(silenceVoicedFraction, 0.05, ...
    sprintf('Silence voiced fraction exceeds 5%%: %.2f', silenceVoicedFraction));
end

function testHarmonicVoiceOctaveErrors(testCase)
fs = 44100;
N = fs;
cfg = pc_default_config();

% Test synthetic voice at 220 Hz
f0_true = 220;
xVoice = pc_synth_voice(fs, f0_true * ones(N, 1));

p = pc_yin(xVoice, fs, cfg);

testCase.verifyGreaterThan(sum(p.voiced), 0);
f0_voiced = p.f0(p.voiced);
centsErr = 1200 * abs(log2(f0_voiced / f0_true));

% < 1% of voiced frames with > 600-cent error (checking no octave doubling/halving)
grossPitchErrorRate = sum(centsErr > 600) / numel(f0_voiced);
testCase.verifyLessThan(grossPitchErrorRate, 0.01, ...
    sprintf('Gross pitch error rate (>600 cents) exceeds 1%%: %.4f', grossPitchErrorRate));
end

function testSpeedBenchmark(testCase)
fs = 44100;
cfg = pc_default_config();

% 10-second harmonic voice signal
x10s = pc_synth_voice(fs, 220 * ones(fs * 10, 1));

tStart = tic;
p = pc_yin(x10s, fs, cfg);
elapsed = toc(tStart);

testCase.verifyLessThan(elapsed, 5.0, ...
    sprintf('10s YIN processing took %.2f seconds (limit is 5.0 s)', elapsed));
testCase.verifyEqual(numel(p.t), numel(p.f0));
end
