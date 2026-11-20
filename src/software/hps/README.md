# HPS program

`oaa_run.c` runs AlexNet conv1 (227x227x3 to 217x217x96) on the FPGA core.
48 passes x 16 tiles: per pass it loads one kernel pair, per tile it loads the
tile, gives one `go` and waits for `tile_done`. acc2d writes the output to the
FPGA SDRAM and raises `img_done` after the last pixel.

## Files

| File | Size | Content |
|---|---|---|
| `image.bin` | 196,608 B | 16 tiles x 12,288 B, uint8; tiles row-major, inside a tile `[ch][row][col]` |
| `kern_all.bin` | 9,584,640 B | 48 passes x 6 buffers x 16,640 int16 |
| `out.bin` | 18,082,176 B | output, 96 x 217 x 217 int32, filter-major, row-major |

`image.bin` and `kern_all.bin` come from `scripts/matlab/gen_hps_inputs.m`
(not tracked in git). A new image only needs a new `image.bin`: zero-pad the raw
227x227x3 uint8 RGB bottom and right to 256x256x3, then cut it into 64x64 tiles
in the order above.

## Run on the board

Copy the files to the `oaa` folder of the SD card FAT partition, then on the board:

```bash
mount /dev/mmcblk0p1 /mnt
mkdir -p ~/oaa && cp /mnt/oaa/* ~/oaa/
umount /mnt
cd ~/oaa
gcc -O2 -o oaa_run oaa_run.c
./oaa_run
```

Output:

```
  AlexNet conv1 on FPGA (OaA-FFT, 50 MHz)
  ---------------------------------------
  core compute         1215.3 ms
  HPS -> FPGA load      786.4 ms
  total to output      2005.3 ms
  FPGA -> HPS read     1062.1 ms
```

All copies use 64-bit words: the HPS-to-FPGA bridge is 64 bits wide and its rate
is set by the number of transfers, not their size.
