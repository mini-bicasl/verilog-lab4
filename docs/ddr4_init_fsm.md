# ddr4_init_fsm — DDR4 Initialization FSM

## Overview

Implements the DDR4 power-up and initialization sequence per JESD79-4 §3.3. Controls RESET_N assertion, CKE assertion, MRS sequence (MR3→MR6→MR5→MR4→MR2→MR1→MR0), ZQCL calibration, and asserts `init_done` when complete.

This module is the first to activate in the control path; `init_done` gates all other subsystems.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `start` | in | 1 | Begin initialization sequence |
| `dram_cmd_valid` | out | 1 | DRAM command valid |
| `dram_cmd_type` | out | 3 | Command type (0=NOP,1=MRS,7=ZQCL) |
| `dram_rank` | out | 2 | Target rank (always 0 during init) |
| `dram_a` | out | 17 | Address bus (MRS payload) |
| `dram_bg` | out | 2 | Bank group — encodes MR[2] |
| `dram_ba` | out | 2 | Bank address — encodes MR[1:0] |
| `mr_select` | out | 3 | MR number being programmed (0–6) |
| `mr_data` | in | 17 | MRS payload from `ddr4_mode_reg` |
| `init_done` | out | 1 | Initialization complete (sticky) |

## FSM States

```
IDLE ─(start)──► RESET_ASSERT (10cy)
                      │
                 RESET_DEASSERT (10cy)
                      │
                 CKE_ASSERT (10cy)
                      │
                 MRS_MR3 → MRS_MR6 → MRS_MR5 → MRS_MR4 → MRS_MR2 → MRS_MR1 → MRS_MR0
                      │
                 ZQCL_WAIT (10cy)
                      │
                 INIT_DONE ── (sticky)
```

## Timing Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RESET_WAIT` | 10 | Wait cycles for RESET_N and CKE phases (sim compressed) |
| `ZQCL_WAIT_CYCLES` | 10 | Wait cycles after ZQCL calibration |

## Related Files

- RTL: `rtl/ddr4_init_fsm.v`
- Testbench: `tb/ddr4_init_fsm_tb.v`
- Connects to: `ddr4_mode_reg` (mr_data input), `ddr4_cmd_scheduler` (gated by init_done)
