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

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
