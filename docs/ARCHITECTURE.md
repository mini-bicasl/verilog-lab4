# Architecture Reference — Commercial Server-Grade DDR4 Memory Controller

**Standard:** JEDEC JESD79-4D (DDR4 SDRAM)
**Reference:** https://www.jedec.org/standards-documents/docs/jesd79-4b (JESD79-4B public summary page;
JESD79-4D is the latest revision and is available to JEDEC members or by purchase).
The public summary page linked above is the most recent publicly accessible version; JESD79-4D supersedes it.

---

## 1. Project Overview

This project implements a **commercial server-grade DDR4 SDRAM controller** in synthesizable Verilog (IEEE 1800-2012 subset compatible with Icarus Verilog). The design targets a single DDR4 channel with the following headline features:

| Feature | Value / Description |
|---|---|
| JEDEC Standard | DDR4 SDRAM – JESD79-4D |
| Data bus width | 64-bit (8 × ×8 devices) + 8-bit ECC (1 × ×8 ECC device) = 72-bit total |
| ECC scheme | SECDED (Single-Error Correct, Double-Error Detect) over 64-bit data words |
| Ranks | 1–4 configurable (RTL parameter `NUM_RANKS`) |
| Banks per rank | 16 (4 bank groups × 4 banks, DDR4 BG addressing) |
| Row address | 17 bits (128 K rows per bank, parameter `ROW_BITS`) |
| Column address | 10 bits (1 K columns per row, parameter `COL_BITS`) |
| Burst length | BL8 (fixed, per JESD79-4) |
| Host interface | AXI4 (64-bit data, 32-bit address) |
| Timing | Fully parameterized; defaults match DDR4-3200 (1600 MHz data rate) |
| Refresh | Auto-refresh (REF), Fine Granularity Refresh (FGR ×2/×4), Per-Bank Refresh (PBR) |
| Power management | Active power-down, self-refresh (SR), clock gating per rank |
| Calibration | ZQ short/long calibration state machine |
| Clock | Single source clock `clk`; PHY generates differential `CK_t/CK_c` |
| Reset | Active-low synchronous `rst_n` throughout |

---

