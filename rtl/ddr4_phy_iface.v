// DDR4 PHY Interface — Abstract PHY Layer
// Bridges the controller's command/data buses to the DDR4 SDRAM pad ring.
// In a real ASIC/FPGA implementation this module would be replaced with
// vendor-specific I/O primitives (Xilinx IOSERDES, Intel LVDS_DDR, etc.).
// Here it provides a behavioural model that satisfies the pad naming required
// by the top-level integration.
module ddr4_phy_iface #(
    parameter NUM_RANKS = 1,
    parameter DQ_WIDTH  = 72,   // 64 data + 8 ECC
    parameter DQS_WIDTH = 9     // one DQS per byte lane
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Controller command bus (from timing engine / scheduler)
    input  wire                  ctrl_cmd_valid,
    input  wire                  ctrl_act_n,
    input  wire                  ctrl_ras_n,
    input  wire                  ctrl_cas_n,
    input  wire                  ctrl_we_n,
    input  wire [1:0]            ctrl_bg,
    input  wire [1:0]            ctrl_ba,
    input  wire [16:0]           ctrl_a,
    input  wire [NUM_RANKS-1:0]  ctrl_cs_n,
    input  wire [NUM_RANKS-1:0]  ctrl_cke,
    input  wire [NUM_RANKS-1:0]  ctrl_odt,
    input  wire                  ctrl_reset_n,

    // Data bus from controller
    input  wire [DQ_WIDTH-1:0]   ctrl_dq_out,
    input  wire [DQS_WIDTH-1:0]  ctrl_dq_oe,   // per-byte-lane output enable
    input  wire [DQS_WIDTH-1:0]  ctrl_dqs_oe,  // DQS output enable

    // Captured data returned to controller
    output reg  [DQ_WIDTH-1:0]   phy_dq_in,
    output reg                   phy_dqs_valid,

    // DDR4 SDRAM pad interface
    // CK is driven combinatorially to track clk at full data rate
    output wire [NUM_RANKS-1:0]  ddr4_ck_t,
    output wire [NUM_RANKS-1:0]  ddr4_ck_c,
    output reg  [NUM_RANKS-1:0]  ddr4_cke,
    output reg  [NUM_RANKS-1:0]  ddr4_cs_n,
    output reg                   ddr4_act_n,
    output reg                   ddr4_ras_n,
    output reg                   ddr4_cas_n,
    output reg                   ddr4_we_n,
    output reg  [1:0]            ddr4_bg,
    output reg  [1:0]            ddr4_ba,
    output reg  [16:0]           ddr4_a,
    output reg  [NUM_RANKS-1:0]  ddr4_odt,
    output reg                   ddr4_reset_n,
    // DQ / DQS are modelled as separate output / input registers
    // (tri-state semantics are represented by the oe signals)
    output reg  [DQ_WIDTH-1:0]   ddr4_dq_out,
    input  wire [DQ_WIDTH-1:0]   ddr4_dq_in,
    output reg  [DQS_WIDTH-1:0]  ddr4_dqs_t,
    output reg  [DQS_WIDTH-1:0]  ddr4_dqs_c,
    output reg  [DQS_WIDTH-1:0]  ddr4_dm_dbi_n
);

    // ---------------------------------------------------------------
    // CK generation — continuous (combinatorial) differential clock
    // ddr4_ck_t tracks clk; ddr4_ck_c is its complement.
    // This is the correct model: a real PHY forwards clk to the DRAM.
    // ---------------------------------------------------------------
    assign ddr4_ck_t = rst_n ? {NUM_RANKS{clk}} : {NUM_RANKS{1'b0}};
    assign ddr4_ck_c = rst_n ? {NUM_RANKS{~clk}} : {NUM_RANKS{1'b1}};

    // ---------------------------------------------------------------
    // Command / address register slice (one-cycle pipeline stage)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ddr4_cke     <= {NUM_RANKS{1'b0}};
            ddr4_cs_n    <= {NUM_RANKS{1'b1}};
            ddr4_act_n   <= 1'b1;
            ddr4_ras_n   <= 1'b1;
            ddr4_cas_n   <= 1'b1;
            ddr4_we_n    <= 1'b1;
            ddr4_bg      <= 2'b00;
            ddr4_ba      <= 2'b00;
            ddr4_a       <= 17'h00000;
            ddr4_odt     <= {NUM_RANKS{1'b0}};
            ddr4_reset_n <= 1'b0;
        end else begin
            ddr4_cke     <= ctrl_cke;
            ddr4_reset_n <= ctrl_reset_n;
            ddr4_odt     <= ctrl_odt;

            if (ctrl_cmd_valid) begin
                ddr4_cs_n  <= ctrl_cs_n;
                ddr4_act_n <= ctrl_act_n;
                ddr4_ras_n <= ctrl_ras_n;
                ddr4_cas_n <= ctrl_cas_n;
                ddr4_we_n  <= ctrl_we_n;
                ddr4_bg    <= ctrl_bg;
                ddr4_ba    <= ctrl_ba;
                ddr4_a     <= ctrl_a;
            end else begin
                // NOP: deselect all ranks
                ddr4_cs_n  <= {NUM_RANKS{1'b1}};
                ddr4_act_n <= 1'b1;
                ddr4_ras_n <= 1'b1;
                ddr4_cas_n <= 1'b1;
                ddr4_we_n  <= 1'b1;
                ddr4_bg    <= 2'b00;
                ddr4_ba    <= 2'b00;
                ddr4_a     <= 17'h00000;
            end
        end
    end

    // ---------------------------------------------------------------
    // DQ / DQS output path
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ddr4_dq_out   <= {DQ_WIDTH{1'b0}};
            ddr4_dqs_t    <= {DQS_WIDTH{1'b0}};
            ddr4_dqs_c    <= {DQS_WIDTH{1'b1}};
            ddr4_dm_dbi_n <= {DQS_WIDTH{1'b1}};
        end else begin
            // Drive DQ only when OE is asserted per byte lane
            begin : dq_out_gen
                integer b;
                for (b = 0; b < DQS_WIDTH; b = b + 1) begin
                    if (ctrl_dq_oe[b])
                        ddr4_dq_out[b*8 +: 8] <= ctrl_dq_out[b*8 +: 8];
                    else
                        ddr4_dq_out[b*8 +: 8] <= 8'hzz; // tri-state model
                end
            end
            // DQS differential strobe
            begin : dqs_gen
                integer b;
                for (b = 0; b < DQS_WIDTH; b = b + 1) begin
                    if (ctrl_dqs_oe[b]) begin
                        ddr4_dqs_t[b] <= clk;
                        ddr4_dqs_c[b] <= ~clk;
                    end else begin
                        ddr4_dqs_t[b] <= 1'bz;
                        ddr4_dqs_c[b] <= 1'bz;
                    end
                end
            end
            ddr4_dm_dbi_n <= {DQS_WIDTH{1'b1}}; // DBI disabled
        end
    end

    // ---------------------------------------------------------------
    // DQ input path — capture on posedge with DQS-valid gating
    // ---------------------------------------------------------------
    // In this abstract model, ddr4_dq_in is captured directly and
    // phy_dqs_valid is asserted each cycle that DQS OE is de-asserted
    // (indicating read data has arrived from DRAM).
    wire dqs_oe_any = |ctrl_dqs_oe;
    reg dqs_oe_prev;
    always @(posedge clk) begin
        if (!rst_n) begin
            phy_dq_in     <= {DQ_WIDTH{1'b0}};
            phy_dqs_valid <= 1'b0;
            dqs_oe_prev   <= 1'b0;
        end else begin
            dqs_oe_prev   <= dqs_oe_any;
            phy_dqs_valid <= 1'b0;
            // Capture read data when not in write-OE mode
            if (!dqs_oe_any) begin
                phy_dq_in     <= ddr4_dq_in;
                phy_dqs_valid <= 1'b1;
            end
        end
    end

endmodule
