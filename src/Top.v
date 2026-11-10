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
  wire        [ 7:0] pix_in;
  reg         [17:0] img_addr;

  // For testing purposes only
  always @(posedge main_clk or negedge reset_n) begin
    if (!reset_n) img_addr <= 18'd0;
    else if (read_enable) img_addr <= img_addr + 18'd1;
  end

  fujian_mountain_256 fujian_mountain_256_inst (
      .address(img_addr),
      .clock  (main_clk),
      .data   (8'd0),
      .wren   (1'b0),
      .q      (pix_in)
  );
  // End of testing purposes only

  Accelerat_ip_src_Acceleration_Cores acceleration_cores_inst (
      .clk       (main_clk),
      .reset     (~reset_n),
      .clk_enable(1'b1),
      .pixIn     (pix_in),
      .ce_out    (ce_out),
      .validOut  (valid_out),
      .dataOut   (data_out),
      .readEnable(read_enable)
  );

endmodule
