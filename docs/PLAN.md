# Implementation Plan — Commercial Server-Grade DDR4 Memory Controller

This plan is organized in three phases aligned with subsystem dependencies.
Agents pick the **first phase with unchecked items** and implement all modules in that phase before moving on.

---

## Phase 1: Core Control Path (`core-ctrl`)

Implements the fundamental command flow: initialization, timing enforcement, scheduling, and refresh. These modules form the backbone that all other phases depend on.

### RTL Modules

- [x] `ddr4_init_fsm`: Power-up and initialization FSM (RESET_N, CKE, MRS, ZQCL sequence per JESD79-4 §3.3)
- [x] `ddr4_mode_reg`: MR0–MR6 shadow registers and MRS payload encoder
- [x] `ddr4_timing_engine`: JEDEC timing constraint down-counters (tRCD, tRP, tRAS, tRC, tCCD, tRRD, tWR, tWTR, tRTP, tFAW, tRFC, tMOD, tZQ)
- [x] `ddr4_refresh_ctrl`: tREFI countdown; all-bank REF, Fine Granularity Refresh (FGR ×2/×4), Per-Bank Refresh (PBR), self-refresh entry/exit
- [x] `ddr4_cmd_scheduler`: Per-bank open/closed-page FSM, command queue, rank interleaving, refresh arbitration

### Testbenches

- [x] `ddr4_init_fsm`: TB — verifies RESET_N deassertion timing, MRS sequence order and MR values, ZQCL, init_done assertion
- [x] `ddr4_mode_reg`: TB — verifies correct MR0–MR6 encoding for representative CL/CWL/RTT combinations
- [x] `ddr4_timing_engine`: TB — verifies that timing_ok bits de-assert after command and re-assert after correct number of cycles for all 16 constraints
- [x] `ddr4_refresh_ctrl`: TB — verifies tREFI expiry generates ref_req; FGR×2 halves effective period; PBR rotates through all 16 banks; sr_active asserted after sr_req
- [x] `ddr4_cmd_scheduler`: TB — issues READ and WRITE requests; verifies ACT→RD/WR→PRE sequence; verifies refresh preemption; verifies rank interleaving

### Documentation

- [x] `docs/ddr4_init_fsm.md`: FSM state diagram, port table, timing diagram for init sequence
- [x] `docs/ddr4_mode_reg.md`: MR0–MR6 bit-field map, encoding tables
- [x] `docs/ddr4_timing_engine.md`: Constraint table, counter architecture, timing_ok semantics
- [x] `docs/ddr4_refresh_ctrl.md`: Refresh mode comparison, self-refresh flow
- [x] `docs/ddr4_cmd_scheduler.md`: Bank FSM states, arbitration policy, refresh integration

### Verification / Coverage

- [ ] `ddr4_init_fsm`: Coverage — all init states visited; correct inter-state wait counts
- [ ] `ddr4_mode_reg`: Coverage — MR0–MR6 exercised; boundary CL/CWL values
- [ ] `ddr4_timing_engine`: Coverage — every timing bit exercised; back-to-back commands to same and different bank groups
- [ ] `ddr4_refresh_ctrl`: Coverage — all three FGR modes; PBR covers all 16 banks; self-refresh entry and exit
- [ ] `ddr4_cmd_scheduler`: Coverage — read/write mix; refresh preemption; multi-rank commands

---

## Phase 2: Data Path and ECC (`data-ecc`)

Implements the data flow between the host-facing FIFO and the PHY pads, including ECC encode/decode. Depends on Phase 1 (`ddr4_cmd_scheduler` read/write request signals).

### RTL Modules

- [x] `ddr4_ecc_engine`: SECDED (72,64) encoder and decoder; syndrome computation; single-bit correction; double-bit detection; error bit identification
- [x] `ddr4_data_path`: Read/write data FIFOs; 8:1 serializer/deserializer bridge; DQS preamble/postamble control; ECC engine integration; read-data correction pipeline

### Testbenches

