# Implementation Plan (Reference for Agents)

This file describes the **Implementation Plan** structure. The actual plan lives in the repo at **`docs/PLAN.md`**. The workflow injects that content into the agent context when present.

## Checklist structure (docs/PLAN.md)

Agents should align with the plan:

### RTL Modules

- [ ] Module A: RTL implementation
- [ ] Module B: RTL implementation
- [ ] Module C: RTL implementation

### Testbenches

- [ ] Module A: Testbench
- [ ] Module B: Testbench
- [ ] Module C: Testbench

### Documentation

- [ ] Module A: Documentation
- [ ] Module B: Documentation
- [ ] Module C: Documentation

### Verification / Coverage

- [ ] Module A: Coverage Analysis
- [ ] Module B: Coverage Analysis
- [ ] Module C: Coverage Analysis

## JSON traceability

When an agent completes a task, the mandatory JSON output should report:

- `rtl_done` / `tb_done` / `doc_done` (via `plan_item_completed` or equivalent)
- `simulation_passed` (for RTL and testbench)
- `coverage_completed` (via `coverage_percentage`)

Results are stored under **`results/`** for traceability.
