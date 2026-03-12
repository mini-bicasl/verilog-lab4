// DDR4 Refresh Controller
// tREFI countdown, FGR modes, per-bank refresh rotation, self-refresh entry/exit
module ddr4_refresh_ctrl #(
    parameter NUM_RANKS = 1
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        init_done,
    input  wire [13:0] cfg_trefi,
    input  wire [1:0]  cfg_fgr_mode,  // 0=normal, 1=FGRx2, 2=FGRx4
    input  wire        cfg_pbr_en,

    output reg         ref_req,
    output reg  [1:0]  ref_rank,
    output reg  [3:0]  ref_bank,

    input  wire        ref_ack,
    input  wire        sr_req,
    output reg         sr_active,
    input  wire        sr_exit_req
);

    reg [13:0] trefi_cnt;
    reg [13:0] trefi_period;

    // Effective tREFI: divide by FGR mode
    always @(*) begin
        case (cfg_fgr_mode)
            2'd1: trefi_period = cfg_trefi >> 1;
            2'd2: trefi_period = cfg_trefi >> 2;
            default: trefi_period = cfg_trefi;
        endcase
    end

    // Self-refresh logic
    always @(posedge clk) begin
        if (!rst_n) begin
            sr_active <= 1'b0;
        end else begin
            if (sr_req && !sr_active)
                sr_active <= 1'b1;
            else if (sr_exit_req && sr_active)
                sr_active <= 1'b0;
        end
    end

    // tREFI countdown and ref_req generation
    always @(posedge clk) begin
        if (!rst_n) begin
            trefi_cnt <= 14'd0;
            ref_req   <= 1'b0;
            ref_rank  <= 2'd0;
            ref_bank  <= 4'd0;
        end else if (!init_done || sr_active) begin
            trefi_cnt <= trefi_period;
            ref_req   <= 1'b0;
        end else begin
            if (ref_req) begin
                // Hold until acked
                if (ref_ack) begin
                    ref_req   <= 1'b0;
                    trefi_cnt <= trefi_period;
                    // Rotate bank for PBR
                    if (cfg_pbr_en)
                        ref_bank <= ref_bank + 1;
                    else
                        ref_bank <= 4'd0;
                end
            end else begin
                if (trefi_cnt == 0 || trefi_cnt == 14'd1) begin
                    ref_req   <= 1'b1;
                    trefi_cnt <= trefi_period;
                end else begin
                    trefi_cnt <= trefi_cnt - 1;
                end
            end
        end
    end

endmodule
