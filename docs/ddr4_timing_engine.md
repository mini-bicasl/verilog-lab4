# ddr4_timing_engine — JEDEC DDR4 Timing Constraint Engine

## Overview

Implements per-bank and per-rank down-counters for all 16 JEDEC DDR4 timing constraints. Each counter is loaded when a qualifying command arrives; `timing_ok[i]` is 1 when counter `i` is zero (constraint satisfied). Feeds into `ddr4_cmd_scheduler` to gate command issue.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `dram_cmd_valid` | in | 1 | Incoming command valid |
| `dram_cmd_type` | in | 3 | Command type (0=NOP,1=MRS,2=REF,3=PRE,4=ACT,5=WR,6=RD,7=ZQCL) |
| `dram_rank` | in | 2 | Target rank |
| `dram_bg` | in | 2 | Bank group |
| `dram_ba` | in | 2 | Bank address |
| `cfg_cl` | in | 5 | CAS latency |
| `cfg_cwl` | in | 5 | CAS write latency |
| `cfg_trcd` | in | 8 | tRCD override (0 = use default) |
| `cfg_trp` | in | 8 | tRP override |
| `cfg_tras` | in | 8 | tRAS override |
| `cfg_trc` | in | 8 | tRC override |
| `cfg_trfc` | in | 10 | tRFC override |
| `cfg_trefi` | in | 14 | tREFI period (unused by this module, for completeness) |
| `timing_ok` | out | 16 | Constraint-satisfied bitmask |

## timing_ok Bit Assignments

| Bit | Constraint | Loaded by | Scope |
|-----|-----------|-----------|-------|
| 0 | tRCD | ACT | Per-bank |
| 1 | tRP | PRE | Per-bank |
| 2 | tRAS | ACT | Per-bank |
| 3 | tRC | ACT | Per-bank |
| 4 | tCCD_L | RD/WR | Rank |
| 5 | tCCD_S | RD/WR | Rank |
| 6 | tRRD_L | ACT | Rank |
| 7 | tRRD_S | ACT | Rank |
| 8 | tWR | WR | Per-bank |
| 9 | tWTR_L | WR | Rank |
| 10 | tWTR_S | WR | Rank |
| 11 | tRTP | RD | Per-bank |
| 12 | tFAW | ACT | Rank |
| 13 | tRFC | REF | Rank |
| 14 | tMOD | MRS | Rank |
| 15 | tZQ | ZQCL | Rank |

## Default Timing Parameters

| Parameter | Default (cycles) |
|-----------|-----------------|
| tRCD | 11 |
| tRP | 11 |
| tRAS | 28 |
| tRC | 39 |
| tCCD_L | 6 |
| tCCD_S | 4 |
| tRRD_L | 6 |
| tRRD_S | 4 |
| tWR | 15 |
| tWTR_L | 12 |
| tWTR_S | 4 |
| tRTP | 6 |
| tFAW | 16 |
| tRFC | 420 |
| tMOD | 24 |
| tZQ | 64 |

## Related Files

- RTL: `rtl/ddr4_timing_engine.v`
- Testbench: `tb/ddr4_timing_engine_tb.v`
- Consumer: `ddr4_cmd_scheduler` uses `timing_ok` to gate command issue
