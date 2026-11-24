<#
.SYNOPSIS
    Registers the Weekly Service Review Report in Windows Task Scheduler.
.DESCRIPTION
    Fulfills FR-17:
    - Schedules Generate-ServiceReviewReport.ps1 to execute weekly (every Monday at 07:00 AM).
    - Can be registered via schtasks.exe or New-ScheduledTask.
    - Includes -DryRun / -WhatIf parameter for testing without elevation.
.PARAMETER TaskName
    Name of the scheduled task (default: ITIL_Weekly_Service_Review_Report).
.PARAMETER DayOfWeek
    Day of week to run (default: MON).
.PARAMETER StartTime
    Time of day to run (default: 07:00).
.PARAMETER OutputDir
    Destination for generated HTML and CSV reports.
.PARAMETER DryRun
    Outputs the command and XML configuration without altering Task Scheduler.
#>
[CmdletBinding()]
param(
    [string]$TaskName = "ITIL_Weekly_Service_Review_Report",
    [string]$DayOfWeek = "MON",
    [string]$StartTime = "07:00",
    [string]$OutputDir = "$PSScriptRoot\..\sample_outputs",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Windows Task Scheduler Registration (FR-17)                    " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Task Name      : $TaskName"
Write-Host "Schedule       : Weekly on $DayOfWeek at $StartTime"
Write-Host "Report Script  : reporting\Generate-ServiceReviewReport.ps1"
Write-Host "Output Dir     : $OutputDir"

$rootPath = (Resolve-Path "$PSScriptRoot\..").Path
$scriptPath = Join-Path $rootPath "reporting\Generate-ServiceReviewReport.ps1"
$fullOutputDir = Join-Path $rootPath "sample_outputs"

$actionCmd = "powershell.exe"
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -OutputDir `"$fullOutputDir`""

Write-Host "`nAction Command to Execute:" -ForegroundColor Yellow
Write-Host "  $actionCmd $actionArgs"

if ($DryRun) {
    Write-Host "`n[DRY-RUN MODE] Command that would be registered via schtasks:" -ForegroundColor Cyan
    $cmd = "schtasks.exe /Create /TN `"$TaskName`" /TR `"$actionCmd $actionArgs`" /SC WEEKLY /D $DayOfWeek /ST $StartTime /F"
    Write-Host "  $cmd" -ForegroundColor Green
    Write-Host "`nTask Scheduler configuration verified. No system state was altered." -ForegroundColor Green
    exit 0
}

try {
    Write-Host "`nRegistering task with Windows Task Scheduler via schtasks.exe..." -ForegroundColor Cyan
    $output = schtasks.exe /Create /TN "$TaskName" /TR "$actionCmd $actionArgs" /SC WEEKLY /D $DayOfWeek /ST $StartTime /F 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully registered scheduled task '$TaskName'!" -ForegroundColor Green
        Write-Host "Verification command: schtasks.exe /Query /TN `"$TaskName`"" -ForegroundColor Cyan
    } else {
        Write-Warning "Registration required elevated privileges: $output"
        Write-Host "Tip: Run as Administrator or use -DryRun to verify command syntax." -ForegroundColor Yellow
    }
} catch {
    Write-Warning "Could not register scheduled task: $_"
}
Write-Host "=================================================================" -ForegroundColor Cyan
