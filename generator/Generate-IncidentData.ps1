<#
.SYNOPSIS
    Generates synthetic ITIL incident ticket data for Oracle XE 21c analytics.
.DESCRIPTION
    Fulfills FR-01, FR-02, and NFR-05:
    - Produces >= 400 tickets across 6 months.
    - Deterministic output via -Seed parameter (NFR-05).
    - Seeds 3 specific recurring issue patterns (FR-02) that rank strictly #1, #2, and #3 (AT-04).
    - Introduces month-end volume spikes (FR-02).
    - Accurately aligns SLA due dates and breach calculations.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = "data/incidents.csv",
    [int]$Count = 520,
    [int]$Seed = 20261124,
    [datetime]$StartDate = (Get-Date "2026-06-01 00:00:00"),
    [datetime]$EndDate = (Get-Date "2026-11-24 23:59:59")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " ITIL Incident Synthetic Data Generator (SRS 2 - FR-01, FR-02)   " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Target Count : $Count tickets"
Write-Host "Random Seed  : $Seed (Reproducible NFR-05)"
Write-Host "Date Window  : $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))"
Write-Host "Output Path  : $OutputPath"

# Ensure output directory exists
$parentDir = Split-Path -Path $OutputPath -Parent
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

$rng = [System.Random]::new($Seed)

# Reference SLA targets in hours
$slaTargets = @{
    "P1" = 4.0
    "P2" = 8.0
    "P3" = 24.0
    "P4" = 72.0
}

# Category to Group mapping
$catGroupMap = @{
    "SOFTWARE"       = "GRP_APP_DEV"
    "DATABASE"       = "GRP_DBA_TEAM"
    "INFRASTRUCTURE" = "GRP_INFRA_OPS"
    "SECURITY"       = "GRP_NET_SEC"
    "HARDWARE"       = "GRP_SERVICE_DESK"
}

# Services list
$services = @("PAYMENT_GATEWAY", "BILLING_ENGINE", "USER_PORTAL", "CORE_BANKING_API", "REPORTING_SERVICE", "IDENTITY_AUTH")

# -----------------------------------------------------------------------------
# FR-02: Seeded Recurring Patterns Definitions (Rank #1, #2, #3 for AT-04)
# -----------------------------------------------------------------------------
# Pattern 1 (Top Repeat Offender - Target for PRB-2026-001 & CHG-2026-042)
$pattern1 = @{
    Category   = "SOFTWARE"
    Service    = "PAYMENT_GATEWAY"
    RootCause  = "Connection Pool Exhaustion under Peak Traffic"
    Group      = "GRP_APP_DEV"
    Priority   = "P1"
    AltPrio    = "P2"
    Count      = 38 # Dominant #1 recurring pattern across the 6 months
}

# Pattern 2 (Database Month-End Contention - Rank #2)
$pattern2 = @{
    Category   = "DATABASE"
    Service    = "BILLING_ENGINE"
    RootCause  = "Batch Job Lock Contention on Invoice Table"
    Group      = "GRP_DBA_TEAM"
    Priority   = "P2"
    AltPrio    = "P3"
    Count      = 27 # Rank #2 recurring pattern, clustered month-ends
}

# Pattern 3 (Infrastructure Edge Gateway Handshake Timeout - Rank #3)
$pattern3 = @{
    Category   = "INFRASTRUCTURE"
    Service    = "USER_PORTAL"
    RootCause  = "SSL Handshake Timeout on Edge Proxy"
    Group      = "GRP_INFRA_OPS"
    Priority   = "P2"
    AltPrio    = "P3"
    Count      = 22 # Rank #3 recurring pattern, repeating bi-weekly
}