## 2. Functional Blocks / Modules

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ddr4_ctrl_top                               │
│                                                                     │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────────────────┐   │
│  │ddr4_host_   │   │ddr4_cmd_     │   │  ddr4_init_fsm        │   │
│  │iface        │──▶│scheduler     │──▶│  (power-up sequence)  │   │
│  │(AXI4 slave) │   │(bank FSMs,   │   └───────────────────────┘   │
│  └─────────────┘   │ queue, rank  │                                │
│                    │ interleaving)│   ┌───────────────────────┐   │
│                    └──────┬───────┘   │  ddr4_mode_reg        │   │
│                           │           │  (MR0–MR6 config)     │   │
│                    ┌──────▼───────┐   └───────────────────────┘   │
│                    │ddr4_timing_  │                                │
│                    │engine        │   ┌───────────────────────┐   │
│                    │(tRCD,tRP,    │   │  ddr4_refresh_ctrl    │   │
│                    │ tCL,tRAS…)   │◀──│  (tREFI timer, FGR,   │   │
│                    └──────┬───────┘   │   PBR, SR)            │   │
│                           │           └───────────────────────┘   │
│                    ┌──────▼───────┐                                │
│                    │ddr4_data_    │   ┌───────────────────────┐   │
│                    │path          │◀──│  ddr4_ecc_engine      │   │
│                    │(RD/WR fifos, │──▶│  (SECDED enc/dec,     │   │
│                    │ DQS align)   │   │   scrub, error log)   │   │
│                    └──────┬───────┘   └───────────────────────┘   │
│                           │                                        │
│                    ┌──────▼───────┐                                │
│                    │ddr4_phy_iface│                                │
│                    │(abstract PHY │                                │
│                    │ I/O pads)    │                                │
│                    └─────────────┘                                 │
└─────────────────────────────────────────────────────────────────────┘
```

| Module | File | Description |
|---|---|---|
| `ddr4_ctrl_top` | `rtl/ddr4_ctrl_top.v` | Top-level wrapper; ties all sub-modules together; exposes AXI4 host port and DRAM I/O |
| `ddr4_host_iface` | `rtl/ddr4_host_iface.v` | AXI4 slave; converts AXI4 read/write transactions into internal command + data requests |
| `ddr4_cmd_scheduler` | `rtl/ddr4_cmd_scheduler.v` | Open/closed-page policy; per-bank FSM (IDLE→ACTIVATE→RD/WR→PRECHARGE); rank interleaving; command queue arbitration |
| `ddr4_timing_engine` | `rtl/ddr4_timing_engine.v` | Enforces all JEDEC timing constraints as down-counters; issues `timing_ok` signals gating command issue |
| `ddr4_refresh_ctrl` | `rtl/ddr4_refresh_ctrl.v` | Tracks tREFI countdown; issues REF/PBR commands; supports FGR×2 and FGR×4; self-refresh entry/exit |
| `ddr4_init_fsm` | `rtl/ddr4_init_fsm.v` | CKE ramp, tDLLK, tZQINIT, MR programming sequence per JESD79-4 §3.3 |
| `ddr4_mode_reg` | `rtl/ddr4_mode_reg.v` | Holds MR0–MR6 shadow registers; provides MRS command to init/reconfiguration path |
| `ddr4_data_path` | `rtl/ddr4_data_path.v` | 8:1 serializer/deserializer bridge; read/write data FIFOs; DQS preamble/postamble generation |
| `ddr4_ecc_engine` | `rtl/ddr4_ecc_engine.v` | SECDED encoder (write path) and decoder (read path); single-bit correction; double-bit detection; error logging register |
| `ddr4_phy_iface` | `rtl/ddr4_phy_iface.v` | Abstract PHY layer; differential I/O buffers for CK, DQS; SSTL15 / POD12 termination placeholders |

---

## 3. Interfaces

### 3.1 `ddr4_ctrl_top` — Top-Level Ports

#### Clock / Reset

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Controller clock (= DDR4 data rate / 8 for DFI-style, e.g. 200 MHz for DDR4-3200) |
| `rst_n` | in | 1 | Active-low synchronous reset |

#### AXI4 Host Interface (slave)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `s_axi_awid` | in | 4 | Write address ID |
| `s_axi_awaddr` | in | 32 | Write address (byte-addressed) |
| `s_axi_awlen` | in | 8 | Burst length − 1 |
| `s_axi_awsize` | in | 3 | Transfer size (must be 3'b011 = 8 bytes for 64-bit bus) |
| `s_axi_awburst` | in | 2 | Burst type (INCR = 2'b01) |
| `s_axi_awvalid` | in | 1 | Write address valid |
| `s_axi_awready` | out | 1 | Write address ready |
| `s_axi_wdata` | in | 64 | Write data |
| `s_axi_wstrb` | in | 8 | Write byte enable |
| `s_axi_wlast` | in | 1 | Write last beat |
| `s_axi_wvalid` | in | 1 | Write data valid |
| `s_axi_wready` | out | 1 | Write data ready |
| `s_axi_bid` | out | 4 | Write response ID |
| `s_axi_bresp` | out | 2 | Write response (OKAY/SLVERR) |
| `s_axi_bvalid` | out | 1 | Write response valid |
| `s_axi_bready` | in | 1 | Write response ready |
| `s_axi_arid` | in | 4 | Read address ID |
| `s_axi_araddr` | in | 32 | Read address (byte-addressed) |
| `s_axi_arlen` | in | 8 | Burst length − 1 |
| `s_axi_arsize` | in | 3 | Transfer size |
| `s_axi_arburst` | in | 2 | Burst type |
| `s_axi_arvalid` | in | 1 | Read address valid |
| `s_axi_arready` | out | 1 | Read address ready |
| `s_axi_rid` | out | 4 | Read data ID |
| `s_axi_rdata` | out | 64 | Read data |
| `s_axi_rresp` | out | 2 | Read response |
| `s_axi_rlast` | out | 1 | Read last beat |
| `s_axi_rvalid` | out | 1 | Read data valid |
| `s_axi_rready` | in | 1 | Read data ready |

#### DRAM Physical Interface (to PHY / pads)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `ddr4_ck_t` | out | `NUM_RANKS` | Differential clock true (one per rank) |
| `ddr4_ck_c` | out | `NUM_RANKS` | Differential clock complement |
| `ddr4_cke` | out | `NUM_RANKS` | Clock enable per rank |
| `ddr4_cs_n` | out | `NUM_RANKS` | Chip select (active low) |
| `ddr4_act_n` | out | 1 | Activate command indicator |
| `ddr4_ras_n` | out | 1 | Row address strobe (address[16]) |
| `ddr4_cas_n` | out | 1 | Column address strobe |
| `ddr4_we_n` | out | 1 | Write enable |
| `ddr4_bg` | out | 2 | Bank group select |
| `ddr4_ba` | out | 2 | Bank address |
| `ddr4_a` | out | 17 | Row/column multiplexed address |
| `ddr4_odt` | out | `NUM_RANKS` | On-die termination control |
| `ddr4_reset_n` | out | 1 | DRAM reset (active low) |
| `ddr4_dq` | inout | 72 | Data bus (64 data + 8 ECC) |
| `ddr4_dqs_t` | inout | 9 | Data strobe true (8 data + 1 ECC lane) |
| `ddr4_dqs_c` | inout | 9 | Data strobe complement |
| `ddr4_dm_dbi_n` | inout | 9 | Data mask / data bus inversion |

#### Status and Control

| Signal | Dir | Width | Description |
|---|---|---|---|
| `init_done` | out | 1 | Asserted when DRAM initialization is complete |
| `ecc_single_err` | out | 1 | Single-bit ECC error detected (corrected) |
| `ecc_double_err` | out | 1 | Double-bit ECC error detected (uncorrectable) |
| `ecc_err_addr` | out | 32 | Address of most recent ECC error |
| `ecc_err_syndrome` | out | 8 | ECC syndrome of last error |
| `ref_in_progress` | out | 1 | Refresh operation active (access blocked) |
| `cfg_timing_base` | in | 1 | 0 = use internal defaults, 1 = load from `cfg_*` ports |
| `cfg_cl` | in | 5 | Configurable CAS Latency (CL) |
| `cfg_cwl` | in | 5 | Configurable CAS Write Latency (CWL) |
| `cfg_trcd` | in | 8 | tRCD in controller clock cycles |
| `cfg_trp` | in | 8 | tRP in controller clock cycles |
| `cfg_tras` | in | 8 | tRAS in controller clock cycles |
| `cfg_trc` | in | 8 | tRC in controller clock cycles |
| `cfg_trfc` | in | 10 | tRFC in controller clock cycles |
| `cfg_trefi` | in | 14 | tREFI in controller clock cycles |
| `cfg_fgr_mode` | in | 2 | 2'b00=normal, 2'b01=FGR×2, 2'b10=FGR×4 |
| `cfg_pbr_en` | in | 1 | Enable per-bank refresh mode |

---

### 3.2 `ddr4_host_iface`

Converts AXI4 transactions into internal command/data words.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| AXI4 slave ports | — | — | Same as §3.1 host interface signals |
| `cmd_valid` | out | 1 | Internal command valid to scheduler |
| `cmd_ready` | in | 1 | Scheduler ready to accept |
| `cmd_type` | out | 2 | 2'b00=READ, 2'b01=WRITE |
| `cmd_addr` | out | 32 | Host byte address |
| `cmd_id` | out | 4 | Transaction ID for reorder |
| `wdata_valid` | out | 1 | Write data valid to data path |
| `wdata_ready` | in | 1 | Data path ready |
| `wdata` | out | 64 | Write data |
| `wdata_strb` | out | 8 | Write byte strobes |
| `rdata_valid` | in | 1 | Read data valid from data path |
| `rdata` | in | 64 | Read data |
| `rdata_id` | in | 4 | Read data transaction ID |
| `rdata_err` | in | 1 | ECC error on this read word |

---

### 3.3 `ddr4_cmd_scheduler`

Arbitrates read/write requests from the host interface into DRAM commands.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `cmd_valid` | in | 1 | New host command presented |
| `cmd_ready` | out | 1 | Ready to accept host command |
| `cmd_type` | in | 2 | READ or WRITE |
| `cmd_addr` | in | 32 | Host byte address |
| `cmd_id` | in | 4 | Transaction ID |
| `ref_req` | in | 1 | Refresh controller requests refresh |
| `ref_rank` | in | RANK_BITS | Target rank for refresh |
| `ref_bank` | in | 4 | Target bank for PBR (0 = all-bank) |
| `ref_ack` | out | 1 | Scheduler acknowledges refresh slot |
| `timing_ok` | in | 16 | Per-timing-constraint ready bits from timing engine |
| `dram_cmd_valid` | out | 1 | DRAM command to timing engine and PHY |
| `dram_cmd_type` | out | 3 | ACT/RD/WR/PRE/REF/MRS/ZQCS/ZQCL |
| `dram_rank` | out | RANK_BITS | Target rank |
| `dram_bg` | out | 2 | Target bank group |
| `dram_ba` | out | 2 | Target bank |
| `dram_row` | out | 17 | Row address (ACTIVATE) |
| `dram_col` | out | 10 | Column address (RD/WR) |
| `rd_data_req` | out | 1 | Read data expected from data path |
| `rd_data_id` | out | 4 | Transaction ID for returning read data |
| `wr_data_req` | out | 1 | Write data request to data path |
| `wr_data_id` | out | 4 | Transaction ID |

---

### 3.4 `ddr4_timing_engine`

Tracks all JEDEC-mandated timing constraints as down-counters and gates command issue.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `dram_cmd_valid` | in | 1 | Command being issued this cycle |
| `dram_cmd_type` | in | 3 | Command type (ACT/RD/WR/PRE/REF/…) |
| `dram_rank` | in | RANK_BITS | Rank being addressed |
| `dram_bg` | in | 2 | Bank group |
| `dram_ba` | in | 2 | Bank address |
| `cfg_cl` | in | 5 | CL (from top) |
| `cfg_cwl` | in | 5 | CWL (from top) |
| `cfg_trcd` | in | 8 | tRCD cycles |
| `cfg_trp` | in | 8 | tRP cycles |
| `cfg_tras` | in | 8 | tRAS cycles |
| `cfg_trc` | in | 8 | tRC cycles |
| `cfg_trfc` | in | 10 | tRFC cycles |
| `cfg_trefi` | in | 14 | tREFI cycles |
| `timing_ok` | out | 16 | Bit-per-constraint: 1 = constraint satisfied |

Constraints tracked (one counter each, per-bank or per-rank as noted):

| Bit | Constraint | Scope | Typical DDR4-3200 value |
|---|---|---|---|
| 0 | tRCD — ACT→RD/WR | per-bank | 11 nCK |
| 1 | tRP — PRE→ACT | per-bank | 11 nCK |
| 2 | tRAS — ACT→PRE (min) | per-bank | 28 nCK |
| 3 | tRC — ACT→ACT (same bank) | per-bank | 39 nCK |
| 4 | tCCD_L — RD/WR→RD/WR (same BG) | per-BG | 6 nCK |
| 5 | tCCD_S — RD/WR→RD/WR (diff BG) | per-rank | 4 nCK |
| 6 | tRRD_L — ACT→ACT (same BG) | per-BG | 6 nCK |
| 7 | tRRD_S — ACT→ACT (diff BG) | per-rank | 4 nCK |
| 8 | tWR — WR→PRE | per-bank | 15 nCK |
| 9 | tWTR_L — WR→RD (same BG) | per-BG | 12 nCK |
| 10 | tWTR_S — WR→RD (diff BG) | per-rank | 4 nCK |
| 11 | tRTP — RD→PRE | per-bank | 6 nCK |
| 12 | tFAW — rolling 4-ACT window | per-rank | 16 nCK |
| 13 | tRFC — REF→ACT | per-rank | 420 nCK (8Gb) |
| 14 | tMOD — MRS→non-MRS | per-rank | 24 nCK |
| 15 | tZQCS/tZQCL | per-rank | 64/512 nCK |

---

### 3.5 `ddr4_refresh_ctrl`

Issues periodic AUTO REFRESH (REF) or PER-BANK REFRESH (PBR) commands.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `init_done` | in | 1 | Asserted when init FSM completes |
| `cfg_trefi` | in | 14 | tREFI period in controller clock cycles |
| `cfg_fgr_mode` | in | 2 | 0=normal, 1=FGR×2, 2=FGR×4 |
| `cfg_pbr_en` | in | 1 | Per-bank refresh enable |
| `ref_req` | out | 1 | Refresh command pending |
| `ref_rank` | out | RANK_BITS | Target rank |
| `ref_bank` | out | 4 | Target bank (all-bank=0 when !cfg_pbr_en) |
| `ref_ack` | in | 1 | Scheduler acknowledged refresh |
| `sr_req` | in | 1 | Request self-refresh entry |
| `sr_active` | out | 1 | Self-refresh mode active |
| `sr_exit_req` | in | 1 | Exit self-refresh request |

---

### 3.6 `ddr4_init_fsm`

Implements the mandatory DDR4 power-up and initialization sequence (JESD79-4 §3.3).

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `start` | in | 1 | Begin initialization (tie to 1 after PLL lock) |
| `dram_cmd_valid` | out | 1 | Command output to PHY |
| `dram_cmd_type` | out | 3 | RESET / CKE-assert / MRS / ZQCL |
| `dram_rank` | out | RANK_BITS | Target rank |
| `dram_a` | out | 17 | Address (MRS data) |
| `dram_bg` | out | 2 | Bank group (MR select) |
| `dram_ba` | out | 2 | Bank (MR select) |
| `init_done` | out | 1 | All ranks initialized |

**Init FSM States:**

```
RESET_ASSERT → RESET_DEASSERT_WAIT (tPW >= 200 us)
  → CKE_ASSERT_WAIT (tXPR)
  → MRS_MR3 → MRS_MR6 → MRS_MR5 → MRS_MR4
  → MRS_MR2 → MRS_MR1 → MRS_MR0
  → ZQCL_WAIT (tZQINIT = 512 nCK)
  → INIT_DONE
