<#
.SYNOPSIS
    Ingests and validates incident CSV data into Oracle XE 21c and local datastore.
.DESCRIPTION
    Fulfills FR-04, FR-05, NFR-03, and NFR-04:
    - Validates CSV schema, data types, date formats, and reference foreign keys.
    - Captures bad rows with precise rejection reasons and exports them to a reject file (FR-04).
    - Idempotent loading: re-loading the same file does not produce duplicate tickets (FR-05).
    - Returns exit code 0 on clean execution, non-zero on fatal errors (NFR-03).
    - Supports Oracle database connection via sqlplus/ODP.NET or local persistent store.
.PARAMETER InputCsv
    Path to the input incidents CSV file.
.PARAMETER RejectCsv
    Path where rejected records will be exported.
.PARAMETER DatastorePath
    Path to the persistent datastore file (default data/incidents_store.json).
.PARAMETER GenerateSql
    Optional path to emit Oracle SQL MERGE statements for Oracle XE 21c import.
.PARAMETER OracleConnectString
    Optional Oracle DB connection string (defaults to $env:ORACLE_CONN_STR).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [string]$RejectCsv = "data/reject_incidents.csv",
    [string]$DatastorePath = "data/incidents_store.json",
    [string]$GenerateSql = "database/07_ingested_incidents.sql",
    [string]$OracleConnectString = $env:ORACLE_CONN_STR
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " ITIL Incident Ingestion & Validation Pipeline (FR-04, FR-05)    " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Input CSV      : $InputCsv"
Write-Host "Reject Output  : $RejectCsv"
Write-Host "Datastore Path : $DatastorePath"

# Check if input file exists
if (-not (Test-Path $InputCsv)) {
    Write-Error "Fatal: Input CSV file does not exist: $InputCsv"
    exit 1
}

# Reference sets for allowed values (FR-03 / Section 5)
$allowedPriorities = [System.Collections.Generic.HashSet[string]]::new([string[]]@("P1", "P2", "P3", "P4"))
$allowedCategories = [System.Collections.Generic.HashSet[string]]::new([string[]]@("SOFTWARE", "DATABASE", "INFRASTRUCTURE", "SECURITY", "HARDWARE"))
$allowedServices   = [System.Collections.Generic.HashSet[string]]::new([string[]]@("PAYMENT_GATEWAY", "BILLING_ENGINE", "USER_PORTAL", "CORE_BANKING_API", "REPORTING_SERVICE", "IDENTITY_AUTH"))
$allowedGroups     = [System.Collections.Generic.HashSet[string]]::new([string[]]@("GRP_APP_DEV", "GRP_DBA_TEAM", "GRP_INFRA_OPS", "GRP_NET_SEC", "GRP_SERVICE_DESK"))
$allowedStatuses   = [System.Collections.Generic.HashSet[string]]::new([string[]]@("OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"))

# Required CSV headers
$requiredHeaders = @("TICKET_ID", "PRIORITY", "CATEGORY", "SERVICE", "ASSIGNMENT_GROUP", "ROOT_CAUSE", "STATUS", "CREATED_TIME", "RESOLVED_TIME", "SLA_DUE_TIME", "RESOLUTION_HOURS", "IS_SLA_BREACH")

# Read CSV rows
try {
    $rows = Import-Csv -Path $InputCsv -Encoding UTF8
} catch {
    Write-Error "Fatal: Failed to read CSV: $_"
    exit 2
}

if ($null -eq $rows -or $rows.Count -eq 0) {
    Write-Warning "Input CSV is empty. Nothing to ingest."
    exit 0
}

# Verify Schema (Headers)
$firstRow = $rows[0]
$headers = $firstRow.PSObject.Properties.Name
foreach ($req in $requiredHeaders) {
    if ($headers -notcontains $req) {
        Write-Error "Schema validation failed: Missing required column '$req' in CSV header."
        exit 3
    }
}

# Load existing datastore for idempotency check (FR-05)
$datastore = @{}
if (Test-Path $DatastorePath) {
    try {
        $existingJson = Get-Content -Path $DatastorePath -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($existingJson)) {
            $existingList = $existingJson | ConvertFrom-Json
            foreach ($item in $existingList) {
                $datastore[$item.TICKET_ID] = $item
            }
        }
    } catch {
        Write-Warning "Existing datastore could not be parsed. Starting fresh."
    }
}

