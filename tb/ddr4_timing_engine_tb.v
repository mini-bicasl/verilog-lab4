`timescale 1ns/1ps
module ddr4_timing_engine_tb;

    reg         clk, rst_n;
    reg         dram_cmd_valid;
    reg [2:0]   dram_cmd_type;
    reg [1:0]   dram_rank, dram_bg, dram_ba;
    reg [4:0]   cfg_cl, cfg_cwl;
    reg [7:0]   cfg_trcd, cfg_trp, cfg_tras, cfg_trc;
    reg [9:0]   cfg_trfc;
    reg [13:0]  cfg_trefi;
    wire [15:0] timing_ok;

    // Use small timing parameters for simulation speed
    ddr4_timing_engine #(
        .tRCD_DEF(5), .tRP_DEF(5), .tRAS_DEF(10),
        .tRC_DEF(15), .tCCD_L_DEF(4), .tCCD_S_DEF(2),
        .tRRD_L_DEF(4), .tRRD_S_DEF(2),
        .tWR_DEF(8), .tWTR_L_DEF(6), .tWTR_S_DEF(2),
        .tRTP_DEF(4), .tFAW_DEF(8), .tRFC_DEF(20),
        .tMOD_DEF(6), .tZQ_DEF(10)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .dram_cmd_valid(dram_cmd_valid),
        .dram_cmd_type(dram_cmd_type),
        .dram_rank(dram_rank),
        .dram_bg(dram_bg), .dram_ba(dram_ba),
        .cfg_cl(cfg_cl), .cfg_cwl(cfg_cwl),
        .cfg_trcd(cfg_trcd), .cfg_trp(cfg_trp),
        .cfg_tras(cfg_tras), .cfg_trc(cfg_trc),
        .cfg_trfc(cfg_trfc), .cfg_trefi(cfg_trefi),
        .timing_ok(timing_ok)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-core-ctrl/ddr4_timing_engine.vcd");
        $dumpvars(0, ddr4_timing_engine_tb);
    end

    task send_cmd;
        input [2:0] ctype;
        input [1:0] bg, ba;
        begin
            @(posedge clk);
            dram_cmd_valid = 1'b1;
            dram_cmd_type  = ctype;
            dram_bg        = bg;
            dram_ba        = ba;
            @(posedge clk);
            dram_cmd_valid = 1'b0;
        end
    endtask

    integer i;

    initial begin
        rst_n           = 0;
        dram_cmd_valid  = 0;
        dram_cmd_type   = 0;
        dram_rank       = 0;
        dram_bg         = 0;
        dram_ba         = 0;
        cfg_cl          = 5'd11;
        cfg_cwl         = 5'd9;
        cfg_trcd        = 8'd0;  // use defaults
        cfg_trp         = 8'd0;
        cfg_tras        = 8'd0;
        cfg_trc         = 8'd0;
        cfg_trfc        = 10'd0;
        cfg_trefi       = 14'd0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // --- Test 1: ACT causes tRCD to deassert ---
        $display("Test 1: ACT -> tRCD");
        send_cmd(3'd4, 2'd0, 2'd0); // ACT bank 0

        // tRCD counter should be loaded; timing_ok[0] should be 0
        @(posedge clk);
        if (timing_ok[0] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRCD should be busy after ACT (got %b)", timing_ok[0]);

        // Wait for tRCD to expire (tRCD_DEF=5 + margin)
        repeat(10) @(posedge clk);
        if (timing_ok[0] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRCD should be OK after wait");
        $display("tRCD recovered correctly");

        // --- Test 2: PRE causes tRP ---
        $display("Test 2: PRE -> tRP");
        send_cmd(3'd3, 2'd0, 2'd0); // PRE bank 0

        @(posedge clk);
        if (timing_ok[1] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRP should be busy after PRE");

        repeat(10) @(posedge clk);
        if (timing_ok[1] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRP should be OK after wait");
        $display("tRP recovered correctly");

        // --- Test 3: REF causes tRFC ---
        $display("Test 3: REF -> tRFC");
        send_cmd(3'd2, 2'd0, 2'd0); // REF

        @(posedge clk);
        if (timing_ok[13] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRFC should be busy after REF");

        // Wait for tRFC (tRFC_DEF=20 + margin)
        repeat(30) @(posedge clk);
        if (timing_ok[13] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRFC should be OK after wait");
        $display("tRFC recovered correctly");

        // --- Test 4: ACT -> tRAS, tRC, tRRD_L, tRRD_S, tFAW ---
        $display("Test 4: ACT -> tRAS, tRC, tRRD_L, tRRD_S, tFAW");
        send_cmd(3'd4, 2'd0, 2'd0); // ACT bank_group=0

        @(posedge clk);
        if (timing_ok[2] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRAS should be busy after ACT");
        if (timing_ok[3] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRC should be busy after ACT");
        if (timing_ok[6] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRRD_L should be busy after ACT");
        if (timing_ok[7] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRRD_S should be busy after ACT");
        if (timing_ok[12] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tFAW should be busy after ACT");

        repeat(20) @(posedge clk);
        if (timing_ok[2] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRAS should be OK after wait");
        if (timing_ok[3] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRC should be OK after wait");
        if (timing_ok[6] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRRD_L should be OK after wait");
        if (timing_ok[7] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRRD_S should be OK after wait");
        if (timing_ok[12] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tFAW should be OK after wait");
        $display("tRAS, tRC, tRRD_L, tRRD_S, tFAW recovered correctly");

        // --- Test 5: ACT (same bank group) -> tRRD_L; ACT (diff bg) -> tRRD_S ---
        $display("Test 5: back-to-back ACT same/diff bank group");
        // ACT to bg=0 ba=0
        send_cmd(3'd4, 2'd0, 2'd0);
        @(posedge clk);
        if (timing_ok[6] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRRD_L should be busy after ACT bg0");
        // Second ACT to bg=1 (different bank group) — tRRD_S loads
        send_cmd(3'd4, 2'd1, 2'd0);
        @(posedge clk);
        if (timing_ok[7] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRRD_S should be busy after second ACT diff bg");
        repeat(10) @(posedge clk);
        if (timing_ok[6] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRRD_L should recover");
        if (timing_ok[7] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRRD_S should recover");
        $display("back-to-back ACT same/diff bank group OK");

        // --- Test 6: WR -> tWR, tWTR_L, tWTR_S, tCCD_L, tCCD_S ---
        $display("Test 6: WR -> tWR, tWTR_L, tWTR_S, tCCD_L, tCCD_S");
        send_cmd(3'd5, 2'd0, 2'd0); // WR bank_group=0

        @(posedge clk);
        if (timing_ok[8] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tWR should be busy after WR");
        if (timing_ok[9] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tWTR_L should be busy after WR");
        if (timing_ok[10] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tWTR_S should be busy after WR");
        if (timing_ok[4] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tCCD_L should be busy after WR");
        if (timing_ok[5] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tCCD_S should be busy after WR");

        repeat(20) @(posedge clk);
        if (timing_ok[8] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tWR should be OK after wait");
        if (timing_ok[9] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tWTR_L should be OK after wait");
        if (timing_ok[10] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tWTR_S should be OK after wait");
        if (timing_ok[4] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tCCD_L should be OK after wait");
        if (timing_ok[5] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tCCD_S should be OK after wait");
        $display("tWR, tWTR_L, tWTR_S, tCCD_L, tCCD_S recovered correctly");

        // --- Test 7: RD -> tRTP, tCCD_L, tCCD_S ---
        $display("Test 7: RD -> tRTP, tCCD_L, tCCD_S");
        send_cmd(3'd6, 2'd0, 2'd0); // RD bank_group=0

        @(posedge clk);
        if (timing_ok[11] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tRTP should be busy after RD");
        if (timing_ok[4] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tCCD_L should be busy after RD");
        if (timing_ok[5] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tCCD_S should be busy after RD");

        repeat(15) @(posedge clk);
        if (timing_ok[11] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tRTP should be OK after wait");
        $display("tRTP, tCCD_L, tCCD_S from RD OK");

        // --- Test 8: MRS -> tMOD ---
        $display("Test 8: MRS -> tMOD");
        send_cmd(3'd1, 2'd0, 2'd0); // MRS

        @(posedge clk);
        if (timing_ok[14] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tMOD should be busy after MRS");

        repeat(15) @(posedge clk);
        if (timing_ok[14] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tMOD should be OK after wait");
        $display("tMOD recovered correctly");

        // --- Test 9: ZQCL -> tZQ ---
        $display("Test 9: ZQCL -> tZQ");
        send_cmd(3'd7, 2'd0, 2'd0); // ZQCL

        @(posedge clk);
        if (timing_ok[15] !== 1'b0)
            $fatal(1, "SIMULATION FAILED: tZQ should be busy after ZQCL");

        repeat(20) @(posedge clk);
        if (timing_ok[15] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: tZQ should be OK after wait");
        $display("tZQ recovered correctly");

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
