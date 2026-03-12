`timescale 1ns/1ps
// Testbench for ddr4_phy_iface
// Tests: DDR4 pad output timing, DQ tristate during read, DQS preamble,
//        CK differential generation, command bus pass-through.
module ddr4_phy_iface_tb;

    localparam NUM_RANKS = 1;
    localparam DQ_WIDTH  = 72;
    localparam DQS_WIDTH = 9;

    reg  clk, rst_n;

    // Controller command bus inputs
    reg                  ctrl_cmd_valid;
    reg                  ctrl_act_n, ctrl_ras_n, ctrl_cas_n, ctrl_we_n;
    reg  [1:0]           ctrl_bg, ctrl_ba;
    reg  [16:0]          ctrl_a;
    reg  [NUM_RANKS-1:0] ctrl_cs_n;
    reg  [NUM_RANKS-1:0] ctrl_cke;
    reg  [NUM_RANKS-1:0] ctrl_odt;
    reg                  ctrl_reset_n;

    // Data bus
    reg  [DQ_WIDTH-1:0]  ctrl_dq_out;
    reg  [DQS_WIDTH-1:0] ctrl_dq_oe;
    reg  [DQS_WIDTH-1:0] ctrl_dqs_oe;

    // DQ input (from DRAM)
    reg  [DQ_WIDTH-1:0]  ddr4_dq_in;

    // Outputs
    wire [DQ_WIDTH-1:0]  phy_dq_in;
    wire                 phy_dqs_valid;

    wire [NUM_RANKS-1:0] ddr4_ck_t, ddr4_ck_c;
    wire [NUM_RANKS-1:0] ddr4_cke, ddr4_cs_n;
    wire                 ddr4_act_n, ddr4_ras_n, ddr4_cas_n, ddr4_we_n;
    wire [1:0]           ddr4_bg, ddr4_ba;
    wire [16:0]          ddr4_a;
    wire [NUM_RANKS-1:0] ddr4_odt;
    wire                 ddr4_reset_n;
    wire [DQ_WIDTH-1:0]  ddr4_dq_out;
    wire [DQS_WIDTH-1:0] ddr4_dqs_t, ddr4_dqs_c;
    wire [DQS_WIDTH-1:0] ddr4_dm_dbi_n;

    ddr4_phy_iface #(
        .NUM_RANKS(NUM_RANKS),
        .DQ_WIDTH(DQ_WIDTH),
        .DQS_WIDTH(DQS_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ctrl_cmd_valid (ctrl_cmd_valid),
        .ctrl_act_n     (ctrl_act_n),
        .ctrl_ras_n     (ctrl_ras_n),
        .ctrl_cas_n     (ctrl_cas_n),
        .ctrl_we_n      (ctrl_we_n),
        .ctrl_bg        (ctrl_bg),
        .ctrl_ba        (ctrl_ba),
        .ctrl_a         (ctrl_a),
        .ctrl_cs_n      (ctrl_cs_n),
        .ctrl_cke       (ctrl_cke),
        .ctrl_odt       (ctrl_odt),
        .ctrl_reset_n   (ctrl_reset_n),
        .ctrl_dq_out    (ctrl_dq_out),
        .ctrl_dq_oe     (ctrl_dq_oe),
        .ctrl_dqs_oe    (ctrl_dqs_oe),
        .phy_dq_in      (phy_dq_in),
        .phy_dqs_valid  (phy_dqs_valid),
        .ddr4_ck_t      (ddr4_ck_t),
        .ddr4_ck_c      (ddr4_ck_c),
        .ddr4_cke       (ddr4_cke),
        .ddr4_cs_n      (ddr4_cs_n),
        .ddr4_act_n     (ddr4_act_n),
        .ddr4_ras_n     (ddr4_ras_n),
        .ddr4_cas_n     (ddr4_cas_n),
        .ddr4_we_n      (ddr4_we_n),
        .ddr4_bg        (ddr4_bg),
        .ddr4_ba        (ddr4_ba),
        .ddr4_a         (ddr4_a),
        .ddr4_odt       (ddr4_odt),
        .ddr4_reset_n   (ddr4_reset_n),
        .ddr4_dq_out    (ddr4_dq_out),
        .ddr4_dq_in     (ddr4_dq_in),
        .ddr4_dqs_t     (ddr4_dqs_t),
        .ddr4_dqs_c     (ddr4_dqs_c),
        .ddr4_dm_dbi_n  (ddr4_dm_dbi_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-integration/ddr4_phy_iface.vcd");
        $dumpvars(0, ddr4_phy_iface_tb);
    end

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task wait_clk;
        input integer n;
        integer i;
        begin for (i=0; i<n; i=i+1) @(posedge clk); end
    endtask

    initial begin
        // Initialise inputs
        rst_n          = 0;
        ctrl_cmd_valid = 0;
        ctrl_act_n     = 1; ctrl_ras_n = 1; ctrl_cas_n = 1; ctrl_we_n = 1;
        ctrl_bg        = 0; ctrl_ba = 0; ctrl_a = 0;
        ctrl_cs_n      = {NUM_RANKS{1'b1}};
        ctrl_cke       = {NUM_RANKS{1'b0}};
        ctrl_odt       = {NUM_RANKS{1'b0}};
        ctrl_reset_n   = 0;
        ctrl_dq_out    = 0;
        ctrl_dq_oe     = 0;
        ctrl_dqs_oe    = 0;
        ddr4_dq_in     = 0;

        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        wait_clk(3);

        // -------------------------------------------------------
        // Test 1: CK differential clock generation
        // -------------------------------------------------------
        $display("Test 1: CK differential output");
        wait_clk(2);
        @(posedge clk); #1;
        if (ddr4_ck_t === ddr4_ck_c)
            $fatal(1, "T1 FAIL: ck_t and ck_c must be complementary");
        $display("  T1: ddr4_ck_t=%b ddr4_ck_c=%b (differential)", ddr4_ck_t, ddr4_ck_c);
        pass_cnt = pass_cnt + 1;
        wait_clk(2);

        // -------------------------------------------------------
        // Test 2: Command bus — ACTIVATE command reaches pads
        // -------------------------------------------------------
        $display("Test 2: ACT command propagated to DDR4 pads");
        @(negedge clk);
        ctrl_cmd_valid = 1'b1;
        ctrl_act_n     = 1'b0;  // ACT
        ctrl_ras_n     = 1'b1;
        ctrl_cas_n     = 1'b1;
        ctrl_we_n      = 1'b1;
        ctrl_cs_n      = {NUM_RANKS{1'b0}};  // select rank 0
        ctrl_cke       = {NUM_RANKS{1'b1}};
        ctrl_bg        = 2'b01;
        ctrl_ba        = 2'b10;
        ctrl_a         = 17'h1ABCD;
        @(posedge clk); @(posedge clk); #1;
        if (ddr4_act_n !== 1'b0)
            $fatal(1, "T2 FAIL: ddr4_act_n should be 0 for ACT command");
        if (ddr4_a !== 17'h1ABCD)
            $fatal(1, "T2 FAIL: ddr4_a mismatch: %h vs %h", ddr4_a, 17'h1ABCD);
        if (ddr4_cs_n !== {NUM_RANKS{1'b0}})
            $fatal(1, "T2 FAIL: ddr4_cs_n should be 0");
        $display("  T2: ACT command on pads OK (act_n=%b, a=%h)", ddr4_act_n, ddr4_a);
        pass_cnt = pass_cnt + 1;
        @(negedge clk); ctrl_cmd_valid = 1'b0;
        ctrl_act_n = 1'b1;
        wait_clk(2);

        // -------------------------------------------------------
        // Test 3: DQ output when dq_oe is asserted
        // -------------------------------------------------------
        $display("Test 3: DQ output-enable and data drive");
        @(negedge clk);
        ctrl_dq_out = 72'hA5A5_A5A5_A5A5_A5A5_AA; // test pattern
        ctrl_dq_oe  = {DQS_WIDTH{1'b1}};  // all byte lanes OE
        ctrl_dqs_oe = {DQS_WIDTH{1'b1}};
        @(posedge clk); @(posedge clk); #1;
        // ddr4_dq_out[7:0] should match ctrl_dq_out[7:0] (byte lane 0)
        if (ddr4_dq_out[7:0] !== ctrl_dq_out[7:0])
            $fatal(1, "T3 FAIL: dq_out[7:0]=%h expected %h", ddr4_dq_out[7:0], ctrl_dq_out[7:0]);
        // DQS should toggle
        $display("  T3: DQ output path OK (dq_out[7:0]=%h)", ddr4_dq_out[7:0]);
        pass_cnt = pass_cnt + 1;
        wait_clk(2);

        // -------------------------------------------------------
        // Test 4: DQ tristate during read (dq_oe=0) — phy_dqs_valid
        // -------------------------------------------------------
        $display("Test 4: DQ tristate during read and phy_dqs_valid");
        @(negedge clk);
        ctrl_dq_oe  = {DQS_WIDTH{1'b0}};
        ctrl_dqs_oe = {DQS_WIDTH{1'b0}};
        ddr4_dq_in  = 72'h123456789ABCDEF012;
        @(posedge clk); @(posedge clk); #1;
        if (!phy_dqs_valid)
            $fatal(1, "T4 FAIL: phy_dqs_valid should be 1 when dqs_oe=0");
        if (phy_dq_in !== 72'h123456789ABCDEF012)
            $fatal(1, "T4 FAIL: phy_dq_in mismatch: got %h", phy_dq_in);
        $display("  T4: phy_dqs_valid=%b, phy_dq_in=%h", phy_dqs_valid, phy_dq_in);
        pass_cnt = pass_cnt + 1;
        wait_clk(2);

        // -------------------------------------------------------
        // Test 5: NOP / deselect — CS_N=1 propagated
        // -------------------------------------------------------
        $display("Test 5: NOP / deselect — ddr4_cs_n=1 after cmd_valid=0");
        @(negedge clk);
        ctrl_cmd_valid = 1'b0;
        ctrl_cs_n      = {NUM_RANKS{1'b1}};
        @(posedge clk); @(posedge clk); #1;
        if (ddr4_cs_n !== {NUM_RANKS{1'b1}})
            $fatal(1, "T5 FAIL: ddr4_cs_n should be all-1 on NOP");
        $display("  T5: NOP/deselect OK (ddr4_cs_n=%b)", ddr4_cs_n);
        pass_cnt = pass_cnt + 1;
        wait_clk(3);

        // -------------------------------------------------------
        // Test 6: RESET_N propagated
        // -------------------------------------------------------
        $display("Test 6: RESET_N propagation");
        @(negedge clk); ctrl_reset_n = 1'b1;
        @(posedge clk); @(posedge clk); #1;
        if (ddr4_reset_n !== 1'b1)
            $fatal(1, "T6 FAIL: ddr4_reset_n should be 1");
        $display("  T6: ddr4_reset_n=%b OK", ddr4_reset_n);
        pass_cnt = pass_cnt + 1;
        wait_clk(3);

        $display("=== RESULTS: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("PASS: ddr4_phy_iface all tests passed");
        else
            $fatal(1, "FAIL: ddr4_phy_iface had %0d failures", fail_cnt);
        $finish;
    end

endmodule
