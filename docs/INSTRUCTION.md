# AI-Assisted RTL Project Workflow Instructions

This document explains the step-by-step workflow for developing RTL projects using AI-assisted tools (Copilot or other LLM agents). The flow is organized around three **issue templates**; you pick the template that matches the phase so each form only shows the fields you need.

- **Specification** – capture the high-level idea and architecture.
- **Implementation** – implement the plan (RTL, testbenches, docs).
- **Verification** – add tests, tighten constraints, or refine RTL/docs.

| Template              | When to use |
|-----------------------|-------------|
| **AI Specification**  | High-level idea → generate/update `docs/ARCHITECTURE.md`. |
| **AI Implementation** | Implement phases from `docs/PLAN.md` (RTL, testbench, docs, and results for the relevant modules). |
| **AI Verification**   | Add tests, tighten constraints, or refine RTL/docs (optional module + focus checkboxes). |

On GitHub: **New issue** → choose one of these three. Each form only shows the fields needed for that phase.

**Labels and assignees:** Each template adds labels by issue type (see table below). The pipeline **routes by parsing the issue body** ("Select Issue Type"), not by labels. Labels (e.g. `AI-task`, `rtl`, `tb`, `doc`, `verification`) must exist in the repo—create them under **Issues → Labels** if needed. The default assignee is **github-copilot**; to change it, edit `assignees` in each template—see `.github/ISSUE_TEMPLATE/README.md`.

---

## **Before you begin – Fork for experiments**

**We recommend forking this repository** before running the AI workflow. Use your fork for:

- Trying the Specification, Planning, Implementation, and Verification flow without touching the upstream repo.
- Creating issues and PRs freely; the pipeline will open `ai/rtl-*`, `ai/tb-*`, and `ai/doc-*` branches and PRs in **your fork**.
- Keeping the upstream repo clean—no experimental branches or test issues there.

**Note:** GitHub allows **one fork per user** per repo. For multiple experiments, use different **branches** in your single fork (the pipeline already creates `ai/rtl-*`, `ai/tb-*`, `ai/doc-*` per run). To start a fresh experiment, you can create a new branch from `main` in your fork and open issues there; or use a separate GitHub account/org if you need another fork.

Clone your fork, then open issues on the fork’s GitHub page and follow the steps below. When you are happy with the result, you can open a pull request from your fork to the upstream repo if you want to contribute back.

---

## **Step 1: Specification – Generate Architecture Document**

Goal: turn your rough idea (e.g. “commercial server-grade DDR4 controller”) into a structured architecture.

1. On GitHub, click **New issue** and choose the **“AI Specification”** template (from `.github/ISSUE_TEMPLATE/1_specification.yml`).
2. The form only asks for:
   - **Idea or description (optional)** – you can leave this blank. If you write something, describe your high-level RTL idea in plain language (e.g. commercial server-grade DDR4 controller with ECC and refresh).
   - **Standards / reference documents (recommended)** – if your request targets a standard (JEDEC/AXI/PCIe/USB/Ethernet/etc.), include the **standard name + version** and add **official links**. If a reference is publicly accessible, the workflow/agent may download it into `docs/` for traceability; do not request downloads of paywalled/copyrighted specs.
3. Submit the issue. The AI agent uses any existing specs in the repo and generates **`docs/ARCHITECTURE.md`** (or updates it) with:
   - Functional blocks and modules
   - Interfaces and I/O signals
   - Protocols, timing, and constraints
   - Block diagrams or FSM descriptions (ASCII or markdown)
4. Review `docs/ARCHITECTURE.md` and refine it until it is the **authoritative design reference**.

You do not need to fill a “module name” or “issue type” – choosing the Specification template is enough.

---

## **Step 2: Implementation – End-to-End Module Generation**

Goal: for each module in the plan, generate RTL, a testbench, and documentation automatically.

1. Click **New issue** and choose the **“AI Implementation”** template (from `.github/ISSUE_TEMPLATE/3_implementation.yml`).
2. The form asks for:
   - **Module name** (required) – the exact name from `ARCHITECTURE.md` / `docs/PLAN.md`, e.g. `ddr4_ctrl_top`.
   - **Description (optional)** – you can leave this blank; the workflow always reads `docs/ARCHITECTURE.md` and `docs/PLAN.md` and the agents infer what to generate.
3. Submit the issue. The pipeline will:
   - Run the RTL, Testbench, and Documentation agents for that module.
   - Produce `rtl/<module_name>.v`, `tb/<module_name>_tb.v`, `docs/<module_name>.md`, and JSON in `results/`.
   - Open pull request(s) for you to review; add the label **`ready-to-merge`** when satisfied.

