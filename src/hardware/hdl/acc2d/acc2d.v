`timescale 1ns/1ps

// acc2d: overlap-add accumulator of the OaA-FFT core.
//
// Takes the ifft2d stream (one NC x NC block per spectrum, row-major) and
// adds every block into the conv1 output image held in SDRAM:
//   first touch of a pixel : write (sample + bias)
//   later touches          : read, add, write
// Output layout (packed, one 32-bit word per pixel):
//   addr = OUT_BASE + 4*(m*HO*HO + row*HO + col)
// Real value of a word: word * 2^-13 (same scale as the ifft2d output).
//
// Contract: tiles in raster order, all Cout filters of a tile before the
// next tile; readyOut is ANDed into cmac2d.readyIn, so the chain starts a
// spectrum only while readyOut is high.
// imgDone pulses when the write of the last output pixel is accepted.
//
// Sections: (1) Position  (2) PixelMap  (3) SampleFIFO  (4) MemWorker

module acc2d #(
    parameter B        = 64,
    parameter K        = 11,
    parameter H        = 227,           // image size (square)
    parameter Cout     = 96,
    parameter IF_WL    = 18,
    parameter LOG2L    = 7,
    parameter BIAS_WL  = 14,            // bias word: max |round(b*2^13)| = 6561 < 2^13
    parameter BIAS_FILE = "bias.mif",    // bias ROM contents, path relative to the tool working folder
    parameter OUT_BASE = 32'h0000_0000, // byte address of the output image
    parameter NFLY     = 1,             // spectra still arriving at a launch: ceil((LAT_UP+NC*L)/17792)-1, measured LAT_UP 8935
    parameter FIFO_AW  = 14             // FIFO depth = 2^FIFO_AW, must exceed (NFLY+1)*NC*NC
) (
    input                           clk,
    input                           reset,

    input  signed [IF_WL+LOG2L-1:0] dataIn,
    input                           validIn,
    output                          readyOut,

    output                          imgDone,

    output [31:0]                   avm_address,
    output                          avm_read,
    output                          avm_write,
    output [31:0]                   avm_writedata,
    input  [31:0]                   avm_readdata,
    input                           avm_readdatavalid,
    input                           avm_waitrequest
);

    // Derived sizes
    localparam NC      = B + K - 1;                      // 74, block side
    localparam NT      = (H + B - 1) / B;                // 4, tiles per side
    localparam HO      = H - K + 1;                      // 217, valid output side
    localparam NW      = $clog2(NC);                     // 7, block counters
    localparam MW      = (Cout > 1) ? $clog2(Cout) : 1;  // 7, filter counter (1 bit when Cout = 1)
    localparam TW      = $clog2(NT);                     // 2, tile counters
    localparam GW      = $clog2((NT-1)*B + NC);          // 9, full-conv coordinate
    localparam OW      = $clog2(HO);                     // 8, output row/col
    localparam WAW     = $clog2(Cout*HO*HO);             // 23, word address
    localparam DW      = IF_WL + LOG2L;                  // 25, input sample
    localparam DW1     = DW + 1;                         // 26, sample + bias
    localparam WORDW   = WAW + 1 + DW1;                  // 50, FIFO word
    localparam DEPTH   = 1 << FIFO_AW;                   // 16384, FIFO words
    localparam SPEC    = NC * NC;                        // 5476, most samples one spectrum can push
    localparam ROOM    = DEPTH - (NFLY + 1) * SPEC;      // readyOut threshold on usedw
    localparam LAST_WA = Cout*HO*HO - 1;                 // word address of the last output pixel

    // =====================================================================
    // (1) Position: cascaded counters c -> r -> m -> tc -> tr
    // Counts valid samples only. A counter steps when every counter before
    // it is at its last value. The registers always hold the position of
    // the sample that is on dataIn now.
    // =====================================================================
    reg [NW-1:0] c, r;      // column and row inside the NC x NC block
    reg [MW-1:0] m;         // filter
    reg [TW-1:0] tc, tr;    // tile column and tile row

    wire cEnd   = (c  == NC-1);
    wire rEnd   = (r  == NC-1);
    wire mEnd   = (m  == Cout-1);
    wire tcEnd  = (tc == NT-1);
    wire trEnd  = (tr == NT-1);

    wire cStep  = validIn;
    wire rStep  = cStep  & cEnd;
    wire mStep  = rStep  & rEnd;
    wire tcStep = mStep  & mEnd;
    wire trStep = tcStep & tcEnd;

    always @(posedge clk or posedge reset)
        if (reset) begin
            c  <= 0;
            r  <= 0;
            m  <= 0;
            tc <= 0;
            tr <= 0;
        end else begin
            if (cStep)  c  <= cEnd  ? 0 : c  + 1'b1;
            if (rStep)  r  <= rEnd  ? 0 : r  + 1'b1;
            if (mStep)  m  <= mEnd  ? 0 : m  + 1'b1;
            if (tcStep) tc <= tcEnd ? 0 : tc + 1'b1;
            if (trStep) tr <= trEnd ? 0 : tr + 1'b1;
        end

    // =====================================================================
    // (2) PixelMap: where the sample goes and whether it is a first touch
    // Stage 0 (combinational): full-conv coordinate, crop, first, address.
    // Stage A (register): the ROM input register delays m by one cycle,
    // so the stage A register lines the sample up with its bias.
    // =====================================================================

    // Full linear convolution coordinate of the sample (tr*B is a shift)
    wire [GW-1:0] gr = tr * B + r;
    wire [GW-1:0] gc = tc * B + c;

    // Crop: keep only the stride-1 valid region, rows/cols K-1 .. K-1+HO-1
    wire keep = (gr >= K-1) && (gr < K-1+HO) &&
                (gc >= K-1) && (gc < K-1+HO);

    // First touch: the tile above and the tile on the left come earlier,
    // so a pixel inside their K-1 margin has already been written
    wire first = (r >= K-1 || tr == 0) && (c >= K-1 || tc == 0);

    // Word address inside the output image (packed HO x HO per filter)
    wire [OW-1:0]  row = gr - (K-1);
    wire [OW-1:0]  col = gc - (K-1);
    wire [WAW-1:0] wa  = m * (HO*HO) + row * HO + col;

    // Stage A register
    reg           pushA;
    reg           firstA;
    reg [WAW-1:0] waA;
    reg [DW-1:0]  dataA;

    always @(posedge clk or posedge reset)
        if (reset) pushA <= 1'b0;
        else       pushA <= validIn & keep;

    always @(posedge clk) begin
        firstA <= first;
        waA    <= wa;
        dataA  <= dataIn;
    end

    // Bias ROM: address m, one cycle latency, contents from BIAS_FILE
    // (two's complement, Cout words of BIAS_WL bits)
    wire [BIAS_WL-1:0] biasQ;

    altsyncram #(
        .operation_mode         ("ROM"),
        .width_a                (BIAS_WL),
        .widthad_a              (MW),
        .numwords_a             (Cout),
        .outdata_reg_a          ("UNREGISTERED"),
        .init_file              (BIAS_FILE),
        .intended_device_family ("Cyclone V"),
        .lpm_type               ("altsyncram")
    ) biasRom (
        .clock0    (clk),
        .address_a (m),
        .q_a       (biasQ)
    );

    // Sample + bias on first touch (explicit sign extension to DW1)
    wire [DW1-1:0] biasX = {{(DW1-BIAS_WL){biasQ[BIAS_WL-1]}}, biasQ};
    wire [DW1-1:0] dataX = {dataA[DW-1], dataA};
    wire [DW1-1:0] dataB = dataX + (firstA ? biasX : {DW1{1'b0}});

    // To SampleFIFO
    wire             push = pushA;
    wire [WORDW-1:0] word = {waA, firstA, dataB};

    // =====================================================================
    // (3) SampleFIFO: waiting room between the stream and the SDRAM
    // Show-ahead scfifo: q holds the head word whenever empty is low, and
    // pop removes it. readyOut tells upstream there is room for every
    // spectrum already in flight plus one more.
    // =====================================================================
    wire [WORDW-1:0]   fq;
    wire               fEmpty, fFull;
    wire [FIFO_AW-1:0] fUsed;
    wire               pop;

    scfifo #(
        .lpm_width              (WORDW),
        .lpm_numwords           (DEPTH),
        .lpm_widthu             (FIFO_AW),
        .lpm_showahead          ("ON"),
        .intended_device_family ("Cyclone V"),
        .lpm_type               ("scfifo")
    ) sampleFifo (
        .clock (clk),
        .aclr  (reset),
        .sclr  (1'b0),
        .data  (word),
        .wrreq (push),
        .rdreq (pop),
        .q     (fq),
        .empty (fEmpty),
        .full  (fFull),
        .usedw (fUsed)
    );

    // usedw wraps to 0 when the FIFO is full, so full is checked too
    assign readyOut = !fFull && (fUsed <= ROOM);

    // =====================================================================
    // (4) MemWorker: one word at a time
    // IDLE: pop the head word; first touch goes straight to WR, else RD.
    // RD:   issue the read.   RDW: wait for the data, add the sample.
    // WR:   issue the write.  Avalon holds each request while waitrequest
    //       is high, which the state registers do by not moving.
    // =====================================================================
    localparam IDLE = 2'd0, RD = 2'd1, RDW = 2'd2, WR = 2'd3;

    reg [1:0]     state;
    reg [WAW-1:0] waR;      // word address of the current pixel
    reg [31:0]    wdata;    // sample (+ bias), then the sum to write
    reg           imgDoneR;

    // Fields of the head word
    wire [WAW-1:0] fWa    = fq[WORDW-1 -: WAW];
    wire           fFirst = fq[DW1];
    wire [DW1-1:0] fData  = fq[DW1-1:0];

    assign pop = (state == IDLE) && !fEmpty;

    always @(posedge clk or posedge reset)
        if (reset) state <= IDLE;
        else case (state)
            IDLE: if (!fEmpty)           state <= fFirst ? WR : RD;
            RD:   if (!avm_waitrequest)  state <= RDW;
            RDW:  if (avm_readdatavalid) state <= WR;
            WR:   if (!avm_waitrequest)  state <= IDLE;
        endcase

    // The head word is captured every IDLE cycle; it only matters on the
    // cycle that pops, which is the cycle that leaves IDLE. On the RD path
    // wdata still holds the sample when the old value arrives.
    always @(posedge clk) begin
        if (state == IDLE) begin
            waR   <= fWa;
            wdata <= {{(32-DW1){fData[DW1-1]}}, fData};
        end
        if (state == RDW && avm_readdatavalid)
            wdata <= avm_readdata + wdata;
    end

    // The last output pixel is touched by the last tile only and is the
    // last word pushed, so its accepted write ends the image
    always @(posedge clk or posedge reset)
        if (reset) imgDoneR <= 1'b0;
        else       imgDoneR <= (state == WR) && !avm_waitrequest && (waR == LAST_WA);

    assign imgDone       = imgDoneR;
    assign avm_address   = OUT_BASE + {waR, 2'b00};
    assign avm_read      = (state == RD);
    assign avm_write     = (state == WR);
    assign avm_writedata = wdata;

endmodule