```

---

### 3.7 `ddr4_mode_reg`

Shadow registers for MR0–MR6; generates MRS command payloads.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `cfg_cl` | in | 5 | CL → encodes into MR0[12,6:4,2] |
| `cfg_cwl` | in | 5 | CWL → encodes into MR2[5:3] |
| `cfg_al` | in | 2 | Additive latency (MR1[4:3]) |
| `cfg_rtt_nom` | in | 3 | RTT_NOM (MR1[10:8]) |
| `cfg_rtt_wr` | in | 3 | RTT_WR (MR2[11:9]) |
| `cfg_rtt_park` | in | 3 | RTT_PARK (MR5[8:6]) |
| `cfg_drive_strength` | in | 2 | Output driver strength (MR1[2:1]) |
| `cfg_wr_recovery` | in | 4 | WR recovery (MR0[13,11:9]) |
| `cfg_dbi_rd_en` | in | 1 | Data Bus Inversion read (MR5[12]) |
| `cfg_dbi_wr_en` | in | 1 | DBI write (MR5[11]) |
| `cfg_ca_parity_en` | in | 1 | CA parity (MR5[0]) |
| `mr_select` | in | 3 | MR number (0–6) to output |
| `mr_data` | out | 17 | MR payload for MRS command address bus |

---

### 3.8 `ddr4_data_path`

Manages read/write data flow between the host interface and PHY.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `wr_req` | in | 1 | Write data enqueue from scheduler |
| `wr_id` | in | 4 | Write transaction ID |
| `wr_data` | in | 64 | Host write data |
| `wr_strb` | in | 8 | Byte enables |
| `wr_ready` | out | 1 | Data path has space |
| `rd_data_return` | in | 72 | Raw 72-bit (64+ECC) read burst from PHY |
| `rd_data_valid_phy` | in | 1 | PHY read valid |
| `rd_id_phy` | in | 4 | Read ID tracking from scheduler |
| `rd_data_out` | out | 64 | Corrected read data to host |
| `rd_data_valid_host` | out | 1 | Host read data valid |
| `rd_data_id_host` | out | 4 | Transaction ID |
| `rd_ecc_err` | out | 1 | ECC error on this read word |
| `phy_dq_out` | out | 72 | Serialized output to PHY pads |
| `phy_dqs_oe` | out | 9 | DQS output-enable per byte lane |
| `phy_dq_oe` | out | 9 | DQ output-enable per byte lane |

---

### 3.9 `ddr4_ecc_engine`

SECDED (72,64) ECC engine; protects the 64-bit data word using 8 check bits.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `enc_data_in` | in | 64 | Uncoded write data |
| `enc_data_out` | out | 72 | ECC-encoded codeword (64 data + 8 check) |
| `dec_data_in` | in | 72 | ECC codeword from DRAM |
| `dec_data_out` | out | 64 | Corrected read data |
| `dec_single_err` | out | 1 | Single-bit error corrected |
| `dec_double_err` | out | 1 | Double-bit error detected |
| `dec_syndrome` | out | 8 | Raw syndrome bits |
| `dec_err_bit` | out | 7 | Bit position of single-bit error (0–71) |

**ECC Matrix (SECDED H-matrix):** Standard (72,64) Hamming code augmented with an overall-parity bit (P0) for double-error detection. Check bits occupy positions that are powers of 2 (bits 0, 1, 2, 4, 8, 16, 32, 64) in the 72-bit codeword. The polynomial used matches common JEDEC practice for DDR memory.

**Error Scrubbing:** The `dec_single_err` and `dec_err_bit` outputs can be routed back to the `ddr4_data_path` for in-place memory scrub (re-write corrected data). Scrub scheduling is handled by the `ddr4_cmd_scheduler` upon receiving a scrub request from the host or internally.

---

### 3.10 `ddr4_phy_iface`

Abstract PHY boundary: FPGA/ASIC I/O buffers, differential I/O, and tristate control.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk`, `rst_n` | in | 1 | Clock and reset |
| `ctrl_cmd_valid` | in | 1 | Command bus valid from controller |
| `ctrl_act_n` | in | 1 | ACT_N pin |
| `ctrl_ras_n` | in | 1 | RAS_N (A16) |
| `ctrl_cas_n` | in | 1 | CAS_N |
| `ctrl_we_n` | in | 1 | WE_N |
| `ctrl_bg` | in | 2 | Bank group |
| `ctrl_ba` | in | 2 | Bank |
| `ctrl_a` | in | 17 | Address |
| `ctrl_cs_n` | in | NUM_RANKS | Chip selects |
| `ctrl_cke` | in | NUM_RANKS | CKE |
| `ctrl_odt` | in | NUM_RANKS | ODT |
| `ctrl_reset_n` | in | 1 | DRAM RESET_N |
| `ctrl_dq_out` | in | 72 | DQ output data |
| `ctrl_dq_oe` | in | 9 | DQ output enable (per byte lane) |
| `ctrl_dqs_oe` | in | 9 | DQS output enable |
| `phy_dq_in` | out | 72 | DQ captured input from pads |
| `phy_dqs_valid` | out | 1 | DQS-aligned capture valid |

