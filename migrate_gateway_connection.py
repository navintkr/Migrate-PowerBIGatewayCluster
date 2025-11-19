import requests
import json
import sys
import time

# -------------------------------------------------------
# CONFIG - Update these values or pass as command line args
# -------------------------------------------------------
tenant_id     = "YOUR-TENANT-ID-HERE"  # Azure AD Tenant ID
use_device_code = True  # Set to True to use interactive login (recommended for gateway admins)
old_gateway   = "OLD-GATEWAY-ID-HERE"  # Source gateway cluster ID
new_gateway   = "NEW-GATEWAY-ID-HERE"  # Target gateway cluster ID
datasource_name_filter = ""  # Filter by datasource name (leave empty to migrate all)
workspace_ids = []  # Leave empty to scan all accessible workspaces, or specify workspace IDs
what_if       = True  # Set to False to actually perform the migration

# Power BI public client ID (official Microsoft Power BI app)
client_id = "ea0616ba-638b-4df5-95b9-636659ae5121"
scope = "https://analysis.windows.net/powerbi/api/.default"
base_url = "https://api.powerbi.com/v1.0/myorg"

# -------------------------------------------------------
# AUTH – Device Code Flow (Interactive Login)
# -------------------------------------------------------
print("="*60)
print("AUTHENTICATION")
print("="*60)

if use_device_code:
    print("Using interactive device code authentication...")
    print("You will authenticate with your own user credentials.\n")
    
    # Request device code
    device_code_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/devicecode"
    device_code_data = {
        "client_id": client_id,
        "scope": scope
    }
    
    device_resp = requests.post(device_code_url, data=device_code_data)
    device_resp.raise_for_status()
    device_info = device_resp.json()
    
    print("="*60)
    print(f"USER ACTION REQUIRED:")
    print(f"1. Go to: {device_info['verification_uri']}")
    print(f"2. Enter code: {device_info['user_code']}")
    print("="*60)
    print("Waiting for authentication...")
    
    # Poll for token
    token_url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    token_data = {
        "client_id": client_id,
        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        "device_code": device_info['device_code']
    }
    
    # Poll until user completes authentication
    interval = device_info.get('interval', 5)
    expires_in = device_info.get('expires_in', 900)
    start_time = time.time()
    
    while True:
        if time.time() - start_time > expires_in:
            print("✗ Authentication timeout. Please try again.")
            sys.exit(1)
        
        time.sleep(interval)
        token_resp = requests.post(token_url, data=token_data)
        
        if token_resp.status_code == 200:
            access_token = token_resp.json()["access_token"]
            print("✓ Authentication successful!\n")
            break
        elif token_resp.status_code == 400:
            error = token_resp.json().get('error')
            if error == 'authorization_pending':
                # Still waiting for user
                continue
            elif error == 'authorization_declined':
                print("✗ Authentication was declined by user.")
                sys.exit(1)
            elif error == 'expired_token':
                print("✗ Device code expired. Please try again.")
                sys.exit(1)
            else:
                print(f"✗ Authentication error: {error}")
                sys.exit(1)
        else:
            print(f"✗ Unexpected error: {token_resp.text}")
            sys.exit(1)
else:
    print("Note: Service principal authentication is not configured.")
    print("Please set use_device_code = True to use interactive login.")
    sys.exit(1)

headers = {
    "Authorization": f"Bearer {access_token}",
    "Content-Type": "application/json"
}

# -------------------------------------------------------
# Helper functions
# -------------------------------------------------------
def pbi_get(url):
    r = requests.get(f"{base_url}{url}", headers=headers)
    r.raise_for_status()
    return r.json()

def pbi_patch(url, body):
    r = requests.patch(f"{base_url}{url}", headers=headers, data=json.dumps(body))
    r.raise_for_status()
    return r

def pbi_post(url, body):
    r = requests.post(f"{base_url}{url}", headers=headers, data=json.dumps(body))
    r.raise_for_status()
    return r.json()

def pbi_post_no_response(url, body=None):
    """POST request that doesn't expect JSON response"""
    if body:
        r = requests.post(f"{base_url}{url}", headers=headers, data=json.dumps(body))
    else:
        r = requests.post(f"{base_url}{url}", headers=headers)
    r.raise_for_status()
    return r

