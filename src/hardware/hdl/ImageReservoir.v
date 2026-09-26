/*
* Images reservoir for testing purposes
*/
module ImageReservoir (
    input         clk,
    input         read_enable,
    input  [13:0] address_in,
    output [23:0] rgb_out
);


  // Testing memory block: Contains index_map for 128x128 image
  wire [7:0] color_address;
  index_map index_map_inst (
      .address(address_in),
      .clock  (clk),
      .data   (0),
      .rden   (read_enable),
      .wren   (0),
      .q      (color_address)
  );

  color_map color_map_inst (
      .address(color_address),
      .clock  (clk),
      .data   (data_sig),
      .wren   (0),
      .q      (rgb_out)
  );



endmodule
