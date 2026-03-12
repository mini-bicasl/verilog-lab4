# ddr4_mode_reg — DDR4 Mode Register Encoder

## Overview

Shadow register and combinational MRS payload encoder for DDR4 Mode Registers MR0–MR6. Takes configuration inputs (CAS latency, RTT, drive strength, etc.) and presents the correct 17-bit payload for any MR number selected by `mr_select`. Used by `ddr4_init_fsm` during the MRS sequence.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `cfg_cl` | in | 5 | CAS latency (9–24) |
| `cfg_cwl` | in | 5 | CAS write latency (9–18) |
| `cfg_al` | in | 2 | Additive latency |
| `cfg_rtt_nom` | in | 3 | RTT_NOM termination code |
| `cfg_rtt_wr` | in | 3 | RTT_WR dynamic ODT code |
| `cfg_rtt_park` | in | 3 | RTT_PARK termination code |
| `cfg_drive_strength` | in | 2 | Output driver impedance |
| `cfg_wr_recovery` | in | 4 | Write recovery cycles |
| `cfg_dbi_rd_en` | in | 1 | Enable read DBI |
| `cfg_dbi_wr_en` | in | 1 | Enable write DBI |
| `cfg_ca_parity_en` | in | 1 | Enable CA parity |
| `mr_select` | in | 3 | MR number to read (0–6) |
| `mr_data` | out | 17 | Encoded MR payload |

## MR Bit-Field Map

### MR0
| Bits | Field |
|------|-------|
| 0 | Burst type (0=nibble) |
| 2:1 | BL (00=BL8) |
| 6:4 | CL[2:0] |
| 11:9 | WR recovery[2:0] |
| 12 | CL[3] |
| 13 | WR recovery[3] |

### MR1
| Bits | Field |
|------|-------|
| 1:0 | Drive strength |
| 4:3 | Additive latency |
| 10:8 | RTT_NOM |

### MR2
| Bits | Field |
|------|-------|
| 5:3 | CWL encoding (CWL–9) |
| 11:9 | RTT_WR |

### MR5
| Bits | Field |
|------|-------|
| 0 | CA parity enable |
| 8:6 | RTT_PARK |
| 11 | DBI write enable |
| 12 | DBI read enable |

MR3, MR4, MR6 return `17'h0` (reserved fields).

## Related Files

- RTL: `rtl/ddr4_mode_reg.v`
- Testbench: `tb/ddr4_mode_reg_tb.v`
- Consumer: `ddr4_init_fsm` reads `mr_data` keyed by `mr_select`
