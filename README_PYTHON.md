# Power BI Gateway Migration Tool (Python)

Python script to automate migration of Power BI datasets from one gateway cluster to another using the Power BI REST API.

## Prerequisites

- **Python 3.x** with `requests` library
- **Gateway Admin Rights**: User must be an administrator on both source and target gateways
- **Dataset Permissions**: User must have write access to datasets being migrated
- **Power BI License**: Pro or Premium Per User license

## Installation

```bash
pip install requests
```

## Configuration

Edit `migrate_gateway_connection.py` and update these variables:

```python
tenant_id     = "YOUR-TENANT-ID-HERE"        # Azure AD Tenant ID
old_gateway   = "OLD-GATEWAY-ID-HERE"        # Source gateway cluster ID
new_gateway   = "NEW-GATEWAY-ID-HERE"        # Target gateway cluster ID
datasource_name_filter = ""                  # Optional: Filter by datasource name
what_if       = True                         # Set to False for actual migration
```

## Usage

1. **Run the script:**
   ```bash
   python migrate_gateway_connection.py
   ```

2. **Authenticate** using device code flow when prompted

3. **Review** the migration plan (in what-if mode)

4. **Execute** by setting `what_if = False` and running again

## How It Works

1. Authenticates using interactive device code flow
2. Retrieves datasources from both gateways
3. Scans all accessible workspaces for datasets using the old gateway
4. Uses Power BI REST API `BindToGateway` endpoint to rebind datasets
5. Optionally triggers dataset refresh to validate connection

## Important: Gateway Type Limitations

### Enterprise Gateway (Recommended)

✅ **Fully automated migration works when:**
- Both source and target are **enterprise gateways**
- User is gateway admin on both gateways
- Datasources are pre-configured on target gateway

### Personal Gateway (Limitations)

⚠️ **Personal gateways have API restrictions:**
- Cannot read datasources via API (returns 401 Unauthorized)
- Cannot automatically create datasources via API
- Requires manual datasource configuration before migration

**Required Manual Steps for Personal Gateway:**

1. Open Power BI Service → Manage Gateways
2. Select the target personal gateway
3. Manually add datasources with **exact same connection details** as source gateway
4. Configure and save credentials
5. Then run the migration script

Without this manual setup, migration will fail with:
```
DMTS_CanNotFindMatchingDatasourceInGatewayError
```

## What-If Mode

The script defaults to **what-if mode** (`what_if = True`), which:
- Shows what would be migrated
- Doesn't make any actual changes
- Safe to run multiple times

Set `what_if = False` only when ready to perform actual migration.

## Error Handling

The script includes fallback mechanisms:
- Discovers compatible gateways before migration
- Attempts `BindToGateway` API (primary method)
- Falls back to `UpdateDatasources` for supported types
- Provides manual instructions if automated methods fail

## Common Errors

### "CanNotFindMatchingDatasourceInGatewayError"
**Cause:** Target gateway doesn't have matching datasource configured

**Solution:** Manually create datasource on target gateway with same connection details

### "User must be added as data source user"
**Cause:** User lacks permissions on target gateway datasources

**Solution:** Add user as datasource user in gateway settings

### "Gateway not compatible"
**Cause:** Dataset cannot be rebound to target gateway type

**Solution:** Check DiscoverGateways output for compatible gateways

## Support

For Power BI REST API details, see [Microsoft Documentation](https://learn.microsoft.com/en-us/rest/api/power-bi/).

## License

This tool is provided as-is. Test in non-production environments before production use.
