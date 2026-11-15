/*
* Kernel reservoir for testing purposes
*/
module KernelReservoir (
    input          clk,
    input          read_enable,
    input  [  7:0] kernel_type,
    input  [ 14:0] address_in,
    output [ 95:0] kernel_value
);

  wire [15:0] ch1_re;
  wire [15:0] ch1_im;
  wire [15:0] ch2_re;
  wire [15:0] ch2_im;
  wire [15:0] ch3_re;
  wire [15:0] ch3_im;

  // One M10K ROM per Cin complex field (read-only). Address is shared;
  // read_enable / kernel_type are reserved for a later request sequencer.
  kern_ch1_re kern_ch1_re_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch1_re)
  );

  kern_ch1_im kern_ch1_im_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch1_im)
  );

  kern_ch2_re kern_ch2_re_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch2_re)
  );

  kern_ch2_im kern_ch2_im_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch2_im)
  );

  kern_ch3_re kern_ch3_re_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch3_re)
  );

  kern_ch3_im kern_ch3_im_inst (
      .address(address_in),
      .clock  (clk),
      .data   (16'd0),
      .wren   (1'b0),
      .q      (ch3_im)
  );

  // Same packing as kern.mif: {im2, re2, im1, re1, im0, re0}
  assign kernel_value = {ch3_im, ch3_re, ch2_im, ch2_re, ch1_im, ch1_re};

endmodule
