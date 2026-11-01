function cfg = pc_default_config()
% PC_DEFAULT_CONFIG Returns default configuration parameters for vocal pitch correction.

cfg.yin.fmin = 70;  cfg.yin.fmax = 1000;      % Hz
cfg.yin.winSec = 0.025; cfg.yin.hopSec = 0.005;
cfg.yin.threshold = 0.15;                     % CMNDF absolute threshold
cfg.yin.voicedMaxAperiodicity = 0.25;         % d' gate
cfg.yin.silenceDb = -45;                      % frame RMS re. full-scale gate
cfg.yin.medianFrames = 5;                     % movmedian over voiced runs
cfg.key = 'C'; cfg.scale = 'chromatic';
cfg.strength = 1.0;                           % 0..1
cfg.retuneMs = 50;                            % 0 = hard snap
cfg.maxShiftSemis = 2;
cfg.psola.unvoicedPeriodSec = 0.01;
cfg.psola.refineMarks = true;
end
