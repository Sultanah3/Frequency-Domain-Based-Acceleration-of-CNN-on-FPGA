// acc2d_tb: drives acc2d with a stream shaped like the ifft2d output, models
// the SDRAM, and compares the output region with the expected words.
//
//   stim.hex      16-bit samples: tile by tile, filter by filter, row-major
//   bias.hex      one 32-bit bias word per filter, placed at address 0
//   expected.hex  output words, filter by filter, row-major (217 x 217 each)
//
// The rest of the memory starts with random data, so the test also shows that
// acc2d does not rely on the output region being cleared.
//
// Run in Questa from src/hardware/tb/acc2d with altera_mf_ver as a search library.

`timescale 1ns/1ps

module acc2d_tb;

    parameter COUT    = 2;          // must match the vectors
    parameter WAITREQ = 1;          // 1: random waitrequest and read latency
    parameter SEED    = 1;
    parameter DIR     = "../../../../vectors/acc2d/";

    localparam B = 64, K = 11, H = 227, W = 227;
    localparam NC       = B + K - 1;
    localparam NS       = NC * NC;
    localparam L        = 1 << $clog2(NC);              // ifft2d frame length
    localparam TILES    = ((H + B - 1) / B) * ((W + B - 1) / B);
    localparam NOUT     = COUT * (H-K+1) * (W-K+1);     // output words
    localparam OUT_BASE = 32'h200;
    localparam MEMW     = OUT_BASE/4 + NOUT;

    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    reg  [15:0]             dataIn  = 0;
    reg                     validIn = 0;
    reg                     doneIn  = 0;
    reg  [$clog2(COUT)-1:0] mIdxIn  = 0;
    wire                    readyOut, imgDone;

    wire [31:0] address, writedata;
    wire        read, write;
    reg  [31:0] readdata      = 0;
    reg         readdatavalid = 0;
    reg         waitrequest   = 0;

    acc2d #(.B(B), .K(K), .H(H), .W(W), .COUT(COUT),
            .OUT_BASE(OUT_BASE), .BIAS_BASE(0)) dut (
        .clk(clk), .reset(reset),
        .dataIn(dataIn), .validIn(validIn), .doneIn(doneIn), .mIdxIn(mIdxIn),
        .readyOut(readyOut),
        .avm_address(address), .avm_read(read), .avm_write(write),
        .avm_writedata(writedata), .avm_readdata(readdata),
        .avm_readdatavalid(readdatavalid), .avm_waitrequest(waitrequest),
        .imgDone(imgDone)
    );

    // SDRAM model, one pending read
    reg [31:0] mem  [0:MEMW-1];
    reg [31:0] exp  [0:NOUT-1];
    reg [15:0] stim [0:TILES*COUT*NS-1];
    integer seed = SEED, rdAddr = 0, rdWait = 0;

    always @(posedge clk) begin
        readdatavalid <= 0;
        if (rdWait > 0) begin
            rdWait = rdWait - 1;
            if (rdWait == 0) begin
                readdata      <= mem[rdAddr];
                readdatavalid <= 1;
            end
        end
        if (!waitrequest) begin
            if (read) begin
                rdAddr = address / 4;
                rdWait = WAITREQ ? 1 + ($random(seed) & 7) : 1;
            end
            if (write) mem[address / 4] <= writedata;
        end
        waitrequest <= WAITREQ ? (($random(seed) & 3) == 0) : 0;
    end

    // imgDone is a one-cycle pulse and can come before the last frame ends
    reg finished = 0;
    always @(posedge clk)
        if (imgDone) finished <= 1;

    // Stimulus: each spectrum starts when readyOut is high, then NC frames of
    // L cycles with NC valid samples each, like ifft2d
    integer t, f, row, col, i, bad;

    initial begin
        for (i = 0; i < MEMW; i = i + 1)
            mem[i] = $random(seed);
        $readmemh({DIR, "bias.hex"}, mem, 0, COUT-1);
        $readmemh({DIR, "stim.hex"}, stim);
        $readmemh({DIR, "expected.hex"}, exp);
        if (^stim[0] === 1'bx || ^exp[0] === 1'bx) begin
            $display("acc2d_tb: cannot read the files in %s", DIR);
            $finish;
        end
        repeat (5) @(posedge clk);
        reset <= 0;

        for (t = 0; t < TILES; t = t + 1)
            for (f = 0; f < COUT; f = f + 1) begin
                @(posedge clk);
                while (!readyOut) @(posedge clk);
                for (row = 0; row < NC; row = row + 1)
                    for (col = 0; col < L; col = col + 1) begin
                        validIn <= col < NC;
                        doneIn  <= row == NC-1 && col == NC-1;
                        dataIn  <= (col < NC) ? stim[(t*COUT + f)*NS + row*NC + col] : 0;
                        mIdxIn  <= f;
                        @(posedge clk);
                    end
                validIn <= 0;
                doneIn  <= 0;
            end

        wait (finished);
        @(posedge clk);

        // Compare the output region with the expected words
        bad = 0;
        for (i = 0; i < NOUT; i = i + 1)
            if (mem[OUT_BASE/4 + i] !== exp[i]) begin
                if (bad < 5)
                    $display("  word %0d: got %h, expected %h", i, mem[OUT_BASE/4 + i], exp[i]);
                bad = bad + 1;
            end

        if (bad == 0)
            $display("acc2d_tb: PASS, %0d words match (COUT = %0d, WAITREQ = %0d)", NOUT, COUT, WAITREQ);
        else
            $display("acc2d_tb: FAIL, %0d of %0d words differ", bad, NOUT);
        $finish;
    end

    // Stop if nothing moves for a long time
    integer idle = 0;
    always @(posedge clk) begin
        idle = (write || validIn) ? 0 : idle + 1;
        if (idle > 100000) begin
            $display("acc2d_tb: FAIL, stalled at %0d ns", $time);
            $finish;
        end
    end

endmodule