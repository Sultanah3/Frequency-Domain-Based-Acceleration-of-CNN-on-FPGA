# Running the OaA-FFT core

The core is tested in two parts: the Simulink chain (fft2d, cmac2d, ifft2d) in
`AcceleratationCore.slx`, and acc2d in Questa. Both are checked from one place,
the "Show output image" button in the model.

## Files

| Path | Content |
|---|---|
| `generated/AcceleratationCore.slx` | Test model: image ROM, fft2d, cmac2d, ifft2d, kernel table |
| `generated/fft2d/fft2d.slx`, `cmac2d/cmac2d.slx`, `ifft2d/ifft2d.slx` | The blocks (Subsystem) |
| `generated/acc2d_fifo.*`, `generated/bias_rom.*` | IP Catalog cores used by acc2d (FIFO and bias ROM) |
| `hdl/acc2d/acc2d.v` | Overlap-add, crop and bias; writes the output image to SDRAM (Avalon-MM) |
| `tb/acc2d/acc2d_tb.v` | acc2d testbench |
| `tb/acc2d/gen_acc_vectors.m` | Writes `sim/acc2d_in.hex` from the last model run |
| `../../scripts/matlab/gen_rom_mif.m` | Writes `resources/kern.mif` (KernelReservoir) and `resources/bias.mif` (bias_rom) |

## Settings

All settings live in the Model Workspace of `AcceleratationCore` (Model Explorer):
the image (`IMG`), `Cout`, `B`, `K` and the word lengths. The scripts read them
from there, so a new image or kernel needs no other edit.
Current setup: `fujian_mountain_227.png`, `Cout = 2`.

## Run

1. Open `AcceleratationCore.slx` and press Run.
2. Click "Show output image": the Simulink result against the golden reference.
3. In MATLAB run `gen_acc_vectors`, then `gen_rom_mif`.
   `gen_acc_vectors` prints `LAT_UP`; it must match the value in `acc2d_tb.v`.
4. Open `quartus/OaA-FFT-Convolution-Accelerator.qpf`, revision `DE10`, then
   Tools > Run Simulation Tool > RTL Simulation.
   The testbench `acc2d_tb` is set in `DE10.qsf`. Questa runs in `simulation/`
   at the repo root, so the MIF paths in the IP (`../resources/...`) work from
   Quartus and Questa alike.
   The Questa transcript prints a report with the expected value next to each
   line.
5. Click "Show output image" again. Expected: `acc2d vs Simulink : 0 of N words differ`.

## Kernel ROM (KernelReservoir)

`resources/kern.mif` holds `Cout * 8320` words of 96 bits,
in the order cmac2d requests them (filter, then column v, then row u):
 
```
bits:  95..80  79..64  63..48  47..32  31..16  15..0
       im2     re2     im1     re1     im0     re0      (16-bit two's complement)
```
 
The ROM address is a counter of `kernReq`, and the ROM output is unregistered,
so the kernel arrives one cycle after the request, as in the model.

## acc2d interface
 
| Port | Width | Note |
|---|---|---|
| `data_in`, `valid_in` | 25, 1 | ifft2d output, no back-pressure per sample |
| `ready_out` | 1 | AND it into `cmac2d.readyIn` |
| `img_done` | 1 | Pulse when the last output pixel is written |
| `avm_*` | 32-bit Avalon-MM master | To the SDRAM Controller |
 
Output layout: one 32-bit word per pixel,
`address = OUT_BASE + 4*(m*217*217 + row*217 + col)`,
real value = `word * 2^(D_IN+D_MID-s) / L^2`.
Parameters to set at integration: `OUT_BASE` and `COUT`.
 
| IP | Setting |
|---|---|
| `acc2d_fifo` | SCFIFO, 50 bits x 16384 words, show-ahead, `almost_full` at 5433 (room for two 74x74 blocks) |
| `bias_rom` | ROM: 1-PORT, 16 bits x 96 words, unregistered output, `../resources/bias.mif` |


