---
applyTo: "rtl/**/*.v,tb/**/*.v"
---

Follow these conventions for RTL and unit testbenches in this repository.

## RTL (`rtl/*.v`)

- Keep modules **synthesizable** unless the file is explicitly a testbench.
- Use a **single clock** and **active-low reset** named `rst_n` unless the architecture specifies otherwise.
- Prefer clear, explicit state machines (one-hot or encoded is fine) with readable state names.
- Avoid `#delay` in synthesizable code.
- Keep port naming consistent with `docs/ARCHITECTURE.md`.

## Testbenches (`tb/*_tb.v`)

- Testbenches must compile/run with **Icarus Verilog** using:
  - `iverilog -g2012 -o build/<module>.out tb/<module>_tb.v rtl/<module>.v`
  - `vvp build/<module>.out`
- Include:
  - Clock generation
  - Reset sequencing
  - Directed stimulus that covers nominal + at least a couple of corner cases
  - Self-checks (assertions or explicit checks with `$fatal`)
  - Waveform dumping to `results/phase-<phase_name>/<module>.vcd`
  - A simulation log written to `results/phase-<phase_name>/<module>_sim.log` (capture stdout/stderr via your run command or TB prints)

## Results + gating

- Write artifacts under `results/phase-<phase_name>/` using the phase name from `docs/PLAN.md`.
- Update `results/phase-<phase_name>/<module>_result.json` with accurate flags.
- Set `simulation_passed: true` **only** if `vvp` ran successfully for that module.

