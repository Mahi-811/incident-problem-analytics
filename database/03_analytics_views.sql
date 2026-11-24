-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/03_analytics_views.sql
-- Description: Analytics Views for Incident KPIs, MTTR, SLAs, and Recurring Issues
-- Author: Mahi Zaman
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. View: Enriched Incidents with Reference Metadata & SLA Variance
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_INCIDENTS_ENRICHED AS
SELECT 
    i.TICKET_ID,
    i.PRIORITY,
    s.PRIORITY_NAME,
    i.CATEGORY,
    c.CATEGORY_NAME,
    i.SERVICE,
    sv.SERVICE_NAME,
    sv.CRITICAL_TIER,
    i.ASSIGNMENT_GROUP,
    g.GROUP_NAME,
    i.ROOT_CAUSE,
    i.STATUS,
    i.CREATED_TIME,
    i.RESOLVED_TIME,
    i.SLA_DUE_TIME,
    i.RESOLUTION_HOURS,
    s.RESOLUTION_TARGET_HOURS AS SLA_TARGET_HOURS,
    ROUND(i.RESOLUTION_HOURS - s.RESOLUTION_TARGET_HOURS, 2) AS SLA_VARIANCE_HOURS,
    i.IS_SLA_BREACH,
    CASE 
        WHEN i.IS_SLA_BREACH = 1 THEN 'BREACHED' 
        ELSE 'MET' 
    END AS SLA_STATUS,
    TO_CHAR(i.CREATED_TIME, 'YYYY-MM') AS CREATED_MONTH,
    TO_CHAR(i.CREATED_TIME, 'YYYY-"W"IW') AS CREATED_WEEK,
    ROUND(CAST(i.RESOLVED_TIME AS DATE) - CAST(i.CREATED_TIME AS DATE), 2) AS AGE_DAYS
FROM INCIDENTS i
JOIN SLA_MATRIX s ON i.PRIORITY = s.PRIORITY
JOIN REF_CATEGORIES c ON i.CATEGORY = c.CATEGORY_CODE
JOIN REF_SERVICES sv ON i.SERVICE = sv.SERVICE_CODE
JOIN REF_ASSIGNMENT_GROUPS g ON i.ASSIGNMENT_GROUP = g.GROUP_CODE;

-- ----------------------------------------------------------------------------
-- 2. View: Repeat Offenders (FR-06)
-- Definition: Same Category, Service, and Root Cause >= 3 times in 30 days
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_REPEAT_OFFENDERS AS
WITH rolling_window AS (
    SELECT 
        i.TICKET_ID,
        i.CATEGORY,
        i.SERVICE,
        i.ROOT_CAUSE,
        i.CREATED_TIME,
        i.RESOLUTION_HOURS,
        COUNT(*) OVER (
            PARTITION BY i.CATEGORY, i.SERVICE, i.ROOT_CAUSE
            ORDER BY i.CREATED_TIME
            RANGE BETWEEN INTERVAL '30' DAY PRECEDING AND CURRENT ROW
        ) AS OCCURRENCES_30D
    FROM INCIDENTS i
),
qualifying_patterns AS (
    SELECT DISTINCT
        CATEGORY,
        SERVICE,
        ROOT_CAUSE
    FROM rolling_window
    WHERE OCCURRENCES_30D >= 3
)
SELECT 
    q.CATEGORY,
    c.CATEGORY_NAME,
    q.SERVICE,
    sv.SERVICE_NAME,
    q.ROOT_CAUSE,
    COUNT(i.TICKET_ID) AS TOTAL_INCIDENTS,
    ROUND(AVG(i.RESOLUTION_HOURS), 2) AS AVG_MTTR_HOURS,
    SUM(i.IS_SLA_BREACH) AS TOTAL_SLA_BREACHES,
    MIN(i.CREATED_TIME) AS FIRST_SEEN_DATE,
    MAX(i.CREATED_TIME) AS LAST_SEEN_DATE,
    MAX(rw.OCCURRENCES_30D) AS MAX_30D_CLUSTER_COUNT,
    DENSE_RANK() OVER (ORDER BY COUNT(i.TICKET_ID) DESC, MAX(rw.OCCURRENCES_30D) DESC) AS RECURRING_RANK
FROM qualifying_patterns q
JOIN INCIDENTS i 
    ON q.CATEGORY = i.CATEGORY 
   AND q.SERVICE = i.SERVICE 
   AND q.ROOT_CAUSE = i.ROOT_CAUSE
JOIN rolling_window rw 
    ON i.TICKET_ID = rw.TICKET_ID
JOIN REF_CATEGORIES c ON q.CATEGORY = c.CATEGORY_CODE
JOIN REF_SERVICES sv ON q.SERVICE = sv.SERVICE_CODE
GROUP BY 
    q.CATEGORY, 
    c.CATEGORY_NAME, 
    q.SERVICE, 
    sv.SERVICE_NAME, 
    q.ROOT_CAUSE;

