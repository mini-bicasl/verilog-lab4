// DDR4 Controller Top-Level Wrapper
// Ties ddr4_host_iface, ddr4_cmd_scheduler, ddr4_timing_engine,
// ddr4_refresh_ctrl, ddr4_init_fsm, ddr4_mode_reg, ddr4_data_path,
// ddr4_ecc_engine (via data_path), and ddr4_phy_iface together.
//
// Internal cmd_type encoding (matches sub-modules):
//   0=NOP, 1=MRS, 2=REF, 3=PRE, 4=ACT, 5=WR, 6=RD, 7=ZQ
//
// cfg_timing_base: 0 = sub-modules use hard-coded defaults,
//                  1 = use cfg_* input ports to override timing.
module ddr4_ctrl_top #(
    parameter NUM_RANKS      = 1,
    parameter ROW_BITS       = 17,
    parameter COL_BITS       = 10,
    parameter DQ_WIDTH       = 72,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    // Reduced wait parameters for simulation
    parameter INIT_RESET_WAIT = 10,
    parameter INIT_ZQCL_WAIT  = 10
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4 Write Address Channel
    input  wire [AXI_ID_WIDTH-1:0]    s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]                 s_axi_awlen,
    input  wire [2:0]                 s_axi_awsize,
    input  wire [1:0]                 s_axi_awburst,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,

    // AXI4 Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                       s_axi_wlast,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,

    // AXI4 Write Response Channel
    output wire [AXI_ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready,

    // AXI4 Read Address Channel
    input  wire [AXI_ID_WIDTH-1:0]    s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]                 s_axi_arlen,
    input  wire [2:0]                 s_axi_arsize,
    input  wire [1:0]                 s_axi_arburst,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,

    // AXI4 Read Data Channel
    output wire [AXI_ID_WIDTH-1:0]    s_axi_rid,
    output wire [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rlast,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    // DRAM Physical Interface
    output wire [NUM_RANKS-1:0]       ddr4_ck_t,
    output wire [NUM_RANKS-1:0]       ddr4_ck_c,
    output wire [NUM_RANKS-1:0]       ddr4_cke,
    output wire [NUM_RANKS-1:0]       ddr4_cs_n,
    output wire                       ddr4_act_n,
    output wire                       ddr4_ras_n,
    output wire                       ddr4_cas_n,
    output wire                       ddr4_we_n,
    output wire [1:0]                 ddr4_bg,
    output wire [1:0]                 ddr4_ba,
    output wire [16:0]                ddr4_a,
    output wire [NUM_RANKS-1:0]       ddr4_odt,
    output wire                       ddr4_reset_n,
    output wire [DQ_WIDTH-1:0]        ddr4_dq_out,
    input  wire [DQ_WIDTH-1:0]        ddr4_dq_in,
    output wire [8:0]                 ddr4_dqs_t,
    output wire [8:0]                 ddr4_dqs_c,
    output wire [8:0]                 ddr4_dm_dbi_n,

    // Status outputs
    output wire                       init_done,
    output reg                        ecc_single_err,
    output reg                        ecc_double_err,
    output reg  [AXI_ADDR_WIDTH-1:0]  ecc_err_addr,
    output reg  [7:0]                 ecc_err_syndrome,
    output wire                       ref_in_progress,

    // Configuration
    input  wire                       cfg_timing_base,
    input  wire [4:0]                 cfg_cl,
    input  wire [4:0]                 cfg_cwl,
    input  wire [7:0]                 cfg_trcd,
    input  wire [7:0]                 cfg_trp,
    input  wire [7:0]                 cfg_tras,
    input  wire [7:0]                 cfg_trc,
    input  wire [9:0]                 cfg_trfc,
    input  wire [13:0]                cfg_trefi,
    input  wire [1:0]                 cfg_fgr_mode,
    input  wire                       cfg_pbr_en,
    input  wire                       cfg_ecc_clr,    // clears sticky ECC flags

    // Self-refresh control
    input  wire                       sr_req,
    output wire                       sr_active,
    input  wire                       sr_exit_req
);

    // ---------------------------------------------------------------
    // Timing parameter mux (0 → use module defaults, 1 → use cfg)
    // ---------------------------------------------------------------
    wire [4:0]  mux_cl    = cfg_timing_base ? cfg_cl    : 5'd0;
    wire [4:0]  mux_cwl   = cfg_timing_base ? cfg_cwl   : 5'd0;
    wire [7:0]  mux_trcd  = cfg_timing_base ? cfg_trcd  : 8'd0;
    wire [7:0]  mux_trp   = cfg_timing_base ? cfg_trp   : 8'd0;
    wire [7:0]  mux_tras  = cfg_timing_base ? cfg_tras  : 8'd0;
    wire [7:0]  mux_trc   = cfg_timing_base ? cfg_trc   : 8'd0;
    wire [9:0]  mux_trfc  = cfg_timing_base ? cfg_trfc  : 10'd0;
    wire [13:0] mux_trefi = cfg_timing_base ? cfg_trefi : 14'd0;

    // ---------------------------------------------------------------
    // Internal wires — Host Interface ↔ Scheduler
    // ---------------------------------------------------------------
    wire                       hi_cmd_valid;
    wire                       hi_cmd_ready;
    wire [1:0]                 hi_cmd_type;
    wire [AXI_ADDR_WIDTH-1:0]  hi_cmd_addr;
    wire [AXI_ID_WIDTH-1:0]    hi_cmd_id;

    wire                       hi_wdata_valid;
    wire                       hi_wdata_ready;
    wire [AXI_DATA_WIDTH-1:0]  hi_wdata;
    wire [AXI_DATA_WIDTH/8-1:0] hi_wdata_strb;

    wire                       hi_rdata_valid;
    wire [AXI_DATA_WIDTH-1:0]  hi_rdata;
    wire [AXI_ID_WIDTH-1:0]    hi_rdata_id;
    wire                       hi_rdata_err;

    // ---------------------------------------------------------------
    // Internal wires — Scheduler DRAM command outputs
    // ---------------------------------------------------------------
    wire        sched_dram_cmd_valid;
    wire [2:0]  sched_dram_cmd_type;
    wire [1:0]  sched_dram_rank;
    wire [1:0]  sched_dram_bg;
    wire [1:0]  sched_dram_ba;
    wire [16:0] sched_dram_row;
    wire [9:0]  sched_dram_col;

    wire        sched_rd_data_req;
    wire [3:0]  sched_rd_data_id;
    wire        sched_wr_data_req;
    wire [3:0]  sched_wr_data_id;

    // ---------------------------------------------------------------
    // Internal wires — Refresh controller
    // ---------------------------------------------------------------
    wire        ref_req;
    wire [1:0]  ref_rank;
    wire [3:0]  ref_bank;
    wire        ref_ack;

    // ---------------------------------------------------------------
    // Internal wires — Timing engine
    // ---------------------------------------------------------------
    wire [15:0] timing_ok;

    // ---------------------------------------------------------------
    // Internal wires — Init FSM and mode reg
    // ---------------------------------------------------------------
    wire        init_dram_cmd_valid;
    wire [2:0]  init_dram_cmd_type;
    wire [1:0]  init_dram_rank;
    wire [16:0] init_dram_a;
    wire [1:0]  init_dram_bg;
    wire [1:0]  init_dram_ba;
    wire [2:0]  init_mr_select;
    wire [16:0] init_mr_data;

    // ---------------------------------------------------------------
    // Internal wires — Data path ↔ PHY
    // ---------------------------------------------------------------
    wire [71:0] dp_phy_dq_out;
    wire [8:0]  dp_phy_dqs_oe;
    wire [8:0]  dp_phy_dq_oe;
    wire [71:0] phy_dq_in_int;
    wire        phy_dqs_valid_int;

    // ---------------------------------------------------------------
    // Command mux: init_fsm takes priority until init_done
    // ---------------------------------------------------------------
    wire        mux_cmd_valid;
    wire [2:0]  mux_cmd_type;
    wire [1:0]  mux_rank;
    wire [1:0]  mux_bg;
    wire [1:0]  mux_ba;
    wire [16:0] mux_row;
    wire [9:0]  mux_col;
    wire [16:0] mux_a_addr;

    assign mux_cmd_valid = init_done ? sched_dram_cmd_valid : init_dram_cmd_valid;
    assign mux_cmd_type  = init_done ? sched_dram_cmd_type  : init_dram_cmd_type;
    assign mux_rank      = init_done ? sched_dram_rank      : init_dram_rank;
    assign mux_bg        = init_done ? sched_dram_bg        : init_dram_bg;
    assign mux_ba        = init_done ? sched_dram_ba        : init_dram_ba;
    assign mux_row       = init_done ? sched_dram_row       : 17'd0;
    assign mux_col       = init_done ? sched_dram_col       : 10'd0;
    // Address bus: init uses MR data; scheduler uses row for ACT, col for RD/WR
    assign mux_a_addr    = init_done ?
                           ((sched_dram_cmd_type == 3'd4) ? sched_dram_row :
                            {7'd0, sched_dram_col}) :
                           init_dram_a;

    // ---------------------------------------------------------------
    // DDR4 pin decode from internal cmd_type
    // cmd_type: 0=NOP,1=MRS,2=REF,3=PRE,4=ACT,5=WR,6=RD,7=ZQ
    // ---------------------------------------------------------------
    wire cmd_is_nop = (mux_cmd_type == 3'd0) || !mux_cmd_valid;
    wire cmd_is_mrs = (mux_cmd_type == 3'd1);
    wire cmd_is_ref = (mux_cmd_type == 3'd2);
    wire cmd_is_pre = (mux_cmd_type == 3'd3);
    wire cmd_is_act = (mux_cmd_type == 3'd4);
    wire cmd_is_wr  = (mux_cmd_type == 3'd5);
    wire cmd_is_rd  = (mux_cmd_type == 3'd6);
    wire cmd_is_zq  = (mux_cmd_type == 3'd7);

    // CKE (deassert during init reset phase, assert afterwards)
    // Simple model: tie CKE high once init_done or during CKE_ASSERT state.
    // For this abstract model, keep CKE=1 after reset.
    wire [NUM_RANKS-1:0] ctrl_cke_sig = {NUM_RANKS{1'b1}};
    wire [NUM_RANKS-1:0] ctrl_odt_sig = {NUM_RANKS{1'b0}};
    wire                 ctrl_reset_n_sig = 1'b1;  // deasserted after reset

    // CS_N: assert (drive low) the targeted rank; others deselected
    wire [NUM_RANKS-1:0] ctrl_cs_n_sig;
    generate
        if (NUM_RANKS == 1)
            assign ctrl_cs_n_sig = cmd_is_nop ? 1'b1 : 1'b0;
        else
            assign ctrl_cs_n_sig = cmd_is_nop ?
                                   {NUM_RANKS{1'b1}} :
                                   ~({{(NUM_RANKS-1){1'b0}}, 1'b1} << mux_rank);
    endgenerate

    // DDR4 command pins
    wire ctrl_act_n_sig = !(cmd_is_act);
    wire ctrl_ras_n_sig = !(cmd_is_pre | cmd_is_ref | cmd_is_mrs);
    wire ctrl_cas_n_sig = !(cmd_is_ref | cmd_is_mrs | cmd_is_rd | cmd_is_wr);
    wire ctrl_we_n_sig  = !(cmd_is_pre | cmd_is_mrs | cmd_is_wr | cmd_is_zq);

    // ---------------------------------------------------------------
    // ECC sticky error registers
    // ---------------------------------------------------------------
    // We tap ECC signals from data path output
    // (dec_single_err / dec_double_err from ecc_engine via data path)
    // In data_path, rd_ecc_err combines both; for separate tracking we'd
    // need a modified data_path. Here we use the single output for both.
    always @(posedge clk) begin
        if (!rst_n || cfg_ecc_clr) begin
            ecc_single_err  <= 1'b0;
            ecc_double_err  <= 1'b0;
            ecc_err_addr    <= {AXI_ADDR_WIDTH{1'b0}};
            ecc_err_syndrome <= 8'b0;
        end else if (hi_rdata_err) begin
            ecc_single_err  <= 1'b1;
            ecc_err_addr    <= hi_cmd_addr;
        end
    end

    // ref_in_progress status
    assign ref_in_progress = ref_req;

    // ---------------------------------------------------------------
    // Module instantiations
    // ---------------------------------------------------------------

    ddr4_host_iface #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH)
    ) u_host_iface (
        .clk            (clk),
        .rst_n          (rst_n),
        // AXI4 write address
        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        // AXI4 write data
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        // AXI4 write response
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        // AXI4 read address
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        // AXI4 read data
        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        // Internal command
        .cmd_valid      (hi_cmd_valid),
        .cmd_ready      (hi_cmd_ready),
        .cmd_type       (hi_cmd_type),
        .cmd_addr       (hi_cmd_addr),
        .cmd_id         (hi_cmd_id),
        // Write data
        .wdata_valid    (hi_wdata_valid),
        .wdata_ready    (hi_wdata_ready),
        .wdata          (hi_wdata),
        .wdata_strb     (hi_wdata_strb),
        // Read data return
        .rdata_valid    (hi_rdata_valid),
        .rdata          (hi_rdata),
        .rdata_id       (hi_rdata_id),
        .rdata_err      (hi_rdata_err)
    );

    ddr4_cmd_scheduler u_scheduler (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (hi_cmd_valid),
        .cmd_ready      (hi_cmd_ready),
        .cmd_type       (hi_cmd_type),
        .cmd_addr       (hi_cmd_addr),
        .cmd_id         (hi_cmd_id),
        .ref_req        (ref_req),
        .ref_rank       (ref_rank),
        .ref_bank       (ref_bank),
        .ref_ack        (ref_ack),
        .timing_ok      (timing_ok),
        .dram_cmd_valid (sched_dram_cmd_valid),
        .dram_cmd_type  (sched_dram_cmd_type),
        .dram_rank      (sched_dram_rank),
        .dram_bg        (sched_dram_bg),
        .dram_ba        (sched_dram_ba),
        .dram_row       (sched_dram_row),
        .dram_col       (sched_dram_col),
        .rd_data_req    (sched_rd_data_req),
        .rd_data_id     (sched_rd_data_id),
        .wr_data_req    (sched_wr_data_req),
        .wr_data_id     (sched_wr_data_id)
    );

    ddr4_timing_engine u_timing (
        .clk            (clk),
        .rst_n          (rst_n),
        .dram_cmd_valid (mux_cmd_valid),
        .dram_cmd_type  (mux_cmd_type),
        .dram_rank      (mux_rank),
        .dram_bg        (mux_bg),
        .dram_ba        (mux_ba),
        .cfg_cl         (mux_cl),
        .cfg_cwl        (mux_cwl),
        .cfg_trcd       (mux_trcd),
        .cfg_trp        (mux_trp),
        .cfg_tras       (mux_tras),
        .cfg_trc        (mux_trc),
        .cfg_trfc       (mux_trfc),
        .cfg_trefi      (mux_trefi),
        .timing_ok      (timing_ok)
    );

    ddr4_refresh_ctrl #(
        .NUM_RANKS(NUM_RANKS)
    ) u_refresh (
        .clk            (clk),
        .rst_n          (rst_n),
        .init_done      (init_done),
        .cfg_trefi      (mux_trefi),
        .cfg_fgr_mode   (cfg_fgr_mode),
        .cfg_pbr_en     (cfg_pbr_en),
        .ref_req        (ref_req),
        .ref_rank       (ref_rank),
        .ref_bank       (ref_bank),
        .ref_ack        (ref_ack),
        .sr_req         (sr_req),
        .sr_active      (sr_active),
        .sr_exit_req    (sr_exit_req)
    );

    ddr4_init_fsm #(
        .RESET_WAIT      (INIT_RESET_WAIT),
        .ZQCL_WAIT_CYCLES(INIT_ZQCL_WAIT)
    ) u_init_fsm (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (1'b1),
        .dram_cmd_valid (init_dram_cmd_valid),
        .dram_cmd_type  (init_dram_cmd_type),
        .dram_rank      (init_dram_rank),
        .dram_a         (init_dram_a),
        .dram_bg        (init_dram_bg),
        .dram_ba        (init_dram_ba),
        .mr_select      (init_mr_select),
        .mr_data        (init_mr_data),
        .init_done      (init_done)
    );

    ddr4_mode_reg u_mode_reg (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_cl             (mux_cl),
        .cfg_cwl            (mux_cwl),
        .cfg_al             (2'd0),
        .cfg_rtt_nom        (3'd0),
        .cfg_rtt_wr         (3'd0),
        .cfg_rtt_park       (3'd0),
        .cfg_drive_strength (2'd0),
        .cfg_wr_recovery    (4'd0),
        .cfg_dbi_rd_en      (1'b0),
        .cfg_dbi_wr_en      (1'b0),
        .cfg_ca_parity_en   (1'b0),
        .mr_select          (init_mr_select),
        .mr_data            (init_mr_data)
    );

    ddr4_data_path u_data_path (
        .clk                (clk),
        .rst_n              (rst_n),
        // Write from host
        .wr_req             (hi_wdata_valid),
        .wr_id              (hi_cmd_id),
        .wr_data            (hi_wdata),
        .wr_strb            (hi_wdata_strb),
        .wr_ready           (hi_wdata_ready),
        // Read from PHY
        .rd_data_return     (phy_dq_in_int),
        .rd_data_valid_phy  (phy_dqs_valid_int),
        .rd_id_phy          (sched_rd_data_id),
        // Read to host
        .rd_data_out        (hi_rdata),
        .rd_data_valid_host (hi_rdata_valid),
        .rd_data_id_host    (hi_rdata_id),
        .rd_ecc_err         (hi_rdata_err),
        // PHY output
        .phy_dq_out         (dp_phy_dq_out),
        .phy_dqs_oe         (dp_phy_dqs_oe),
        .phy_dq_oe          (dp_phy_dq_oe)
    );

    ddr4_phy_iface #(
        .NUM_RANKS(NUM_RANKS),
        .DQ_WIDTH (DQ_WIDTH),
        .DQS_WIDTH(9)
    ) u_phy (
        .clk            (clk),
        .rst_n          (rst_n),
        // Command bus
        .ctrl_cmd_valid (mux_cmd_valid),
        .ctrl_act_n     (ctrl_act_n_sig),
        .ctrl_ras_n     (ctrl_ras_n_sig),
        .ctrl_cas_n     (ctrl_cas_n_sig),
        .ctrl_we_n      (ctrl_we_n_sig),
        .ctrl_bg        (mux_bg),
        .ctrl_ba        (mux_ba),
        .ctrl_a         (mux_a_addr),
        .ctrl_cs_n      (ctrl_cs_n_sig),
        .ctrl_cke       (ctrl_cke_sig),
        .ctrl_odt       (ctrl_odt_sig),
        .ctrl_reset_n   (ctrl_reset_n_sig),
        // Data bus
        .ctrl_dq_out    (dp_phy_dq_out),
        .ctrl_dq_oe     (dp_phy_dq_oe),
        .ctrl_dqs_oe    (dp_phy_dqs_oe),
        // PHY captured data
        .phy_dq_in      (phy_dq_in_int),
        .phy_dqs_valid  (phy_dqs_valid_int),
        // DRAM pads
        .ddr4_ck_t      (ddr4_ck_t),
        .ddr4_ck_c      (ddr4_ck_c),
        .ddr4_cke       (ddr4_cke),
        .ddr4_cs_n      (ddr4_cs_n),
        .ddr4_act_n     (ddr4_act_n),
        .ddr4_ras_n     (ddr4_ras_n),
        .ddr4_cas_n     (ddr4_cas_n),
        .ddr4_we_n      (ddr4_we_n),
        .ddr4_bg        (ddr4_bg),
        .ddr4_ba        (ddr4_ba),
        .ddr4_a         (ddr4_a),
        .ddr4_odt       (ddr4_odt),
        .ddr4_reset_n   (ddr4_reset_n),
        .ddr4_dq_out    (ddr4_dq_out),
        .ddr4_dq_in     (ddr4_dq_in),
        .ddr4_dqs_t     (ddr4_dqs_t),
        .ddr4_dqs_c     (ddr4_dqs_c),
        .ddr4_dm_dbi_n  (ddr4_dm_dbi_n)
    );

endmodule
