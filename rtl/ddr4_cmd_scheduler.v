// DDR4 Command Scheduler
// Single-bank open/closed-page FSM with command queue and refresh arbitration
module ddr4_cmd_scheduler (
    input  wire        clk,
    input  wire        rst_n,

    // Host command interface
    input  wire        cmd_valid,
    output reg         cmd_ready,
    input  wire [1:0]  cmd_type,   // 0=READ, 1=WRITE
    input  wire [31:0] cmd_addr,
    input  wire [3:0]  cmd_id,

    // Refresh interface
    input  wire        ref_req,
    input  wire [1:0]  ref_rank,
    input  wire [3:0]  ref_bank,
    output reg         ref_ack,

    // Timing gate
    input  wire [15:0] timing_ok,

    // DRAM command output
    output reg         dram_cmd_valid,
    output reg  [2:0]  dram_cmd_type,
    output reg  [1:0]  dram_rank,
    output reg  [1:0]  dram_bg,
    output reg  [1:0]  dram_ba,
    output reg  [16:0] dram_row,
    output reg  [9:0]  dram_col,

    // Data request signals
    output reg         rd_data_req,
    output reg  [3:0]  rd_data_id,
    output reg         wr_data_req,
    output reg  [3:0]  wr_data_id
);

    // Command type encoding
    localparam CMD_NOP  = 3'd0;
    localparam CMD_MRS  = 3'd1;
    localparam CMD_REF  = 3'd2;
    localparam CMD_PRE  = 3'd3;
    localparam CMD_ACT  = 3'd4;
    localparam CMD_WR   = 3'd5;
    localparam CMD_RD   = 3'd6;

    // Bank FSM states
    localparam [2:0]
        BS_IDLE        = 3'd0,
        BS_ACTIVATING  = 3'd1,
        BS_ACTIVE      = 3'd2,
        BS_READING     = 3'd3,
        BS_WRITING     = 3'd4,
        BS_PRECHARGING = 3'd5,
        BS_REFRESH     = 3'd6;

    // Address decode
    wire [1:0]  dec_rank = cmd_addr[27:26];
    wire [16:0] dec_row  = cmd_addr[25:9];
    wire [1:0]  dec_ba   = cmd_addr[8:7];
    wire [1:0]  dec_bg   = cmd_addr[6:5];
    wire [9:0]  dec_col  = {cmd_addr[4:3], cmd_addr[12:5]};

    // Timing check aliases
    wire t_rcd_ok  = timing_ok[0];
    wire t_rp_ok   = timing_ok[1];
    wire t_ras_ok  = timing_ok[2];
    wire t_faw_ok  = timing_ok[12];
    wire t_rrd_s_ok= timing_ok[7];
    wire t_rtp_ok  = timing_ok[11];
    wire t_wr_ok   = timing_ok[8];

    // Bank state machine (single bank per scheduler instance)
    reg  [2:0]  bank_state;
    reg  [16:0] open_row;
    reg  [1:0]  open_rank;
    reg  [1:0]  open_bg;
    reg  [1:0]  open_ba;

    // Stored command
    reg         pend_valid;
    reg  [1:0]  pend_type;
    reg  [31:0] pend_addr;
    reg  [3:0]  pend_id;

    // Decoded pending command address
    wire [1:0]  pend_rank = pend_addr[27:26];
    wire [16:0] pend_row  = pend_addr[25:9];
    wire [1:0]  pend_ba   = pend_addr[8:7];
    wire [1:0]  pend_bg   = pend_addr[6:5];
    wire [9:0]  pend_col  = {pend_addr[4:3], pend_addr[12:5]};

    always @(posedge clk) begin
        if (!rst_n) begin
            bank_state    <= BS_IDLE;
            open_row      <= 17'd0;
            open_rank     <= 2'd0;
            open_bg       <= 2'd0;
            open_ba       <= 2'd0;
            pend_valid    <= 1'b0;
            pend_type     <= 2'd0;
            pend_addr     <= 32'd0;
            pend_id       <= 4'd0;
            cmd_ready     <= 1'b1;
            dram_cmd_valid<= 1'b0;
            dram_cmd_type <= CMD_NOP;
            dram_rank     <= 2'd0;
            dram_bg       <= 2'd0;
            dram_ba       <= 2'd0;
            dram_row      <= 17'd0;
            dram_col      <= 10'd0;
            rd_data_req   <= 1'b0;
            rd_data_id    <= 4'd0;
            wr_data_req   <= 1'b0;
            wr_data_id    <= 4'd0;
            ref_ack       <= 1'b0;
        end else begin
            // Default pulse signals off
            dram_cmd_valid <= 1'b0;
            rd_data_req    <= 1'b0;
            wr_data_req    <= 1'b0;
            ref_ack        <= 1'b0;

            // Capture incoming command when ready
            if (cmd_valid && cmd_ready && !pend_valid) begin
                pend_valid <= 1'b1;
                pend_type  <= cmd_type;
                pend_addr  <= cmd_addr;
                pend_id    <= cmd_id;
                cmd_ready  <= 1'b0;
            end

            case (bank_state)
                BS_IDLE: begin
                    // Priority: refresh > pending command
                    if (ref_req && t_rp_ok) begin
                        bank_state     <= BS_REFRESH;
                        dram_cmd_valid <= 1'b1;
                        dram_cmd_type  <= CMD_REF;
                        dram_rank      <= ref_rank;
                        dram_bg        <= 2'd0;
                        dram_ba        <= 2'd0;
                        ref_ack        <= 1'b1;
                    end else if (pend_valid && t_rp_ok && t_rrd_s_ok && t_faw_ok) begin
                        bank_state     <= BS_ACTIVATING;
                        dram_cmd_valid <= 1'b1;
                        dram_cmd_type  <= CMD_ACT;
                        dram_rank      <= pend_rank;
                        dram_bg        <= pend_bg;
                        dram_ba        <= pend_ba;
                        dram_row       <= pend_row;
                        open_row       <= pend_row;
                        open_rank      <= pend_rank;
                        open_bg        <= pend_bg;
                        open_ba        <= pend_ba;
                    end
                end

                BS_ACTIVATING: begin
                    // Wait for tRCD
                    if (t_rcd_ok)
                        bank_state <= BS_ACTIVE;
                end

                BS_ACTIVE: begin
                    if (pend_valid && t_rcd_ok) begin
                        if (pend_type == 2'd1) begin
                            // WRITE
                            bank_state     <= BS_WRITING;
                            dram_cmd_valid <= 1'b1;
                            dram_cmd_type  <= CMD_WR;
                            dram_rank      <= pend_rank;
                            dram_bg        <= pend_bg;
                            dram_ba        <= pend_ba;
                            dram_col       <= pend_col;
                            wr_data_req    <= 1'b1;
                            wr_data_id     <= pend_id;
                            pend_valid     <= 1'b0;
                            cmd_ready      <= 1'b1;
                        end else begin
                            // READ
                            bank_state     <= BS_READING;
                            dram_cmd_valid <= 1'b1;
                            dram_cmd_type  <= CMD_RD;
                            dram_rank      <= pend_rank;
                            dram_bg        <= pend_bg;
                            dram_ba        <= pend_ba;
                            dram_col       <= pend_col;
                            rd_data_req    <= 1'b1;
                            rd_data_id     <= pend_id;
                            pend_valid     <= 1'b0;
                            cmd_ready      <= 1'b1;
                        end
                    end
                end

                BS_READING: begin
                    if (t_rtp_ok) begin
                        bank_state     <= BS_PRECHARGING;
                        dram_cmd_valid <= 1'b1;
                        dram_cmd_type  <= CMD_PRE;
                        dram_rank      <= open_rank;
                        dram_bg        <= open_bg;
                        dram_ba        <= open_ba;
                    end
                end

                BS_WRITING: begin
                    if (t_wr_ok && t_ras_ok) begin
                        bank_state     <= BS_PRECHARGING;
                        dram_cmd_valid <= 1'b1;
                        dram_cmd_type  <= CMD_PRE;
                        dram_rank      <= open_rank;
                        dram_bg        <= open_bg;
                        dram_ba        <= open_ba;
                    end
                end

                BS_PRECHARGING: begin
                    if (t_rp_ok)
                        bank_state <= BS_IDLE;
                end

                BS_REFRESH: begin
                    // tRFC handled by timing engine; return to IDLE when tRFC ok
                    if (timing_ok[13])
                        bank_state <= BS_IDLE;
                end

                default: bank_state <= BS_IDLE;
            endcase
        end
    end

endmodule