# Extensive pool of 45 diverse realistic operational causes so background noise is distributed thinly (2-7 per cause)
$generalCauses = @(
    @{ Cat = "SOFTWARE";       Svc = "CORE_BANKING_API";  Cause = "NullPointerException in JSON Deserializer" },
    @{ Cat = "SOFTWARE";       Svc = "REPORTING_SERVICE"; Cause = "Out of Memory in PDF Export Microservice" },
    @{ Cat = "SOFTWARE";       Svc = "USER_PORTAL";       Cause = "Race Condition in Session Token Refresh" },
    @{ Cat = "SOFTWARE";       Svc = "IDENTITY_AUTH";     Cause = "LDAP Connection Pool Timeout During Sync" },
    @{ Cat = "SOFTWARE";       Svc = "CORE_BANKING_API";  Cause = "Invalid Currency Rounding in FX Exchange Routine" },
    @{ Cat = "SOFTWARE";       Svc = "BILLING_ENGINE";    Cause = "Missing Tax Rate Calculation for Jurisdiction Code" },
    @{ Cat = "SOFTWARE";       Svc = "USER_PORTAL";       Cause = "Broken Image Thumbnail Generation in CDN Sync" },
    @{ Cat = "SOFTWARE";       Svc = "PAYMENT_GATEWAY";   Cause = "Malformed ISO 8583 Message Payload Parsing Failure" },
    @{ Cat = "SOFTWARE";       Svc = "REPORTING_SERVICE"; Cause = "Deadlock between Extract and Aggregator Workers" },
    @{ Cat = "SOFTWARE";       Svc = "CORE_BANKING_API";  Cause = "Kafka Consumer Group Rebalance Lag on Ledger Queue" },

    @{ Cat = "DATABASE";       Svc = "CORE_BANKING_API";  Cause = "Deadlock on Account Ledger During Settlement" },
    @{ Cat = "DATABASE";       Svc = "REPORTING_SERVICE"; Cause = "Temporary Tablespace Exhaustion on Large Query" },
    @{ Cat = "DATABASE";       Svc = "PAYMENT_GATEWAY";   Cause = "Stale Execution Plan after Table Statistics Gather" },
    @{ Cat = "DATABASE";       Svc = "USER_PORTAL";       Cause = "Row Lock Contention on User Notification Log" },
    @{ Cat = "DATABASE";       Svc = "IDENTITY_AUTH";     Cause = "Undo Retention Exceeded During User Bulk Import" },
    @{ Cat = "DATABASE";       Svc = "CORE_BANKING_API";  Cause = "Sequence Number Cache Exhaustion on Transaction IDs" },
    @{ Cat = "DATABASE";       Svc = "BILLING_ENGINE";    Cause = "Index Fragmentation on Monthly Ledger Partition" },
    @{ Cat = "DATABASE";       Svc = "REPORTING_SERVICE"; Cause = "Materialized View Refresh ORA-01555 Snapshot Too Old" },

    @{ Cat = "INFRASTRUCTURE"; Svc = "PAYMENT_GATEWAY";   Cause = "Network Packet Drop across Availability Zones" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "BILLING_ENGINE";    Cause = "Container Host CPU Throttling on Shared Node" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "CORE_BANKING_API";  Cause = "Kubernetes Ingress Controller 502 Bad Gateway" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "IDENTITY_AUTH";     Cause = "NTP Time Drift Exceeding Kerberos Tolerance" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "USER_PORTAL";       Cause = "BGP Route Flapping on Primary Transit Link" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "REPORTING_SERVICE"; Cause = "NFS Mount Stale File Handle on Backup Target" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "CORE_BANKING_API";  Cause = "DNS Latency Spike in Internal Core Resolvers" },
    @{ Cat = "INFRASTRUCTURE"; Svc = "PAYMENT_GATEWAY";   Cause = "Firewall State Table Exhaustion on VPN Tunnel" },

    @{ Cat = "SECURITY";       Svc = "IDENTITY_AUTH";     Cause = "Expired OAuth Client Secret in Token Exchange" },
    @{ Cat = "SECURITY";       Svc = "USER_PORTAL";       Cause = "WAF False Positive Blocking Legitimate API Requests" },
    @{ Cat = "SECURITY";       Svc = "CORE_BANKING_API";  Cause = "mTLS Certificate Expiration on Partner Gateway" },
    @{ Cat = "SECURITY";       Svc = "PAYMENT_GATEWAY";   Cause = "HSM Crypto Module Communication Failure" },
    @{ Cat = "SECURITY";       Svc = "BILLING_ENGINE";    Cause = "Vault Token Revocation Causing Decryption Errors" },
    @{ Cat = "SECURITY";       Svc = "USER_PORTAL";       Cause = "Rate Limiter Tripped by Vulnerability Scanner" },
    @{ Cat = "SECURITY";       Svc = "REPORTING_SERVICE"; Cause = "Missing RBAC Permission on Financial Data Mart" },

    @{ Cat = "HARDWARE";       Svc = "CORE_BANKING_API";  Cause = "Fiber Channel Storage Adapter Controller Fault" },
    @{ Cat = "HARDWARE";       Svc = "BILLING_ENGINE";    Cause = "Degraded RAID Disk Array on Primary DB Host" },
    @{ Cat = "HARDWARE";       Svc = "USER_PORTAL";       Cause = "Top of Rack Switch Power Supply Unit Failure" },
    @{ Cat = "HARDWARE";       Svc = "PAYMENT_GATEWAY";   Cause = "Memory DIMM ECC Multi-Bit Error on Compute Blade" },
    @{ Cat = "HARDWARE";       Svc = "REPORTING_SERVICE"; Cause = "SAN Controller Cache Battery Discharge" }
)

