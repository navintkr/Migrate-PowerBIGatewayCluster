# README: Power BI Gateway Migration Script

## Overview
Automates load balancing and redistribution of Power BI data sources across gateway clusters when approaching the 1,000 data source limit. Split connections between multiple gateways to maintain capacity for growth.

## The Problem
- Power BI on-premises and VNet gateways have a **hard limit of 1,000 data sources** per cluster
- This limit is fixed regardless of data source type
- Adding new gateway members to a cluster does NOT increase this limit
- When approaching 1,000 connections, you **cannot add more** until you free up capacity
- **Solution:** Create a new gateway cluster and redistribute/rebalance connections across both clusters

## The Solution
This repository provides automated tools to redistribute and load balance connections across multiple gateway clusters:

### Approach 1: Automated Redistribution (Create New Cluster)
Creates a new gateway cluster and automatically redistributes connections when threshold is reached:
1. ✅ Monitors data source count on existing gateway
2. ✅ Creates a new gateway cluster when threshold is reached (e.g., 900 out of 1,000)
3. ✅ Moves a portion of data sources to the new gateway (not all)
4. ✅ Both gateways now have capacity for growth
5. ✅ Provides cleanup guidance

**Use Case:** Automatic capacity management with threshold monitoring

### Approach 2: Manual Load Balancing (Use Existing Gateways)
For scenarios where you already have multiple gateways and need to redistribute workloads:
1. ✅ Finds matching data sources on both gateways
2. ✅ Moves specified data sources (by count, name, or filter)
3. ✅ No duplicate data sources created
4. ✅ Faster execution with granular control

**Use Case:** Redistribute specific workloads, separate environments (Dev/Prod), or balance load manually

## Files

### `Migrate-PowerBIGatewayCluster.ps1`
**Automated gateway creation and redistribution** - Creates new gateway cluster and redistributes connections automatically.
- Use when: Monitoring capacity and need automatic redistribution at threshold
- Creates gateway cluster automatically
- Moves portion of connections to new gateway (configurable)
- Requires credential reconfiguration for moved connections

### `Rebind-DatasetsToNewGateway.ps1`
**Manual load balancing and workload distribution** - Redistributes connections between existing gateways.
- Use when: Both gateways already exist and configured
- Granular control: move by count, name, or filter
- No data source duplication
- Credentials already configured on target gateway
- Faster execution

**Common Scenarios:**
- Split 1,000 connections → 500/500 across two gateways
- Move HR/Finance workloads to dedicated gateway
- Separate Dev/Test from Production environments
- Rebalance after adding new gateway capacity

### `Example-GatewayMigration.ps1`
Example configuration and usage guide for automated redistribution approach.

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

### Option 1: Automated Capacity Management (Create New Cluster + Redistribute)

**Use when:** You want automated monitoring and redistribution when approaching the 1,000 limit.

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

**What it does:** 
- Monitors Gateway 01 (if it hits 900+ connections)
- Creates Gateway 02 automatically
- Redistributes connections between both gateways
- Both gateways now have capacity for growth

### Option 2: Manual Load Balancing (Redistribute Between Existing Gateways)

**Use when:** You already have multiple gateways and need to redistribute workloads strategically.

**Example A: Balance Load - Split 500 Connections**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "gateway-01-with-950-connections" `
    -NewGatewayId "gateway-02-new-cluster" `
    -MaxDatasourcesToMigrate 500 `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```
**Result:** Gateway 01 has 450 connections (550 slots free), Gateway 02 has 500 connections (500 slots free)

**Example B: Separate Workloads by Department**

**Example B: Separate Workloads by Department**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "gateway-shared" `
    -NewGatewayId "gateway-hr-finance" `
    -IncludeDatasourceNames @("HR-Server1", "HR-Server2", "Finance-DB1") `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```
**Result:** HR/Finance workloads on dedicated gateway, production stays on shared gateway

**Example C: Move Everything Except Production**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "gateway-all" `
    -NewGatewayId "gateway-nonprod" `
    -ExcludeDatasourceNames @("Prod-DB1", "Prod-DB2", "Prod-Server1") `
    -TenantId "YOUR-TENANT-ID" `
    -ClientId "YOUR-CLIENT-ID" `
    -ClientSecret (Read-Host -AsSecureString -Prompt "Client Secret")
```
**Result:** Production stays, dev/test/staging moves to new gateway

**Example D: Gradual Redistribution (100 at a Time)**
```powershell
# Phase 1: Move first 100
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "gateway-01" `
    -NewGatewayId "gateway-02" `
    -MaxDatasourcesToMigrate 100 `
    -TenantId "..." -ClientId "..." -ClientSecret $secret

# Phase 2: Move next 100 after validation
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "gateway-01" `
    -NewGatewayId "gateway-02" `
    -MaxDatasourcesToMigrate 100 `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```
**Result:** Gradual, low-risk redistribution with validation between phases

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

### Typical Redistribution Scenarios

**You are NOT moving all 1,000 connections.** You're redistributing them for capacity management:

