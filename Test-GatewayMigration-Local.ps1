<#
.SYNOPSIS
    Local test/demo version of the Power BI Gateway Migration Script
    
.DESCRIPTION
    This script simulates the gateway migration process without requiring:
    - Actual Power BI gateways
    - Azure AD authentication
    - Power BI API access
    
    It demonstrates the workflow and logic with mock data.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CurrentGatewayName = "TestGatewayCluster01",
    
    [Parameter(Mandatory = $false)]
    [int]$Threshold = 900,
    
    [Parameter(Mandatory = $false)]
    [int]$SimulatedDataSourceCount = 950
)

# Mock data structures
$script:MockGateways = @()
$script:MockDatasources = @()
$script:MockDatasets = @()

#region Mock Functions

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

function Initialize-MockData {
    param([string]$GatewayName, [int]$DataSourceCount)
    
    Write-Log "Initializing mock data for testing..." -Level Info
    
    # Create mock gateway
    $script:MockGateways += [PSCustomObject]@{
        Id          = "gateway-" + (New-Guid).ToString()
        Name        = $GatewayName
        Region      = "WestUS2"
        Status      = "Active"
        CreatedDate = (Get-Date).AddMonths(-6)
    }
    
    # Create mock datasources
    $dsTypes = @('Sql', 'OData', 'File', 'SharePoint', 'Oracle', 'MySQL')
    for ($i = 1; $i -le $DataSourceCount; $i++) {
        $dsType = $dsTypes[$i % $dsTypes.Count]
        
        $script:MockDatasources += [PSCustomObject]@{
            Id             = "datasource-" + (New-Guid).ToString()
            GatewayId      = $script:MockGateways[0].Id
            Name           = "DataSource_$i"
            Type           = $dsType
            ConnectionDetails = @{
                server   = "server$i.database.windows.net"
                database = "database$i"
            } | ConvertTo-Json
            CreatedDate    = (Get-Date).AddDays(-($i % 180))
        }
    }
    
    # Create mock datasets (fewer than datasources, some share datasources)
    $datasetCount = [Math]::Min(100, $DataSourceCount / 3)
    for ($i = 1; $i -le $datasetCount; $i++) {
        $dsIndex = ($i * 3) % $script:MockDatasources.Count
        
        $script:MockDatasets += [PSCustomObject]@{
            Id           = "dataset-" + (New-Guid).ToString()
            WorkspaceId  = "workspace-" + (($i % 10) + 1)
            WorkspaceName = "Workspace " + (($i % 10) + 1)
            Name         = "Sales Report $i"
            DatasourceId = $script:MockDatasources[$dsIndex].Id
            GatewayId    = $script:MockGateways[0].Id
        }
    }
    
    Write-Log "Mock data initialized:" -Level Success
    Write-Log "  - Gateways: $($script:MockGateways.Count)" -Level Info
    Write-Log "  - Data Sources: $($script:MockDatasources.Count)" -Level Info
    Write-Log "  - Datasets: $($script:MockDatasets.Count)" -Level Info
}

function Mock-GetGatewayCluster {
    param([string]$Name)
    
    $gateway = $script:MockGateways | Where-Object { $_.Name -eq $Name }
    if (-not $gateway) {
        throw "Gateway cluster '$Name' not found"
    }
    return $gateway
}

function Mock-GetGatewayDatasources {
    param([string]$GatewayId)
    
    return $script:MockDatasources | Where-Object { $_.GatewayId -eq $GatewayId }
}

function Mock-CreateGatewayCluster {
    param([string]$Name, [string]$Region)
    
    Write-Log "Creating mock gateway cluster: $Name in $Region"
    Start-Sleep -Seconds 1  # Simulate API delay
    
    $newGateway = [PSCustomObject]@{
        Id          = "gateway-" + (New-Guid).ToString()
        Name        = $Name
        Region      = $Region
        Status      = "Active"
        CreatedDate = Get-Date
    }
    
    $script:MockGateways += $newGateway
    return $newGateway
}

function Mock-CloneDatasource {
    param([object]$Datasource, [string]$NewGatewayId)
    
    Write-Log "  Cloning: $($Datasource.Name) ($($Datasource.Type))"
    Start-Sleep -Milliseconds 100  # Simulate API delay
    
    # Simulate 95% success rate
    if ((Get-Random -Minimum 1 -Maximum 100) -le 95) {
        $newDs = [PSCustomObject]@{
            Id             = "datasource-" + (New-Guid).ToString()
            GatewayId      = $NewGatewayId
            Name           = $Datasource.Name
            Type           = $Datasource.Type
            ConnectionDetails = $Datasource.ConnectionDetails
            CreatedDate    = Get-Date
        }
        
        $script:MockDatasources += $newDs
        return $newDs.Id
    }
    else {
        Write-Log "    Failed to clone datasource (simulated error)" -Level Warning
        return $null
    }
}