$initialExistingCount = $datastore.Count
Write-Host "Pre-existing tickets in datastore: $initialExistingCount"

$validRows = [System.Collections.Generic.List[PSObject]]::new()
$rejectedRows = [System.Collections.Generic.List[PSObject]]::new()
$skippedDuplicates = 0
$updatedRecords = 0

# Row-by-row validation (FR-04)
$rowNumber = 1
foreach ($row in $rows) {
    $rowNumber++
    $errors = [System.Collections.Generic.List[string]]::new()

    # 1. TICKET_ID check
    $ticketId = if ($null -ne $row.TICKET_ID) { $row.TICKET_ID.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($ticketId)) {
        $errors.Add("TICKET_ID is missing or blank")
    } elseif ($ticketId -notmatch '^INC-[A-Za-z0-9\-]+$') {
        $errors.Add("TICKET_ID format invalid ('$ticketId')")
    }

    # 2. Priority check
    $prio = if ($null -ne $row.PRIORITY) { $row.PRIORITY.Trim().ToUpper() } else { "" }
    if (-not $allowedPriorities.Contains($prio)) {
        $errors.Add("PRIORITY '$prio' is invalid (allowed: P1, P2, P3, P4)")
    }

    # 3. Category check
    $cat = if ($null -ne $row.CATEGORY) { $row.CATEGORY.Trim().ToUpper() } else { "" }
    if (-not $allowedCategories.Contains($cat)) {
        $errors.Add("CATEGORY '$cat' is invalid (allowed: SOFTWARE, DATABASE, INFRASTRUCTURE, SECURITY, HARDWARE)")
    }

    # 4. Service check
    $svc = if ($null -ne $row.SERVICE) { $row.SERVICE.Trim().ToUpper() } else { "" }
    if (-not $allowedServices.Contains($svc)) {
        $errors.Add("SERVICE '$svc' is invalid")
    }

    # 5. Assignment group check
    $grp = if ($null -ne $row.ASSIGNMENT_GROUP) { $row.ASSIGNMENT_GROUP.Trim().ToUpper() } else { "" }
    if (-not $allowedGroups.Contains($grp)) {
        $errors.Add("ASSIGNMENT_GROUP '$grp' is invalid")
    }

    # 6. Root cause check
    $rc = if ($null -ne $row.ROOT_CAUSE) { $row.ROOT_CAUSE.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($rc)) {
        $errors.Add("ROOT_CAUSE is missing or blank")
    }

    # 7. Status check
    $status = if ($null -ne $row.STATUS) { $row.STATUS.Trim().ToUpper() } else { "RESOLVED" }
    if (-not $allowedStatuses.Contains($status)) {
        $errors.Add("STATUS '$status' is invalid")
    }

    # 8. Date validations
    $dtCreated = [DateTime]::MinValue
    $dtResolved = [DateTime]::MinValue
    $dtDue = [DateTime]::MinValue

    if (-not [DateTime]::TryParse($row.CREATED_TIME, [ref]$dtCreated)) {
        $errors.Add("CREATED_TIME '$($row.CREATED_TIME)' is not a valid date format")
    }

    if (-not [DateTime]::TryParse($row.RESOLVED_TIME, [ref]$dtResolved)) {
        $errors.Add("RESOLVED_TIME '$($row.RESOLVED_TIME)' is not a valid date format")
    }

    if (-not [DateTime]::TryParse($row.SLA_DUE_TIME, [ref]$dtDue)) {
        $errors.Add("SLA_DUE_TIME '$($row.SLA_DUE_TIME)' is not a valid date format")
    }

    # Chronological logic
    if ($dtCreated -ne [DateTime]::MinValue -and $dtResolved -ne [DateTime]::MinValue) {
        if ($dtResolved -lt $dtCreated) {
            $errors.Add("RESOLVED_TIME ($($row.RESOLVED_TIME)) cannot be earlier than CREATED_TIME ($($row.CREATED_TIME))")
        }
    }

    # 9. Numeric check
    $resHrs = 0.0
    if (-not [double]::TryParse($row.RESOLUTION_HOURS, [ref]$resHrs) -or $resHrs -lt 0) {
        $errors.Add("RESOLUTION_HOURS '$($row.RESOLUTION_HOURS)' must be a non-negative number")
    }

    # Evaluation
    if ($errors.Count -gt 0) {
        $reason = $errors -join "; "
        $rejectItem = [PSCustomObject]@{
            ROW_NUMBER       = $rowNumber
            TICKET_ID        = $row.TICKET_ID
            PRIORITY         = $row.PRIORITY
            CATEGORY         = $row.CATEGORY
            SERVICE          = $row.SERVICE
            ASSIGNMENT_GROUP = $row.ASSIGNMENT_GROUP
            ROOT_CAUSE       = $row.ROOT_CAUSE
            STATUS           = $row.STATUS
            CREATED_TIME     = $row.CREATED_TIME
            RESOLVED_TIME    = $row.RESOLVED_TIME
            SLA_DUE_TIME     = $row.SLA_DUE_TIME
            RESOLUTION_HOURS = $row.RESOLUTION_HOURS
            IS_SLA_BREACH    = $row.IS_SLA_BREACH
            REJECTION_REASON = $reason
        }
        $rejectedRows.Add($rejectItem)
    } else {
        # Valid Row: Check for Idempotency (FR-05)
        $cleanObject = [PSCustomObject]@{
            TICKET_ID        = $ticketId
            PRIORITY         = $prio
            CATEGORY         = $cat
            SERVICE          = $svc
            ASSIGNMENT_GROUP = $grp
            ROOT_CAUSE       = $rc
            STATUS           = $status
            CREATED_TIME     = $dtCreated.ToString("yyyy-MM-dd HH:mm:ss")
            RESOLVED_TIME    = $dtResolved.ToString("yyyy-MM-dd HH:mm:ss")
            SLA_DUE_TIME     = $dtDue.ToString("yyyy-MM-dd HH:mm:ss")
            RESOLUTION_HOURS = [Math]::Round($resHrs, 2)
            IS_SLA_BREACH    = [int]$row.IS_SLA_BREACH
        }

        if ($datastore.ContainsKey($ticketId)) {
            $skippedDuplicates++
            # Ensure it is idempotently updated in place without row inflation
            $datastore[$ticketId] = $cleanObject
        } else {
            $datastore[$ticketId] = $cleanObject
            $validRows.Add($cleanObject)
        }
    }
}

