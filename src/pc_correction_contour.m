function c = pc_correction_contour(p, cfg)
% PC_CORRECTION_CONTOUR Compute pitch correction contour.
%   c = pc_correction_contour(p, cfg) calculates target MIDI notes, cents
%   deviation, shift amount in semitones with one-pole retune speed smoothing,
%   and playback resynthesis frequency ratio for each frame in p.
%
%   Output struct c contains matching column vectors:
%       c.midiDet     - Detected pitch in fractional MIDI note number.
%       c.midiTarget  - Target scale note in integer MIDI note number.
%       c.centsDev    - Deviation in cents = 100 * (midiDet - midiTarget).
%       c.shiftSemis  - Applied pitch shift in semitones (smoothed and clamped).
%       c.ratio       - Resynthesis frequency ratio = 2^(shiftSemis / 12).
%       c.midiOut     - Expected output MIDI note = midiDet + shiftSemis.

if nargin < 2 || isempty(cfg)
    cfg = pc_default_config();
end

% Extract configuration parameters with defaults
key = 'C';
scale = 'chromatic';
strength = 1.0;
retuneMs = 50;
maxShiftSemis = 2.0;
hopSecDefault = 0.005;

if isfield(cfg, 'key'), key = cfg.key; end
if isfield(cfg, 'scale'), scale = cfg.scale; end
if isfield(cfg, 'strength'), strength = cfg.strength; end
if isfield(cfg, 'retuneMs'), retuneMs = cfg.retuneMs; end
if isfield(cfg, 'maxShiftSemis'), maxShiftSemis = cfg.maxShiftSemis; end
if isfield(cfg, 'yin') && isfield(cfg.yin, 'hopSec')
    hopSecDefault = cfg.yin.hopSec;
end

N_frames = numel(p.t);
if N_frames == 0
    c.midiDet = zeros(0, 1);
    c.midiTarget = zeros(0, 1);
    c.centsDev = zeros(0, 1);
    c.shiftSemis = zeros(0, 1);
    c.ratio = zeros(0, 1);
    c.midiOut = zeros(0, 1);
    return;
end

% Scale pitch classes
pcs = pc_scale_pcs(key, scale);

% Voiced masking and MIDI conversion
f0_voiced = p.f0(:);
if isfield(p, 'voiced')
    f0_voiced(~p.voiced) = NaN;
end

midiDet = pc_hz2midi(f0_voiced);
isVoicedFrame = ~isnan(midiDet);

midiTarget = pc_snap_to_scale(midiDet, pcs);
centsDev = 100 * (midiDet - midiTarget);

% Raw shift: strength * (target - detected), clamped to maxShiftSemis
rawShift = nan(N_frames, 1);
rawShift(isVoicedFrame) = strength * (midiTarget(isVoicedFrame) - midiDet(isVoicedFrame));
rawShift(isVoicedFrame) = max(-maxShiftSemis, min(maxShiftSemis, rawShift(isVoicedFrame)));

% Determine hop time Thop
if N_frames > 1
    diffT = diff(p.t);
    Thop = median(diffT);
    if isnan(Thop) || Thop <= 0
        Thop = hopSecDefault;
    end
else
    Thop = hopSecDefault;
end

% One-pole retune smoothing parameter alpha
if retuneMs <= 0
    alpha = 1.0;
else
    tauSec = retuneMs / 1000;
    alpha = 1.0 - exp(-Thop / tauSec);
end

% State tracking and output arrays
shiftSemis = zeros(N_frames, 1);
ratio = ones(N_frames, 1);
midiOut = nan(N_frames, 1);

s_prev = 0;
for n = 1:N_frames
    if isVoicedFrame(n)
        % Reset smoothing filter state on voiced-run onset
        if (n == 1) || (~isVoicedFrame(n - 1))
            s_prev = 0;
        end
        
        % One-pole smoothing update
        s_curr = s_prev + alpha * (rawShift(n) - s_prev);
        
        % Clamp shift to [-maxShiftSemis, maxShiftSemis]
        s_curr = max(-maxShiftSemis, min(maxShiftSemis, s_curr));
        
        shiftSemis(n) = s_curr;
        ratio(n) = 2^(s_curr / 12);
        midiOut(n) = midiDet(n) + s_curr;
        
        s_prev = s_curr;
    else
        s_prev = 0;
        shiftSemis(n) = 0;
        ratio(n) = 1.0;
        midiOut(n) = NaN;
    end
end

c.midiDet = midiDet(:);
c.midiTarget = midiTarget(:);
c.centsDev = centsDev(:);
c.shiftSemis = shiftSemis(:);
c.ratio = ratio(:);
c.midiOut = midiOut(:);
end