function Mock-RebindDataset {
    param([object]$Dataset, [string]$NewGatewayId, [string]$NewDatasourceId)
    
    Write-Log "  Rebinding: $($Dataset.Name) in $($Dataset.WorkspaceName)"
    Start-Sleep -Milliseconds 50  # Simulate API delay
    
    # Simulate 98% success rate
    if ((Get-Random -Minimum 1 -Maximum 100) -le 98) {
        $Dataset.GatewayId = $NewGatewayId
        $Dataset.DatasourceId = $NewDatasourceId
        return $true
    }
    else {
        Write-Log "    Failed to rebind dataset (simulated error)" -Level Warning
        return $false
    }
}

#endregion

#region Main Test Script

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Power BI Gateway Migration - LOCAL TEST" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "This is a LOCAL TEST that simulates the migration process" -Level Warning
Write-Log "No actual Azure resources or Power BI gateways are required" -Level Warning
Write-Log ""

# Initialize test data
Initialize-MockData -GatewayName $CurrentGatewayName -DataSourceCount $SimulatedDataSourceCount

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Step 1: Checking Current Gateway Status" -Level Info
Write-Log "========================================" -Level Info

$currentGateway = Mock-GetGatewayCluster -Name $CurrentGatewayName
$currentDatasources = Mock-GetGatewayDatasources -GatewayId $currentGateway.Id

Write-Log ""
Write-Log "Current Gateway: $($currentGateway.Name)" -Level Info
Write-Log "  Gateway ID: $($currentGateway.Id)" -Level Info
Write-Log "  Region: $($currentGateway.Region)" -Level Info
Write-Log "  Status: $($currentGateway.Status)" -Level Info
Write-Log "  Data Sources: $($currentDatasources.Count) / 1000" -Level $(if ($currentDatasources.Count -ge $Threshold) { 'Warning' } else { 'Success' })
Write-Log "  Threshold: $Threshold" -Level Info

if ($currentDatasources.Count -lt $Threshold) {
    Write-Log ""
    Write-Log "Data source count is below threshold - no migration needed!" -Level Success
    Write-Log "Current: $($currentDatasources.Count) / Threshold: $Threshold" -Level Info
    exit 0
}

Write-Log ""
Write-Log "WARNING: Threshold exceeded! Migration required." -Level Warning
Write-Log "Current: $($currentDatasources.Count) / Threshold: $Threshold" -Level Warning

# Determine new gateway name
$clusterNumber = 1
if ($CurrentGatewayName -match '(\d+)$') {
    $clusterNumber = [int]$Matches[1] + 1
}
$newGatewayName = $CurrentGatewayName -replace '\d+$', $clusterNumber.ToString('00')

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Step 2: Creating New Gateway Cluster" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

$newGateway = Mock-CreateGatewayCluster -Name $newGatewayName -Region $currentGateway.Region

Write-Log ""
Write-Log "New gateway created successfully!" -Level Success
Write-Log "  Name: $($newGateway.Name)" -Level Info
Write-Log "  ID: $($newGateway.Id)" -Level Info
Write-Log "  Region: $($newGateway.Region)" -Level Info

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Step 3: Cloning Data Sources" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""
Write-Log "Cloning $($currentDatasources.Count) data sources to new gateway..."
Write-Log "This may take a while..." -Level Warning
Write-Log ""

$datasourceMapping = @{}
$cloneSuccessCount = 0
$cloneFailCount = 0
$progressCounter = 0

foreach ($ds in $currentDatasources) {
    $progressCounter++
    
    # Show progress every 50 datasources
    if ($progressCounter % 50 -eq 0 -or $progressCounter -eq 1) {
        $percentComplete = [Math]::Round(($progressCounter / $currentDatasources.Count) * 100, 1)
        Write-Log "Progress: $progressCounter / $($currentDatasources.Count) ($percentComplete%)" -Level Info
    }
    
    $newDsId = Mock-CloneDatasource -Datasource $ds -NewGatewayId $newGateway.Id
    
    if ($newDsId) {
        $datasourceMapping[$ds.Id] = $newDsId
        $cloneSuccessCount++
    }
    else {
        $cloneFailCount++
    }
}

