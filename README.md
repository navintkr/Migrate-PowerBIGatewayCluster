# README: Power BI Gateway Migration Script

## Overview
This script automates the migration of Power BI datasets and data sources when an on-premises gateway cluster approaches the hard limit of 1,000 data sources.

## The Problem
- Power BI on-premises and VNet gateways have a **hard limit of 1,000 data sources** per cluster
- This limit is fixed regardless of data source type
- Adding new gateway members does NOT increase this limit
- When the limit is reached, you must create a new gateway cluster and migrate

## The Solution
This repository provides two approaches to handle the gateway migration:

### Approach 1: Full Migration (Create New Datasources)
Automates:
1. ✅ Monitoring data source count
2. ✅ Creating a new gateway cluster when threshold is reached
3. ✅ Cloning all data sources to the new gateway
4. ✅ Rebinding datasets to the new gateway cluster
5. ✅ Providing cleanup guidance

### Approach 2: Dataset Rebinding (Use Existing Datasources)
For scenarios where you already have datasources on both gateways:
1. ✅ Finds matching datasources on both gateways
2. ✅ Rebinds datasets to use new gateway's existing datasources
3. ✅ No duplicate datasources created
4. ✅ Faster migration with less cleanup

## Files

### `Migrate-PowerBIGatewayCluster.ps1`
**Full migration script** - Creates new gateway, clones datasources, and rebinds datasets.
- Use when: Starting fresh with a new gateway cluster
- Creates duplicate datasources on new gateway
- Requires credential reconfiguration

### `Rebind-DatasetsToNewGateway.ps1`
**Dataset rebinding script** - Switches datasets to existing datasources on new gateway.
- Use when: Both gateways already have matching datasources
- No datasource duplication
- Faster execution
- Credentials already configured on new gateway

### `Example-GatewayMigration.ps1`
Example configuration and usage guide for full migration approach.

### `Test-GatewayMigration-Local.ps1`
Local testing script with mock data - test the migration logic without Azure resources.

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

### Option 1: Full Migration (New Gateway + Clone Data Sources)

**Use when:** You're creating a brand new gateway cluster and need to clone everything.

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

### Option 2: Dataset Rebinding (Use Existing Data Sources)

**Use when:** Both gateways already have matching data sources and you just need to switch datasets over.

**Migrate Everything:**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-gateway-guid" `
    -NewGatewayId "new-gateway-guid" `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

**Partial Migration - First 100 Data Sources:**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-gateway-guid" `
    -NewGatewayId "new-gateway-guid" `
    -MaxDatasourcesToMigrate 100 `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

**Partial Migration - First 50 Datasets:**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-gateway-guid" `
    -NewGatewayId "new-gateway-guid" `
    -MaxDatasetsToMigrate 50 `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

**Migrate Specific Data Sources Only:**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-gateway-guid" `
    -NewGatewayId "new-gateway-guid" `
    -IncludeDatasourceNames @("SQL-Prod-Server1", "SQL-Prod-Server2") `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

**Exclude Specific Data Sources:**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-gateway-guid" `
    -NewGatewayId "new-gateway-guid" `
    -ExcludeDatasourceNames @("Dev-Server", "Test-Server") `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```

**Benefits:**
- ✅ No duplicate data sources created
- ✅ Faster migration (no data source creation)
- ✅ Credentials already configured on new gateway
- ✅ Cleaner final state
- ✅ **Supports partial/phased migration**

### Dry Run (Recommended First!)

Both scripts support `-WhatIf` mode to preview changes:

```powershell
.\Migrate-PowerBIGatewayCluster.ps1 `
    [... same parameters ...] `
    -WhatIf