def find_matching_datasource(old_ds, new_gw_datasources):
    """Find a matching datasource on the new gateway by connection details"""
    old_conn = json.loads(old_ds["connectionDetails"]) if isinstance(old_ds["connectionDetails"], str) else old_ds["connectionDetails"]
    old_type = old_ds["datasourceType"]
    
    for new_ds in new_gw_datasources:
        new_conn = json.loads(new_ds["connectionDetails"]) if isinstance(new_ds["connectionDetails"], str) else new_ds["connectionDetails"]
        new_type = new_ds["datasourceType"]
        
        # Match by type and key connection properties
        if old_type == new_type:
            # For SQL/database sources, match server and database
            if old_conn.get("server") and old_conn.get("database"):
                if (old_conn.get("server") == new_conn.get("server") and 
                    old_conn.get("database") == new_conn.get("database")):
                    return new_ds
            # For other sources, match by path or other relevant properties
            elif old_conn.get("path") and old_conn.get("path") == new_conn.get("path"):
                return new_ds
    
    return None

# -------------------------------------------------------
# Get datasources from both gateways
# -------------------------------------------------------
print(f"Getting datasources from old gateway ({old_gateway})...")
try:
    # Try non-admin API first
    old_gw_datasources = pbi_get(f"/gateways/{old_gateway}/datasources")["value"]
    print(f"✓ Found {len(old_gw_datasources)} datasources on old gateway")
except requests.exceptions.HTTPError as e:
    if e.response.status_code == 401:
        print("✗ Unauthorized. The service principal needs to be added as an admin to the gateway.")
        print("  Or grant 'Tenant.Read.All' and 'Gateway.Read.All' permissions for admin API access.")
        sys.exit(1)
    raise

print(f"\nGetting datasources from new gateway ({new_gateway})...")
try:
    new_gw_datasources = pbi_get(f"/gateways/{new_gateway}/datasources")["value"]
    print(f"✓ Found {len(new_gw_datasources)} datasources on new gateway")
    can_read_new_gateway = True
except requests.exceptions.HTTPError as e:
    if e.response.status_code == 401:
        print("⚠ Cannot access new gateway datasources (personal gateway)")
        print("  Will attempt to create datasources as needed during migration")
        new_gw_datasources = []
        can_read_new_gateway = False
    else:
        raise
print()

# Filter old gateway datasources by name if specified
if datasource_name_filter:
    old_gw_datasources = [ds for ds in old_gw_datasources if ds["datasourceName"] == datasource_name_filter]
    print(f"Filtered to {len(old_gw_datasources)} datasource(s) matching name: '{datasource_name_filter}'\n")

if not old_gw_datasources:
    print("No datasources found matching the criteria. Exiting.")
    sys.exit(0)

# -------------------------------------------------------
# Build datasource mapping (old -> new)
# -------------------------------------------------------
datasource_mapping = {}

if can_read_new_gateway and new_gw_datasources:
    print("Building datasource mapping (old gateway -> new gateway)...")
    for old_ds in old_gw_datasources:
        new_ds = find_matching_datasource(old_ds, new_gw_datasources)
        if new_ds:
            datasource_mapping[old_ds["id"]] = new_ds
            print(f"✓ Mapped: {old_ds['datasourceName']} -> {new_ds['datasourceName']}")
        else:
            print(f"⚠ No match found on new gateway for: {old_ds['datasourceName']}")
            print(f"  Will use old datasource connection details for migration")
            # Store old datasource info to use during migration
            datasource_mapping[old_ds["id"]] = {
                "id": None,  # Will be determined during migration
                "datasourceName": old_ds["datasourceName"],
                "datasourceType": old_ds["datasourceType"],
                "connectionDetails": old_ds["connectionDetails"]
            }
else:
    print("Cannot read new gateway datasources. Will use connection details from old gateway.")
    for old_ds in old_gw_datasources:
        datasource_mapping[old_ds["id"]] = {
            "id": None,  # Will be determined during migration
            "datasourceName": old_ds["datasourceName"],
            "datasourceType": old_ds["datasourceType"],
            "connectionDetails": old_ds["connectionDetails"]
        }

if not datasource_mapping:
    print("\nNo datasources to map. Exiting.")
    sys.exit(1)

print(f"\n{len(datasource_mapping)} datasource(s) ready for migration.\n")

# -------------------------------------------------------
# Get all datasets (in accessible workspaces or specified workspaces)
# -------------------------------------------------------
print("Scanning for datasets using the old gateway datasources...")
datasets_to_migrate = {}  # key: dataset_id, value: {workspace_id, dataset_name, update_details}

# Get workspaces
if workspace_ids:
    print(f"Checking {len(workspace_ids)} specified workspace(s)...")
    workspaces = [{"id": wid, "name": f"Workspace-{wid}"} for wid in workspace_ids]
