% gen_hps_inputs.m: input files for the HPS program (src/software/hps/oaa_run.c)
% and the bias ROM, all from the Model Workspace of AcceleratationCore (Cout = 96).
%   src/software/hps/image.bin    : 16 tiles x 12288 B, uint8. Tile order row-major,
%                                   inside a tile [ch][row][col] (IMG_VEC of the model).
%   src/software/hps/kern_all.bin : 48 passes x 6 buffers x 16640 int16 (little endian).
%                                   Buffers: ch1 re, ch1 im, ch2 re, ch2 im, ch3 re, ch3 im.
%                                   Word order as cmac2d requests it: filter, column v, row u.
%   resources/bias.mif            : 96 x 16 bit, at the scale of the acc2d samples.
% Kernels and bias share the scale s, so always regenerate them together.

here = fileparts(mfilename('fullpath'));                    % scripts/matlab
root = fullfile(here, '..', '..');                          % repo root
out  = fullfile(root, 'src', 'software', 'hps');
load_system('AcceleratationCore');
mws = get_param('AcceleratationCore', 'ModelWorkspace');  eval(mws.MATLABCode);
assert(Cout == 96, 'Set Cout = 96 in the Model Workspace.');

% image.bin
f = fopen(fullfile(out, 'image.bin'), 'w');  fwrite(f, IMG_VEC, 'uint8');  fclose(f);

% kern_all.bin: one pass = one filter pair = NW words per buffer
NW = 2 * L * NKEEP;
A  = zeros(NW, 2*Cin, Cout/2, 'int16');
for p = 1:Cout/2
    cols = KERN_TAB(:, (p-1)*NW + (1:NW));
    for c = 1:Cin
        A(:, 2*c-1, p) = real(cols(c, :));
        A(:, 2*c,   p) = imag(cols(c, :));
    end
end
f = fopen(fullfile(out, 'kern_all.bin'), 'w');  fwrite(f, A, 'int16', 'ieee-le');  fclose(f);

% bias.mif
p1 = load(fullfile(root, 'vectors', 'phase1_inputs.mat'), 'b');
bq = round(double(p1.b(:)) * L^2 / 2^(D_IN + D_MID - double(s)));
assert(max(abs(bq)) < 2^15, 'Bias does not fit in 16 bits at this scale.');
write_mif(fullfile(root, 'resources', 'bias.mif'), mod(bq, 2^16), 16, numel(bq));

fprintf('s = %d: image.bin %d B, kern_all.bin %d B, bias.mif %d words\n', ...
        s, numel(IMG_VEC), 2*numel(A), numel(bq));
