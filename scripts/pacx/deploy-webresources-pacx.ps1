# Deploy web resources to Dataverse using pacx (Greg.Xrm.Command)
# Prerequisites: dotnet tool install -g Greg.Xrm.Command
#                pacx auth create --name "UKS Connect Dev" --environment "https://uksconnectdev.crm11.dynamics.com"
#
# Usage (from repo root):
#   .\scripts\pacx\deploy-webresources-pacx.ps1                                          # push all web resources
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -File "uks\JavaScript\rg_example.js"     # push a single file
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -WhatIf                                  # dry run (no changes)
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -NoPublish                               # push without publishing
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -Solution "OtherSolution"                # target a different solution

param(
    [Parameter(Mandatory=$false)]
    [string]$File,

    [Parameter(Mandatory=$false)]
    [string]$Solution = "UKSConnect",

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,

    [Parameter(Mandatory=$false)]
    [switch]$NoPublish
)

$ErrorActionPreference = "Stop"

$pacx = Get-Command pacx -ErrorAction SilentlyContinue
if (-not $pacx) {
    Write-Host "pacx is not installed. Run: dotnet tool install -g Greg.Xrm.Command" -ForegroundColor Red
    exit 1
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$webresourcesRoot = Join-Path $repoRoot "UKS-Connect\Webresources"
if (-not (Test-Path $webresourcesRoot)) {
    Write-Host "Webresources folder not found at: $webresourcesRoot" -ForegroundColor Red
    exit 1
}

if ($File) {
    $targetPath = Join-Path $webresourcesRoot $File
    if (-not (Test-Path $targetPath)) {
        Write-Host "File not found: $targetPath" -ForegroundColor Red
        exit 1
    }
} else {
    $targetPath = $webresourcesRoot
}

$args_list = @("webresources", "push", "--path", $targetPath, "--solution", $Solution)

if ($WhatIf) {
    $args_list += "--no-action"
    Write-Host "[DRY RUN] Showing what would be pushed (no changes will be made)" -ForegroundColor Yellow
}

if ($NoPublish) {
    $args_list += "--no-publish"
    Write-Host "Publishing will be skipped after push" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "pacx $($args_list -join ' ')" -ForegroundColor Cyan
Write-Host "Target:   $targetPath" -ForegroundColor Gray
Write-Host "Solution: $Solution" -ForegroundColor Gray
Write-Host ""

& pacx @args_list

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "pacx webresources push failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
