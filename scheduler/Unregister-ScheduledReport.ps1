<#
.SYNOPSIS
    Removes the Weekly Service Review Report task from Windows Task Scheduler.
.PARAMETER TaskName
    Name of the scheduled task to remove.
#>
[CmdletBinding()]
param(
    [string]$TaskName = "ITIL_Weekly_Service_Review_Report",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Windows Task Scheduler Unregistration (FR-17)                  " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DRY-RUN] Would execute: schtasks.exe /Delete /TN `"$TaskName`" /F" -ForegroundColor Green
    exit 0
}

try {
    schtasks.exe /Delete /TN "$TaskName" /F 2>&1 | Out-Null
    Write-Host "Successfully deleted task '$TaskName'." -ForegroundColor Green
} catch {
    Write-Warning "Task '$TaskName' was not found or could not be removed: $_"
}
Write-Host "=================================================================" -ForegroundColor Cyan
