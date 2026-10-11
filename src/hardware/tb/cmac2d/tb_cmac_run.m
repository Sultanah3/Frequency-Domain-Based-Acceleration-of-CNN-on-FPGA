% tb_cmac_run.m
% Runs cmac2d_tb on block 1 (tile 1 of R, G, B) with COUT_SYS filters.
% fft2d turns the three tiles into spectra, cmac2d stores them and for each
% filter m returns sum over channels of X_c .* H_c(m).
%
% Checks:
%   counts  COUT spectra of NOUT samples, COUT doneOut pulses, one tileDone
%   exact   y == sum_c x_c .* h_c using the samples cmac2d actually received
%   SQNR    y against the same sum computed in double (reported only)
%
% cmac2d_tb needs:
%   srcStart (stimStart), srcSel (stimSel), tileMem (tileMem), srcReady (stimReady)
%   kIdx (KMAX, KIDX_W, enable = MAC.kernRd), LUT_kRe / LUT_kIm (kRe / kIm)
%   logs fftData, fftValid, macData, macValid, macDone, macKernRd, macTileDone, macKern

clear; clc;

B      = 64;              % tile size
K      = 11;              % kernel size
L      = 128;             % FFT length
NKEEP  = L/2 + 1;         % 65 stored columns
NOUT   = L * NKEEP;       % 8320 samples per spectrum
PERIOD = 20000;           % cycles between channel starts, longer than one fft2d tile

load('phase1_inputs.mat', 'X', 'W');
dd   = Simulink.data.dictionary.open('fxp_sys.sldd');
sect = getSection(dd, 'Design Data');
COUT = getValue(getEntry(sect, 'COUT_SYS'));
Cin  = size(X, 3);

% Block 1: the top-left tile of each channel
tiles = cell(1, Cin);
for c = 1:Cin
    tiles{c} = X(1:B, 1:B, c);
end

% Kernel spectra as in Phase 1: flip, pad to LxL, fft2, keep bins 0..L/2
H = complex(zeros(L, NKEEP, Cin, COUT));
for m = 1:COUT
    for c = 1:Cin
        Kp = zeros(L);
        Kp(1:K, 1:K) = rot90(W(:, :, c, m), 2);
        F = fft2(Kp);
        H(:, :, c, m) = F(:, 1:NKEEP);
    end
end

% Kernel tables: row = channel, column = read index (filter by filter)
kRe = zeros(Cin, COUT*NOUT);
kIm = zeros(Cin, COUT*NOUT);
for m = 1:COUT
    cols = (m-1)*NOUT + (1:NOUT);
    for c = 1:Cin
        h = reshape(H(:, :, c, m), 1, []);
        kRe(c, cols) = real(h);
        kIm(c, cols) = imag(h);
    end
end
KMAX = COUT*NOUT - 1;

% Tile memory: one tile per column, row-major
mem = zeros(B*B, Cin);
for c = 1:Cin
    mem(:, c) = reshape(tiles{c}.', [], 1);
end

% One start per channel, PERIOD cycles apart; readyIn always high
starts = 1 + (0:Cin-1) * PERIOD;
tStop  = starts(end) + PERIOD + COUT*(NOUT + 1) + 1000;
stimStart = false(starts(end), 1);
stimStart(starts) = true;
stimSel = zeros(starts(end), 1);
for c = 2:Cin
    stimSel(starts(c):end) = c - 1;
end
stimReady = true(tStop + 1, 1);

% Simulate
in = Simulink.SimulationInput('cmac2d_tb');
in = in.setVariable('stimStart', stimStart);
in = in.setVariable('stimSel',   stimSel);
in = in.setVariable('tileMem',   mem);
in = in.setVariable('stimReady', stimReady);
in = in.setVariable('kRe',       kRe);
in = in.setVariable('kIm',       kIm);
in = in.setVariable('KMAX',      KMAX);
in = in.setVariable('KIDX_W',    ceil(log2(KMAX + 1)));
in = in.setModelParameter('StopTime', num2str(tStop));
fprintf('Simulating block 1, %d filters, %d cycles...\n', COUT, tStop);
out = sim(in);

x  = double(out.fftData(:));
vx = logical(out.fftValid(:));
y  = double(out.macData(:));
vy = logical(out.macValid(:));
hk = double(squeeze(out.macKern));
if size(hk, 1) == Cin && size(hk, 2) ~= Cin
    hk = hk.';                       % one row per cycle, one column per channel
end
nDone = nnz(out.macDone);
nTile = nnz(out.macTileDone);

% Compare
xs = x(vx);                          % spectra written into cmac2d, channel after channel
ys = y(vy);
countsOK = numel(xs) == Cin*NOUT && numel(ys) == COUT*NOUT && nDone == COUT && nTile == 1;

exactOK = false;
sqnr    = nan(1, COUT);
if countsOK
    Xin = reshape(xs, NOUT, Cin);                    % what cmac2d stored
    hs  = hk(logical(out.macKernRd(:)), :);          % kernel at each read (logged at kernIn)
    G = complex(zeros(NOUT, Cin));                   % same spectra in double
    for c = 1:Cin
        Xp = zeros(L);
        Xp(1:B, 1:B) = tiles{c};
        F = fft2(Xp);
        G(:, c) = reshape(F(:, 1:NKEEP), [], 1);
    end
    exactOK = true;
    for m = 1:COUT
        k = (m-1)*NOUT + (1:NOUT);
        exactOK = exactOK && isequal(ys(k), sum(Xin .* hs(k, :), 2));
        ref = sum(G .* reshape(H(:, :, :, m), NOUT, Cin), 2);
        sqnr(m) = 10*log10(sum(abs(ref).^2) / sum(abs(ys(k) - ref).^2));
    end
end

fprintf('spectra out   : %d (expected %d)\n', numel(ys)/NOUT, COUT);
fprintf('doneOut pulses: %d (expected %d)\n', nDone, COUT);
fprintf('tileDone      : %d (expected 1)\n', nTile);
fprintf('exact sum     : %s\n', string(exactOK));
fprintf('SQNR          : worst %.2f dB, median %.2f dB\n', min(sqnr), median(sqnr));
if countsOK && exactOK
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end