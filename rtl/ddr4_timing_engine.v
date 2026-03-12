// DDR4 Timing Engine — per-bank/rank down-counters for all 16 JEDEC constraints
// timing_ok[i] = 1 when counter[i] == 0 (constraint satisfied)
module ddr4_timing_engine #(
    parameter NUM_BANKS   = 16,
    parameter NUM_BG      = 4,
    parameter tRCD_DEF    = 11,
    parameter tRP_DEF     = 11,
    parameter tRAS_DEF    = 28,
    parameter tRC_DEF     = 39,
    parameter tCCD_L_DEF  = 6,
    parameter tCCD_S_DEF  = 4,
    parameter tRRD_L_DEF  = 6,
    parameter tRRD_S_DEF  = 4,
    parameter tWR_DEF     = 15,
    parameter tWTR_L_DEF  = 12,
    parameter tWTR_S_DEF  = 4,
    parameter tRTP_DEF    = 6,
    parameter tFAW_DEF    = 16,
    parameter tRFC_DEF    = 420,
    parameter tMOD_DEF    = 24,
    parameter tZQ_DEF     = 64
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        dram_cmd_valid,
    input  wire [2:0]  dram_cmd_type,
    input  wire [1:0]  dram_rank,
    input  wire [1:0]  dram_bg,
    input  wire [1:0]  dram_ba,

    input  wire [4:0]  cfg_cl,
    input  wire [4:0]  cfg_cwl,
    input  wire [7:0]  cfg_trcd,
    input  wire [7:0]  cfg_trp,
    input  wire [7:0]  cfg_tras,
    input  wire [7:0]  cfg_trc,
    input  wire [9:0]  cfg_trfc,
    input  wire [13:0] cfg_trefi,

    output wire [15:0] timing_ok
);

    // timing_ok bit indices
    localparam T_RCD   = 0;
    localparam T_RP    = 1;
    localparam T_RAS   = 2;
    localparam T_RC    = 3;
    localparam T_CCD_L = 4;
    localparam T_CCD_S = 5;
    localparam T_RRD_L = 6;
    localparam T_RRD_S = 7;
    localparam T_WR    = 8;
    localparam T_WTR_L = 9;
    localparam T_WTR_S = 10;
    localparam T_RTP   = 11;
    localparam T_FAW   = 12;
    localparam T_RFC   = 13;
    localparam T_MOD   = 14;
    localparam T_ZQ    = 15;

    // Command type encoding
    localparam CMD_NOP  = 3'd0;
    localparam CMD_MRS  = 3'd1;
    localparam CMD_REF  = 3'd2;
    localparam CMD_PRE  = 3'd3;
    localparam CMD_ACT  = 3'd4;
    localparam CMD_WR   = 3'd5;
    localparam CMD_RD   = 3'd6;
    localparam CMD_ZQCL = 3'd7;

    // Bank index from bg/ba
    wire [3:0] bank_idx = {dram_bg, dram_ba};

    // Per-bank counters (addressed by {bg,ba} = 4 bits = 16 banks)
    reg [7:0]  cnt_rcd [0:15];
    reg [7:0]  cnt_rp  [0:15];
    reg [7:0]  cnt_ras [0:15];
    reg [7:0]  cnt_rc  [0:15];
    reg [7:0]  cnt_rtp [0:15];
    reg [7:0]  cnt_wr  [0:15];

    // Rank-level counters
    reg [9:0]  cnt_rfc;
    reg [7:0]  cnt_faw;
    reg [7:0]  cnt_rrd_l;
    reg [7:0]  cnt_rrd_s;
    reg [7:0]  cnt_ccd_l;
    reg [7:0]  cnt_ccd_s;
    reg [7:0]  cnt_wtr_l;
    reg [7:0]  cnt_wtr_s;
    reg [7:0]  cnt_mod;
    reg [7:0]  cnt_zq;

    // Effective timing values (use cfg if nonzero, else defaults)
    wire [7:0]  trcd_val  = (cfg_trcd  != 0) ? cfg_trcd  : tRCD_DEF[7:0];
    wire [7:0]  trp_val   = (cfg_trp   != 0) ? cfg_trp   : tRP_DEF[7:0];
    wire [7:0]  tras_val  = (cfg_tras  != 0) ? cfg_tras  : tRAS_DEF[7:0];
    wire [7:0]  trc_val   = (cfg_trc   != 0) ? cfg_trc   : tRC_DEF[7:0];
    wire [9:0]  trfc_val  = (cfg_trfc  != 0) ? cfg_trfc  : tRFC_DEF[9:0];

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                cnt_rcd[i] <= 8'd0;
                cnt_rp[i]  <= 8'd0;
                cnt_ras[i] <= 8'd0;
                cnt_rc[i]  <= 8'd0;
                cnt_rtp[i] <= 8'd0;
                cnt_wr[i]  <= 8'd0;
            end
            cnt_rfc   <= 10'd0;
            cnt_faw   <= 8'd0;
            cnt_rrd_l <= 8'd0;
            cnt_rrd_s <= 8'd0;
            cnt_ccd_l <= 8'd0;
            cnt_ccd_s <= 8'd0;
            cnt_wtr_l <= 8'd0;
            cnt_wtr_s <= 8'd0;
            cnt_mod   <= 8'd0;
            cnt_zq    <= 8'd0;
        end else begin
            // Decrement all non-zero counters
            for (i = 0; i < 16; i = i + 1) begin
                if (cnt_rcd[i] != 0) cnt_rcd[i] <= cnt_rcd[i] - 1;
                if (cnt_rp[i]  != 0) cnt_rp[i]  <= cnt_rp[i]  - 1;
                if (cnt_ras[i] != 0) cnt_ras[i] <= cnt_ras[i] - 1;
                if (cnt_rc[i]  != 0) cnt_rc[i]  <= cnt_rc[i]  - 1;
                if (cnt_rtp[i] != 0) cnt_rtp[i] <= cnt_rtp[i] - 1;
                if (cnt_wr[i]  != 0) cnt_wr[i]  <= cnt_wr[i]  - 1;
            end
            if (cnt_rfc   != 0) cnt_rfc   <= cnt_rfc   - 1;
            if (cnt_faw   != 0) cnt_faw   <= cnt_faw   - 1;
            if (cnt_rrd_l != 0) cnt_rrd_l <= cnt_rrd_l - 1;
            if (cnt_rrd_s != 0) cnt_rrd_s <= cnt_rrd_s - 1;
            if (cnt_ccd_l != 0) cnt_ccd_l <= cnt_ccd_l - 1;
            if (cnt_ccd_s != 0) cnt_ccd_s <= cnt_ccd_s - 1;
            if (cnt_wtr_l != 0) cnt_wtr_l <= cnt_wtr_l - 1;
            if (cnt_wtr_s != 0) cnt_wtr_s <= cnt_wtr_s - 1;
            if (cnt_mod   != 0) cnt_mod   <= cnt_mod   - 1;
            if (cnt_zq    != 0) cnt_zq    <= cnt_zq    - 1;

            // Load counters on valid command
            if (dram_cmd_valid) begin
                case (dram_cmd_type)
                    CMD_ACT: begin
                        cnt_rcd[bank_idx] <= trcd_val;
                        cnt_ras[bank_idx] <= tras_val;
                        cnt_rc[bank_idx]  <= trc_val;
                        cnt_rrd_l         <= tRRD_L_DEF[7:0];
                        cnt_rrd_s         <= tRRD_S_DEF[7:0];
                        cnt_faw           <= tFAW_DEF[7:0];
                    end
                    CMD_RD: begin
                        cnt_ccd_l         <= tCCD_L_DEF[7:0];
                        cnt_ccd_s         <= tCCD_S_DEF[7:0];
                        cnt_rtp[bank_idx] <= tRTP_DEF[7:0];
                    end
                    CMD_WR: begin
                        cnt_ccd_l         <= tCCD_L_DEF[7:0];
                        cnt_ccd_s         <= tCCD_S_DEF[7:0];
                        cnt_wr[bank_idx]  <= tWR_DEF[7:0];
                        cnt_wtr_l         <= tWTR_L_DEF[7:0];
                        cnt_wtr_s         <= tWTR_S_DEF[7:0];
                    end
                    CMD_PRE: begin
                        cnt_rp[bank_idx]  <= trp_val;
                    end
                    CMD_REF: begin
                        cnt_rfc           <= trfc_val;
                    end
                    CMD_MRS: begin
                        cnt_mod           <= tMOD_DEF[7:0];
                    end
                    CMD_ZQCL: begin
                        cnt_zq            <= tZQ_DEF[7:0];
                    end
                    default: begin end
                endcase
            end
        end
    end

    // timing_ok[i] = 1 when counter is 0 (constraint met)
    // Report status for the addressed bank
    assign timing_ok[T_RCD]   = (cnt_rcd[bank_idx] == 0);
    assign timing_ok[T_RP]    = (cnt_rp[bank_idx]  == 0);
    assign timing_ok[T_RAS]   = (cnt_ras[bank_idx] == 0);
    assign timing_ok[T_RC]    = (cnt_rc[bank_idx]  == 0);
    assign timing_ok[T_CCD_L] = (cnt_ccd_l == 0);
    assign timing_ok[T_CCD_S] = (cnt_ccd_s == 0);
    assign timing_ok[T_RRD_L] = (cnt_rrd_l == 0);
    assign timing_ok[T_RRD_S] = (cnt_rrd_s == 0);
    assign timing_ok[T_WR]    = (cnt_wr[bank_idx]  == 0);
    assign timing_ok[T_WTR_L] = (cnt_wtr_l == 0);
    assign timing_ok[T_WTR_S] = (cnt_wtr_s == 0);
    assign timing_ok[T_RTP]   = (cnt_rtp[bank_idx] == 0);
    assign timing_ok[T_FAW]   = (cnt_faw   == 0);
    assign timing_ok[T_RFC]   = (cnt_rfc   == 0);
    assign timing_ok[T_MOD]   = (cnt_mod   == 0);
    assign timing_ok[T_ZQ]    = (cnt_zq    == 0);

endmodule