You can repeat this for every module listed in `docs/PLAN.md`. Only the **module name** is required; description is optional.

### 3.2 What the automation does for an Implementation issue

Once you submit the issue:

1. The **`ai-pipeline.yml` workflow** triggers on `issues: opened`.
2. It parses the issue body:
   - Because you used the **AI Implementation** template, it detects **Implementation** and enables all three generation jobs: RTL, Testbench, and Documentation.
   - It reads the **Module name** from the form and uses it for filenames and prompts.
3. It builds a **context file** from:
   - `docs/ARCHITECTURE.md` (or `ARCHITECTURE.md` in repo root)
   - `docs/PLAN.md` (if present)
   - Optional: `INTERFACE_SPEC.md`, `NAMING_CONVENTIONS.md`, `TESTPLAN.md` (root or `docs/`)
4. It calls the AI agents with that context and the module name; they generate RTL, TB, and docs and write JSON to `results/`.
5. The workflow commits on `ai/...` branches and opens PR(s) against the repo’s default branch; you label **`ready-to-merge`** to auto-merge.

---

## **Step 3: Verification and Auto-Merge**

Verification can be done both manually and via the **“AI Verification”** issue template.

1. For **Implementation PRs**:
   - Review the generated RTL, testbench, docs, and JSON summaries.
   - Run additional local simulations or checks if desired.
2. When you are satisfied that a PR is correct:
   - Add the label **`ready-to-merge`** to the pull request.
3. The **same `ai-pipeline.yml` workflow** listens for `pull_request: labeled` events:
   - When it sees the label **`ready-to-merge`**, it will automatically merge the PR into the repository’s **default branch** (usually `main`).
4. If coverage or tests fail, or behavior is not as expected:
   - Open a new issue with the **“AI Verification”** template (`.github/ISSUE_TEMPLATE/4_verification.yml`).
   - Optionally pick **Module name** and **What do you want to improve?** (add tests, tighten constraints, refine RTL/docs). Description can stay blank.
   - Use the issue to track adding more tests, tightening constraints, or refining RTL/documentation; repeat Implementation for the same module if needed.

---

## **Iterative Refinement**

You can iterate on all three phases as the design evolves:

- Update `docs/ARCHITECTURE.md` if new requirements or blocks are identified.
- Update `docs/PLAN.md` when you add modules, change priorities, or discover new dependencies (manually or via future automation).
- Add new AI issues for:
  - Missing features → **AI Implementation** (with module name).
  - Additional tests or coverage → **AI Verification**.
- Documentation or plan updates → **AI Specification** (and direct edits to `docs/PLAN.md` as needed).
- Ensure all merged PRs maintain:
  - **JSON traceability** in `results/`.
  - **Simulation/coverage verification** where applicable.

---

## **Folder Structure**

After executing tasks, your repository should include:

- `rtl/` – RTL modules (`rtl/<module_name>.v`)
- `tb/` – Testbenches (`tb/<module_name>_tb.v`)
- `docs/` – Markdown documentation (per module and high-level docs)
- `results/` – Simulation logs and JSON summaries
- `.github/agents/prompt-templates/` – AI prompt templates used by the workflow
- `docs/ARCHITECTURE.md` – architecture specification
- `docs/PLAN.md` – implementation plan

---

## **Best Practices**

- **Fork the repo for experiments** so the upstream stays clean; run issues and PRs in your fork, then contribute back via pull request when ready.
- Always **start with `docs/ARCHITECTURE.md`**; it is the single source of truth for modules and interfaces.
- Keep `docs/PLAN.md` up to date; it drives which Implementation issues you create.
- Use **structured AI prompts** from `.github/agents/prompt-templates/` as a reference when refining templates or agent behavior.
- Check **JSON outputs** in `results/` to ensure the AI agents met all requirements (simulation_passed, coverage, plan_item_completed).
- Review PRs manually when unsure; do not rely solely on automation for critical changes.
- For complex designs, use hierarchical issues (Epic → Specification → Planning → Implementation / Verification) to keep work organized.

---

## **Summary Workflow**

1. **Specification**: New issue → **AI Specification** template (optional description). Generates/refines `docs/ARCHITECTURE.md` (and you may maintain `docs/PLAN.md` alongside it).
2. **Implementation**: New issue → **AI Implementation** template; fill **Module name**, description optional. Implements the next phase from `docs/PLAN.md`, generates RTL, TB, docs, results, and opens PR(s).
3. **Verification & Merge**: Review PRs, add label **`ready-to-merge`** to auto-merge. For gaps, use **AI Verification** template and iterate until the project is complete.
