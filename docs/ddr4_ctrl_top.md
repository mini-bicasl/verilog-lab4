# `ddr4_ctrl_top` — Top-Level DDR4 Controller Wrapper

## Overview

`ddr4_ctrl_top` is the top-level integration module for the DDR4 SDRAM
controller. It instantiates and wires together all sub-modules:

| Sub-module | Role |
|------------|------|
| `ddr4_host_iface` | AXI4 slave → internal command/data bus |
| `ddr4_cmd_scheduler` | Per-bank open/closed-page FSM, command arbitration |
| `ddr4_timing_engine` | JEDEC timing constraint down-counters |
| `ddr4_refresh_ctrl` | tREFI countdown, FGR, PBR, self-refresh |
| `ddr4_init_fsm` | Power-up and MRS/ZQCL initialization sequence |
| `ddr4_mode_reg` | MR0–MR6 shadow registers and MRS payload encoder |
| `ddr4_data_path` | Read/write FIFOs + ECC engine integration |
| `ddr4_phy_iface` | Abstract PHY layer / DDR4 pad drivers |

**Source files:**
- RTL: `rtl/ddr4_ctrl_top.v`
- Testbench: `tb/ddr4_ctrl_top_tb.v`

---

## Top-Level Port Table

### Clock / Reset

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `clk` | in | 1 | Controller clock |
| `rst_n` | in | 1 | Active-low synchronous reset |

### AXI4 Host Interface (slave)

*(same signals as documented in `docs/ddr4_host_iface.md`)*

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `s_axi_aw*` | in | — | Write address channel |
| `s_axi_w*` | in | — | Write data channel |
| `s_axi_b*` | out | — | Write response channel |
| `s_axi_ar*` | in | — | Read address channel |
| `s_axi_r*` | out | — | Read data channel |

### DDR4 Physical Interface

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `ddr4_ck_t` | out | `NUM_RANKS` | Differential clock true |
| `ddr4_ck_c` | out | `NUM_RANKS` | Differential clock complement |
| `ddr4_cke` | out | `NUM_RANKS` | Clock enable |
| `ddr4_cs_n` | out | `NUM_RANKS` | Chip select (active-low) |
| `ddr4_act_n` | out | 1 | Activate command |
| `ddr4_ras_n` | out | 1 | RAS_N |
| `ddr4_cas_n` | out | 1 | CAS_N |
| `ddr4_we_n` | out | 1 | WE_N |
| `ddr4_bg` | out | 2 | Bank group |
| `ddr4_ba` | out | 2 | Bank address |
| `ddr4_a` | out | 17 | Address bus |
| `ddr4_odt` | out | `NUM_RANKS` | On-die termination |
| `ddr4_reset_n` | out | 1 | DRAM RESET_N |
| `ddr4_dq_out` | out | 72 | DQ write data |
| `ddr4_dq_in` | in | 72 | DQ read data from DRAM |
| `ddr4_dqs_t` | out | 9 | DQS true strobe |
| `ddr4_dqs_c` | out | 9 | DQS complement strobe |
| `ddr4_dm_dbi_n` | out | 9 | Data mask / DBI |

### Status and Control

| Signal | Dir | Width | Description |
|--------|-----|-------|-------------|
| `init_done` | out | 1 | Initialization complete |
| `ecc_single_err` | out | 1 | Sticky: single-bit ECC error detected |
| `ecc_double_err` | out | 1 | Sticky: double-bit ECC error detected |
| `ecc_err_addr` | out | 32 | Address of last ECC error |
| `ecc_err_syndrome` | out | 8 | Syndrome of last ECC error |
| `ref_in_progress` | out | 1 | Refresh request pending |
| `cfg_timing_base` | in | 1 | 0 = internal defaults, 1 = use `cfg_*` |
| `cfg_cl` | in | 5 | CAS Latency override |
| `cfg_cwl` | in | 5 | CAS Write Latency override |
| `cfg_trcd` | in | 8 | tRCD override (nCK) |
| `cfg_trp` | in | 8 | tRP override |
| `cfg_tras` | in | 8 | tRAS override |
| `cfg_trc` | in | 8 | tRC override |
| `cfg_trfc` | in | 10 | tRFC override |
| `cfg_trefi` | in | 14 | tREFI override |
| `cfg_fgr_mode` | in | 2 | 2'b00=normal, 2'b01=FGR×2, 2'b10=FGR×4 |
| `cfg_pbr_en` | in | 1 | Per-bank refresh enable |
| `cfg_ecc_clr` | in | 1 | Pulse to clear sticky ECC error flags |
| `sr_req` | in | 1 | Request self-refresh entry |
| `sr_active` | out | 1 | Self-refresh mode active |
| `sr_exit_req` | in | 1 | Request self-refresh exit |

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_RANKS` | 1 | Number of DRAM ranks |
| `ROW_BITS` | 17 | Row address width |
| `COL_BITS` | 10 | Column address width |
| `DQ_WIDTH` | 72 | DQ bus width |
| `AXI_DATA_WIDTH` | 64 | AXI4 data width |
| `AXI_ADDR_WIDTH` | 32 | AXI4 address width |
| `AXI_ID_WIDTH` | 4 | AXI4 ID width |
| `INIT_RESET_WAIT` | 10 | Reset hold cycles in init FSM |
| `INIT_ZQCL_WAIT` | 10 | ZQCL wait cycles in init FSM |

---

## Integration Diagram

```
AXI4 Master
   │  AW/W/B channels (write)
   │  AR/R channels (read)
   ▼
