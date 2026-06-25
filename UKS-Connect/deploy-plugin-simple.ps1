# Simple Plugin Deployment Script for Dynamics 365
# Usage examples:
#   .\deploy-plugin-simple.ps1  (will prompt for all credentials)
#   .\deploy-plugin-simple.ps1 -OrgUrl "https://yourorg.crm.dynamics.com" -Username "user@domain.com" -Password "password"
#   .\deploy-plugin-simple.ps1 -OrgUrl "https://yourorg.crm.dynamics.com" -ClientId "xxx" -ClientSecret "xxx"

param(
    [Parameter(Mandatory=$false)]
    [string]$OrgUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$DllPath = "bin\Debug\UKS-Connect.dll",
    
    [Parameter(Mandatory=$false)]
    [string]$AssemblyName = "UKS-Connect",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseClientSecret,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseOAuth,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseOffice365,
    
    [Parameter(Mandatory=$false)]
    [switch]$ClearCredentials,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Dev", "Prod", "")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

# Credential storage file
$credentialFile = Join-Path $PSScriptRoot ".crm-credentials.json"

# Function to register plugin steps and images from CrmPluginRegistration attributes
function Register-PluginStepsAndImages {
    param(
        [Microsoft.Xrm.Sdk.IOrganizationService]$Service,
        [Guid]$AssemblyId,
        [string]$DllPath,
        [string]$AssemblyName
    )
    
    Write-Host "Loading DLL to read plugin registration attributes..." -ForegroundColor Gray
    
    # Load the DLL using reflection
    $dllAssembly = [System.Reflection.Assembly]::LoadFrom($DllPath)
    
    # Get all types that implement IPlugin
    $allTypes = $dllAssembly.GetTypes()
    Write-Host "Found $($allTypes.Count) total types in assembly" -ForegroundColor Gray
    
    $pluginTypes = @()
    foreach ($type in $allTypes) {
        # Check if type implements IPlugin
        $implementsIPlugin = $false
        foreach ($iface in $type.GetInterfaces()) {
            if ($iface.FullName -eq "Microsoft.Xrm.Sdk.IPlugin") {
                $implementsIPlugin = $true
                break
            }
        }
        
        if ($implementsIPlugin) {
            Write-Host "  Found IPlugin type: $($type.Name)" -ForegroundColor Gray
            
            # Check for CrmPluginRegistration attributes
            $attrs = $type.GetCustomAttributes($false)
            foreach ($attr in $attrs) {
                if ($attr.GetType().Name -eq "CrmPluginRegistrationAttribute") {
                    $pluginTypes += $type
                    Write-Host "    Has CrmPluginRegistration attribute: $($attr.Message) on $($attr.EntityLogicalName)" -ForegroundColor Green
                    break
                }
            }
        }
    }
    
    if ($pluginTypes.Count -eq 0) {
        Write-Host "No plugin types with CrmPluginRegistration attributes found." -ForegroundColor Yellow
        Write-Host "Make sure you have rebuilt the solution after adding Package.cs" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($pluginTypes.Count) plugin type(s) with registration attributes" -ForegroundColor Gray
    
    foreach ($pluginType in $pluginTypes) {
        $attributes = $pluginType.GetCustomAttributes($false) | Where-Object { $_.GetType().Name -eq "CrmPluginRegistrationAttribute" }
        
        # Find or create plugin type
        $pluginTypeQuery = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("plugintype")
        $pluginTypeQuery.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet("plugintypeid", "name", "typename")
        $pluginTypeQuery.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $pluginType.Name)
        $pluginTypeQuery.Criteria.AddCondition("pluginassemblyid", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $AssemblyId)
        
        $existingTypes = $Service.RetrieveMultiple($pluginTypeQuery)
        $pluginTypeId = $null
        
        if ($existingTypes.Entities.Count -gt 0) {
            $pluginTypeId = [Guid]$existingTypes.Entities[0].Id
            Write-Host "Found existing plugin type: $($pluginType.Name)" -ForegroundColor Gray
        } else {
            # Create plugin type
            $newPluginType = New-Object Microsoft.Xrm.Sdk.Entity("plugintype")
            $newPluginType["name"] = [string]$pluginType.Name
            $newPluginType["typename"] = [string]$pluginType.FullName
            $newPluginType["pluginassemblyid"] = New-Object Microsoft.Xrm.Sdk.EntityReference("pluginassembly", [Guid]$AssemblyId)
            $newPluginType["friendlyname"] = [string]$pluginType.Name
            $newPluginType["description"] = [string]"Auto-registered from $AssemblyName"
            
            $pluginTypeId = [Guid]$Service.Create($newPluginType)
            Write-Host "Created plugin type: $($pluginType.Name)" -ForegroundColor Green
        }
        
        # Process each registration attribute
        foreach ($attr in $attributes) {
            if (-not $attr.Message -or -not $attr.EntityLogicalName) {
                continue  # Skip custom API registrations
            }
            
            $stepName = if ($attr.Name) { $attr.Name } else { "$($AssemblyName).$($pluginType.Name): $($attr.Message) of $($attr.EntityLogicalName)" }
            
            # Find existing step
            $stepQuery = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("sdkmessageprocessingstep")
            $stepQuery.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet($true)
            $stepQuery.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $stepName)
            $stepQuery.Criteria.AddCondition("plugintypeid", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $pluginTypeId)
            
            $existingSteps = $Service.RetrieveMultiple($stepQuery)
            $stepId = $null
            
            # Get SDK Message ID
            $messageQuery = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("sdkmessage")
            $messageQuery.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet("sdkmessageid", "name")
            $messageQuery.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $attr.Message)
            $messages = $Service.RetrieveMultiple($messageQuery)
            
            if ($messages.Entities.Count -eq 0) {
                Write-Host "WARNING: SDK Message '$($attr.Message)' not found. Skipping step: $stepName" -ForegroundColor Yellow
                continue
            }
            
            $messageId = $messages.Entities[0].Id
            
            if ($existingSteps.Entities.Count -gt 0) {
                $stepId = $existingSteps.Entities[0].Id
                Write-Host "Updating existing step: $stepName" -ForegroundColor Gray
                
                # Update step
                $updateStep = New-Object Microsoft.Xrm.Sdk.Entity("sdkmessageprocessingstep")
                $updateStep.Id = $stepId
                if ($attr.FilteringAttributes) { $updateStep["filteringattributes"] = [string]$attr.FilteringAttributes }
                if ($attr.Description) { $updateStep["description"] = [string]$attr.Description }
                $updateStep["mode"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue([int]$attr.ExecutionMode)
                $updateStep["stage"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue([int]$attr.Stage.Value)
                $updateStep["rank"] = [int]$attr.ExecutionOrder
                $updateStep["supporteddeployment"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue(0) # Server only
                
                if ($attr.EntityLogicalName) {
                    $filterRef = GetMessageFilter -Service $Service -MessageId $messageId -EntityLogicalName $attr.EntityLogicalName
                    if ($filterRef) {
                        $updateStep["sdkmessagefilterid"] = $filterRef
                    }
                }
                
                $Service.Update($updateStep)
            } else {
                Write-Host "Creating new step: $stepName" -ForegroundColor Green
                
                # Create step
                $newStep = New-Object Microsoft.Xrm.Sdk.Entity("sdkmessageprocessingstep")
                $newStep["name"] = [string]$stepName
                $newStep["plugintypeid"] = New-Object Microsoft.Xrm.Sdk.EntityReference("plugintype", [Guid]$pluginTypeId)
                $newStep["sdkmessageid"] = New-Object Microsoft.Xrm.Sdk.EntityReference("sdkmessage", [Guid]$messageId)
                if ($attr.FilteringAttributes) { $newStep["filteringattributes"] = [string]$attr.FilteringAttributes }
                if ($attr.Description) { $newStep["description"] = [string]$attr.Description }
                $newStep["mode"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue([int]$attr.ExecutionMode)
                $newStep["stage"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue([int]$attr.Stage.Value)
                $newStep["rank"] = [int]$attr.ExecutionOrder
                $newStep["supporteddeployment"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue(0) # Server only
                
                if ($attr.Id) {
                    $newStep["sdkmessageprocessingstepid"] = [Guid]::Parse($attr.Id)
                }
                
                if ($attr.EntityLogicalName) {
                    $filterRef = GetMessageFilter -Service $Service -MessageId $messageId -EntityLogicalName $attr.EntityLogicalName
                    if ($filterRef) {
                        $newStep["sdkmessagefilterid"] = $filterRef
                    }
                }
                
                $stepId = $Service.Create($newStep)
            }
            
            # Register images
            if ($stepId) {
                Register-PluginImage -Service $Service -StepId $stepId -ImageNumber 1 -ImageType $attr.Image1Type -ImageName $attr.Image1Name -ImageAttributes $attr.Image1Attributes
                Register-PluginImage -Service $Service -StepId $stepId -ImageNumber 2 -ImageType $attr.Image2Type -ImageName $attr.Image2Name -ImageAttributes $attr.Image2Attributes
            }
        }
    }
    
    Write-Host "Plugin steps and images registration completed!" -ForegroundColor Green
}

function GetMessageFilter {
    param(
        [Microsoft.Xrm.Sdk.IOrganizationService]$Service,
        [Guid]$MessageId,
        [string]$EntityLogicalName
    )
    
    $filterQuery = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("sdkmessagefilter")
    $filterQuery.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet("sdkmessagefilterid")
    $filterQuery.Criteria.AddCondition("sdkmessageid", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $MessageId)
    $filterQuery.Criteria.AddCondition("primaryobjecttypecode", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $EntityLogicalName)
    
    $filters = $Service.RetrieveMultiple($filterQuery)
    
    if ($filters.Entities.Count -gt 0) {
        $filterId = [Guid]$filters.Entities[0].Id
        return New-Object Microsoft.Xrm.Sdk.EntityReference("sdkmessagefilter", $filterId)
    }
    
    Write-Host "WARNING: Message filter not found for $EntityLogicalName" -ForegroundColor Yellow
    return $null
}

function Register-PluginImage {
    param(
        [Microsoft.Xrm.Sdk.IOrganizationService]$Service,
        [Guid]$StepId,
        [int]$ImageNumber,
        $ImageType,
        [string]$ImageName,
        [string]$ImageAttributes
    )
    
    if (-not $ImageName) {
        return  # No image name specified
    }
    
    # Convert ImageType enum to int if needed
    $imageTypeValue = 0
    if ($ImageType -ne $null) {
        if ($ImageType -is [System.Enum]) {
            $imageTypeValue = [int]$ImageType
        } elseif ($ImageType -is [int]) {
            $imageTypeValue = $ImageType
        } else {
            $imageTypeValue = [int]$ImageType
        }
    } else {
        return  # No image type specified
    }
    
    $imageQuery = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("sdkmessageprocessingstepimage")
    $imageQuery.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet("sdkmessageprocessingstepimageid")
    $imageQuery.Criteria.AddCondition("sdkmessageprocessingstepid", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $StepId)
    $imageQuery.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $ImageName)
    
    $existingImages = $Service.RetrieveMultiple($imageQuery)
    
    $imageEntity = New-Object Microsoft.Xrm.Sdk.Entity("sdkmessageprocessingstepimage")
    if ($existingImages.Entities.Count -gt 0) {
        $imageEntity.Id = $existingImages.Entities[0].Id
    }
    
    $imageEntity["sdkmessageprocessingstepid"] = New-Object Microsoft.Xrm.Sdk.EntityReference("sdkmessageprocessingstep", [Guid]$StepId)
    $imageEntity["name"] = [string]$ImageName
    $imageEntity["imagetype"] = New-Object Microsoft.Xrm.Sdk.OptionSetValue([int]$imageTypeValue)
    
    # Set messagepropertyname - must be "Target" for Create/Update messages
    $imageEntity["messagepropertyname"] = [string]"Target"
    
    $imageEntity["entityalias"] = [string]$ImageName
    
    if ($ImageAttributes) {
        $imageEntity["attributes"] = [string]$ImageAttributes
    }
    
    if ($existingImages.Entities.Count -gt 0) {
        $Service.Update($imageEntity)
        Write-Host "  Updated image: $ImageName" -ForegroundColor Gray
    } else {
        $Service.Create($imageEntity)
        Write-Host "  Created image: $ImageName" -ForegroundColor Green
    }
}

# Clear credentials if requested
if ($ClearCredentials) {
    if (Test-Path $credentialFile) {
        Remove-Item $credentialFile -Force
        Write-Host "Saved credentials have been cleared." -ForegroundColor Green
    } else {
        Write-Host "No saved credentials found." -ForegroundColor Yellow
    }
    
    # Also clear OAuth token cache
    $tokenCachePath = Join-Path $PSScriptRoot ".oauth-tokencache"
    if (Test-Path $tokenCachePath) {
        Remove-Item $tokenCachePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "OAuth token cache has been cleared." -ForegroundColor Green
    }
    
    exit 0
}

# Functions to save/load credentials
function Save-Credentials {
    param(
        [string]$DevUrl,
        [string]$ProdUrl,
        [string]$Username,
        [string]$Password,
        [string]$ClientId,
        [string]$ClientSecret,
        [bool]$UseClientSecret,
        [bool]$UseOAuth = $false
    )
    
    # Encrypt sensitive data
    $encryptedPassword = $null
    if ($Password) {
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $encryptedPassword = ConvertFrom-SecureString $securePassword
    }
    
    $secureClientSecret = $null
    $encryptedClientSecret = $null
    if ($ClientSecret) {
        $secureClientSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $encryptedClientSecret = ConvertFrom-SecureString $secureClientSecret
    }
    
    $credentials = @{
        DevUrl = $DevUrl
        ProdUrl = $ProdUrl
        Username = $Username
        EncryptedPassword = $encryptedPassword
        ClientId = $ClientId
        EncryptedClientSecret = $encryptedClientSecret
        UseClientSecret = $UseClientSecret
        UseOAuth = $UseOAuth
        SavedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    $credentials | ConvertTo-Json | Out-File $credentialFile -Encoding UTF8 -Force
    Write-Host "Credentials saved successfully!" -ForegroundColor Green
}

function Load-Credentials {
    if (-not (Test-Path $credentialFile)) {
        return $null
    }
    
    try {
        $saved = Get-Content $credentialFile -Raw | ConvertFrom-Json
        
        # Decrypt password
        $securePassword = ConvertTo-SecureString $saved.EncryptedPassword
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $decryptedPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        
        $decryptedClientSecret = $null
        if ($saved.EncryptedClientSecret) {
            $secureClientSecret = ConvertTo-SecureString $saved.EncryptedClientSecret
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureClientSecret)
            $decryptedClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        
        return @{
            DevUrl = $saved.DevUrl
            ProdUrl = $saved.ProdUrl
            Username = $saved.Username
            Password = $decryptedPassword
            ClientId = $saved.ClientId
            ClientSecret = $decryptedClientSecret
            UseClientSecret = $saved.UseClientSecret
            SavedDate = $saved.SavedDate
        }
    } catch {
        Write-Warning "Failed to load saved credentials: $_"
        return $null
    }
}

# Try to load saved credentials
$savedCreds = Load-Credentials
$useSavedCreds = $false

# Environment selection
if (-not $Environment -and $savedCreds) {
    Write-Host ""
    Write-Host "Environment Selection:" -ForegroundColor Cyan
    Write-Host "1. Dev  - $($savedCreds.DevUrl)" -ForegroundColor Yellow
    Write-Host "2. Prod - $($savedCreds.ProdUrl)" -ForegroundColor Yellow
    Write-Host ""
    $envChoice = Read-Host "Select environment (1 or 2)"
    
    if ($envChoice -eq "1") {
        $Environment = "Dev"
    } elseif ($envChoice -eq "2") {
        $Environment = "Prod"
    } else {
        Write-Host "Invalid selection. Using Dev by default." -ForegroundColor Yellow
        $Environment = "Dev"
    }
}

# If environment is specified via parameter but no saved creds, still prompt
if ($Environment -and -not $savedCreds) {
    Write-Host ""
    Write-Host "Environment: $Environment" -ForegroundColor Cyan
}

# Use saved credentials if available
if ($savedCreds -and -not $OrgUrl -and -not $Username -and -not $ClientId) {
    if (-not $Environment) {
        Write-Host ""
        Write-Host "Environment Selection:" -ForegroundColor Cyan
        Write-Host "1. Dev  - $($savedCreds.DevUrl)" -ForegroundColor Yellow
        Write-Host "2. Prod - $($savedCreds.ProdUrl)" -ForegroundColor Yellow
        Write-Host ""
        $envChoice = Read-Host "Select environment (1 or 2)"
        
        if ($envChoice -eq "1") {
            $Environment = "Dev"
        } elseif ($envChoice -eq "2") {
            $Environment = "Prod"
        } else {
            $Environment = "Dev"
        }
    }
    
    # Set URL based on environment
    if ($Environment -eq "Prod") {
        $OrgUrl = $savedCreds.ProdUrl
    } else {
        $OrgUrl = $savedCreds.DevUrl
    }
    
    Write-Host ""
    Write-Host "Found saved credentials for: $Environment environment" -ForegroundColor Cyan
    Write-Host "URL: $OrgUrl" -ForegroundColor Gray
    Write-Host "Saved on: $($savedCreds.SavedDate)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Authentication Options:" -ForegroundColor Cyan
    if ($savedCreds.UseOAuth) {
        Write-Host "1. Use saved OAuth (Token cached - may prompt if expired) [RECOMMENDED]" -ForegroundColor Green
        Write-Host "2. Use Office365 credentials (No MFA support)" -ForegroundColor Yellow
        Write-Host "3. Enter new credentials" -ForegroundColor Yellow
        Write-Host ""
        $authOption = Read-Host "Select option (1, 2, or 3) [Default: 1 - OAuth]"
        
        if ([string]::IsNullOrWhiteSpace($authOption)) {
            $authOption = "1"  # Default to saved OAuth
        }
        
        if ($authOption -eq "1") {
            $UseOAuth = $true
            Write-Host "Using saved OAuth authentication (token cached)..." -ForegroundColor Green
        } elseif ($authOption -eq "2") {
            $Username = $savedCreds.Username
            $Password = $savedCreds.Password
            $ClientId = $savedCreds.ClientId
            $ClientSecret = $savedCreds.ClientSecret
            $UseClientSecret = $savedCreds.UseClientSecret
            $useSavedCreds = $true
            Write-Host "Using saved Office365 credentials..." -ForegroundColor Green
            Write-Host "WARNING: Office365 does NOT support MFA!" -ForegroundColor Yellow
        } else {
            # User wants to enter new credentials - clear the saved ones for this session
            $useSavedCreds = $false
        }
    } else {
        Write-Host "1. Use saved credentials (Office365 - No MFA support)" -ForegroundColor Yellow
        Write-Host "2. Use OAuth (Interactive - Supports MFA) [RECOMMENDED]" -ForegroundColor Green
        Write-Host "3. Enter new credentials" -ForegroundColor Yellow
        Write-Host ""
        $authOption = Read-Host "Select option (1, 2, or 3) [Default: 2 - OAuth]"
        
        if ([string]::IsNullOrWhiteSpace($authOption)) {
            $authOption = "2"  # Default to OAuth
        }
        
        if ($authOption -eq "1") {
            $Username = $savedCreds.Username
            $Password = $savedCreds.Password
            $ClientId = $savedCreds.ClientId
            $ClientSecret = $savedCreds.ClientSecret
            $UseClientSecret = $savedCreds.UseClientSecret
            $useSavedCreds = $true
            Write-Host "Using saved credentials for $Environment environment..." -ForegroundColor Green
            Write-Host "WARNING: Saved credentials use Office365 which does NOT support MFA!" -ForegroundColor Yellow
        } elseif ($authOption -eq "2") {
            $UseOAuth = $true
            Write-Host "Using OAuth authentication (supports MFA)..." -ForegroundColor Green
            Write-Host "OAuth token will be cached for future use." -ForegroundColor Gray
        } else {
            # User wants to enter new credentials - clear the saved ones for this session
            $useSavedCreds = $false
        }
    }
}

# Prompt for missing credentials
if (-not $OrgUrl) {
    if (-not $Environment) {
        Write-Host ""
        Write-Host "Environment Selection:" -ForegroundColor Cyan
        Write-Host "1. Dev"
        Write-Host "2. Prod"
        Write-Host ""
        $envChoice = Read-Host "Select environment (1 or 2)"
        
        if ($envChoice -eq "1") {
            $Environment = "Dev"
        } elseif ($envChoice -eq "2") {
            $Environment = "Prod"
        } else {
            $Environment = "Dev"
        }
    }
    
    if ($Environment -eq "Prod") {
        $defaultUrl = "https://uksconnect.crm11.dynamics.com"
    } else {
        $defaultUrl = "https://uksconnectdev.crm11.dynamics.com"
    }
    
    $OrgUrl = Read-Host "Enter your Dynamics 365 organization URL (default: $defaultUrl)"
    if ([string]::IsNullOrWhiteSpace($OrgUrl)) {
        $OrgUrl = $defaultUrl
    }
}

if (-not $UseClientSecret -and -not $ClientId -and -not $Username -and -not $UseOAuth -and -not $UseOffice365) {
    Write-Host ""
    Write-Host "Authentication Method:" -ForegroundColor Cyan
    Write-Host "1. OAuth (Interactive - Supports MFA) [RECOMMENDED]"
    Write-Host "2. Office365 (Username/Password - No MFA)"
    Write-Host "3. Client Secret (App Registration)"
    $authChoice = Read-Host "Select authentication method (1, 2, or 3) [Default: 1]"
    
    if ([string]::IsNullOrWhiteSpace($authChoice)) {
        $authChoice = "1"  # Default to OAuth
    }
    
    if ($authChoice -eq "2") {
        $UseOffice365 = $true
    } elseif ($authChoice -eq "3") {
        $UseClientSecret = $true
    } else {
        $UseOAuth = $true
    }
}

if ($UseClientSecret -or $ClientId) {
    # Client Secret authentication
    if (-not $ClientId) {
        $ClientId = Read-Host "Enter Client ID (Application ID)"
    }
    if (-not $ClientSecret) {
        $secureSecret = Read-Host "Enter Client Secret" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
        $ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
    $connectionString = "AuthType=ClientSecret;Url=$OrgUrl;ClientId=$ClientId;ClientSecret=$ClientSecret"
} else {
    # Determine if we should use OAuth
    $shouldUseOAuth = $UseOAuth
    if (-not $shouldUseOAuth) {
        $shouldUseOAuth = (-not $UseOffice365 -and -not $UseClientSecret -and -not $ClientId -and -not $Username -and -not $useSavedCreds)
    }
    
    if ($shouldUseOAuth) {
        # OAuth authentication (supports MFA)
        Write-Host ""
        Write-Host "OAuth Authentication (Supports MFA)" -ForegroundColor Cyan
        Write-Host "A browser window will open for you to sign in." -ForegroundColor Yellow
        Write-Host "If you have MFA enabled, you'll be prompted during sign-in." -ForegroundColor Yellow
        Write-Host ""
        # Use OAuth with interactive login - this allows MFA prompts
        # AppId and RedirectUri are required for the browser to open
        # TokenCacheStorePath saves the token so you don't need to authenticate every time
        $tokenCachePath = Join-Path $PSScriptRoot ".oauth-tokencache"
        $connectionString = "AuthType=OAuth;Url=$OrgUrl;AppId=51f81489-12ee-4a9e-aaae-a2591f45987d;RedirectUri=app://58145B91-0C36-4500-8554-080854F2AC97;TokenCacheStorePath=$tokenCachePath"
    } else {
        # Office365 authentication (no MFA support)
        Write-Host ""
        Write-Host "WARNING: Office365 authentication does NOT support MFA." -ForegroundColor Yellow
        Write-Host "If your account has MFA enabled, this will fail." -ForegroundColor Yellow
        Write-Host "Please use OAuth authentication (option 1) instead." -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            Write-Host "Cancelled. Please run the script again and select OAuth authentication." -ForegroundColor Yellow
            exit 0
        }
        
        if (-not $Username) {
            $Username = Read-Host "Enter Username (email)"
        }
        if (-not $Password) {
            $securePassword = Read-Host "Enter Password" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        $connectionString = "AuthType=Office365;Url=$OrgUrl;Username=$Username;Password=$Password"
    }
}

# Ask to save credentials/OAuth preference
if (-not $useSavedCreds) {
    Write-Host ""
    if ($UseOAuth) {
        $saveCreds = Read-Host "Save OAuth preference for future use? (Y/n)"
        if ($saveCreds -eq "" -or $saveCreds -eq "Y" -or $saveCreds -eq "y") {
            # Get or prompt for both URLs
            $devUrl = if ($savedCreds) { $savedCreds.DevUrl } else { $null }
            $prodUrl = if ($savedCreds) { $savedCreds.ProdUrl } else { $null }
            
            if (-not $devUrl) {
                $devUrl = Read-Host "Enter Dev URL (default: https://uksconnectdev.crm11.dynamics.com)"
                if ([string]::IsNullOrWhiteSpace($devUrl)) {
                    $devUrl = "https://uksconnectdev.crm11.dynamics.com"
                }
            }
            
            if (-not $prodUrl) {
                $prodUrl = Read-Host "Enter Prod URL (default: https://uksconnect.crm11.dynamics.com)"
                if ([string]::IsNullOrWhiteSpace($prodUrl)) {
                    $prodUrl = "https://uksconnect.crm11.dynamics.com"
                }
            }
            
            Save-Credentials -DevUrl $devUrl -ProdUrl $prodUrl -UseOAuth $true
            Write-Host "OAuth preference saved. Token is cached in .oauth-tokencache" -ForegroundColor Green
        }
    } elseif ($Username -or $ClientId) {
        $saveCreds = Read-Host "Save these credentials for future use? (Y/n)"
        if ($saveCreds -eq "" -or $saveCreds -eq "Y" -or $saveCreds -eq "y") {
            # Get or prompt for both URLs
            $devUrl = if ($savedCreds) { $savedCreds.DevUrl } else { $null }
            $prodUrl = if ($savedCreds) { $savedCreds.ProdUrl } else { $null }
            
            if (-not $devUrl) {
                $devUrl = Read-Host "Enter Dev URL (default: https://uksconnectdev.crm11.dynamics.com)"
                if ([string]::IsNullOrWhiteSpace($devUrl)) {
                    $devUrl = "https://uksconnectdev.crm11.dynamics.com"
                }
            }
            
            if (-not $prodUrl) {
                $prodUrl = Read-Host "Enter Prod URL (default: https://uksconnect.crm11.dynamics.com)"
                if ([string]::IsNullOrWhiteSpace($prodUrl)) {
                    $prodUrl = "https://uksconnect.crm11.dynamics.com"
                }
            }
            
            Save-Credentials -DevUrl $devUrl -ProdUrl $prodUrl -Username $Username -Password $Password -ClientId $ClientId -ClientSecret $ClientSecret -UseClientSecret $UseClientSecret
        }
    }
}

# Check if DLL exists
$fullDllPath = Join-Path $PSScriptRoot $DllPath
if (-not (Test-Path $fullDllPath)) {
    Write-Error "DLL not found at $fullDllPath"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Plugin Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
if ($Environment) {
    Write-Host "Environment: $Environment" -ForegroundColor Magenta
}
Write-Host "Organization: $OrgUrl" -ForegroundColor Yellow
Write-Host "DLL Path: $fullDllPath" -ForegroundColor Yellow
Write-Host "Assembly Name: $AssemblyName" -ForegroundColor Yellow
Write-Host ""

# Load SDK assemblies with proper dependency resolution
$binPath = Join-Path $PSScriptRoot "bin\Debug"
$sdkPath = Join-Path $binPath "Microsoft.Xrm.Sdk.dll"
$proxyPath = Join-Path $binPath "Microsoft.Crm.Sdk.Proxy.dll"

if (-not (Test-Path $sdkPath)) {
    Write-Host "ERROR: Microsoft.Xrm.Sdk.dll not found at: $sdkPath" -ForegroundColor Red
    Write-Host "Please build the project first (Debug or Release configuration)" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $proxyPath)) {
    Write-Host "ERROR: Microsoft.Crm.Sdk.Proxy.dll not found at: $proxyPath" -ForegroundColor Red
    Write-Host "Please build the project first (Debug or Release configuration)" -ForegroundColor Yellow
    exit 1
}

# Set up assembly resolver to find dependencies in bin folder
$OnAssemblyResolve = [System.ResolveEventHandler]{
    param($sender, $e)
    
    $assemblyName = $e.Name.Split(',')[0]
    $dllPath = Join-Path $binPath "$assemblyName.dll"
    
    if (Test-Path $dllPath) {
        return [System.Reflection.Assembly]::LoadFrom($dllPath)
    }
    
    return $null
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)

# Load all DLLs from bin\Debug folder first (dependencies)
Write-Host "Loading dependencies from bin\Debug..." -ForegroundColor Gray
$dllFiles = Get-ChildItem -Path $binPath -Filter "*.dll" -ErrorAction SilentlyContinue | Where-Object { 
    $_.Name -notlike "UKS-Connect*" 
} | Sort-Object Name

foreach ($dll in $dllFiles) {
    try {
        [System.Reflection.Assembly]::LoadFrom($dll.FullName) | Out-Null
    } catch {
        # Ignore errors - assembly may already be loaded or not needed
    }
}

# Now load the main SDK assemblies
try {
    Write-Host "Loading Microsoft.Xrm.Sdk.dll..." -ForegroundColor Gray
    $sdkAssembly = [System.Reflection.Assembly]::LoadFrom($sdkPath)
    
    Write-Host "Loading Microsoft.Crm.Sdk.Proxy.dll..." -ForegroundColor Gray
    $proxyAssembly = [System.Reflection.Assembly]::LoadFrom($proxyPath)
    
    Write-Host "SDK assemblies loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to load SDK assemblies" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.Exception.LoaderExceptions) {
        Write-Host ""
        Write-Host "Loader Exceptions:" -ForegroundColor Yellow
        foreach ($loaderEx in $_.Exception.LoaderExceptions) {
            Write-Host "  - $($loaderEx.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Ensure all DLL dependencies are in bin\Debug folder" -ForegroundColor White
    Write-Host "2. Try rebuilding the project in Visual Studio" -ForegroundColor White
    Write-Host "3. Check if .NET Framework 4.7.1 or higher is installed" -ForegroundColor White
    Write-Host "4. Verify the DLLs are not corrupted or locked by another process" -ForegroundColor White
    exit 1
}

# Try to load Tooling Connector (better connection handling)
# Check multiple possible locations
$toolingPath = $null

# Check bin\coretools first
$path1 = Join-Path $PSScriptRoot "bin\coretools\Microsoft.Xrm.Tooling.Connector.dll"
if (Test-Path $path1) {
    $toolingPath = $path1
} else {
    # Check packages folder with wildcard
    $packagesRoot = Join-Path $PSScriptRoot "..\packages"
    if (Test-Path $packagesRoot) {
        $found = Get-ChildItem -Path $packagesRoot -Recurse -Filter "Microsoft.Xrm.Tooling.Connector.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $toolingPath = $found.FullName
        }
    }
}

if ($toolingPath -and (Test-Path $toolingPath)) {
    Add-Type -Path $toolingPath
    $useTooling = $true
    Write-Host "Using Tooling Connector from: $toolingPath" -ForegroundColor Gray
} else {
    $useTooling = $false
    Write-Warning "Microsoft.Xrm.Tooling.Connector.dll not found. Trying alternative connection method..."
}

try {
    Write-Host "Connecting to CRM..." -ForegroundColor Cyan
    
    if ($useTooling) {
        # For OAuth, ensure we allow interactive authentication
        if ($UseOAuth -or $connectionString -like "*AuthType=OAuth*") {
            Write-Host "Initializing OAuth connection (browser will open for sign-in)..." -ForegroundColor Yellow
        }
        
        # For OAuth, create connection with proper initialization
        if ($UseOAuth -or $connectionString -like "*AuthType=OAuth*") {
            Write-Host "Opening browser for OAuth sign-in..." -ForegroundColor Yellow
            Write-Host "Please complete sign-in in the browser window (including MFA if required)." -ForegroundColor Yellow
            Write-Host ""
        }
        
        $conn = New-Object Microsoft.Xrm.Tooling.Connector.CrmServiceClient($connectionString)
        
        # For OAuth, wait longer for browser interaction
        if ($UseOAuth -or $connectionString -like "*AuthType=OAuth*") {
            $maxWait = 120  # Wait up to 2 minutes for user to complete sign-in
            $waited = 0
            while (-not $conn.IsReady -and $waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $waited += 2
                if ($waited % 10 -eq 0) {
                    Write-Host "Waiting for authentication... ($waited seconds)" -ForegroundColor Gray
                }
            }
        }
        
        if (-not $conn.IsReady) {
            $errorMsg = $conn.LastCrmError
            if ($errorMsg -like "*MFA*" -or $errorMsg -like "*AADSTS50076*" -or $errorMsg -like "*interaction_required*" -or $errorMsg -like "*USER intervention required*") {
                Write-Host ""
                Write-Host "========================================" -ForegroundColor Red
                Write-Host "MFA Authentication Required!" -ForegroundColor Yellow
                Write-Host "========================================" -ForegroundColor Red
                Write-Host ""
                Write-Host "Your account requires Multi-Factor Authentication (MFA)." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "To fix this:" -ForegroundColor Cyan
                Write-Host "1. Clear saved credentials: .\deploy-plugin-simple.ps1 -ClearCredentials" -ForegroundColor White
                Write-Host "2. Run the script again: .\deploy-plugin.bat" -ForegroundColor White
                Write-Host "3. When prompted, select OAuth (option 2 or just press Enter)" -ForegroundColor White
                Write-Host "4. Complete MFA in the browser window that opens" -ForegroundColor White
                Write-Host ""
            }
            throw "Connection failed: $errorMsg"
        }
        # Handle different service client types
        if ($conn.OrganizationWebProxyClient) {
            $service = $conn.OrganizationWebProxyClient
        } elseif ($conn.OrganizationServiceProxy) {
            $service = $conn.OrganizationServiceProxy
        } else {
            throw "Unable to get organization service from connection"
        }
        Write-Host "Connected successfully!" -ForegroundColor Green
    } else {
        # Basic connection (may require additional setup)
        throw "Tooling Connector required. Please ensure bin\coretools\Microsoft.Xrm.Tooling.Connector.dll exists or it's in the packages folder."
    }
    
    # Read DLL
    Write-Host "Reading DLL..." -ForegroundColor Cyan
    $dllBytes = [System.IO.File]::ReadAllBytes($fullDllPath)
    $dllBase64 = [System.Convert]::ToBase64String($dllBytes)
    Write-Host "DLL size: $($dllBytes.Length) bytes" -ForegroundColor Gray
    
    # Find plugin assembly
    Write-Host "Searching for plugin assembly..." -ForegroundColor Cyan
    $query = New-Object Microsoft.Xrm.Sdk.Query.QueryExpression("pluginassembly")
    $query.ColumnSet = New-Object Microsoft.Xrm.Sdk.Query.ColumnSet("pluginassemblyid", "name", "content")
    $query.Criteria.AddCondition("name", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $AssemblyName)
    
    $results = $service.RetrieveMultiple($query)
    
    if ($results.Entities.Count -eq 0) {
        Write-Error "Plugin assembly '$AssemblyName' not found in CRM.`nPlease register it first using Plugin Registration Tool or XrmToolBox."
        exit 1
    }
    
    $assembly = $results.Entities[0]
    $assemblyId = $assembly.Id
    # Use indexer syntax instead of GetAttributeValue extension method (PowerShell compatibility)
    $currentName = $assembly["name"]
    if ($null -eq $currentName) {
        $currentName = $AssemblyName
    }
    
    Write-Host "Found assembly: $currentName (ID: $assemblyId)" -ForegroundColor Green
    
    # Update assembly
    Write-Host "Updating plugin assembly..." -ForegroundColor Cyan
    $updateEntity = New-Object Microsoft.Xrm.Sdk.Entity("pluginassembly")
    $updateEntity.Id = $assemblyId
    $updateEntity["content"] = $dllBase64
    
    $service.Update($updateEntity)
    
    Write-Host ""
    Write-Host "Plugin assembly updated successfully!" -ForegroundColor Green
    Write-Host ""
    
    # Note: Auto-registration of plugin steps is disabled due to PowerShell/CRM SDK serialization issues
    # You need to register new plugin steps manually using Plugin Registration Tool or XrmToolBox
    Write-Host ""
    Write-Host "IMPORTANT: Plugin steps must be registered manually!" -ForegroundColor Yellow
    Write-Host "Use Plugin Registration Tool or XrmToolBox to register steps for new plugins like Package.cs" -ForegroundColor Yellow
    Write-Host ""
    
    # Skip auto-registration - it has PowerShell serialization issues
    $skipAutoRegistration = $true
    if (-not $skipAutoRegistration) {
    Write-Host "Registering plugin steps and images from attributes..." -ForegroundColor Cyan
    try {
        Register-PluginStepsAndImages -Service $service -AssemblyId $assemblyId -DllPath $fullDllPath -AssemblyName $AssemblyName
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "SUCCESS! Plugin assembly and steps updated." -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "WARNING: Failed to register plugin steps/images: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Assembly was updated, but you may need to register steps manually." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "SUCCESS! Plugin assembly updated." -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    }
    } else {
        # Auto-registration skipped
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "SUCCESS! Plugin assembly updated." -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Note: Changes may take a few moments to take effect." -ForegroundColor Yellow
    Write-Host "You may need to restart the CRM service or wait for the plugin to reload." -ForegroundColor Yellow
    
} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "ERROR: Deployment failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.Exception.StackTrace -ForegroundColor Gray
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify your organization URL is correct" -ForegroundColor White
    Write-Host "2. Check your credentials are correct" -ForegroundColor White
    Write-Host "3. Ensure you have permissions to update plugin assemblies" -ForegroundColor White
    Write-Host "4. Check if the plugin assembly exists in CRM" -ForegroundColor White
    exit 1
}