Write-Log ""
Write-Log "Data source cloning completed!" -Level Success
Write-Log "  Succeeded: $cloneSuccessCount" -ForegroundColor Green
Write-Log "  Failed: $cloneFailCount" -ForegroundColor $(if ($cloneFailCount -gt 0) { 'Yellow' } else { 'Green' })

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "Step 4: Rebinding Datasets" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""

$affectedDatasets = $script:MockDatasets | Where-Object { $_.GatewayId -eq $currentGateway.Id }
Write-Log "Found $($affectedDatasets.Count) datasets to rebind"
Write-Log ""

$rebindSuccessCount = 0
$rebindFailCount = 0

foreach ($dataset in $affectedDatasets) {
    $newDsId = $datasourceMapping[$dataset.DatasourceId]
    
    if ($newDsId) {
        $result = Mock-RebindDataset -Dataset $dataset -NewGatewayId $newGateway.Id -NewDatasourceId $newDsId
        
        if ($result) {
            $rebindSuccessCount++
        }
        else {
            $rebindFailCount++
        }
    }
    else {
        Write-Log "  Skipped: $($dataset.Name) (datasource clone failed)" -Level Warning
        $rebindFailCount++
    }
}

Write-Log ""
Write-Log "Dataset rebinding completed!" -Level Success
Write-Log "  Succeeded: $rebindSuccessCount" -ForegroundColor Green
Write-Log "  Failed: $rebindFailCount" -ForegroundColor $(if ($rebindFailCount -gt 0) { 'Yellow' } else { 'Green' })

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "MIGRATION SUMMARY" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""
Write-Log "Old Gateway:" -Level Info
Write-Log "  Name: $($currentGateway.Name)" -Level Info
Write-Log "  ID: $($currentGateway.Id)" -Level Info
Write-Log "  Data Sources: $($currentDatasources.Count)" -Level Info
Write-Log ""
Write-Log "New Gateway:" -Level Info
Write-Log "  Name: $($newGateway.Name)" -Level Info
Write-Log "  ID: $($newGateway.Id)" -Level Info
Write-Log "  Data Sources: $cloneSuccessCount" -Level Info
Write-Log ""
Write-Log "Migration Results:" -Level Info
Write-Log "  Data Sources Cloned: $cloneSuccessCount / $($currentDatasources.Count)" -Level Info
Write-Log "  Datasets Rebound: $rebindSuccessCount / $($affectedDatasets.Count)" -Level Info
Write-Log "  Total Failures: $($cloneFailCount + $rebindFailCount)" -Level $(if (($cloneFailCount + $rebindFailCount) -gt 0) { 'Warning' } else { 'Success' })

Write-Log ""
Write-Log "========================================" -Level Info
Write-Log "NEXT STEPS (In Real Environment)" -Level Info
Write-Log "========================================" -Level Info
Write-Log ""
Write-Log "1. Configure credentials for all data sources on new gateway" -Level Warning
Write-Log "2. Test dataset refreshes to verify connectivity" -Level Warning
Write-Log "3. Monitor both gateways for 24-48 hours" -Level Warning
Write-Log "4. After verification, decommission old gateway:" -Level Info
Write-Log "   Remove-DataGatewayCluster -GatewayClusterId $($currentGateway.Id)" -Level Info

Write-Log ""
Write-Log "========================================" -Level Success
Write-Log "LOCAL TEST COMPLETED SUCCESSFULLY!" -Level Success
Write-Log "========================================" -Level Success
Write-Log ""

# Show final statistics
Write-Host ""
Write-Host "Mock Data Statistics:" -ForegroundColor Cyan
Write-Host "  Total Gateways: $($script:MockGateways.Count)" -ForegroundColor White
Write-Host "  Total Data Sources: $($script:MockDatasources.Count)" -ForegroundColor White
Write-Host "  Total Datasets: $($script:MockDatasets.Count)" -ForegroundColor White
Write-Host ""

# Option to inspect mock data
$inspect = Read-Host "Would you like to inspect the mock data? (y/n)"
if ($inspect -eq 'y') {
    Write-Host "`nGateways:" -ForegroundColor Cyan
    $script:MockGateways | Format-Table -AutoSize
    
    Write-Host "`nData Sources (first 10):" -ForegroundColor Cyan
    $script:MockDatasources | Select-Object -First 10 | Format-Table -AutoSize
    
    Write-Host "`nDatasets (first 10):" -ForegroundColor Cyan
    $script:MockDatasets | Select-Object -First 10 | Format-Table -AutoSize
}

#endregion