- [x] `ddr4_ecc_engine`: TB — encodes known data; injects single-bit errors at every bit position (0–71) and verifies correction; injects two-bit errors and verifies detection; verifies syndrome = 0 on clean data
- [x] `ddr4_data_path`: TB — writes data through FIFO; reads back and verifies data integrity; injects correctable ECC error and checks rd_ecc_err; verifies DQS OE timing

### Documentation

- [x] `docs/ddr4_ecc_engine.md`: SECDED H-matrix description, codeword layout, encoder/decoder flow, error classification table
- [x] `docs/ddr4_data_path.md`: FIFO depth and backpressure behavior, serialization pipeline, DQS timing diagram

### Verification / Coverage

- [ ] `ddr4_ecc_engine`: Coverage — all 72 single-bit error positions corrected; double-bit errors tested at all C(72,2)=2556 pairs (or exhaustive for simulation; at minimum all adjacent-bit pairs and all pairs spanning check-bit boundaries); syndrome = 0 on clean data; no false correction on double-bit error
- [ ] `ddr4_data_path`: Coverage — FIFO full/empty corner cases; back-to-back write and read; ECC error propagation to host

---

## Phase 3: Host Interface, PHY, and Top-Level Integration (`integration`)

Integrates all modules into the top-level and provides the AXI4 host interface and abstract PHY layer. Depends on Phases 1 and 2.

### RTL Modules

- [x] `ddr4_host_iface`: AXI4 slave; address decoding; write channel buffering; read response reorder buffer; ECC error reporting to AXI SLVERR
- [x] `ddr4_phy_iface`: Abstract PHY with differential CK, DQS I/O buffers; tristate DQ/DQS control; SSTL/POD pad model
- [x] `ddr4_ctrl_top`: Top-level wrapper tying all sub-modules; configuration port muxing (internal defaults vs. cfg_* inputs); ECC sticky error registers; init_done, ref_in_progress status

### Testbenches

- [x] `ddr4_host_iface`: TB — issues AXI4 WRITE and READ bursts; verifies cmd_valid/cmd_ready handshake; verifies write response; verifies read data return with correct ID
- [x] `ddr4_phy_iface`: TB — drives ctrl_* signals; verifies DDR4 pad output timing; verifies DQ tristate during read; verifies DQS preamble
- [x] `ddr4_ctrl_top`: Integration TB — full AXI4 write followed by read; verifies correct round-trip data; ECC error injection; refresh during idle; init sequence on reset release

### Documentation

- [x] `docs/ddr4_host_iface.md`: AXI4 transaction flow, address mapping, error response behavior
- [x] `docs/ddr4_phy_iface.md`: PHY abstraction model, I/O buffer instantiation guidance
- [x] `docs/ddr4_ctrl_top.md`: Integration diagram, configuration port usage, status/error register map

### Verification / Coverage

- [ ] `ddr4_host_iface`: Coverage — write-only, read-only, mixed traffic; narrow vs. full-width bursts; back-pressure on wready/rready
- [ ] `ddr4_phy_iface`: Coverage — DQ OE transitions; DQS preamble/postamble; CKE and ODT control
- [ ] `ddr4_ctrl_top`: Coverage — end-to-end write/read; correctable ECC error flagged and corrected; refresh completes; self-refresh entry and exit

---

## JSON Traceability

For each completed module, update `results/phase-<phase_name>/<module>_result.json` with:

- `module`, `rtl_done`, `tb_done`, `doc_done`
- `simulation_passed` (true **only** if `vvp` ran successfully)
- `coverage_completed`, `coverage_percentage`
- `plan_item_completed` (true only when RTL + TB + docs exist and simulation_passed is true)
- `error_summary` (empty string when passing)
- `sim_log` (path to simulation log under same `results/phase-*/` directory)

Phase directories:
- Phase 1 results: `results/phase-core-ctrl/`
- Phase 2 results: `results/phase-data-ecc/`
- Phase 3 results: `results/phase-integration/`
