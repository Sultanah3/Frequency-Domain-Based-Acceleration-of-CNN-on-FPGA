% tb_ifft_run.m
% Runs ifft2d_tb (fft2d -> cmac2d -> ifft2d) on block 1 with COUT_SYS filters.
% For each filter, ifft2d returns the 74x74 output block of the tile, row-major.
% The reference is the double IFFT of the spectrum ifft2d actually received
% from cmac2d, so the SQNR shows the error of ifft2d alone.
%
% Checks:
%   counts  COUT blocks of 74x74 valid samples, COUT doneOut pulses
%   frame   each row is 74 samples in a row, rows start L cycles apart
%   mIdx    mIdxOut equals the filter index on every valid sample
%   SQNR    against real(ifft2) of the cmac2d output (reported only)
%
% ifft2d_tb needs:
%   srcStart (stimStart), srcSel (stimSel), tileMem (tileMem)
%   kIdx (KMAX, KIDX_W), LUT_kRe / LUT_kIm (kRe / kIm)
%   logs macData, macValid, ifft_dataOut, ifft_validOut, ifft_doneOut, ifft_mIdxOut

clear; clc;

B      = 64;              % tile size
K      = 11;              % kernel size
NC     = B + K - 1;       % 74, output block size
L      = 128;             % FFT length
NKEEP  = L/2 + 1;         % 65 stored columns
NOUT   = L * NKEEP;       % 8320 samples per spectrum
PERIOD = 20000;           % cycles between channel starts, longer than one fft2d tile

load('phase1_inputs.mat', 'X', 'W');
dd   = Simulink.data.dictionary.open('fxp_sys.sldd');
sect = getSection(dd, 'Design Data');
COUT = getValue(getEntry(sect, 'COUT_SYS'));
Cin  = size(X, 3);

% Kernel tables for cmac2d: flip, pad to LxL, fft2, keep bins 0..L/2
kRe = zeros(Cin, COUT*NOUT);
kIm = zeros(Cin, COUT*NOUT);
for m = 1:COUT
    cols = (m-1)*NOUT + (1:NOUT);
    for c = 1:Cin
        Kp = zeros(L);
        Kp(1:K, 1:K) = rot90(W(:, :, c, m), 2);
        F = fft2(Kp);
        h = reshape(F(:, 1:NKEEP), 1, []);
        kRe(c, cols) = real(h);
        kIm(c, cols) = imag(h);
    end
end
KMAX = COUT*NOUT - 1;

% Tile memory: block 1 (top-left tile of each channel), row-major
mem = zeros(B*B, Cin);
for c = 1:Cin
    mem(:, c) = reshape(X(1:B, 1:B, c).', [], 1);
end

% One start per channel, PERIOD cycles apart
starts = 1 + (0:Cin-1) * PERIOD;
tStop  = starts(end) + (COUT + 2) * PERIOD;
stimStart = false(starts(end), 1);
stimStart(starts) = true;
stimSel = zeros(starts(end), 1);
for c = 2:Cin
    stimSel(starts(c):end) = c - 1;
end

% Simulate
in = Simulink.SimulationInput('ifft2d_tb');
in = in.setVariable('stimStart', stimStart);
in = in.setVariable('stimSel',   stimSel);
in = in.setVariable('tileMem',   mem);
in = in.setVariable('kRe',       kRe);
in = in.setVariable('kIm',       kIm);
in = in.setVariable('KMAX',      KMAX);
in = in.setVariable('KIDX_W',    ceil(log2(KMAX + 1)));
in = in.setModelParameter('StopTime', num2str(tStop));
fprintf('Simulating block 1, %d filters, up to %d cycles...\n', COUT, tStop);
out = sim(in);

ymac = double(out.macData(:));
vmac = logical(out.macValid(:));
z    = double(out.ifft_dataOut(:));
vz   = logical(out.ifft_validOut(:));
mi   = double(out.ifft_mIdxOut(:));
nDone = nnz(out.ifft_doneOut);

ys = ymac(vmac);                       % spectra ifft2d received
zs = z(vz);                            % blocks ifft2d produced
zi = find(vz);                         % cycle of each output sample

% Compare
countsOK = numel(ys) == COUT*NOUT && numel(zs) == COUT*NC*NC && nDone == COUT;
frameOK = false;
mIdxOK  = false;
sqnr    = nan(1, COUT);
if countsOK
    rows    = reshape(zi, NC, []);                      % one column per output row
    starts  = reshape(rows(1, :), NC, COUT);            % row start cycles, one column per block
    frameOK = all(diff(rows) == 1, 'all') && ...        % 74 samples in a row
              all(diff(starts) == L, 'all');            % rows of one block exactly L apart
    mIdxOK  = isequal(mi(vz), kron((0:COUT-1).', ones(NC*NC, 1)));
    for m = 1:COUT
        Yh = reshape(ys((m-1)*NOUT + (1:NOUT)), L, NKEEP);
        Yf = zeros(L);                                  % rebuild the full spectrum
        Yf(:, 1:NKEEP)       = Yh;
        Yf(1, NKEEP+1:L)     = conj(Yh(1, end-1:-1:2));
        Yf(2:end, NKEEP+1:L) = conj(Yh(end:-1:2, end-1:-1:2));
        blk = real(ifft2(Yf));
        ref = blk(1:NC, 1:NC);
        got = reshape(zs((m-1)*NC*NC + (1:NC*NC)), NC, NC).';   % row-major
        sqnr(m) = 10*log10(sum(ref(:).^2) / sum((got(:) - ref(:)).^2));
    end
end

fprintf('blocks out    : %d (expected %d)\n', numel(zs)/(NC*NC), COUT);
fprintf('doneOut pulses: %d (expected %d)\n', nDone, COUT);
fprintf('frame shape   : %s\n', string(frameOK));
fprintf('mIdx order    : %s\n', string(mIdxOK));
fprintf('SQNR (ifft2d) : worst %.2f dB, median %.2f dB\n', min(sqnr), median(sqnr));
if countsOK && frameOK && mIdxOK
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end