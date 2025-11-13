
<#
.SYNOPSIS
    Automates Power BI On-Premises Gateway cluster migration when approaching 1,000 data source limit.

.DESCRIPTION
    This script monitors data source count on a Power BI gateway cluster and automatically:
    1. Creates a new gateway cluster when threshold is reached
    2. Clones data sources to the new gateway
    3. Rebinds datasets to the new gateway cluster
    4. Provides cleanup guidance for the old gateway

.NOTES
    Requirements:
    - DataGateway PowerShell module (Install-Module -Name DataGateway)
    - Azure AD App Registration with Power BI API permissions
    - Gateway admin permissions
    - Recovery key for gateway cluster creation

.LINK
    https://learn.microsoft.com/power-bi/connect-data/service-gateway-data-sources
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentGatewayName,
    
    [Parameter(Mandatory = $true)]
    [string]$NewGatewayNamePrefix,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$RecoveryKey,
    
    [Parameter(Mandatory = $false)]
    [string]$Region = 'WestUS2',
    
    [Parameter(Mandatory = $false)]
    [int]$Threshold = 900,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$ClientSecret,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'White' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-PBIAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret
    )
    
    try {
        $clientSecretPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        )
        
        $body = @{
            grant_type    = 'client_credentials'
            scope         = 'https://analysis.windows.net/powerbi/api/.default'
            client_id     = $ClientId
            client_secret = $clientSecretPlain
        }
        
        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
        
        Write-Log "Successfully obtained Power BI access token" -Level Success
        return $tokenResponse.access_token
    }
    catch {
        Write-Log "Failed to obtain access token: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-CurrentGatewayInfo {
    param([string]$GatewayName)
    
    try {
        Write-Log "Retrieving gateway cluster information for: $GatewayName"
        
        $clusters = Get-DataGatewayCluster
        $gateway = $clusters | Where-Object { $_.Name -eq $GatewayName }
        
        if (-not $gateway) {
            throw "Gateway cluster '$GatewayName' not found"
        }
        
        Write-Log "Found gateway cluster: $($gateway.Name) (ID: $($gateway.Id))" -Level Success
        
        $datasources = Get-DataGatewayClusterDatasource -GatewayClusterId $gateway.Id
        Write-Log "Found $($datasources.Count) data sources on gateway cluster" -Level Info
        
        return @{
            Cluster     = $gateway
            Datasources = $datasources
        }
    }
    catch {
        Write-Log "Failed to retrieve gateway information: $($_.Exception.Message)" -Level Error
        throw
    }
}

function New-GatewayClusterWithRetry {
    param(
        [string]$GatewayName,
        [SecureString]$RecoveryKey,
        [string]$Region
    )
    
    try {
        Write-Log "Creating new gateway cluster: $GatewayName in region $Region"
        
        if ($WhatIf) {
            Write-Log "[WHATIF] Would create gateway cluster: $GatewayName" -Level Warning
            return [PSCustomObject]@{
                Id   = "whatif-gateway-id"
                Name = $GatewayName
            }
        }
        
        $newGateway = Add-DataGatewayCluster -GatewayName $GatewayName -RecoveryKey $RecoveryKey -Region $Region
        
        Write-Log "Successfully created gateway cluster: $($newGateway.Name) (ID: $($newGateway.Id))" -Level Success
        return $newGateway
    }
    catch {
        Write-Log "Failed to create gateway cluster: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-DatasourcesByGateway {
    param(
        [string]$GatewayId,
        [string]$AccessToken
    )
    
    try {
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type'  = 'application/json'
        }
        
        $uri = "https://api.powerbi.com/v1.0/myorg/gateways/$GatewayId/datasources"
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        
        return $response.value
    }
    catch {
        Write-Log "Failed to retrieve datasources via API: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Copy-GatewayDatasource {
    param(
        [object]$Datasource,
        [string]$NewGatewayId,
        [string]$AccessToken
    )
    
    try {
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type'  = 'application/json'
        }
        
        # Parse connection details
        $connectionDetails = $Datasource.connectionDetails | ConvertFrom-Json
        
        # Build datasource creation body
        $body = @{
            datasourceName    = $Datasource.datasourceName
            datasourceType    = $Datasource.datasourceType
            connectionDetails = $connectionDetails
        } | ConvertTo-Json -Depth 10
        
        if ($WhatIf) {
            Write-Log "[WHATIF] Would create datasource: $($Datasource.datasourceName) on new gateway" -Level Warning
            return "whatif-datasource-id"
        }
        
        $uri = "https://api.powerbi.com/v1.0/myorg/gateways/$NewGatewayId/datasources"
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
        
        Write-Log "Created datasource: $($Datasource.datasourceName) (New ID: $($response.id))" -Level Success
        return $response.id
    }
    catch {
        Write-Log "Failed to create datasource $($Datasource.datasourceName): $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Update-DatasourceCredentials {
    param(
        [string]$GatewayId,
        [string]$DatasourceId,
        [object]$SourceCredentials,
        [string]$AccessToken
    )
    
    try {
        if ($WhatIf) {
            Write-Log "[WHATIF] Would update credentials for datasource: $DatasourceId" -Level Warning
            return
        }
        
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type'  = 'application/json'
        }
        
        # Note: This requires the source credentials to be retrieved first
        # In practice, you may need to manually set credentials or use a secure vault
        Write-Log "Credentials must be manually configured for datasource: $DatasourceId" -Level Warning
        
        # Placeholder for credential update logic
        # $uri = "https://api.powerbi.com/v1.0/myorg/gateways/$GatewayId/datasources/$DatasourceId"
        # Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -Body $credBody
    }
    catch {
        Write-Log "Failed to update datasource credentials: $($_.Exception.Message)" -Level Error
    }
}

