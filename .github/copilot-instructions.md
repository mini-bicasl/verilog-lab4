# Copilot instructions (verilog-lab)

This repository is an AI-assisted **Verilog/SystemVerilog RTL lab**. Follow the repo workflow and validation gates so changes are testable and reviewable.

## Sources of truth

- **Project architecture**: `docs/ARCHITECTURE.md`
- **Implementation roadmap (phases + checklists)**: `docs/PLAN.md`
- **How issues are intended to be used**: `docs/INSTRUCTION.md`
- **Issue templates**: `.github/ISSUE_TEMPLATE/*.yml` (Specification / Planning / Implementation / Verification)

If you are acting on a GitHub Issue, treat the issue body as **requirements** and follow the corresponding template’s steps.

## Repo layout (expected outputs)

- `rtl/`: synthesizable RTL modules (`rtl/<module>.v`)
- `tb/`: unit testbenches (`tb/<module>_tb.v`)
- `docs/`: module docs (`docs/<module>.md`) + high-level docs
- `results/`: validation artifacts and status JSON under `results/phase-<phase_name>/`

## Implementation rule: phase-first, gated completion

When implementing work from `docs/PLAN.md`:

- Pick the **first phase with unchecked items** (or the first phase if none are checked).
- Implement **all modules** in that immediate phase (unless the issue explicitly scopes it differently).
- Do not claim completion unless validation actually ran successfully.

## Hard validation gate (must be real)

For each implemented module, run (and only then mark passing):

- Compile:
  - `iverilog -g2012 -o build/<module>.out tb/<module>_tb.v rtl/<module>.v`
- Execute:
  - `vvp build/<module>.out`

If compilation or simulation fails, iterate on RTL/TB until it succeeds.

## Required artifacts + traceability JSON

All simulation artifacts must be written under a stable, phase-scoped directory:

- `results/phase-<phase_name>/`

For every module you touch, update/create:

- `results/phase-<phase_name>/<module>_result.json`

Required fields (keep them accurate):

- `module`
- `rtl_done`, `tb_done`, `doc_done`
- `simulation_passed` (**true only if `vvp` ran successfully**)
- `coverage_completed`, `coverage_percentage`
- `plan_item_completed` (**true only if RTL+TB+docs exist and simulation_passed is true**)
- `error_summary` (empty if everything passes; otherwise a short reason)
- `sim_log` (path to a log under the same `results/phase-.../` directory, when useful)

## Expectations for PR-quality outputs

- RTL must be synthesizable and match the interfaces described in `docs/ARCHITECTURE.md`.
- Testbenches must be deterministic, include clock/reset, and produce a VCD for debugging.
- Documentation must explain purpose, interface, and any FSM/control behavior.
- Never say tests passed unless you actually ran them; include the exact commands and where outputs were written.

