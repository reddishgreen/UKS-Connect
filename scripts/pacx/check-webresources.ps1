# Compare web resources in a Dataverse solution against the local Webresources folder.
# Reports mismatches in both directions:
#   - In solution but not in project (orphans, e.g. after a rename)
#   - In project but not in solution (new files not yet pushed)
#
# Prerequisites: pacx auth profile configured (pacx auth create ...)
#
# Usage (from repo root):
#   .\scripts\pacx\check-webresources.ps1
#   .\scripts\pacx\check-webresources.ps1 -Solution "OtherSolution"
#   .\scripts\pacx\check-webresources.ps1 -ExcludePrefixes @()              # include everything
#   .\scripts\pacx\check-webresources.ps1 -ExcludePrefixes @("svg/","js/")  # custom exclusions

param(
    [Parameter(Mandatory=$false)]
    [string]$Solution = "UKSConnect",

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludePrefixes = @("html/", "js/", "jpg/", "rg/", "svg/")
)

$ErrorActionPreference = "Stop"

# --- 1. Get solution components from pacx (type 61 = web resource) ---

Write-Host "Fetching solution components from '$Solution'..." -ForegroundColor Cyan

$rawOutput = & pacx solution component list --solution $Solution --format Json 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to list solution components. Is pacx auth configured?" -ForegroundColor Red
    Write-Host $rawOutput
    exit 1
}

# Extract just the JSON array from the output (skip pacx banner lines)
if ($rawOutput -match '(?s)(\[.*\])') {
    $jsonText = $matches[1]
} else {
    Write-Host "Could not find JSON array in pacx output." -ForegroundColor Red
    Write-Host $rawOutput
    exit 1
}

try {
    $components = $jsonText | ConvertFrom-Json
} catch {
    Write-Host "Failed to parse JSON: $_" -ForegroundColor Red
    exit 1
}

# pacx returns ComponentTypeCode=61 for web resources, and Label = logical name
$wrComponents = $components | Where-Object { $_.ComponentTypeCode -eq 61 }

$solutionWrNames = @{}
foreach ($c in $wrComponents) {
    if ($c.Label) {
        $solutionWrNames[$c.Label.ToLower()] = $c.ObjectId
    }
}

Write-Host "Found $($solutionWrNames.Count) web resource(s) in solution." -ForegroundColor Gray

# --- 1b. Filter out managed/external solution web resources ---

if ($ExcludePrefixes.Count -gt 0) {
    $excludedCount = 0
    $filteredNames = @{}
    foreach ($name in $solutionWrNames.Keys) {
        $excluded = $false
        foreach ($prefix in $ExcludePrefixes) {
            if ($name.StartsWith($prefix.ToLower())) {
                $excluded = $true
                break
            }
        }
        # Also exclude extensionless root-level names (no "/" and no "." = managed image/theme resources)
        if (-not $excluded -and $name -notmatch '/' -and $name -notmatch '\.') {
            $excluded = $true
        }
        if ($excluded) {
            $excludedCount++
        } else {
            $filteredNames[$name] = $solutionWrNames[$name]
        }
    }
    if ($excludedCount -gt 0) {
        Write-Host "Excluded $excludedCount managed/external web resource(s) (prefixes: $($ExcludePrefixes -join ', '); plus extensionless root names)." -ForegroundColor DarkGray
    }
    $solutionWrNames = $filteredNames
    Write-Host "Comparing against $($solutionWrNames.Count) web resource(s) after exclusions." -ForegroundColor Gray
}

# --- 2. Scan local Webresources folder and derive logical names ---

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$webresourcesRoot = Join-Path $repoRoot "UKS-Connect\Webresources"
if (-not (Test-Path $webresourcesRoot)) {
    Write-Host "Webresources folder not found at: $webresourcesRoot" -ForegroundColor Red
    exit 1
}

$localWrNames = @{}
$localWrCandidates = @{}
$allowedExtensions = @(".js", ".html", ".htm", ".svg", ".png", ".jpg", ".gif", ".ico", ".css", ".xml", ".resx", ".xsl", ".xap")

Get-ChildItem -Path $webresourcesRoot -Recurse -File | Where-Object {
    $allowedExtensions -contains $_.Extension.ToLower()
} | ForEach-Object {
    $relativePath = $_.FullName.Substring($webresourcesRoot.Length + 1).Replace("\", "/")
    $relativeLower = $relativePath.ToLower()
    $fileNameLower = $_.Name.ToLower()
    $stemLower = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower()
    $rgPrefixedStemLower = "rg_$stemLower"

    $localWrNames[$relativeLower] = $relativePath

    $localWrCandidates[$relativeLower] = @(
        $relativeLower,
        $fileNameLower,
        $stemLower,
        $rgPrefixedStemLower
    )
}

Write-Host "Found $($localWrNames.Count) web resource file(s) in project." -ForegroundColor Gray

# --- 3. Compare and report ---

Write-Host ""
Write-Host "=== Comparison ===" -ForegroundColor White

$localCandidatesSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($candidates in $localWrCandidates.Values) {
    foreach ($candidate in $candidates) {
        [void]$localCandidatesSet.Add($candidate)
    }
}

$inSolutionNotProject = @()
foreach ($name in $solutionWrNames.Keys) {
    if (-not $localCandidatesSet.Contains($name)) {
        $inSolutionNotProject += $name
    }
}

$inProjectNotSolution = @()
foreach ($name in $localWrNames.Keys) {
    $isMatched = $false
    foreach ($candidate in $localWrCandidates[$name]) {
        if ($solutionWrNames.ContainsKey($candidate)) {
            $isMatched = $true
            break
        }
    }

    if (-not $isMatched) {
        $inProjectNotSolution += $name
    }
}

$matched = $solutionWrNames.Count - $inSolutionNotProject.Count

if ($inSolutionNotProject.Count -eq 0 -and $inProjectNotSolution.Count -eq 0) {
    Write-Host ""
    Write-Host "All $matched web resource(s) match between solution and project." -ForegroundColor Green
} else {
    if ($inSolutionNotProject.Count -gt 0) {
        Write-Host ""
        Write-Host "IN SOLUTION but NOT in project ($($inSolutionNotProject.Count)):" -ForegroundColor Yellow
        Write-Host "(These may be orphans from renames, or resources not managed in this project)" -ForegroundColor DarkYellow
        foreach ($name in ($inSolutionNotProject | Sort-Object)) {
            Write-Host "  - $name" -ForegroundColor Yellow
        }
    }

    if ($inProjectNotSolution.Count -gt 0) {
        Write-Host ""
        Write-Host "IN PROJECT but NOT in solution ($($inProjectNotSolution.Count)):" -ForegroundColor Magenta
        Write-Host "(Run 'pacx webresources push' to add these)" -ForegroundColor DarkMagenta
        foreach ($name in ($inProjectNotSolution | Sort-Object)) {
            Write-Host "  - $name ($($localWrNames[$name]))" -ForegroundColor Magenta
        }
    }

    Write-Host ""
    Write-Host "Matched: $matched | In solution only: $($inSolutionNotProject.Count) | In project only: $($inProjectNotSolution.Count)" -ForegroundColor Cyan
}
