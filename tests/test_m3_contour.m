function tests = test_m3_contour
tests = functiontests(localfunctions);
end

function testZeroStrength(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.5)';
f0 = pc_midi2hz(60.4) * ones(size(t));

p.t = t;
p.f0 = f0;
p.voiced = true(size(t));

cfg = pc_default_config();
cfg.strength = 0;

c = pc_correction_contour(p, cfg);

testCase.verifyEqual(c.shiftSemis, zeros(size(t)));
testCase.verifyEqual(c.ratio, ones(size(t)));
testCase.verifyEqual(c.midiOut, c.midiDet, 'AbsTol', 1e-12);
end

function testHardSnap(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.5)';
f0 = pc_midi2hz(60.4) * ones(size(t));

p.t = t;
p.f0 = f0;
p.voiced = true(size(t));

cfg = pc_default_config();
cfg.strength = 1.0;
cfg.retuneMs = 0;

c = pc_correction_contour(p, cfg);

testCase.verifyEqual(c.midiOut(p.voiced), c.midiTarget(p.voiced), 'AbsTol', 1e-9);
end

function testStepResponse(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.5)';
% Detected note is 60.4; in chromatic, nearest note is 60; step raw shift = -0.4
f0 = pc_midi2hz(60.4) * ones(size(t));

p.t = t;
p.f0 = f0;
p.voiced = true(size(t));

cfg = pc_default_config();
cfg.strength = 1.0;
cfg.retuneMs = 50; % tau = 50 ms

c = pc_correction_contour(p, cfg);

% Theoretical step response reached: 1 - 1/e ~= 63.2%
rawTargetShift = -0.4;
targetFraction = 1 - exp(-1);

% At t = tau = 50 ms, exactly 10 hops (k = 10) have elapsed
fractions = c.shiftSemis / rawTargetShift;

% Verify that at k = 10 (or 11), the response reaches targetFraction within +-1 hop interval
% Check fraction at k = 10 is within 1e-6
testCase.verifyEqual(fractions(10), targetFraction, 'AbsTol', 1e-5);
end

function testUnvoicedFrames(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.2)';
f0 = pc_midi2hz(60.4) * ones(size(t));
voiced = true(size(t));

% Make middle frames unvoiced
unvoicedIdx = 10:20;
f0(unvoicedIdx) = NaN;
voiced(unvoicedIdx) = false;

p.t = t;
p.f0 = f0;
p.voiced = voiced;

cfg = pc_default_config();
c = pc_correction_contour(p, cfg);

% Unvoiced frames must have ratio == 1.0, shiftSemis == 0, midiOut == NaN
testCase.verifyTrue(all(c.shiftSemis(~voiced) == 0));
testCase.verifyTrue(all(c.ratio(~voiced) == 1.0));
testCase.verifyTrue(all(isnan(c.midiOut(~voiced))));
testCase.verifyTrue(all(isnan(c.midiDet(~voiced))));
testCase.verifyTrue(all(isnan(c.midiTarget(~voiced))));
testCase.verifyTrue(all(isnan(c.centsDev(~voiced))));
end

function testMaxShiftClamping(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.2)';

% Detected note is 63.0 (D#4); in C major, nearest notes are 62 (D4) and 64 (E4), distance 1.0
% In C pentatonic or if target is 3 semitones away:
% Suppose key is C, scale is minor: {0, 2, 3, 5, 7, 8, 10}
% If note is 61.0 (C#4), scale notes are 60 (C4) and 62 (D4)
% Let's test custom target: detected note is 60, but pcs only has note 3 (Eb)
% Then nearest scale note is 63 (3 semitones away)
f0 = pc_midi2hz(60.0) * ones(size(t));

p.t = t;
p.f0 = f0;
p.voiced = true(size(t));

cfg = pc_default_config();
cfg.maxShiftSemis = 2.0;
cfg.strength = 1.0;
cfg.retuneMs = 0; % hard snap to immediately see clamped shift

% In C major, if we detect note 61.0 and scale has only 64 (4 semitones away)
% Or test with scale where target note is 3 semitones away
% For instance: key is 'C', scale is 'major' (0,2,4,5,7,9,11)
% Note 61 snaps to 60 (1 away).
% If note is 63.0 (D#4): in C major, 62 is D (1 away), 64 is E (1 away).
% To get target 3 away:
% What if pcs is just [7] (G)?
% Note 64 (E) is 3 away from 67 (G).
% We can set pcs directly if tested, or test pc_correction_contour with scaleType:
% Or set maxShiftSemis = 0.5:
% Target is 60, detected is 60.8 (snap to 61 -> 0.2 away) or 60.6 -> raw shift = +0.4 > 0.5? No, 0.4.
% If detected is 60.4, target is 60 -> raw shift = -0.4.
% If maxShiftSemis = 0.2, then |-0.4| > 0.2, so it MUST clamp to 0.2!
cfg.maxShiftSemis = 0.2;
c = pc_correction_contour(p, cfg);

% Raw shift would be 0 (if 60 snaps to 60)
% Let's use 60.4:
f0_dev = pc_midi2hz(60.4) * ones(size(t));
p.f0 = f0_dev;
c_clamped = pc_correction_contour(p, cfg);

% Raw shift is 60 - 60.4 = -0.4; clamped to -0.2
testCase.verifyEqual(max(abs(c_clamped.shiftSemis)), 0.2, 'AbsTol', 1e-12);
end

function testOnsetReset(testCase)
hopSec = 0.005;
t = (0 : hopSec : 0.5)';
f0 = pc_midi2hz(60.4) * ones(size(t));
voiced = true(size(t));

% Make an unvoiced gap between frame 20 and 40
voiced(20:40) = false;
f0(20:40) = NaN;

p.t = t;
p.f0 = f0;
p.voiced = voiced;

cfg = pc_default_config();
cfg.retuneMs = 100;
c = pc_correction_contour(p, cfg);

% The first voiced frame after the gap (frame 41) must reset state to 0
% So its shift should equal alpha * rawShift, not continuing from frame 19
alpha = 1 - exp(-0.005 / 0.1);
expectedFirstShift = alpha * (-0.4);

testCase.verifyEqual(c.shiftSemis(41), expectedFirstShift, 'AbsTol', 1e-6);
end
