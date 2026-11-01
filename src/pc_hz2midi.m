function m = pc_hz2midi(f)
% PC_HZ2MIDI Convert frequency in Hz to MIDI note number.
%   m = pc_hz2midi(f) converts frequency f in Hz to fractional MIDI note.
%   m = 69 + 12*log2(f/440).
%   Vectorised, NaN-propagating, shape-preserving.
%   f <= 0 returns NaN.

m = nan(size(f));
pos = (f > 0);
m(pos) = 69 + 12 * log2(f(pos) / 440);
end
