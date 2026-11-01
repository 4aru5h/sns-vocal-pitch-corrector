function w = pc_hann(N)
% PC_HANN Symmetric Hann window column vector.
%   w = pc_hann(N) returns an N-point symmetric Hann window as a column vector.
%   w(n) = 0.5 - 0.5*cos(2*pi*(n-1)/(N-1)) for n = 1..N.
%   N == 1 returns 1.
%   Errors if N < 1 or if N is non-integer.

if ~isnumeric(N) || ~isscalar(N) || isnan(N) || isinf(N) || N < 1 || floor(N) ~= N
    error('pc_hann:invalidN', 'N must be a positive integer scalar >= 1.');
end

if N == 1
    w = 1;
    return;
end

n = (0:(N - 1))';
w = 0.5 - 0.5 * cos(2 * pi * n / (N - 1));
end
