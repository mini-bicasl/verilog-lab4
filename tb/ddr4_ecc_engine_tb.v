`timescale 1ns/1ps
// Testbench: ddr4_ecc_engine
// Covers:
//   1. No error  — syndrome = 0, dec_data_out == enc_data_out extracted data
//   2. Single-bit error at every bit position (0..71) — corrected
//   3. Double-bit error at representative bit pairs — detected, not miscorrected
//   4. Zero syndrome on clean codeword
//   5. DBE at all check-bit spanning pairs — all pairs where ≥1 bit is a check
//      bit position {0,1,2,4,8,16,32,64} (covers all C(8,2)+8×64=540 pairs)
module ddr4_ecc_engine_tb;

    // ---------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------
    reg         clk, rst_n;
    reg  [63:0] enc_data_in;
    wire [71:0] enc_data_out;
    reg  [71:0] dec_data_in;
    wire [63:0] dec_data_out;
    wire        dec_single_err, dec_double_err;
    wire [7:0]  dec_syndrome;
    wire [6:0]  dec_err_bit;

    ddr4_ecc_engine dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .enc_data_in   (enc_data_in),
        .enc_data_out  (enc_data_out),
        .dec_data_in   (dec_data_in),
        .dec_data_out  (dec_data_out),
        .dec_single_err(dec_single_err),
        .dec_double_err(dec_double_err),
        .dec_syndrome  (dec_syndrome),
        .dec_err_bit   (dec_err_bit)
    );

    // ---------------------------------------------------------------
    // Clock: 10 ns period
    // ---------------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // ---------------------------------------------------------------
    // VCD
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("results/phase-data-ecc/ddr4_ecc_engine.vcd");
        $dumpvars(0, ddr4_ecc_engine_tb);
    end

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------
    integer i, j;
    integer pass_cnt, fail_cnt;
    reg [71:0] injected;

    task check_no_error;
        input [63:0] data;
        begin
            enc_data_in = data;
            #1;  // combinatorial settle
            dec_data_in = enc_data_out;
            #1;
            if (dec_syndrome !== 8'h00) begin
                $display("FAIL no-error test: data=%h syndrome=%h", data, dec_syndrome);
                fail_cnt = fail_cnt + 1;
            end else if (dec_data_out !== data) begin
                $display("FAIL no-error: data=%h dec_out=%h", data, dec_data_out);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task check_sbe;
        input [63:0] data;
        input integer bit_pos;
        begin
            enc_data_in = data;
            #1;
            injected    = enc_data_out ^ (72'b1 << bit_pos);
            dec_data_in = injected;
            #1;
            // Special case: error at position 0 (P0 check bit).
            // Hamming syndrome = 0, overall parity = 1.
            // Architecture table does not classify syndrome[7:1]=0,P0=1 as SBE
            // (P0 itself is wrong; no data correction needed).
            if (bit_pos == 0) begin
                if (dec_syndrome !== 8'h01) begin
                    $display("FAIL SBE pos=0 (P0): expected syndrome=01, got %h", dec_syndrome);
                    fail_cnt = fail_cnt + 1;
                end else if (dec_double_err) begin
                    $display("FAIL SBE pos=0: dec_double_err spuriously set");
                    fail_cnt = fail_cnt + 1;
                end else begin
                    pass_cnt = pass_cnt + 1; // P0-only error correctly identified
                end
            end else begin
                // Syndrome[7:1] must equal bit_pos, syndrome[0] must be 1
                if (!dec_single_err) begin
                    $display("FAIL SBE pos=%0d: dec_single_err not set, syndrome=%h",
                             bit_pos, dec_syndrome);
                    fail_cnt = fail_cnt + 1;
                end else if (dec_double_err) begin
                    $display("FAIL SBE pos=%0d: dec_double_err spuriously set", bit_pos);
                    fail_cnt = fail_cnt + 1;
                end else if (dec_err_bit !== bit_pos[6:0]) begin
                    $display("FAIL SBE pos=%0d: dec_err_bit=%0d", bit_pos, dec_err_bit);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    // Verify corrected data matches original for data positions
                    // (check-bit positions 1,2,4,8,16,32,64 don't affect dec_data_out)
                    if (bit_pos != 1 && bit_pos != 2 && bit_pos != 4 &&
                        bit_pos != 8 && bit_pos != 16 && bit_pos != 32 &&
                        bit_pos != 64) begin
                        if (dec_data_out !== data) begin
                            $display("FAIL SBE correction pos=%0d: data=%h dec_out=%h",
                                     bit_pos, data, dec_data_out);
                            fail_cnt = fail_cnt + 1;
                        end else
                            pass_cnt = pass_cnt + 1;
                    end else begin
                        pass_cnt = pass_cnt + 1; // check-bit error: no data change needed
                    end
                end
            end
        end
    endtask

    task check_dbe;
        input [63:0] data;
        input integer pos_a;
        input integer pos_b;
        begin
            enc_data_in = data;
            #1;
            injected    = enc_data_out ^ (72'b1 << pos_a) ^ (72'b1 << pos_b);
            dec_data_in = injected;
            #1;
            if (!dec_double_err) begin
                $display("FAIL DBE pos_a=%0d pos_b=%0d: dec_double_err not set, syn=%h",
                         pos_a, pos_b, dec_syndrome);
                fail_cnt = fail_cnt + 1;
            end else if (dec_single_err) begin
                $display("FAIL DBE pos_a=%0d pos_b=%0d: dec_single_err spuriously set",
                         pos_a, pos_b);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Test body
    // ---------------------------------------------------------------
    initial begin
        rst_n    = 0;
        enc_data_in = 64'h0;
        dec_data_in = 72'h0;
        pass_cnt = 0;
        fail_cnt = 0;

        @(posedge clk); @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ----- Test 1: No-error on several data patterns -----
        $display("=== Test 1: No-error encode/decode ===");
        check_no_error(64'h0000000000000000);
        check_no_error(64'hFFFFFFFFFFFFFFFF);
        check_no_error(64'hA5A5A5A5A5A5A5A5);
        check_no_error(64'h5A5A5A5A5A5A5A5A);
        check_no_error(64'hDEADBEEFCAFEBABE);
        check_no_error(64'h0123456789ABCDEF);

        // ----- Test 2: Single-bit error at every bit position (0..71) -----
        $display("=== Test 2: SBE at every bit position ===");
        for (i = 0; i < 72; i = i + 1) begin
            check_sbe(64'hDEADBEEFCAFEBABE, i);
        end
        // Also test with all-zeros and all-ones data
        for (i = 0; i < 72; i = i + 1) begin
            check_sbe(64'h0000000000000000, i);
        end
        for (i = 0; i < 72; i = i + 1) begin
            check_sbe(64'hFFFFFFFFFFFFFFFF, i);
        end

        // ----- Test 3: Double-bit error — all adjacent pairs (0..70,1..71) -----
        $display("=== Test 3: DBE at adjacent and boundary pairs ===");
        for (i = 0; i < 71; i = i + 1) begin
            check_dbe(64'hA5A5A5A5A5A5A5A5, i, i+1);
        end
        // Pairs spanning check-bit boundaries
        check_dbe(64'hA5A5A5A5A5A5A5A5,  0, 64);
        check_dbe(64'hA5A5A5A5A5A5A5A5,  1, 32);
        check_dbe(64'hA5A5A5A5A5A5A5A5,  2, 16);
        check_dbe(64'hA5A5A5A5A5A5A5A5,  4, 8);
        check_dbe(64'hA5A5A5A5A5A5A5A5,  0, 71);
        check_dbe(64'hA5A5A5A5A5A5A5A5,  3, 65);
        check_dbe(64'hA5A5A5A5A5A5A5A5, 31, 63);

        // ----- Test 4: Zero syndrome on clean encoded word -----
        $display("=== Test 4: Zero syndrome on clean codeword ===");
        enc_data_in = 64'hCAFEBABEDEAD1234;
        #1;
        dec_data_in = enc_data_out;
        #1;
        if (dec_syndrome !== 8'h00) begin
            $display("FAIL clean codeword has non-zero syndrome: %h", dec_syndrome);
            fail_cnt = fail_cnt + 1;
        end else
            pass_cnt = pass_cnt + 1;

        // ----- Test 5: DBE at all check-bit spanning pairs -----
        // Check-bit positions: 0 (P0), 1 (P1), 2 (P2), 4 (P4), 8 (P8),
        //                      16 (P16), 32 (P32), 64 (P64)
        // Test every ordered pair (i < j) where at least one of i,j is a check bit.
        // This exercises all C(8,2)=28 check/check pairs and 8×64=512 check/data pairs.
        $display("=== Test 5: DBE at all check-bit spanning pairs ===");
        begin : T5_chk
            integer is_chk_i, is_chk_j;
            for (i = 0; i < 72; i = i + 1) begin
                is_chk_i = (i==0)||(i==1)||(i==2)||(i==4)||(i==8)||(i==16)||(i==32)||(i==64);
                for (j = i + 1; j < 72; j = j + 1) begin
                    is_chk_j = (j==0)||(j==1)||(j==2)||(j==4)||(j==8)||(j==16)||(j==32)||(j==64);
                    if (is_chk_i || is_chk_j) begin
                        check_dbe(64'h5A5A5A5A5A5A5A5A, i, j);
                    end
                end
            end
        end

        // ----- Summary -----
        #10;
        $display("=== RESULTS: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("PASS: ddr4_ecc_engine all tests passed");
        else
            $display("FAIL: ddr4_ecc_engine %0d tests failed", fail_cnt);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #2000000;
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule
