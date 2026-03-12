// DDR4 ECC Engine — SECDED (72,64) encoder and decoder
// Check bits at codeword positions: 0 (overall parity P0), 1 (P1), 2 (P2),
// 4 (P4), 8 (P8), 16 (P16), 32 (P32), 64 (P64).
// Data bits fill the remaining 64 positions: 3,5,6,7,9..15,17..31,33..63,65..71.
//
// Syndrome encoding (dec_syndrome[7:0]):
//   [7:1] = {S64,S32,S16,S8,S4,S2,S1}  — Hamming syndrome (= error position for SBE)
//   [0]   = overall parity check P0
//   No error : syndrome == 8'h00
//   SBE      : syndrome[7:1] != 0 && syndrome[0] == 1
//   DBE      : syndrome[7:1] != 0 && syndrome[0] == 0
module ddr4_ecc_engine (
    input  wire        clk,
    input  wire        rst_n,

    // Encoder (write path) — combinatorial
    input  wire [63:0] enc_data_in,
    output wire [71:0] enc_data_out,

    // Decoder (read path) — combinatorial
    input  wire [71:0] dec_data_in,
    output wire [63:0] dec_data_out,
    output wire        dec_single_err,
    output wire        dec_double_err,
    output wire [7:0]  dec_syndrome,
    output wire [6:0]  dec_err_bit
);

    // ----------------------------------------------------------------
    // ENCODER
    // ----------------------------------------------------------------
    // Build partial codeword: data bits placed at data positions,
    // check-bit positions start at 0.
    // Data bit d[i] → codeword position dp[i]:
    //   i=0..3   → pos 3,5,6,7
    //   i=4..10  → pos 9..15
    //   i=11..25 → pos 17..31
    //   i=26..56 → pos 33..63
    //   i=57..63 → pos 65..71

    // Partial codeword (check bits will be inserted)
    wire [71:0] enc_partial;
    assign enc_partial[2:0]   = 3'b0;          // positions 0,1,2 = check bits
    assign enc_partial[3]     = enc_data_in[0];
    assign enc_partial[4]     = 1'b0;           // position 4 = check bit
    assign enc_partial[5]     = enc_data_in[1];
    assign enc_partial[6]     = enc_data_in[2];
    assign enc_partial[7]     = enc_data_in[3];
    assign enc_partial[8]     = 1'b0;           // position 8 = check bit
    assign enc_partial[9]     = enc_data_in[4];
    assign enc_partial[10]    = enc_data_in[5];
    assign enc_partial[11]    = enc_data_in[6];
    assign enc_partial[12]    = enc_data_in[7];
    assign enc_partial[13]    = enc_data_in[8];
    assign enc_partial[14]    = enc_data_in[9];
    assign enc_partial[15]    = enc_data_in[10];
    assign enc_partial[16]    = 1'b0;           // position 16 = check bit
    assign enc_partial[17]    = enc_data_in[11];
    assign enc_partial[18]    = enc_data_in[12];
    assign enc_partial[19]    = enc_data_in[13];
    assign enc_partial[20]    = enc_data_in[14];
    assign enc_partial[21]    = enc_data_in[15];
    assign enc_partial[22]    = enc_data_in[16];
    assign enc_partial[23]    = enc_data_in[17];
    assign enc_partial[24]    = enc_data_in[18];
    assign enc_partial[25]    = enc_data_in[19];
    assign enc_partial[26]    = enc_data_in[20];
    assign enc_partial[27]    = enc_data_in[21];
    assign enc_partial[28]    = enc_data_in[22];
    assign enc_partial[29]    = enc_data_in[23];
    assign enc_partial[30]    = enc_data_in[24];
    assign enc_partial[31]    = enc_data_in[25];
    assign enc_partial[32]    = 1'b0;           // position 32 = check bit
    assign enc_partial[33]    = enc_data_in[26];
    assign enc_partial[34]    = enc_data_in[27];
    assign enc_partial[35]    = enc_data_in[28];
    assign enc_partial[36]    = enc_data_in[29];
    assign enc_partial[37]    = enc_data_in[30];
    assign enc_partial[38]    = enc_data_in[31];
    assign enc_partial[39]    = enc_data_in[32];
    assign enc_partial[40]    = enc_data_in[33];
    assign enc_partial[41]    = enc_data_in[34];
    assign enc_partial[42]    = enc_data_in[35];
    assign enc_partial[43]    = enc_data_in[36];
    assign enc_partial[44]    = enc_data_in[37];
    assign enc_partial[45]    = enc_data_in[38];
    assign enc_partial[46]    = enc_data_in[39];
    assign enc_partial[47]    = enc_data_in[40];
    assign enc_partial[48]    = enc_data_in[41];
    assign enc_partial[49]    = enc_data_in[42];
    assign enc_partial[50]    = enc_data_in[43];
    assign enc_partial[51]    = enc_data_in[44];
    assign enc_partial[52]    = enc_data_in[45];
    assign enc_partial[53]    = enc_data_in[46];
    assign enc_partial[54]    = enc_data_in[47];
    assign enc_partial[55]    = enc_data_in[48];
    assign enc_partial[56]    = enc_data_in[49];
    assign enc_partial[57]    = enc_data_in[50];
    assign enc_partial[58]    = enc_data_in[51];
    assign enc_partial[59]    = enc_data_in[52];
    assign enc_partial[60]    = enc_data_in[53];
    assign enc_partial[61]    = enc_data_in[54];
    assign enc_partial[62]    = enc_data_in[55];
    assign enc_partial[63]    = enc_data_in[56];
    assign enc_partial[64]    = 1'b0;           // position 64 = check bit
    assign enc_partial[65]    = enc_data_in[57];
    assign enc_partial[66]    = enc_data_in[58];
    assign enc_partial[67]    = enc_data_in[59];
    assign enc_partial[68]    = enc_data_in[60];
    assign enc_partial[69]    = enc_data_in[61];
    assign enc_partial[70]    = enc_data_in[62];
    assign enc_partial[71]    = enc_data_in[63];

    // Hamming check bits: Pk = XOR of all data bits at positions covered by Pk
    wire enc_p1, enc_p2, enc_p4, enc_p8, enc_p16, enc_p32, enc_p64;

    assign enc_p1 =
        enc_data_in[0]  ^ enc_data_in[1]  ^ enc_data_in[3]  ^ enc_data_in[4]  ^
        enc_data_in[6]  ^ enc_data_in[8]  ^ enc_data_in[10] ^ enc_data_in[11] ^
        enc_data_in[13] ^ enc_data_in[15] ^ enc_data_in[17] ^ enc_data_in[19] ^
        enc_data_in[21] ^ enc_data_in[23] ^ enc_data_in[25] ^ enc_data_in[26] ^
        enc_data_in[28] ^ enc_data_in[30] ^ enc_data_in[32] ^ enc_data_in[34] ^
        enc_data_in[36] ^ enc_data_in[38] ^ enc_data_in[40] ^ enc_data_in[42] ^
        enc_data_in[44] ^ enc_data_in[46] ^ enc_data_in[48] ^ enc_data_in[50] ^
        enc_data_in[52] ^ enc_data_in[54] ^ enc_data_in[56] ^ enc_data_in[57] ^
        enc_data_in[59] ^ enc_data_in[61] ^ enc_data_in[63];

    assign enc_p2 =
        enc_data_in[0]  ^ enc_data_in[2]  ^ enc_data_in[3]  ^ enc_data_in[5]  ^
        enc_data_in[6]  ^ enc_data_in[9]  ^ enc_data_in[10] ^ enc_data_in[12] ^
        enc_data_in[13] ^ enc_data_in[16] ^ enc_data_in[17] ^ enc_data_in[20] ^
        enc_data_in[21] ^ enc_data_in[24] ^ enc_data_in[25] ^ enc_data_in[27] ^
        enc_data_in[28] ^ enc_data_in[31] ^ enc_data_in[32] ^ enc_data_in[35] ^
        enc_data_in[36] ^ enc_data_in[39] ^ enc_data_in[40] ^ enc_data_in[43] ^
        enc_data_in[44] ^ enc_data_in[47] ^ enc_data_in[48] ^ enc_data_in[51] ^
        enc_data_in[52] ^ enc_data_in[55] ^ enc_data_in[56] ^ enc_data_in[58] ^
        enc_data_in[59] ^ enc_data_in[62] ^ enc_data_in[63];

    assign enc_p4 =
        enc_data_in[1]  ^ enc_data_in[2]  ^ enc_data_in[3]  ^ enc_data_in[7]  ^
        enc_data_in[8]  ^ enc_data_in[9]  ^ enc_data_in[10] ^ enc_data_in[14] ^
        enc_data_in[15] ^ enc_data_in[16] ^ enc_data_in[17] ^ enc_data_in[22] ^
        enc_data_in[23] ^ enc_data_in[24] ^ enc_data_in[25] ^ enc_data_in[29] ^
        enc_data_in[30] ^ enc_data_in[31] ^ enc_data_in[32] ^ enc_data_in[37] ^
        enc_data_in[38] ^ enc_data_in[39] ^ enc_data_in[40] ^ enc_data_in[45] ^
        enc_data_in[46] ^ enc_data_in[47] ^ enc_data_in[48] ^ enc_data_in[53] ^
        enc_data_in[54] ^ enc_data_in[55] ^ enc_data_in[56] ^ enc_data_in[60] ^
        enc_data_in[61] ^ enc_data_in[62] ^ enc_data_in[63];

    assign enc_p8 =
        enc_data_in[4]  ^ enc_data_in[5]  ^ enc_data_in[6]  ^ enc_data_in[7]  ^
        enc_data_in[8]  ^ enc_data_in[9]  ^ enc_data_in[10] ^ enc_data_in[18] ^
        enc_data_in[19] ^ enc_data_in[20] ^ enc_data_in[21] ^ enc_data_in[22] ^
        enc_data_in[23] ^ enc_data_in[24] ^ enc_data_in[25] ^ enc_data_in[33] ^
        enc_data_in[34] ^ enc_data_in[35] ^ enc_data_in[36] ^ enc_data_in[37] ^
        enc_data_in[38] ^ enc_data_in[39] ^ enc_data_in[40] ^ enc_data_in[49] ^
        enc_data_in[50] ^ enc_data_in[51] ^ enc_data_in[52] ^ enc_data_in[53] ^
        enc_data_in[54] ^ enc_data_in[55] ^ enc_data_in[56];

    assign enc_p16 =
        enc_data_in[11] ^ enc_data_in[12] ^ enc_data_in[13] ^ enc_data_in[14] ^
        enc_data_in[15] ^ enc_data_in[16] ^ enc_data_in[17] ^ enc_data_in[18] ^
        enc_data_in[19] ^ enc_data_in[20] ^ enc_data_in[21] ^ enc_data_in[22] ^
        enc_data_in[23] ^ enc_data_in[24] ^ enc_data_in[25] ^ enc_data_in[41] ^
        enc_data_in[42] ^ enc_data_in[43] ^ enc_data_in[44] ^ enc_data_in[45] ^
        enc_data_in[46] ^ enc_data_in[47] ^ enc_data_in[48] ^ enc_data_in[49] ^
        enc_data_in[50] ^ enc_data_in[51] ^ enc_data_in[52] ^ enc_data_in[53] ^
        enc_data_in[54] ^ enc_data_in[55] ^ enc_data_in[56];

    assign enc_p32 =
        enc_data_in[26] ^ enc_data_in[27] ^ enc_data_in[28] ^ enc_data_in[29] ^
        enc_data_in[30] ^ enc_data_in[31] ^ enc_data_in[32] ^ enc_data_in[33] ^
        enc_data_in[34] ^ enc_data_in[35] ^ enc_data_in[36] ^ enc_data_in[37] ^
        enc_data_in[38] ^ enc_data_in[39] ^ enc_data_in[40] ^ enc_data_in[41] ^
        enc_data_in[42] ^ enc_data_in[43] ^ enc_data_in[44] ^ enc_data_in[45] ^
        enc_data_in[46] ^ enc_data_in[47] ^ enc_data_in[48] ^ enc_data_in[49] ^
        enc_data_in[50] ^ enc_data_in[51] ^ enc_data_in[52] ^ enc_data_in[53] ^
        enc_data_in[54] ^ enc_data_in[55] ^ enc_data_in[56];

    assign enc_p64 =
        enc_data_in[57] ^ enc_data_in[58] ^ enc_data_in[59] ^ enc_data_in[60] ^
        enc_data_in[61] ^ enc_data_in[62] ^ enc_data_in[63];

    // Assemble codeword with check bits inserted (P0 computed last)
    wire [71:0] enc_cw_noP0;
    assign enc_cw_noP0 = {enc_partial[71:65],
                          enc_p64,           // bit 64
                          enc_partial[63:33],
                          enc_p32,           // bit 32
                          enc_partial[31:17],
                          enc_p16,           // bit 16
                          enc_partial[15:9],
                          enc_p8,            // bit 8
                          enc_partial[7:5],
                          enc_p4,            // bit 4
                          enc_partial[3],
                          enc_p2,            // bit 2
                          enc_p1,            // bit 1
                          1'b0};             // bit 0 placeholder for P0

    // P0 = XOR of all 72 bits (even parity); compute over all non-P0 bits
    wire enc_p0;
    assign enc_p0 = ^enc_cw_noP0[71:1];  // XOR of bits 1..71

    assign enc_data_out = {enc_cw_noP0[71:1], enc_p0};

    // ----------------------------------------------------------------
    // DECODER
    // ----------------------------------------------------------------
    // Compute syndrome: Sk = XOR of all received bits at positions covered by Pk
    wire dec_s1, dec_s2, dec_s4, dec_s8, dec_s16, dec_s32, dec_s64;

    assign dec_s1 =
        dec_data_in[1]  ^ dec_data_in[3]  ^ dec_data_in[5]  ^ dec_data_in[7]  ^
        dec_data_in[9]  ^ dec_data_in[11] ^ dec_data_in[13] ^ dec_data_in[15] ^
        dec_data_in[17] ^ dec_data_in[19] ^ dec_data_in[21] ^ dec_data_in[23] ^
        dec_data_in[25] ^ dec_data_in[27] ^ dec_data_in[29] ^ dec_data_in[31] ^
        dec_data_in[33] ^ dec_data_in[35] ^ dec_data_in[37] ^ dec_data_in[39] ^
        dec_data_in[41] ^ dec_data_in[43] ^ dec_data_in[45] ^ dec_data_in[47] ^
        dec_data_in[49] ^ dec_data_in[51] ^ dec_data_in[53] ^ dec_data_in[55] ^
        dec_data_in[57] ^ dec_data_in[59] ^ dec_data_in[61] ^ dec_data_in[63] ^
        dec_data_in[65] ^ dec_data_in[67] ^ dec_data_in[69] ^ dec_data_in[71];

    assign dec_s2 =
        dec_data_in[2]  ^ dec_data_in[3]  ^ dec_data_in[6]  ^ dec_data_in[7]  ^
        dec_data_in[10] ^ dec_data_in[11] ^ dec_data_in[14] ^ dec_data_in[15] ^
        dec_data_in[18] ^ dec_data_in[19] ^ dec_data_in[22] ^ dec_data_in[23] ^
        dec_data_in[26] ^ dec_data_in[27] ^ dec_data_in[30] ^ dec_data_in[31] ^
        dec_data_in[34] ^ dec_data_in[35] ^ dec_data_in[38] ^ dec_data_in[39] ^
        dec_data_in[42] ^ dec_data_in[43] ^ dec_data_in[46] ^ dec_data_in[47] ^
        dec_data_in[50] ^ dec_data_in[51] ^ dec_data_in[54] ^ dec_data_in[55] ^
        dec_data_in[58] ^ dec_data_in[59] ^ dec_data_in[62] ^ dec_data_in[63] ^
        dec_data_in[66] ^ dec_data_in[67] ^ dec_data_in[70] ^ dec_data_in[71];

    assign dec_s4 =
        dec_data_in[4]  ^ dec_data_in[5]  ^ dec_data_in[6]  ^ dec_data_in[7]  ^
        dec_data_in[12] ^ dec_data_in[13] ^ dec_data_in[14] ^ dec_data_in[15] ^
        dec_data_in[20] ^ dec_data_in[21] ^ dec_data_in[22] ^ dec_data_in[23] ^
        dec_data_in[28] ^ dec_data_in[29] ^ dec_data_in[30] ^ dec_data_in[31] ^
        dec_data_in[36] ^ dec_data_in[37] ^ dec_data_in[38] ^ dec_data_in[39] ^
        dec_data_in[44] ^ dec_data_in[45] ^ dec_data_in[46] ^ dec_data_in[47] ^
        dec_data_in[52] ^ dec_data_in[53] ^ dec_data_in[54] ^ dec_data_in[55] ^
        dec_data_in[60] ^ dec_data_in[61] ^ dec_data_in[62] ^ dec_data_in[63] ^
        dec_data_in[68] ^ dec_data_in[69] ^ dec_data_in[70] ^ dec_data_in[71];

    assign dec_s8 =
        dec_data_in[8]  ^ dec_data_in[9]  ^ dec_data_in[10] ^ dec_data_in[11] ^
        dec_data_in[12] ^ dec_data_in[13] ^ dec_data_in[14] ^ dec_data_in[15] ^
        dec_data_in[24] ^ dec_data_in[25] ^ dec_data_in[26] ^ dec_data_in[27] ^
        dec_data_in[28] ^ dec_data_in[29] ^ dec_data_in[30] ^ dec_data_in[31] ^
        dec_data_in[40] ^ dec_data_in[41] ^ dec_data_in[42] ^ dec_data_in[43] ^
        dec_data_in[44] ^ dec_data_in[45] ^ dec_data_in[46] ^ dec_data_in[47] ^
        dec_data_in[56] ^ dec_data_in[57] ^ dec_data_in[58] ^ dec_data_in[59] ^
        dec_data_in[60] ^ dec_data_in[61] ^ dec_data_in[62] ^ dec_data_in[63];

    assign dec_s16 =
        dec_data_in[16] ^ dec_data_in[17] ^ dec_data_in[18] ^ dec_data_in[19] ^
        dec_data_in[20] ^ dec_data_in[21] ^ dec_data_in[22] ^ dec_data_in[23] ^
        dec_data_in[24] ^ dec_data_in[25] ^ dec_data_in[26] ^ dec_data_in[27] ^
        dec_data_in[28] ^ dec_data_in[29] ^ dec_data_in[30] ^ dec_data_in[31] ^
        dec_data_in[48] ^ dec_data_in[49] ^ dec_data_in[50] ^ dec_data_in[51] ^
        dec_data_in[52] ^ dec_data_in[53] ^ dec_data_in[54] ^ dec_data_in[55] ^
        dec_data_in[56] ^ dec_data_in[57] ^ dec_data_in[58] ^ dec_data_in[59] ^
        dec_data_in[60] ^ dec_data_in[61] ^ dec_data_in[62] ^ dec_data_in[63];

    assign dec_s32 =
        dec_data_in[32] ^ dec_data_in[33] ^ dec_data_in[34] ^ dec_data_in[35] ^
        dec_data_in[36] ^ dec_data_in[37] ^ dec_data_in[38] ^ dec_data_in[39] ^
        dec_data_in[40] ^ dec_data_in[41] ^ dec_data_in[42] ^ dec_data_in[43] ^
        dec_data_in[44] ^ dec_data_in[45] ^ dec_data_in[46] ^ dec_data_in[47] ^
        dec_data_in[48] ^ dec_data_in[49] ^ dec_data_in[50] ^ dec_data_in[51] ^
        dec_data_in[52] ^ dec_data_in[53] ^ dec_data_in[54] ^ dec_data_in[55] ^
        dec_data_in[56] ^ dec_data_in[57] ^ dec_data_in[58] ^ dec_data_in[59] ^
        dec_data_in[60] ^ dec_data_in[61] ^ dec_data_in[62] ^ dec_data_in[63];

    assign dec_s64 =
        dec_data_in[64] ^ dec_data_in[65] ^ dec_data_in[66] ^ dec_data_in[67] ^
        dec_data_in[68] ^ dec_data_in[69] ^ dec_data_in[70] ^ dec_data_in[71];

    // Overall parity (P0 syndrome): XOR of all 72 received bits
    wire dec_p0_check;
    assign dec_p0_check = ^dec_data_in;

    // Syndrome: [7:1] = {S64,S32,S16,S8,S4,S2,S1}, [0] = P0
    wire [6:0] dec_hamming_syn;
    assign dec_hamming_syn = {dec_s64, dec_s32, dec_s16, dec_s8, dec_s4, dec_s2, dec_s1};
    assign dec_syndrome    = {dec_hamming_syn, dec_p0_check};

    // Error classification
    assign dec_single_err = (dec_hamming_syn != 7'b0) &&  dec_p0_check;
    assign dec_double_err = (dec_hamming_syn != 7'b0) && ~dec_p0_check;
    assign dec_err_bit    = dec_hamming_syn;  // error position (0–71)

    // Corrected received codeword: flip bit at error position when SBE
    wire [71:0] dec_corrected_cw;
    genvar gi;
    generate
        for (gi = 0; gi < 72; gi = gi + 1) begin : gen_correct
            assign dec_corrected_cw[gi] = dec_single_err && (dec_hamming_syn == gi[6:0])
                                          ? ~dec_data_in[gi]
                                          :  dec_data_in[gi];
        end
    endgenerate

    // Extract data bits from corrected codeword
    assign dec_data_out[0]  = dec_corrected_cw[3];
    assign dec_data_out[1]  = dec_corrected_cw[5];
    assign dec_data_out[2]  = dec_corrected_cw[6];
    assign dec_data_out[3]  = dec_corrected_cw[7];
    assign dec_data_out[4]  = dec_corrected_cw[9];
    assign dec_data_out[5]  = dec_corrected_cw[10];
    assign dec_data_out[6]  = dec_corrected_cw[11];
    assign dec_data_out[7]  = dec_corrected_cw[12];
    assign dec_data_out[8]  = dec_corrected_cw[13];
    assign dec_data_out[9]  = dec_corrected_cw[14];
    assign dec_data_out[10] = dec_corrected_cw[15];
    assign dec_data_out[11] = dec_corrected_cw[17];
    assign dec_data_out[12] = dec_corrected_cw[18];
    assign dec_data_out[13] = dec_corrected_cw[19];
    assign dec_data_out[14] = dec_corrected_cw[20];
    assign dec_data_out[15] = dec_corrected_cw[21];
    assign dec_data_out[16] = dec_corrected_cw[22];
    assign dec_data_out[17] = dec_corrected_cw[23];
    assign dec_data_out[18] = dec_corrected_cw[24];
    assign dec_data_out[19] = dec_corrected_cw[25];
    assign dec_data_out[20] = dec_corrected_cw[26];
    assign dec_data_out[21] = dec_corrected_cw[27];
    assign dec_data_out[22] = dec_corrected_cw[28];
    assign dec_data_out[23] = dec_corrected_cw[29];
    assign dec_data_out[24] = dec_corrected_cw[30];
    assign dec_data_out[25] = dec_corrected_cw[31];
    assign dec_data_out[26] = dec_corrected_cw[33];
    assign dec_data_out[27] = dec_corrected_cw[34];
    assign dec_data_out[28] = dec_corrected_cw[35];
    assign dec_data_out[29] = dec_corrected_cw[36];
    assign dec_data_out[30] = dec_corrected_cw[37];
    assign dec_data_out[31] = dec_corrected_cw[38];
    assign dec_data_out[32] = dec_corrected_cw[39];
    assign dec_data_out[33] = dec_corrected_cw[40];
    assign dec_data_out[34] = dec_corrected_cw[41];
    assign dec_data_out[35] = dec_corrected_cw[42];
    assign dec_data_out[36] = dec_corrected_cw[43];
    assign dec_data_out[37] = dec_corrected_cw[44];
    assign dec_data_out[38] = dec_corrected_cw[45];
    assign dec_data_out[39] = dec_corrected_cw[46];
    assign dec_data_out[40] = dec_corrected_cw[47];
    assign dec_data_out[41] = dec_corrected_cw[48];
    assign dec_data_out[42] = dec_corrected_cw[49];
    assign dec_data_out[43] = dec_corrected_cw[50];
    assign dec_data_out[44] = dec_corrected_cw[51];
    assign dec_data_out[45] = dec_corrected_cw[52];
    assign dec_data_out[46] = dec_corrected_cw[53];
    assign dec_data_out[47] = dec_corrected_cw[54];
    assign dec_data_out[48] = dec_corrected_cw[55];
    assign dec_data_out[49] = dec_corrected_cw[56];
    assign dec_data_out[50] = dec_corrected_cw[57];
    assign dec_data_out[51] = dec_corrected_cw[58];
    assign dec_data_out[52] = dec_corrected_cw[59];
    assign dec_data_out[53] = dec_corrected_cw[60];
    assign dec_data_out[54] = dec_corrected_cw[61];
    assign dec_data_out[55] = dec_corrected_cw[62];
    assign dec_data_out[56] = dec_corrected_cw[63];
    assign dec_data_out[57] = dec_corrected_cw[65];
    assign dec_data_out[58] = dec_corrected_cw[66];
    assign dec_data_out[59] = dec_corrected_cw[67];
    assign dec_data_out[60] = dec_corrected_cw[68];
    assign dec_data_out[61] = dec_corrected_cw[69];
    assign dec_data_out[62] = dec_corrected_cw[70];
    assign dec_data_out[63] = dec_corrected_cw[71];

endmodule
