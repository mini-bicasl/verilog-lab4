// DDR4 Initialization FSM
// Follows JESD79-4 §3.3 power-up sequence (compressed timing for simulation)
module ddr4_init_fsm #(
    parameter RESET_WAIT      = 10,
    parameter ZQCL_WAIT_CYCLES = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg         dram_cmd_valid,
    output reg  [2:0]  dram_cmd_type,
    output reg  [1:0]  dram_rank,
    output reg  [16:0] dram_a,
    output reg  [1:0]  dram_bg,
    output reg  [1:0]  dram_ba,
    output reg  [2:0]  mr_select,

    input  wire [16:0] mr_data,
    output reg         init_done
);

    // State encoding
    localparam [3:0]
        S_IDLE              = 4'd0,
        S_RESET_ASSERT      = 4'd1,
        S_RESET_DEASSERT    = 4'd2,
        S_CKE_ASSERT        = 4'd3,
        S_MRS_MR3           = 4'd4,
        S_MRS_MR6           = 4'd5,
        S_MRS_MR5           = 4'd6,
        S_MRS_MR4           = 4'd7,
        S_MRS_MR2           = 4'd8,
        S_MRS_MR1           = 4'd9,
        S_MRS_MR0           = 4'd10,
        S_ZQCL              = 4'd11,
        S_INIT_DONE         = 4'd12;

    reg [3:0]  state, next_state;
    reg [9:0]  wait_cnt;

    // CMD type constants
    localparam CMD_NOP  = 3'd0;
    localparam CMD_MRS  = 3'd1;
    localparam CMD_ZQCL = 3'd7;

    // State register
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            wait_cnt <= 10'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state    <= S_RESET_ASSERT;
                        wait_cnt <= RESET_WAIT - 1;
                    end
                end

                S_RESET_ASSERT: begin
                    if (wait_cnt == 0)
                        state <= S_RESET_DEASSERT;
                    else
                        wait_cnt <= wait_cnt - 1;
                end

                S_RESET_DEASSERT: begin
                    if (wait_cnt == 0) begin
                        state    <= S_CKE_ASSERT;
                        wait_cnt <= RESET_WAIT - 1;
                    end else begin
                        wait_cnt <= wait_cnt - 1;
                    end
                end

                S_CKE_ASSERT: begin
                    if (wait_cnt == 0)
                        state <= S_MRS_MR3;
                    else
                        wait_cnt <= wait_cnt - 1;
                end

                S_MRS_MR3: state <= S_MRS_MR6;
                S_MRS_MR6: state <= S_MRS_MR5;
                S_MRS_MR5: state <= S_MRS_MR4;
                S_MRS_MR4: state <= S_MRS_MR2;
                S_MRS_MR2: state <= S_MRS_MR1;
                S_MRS_MR1: state <= S_MRS_MR0;
                S_MRS_MR0: begin
                    state    <= S_ZQCL;
                    wait_cnt <= ZQCL_WAIT_CYCLES - 1;
                end

                S_ZQCL: begin
                    if (wait_cnt == 0)
                        state <= S_INIT_DONE;
                    else
                        wait_cnt <= wait_cnt - 1;
                end

                S_INIT_DONE: state <= S_INIT_DONE;

                default: state <= S_IDLE;
            endcase
        end
    end

    // Output logic — derive MR select from state
    function [2:0] state_to_mr;
        input [3:0] s;
        case (s)
            S_MRS_MR0: state_to_mr = 3'd0;
            S_MRS_MR1: state_to_mr = 3'd1;
            S_MRS_MR2: state_to_mr = 3'd2;
            S_MRS_MR3: state_to_mr = 3'd3;
            S_MRS_MR4: state_to_mr = 3'd4;
            S_MRS_MR5: state_to_mr = 3'd5;
            S_MRS_MR6: state_to_mr = 3'd6;
            default:   state_to_mr = 3'd0;
        endcase
    endfunction

    wire mrs_state = (state == S_MRS_MR0 || state == S_MRS_MR1 ||
                      state == S_MRS_MR2 || state == S_MRS_MR3 ||
                      state == S_MRS_MR4 || state == S_MRS_MR5 ||
                      state == S_MRS_MR6);

    always @(*) begin
        dram_cmd_valid = 1'b0;
        dram_cmd_type  = CMD_NOP;
        dram_rank      = 2'd0;
        dram_a         = 17'd0;
        dram_bg        = 2'd0;
        dram_ba        = 2'd0;
        mr_select      = 3'd0;
        init_done      = 1'b0;

        case (state)
            S_MRS_MR0, S_MRS_MR1, S_MRS_MR2,
            S_MRS_MR3, S_MRS_MR4, S_MRS_MR5, S_MRS_MR6: begin
                dram_cmd_valid = 1'b1;
                dram_cmd_type  = CMD_MRS;
                mr_select      = state_to_mr(state);
                dram_bg        = {1'b0, mr_select[2]};
                dram_ba        = mr_select[1:0];
                dram_a         = mr_data;
            end

            S_ZQCL: begin
                // Only assert ZQCL on first cycle
                dram_cmd_valid = (wait_cnt == ZQCL_WAIT_CYCLES - 1);
                dram_cmd_type  = CMD_ZQCL;
            end

            S_INIT_DONE: begin
                init_done = 1'b1;
            end

            default: begin end
        endcase
    end

endmodule
