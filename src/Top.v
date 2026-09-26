/*   ////=====================================
 *   ///  OaA-FFT Convolution Accelerator   //
 *   //             Top Module             ///
 *   =====================================////
 */

module Top (
    input main_clk,
    input reset_n
);

  // FOR TESTING ONLY
  wire [23:0] rgb_reg;
  ImageReservoir image_reservoir_inst (
      .clk        (main_clk),
      .read_enable(1),
      .address_in (5),
      .rgb_out    (rgb_reg)
  );

  wire [13:0] pixel_address;
  AccelerationCore acceleration_core_inst (
      .clk          (main_clk),
      .reset_n      (reset_n),
      .kernel_pixel (0),
      .rgb_pixel    (0),
      .pixel_address(pixel_address)
  );

endmodule