# Export Rejects File if any (FR-04)
if ($rejectedRows.Count -gt 0) {
    $rejectDir = Split-Path -Path $RejectCsv -Parent
    if ($rejectDir -and -not (Test-Path $rejectDir)) {
        New-Item -ItemType Directory -Path $rejectDir -Force | Out-Null
    }
    $rejectedRows | Export-Csv -Path $RejectCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($rejectedRows.Count) rejected records with error reasons to '$RejectCsv'" -ForegroundColor Red
} else {
    Write-Host "Zero rows rejected! Validation passed with 100% clean schema." -ForegroundColor Green
    if (Test-Path $RejectCsv) {
        Remove-Item -Path $RejectCsv -Force -ErrorAction SilentlyContinue
    }
}

# Save updated datastore (FR-05 Idempotency preservation)
$datastoreDir = Split-Path -Path $DatastorePath -Parent
if ($datastoreDir -and -not (Test-Path $datastoreDir)) {
    New-Item -ItemType Directory -Path $datastoreDir -Force | Out-Null
}
$allTickets = @($datastore.Values) | Sort-Object { [DateTime]::Parse($_.CREATED_TIME) }
$allTickets | ConvertTo-Json -Depth 5 | Set-Content -Path $DatastorePath -Encoding UTF8

# Generate Oracle MERGE SQL Script (FR-05, Oracle DB XE 21c support)
if ($GenerateSql -and $validRows.Count -gt 0) {
    $sqlDir = Split-Path -Path $GenerateSql -Parent
    if ($sqlDir -and -not (Test-Path $sqlDir)) {
        New-Item -ItemType Directory -Path $sqlDir -Force | Out-Null
    }
    
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("-- ============================================================================")
    [void]$sb.AppendLine("-- Ingested Incidents SQL MERGE Script (FR-05 Repeatable Loading)")
    [void]$sb.AppendLine("-- Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("-- ============================================================================")
    [void]$sb.AppendLine("SET DEFINE OFF;")
    [void]$sb.AppendLine("BEGIN")

    foreach ($vr in $allTickets) {
        $safeCause = $vr.ROOT_CAUSE.Replace("'", "''")
        $mergeStmt = @"
  MERGE INTO INCIDENTS dst
  USING (SELECT '$($vr.TICKET_ID)' AS TICKET_ID FROM DUAL) src
  ON (dst.TICKET_ID = src.TICKET_ID)
  WHEN MATCHED THEN
    UPDATE SET 
      PRIORITY = '$($vr.PRIORITY)',
      CATEGORY = '$($vr.CATEGORY)',
      SERVICE = '$($vr.SERVICE)',
      ASSIGNMENT_GROUP = '$($vr.ASSIGNMENT_GROUP)',
      ROOT_CAUSE = '$safeCause',
      STATUS = '$($vr.STATUS)',
      CREATED_TIME = TIMESTAMP '$($vr.CREATED_TIME)',
      RESOLVED_TIME = TIMESTAMP '$($vr.RESOLVED_TIME)',
      SLA_DUE_TIME = TIMESTAMP '$($vr.SLA_DUE_TIME)',
      RESOLUTION_HOURS = $($vr.RESOLUTION_HOURS),
      IS_SLA_BREACH = $($vr.IS_SLA_BREACH)
  WHEN NOT MATCHED THEN
    INSERT (
      TICKET_ID, PRIORITY, CATEGORY, SERVICE, ASSIGNMENT_GROUP, ROOT_CAUSE,
      STATUS, CREATED_TIME, RESOLVED_TIME, SLA_DUE_TIME, RESOLUTION_HOURS, IS_SLA_BREACH
    ) VALUES (
      '$($vr.TICKET_ID)', '$($vr.PRIORITY)', '$($vr.CATEGORY)', '$($vr.SERVICE)', 
      '$($vr.ASSIGNMENT_GROUP)', '$safeCause', '$($vr.STATUS)',
      TIMESTAMP '$($vr.CREATED_TIME)', TIMESTAMP '$($vr.RESOLVED_TIME)', TIMESTAMP '$($vr.SLA_DUE_TIME)',
      $($vr.RESOLUTION_HOURS), $($vr.IS_SLA_BREACH)
    );
"@
        [void]$sb.AppendLine($mergeStmt)
    }

    [void]$sb.AppendLine("  COMMIT;")
    [void]$sb.AppendLine("END;")
    [void]$sb.AppendLine("/")
    [void]$sb.AppendLine("PROMPT Ingestion completed. Total records in INCIDENTS table:;")
    [void]$sb.AppendLine("SELECT COUNT(*) AS TOTAL_INCIDENTS FROM INCIDENTS;")

    [System.IO.File]::WriteAllText((Resolve-Path -Path $sqlDir).Path + "\" + (Split-Path -Path $GenerateSql -Leaf), $sb.ToString())
    Write-Host "Generated Oracle SQL Merge script: $GenerateSql" -ForegroundColor Cyan
}

# Optional direct Oracle XE execution if credentials provided
if ($OracleConnectString -and (Get-Command sqlplus -ErrorAction SilentlyContinue)) {
    Write-Host "Running Oracle SQL Ingestion via SQL*Plus..." -ForegroundColor Yellow
    sqlplus -s $OracleConnectString "@$GenerateSql"
}

# Print Ingestion Pipeline Report
Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " INGESTION SUMMARY REPORT                                        " -ForegroundColor Cyan
Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ("  Total Rows Processed       : {0,5}" -f $rows.Count)
Write-Host ("  New Valid Rows Ingested    : {0,5}" -f $validRows.Count) -ForegroundColor Green
Write-Host ("  Duplicate Rows Re-loaded   : {0,5} (FR-05 Idempotency Preserved)" -f $skippedDuplicates) -ForegroundColor Yellow
Write-Host ("  Rejected Corrupt Rows      : {0,5}" -f $rejectedRows.Count) -ForegroundColor $(if ($rejectedRows.Count -gt 0) { "Red" } else { "Green" })
Write-Host ("  Total Active Records In DB : {0,5}" -f $datastore.Count) -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

exit 0