---

## 4. Timing Parameters

All timing values are expressed in **nCK** (DDR4 SDRAM clock cycles, i.e., half the data-rate period). At DDR4-3200 (tCK = 0.625 ns), one nCK = 0.625 ns.

### 4.1 Key Timing Parameters (defaults = DDR4-3200, x8, 8Gb)

| Parameter | Symbol | Default (nCK) | Min (nCK) | Max (nCK) | Notes |
|---|---|---|---|---|---|
| CAS Latency | CL | 22 | 9 | 36 | Configured in MR0 |
| CAS Write Latency | CWL | 16 | 9 | 24 | Configured in MR2 |
| ACT to RD/WR | tRCD | 11 | 5 | — | |
| PRE to ACT | tRP | 11 | 5 | — | |
| ACT to PRE | tRAS (min) | 28 | 15 | 9×tREFI | |
| ACT to ACT (same bank) | tRC | 39 | 20 | — | = tRAS + tRP |
| RD/WR to RD/WR (same BG) | tCCD_L | 6 | 5 | — | |
| RD/WR to RD/WR (diff BG) | tCCD_S | 4 | 4 | — | |
| ACT to ACT (same BG) | tRRD_L | 6 | 4 | — | |
| ACT to ACT (diff BG) | tRRD_S | 4 | 4 | — | |
| Write recovery | tWR | 15 | 10 | — | WR→PRE |
| WR→RD (same BG) | tWTR_L | 12 | 10 | — | |
| WR→RD (diff BG) | tWTR_S | 4 | 2 | — | |
| RD to PRE | tRTP | 6 | 4 | — | |
| Four-ACT window | tFAW | 16 | 13 | — | |
| Refresh interval | tREFI | 6240 | — | — | = 3.9 us at 1600 MHz |
| REF to ACT (8Gb) | tRFC | 420 | — | — | = 260 ns |
| REF to ACT (16Gb) | tRFC | 560 | — | — | = 350 ns |
| Mode Reg set time | tMOD | 24 | 24 | — | |
| ZQ calibration short | tZQCS | 64 | 64 | — | |
| ZQ calibration long | tZQCL | 512 | 512 | — | |
| DLL lock time | tDLLK | 768 | 768 | — | |
| Exit power-down | tXP | 6 | 4 | — | |
| Exit self-refresh | tXS | 432 | — | — | = tRFC + 10 nCK |

