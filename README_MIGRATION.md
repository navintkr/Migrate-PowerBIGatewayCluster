# Power BI Gateway Connection Migration Script

## Overview
This Python script migrates Power BI datasets from one gateway to another by rebinding datasource connections. It works at the tenant level, scanning all accessible workspaces to find datasets using specific datasources on the old gateway and rebinding them to the new gateway.

## Prerequisites

### 1. Python Requirements
- Python 3.7 or higher
- Install required package:
  ```powershell
  pip install requests
  ```

### 2. User Authentication (Recommended)
**The script uses interactive device code authentication** - you simply log in with your own user credentials when prompted.

**Requirements:**
- You must be an admin on both gateways (old and new)
- You must have access to workspaces containing the datasets
- You need a browser to complete the authentication

**No additional setup required!** Just run the script and follow the login prompts.

### 3. Alternative: Service Principal Authentication
If you need unattended/automated execution, you can configure service principal authentication:

<details>
<summary>Click to expand service principal setup instructions</summary>

The service principal must have:

1. **Gateway Admin Access**: Add the service principal as an admin on BOTH gateways
2. **Workspace Access**: Add as Admin or Member to workspaces with datasets
3. **Power BI API Permissions**: Tenant.Read.All, Dataset.ReadWrite.All

Then update the script to set `use_device_code = False` and configure the client credentials.

</details>

## Configuration

Edit the `migrate_gateway_connection.py` file to configure:

```python
# Authentication method
use_device_code = True  # Keep True for interactive login

# Gateway IDs
old_gateway   = "OLD-GATEWAY-ID-HERE"
new_gateway   = "NEW-GATEWAY-ID-HERE"

# Filter by datasource name (optional - leave empty to migrate all datasources)
datasource_name_filter = ""

# Workspace IDs (optional - leave empty to scan all accessible workspaces)
workspace_ids = []  # Example: ["workspace-id-1", "workspace-id-2"]

# What-if mode (set to False to perform actual migration)
what_if = True
```

## Usage

### Step 1: Test Run (What-If Mode)
First, run in what-if mode to see what would be migrated without making changes:

```powershell
python migrate_gateway_connection.py
```

**The script will prompt you to authenticate:**
1. It will display a URL (https://microsoft.com/devicelogin) and a code
2. Open the URL in your browser
3. Enter the code when prompted
4. Sign in with your credentials (gateway admin account)
5. Once authenticated, the script will continue automatically

The script will:
- List all datasources found on the old gateway
- Show which datasources can be mapped to the new gateway
- Display all datasets that would be migrated
- Show update details without making actual changes

### Step 2: Actual Migration
Once you've verified the what-if output, set `what_if = False` in the script and run:

```powershell
python migrate_gateway_connection.py
```

## How It Works

1. **Authentication**: Uses OAuth client credentials flow to get a Power BI access token
2. **Datasource Discovery**: 
   - Gets datasources from the old gateway
   - Attempts to get datasources from the new gateway (may fail for personal gateways)
   - Filters by datasource name if specified
3. **Datasource Mapping**: Maps old datasources to new datasources based on connection properties (server, database, etc.)
4. **Workspace Scanning**: Scans all accessible workspaces to find datasets
5. **Dataset Detection**: Identifies datasets using the old gateway datasources
6. **Migration**: Updates dataset bindings to use the new gateway

## Output Example

```
Authenticating with Azure AD...
✓ Authentication successful

Getting datasources from old gateway (e9b74af7-3c21-40eb-803d-7b5a03451eb2)...
✓ Found 1 datasources on old gateway

Getting datasources from new gateway (3289ad78-37f2-42e2-8574-525443fefbeb)...
✓ Found 2 datasources on new gateway

Filtered to 1 datasource(s) matching name: 'gateway-demo-conn'
✓ Mapped: gateway-demo-conn -> gateway-demo-conn-new

1 datasource(s) mapped successfully.

Scanning for datasets using the old gateway datasources...
Found 5 accessible workspaces
  Found: Sales Report in workspace 'Finance'
  Found: Customer Dashboard in workspace 'Marketing'

✓ Scanned 23 datasets across 5 workspaces
✓ Found 2 dataset(s) using the target datasource(s)

============================================================
WHAT-IF MODE: No actual changes will be made
============================================================

Processing: Sales Report (Workspace: Finance)
  [WHAT-IF] Would update 1 datasource binding(s)
    - Type: Sql, Server: sql-server.database.windows.net, DB: SalesDB

Processing: Customer Dashboard (Workspace: Marketing)
  [WHAT-IF] Would update 1 datasource binding(s)
    - Type: Sql, Server: sql-server.database.windows.net, DB: CustomersDB

============================================================
SUMMARY
============================================================
Total datasets processed: 2
Successful: 2

⚠ WHAT-IF MODE was enabled. No actual changes were made.
Set what_if = False to perform the actual migration.
```

## Troubleshooting

### Error: "401 Unauthorized" when accessing gateways
**Solution**: Ensure the service principal is added as an admin to both gateways.

### Error: "Found 0 accessible workspaces"
**Solution**: Either:
- Add the service principal as a member/admin to workspaces containing the datasets
- Specify workspace IDs directly in the `workspace_ids` configuration

### Error: "No datasets found using the specified datasources"
**Possible causes**:
- The datasource name filter doesn't match any datasources
- No datasets are currently using the old gateway datasource
- Service principal doesn't have access to workspaces with datasets

### Personal Gateway Limitations
If the new gateway is a personal gateway:
- The script cannot read datasources from it (by design)
- The script will use connection details from the old gateway
- Power BI will automatically match to existing datasources on the new gateway
- You may need to manually configure credentials on the new gateway after migration

## Post-Migration Steps

After running the migration:

1. **Verify Dataset Connections**:
   - Open each migrated dataset in Power BI Service
   - Check Settings → Data source credentials
   - Ensure the dataset is bound to the new gateway

2. **Update Credentials** (if needed):
   - If credentials need to be reconfigured, update them in Settings → Data source credentials

3. **Test Dataset Refresh**:
   - Manually trigger a refresh for each migrated dataset
   - Verify the refresh succeeds with the new gateway

4. **Monitor Scheduled Refreshes**:
   - Check that scheduled refreshes continue to work
   - Review refresh history for any errors

## Support

For issues or questions:
- Review the Power BI Admin Portal for gateway status
- Check dataset refresh history for error details
- Ensure all prerequisites are met (permissions, gateway access, workspace access)
