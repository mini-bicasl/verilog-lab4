# ddr4_refresh_ctrl — DDR4 Refresh Controller

## Overview

Manages the tREFI countdown and generates `ref_req` to the command scheduler. Supports three refresh modes: normal (1x), Fine Granularity Refresh ×2 (FGRx2), and FGRx4. Supports Per-Bank Refresh (PBR) with 16-bank rotation. Handles self-refresh entry and exit.

## Interface

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| `init_done` | in | 1 | From `ddr4_init_fsm`; enables refresh |
| `cfg_trefi` | in | 14 | Refresh interval in clock cycles |
| `cfg_fgr_mode` | in | 2 | 0=normal, 1=FGRx2, 2=FGRx4 |
| `cfg_pbr_en` | in | 1 | Enable per-bank refresh rotation |
| `ref_req` | out | 1 | Refresh request to scheduler |
| `ref_rank` | out | 2 | Target rank for refresh (always 0 for single-rank) |
| `ref_bank` | out | 4 | Target bank (0 unless PBR enabled) |
| `ref_ack` | in | 1 | Acknowledge from scheduler (clears ref_req) |
| `sr_req` | in | 1 | Request self-refresh entry |
| `sr_active` | out | 1 | Self-refresh active |
| `sr_exit_req` | in | 1 | Request self-refresh exit |

## Logic Description

### Refresh Generation

- `init_done` enables the refresh counter.
- Effective period = `cfg_trefi >> cfg_fgr_mode` (FGR divides interval).
- On counter expiry, `ref_req` asserts.
- `ref_req` deasserts when `ref_ack` is received; counter reloads.
- PBR: `ref_bank` increments (mod 16) on each acknowledged refresh.

### Self-Refresh

```
sr_req ──► sr_active=1 → refresh suppressed, ref_req held low
sr_exit_req ──► sr_active=0 → refresh resumes
```

## FGR Mode Comparison

| Mode | `cfg_fgr_mode` | Effective tREFI |
|------|----------------|-----------------|
| Normal | 0 | cfg_trefi |
| FGRx2 | 1 | cfg_trefi / 2 |
| FGRx4 | 2 | cfg_trefi / 4 |

## Related Files

- RTL: `rtl/ddr4_refresh_ctrl.v`
- Testbench: `tb/ddr4_refresh_ctrl_tb.v`
- Consumer: `ddr4_cmd_scheduler` receives `ref_req`/`ref_rank`/`ref_bank`
