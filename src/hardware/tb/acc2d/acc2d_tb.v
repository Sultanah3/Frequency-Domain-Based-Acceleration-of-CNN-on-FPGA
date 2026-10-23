`timescale 1ns/1ps

// acc2d_tb: acc2d driven by the real ifft2d stream, with an Avalon SDRAM model.
//
// Folder : DIR, relative to the Questa working folder (NativeLink runs in
//          hdl/acc2d/simulation/questa, so DIR points at src/hardware/sim)
// Inputs : acc2d_in.hex  every valid ifft2d sample of the whole image, in
//                        arrival order, 25-bit two's complement hex
//          bias.mif      bias ROM contents (read by the design itself)
// Output : acc2d_out.hex the output region after the run, one 32-bit word per
//                        pixel, packed (m, row, col)
//
// The data verdict is made in MATLAB against an independent overlap-add of
// the same samples and against the Phase 1 golden. This bench checks what
// MATLAB cannot see: lost samples, Avalon protocol, address range, imgDone.

module acc2d_tb;

    // ---------------- Design parameters (match acc2d) ----------------
    localparam B        = 64;
    localparam K        = 11;
    localparam H        = 227;
    localparam Cout     = 2;              // = Cout in the model workspace
    localparam IF_WL    = 18;
    localparam LOG2L    = 7;
    localparam BIAS_WL  = 14;             // printed by gen_acc_vectors (13 for Cout = 2, 14 for 96)
    localparam OUT_BASE = 32'h0200_0000;  // upper half of the 64 MB SDRAM, as in the real map
    localparam NFLY     = 1;
    localparam FIFO_AW  = 14;
    localparam DIR      = "../../../../sim/";

    localparam NC    = B + K - 1;         // 74
    localparam NT    = (H + B - 1) / B;   // 4
    localparam HO    = H - K + 1;         // 217
    localparam DW    = IF_WL + LOG2L;     // 25
    localparam NSPEC = NT * NT * Cout;    // 1536 spectra
    localparam NSAMP = NSPEC * NC * NC;   // samples in acc2d_in.hex
    localparam NPIX  = Cout * HO * HO;    // words in acc2d_out.hex

    // ---------------- Upstream timing (ifft2d contract) ----------------
    localparam ROWLEN = 128;              // 74 valid then 54 idle cycles per row
    localparam PERIOD = 17792;            // cycles between spectrum starts
    localparam LAT_UP = 8935;             // measured in Simulink: first cmacValid to first ifftValid

    // ---------------- SDRAM model (stress settings, not SDRAM facts) ----
    localparam RD_LAT    = 4;             // accepted read to readdatavalid
    localparam WAIT_MAX  = 3;             // random extra waitrequest cycles per request
    localparam REF_EVERY = 400;           // a blocking window every REF_EVERY cycles
    localparam REF_LEN   = 10;            // length of the blocking window

    // ---------------- Clock, reset, cycle counter ----------------
    reg     clk   = 1'b0;
    reg     reset = 1'b1;
    integer cyc   = 0;
    integer seed  = 1;

    always #5 clk = ~clk;
    always @(posedge clk) cyc <= cyc + 1;

    initial begin
        repeat (5) @(negedge clk);
        reset = 1'b0;
    end

    // ---------------- DUT ----------------
    reg  signed [DW-1:0] dataIn;
    reg                  validIn;
    wire                 readyOut, imgDone;
    wire [31:0]          avm_address, avm_writedata, avm_readdata;
    wire                 avm_read, avm_write, avm_readdatavalid, avm_waitrequest;

    acc2d #(
        .B(B), .K(K), .H(H), .Cout(Cout), .IF_WL(IF_WL), .LOG2L(LOG2L),
        .BIAS_WL(BIAS_WL), .BIAS_FILE({DIR, "bias.mif"}), .OUT_BASE(OUT_BASE), .NFLY(NFLY), .FIFO_AW(FIFO_AW)
    ) dut (
        .clk               (clk),
        .reset             (reset),
        .dataIn            (dataIn),
        .validIn           (validIn),
        .readyOut          (readyOut),
        .imgDone           (imgDone),
        .avm_address       (avm_address),
        .avm_read          (avm_read),
        .avm_write         (avm_write),
        .avm_writedata     (avm_writedata),
        .avm_readdata      (avm_readdata),
        .avm_readdatavalid (avm_readdatavalid),
        .avm_waitrequest   (avm_waitrequest)
    );

    // ---------------- Upstream model ----------------
    // Launch: a new spectrum may enter the chain once per PERIOD, and only
    // while readyOut is high (readyOut is ANDed into cmac2d.readyIn).
    // Arrival: it reaches acc2d LAT_UP cycles after its launch.
    reg [DW-1:0] stim [0:NSAMP-1];
    integer      arrive [0:NSPEC-1];
    integer      nLaunch = 0, lastLaunch = 0, stallCyc = 0;
    integer      s, row, col, idx = 0;

    initial begin
        $readmemh({DIR, "acc2d_in.hex"}, stim);
        if (stim[0] === {DW{1'bx}}) begin
            $display("ERROR: %0sacc2d_in.hex not found or empty", DIR);
            $finish;
        end
    end

    always @(negedge clk)
        if (!reset && nLaunch < NSPEC &&
            (nLaunch == 0 || cyc >= lastLaunch + PERIOD)) begin
            if (readyOut) begin
                arrive[nLaunch] = cyc + LAT_UP;
                lastLaunch      = cyc;
                nLaunch         = nLaunch + 1;
            end else
                stallCyc = stallCyc + 1;
        end

    // Emission: rows of 74 valid samples and 54 idle cycles; idle cycles
    // carry junk data, so the design must look at validIn only
    initial begin
        validIn = 1'b0;
        dataIn  = 0;
        wait (!reset);
        for (s = 0; s < NSPEC; s = s + 1) begin
            wait (nLaunch > s);
            while (cyc < arrive[s]) @(negedge clk);
            for (row = 0; row < NC; row = row + 1)
                for (col = 0; col < ROWLEN; col = col + 1) begin
                    @(negedge clk);
                    if (col < NC) begin
                        validIn = 1'b1;
                        dataIn  = stim[idx];
                        idx     = idx + 1;
                    end else begin
                        validIn = 1'b0;
                        dataIn  = $random(seed);
                    end
                end
        end
        @(negedge clk);
        validIn = 1'b0;
    end

    // ---------------- SDRAM model (Avalon-MM slave) ----------------
    // Output region only. Unwritten words start as DEADBEEF, not zero, so a
    // missing first write shows up as a wrong pixel instead of hiding.
    // Every request waits at least one cycle (a 32-bit word is two beats on
    // the 16-bit chip), plus a random number of cycles, plus refresh windows.
    reg  [31:0] mem [0:NPIX-1];
    reg  [31:0] rdData  [0:RD_LAT-1];
    reg         rdValid [0:RD_LAT-1];
    integer     i;

    initial begin
        for (i = 0; i < NPIX;   i = i + 1) mem[i]     = 32'hDEADBEEF;
        for (i = 0; i < RD_LAT; i = i + 1) rdValid[i] = 1'b0;
    end

    wire        req     = avm_read | avm_write;
    wire        refresh = (cyc % REF_EVERY) < REF_LEN;
    reg         seen;
    integer     hold;

    assign avm_waitrequest = req && (!seen || hold != 0 || refresh);
    wire   accept          = req && !avm_waitrequest;

    always @(posedge clk)
        if (reset) begin
            seen <= 1'b0;
            hold <= 0;
        end else if (accept)
            seen <= 1'b0;
        else if (req && !seen) begin
            seen <= 1'b1;
            hold <= {$random(seed)} % (WAIT_MAX + 1);
        end else if (hold != 0)
            hold <= hold - 1;

    wire [31:0] off     = avm_address - OUT_BASE;
    wire        inRange = (avm_address >= OUT_BASE) && (off < 4*NPIX) && (off[1:0] == 2'b00);

    integer k;
    always @(posedge clk) begin
        for (k = RD_LAT-1; k > 0; k = k - 1) begin
            rdValid[k] <= rdValid[k-1];
            rdData[k]  <= rdData[k-1];
        end
        rdValid[0] <= accept && avm_read;
        rdData[0]  <= mem[off >> 2];
        if (accept && avm_write && inRange)
            mem[off >> 2] <= avm_writedata;
    end

    assign avm_readdatavalid = rdValid[RD_LAT-1];
    assign avm_readdata      = rdData[RD_LAT-1];

    // ---------------- Checks ----------------
    integer    errors = 0, nDone = 0, doneCyc = 0, accAfterDone = 0;
    integer    nWr = 0, nRd = 0, used, maxUsed = 0;
    reg        pWait = 1'b0, pRd, pWr;
    reg [31:0] pAddr, pData;

    task fail(input [8*40-1:0] msg);
        begin
            errors = errors + 1;
            if (errors <= 10) $display("ERROR cycle %0d: %0s", cyc, msg);
        end
    endtask

    always @(posedge clk) if (!reset) begin
        // 1. No pushed word may be dropped at the FIFO
        if (dut.push && dut.fFull) fail("FIFO overflow, sample lost");

        // 2. Avalon: a request held by waitrequest must not change
        if (pWait && (avm_read != pRd || avm_write != pWr || avm_address != pAddr ||
                      (pWr && avm_writedata != pData)))
            fail("request changed while waitrequest");

        // 3. Every access stays inside the output region, word aligned
        if (accept && !inRange) fail("access outside the output region");

        // 4. imgDone exactly once, and no access after it
        if (imgDone) begin
            nDone = nDone + 1;
            if (nDone == 1) doneCyc = cyc;
        end
        if (accept && nDone > 0) accAfterDone = accAfterDone + 1;

        // Measurements
        if (accept && avm_write) nWr = nWr + 1;
        if (accept && avm_read)  nRd = nRd + 1;
        used = dut.fFull ? (1 << FIFO_AW) : dut.fUsed;
        if (used > maxUsed) maxUsed = used;

        pWait <= req && avm_waitrequest;
        pRd   <= avm_read;
        pWr   <= avm_write;
        pAddr <= avm_address;
        pData <= avm_writedata;
    end

    // ---------------- End of run ----------------
    task report;
        begin
            $writememh({DIR, "acc2d_out.hex"}, mem);
            $display("---------------- acc2d_tb ----------------");
            $display("samples sent      %0d of %0d", idx, NSAMP);
            $display("spectra launched  %0d of %0d", nLaunch, NSPEC);
            $display("imgDone pulses    %0d (expected 1)", nDone);
            $display("accesses after    %0d (expected 0)", accAfterDone);
            $display("writes / reads    %0d / %0d", nWr, nRd);
            $display("done at cycle     %0d (no-stall pace %0d)", doneCyc, NSPEC * PERIOD + LAT_UP);
            $display("launch stalls     %0d cycles", stallCyc);
            $display("max FIFO words    %0d of %0d", maxUsed, 1 << FIFO_AW);
            $display("protocol errors   %0d", errors);
            $display("data verdict: compare acc2d_out.hex in MATLAB");
        end
    endtask

    initial begin
        wait (nDone > 0);
        repeat (1000) @(posedge clk);
        if (idx != NSAMP) fail("not all samples were sent");
        report;
        $finish;
    end

    initial begin
        #(10 * NSPEC * PERIOD * 4);
        fail("timeout, imgDone never came");
        report;
        $finish;
    end

endmodule