function Get-DatasetsByDatasource {
    param(
        [string]$DatasourceId,
        [string]$AccessToken
    )
    
    try {
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
        }
        
        # Get all workspaces
        $workspaces = Invoke-RestMethod -Method Get -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers $headers
        
        $datasets = @()
        
        foreach ($workspace in $workspaces.value) {
            try {
                $wsDatasets = Invoke-RestMethod -Method Get -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.id)/datasets" -Headers $headers
                
                foreach ($dataset in $wsDatasets.value) {
                    # Check if dataset uses this datasource
                    try {
                        $dsInfo = Invoke-RestMethod -Method Get -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.id)/datasets/$($dataset.id)/datasources" -Headers $headers
                        
                        if ($dsInfo.value | Where-Object { $_.datasourceId -eq $DatasourceId }) {
                            $datasets += [PSCustomObject]@{
                                DatasetId    = $dataset.id
                                DatasetName  = $dataset.name
                                WorkspaceId  = $workspace.id
                                WorkspaceName = $workspace.name
                            }
                        }
                    }
                    catch {
                        # Dataset may not have datasources or we don't have permission
                    }
                }
            }
            catch {
                Write-Log "Could not access workspace: $($workspace.name)" -Level Warning
            }
        }
        
        return $datasets
    }
    catch {
        Write-Log "Failed to retrieve datasets: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Update-DatasetGatewayBinding {
    param(
        [string]$WorkspaceId,
        [string]$DatasetId,
        [string]$NewGatewayId,
        [string]$NewDatasourceId,
        [string]$AccessToken
    )
    
    try {
        if ($WhatIf) {
            Write-Log "[WHATIF] Would rebind dataset $DatasetId to gateway $NewGatewayId" -Level Warning
            return
        }
        
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type'  = 'application/json'
        }
        
        $body = @{
            gatewayObjectId      = $NewGatewayId
            datasourceObjectIds = @($NewDatasourceId)
        } | ConvertTo-Json
        
        $uri = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$DatasetId/Default.BindToGateway"
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
        
        Write-Log "Successfully rebound dataset $DatasetId to new gateway" -Level Success
    }
    catch {
        Write-Log "Failed to rebind dataset $DatasetId: $($_.Exception.Message)" -Level Error
    }
}

#endregion

#region Main Script

Write-Log "========================================" -Level Info
Write-Log "Power BI Gateway Migration Script" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

# Verify prerequisites
Write-Log "Checking prerequisites..."

# Check if DataGateway module is installed
if (-not (Get-Module -ListAvailable -Name DataGateway)) {
    Write-Log "DataGateway module not found. Installing..." -Level Warning
    Install-Module -Name DataGateway -Scope CurrentUser -Force
}

Import-Module DataGateway -ErrorAction Stop
Write-Log "DataGateway module loaded successfully" -Level Success

# Connect to Data Gateway Service
Write-Log "Connecting to Data Gateway Service..."
try {
    Connect-DataGatewayServiceAccount -ErrorAction Stop
    Write-Log "Connected to Data Gateway Service" -Level Success
}
catch {
    Write-Log "Failed to connect to Data Gateway Service: $($_.Exception.Message)" -Level Error
    exit 1
}

# Get current gateway information
$gatewayInfo = Get-CurrentGatewayInfo -GatewayName $CurrentGatewayName
$currentDatasourceCount = $gatewayInfo.Datasources.Count

Write-Log ""
Write-Log "Current Gateway Status:" -Level Info
Write-Log "  Gateway Name: $CurrentGatewayName" -Level Info
Write-Log "  Gateway ID: $($gatewayInfo.Cluster.Id)" -Level Info
Write-Log "  Data Sources: $currentDatasourceCount / 1000" -Level Info
Write-Log "  Threshold: $Threshold" -Level Info
Write-Log ""

