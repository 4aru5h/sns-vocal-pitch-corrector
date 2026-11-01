function [S, f, t] = pc_stft(x, fs, N, hop)
% PC_STFT Compute one-sided magnitude Short-Time Fourier Transform.
%   [S, f, t] = pc_stft(x, fs, N, hop) computes the one-sided magnitude
%   spectrogram of signal x using an N-point symmetric Hann window (pc_hann).
%
%   x:      Monophonic input audio signal (column vector).
%   fs:     Sampling frequency in Hz.
%   N:      Window and FFT length (default 1024).
%   hop:    Hop length in samples (default 256).
%
%   Output:
%       S:  Magnitude STFT matrix (size floor(N/2)+1 x numFrames).
%       f:  Frequency vector in Hz (size floor(N/2)+1 x 1).
%       t:  Time vector in seconds (frame centers, size 1 x numFrames).

x = double(x(:));
xLen = numel(x);

if nargin < 3 || isempty(N), N = 1024; end
if nargin < 4 || isempty(hop), hop = 256; end

w = pc_hann(N);
N_bins = floor(N / 2) + 1;
f = (0 : (N_bins - 1))' * (fs / N);

if xLen < N
    % Zero-pad signal to at least N samples
    x = [x; zeros(N - xLen, 1)];
    xLen = N;
end

frameStarts = 1 : hop : (xLen - N + 1);
numFrames = numel(frameStarts);

t = ((frameStarts - 1) + (N - 1) / 2) / fs;
t = t(:)';

S = zeros(N_bins, numFrames);
for m = 1:numFrames
    idx = frameStarts(m) : frameStarts(m) + N - 1;
    frame = x(idx) .* w;
    X_fft = fft(frame, N);
    S(:, m) = abs(X_fft(1 : N_bins));
end
end
