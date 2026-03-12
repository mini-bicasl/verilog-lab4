// DDR4 Host Interface — AXI4 Slave
// Converts AXI4 read/write transactions to internal command + data requests.
// Supports single-beat and burst (INCR) transfers; each burst beat issues
// one internal command to the scheduler.
//
// Priority: write path takes precedence over read path on the shared cmd bus.
// Both FSMs serialize independently and the arbiter muxes onto cmd_*.
module ddr4_host_iface #(
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4
)(
    input  wire                        clk,
    input  wire                        rst_n,

    // AXI4 Write Address Channel
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]                  s_axi_awlen,
    input  wire [2:0]                  s_axi_awsize,
    input  wire [1:0]                  s_axi_awburst,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,

    // AXI4 Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                        s_axi_wlast,
    input  wire                        s_axi_wvalid,
    output reg                         s_axi_wready,

    // AXI4 Write Response Channel
    output reg  [AXI_ID_WIDTH-1:0]     s_axi_bid,
    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,

    // AXI4 Read Address Channel
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]                  s_axi_arlen,
    input  wire [2:0]                  s_axi_arsize,
    input  wire [1:0]                  s_axi_arburst,
    input  wire                        s_axi_arvalid,
    output reg                         s_axi_arready,

    // AXI4 Read Data Channel
    output reg  [AXI_ID_WIDTH-1:0]     s_axi_rid,
    output reg  [AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rlast,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready,

    // Internal command interface (to scheduler)
    output reg                         cmd_valid,
    input  wire                        cmd_ready,
    output reg  [1:0]                  cmd_type,   // 0=READ, 1=WRITE
    output reg  [AXI_ADDR_WIDTH-1:0]   cmd_addr,
    output reg  [AXI_ID_WIDTH-1:0]     cmd_id,

    // Write data path
    output reg                         wdata_valid,
    input  wire                        wdata_ready,
    output reg  [AXI_DATA_WIDTH-1:0]   wdata,
    output reg  [AXI_DATA_WIDTH/8-1:0] wdata_strb,

    // Read data return (from data path)
    input  wire                        rdata_valid,
    input  wire [AXI_DATA_WIDTH-1:0]   rdata,
    input  wire [AXI_ID_WIDTH-1:0]     rdata_id,
    input  wire                        rdata_err
);

    // AXI4 response codes
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // ---------------------------------------------------------------
    // Write FSM
    // ---------------------------------------------------------------
    localparam [1:0]
        WS_IDLE = 2'd0,
        WS_DATA = 2'd1,
        WS_CMD  = 2'd2,
        WS_RESP = 2'd3;

    reg [1:0]                  wr_state;
    reg [AXI_ID_WIDTH-1:0]     wr_id;
    reg [AXI_ADDR_WIDTH-1:0]   wr_addr;
    reg [7:0]                  wr_len;
    reg [7:0]                  wr_beat;
    reg [AXI_DATA_WIDTH-1:0]   wr_data_latch;
    reg [AXI_DATA_WIDTH/8-1:0] wr_strb_latch;
    reg                        wr_last;

    // Pending write command flag (to arbiter)
    reg                        wr_cmd_pend;
    reg [AXI_ADDR_WIDTH-1:0]   wr_cmd_addr;
    reg [AXI_ID_WIDTH-1:0]     wr_cmd_id;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state      <= WS_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bid     <= {AXI_ID_WIDTH{1'b0}};
            s_axi_bresp   <= RESP_OKAY;
            wdata_valid   <= 1'b0;
            wdata         <= {AXI_DATA_WIDTH{1'b0}};
            wdata_strb    <= {(AXI_DATA_WIDTH/8){1'b0}};
            wr_id         <= {AXI_ID_WIDTH{1'b0}};
            wr_addr       <= {AXI_ADDR_WIDTH{1'b0}};
            wr_len        <= 8'd0;
            wr_beat       <= 8'd0;
            wr_data_latch <= {AXI_DATA_WIDTH{1'b0}};
            wr_strb_latch <= {(AXI_DATA_WIDTH/8){1'b0}};
            wr_last       <= 1'b0;
            wr_cmd_pend   <= 1'b0;
            wr_cmd_addr   <= {AXI_ADDR_WIDTH{1'b0}};
            wr_cmd_id     <= {AXI_ID_WIDTH{1'b0}};
        end else begin
            // Clear wdata_valid when consumed
            if (wdata_valid && wdata_ready)
                wdata_valid <= 1'b0;
            // Clear wr_cmd_pend when arbiter issues it
            if (wr_cmd_pend && cmd_valid && cmd_ready && cmd_type == 2'b01)
                wr_cmd_pend <= 1'b0;

            case (wr_state)
                WS_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id         <= s_axi_awid;
                        wr_addr       <= s_axi_awaddr;
                        wr_len        <= s_axi_awlen;
                        wr_beat       <= 8'd0;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WS_DATA;
                    end
                end

                WS_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Latch data and issue command
                        wr_data_latch <= s_axi_wdata;
                        wr_strb_latch <= s_axi_wstrb;
                        wr_last       <= s_axi_wlast;
                        s_axi_wready  <= 1'b0;
                        // Stage write command for arbiter
                        wr_cmd_pend   <= 1'b1;
                        wr_cmd_addr   <= wr_addr + {{(AXI_ADDR_WIDTH-11){1'b0}}, wr_beat, 3'b000};
                        wr_cmd_id     <= wr_id;
                        wr_beat       <= wr_beat + 8'd1;
                        // Push write data immediately
                        wdata_valid   <= 1'b1;
                        wdata         <= s_axi_wdata;
                        wdata_strb    <= s_axi_wstrb;
                        wr_state      <= WS_CMD;
                    end
                end

                WS_CMD: begin
                    // Wait for arbiter to issue the command
                    if (!wr_cmd_pend) begin
                        if (wr_last) begin
                            wr_state <= WS_RESP;
                        end else begin
                            // More beats to process
                            s_axi_wready <= 1'b1;
                            wr_state     <= WS_DATA;
                        end
                    end
                end

                WS_RESP: begin
                    s_axi_bvalid <= 1'b1;
                    s_axi_bid    <= wr_id;
                    s_axi_bresp  <= RESP_OKAY;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WS_IDLE;
                    end
                end

                default: wr_state <= WS_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Read FSM
    // ---------------------------------------------------------------
    localparam [1:0]
        RS_IDLE   = 2'd0,
        RS_CMD    = 2'd1,
        RS_WAIT   = 2'd2,
        RS_RETURN = 2'd3;

    reg [1:0]                 rd_state;
    reg [AXI_ID_WIDTH-1:0]    rd_id;
    reg [AXI_ADDR_WIDTH-1:0]  rd_addr;
    reg [7:0]                 rd_len;
    reg [7:0]                 rd_beat;       // commands issued so far
    reg [7:0]                 rd_returns;    // data beats returned so far

    // Pending read command flag (to arbiter)
    reg                        rd_cmd_pend;
    reg [AXI_ADDR_WIDTH-1:0]   rd_cmd_addr;
    reg [AXI_ID_WIDTH-1:0]     rd_cmd_id;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state      <= RS_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rid     <= {AXI_ID_WIDTH{1'b0}};
            s_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
            rd_id         <= {AXI_ID_WIDTH{1'b0}};
            rd_addr       <= {AXI_ADDR_WIDTH{1'b0}};
            rd_len        <= 8'd0;
            rd_beat       <= 8'd0;
            rd_returns    <= 8'd0;
            rd_cmd_pend   <= 1'b0;
            rd_cmd_addr   <= {AXI_ADDR_WIDTH{1'b0}};
            rd_cmd_id     <= {AXI_ID_WIDTH{1'b0}};
        end else begin
            // Clear read cmd_pend when arbiter issues it
            if (rd_cmd_pend && cmd_valid && cmd_ready && cmd_type == 2'b00)
                rd_cmd_pend <= 1'b0;

            // Clear rvalid when accepted
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            case (rd_state)
                RS_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        rd_addr       <= s_axi_araddr;
                        rd_len        <= s_axi_arlen;
                        rd_beat       <= 8'd0;
                        rd_returns    <= 8'd0;
                        s_axi_arready <= 1'b0;
                        // Issue first read command
                        rd_cmd_pend   <= 1'b1;
                        rd_cmd_addr   <= s_axi_araddr;
                        rd_cmd_id     <= s_axi_arid;
                        rd_beat       <= 8'd1;
                        rd_state      <= RS_WAIT;
                    end
                end

                RS_WAIT: begin
                    // Issue subsequent burst commands as soon as previous one is taken
                    if (!rd_cmd_pend && rd_beat <= rd_len) begin
                        rd_cmd_pend <= 1'b1;
                        rd_cmd_addr <= rd_addr + {{(AXI_ADDR_WIDTH-11){1'b0}}, rd_beat, 3'b000};
                        rd_cmd_id   <= rd_id;
                        rd_beat     <= rd_beat + 8'd1;
                    end
                    // Return read data to AXI master
                    if (rdata_valid && !s_axi_rvalid) begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rid    <= rdata_id;
                        s_axi_rdata  <= rdata;
                        s_axi_rresp  <= rdata_err ? RESP_SLVERR : RESP_OKAY;
                        if (rd_returns == rd_len) begin
                            s_axi_rlast <= 1'b1;
                            rd_state    <= RS_RETURN;
                        end else begin
                            s_axi_rlast <= 1'b0;
                            rd_returns  <= rd_returns + 8'd1;
                        end
                    end
                end

                RS_RETURN: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rd_state     <= RS_IDLE;
                    end
                end

                default: rd_state <= RS_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Command arbiter (write > read priority)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            cmd_valid <= 1'b0;
            cmd_type  <= 2'b00;
            cmd_addr  <= {AXI_ADDR_WIDTH{1'b0}};
            cmd_id    <= {AXI_ID_WIDTH{1'b0}};
        end else begin
            if (cmd_valid && cmd_ready)
                cmd_valid <= 1'b0;

            if (!cmd_valid) begin
                if (wr_cmd_pend) begin
                    cmd_valid <= 1'b1;
                    cmd_type  <= 2'b01; // WRITE
                    cmd_addr  <= wr_cmd_addr;
                    cmd_id    <= wr_cmd_id;
                end else if (rd_cmd_pend) begin
                    cmd_valid <= 1'b1;
                    cmd_type  <= 2'b00; // READ
                    cmd_addr  <= rd_cmd_addr;
                    cmd_id    <= rd_cmd_id;
                end
            end
        end
    end

endmodule
