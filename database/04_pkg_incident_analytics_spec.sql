-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/04_pkg_incident_analytics_spec.sql
-- Description: PL/SQL Package Specification: PKG_INCIDENT_ANALYTICS
-- Author: Mahi Zaman
-- ============================================================================

CREATE OR REPLACE PACKAGE PKG_INCIDENT_ANALYTICS AUTHID DEFINER AS
    /**
     * PKG_INCIDENT_ANALYTICS
     * Core PL/SQL package providing ITIL Incident, Problem and SLA analytics,
     * Repeat-Offender detection, MTTR window functions, and Pareto reporting.
     */

    -- FR-06: Report repeat offenders (category, service, root cause >= min_count in window)
    FUNCTION get_repeat_offenders(
        p_days_window   IN NUMBER DEFAULT 30,
        p_min_count     IN NUMBER DEFAULT 3
    ) RETURN SYS_REFCURSOR;

    -- FR-07: Compute MTTR by category, priority and month using analytic functions
    FUNCTION get_mttr_analytics(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- FR-08: Report SLA breaches and breach percentage by priority
    FUNCTION get_sla_breach_summary(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- FR-09: Produce a Pareto distribution of root causes
    FUNCTION get_root_cause_pareto(
        p_start_date    IN DATE DEFAULT NULL,
        p_end_date      IN DATE DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- FR-09: Monthly volume, SLA breaches, and month-end backlog/spike trends
    FUNCTION get_monthly_volume_trend(
        p_months_back   IN NUMBER DEFAULT 6
    ) RETURN SYS_REFCURSOR;

    -- FR-10 & FR-11: Period KPI summary comparing current window vs prior window
    FUNCTION get_kpi_summary(
        p_start_date    IN DATE,
        p_end_date      IN DATE
    ) RETURN SYS_REFCURSOR;

    -- FR-12 & FR-13: Auto-create Problem record from top recurring issue and link incidents
    PROCEDURE create_problem_from_top_recurring(
        p_problem_id    OUT VARCHAR2,
        p_linked_count  OUT NUMBER
    );

    -- FR-14: Create Change Request record for documented fix, risk, rollback and approval
    PROCEDURE create_change_request(
        p_problem_id    IN  VARCHAR2,
        p_change_id     OUT VARCHAR2
    );

    -- FR-15: Post-Implementation Review (PIR) comparison before vs after fix
    FUNCTION get_pir_metrics(
        p_problem_id    IN VARCHAR2
    ) RETURN SYS_REFCURSOR;

END PKG_INCIDENT_ANALYTICS;
/
