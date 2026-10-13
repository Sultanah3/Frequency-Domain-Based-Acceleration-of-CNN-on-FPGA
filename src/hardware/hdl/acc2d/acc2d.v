// acc2d: overlap-add, crop and bias for the OaA-FFT core.
//
// Takes the ifft2d stream (NC x NC samples per spectrum, row-major) and
// accumulates it in SDRAM through an Avalon-MM master. Each output pixel is
// a 32-bit word with the same fraction bits as the input:
//     addr = OUT_BASE + 4*(m*HO*WO + row*WO + col)
// The first touch of a pixel writes it, later touches do read-add-write.
// The bias is read from BIAS_BASE + 4*m and added at the last touch.
//
// Tiles must arrive in raster order, all COUT filters of a tile before the
// next tile. Upstream starts a new spectrum only while readyOut is high.
// Avalon: byte addresses, one pending read. scfifo is from altera_mf.

module acc2d #(
    parameter B         = 64,
    parameter K         = 11,
    parameter H         = 227,
    parameter W         = 227,
    parameter COUT      = 96,
    parameter DW        = 16,        // input word (WL_SYS)
    parameter SLACK     = 512,       // samples ifft2d still sends after its readyOut rises
    parameter OUT_BASE  = 32'h200,
    parameter BIAS_BASE = 32'h0
) (
    input                     clk,
    input                     reset,

    input  [DW-1:0]           dataIn,
    input                     validIn,
    input                     doneIn,
    input  [$clog2(COUT)-1:0] mIdxIn,
    output reg                readyOut,

    output [31:0]             avm_address,
    output                    avm_read,
    output                    avm_write,
    output [31:0]             avm_writedata,
    input  [31:0]             avm_readdata,
    input                     avm_readdatavalid,
    input                     avm_waitrequest,

    output reg                imgDone
);

    localparam NC    = B + K - 1;           // 74
    localparam HO    = H - K + 1;           // 217
    localparam WO    = W - K + 1;           // 217
    localparam TR    = (H + B - 1) / B;     // 4
    localparam TC    = (W + B - 1) / B;     // 4
    localparam MW    = $clog2(COUT);
    localparam NW    = $clog2(NC);
    localparam TW    = $clog2(TR > TC ? TR : TC) + 1;
    localparam AW    = $clog2(NC*NC + SLACK + 1);
    localparam DEPTH = 1 << AW;             // 8192

    // Tile position of the incoming spectrum
    reg          inSpec;
    reg [TW-1:0] trIn, tcIn;
    wire         newSpec = validIn & ~inSpec;

    always @(posedge clk or posedge reset)
        if (reset) begin
            inSpec <= 0;
            trIn   <= 0;
            tcIn   <= 0;
        end else begin
            if (validIn) inSpec <= 1;
            if (doneIn)  inSpec <= 0;
            if (doneIn && mIdxIn == COUT-1) begin
                tcIn <= (tcIn == TC-1) ? 0 : tcIn + 1;
                if (tcIn == TC-1)
                    trIn <= (trIn == TR-1) ? 0 : trIn + 1;
            end
        end

    // Header FIFO: {m, tr, tc} of each spectrum, 4 deep
    reg  [MW+2*TW-1:0] hdr [0:3];
    reg  [1:0]         hWr, hRd;
    reg  [2:0]         hCnt;
    wire               hPop;
    wire [MW-1:0]      hM;
    wire [TW-1:0]      hTr, hTc;

    assign {hM, hTr, hTc} = hdr[hRd];

    always @(posedge clk)
        if (newSpec) hdr[hWr] <= {mIdxIn, trIn, tcIn};

    always @(posedge clk or posedge reset)
        if (reset) begin
            hWr  <= 0;
            hRd  <= 0;
            hCnt <= 0;
        end else begin
            hWr  <= hWr + newSpec;
            hRd  <= hRd + hPop;
            hCnt <= hCnt + newSpec - hPop;
        end

    // Sample FIFO: one spectrum plus SLACK
    wire [DW-1:0] fq;
    wire [AW-1:0] fUsed;
    wire          fEmpty, fFull, fRd;

    scfifo #(
        .lpm_type               ("scfifo"),
        .lpm_width              (DW),
        .lpm_numwords           (DEPTH),
        .lpm_widthu             (AW),
        .lpm_showahead          ("ON"),
        .intended_device_family ("Cyclone V")
    ) fifo (
        .clock (clk),
        .aclr  (reset),
        .sclr  (1'b0),
        .data  (dataIn),
        .wrreq (validIn),
        .rdreq (fRd),
        .q     (fq),
        .empty (fEmpty),
        .full  (fFull),
        .usedw (fUsed)
    );

    // usedw reads 0 when the FIFO is full, so check full as well
    always @(posedge clk or posedge reset)
        if (reset) readyOut <= 0;
        else       readyOut <= !fFull && fUsed <= DEPTH - NC*NC - SLACK;

    // Output side
    localparam IDLE = 0, BIAS_RD = 1, BIAS_WAIT = 2, PIX = 3,
               RD   = 4, RD_WAIT = 5, WR        = 6;

    reg [2:0]    state;
    reg [MW-1:0] m;
    reg [TW-1:0] tr, tc;
    reg [NW-1:0] r, c;                      // position inside the NC x NC block
    reg [31:0]   base, bias, addr, sample, wdata;
    reg          lastQ;

    // Where the sample at the FIFO head goes
    wire [15:0] gr      = tr * B + r;
    wire [15:0] gc      = tc * B + c;
    wire        keep    = gr >= K-1 && gr < K-1+HO && gc >= K-1 && gc < K-1+WO;
    wire        first   = (r >= K-1 || tr == 0)    && (c >= K-1 || tc == 0);
    wire        last    = (r <  B   || tr == TR-1) && (c <  B   || tc == TC-1);
    wire [31:0] pixAddr = base + 4 * ((gr - (K-1)) * WO + (gc - (K-1)));
    wire [31:0] din     = {{(32-DW){fq[DW-1]}}, fq};

    wire next = (state == PIX && !fEmpty && !keep) ||
                (state == WR  && !avm_waitrequest);

    assign hPop          = state == IDLE && hCnt != 0;
    assign fRd           = state == PIX && !fEmpty;
    assign avm_read      = state == BIAS_RD || state == RD;
    assign avm_write     = state == WR;
    assign avm_address   = (state == BIAS_RD) ? BIAS_BASE + 4*m : addr;
    assign avm_writedata = wdata;

    always @(posedge clk or posedge reset)
        if (reset) begin
            state   <= IDLE;
            imgDone <= 0;
            m       <= 0;
            tr      <= 0;
            tc      <= 0;
            r       <= 0;
            c       <= 0;
            base    <= 0;
            bias    <= 0;
            addr    <= 0;
            sample  <= 0;
            wdata   <= 0;
            lastQ   <= 0;
        end else begin
            imgDone <= 0;

            case (state)
                IDLE: if (hCnt != 0) begin
                    m     <= hM;
                    tr    <= hTr;
                    tc    <= hTc;
                    base  <= OUT_BASE + 4 * hM * HO * WO;
                    r     <= 0;
                    c     <= 0;
                    state <= BIAS_RD;
                end

                BIAS_RD:   if (!avm_waitrequest) state <= BIAS_WAIT;

                BIAS_WAIT: if (avm_readdatavalid) begin
                    bias  <= avm_readdata;
                    state <= PIX;
                end

                PIX: if (!fEmpty && keep) begin
                    addr   <= pixAddr;
                    sample <= din;
                    lastQ  <= last;
                    if (first) begin
                        wdata <= din + (last ? bias : 0);
                        state <= WR;
                    end else begin
                        state <= RD;
                    end
                end

                RD:      if (!avm_waitrequest) state <= RD_WAIT;

                RD_WAIT: if (avm_readdatavalid) begin
                    wdata <= avm_readdata + sample + (lastQ ? bias : 0);
                    state <= WR;
                end

                WR: ;   // handled below
            endcase

            // Next sample: after a dropped sample or an accepted write
            if (next) begin
                if (r == NC-1 && c == NC-1) begin
                    state   <= IDLE;
                    imgDone <= m == COUT-1 && tr == TR-1 && tc == TC-1;
                end else begin
                    state <= PIX;
                    c     <= (c == NC-1) ? 0 : c + 1;
                    if (c == NC-1) r <= r + 1;
                end
            end
        end

endmodule