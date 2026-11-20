/*
 * oaa_run.c
 * AlexNet conv1 (227x227x3 -> 217x217x96) on the OaA core of the DE10-Standard.
 *
 * 48 passes x 16 tiles. Per pass the HPS loads one kernel pair; per tile it
 * loads the tile and gives one go, then waits for tile_done. acc2d writes the
 * output to the FPGA SDRAM and raises img_done after the last pixel.
 *
 * In:  image.bin     16 tiles x 12288 B (splitter output)
 *      kern_all.bin  48 passes x 199680 B
 * Out: out.bin       96 x 217 x 217 int32
 *
 * Build: gcc -O2 -o oaa_run oaa_run.c      Run as root: ./oaa_run
 */

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>

#define TILE_BYTES 12288
#define KERN_BYTES 199680           /* 6 buffers x 16640 x 16 bit */
#define OUT_WORDS  (96 * 217 * 217)

static double ms(void)
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static void *load(const char *name, size_t bytes)
{
  void *p = malloc(bytes);
  FILE *f = fopen(name, "rb");
  if (!f || fread(p, 1, bytes, f) != bytes) {
    printf("cannot read %s\n", name);
    exit(1);
  }
  fclose(f);
  return p;
}

int main(void)
{
  uint8_t  *image = load("image.bin", 16 * TILE_BYTES);
  uint8_t  *kern  = load("kern_all.bin", 48 * KERN_BYTES);
  uint32_t *out   = malloc(OUT_WORDS * 4);

  int fd = open("/dev/mem", O_RDWR | O_SYNC);
  /* All data moves in 64-bit words: the HPS-to-FPGA bridge is 64 bits wide,
   * and the bridge rate is set by the number of transfers, not their size */
  volatile uint64_t *sdram = mmap(0, OUT_WORDS * 4, PROT_READ, MAP_SHARED, fd, 0xC0000000);
  volatile uint64_t *buf   = mmap(0, 0x70000, PROT_WRITE, MAP_SHARED, fd, 0xC4000000);
  volatile uint32_t *lw    = mmap(0, 0x10000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0xFF200000);

  volatile uint64_t *tile_hw = buf;                  /* tile buffer, 0xC4000000 */
  volatile uint32_t *go      = lw + 0x6000 / 4;      /* ctrl_pio */
  volatile uint32_t *done    = lw + 0x700C / 4;      /* stat_pio edge: [0] tile, [1] image */
  volatile uint32_t *cycles  = lw + 0x8000 / 4;      /* core busy cycles */

  double t_load = 0, t0, t_start;
  int p, t, k, i;

  do *done = 3; while (*done & 3);                   /* clear both flags */
  t_start = ms();

  for (p = 0; p < 48; p++) {
    t0 = ms();
    uint64_t *kp = (uint64_t *)(kern + p * KERN_BYTES);
    for (k = 0; k < 6; k++)                          /* 6 kernel buffers, 0x10000 apart */
      for (i = 0; i < KERN_BYTES / 48; i++)
        buf[(k + 1) * 0x2000 + i] = kp[k * (KERN_BYTES / 48) + i];
    t_load += ms() - t0;

    for (t = 0; t < 16; t++) {
      t0 = ms();
      uint64_t *tp = (uint64_t *)(image + t * TILE_BYTES);
      for (i = 0; i < TILE_BYTES / 8; i++) tile_hw[i] = tp[i];
      t_load += ms() - t0;

      do *done = 1; while (*done & 1);               /* clear tile_done, wait until cleared */
      *go = 1;
      *go = 0;
      while (!(*done & 1));                          /* wait for tile_done */
    }
    printf("\rpass %2d / 48", p + 1);
    fflush(stdout);
  }
  while (!(*done & 2));                              /* wait for img_done */
  double t_total = ms() - t_start;
  double t_core  = *cycles / 50e3;                   /* 50 MHz */

  t0 = ms();
  for (i = 0; i < OUT_WORDS / 2; i++) ((uint64_t *)out)[i] = sdram[i];
  double t_read = ms() - t0;

  FILE *f = fopen("out.bin", "wb");
  fwrite(out, 4, OUT_WORDS, f);
  fclose(f);

  printf("\n\n");
  printf("  AlexNet conv1 on FPGA (OaA-FFT, 50 MHz)\n");
  printf("  ---------------------------------------\n");
  printf("  core compute       %8.1f ms\n", t_core);
  printf("  HPS -> FPGA load   %8.1f ms\n", t_load);
  printf("  total to output    %8.1f ms\n", t_total);
  printf("  FPGA -> HPS read   %8.1f ms\n", t_read);
  printf("  ---------------------------------------\n");
  printf("  output: out.bin, 96 x 217 x 217\n");
  return 0;
}
