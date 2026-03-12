# ddr4_cmd_scheduler — DDR4 Command Scheduler

## Overview

Implements a single-bank open/closed-page FSM with command queuing and refresh arbitration. Accepts host READ/WRITE commands, decodes addresses to rank/row/bank/column, and issues the correct DRAM command sequence (ACT→RD/WR→PRE) while respecting timing constraints from `ddr4_timing_engine`. Handles refresh preemption via `ref_req`/`ref_ack`.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `cmd_valid` | in | 1 | Host command valid |
| `cmd_ready` | out | 1 | Scheduler ready to accept command |
| `cmd_type` | in | 2 | 0=READ, 1=WRITE |
| `cmd_addr` | in | 32 | Host byte address |
| `cmd_id` | in | 4 | Transaction ID |
| `ref_req` | in | 1 | Refresh request from `ddr4_refresh_ctrl` |
| `ref_rank` | in | 2 | Refresh target rank |
| `ref_bank` | in | 4 | Refresh target bank |
| `ref_ack` | out | 1 | Refresh acknowledged |
| `timing_ok` | in | 16 | Constraint-satisfied bitmask from timing engine |
| `dram_cmd_valid` | out | 1 | DRAM command valid |
| `dram_cmd_type` | out | 3 | DRAM command type |
| `dram_rank` | out | 2 | DRAM rank |
| `dram_bg` | out | 2 | DRAM bank group |
| `dram_ba` | out | 2 | DRAM bank address |
| `dram_row` | out | 17 | DRAM row address |
| `dram_col` | out | 10 | DRAM column address |
| `rd_data_req` | out | 1 | Read data request pulse |
| `rd_data_id` | out | 4 | Read transaction ID |
| `wr_data_req` | out | 1 | Write data request pulse |
| `wr_data_id` | out | 4 | Write transaction ID |

## Address Decode

```
rank = addr[27:26]
row  = addr[25:9]
ba   = addr[8:7]
bg   = addr[6:5]
col  = {addr[4:3], addr[12:5]}  (10 bits)
```

## Bank FSM

```
IDLE ─(cmd+timing_ok[tRP,tRRD_S,tFAW])──► ACTIVATING ─(tRCD ok)──► ACTIVE
                                                                         │
                               ┌─────(WR cmd)──────────────────── WRITING
                               │                                        │
                               └─────(RD cmd)──────────────────── READING
                                                                        │
                                          PRECHARGING ◄────────────────┘
                                               │
                                             IDLE
```

Refresh preemption: while in IDLE, if `ref_req` is asserted and `timing_ok[tRP]` is met, the scheduler issues REF and asserts `ref_ack`.

## Arbitration Policy

Refresh has priority over pending host commands in the IDLE state.

## Related Files

- RTL: `rtl/ddr4_cmd_scheduler.v`
- Testbench: `tb/ddr4_cmd_scheduler_tb.v`
- Depends on: `ddr4_timing_engine` (timing_ok), `ddr4_refresh_ctrl` (ref_req)