### 4.2 Refresh Modes

| Mode | tREFI effective | Description |
|---|---|---|
| Normal 1x | 6240 nCK | All-bank REF every 3.9 us (per rank) |
| Fine Granularity x2 | 3120 nCK | REF every 1.95 us |
| Fine Granularity x4 | 1560 nCK | REF every 0.975 us |
| Per-Bank Refresh | 390 nCK/bank | PBR to individual banks; covers all 16 banks in one tREFI interval |

---

## 5. Address Mapping

Physical DRAM address components are decoded from the 32-bit host byte address as follows (default; reconfigurable in `ddr4_host_iface`):

```
Byte address [31:0]:
  [31:28] → unused (must be 0)
  [27:26] → rank select  (2 bits for up to 4 ranks)
  [25:9]  → row address  (17 bits, ROW_BITS)
  [8:7]   → bank address (BA[1:0])
  [6:5]   → bank group   (BG[1:0])
  [4:3]   → column[9:8]  (upper 2 column bits)
  [12:5]  → column[7:0]  (lower 8 column bits, overlapping with BG/BA above in interleaved mode)
  [2:0]   → must be 3'b000 (BL8 forces 8-byte alignment; unaligned accesses are undefined behavior)
```

> **Note on column address:** In the default contiguous mapping the full 10-bit column address
> (`col[9:0]`) is spread across bits [4:3] (col[9:8]) and bits [12:5] (col[7:0]) of the host
> address.  Because bank group (BG) and bank (BA) are interleaved into bits [6:3], different
> mapping schemes (e.g., row-interleaved) can be selected by reconfiguring `ddr4_host_iface`
> parameters.  Bits [2:0] must always be zero; the controller ignores them and treats all
> accesses as BL8-aligned 8-byte transfers.