else:
    print("Checking all accessible workspaces (non-admin API)...")
    try:
        workspaces = pbi_get("/groups?$top=5000")["value"]
        print(f"Found {len(workspaces)} accessible workspaces")
    except Exception as e:
        print(f"Error getting workspaces: {e}")
        print("Note: Service principal may need to be added to workspaces or use workspace_ids parameter")
        sys.exit(1)

total_datasets_checked = 0
for workspace in workspaces:
    workspace_id = workspace["id"]
    workspace_name = workspace.get("name", "Unknown")
    
    try:
        # Get datasets in this workspace (non-admin API)
        datasets_response = pbi_get(f"/groups/{workspace_id}/datasets")
        datasets = datasets_response.get("value", [])
        
        print(f"  Checking workspace: {workspace_name} ({len(datasets)} datasets)")
        
        for dataset in datasets:
            total_datasets_checked += 1
            dataset_id = dataset["id"]
            dataset_name = dataset.get("name", "Unknown")
            
            try:
                # Get datasources for this dataset (non-admin API)
                ds_sources = pbi_get(f"/groups/{workspace_id}/datasets/{dataset_id}/datasources")["value"]
                
                # Debug: Show what gateway each dataset is using
                for ds in ds_sources:
                    if ds.get("gatewayId") == old_gateway:
                        print(f"    Dataset '{dataset_name}' uses old gateway, datasource: {ds.get('datasourceId')}")
                
                # Check if any datasource is from our old gateway
                old_sources = [s for s in ds_sources if s.get("gatewayId") == old_gateway and s.get("datasourceId") in datasource_mapping]
                
                if old_sources:
                    print(f"  Found: {dataset_name} in workspace '{workspace_name}'")
                    
                    # Build update details for this dataset
                    update_details = []
                    for old_source in old_sources:
                        mapped_ds = datasource_mapping[old_source["datasourceId"]]
                        old_conn = json.loads(old_source["connectionDetails"]) if isinstance(old_source["connectionDetails"], str) else old_source["connectionDetails"]
                        
                        # Store the new datasource ID if we have it
                        new_datasource_id = mapped_ds.get("id") if mapped_ds else None
                        
                        update_details.append({
                            "datasourceType": old_source["datasourceType"],
                            "connectionDetails": old_conn,
                            "old_datasource_id": old_source["datasourceId"],
                            "new_datasource_id": new_datasource_id
                        })
                    
                    datasets_to_migrate[dataset_id] = {
                        "workspace_id": workspace_id,
                        "workspace_name": workspace_name,
                        "dataset_name": dataset_name,
                        "update_details": update_details
                    }
            except Exception as e:
                # Skip datasets we can't access
                pass
                
    except Exception as e:
        # Skip workspaces we can't access
        pass

print(f"\n✓ Scanned {total_datasets_checked} datasets across {len(workspaces)} workspaces")
print(f"✓ Found {len(datasets_to_migrate)} dataset(s) using the target datasource(s)\n")

if not datasets_to_migrate:
    print("No datasets found using the specified datasources. Nothing to migrate.")
    sys.exit(0)

# -------------------------------------------------------
# Migrate datasets
# -------------------------------------------------------
print("="*60)
if what_if:
    print("WHAT-IF MODE: No actual changes will be made")
else:
    print("MIGRATION MODE: Datasets will be updated")
print("="*60)
print()

success_count = 0
error_count = 0