| Current State | Action | Result |
|---------------|--------|--------|
| Gateway 01: 950 connections | Move 400 to Gateway 02 | Gateway 01: 550 (450 free)<br>Gateway 02: 400 (600 free) |
| Gateway 01: 1000 connections | Move 500 to Gateway 02 | Gateway 01: 500 (500 free)<br>Gateway 02: 500 (500 free) |
| Gateway 01: 850 mixed workloads | Move HR/Finance to Gateway 02 | Gateway 01: Production only<br>Gateway 02: HR/Finance isolated |

**Goal:** Both gateways have room for new connections and future growth.

### Choose the Right Approach

**Choose the right script for your scenario:**

| Scenario | Use This Script | Why |
|----------|----------------|-----|
| Need automated capacity monitoring | `Migrate-PowerBIGatewayCluster.ps1` | Monitors and acts at threshold |
| Both gateways already configured | `Rebind-DatasetsToNewGateway.ps1` | Faster, granular control |
| Need to test locally first | `Test-GatewayMigration-Local.ps1` | Safe testing with mock data |
| **Redistribute 500 out of 1000 connections** | `Rebind-DatasetsToNewGateway.ps1` | **Use MaxDatasourcesToMigrate** |
| **Separate HR/Finance workloads** | `Rebind-DatasetsToNewGateway.ps1` | **Use IncludeDatasourceNames filter** |
| **Move everything except Production** | `Rebind-DatasetsToNewGateway.ps1` | **Use ExcludeDatasourceNames filter** |

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

### Why Redistribute in Phases?

When you have many connections approaching the 1,000 limit, redistributing in batches allows you to:
- ✅ Test and validate small batches before continuing
- ✅ Minimize disruption to business operations
- ✅ Roll back easily if issues occur
- ✅ Monitor performance incrementally
- ✅ **NOT moving all 1,000** - just redistributing for capacity

### Recommended Phased Approach for Load Balancing

**Scenario:** Gateway 01 has 950 connections, approaching limit

**Phase 1: Test with Low-Impact Data Sources (10-20)**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -IncludeDatasourceNames @("Test-DS1", "Test-DS2") `
    -WhatIf  # Dry run first
```

**Phase 2: Redistribute First Batch (100-200)**
```powershell
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -MaxDatasourcesToMigrate 200 `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```
**Result:** Gateway 01 now has 750 connections (250 slots free), Gateway 02 has 200 (800 slots free)

**Phase 3: Monitor for 24-48 Hours**
- Check dataset refresh success rates
- Monitor gateway performance
- Review error logs
- **Both gateways now have capacity for new connections**

**Phase 4: Continue with Next Batch if Needed**
```powershell
# Move another 200 if more capacity needed
.\Rebind-DatasetsToNewGateway.ps1 `
    -OldGatewayId "old-id" `
    -NewGatewayId "new-id" `
    -MaxDatasourcesToMigrate 200 `
    -TenantId "..." -ClientId "..." -ClientSecret $secret
```
**Result:** Gateway 01: 550 connections (450 free), Gateway 02: 400 connections (600 free)

**Phase 5: Both Gateways Balanced**
- Stop when both gateways have adequate capacity for growth
- You do NOT need to move all connections
- Goal is capacity management, not full migration

### Tracking Your Redistribution Progress

Keep a log of redistributed data sources:
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

**Answer:** By default, the scripts can redistribute ALL matching connections, but the `Rebind-DatasetsToNewGateway.ps1` script provides granular control:

**Key Point:** You are **NOT moving all 1,000 connections**. You're redistributing some to free up capacity.

- ✅ **Limit by count**: Move only first N data sources or datasets
- ✅ **Include specific**: Move only named data sources  
- ✅ **Exclude specific**: Skip certain data sources
- ✅ **Phased redistribution**: Gradually rebalance in batches

**Examples:**
```powershell
# Redistribute 500 out of 950 connections
-MaxDatasourcesToMigrate 500

# Move only 50 datasets
-MaxDatasetsToMigrate 50

# Move specific datasources only (HR/Finance workload)
-IncludeDatasourceNames @("HR-Server1", "Finance-DB1")

# Skip production datasources (move dev/test)
-ExcludeDatasourceNames @("Prod-DB1", "Prod-Server1")
```

**Recommended for 1,000 connections:** Redistribute 400-500 to new gateway, keeping 500-600 on original. Both now have capacity for growth.

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
- You want automated capacity monitoring and redistribution
- You want to create a new gateway automatically at threshold
- You want automated workload balancing

**Use `Rebind-DatasetsToNewGateway.ps1` if:**
- Both gateways already exist and are configured
- Data sources already exist on both gateways
- You want granular control over what moves (by count, name, or filter)
- You want to redistribute specific workloads (HR, Finance, Dev/Test)
- You want to avoid duplicate data sources

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
- v1.2 (2025-11-13): Added partial/phased redistribution support with filters and limits
- v1.1 (2025-11-13): Added dataset rebinding script for load balancing across gateways
- v1.0 (2025-11-13): Initial release with automated capacity management
