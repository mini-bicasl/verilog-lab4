`timescale 1ns/1ps
// Testbench for ddr4_host_iface
// Tests: AXI4 single-beat WRITE, AXI4 single-beat READ, burst WRITE,
//        cmd_valid/cmd_ready handshake, write response, read data return.
module ddr4_host_iface_tb;

    // DUT parameters
    localparam AXI_DATA_WIDTH = 64;
    localparam AXI_ADDR_WIDTH = 32;
    localparam AXI_ID_WIDTH   = 4;

    reg  clk, rst_n;

    // AXI4 write address
    reg  [AXI_ID_WIDTH-1:0]     awid;
    reg  [AXI_ADDR_WIDTH-1:0]   awaddr;
    reg  [7:0]                  awlen;
    reg  [2:0]                  awsize;
    reg  [1:0]                  awburst;
    reg                         awvalid;
    wire                        awready;
    // AXI4 write data
    reg  [AXI_DATA_WIDTH-1:0]   wdata;
    reg  [AXI_DATA_WIDTH/8-1:0] wstrb;
    reg                         wlast;
    reg                         wvalid;
    wire                        wready;
    // AXI4 write response
    wire [AXI_ID_WIDTH-1:0]     bid;
    wire [1:0]                  bresp;
    wire                        bvalid;
    reg                         bready;
    // AXI4 read address
    reg  [AXI_ID_WIDTH-1:0]     arid;
    reg  [AXI_ADDR_WIDTH-1:0]   araddr;
    reg  [7:0]                  arlen;
    reg  [2:0]                  arsize;
    reg  [1:0]                  arburst;
    reg                         arvalid;
    wire                        arready;
    // AXI4 read data
    wire [AXI_ID_WIDTH-1:0]     rid;
    wire [AXI_DATA_WIDTH-1:0]   rdata;
    wire [1:0]                  rresp;
    wire                        rlast;
    wire                        rvalid;
    reg                         rready;

    // Internal command interface
    wire                        cmd_valid;
    reg                         cmd_ready;
    wire [1:0]                  cmd_type;
    wire [AXI_ADDR_WIDTH-1:0]   cmd_addr;
    wire [AXI_ID_WIDTH-1:0]     cmd_id;

    // Write data path
    wire                        wdata_valid;
    reg                         wdata_ready;
    wire [AXI_DATA_WIDTH-1:0]   wdata_out;
    wire [AXI_DATA_WIDTH/8-1:0] wdata_strb_out;

    // Read data return
    reg                         rdata_valid_in;
    reg  [AXI_DATA_WIDTH-1:0]   rdata_in;
    reg  [AXI_ID_WIDTH-1:0]     rdata_id_in;
    reg                         rdata_err_in;

    ddr4_host_iface #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (awid),
        .s_axi_awaddr   (awaddr),
        .s_axi_awlen    (awlen),
        .s_axi_awsize   (awsize),
        .s_axi_awburst  (awburst),
        .s_axi_awvalid  (awvalid),
        .s_axi_awready  (awready),
        .s_axi_wdata    (wdata),
        .s_axi_wstrb    (wstrb),
        .s_axi_wlast    (wlast),
        .s_axi_wvalid   (wvalid),
        .s_axi_wready   (wready),
        .s_axi_bid      (bid),
        .s_axi_bresp    (bresp),
        .s_axi_bvalid   (bvalid),
        .s_axi_bready   (bready),
        .s_axi_arid     (arid),
        .s_axi_araddr   (araddr),
        .s_axi_arlen    (arlen),
        .s_axi_arsize   (arsize),
        .s_axi_arburst  (arburst),
        .s_axi_arvalid  (arvalid),
        .s_axi_arready  (arready),
        .s_axi_rid      (rid),
        .s_axi_rdata    (rdata),
        .s_axi_rresp    (rresp),
        .s_axi_rlast    (rlast),
        .s_axi_rvalid   (rvalid),
        .s_axi_rready   (rready),
        .cmd_valid      (cmd_valid),
        .cmd_ready      (cmd_ready),
        .cmd_type       (cmd_type),
        .cmd_addr       (cmd_addr),
        .cmd_id         (cmd_id),
        .wdata_valid    (wdata_valid),
        .wdata_ready    (wdata_ready),
        .wdata          (wdata_out),
        .wdata_strb     (wdata_strb_out),
        .rdata_valid    (rdata_valid_in),
        .rdata          (rdata_in),
        .rdata_id       (rdata_id_in),
        .rdata_err      (rdata_err_in)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-integration/ddr4_host_iface.vcd");
        $dumpvars(0, ddr4_host_iface_tb);
    end

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Helper: wait N clocks
    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // Helper: issue one AXI4 write beat (single-beat burst)
    task axi_write;
        input [AXI_ID_WIDTH-1:0]   id;
        input [AXI_ADDR_WIDTH-1:0] addr;
        input [AXI_DATA_WIDTH-1:0] data;
        integer timeout;
        begin
            timeout = 0;
            @(negedge clk);
            awid    = id;
            awaddr  = addr;
            awlen   = 8'd0;    // 1 beat
            awsize  = 3'd3;    // 8 bytes
            awburst = 2'd1;    // INCR
            awvalid = 1'b1;
            wdata   = data;
            wstrb   = 8'hFF;
            wlast   = 1'b1;
            wvalid  = 1'b1;
            bready  = 1'b1;
            // Wait for aw handshake
            @(posedge clk);
            while (!awready) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) $fatal(1, "T1: awready timeout");
            end
            @(negedge clk);
            awvalid = 1'b0;
            // Wait for w handshake
            timeout = 0;
            @(posedge clk);
            while (!wready) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) $fatal(1, "T1: wready timeout");
            end
            @(negedge clk);
            wvalid = 1'b0;
            // Wait for b response
            timeout = 0;
            @(posedge clk);
            while (!bvalid) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) $fatal(1, "T1: bvalid timeout");
            end
        end
    endtask

    // Helper: issue one AXI4 read (single-beat)
    task axi_read_issue;
        input [AXI_ID_WIDTH-1:0]   id;
        input [AXI_ADDR_WIDTH-1:0] addr;
        integer timeout;
        begin
            timeout = 0;
            @(negedge clk);
            arid    = id;
            araddr  = addr;
            arlen   = 8'd0;
            arsize  = 3'd3;
            arburst = 2'd1;
            arvalid = 1'b1;
            rready  = 1'b1;
            @(posedge clk);
            while (!arready) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 50) $fatal(1, "T2: arready timeout");
            end
            @(negedge clk);
            arvalid = 1'b0;
        end
    endtask

    initial begin
        // Reset
        rst_n        = 0;
        awvalid      = 0; awid   = 0; awaddr  = 0; awlen = 0; awsize = 0; awburst = 0;
        wvalid       = 0; wdata  = 0; wstrb   = 0; wlast = 0;
        bready       = 0;
        arvalid      = 0; arid   = 0; araddr  = 0; arlen = 0; arsize = 0; arburst = 0;
        rready       = 0;
        cmd_ready    = 1;
        wdata_ready  = 1;
        rdata_valid_in = 0; rdata_in = 0; rdata_id_in = 0; rdata_err_in = 0;

        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(3) @(posedge clk);

        // -------------------------------------------------------
        // Test 1: Single AXI4 WRITE — verify cmd_valid with WRITE type
        // -------------------------------------------------------
        $display("Test 1: Single AXI4 WRITE -> cmd_valid/cmd_type=WRITE");
        fork
            // Drive cmd_ready when cmd_valid asserted
            begin
                @(posedge cmd_valid);
                if (cmd_type !== 2'b01)
                    $fatal(1, "T1 FAIL: cmd_type=%0b expected WRITE(01)", cmd_type);
                $display("  T1: cmd_valid seen, cmd_type=WRITE, addr=%h, id=%0d",
                         cmd_addr, cmd_id);
                pass_cnt = pass_cnt + 1;
            end
            axi_write(4'h1, 32'h1000, 64'hDEAD_BEEF_CAFE_0001);
        join
        wait_clk(5);

        // -------------------------------------------------------
        // Test 2: AXI4 READ — verify cmd_valid with READ type and read data return
        // -------------------------------------------------------
        $display("Test 2: Single AXI4 READ -> cmd_valid/cmd_type=READ and rdata");
        fork
            begin
                @(posedge cmd_valid);
                if (cmd_type !== 2'b00)
                    $fatal(1, "T2 FAIL: cmd_type=%0b expected READ(00)", cmd_type);
                $display("  T2: cmd_valid seen, cmd_type=READ, addr=%h", cmd_addr);
                // Simulate data path returning data
                repeat(3) @(posedge clk);
                @(negedge clk);
                rdata_valid_in = 1'b1;
                rdata_in       = 64'hCAFE_BABE_1234_5678;
                rdata_id_in    = 4'h2;
                rdata_err_in   = 1'b0;
                @(posedge clk);
                @(negedge clk);
                rdata_valid_in = 1'b0;
            end
            axi_read_issue(4'h2, 32'h2000);
        join
        // Wait for rvalid
        begin : t2_rdata
            integer to2;
            to2 = 0;
            @(posedge clk);
            while (!rvalid) begin
                @(posedge clk);
                to2 = to2 + 1;
                if (to2 > 30) $fatal(1, "T2 FAIL: rvalid timeout");
            end
            if (rdata !== 64'hCAFE_BABE_1234_5678)
                $fatal(1, "T2 FAIL: rdata mismatch got=%h", rdata);
            $display("  T2: rvalid seen, rdata=%h", rdata);
            pass_cnt = pass_cnt + 1;
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 3: 2-beat AXI4 burst WRITE — verify two cmd_valid pulses
        // -------------------------------------------------------
        $display("Test 3: 2-beat burst WRITE -> two cmd_valid pulses");
        begin : t3
            integer seen_cmds;
            integer to3;
            seen_cmds = 0;
            // Issue burst write address
            @(negedge clk);
            awid    = 4'h3;
            awaddr  = 32'h3000;
            awlen   = 8'd1;   // 2 beats (len=1)
            awsize  = 3'd3;
            awburst = 2'd1;
            awvalid = 1'b1;
            bready  = 1'b1;
            to3     = 0;
            @(posedge clk);
            while (!awready) begin @(posedge clk); to3=to3+1; if(to3>50) $fatal(1,"T3 aw timeout"); end
            @(negedge clk); awvalid = 1'b0;

            // Issue beat 1
            wdata  = 64'hAAAA_1111_BBBB_2222;
            wstrb  = 8'hFF;
            wlast  = 1'b0;
            wvalid = 1'b1;
            to3    = 0;
            @(posedge clk);
            while (!wready) begin @(posedge clk); to3=to3+1; if(to3>50) $fatal(1,"T3 w1 timeout"); end
            @(posedge cmd_valid); seen_cmds = seen_cmds + 1;

            // Issue beat 2 (last)
            @(negedge clk);
            wdata  = 64'hCCCC_3333_DDDD_4444;
            wlast  = 1'b1;
            to3    = 0;
            @(posedge clk);
            while (!wready) begin @(posedge clk); to3=to3+1; if(to3>50) $fatal(1,"T3 w2 timeout"); end
            @(posedge cmd_valid); seen_cmds = seen_cmds + 1;
            @(negedge clk); wvalid = 1'b0;

            // Wait for BRESP
            to3 = 0;
            @(posedge clk);
            while (!bvalid) begin @(posedge clk); to3=to3+1; if(to3>50) $fatal(1,"T3 bresp timeout"); end

            if (seen_cmds == 2) begin
                $display("  T3: saw 2 cmd_valid pulses for 2-beat burst");
                pass_cnt = pass_cnt + 1;
            end else
                $fatal(1, "T3 FAIL: expected 2 cmds, saw %0d", seen_cmds);
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 4: cmd_ready back-pressure on write
        // -------------------------------------------------------
        $display("Test 4: cmd_ready back-pressure");
        begin : t4
            integer to4;
            cmd_ready = 1'b0;  // hold off scheduler
            @(negedge clk);
            awid    = 4'h4;
            awaddr  = 32'h4000;
            awlen   = 8'd0;
            awsize  = 3'd3;
            awburst = 2'd1;
            awvalid = 1'b1;
            wdata   = 64'hF00D_F00D_F00D_F00D;
            wstrb   = 8'hFF;
            wlast   = 1'b1;
            wvalid  = 1'b1;
            bready  = 1'b1;
            to4     = 0;
            @(posedge clk);
            while (!awready) begin @(posedge clk); to4=to4+1; if(to4>50) $fatal(1,"T4 aw timeout"); end
            @(negedge clk); awvalid = 1'b0;
            to4 = 0;
            @(posedge clk);
            while (!wready) begin @(posedge clk); to4=to4+1; if(to4>50) $fatal(1,"T4 wr timeout"); end
            @(negedge clk); wvalid = 1'b0;
            // Give 3 cycles with cmd_ready=0 — cmd should be pending
            repeat(3) @(posedge clk);
            // Now release cmd_ready
            @(negedge clk); cmd_ready = 1'b1;
            // cmd_valid should fire
            to4 = 0;
            @(posedge clk);
            while (!cmd_valid) begin
                @(posedge clk); to4=to4+1;
                if(to4>20) $fatal(1,"T4 FAIL: cmd_valid never asserted after cmd_ready release");
            end
            $display("  T4: cmd_valid asserted after cmd_ready released");
            pass_cnt = pass_cnt + 1;
            // Wait for BRESP
            to4 = 0;
            @(posedge clk);
            while (!bvalid) begin @(posedge clk); to4=to4+1; if(to4>50) $fatal(1,"T4 bvalid timeout"); end
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 5: Read-only traffic — two back-to-back reads, no writes
        // -------------------------------------------------------
        $display("Test 5: Read-only traffic — two consecutive single-beat reads");
        begin : t5
            integer to5;
            integer rd_cnt;
            rd_cnt = 0;

            // Issue read 1
            @(negedge clk);
            arid    = 4'h5;
            araddr  = 32'h5000;
            arlen   = 8'd0;
            arsize  = 3'd3;
            arburst = 2'd1;
            arvalid = 1'b1;
            rready  = 1'b1;
            to5     = 0;
            @(posedge clk);
            while (!arready) begin @(posedge clk); to5=to5+1; if(to5>50) $fatal(1,"T5 ar1 timeout"); end
            @(negedge clk); arvalid = 1'b0;
            // Feed rdata for read 1
            to5 = 0;
            @(posedge clk);
            while (!cmd_valid) begin @(posedge clk); to5=to5+1; if(to5>30) $fatal(1,"T5 cmd_valid r1 timeout"); end
            repeat(2) @(posedge clk);
            @(negedge clk);
            rdata_valid_in = 1'b1;
            rdata_in       = 64'h1111_2222_3333_4444;
            rdata_id_in    = 4'h5;
            rdata_err_in   = 1'b0;
            @(posedge clk);
            @(negedge clk); rdata_valid_in = 1'b0;
            // Wait for rvalid
            to5 = 0;
            @(posedge clk);
            while (!rvalid) begin @(posedge clk); to5=to5+1; if(to5>30) $fatal(1,"T5 rvalid1 timeout"); end
            if (rdata !== 64'h1111_2222_3333_4444)
                $fatal(1, "T5 FAIL: rdata1 mismatch got=%h", rdata);
            rd_cnt = rd_cnt + 1;
            wait_clk(3);

            // Issue read 2
            @(negedge clk);
            arid    = 4'h6;
            araddr  = 32'h6000;
            arvalid = 1'b1;
            rready  = 1'b1;
            to5     = 0;
            @(posedge clk);
            while (!arready) begin @(posedge clk); to5=to5+1; if(to5>50) $fatal(1,"T5 ar2 timeout"); end
            @(negedge clk); arvalid = 1'b0;
            // Feed rdata for read 2
            to5 = 0;
            @(posedge clk);
            while (!cmd_valid) begin @(posedge clk); to5=to5+1; if(to5>30) $fatal(1,"T5 cmd_valid r2 timeout"); end
            repeat(2) @(posedge clk);
            @(negedge clk);
            rdata_valid_in = 1'b1;
            rdata_in       = 64'h5555_6666_7777_8888;
            rdata_id_in    = 4'h6;
            rdata_err_in   = 1'b0;
            @(posedge clk);
            @(negedge clk); rdata_valid_in = 1'b0;
            // Wait for rvalid
            to5 = 0;
            @(posedge clk);
            while (!rvalid) begin @(posedge clk); to5=to5+1; if(to5>30) $fatal(1,"T5 rvalid2 timeout"); end
            if (rdata !== 64'h5555_6666_7777_8888)
                $fatal(1, "T5 FAIL: rdata2 mismatch got=%h", rdata);
            rd_cnt = rd_cnt + 1;

            if (rd_cnt == 2) begin
                $display("  T5: Both read-only reads returned correct data (%0d reads)", rd_cnt);
                pass_cnt = pass_cnt + 1;
            end else
                $fatal(1, "T5 FAIL: expected 2 reads, got %0d", rd_cnt);
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 6: Mixed traffic — write then read, both cmds observed
        // Strategy: start the cmd_valid edge monitor as soon as write
        // data handshake completes (before AR), so the WRITE cmd pulse
        // (which fires ~2 cycles later) is captured.
        // -------------------------------------------------------
        $display("Test 6: Mixed traffic — write followed immediately by read");
        begin : t6
            integer to6;
            integer got_wr_cmd;
            integer got_rd_cmd;
            got_wr_cmd = 0;
            got_rd_cmd = 0;

            // AW handshake
            @(negedge clk);
            awid    = 4'h7;
            awaddr  = 32'h7000;
            awlen   = 8'd0;
            awsize  = 3'd3;
            awburst = 2'd1;
            awvalid = 1'b1;
            bready  = 1'b1;
            wdata   = 64'hAAAA_BBBB_CCCC_DDDD;
            wstrb   = 8'hFF;
            wlast   = 1'b1;
            wvalid  = 1'b1;
            to6     = 0;
            @(posedge clk);
            while (!awready) begin @(posedge clk); to6=to6+1; if(to6>50) $fatal(1,"T6 aw timeout"); end
            @(negedge clk); awvalid = 1'b0;
            // W handshake
            to6 = 0;
            @(posedge clk);
            while (!wready) begin @(posedge clk); to6=to6+1; if(to6>50) $fatal(1,"T6 wr timeout"); end
            @(negedge clk); wvalid = 1'b0;
            // Fork: monitor cmd_valid edges while issuing the read AR
            // cmd_valid for WRITE fires ~2 cycles after wready handshake,
            // so the monitor must start HERE (before AR) to catch it.
            fork
                begin : t6_monitor
                    integer mon_to;
                    // Catch WRITE cmd pulse (edge-triggered, reliable)
                    @(posedge cmd_valid);
                    if (cmd_type === 2'b01) got_wr_cmd = 1;
                    // Catch READ cmd pulse
                    mon_to = 0;
                    @(posedge cmd_valid);
                    if (cmd_type === 2'b00) got_rd_cmd = 1;
                    // Feed read data so read FSM can complete
                    repeat(2) @(posedge clk);
                    @(negedge clk);
                    rdata_valid_in = 1'b1;
                    rdata_in       = 64'hEEEE_FFFF_0000_1111;
                    rdata_id_in    = 4'h8;
                    rdata_err_in   = 1'b0;
                    @(posedge clk);
                    @(negedge clk); rdata_valid_in = 1'b0;
                    // Wait for rvalid (rready=1 so it may pulse briefly)
                    mon_to = 0;
                    @(posedge clk);
                    while (!rvalid) begin
                        @(posedge clk); mon_to=mon_to+1;
                        if (mon_to>20) $fatal(1,"T6 FAIL: rvalid timeout");
                    end
                end
                begin : t6_read
                    @(negedge clk);
                    arid    = 4'h8;
                    araddr  = 32'h8000;
                    arlen   = 8'd0;
                    arsize  = 3'd3;
                    arburst = 2'd1;
                    arvalid = 1'b1;
                    rready  = 1'b1;
                    to6     = 0;
                    @(posedge clk);
                    while (!arready) begin @(posedge clk); to6=to6+1; if(to6>50) $fatal(1,"T6 ar timeout"); end
                    @(negedge clk); arvalid = 1'b0;
                end
            join

            if (got_wr_cmd && got_rd_cmd) begin
                $display("  T6: Mixed traffic OK — WRITE cmd and READ cmd both observed");
                pass_cnt = pass_cnt + 1;
            end else
                $fatal(1, "T6 FAIL: wr_cmd=%0d rd_cmd=%0d", got_wr_cmd, got_rd_cmd);
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 7: Narrow burst write (awsize=1, 2-byte lane)
        // -------------------------------------------------------
        $display("Test 7: Narrow burst write (awsize=1 → 2-byte strobe)");
        begin : t7
            integer to7;
            @(negedge clk);
            awid    = 4'h9;
            awaddr  = 32'h9002;   // byte-aligned to 2-byte boundary
            awlen   = 8'd0;
            awsize  = 3'd1;       // narrow: 2 bytes per beat
            awburst = 2'd1;
            awvalid = 1'b1;
            wdata   = 64'hDEAD_BEEF_DEAD_BEEF;
            wstrb   = 8'h0C;      // bytes [3:2] active for awsize=1 at offset 2
            wlast   = 1'b1;
            wvalid  = 1'b1;
            bready  = 1'b1;
            to7     = 0;
            @(posedge clk);
            while (!awready) begin @(posedge clk); to7=to7+1; if(to7>50) $fatal(1,"T7 aw timeout"); end
            @(negedge clk); awvalid = 1'b0;
            to7 = 0;
            @(posedge clk);
            while (!wready) begin @(posedge clk); to7=to7+1; if(to7>50) $fatal(1,"T7 wr timeout"); end
            @(negedge clk); wvalid = 1'b0;
            // Should generate a cmd_valid for WRITE
            to7 = 0;
            @(posedge clk);
            while (!cmd_valid) begin @(posedge clk); to7=to7+1; if(to7>30) $fatal(1,"T7 cmd_valid timeout"); end
            if (cmd_type !== 2'b01)
                $fatal(1, "T7 FAIL: expected WRITE cmd_type, got %b", cmd_type);
            to7 = 0;
            @(posedge clk);
            while (!bvalid) begin @(posedge clk); to7=to7+1; if(to7>50) $fatal(1,"T7 bvalid timeout"); end
            if (bresp !== 2'b00)
                $fatal(1, "T7 FAIL: bresp=%b expected OKAY", bresp);
            $display("  T7: Narrow burst write completed with BRESP=OKAY");
            pass_cnt = pass_cnt + 1;
        end
        wait_clk(5);

        // -------------------------------------------------------
        // Test 8: rready back-pressure on read data return
        // -------------------------------------------------------
        $display("Test 8: rready back-pressure — hold rready low then release");
        begin : t8
            integer to8;
            rready = 1'b0;   // back-pressure on read return

            @(negedge clk);
            arid    = 4'hA;
            araddr  = 32'hA000;
            arlen   = 8'd0;
            arsize  = 3'd3;
            arburst = 2'd1;
            arvalid = 1'b1;
            to8     = 0;
            @(posedge clk);
            while (!arready) begin @(posedge clk); to8=to8+1; if(to8>50) $fatal(1,"T8 ar timeout"); end
            @(negedge clk); arvalid = 1'b0;

            // Wait for cmd_valid (READ), then feed rdata
            to8 = 0;
            @(posedge clk);
            while (!cmd_valid) begin @(posedge clk); to8=to8+1; if(to8>30) $fatal(1,"T8 cmd_valid timeout"); end
            repeat(2) @(posedge clk);
            @(negedge clk);
            rdata_valid_in = 1'b1;
            rdata_in       = 64'hBEEF_CAFE_FEED_FACE;
            rdata_id_in    = 4'hA;
            rdata_err_in   = 1'b0;
            @(posedge clk);
            @(negedge clk); rdata_valid_in = 1'b0;

            // rvalid should be high but rdata held until rready asserted
            to8 = 0;
            @(posedge clk);
            while (!rvalid) begin @(posedge clk); to8=to8+1; if(to8>30) $fatal(1,"T8 rvalid timeout"); end
            // Hold rready=0 for 3 more cycles — rvalid must stay asserted
            repeat(3) @(posedge clk);
            if (!rvalid)
                $fatal(1, "T8 FAIL: rvalid dropped before rready asserted");
            // Now release rready
            @(negedge clk); rready = 1'b1;
            @(posedge clk);
            if (rdata !== 64'hBEEF_CAFE_FEED_FACE)
                $fatal(1, "T8 FAIL: rdata mismatch got=%h", rdata);
            $display("  T8: rready back-pressure OK — rvalid held, data correct");
            pass_cnt = pass_cnt + 1;
        end
        wait_clk(5);

        // Report results
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("PASS: ddr4_host_iface all tests passed");
        else
            $fatal(1, "FAIL: ddr4_host_iface had %0d failures", fail_cnt);
        $finish;
    end

endmodule
