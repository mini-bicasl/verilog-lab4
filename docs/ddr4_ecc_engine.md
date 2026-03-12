# `ddr4_ecc_engine` — SECDED (72,64) ECC Engine

## Overview

`ddr4_ecc_engine` implements a **Single-Error Correct, Double-Error Detect (SECDED)** Hamming code over a 64-bit data word with 8 check bits, producing a 72-bit codeword. It is instantiated inside [`ddr4_data_path`](ddr4_data_path.md) and provides the write-path encoder and read-path decoder for the DDR4 controller.

**Source files:** `rtl/ddr4_ecc_engine.v` · `tb/ddr4_ecc_engine_tb.v`

---

## Interface

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Controller clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `enc_data_in` | in | 64 | Uncoded write data |
| `enc_data_out` | out | 72 | ECC-encoded codeword (64 data + 8 check bits) |
| `dec_data_in` | in | 72 | ECC codeword from DRAM |
| `dec_data_out` | out | 64 | Corrected read data |
| `dec_single_err` | out | 1 | Single-bit error detected and corrected |
| `dec_double_err` | out | 1 | Double-bit error detected (uncorrectable) |
| `dec_syndrome` | out | 8 | Raw syndrome: `[7:1]` = Hamming position, `[0]` = P0 overall parity |
| `dec_err_bit` | out | 7 | Codeword bit position of single-bit error (0–71) |

Both encoder and decoder are **fully combinatorial**. Clock and reset are present on the module boundary for DFT and potential future pipelining.

---

## Codeword Structure (72,64)

```
Bit position:  71..65  64   63..33  32   31..17  16   15..9  8   7..5  4   3   2   1   0
Type:            D     P64    D     P32    D     P16    D    P8   D   P4   D  P2  P1  P0
```

- **P0** (bit 0): overall parity of all 72 bits — augments Hamming code to SECDED
- **P1** (bit 1): parity over all positions where `pos[0]=1`
- **P2** (bit 2): parity over all positions where `pos[1]=1`
- **P4** (bit 4): parity over all positions where `pos[2]=1`
- **P8** (bit 8): parity over all positions where `pos[3]=1`
- **P16** (bit 16): parity over all positions where `pos[4]=1`
- **P32** (bit 32): parity over all positions where `pos[5]=1`
- **P64** (bit 64): parity over all positions where `pos[6]=1`

The 64 data bits occupy the remaining positions:
`3, 5, 6, 7, 9–15, 17–31, 33–63, 65–71`

---

## Encoder Flow

1. Place each `enc_data_in[i]` at its corresponding codeword data position.
2. Compute each Hamming check bit **Pk** = XOR of all data bit positions covered by Pk.
3. Compute **P0** = XOR of bits 1–71 of the codeword (overall even parity).
4. Output full 72-bit codeword as `enc_data_out`.

---

## Decoder Flow

1. Compute syndrome bits **S1, S2, S4, S8, S16, S32, S64** = XOR of all received codeword bits at positions covered by each check equation.
2. Compute overall parity **P0_check** = XOR of all 72 received bits.
3. Form syndrome: `dec_syndrome = {S64, S32, S16, S8, S4, S2, S1, P0_check}`
4. Classify error:
   - If correction required (`dec_single_err`), flip the bit at position `dec_syndrome[7:1]` in the received codeword.
5. Extract the 64 corrected data bits from codeword data positions → `dec_data_out`.

---

## Error Classification Table

| `dec_syndrome[7:1]` | `dec_syndrome[0]` (P0) | Interpretation |
|---|---|---|
| `7'b000_0000` | 0 | **No error** |
| `7'b000_0000` | 1 | Error in P0 itself (check bit only; data unaffected) |
| Non-zero | 1 | **Single-bit error** — corrected at position `dec_syndrome[7:1]` |
| Non-zero | 0 | **Double-bit error** — uncorrectable; `dec_double_err` raised |

---

## Key Constraints

- **Latency**: Purely combinatorial; zero clock cycles.
- **Reset**: Module accepts `rst_n` for DFT compliance but no internal state is reset-critical in this implementation.
- **Scrub support**: The `dec_single_err` and `dec_err_bit` outputs may be routed back through `ddr4_data_path` to trigger a scrub write-back of corrected data.

---

## References

- JEDEC Standard JESD79-4D — DDR4 SDRAM (§3.3 ECC)
- `docs/ARCHITECTURE.md` §6 (ECC Architecture Detail)
