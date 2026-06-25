# Get-InstalledModule
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
# may need -AllowClobber
# Connect-AzAccount required if you need to login
# Ensure Azure account plugin install and you do an Azure Sign in

Write-Host "deploy : $($args[0])"
$spkl_exe = Get-Childitem -Path ..\..\ -Recurse -Include spkl.exe |  Select-Object -first 1 | % { Write-Output $_.fullname }
Write-Host "Found spkl exe at : $($spkl_exe)"

$rg_config = Get-Content '..\rg_spkl.json' | Out-String | ConvertFrom-Json

Write-Host "Getting secret $($rg_config.secret_name) in $($rg_config.vault_name)"

# Connect-AzAccount
# $spkl_secret = az keyvault secret show --name spkl-rad-dev --vault-name kv-rgdev | ConvertFrom-Json
# $spkl_secret = az keyvault secret show --name $(rg_config.secret_name) --vault-name $(rg_config.vault_name) | ConvertFrom-Json
$spkl_secret = Get-AzKeyVaultSecret -Name $rg_config.secret_name -VaultName $rg_config.vault_name -AsPlainText -ErrorAction Stop 
if ($null -eq $spkl_secret)
{
    Write-Host "Secret not found"
    Exit
} 
else
{
    $spkl_secret = $spkl_secret | ConvertFrom-Json 
}


# Write-Host $spkl_secret
# Write-Host $spkl_secret.client_id, $spkl_secret.client_secret, $spkl_secret.url -ForegroundColor DarkMagenta

Write-Host "Deploying to $($spkl_secret.url)" -ForegroundColor DarkMagenta

$deploy_type = $args[0]
$path = ".\.." 
$connection = "AuthType=ClientSecret;url=$($spkl_secret.url);ClientId=$($spkl_secret.client_id);ClientSecret=$($spkl_secret.client_secret)"
$params = "$($deploy_type)","$($path)","$($connection)"
$expression = "$($spkl_exe) $($deploy_type) '$($path)' '$($connection)'"
# D:\Development\VisualStudio\Radcliffe-CRM-Plugin\'Radcliffe Webresources'\packages\spkl.1.0.640\tools\spkl.exe
# Write-Host $expression

# spkl [deploy type] [path] [connection-string]
# Start-Process -FilePath $spkl_exe -ArgumentList "$deploy_type","$path","$connection" -Wait
# Invoke-Expression $expression 
& $spkl_exe $deploy_type $path $connection


Write-Host end