.\Rebind-DatasetsToNewGateway.ps1 `
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

### Migrate-PowerBIGatewayCluster.ps1

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `CurrentGatewayName` | Yes | Name of the current gateway cluster | - |
| `NewGatewayNamePrefix` | Yes | Prefix for new gateway (will append 01, 02, etc.) | - |
| `RecoveryKey` | Yes | Gateway recovery key (SecureString) | - |
| `Region` | No | Azure region for gateway metadata registration* | WestUS2 |
| `Threshold` | No | Data source count threshold to trigger migration | 900 |
| `TenantId` | Yes | Azure AD Tenant ID | - |
| `ClientId` | Yes | Azure AD App Client ID | - |
| `ClientSecret` | Yes | Azure AD App Client Secret (SecureString) | - |
| `WhatIf` | No | Run in simulation mode without making changes | false |

*_Note: The Region parameter specifies where gateway metadata is stored in Azure, NOT where the physical gateway software runs. The gateway software remains on-premises. Choose a region close to your Power BI tenant for best performance._

### Rebind-DatasetsToNewGateway.ps1

| Parameter | Required | Description |
|-----------|----------|-------------|
| `OldGatewayId` | Yes | Gateway ID of the current gateway |
| `NewGatewayId` | Yes | Gateway ID of the new gateway |
| `TenantId` | Yes | Azure AD Tenant ID |
| `ClientId` | Yes | Azure AD App Client ID |
| `ClientSecret` | Yes | Azure AD App Client Secret (SecureString) |
| `MaxDatasourcesToMigrate` | No | Maximum number of data sources to migrate (0 = all) |
| `MaxDatasetsToMigrate` | No | Maximum number of datasets to migrate (0 = all) |
| `IncludeDatasourceNames` | No | Array of data source names to migrate (empty = all) |
| `ExcludeDatasourceNames` | No | Array of data source names to exclude from migration |
| `WhatIf` | No | Run in simulation mode without making changes |

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

### Two Migration Approaches

**Choose the right script for your scenario:**

| Scenario | Use This Script | Why |
|----------|----------------|-----|
| Creating a brand new gateway cluster | `Migrate-PowerBIGatewayCluster.ps1` | Clones everything from scratch |
| Both gateways already configured | `Rebind-DatasetsToNewGateway.ps1` | Faster, no duplication |
| Need to test locally first | `Test-GatewayMigration-Local.ps1` | Safe testing with mock data |
| **Migrate in phases (100-200 at a time)** | `Rebind-DatasetsToNewGateway.ps1` | **Supports partial migration** |
| Have 1000 connections, want to move gradually | `Rebind-DatasetsToNewGateway.ps1` | **Use filters or limits** |

### Credentials
⚠️ **Data source credentials cannot be automatically migrated** due to security restrictions. 

**For Migrate-PowerBIGatewayCluster.ps1:**
1. After migration, go to Power BI Service → Settings → Manage gateways
2. For each data source on the new gateway, configure credentials
3. Test with a dataset refresh

**For Rebind-DatasetsToNewGateway.ps1:**
- Credentials should already be configured on new gateway's data sources
- Only rebinding happens, no credential work needed

### Verification Period
- **Do NOT delete the old gateway immediately**
- Monitor for 24-48 hours
- Verify all datasets refresh successfully
- Check for any errors in reports

### Understanding the Power BI Gateway API Limitation

⚠️ **Important:** Power BI's REST API does NOT support moving/transferring data sources between gateways. You cannot:
- Move a data source object from Gateway A to Gateway B
- Update a data source's gateway ID
- "Reassign" a data source to a different gateway

This is why we offer two approaches:
1. **Clone approach**: Create new data sources on new gateway (duplicates exist temporarily)
2. **Rebind approach**: Use existing data sources on new gateway (no duplication)

## Phased Migration Strategy

### Why Migrate in Phases?

When you have many connections (e.g., 1,000 data sources), migrating everything at once can be risky. A phased approach allows you to:
- ✅ Test and validate small batches
- ✅ Minimize disruption to business operations
- ✅ Roll back easily if issues occur
- ✅ Monitor performance incrementally

### Recommended Phased Approach

**Phase 1: Test with Low-Impact Data Sources (10-20)**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -IncludeDatasourceNames @("Test-DS1", "Test-DS2") `
    -WhatIf  # Dry run first
```

**Phase 2: Migrate First Batch (100-200)**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -MaxDatasourcesToMigrate 100 `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```

**Phase 3: Monitor for 24-48 Hours**
- Check dataset refresh success rates
- Monitor gateway performance
- Review error logs

**Phase 4: Continue with Next Batch**
```powershell
# Exclude already migrated datasources
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -MaxDatasourcesToMigrate 200 `
    -ExcludeDatasourceNames @("Already-Migrated-DS1", "Already-Migrated-DS2") `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```

**Phase 5: Final Batch**
```powershell
# Migrate remaining datasources
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```

### Tracking Your Migration Progress

Keep a log of migrated data sources:
```powershell
# Run with WhatIf to get a list first
.\Rebind-DatasetsToNewGateway.ps1 -WhatIf ... | Tee-Object -FilePath "migration-log.txt"
```

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

### Does it move all connections or can I specify how many?

**Answer:** By default, both scripts migrate ALL matching connections. However, the `Rebind-DatasetsToNewGateway.ps1` script now supports:

- ✅ **Limit by count**: Migrate only first N data sources or datasets
- ✅ **Include specific**: Migrate only named data sources
- ✅ **Exclude specific**: Skip certain data sources
- ✅ **Phased migration**: Gradually move connections in batches

**Examples:**
```powershell
# Move only 100 datasources
-MaxDatasourcesToMigrate 100

# Move only 50 datasets
-MaxDatasetsToMigrate 50

# Move specific datasources only
-IncludeDatasourceNames @("Server1", "Server2")

# Skip certain datasources
-ExcludeDatasourceNames @("Dev", "Test")
```

For 1,000 connections, we recommend migrating 100-200 at a time, testing each batch before continuing.

### "Gateway cluster not found"
- Verify gateway name spelling
- Ensure you're connected: `Connect-DataGatewayServiceAccount`
- Check permissions: must be gateway admin

### "Failed to obtain access token"
- Verify Tenant ID, Client ID, Client Secret
- Check app registration has correct API permissions
- Ensure admin consent was granted

### "Failed to create data source"
- Check if data source type is supported
- Verify connection details are valid
- Some data source types may need manual creation

### "Dataset rebinding failed"
- Ensure app has `Dataset.ReadWrite.All` permission
- Check if you have workspace admin rights
- Some datasets may need manual rebinding

### "No matching data sources found" (Rebind script)
- Ensure data sources exist on both gateways
- Verify connection details match exactly (server name, database name, etc.)
- Data source names don't need to match, but connection details do

### Which Script Should I Use?

**Use `Migrate-PowerBIGatewayCluster.ps1` if:**
- You're creating a new gateway from scratch
- You want automated gateway cluster creation
- You want monitoring based on threshold

**Use `Rebind-DatasetsToNewGateway.ps1` if:**
- Both gateways already exist and are configured
- Data sources already exist on both gateways
- You want to avoid duplicate data sources
- You just need to switch datasets over

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
- v1.2 (2025-11-13): Added partial/phased migration support with filters and limits
- v1.1 (2025-11-13): Added dataset rebinding script for existing data sources
- v1.0 (2025-11-13): Initial release with full automation
