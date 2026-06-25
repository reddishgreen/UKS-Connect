param([string]$FullRelativePath)

# Strip the "UKS-Connect\Webresources\" prefix that VS Code includes
$rel = $FullRelativePath -replace '^UKS-Connect[\\/]Webresources[\\/]', ''

Write-Host "Deploying: $rel" -ForegroundColor Cyan

& "$PSScriptRoot\deploy-webresources-pacx.ps1" -File $rel
