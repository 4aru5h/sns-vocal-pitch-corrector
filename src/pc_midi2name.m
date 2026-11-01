function s = pc_midi2name(m)
% PC_MIDI2NAME Convert MIDI note numbers to note names with octaves.
%   s = pc_midi2name(m) rounds m to the nearest integer note and returns
%   standard scientific pitch notation using sharp names:
%   C, C#, D, D#, E, F, F#, G, G#, A, A#, B.
%   Octave: floor(round(m)/12) - 1.
%   Returns a string array of the same size as m.
%   NaN elements in m yield "".

s = strings(size(m));
valid = ~isnan(m);

if any(valid, 'all')
    mRound = round(m(valid));
    mRound = mRound(:);
    noteNames = ["C"; "C#"; "D"; "D#"; "E"; "F"; "F#"; "G"; "G#"; "A"; "A#"; "B"];
    pcs = mod(mRound, 12); % 0..11, column vector
    octaves = floor(mRound / 12) - 1; % column vector
    names = noteNames(pcs + 1) + string(octaves); % K x 1 column vector
    s(valid) = names;
end

s(~valid) = "";
end
