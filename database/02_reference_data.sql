-- ============================================================================
-- Project: Incident, Problem & Recurring-Issue Analytics (SRS 2)
-- File: database/02_reference_data.sql
-- Description: Seed reference data for SLA Matrix, Categories, Services, Groups
-- Author: Mahi Zaman
-- ============================================================================

-- 1. SLA Matrix (FR-03, Section 5)
INSERT INTO SLA_MATRIX (PRIORITY, PRIORITY_NAME, RESPONSE_TARGET_HOURS, RESOLUTION_TARGET_HOURS, DESCRIPTION)
VALUES ('P1', 'Critical / Blocker', 0.25, 4.00, 'Complete service outage or severe critical impact to revenue/operations');

INSERT INTO SLA_MATRIX (PRIORITY, PRIORITY_NAME, RESPONSE_TARGET_HOURS, RESOLUTION_TARGET_HOURS, DESCRIPTION)
VALUES ('P2', 'High / Major', 0.50, 8.00, 'Significant business degradation with no immediate workaround');

INSERT INTO SLA_MATRIX (PRIORITY, PRIORITY_NAME, RESPONSE_TARGET_HOURS, RESOLUTION_TARGET_HOURS, DESCRIPTION)
VALUES ('P3', 'Medium / Moderate', 2.00, 24.00, 'Non-critical function impaired or workaround in place');

INSERT INTO SLA_MATRIX (PRIORITY, PRIORITY_NAME, RESPONSE_TARGET_HOURS, RESOLUTION_TARGET_HOURS, DESCRIPTION)
VALUES ('P4', 'Low / Minor', 4.00, 72.00, 'Minor inquiry, cosmetic issue or informational request');

-- 2. Categories (FR-03)
INSERT INTO REF_CATEGORIES (CATEGORY_CODE, CATEGORY_NAME, DESCRIPTION)
VALUES ('SOFTWARE', 'Software & Application Integrations', 'Core application logic, microservices, APIs, and enterprise integrations');

INSERT INTO REF_CATEGORIES (CATEGORY_CODE, CATEGORY_NAME, DESCRIPTION)
VALUES ('DATABASE', 'Database & Storage Services', 'Relational databases, transaction logs, locking, schemas, and persistence');

INSERT INTO REF_CATEGORIES (CATEGORY_CODE, CATEGORY_NAME, DESCRIPTION)
VALUES ('INFRASTRUCTURE', 'Cloud, Network & Compute', 'Virtual machines, containers, edge proxies, DNS, routing, and physical hosts');

INSERT INTO REF_CATEGORIES (CATEGORY_CODE, CATEGORY_NAME, DESCRIPTION)
VALUES ('SECURITY', 'Identity, Security & Access', 'Authentication tokens, SSL certificates, firewall rules, and IAM policies');

INSERT INTO REF_CATEGORIES (CATEGORY_CODE, CATEGORY_NAME, DESCRIPTION)
VALUES ('HARDWARE', 'Physical & Edge Systems', 'Server chassis, storage arrays, network switches, and hardware interfaces');

-- 3. Services (FR-03)
INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('PAYMENT_GATEWAY', 'Payment Processing Gateway', 'Tier-1', 'Real-time card, ACH and instant transaction processing');

INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('BILLING_ENGINE', 'Billing & Invoicing Service', 'Tier-1', 'Automated subscription, ledgering, tax and invoice calculation');

INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('USER_PORTAL', 'Customer Self-Service Portal', 'Tier-2', 'Customer web application and mobile dashboard interfaces');

INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('CORE_BANKING_API', 'Core Banking API Service', 'Tier-1', 'Inter-bank settlement, balances, and account ledger APIs');

INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('REPORTING_SERVICE', 'BI & Financial Reporting', 'Tier-3', 'Regulatory reports, data warehouse sync, and dashboard extracts');

INSERT INTO REF_SERVICES (SERVICE_CODE, SERVICE_NAME, CRITICAL_TIER, DESCRIPTION)
VALUES ('IDENTITY_AUTH', 'IAM & Single Sign-On', 'Tier-1', 'Enterprise identity provider, OAuth2, and multi-factor authentication');

-- 4. Assignment Groups (FR-03)
INSERT INTO REF_ASSIGNMENT_GROUPS (GROUP_CODE, GROUP_NAME, LEAD_NAME, ESCALATION_EMAIL)
VALUES ('GRP_APP_DEV', 'Application Engineering Group', 'David Chen', 'app-dev-lead@corp.local');

INSERT INTO REF_ASSIGNMENT_GROUPS (GROUP_CODE, GROUP_NAME, LEAD_NAME, ESCALATION_EMAIL)
VALUES ('GRP_DBA_TEAM', 'Database Operations Team', 'Elena Rostova', 'dba-lead@corp.local');

INSERT INTO REF_ASSIGNMENT_GROUPS (GROUP_CODE, GROUP_NAME, LEAD_NAME, ESCALATION_EMAIL)
VALUES ('GRP_INFRA_OPS', 'Cloud & Infrastructure Operations', 'Marcus Vance', 'infra-lead@corp.local');

INSERT INTO REF_ASSIGNMENT_GROUPS (GROUP_CODE, GROUP_NAME, LEAD_NAME, ESCALATION_EMAIL)
VALUES ('GRP_NET_SEC', 'Network & Cyber Security Team', 'Sarah Jenkins', 'security-lead@corp.local');

INSERT INTO REF_ASSIGNMENT_GROUPS (GROUP_CODE, GROUP_NAME, LEAD_NAME, ESCALATION_EMAIL)
VALUES ('GRP_SERVICE_DESK', 'Tier-1 Incident Command & Support', 'Priya Patel', 'servicedesk-lead@corp.local');

COMMIT;
