function f = pc_midi2hz(m)
% PC_MIDI2HZ Convert MIDI note number to frequency in Hz.
%   f = pc_midi2hz(m) converts fractional MIDI note m to frequency in Hz.
%   f = 440 * 2.^((m - 69) / 12).
%   Vectorised, NaN-propagating, shape-preserving.

f = 440 * 2.^((m - 69) / 12);
end
