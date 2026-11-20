/*   ////=====================================
 *   ///  OaA-FFT Convolution Accelerator   //
 *   //             Top Module             ///
 *   =====================================////
 *
 * The HPS writes one tile and one kernel pair into the on-chip buffers
 * (soc_system), gives one go per tile and waits for tile_done. acc2d writes
 * the output image into the FPGA SDRAM and raises img_done after the last pixel.
 */

module Top (
    input CLOCK_50,

    // FPGA SDRAM (acc2d output)
    output        DRAM_CLK,
    output        DRAM_CKE,
    output [12:0] DRAM_ADDR,
    output [ 1:0] DRAM_BA,
    inout  [15:0] DRAM_DQ,
    output        DRAM_LDQM,
    output        DRAM_UDQM,
    output        DRAM_CS_N,
    output        DRAM_WE_N,
    output        DRAM_CAS_N,
    output        DRAM_RAS_N,

    // HPS DDR3
    output [14:0] HPS_DDR3_ADDR,
    output [ 2:0] HPS_DDR3_BA,
    output        HPS_DDR3_CAS_N,
    output        HPS_DDR3_CKE,
    output        HPS_DDR3_CK_N,
    output        HPS_DDR3_CK_P,
    output        HPS_DDR3_CS_N,
    output [ 3:0] HPS_DDR3_DM,
    inout  [31:0] HPS_DDR3_DQ,
    inout  [ 3:0] HPS_DDR3_DQS_N,
    inout  [ 3:0] HPS_DDR3_DQS_P,
    output        HPS_DDR3_ODT,
    output        HPS_DDR3_RAS_N,
    output        HPS_DDR3_RESET_N,
    input         HPS_DDR3_RZQ,
    output        HPS_DDR3_WE_N,

    // HPS peripherals (fixed by the hps_0 settings the preloader was built for)
    inout        HPS_CONV_USB_N,
    output       HPS_ENET_GTX_CLK,
    inout        HPS_ENET_INT_N,
    output       HPS_ENET_MDC,
    inout        HPS_ENET_MDIO,
    input        HPS_ENET_RX_CLK,
    input  [3:0] HPS_ENET_RX_DATA,
    input        HPS_ENET_RX_DV,
    output [3:0] HPS_ENET_TX_DATA,
    output       HPS_ENET_TX_EN,
    inout  [3:0] HPS_FLASH_DATA,
    output       HPS_FLASH_DCLK,
    output       HPS_FLASH_NCSO,
    inout        HPS_GSENSOR_INT,
    inout        HPS_I2C1_SCLK,
    inout        HPS_I2C1_SDAT,
    inout        HPS_I2C2_SCLK,
    inout        HPS_I2C2_SDAT,
    inout        HPS_I2C_CONTROL,
    inout        HPS_KEY,
    inout        HPS_LCM_BK,
    inout        HPS_LCM_D_C,
    inout        HPS_LCM_RST_N,
    output       HPS_LCM_SPIM_CLK,
    output       HPS_LCM_SPIM_MOSI,
    output       HPS_LCM_SPIM_SS,
    input        HPS_LCM_SPIM_MISO,
    inout        HPS_LED,
    inout        HPS_LTC_GPIO,
    output       HPS_SD_CLK,
    inout        HPS_SD_CMD,
    inout  [3:0] HPS_SD_DATA,
    output       HPS_SPIM_CLK,
    input        HPS_SPIM_MISO,
    output       HPS_SPIM_MOSI,
    inout        HPS_SPIM_SS,
    input        HPS_UART_RX,
    output       HPS_UART_TX,
    input        HPS_USB_CLKOUT,
    inout  [7:0] HPS_USB_DATA,
    input        HPS_USB_DIR,
    input        HPS_USB_NXT,
    output       HPS_USB_STP
);

  wire               hps_reset_n;
  wire               reset;
  wire               go;
  reg                go_d;
  wire               go_rise;
  reg                fft_busy_d;
  wire               fft_fall;
  reg         [ 1:0] ch_left;
  wire               start;
  wire               idle;
  wire               tile_done;
  wire               img_done;
  reg                cyc_run;
  reg         [31:0] cyc_cnt;
  wire               ce_out;
  wire               valid_out;
  wire signed [24:0] data_out;
  wire               read_enable;
  wire        [14:0] kern_addr;
  wire               cmac_busy;
  wire               fft_busy;
  reg         [13:0] img_addr;
  wire        [ 7:0] pix_in;
  wire signed [15:0] kern_ch1_re;
  wire signed [15:0] kern_ch1_im;
  wire signed [15:0] kern_ch2_re;
  wire signed [15:0] kern_ch2_im;
  wire signed [15:0] kern_ch3_re;
  wire signed [15:0] kern_ch3_im;
  wire               acc_ready;
  wire        [31:0] acc_address;
  wire               acc_read;
  wire               acc_write;
  wire        [31:0] acc_writedata;
  wire        [31:0] acc_readdata;
  wire               acc_readdatavalid;
  wire               acc_waitrequest;
  wire        [ 1:0] dram_dqm;

  assign reset     = ~hps_reset_n;
  assign DRAM_LDQM = dram_dqm[0];
  assign DRAM_UDQM = dram_dqm[1];

  // Start sequencer: one go per tile from the HPS, three starts to the core
  // (one per input channel). Start 1 comes with the go, starts 2 and 3 when
  // fft2d finishes a channel (falling edge of fftBusy).
  assign go_rise  = go & ~go_d;
  assign fft_fall = fft_busy_d & ~fft_busy;
  assign start    = go_rise | (fft_fall & (ch_left != 2'd0));

  always @(posedge CLOCK_50 or posedge reset) begin
    if (reset) begin
      go_d       <= 1'b0;
      fft_busy_d <= 1'b0;
      ch_left    <= 2'd0;
    end else begin
      go_d       <= go;
      fft_busy_d <= fft_busy;
      if (go_rise) ch_left <= 2'd2;
      else if (fft_fall && ch_left != 2'd0) ch_left <= ch_left - 2'd1;
    end
  end

  // tile_done: all three channels through the core. idle alone rises for one
  // cycle between channels, so ch_left and start keep it low there.
  assign idle      = ~(cmac_busy | fft_busy);
  assign tile_done = idle & (ch_left == 2'd0) & ~start;

  // Core busy cycles, from the first go until img_done. HPS transfer time
  // (tile_done high) is not counted.
  always @(posedge CLOCK_50 or posedge reset) begin
    if (reset) begin
      cyc_run <= 1'b0;
      cyc_cnt <= 32'd0;
    end else if (go_rise && !cyc_run) begin
      cyc_run <= 1'b1;
      cyc_cnt <= 32'd0;
    end else if (img_done) cyc_run <= 1'b0;
    else if (cyc_run && !tile_done) cyc_cnt <= cyc_cnt + 32'd1;
  end

  // Tile buffer address: 3 channels x 4096 pixels
  always @(posedge CLOCK_50 or posedge reset) begin
    if (reset) img_addr <= 14'd0;
    else if (read_enable) begin
      if (img_addr == 14'd12287) img_addr <= 14'd0;
      else img_addr <= img_addr + 14'd1;
    end
  end

  soc_system soc_system_inst (
      .clk_clk      (CLOCK_50),
      .reset_reset_n(1'b1),

      // HPS: reset to the fabric, no reset requests, no trace events
      .hps_0_h2f_reset_reset_n             (hps_reset_n),
      .hps_0_f2h_cold_reset_req_reset_n    (1'b1),
      .hps_0_f2h_debug_reset_req_reset_n   (1'b1),
      .hps_0_f2h_warm_reset_req_reset_n    (1'b1),
      .hps_0_f2h_stm_hw_events_stm_hwevents(28'd0),

      // Control and status (lightweight bridge)
      .ctrl_export(go),
      .stat_export({img_done, tile_done}),
      .cyc_export (cyc_cnt),

      // Tile and kernel buffers: the HPS writes s1, the core reads s2
      .tile_buf_s2_address   (img_addr),
      .tile_buf_s2_chipselect(1'b1),
      .tile_buf_s2_clken     (1'b1),
      .tile_buf_s2_write     (1'b0),
      .tile_buf_s2_writedata (8'd0),
      .tile_buf_s2_readdata  (pix_in),

      .kern_ch1_re_s2_address   (kern_addr),
      .kern_ch1_re_s2_chipselect(1'b1),
      .kern_ch1_re_s2_clken     (1'b1),
      .kern_ch1_re_s2_write     (1'b0),
      .kern_ch1_re_s2_writedata (16'd0),
      .kern_ch1_re_s2_byteenable(2'b11),
      .kern_ch1_re_s2_readdata  (kern_ch1_re),

      .kern_ch1_im_s2_address   (kern_addr),
      .kern_ch1_im_s2_chipselect(1'b1),
      .kern_ch1_im_s2_clken     (1'b1),
      .kern_ch1_im_s2_write     (1'b0),
      .kern_ch1_im_s2_writedata (16'd0),
      .kern_ch1_im_s2_byteenable(2'b11),
      .kern_ch1_im_s2_readdata  (kern_ch1_im),

      .kern_ch2_re_s2_address   (kern_addr),
      .kern_ch2_re_s2_chipselect(1'b1),
      .kern_ch2_re_s2_clken     (1'b1),
      .kern_ch2_re_s2_write     (1'b0),
      .kern_ch2_re_s2_writedata (16'd0),
      .kern_ch2_re_s2_byteenable(2'b11),
      .kern_ch2_re_s2_readdata  (kern_ch2_re),

      .kern_ch2_im_s2_address   (kern_addr),
      .kern_ch2_im_s2_chipselect(1'b1),
      .kern_ch2_im_s2_clken     (1'b1),
      .kern_ch2_im_s2_write     (1'b0),
      .kern_ch2_im_s2_writedata (16'd0),
      .kern_ch2_im_s2_byteenable(2'b11),
      .kern_ch2_im_s2_readdata  (kern_ch2_im),

      .kern_ch3_re_s2_address   (kern_addr),
      .kern_ch3_re_s2_chipselect(1'b1),
      .kern_ch3_re_s2_clken     (1'b1),
      .kern_ch3_re_s2_write     (1'b0),
      .kern_ch3_re_s2_writedata (16'd0),
      .kern_ch3_re_s2_byteenable(2'b11),
      .kern_ch3_re_s2_readdata  (kern_ch3_re),

      .kern_ch3_im_s2_address   (kern_addr),
      .kern_ch3_im_s2_chipselect(1'b1),
      .kern_ch3_im_s2_clken     (1'b1),
      .kern_ch3_im_s2_write     (1'b0),
      .kern_ch3_im_s2_writedata (16'd0),
      .kern_ch3_im_s2_byteenable(2'b11),
      .kern_ch3_im_s2_readdata  (kern_ch3_im),

      // acc2d into the FPGA SDRAM
      .acc2d_address      (acc_address[25:0]),
      .acc2d_read         (acc_read),
      .acc2d_write        (acc_write),
      .acc2d_writedata    (acc_writedata),
      .acc2d_byteenable   (4'hF),
      .acc2d_burstcount   (1'b1),
      .acc2d_debugaccess  (1'b0),
      .acc2d_readdata     (acc_readdata),
      .acc2d_readdatavalid(acc_readdatavalid),
      .acc2d_waitrequest  (acc_waitrequest),

      .sdram_addr   (DRAM_ADDR),
      .sdram_ba     (DRAM_BA),
      .sdram_cas_n  (DRAM_CAS_N),
      .sdram_cke    (DRAM_CKE),
      .sdram_cs_n   (DRAM_CS_N),
      .sdram_dq     (DRAM_DQ),
      .sdram_dqm    (dram_dqm),
      .sdram_ras_n  (DRAM_RAS_N),
      .sdram_we_n   (DRAM_WE_N),
      .sdram_clk_clk(DRAM_CLK),

      // HPS DDR3
      .memory_mem_a      (HPS_DDR3_ADDR),
      .memory_mem_ba     (HPS_DDR3_BA),
      .memory_mem_ck     (HPS_DDR3_CK_P),
      .memory_mem_ck_n   (HPS_DDR3_CK_N),
      .memory_mem_cke    (HPS_DDR3_CKE),
      .memory_mem_cs_n   (HPS_DDR3_CS_N),
      .memory_mem_ras_n  (HPS_DDR3_RAS_N),
      .memory_mem_cas_n  (HPS_DDR3_CAS_N),
      .memory_mem_we_n   (HPS_DDR3_WE_N),
      .memory_mem_reset_n(HPS_DDR3_RESET_N),
      .memory_mem_dq     (HPS_DDR3_DQ),
      .memory_mem_dqs    (HPS_DDR3_DQS_P),
      .memory_mem_dqs_n  (HPS_DDR3_DQS_N),
      .memory_mem_odt    (HPS_DDR3_ODT),
      .memory_mem_dm     (HPS_DDR3_DM),
      .memory_oct_rzqin  (HPS_DDR3_RZQ),

      // HPS peripherals
      .hps_0_hps_io_hps_io_emac1_inst_TX_CLK(HPS_ENET_GTX_CLK),
      .hps_0_hps_io_hps_io_emac1_inst_TXD0  (HPS_ENET_TX_DATA[0]),
      .hps_0_hps_io_hps_io_emac1_inst_TXD1  (HPS_ENET_TX_DATA[1]),
      .hps_0_hps_io_hps_io_emac1_inst_TXD2  (HPS_ENET_TX_DATA[2]),
      .hps_0_hps_io_hps_io_emac1_inst_TXD3  (HPS_ENET_TX_DATA[3]),
      .hps_0_hps_io_hps_io_emac1_inst_RXD0  (HPS_ENET_RX_DATA[0]),
      .hps_0_hps_io_hps_io_emac1_inst_MDIO  (HPS_ENET_MDIO),
      .hps_0_hps_io_hps_io_emac1_inst_MDC   (HPS_ENET_MDC),
      .hps_0_hps_io_hps_io_emac1_inst_RX_CTL(HPS_ENET_RX_DV),
      .hps_0_hps_io_hps_io_emac1_inst_TX_CTL(HPS_ENET_TX_EN),
      .hps_0_hps_io_hps_io_emac1_inst_RX_CLK(HPS_ENET_RX_CLK),
      .hps_0_hps_io_hps_io_emac1_inst_RXD1  (HPS_ENET_RX_DATA[1]),
      .hps_0_hps_io_hps_io_emac1_inst_RXD2  (HPS_ENET_RX_DATA[2]),
      .hps_0_hps_io_hps_io_emac1_inst_RXD3  (HPS_ENET_RX_DATA[3]),
      .hps_0_hps_io_hps_io_qspi_inst_IO0    (HPS_FLASH_DATA[0]),
      .hps_0_hps_io_hps_io_qspi_inst_IO1    (HPS_FLASH_DATA[1]),
      .hps_0_hps_io_hps_io_qspi_inst_IO2    (HPS_FLASH_DATA[2]),
      .hps_0_hps_io_hps_io_qspi_inst_IO3    (HPS_FLASH_DATA[3]),
      .hps_0_hps_io_hps_io_qspi_inst_SS0    (HPS_FLASH_NCSO),
      .hps_0_hps_io_hps_io_qspi_inst_CLK    (HPS_FLASH_DCLK),
      .hps_0_hps_io_hps_io_sdio_inst_CMD    (HPS_SD_CMD),
      .hps_0_hps_io_hps_io_sdio_inst_D0     (HPS_SD_DATA[0]),
      .hps_0_hps_io_hps_io_sdio_inst_D1     (HPS_SD_DATA[1]),
      .hps_0_hps_io_hps_io_sdio_inst_CLK    (HPS_SD_CLK),
      .hps_0_hps_io_hps_io_sdio_inst_D2     (HPS_SD_DATA[2]),
      .hps_0_hps_io_hps_io_sdio_inst_D3     (HPS_SD_DATA[3]),
      .hps_0_hps_io_hps_io_usb1_inst_D0     (HPS_USB_DATA[0]),
      .hps_0_hps_io_hps_io_usb1_inst_D1     (HPS_USB_DATA[1]),
      .hps_0_hps_io_hps_io_usb1_inst_D2     (HPS_USB_DATA[2]),
      .hps_0_hps_io_hps_io_usb1_inst_D3     (HPS_USB_DATA[3]),
      .hps_0_hps_io_hps_io_usb1_inst_D4     (HPS_USB_DATA[4]),
      .hps_0_hps_io_hps_io_usb1_inst_D5     (HPS_USB_DATA[5]),
      .hps_0_hps_io_hps_io_usb1_inst_D6     (HPS_USB_DATA[6]),
      .hps_0_hps_io_hps_io_usb1_inst_D7     (HPS_USB_DATA[7]),
      .hps_0_hps_io_hps_io_usb1_inst_CLK    (HPS_USB_CLKOUT),
      .hps_0_hps_io_hps_io_usb1_inst_STP    (HPS_USB_STP),
      .hps_0_hps_io_hps_io_usb1_inst_DIR    (HPS_USB_DIR),
      .hps_0_hps_io_hps_io_usb1_inst_NXT    (HPS_USB_NXT),
      .hps_0_hps_io_hps_io_spim0_inst_CLK   (HPS_LCM_SPIM_CLK),
      .hps_0_hps_io_hps_io_spim0_inst_MOSI  (HPS_LCM_SPIM_MOSI),
      .hps_0_hps_io_hps_io_spim0_inst_MISO  (HPS_LCM_SPIM_MISO),
      .hps_0_hps_io_hps_io_spim0_inst_SS0   (HPS_LCM_SPIM_SS),
      .hps_0_hps_io_hps_io_spim1_inst_CLK   (HPS_SPIM_CLK),
      .hps_0_hps_io_hps_io_spim1_inst_MOSI  (HPS_SPIM_MOSI),
      .hps_0_hps_io_hps_io_spim1_inst_MISO  (HPS_SPIM_MISO),
      .hps_0_hps_io_hps_io_spim1_inst_SS0   (HPS_SPIM_SS),
      .hps_0_hps_io_hps_io_uart0_inst_RX    (HPS_UART_RX),
      .hps_0_hps_io_hps_io_uart0_inst_TX    (HPS_UART_TX),
      .hps_0_hps_io_hps_io_i2c0_inst_SDA    (HPS_I2C1_SDAT),
      .hps_0_hps_io_hps_io_i2c0_inst_SCL    (HPS_I2C1_SCLK),
      .hps_0_hps_io_hps_io_i2c1_inst_SDA    (HPS_I2C2_SDAT),
      .hps_0_hps_io_hps_io_i2c1_inst_SCL    (HPS_I2C2_SCLK),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO09 (HPS_CONV_USB_N),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO35 (HPS_ENET_INT_N),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO37 (HPS_LCM_BK),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO40 (HPS_LTC_GPIO),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO41 (HPS_LCM_D_C),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO44 (HPS_LCM_RST_N),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO48 (HPS_I2C_CONTROL),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO53 (HPS_LED),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO54 (HPS_KEY),
      .hps_0_hps_io_hps_io_gpio_inst_GPIO61 (HPS_GSENSOR_INT)
  );

  Accelerat_ip_src_Acceleration_Cores acceleration_cores_inst (
      .clk         (CLOCK_50),
      .reset       (reset),
      .clk_enable  (1'b1),
      .pixIn       (pix_in),
      .kernInCH1Re (kern_ch1_re),
      .kernInCH1Img(kern_ch1_im),
      .kernInCH2Re (kern_ch2_re),
      .kernInCH2Img(kern_ch2_im),
      .kernInCH3Re (kern_ch3_re),
      .kernInCH3Img(kern_ch3_im),
      .readyIn     (acc_ready),
      .start       (start),
      .ce_out      (ce_out),
      .validOut    (valid_out),
      .dataOut     (data_out),
      .readEnable  (read_enable),
      .kernAddr    (kern_addr),
      .cmacBusy    (cmac_busy),
      .fftBusy     (fft_busy)
  );

  // Full image: 227 x 227 input, 96 filters in 48 passes of 2
  acc2d #(
      .H        (227),
      .COUT     (96),
      .COUT_PASS(2)
  ) acc2d_inst (
      .clk              (CLOCK_50),
      .reset            (reset),
      .data_in          (data_out),
      .valid_in         (valid_out),
      .ready_out        (acc_ready),
      .img_done         (img_done),
      .avm_address      (acc_address),
      .avm_read         (acc_read),
      .avm_write        (acc_write),
      .avm_writedata    (acc_writedata),
      .avm_readdata     (acc_readdata),
      .avm_readdatavalid(acc_readdatavalid),
      .avm_waitrequest  (acc_waitrequest)
  );

endmodule