Exact bit assignments are controlled by `ddr4_host_iface` parameters to allow interleaved or contiguous mapping.

---

## 6. ECC Architecture Detail

### 6.1 Codeword Structure (72,64) SECDED

```
Bit position:  71..65  64  63..33  32  31..17  16  15..9  8  7..5  4  3  2  1  0
Type:            D     P64   D    P32    D     P16    D   P8   D   P4  D  P2 P1 P0
```

- **P0** (bit 0): overall parity of all 72 bits — augments Hamming code to SECDED
- **P1** (bit 1): parity over all positions where bit[0]=1
- **P2** (bit 2): parity over all positions where bit[1]=1
- **P4** (bit 4): parity over all positions where bit[2]=1
- **P8** (bit 8): parity over all positions where bit[3]=1
- **P16** (bit 16): parity over all positions where bit[4]=1
- **P32** (bit 32): parity over all positions where bit[5]=1
- **P64** (bit 64): parity over all positions where bit[6]=1

### 6.2 Error Classification

| Syndrome [7:1] | P0 (bit 0) | Interpretation |
|---|---|---|
| 7'b0000000 | 0 | No error |
| Non-zero | 1 | Single-bit error; corrected bit = syndrome[7:1] |
| Non-zero | 0 | Double-bit error (uncorrectable; raise interrupt) |

