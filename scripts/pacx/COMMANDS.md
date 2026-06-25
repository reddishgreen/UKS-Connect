# PACX Commands Cheat Sheet

Run these from the repo root: `UKS Connect`

## VS Code Quick Deploy (Ctrl+Shift+U)

Open any web resource file in VS Code and press `Ctrl+Shift+U` to deploy it to D365.

**One-time setup per developer:**
1. `Ctrl+Shift+P` → "Open Keyboard Shortcuts (JSON)"
2. Add this inside the `[]` array:

```json
{
  "key": "ctrl+shift+u",
  "command": "workbench.action.tasks.runTask",
  "args": "Deploy Web Resource to D365"
}
```

3. Save and close. The task definition is already in `.vscode/tasks.json`.

---

## Webresource Deploy

- Dry run:
  - `.\scripts\pacx\deploy-webresources-pacx.ps1 -WhatIf`
- Deploy all:
  - `.\scripts\pacx\deploy-webresources-pacx.ps1`
- Deploy one file:
  - `.\scripts\pacx\deploy-webresources-pacx.ps1 -File "uks\JavaScript\rg_example.js"`
- Deploy without publish:
  - `.\scripts\pacx\deploy-webresources-pacx.ps1 -NoPublish`

## Name/Presence Checks

- Solution vs project alignment:
  - `.\scripts\pacx\check-webresources.ps1`
- With explicit solution:
  - `.\scripts\pacx\check-webresources.ps1 -Solution "UKSConnect"`

## Content Checks

- Normalized compare (ignores line endings/trailing newline for text files):
  - `.\scripts\pacx\compare-webresources-content.ps1`
- Strict byte compare:
  - `.\scripts\pacx\compare-webresources-content.ps1 -StrictBytes`

## Inspecting tables and solution (form / plugin context)

- Export a table's metadata (entity, attributes, relationships) to a folder:
  - `pacx table exportMetadata --table rg_<table> --output pacx-exports --format Json`
  - Or: `pacx table exportMetadata -t rg_<table> -o pacx-exports -f Json`
- List all components in the solution (forms, plugins, web resources, etc.) as JSON:
  - `pacx solution component list --solution UKSConnect --format Json > solution-components.json`
  - Then search for a table name or component type (e.g. 20 = Form, 62 = Plugin step) to see what runs on save.

Component type codes (for filtering): 20 = Form, 29 = Plugin Assembly, 62 = SdkMessageProcessingStep, 61 = Web Resource.

- List plugin steps on a table (see what runs on Save):
  - `pacx plugin list --table rg_<table> --format Table`
  - `pacx plugin list -t rg_<table> -f Json > pacx-exports\plugin-steps-rg_<table>.json`

## PACX Auth

- List profiles:
  - `pacx auth list`
- Select profile:
  - `pacx auth select`
- Ping current profile:
  - `pacx auth ping`
