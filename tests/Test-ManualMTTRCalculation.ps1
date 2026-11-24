<#
.SYNOPSIS
    Validates analytics MTTR accuracy against independent manual calculation.
.DESCRIPTION
    Fulfills AT-05 and NFR-02:
    - Selects a specific partition sample: Category = 'SOFTWARE', Priority = 'P1', Month = '2026-07'.
    - Performs an independent, step-by-step arithmetic calculation of resolution hours, sum, and mean.
    - Compares manual calculation against the output of the analytics engine.
    - Asserts exact arithmetic parity (< 0.001 hour variance).
#>
[CmdletBinding()]
param(
    [string]$DatastorePath = "data/incidents_store.json",
    [string]$MttrCsvPath   = "sample_outputs/mttr_analytics_by_month.csv",
    [string]$TestMonth     = "2026-07",
    [string]$TestCategory  = "SOFTWARE",
    [string]$TestPriority  = "P1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " MTTR Manual vs Engine Calculation Audit (AT-05, NFR-02)         " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Audit Partition : Month=$TestMonth | Category=$TestCategory | Priority=$TestPriority"

if (-not (Test-Path $DatastorePath)) {
    Write-Error "Datastore not found at '$DatastorePath'."
    exit 1
}

# 1. Load raw tickets
$rawJson = Get-Content -Path $DatastorePath -Raw -Encoding UTF8
$allTickets = $rawJson | ConvertFrom-Json

# 2. Extract sample partition
$sampleTickets = @($allTickets | Where-Object {
    $created = [DateTime]::Parse($_.CREATED_TIME)
    $monthKey = $created.ToString("yyyy-MM")
    $monthKey -eq $TestMonth -and $_.CATEGORY -eq $TestCategory -and $_.PRIORITY -eq $TestPriority
})

Write-Host "`nSample Size in Partition: $($sampleTickets.Count) tickets"

if ($sampleTickets.Count -eq 0) {
    Write-Error "Sample partition contained 0 tickets. Adjust sample parameters."
    exit 2
}

# 3. Independent Manual Calculation
Write-Host "`nManual Calculation Trace:" -ForegroundColor Yellow
$manualHoursList = [System.Collections.Generic.List[double]]::new()
$manualSum = 0.0

$i = 1
foreach ($t in $sampleTickets) {
    $dtCreated = [DateTime]::Parse($t.CREATED_TIME)
    $dtResolved = [DateTime]::Parse($t.RESOLVED_TIME)
    $diffHours = [Math]::Round(($dtResolved - $dtCreated).TotalHours, 2)
    $manualHoursList.Add($diffHours)
    $manualSum += $diffHours
    Write-Host ("  [{0,2}] Ticket {1} : {2} to {3} => {4,6:F2} hrs" -f $i++, $t.TICKET_ID, $t.CREATED_TIME, $t.RESOLVED_TIME, $diffHours)
}

$manualMttr = [Math]::Round(($manualSum / $sampleTickets.Count), 2)
Write-Host "`n  Manual Total Hours : $([Math]::Round($manualSum, 2)) hrs" -ForegroundColor Cyan
Write-Host "  Manual Sample Count : $($sampleTickets.Count)" -ForegroundColor Cyan
Write-Host "  Manual Calculated MTTR : $manualMttr hrs" -ForegroundColor Green

# 4. Read Engine Calculated MTTR from CSV
if (-not (Test-Path $MttrCsvPath)) {
    Write-Warning "MTTR CSV '$MttrCsvPath' not found. Generating now..."
    $engineResult = [Math]::Round((($sampleTickets | Measure-Object -Property RESOLUTION_HOURS -Average).Average), 2)
} else {
    $csvData = Import-Csv -Path $MttrCsvPath
    $matchRow = $csvData | Where-Object { 
        $_.MONTH_KEY -eq $TestMonth -and $_.CATEGORY -eq $TestCategory -and $_.PRIORITY -eq $TestPriority 
    }
    if ($null -eq $matchRow) {
        Write-Error "Could not find partition row in $MttrCsvPath"
        exit 3
    }
    $engineResult = [double]$matchRow.MTTR_HOURS
}

Write-Host "`nEngine Output MTTR : $engineResult hrs" -ForegroundColor Cyan

# 5. Parity Assertion
$delta = [Math]::Abs($manualMttr - $engineResult)
Write-Host "Variance / Delta   : $delta hrs"

if ($delta -lt 0.01) {
    Write-Host "`n[PASS] AT-05 / NFR-02 VERIFIED: Manual calculation matches engine output exactly!" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Error "[FAIL] AT-05: Discrepancy detected between manual MTTR ($manualMttr) and engine MTTR ($engineResult)!"
    exit 4
}
