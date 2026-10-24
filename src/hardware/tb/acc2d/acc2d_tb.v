`timescale 1ns / 1ps

// acc2d testbench.
// Plays acc2d_in.hex (the ifft2d stream from Simulink, written by
// gen_acc_vectors.m) with the ifft2d timing, models the SDRAM as an Avalon
// slave with random wait states, and writes the output image to
// acc2d_out.hex. The data are checked in MATLAB ("Show output image" in
// AcceleratationCore); this bench checks the protocol.
module acc2d_tb;

  localparam B = 64, K = 11, H = 227, COUT = 2;  // COUT = Cout in the model workspace
  localparam NC = B + K - 1, NT = (H + B - 1) / B, HO = H - K + 1, L = 128;
  localparam NBLK = NT * NT * COUT;  // blocks in the image
  localparam NPIX = COUT * HO * HO;  // output words
  localparam PERIOD = 17792;  // ifft2d: cycles between block starts
  localparam LAT_UP = 8935;  // block start at cmac2d to first ifft2d sample (gen_acc_vectors)
  localparam OUT_BASE = 32'h0200_0000;
  // Questa runs in simulation/ at the repo root (EDA output directory
  // ../simulation), one level down like quartus/, so this path and the IP
  // MIF paths (../resources/...) work from both tools
  localparam DIR = "../src/hardware/sim/";

  reg clk = 0, reset = 1;
  integer cyc = 0, seed = 1;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  initial #50 reset = 0;

  reg  signed [24:0] data_in;
  reg                valid_in = 0;
  wire               ready_out, img_done;
  wire        [31:0] avm_address, avm_writedata, avm_readdata;
  wire               avm_read, avm_write, avm_readdatavalid, avm_waitrequest;

  acc2d #(
      .B       (B),
      .K       (K),
      .H       (H),
      .COUT    (COUT),
      .OUT_BASE(OUT_BASE)
  ) dut (
      .clk              (clk),
      .reset            (reset),
      .data_in          (data_in),
      .valid_in         (valid_in),
      .ready_out        (ready_out),
      .img_done         (img_done),
      .avm_address      (avm_address),
      .avm_read         (avm_read),
      .avm_write        (avm_write),
      .avm_writedata    (avm_writedata),
      .avm_readdata     (avm_readdata),
      .avm_readdatavalid(avm_readdatavalid),
      .avm_waitrequest  (avm_waitrequest)
  );

  // ifft2d model: a block may start every PERIOD cycles while ready_out is
  // high (ready_out goes into cmac2d.readyIn). It arrives LAT_UP cycles later
  // as NC rows of NC valid samples, each followed by L - NC idle cycles.
  reg [24:0] stim[0:NBLK*NC*NC-1];
  integer start[0:NBLK-1];
  integer n_start = 0, last_start = -PERIOD, stalls = 0;
  integer blk, row, col, idx = 0;

  initial begin
    $readmemh({DIR, "acc2d_in.hex"}, stim);
    if (stim[0] === 25'bx) begin
      $display("ERROR: %0sacc2d_in.hex not found", DIR);
      $finish;
    end
  end

  always @(negedge clk)
    if (!reset && n_start < NBLK && cyc >= last_start + PERIOD) begin
      if (ready_out) begin
        start[n_start] = cyc;
        last_start     = cyc;
        n_start        = n_start + 1;
      end else stalls = stalls + 1;
    end

  initial begin
    wait (!reset);
    for (blk = 0; blk < NBLK; blk = blk + 1) begin
      wait (n_start > blk);
      while (cyc < start[blk] + LAT_UP) @(negedge clk);
      for (row = 0; row < NC; row = row + 1)
        for (col = 0; col < L; col = col + 1) begin
          @(negedge clk);
          valid_in = col < NC;
          data_in  = valid_in ? stim[idx] : $random(seed);  // idle cycles carry junk
          if (valid_in) idx = idx + 1;
        end
    end
    @(negedge clk) valid_in = 0;
  end

  // SDRAM model: Avalon-MM slave over the output region. Every request waits
  // 1 to 4 cycles, plus a 10-cycle refresh every 400 cycles; reads return
  // 4 cycles after they are accepted. Words start as DEADBEEF, so a missing
  // first write shows up as a wrong pixel.
  reg     [31:0] mem      [0:NPIX-1];
  reg     [31:0] rd_pipe  [0:3];
  reg     [ 3:0] rd_valid = 0;
  integer        wait_cnt = -1, i;

  initial for (i = 0; i < NPIX; i = i + 1) mem[i] = 32'hDEADBEEF;

  wire        req = avm_read || avm_write;
  wire        refresh = cyc % 400 < 10;
  wire [31:0] word = (avm_address - OUT_BASE) >> 2;
  wire        accept = req && !avm_waitrequest;
  assign avm_waitrequest = req && (wait_cnt != 0 || refresh);

  always @(posedge clk) begin
    if (accept) wait_cnt <= -1;
    else if (req && wait_cnt == -1) wait_cnt <= {$random(seed)} % 4;
    else if (wait_cnt > 0) wait_cnt <= wait_cnt - 1;

    rd_valid   <= {rd_valid[2:0], accept && avm_read};
    rd_pipe[0] <= mem[word];
    rd_pipe[1] <= rd_pipe[0];
    rd_pipe[2] <= rd_pipe[1];
    rd_pipe[3] <= rd_pipe[2];
    if (accept && avm_write) mem[word] <= avm_writedata;
  end

  assign avm_readdatavalid = rd_valid[3];
  assign avm_readdata      = rd_pipe[3];

  // Protocol checks
  integer errors = 0, done = 0, done_cyc = 0, after_done = 0, writes = 0, reads = 0, max_used = 0;
  reg held = 0, held_rd, held_wr;
  reg [31:0] held_addr, held_data;

  task fail(input [8*40-1:0] msg);
    begin
      errors = errors + 1;
      if (errors <= 10) $display("ERROR cycle %0d: %0s", cyc, msg);
    end
  endtask

  always @(posedge clk)
    if (!reset) begin
      if (dut.wr_q && dut.fifo_full) fail("FIFO overflow, sample lost");
      if (held && (avm_read != held_rd || avm_write != held_wr || avm_address != held_addr ||
                   (held_wr && avm_writedata != held_data)))
        fail("request changed during waitrequest");
      if (accept && (avm_address < OUT_BASE || word >= NPIX || avm_address[1:0] != 0))
        fail("access outside the output region");
      if (accept && done) after_done = after_done + 1;
      if (img_done) begin
        done     = done + 1;
        done_cyc = cyc;
      end
      writes = writes + (accept && avm_write);
      reads  = reads + (accept && avm_read);
      if (dut.fifo_usedw > max_used) max_used = dut.fifo_usedw;
      held      <= req && avm_waitrequest;
      held_rd   <= avm_read;
      held_wr   <= avm_write;
      held_addr <= avm_address;
      held_data <= avm_writedata;
    end

  task report;
    begin
      $writememh({DIR, "acc2d_out.hex"}, mem);
      $display("------------------ acc2d_tb ------------------");
      $display("samples in        : %0d of %0d", idx, NBLK * NC * NC);
      $display("blocks            : %0d of %0d", n_start, NBLK);
      $display("img_done pulses   : %0d (expect 1)", done);
      $display("accesses after it : %0d (expect 0)", after_done);
      $display("writes - reads    : %0d (expect %0d, one per pixel)", writes - reads, NPIX);
      $display("protocol errors   : %0d (expect 0)", errors);
      $display("done at cycle     : %0d", done_cyc);
      $display("stall cycles      : %0d", stalls);
      $display("FIFO max          : %0d of 16384", max_used);
      $display("output            : %0sacc2d_out.hex, check it in MATLAB", DIR);
      $display("-----------------------------------------------");
      $finish;
    end
  endtask

  initial begin
    wait (done);
    repeat (1000) @(posedge clk);
    report;
  end

  initial begin
    #(NBLK * PERIOD * 40);  // 4x the run time without stalls
    fail("timeout, img_done never came");
    report;
  end

endmodule