-- ----------------------------------------------------------------------------
-- 3. View: MTTR Analytics by Category, Priority and Month (FR-07)
-- Uses Oracle Analytic Functions (AVG, MEDIAN, STDDEV, RATIO_TO_REPORT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_MTTR_ANALYTICS AS
SELECT 
    TO_CHAR(CREATED_TIME, 'YYYY-MM') AS MONTH_KEY,
    CATEGORY,
    PRIORITY,
    COUNT(*) AS TICKET_COUNT,
    ROUND(AVG(RESOLUTION_HOURS), 2) AS MTTR_HOURS,
    ROUND(MEDIAN(RESOLUTION_HOURS), 2) AS MEDIAN_TTR_HOURS,
    ROUND(MIN(RESOLUTION_HOURS), 2) AS MIN_TTR_HOURS,
    ROUND(MAX(RESOLUTION_HOURS), 2) AS MAX_TTR_HOURS,
    ROUND(STDDEV(RESOLUTION_HOURS), 2) AS STDDEV_TTR_HOURS,
    ROUND(AVG(AVG(RESOLUTION_HOURS)) OVER (
        PARTITION BY CATEGORY, PRIORITY 
        ORDER BY TO_CHAR(CREATED_TIME, 'YYYY-MM') 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS ROLLING_3M_MTTR
FROM INCIDENTS
GROUP BY TO_CHAR(CREATED_TIME, 'YYYY-MM'), CATEGORY, PRIORITY;

-- ----------------------------------------------------------------------------
-- 4. View: SLA Breaches & Breach Percentage by Priority (FR-08)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_SLA_BREACH_SUMMARY AS
SELECT 
    s.PRIORITY,
    s.PRIORITY_NAME,
    s.RESOLUTION_TARGET_HOURS AS SLA_TARGET_HOURS,
    COUNT(i.TICKET_ID) AS TOTAL_TICKETS,
    SUM(CASE WHEN i.IS_SLA_BREACH = 0 THEN 1 ELSE 0 END) AS MET_SLA_COUNT,
    SUM(CASE WHEN i.IS_SLA_BREACH = 1 THEN 1 ELSE 0 END) AS BREACH_COUNT,
    ROUND(SUM(CASE WHEN i.IS_SLA_BREACH = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(i.TICKET_ID), 0), 2) AS BREACH_PERCENTAGE,
    ROUND(SUM(CASE WHEN i.IS_SLA_BREACH = 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(i.TICKET_ID), 0), 2) AS SLA_COMPLIANCE_PERCENTAGE,
    ROUND(AVG(i.RESOLUTION_HOURS), 2) AS ACTUAL_MTTR_HOURS
FROM SLA_MATRIX s
LEFT JOIN INCIDENTS i ON s.PRIORITY = i.PRIORITY
GROUP BY s.PRIORITY, s.PRIORITY_NAME, s.RESOLUTION_TARGET_HOURS;

-- ----------------------------------------------------------------------------
-- 5. View: Root Cause Pareto Analysis (FR-09)
-- Computes frequency, cumulative frequency, and cumulative percentage (80/20 rule)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ROOT_CAUSE_PARETO AS
WITH cause_counts AS (
    SELECT 
        ROOT_CAUSE,
        CATEGORY,
        SERVICE,
        COUNT(*) AS INCIDENT_COUNT,
        ROUND(AVG(RESOLUTION_HOURS), 2) AS AVG_RESOLUTION_HOURS,
        SUM(IS_SLA_BREACH) AS TOTAL_BREACHES
    FROM INCIDENTS
    GROUP BY ROOT_CAUSE, CATEGORY, SERVICE
)
SELECT 
    ROOT_CAUSE,
    CATEGORY,
    SERVICE,
    INCIDENT_COUNT,
    AVG_RESOLUTION_HOURS,
    TOTAL_BREACHES,
    SUM(INCIDENT_COUNT) OVER (
        ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CUMULATIVE_COUNT,
    SUM(INCIDENT_COUNT) OVER () AS GRAND_TOTAL_COUNT,
    ROUND(
        SUM(INCIDENT_COUNT) OVER (
            ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / SUM(INCIDENT_COUNT) OVER (), 
        2
    ) AS CUMULATIVE_PERCENTAGE,
    CASE 
        WHEN SUM(INCIDENT_COUNT) OVER (
            ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0 / SUM(INCIDENT_COUNT) OVER () <= 80.0 THEN 'YES'
        ELSE 'NO'
    END AS IS_TOP_80_PARETO
FROM cause_counts;

-- ----------------------------------------------------------------------------
-- 6. View: Monthly Volume & Backlog-Ageing Trend (FR-09)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_MONTHLY_VOLUME_TREND AS
SELECT 
    TO_CHAR(CREATED_TIME, 'YYYY-MM') AS MONTH_KEY,
    COUNT(*) AS TOTAL_INCIDENTS,
    SUM(CASE WHEN PRIORITY = 'P1' THEN 1 ELSE 0 END) AS P1_COUNT,
    SUM(CASE WHEN PRIORITY = 'P2' THEN 1 ELSE 0 END) AS P2_COUNT,
    SUM(CASE WHEN PRIORITY = 'P3' THEN 1 ELSE 0 END) AS P3_COUNT,
    SUM(CASE WHEN PRIORITY = 'P4' THEN 1 ELSE 0 END) AS P4_COUNT,
    ROUND(AVG(RESOLUTION_HOURS), 2) AS MTTR_HOURS,
    SUM(IS_SLA_BREACH) AS BREACH_COUNT,
    ROUND(SUM(IS_SLA_BREACH) * 100.0 / COUNT(*), 2) AS BREACH_RATE_PCT,
    -- Month-end volume calculation (last 4 days of month)
    SUM(CASE 
        WHEN EXTRACT(DAY FROM LAST_DAY(CAST(CREATED_TIME AS DATE))) - EXTRACT(DAY FROM CAST(CREATED_TIME AS DATE)) < 4 
        THEN 1 ELSE 0 
    END) AS MONTH_END_SPIKE_VOLUME,
    ROUND(
        SUM(CASE 
            WHEN EXTRACT(DAY FROM LAST_DAY(CAST(CREATED_TIME AS DATE))) - EXTRACT(DAY FROM CAST(CREATED_TIME AS DATE)) < 4 
            THEN 1 ELSE 0 
        END) * 100.0 / COUNT(*), 
        2
    ) AS MONTH_END_VOLUME_PCT
FROM INCIDENTS
GROUP BY TO_CHAR(CREATED_TIME, 'YYYY-MM');
