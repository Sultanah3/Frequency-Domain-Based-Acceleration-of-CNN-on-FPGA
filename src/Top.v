/*   ////=====================================
 *   ///  OaA-FFT Convolution Accelerator   //
 *   //             Top Module             ///
 *   =====================================////
 */

module Top (
    input main_clk,
    input reset_n
);

  wire               ce_out;
  wire               valid_out;
  wire signed [24:0] data_out;
  wire               read_enable;
  wire        [14:0] kern_addr;
  wire               cmac_busy;
  wire               fft_busy;
  wire               idle;
  wire               start;
  reg                idle_d;
  wire        [ 7:0] pix_in;
  wire        [95:0] kernel_value;
  wire signed [15:0] kern_ch1_re;
  wire signed [15:0] kern_ch1_im;
  wire signed [15:0] kern_ch2_re;
  wire signed [15:0] kern_ch2_im;
  wire signed [15:0] kern_ch3_re;
  wire signed [15:0] kern_ch3_im;
  reg         [17:0] img_addr;

  assign {kern_ch3_im, kern_ch3_re, kern_ch2_im, kern_ch2_re, kern_ch1_im, kern_ch1_re} =
      kernel_value;

  // start: Detect Rise on NOR(cmacBusy, fftBusy). Simulink's extra 1/z is omitted;
  // it only broke the algebraic loop.
  assign idle  = ~(cmac_busy | fft_busy);
  assign start = idle & ~idle_d;

  always @(posedge main_clk or negedge reset_n) begin
    if (!reset_n) idle_d <= 1'b0;
    else idle_d <= idle;
  end

  // For testing purposes only
  always @(posedge main_clk or negedge reset_n) begin
    if (!reset_n) img_addr <= 18'd0;
    else if (read_enable) begin
      if (img_addr == 18'd196607) img_addr <= 18'd0;
      else img_addr <= img_addr + 18'd1;
    end
  end

  fujian_mountain_256 fujian_mountain_256_inst (
      .address(img_addr),
      .clock  (main_clk),
      .data   (8'd0),
      .wren   (1'b0),
      .q      (pix_in)
  );
  // End of testing purposes only

  KernelReservoir kernel_reservoir_inst (
      .clk         (main_clk),
      .read_enable (read_enable),
      .kernel_type (8'd0),
      .address_in  (kern_addr),
      .kernel_value(kernel_value)
  );

  Accelerat_ip_src_Acceleration_Cores acceleration_cores_inst (
      .clk         (main_clk),
      .reset       (~reset_n),
      .clk_enable  (1'b1),
      .pixIn       (pix_in),
      .kernInCH1Re (kern_ch1_re),
      .kernInCH1Img(kern_ch1_im),
      .kernInCH2Re (kern_ch2_re),
      .kernInCH2Img(kern_ch2_im),
      .kernInCH3Re (kern_ch3_re),
      .kernInCH3Img(kern_ch3_im),
      .readyIn     (1'b1),
      .start       (start),
      .ce_out      (ce_out),
      .validOut    (valid_out),
      .dataOut     (data_out),
      .readEnable  (read_enable),
      .kernAddr    (kern_addr),
      .cmacBusy    (cmac_busy),
      .fftBusy     (fft_busy)
  );

endmodule
