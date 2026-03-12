`timescale 1ns/1ps
module ddr4_refresh_ctrl_tb;

    reg        clk, rst_n;
    reg        init_done;
    reg [13:0] cfg_trefi;
    reg [1:0]  cfg_fgr_mode;
    reg        cfg_pbr_en;
    wire       ref_req;
    wire [1:0] ref_rank;
    wire [3:0] ref_bank;
    reg        ref_ack;
    reg        sr_req, sr_exit_req;
    wire       sr_active;

    ddr4_refresh_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .init_done(init_done),
        .cfg_trefi(cfg_trefi),
        .cfg_fgr_mode(cfg_fgr_mode),
        .cfg_pbr_en(cfg_pbr_en),
        .ref_req(ref_req),
        .ref_rank(ref_rank),
        .ref_bank(ref_bank),
        .ref_ack(ref_ack),
        .sr_req(sr_req),
        .sr_active(sr_active),
        .sr_exit_req(sr_exit_req)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-core-ctrl/ddr4_refresh_ctrl.vcd");
        $dumpvars(0, ddr4_refresh_ctrl_tb);
    end

    integer wait_cnt;

    initial begin
        rst_n        = 0;
        init_done    = 0;
        cfg_trefi    = 14'd20;  // short period for sim
        cfg_fgr_mode = 2'd0;
        cfg_pbr_en   = 1'b0;
        ref_ack      = 0;
        sr_req       = 0;
        sr_exit_req  = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Start refresh controller
        init_done = 1;

        // --- Test 1: Wait for ref_req ---
        $display("Test 1: waiting for ref_req");
        wait_cnt = 0;
        while (!ref_req) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
            if (wait_cnt >= 200)
                $fatal(1, "SIMULATION FAILED: ref_req not asserted within 200 cycles");
        end
        $display("ref_req asserted after %0d cycles", wait_cnt);

        // --- Test 2: ACK clears ref_req ---
        ref_ack = 1;
        @(posedge clk);
        ref_ack = 0;
        @(posedge clk);
        if (ref_req !== 1'b0)
            $fatal(1, "SIMULATION FAILED: ref_req should deassert after ack");
        $display("ref_req deasserted after ack");

        // --- Test 3: self-refresh entry ---
        $display("Test 3: self-refresh");
        sr_req = 1;
        @(posedge clk);
        @(posedge clk);
        if (!sr_active)
            $fatal(1, "SIMULATION FAILED: sr_active should be high after sr_req");
        $display("sr_active asserted");

        // While in self-refresh, ref_req should not assert
        repeat(30) @(posedge clk);
        if (ref_req)
            $fatal(1, "SIMULATION FAILED: ref_req should not assert during self-refresh");
        $display("ref_req suppressed during self-refresh");

        // --- Test 4: self-refresh exit ---
        sr_req      = 0;
        sr_exit_req = 1;
        @(posedge clk);
        sr_exit_req = 0;
        @(posedge clk);
        if (sr_active)
            $fatal(1, "SIMULATION FAILED: sr_active should deassert after exit_req");
        $display("sr_active deasserted");

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
