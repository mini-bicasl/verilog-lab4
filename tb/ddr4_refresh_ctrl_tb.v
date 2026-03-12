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

        // --- Test 5: FGR×2 — period should halve ---
        // Re-init: reset and use FGR mode 1
        rst_n        = 0;
        init_done    = 0;
        cfg_fgr_mode = 2'd1;  // FGRx2
        cfg_pbr_en   = 1'b0;
        cfg_trefi    = 14'd20;
        ref_ack      = 0;
        repeat(4) @(posedge clk);
        rst_n     = 1;
        @(posedge clk);
        init_done = 1;

        $display("Test 5: FGRx2 mode — effective period = trefi/2 = 10");
        // With FGRx2, effective period = 20/2 = 10 cycles
        // ref_req must appear in <=15 cycles
        wait_cnt = 0;
        while (!ref_req) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
            if (wait_cnt >= 30)
                $fatal(1, "SIMULATION FAILED: FGRx2 ref_req not seen within 30 cycles");
        end
        if (wait_cnt > 15)
            $fatal(1, "SIMULATION FAILED: FGRx2 period too long (%0d), expected <=15", wait_cnt);
        $display("FGRx2 ref_req asserted after %0d cycles (OK, <=15)", wait_cnt);
        // ACK
        ref_ack = 1; @(posedge clk); ref_ack = 0; @(posedge clk);

        // --- Test 6: FGR×4 — period should quarter ---
        rst_n        = 0;
        init_done    = 0;
        cfg_fgr_mode = 2'd2;  // FGRx4
        cfg_trefi    = 14'd20;
        repeat(4) @(posedge clk);
        rst_n     = 1;
        @(posedge clk);
        init_done = 1;

        $display("Test 6: FGRx4 mode — effective period = trefi/4 = 5");
        wait_cnt = 0;
        while (!ref_req) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
            if (wait_cnt >= 20)
                $fatal(1, "SIMULATION FAILED: FGRx4 ref_req not seen within 20 cycles");
        end
        if (wait_cnt > 10)
            $fatal(1, "SIMULATION FAILED: FGRx4 period too long (%0d), expected <=10", wait_cnt);
        $display("FGRx4 ref_req asserted after %0d cycles (OK, <=10)", wait_cnt);
        ref_ack = 1; @(posedge clk); ref_ack = 0; @(posedge clk);

        // --- Test 7: PBR — bank rotates through all 16 banks ---
        rst_n        = 0;
        init_done    = 0;
        cfg_fgr_mode = 2'd0;
        cfg_pbr_en   = 1'b1;
        cfg_trefi    = 14'd10;
        repeat(4) @(posedge clk);
        rst_n     = 1;
        @(posedge clk);
        init_done = 1;

        $display("Test 7: PBR — bank rotates through all 16 banks");
        begin : pbr_loop
            integer b;
            for (b = 0; b < 16; b = b + 1) begin
                // Wait for ref_req
                wait_cnt = 0;
                @(posedge clk); // extra cycle so we don't exit immediately
                while (!ref_req) begin
                    @(posedge clk);
                    wait_cnt = wait_cnt + 1;
                    if (wait_cnt >= 50)
                        $fatal(1, "SIMULATION FAILED: PBR ref_req not seen (bank %0d)", b);
                end
                if (ref_bank !== b[3:0])
                    $fatal(1, "SIMULATION FAILED: PBR bank mismatch: got %0d expected %0d",
                               ref_bank, b);
                // Drive ACK on negedge to ensure RTL samples ref_ack=1 cleanly on next posedge
                @(negedge clk);
                ref_ack = 1;
                @(posedge clk);  // RTL sees ref_ack=1 → ACK fires (ref_bank++)
                @(negedge clk);
                ref_ack = 0;
            end
        end
        $display("PBR rotated through all 16 banks OK");

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
