---
applyTo: "docs/**/*.md"
---

Documentation in this repository should be concise, technical, and directly tied to the implemented RTL and tests.

## Standards & reference docs

If a module/design targets an external standard (e.g. JEDEC DDRx, AMBA AXI, PCIe, USB, Ethernet):

- Capture **standard name + version** and include official citation links.
- When the reference is **publicly accessible**, store a local copy under `docs/` and link to it from the relevant docs (especially `docs/ARCHITECTURE.md`).
- Do **not** download or redistribute **paywalled/copyrighted** documents. Instead, rely on user-provided excerpts/requirements or public summaries.

## Module docs (`docs/<module>.md`)

When writing or updating module documentation:

- Start with a short overview: what the module does and where it fits in `docs/ARCHITECTURE.md`.
- Document the interface:
  - Port name, direction, width, and meaning (tables are preferred).
- Describe control flow:
  - FSM states and transitions (ASCII or Mermaid diagrams are fine).
- Note any key constraints:
  - Timing assumptions, backpressure/handshake semantics, reset behavior.
- Cross-link the code:
  - `rtl/<module>.v` and `tb/<module>_tb.v`.

## Plan/architecture edits

- `docs/ARCHITECTURE.md` is the system-level source of truth (modules + interfaces).
- `docs/PLAN.md` is the incremental implementation checklist (phases + dependency notes).
- Keep these consistent with any new modules, renamed modules, or interface changes.