for dataset_id, info in datasets_to_migrate.items():
    workspace_id = info["workspace_id"]
    workspace_name = info["workspace_name"]
    dataset_name = info["dataset_name"]
    update_details = info["update_details"]
    
    print(f"Processing: {dataset_name} (Workspace: {workspace_name})")
    
    if what_if:
        print(f"  [WHAT-IF] Would update {len(update_details)} datasource binding(s)")
        for detail in update_details:
            conn = detail["connectionDetails"]
            print(f"    - Type: {detail['datasourceType']}, Server: {conn.get('server', 'N/A')}, DB: {conn.get('database', 'N/A')}")
        success_count += 1
    else:
        # First, discover which gateways this dataset can bind to
        try:
            print(f"  Discovering compatible gateways for dataset...")
            compatible_gateways = pbi_get(f"/groups/{workspace_id}/datasets/{dataset_id}/Default.DiscoverGateways")
            compatible_gateway_ids = [gw["id"] for gw in compatible_gateways.get("value", [])]
            
            if new_gateway in compatible_gateway_ids:
                print(f"  ✓ New gateway is compatible with this dataset")
            else:
                print(f"  ⚠ Warning: New gateway may not be compatible (not in discovered gateways list)")
                if len(compatible_gateway_ids) > 0:
                    print(f"    Compatible gateways: {compatible_gateway_ids[:3]}...")
        except Exception as discover_err:
            print(f"  ⚠ Could not discover gateways: {discover_err}")
        
        # Try multiple methods to rebind the dataset
        try:
            print(f"  Attempting to rebind dataset to new gateway...")
            
            # Method 1: Use official BindToGateway API
            try:
                # Build datasource object IDs for new gateway
                new_datasource_ids = []
                for detail in update_details:
                    if detail["new_datasource_id"]:
                        new_datasource_ids.append(detail["new_datasource_id"])
                
                bind_body = {
                    "gatewayObjectId": new_gateway
                }
                
                # Include datasourceObjectIds if we have them (recommended for explicit mapping)
                if new_datasource_ids:
                    bind_body["datasourceObjectIds"] = new_datasource_ids
                    print(f"  Binding to {len(new_datasource_ids)} datasource(s) on new gateway...")
                else:
                    print(f"  Binding to gateway (will auto-match datasources)...")
                
                pbi_post_no_response(f"/groups/{workspace_id}/datasets/{dataset_id}/Default.BindToGateway", bind_body)
                print(f"  ✓ Successfully bound dataset to new gateway")
                
                # Trigger refresh to validate new connection
                try:
                    print(f"  Triggering dataset refresh to validate connection...")
                    pbi_post_no_response(f"/groups/{workspace_id}/datasets/{dataset_id}/refreshes", {})
                    print(f"  ✓ Dataset refresh started")
                except Exception as refresh_err:
                    print(f"  ⚠ Note: Could not trigger refresh - {refresh_err}")
                
                success_count += 1
                
            except requests.exceptions.HTTPError as e1:
                error_detail = e1.response.text if hasattr(e1.response, 'text') else str(e1)
                
                # Check for specific error conditions
                if e1.response.status_code == 404:
                    # BindToGateway not supported - try UpdateDatasources for SQL datasets
                    print(f"  BindToGateway not available, trying UpdateDatasources...")
                    try:
                        update_payload = {"updateDetails": []}
                        for detail in update_details:
                            conn = detail["connectionDetails"]
                            if detail["datasourceType"] in ["Sql", "AnalysisServices", "OData"]:
                                update_payload["updateDetails"].append({
                                    "datasourceSelector": {
                                        "datasourceType": detail["datasourceType"],
                                        "connectionDetails": conn
                                    },
                                    "connectionDetails": conn,
                                    "gatewayObjectId": new_gateway
                                })
                        
                        if update_payload["updateDetails"]:
                            pbi_post_no_response(f"/groups/{workspace_id}/datasets/{dataset_id}/Default.UpdateDatasources", update_payload)
                            print(f"  ✓ Successfully updated datasources")
                            success_count += 1
                        else:
                            raise Exception("UpdateDatasources not applicable for this datasource type")
                    except Exception as e2:
                        raise Exception(
                            f"Automated rebinding not supported. Error: {error_detail}\n"
                            f"Please manually update in Power BI Service:\n"
                            f"  1. Go to workspace: {workspace_name}\n"
                            f"  2. Dataset: {dataset_name} → Settings → Gateway connection\n"
                            f"  3. Select new gateway: {new_gateway}\n"
                            f"  4. Configure datasource credentials"
                        )
                elif "not a data source user" in error_detail.lower() or "unauthorized" in error_detail.lower():
                    raise Exception(
                        f"Permission error: User must be added as data source user on the gateway.\n"
                        f"Add user to gateway datasources in Power BI Service or via Gateway admin tools."
                    )
                else:
                    raise Exception(f"API Error: {error_detail}")
                
        except Exception as e:
            error_msg = str(e)
            print(f"  ✗ Error updating dataset: {error_msg}")
            # Check if it's a credentials error
            if "credentials" in error_msg.lower() or "datasource" in error_msg.lower():
                print(f"    Note: You may need to manually configure credentials for this datasource on the new gateway")
            error_count += 1
    print()

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
print("="*60)
print("SUMMARY")
print("="*60)
print(f"Total datasets processed: {len(datasets_to_migrate)}")
print(f"Successful: {success_count}")
if error_count > 0:
    print(f"Errors: {error_count}")
if what_if:
    print("\n⚠ WHAT-IF MODE was enabled. No actual changes were made.")
    print("Set what_if = False to perform the actual migration.")
else:
    print("\n✓ Migration completed!")
