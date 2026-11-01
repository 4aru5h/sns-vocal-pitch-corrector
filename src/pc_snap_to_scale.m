function mT = pc_snap_to_scale(m, pcs)
% PC_SNAP_TO_SCALE Snap MIDI note numbers to nearest scale note.
%   mT = pc_snap_to_scale(m, pcs) snaps each note in m to the nearest
%   integer MIDI note n such that mod(n, 12) is in pcs.
%   Candidates evaluated: floor(m)-2 : ceil(m)+2.
%   On an exact distance tie, chooses the LOWER note.
%   NaN in m produces NaN in mT.
%   Vectorised, NaN-propagating, shape-preserving.

if ~isnumeric(m)
    error('pc_snap_to_scale:invalidM', 'm must be numeric.');
end

if ~isnumeric(pcs) || isempty(pcs)
    error('pc_snap_to_scale:invalidPcs', 'pcs must be a non-empty numeric vector.');
end

mT = nan(size(m));
if isempty(m)
    return;
end

m_vec = m(:);
valid = ~isnan(m_vec);

if ~any(valid)
    return;
end

mv = m_vec(valid);
N_valid = numel(mv);

c_low = floor(mv) - 2;
c_high = ceil(mv) + 2;

% Offsets 0..5 cover all integers in [floor(mv)-2, ceil(mv)+2]
offsets = 0:5;
cands = c_low + offsets; % N_valid x 6

% Check which candidates are within [c_low, c_high] and in scale
pcs_mod = mod(pcs, 12);
isValidCand = (cands <= c_high) & ismember(mod(cands, 12), pcs_mod);

dists = abs(cands - mv);
dists(~isValidCand) = Inf;

% min returns the first occurrence index, which corresponds to the lower note
[minDist, minCol] = min(dists, [], 2);

rowIdx = (1:N_valid)';
candIdx = sub2ind(size(cands), rowIdx, minCol);
chosenCand = cands(candIdx);
chosenCand(isinf(minDist)) = NaN;

mT_vec = nan(numel(m), 1);
mT_vec(valid) = chosenCand;
mT = reshape(mT_vec, size(m));
end
