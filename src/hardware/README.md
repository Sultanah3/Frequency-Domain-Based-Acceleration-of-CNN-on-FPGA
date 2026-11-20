# Running the OaA-FFT core

The core is checked in three places: the Simulink chain (fft2d, cmac2d, ifft2d)
in `AcceleratationCore.slx`, acc2d in Questa, and the full system on the
DE10-Standard board (HPS + FPGA).

## Files

| Path | Content |
|---|---|
| `generated/AcceleratationCore.slx` | Test model: image, fft2d, cmac2d, ifft2d, kernel table |
| `generated/fft2d/fft2d.slx`, `cmac2d/cmac2d.slx`, `ifft2d/ifft2d.slx` | The blocks (Subsystem) |
| `generated/acceleration_core/` | HDL Coder output of the core (`Accelerat_ip_src_*.v`) |
| `generated/acc2d_fifo.*`, `generated/bias_rom.*` | IP Catalog cores used by acc2d (FIFO and bias ROM) |
| `hdl/acc2d/acc2d.v` | Overlap-add, crop and bias; writes the output image to SDRAM (Avalon-MM) |
| `tb/acc2d/acc2d_tb.v` | acc2d testbench |
| `tb/acc2d/gen_acc_vectors.m` | Writes `sim/acc2d_in.hex` from the last model run |
| `../Top.v` | FPGA top (Terasic GHRD base): HPS system, core, acc2d, start sequencer, cycle counter |
| `../../quartus/` | Project `OaA-FFT-Convolution-Accelerator.qpf`, revision `DE10`, Platform Designer system `soc_system.qsys` |
| `../software/hps/` | HPS program `oaa_run.c` |
| `../../scripts/matlab/gen_hps_inputs.m` | Writes `image.bin`, `kern_all.bin` (HPS inputs) and `resources/bias.mif` (bias_rom) |

## Settings

All settings live in the Model Workspace of `AcceleratationCore` (Model Explorer):
the image (`IMG`), `Cout`, `B`, `K` and the word lengths. The scripts read them
from there, so a new image or kernel needs no other edit.
Current setup: `fujian_mountain_227.png`, `Cout = 96` (kernel scale s = 19).

## Simulink and acc2d

1. Open `AcceleratationCore.slx` and press Run.
2. Click "Show output image": the Simulink result against the golden reference.
3. In MATLAB run `gen_acc_vectors`, then `gen_hps_inputs`.
   `gen_acc_vectors` prints `LAT_UP`; it must match the value in `acc2d_tb.v`.
4. Open `quartus/OaA-FFT-Convolution-Accelerator.qpf`, revision `DE10`, then
   Tools > Run Simulation Tool > RTL Simulation.
   The testbench `acc2d_tb` is set in `DE10.qsf`. Questa runs in `simulation/`
   at the repo root, so the MIF paths in the IP (`../resources/...`) work from
   Quartus and Questa alike.
5. Click "Show output image" again. Expected: `acc2d vs Simulink : 0 of N words differ`.

## Board (DE10-Standard)

1. Quartus: open `soc_system.qsys` in Platform Designer, Generate HDL (Verilog,
   synthesis). Do not change `hps_0`: the preloader on the SD card depends on it.
2. Compile revision `DE10`.
3. File > Convert Programming Files: Raw Binary File (.rbf), Passive Parallel x16,
   Compression ON, name `soc_system.rbf`. Copy it to the FAT partition of the SD card.
4. MSEL = 01010 (SW10: 1 ON, 2 OFF, 3 ON, 4 OFF, 5 ON). U-Boot loads the `.rbf`
   and enables the bridges at boot.
5. Copy `oaa_run.c`, `image.bin` and `kern_all.bin` to the board and run
   (see `../software/hps/README.md`).

### Address map (HPS side)

| Slave | Address |
|---|---|
| `ctrl_pio` (go) | 0xFF206000 |
| `stat_pio` ([0] tile_done, [1] img_done), edge capture | 0xFF207000, 0xFF20700C |
| `cyc_pio` (core busy cycles) | 0xFF208000 |
| FPGA SDRAM (output) | 0xC0000000 |
| `tile_buf` (8 bit x 12288) | 0xC4000000 |
| `kern_ch1_re`, `ch1_im`, `ch2_re`, `ch2_im`, `ch3_re`, `ch3_im` (16 bit x 16640) | 0xC4010000 + k x 0x10000 |

### Start sequencer

Each core start processes one input channel, so a tile needs 3 starts. The HPS
gives one `go` per tile; the top gives start 1 on `go` and starts 2 and 3 at the
falling edge of `fftBusy`. `tile_done = idle & (ch_left == 0) & ~start`, because
`idle` alone rises for one cycle between channels.

## acc2d interface

| Port | Width | Note |
|---|---|---|
| `data_in`, `valid_in` | 25, 1 | ifft2d output, no back-pressure per sample |
| `ready_out` | 1 | AND it into `cmac2d.readyIn` |
| `img_done` | 1 | Pulse when the last output pixel is written |
| `avm_*` | 32-bit Avalon-MM master | To the SDRAM Controller |

Filters run in passes of `COUT_PASS` (one kernel set per pass). Within a pass,
blocks arrive tile by tile in raster order, all `COUT_PASS` filters of a tile
before the next one.

Output layout: one 32-bit word per pixel,
`address = OUT_BASE + 4*(m*217*217 + row*217 + col)`,
real value = `word * 2^(D_IN+D_MID-s) / L^2`.
Parameters: `H`, `COUT`, `COUT_PASS`, `OUT_BASE`.

| IP | Setting |
|---|---|
| `acc2d_fifo` | SCFIFO, 50 bits x 16384 words, show-ahead, `almost_full` at 5433 (room for two 74x74 blocks) |
| `bias_rom` | ROM: 1-PORT, 16 bits x 96 words, unregistered output, `../resources/bias.mif` |
