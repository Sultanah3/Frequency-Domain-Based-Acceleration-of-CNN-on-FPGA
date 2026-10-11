% tb_fft2d_run.m
% Runs fft2d_tb on the full image (16 tiles x 3 channels) and compares each
% output spectrum with fft2 of the same quantized, zero-padded tile.
%
% fft2d_tb needs:
%   srcStart  Signal = stimStart
%   srcSel    Signal = stimSel   (hold final value)
%   tileMem   Table  = tileMem   (2-D Direct Lookup Table: row = pixAddr, column = tile)
%   logs fftData, fftValid, fftDone, fftPixRd

clear; clc;

B      = 64;        % tile size
L      = 128;       % FFT length
NBIN   = L/2 + 1;   % 65 stored columns (Hermitian fold)
PERIOD = 20000;     % cycles between startTile pulses, longer than one tile

load('phase1_inputs.mat', 'X');
dd     = Simulink.data.dictionary.open('fxp_sys.sldd');
sect   = getSection(dd, 'Design Data');
WL_SYS = getValue(getEntry(sect, 'WL_SYS'));
I_SYS  = getValue(getEntry(sect, 'I_SYS'));

% Split the image into tiles: channel, tile row, tile column
[H, W, C] = size(X);
tiles = {};
for ch = 1:C
    for r0 = 1:B:H
        for c0 = 1:B:W
            tiles{end+1} = X(r0:min(r0+B-1, H), c0:min(c0+B-1, W), ch); %#ok<SAGROW>
        end
    end
end
nT = numel(tiles);

% Tile memory: one 64x64 tile per column, row-major, zero outside the image
mem = zeros(B*B, nT);
for n = 1:nT
    t = zeros(B);
    t(1:size(tiles{n},1), 1:size(tiles{n},2)) = tiles{n};
    mem(:, n) = reshape(t.', [], 1);
end

% One startTile every PERIOD cycles, tileMem switches to the next tile with it
startIdx = 1 + (0:nT-1) * PERIOD;
stimStart = false(startIdx(end), 1);
stimStart(startIdx) = true;
stimSel = zeros(startIdx(end), 1);
for n = 2:nT
    stimSel(startIdx(n):end) = n - 1;
end

% Simulate
in = Simulink.SimulationInput('fft2d_tb');
in = in.setVariable('stimStart', stimStart);
in = in.setVariable('stimSel',   stimSel);
in = in.setVariable('tileMem',   mem);
in = in.setModelParameter('StopTime', num2str(startIdx(end) + PERIOD));
fprintf('Simulating %d tiles...\n', nT);
out = sim(in);

valid = logical(out.fftValid(:));
data  = double(out.fftData(:));
y     = data(valid);
nDone = nnz(out.fftDone);
nRd   = nnz(out.fftPixRd);

% Compare every tile with fft2 of the quantized tile
sqnr = nan(1, nT);
if numel(y) == NBIN*L*nT
    for n = 1:nT
        q = fi(tiles{n}, 1, WL_SYS, WL_SYS-1-I_SYS, ...
               'RoundingMethod', 'Nearest', 'OverflowAction', 'Saturate');
        Xp = zeros(L);
        Xp(1:size(q,1), 1:size(q,2)) = double(q);
        G = fft2(Xp);
        g = reshape(G(:, 1:NBIN), [], 1);
        e = y((n-1)*NBIN*L + (1:NBIN*L)) - g;
        sqnr(n) = 10*log10(sum(abs(g).^2) / sum(abs(e).^2));
    end
end

countsOK = numel(y) == NBIN*L*nT && nDone == nT && nRd == B*L*nT;


fprintf('valid samples : %d (expected %d)\n', numel(y), NBIN*L*nT);
fprintf('doneOut pulses: %d (expected %d)\n', nDone, nT);
fprintf('pixRd cycles  : %d (expected %d)\n', nRd, B*L*nT);
fprintf('worst SQNR    : %.2f dB\n', min(sqnr));
if countsOK
    fprintf('PASS\n');
else
    fprintf('FAIL\n');
end