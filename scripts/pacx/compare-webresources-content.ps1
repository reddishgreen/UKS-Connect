# Compare local web resource file content with CRM content (hash-based).
# Uses pacx to download solution web resources to a temp folder, then compares bytes.
#
# Usage (from repo root):
#   .\scripts\pacx\compare-webresources-content.ps1
#   .\scripts\pacx\compare-webresources-content.ps1 -Solution "UKSConnect"
#
# Notes:
# - Comparison is byte-level (SHA256 local bytes vs downloaded CRM bytes).
# - Local files that don't map to a solution web resource are listed separately.

param(
    [Parameter(Mandatory=$false)]
    [string]$Solution = "UKSConnect",

    [Parameter(Mandatory=$false)]
    [switch]$StrictBytes
)

$ErrorActionPreference = "Stop"

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
    } finally {
        $sha.Dispose()
    }
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
}

function Normalize-TextContent {
    param([string]$Text)

    # Ignore Windows/Linux line-ending differences and trailing blank lines.
    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return $normalized.TrimEnd("`n")
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$webresourcesRoot = Join-Path $repoRoot "UKS-Connect\Webresources"
if (-not (Test-Path $webresourcesRoot)) {
    throw "Webresources folder not found at: $webresourcesRoot"
}

$allowedExtensions = @(".js", ".html", ".htm", ".svg", ".png", ".jpg", ".gif", ".ico", ".css", ".xml", ".resx", ".xsl", ".xap")
$textExtensions = @(".js", ".html", ".htm", ".svg", ".css", ".xml", ".resx", ".xsl")
$localFiles = Get-ChildItem -Path $webresourcesRoot -Recurse -File | Where-Object {
    $allowedExtensions -contains $_.Extension.ToLower()
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wr-compare-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

Write-Host "Downloading solution web resources to temp folder..." -ForegroundColor Cyan
Write-Host $tempRoot -ForegroundColor DarkGray

try {
    $initOutput = & pacx webresources init --remote --solution $Solution --folder $tempRoot 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "pacx webresources init failed.`n$initOutput"
    }
} catch {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

$remoteFiles = Get-ChildItem -Path $tempRoot -Recurse -File | Where-Object {
    $_.Name -ne ".wr.pacx" -and (
        [string]::IsNullOrEmpty($_.Extension) -or
        ($allowedExtensions -contains $_.Extension.ToLower())
    )
}

$remoteByLabel = @{}
foreach ($file in $remoteFiles) {
    $relative = $file.FullName.Substring($tempRoot.Length + 1).Replace("\", "/")
    $remoteByLabel[$relative.ToLower()] = [pscustomobject]@{
        RelativePath = $relative
        FullPath     = $file.FullName
    }
}

Write-Host "Found $($remoteByLabel.Count) web resource file(s) in solution download." -ForegroundColor Gray

$matches = @()
$unmatchedLocal = @()

foreach ($file in $localFiles) {
    $relativePath = $file.FullName.Substring($webresourcesRoot.Length + 1).Replace("\", "/")
    $relativeLower = $relativePath.ToLower()
    $fileNameLower = $file.Name.ToLower()
    $stemLower = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToLower()
    $rgPrefixedStemLower = "rg_$stemLower"

    $candidates = @($relativeLower, $fileNameLower, $stemLower, $rgPrefixedStemLower)
    $hit = $null
    foreach ($candidate in $candidates) {
        if ($remoteByLabel.ContainsKey($candidate)) {
            $hit = $remoteByLabel[$candidate]
            break
        }
    }

    if ($null -eq $hit) {
        $unmatchedLocal += $relativePath
        continue
    }

    $matches += [pscustomobject]@{
        LocalRelativePath = $relativePath
        LocalFullPath     = $file.FullName
        SolutionLabel     = $hit.RelativePath
        SolutionFullPath  = $hit.FullPath
    }
}

Write-Host "Matched $($matches.Count) local file(s) to solution web resources." -ForegroundColor Gray
if ($unmatchedLocal.Count -gt 0) {
    Write-Host "Local files not mapped to solution labels: $($unmatchedLocal.Count)" -ForegroundColor Yellow
}

Write-Host "Comparing content hashes..." -ForegroundColor Cyan
if ($StrictBytes) {
    Write-Host "Mode: strict byte compare" -ForegroundColor DarkGray
} else {
    Write-Host "Mode: normalized text compare for text files (line endings/trailing newline ignored)" -ForegroundColor DarkGray
}

$results = @()
$i = 0
foreach ($item in $matches) {
    $i++
    Write-Progress -Activity "Comparing web resources" -Status "$i / $($matches.Count) - $($item.LocalRelativePath)" -PercentComplete (($i / [Math]::Max($matches.Count, 1)) * 100)

    $localBytes = [System.IO.File]::ReadAllBytes($item.LocalFullPath)
    $localHash = Get-Sha256Hex -Bytes $localBytes

    $crmBytes = [System.IO.File]::ReadAllBytes($item.SolutionFullPath)
    $crmHash = Get-Sha256Hex -Bytes $crmBytes
    $status = if ($localHash -eq $crmHash) { "MATCH" } else { "DIFFERENT" }
    $details = ""

    $localExtension = [System.IO.Path]::GetExtension($item.LocalFullPath).ToLower()
    if (-not $StrictBytes -and $status -eq "DIFFERENT" -and ($textExtensions -contains $localExtension)) {
        $localText = [System.IO.File]::ReadAllText($item.LocalFullPath)
        $crmText = [System.IO.File]::ReadAllText($item.SolutionFullPath)
        $localNormHash = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes((Normalize-TextContent -Text $localText)))
        $crmNormHash = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes((Normalize-TextContent -Text $crmText)))

        if ($localNormHash -eq $crmNormHash) {
            $status = "MATCH_NORMALIZED"
            $details = "Only line endings/trailing newline differ"
        }
    }

    $results += [pscustomobject]@{
        LocalPath    = $item.LocalRelativePath
        SolutionName = $item.SolutionLabel
        Status       = $status
        LocalHash    = $localHash
        CrmHash      = $crmHash
        Details      = $details
    }
}

Write-Progress -Activity "Comparing web resources" -Completed

$diff = $results | Where-Object { $_.Status -eq "DIFFERENT" }
$normalizedOnly = $results | Where-Object { $_.Status -eq "MATCH_NORMALIZED" }
$errors = $results | Where-Object { $_.Status -like "ERROR_*" }
$matchCount = ($results | Where-Object { $_.Status -eq "MATCH" -or $_.Status -eq "MATCH_NORMALIZED" }).Count

Write-Host ""
Write-Host "=== Content Comparison Summary ===" -ForegroundColor White
Write-Host "Matched in content: $matchCount" -ForegroundColor Green
Write-Host "Different content: $($diff.Count)" -ForegroundColor Yellow
Write-Host "Normalized-only matches: $($normalizedOnly.Count)" -ForegroundColor DarkYellow
Write-Host "Fetch/content errors: $($errors.Count)" -ForegroundColor Red
Write-Host "Local not mapped to solution: $($unmatchedLocal.Count)" -ForegroundColor Magenta

if ($normalizedOnly.Count -gt 0) {
    Write-Host ""
    Write-Host "MATCH NORMALIZED ONLY ($($normalizedOnly.Count)):" -ForegroundColor DarkYellow
    foreach ($n in $normalizedOnly | Sort-Object LocalPath) {
        Write-Host "  - $($n.LocalPath)  <->  $($n.SolutionName) [$($n.Details)]" -ForegroundColor DarkYellow
    }
}

if ($diff.Count -gt 0) {
    Write-Host ""
    Write-Host "DIFFERENT CONTENT ($($diff.Count)):" -ForegroundColor Yellow
    foreach ($d in $diff | Sort-Object LocalPath) {
        Write-Host "  - $($d.LocalPath)  <->  $($d.SolutionName)" -ForegroundColor Yellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "ERRORS ($($errors.Count)):" -ForegroundColor Red
    foreach ($e in $errors | Sort-Object LocalPath) {
        Write-Host "  - $($e.LocalPath) [$($e.Status)] $($e.Details)" -ForegroundColor Red
    }
}

if ($unmatchedLocal.Count -gt 0) {
    Write-Host ""
    Write-Host "LOCAL NOT MAPPED TO SOLUTION LABEL ($($unmatchedLocal.Count)):" -ForegroundColor Magenta
    foreach ($u in $unmatchedLocal | Sort-Object) {
        Write-Host "  - $u" -ForegroundColor Magenta
    }
}

Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
