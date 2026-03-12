`timescale 1ns/1ps
module ddr4_mode_reg_tb;

    reg        clk, rst_n;
    reg [4:0]  cfg_cl, cfg_cwl;
    reg [1:0]  cfg_al;
    reg [2:0]  cfg_rtt_nom, cfg_rtt_wr, cfg_rtt_park;
    reg [1:0]  cfg_drive_strength;
    reg [3:0]  cfg_wr_recovery;
    reg        cfg_dbi_rd_en, cfg_dbi_wr_en, cfg_ca_parity_en;
    reg [2:0]  mr_select;
    wire [16:0] mr_data;

    ddr4_mode_reg dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_cl(cfg_cl), .cfg_cwl(cfg_cwl),
        .cfg_al(cfg_al),
        .cfg_rtt_nom(cfg_rtt_nom), .cfg_rtt_wr(cfg_rtt_wr),
        .cfg_rtt_park(cfg_rtt_park),
        .cfg_drive_strength(cfg_drive_strength),
        .cfg_wr_recovery(cfg_wr_recovery),
        .cfg_dbi_rd_en(cfg_dbi_rd_en), .cfg_dbi_wr_en(cfg_dbi_wr_en),
        .cfg_ca_parity_en(cfg_ca_parity_en),
        .mr_select(mr_select),
        .mr_data(mr_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("results/phase-core-ctrl/ddr4_mode_reg.vcd");
        $dumpvars(0, ddr4_mode_reg_tb);
    end

    task read_mr;
        input [2:0] sel;
        output [16:0] data;
        begin
            mr_select = sel;
            #1;
            data = mr_data;
        end
    endtask

    reg [16:0] data0, data1, data2, data3, data4, data5, data6;

    initial begin
        rst_n = 0;
        // cfg: CL=22, CWL=16, others typical
        cfg_cl             = 5'd22;
        cfg_cwl            = 5'd16;
        cfg_al             = 2'd0;
        cfg_rtt_nom        = 3'd4;
        cfg_rtt_wr         = 3'd1;
        cfg_rtt_park       = 3'd2;
        cfg_drive_strength = 2'd0;
        cfg_wr_recovery    = 4'd8;
        cfg_dbi_rd_en      = 1'b1;
        cfg_dbi_wr_en      = 1'b0;
        cfg_ca_parity_en   = 1'b1;
        mr_select          = 3'd0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Read all MRs
        read_mr(3'd0, data0);
        read_mr(3'd1, data1);
        read_mr(3'd2, data2);
        read_mr(3'd3, data3);
        read_mr(3'd4, data4);
        read_mr(3'd5, data5);
        read_mr(3'd6, data6);

        $display("MR0=0x%05x MR1=0x%05x MR2=0x%05x MR3=0x%05x",
                 data0, data1, data2, data3);
        $display("MR4=0x%05x MR5=0x%05x MR6=0x%05x",
                 data4, data5, data6);

        // Verify MR2 bits[5:3] = (CWL-9)[2:0] = (16-9)[2:0] = 7[2:0] = 3'b111
        if (data2[5:3] !== 3'b111) begin
            $display("FAIL: MR2[5:3]=%0b, expected 3'b111 (CWL=16, cwl_enc=7)",
                     data2[5:3]);
            $fatal(1, "SIMULATION FAILED");
        end

        // Verify MR3, MR4, MR6 are zero
        if (data3 !== 17'h0)
            $fatal(1, "SIMULATION FAILED: MR3 should be 0, got 0x%05x", data3);
        if (data4 !== 17'h0)
            $fatal(1, "SIMULATION FAILED: MR4 should be 0, got 0x%05x", data4);
        if (data6 !== 17'h0)
            $fatal(1, "SIMULATION FAILED: MR6 should be 0, got 0x%05x", data6);

        // Verify MR5 DBI_RD bit (bit12)
        if (data5[12] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: MR5[12] DBI_RD should be 1");
        // Verify MR5 CA_PARITY bit (bit0)
        if (data5[0] !== 1'b1)
            $fatal(1, "SIMULATION FAILED: MR5[0] CA_PARITY should be 1");

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
