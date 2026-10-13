% gen_acc_vectors.m
% Writes the acc2d_tb vectors into vectors/acc2d/:
%   stim.hex      what ifft2d sends: for every tile and filter, the 74x74 block of
%                 real(ifft2(sum over channels of X.*H)), quantized to Q4.11
%   bias.hex      one bias word per filter (Q4.11 in 32 bits), loaded at address 0
%   expected.hex  overlap-add, crop and bias applied to the same quantized samples
% acc2d must match expected.hex exactly.

clear; clc;

COUT = 2;          % filters in the vectors, must match COUT in acc2d_tb.v
B    = 64;         % tile size
K    = 11;         % kernel size
FL   = 11;         % fraction bits of the ifft2d output (Q4.11)

load('phase1_inputs.mat', 'X', 'W', 'b');
outDir = fullfile(fileparts(which('phase1_inputs.mat')), 'acc2d');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

[H, Wd, Cin] = size(X);
NC = B + K - 1;
L  = 2^nextpow2(NC);
HO = H - K + 1;
WO = Wd - K + 1;

% Kernel spectra, flipped for cross-correlation as in Phase 1
Kf = zeros(L, L, Cin, COUT);
for m = 1:COUT
    for c = 1:Cin
        Kp = zeros(L);
        Kp(1:K, 1:K) = rot90(W(:, :, c, m), 2);
        Kf(:, :, c, m) = fft2(Kp);
    end
end

% Blocks per tile and filter, and their overlap-add
stim = [];
acc  = zeros(ceil(H/B)*B + K, ceil(Wd/B)*B + K, COUT);
nSat = 0;
for r0 = 1:B:H
    for c0 = 1:B:Wd
        rows = r0 : min(r0+B-1, H);
        cols = c0 : min(c0+B-1, Wd);
        Xf = zeros(L, L, Cin);
        for c = 1:Cin
            Xp = zeros(L);
            Xp(1:numel(rows), 1:numel(cols)) = X(rows, cols, c);
            Xf(:, :, c) = fft2(Xp);
        end
        for m = 1:COUT
            blk  = real(ifft2(sum(Xf .* Kf(:, :, :, m), 3)));
            q    = round(blk(1:NC, 1:NC) * 2^FL);
            nSat = nSat + nnz(q > 2^15-1 | q < -2^15);
            q    = min(max(q, -2^15), 2^15-1);
            stim = [stim; reshape(q.', [], 1)]; %#ok<AGROW>
            ri = r0 - 1 + (1:NC);
            ci = c0 - 1 + (1:NC);
            acc(ri, ci, m) = acc(ri, ci, m) + q;
        end
    end
end

% Expected output: crop to the valid region, add the bias once
bq  = round(double(b(1:COUT)) * 2^FL);
expOut = zeros(HO*WO, COUT);
for m = 1:COUT
    expOut(:, m) = reshape((acc(K:K+HO-1, K:K+WO-1, m) + bq(m)).', [], 1);
end

writeHex(fullfile(outDir, 'stim.hex'),     mod(stim, 2^16),   '%04x\n');
writeHex(fullfile(outDir, 'bias.hex'),     mod(bq(:), 2^32),  '%08x\n');
writeHex(fullfile(outDir, 'expected.hex'), mod(expOut(:), 2^32), '%08x\n');
fprintf('COUT = %d, %d blocks, %d saturated samples, written to %s\n', ...
        COUT, numel(stim)/(NC*NC), nSat, outDir);

function writeHex(file, values, fmt)
    fid = fopen(file, 'w');
    fprintf(fid, fmt, values);
    fclose(fid);
end