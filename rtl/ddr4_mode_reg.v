// DDR4 Mode Register Shadow and MRS Payload Encoder
// Encodes cfg_* inputs into JEDEC DDR4 MR0-MR6 payload
module ddr4_mode_reg (
    input  wire        clk,
    input  wire        rst_n,

    // Configuration inputs
    input  wire [4:0]  cfg_cl,
    input  wire [4:0]  cfg_cwl,
    input  wire [1:0]  cfg_al,
    input  wire [2:0]  cfg_rtt_nom,
    input  wire [2:0]  cfg_rtt_wr,
    input  wire [2:0]  cfg_rtt_park,
    input  wire [1:0]  cfg_drive_strength,
    input  wire [3:0]  cfg_wr_recovery,
    input  wire        cfg_dbi_rd_en,
    input  wire        cfg_dbi_wr_en,
    input  wire        cfg_ca_parity_en,

    // MR access
    input  wire [2:0]  mr_select,
    output reg  [16:0] mr_data
);

    wire [16:0] mr0, mr1, mr2, mr3, mr4, mr5, mr6;

    // MR0: BL=BL8, CL, WR recovery (17 bits)
    // bit0=burst_type(0), bits[2:1]=BL(2'b00=BL8), bit3=0
    // bits[6:4]=CL[2:0], bit7=0, bit8=0
    // bits[11:9]=WR[2:0], bit12=CL[3], bit13=WR[3], bits[16:14]=0
    assign mr0 = {3'b000, cfg_wr_recovery[3], cfg_cl[3],
                  cfg_wr_recovery[2:0],
                  2'b00, cfg_cl[2:0],
                  1'b0, 2'b00, 1'b0};

    // MR1: drive_strength[1:0], AL[1:0], RTT_NOM[2:0]
    // bits[1:0]=drive, bits[4:3]=AL, bits[10:8]=RTT_NOM
    assign mr1 = {6'b000000, cfg_rtt_nom, 3'b000, cfg_al, 1'b0, cfg_drive_strength};

    // MR2: CWL encoding, RTT_WR
    // bits[5:3]=CWL-9 clamped, bits[11:9]=RTT_WR
    wire [2:0] cwl_enc = (cfg_cwl >= 5'd9) ? (cfg_cwl - 5'd9) : 3'd0;
    assign mr2 = {5'b00000, cfg_rtt_wr, 3'b000, cwl_enc, 3'b000};

    // MR3,MR4,MR6: reserved, return 0
    assign mr3 = 17'h0;
    assign mr4 = 17'h0;
    assign mr6 = 17'h0;

    // MR5: RTT_PARK, DBI, CA parity (17 bits)
    // bit0=CA_PARITY, bits[8:6]=RTT_PARK, bit11=DBI_WR, bit12=DBI_RD
    assign mr5 = {4'b0000, cfg_dbi_rd_en, cfg_dbi_wr_en, 2'b00,
                  cfg_rtt_park, 5'b00000, cfg_ca_parity_en};

    always @(*) begin
        case (mr_select)
            3'd0: mr_data = mr0;
            3'd1: mr_data = mr1;
            3'd2: mr_data = mr2;
            3'd3: mr_data = mr3;
            3'd4: mr_data = mr4;
            3'd5: mr_data = mr5;
            3'd6: mr_data = mr6;
            default: mr_data = 17'h0;
        endcase
    end

endmodule
