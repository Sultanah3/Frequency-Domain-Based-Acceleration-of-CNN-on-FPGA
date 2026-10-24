% gen_rom_mif.m: ROM contents for synthesis, written into resources/.
%   kern.mif : kernel spectra for KernelReservoir, Cout*NKEEP*L words x 96 bits,
%              in the order cmac2d requests them (filter m, then column v, then row u).
%              Word = {im2, re2, im1, re1, im0, re0}, KERN_WL-bit two's complement each.
%   bias.mif : bias for acc2d (bias_rom IP), 96 words x 16 bits, two's complement,
%              at the scale of the acc2d samples, 2^(D_IN+D_MID-s)/L^2 (the only rounding point of acc2d).
% Image, kernels, Cout and word lengths come from the model workspace, so there is nothing to edit here.

here = fileparts(mfilename('fullpath'));                    % scripts/matlab
root = fullfile(here, '..', '..');                          % repo root
load_system('AcceleratationCore');
mws = get_param('AcceleratationCore', 'ModelWorkspace');  eval(mws.MATLABCode);

% kern.mif (a 96-bit word does not fit in a double, so the words are built as hex text)
kt = double(KERN_TAB(:, 1:Cout*L*NKEEP));                   % Cin x N, complex
P  = zeros(2*Cin, size(kt,2));                              % fields, low first: re0, im0, re1, im1, ...
P(1:2:end, :) = real(kt);
P(2:2:end, :) = imag(kt);
H     = dec2hex(reshape(mod(flipud(P), 2^KERN_WL), [], 1), KERN_WL/4);   % one field per row, high field first
words = string(reshape(H.', [], size(kt,2)).');                          % one word per row
writelines(["WIDTH=" + 2*Cin*KERN_WL + ";"; "DEPTH=" + size(kt,2) + ";"; "ADDRESS_RADIX=HEX;"; "DATA_RADIX=HEX;"; ...
    "CONTENT BEGIN"; compose("   %X : %s;", (0:size(kt,2)-1)', words); "END;"], fullfile(root, 'resources', 'kern.mif'));

% bias.mif (all 96 filters, so the ROM size never changes; Cout only decides how many are read)
p1 = load(fullfile(root, 'vectors', 'phase1_inputs.mat'), 'b');
bq = round(double(p1.b(:)) * L^2 / 2^(D_IN + D_MID - double(s)));
assert(max(abs(bq)) < 2^15, 'Bias does not fit in 16 bits at this scale.');
write_mif(fullfile(root, 'resources', 'bias.mif'), mod(bq, 2^16), 16, numel(bq));

fprintf('kern.mif: %d words x %d bits, bias.mif: %d words x 16 bits\n', size(kt,2), 2*Cin*KERN_WL, numel(bq));