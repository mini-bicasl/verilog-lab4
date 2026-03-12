# `ddr4_host_iface` — AXI4 Host Interface

## Overview

`ddr4_host_iface` is an AXI4 slave that converts AXI4 read and write transactions
from the host CPU/PCIe fabric into the controller's internal command and data
request signals. It bridges the standard AXI4 protocol to the flat
`cmd_valid`/`cmd_ready` command bus consumed by `ddr4_cmd_scheduler`.

**Source files:**
- RTL: `rtl/ddr4_host_iface.v`
- Testbench: `tb/ddr4_host_iface_tb.v`

---

## Interface (Port Table)

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | in | 1 | Controller clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| **AXI4 Write Address** | | | |
| `s_axi_awid` | in | `AXI_ID_WIDTH` | Write address ID |
| `s_axi_awaddr` | in | `AXI_ADDR_WIDTH` | Write byte address |
| `s_axi_awlen` | in | 8 | Burst length − 1 |
| `s_axi_awsize` | in | 3 | Transfer size (must be 3'b011 = 8 bytes) |
| `s_axi_awburst` | in | 2 | Burst type (INCR = 2'b01) |
| `s_axi_awvalid` | in | 1 | Write address valid |
| `s_axi_awready` | out | 1 | Write address ready |
| **AXI4 Write Data** | | | |
| `s_axi_wdata` | in | 64 | Write data |
| `s_axi_wstrb` | in | 8 | Write byte strobes |
| `s_axi_wlast` | in | 1 | Write last beat flag |
| `s_axi_wvalid` | in | 1 | Write data valid |
| `s_axi_wready` | out | 1 | Write data ready |
| **AXI4 Write Response** | | | |
| `s_axi_bid` | out | `AXI_ID_WIDTH` | Write response ID |
| `s_axi_bresp` | out | 2 | Write response (OKAY/SLVERR) |
| `s_axi_bvalid` | out | 1 | Write response valid |
| `s_axi_bready` | in | 1 | Write response ready |
| **AXI4 Read Address** | | | |
| `s_axi_arid` | in | `AXI_ID_WIDTH` | Read address ID |
| `s_axi_araddr` | in | `AXI_ADDR_WIDTH` | Read byte address |
| `s_axi_arlen` | in | 8 | Burst length − 1 |
| `s_axi_arsize` | in | 3 | Transfer size |
| `s_axi_arburst` | in | 2 | Burst type |
| `s_axi_arvalid` | in | 1 | Read address valid |
| `s_axi_arready` | out | 1 | Read address ready |
| **AXI4 Read Data** | | | |
| `s_axi_rid` | out | `AXI_ID_WIDTH` | Read data ID |
| `s_axi_rdata` | out | 64 | Read data |
| `s_axi_rresp` | out | 2 | Read response |
| `s_axi_rlast` | out | 1 | Read last beat |
| `s_axi_rvalid` | out | 1 | Read data valid |
| `s_axi_rready` | in | 1 | Read data ready |
| **Internal Command Interface** | | | |
| `cmd_valid` | out | 1 | Command valid to scheduler |
| `cmd_ready` | in | 1 | Scheduler ready to accept |
| `cmd_type` | out | 2 | 2'b00=READ, 2'b01=WRITE |
| `cmd_addr` | out | `AXI_ADDR_WIDTH` | Host byte address |
| `cmd_id` | out | `AXI_ID_WIDTH` | Transaction ID |
| **Write Data Path** | | | |
| `wdata_valid` | out | 1 | Write data presented to data path |
| `wdata_ready` | in | 1 | Data path ready to accept |
| `wdata` | out | 64 | Write data word |
| `wdata_strb` | out | 8 | Write byte strobes |
| **Read Data Return** | | | |
| `rdata_valid` | in | 1 | Read data available from data path |
| `rdata` | in | 64 | Corrected read data |
| `rdata_id` | in | `AXI_ID_WIDTH` | Read transaction ID |
| `rdata_err` | in | 1 | ECC error on this read word |

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `AXI_DATA_WIDTH` | 64 | AXI4 data bus width (must be 64 for DDR4) |
| `AXI_ADDR_WIDTH` | 32 | AXI4 address bus width |
| `AXI_ID_WIDTH` | 4 | AXI4 transaction ID width |

---

## Control Flow

### Write Path FSM

```
WS_IDLE ──(awvalid & awready)──> WS_DATA
WS_DATA ──(wvalid & wready, each beat)──> WS_CMD
WS_CMD  ──(cmd accepted by scheduler)──> WS_DATA (more beats)
                                       ──> WS_RESP (last beat)
WS_RESP ──(bvalid & bready)──> WS_IDLE
```

Each burst beat generates one internal write command (`cmd_type=WRITE`) and one
`wdata_valid` pulse to the data path. The AXI BRESP is returned after all beats
and the last command has been dispatched.

### Read Path FSM

```
RS_IDLE ──(arvalid & arready)──> RS_WAIT
RS_WAIT ──(rdata_valid from data path)──> RS_RETURN (last beat)
                                        ──> RS_WAIT   (more beats)
RS_RETURN ──(rvalid & rready)──> RS_IDLE
```

One internal read command (`cmd_type=READ`) is issued per burst beat. Read data
is returned from the data path in order. If `rdata_err=1`, `rresp=SLVERR` is
signalled to the master.

### Command Arbitration

Write and read paths each maintain a pending-command flag (`wr_cmd_pend`,
`rd_cmd_pend`). The arbiter drives the shared `cmd_valid`/`cmd_addr`/`cmd_type`
bus with **write priority**: a write command is issued first if both are pending.

---

## Handshake Semantics

- **AXI4 address channels**: `ready` is deasserted while a transaction is being
  processed; reasserted in IDLE so the master can pipeline the next address.
- **cmd_valid/cmd_ready**: standard valid/ready handshake; command is latched
  when both are 1 on the rising edge of `clk`.
- **wdata_valid/wdata_ready**: one-cycle pulse per data beat; the data path
  asserts `wdata_ready` once it has space in the write FIFO.

---

## Error Behavior

- AXI `BRESP=SLVERR` is returned if any beat incurred an internal error.
- AXI `RRESP=SLVERR` is returned on the data beat where `rdata_err=1`
  (ECC uncorrectable error signal from `ddr4_data_path`).
