function pcs = pc_scale_pcs(key, scaleType)
% PC_SCALE_PCS Return sorted pitch classes (0..11) for a given key and scale type.
%   pcs = pc_scale_pcs(key, scaleType) returns a sorted row vector of
%   pitch classes in 0..11 for the specified key and scale type.
%
%   key: string or char from {C, C#, D, D#, E, F, F#, G, G#, A, A#, B}
%        (case-insensitive; flat equivalents Db, Eb, Gb, Ab, Bb also accepted).
%   scaleType: string or char from {chromatic, major, minor}.
%
%   Major: [0 2 4 5 7 9 11] mod 12
%   Natural minor: [0 2 3 5 7 8 10] mod 12
%   Chromatic: 0..11

if (~ischar(key) && ~isstring(key)) || isempty(key) || (isstring(key) && ~isscalar(key))
    error('pc_scale_pcs:invalidKey', 'Key must be a non-empty character vector or string scalar.');
end

if (~ischar(scaleType) && ~isstring(scaleType)) || isempty(scaleType) || (isstring(scaleType) && ~isscalar(scaleType))
    error('pc_scale_pcs:invalidScaleType', 'Scale type must be a non-empty character vector or string scalar.');
end

keyStr = upper(strtrim(string(key)));
scaleStr = lower(strtrim(string(scaleType)));

switch keyStr
    case "C"
        key_pc = 0;
    case {"C#", "DB"}
        key_pc = 1;
    case "D"
        key_pc = 2;
    case {"D#", "EB"}
        key_pc = 3;
    case "E"
        key_pc = 4;
    case "F"
        key_pc = 5;
    case {"F#", "GB"}
        key_pc = 6;
    case "G"
        key_pc = 7;
    case {"G#", "AB"}
        key_pc = 8;
    case "A"
        key_pc = 9;
    case {"A#", "BB"}
        key_pc = 10;
    case "B"
        key_pc = 11;
    otherwise
        error('pc_scale_pcs:invalidKey', 'Invalid musical key: "%s".', keyStr);
end

switch scaleStr
    case "chromatic"
        intervals = 0:11;
    case "major"
        intervals = [0, 2, 4, 5, 7, 9, 11];
    case "minor"
        intervals = [0, 2, 3, 5, 7, 8, 10];
    case {"pentatonic", "pentatonic_major", "major_pentatonic"}
        intervals = [0, 2, 4, 7, 9];
    case {"minor_pentatonic", "pentatonic_minor"}
        intervals = [0, 3, 5, 7, 10];
    otherwise
        error('pc_scale_pcs:invalidScaleType', 'Invalid scale type: "%s". Must be chromatic, major, minor, or pentatonic.', scaleStr);
end

pcs = mod(key_pc + intervals, 12);
pcs = sort(unique(pcs(:)'));
end
