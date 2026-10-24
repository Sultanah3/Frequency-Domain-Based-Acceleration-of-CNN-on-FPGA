`timescale 1ns / 1ps

// Overlap-add accumulator.
// Adds every NC x NC block from ifft2d into the output image in SDRAM.
// The first touch of a pixel writes sample + bias; later touches read, add
// and write. Blocks arrive tile by tile in raster order, all COUT filters of
// a tile before the next one.
//   address = OUT_BASE + 4 * (m * HO * HO + row * HO + col)
// ready_out drops when the FIFO has no room for two more blocks.
module acc2d #(
    parameter B        = 64,
    parameter K        = 11,
    parameter H        = 227,
    parameter COUT     = 96,
    parameter OUT_BASE = 32'h0
) (
    input  wire               clk,
    input  wire               reset,
    input  wire signed [24:0] data_in,
    input  wire               valid_in,
    output wire               ready_out,
    output reg                img_done,
    output wire        [31:0] avm_address,
    output wire               avm_read,
    output wire               avm_write,
    output wire        [31:0] avm_writedata,
    input  wire        [31:0] avm_readdata,
    input  wire               avm_readdatavalid,
    input  wire               avm_waitrequest
);

  localparam NC = B + K - 1;  // block side
  localparam NT = (H + B - 1) / B;  // tiles per side
  localparam HO = H - K + 1;  // output side
  localparam GW = $clog2(NT * B + K);  // full-convolution coordinate width

  // Position of the incoming sample: column c and row r in the block,
  // filter m, tile column tc and tile row tr
  reg [$clog2(NC)-1:0] c, r;
  reg [6:0] m;
  reg [$clog2(NT)-1:0] tc, tr;

  wire c_end = c == NC - 1;
  wire r_end = r == NC - 1;
  wire m_end = m == COUT - 1;
  wire tc_end = tc == NT - 1;

  always @(posedge clk or posedge reset)
    if (reset) {tr, tc, m, r, c} <= 0;
    else if (valid_in) begin
      c <= c_end ? 0 : c + 1'b1;
      if (c_end) begin
        r <= r_end ? 0 : r + 1'b1;
        if (r_end) begin
          m <= m_end ? 0 : m + 1'b1;
          if (m_end) begin
            tc <= tc_end ? 0 : tc + 1'b1;
            if (tc_end) tr <= tr == NT - 1 ? 0 : tr + 1'b1;
          end
        end
      end
    end

  // Crop to the valid region, first touch (the tiles above and to the left
  // came earlier) and the word address of the pixel
  wire [GW-1:0] gr = tr * B + r;
  wire [GW-1:0] gc = tc * B + c;
  wire keep = gr >= K - 1 && gr < K - 1 + HO && gc >= K - 1 && gc < K - 1 + HO;
  wire first = (r >= K - 1 || tr == 0) && (c >= K - 1 || tc == 0);
  wire [22:0] addr = m * HO * HO + (gr - (K - 1)) * HO + (gc - (K - 1));

  // One register stage, so the sample meets its bias (bias_rom registers
  // the address)
  reg               wr_q;
  reg               first_q;
  reg        [22:0] addr_q;
  reg signed [24:0] data_q;
  wire signed [15:0] bias;

  always @(posedge clk or posedge reset)
    if (reset) wr_q <= 1'b0;
    else wr_q <= valid_in && keep;

  always @(posedge clk) begin
    first_q <= first;
    addr_q  <= addr;
    data_q  <= data_in;
  end

  bias_rom u_bias_rom (
      .address(m),
      .clock  (clk),
      .q      (bias)
  );

  wire signed [25:0] sum = data_q + (first_q ? bias : 16'sd0);

  // FIFO word: {addr[22:0], first, sum[25:0]}
  localparam IDLE = 2'd0, RD = 2'd1, RD_WAIT = 2'd2, WR = 2'd3;
  reg  [ 1:0] state;
  wire [49:0] fifo_q;
  wire [13:0] fifo_usedw;
  wire        fifo_empty, fifo_full, fifo_almost_full;
  wire        fifo_rd = state == IDLE && !fifo_empty;

  acc2d_fifo u_fifo (
      .aclr       (reset),
      .clock      (clk),
      .data       ({addr_q, first_q, sum}),
      .wrreq      (wr_q),
      .rdreq      (fifo_rd),
      .almost_full(fifo_almost_full),
      .empty      (fifo_empty),
      .full       (fifo_full),
      .q          (fifo_q),
      .usedw      (fifo_usedw)
  );

  assign ready_out = !fifo_almost_full;

  // Memory side: write on the first touch, otherwise read, add and write.
  // Avalon requests are held while waitrequest is high.
  reg [22:0] wr_addr;
  reg [31:0] wdata;

  always @(posedge clk or posedge reset)
    if (reset) state <= IDLE;
    else
      case (state)
        IDLE:    if (!fifo_empty) state <= fifo_q[26] ? WR : RD;
        RD:      if (!avm_waitrequest) state <= RD_WAIT;
        RD_WAIT: if (avm_readdatavalid) state <= WR;
        WR:      if (!avm_waitrequest) state <= IDLE;
      endcase

  always @(posedge clk)
    if (state == IDLE) begin
      wr_addr <= fifo_q[49:27];
      wdata   <= $signed(fifo_q[25:0]);
    end else if (state == RD_WAIT && avm_readdatavalid) wdata <= wdata + avm_readdata;

  // The last output pixel belongs to the last tile only, so its write ends the image
  always @(posedge clk or posedge reset)
    if (reset) img_done <= 1'b0;
    else img_done <= state == WR && !avm_waitrequest && wr_addr == COUT * HO * HO - 1;

  assign avm_address   = OUT_BASE + {wr_addr, 2'b00};
  assign avm_read      = state == RD;
  assign avm_write     = state == WR;
  assign avm_writedata = wdata;

endmodule