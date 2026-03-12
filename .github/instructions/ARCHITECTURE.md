# Architecture Reference (for Agents)

The **authoritative architecture** is in the repo at **`docs/ARCHITECTURE.md`** (or root **`ARCHITECTURE.md`**). The workflow injects that file into the agent context. This file is only a structural reference.

## Expected sections in docs/ARCHITECTURE.md

- **Project Overview** – design purpose and high-level summary
- **Functional Blocks / Modules** – list of modules and short descriptions
- **Interfaces** – inputs, outputs, widths, directions, clock/reset
- **Timing / Protocols / Constraints** – clocks, latency, protocols (e.g. AXI, custom)
- **Block Diagram** – ASCII or Markdown diagram of module connections
- **Notes** – assumptions and links to external specs

Agents must use the project’s `ARCHITECTURE.md` as the single source of truth for interfaces and structure.

## Standards-based designs (JEDEC/AXI/PCIe/etc.)

If the user request depends on an external standard or reference document:

- Prefer **official sources** (standards body / vendor) and record **name + version**.
- If the spec is **publicly accessible**, download it (or the relevant subset) and place it under `docs/`.
- In `docs/ARCHITECTURE.md`, add a short **“Standards & references”** section:
  - bullet list with **standard name, version, and citation link**
  - link to the downloaded local copy in `docs/` when available
- If the doc is **paywalled/copyrighted** or requires login, do **not** download it.
  - Ask for the user to provide requirements, excerpts they are allowed to share, or a link plus a plain-language summary they want implemented.
