function tests = test_m0_basics
tests = functiontests(localfunctions);
end

function testHann(testCase)
w5 = pc_hann(5);
testCase.verifyEqual(w5, [0; 0.5; 1; 0.5; 0], 'AbsTol', 1e-12);
testCase.verifyTrue(iscolumn(w5));

w1 = pc_hann(1);
testCase.verifyEqual(w1, 1);
testCase.verifyTrue(iscolumn(w1));

testCase.verifyError(@() pc_hann(0), ?MException);
testCase.verifyError(@() pc_hann(-5), ?MException);
testCase.verifyError(@() pc_hann(2.5), ?MException);
end

function testSynthVoice(testCase)
fs = 44100;
f0 = 220 * ones(fs, 1);
x = pc_synth_voice(fs, f0);

testCase.verifyEqual(size(x), [fs, 1]);
testCase.verifyFalse(any(isnan(x)));
testCase.verifyEqual(max(abs(x)), 0.9, 'AbsTol', 1e-12);
end

function testDefaultConfig(testCase)
cfg = pc_default_config();

testCase.verifyTrue(isfield(cfg, 'yin'));
testCase.verifyTrue(isfield(cfg.yin, 'fmin'));
testCase.verifyTrue(isfield(cfg, 'strength'));
testCase.verifyTrue(isfield(cfg, 'retuneMs'));
testCase.verifyTrue(isfield(cfg, 'psola'));
testCase.verifyTrue(isfield(cfg.psola, 'refineMarks'));
end
