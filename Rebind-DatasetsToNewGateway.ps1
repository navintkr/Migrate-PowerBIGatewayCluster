<#
.SYNOPSIS
    Rebind Power BI datasets to a new gateway WITHOUT creating duplicate datasources
    
.DESCRIPTION
    This script finds equivalent datasources on a new gateway and rebinds datasets
    to use them, avoiding the need to duplicate datasources.
    
    Use Case: When you have identical datasources on two gateways and want to
    switch datasets to use the new gateway's datasources instead.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OldGatewayId,
    
    [Parameter(Mandatory = $true)]
    [string]$NewGatewayId,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $true)]
    [SecureString]$ClientSecret,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'White' }
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-PBIAccessToken {
    param([string]$TenantId, [string]$ClientId, [SecureString]$ClientSecret)
    
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
    $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    
    return $response.access_token
}

function Get-GatewayDatasources {
    param([string]$GatewayId, [string]$Token)
    
    $headers = @{ 'Authorization' = "Bearer $Token" }
    $uri = "https://api.powerbi.com/v1.0/myorg/gateways/$GatewayId/datasources"
    
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    return $response.value
}

function Find-MatchingDatasource {
    param(
        [object]$SourceDatasource,
        [array]$TargetDatasources
    )
    
    # Match based on datasource type and connection details
    foreach ($targetDs in $TargetDatasources) {
        if ($targetDs.datasourceType -ne $SourceDatasource.datasourceType) {
            continue
        }
        
        # Compare connection details (parse JSON)
        $sourceConn = $SourceDatasource.connectionDetails | ConvertFrom-Json
        $targetConn = $targetDs.connectionDetails | ConvertFrom-Json
        
        # For SQL datasources, match server and database
        if ($SourceDatasource.datasourceType -eq 'Sql') {
            if ($sourceConn.server -eq $targetConn.server -and 
                $sourceConn.database -eq $targetConn.database) {
                return $targetDs
            }
        }
        # For other datasources, do generic comparison
        elseif (($sourceConn | ConvertTo-Json -Compress) -eq ($targetConn | ConvertTo-Json -Compress)) {
            return $targetDs
        }
    }
    
    return $null
}

