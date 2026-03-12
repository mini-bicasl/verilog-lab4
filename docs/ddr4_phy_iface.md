# `ddr4_phy_iface` — Abstract PHY Interface

## Overview

`ddr4_phy_iface` is an abstract behavioural model of the DDR4 SDRAM physical
layer boundary. It bridges the controller's registered command and data buses to
the differential DDR4 SDRAM pad ring. In a production implementation, this
module would be replaced by a vendor-specific PHY IP (Xilinx MIG, Intel EMIF,
or a custom ASIC PHY with DLL and IO cells). The abstract model is sufficient
for functional RTL simulation with Icarus Verilog.

**Source files:**
- RTL: `rtl/ddr4_phy_iface.v`
- Testbench: `tb/ddr4_phy_iface_tb.v`

---

## Interface (Port Table)

### Controller-Side Inputs

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | in | 1 | Controller clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `ctrl_cmd_valid` | in | 1 | Command bus valid |
| `ctrl_act_n` | in | 1 | ACT_N DDR4 pin value |
| `ctrl_ras_n` | in | 1 | RAS_N (A16) DDR4 pin value |
| `ctrl_cas_n` | in | 1 | CAS_N DDR4 pin value |
| `ctrl_we_n` | in | 1 | WE_N DDR4 pin value |
| `ctrl_bg` | in | 2 | Bank group select |
| `ctrl_ba` | in | 2 | Bank address |
| `ctrl_a` | in | 17 | Address bus (row/column/MR payload) |
| `ctrl_cs_n` | in | `NUM_RANKS` | Chip select per rank (active-low) |
| `ctrl_cke` | in | `NUM_RANKS` | Clock enable per rank |
| `ctrl_odt` | in | `NUM_RANKS` | On-die termination control |
| `ctrl_reset_n` | in | 1 | DRAM RESET_N |
| `ctrl_dq_out` | in | `DQ_WIDTH` | DQ output data |
| `ctrl_dq_oe` | in | `DQS_WIDTH` | DQ output-enable per byte lane |
| `ctrl_dqs_oe` | in | `DQS_WIDTH` | DQS output-enable per byte lane |

### Controller-Side Outputs (Captured Data)

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `phy_dq_in` | out | `DQ_WIDTH` | DQ captured from DRAM pads |
| `phy_dqs_valid` | out | 1 | 1 = captured `phy_dq_in` is valid this cycle |

### DDR4 SDRAM Pad Interface

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `ddr4_ck_t` | out (wire) | `NUM_RANKS` | Differential clock true |
| `ddr4_ck_c` | out (wire) | `NUM_RANKS` | Differential clock complement |
| `ddr4_cke` | out (reg) | `NUM_RANKS` | Clock enable |
| `ddr4_cs_n` | out (reg) | `NUM_RANKS` | Chip select (active-low) |
| `ddr4_act_n` | out (reg) | 1 | ACT_N command pin |
| `ddr4_ras_n` | out (reg) | 1 | RAS_N pin |
| `ddr4_cas_n` | out (reg) | 1 | CAS_N pin |
| `ddr4_we_n` | out (reg) | 1 | WE_N pin |
| `ddr4_bg` | out (reg) | 2 | Bank group |
| `ddr4_ba` | out (reg) | 2 | Bank address |
| `ddr4_a` | out (reg) | 17 | Row/column/MR address |
| `ddr4_odt` | out (reg) | `NUM_RANKS` | ODT control |
| `ddr4_reset_n` | out (reg) | 1 | DRAM RESET_N |
| `ddr4_dq_out` | out (reg) | `DQ_WIDTH` | DQ output (write data) |
| `ddr4_dq_in` | in | `DQ_WIDTH` | DQ input (read data from DRAM) |
| `ddr4_dqs_t` | out (reg) | `DQS_WIDTH` | DQS true strobe |
| `ddr4_dqs_c` | out (reg) | `DQS_WIDTH` | DQS complement strobe |
| `ddr4_dm_dbi_n` | out (reg) | `DQS_WIDTH` | Data mask / DBI (tied high, DBI disabled) |

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_RANKS` | 1 | Number of DRAM ranks (1–4) |
| `DQ_WIDTH` | 72 | DQ bus width (64 data + 8 ECC) |
| `DQS_WIDTH` | 9 | DQS lanes (one per byte lane) |

---

## Functional Description

### Clock Forwarding (CK_T / CK_C)

The differential DDR4 clock is generated combinatorially:

```
ddr4_ck_t = rst_n ? {NUM_RANKS{clk}} : 0
ddr4_ck_c = rst_n ? {NUM_RANKS{~clk}} : 1
```

This produces a DDR4 differential clock that matches the controller clock
frequency. A production PHY would typically generate the high-speed DDR4
clock with a PLL/DLL running at ×8 the controller rate.

### Command / Address Pipeline

The command and address pins are registered in a one-cycle pipeline stage
aligned with `posedge clk`:

- When `ctrl_cmd_valid=1`, the command pins (`cs_n`, `act_n`, `ras_n`, `cas_n`,
  `we_n`, `bg`, `ba`, `a`) are driven with the provided values.
- When `ctrl_cmd_valid=0`, a NOP is issued: all rank CS_N are deasserted (1).
- `cke`, `odt`, and `reset_n` track their control inputs continuously.

### DQ Write Path

When `ctrl_dq_oe[b]=1` for byte lane `b`, the corresponding 8-bit DQ slice
(`ddr4_dq_out[b*8+:8]`) is driven from `ctrl_dq_out[b*8+:8]`. When `oe=0`,
the output is placed in high-impedance (tri-state model).

DQS differential strobes toggle with `clk` when `ctrl_dqs_oe[b]=1` (write
burst), and are tri-stated when `ctrl_dqs_oe=0` (read mode or idle).

### DQ Read Path (Capture)

In this abstract model, `phy_dqs_valid` is asserted each clock cycle that
`ctrl_dqs_oe=0` (not in write mode), and `phy_dq_in` is updated from
`ddr4_dq_in`. The controller-level data path (`ddr4_data_path`) should gate
read data consumption on the scheduler's `rd_data_req` signal rather than
relying on continuous `phy_dqs_valid` assertion.

In a real PHY, `phy_dqs_valid` would be gated by actual DQS edge detection
and a CL-latency shift register, ensuring data is only presented after a
READ command + CAS Latency cycles.

---

## Timing Diagram (Abstract Model)

```
          ____    ____    ____    ____
clk   ___|    |__|    |__|    |__|    |__
             ↑              ↑
       ctrl_cmd_valid=1  ctrl_cmd_valid=0
       cmd registered    NOP on pads

ddr4_ck_t  ___/‾‾‾\___/‾‾‾\___   (follows clk)
ddr4_ck_c  ‾‾‾\___/‾‾‾\___/‾‾‾   (complement)
```
