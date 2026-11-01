function tests = test_m7_gui
tests = functiontests(localfunctions);
end

function testGuiSmokeTest(testCase)
% Create app headlessly
app = PitchCorrectorApp('Visible', 'off');
c1 = onCleanup(@() delete(app.fig));

testCase.verifyTrue(isvalid(app.fig));

% Synthesise test voice
fs = 44100;
N = fs;
x = pc_synth_voice(fs, 220 * ones(N, 1));

% Load audio via programmatic test hook
app.loadAudio(x, fs);

% Run processing
app.process();

% Check that all 3 axes are populated with graphical children
testCase.verifyNotEmpty(app.axWave.Children);
testCase.verifyNotEmpty(app.axPitch.Children);
testCase.verifyNotEmpty(app.axSpec.Children);

% Verify result struct is populated
res = app.getResult();
testCase.verifyNotEmpty(res);
testCase.verifyEqual(numel(res.y), numel(x));
end
