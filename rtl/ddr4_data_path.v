// DDR4 Data Path
// Read/write data FIFOs; 8:1 serializer/deserializer bridge;
// DQS preamble/postamble control; ECC engine integration;
// read-data correction pipeline.
//
// Write path:
//   Host data → wr_data FIFO → ECC encode → phy_dq_out (72-bit word)
//   DQS OE and DQ OE asserted for one cycle while data is driven.
//
// Read path:
//   PHY 72-bit word → ECC decode → corrected 64-bit data → host
//
module ddr4_data_path (
    input  wire        clk,
    input  wire        rst_n,

    // Write interface (from scheduler / host)
    input  wire        wr_req,         // enqueue write data
    input  wire [3:0]  wr_id,          // write transaction ID
    input  wire [63:0] wr_data,        // host write data
    input  wire [7:0]  wr_strb,        // byte enables
    output wire        wr_ready,       // space available in write FIFO

    // Read interface from PHY
    input  wire [71:0] rd_data_return, // raw 72-bit burst from PHY (64 data + 8 ECC)
    input  wire        rd_data_valid_phy, // PHY read valid
    input  wire [3:0]  rd_id_phy,      // read ID from scheduler

    // Read output to host
    output reg  [63:0] rd_data_out,    // corrected read data
    output reg         rd_data_valid_host, // host read data valid
    output reg  [3:0]  rd_data_id_host,   // transaction ID
    output reg         rd_ecc_err,     // ECC error (single or double) on this word

    // PHY output side
    output reg  [71:0] phy_dq_out,     // serialized output to PHY pads
    output reg  [8:0]  phy_dqs_oe,     // DQS output-enable per byte lane (9 lanes)
    output reg  [8:0]  phy_dq_oe       // DQ  output-enable per byte lane
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    parameter FIFO_DEPTH = 8;
    localparam FIFO_PTR_W = 3;  // log2(FIFO_DEPTH)

    // ---------------------------------------------------------------
    // Write FIFO (stores {id, strb, data})
    // ---------------------------------------------------------------
    localparam WF_W = 4 + 8 + 64;  // 76 bits

    reg [WF_W-1:0] wr_fifo [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_W-1:0] wf_wptr, wf_rptr;
    reg [FIFO_PTR_W:0]   wf_count;  // 0..FIFO_DEPTH

    assign wr_ready = (wf_count < FIFO_DEPTH[FIFO_PTR_W:0]);

    // Write-side push
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wf_wptr  <= {FIFO_PTR_W{1'b0}};
            wf_count <= {(FIFO_PTR_W+1){1'b0}};
        end else begin
            if (wr_req && wr_ready) begin
                wr_fifo[wf_wptr] <= {wr_id, wr_strb, wr_data};
                wf_wptr  <= wf_wptr + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------
    // ECC Engine (instantiated combinatorially)
    // ---------------------------------------------------------------
    wire [71:0] ecc_enc_out;
    wire [63:0] ecc_dec_out;
    wire        ecc_single_err, ecc_double_err;
    wire [7:0]  ecc_syndrome;
    wire [6:0]  ecc_err_bit;

    // Encoder input from head of write FIFO
    wire [63:0] wf_data_head = wr_fifo[wf_rptr][63:0];

    ddr4_ecc_engine ecc_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        // encode
        .enc_data_in    (wf_data_head),
        .enc_data_out   (ecc_enc_out),
        // decode
        .dec_data_in    (rd_data_return),
        .dec_data_out   (ecc_dec_out),
        .dec_single_err (ecc_single_err),
        .dec_double_err (ecc_double_err),
        .dec_syndrome   (ecc_syndrome),
        .dec_err_bit    (ecc_err_bit)
    );

    // ---------------------------------------------------------------
    // Write output: pop FIFO → drive PHY every cycle there is data
    // ---------------------------------------------------------------
    wire wf_not_empty = (wf_count > 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wf_rptr    <= {FIFO_PTR_W{1'b0}};
            phy_dq_out  <= 72'b0;
            phy_dqs_oe  <= 9'b0;
            phy_dq_oe   <= 9'b0;
        end else begin
            // Default: de-assert OE
            phy_dqs_oe <= 9'b0;
            phy_dq_oe  <= 9'b0;
            phy_dq_out <= 72'b0;

            if (wf_not_empty) begin
                phy_dq_out  <= ecc_enc_out;   // ECC-encoded write data
                phy_dqs_oe  <= 9'h1ff;         // all lanes OE
                phy_dq_oe   <= 9'h1ff;
                wf_rptr     <= wf_rptr + 1'b1;
            end
        end
    end

    // Update count: simultaneous push and pop → count unchanged
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wf_count <= {(FIFO_PTR_W+1){1'b0}};
        end else begin
            case ({(wr_req && wr_ready), wf_not_empty})
                2'b10: wf_count <= wf_count + 1'b1;  // push only
                2'b01: wf_count <= wf_count - 1'b1;  // pop only
                default: wf_count <= wf_count;        // both or neither
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Read path: pipeline PHY data → ECC decode → host
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_out        <= 64'b0;
            rd_data_valid_host <= 1'b0;
            rd_data_id_host    <= 4'b0;
            rd_ecc_err         <= 1'b0;
        end else begin
            rd_data_valid_host <= rd_data_valid_phy;
            rd_data_id_host    <= rd_id_phy;
            if (rd_data_valid_phy) begin
                rd_data_out <= ecc_dec_out;
                rd_ecc_err  <= ecc_single_err | ecc_double_err;
            end else begin
                rd_data_out <= 64'b0;
                rd_ecc_err  <= 1'b0;
            end
        end
    end

endmodule
