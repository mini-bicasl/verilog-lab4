---
applyTo: "results/**/*.json"
---

Status JSON files under `results/phase-<phase_name>/` must be machine-readable and reflect *real* validation.

## Required keys

Every `<module>_result.json` must contain at least:

- `module` (string)
- `rtl_done` (boolean)
- `tb_done` (boolean)
- `doc_done` (boolean)
- `simulation_passed` (boolean) — **true only if `vvp` was executed successfully**
- `coverage_completed` (boolean)
- `coverage_percentage` (number, 0–100)
- `plan_item_completed` (boolean) — true only if RTL+TB+docs exist and simulation_passed is true
- `error_summary` (string, empty when passing)

Optional but recommended when there is a failure:

- `sim_log` (string path under the same `results/phase-.../` directory)

## Semantics

- Do not “optimistically” set passing flags.
- If simulation fails, keep `simulation_passed: false` and set `error_summary` to a short actionable description.

