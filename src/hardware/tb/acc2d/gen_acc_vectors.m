% gen_acc_vectors.m: acc2d Questa inputs from the last AcceleratationCore run.
% Run the model on the full image first, so "out" is in the workspace.
% Image, kernels and sizes all come from the model workspace, so a new image or kernel needs no edit here.

here   = fileparts(mfilename('fullpath'));                 % src/hardware/tb/acc2d
root   = fullfile(here, '..', '..', '..', '..');            % repo root
simDir = fullfile(root, 'src', 'hardware', 'sim');
addpath(fullfile(root, 'scripts', 'matlab'));               % write_hex, write_mif

load_system('AcceleratationCore');
mws = get_param('AcceleratationCore', 'ModelWorkspace');  eval(mws.MATLABCode);

% ifft2d stream -> acc2d_in.hex
v = out.logsout.get('ifftValid').Values.Data(:);
x = double(out.logsout.get('ifftData').Values.Data(:));
x = x(v);
x = x(1 : Cout*(B+K-1)^2 * numel(IMG_VEC)/(Cin*B^2));         % error here = the run did not cover the whole image
write_hex(fullfile(simDir, 'acc2d_in.hex'), x, IF_WL+LOG2L);

% bias -> bias.mif at the sample scale (the only rounding point of acc2d)
p1 = load(fullfile(root, 'vectors', 'phase1_inputs.mat'), 'b');
b  = double(p1.b(:));                                           % b is stored 1x1xN, so make it a column first
bq = round(b(1:Cout) * L^2 / 2^(D_IN + D_MID - double(s)));     % first Cout filters, as in the model
BIAS_WL = ceil(log2(max(abs(bq)) + 1)) + 1;
write_mif(fullfile(simDir, 'bias.mif'), mod(bq, 2^BIAS_WL), BIAS_WL, Cout);

% Values acc2d_tb.v must match
LAT_UP = find(v, 1) - find(out.logsout.get('cmacValid').Values.Data(:), 1);
fprintf('acc2d_tb.v: BIAS_WL = %d, LAT_UP = %d\n', BIAS_WL, LAT_UP);