ddr4_host_iface
   │  cmd_valid/cmd_ready/cmd_type/cmd_addr/cmd_id
   │  wdata_valid/wdata/wdata_strb
   ▼
ddr4_cmd_scheduler ◄── ref_req/ref_rank/ref_bank ── ddr4_refresh_ctrl
   │  dram_cmd_valid/type/rank/bg/ba/row/col            ▲
   │  rd_data_req/id, wr_data_req/id              init_done
   ▼                                                    │
Command MUX ◄─────────────────────── ddr4_init_fsm ── ddr4_mode_reg
(init priority)
   │
   ▼
ddr4_timing_engine ── timing_ok[15:0] ──► ddr4_cmd_scheduler
   │  (mux_cmd_valid passthrough)
   │
   ▼
ddr4_phy_iface (command + CK + CKE + CS_N → DRAM pads)
   ▲
ddr4_data_path ── phy_dq_out/dqs_oe/dq_oe
   ▲                    │
   │                    ▼
ddr4_ecc_engine    ddr4_phy_iface ── ddr4_dq_in ── DRAM
(inside data_path)
```

---

## Configuration

### `cfg_timing_base` Mux

When `cfg_timing_base=0`, all timing parameters passed to `ddr4_timing_engine`
and `ddr4_refresh_ctrl` are zero, causing those modules to fall back on their
hard-coded JEDEC defaults (DDR4-3200, 8Gb).

When `cfg_timing_base=1`, the `cfg_cl`, `cfg_trcd`, `cfg_trefi`, etc. inputs
are forwarded directly to the sub-modules, allowing runtime reconfiguration.

### ECC Sticky Error Registers

`ddr4_ctrl_top` latches ECC error events in sticky registers:

- `ecc_single_err` is set whenever `rd_ecc_err=1` from the data path.
- The `ecc_err_addr` register is updated with the last faulting host address.
- All sticky registers are cleared by asserting `cfg_ecc_clr` for one cycle.

### Command Priority

During initialization (`init_done=0`), the `ddr4_init_fsm` commands take
priority over the scheduler on the DRAM command bus. After `init_done=1`, the
`ddr4_cmd_scheduler` controls the command bus.

---

## DDR4 Pin Encoding

The ctrl_top decodes the internal 3-bit command type to DDR4 pin levels:

| Internal `cmd_type` | Command | `act_n` | `ras_n` | `cas_n` | `we_n` |
|---------------------|---------|---------|---------|---------|--------|
| 3'd0 | NOP | 1 | 1 | 1 | 1 (CS_N=1) |
| 3'd1 | MRS | 1 | 0 | 0 | 0 |
| 3'd2 | REF | 1 | 0 | 0 | 1 |
| 3'd3 | PRE | 1 | 0 | 1 | 0 |
| 3'd4 | ACT | 0 | 1 | 1 | 1 |
| 3'd5 | WR  | 1 | 1 | 0 | 0 |
| 3'd6 | RD  | 1 | 1 | 0 | 1 |
| 3'd7 | ZQCL | 1 | 1 | 1 | 0 |

---

## Reset Behavior

All registered outputs (AXI channels, command bus, DRAM pads) are cleared on
active-low `rst_n` assertion. The `ddr4_init_fsm` begins its initialization
sequence immediately when `rst_n` deasserts (since `start` is tied to 1'b1).
`init_done` asserts after the full power-up sequence completes.