### 6.3 Error Logging

The `ddr4_ecc_engine` drives `dec_single_err` and `dec_double_err` pulses for one clock cycle. The `ddr4_ctrl_top` latches:

- Address of the errored transaction → `ecc_err_addr`
- Syndrome → `ecc_err_syndrome`
- Type flags → `ecc_single_err`, `ecc_double_err`

These are sticky bits; cleared by asserting `cfg_ecc_clr` for one cycle.

---

## 7. Command Encoding

Internal 3-bit command type used throughout the controller:

| `cmd_type[2:0]` | Command | DDR4 Pins |
|---|---|---|
| 3'b000 | NOP | ACT_N=1, CS_N=1 |
| 3'b001 | ACTIVATE (ACT) | ACT_N=0, A[16:0]=row |
| 3'b010 | READ (RD) | ACT_N=1, CAS_N=0, WE_N=1, A[10]=AP |
| 3'b011 | WRITE (WR) | ACT_N=1, CAS_N=0, WE_N=0, A[10]=AP |
| 3'b100 | PRECHARGE (PRE) | ACT_N=1, RAS_N=0, CAS_N=1, WE_N=0, A[10]=AP-all |
| 3'b101 | AUTO REFRESH (REF) | ACT_N=1, RAS_N=0, CAS_N=0, WE_N=1 |
| 3'b110 | MODE REG SET (MRS) | ACT_N=1, RAS_N=0, CAS_N=0, WE_N=0, BA/BG/A=MR |
| 3'b111 | ZQ CALIBRATE (ZQCS/ZQCL) | ACT_N=1, RAS_N=1, CAS_N=1, WE_N=0, A[10]=0/1 |

---

## 8. RTL Parameters

All modules accept the following Verilog parameters for configurability:

| Parameter | Default | Description |
|---|---|---|
| `NUM_RANKS` | 1 | Number of DRAM ranks (1–4) |
| `ROW_BITS` | 17 | Row address width |
| `COL_BITS` | 10 | Column address width |
| `BG_BITS` | 2 | Bank group bits (2 for DDR4) |
| `BA_BITS` | 2 | Bank address bits |
| `DQ_WIDTH` | 72 | DQ bus width including ECC byte |
| `AXI_DATA_WIDTH` | 64 | AXI4 data bus width |
| `AXI_ADDR_WIDTH` | 32 | AXI4 address width |
| `AXI_ID_WIDTH` | 4 | AXI4 ID width |
| `CMD_QUEUE_DEPTH` | 8 | Command queue depth per rank |
| `DEFAULT_CL` | 22 | Default CAS Latency in nCK |
| `DEFAULT_CWL` | 16 | Default CAS Write Latency in nCK |
| `DEFAULT_TRCD` | 11 | Default tRCD in nCK |
| `DEFAULT_TRP` | 11 | Default tRP in nCK |
| `DEFAULT_TRAS` | 28 | Default tRAS in nCK |
| `DEFAULT_TRC` | 39 | Default tRC in nCK |
| `DEFAULT_TRFC` | 420 | Default tRFC in nCK (8Gb) |
| `DEFAULT_TREFI` | 6240 | Default tREFI in nCK |