$tickets = [System.Collections.Generic.List[PSObject]]::new()
$ticketCounter = 1

function Format-SqlDate([datetime]$dt) {
    return $dt.ToString("yyyy-MM-dd HH:mm:ss")
}

# Helper to generate random timestamp in date range with month-end weighting
function Get-RandomTimestamp([datetime]$start, [datetime]$end, [bool]$preferMonthEnd = $false) {
    $totalSeconds = ($end - $start).TotalSeconds
    
    if ($preferMonthEnd) {
        $monthOffset = $rng.Next(0, 6)
        $mStart = $start.AddMonths($monthOffset)
        $daysInMonth = [DateTime]::DaysInMonth($mStart.Year, $mStart.Month)
        $day = $rng.Next([Math]::Max(1, $daysInMonth - 3), $daysInMonth + 1)
        $hour = $rng.Next(8, 22)
        $min = $rng.Next(0, 60)
        $sec = $rng.Next(0, 60)
        $dt = [DateTime]::new($mStart.Year, $mStart.Month, $day, $hour, $min, $sec)
        if ($dt -gt $end) { $dt = $end.AddHours(-($rng.Next(1, 24))) }
        return $dt
    } else {
        $secOffset = $rng.NextDouble() * $totalSeconds
        return $start.AddSeconds($secOffset)
    }
}

# 1. Generate Pattern 1 Tickets (Seeded Top Repeat Offender: 38 tickets)
Write-Host "Seeding Pattern 1 (Rank #1): Payment Gateway Connection Pool Exhaustion..." -ForegroundColor Yellow
for ($i = 0; $i -lt $pattern1.Count; $i++) {
    $prio = if ($rng.NextDouble() -lt 0.70) { $pattern1.Priority } else { $pattern1.AltPrio }
    $monthIndex = $i % 6
    $mBase = $StartDate.AddMonths($monthIndex)
    $day = $rng.Next(1, [DateTime]::DaysInMonth($mBase.Year, $mBase.Month) + 1)
    $hour = $rng.Next(9, 21)
    $min = $rng.Next(0, 60)
    $created = [DateTime]::new($mBase.Year, $mBase.Month, $day, $hour, $min, $rng.Next(0, 60))
    if ($created -gt $EndDate) { $created = $EndDate.AddHours(-($rng.Next(1, 48))) }

    $targetHrs = $slaTargets[$prio]
    $slaDue = $created.AddHours($targetHrs)
    
    $isBreach = if ($rng.NextDouble() -lt 0.20) { 1 } else { 0 }
    if ($isBreach -eq 1) {
        $resolveHrs = [Math]::Round($targetHrs * (1.1 + ($rng.NextDouble() * 1.2)), 2)
    } else {
        $resolveHrs = [Math]::Round($targetHrs * (0.3 + ($rng.NextDouble() * 0.6)), 2)
    }
    $resolved = $created.AddHours($resolveHrs)

    $tickets.Add([PSCustomObject]@{
        TICKET_ID        = "INC-2026-{0:D4}" -f $ticketCounter++
        PRIORITY         = $prio
        CATEGORY         = $pattern1.Category
        SERVICE          = $pattern1.Service
        ASSIGNMENT_GROUP = $pattern1.Group
        ROOT_CAUSE       = $pattern1.RootCause
        STATUS           = "RESOLVED"
        CREATED_TIME     = (Format-SqlDate $created)
        RESOLVED_TIME    = (Format-SqlDate $resolved)
        SLA_DUE_TIME     = (Format-SqlDate $slaDue)
        RESOLUTION_HOURS = $resolveHrs
        IS_SLA_BREACH    = $isBreach
    })
}

