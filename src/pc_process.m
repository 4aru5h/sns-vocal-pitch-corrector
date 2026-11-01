function res = pc_process(xIn, fs, cfg)
% PC_PROCESS Orchestrate the entire vocal pitch-correction pipeline.
%   res = pc_process(xIn, fs, cfg) performs:
%       1. pc_preprocess: mono mixdown, DC removal, peak normalisation
%       2. pc_yin: fundamental frequency (f0) estimation
%       3. pc_correction_contour: target note snapping, retune smoothing
%       4. pc_psola: pitch-synchronous overlap-add resynthesis
%       5. pc_yin: re-run on output y for verification (res.pitchOut)
%
%   Returns struct res with fields:
%       x           - Preprocessed input audio signal
%       y           - Pitch-corrected output audio signal
%       fs          - Sampling rate in Hz
%       pitch       - Initial YIN analysis struct
%       contour     - Pitch correction contour struct
%       pitchOut    - Verification YIN analysis struct on y
%       cfg         - Configuration struct used
%       info        - Preprocessing info struct (gain, silent)

if nargin < 3 || isempty(cfg)
    cfg = pc_default_config();
end

% 1. Preprocess
[x, info] = pc_preprocess(xIn, fs);

% Handle silent input
if info.silent
    y = zeros(size(x));
    pitch = pc_yin(x, fs, cfg);
    contour = pc_correction_contour(pitch, cfg);
    pitchOut = pc_yin(y, fs, cfg);
    
    res.x = x;
    res.y = y;
    res.fs = fs;
    res.pitch = pitch;
    res.contour = contour;
    res.pitchOut = pitchOut;
    res.cfg = cfg;
    res.info = info;
    return;
end

% 2. YIN pitch tracking on input
pitch = pc_yin(x, fs, cfg);

% 3. Pitch correction contour
contour = pc_correction_contour(pitch, cfg);

% 4. TD-PSOLA resynthesis
y = pc_psola(x, fs, pitch, contour.ratio, cfg);

% 5. Re-run YIN pitch tracking on output y for verification
pitchOut = pc_yin(y, fs, cfg);

res.x = x;
res.y = y;
res.fs = fs;
res.pitch = pitch;
res.contour = contour;
res.pitchOut = pitchOut;
res.cfg = cfg;
res.info = info;
end