# Check if migration is needed
if ($currentDatasourceCount -lt $Threshold) {
    Write-Log "Data source count ($currentDatasourceCount) is below threshold ($Threshold)" -Level Success
    Write-Log "No migration required at this time" -Level Info
    exit 0
}

Write-Log "Data source count ($currentDatasourceCount) has reached threshold ($Threshold)" -Level Warning
Write-Log "Starting migration process..." -Level Info
Write-Log ""

# Determine next cluster number
$clusterNumber = 1
if ($CurrentGatewayName -match '(\d+)$') {
    $clusterNumber = [int]$Matches[1] + 1
}

$newGatewayName = "$NewGatewayNamePrefix$($clusterNumber.ToString('00'))"

# Create new gateway cluster
Write-Log "Step 1: Creating new gateway cluster" -Level Info
$newGateway = New-GatewayClusterWithRetry -GatewayName $newGatewayName -RecoveryKey $RecoveryKey -Region $Region

Write-Log ""
Write-Log "Step 2: Obtaining Power BI API access token" -Level Info
$accessToken = Get-PBIAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

Write-Log ""
Write-Log "Step 3: Cloning data sources to new gateway" -Level Info

# Get detailed datasource information via API
$apiDatasources = Get-DatasourcesByGateway -GatewayId $gatewayInfo.Cluster.Id -AccessToken $accessToken

$datasourceMapping = @{}
$successCount = 0
$failCount = 0

foreach ($ds in $apiDatasources) {
    Write-Log "Processing datasource: $($ds.datasourceName)"
    
    $newDsId = Copy-GatewayDatasource -Datasource $ds -NewGatewayId $newGateway.Id -AccessToken $accessToken
    
    if ($newDsId) {
        $datasourceMapping[$ds.id] = $newDsId
        $successCount++
        
        # Note: Credentials need to be set manually or via secure method
        Update-DatasourceCredentials -GatewayId $newGateway.Id -DatasourceId $newDsId -SourceCredentials $null -AccessToken $accessToken
    }
    else {
        $failCount++
    }
}

Write-Log ""
Write-Log "Datasource cloning completed: $successCount succeeded, $failCount failed" -Level $(if ($failCount -eq 0) { 'Success' } else { 'Warning' })

Write-Log ""
Write-Log "Step 4: Rebinding datasets to new gateway" -Level Info

$rebindCount = 0
$rebindFailCount = 0

foreach ($oldDsId in $datasourceMapping.Keys) {
    $newDsId = $datasourceMapping[$oldDsId]
    
    # Find datasets using this datasource
    $datasets = Get-DatasetsByDatasource -DatasourceId $oldDsId -AccessToken $accessToken
    
    Write-Log "Found $($datasets.Count) dataset(s) using datasource $oldDsId"
    
    foreach ($dataset in $datasets) {
        try {
            Update-DatasetGatewayBinding -WorkspaceId $dataset.WorkspaceId -DatasetId $dataset.DatasetId `
                -NewGatewayId $newGateway.Id -NewDatasourceId $newDsId -AccessToken $accessToken
            $rebindCount++
        }
        catch {
            $rebindFailCount++
        }
    }
}

Write-Log ""
Write-Log "Dataset rebinding completed: $rebindCount succeeded, $rebindFailCount failed" -Level $(if ($rebindFailCount -eq 0) { 'Success' } else { 'Warning' })

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Migration Summary" -Level Info
Write-Log "========================================" -Level Info
Write-Log "Old Gateway: $CurrentGatewayName ($($gatewayInfo.Cluster.Id))" -Level Info
Write-Log "New Gateway: $newGatewayName ($($newGateway.Id))" -Level Info
Write-Log "Data Sources Migrated: $successCount / $($apiDatasources.Count)" -Level Info
Write-Log "Datasets Rebound: $rebindCount" -Level Info
Write-Log ""

if (-not $WhatIf) {
    Write-Log "IMPORTANT: Next Steps" -Level Warning
    Write-Log "1. Verify all datasets are refreshing successfully on the new gateway" -Level Warning
    Write-Log "2. Manually configure credentials for data sources that failed" -Level Warning
    Write-Log "3. Monitor both gateways for 24-48 hours" -Level Warning
    Write-Log "4. After verification, you can decommission the old gateway: $CurrentGatewayName" -Level Warning
    Write-Log ""
    Write-Log "To remove the old gateway cluster, run:" -Level Info
    Write-Log "  Remove-DataGatewayCluster -GatewayClusterId $($gatewayInfo.Cluster.Id)" -Level Info
}

Write-Log ""
Write-Log "Migration process completed!" -Level Success

#endregion