---

## 9. Block Diagram (Signal-Level)

```
                        +------------------------------------------------+
  HOST (CPU/PCIe)       |              ddr4_ctrl_top                     |
  ─────────────         |                                                |
  AXI4 R/W ──────────> | +───────────────+   cmd + data                |
                        | |ddr4_host_iface|──────────────────+          |
  init_done <─────────  | +───────────────+                  v          |
  ecc_single_err <────  |                          +──────────────────+ |
  ecc_double_err <────  |                          |ddr4_cmd_scheduler| |
  ecc_err_addr <──────  |  +────────────────+      |  (bank FSMs,     | |
  cfg_* ──────────────> |  |ddr4_refresh_ctrl|─ref─|   arbitration)   | |
                        |  +────────────────+      +────────+─────────+ |
                        |                                   | DRAM cmds |
                        |  +────────────────+               v           |
                        |  |ddr4_init_fsm   |─init─> +────────────────+|
                        |  +────────────────+        |ddr4_timing_    ||
                        |                            |engine          ||
                        |  +────────────────+        +────────+───────+|
                        |  |ddr4_mode_reg   |─MRS─────────────+        |
                        |  +────────────────+                           |
                        |                           +────────────────+  |
                        |  +────────────────+       |ddr4_data_path  |  |
                        |  |ddr4_ecc_engine |<─────>|  (FIFOs,       |  |
                        |  +────────────────+       |   serialize)   |  |
                        |                           +────────+───────+  |
                        |                                    |          |
                        |                          +─────────v────────+ |
                        |                          | ddr4_phy_iface   | |
                        |                          | (I/O buffers,    | |
                        |                          |  diff. drivers)  | |
                        |                          +─────────+────────+ |
                        +────────────────────────────────────+-----------+
                                                             |
                                          DDR4 DRAM Devices (x8 x9)
                                          CK, CKE, CS_N, ACT_N, RAS/CAS/WE,
                                          BG[1:0], BA[1:0], A[16:0],
                                          DQ[71:0], DQS[8:0], DM_DBI[8:0]
```

---

## 10. Notes, Assumptions, and Standard References

1. **JEDEC Standard**: This design targets JEDEC Standard No. 79-4D (DDR4 SDRAM).
   - Public summary page (JESD79-4B): https://www.jedec.org/standards-documents/docs/jesd79-4b
   - JESD79-4D is the latest revision and supersedes JESD79-4B. It is available to JEDEC members or by purchase at https://www.jedec.org/. Implementation is based on publicly available JEDEC summaries and DDR4 component datasheets.

2. **Clock domain**: A single controller clock `clk` is used throughout. The PHY layer is responsible for generating the DDR4 differential clock and performing the clock-domain crossing to the high-speed DDR4 data rate. The RTL models the controller at 1/8 data rate (DFI-like).

3. **Reset**: All flip-flops use active-low synchronous reset (`rst_n`). DRAM `RESET_N` is driven low during power-up and deasserted by `ddr4_init_fsm`.

4. **ECC**: The (72,64) SECDED code is a standard Hamming code variant widely used in server DRAM (JEDEC SPD byte 13 = ECC). No ChipKill or advanced multi-bit ECC is implemented in this version.

5. **Rank interleaving**: `ddr4_cmd_scheduler` implements simple round-robin rank interleaving to hide tRFC latency across ranks.

6. **PHY abstraction**: `ddr4_phy_iface` is an abstract placeholder. For FPGA targets, this would be replaced with Xilinx MIG or Intel EMIF IP. For ASIC, a custom PHY with DLL and I/O cells would be inserted.

7. **Self-refresh**: Supported via `sr_req`/`sr_active`/`sr_exit_req` signals. The `ddr4_refresh_ctrl` module manages CKE gating and the tCKESR/tXS timing.

8. **Write DBI**: Data Bus Inversion (write and read) is supported in mode registers but the PHY inversion logic is reserved for future implementation.

9. **CA Parity**: Command/Address parity (MR5) is configurable but parity generation/checking is not implemented in the RTL controller path in Phase 1.

10. **Simulation**: The RTL targets Icarus Verilog (`iverilog -g2012`). No proprietary simulation features are used. VCD waveform output is enabled in testbenches via `$dumpfile`/`$dumpvars`.
