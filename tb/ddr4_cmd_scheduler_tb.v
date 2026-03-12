`timescale 1ns/1ps
module ddr4_cmd_scheduler_tb;

    reg        clk, rst_n;
    reg        cmd_valid;
    wire       cmd_ready;
    reg [1:0]  cmd_type;
    reg [31:0] cmd_addr;
    reg [3:0]  cmd_id;
    reg        ref_req;
    reg [1:0]  ref_rank;
    reg [3:0]  ref_bank;
    wire       ref_ack;
    reg [15:0] timing_ok;
    wire       dram_cmd_valid;
    wire [2:0] dram_cmd_type;
    wire [1:0] dram_rank, dram_bg, dram_ba;
    wire [16:0] dram_row;
    wire [9:0]  dram_col;
    wire        rd_data_req, wr_data_req;
    wire [3:0]  rd_data_id, wr_data_id;

    ddr4_cmd_scheduler dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_type(cmd_type), .cmd_addr(cmd_addr), .cmd_id(cmd_id),
        .ref_req(ref_req), .ref_rank(ref_rank), .ref_bank(ref_bank),
        .ref_ack(ref_ack),
        .timing_ok(timing_ok),
        .dram_cmd_valid(dram_cmd_valid),
        .dram_cmd_type(dram_cmd_type),
        .dram_rank(dram_rank), .dram_bg(dram_bg), .dram_ba(dram_ba),
        .dram_row(dram_row), .dram_col(dram_col),
        .rd_data_req(rd_data_req), .rd_data_id(rd_data_id),
        .wr_data_req(wr_data_req), .wr_data_id(wr_data_id)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-core-ctrl/ddr4_cmd_scheduler.vcd");
        $dumpvars(0, ddr4_cmd_scheduler_tb);
    end

    integer wait_cnt;

    // Drive stimulus on negedge to avoid posedge race with RTL
    task issue_cmd;
        input [1:0]  ctype;
        input [31:0] addr;
        input [3:0]  id;
        begin
            @(negedge clk);
            cmd_valid = 1'b1;
            cmd_type  = ctype;
            cmd_addr  = addr;
            cmd_id    = id;
            // Hold until command is accepted (cmd_ready goes low)
            @(posedge clk); // RTL samples cmd_valid=1, cmd_ready=1 → latches
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    // Wait for a specific dram_cmd_type; check on posedge
    task wait_for_dram_cmd;
        input [2:0] expected;
        input integer timeout;
        begin
            wait_cnt = 0;
            @(posedge clk);
            while (!(dram_cmd_valid && dram_cmd_type == expected)) begin
                wait_cnt = wait_cnt + 1;
                if (wait_cnt >= timeout)
                    $fatal(1, "SIMULATION FAILED: timeout waiting for dram_cmd_type=%0d", expected);
                @(posedge clk);
            end
        end
    endtask

    initial begin
        rst_n       = 0;
        cmd_valid   = 0;
        cmd_type    = 0;
        cmd_addr    = 0;
        cmd_id      = 0;
        ref_req     = 0;
        ref_rank    = 0;
        ref_bank    = 0;
        timing_ok   = 16'hFFFF;  // all timing satisfied

        repeat(5) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // --- Test 1: WRITE command → ACT → WR → PRE ---
        $display("Test 1: WRITE sequence ACT->WR->PRE");
        issue_cmd(2'd1, 32'h04000000, 4'h1); // WRITE

        wait_for_dram_cmd(3'd4, 50); // CMD_ACT=4
        $display("  Saw ACT");

        wait_for_dram_cmd(3'd5, 50); // CMD_WR=5
        $display("  Saw WR");
        if (!wr_data_req)
            $fatal(1, "SIMULATION FAILED: wr_data_req not asserted with WR");

        wait_for_dram_cmd(3'd3, 50); // CMD_PRE=3
        $display("  Saw PRE");

        repeat(5) @(posedge clk);

        // --- Test 2: READ command → ACT → RD → PRE ---
        $display("Test 2: READ sequence ACT->RD->PRE");
        issue_cmd(2'd0, 32'h04000000, 4'h2); // READ

        wait_for_dram_cmd(3'd4, 50); // ACT
        $display("  Saw ACT");
        wait_for_dram_cmd(3'd6, 50); // CMD_RD=6
        $display("  Saw RD");
        if (!rd_data_req)
            $fatal(1, "SIMULATION FAILED: rd_data_req not asserted with RD");
        wait_for_dram_cmd(3'd3, 50); // PRE
        $display("  Saw PRE");

        repeat(5) @(posedge clk);

        // --- Test 3: Refresh preemption in idle state ---
        $display("Test 3: Refresh preemption");
        @(negedge clk);
        ref_req  = 1'b1;
        ref_rank = 2'd0;
        ref_bank = 4'd0;

        wait_cnt = 0;
        @(posedge clk);
        while (!ref_ack) begin
            wait_cnt = wait_cnt + 1;
            if (wait_cnt >= 50)
                $fatal(1, "SIMULATION FAILED: ref_ack not seen within timeout");
            @(posedge clk);
        end
        $display("  ref_ack received");
        @(negedge clk);
        ref_req = 1'b0;
        $display("  Refresh preemption handled");

        repeat(5) @(posedge clk);
        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
