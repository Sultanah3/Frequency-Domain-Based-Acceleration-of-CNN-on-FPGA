% gen_acc_vectors.m: acc2d testbench input from the last AcceleratationCore run.
% Run the model on the full image first, so "out" is in the workspace.
% Writes src/hardware/sim/acc2d_in.hex: every valid ifft2d sample, 25-bit two's complement, one per line.
% The bias ROM contents (resources/bias.mif) come from gen_rom_mif.

here   = fileparts(mfilename('fullpath'));                 % src/hardware/tb/acc2d
root   = fullfile(here, '..', '..', '..', '..');            % repo root
simDir = fullfile(root, 'src', 'hardware', 'sim');

load_system('AcceleratationCore');
mws = get_param('AcceleratationCore', 'ModelWorkspace');  eval(mws.MATLABCode);

v = out.logsout.get('ifftValid').Values.Data(:);
x = double(out.logsout.get('ifftData').Values.Data(:));
x = x(v);
x = x(1 : Cout*(B+K-1)^2 * numel(IMG_VEC)/(Cin*B^2));         % error here = the run did not cover the whole image
write_hex(fullfile(simDir, 'acc2d_in.hex'), x, IF_WL+LOG2L);

% Upstream latency used by acc2d_tb.v (LAT_UP), measured on this run
LAT_UP = find(v, 1) - find(out.logsout.get('cmacValid').Values.Data(:), 1);
fprintf('acc2d_in.hex: %d samples, LAT_UP = %d\n', numel(x), LAT_UP);