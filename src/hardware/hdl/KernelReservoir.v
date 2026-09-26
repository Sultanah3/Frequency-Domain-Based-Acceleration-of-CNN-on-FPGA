/*
* Kernel reservoir for testing purposes
*/
module KernelReservoir (
    input         clk,
    input         read_enable,
    input  [ 7:0] kernel_type,
    input  [ 7:0] address_in,
    output [31:0] kernel_value
);

  // List all kernel filters or specify their address from SDRAM later.

  always @(posedge clk) begin
    // Switch to the wanted kernel using kernel_type
  end

endmodule
