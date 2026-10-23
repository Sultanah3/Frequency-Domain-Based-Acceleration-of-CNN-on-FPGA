% gen_kernel_mif.m: kernel spectra of the model as one ROM for KernelReservoir (resources/kern.mif).
% One word per cmac2d kernel request, in KERN_TAB order (filter m, then column v = 0..NKEEP-1, then row u = 0..L-1).
% Word = Cin complex values, KERN_WL-bit two's complement fields, channel 0 in the low bits:
%   {im2, re2, im1, re1, im0, re0}  ->  re(c) = q[2c*KERN_WL +: KERN_WL], im(c) = q[(2c+1)*KERN_WL +: KERN_WL]
% it takes only 2*Cin*KERN_WL bits to store one kernel, so the ROM is Cin*KERN_WL words wide and Cout*L*NKEEP words deep

here = fileparts(mfilename('fullpath'));                    % scripts/matlab
root = fullfile(here, '..', '..');                          % repo root
load_system('AcceleratationCore');
mws = get_param('AcceleratationCore', 'ModelWorkspace');  eval(mws.MATLABCode);

kt = double(KERN_TAB(:, 1:Cout*L*NKEEP));                   % Cin x N, complex
P  = zeros(2*Cin, size(kt,2));                              % fields, low first: re0, im0, re1, im1, ...
P(1:2:end, :) = real(kt);
P(2:2:end, :) = imag(kt);
H     = dec2hex(reshape(mod(flipud(P), 2^KERN_WL), [], 1), KERN_WL/4);   % one field per row, high field first
words = string(reshape(H.', [], size(kt,2)).');                          % one word per row
% MIF in the same format as write_mif (which takes numbers, and a 96-bit word does not fit in a double)
writelines(["WIDTH=" + 2*Cin*KERN_WL + ";"; "DEPTH=" + size(kt,2) + ";"; "ADDRESS_RADIX=HEX;"; "DATA_RADIX=HEX;"; ...
    "CONTENT BEGIN"; compose("   %X : %s;", (0:size(kt,2)-1)', words); "END;"], fullfile(root, 'resources', 'kern.mif'));
fprintf('kern.mif: %d words x %d bits\n', size(kt,2), 2*Cin*KERN_WL);