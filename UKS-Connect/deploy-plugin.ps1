# Deploy Plugin DLL to Dynamics 365 CRM
# Usage: .\deploy-plugin.ps1 -ConnectionString "AuthType=Office365;Url=https://yourorg.crm.dynamics.com;Username=user@domain.com;Password=password"
# Or: .\deploy-plugin.ps1 -ConnectionString "AuthType=ClientSecret;Url=https://yourorg.crm.dynamics.com;ClientId=xxx;ClientSecret=xxx"

param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString,
    
    [Parameter(Mandatory=$false)]
    [string]$DllPath = "bin\Debug\UKS-Connect.dll",
    
    [Parameter(Mandatory=$false)]
    [string]$AssemblyName = "UKS-Connect"
)

# Load required assemblies
$sdkPath = Join-Path $PSScriptRoot "bin\Debug\Microsoft.Xrm.Sdk.dll"
$toolingPath = Join-Path $PSScriptRoot "bin\Debug\Microsoft.Crm.Sdk.Proxy.dll"

if (-not (Test-Path $sdkPath)) {
    Write-Error "Microsoft.Xrm.Sdk.dll not found at $sdkPath"
    exit 1
}

Add-Type -Path $sdkPath
Add-Type -Path $toolingPath

# Load Microsoft.Xrm.Tooling.Connector if available
$toolingConnectorPath = Join-Path $PSScriptRoot "bin\coretools\Microsoft.Xrm.Tooling.Connector.dll"
if (Test-Path $toolingConnectorPath) {
    Add-Type -Path $toolingConnectorPath
}

# Get full DLL path
$fullDllPath = Join-Path $PSScriptRoot $DllPath
if (-not (Test-Path $fullDllPath)) {
    Write-Error "DLL not found at $fullDllPath"
    exit 1
}

Write-Host "Connecting to CRM..." -ForegroundColor Cyan

try {
    # Create connection using CrmServiceClient
    if (Test-Path $toolingConnectorPath) {
        $conn = New-Object Microsoft.Xrm.Tooling.Connector.CrmServiceClient($ConnectionString)
        if (-not $conn.IsReady) {
            Write-Error "Failed to connect to CRM: $($conn.LastCrmError)"
            exit 1
        }
        if ($conn.OrganizationWebProxyClient) {
            $service = $conn.OrganizationWebProxyClient
        } else {
            $service = $conn.OrganizationServiceProxy
        }
    } else {
        # Fallback to direct connection
        $conn = New-Object Microsoft.Xrm.Sdk.Client.OrganizationServiceProxy(
            [System.Uri]::new(([regex]::Match($ConnectionString, 'Url=([^;]+)')).Groups[1].Value + "/XRMServices/2011/Organization.svc"),
            $null,
            $null,
            $null
        )
        $service = $conn
    }
    
    Write-Host "Connected successfully!" -ForegroundColor Green
    
    # Read the DLL
    Write-Host "Reading DLL from $fullDllPath..." -ForegroundColor Cyan
    $dllBytes = [System.IO.File]::ReadAllBytes($fullDllPath)
    
    # Find the plugin assembly
    Write-Host "Searching for plugin assembly '$AssemblyName'..." -ForegroundColor Cyan
    $query = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("pluginassembly")
    $query.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet($true)
    $query.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $AssemblyName)
    
    $assemblies = $service.RetrieveMultiple($query)
    
    if ($assemblies.Entities.Count -eq 0) {
        Write-Error "Plugin assembly '$AssemblyName' not found in CRM. Please register it first using Plugin Registration Tool."
        exit 1
    }
    
    $assembly = $assemblies.Entities[0]
    $assemblyId = $assembly.Id
    
    Write-Host "Found assembly: $($assembly.GetAttributeValue('name')) (ID: $assemblyId)" -ForegroundColor Green
    
    # Update the assembly
    Write-Host "Updating plugin assembly..." -ForegroundColor Cyan
    $updateEntity = New-Object Microsoft.Xrm.Sdk.Entity("pluginassembly")
    $updateEntity.Id = $assemblyId
    $updateEntity["content"] = [System.Convert]::ToBase64String($dllBytes)
    
    $service.Update($updateEntity)
    
    Write-Host "Plugin assembly updated successfully!" -ForegroundColor Green
    Write-Host "You may need to restart the CRM service or wait a few moments for changes to take effect." -ForegroundColor Yellow
    
} catch {
    Write-Error "Error deploying plugin: $_"
    Write-Error $_.Exception.Message
    exit 1
}

