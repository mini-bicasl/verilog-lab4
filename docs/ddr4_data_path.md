# `ddr4_data_path` — Read/Write Data Path

## Overview

`ddr4_data_path` manages the full data flow between the host-facing write interface and the PHY pads, and from the PHY back to the host on reads. It instantiates the [`ddr4_ecc_engine`](ddr4_ecc_engine.md) for transparent ECC on both paths.

**Source files:** `rtl/ddr4_data_path.v` · `tb/ddr4_data_path_tb.v`

---

## Interface

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Controller clock |
| `rst_n` | in | 1 | Active-low synchronous reset |
| **Write side** | | | |
| `wr_req` | in | 1 | Enqueue write data into write FIFO |
| `wr_id` | in | 4 | Write transaction ID |
| `wr_data` | in | 64 | Host write data |
| `wr_strb` | in | 8 | Byte enable strobes |
| `wr_ready` | out | 1 | Write FIFO has space (backpressure) |
| **PHY read side** | | | |
| `rd_data_return` | in | 72 | Raw 72-bit burst from PHY (64 data + 8 ECC) |
| `rd_data_valid_phy` | in | 1 | PHY read data valid |
| `rd_id_phy` | in | 4 | Transaction ID from scheduler |
| **Host read side** | | | |
| `rd_data_out` | out | 64 | Corrected read data to host |
| `rd_data_valid_host` | out | 1 | Read data valid to host |
| `rd_data_id_host` | out | 4 | Transaction ID |
| `rd_ecc_err` | out | 1 | ECC error (SBE or DBE) on this read word |
| **PHY output** | | | |
| `phy_dq_out` | out | 72 | ECC-encoded write data to PHY pads |
| `phy_dqs_oe` | out | 9 | DQS output-enable per byte lane |
| `phy_dq_oe` | out | 9 | DQ output-enable per byte lane |

---

## Write Path

```
wr_req + wr_data ──► Write FIFO (8 entries × 76 bits) ──► ECC encode ──► phy_dq_out
                                                                       └──► phy_dqs_oe / phy_dq_oe
```

1. When `wr_req` is asserted and `wr_ready` is high, `{wr_id, wr_strb, wr_data}` is pushed into the write FIFO.
2. Every cycle the FIFO is non-empty, the head entry is popped, ECC-encoded by `ddr4_ecc_engine`, and driven onto `phy_dq_out`.
3. `phy_dqs_oe` and `phy_dq_oe` are asserted (`9'h1ff`) for the same cycle the data is driven, and de-asserted otherwise.

### FIFO Backpressure

The write FIFO has depth **8** (parameterizable via `FIFO_DEPTH`). `wr_ready` is de-asserted when the FIFO is full, signaling backpressure to the host interface or scheduler.

---

## Read Path

```
rd_data_return + rd_data_valid_phy ──► ECC decode ──► [1-cycle register] ──► rd_data_out
                                                                           └──► rd_ecc_err
```

1. When `rd_data_valid_phy` is asserted, the 72-bit `rd_data_return` word is fed into the ECC decoder.
2. The corrected 64-bit data, valid flag, transaction ID, and ECC error flag are registered on the next clock edge.
3. `rd_ecc_err` is set if either `dec_single_err` or `dec_double_err` from the ECC engine is active.

### Timing

```
         clk   ___/‾\___/‾\___/‾\___/‾\
rd_data_valid_phy   ‾‾‾‾‾‾‾‾‾______
rd_data_return    ──| valid word |──
rd_data_valid_host        ‾‾‾‾‾‾‾‾‾___
rd_data_out           ──────| corrected |
```

**Read latency: 1 clock cycle** from PHY valid to host valid.

---

## DQS Preamble/Postamble

`phy_dqs_oe` and `phy_dq_oe` follow the write data cycle exactly (1-cycle assertion). In a real PHY integration these signals drive the output-enable of the SSTL/POD I/O buffers. Preamble extension (2-cycle OE) can be added by extending the pop logic.

---

## ECC Integration

The module instantiates `ddr4_ecc_engine` with:
- **Encoder input**: head of write FIFO (`wf_data_head = wr_fifo[wf_rptr][63:0]`)
- **Decoder input**: `rd_data_return` from PHY

---

## Key Constraints and Parameters

| Parameter | Default | Description |
|---|---|---|
| `FIFO_DEPTH` | 8 | Write FIFO depth |

- Active-low synchronous reset throughout.
- DQS/DQ OE pulses are one cycle wide aligned with the write data burst.

---

## References

- `docs/ARCHITECTURE.md` §3.8 (`ddr4_data_path` interface)
- `docs/ddr4_ecc_engine.md` (ECC engine detail)
- JEDEC JESD79-4D — DDR4 DQS timing (§3.5)
