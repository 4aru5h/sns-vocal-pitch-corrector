function tests = test_m4_psola
tests = functiontests(localfunctions);
end

function testIdentityShift(testCase)
fs = 44100;
N = fs;
f0 = 220;
x = pc_synth_voice(fs, f0 * ones(N, 1));
cfg = pc_default_config();

p = pc_yin(x, fs, cfg);
y = pc_psola(x, fs, p, 1.0, cfg);

testCase.verifyEqual(numel(y), numel(x));
testCase.verifyFalse(any(isnan(y)));
testCase.verifyFalse(any(isinf(y)));

% Check SNR >= 60 dB
err = x - y;
snr = 20 * log10(norm(x) / norm(err));
testCase.verifyGreaterThanOrEqual(snr, 60.0, ...
    sprintf('Identity shift SNR is %.2f dB (expected >= 60 dB)', snr));
end

function testPitchShiftSemitones(testCase)
fs = 44100;
N = fs;
f0 = 220;
x = pc_synth_voice(fs, f0 * ones(N, 1));
cfg = pc_default_config();

p = pc_yin(x, fs, cfg);

% 1. Shift +1 semitone: ratio = 2^(1/12)
ratioUp1 = 2^(1/12);
yUp1 = pc_psola(x, fs, p, ratioUp1, cfg);
testCase.verifyEqual(numel(yUp1), numel(x));
pUp1 = pc_yin(yUp1, fs, cfg);

f_targetUp1 = f0 * ratioUp1;
f_medUp1 = median(pUp1.f0, 'omitnan');
centsUp1 = 1200 * abs(log2(f_medUp1 / f_targetUp1));
testCase.verifyLessThan(centsUp1, 10.0, ...
    sprintf('+1 semitone shift error %.2f cents (limit 10 cents)', centsUp1));

% 2. Shift -1 semitone: ratio = 2^(-1/12)
ratioDown1 = 2^(-1/12);
yDown1 = pc_psola(x, fs, p, ratioDown1, cfg);
testCase.verifyEqual(numel(yDown1), numel(x));
pDown1 = pc_yin(yDown1, fs, cfg);

f_targetDown1 = f0 * ratioDown1;
f_medDown1 = median(pDown1.f0, 'omitnan');
centsDown1 = 1200 * abs(log2(f_medDown1 / f_targetDown1));
testCase.verifyLessThan(centsDown1, 10.0, ...
    sprintf('-1 semitone shift error %.2f cents (limit 10 cents)', centsDown1));

% 3. Shift +3 semitones: ratio = 2^(3/12)
ratioUp3 = 2^(3/12);
yUp3 = pc_psola(x, fs, p, ratioUp3, cfg);
pUp3 = pc_yin(yUp3, fs, cfg);
f_targetUp3 = f0 * ratioUp3;
f_medUp3 = median(pUp3.f0, 'omitnan');
centsUp3 = 1200 * abs(log2(f_medUp3 / f_targetUp3));
testCase.verifyLessThan(centsUp3, 15.0, ...
    sprintf('+3 semitone shift error %.2f cents (limit 15 cents)', centsUp3));

% 4. Shift -3 semitones: ratio = 2^(-3/12)
ratioDown3 = 2^(-3/12);
yDown3 = pc_psola(x, fs, p, ratioDown3, cfg);
pDown3 = pc_yin(yDown3, fs, cfg);
f_targetDown3 = f0 * ratioDown3;
f_medDown3 = median(pDown3.f0, 'omitnan');
centsDown3 = 1200 * abs(log2(f_medDown3 / f_targetDown3));
testCase.verifyLessThan(centsDown3, 15.0, ...
    sprintf('-3 semitone shift error %.2f cents (limit 15 cents)', centsDown3));

% RMS ratio check in [0.8, 1.25]
rms_in = sqrt(mean(x.^2));
rms_out = sqrt(mean(yUp1.^2));
rms_ratio = rms_out / rms_in;
testCase.verifyGreaterThanOrEqual(rms_ratio, 0.8, 'RMS ratio below 0.8');
testCase.verifyLessThanOrEqual(rms_ratio, 1.25, 'RMS ratio exceeds 1.25');
end

function testUnvoicedSignalAndGaps(testCase)
fs = 44100;
N = fs;
f0_vec = 220 * ones(N, 1);
% Create an unvoiced gap in the middle
f0_vec(round(0.3 * fs) : round(0.6 * fs)) = NaN;

x = pc_synth_voice(fs, f0_vec);
cfg = pc_default_config();

p = pc_yin(x, fs, cfg);
y = pc_psola(x, fs, p, 2^(1/12), cfg);

testCase.verifyEqual(numel(y), numel(x));
testCase.verifyFalse(any(isnan(y)));
testCase.verifyFalse(any(isinf(y)));
end
