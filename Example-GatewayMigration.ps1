# Example: How to use the Migrate-PowerBIGatewayCluster.ps1 script

<#
PREREQUISITES:
1. Install DataGateway module:
   Install-Module -Name DataGateway -Scope CurrentUser

2. Create an Azure AD App Registration:
   - Go to portal.azure.com -> Azure Active Directory -> App registrations
   - Create new registration
   - API Permissions: Add "Power BI Service" -> "Tenant.Read.All"
   - Certificates & secrets: Create a new client secret
   - Note down: Tenant ID, Client ID (App ID), Client Secret

3. Ensure you have gateway admin permissions
#>

# ============================================
# CONFIGURATION
# ============================================

# Current gateway that's approaching 1,000 data source limit
$currentGatewayName = "OnPremGatewayCluster01"

# Prefix for new gateway clusters (will append 01, 02, 03, etc.)
$newGatewayPrefix = "OnPremGatewayCluster"

# Gateway recovery key (IMPORTANT: Store this securely!)
# This is the recovery key you used when creating the original gateway
$recoveryKeyPlainText = Read-Host -Prompt "Enter Gateway Recovery Key" -AsSecureString

# Azure region where gateway should be registered
$region = "WestUS2"  # Change to your region

# Threshold - create new gateway when approaching this number
$threshold = 900  # Out of 1,000 maximum

# Azure AD App Registration details
$tenantId = "YOUR-TENANT-ID"  # e.g., "12345678-1234-1234-1234-123456789abc"
$clientId = "YOUR-CLIENT-ID"  # e.g., "87654321-4321-4321-4321-cba987654321"
$clientSecretPlain = Read-Host -Prompt "Enter Client Secret" -AsSecureString

# ============================================
# RUN THE MIGRATION (DRY RUN FIRST)
# ============================================

# STEP 1: Test with -WhatIf to see what would happen
.\Migrate-PowerBIGatewayCluster.ps1 `
    -CurrentGatewayName $currentGatewayName `
    -NewGatewayNamePrefix $newGatewayPrefix `
    -RecoveryKey $recoveryKeyPlainText `
    -Region $region `
    -Threshold $threshold `
    -TenantId $tenantId `
    -ClientId $clientId `
    -ClientSecret $clientSecretPlain `
    -WhatIf `
    -Verbose

# STEP 2: If dry run looks good, run the actual migration
# Remove -WhatIf parameter
<#
.\Migrate-PowerBIGatewayCluster.ps1 `
    -CurrentGatewayName $currentGatewayName `
    -NewGatewayNamePrefix $newGatewayPrefix `
    -RecoveryKey $recoveryKeyPlainText `
    -Region $region `
    -Threshold $threshold `
    -TenantId $tenantId `
    -ClientId $clientId `
    -ClientSecret $clientSecretPlain `
    -Verbose
#>

# ============================================
# AUTOMATED MONITORING SETUP
# ============================================

<#
You can schedule this script to run daily to automatically monitor
and migrate when needed:

1. Create a scheduled task:
   - Trigger: Daily at 2:00 AM
   - Action: Run PowerShell script
   - Program: powershell.exe
   - Arguments: -File "C:\Scripts\Migrate-PowerBIGatewayCluster.ps1" -CurrentGatewayName "..." [other params]

2. Store credentials securely using Windows Credential Manager or Azure Key Vault

3. Set up email notifications for when migration occurs
#>

# ============================================
# POST-MIGRATION VERIFICATION
# ============================================

<#
After migration completes:

1. Verify datasets are refreshing:
   - Check Power BI service for any refresh failures
   - Test manual refresh on key datasets

2. Monitor gateway health:
   - Check gateway status in Power BI Admin portal
   - Review gateway logs for errors

3. Update documentation:
   - Update gateway inventory
   - Document new gateway cluster details

4. Clean up old gateway (after 24-48 hours):
   Get-DataGatewayCluster | Where-Object { $_.Name -eq "OnPremGatewayCluster01" } | Remove-DataGatewayCluster
#>