# 2. Generate Pattern 2 Tickets (Seeded Month-End Database Lock Contention: 27 tickets)
Write-Host "Seeding Pattern 2 (Rank #2): Billing Engine Lock Contention (Month-End Cluster)..." -ForegroundColor Yellow
for ($i = 0; $i -lt $pattern2.Count; $i++) {
    $prio = if ($rng.NextDouble() -lt 0.60) { $pattern2.Priority } else { $pattern2.AltPrio }
    $created = Get-RandomTimestamp $StartDate $EndDate -preferMonthEnd $true
    $targetHrs = $slaTargets[$prio]
    $slaDue = $created.AddHours($targetHrs)
    $isBreach = if ($rng.NextDouble() -lt 0.15) { 1 } else { 0 }
    if ($isBreach -eq 1) {
        $resolveHrs = [Math]::Round($targetHrs * (1.15 + ($rng.NextDouble() * 0.8)), 2)
    } else {
        $resolveHrs = [Math]::Round($targetHrs * (0.4 + ($rng.NextDouble() * 0.5)), 2)
    }
    $resolved = $created.AddHours($resolveHrs)

    $tickets.Add([PSCustomObject]@{
        TICKET_ID        = "INC-2026-{0:D4}" -f $ticketCounter++
        PRIORITY         = $prio
        CATEGORY         = $pattern2.Category
        SERVICE          = $pattern2.Service
        ASSIGNMENT_GROUP = $pattern2.Group
        ROOT_CAUSE       = $pattern2.RootCause
        STATUS           = "RESOLVED"
        CREATED_TIME     = (Format-SqlDate $created)
        RESOLVED_TIME    = (Format-SqlDate $resolved)
        SLA_DUE_TIME     = (Format-SqlDate $slaDue)
        RESOLUTION_HOURS = $resolveHrs
        IS_SLA_BREACH    = $isBreach
    })
}

# 3. Generate Pattern 3 Tickets (Seeded Edge Gateway SSL Handshake: 20 tickets)
Write-Host "Seeding Pattern 3 (Rank #3): User Portal SSL Handshake Timeout (Bi-weekly Cluster)..." -ForegroundColor Yellow
for ($i = 0; $i -lt $pattern3.Count; $i++) {
    $prio = if ($rng.NextDouble() -lt 0.50) { $pattern3.Priority } else { $pattern3.AltPrio }
    $weekNum = [Math]::Floor($i * 1.2)
    $created = $StartDate.AddDays($weekNum * 7 + $rng.Next(1, 5)).AddHours($rng.Next(8, 18)).AddMinutes($rng.Next(0, 60))
    if ($created -gt $EndDate) { $created = $EndDate.AddHours(-($rng.Next(1, 48))) }
    $targetHrs = $slaTargets[$prio]
    $slaDue = $created.AddHours($targetHrs)
    $isBreach = if ($rng.NextDouble() -lt 0.10) { 1 } else { 0 }
    if ($isBreach -eq 1) {
        $resolveHrs = [Math]::Round($targetHrs * (1.1 + ($rng.NextDouble() * 0.5)), 2)
    } else {
        $resolveHrs = [Math]::Round($targetHrs * (0.35 + ($rng.NextDouble() * 0.5)), 2)
    }
    $resolved = $created.AddHours($resolveHrs)

    $tickets.Add([PSCustomObject]@{
        TICKET_ID        = "INC-2026-{0:D4}" -f $ticketCounter++
        PRIORITY         = $prio
        CATEGORY         = $pattern3.Category
        SERVICE          = $pattern3.Service
        ASSIGNMENT_GROUP = $pattern3.Group
        ROOT_CAUSE       = $pattern3.RootCause
        STATUS           = "RESOLVED"
        CREATED_TIME     = (Format-SqlDate $created)
        RESOLVED_TIME    = (Format-SqlDate $resolved)
        SLA_DUE_TIME     = (Format-SqlDate $slaDue)
        RESOLUTION_HOURS = $resolveHrs
        IS_SLA_BREACH    = $isBreach
    })
}

# 4. Generate Remaining General Population Tickets (with Month-End Volume Spike)
$remaining = $Count - $tickets.Count
Write-Host "Generating remaining $remaining operational tickets spread across general pool..." -ForegroundColor Cyan

