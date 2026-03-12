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
