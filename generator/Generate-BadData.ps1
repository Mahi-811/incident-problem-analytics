<#
.SYNOPSIS
    Generates test data with deliberate schema and data anomalies.
.DESCRIPTION
    Fulfills AT-02:
    - Mixes valid rows with intentionally invalid rows.
    - Tests date validation, range validation, foreign key / enum constraints, and missing fields.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = "data/bad_incidents.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$parentDir = Split-Path -Path $OutputPath -Parent
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

$rows = @(
    # --- Valid Rows (should load successfully) ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-0001"
        PRIORITY         = "P1"
        CATEGORY         = "SOFTWARE"
        SERVICE          = "PAYMENT_GATEWAY"
        ASSIGNMENT_GROUP = "GRP_APP_DEV"
        ROOT_CAUSE       = "Connection Pool Exhaustion under Peak Traffic"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-01 10:00:00"
        RESOLVED_TIME    = "2026-10-01 12:30:00"
        SLA_DUE_TIME     = "2026-10-01 14:00:00"
        RESOLUTION_HOURS = 2.50
        IS_SLA_BREACH    = 0
    },
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-0002"
        PRIORITY         = "P2"
        CATEGORY         = "DATABASE"
        SERVICE          = "BILLING_ENGINE"
        ASSIGNMENT_GROUP = "GRP_DBA_TEAM"
        ROOT_CAUSE       = "Batch Job Lock Contention on Invoice Table"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-02 11:00:00"
        RESOLVED_TIME    = "2026-10-02 16:00:00"
        SLA_DUE_TIME     = "2026-10-02 19:00:00"
        RESOLUTION_HOURS = 5.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 1: Invalid Priority ('P9') ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-01"
        PRIORITY         = "P9"
        CATEGORY         = "SOFTWARE"
        SERVICE          = "PAYMENT_GATEWAY"
        ASSIGNMENT_GROUP = "GRP_APP_DEV"
        ROOT_CAUSE       = "Memory leak in transaction router"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-03 10:00:00"
        RESOLVED_TIME    = "2026-10-03 12:00:00"
        SLA_DUE_TIME     = "2026-10-03 14:00:00"
        RESOLUTION_HOURS = 2.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 2: Invalid Date Format in CREATED_TIME ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-02"
        PRIORITY         = "P2"
        CATEGORY         = "DATABASE"
        SERVICE          = "BILLING_ENGINE"
        ASSIGNMENT_GROUP = "GRP_DBA_TEAM"
        ROOT_CAUSE       = "Deadlock on account ledger"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-99-99 99:99:99"
        RESOLVED_TIME    = "2026-10-04 12:00:00"
        SLA_DUE_TIME     = "2026-10-04 18:00:00"
        RESOLUTION_HOURS = 6.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 3: Resolved Time Earlier Than Created Time ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-03"
        PRIORITY         = "P3"
        CATEGORY         = "INFRASTRUCTURE"
        SERVICE          = "USER_PORTAL"
        ASSIGNMENT_GROUP = "GRP_INFRA_OPS"
        ROOT_CAUSE       = "DNS Resolution Failure across VPC"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-05 15:00:00"
        RESOLVED_TIME    = "2026-10-05 10:00:00" # Earlier!
        SLA_DUE_TIME     = "2026-10-06 15:00:00"
        RESOLUTION_HOURS = -5.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 4: Unknown Category ('AI_ROBOTICS') ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-04"
        PRIORITY         = "P2"
        CATEGORY         = "AI_ROBOTICS"
        SERVICE          = "USER_PORTAL"
        ASSIGNMENT_GROUP = "GRP_INFRA_OPS"
        ROOT_CAUSE       = "Model drift detected"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-06 10:00:00"
        RESOLVED_TIME    = "2026-10-06 14:00:00"
        SLA_DUE_TIME     = "2026-10-06 18:00:00"
        RESOLUTION_HOURS = 4.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 5: Unknown Service ('CRYPTOCURRENCY_MINE') ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-05"
        PRIORITY         = "P3"
        CATEGORY         = "SOFTWARE"
        SERVICE          = "CRYPTOCURRENCY_MINE"
        ASSIGNMENT_GROUP = "GRP_APP_DEV"
        ROOT_CAUSE       = "Hash rate drop"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-07 10:00:00"
        RESOLVED_TIME    = "2026-10-07 16:00:00"
        SLA_DUE_TIME     = "2026-10-08 10:00:00"
        RESOLUTION_HOURS = 6.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 6: Unknown Assignment Group ('GRP_ROGUE_AGENTS') ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-06"
        PRIORITY         = "P2"
        CATEGORY         = "SECURITY"
        SERVICE          = "IDENTITY_AUTH"
        ASSIGNMENT_GROUP = "GRP_ROGUE_AGENTS"
        ROOT_CAUSE       = "Unauthorized admin token"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-08 10:00:00"
        RESOLVED_TIME    = "2026-10-08 14:00:00"
        SLA_DUE_TIME     = "2026-10-08 18:00:00"
        RESOLUTION_HOURS = 4.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 7: Missing Required Field (Empty TICKET_ID) ---
    [PSCustomObject]@{
        TICKET_ID        = ""
        PRIORITY         = "P1"
        CATEGORY         = "SOFTWARE"
        SERVICE          = "PAYMENT_GATEWAY"
        ASSIGNMENT_GROUP = "GRP_APP_DEV"
        ROOT_CAUSE       = "Null ticket identifier"
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-09 10:00:00"
        RESOLVED_TIME    = "2026-10-09 12:00:00"
        SLA_DUE_TIME     = "2026-10-09 14:00:00"
        RESOLUTION_HOURS = 2.00
        IS_SLA_BREACH    = 0
    },

    # --- Bad Row 8: Missing Required Field (Empty ROOT_CAUSE) ---
    [PSCustomObject]@{
        TICKET_ID        = "INC-TEST-BAD-08"
        PRIORITY         = "P2"
        CATEGORY         = "SOFTWARE"
        SERVICE          = "PAYMENT_GATEWAY"
        ASSIGNMENT_GROUP = "GRP_APP_DEV"
        ROOT_CAUSE       = ""
        STATUS           = "RESOLVED"
        CREATED_TIME     = "2026-10-10 10:00:00"
        RESOLVED_TIME    = "2026-10-10 14:00:00"
        SLA_DUE_TIME     = "2026-10-10 18:00:00"
        RESOLUTION_HOURS = 4.00
        IS_SLA_BREACH    = 0
    }
)

$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Generated $($rows.Count) test records ($($rows.Count - 2) intentional bad records) to '$OutputPath'" -ForegroundColor Green
