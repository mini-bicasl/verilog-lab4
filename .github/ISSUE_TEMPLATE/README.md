# Issue templates (AI workflow)

These templates drive the AI-assisted RTL workflow. Use **New issue** and pick one of:

- **1_specification.yml** – AI Specification  
- **2_planning.yml** – AI Planning  
- **3_implementation.yml** – AI Implementation  
- **4_verification.yml** – AI Verification  

## Labels

Labels are set **per template** so issues are tagged by type. The workflow (`.github/workflows/ai-pipeline.yml`) **does not use labels for routing**—it parses the issue body for "Select Issue Type". Labels are for filtering and clarity.

| Template        | Labels applied |
|-----------------|----------------|
| Specification   | `AI-task` |
| Planning        | `AI-task` |
| Implementation  | `AI-task`, `rtl`, `tb`, `doc` |
| Verification    | `AI-task`, `verification` |

Ensure these labels exist in the repo: **Issues → Labels** ([mini-bicasl/verilog-lab/labels](https://github.com/mini-bicasl/verilog-lab/labels)). If any are missing, create them so the templates can apply them.

## Assignees

Each template sets **`assignees: ['github-copilot']`** so new issues are assigned to Copilot by default.

To use a **different bot or user** (e.g. a team or your username):

1. Open each template file (e.g. `1_specification.yml`).
2. Change `assignees: ['github-copilot']` to the desired GitHub username(s), e.g. `assignees: [your-username]` or `assignees: [alice, bob]`.
3. Save. New issues from that template will then be assigned accordingly.

See **`docs/INSTRUCTION.md`** for the full workflow.
