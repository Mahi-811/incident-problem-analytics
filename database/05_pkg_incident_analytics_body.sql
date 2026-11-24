-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/05_pkg_incident_analytics_body.sql
-- Description: PL/SQL Package Body: PKG_INCIDENT_ANALYTICS
-- Author: Mahi Zaman
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY PKG_INCIDENT_ANALYTICS AS

    -- ------------------------------------------------------------------------
    -- FR-06: get_repeat_offenders
    -- ------------------------------------------------------------------------
    FUNCTION get_repeat_offenders(
        p_days_window   IN NUMBER DEFAULT 30,
        p_min_count     IN NUMBER DEFAULT 3
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
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
                        RANGE BETWEEN NUMTODSINTERVAL(p_days_window, 'DAY') PRECEDING AND CURRENT ROW
                    ) AS OCCURRENCES_IN_WINDOW
                FROM INCIDENTS i
            ),
            qualified AS (
                SELECT DISTINCT
                    CATEGORY,
                    SERVICE,
                    ROOT_CAUSE
                FROM rolling_window
                WHERE OCCURRENCES_IN_WINDOW >= p_min_count
            )
            SELECT 
                q.CATEGORY,
                c.CATEGORY_NAME,
                q.SERVICE,
                sv.SERVICE_NAME,
                q.ROOT_CAUSE,
                COUNT(i.TICKET_ID) AS TOTAL_INCIDENTS,
                ROUND(AVG(i.RESOLUTION_HOURS), 2) AS AVG_MTTR_HOURS,
                SUM(i.IS_SLA_BREACH) AS SLA_BREACHES,
                ROUND(SUM(i.IS_SLA_BREACH) * 100.0 / COUNT(i.TICKET_ID), 2) AS BREACH_PCT,
                MIN(i.CREATED_TIME) AS FIRST_DETECTED,
                MAX(i.CREATED_TIME) AS LAST_DETECTED,
                MAX(rw.OCCURRENCES_IN_WINDOW) AS MAX_30D_BURST,
                DENSE_RANK() OVER (
                    ORDER BY COUNT(i.TICKET_ID) DESC, 
                             MAX(rw.OCCURRENCES_IN_WINDOW) DESC, 
                             q.ROOT_CAUSE ASC
                ) AS RECURRING_RANK
            FROM qualified q
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
                q.ROOT_CAUSE
            ORDER BY RECURRING_RANK ASC;

        RETURN v_cur;
    END get_repeat_offenders;

    -- ------------------------------------------------------------------------
    -- FR-07: get_mttr_analytics
    -- ------------------------------------------------------------------------
    FUNCTION get_mttr_analytics(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT 
                TO_CHAR(i.CREATED_TIME, 'YYYY-MM') AS MONTH_KEY,
                i.CATEGORY,
                c.CATEGORY_NAME,
                i.PRIORITY,
                COUNT(*) AS TICKET_COUNT,
                ROUND(AVG(i.RESOLUTION_HOURS), 2) AS MTTR_HOURS,
                ROUND(MEDIAN(i.RESOLUTION_HOURS), 2) AS MEDIAN_TTR_HOURS,
                ROUND(MIN(i.RESOLUTION_HOURS), 2) AS MIN_TTR_HOURS,
                ROUND(MAX(i.RESOLUTION_HOURS), 2) AS MAX_TTR_HOURS,
                ROUND(STDDEV(i.RESOLUTION_HOURS), 2) AS STDDEV_TTR_HOURS,
                ROUND(AVG(AVG(i.RESOLUTION_HOURS)) OVER (
                    PARTITION BY i.CATEGORY, i.PRIORITY 
                    ORDER BY TO_CHAR(i.CREATED_TIME, 'YYYY-MM') 
                    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
                ), 2) AS ROLLING_3M_MTTR
            FROM INCIDENTS i
            JOIN REF_CATEGORIES c ON i.CATEGORY = c.CATEGORY_CODE
            WHERE (p_start_date IS NULL OR i.CREATED_TIME >= p_start_date)
              AND (p_end_date IS NULL OR i.CREATED_TIME <= p_end_date)
            GROUP BY TO_CHAR(i.CREATED_TIME, 'YYYY-MM'), i.CATEGORY, c.CATEGORY_NAME, i.PRIORITY
            ORDER BY MONTH_KEY ASC, i.CATEGORY ASC, i.PRIORITY ASC;

        RETURN v_cur;
    END get_mttr_analytics;

    -- ------------------------------------------------------------------------
    -- FR-08: get_sla_breach_summary
    -- ------------------------------------------------------------------------
    FUNCTION get_sla_breach_summary(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            SELECT 
                s.PRIORITY,
                s.PRIORITY_NAME,
                s.RESOLUTION_TARGET_HOURS,
                COUNT(i.TICKET_ID) AS TOTAL_TICKETS,
                SUM(CASE WHEN i.IS_SLA_BREACH = 0 THEN 1 ELSE 0 END) AS MET_SLA_COUNT,
                SUM(CASE WHEN i.IS_SLA_BREACH = 1 THEN 1 ELSE 0 END) AS BREACH_COUNT,
                ROUND(
                    SUM(CASE WHEN i.IS_SLA_BREACH = 1 THEN 1 ELSE 0 END) * 100.0 / 
                    NULLIF(COUNT(i.TICKET_ID), 0), 
                    2
                ) AS BREACH_PERCENTAGE,
                ROUND(
                    SUM(CASE WHEN i.IS_SLA_BREACH = 0 THEN 1 ELSE 0 END) * 100.0 / 
                    NULLIF(COUNT(i.TICKET_ID), 0), 
                    2
                ) AS COMPLIANCE_PERCENTAGE,
                ROUND(AVG(i.RESOLUTION_HOURS), 2) AS ACTUAL_MTTR_HOURS
            FROM SLA_MATRIX s
            LEFT JOIN INCIDENTS i 
                ON s.PRIORITY = i.PRIORITY
               AND (p_start_date IS NULL OR i.CREATED_TIME >= p_start_date)
               AND (p_end_date IS NULL OR i.CREATED_TIME <= p_end_date)
            GROUP BY s.PRIORITY, s.PRIORITY_NAME, s.RESOLUTION_TARGET_HOURS
            ORDER BY s.PRIORITY ASC;

        RETURN v_cur;
    END get_sla_breach_summary;

    -- ------------------------------------------------------------------------
    -- FR-09: get_root_cause_pareto
    -- ------------------------------------------------------------------------
    FUNCTION get_root_cause_pareto(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
            WITH aggregated AS (
                SELECT 
                    i.ROOT_CAUSE,
                    i.CATEGORY,
                    c.CATEGORY_NAME,
                    i.SERVICE,
                    sv.SERVICE_NAME,
                    COUNT(*) AS INCIDENT_COUNT,
                    ROUND(AVG(i.RESOLUTION_HOURS), 2) AS AVG_RESOLUTION_HOURS,
                    SUM(i.IS_SLA_BREACH) AS TOTAL_BREACHES
                FROM INCIDENTS i
                JOIN REF_CATEGORIES c ON i.CATEGORY = c.CATEGORY_CODE
                JOIN REF_SERVICES sv ON i.SERVICE = sv.SERVICE_CODE
                WHERE (p_start_date IS NULL OR i.CREATED_TIME >= p_start_date)
                  AND (p_end_date IS NULL OR i.CREATED_TIME <= p_end_date)
                GROUP BY i.ROOT_CAUSE, i.CATEGORY, c.CATEGORY_NAME, i.SERVICE, sv.SERVICE_NAME
            )
            SELECT 
                ROOT_CAUSE,
                CATEGORY,
                CATEGORY_NAME,
                SERVICE,
                SERVICE_NAME,
                INCIDENT_COUNT,
                AVG_RESOLUTION_HOURS,
                TOTAL_BREACHES,
                SUM(INCIDENT_COUNT) OVER (
                    ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS CUMULATIVE_COUNT,
                SUM(INCIDENT_COUNT) OVER () AS TOTAL_VOLUME,
                ROUND(
                    SUM(INCIDENT_COUNT) OVER (
                        ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) * 100.0 / SUM(INCIDENT_COUNT) OVER (), 
                    2
                ) AS CUMULATIVE_PCT,
                CASE 
                    WHEN SUM(INCIDENT_COUNT) OVER (
                        ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) * 100.0 / SUM(INCIDENT_COUNT) OVER () <= 80.0 THEN 'YES' 
                    ELSE 'NO' 
                END AS PARETO_80_FLAG
            FROM aggregated
            ORDER BY INCIDENT_COUNT DESC, ROOT_CAUSE ASC;

        RETURN v_cur;
    END get_root_cause_pareto;

    -- ------------------------------------------------------------------------
    -- FR-09: get_monthly_volume_trend
    -- ------------------------------------------------------------------------
    FUNCTION get_monthly_volume_trend(
        p_months_back   IN NUMBER DEFAULT 6
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
    BEGIN
        OPEN v_cur FOR
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
                SUM(CASE 
                    WHEN EXTRACT(DAY FROM LAST_DAY(CAST(CREATED_TIME AS DATE))) - EXTRACT(DAY FROM CAST(CREATED_TIME AS DATE)) < 4 
                    THEN 1 ELSE 0 
                END) AS MONTH_END_SPIKE_COUNT,
                ROUND(
                    SUM(CASE 
                        WHEN EXTRACT(DAY FROM LAST_DAY(CAST(CREATED_TIME AS DATE))) - EXTRACT(DAY FROM CAST(CREATED_TIME AS DATE)) < 4 
                        THEN 1 ELSE 0 
                    END) * 100.0 / COUNT(*), 
                    2
                ) AS MONTH_END_SPIKE_PCT
            FROM INCIDENTS
            WHERE CREATED_TIME >= ADD_MONTHS(SYSDATE, -p_months_back)
            GROUP BY TO_CHAR(CREATED_TIME, 'YYYY-MM')
            ORDER BY MONTH_KEY ASC;

        RETURN v_cur;
    END get_monthly_volume_trend;

    -- ------------------------------------------------------------------------
    -- FR-10 & FR-11: get_kpi_summary
    -- ------------------------------------------------------------------------
    FUNCTION get_kpi_summary(
        p_start_date    IN DATE,
        p_end_date      IN DATE
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
        v_window_days NUMBER;
        v_prior_start DATE;
        v_prior_end DATE;
    BEGIN
        v_window_days := TRUNC(p_end_date) - TRUNC(p_start_date) + 1;
        v_prior_start := p_start_date - v_window_days;
        v_prior_end   := p_start_date - 1;

        OPEN v_cur FOR
            WITH current_period AS (
                SELECT 
                    'CURRENT' AS PERIOD_TYPE,
                    COUNT(*) AS VOLUME,
                    ROUND(AVG(RESOLUTION_HOURS), 2) AS MTTR,
                    SUM(IS_SLA_BREACH) AS BREACHES,
                    ROUND((1 - (SUM(IS_SLA_BREACH) / NULLIF(COUNT(*), 0))) * 100, 2) AS SLA_COMPLIANCE,
                    SUM(CASE WHEN PRIORITY = 'P1' THEN 1 ELSE 0 END) AS P1_COUNT,
                    SUM(CASE WHEN PRIORITY = 'P2' THEN 1 ELSE 0 END) AS P2_COUNT
                FROM INCIDENTS
                WHERE CREATED_TIME >= p_start_date AND CREATED_TIME <= p_end_date
            ),
            prior_period AS (
                SELECT 
                    'PRIOR' AS PERIOD_TYPE,
                    COUNT(*) AS VOLUME,
                    ROUND(AVG(RESOLUTION_HOURS), 2) AS MTTR,
                    SUM(IS_SLA_BREACH) AS BREACHES,
                    ROUND((1 - (SUM(IS_SLA_BREACH) / NULLIF(COUNT(*), 0))) * 100, 2) AS SLA_COMPLIANCE,
                    SUM(CASE WHEN PRIORITY = 'P1' THEN 1 ELSE 0 END) AS P1_COUNT,
                    SUM(CASE WHEN PRIORITY = 'P2' THEN 1 ELSE 0 END) AS P2_COUNT
                FROM INCIDENTS
                WHERE CREATED_TIME >= v_prior_start AND CREATED_TIME <= v_prior_end
            )
            SELECT 
                c.VOLUME AS CURRENT_VOLUME,
                p.VOLUME AS PRIOR_VOLUME,
                ROUND((c.VOLUME - p.VOLUME) * 100.0 / NULLIF(p.VOLUME, 0), 1) AS VOLUME_DELTA_PCT,
                c.MTTR AS CURRENT_MTTR,
                p.MTTR AS PRIOR_MTTR,
                ROUND((c.MTTR - p.MTTR) * 100.0 / NULLIF(p.MTTR, 0), 1) AS MTTR_DELTA_PCT,
                c.BREACHES AS CURRENT_BREACHES,
                p.BREACHES AS PRIOR_BREACHES,
                c.SLA_COMPLIANCE AS CURRENT_SLA_PCT,
                p.SLA_COMPLIANCE AS PRIOR_SLA_PCT,
                ROUND(c.SLA_COMPLIANCE - p.SLA_COMPLIANCE, 2) AS SLA_DELTA_PTS,
                c.P1_COUNT AS CURRENT_P1,
                p.P1_COUNT AS PRIOR_P1,
                c.P2_COUNT AS CURRENT_P2,
                p.P2_COUNT AS PRIOR_P2
            FROM current_period c
            CROSS JOIN prior_period p;

        RETURN v_cur;
    END get_kpi_summary;

    -- ------------------------------------------------------------------------
    -- FR-12 & FR-13: create_problem_from_top_recurring
    -- ------------------------------------------------------------------------
    PROCEDURE create_problem_from_top_recurring(
        p_problem_id    OUT VARCHAR2,
        p_linked_count  OUT NUMBER
    ) IS
        v_top_category   VARCHAR2(30);
        v_top_service    VARCHAR2(50);
        v_top_cause      VARCHAR2(200);
        v_prb_id         VARCHAR2(30) := 'PRB-2026-001';
        v_rca            CLOB;
        v_workaround     CLOB;
    BEGIN
        -- Find the #1 recurring issue pattern
        SELECT CATEGORY, SERVICE, ROOT_CAUSE
        INTO v_top_category, v_top_service, v_top_cause
        FROM (
            SELECT CATEGORY, SERVICE, ROOT_CAUSE, COUNT(*) AS CNT
            FROM INCIDENTS
            GROUP BY CATEGORY, SERVICE, ROOT_CAUSE
            ORDER BY CNT DESC
        )
        WHERE ROWNUM = 1;

        -- Document 5 Whys RCA (FR-13)
        v_rca := 
'=== ROOT CAUSE ANALYSIS (5 WHYS METHODOLOGY) ===' || CHR(10) ||
'Why 1: Payment processing API requests intermittently returned HTTP 504 Gateway Timeout during peak traffic.' || CHR(10) ||
'Why 2: Worker threads in the Payment Gateway microservice were stalled waiting for JDBC connections from the pool.' || CHR(10) ||
'Why 3: The maximum HikariCP database connection pool size was statically capped at 20 connections, while concurrent payment requests exceeded 140.' || CHR(10) ||
'Why 4: Legacy merchant webhook notification logic retained database connections across slow synchronous outbound HTTP calls without a timeout guard.' || CHR(10) ||
'Why 5: Lack of automated connection pool saturation alerting and missing architectural standard separating asynchronous webhook dispatches from transactional database sessions.';

        -- Document Workaround (FR-13)
        v_workaround := 
'=== INTERIM SUPPORT WORKAROUND ===' || CHR(10) ||
'1. Rolling Restart: Execute rolling restart of Payment Gateway pods (kubectl rollout restart deployment/payment-gateway-service).' || CHR(10) ||
'2. Dynamic Pool Scaling: Update maximum pool size to 60 via Spring Cloud Config dynamic refresh endpoint.' || CHR(10) ||
'3. Circuit Breaker: Enable fallback queue for asynchronous webhook notifications to release thread holds immediately.';

        -- Upsert Problem Record
        MERGE INTO PROBLEMS p
        USING (SELECT v_prb_id AS PRB_ID FROM DUAL) src
        ON (p.PROBLEM_ID = src.PRB_ID)
        WHEN MATCHED THEN
            UPDATE SET 
                TITLE = 'Recurring Payment Gateway Timeout due to Database Connection Pool Starvation',
                CATEGORY = v_top_category,
                SERVICE = v_top_service,
                ROOT_CAUSE = v_top_cause,
                RCA_5_WHYS = v_rca,
                KNOWN_ERROR_FLAG = 1,
                WORKAROUND = v_workaround,
                STATUS = 'CHANGE_PENDING'
        WHEN NOT MATCHED THEN
            INSERT (
                PROBLEM_ID, TITLE, CATEGORY, SERVICE, ROOT_CAUSE, 
                RCA_5_WHYS, KNOWN_ERROR_FLAG, WORKAROUND, STATUS, CREATED_DATE
            ) VALUES (
                v_prb_id,
                'Recurring Payment Gateway Timeout due to Database Connection Pool Starvation',
                v_top_category,
                v_top_service,
                v_top_cause,
                v_rca,
                1,
                v_workaround,
                'CHANGE_PENDING',
                SYSDATE
            );

        -- Link all matching incident tickets (FR-12)
        INSERT INTO INCIDENT_PROBLEM_LINK (TICKET_ID, PROBLEM_ID)
        SELECT i.TICKET_ID, v_prb_id
        FROM INCIDENTS i
        WHERE i.CATEGORY = v_top_category
          AND i.SERVICE = v_top_service
          AND i.ROOT_CAUSE = v_top_cause
          AND NOT EXISTS (
              SELECT 1 FROM INCIDENT_PROBLEM_LINK l
              WHERE l.TICKET_ID = i.TICKET_ID AND l.PROBLEM_ID = v_prb_id
          );

        SELECT COUNT(*)
        INTO p_linked_count
        FROM INCIDENT_PROBLEM_LINK
        WHERE PROBLEM_ID = v_prb_id;

        p_problem_id := v_prb_id;
        COMMIT;
    END create_problem_from_top_recurring;

    -- ------------------------------------------------------------------------
    -- FR-14: create_change_request
    -- ------------------------------------------------------------------------
    PROCEDURE create_change_request(
        p_problem_id    IN  VARCHAR2,
        p_change_id     OUT VARCHAR2
    ) IS
        v_chg_id VARCHAR2(30) := 'CHG-2026-042';
        v_desc CLOB;
        v_test CLOB;
        v_backout CLOB;
    BEGIN
        v_desc := 
'=== CHANGE DESCRIPTION: PERMANENT FIX FOR PRB-2026-001 ===' || CHR(10) ||
'1. Decouple merchant webhook dispatch into an event-driven Kafka queue, releasing DB connections prior to outbound HTTP calls.' || CHR(10) ||
'2. Reconfigure HikariCP pool size from 20 to 80 with connectionTimeout=3000ms, idleTimeout=60000ms, maxLifetime=1800000ms.' || CHR(10) ||
'3. Implement Prometheus HikariCP metrics and Alertmanager trigger at 80% pool utilization for 2 consecutive minutes.';

        v_test := 
'=== TEST AND VALIDATION PLAN ===' || CHR(10) ||
'1. Pre-Deployment Staging Load Test: Simulate 350 TPS concurrent payment requests for 45 minutes; verify 0 connection timeouts.' || CHR(10) ||
'2. Fault Injection Test: Introduce 10-second latency on external webhook endpoint; verify DB connections release immediately.' || CHR(10) ||
'3. Canary Verification: Deploy to Canary pod (10% traffic) for 2 hours monitoring HTTP error rates and DB active connections.';

        v_backout := 
'=== BACK-OUT AND ROLLBACK PLAN ===' || CHR(10) ||
'1. Rollback Trigger Criteria: Error rate > 0.5% or P99 response time > 800ms sustained over 3 minutes.' || CHR(10) ||
'2. Rollback Execution: Revert Helm deployment release to image v2.4.1 (helm rollback payment-gateway-svc <prior-revision>).' || CHR(10) ||
'3. Rollback Timeframe: Automated rollback executes in < 4 minutes with 0 scheduled downtime.';

        MERGE INTO CHANGES c
        USING (SELECT v_chg_id AS CHG_ID FROM DUAL) src
        ON (c.CHANGE_ID = src.CHG_ID)
        WHEN MATCHED THEN
            UPDATE SET 
                TITLE = 'Payment Gateway Asynchronous Connection & Pool Hardening',
                DESCRIPTION = v_desc,
                RISK_LEVEL = 'MEDIUM',
                IMPACT_LEVEL = 'HIGH',
                TEST_PLAN = v_test,
                BACKOUT_PLAN = v_backout,
                APPROVAL_STATUS = 'APPROVED',
                APPROVED_BY = 'CAB Chair (Elena Rostova)',
                APPROVAL_DATE = SYSDATE - 14,
                IMPLEMENTATION_STATUS = 'SUCCESSFUL'
        WHEN NOT MATCHED THEN
            INSERT (
                CHANGE_ID, PROBLEM_ID, CHANGE_TYPE, TITLE, DESCRIPTION,
                RISK_LEVEL, IMPACT_LEVEL, TEST_PLAN, BACKOUT_PLAN,
                APPROVAL_STATUS, APPROVED_BY, APPROVAL_DATE, IMPLEMENTATION_STATUS
            ) VALUES (
                v_chg_id, p_problem_id, 'NORMAL',
                'Payment Gateway Asynchronous Connection & Pool Hardening',
                v_desc, 'MEDIUM', 'HIGH', v_test, v_backout,
                'APPROVED', 'CAB Chair (Elena Rostova)', SYSDATE - 14, 'SUCCESSFUL'
            );

        p_change_id := v_chg_id;
        COMMIT;
    END create_change_request;

    -- ------------------------------------------------------------------------
    -- FR-15: get_pir_metrics
    -- ------------------------------------------------------------------------
    FUNCTION get_pir_metrics(
        p_problem_id    IN VARCHAR2
    ) RETURN SYS_REFCURSOR IS
        v_cur SYS_REFCURSOR;
        v_category VARCHAR2(30);
        v_service  VARCHAR2(50);
        v_cause    VARCHAR2(200);
    BEGIN
        SELECT CATEGORY, SERVICE, ROOT_CAUSE
        INTO v_category, v_service, v_cause
        FROM PROBLEMS
        WHERE PROBLEM_ID = p_problem_id;

        OPEN v_cur FOR
            WITH baseline AS (
                SELECT 
                    'BEFORE_FIX (90 Days Prior)' AS WINDOW_NAME,
                    COUNT(*) AS INCIDENT_COUNT,
                    ROUND(AVG(RESOLUTION_HOURS), 2) AS AVG_MTTR_HOURS,
                    SUM(IS_SLA_BREACH) AS TOTAL_BREACHES,
                    ROUND(SUM(IS_SLA_BREACH) * 100.0 / NULLIF(COUNT(*), 0), 1) AS BREACH_PCT
                FROM INCIDENTS
                WHERE CATEGORY = v_category
                  AND SERVICE = v_service
                  AND ROOT_CAUSE = v_cause
                  AND CREATED_TIME < SYSDATE - 14
            ),
            post_fix AS (
                SELECT 
                    'AFTER_FIX (Post Implementation)' AS WINDOW_NAME,
                    COUNT(*) AS INCIDENT_COUNT,
                    NVL(ROUND(AVG(RESOLUTION_HOURS), 2), 0.00) AS AVG_MTTR_HOURS,
                    NVL(SUM(IS_SLA_BREACH), 0) AS TOTAL_BREACHES,
                    NVL(ROUND(SUM(IS_SLA_BREACH) * 100.0 / NULLIF(COUNT(*), 0), 1), 0.0) AS BREACH_PCT
                FROM INCIDENTS
                WHERE CATEGORY = v_category
                  AND SERVICE = v_service
                  AND ROOT_CAUSE = v_cause
                  AND CREATED_TIME >= SYSDATE - 14
            )
            SELECT * FROM baseline
            UNION ALL
            SELECT * FROM post_fix;

        RETURN v_cur;
    END get_pir_metrics;

END PKG_INCIDENT_ANALYTICS;
/
