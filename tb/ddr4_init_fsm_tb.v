`timescale 1ns/1ps
module ddr4_init_fsm_tb;

    reg        clk, rst_n, start;
    wire       dram_cmd_valid;
    wire [2:0] dram_cmd_type;
    wire [1:0] dram_rank;
    wire [16:0] dram_a;
    wire [1:0] dram_bg, dram_ba;
    wire [2:0] mr_select;
    wire       init_done;

    // Provide constant mr_data for the FSM
    reg [16:0] mr_data;

    // DUT
    ddr4_init_fsm #(.RESET_WAIT(10), .ZQCL_WAIT_CYCLES(10)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .dram_cmd_valid(dram_cmd_valid),
        .dram_cmd_type(dram_cmd_type),
        .dram_rank(dram_rank),
        .dram_a(dram_a),
        .dram_bg(dram_bg),
        .dram_ba(dram_ba),
        .mr_select(mr_select),
        .mr_data(mr_data),
        .init_done(init_done)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // VCD
    initial begin
        $dumpfile("results/phase-core-ctrl/ddr4_init_fsm.vcd");
        $dumpvars(0, ddr4_init_fsm_tb);
    end

    integer cycle_count;
    reg saw_mrs;

    initial begin
        rst_n      = 0;
        start      = 0;
        mr_data    = 17'h1A5A5; // arbitrary non-zero
        saw_mrs    = 0;
        cycle_count = 0;

        // Assert reset for 5 cycles, deassert on negedge to avoid posedge race
        repeat(5) @(posedge clk);
        @(negedge clk);
        rst_n = 1;

        // Start initialization — drive on negedge so FSM sees it cleanly
        @(negedge clk);
        start = 1;
        @(posedge clk);
        @(negedge clk);
        start = 0;

        // Wait for init_done (timeout 500 cycles)
        fork
            begin : wait_done
                while (!init_done) begin
                    @(posedge clk);
                    cycle_count = cycle_count + 1;
                    if (dram_cmd_valid && dram_cmd_type == 3'b001)
                        saw_mrs = 1;
                    if (cycle_count >= 500) begin
                        $display("TIMEOUT: init_done not asserted within 500 cycles");
                        $fatal(1, "SIMULATION FAILED: init_done timeout");
                    end
                end
            end
        join

        // Verify MRS was issued
        if (!saw_mrs) begin
            $fatal(1, "SIMULATION FAILED: no MRS command observed");
        end

        // Verify init_done stays high
        @(posedge clk);
        if (!init_done)
            $fatal(1, "SIMULATION FAILED: init_done deasserted unexpectedly");

        $display("init_done asserted after %0d cycles", cycle_count);
        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
