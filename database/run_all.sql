-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/run_all.sql
-- Description: Master Execution Script for Oracle Database XE 21c
-- Usage: sqlplus username/password@//localhost:1521/XEPDB1 @run_all.sql
-- Author: Mahi Zaman
-- ============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT =======================================================================
PROMPT Phase 1: Deploying DDL Schema Tables and Constraints...
PROMPT =======================================================================
@database/01_schema_ddl.sql

PROMPT =======================================================================
PROMPT Phase 2: Loading Reference Data (SLA Matrix, Services, Categories)...
PROMPT =======================================================================
@database/02_reference_data.sql

PROMPT =======================================================================
PROMPT Phase 3: Creating Analytics Views...
PROMPT =======================================================================
@database/03_analytics_views.sql

PROMPT =======================================================================
PROMPT Phase 4: Compiling Package Specification PKG_INCIDENT_ANALYTICS...
PROMPT =======================================================================
@database/04_pkg_incident_analytics_spec.sql

PROMPT =======================================================================
PROMPT Phase 5: Compiling Package Body PKG_INCIDENT_ANALYTICS...
PROMPT =======================================================================
@database/05_pkg_incident_analytics_body.sql

PROMPT =======================================================================
PROMPT Phase 6: Seeding Problem and Change Records...
PROMPT =======================================================================
@database/06_seed_problem_and_change.sql

PROMPT =======================================================================
PROMPT Oracle Database XE 21c Schema & Package Deployment Complete!
PROMPT =======================================================================
