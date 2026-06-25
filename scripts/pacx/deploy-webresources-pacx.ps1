# Deploy web resources to Dataverse using pacx (Greg.Xrm.Command)
# Prerequisites: dotnet tool install -g Greg.Xrm.Command
#                pacx auth create --name "UKS Connect Dev" --environment "https://uksconnectdev.crm11.dynamics.com"
#
# Notes:
#   - pacx targets .NET 8. If your default `dotnet` is newer (e.g. .NET 10 via Homebrew),
#     this script auto-points DOTNET_ROOT at a .NET 8 runtime when one isn't already set.
#   - Before pushing, the script verifies the active auth profile matches -EnvironmentUrl
#     (default: UKS Connect Dev) and switches to it if needed, so you never push to the
#     wrong environment. Use -SkipEnvCheck to bypass, or -EnvironmentUrl to target another.
#
# Usage (from repo root):
#   .\scripts\pacx\deploy-webresources-pacx.ps1                                          # push all web resources
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -File "uks\JavaScript\rg_example.js"     # push a single file
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -WhatIf                                  # dry run (no changes)
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -NoPublish                               # push without publishing
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -Solution "OtherSolution"                # target a different solution
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -EnvironmentUrl "https://other.crm.dynamics.com"  # target another env
#   .\scripts\pacx\deploy-webresources-pacx.ps1 -SkipEnvCheck                            # skip env verification

param(
    [Parameter(Mandatory=$false)]
    [string]$File,

    [Parameter(Mandatory=$false)]
    [string]$Solution = "UKSConnect",

    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,

    [Parameter(Mandatory=$false)]
    [switch]$NoPublish,

    [Parameter(Mandatory=$false)]
    [string]$EnvironmentUrl = "https://uksconnectdev.crm11.dynamics.com",

    [Parameter(Mandatory=$false)]
    [switch]$SkipEnvCheck
)

$ErrorActionPreference = "Stop"

$pacx = Get-Command pacx -ErrorAction SilentlyContinue
if (-not $pacx) {
    Write-Host "pacx is not installed. Run: dotnet tool install -g Greg.Xrm.Command" -ForegroundColor Red
    exit 1
}

# pacx (Greg.Xrm.Command) targets .NET 8. If the machine's default `dotnet` is a
# newer major (e.g. .NET 10 via Homebrew), pacx can't locate its runtime unless
# DOTNET_ROOT points at a .NET 8 install. Resolve one automatically if unset.
if (-not $env:DOTNET_ROOT) {
    $dotnet8Candidates = @(
        "/opt/homebrew/opt/dotnet@8/libexec",   # Homebrew (Apple Silicon)
        "/usr/local/opt/dotnet@8/libexec",       # Homebrew (Intel)
        (Join-Path $HOME ".dotnet")               # manual install
    )
    foreach ($candidate in $dotnet8Candidates) {
        $sharedRoot = Join-Path $candidate "shared/Microsoft.NETCore.App"
        if (Test-Path $sharedRoot) {
            $has8 = Get-ChildItem $sharedRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "8.*" }
            if ($has8) {
                $env:DOTNET_ROOT = $candidate
                Write-Host "DOTNET_ROOT -> $candidate (.NET 8 runtime for pacx)" -ForegroundColor DarkGray
                break
            }
        }
    }
}

# Verify (and pin) the target environment so we never push to the wrong tenant.
if (-not $SkipEnvCheck) {
    Write-Host "Verifying target environment ($EnvironmentUrl)..." -ForegroundColor Gray
    $authOutput = & pacx auth list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to read pacx auth profiles:" -ForegroundColor Red
        Write-Host ($authOutput -join "`n")
        exit 1
    }

    # Parse only the rows under the "authentication profiles are stored" header
    # (avoids matching the banner's documentation URLs).
    $profiles = @()
    $inProfileList = $false
    foreach ($line in $authOutput) {
        if ($line -match 'authentication profiles are stored') { $inProfileList = $true; continue }
        if (-not $inProfileList) { continue }
        if ($line -match '^\s*(?<name>.*?)\s+(?<url>https?://\S+)\s*$') {
            $name = $Matches['name']
            $isDefault = $name.EndsWith('*')
            $profiles += [pscustomobject]@{
                Name      = $name.TrimEnd('*').Trim()
                Url       = $Matches['url'].TrimEnd('/')
                IsDefault = $isDefault
            }
        }
    }

    $wanted = $EnvironmentUrl.TrimEnd('/')
    $target = $profiles | Where-Object { $_.Url -eq $wanted } | Select-Object -First 1
    if (-not $target) {
        Write-Host "No auth profile points to $EnvironmentUrl" -ForegroundColor Red
        Write-Host "Create one with:" -ForegroundColor Yellow
        Write-Host "  pacx auth create --name `"UKS Connect Dev`" --environment `"$EnvironmentUrl`"" -ForegroundColor Yellow
        exit 1
    }

    $current = $profiles | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $current -or $current.Url -ne $wanted) {
        Write-Host "Switching active profile to '$($target.Name)' ($EnvironmentUrl)" -ForegroundColor Yellow
        & pacx auth select --name $target.Name | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to select auth profile '$($target.Name)'" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "Environment OK: $($target.Name) ($EnvironmentUrl)" -ForegroundColor Green
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
