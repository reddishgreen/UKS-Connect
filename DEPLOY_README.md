# Deployment Guide

---

## Web Resource Deploy (PAC + pacx) -- Recommended for quick changes

Uses [pacx (Greg.Xrm.Command)](https://github.com/neronotte/Greg.Xrm.Command) to push JS, HTML, SVG, XML web resources directly to Dataverse. Updates existing resources by logical name; only creates a new record when the resource is missing. No solution pack/import needed.

### Prerequisites

1. **Power Platform CLI (pac)** -- install via the [Power Platform VS Code extension](https://marketplace.visualstudio.com/items?itemName=microsoft-IsvExpTools.powerplatform-vscode) or standalone.
2. **pacx** -- install as a global .NET tool:
   ```powershell
   dotnet tool install -g Greg.Xrm.Command
   ```
3. **Auth profile** -- create once per environment:
   ```powershell
   pacx auth create --name "UKS Connect Dev" --environment "https://uksconnectdev.crm11.dynamics.com"
   pacx auth create --name "UKS Connect Prod" --environment "https://<UKS_PROD_URL>.crm11.dynamics.com"
   ```
   This opens a browser for OAuth sign-in (supports MFA).

   > The production environment URL has not been provided yet -- replace `<UKS_PROD_URL>` once the
   > production environment exists.

### Push all web resources

```powershell
.\scripts\pacx\deploy-webresources-pacx.ps1
```

### Push a single file

```powershell
.\scripts\pacx\deploy-webresources-pacx.ps1 -File "uks\JavaScript\rg_example.js"
```

### Dry run (preview what would be pushed, no changes)

```powershell
.\scripts\pacx\deploy-webresources-pacx.ps1 -WhatIf
```

### Push without publishing

```powershell
.\scripts\pacx\deploy-webresources-pacx.ps1 -NoPublish
```

### Check solution vs project alignment

Compares web resources in the Dataverse solution with files in the local `Webresources/` folder. Reports orphans (renamed/deleted locally but still in solution) and new files not yet pushed.

```powershell
.\scripts\pacx\check-webresources.ps1
```

### Compare local content with CRM content

Downloads solution web resources and compares file content (SHA256). Reports exact matches, normalized-only matches (line-ending differences), and files with different content.

```powershell
.\scripts\pacx\compare-webresources-content.ps1
```

For strict byte-level comparison (no line-ending normalization):

```powershell
.\scripts\pacx\compare-webresources-content.ps1 -StrictBytes
```

### Other pacx capabilities

pacx also provides commands for ribbons, forms, views, columns, option sets, plugins, and more. Run `pacx --help` to see all command groups. Notable:

- `pacx plugin push` -- push plugin assemblies (CLI alternative to Plugin Registration Tool)
- `pacx ribbon get` -- get ribbon/command bar definitions
- `pacx view list` / `pacx view get` -- inspect views
- `pacx optionset add` / `update` -- manage picklist values
- `pacx solution component list` -- list all components in a solution

See [scripts/pacx/COMMANDS.md](scripts/pacx/COMMANDS.md) for the full cheat sheet.

---

## Legacy: spkl Web Resource Deploy

The older spkl-based web resource deploy is still available (used for CI via Azure Key Vault):

```batch
cd spkl
deploy-webresources.bat
```

Or via the rg_spkl script (uses Key Vault for connection string):
```powershell
cd rg_spkl
.\deploy.ps1 webresources
```

Config: `spkl.json` (solution: UKSConnect, root: `./Webresources`, autodetect: yes).

> The rg_spkl Key Vault settings are placeholders -- set `vault_name` and `secret_name` in
> `UKS-Connect\rg_spkl.json` (and `UKS-Connect\rg_spkl\rg_spkl.json`) before using the rg_spkl
> deploy path. The Key Vault secret must contain JSON with `url`, `client_id`, and `client_secret`.

For new local/quick deploys, prefer the **pacx** approach above. Keep spkl for CI until CI is migrated to pac/pacx auth.