function Get-DatasetsUsingDatasource {
    param([string]$DatasourceId, [string]$Token)
    
    $headers = @{ 'Authorization' = "Bearer $Token" }
    $datasets = @()
    
    # Get all workspaces
    $workspaces = Invoke-RestMethod -Method Get -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers $headers
    
    foreach ($workspace in $workspaces.value) {
        try {
            # Get datasets in workspace
            $wsDatasets = Invoke-RestMethod -Method Get `
                -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.id)/datasets" `
                -Headers $headers
            
            foreach ($dataset in $wsDatasets.value) {
                try {
                    # Get datasources for this dataset
                    $dsSources = Invoke-RestMethod -Method Get `
                        -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($workspace.id)/datasets/$($dataset.id)/datasources" `
                        -Headers $headers
                    
                    # Check if this dataset uses our datasource
                    if ($dsSources.value | Where-Object { $_.datasourceId -eq $DatasourceId }) {
                        $datasets += [PSCustomObject]@{
                            DatasetId     = $dataset.id
                            DatasetName   = $dataset.name
                            WorkspaceId   = $workspace.id
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

function Update-DatasetGateway {
    param(
        [string]$WorkspaceId,
        [string]$DatasetId,
        [string]$GatewayId,
        [string]$DatasourceId,
        [string]$Token
    )
    
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type'  = 'application/json'
    }
    
    $body = @{
        gatewayObjectId     = $GatewayId
        datasourceObjectIds = @($DatasourceId)
    } | ConvertTo-Json
    
    $uri = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$DatasetId/Default.BindToGateway"
    
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
}

#region Main Script

Write-Log "========================================" -Level Info
Write-Log "Dataset Gateway Rebinding Script" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

# Get access token
Write-Log "Obtaining Power BI access token..."
$accessToken = Get-PBIAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

# Get datasources from both gateways
Write-Log "Retrieving datasources from old gateway: $OldGatewayId"
$oldDatasources = Get-GatewayDatasources -GatewayId $OldGatewayId -Token $accessToken
Write-Log "Found $($oldDatasources.Count) datasources on old gateway" -Level Success

Write-Log "Retrieving datasources from new gateway: $NewGatewayId"
$newDatasources = Get-GatewayDatasources -GatewayId $NewGatewayId -Token $accessToken
Write-Log "Found $($newDatasources.Count) datasources on new gateway" -Level Success

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Finding Matching Datasources" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

$datasourceMapping = @{}
$matchedCount = 0
$unmatchedCount = 0

foreach ($oldDs in $oldDatasources) {
    Write-Log "Checking: $($oldDs.datasourceName) ($($oldDs.datasourceType))"
    
    $match = Find-MatchingDatasource -SourceDatasource $oldDs -TargetDatasources $newDatasources
    
    if ($match) {
        $datasourceMapping[$oldDs.id] = $match.id
        Write-Log "  ✓ Matched to: $($match.datasourceName)" -Level Success
        $matchedCount++
    }
    else {
        Write-Log "  ✗ No matching datasource found on new gateway" -Level Warning
        $unmatchedCount++
    }
}

Write-Log ""
Write-Log "Matching Summary: $matchedCount matched, $unmatchedCount unmatched" -Level Info

if ($unmatchedCount -gt 0) {
    Write-Log ""
    Write-Log "WARNING: $unmatchedCount datasources on old gateway have no match on new gateway" -Level Warning
    Write-Log "Datasets using these datasources cannot be migrated automatically" -Level Warning
}

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Rebinding Datasets" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

$totalRebound = 0
$totalFailed = 0
$totalSkipped = 0

foreach ($oldDsId in $datasourceMapping.Keys) {
    $newDsId = $datasourceMapping[$oldDsId]
    $oldDs = $oldDatasources | Where-Object { $_.id -eq $oldDsId }
    
    Write-Log "Processing datasource: $($oldDs.datasourceName)"
    
    # Find datasets using this datasource
    $datasets = Get-DatasetsUsingDatasource -DatasourceId $oldDsId -Token $accessToken
    
    if ($datasets.Count -eq 0) {
        Write-Log "  No datasets using this datasource" -Level Info
        continue
    }
    
    Write-Log "  Found $($datasets.Count) dataset(s)"
    
    foreach ($dataset in $datasets) {
        if ($WhatIf) {
            Write-Log "  [WHATIF] Would rebind: $($dataset.DatasetName) in $($dataset.WorkspaceName)" -Level Warning
            $totalRebound++
        }
        else {
            try {
                Update-DatasetGateway -WorkspaceId $dataset.WorkspaceId `
                    -DatasetId $dataset.DatasetId `
                    -GatewayId $NewGatewayId `
                    -DatasourceId $newDsId `
                    -Token $accessToken
                
                Write-Log "  ✓ Rebound: $($dataset.DatasetName)" -Level Success
                $totalRebound++
            }
            catch {
                Write-Log "  ✗ Failed: $($dataset.DatasetName) - $($_.Exception.Message)" -Level Error
                $totalFailed++
            }
        }
    }
}

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "SUMMARY" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""
Write-Log "Datasources:" -Level Info
Write-Log "  Matched: $matchedCount" -Level Info
Write-Log "  Unmatched: $unmatchedCount" -Level Info
Write-Log ""
Write-Log "Datasets:" -Level Info
Write-Log "  Rebound: $totalRebound" -Level Success
Write-Log "  Failed: $totalFailed" -Level $(if ($totalFailed -gt 0) { 'Error' } else { 'Success' })
Write-Log ""

if (-not $WhatIf) {
    Write-Log "IMPORTANT: Test dataset refreshes to verify connectivity!" -Level Warning
}

#endregion
