# README: Power BI Gateway Migration Script

## Overview
This script automates the migration of Power BI datasets and data sources when an on-premises gateway cluster approaches the hard limit of 1,000 data sources.

## The Problem
- Power BI on-premises and VNet gateways have a **hard limit of 1,000 data sources** per cluster
- This limit is fixed regardless of data source type
- Adding new gateway members does NOT increase this limit
- When the limit is reached, you must create a new gateway cluster and migrate

## The Solution
This script automates:
1. ✅ Monitoring data source count
2. ✅ Creating a new gateway cluster when threshold is reached
3. ✅ Cloning all data sources to the new gateway
4. ✅ Rebinding datasets to the new gateway cluster
5. ✅ Providing cleanup guidance

## Files

### `Migrate-PowerBIGatewayCluster.ps1`
Main migration script with full automation and error handling.

### `Example-GatewayMigration.ps1`
Example configuration and usage guide.

### `Check-FabricCapacityReservations.ps1`
(Unrelated - for checking Fabric capacity reservation status)

## Prerequisites

### 1. Install PowerShell Module
```powershell
Install-Module -Name DataGateway -Scope CurrentUser
```

### 2. Create Azure AD App Registration
1. Go to [Azure Portal](https://portal.azure.com) → Azure Active Directory → App registrations
2. Click "New registration"
   - Name: `PowerBI-Gateway-Migration`
   - Supported account types: Accounts in this organizational directory only
3. After creation, note the **Application (client) ID** and **Directory (tenant) ID**
4. Go to "API permissions"
   - Add permission → Power BI Service → Delegated permissions
   - Add: `Tenant.Read.All`, `Dataset.ReadWrite.All`, `Gateway.ReadWrite.All`
   - Grant admin consent
5. Go to "Certificates & secrets"
   - New client secret → Add description → Add
   - **Copy the secret value immediately** (you can't see it again!)

### 3. Gateway Requirements
- Gateway admin permissions
- Gateway recovery key (from original gateway setup)
- At least one gateway member installed and registered

## Usage

### Basic Usage

```powershell
.\Migrate-PowerBIGatewayCluster.ps1 `
    -CurrentGatewayName "OnPremGatewayCluster01" `
    -NewGatewayNamePrefix "OnPremGatewayCluster" `
    -RecoveryKey (Read-Host -AsSecureString -Prompt "Recovery Key") `
    -Region "WestUS2" `
    -Threshold 900 `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

### Dry Run (Recommended First!)

```powershell
.\Migrate-PowerBIGatewayCluster.ps1 `
    [... same parameters ...] `
    -WhatIf
```

### Check Current Gateway Status

```powershell
# Connect to gateway service
Connect-DataGatewayServiceAccount

# List all gateway clusters
Get-DataGatewayCluster

# Check data source count for specific gateway
$gateway = Get-DataGatewayCluster | Where-Object { $_.Name -eq "OnPremGatewayCluster01" }
$datasources = Get-DataGatewayClusterDatasource -GatewayClusterId $gateway.Id
Write-Host "Data sources: $($datasources.Count) / 1000"
```

## Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `CurrentGatewayName` | Yes | Name of the current gateway cluster | - |
| `NewGatewayNamePrefix` | Yes | Prefix for new gateway (will append 01, 02, etc.) | - |
| `RecoveryKey` | Yes | Gateway recovery key (SecureString) | - |
| `Region` | No | Azure region for new gateway | WestUS2 |
| `Threshold` | No | Data source count threshold to trigger migration | 900 |
| `TenantId` | Yes | Azure AD Tenant ID | - |
| `ClientId` | Yes | Azure AD App Client ID | - |
| `ClientSecret` | Yes | Azure AD App Client Secret (SecureString) | - |
| `WhatIf` | No | Run in simulation mode without making changes | false |

## What Happens During Migration

1. **Pre-flight Checks**
   - Verifies DataGateway module is installed
   - Connects to Data Gateway Service
   - Retrieves current gateway information
   - Checks if threshold is reached

2. **New Gateway Creation**
   - Determines next cluster number
   - Creates new gateway cluster with recovery key
   - Registers in specified region

3. **Data Source Cloning**
   - Retrieves all data sources from old gateway
   - Creates equivalent data sources on new gateway
   - **Note:** Credentials must be manually configured

4. **Dataset Rebinding**
   - Finds all datasets using old gateway
   - Updates dataset bindings to new gateway
   - Maintains workspace associations

5. **Post-Migration**
   - Provides summary report
   - Lists next steps for verification
   - Keeps old gateway active for verification period

## Important Notes

### Credentials
⚠️ **Data source credentials cannot be automatically migrated** due to security restrictions. After migration:
1. Go to Power BI Service → Settings → Manage gateways
2. For each data source on the new gateway, configure credentials
3. Test with a dataset refresh

### Verification Period
- **Do NOT delete the old gateway immediately**
- Monitor for 24-48 hours
- Verify all datasets refresh successfully
- Check for any errors in reports

### Cleanup
After verification, remove the old gateway:
```powershell
$oldGateway = Get-DataGatewayCluster | Where-Object { $_.Name -eq "OnPremGatewayCluster01" }
Remove-DataGatewayCluster -GatewayClusterId $oldGateway.Id
```

## Automated Monitoring

You can schedule this script to run daily:

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-File "C:\Scripts\Migrate-PowerBIGatewayCluster.ps1" [parameters]'
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "PowerBI-Gateway-Monitor" -Action $action -Trigger $trigger
```

## Troubleshooting

### "Gateway cluster not found"
- Verify gateway name spelling
- Ensure you're connected: `Connect-DataGatewayServiceAccount`
- Check permissions: must be gateway admin

### "Failed to obtain access token"
- Verify Tenant ID, Client ID, Client Secret
- Check app registration has correct API permissions
- Ensure admin consent was granted

### "Failed to create datasource"
- Check if datasource type is supported
- Verify connection details are valid
- Some datasource types may need manual creation

### "Dataset rebinding failed"
- Ensure app has `Dataset.ReadWrite.All` permission
- Check if you have workspace admin rights
- Some datasets may need manual rebinding

## Limitations

1. **Credential Migration**: Credentials must be manually reconfigured
2. **Custom Connectors**: May need manual setup on new gateway
3. **VNet Gateways**: Some additional networking configuration may be required
4. **Permissions**: Requires Power BI admin or workspace admin rights

## Support & References

- [Power BI Gateway Documentation](https://learn.microsoft.com/power-bi/connect-data/service-gateway-onprem)
- [Gateway Data Source Limits](https://learn.microsoft.com/power-bi/connect-data/service-gateway-data-sources)
- [Power BI REST API](https://learn.microsoft.com/rest/api/power-bi/)
- [DataGateway PowerShell Module](https://learn.microsoft.com/powershell/module/datagateway/)

## License
MIT License - Feel free to modify and distribute

## Version History
- v1.0 (2025-11-13): Initial release with full automation