for ($i = 0; $i -lt $remaining; $i++) {
    # Month-end spike probability: 30% of remaining tickets occur in last 4 days of month
    $isMonthEndTicket = ($rng.NextDouble() -lt 0.30)
    $created = Get-RandomTimestamp $StartDate $EndDate -preferMonthEnd $isMonthEndTicket

    # Priority distribution: P1 (8%), P2 (22%), P3 (50%), P4 (20%)
    $pVal = $rng.NextDouble()
    $prio = if ($pVal -lt 0.08) { "P1" }
            elseif ($pVal -lt 0.30) { "P2" }
            elseif ($pVal -lt 0.80) { "P3" }
            else { "P4" }

    # Pick cause from diverse generalCauses pool
    $causeObj = $generalCauses[$rng.Next(0, $generalCauses.Count)]
    $cat = $causeObj.Cat
    $svc = $causeObj.Svc
    $cause = $causeObj.Cause
    $grp = $catGroupMap[$cat]

    $targetHrs = $slaTargets[$prio]
    $slaDue = $created.AddHours($targetHrs)

    # Realistic SLA breach rate ~ 11% overall
    $isBreach = if ($rng.NextDouble() -lt 0.11) { 1 } else { 0 }
    if ($isBreach -eq 1) {
        $resolveHrs = [Math]::Round($targetHrs * (1.05 + ($rng.NextDouble() * 1.5)), 2)
    } else {
        $resolveHrs = [Math]::Round($targetHrs * (0.15 + ($rng.NextDouble() * 0.75)), 2)
    }
    if ($resolveHrs -lt 0.10) { $resolveHrs = 0.10 }
    $resolved = $created.AddHours($resolveHrs)

    $status = "RESOLVED"
    if ($created -gt $EndDate.AddDays(-3) -and ($rng.NextDouble() -lt 0.25)) {
        $status = if ($rng.NextDouble() -lt 0.5) { "IN_PROGRESS" } else { "OPEN" }
    }

    $tickets.Add([PSCustomObject]@{
        TICKET_ID        = "INC-2026-{0:D4}" -f $ticketCounter++
        PRIORITY         = $prio
        CATEGORY         = $cat
        SERVICE          = $svc
        ASSIGNMENT_GROUP = $grp
        ROOT_CAUSE       = $cause
        STATUS           = $status
        CREATED_TIME     = (Format-SqlDate $created)
        RESOLVED_TIME    = (Format-SqlDate $resolved)
        SLA_DUE_TIME     = (Format-SqlDate $slaDue)
        RESOLUTION_HOURS = $resolveHrs
        IS_SLA_BREACH    = $isBreach
    })
}

# Sort all tickets by CREATED_TIME ascending for chronological realism
$sortedTickets = $tickets | Sort-Object { [DateTime]::Parse($_.CREATED_TIME) }

# Re-assign sequential IDs in clean chronological order
$reId = 1
foreach ($t in $sortedTickets) {
    $t.TICKET_ID = "INC-2026-{0:D4}" -f $reId++
}

# Export to CSV
$sortedTickets | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Successfully generated $($sortedTickets.Count) tickets to '$OutputPath'" -ForegroundColor Green

# Print Summary Diagnostics
$prioSummary = $sortedTickets | Group-Object PRIORITY | Select-Object Name, Count
Write-Host "`nPriority Distribution:" -ForegroundColor Yellow
$prioSummary | ForEach-Object { Write-Host ("  {0,-5} : {1,4} tickets ({2,5:P1})" -f $_.Name, $_.Count, ($_.Count / $sortedTickets.Count)) }

$topCauses = $sortedTickets | Group-Object ROOT_CAUSE | Sort-Object Count -Descending | Select-Object -First 5
Write-Host "`nTop 5 Root Causes:" -ForegroundColor Yellow
$topCauses | ForEach-Object { Write-Host ("  {0,-52} : {1,3} occurrences" -f $_.Name, $_.Count) }

$breachCount = ($sortedTickets | Where-Object { $_.IS_SLA_BREACH -eq 1 }).Count
Write-Host "`nSLA Breach Metrics:" -ForegroundColor Yellow
Write-Host ("  Total Breaches : {0} / {1} ({2:P1})" -f $breachCount, $sortedTickets.Count, ($breachCount / $sortedTickets.Count))
Write-Host "=================================================================" -ForegroundColor Cyan
