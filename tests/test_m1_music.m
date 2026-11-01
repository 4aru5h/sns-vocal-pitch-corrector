function tests = test_m1_music
tests = functiontests(localfunctions);
end

function testHzMidiConversions(testCase)
% 440 -> 69 exact
testCase.verifyEqual(pc_hz2midi(440), 69);

% 261.6256 -> 60 within 1e-3
testCase.verifyEqual(pc_hz2midi(261.6256), 60, 'AbsTol', 1e-3);

% hz -> midi -> hz round-trip relative error < 1e-9 over 50..2000 Hz
f = linspace(50, 2000, 500);
m = pc_hz2midi(f);
f_rt = pc_midi2hz(m);
relErr = abs(f_rt - f) ./ f;
testCase.verifyTrue(all(relErr < 1e-9));

% midi -> hz check for 69 -> 440
testCase.verifyEqual(pc_midi2hz(69), 440, 'RelTol', 1e-12);

% f <= 0 gives NaN
testCase.verifyTrue(isnan(pc_hz2midi(0)));
testCase.verifyTrue(isnan(pc_hz2midi(-50)));
end

function testMidi2Name(testCase)
% names 60->"C4", 69->"A4", 73->"C#5"
testCase.verifyEqual(pc_midi2name(60), "C4");
testCase.verifyEqual(pc_midi2name(69), "A4");
testCase.verifyEqual(pc_midi2name(73), "C#5");

% Rounding to nearest
testCase.verifyEqual(pc_midi2name(60.2), "C4");
testCase.verifyEqual(pc_midi2name(59.8), "C4");

% NaN gives ""
testCase.verifyEqual(pc_midi2name(NaN), "");
end

function testScalePcs(testCase)
% pc_scale_pcs('A','minor') == [0 2 4 5 7 9 11] (sorted set {9,11,0,2,4,5,7})
testCase.verifyEqual(pc_scale_pcs('A', 'minor'), [0 2 4 5 7 9 11]);

% pc_scale_pcs('C','major') == [0 2 4 5 7 9 11]
testCase.verifyEqual(pc_scale_pcs('C', 'major'), [0 2 4 5 7 9 11]);

% Chromatic returns 0..11
testCase.verifyEqual(pc_scale_pcs('D', 'chromatic'), 0:11);

% Enharmonics / flats
testCase.verifyEqual(pc_scale_pcs('Db', 'major'), pc_scale_pcs('C#', 'major'));
testCase.verifyEqual(pc_scale_pcs('bb', 'minor'), pc_scale_pcs('A#', 'minor'));

% Invalid key raises error
testCase.verifyError(@() pc_scale_pcs('H', 'major'), ?MException);
testCase.verifyError(@() pc_scale_pcs('X#', 'minor'), ?MException);

% Invalid scale type raises error
testCase.verifyError(@() pc_scale_pcs('C', 'mixolydian'), ?MException);
end

function testSnapToScale(testCase)
pcsC = pc_scale_pcs('C', 'major');

% with C major: 61.4->62, 61.0->60, 64.6->65, 63.5->64
testCase.verifyEqual(pc_snap_to_scale(61.4, pcsC), 62);
testCase.verifyEqual(pc_snap_to_scale(61.0, pcsC), 60);
testCase.verifyEqual(pc_snap_to_scale(64.6, pcsC), 65);
testCase.verifyEqual(pc_snap_to_scale(63.5, pcsC), 64);

% chromatic: 60.49->60, 60.51->61, 60.5->60 (tie lower)
pcsChrom = pc_scale_pcs('C', 'chromatic');
testCase.verifyEqual(pc_snap_to_scale(60.49, pcsChrom), 60);
testCase.verifyEqual(pc_snap_to_scale(60.51, pcsChrom), 61);
testCase.verifyEqual(pc_snap_to_scale(60.50, pcsChrom), 60);
end

function testNaNPropagation(testCase)
% NaN in gives NaN out
pcsC = pc_scale_pcs('C', 'major');
testCase.verifyTrue(isnan(pc_hz2midi(NaN)));
testCase.verifyTrue(isnan(pc_midi2hz(NaN)));
testCase.verifyEqual(pc_midi2name(NaN), "");
testCase.verifyTrue(isnan(pc_snap_to_scale(NaN, pcsC)));
end

function testMatrixShapePreservation(testCase)
% A matrix input keeps its shape
pcsC = pc_scale_pcs('C', 'major');
M = [60.49, 61.4, 69; 73, NaN, 261.6256];

resHz = pc_midi2hz(M);
testCase.verifyEqual(size(resHz), size(M));

resMidi = pc_hz2midi(resHz);
testCase.verifyEqual(size(resMidi), size(M));

resName = pc_midi2name(M);
testCase.verifyEqual(size(resName), size(M));

resSnap = pc_snap_to_scale(M, pcsC);
testCase.verifyEqual(size(resSnap), size(M));

% Test row vector and column vector
rowVec = [60, 61, 62];
testCase.verifyEqual(size(pc_snap_to_scale(rowVec, pcsC)), [1, 3]);
colVec = [60; 61; 62];
testCase.verifyEqual(size(pc_snap_to_scale(colVec, pcsC)), [3, 1]);
end
